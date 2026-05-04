import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

void main() {
  group('TestFilterListClient', () {
    late Directory tempDir;
    late TestFilterListClient client;
    late FilterSubscription subscription;
    late File testFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('test_filter_list_client_');
      client = TestFilterListClient();
      testFile = File('${tempDir.path}/test_list.txt');
      subscription = FilterSubscription(url: testFile.path);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fetch should read file and return bytes with etag', () async {
      testFile.writeAsStringSync('test data');
      final result = await client.fetch(subscription);

      expect(String.fromCharCodes(result.bytes), 'test data');
      expect(result.etag, startsWith('test_etag_'));
    });

    test('fetch should throw exception when file not found', () async {
      expect(
        () => client.fetch(subscription),
        throwsA(
          isA<Exception>().having((e) => e.toString(), 'message', contains('Test file not found')),
        ),
      );
    });

    test('head should return etag when file exists', () async {
      testFile.writeAsStringSync('test data');
      final result = await client.head(subscription);

      expect(result.etag, startsWith('test_etag_'));
    });

    test('head should return null etag when file not found', () async {
      final result = await client.head(subscription);

      expect(result.etag, isNull);
    });
  });
}
