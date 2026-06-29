/// -_-

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
      client.close(force: true);
      await server.close(force: true);
    });

    test('fetch should return bytes and etag', () async {
      final result = await client.fetch(FilterSubscription(url: serverUrl));

      expect(utf8.decode(result.bytes), 'test data');
      expect(result.etag, '12345');
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
      client.close(force: true);

      await expectLater(
        client.fetch(FilterSubscription(url: serverUrl)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
