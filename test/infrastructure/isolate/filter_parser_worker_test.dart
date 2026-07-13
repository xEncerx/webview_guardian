import 'dart:async';
import 'dart:io';

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
