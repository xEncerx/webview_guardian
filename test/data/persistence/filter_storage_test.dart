import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:webview_guardian/src/data/data.dart';

void main() {
  group('FilterStorage', () {
    late Directory tempDir;
    late FilterStorage storage;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('filter_storage_test_');
      storage = FilterStorage(overridePath: tempDir.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('does not load engine bytes when metadata belongs to different bytes', () async {
      await storage.saveEngineBytes(Uint8List.fromList([1, 2, 3]), cacheIdentity: 'identity-a');

      final engineFile = File('${tempDir.path}/adblocker/compiled_filter_engine.bin');
      await engineFile.writeAsBytes(Uint8List.fromList([4, 5, 6]), flush: true);

      final loaded = await storage.loadEngineBytes(cacheIdentity: 'identity-a');

      expect(loaded, isNull);
    });

    test('loads filter list metadata without payload bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await storage.saveFilterList(
        url: 'https://filters.test/list.txt',
        etag: 'etag-1',
        bytes: bytes,
      );

      final metadata = await storage.loadFilterListMetadata('https://filters.test/list.txt');

      expect(metadata, isNotNull);
      expect(metadata!.etag, 'etag-1');
      expect(metadata.payloadSha256, sha256.convert(bytes).toString());
      expect(metadata.payloadLength, bytes.length);
    });

    test('validates filter list header without reading payload bytes', () async {
      await storage.saveFilterList(
        url: 'https://filters.test/list.txt',
        etag: 'etag-1',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      expect(await storage.hasFilterList('https://filters.test/list.txt'), isTrue);
      expect(await storage.hasFilterList('https://filters.test/missing.txt'), isFalse);
    });

    test('loads legacy filter metadata and backfills payload hash sidecar', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await storage.saveFilterList(
        url: 'https://filters.test/list.txt',
        etag: 'etag-1',
        bytes: bytes,
      );

      final filterFile = Directory(
        '${tempDir.path}/adblocker/filter_lists',
      ).listSync().whereType<File>().singleWhere((file) => file.path.endsWith('.bin'));
      final metadataFile = File('${filterFile.path}.json');
      await metadataFile.delete();

      final metadata = await storage.loadFilterListMetadata('https://filters.test/list.txt');

      expect(metadata, isNotNull);
      expect(metadata!.payloadSha256, sha256.convert(bytes).toString());
      expect(metadataFile.existsSync(), isTrue);
    });

    test('cleanup preserves metadata sidecar for valid filter list', () async {
      await storage.saveFilterList(
        url: 'https://filters.test/list.txt',
        etag: 'etag-1',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );
      final filterFile = Directory(
        '${tempDir.path}/adblocker/filter_lists',
      ).listSync().whereType<File>().singleWhere((file) => file.path.endsWith('.bin'));
      final metadataFile = File('${filterFile.path}.json');

      await storage.cleanupOrphanedFilterLists(['https://filters.test/list.txt']);

      expect(filterFile.existsSync(), isTrue);
      expect(metadataFile.existsSync(), isTrue);
    });
  });
}
