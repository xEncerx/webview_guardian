import 'package:test/test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/isolate/filter_parser_worker.dart';

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
