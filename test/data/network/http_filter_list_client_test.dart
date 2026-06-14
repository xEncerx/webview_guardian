/// -_-
// ignore_for_file: discarded_futures

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
    final requestHeaders = <String, String>{};

    setUp(() async {
      expectedResponseBody = 'test data';
      expectedResponseEtag = '12345';
      requestHeaders.clear();

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverUrl = 'http://${server.address.address}:${server.port}';

      server.listen((request) {
        request.headers.forEach((name, values) {
          requestHeaders[name] = values.join(', ');
        });

        if (expectedResponseEtag != null) {
          request.response.headers.set('etag', expectedResponseEtag!);
        }

        if (request.method == 'HEAD') {
          request.response.close();
        } else {
          if (expectedResponseBody != null) {
            request.response.write(expectedResponseBody);
          }
          request.response.close();
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

    test('head should return etag without downloading body', () async {
      final result = await client.head(FilterSubscription(url: serverUrl));

      expect(result.etag, '12345');
    });

    test('fetch should throw exception on invalid URL', () async {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final unusedPort = socket.port;
      await socket.close();

      await expectLater(
        client.fetch(FilterSubscription(url: 'http://127.0.0.1:$unusedPort')),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
