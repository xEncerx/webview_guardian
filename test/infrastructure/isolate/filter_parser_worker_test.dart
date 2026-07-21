import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';
import 'package:webview_guardian/src/infrastructure/isolate/isolate.dart';

void main() {
  group('filter parser worker cache identity', () {
    test('uses metadata hashes deterministically regardless of subscription order', () {
      const first = FilterSubscription(url: 'https://filters.test/first.txt');
      const second = FilterSubscription(url: 'https://filters.test/second.txt');
      final metadataByUrl = <String, CachedFilterListMetadata>{
        first.url: _metadata(payloadSha256: 'a' * 64, payloadLength: 10),
        second.url: _metadata(payloadSha256: 'b' * 64, payloadLength: 20),
      };

      final identityA = buildEngineCacheIdentityForTesting(
        subscriptions: [first, second],
        metadataByUrl: metadataByUrl,
      );
      final identityB = buildEngineCacheIdentityForTesting(
        subscriptions: [second, first],
        metadataByUrl: metadataByUrl,
      );

      expect(identityA, identityB);
    });

    test('changes when stored payload hash changes', () {
      const subscription = FilterSubscription(url: 'https://filters.test/list.txt');

      final identityA = buildEngineCacheIdentityForTesting(
        subscriptions: [subscription],
        metadataByUrl: {
          subscription.url: _metadata(payloadSha256: 'a' * 64, payloadLength: 10),
        },
      );
      final identityB = buildEngineCacheIdentityForTesting(
        subscriptions: [subscription],
        metadataByUrl: {
          subscription.url: _metadata(payloadSha256: 'b' * 64, payloadLength: 10),
        },
      );

      expect(identityA, isNot(identityB));
    });

    test('changes when subscription data is missing instead of using ad-hoc booleans', () {
      const subscription = FilterSubscription(url: 'https://filters.test/list.txt');

      final missingIdentity = buildEngineCacheIdentityForTesting(
        subscriptions: [subscription],
        metadataByUrl: const {},
      );
      final presentIdentity = buildEngineCacheIdentityForTesting(
        subscriptions: [subscription],
        metadataByUrl: {
          subscription.url: _metadata(payloadSha256: 'a' * 64, payloadLength: 10),
        },
      );

      expect(missingIdentity, isNot(presentIdentity));
    });

    test('does not reuse compiled cache identity from engine format 4', () async {
      const subscription = FilterSubscription(
        url: 'https://filters.test/list.txt',
        updateInterval: Duration(hours: 6),
      );
      final metadata = _metadata(payloadSha256: 'a' * 64, payloadLength: 10);
      final metadataByUrl = {subscription.url: metadata};
      final previousIdentity = sha256
          .convert(
            utf8.encode(
              jsonEncode({
                'engineCacheFormatVersion': 4,
                'filterParserVersion': 3,
                'subscriptions': [
                  {
                    'url': subscription.url,
                    'updateIntervalMicroseconds': subscription.updateInterval?.inMicroseconds,
                    'filterSha256': metadata.payloadSha256,
                    'filterLength': metadata.payloadLength,
                  },
                ],
              }),
            ),
          )
          .toString();
      final currentIdentity = buildEngineCacheIdentityForTesting(
        subscriptions: [subscription],
        metadataByUrl: metadataByUrl,
      );
      final tempDir = Directory.systemTemp.createTempSync('filter_parser_worker_test_');
      final storage = FilterStorage(overridePath: tempDir.path);

      try {
        await storage.saveEngineBytes(
          Uint8List.fromList([1, 2, 3]),
          cacheIdentity: previousIdentity,
        );

        expect(await storage.loadEngineBytes(cacheIdentity: currentIdentity), isNull);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('filter parser worker materialization', () {
    late Directory tempDir;
    late File filterFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('filter_parser_worker_test_');
      filterFile = File('${tempDir.path}/filters.txt')
        ..writeAsStringSync(r'''
[Adblock Plus 2.0]
banner.js
first.example,second.example#$#body { color: red; }
''');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('materialized compiled engine matches token-dispatched rules', () async {
      final completer = Completer<CompiledFilterEngine>();
      final errors = <WebViewError>[];
      final manager = FilterIsolateManager(
        onEngineReady: (engine, _, _, _) => completer.complete(engine),
        onWorkerEvent: (_) {},
        onWorkerError: errors.add,
      );

      await manager
          .runBuildJob(
            subscriptions: [FilterSubscription(url: filterFile.path)],
            httpOptions: const FilterHttpOptions(),
            storagePath: tempDir.path,
            useTestClient: true,
          )
          .timeout(const Duration(seconds: 5));

      final engine = await completer.future.timeout(const Duration(seconds: 5));
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(_request('https://site.test/banner.js'));

      expect(errors, isEmpty);
      expect(result, isA<Block>());
      expect(engine.cssInjectRules['first.example'], hasLength(1));
      expect(engine.cssInjectRules['second.example'], hasLength(1));
      expect(engine.cssInjectRules, isNot(contains('*')));

      manager.dispose();
    });

    test('keeps only trie-complete hostname rules out of dispatch', () async {
      filterFile.writeAsStringSync(r'''
[Adblock Plus 2.0]
||a.co^$script,third-party,important,domain=site.test
||B.co^
||c.co
||d.co^$match-case
||e_f^
''');
      final completer = Completer<CompiledFilterEngine>();
      final errors = <WebViewError>[];
      final manager = FilterIsolateManager(
        onEngineReady: (engine, _, _, _) => completer.complete(engine),
        onWorkerEvent: (_) {},
        onWorkerError: errors.add,
      );

      try {
        await manager
            .runBuildJob(
              subscriptions: [FilterSubscription(url: filterFile.path)],
              httpOptions: const FilterHttpOptions(),
              storagePath: tempDir.path,
              useTestClient: true,
            )
            .timeout(const Duration(seconds: 5));

        final engine = await completer.future.timeout(const Duration(seconds: 5));
        final matcher = FilterMatcher(FilterEngineRef(engine));
        const completeRule = NetworkBlockRule(
          pattern: '||a.co^',
          resourceTypes: {ResourceType.script},
          isThirdPartyOnly: true,
          isImportant: true,
          includeDomains: {'site.test'},
        );
        final unsafeRules = <FilterRule>{
          const NetworkBlockRule(pattern: '||B.co^'),
          const NetworkBlockRule(pattern: '||c.co'),
          const NetworkBlockRule(pattern: '||d.co^', isMatchCase: true),
          const NetworkBlockRule(pattern: '||e_f^'),
        };

        expect(errors, isEmpty);
        expect(engine.trieRules, contains(completeRule));
        expect(
          engine.tokenDispatchTable.values.expand((rules) => rules),
          isNot(contains(completeRule)),
        );
        expect(engine.fallbackRules, isNot(contains(completeRule)));
        expect(engine.fallbackRules, containsAll(unsafeRules));
        expect(matcher.matchNetworkRequest(_request('https://a.co/script.js')), isA<Block>());
        expect(matcher.matchNetworkRequest(_request('https://b.co/script.js')), isA<Block>());
      } finally {
        manager.dispose();
      }
    });
  });

  test('limits concurrent subscription downloads and preserves URL metadata', () async {
    final tempDir = Directory.systemTemp.createTempSync('filter_parser_worker_test_');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final errors = <WebViewError>[];
    var activeDownloads = 0;
    var maxActiveDownloads = 0;
    server.listen((request) async {
      request.response.persistentConnection = false;
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
        return;
      }

      activeDownloads++;
      if (activeDownloads > maxActiveDownloads) maxActiveDownloads = activeDownloads;
      final name = request.uri.pathSegments.single;
      try {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        request.response
          ..headers.set(HttpHeaders.etagHeader, 'etag-$name')
          ..write('[Adblock Plus 2.0]\n||$name.example^');
        await request.response.close();
      } finally {
        activeDownloads--;
      }
    });
    final subscriptions = List.generate(
      5,
      (index) => FilterSubscription(
        url: 'http://${server.address.address}:${server.port}/list-$index',
      ),
    );
    final manager = FilterIsolateManager(
      onEngineReady: (_, _, _, _) {},
      onWorkerEvent: (_) {},
      onWorkerError: errors.add,
    );

    try {
      await manager
          .runBuildJob(
            subscriptions: subscriptions,
            httpOptions: const FilterHttpOptions(
              maxConcurrentDownloads: 2,
              connectTimeout: Duration(seconds: 1),
              receiveTimeout: Duration(seconds: 2),
            ),
            storagePath: tempDir.path,
          )
          .timeout(const Duration(seconds: 10));

      expect(maxActiveDownloads, 2);
      expect(errors.whereType<FilterFetchFailed>(), isEmpty);
      final storage = FilterStorage(overridePath: tempDir.path);
      for (final subscription in subscriptions) {
        final name = Uri.parse(subscription.url).pathSegments.single;
        final metadata = await storage.loadFilterListMetadata(subscription.url);
        expect(metadata?.etag, 'etag-$name');
      }
    } finally {
      manager.dispose();
      await server.close(force: true);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  });
}

NetworkRequest _request(String url) {
  final uri = Uri.parse(url);
  return NetworkRequest(
    url: uri.toString(),
    host: uri.host,
    sourceHost: 'site.test',
    resourceType: ResourceType.script,
  );
}

CachedFilterListMetadata _metadata({
  required String payloadSha256,
  required int payloadLength,
}) {
  return (
    etag: 'etag',
    timestamp: 1,
    payloadSha256: payloadSha256,
    payloadLength: payloadLength,
  );
}
