import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_guardian/src/domain/domain.dart';

final String _sep = Platform.pathSeparator;

/// Metadata extracted from a cached filter list file.
typedef CachedFilterMetadata = ({String etag, int timestamp, Uint8List data});

/// Metadata for a cached filter list.
typedef CachedFilterListMetadata = ({
  String etag,
  int timestamp,
  String payloadSha256,
  int payloadLength,
});

typedef _FilterListHeader = ({String etag, int timestamp, int payloadOffset, int payloadLength});

/// A local storage implementation for persisting binary data.
class FilterStorage {
  /// Creates a [FilterStorage] instance.
  const FilterStorage({this.overridePath});

  /// Optional override path for the storage directory, used for testing.
  final String? overridePath;

  static const String _engineFileName = 'compiled_filter_engine.bin';
  static const String _engineMetadataFileName = 'compiled_filter_engine.json';
  static const String _filterListsDir = 'filter_lists';
  static const List<int> _magicHeader = [0x46, 0x4C, 0x54, 0x52]; // "FLTR"

  /// Saves the compiled engine bytes to the local file system.
  Future<void> saveEngineBytes(Uint8List bytes, {required String cacheIdentity}) async {
    final file = await _getEngineFile();
    final metadataFile = await _getEngineMetadataFile();
    final engineSha256 = sha256.convert(bytes).toString();

    await file.writeAsBytes(bytes, flush: true);
    await metadataFile.writeAsString(
      jsonEncode({
        'cacheIdentity': cacheIdentity,
        'engineSha256': engineSha256,
      }),
      flush: true,
    );
  }

  /// Loads the compiled engine bytes from the local file system.
  Future<Uint8List?> loadEngineBytes({required String cacheIdentity}) async {
    final file = await _getEngineFile();
    final metadataFile = await _getEngineMetadataFile();
    if (!file.existsSync()) return null;
    if (!metadataFile.existsSync()) return null;

    final metadata = jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
    if (metadata['cacheIdentity'] != cacheIdentity) return null;

    final bytes = await file.readAsBytes();
    if (metadata['engineSha256'] != sha256.convert(bytes).toString()) {
      return null;
    }

    return bytes;
  }

  /// Saves a filter list with its ETag metadata to the local file system.
  Future<void> saveFilterList({
    required String url,
    required String etag,
    required Uint8List bytes,
  }) async {
    final fileName = _hashUrl(url);
    final file = await _getFilterListFile(fileName);
    final metadataFile = _getFilterListMetadataFile(file);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final payloadSha256 = sha256.convert(bytes).toString();

    final writer = BinaryWriter();
    _magicHeader.forEach(writer.writeUint8);
    writer
      ..writeString(etag)
      ..writeInt64(timestamp);

    await (file.openWrite()
          ..add(writer.toBytes())
          ..add(bytes))
        .close();

    await metadataFile.writeAsString(
      jsonEncode({
        'etag': etag,
        'timestamp': timestamp,
        'payloadSha256': payloadSha256,
        'payloadLength': bytes.length,
      }),
      flush: true,
    );
  }

  /// Returns whether a valid filter list cache entry exists for [url].
  Future<bool> hasFilterList(String url) => validateFilterListHeader(url);

