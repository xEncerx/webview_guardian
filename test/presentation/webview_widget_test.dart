import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_guardian/src/src.dart';

class _MockInAppWebViewController extends Mock implements InAppWebViewController {}

class _MockFilterRepository extends Mock implements FilterRepository {}

class _FakeAdblockService extends AdblockService {
  _FakeAdblockService(this._orchestrator);

  final InjectionOrchestrator _orchestrator;
  final ValueNotifier<bool> ready = ValueNotifier(false);

  @override
  ValueNotifier<bool> get isReady => ready;

  @override
  int get ruleCount => 1;

  @override
  InjectionOrchestrator? get orchestrator => ready.value ? _orchestrator : null;

  @override
  void dispose() {
    ready.dispose();
  }
}

class _FakeInjectionOrchestrator extends InjectionOrchestrator {
  _FakeInjectionOrchestrator() : super(_MockFilterRepository());

  @override
  List<UserScript> buildUserScripts(String hostname) => [
    UserScript(
      source: 'document.documentElement.dataset.injectedHost = "$hostname";',
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
  ];
}

class _FakeInAppWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _FakePlatformInAppWebViewWidget(params);
}

class _FakePlatformInAppWebViewWidget extends PlatformInAppWebViewWidget {
  _FakePlatformInAppWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    InAppWebViewPlatform.instance = _FakeInAppWebViewPlatform();
    registerFallbackValue(
      UserScript(
        source: '',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
  });

  group('WebView injection lifecycle', () {
    late _FakeAdblockService service;
    late _MockInAppWebViewController controller;

    setUp(() {
      service = _FakeAdblockService(_FakeInjectionOrchestrator());
      controller = _MockInAppWebViewController();

      when(() => controller.removeAllUserScripts()).thenAnswer((_) async {});
      when(
        () => controller.addUserScript(userScript: any(named: 'userScript')),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      service.dispose();
    });

    testWidgets('retries same-host injection when initial scripts were unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: 'https://example.com',
            adblockService: service,
          ),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;
      expect(webViewParams.initialUserScripts, isEmpty);

      service.ready.value = true;
      expect(service.isReady.value, isTrue);
      expect(service.orchestrator!.buildUserScripts('example.com'), isNotEmpty);

      webViewParams.onLoadStart!(controller, WebUri('https://example.com'));
      await tester.pump();

      verify(() => controller.removeAllUserScripts()).called(1);
      verify(() => controller.addUserScript(userScript: any(named: 'userScript'))).called(
        greaterThan(0),
      );
    });
  });
}
