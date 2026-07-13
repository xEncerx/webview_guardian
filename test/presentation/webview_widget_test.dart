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

      when(
        () => controller.removeUserScriptsByGroupName(groupName: any(named: 'groupName')),
      ).thenAnswer((_) async {});
      when(
        () => controller.addUserScript(userScript: any(named: 'userScript')),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      service.dispose();
    });

    testWidgets('uses the initial Uri for the platform request and adblock host', (tester) async {
      service.ready.value = true;
      final initialUri = Uri.parse('https://sub.example.com/path?item=1');

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: initialUri,
            adblockService: service,
          ),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;
      final requestedUrl = webViewParams.initialUrlRequest?.url;

      expect(requestedUrl, isNotNull);
      expect(requestedUrl!.toString(), initialUri.toString());
      expect(requestedUrl.host, initialUri.host);
      expect(webViewParams.initialUserScripts, hasLength(1));
      expect(webViewParams.initialUserScripts!.single.source, contains(initialUri.host));
    });

    testWidgets('retries same-host injection when initial scripts were unavailable', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
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

      verify(
        () => controller.removeUserScriptsByGroupName(groupName: any(named: 'groupName')),
      ).called(1);
      verify(() => controller.addUserScript(userScript: any(named: 'userScript'))).called(
        greaterThan(0),
      );
    });

    testWidgets('provides initial document-start scripts when adblock is ready', (
      tester,
    ) async {
      service.ready.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
            adblockService: service,
          ),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final scripts = webView.platform.params.initialUserScripts!;

      expect(scripts, hasLength(1));
      expect(scripts.single.source, contains('example.com'));
      expect(scripts.single.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
    });

    testWidgets('does not re-install same-host initial scripts from onLoadStart', (
      tester,
    ) async {
      service.ready.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
            adblockService: service,
          ),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;
      expect(webViewParams.initialUserScripts, isNotEmpty);

      webViewParams.onLoadStart!(controller, WebUri('https://example.com'));
      await tester.pump();

      verifyNever(
        () => controller.removeUserScriptsByGroupName(groupName: any(named: 'groupName')),
      );
      verifyNever(() => controller.addUserScript(userScript: any(named: 'userScript')));
    });

    testWidgets('parent rebuild does not rearm initial preload skip', (
      tester,
    ) async {
      service.ready.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
            adblockService: service,
          ),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;
      final shouldOverrideUrlLoading = webViewParams.shouldOverrideUrlLoading!;

      webViewParams.onLoadStart!(controller, WebUri('https://example.com'));
      await tester.pump();

      await shouldOverrideUrlLoading(
        controller,
        NavigationAction(
          isForMainFrame: true,
          request: URLRequest(url: WebUri('https://other.example')),
        ),
      );
      clearInteractions(controller);

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
            adblockService: service,
          ),
        ),
      );

      await shouldOverrideUrlLoading(
        controller,
        NavigationAction(
          isForMainFrame: true,
          request: URLRequest(url: WebUri('https://example.com')),
        ),
      );

      verify(
        () => controller.removeUserScriptsByGroupName(groupName: any(named: 'groupName')),
      ).called(1);
      final captured = verify(
        () => controller.addUserScript(userScript: captureAny(named: 'userScript')),
      ).captured.cast<UserScript>();
      expect(captured, hasLength(1));
      expect(captured.single.source, contains('example.com'));
    });

    testWidgets('does not enable adblock-specific settings without adblock service', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: WebView(initialUrl: Uri.parse('https://example.com')),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;
      final settings = webViewParams.initialSettings;

      expect(settings?.useShouldOverrideUrlLoading, isFalse);
      expect(settings?.useShouldInterceptRequest, isFalse);
      expect(settings?.mixedContentMode, isNull);
      expect(settings?.thirdPartyCookiesEnabled, isNull);
      expect(settings?.transparentBackground, isNull);
      expect(settings?.allowsLinkPreview, isNull);
      expect(settings?.resourceCustomSchemes, isNull);
      expect(webViewParams.shouldOverrideUrlLoading, isNull);
      expect(webViewParams.shouldInterceptRequest, isNull);
    });

    testWidgets('removes adblock callbacks when service is removed on rebuild', (tester) async {
      service.ready.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
            adblockService: service,
          ),
        ),
      );

      var webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      expect(webView.platform.params.shouldInterceptRequest, isNotNull);
      expect(webView.platform.params.shouldOverrideUrlLoading, isNotNull);

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(initialUrl: Uri.parse('https://example.com')),
        ),
      );

      webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;

      expect(webViewParams.initialSettings?.useShouldInterceptRequest, isFalse);
      expect(webViewParams.initialSettings?.useShouldOverrideUrlLoading, isFalse);
      expect(webViewParams.shouldInterceptRequest, isNull);
      expect(webViewParams.shouldOverrideUrlLoading, isNull);
    });

    testWidgets('updates host scripts before allowing a main-frame navigation', (
      tester,
    ) async {
      service.ready.value = true;

      await tester.pumpWidget(
        MaterialApp(
          home: WebView(
            initialUrl: Uri.parse('https://example.com'),
            adblockService: service,
          ),
        ),
      );

      final webView = tester.widget<InAppWebView>(find.byType(InAppWebView));
      final webViewParams = webView.platform.params;
      final shouldOverrideUrlLoading = webViewParams.shouldOverrideUrlLoading;

      expect(webViewParams.initialSettings?.useShouldOverrideUrlLoading, isTrue);
      expect(shouldOverrideUrlLoading, isNotNull);

      final policy = await shouldOverrideUrlLoading!(
        controller,
        NavigationAction(
          isForMainFrame: true,
          request: URLRequest(url: WebUri('https://other.example')),
        ),
      );

      expect(policy, NavigationActionPolicy.ALLOW);
      verify(
        () => controller.removeUserScriptsByGroupName(groupName: any(named: 'groupName')),
      ).called(1);
      final captured = verify(
        () => controller.addUserScript(userScript: captureAny(named: 'userScript')),
      ).captured.cast<UserScript>();
      expect(captured, hasLength(1));
      expect(captured.single.source, contains('other.example'));
      expect(captured.single.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
    });
  });
}