  /// Validates the cached filter list header without loading payload bytes.
  Future<bool> validateFilterListHeader(String url) async {
    final fileName = _hashUrl(url);
    final file = await _getFilterListFile(fileName);

    if (!file.existsSync()) return false;

    try {
      await _readFilterListHeader(file);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Loads cached filter list metadata without loading its payload bytes.
  Future<CachedFilterListMetadata?> loadFilterListMetadata(String url) async {
    final fileName = _hashUrl(url);
    final file = await _getFilterListFile(fileName);

    if (!file.existsSync()) return null;

    final header = await _readFilterListHeader(file);
    final metadataFile = _getFilterListMetadataFile(file);
    final cachedMetadata = await _loadFilterListMetadataSidecar(metadataFile);
    if (cachedMetadata != null &&
        cachedMetadata.etag == header.etag &&
        cachedMetadata.timestamp == header.timestamp &&
        cachedMetadata.payloadLength == header.payloadLength) {
      return cachedMetadata;
    }

    final payloadSha256 = await _computePayloadSha256(file, header.payloadOffset);
    final metadata = (
      etag: header.etag,
      timestamp: header.timestamp,
      payloadSha256: payloadSha256,
      payloadLength: header.payloadLength,
    );
    await _saveFilterListMetadataSidecar(metadataFile, metadata);
    return metadata;
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
    final engineMetadataFile = await _getEngineMetadataFile();
    if (engineMetadataFile.existsSync()) await engineMetadataFile.delete();
  }

  /// Deletes filter lists that are not present in the provided list of valid URLs.
  ///
  /// Returns `true` if any orphaned files were deleted, `false` otherwise.
  Future<bool> cleanupOrphanedFilterLists(List<String> validUrls) async {
    var hasDeletions = false;
    final directory = await _getFilterListsDirectory();

    if (!directory.existsSync()) return false;

    final validFileNames = validUrls.expand((url) {
      final fileName = '${_hashUrl(url)}.bin';
      return [fileName, '$fileName.json'];
    }).toSet();

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
    final adblockerDir = Directory('${dir.path}${_sep}adblocker');
    if (!adblockerDir.existsSync()) {
      adblockerDir.createSync(recursive: true);
    }
    return adblockerDir;
  }

  Future<File> _getEngineFile() async {
    final directory = await _getBaseDirectory();
    return File('${directory.path}$_sep$_engineFileName');
  }

  Future<File> _getEngineMetadataFile() async {
    final directory = await _getBaseDirectory();
    return File('${directory.path}$_sep$_engineMetadataFileName');
  }

  Future<Directory> _getFilterListsDirectory() async {
    final directory = await _getBaseDirectory();
    return Directory('${directory.path}$_sep$_filterListsDir');
  }

  Future<File> _getFilterListFile(String fileName) async {
    final directory = await _getFilterListsDirectory();
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}$_sep$fileName.bin');
  }

  File _getFilterListMetadataFile(File filterListFile) => File('${filterListFile.path}.json');

  Future<CachedFilterListMetadata?> _loadFilterListMetadataSidecar(File file) async {
    if (!file.existsSync()) return null;

    try {
      final metadata = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return (
        etag: metadata['etag']! as String,
        timestamp: metadata['timestamp']! as int,
        payloadSha256: metadata['payloadSha256']! as String,
        payloadLength: metadata['payloadLength']! as int,
      );
    } on Object {
      return null;
    }
  }

  Future<void> _saveFilterListMetadataSidecar(
    File file,
    CachedFilterListMetadata metadata,
  ) async {
    await file.writeAsString(
      jsonEncode({
        'etag': metadata.etag,
        'timestamp': metadata.timestamp,
        'payloadSha256': metadata.payloadSha256,
        'payloadLength': metadata.payloadLength,
      }),
      flush: true,
    );
  }

  Future<_FilterListHeader> _readFilterListHeader(File file) async {
    final raf = await file.open();
    try {
      final magicAndLength = await _readExact(raf, _magicHeader.length + 4);
      for (var i = 0; i < _magicHeader.length; i++) {
        if (magicAndLength[i] != _magicHeader[i]) {
          throw const FormatException('Invalid magic header');
        }
      }

      final etagLength = ByteData.sublistView(
        magicAndLength,
        _magicHeader.length,
        _magicHeader.length + 4,
      ).getInt32(0, Endian.little);
      if (etagLength < 0) {
        throw const FormatException('Invalid ETag length');
      }

      final etagBytes = await _readExact(raf, etagLength);
      final timestampBytes = await _readExact(raf, 8);
      final timestamp = ByteData.sublistView(timestampBytes).getInt64(0, Endian.little);
      final payloadOffset = _magicHeader.length + 4 + etagLength + 8;
      final payloadLength = await file.length() - payloadOffset;
      if (payloadLength < 0) {
        throw const FormatException('Invalid payload length');
      }

      return (
        etag: utf8.decode(etagBytes),
        timestamp: timestamp,
        payloadOffset: payloadOffset,
        payloadLength: payloadLength,
      );
    } finally {
      await raf.close();
    }
  }

  Future<Uint8List> _readExact(RandomAccessFile file, int length) async {
    final bytes = await file.read(length);
    if (bytes.length != length) {
      throw const FormatException('Unexpected end of filter list file');
    }
    return bytes;
  }

  Future<String> _computePayloadSha256(File file, int payloadOffset) async {
    final digest = await sha256.bind(file.openRead(payloadOffset)).first;
    return digest.toString();
  }
}
