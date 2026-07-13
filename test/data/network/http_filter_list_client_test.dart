/// -_-

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

void main() {
  group('HttpFilterListClient', () {
    late HttpServer server;
    late String serverUrl;
    late HttpFilterListClient client;
    String? expectedResponseEtag;
    String? expectedResponseBody;
    late int expectedResponseStatusCode;
    final requestHeaders = <String, String>{};

    setUp(() async {
      expectedResponseBody = 'test data';
      expectedResponseEtag = '12345';
      expectedResponseStatusCode = HttpStatus.ok;
      requestHeaders.clear();

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUrl = 'http://${server.address.address}:${server.port}';

      server.listen((request) async {
        request.headers.forEach((name, values) {
          requestHeaders[name] = values.join(', ');
        });
        request.response.statusCode = expectedResponseStatusCode;

        if (expectedResponseEtag != null) {
          request.response.headers.set('etag', expectedResponseEtag!);
        }

        if (request.method == 'HEAD') {
          await request.response.close();
        } else {
          if (expectedResponseBody != null) {
            request.response.write(expectedResponseBody);
          }
          await request.response.close();
        }
      });

      client = HttpFilterListClient(
        const FilterHttpOptions(
          headers: {'X-Custom-Header': 'CustomValue'},
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
        ),
      );
    });

    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });

    test('fetch should return bytes and etag', () async {
      final result = await client.fetch(FilterSubscription(url: serverUrl));

      expect(utf8.decode(result.bytes), 'test data');
      expect(result.etag, '12345');
    });

    test('rejects a declared oversized response before reading its body', () async {
      final rawServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final releaseBody = Completer<void>();
      var bodyStarted = false;
      rawServer.listen((socket) async {
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 9\r\nConnection: close\r\n\r\n');
        await socket.flush();
        await releaseBody.future;
        bodyStarted = true;
        socket.destroy();
      });
      await client.dispose();
      client = HttpFilterListClient(
        const FilterHttpOptions(
          maxFilterListBytes: 8,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
        ),
      );
      final rawServerUrl = 'http://${rawServer.address.address}:${rawServer.port}';

      try {
        await expectLater(
          client.fetch(FilterSubscription(url: rawServerUrl)),
          throwsA(
            isA<HttpException>().having((error) => error.message, 'message', contains('8')),
          ),
        );

        expect(bodyStarted, isFalse);
      } finally {
        releaseBody.complete();
        await rawServer.close();
      }
    });

    test('rejects an oversized chunked response at the configured byte limit', () async {
      await client.dispose();
      client = HttpFilterListClient(
        const FilterHttpOptions(
          maxFilterListBytes: 8,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
        ),
      );
      expectedResponseBody = '123456789';

      await expectLater(
        client.fetch(FilterSubscription(url: serverUrl)),
        throwsA(
          isA<HttpException>().having((error) => error.message, 'message', contains('8')),
        ),
      );
    });

    test('accepts a response at the configured byte limit', () async {
      await client.dispose();
      client = HttpFilterListClient(
        const FilterHttpOptions(
          maxFilterListBytes: 8,
          connectTimeout: Duration(seconds: 1),
          receiveTimeout: Duration(seconds: 1),
        ),
      );
      expectedResponseBody = '12345678';

      final result = await client.fetch(FilterSubscription(url: serverUrl));

      expect(utf8.decode(result.bytes), '12345678');
    });

    test('fetch should apply default User-Agent and custom headers', () async {
      await client.fetch(FilterSubscription(url: serverUrl));

      expect(requestHeaders['user-agent'], isNotNull);
      expect(requestHeaders['user-agent'], contains('Mozilla'));
      expect(requestHeaders['x-custom-header'], 'CustomValue');
    });

    test('fetch should throw HttpException for unsuccessful status code', () async {
      expectedResponseStatusCode = HttpStatus.notFound;
      expectedResponseBody = 'not a filter list';

      await expectLater(
        client.fetch(FilterSubscription(url: serverUrl)),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('head should return etag without downloading body', () async {
      final result = await client.head(FilterSubscription(url: serverUrl));

      expect(result.etag, '12345');
    });

    test('head should throw HttpException for unsuccessful status code', () async {
      expectedResponseStatusCode = HttpStatus.internalServerError;
      expectedResponseEtag = 'error-etag';

      await expectLater(
        client.head(FilterSubscription(url: serverUrl)),
        throwsA(
          isA<HttpException>().having(
            (error) => error.message,
            'message',
            contains('500'),
          ),
        ),
      );
    });

    test('fetch should throw exception on invalid URL', () async {
      await expectLater(
        client.fetch(const FilterSubscription(url: 'http://127.0.0.1:invalid')),
        throwsA(isA<FormatException>()),
      );
    });

    test('close should release the owned HTTP client', () async {
      await client.dispose();

      await expectLater(
        client.fetch(FilterSubscription(url: serverUrl)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('FilterHttpOptions', () {
    test('uses bounded defaults', () {
      const options = FilterHttpOptions();

      expect(options.maxFilterListBytes, 32 * 1024 * 1024);
      expect(options.maxConcurrentDownloads, 4);
    });

    test('requires positive download limits', () {
      expect(() => FilterHttpOptions(maxFilterListBytes: 0), throwsA(isA<AssertionError>()));
      expect(() => FilterHttpOptions(maxConcurrentDownloads: 0), throwsA(isA<AssertionError>()));
    });
  });
}
