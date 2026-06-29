import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/webview_guardian.dart';

void main() {
  group('StreamWebViewObserver', () {
    test('late onEvent after dispose does not throw or emit', () async {
      final observer = StreamWebViewObserver(delegates: const []);
      final events = <WebViewEvent>[];
      final subscription = observer.events.listen(events.add);

      observer.dispose();

      expect(() => observer.onEvent(const FilterCacheCleared()), returnsNormally);
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      await subscription.cancel();
    });

    test('late onError after dispose does not throw or emit', () async {
      final observer = StreamWebViewObserver(delegates: const []);
      final errors = <WebViewError>[];
      final subscription = observer.errors.listen(errors.add);

      observer.dispose();

      expect(
        () => observer.onError(const EngineInitFailed('late error')),
        returnsNormally,
      );
      await Future<void>.delayed(Duration.zero);

      expect(errors, isEmpty);

      await subscription.cancel();
    });
  });
}
