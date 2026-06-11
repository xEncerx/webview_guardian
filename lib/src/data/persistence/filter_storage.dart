import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Metadata extracted from a cached filter list file.
typedef CachedFilterMetadata = ({String etag, int timestamp, Uint8List data});

/// A local storage implementation for persisting binary data.
class FilterStorage {
  /// Creates a [FilterStorage] instance.
  const FilterStorage({this.overridePath});

  /// Optional override path for the storage directory, used for testing.
  final String? overridePath;

  static const String _engineFileName = 'compiled_filter_engine.bin';
  static const String _filterListsDir = 'filter_lists';
  static const List<int> _magicHeader = [0x46, 0x4C, 0x54, 0x52]; // "FLTR"

  /// Saves the compiled engine bytes to the local file system.
  Future<void> saveEngineBytes(Uint8List bytes) async {
    final file = await _getEngineFile();

    await file.writeAsBytes(bytes, flush: true);
  }

  /// Loads the compiled engine bytes from the local file system.
  Future<Uint8List?> loadEngineBytes() async {
    final file = await _getEngineFile();
    if (!file.existsSync()) {
      return null;
    }

    return file.readAsBytes();
  }

  /// Saves a filter list with its ETag metadata to the local file system.
  Future<void> saveFilterList({
    required String url,
    required String etag,
    required Uint8List bytes,
  }) async {
    final fileName = _hashUrl(url);
    final file = await _getFilterListFile(fileName);

    final writer = BinaryWriter();
    _magicHeader.forEach(writer.writeUint8);
    writer
      ..writeString(etag)
      ..writeInt64(DateTime.now().millisecondsSinceEpoch)
      ..writeBytes(bytes);

    await file.writeAsBytes(writer.toBytes(), flush: true);
  }

  /// Loads a filter list with its metadata from the local file system.
  Future<CachedFilterMetadata?> loadFilterList(String url) async {
    final fileName = _hashUrl(url);
    final file = await _getFilterListFile(fileName);

    if (!file.existsSync()) {
      return null;
    }

    final bytes = await file.readAsBytes();
    final reader = BinaryReader(bytes);

    for (final expectedByte in _magicHeader) {
      if (reader.readUint8() != expectedByte) {
        throw const FormatException('Invalid magic header');
      }
    }

    final etag = reader.readString();
    final timestamp = reader.readInt64();
    final data = reader.readRemainingBytes();

    return (
      etag: etag,
      timestamp: timestamp,
      data: data,
    );
  }

  /// Deletes a specific filter list from the local file system.
  Future<void> deleteFilterList(String url) async {
    final fileName = _hashUrl(url);
    final file = await _getFilterListFile(fileName);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Clears all cached filter lists from the local file system.
  Future<void> clearFilterListsCache() async {
    // 1. Delete all filter list files
    final directory = await _getFilterListsDirectory();
    if (directory.existsSync()) await directory.delete(recursive: true);

    // 2. Delete compiled engine file
    final engineFile = await _getEngineFile();
    if (engineFile.existsSync()) await engineFile.delete();
  }

  /// Deletes filter lists that are not present in the provided list of valid URLs.
  ///
  /// Returns `true` if any orphaned files were deleted, `false` otherwise.
  Future<bool> cleanupOrphanedFilterLists(List<String> validUrls) async {
    var hasDeletions = false;
    final directory = await _getFilterListsDirectory();

    if (!directory.existsSync()) return false;

    final validFileNames = validUrls.map((url) => '${_hashUrl(url)}.bin').toSet();

    final files = directory.listSync();
    for (final entity in files) {
      if (entity is File) {
        final fileName = entity.uri.pathSegments.last;
        if (!validFileNames.contains(fileName)) {
          await entity.delete();
          hasDeletions = true;
        }
      }
    }

    return hasDeletions;
  }

  String _hashUrl(String url) {
    final bytes = utf8.encode(url);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<Directory> _getBaseDirectory() async {
    final dir = overridePath != null
        ? Directory(overridePath!)
        : await getApplicationSupportDirectory();

    // Create subdirectory for adblocker data
    final adblockerDir = Directory('${dir.path}/adblocker');
    if (!adblockerDir.existsSync()) {
      adblockerDir.createSync(recursive: true);
    }
    return adblockerDir;
  }

  Future<File> _getEngineFile() async {
    final directory = await _getBaseDirectory();
    return File('${directory.path}/$_engineFileName');
  }

  Future<Directory> _getFilterListsDirectory() async {
    final directory = await _getBaseDirectory();
    return Directory('${directory.path}/$_filterListsDir');
  }

  Future<File> _getFilterListFile(String fileName) async {
    final directory = await _getFilterListsDirectory();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$fileName.bin');
  }
}
