import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webview_guardian/src/src.dart';

class _MockInAppWebViewController extends Mock implements InAppWebViewController {}

class _MockWebResourceRequest extends Mock implements WebResourceRequest {}

class _MockFilterRepository extends Mock implements FilterRepository {}

class _FakeInjectionOrchestrator extends InjectionOrchestrator {
  _FakeInjectionOrchestrator() : super(_MockFilterRepository());

  final requestedHosts = <String>[];
  String scriptMarker = 'initial';

  @override
  List<UserScript> buildUserScripts(String hostname) {
    requestedHosts.add(hostname);
    return [
      UserScript(
        source: 'document.documentElement.dataset.injectedHost = "$hostname:$scriptMarker";',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ];
  }
}

class _FakeTrafficInterceptor implements TrafficInterceptor {
  int callCount = 0;

  @override
  Future<void> onEngineUpdated() async {}

  @override
  FutureOr<WebResourceResponse?> Function(
    InAppWebViewController controller,
    WebResourceRequest request,
  )?
  get shouldInterceptRequest => _intercept;

  WebResourceResponse? _intercept(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) {
    callCount++;
    return WebResourceResponse(statusCode: 204, data: Uint8List(0));
  }
}

class _FakeAdblockService extends AdblockService {
  _FakeAdblockService({
    required this.ready,
    required this.rules,
    this.fakeOrchestrator,
    this.fakeTrafficInterceptor,
  });

  final ValueNotifier<bool> ready;
  final int rules;
  final _FakeInjectionOrchestrator? fakeOrchestrator;
  final _FakeTrafficInterceptor? fakeTrafficInterceptor;
  final StreamController<int> _ruleCounts = StreamController<int>.broadcast();
  bool enabled = true;

  @override
  bool get isEnabled => enabled;

  @override
  set isEnabled(bool value) {
    enabled = value;
  }

  @override
  ValueNotifier<bool> get isReady => ready;

  @override
  int get ruleCount => rules;

  @override
  Stream<int> get ruleCountStream => _ruleCounts.stream;

  @override
  InjectionOrchestrator? get orchestrator => fakeOrchestrator;

  @override
  TrafficInterceptor? get trafficInterceptor => fakeTrafficInterceptor;

  void emitRuleCount(int count) => _ruleCounts.add(count);

  @override
  void dispose() {
    ready.dispose();
    unawaited(_ruleCounts.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      UserScript(
        source: '',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    );
  });

  group('InAppWebViewAdblockAdapter', () {
    late _FakeInjectionOrchestrator orchestrator;
    late _FakeTrafficInterceptor trafficInterceptor;
    late _FakeAdblockService service;
    late _MockInAppWebViewController controller;
    late _MockWebResourceRequest request;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      orchestrator = _FakeInjectionOrchestrator();
      trafficInterceptor = _FakeTrafficInterceptor();
      service = _FakeAdblockService(
        ready: ValueNotifier(true),
        rules: 1,
        fakeOrchestrator: orchestrator,
        fakeTrafficInterceptor: trafficInterceptor,
      );
      controller = _MockInAppWebViewController();
      request = _MockWebResourceRequest();

      when(() => controller.removeAllUserScripts()).thenAnswer((_) async {});
      when(
        () => controller.addUserScript(userScript: any(named: 'userScript')),
      ).thenAnswer((_) async {});
    });

    tearDown(() {
      service.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    test('applies adblock settings on top of base settings', () {
      final adapter = InAppWebViewAdblockAdapter(
        adblockService: service,
        baseSettings: InAppWebViewSettings(javaScriptEnabled: false),
      );

      final settings = adapter.initialSettings;

      expect(settings.javaScriptEnabled, isFalse);
      expect(settings.useShouldInterceptRequest, isTrue);
      expect(settings.useShouldOverrideUrlLoading, isTrue);
      expect(settings.transparentBackground, isTrue);
      expect(settings.mixedContentMode, MixedContentMode.MIXED_CONTENT_NEVER_ALLOW);
      expect(settings.thirdPartyCookiesEnabled, isFalse);
      expect(settings.allowsLinkPreview, isFalse);
      expect(settings.resourceCustomSchemes, ['adblock']);
    });

    test('merges adblock scheme with caller-provided custom schemes', () {
      final adapter = InAppWebViewAdblockAdapter(
        adblockService: service,
        baseSettings: InAppWebViewSettings(resourceCustomSchemes: ['app']),
      );

      expect(adapter.initialSettings.resourceCustomSchemes, ['app', 'adblock']);
    });

    test('does not mutate caller-owned base settings', () {
      final baseSettings = InAppWebViewSettings(
        javaScriptEnabled: false,
        resourceCustomSchemes: ['app'],
      );

      final adapter = InAppWebViewAdblockAdapter(
        adblockService: service,
        baseSettings: baseSettings,
      );

      expect(adapter.initialSettings.useShouldInterceptRequest, isTrue);
      expect(adapter.initialSettings.resourceCustomSchemes, ['app', 'adblock']);
      expect(baseSettings.useShouldInterceptRequest, isNull);
      expect(baseSettings.resourceCustomSchemes, ['app']);
    });

    test('builds initial scripts for initial URL when service is ready', () {
      final adapter = InAppWebViewAdblockAdapter(
        adblockService: service,
        initialUrl: Uri.parse('https://example.com/page'),
      );

      final scripts = adapter.initialUserScripts;

      expect(scripts, hasLength(1));
      expect(scripts.single.source, contains('example.com'));
      expect(orchestrator.requestedHosts, ['example.com']);
    });

    test('returns empty initial scripts when initial URL is omitted', () {
      final adapter = InAppWebViewAdblockAdapter(adblockService: service);

      expect(adapter.initialUserScripts, isEmpty);
      expect(orchestrator.requestedHosts, isEmpty);
    });

    test('retries same-host injection when initial scripts were unavailable', () async {
      final notReadyService = _FakeAdblockService(
        ready: ValueNotifier(false),
        rules: 1,
        fakeOrchestrator: orchestrator,
        fakeTrafficInterceptor: trafficInterceptor,
      );
      final adapter = InAppWebViewAdblockAdapter(
        adblockService: notReadyService,
        initialUrl: Uri.parse('https://example.com'),
      );

      expect(adapter.initialUserScripts, isEmpty);

      notReadyService.ready.value = true;
      await adapter.onLoadStart(controller, WebUri('https://example.com'));

      verify(() => controller.removeAllUserScripts()).called(1);
      final captured = verify(
        () => controller.addUserScript(userScript: captureAny(named: 'userScript')),
      ).captured.cast<UserScript>();
      expect(captured.single.source, contains('example.com'));

      notReadyService.dispose();
    });

    test('does not reinstall same-host scripts when initial scripts were preloaded', () async {
      final adapter = InAppWebViewAdblockAdapter(
        adblockService: service,
        initialUrl: Uri.parse('https://example.com'),
      );

      expect(adapter.initialUserScripts, isNotEmpty);
      await adapter.onLoadStart(controller, WebUri('https://example.com'));

      verifyNever(() => controller.removeAllUserScripts());
      verifyNever(() => controller.addUserScript(userScript: any(named: 'userScript')));
    });

    test('applies scripts for a new host before allowing main-frame navigation', () async {
      final adapter = InAppWebViewAdblockAdapter(
        adblockService: service,
        initialUrl: Uri.parse('https://example.com'),
      );

      final policy = await adapter.shouldOverrideUrlLoading!(
        controller,
        NavigationAction(
          isForMainFrame: true,
          request: URLRequest(url: WebUri('https://other.example')),
        ),
      );

      expect(policy, NavigationActionPolicy.ALLOW);
      verify(() => controller.removeAllUserScripts()).called(1);
      final captured = verify(
        () => controller.addUserScript(userScript: captureAny(named: 'userScript')),
      ).captured.cast<UserScript>();
      expect(captured.single.source, contains('other.example'));
    });

    test('reinstalls same-host scripts after engine updates', () async {
      final adapter = InAppWebViewAdblockAdapter(adblockService: service);

      await adapter.onLoadStart(controller, WebUri('https://example.com'));

      verify(() => controller.removeAllUserScripts()).called(1);
      var captured = verify(
        () => controller.addUserScript(userScript: captureAny(named: 'userScript')),
      ).captured.cast<UserScript>();
      expect(captured.single.source, contains('example.com:initial'));

      reset(controller);
      when(() => controller.removeAllUserScripts()).thenAnswer((_) async {});
      when(
        () => controller.addUserScript(userScript: any(named: 'userScript')),
      ).thenAnswer((_) async {});

      orchestrator.scriptMarker = 'updated';
      service.emitRuleCount(2);
      await Future<void>.delayed(Duration.zero);

      await adapter.onLoadStart(controller, WebUri('https://example.com'));

      verify(() => controller.removeAllUserScripts()).called(1);
      captured = verify(
        () => controller.addUserScript(userScript: captureAny(named: 'userScript')),
      ).captured.cast<UserScript>();
      expect(captured.single.source, contains('example.com:updated'));
    });

    test('bypasses request interception when service is disabled', () {
      service.isEnabled = false;
      final adapter = InAppWebViewAdblockAdapter(adblockService: service);

      final response = adapter.shouldInterceptRequest!(controller, request);

      expect(response, isNull);
      expect(trafficInterceptor.callCount, 0);
    });

    test('delegates request interception when service can block requests', () {
      final adapter = InAppWebViewAdblockAdapter(adblockService: service);

      final response = adapter.shouldInterceptRequest!(controller, request) as WebResourceResponse?;

      expect(response, isNotNull);
      expect(response!.statusCode, 204);
      expect(trafficInterceptor.callCount, 1);
    });
  });
}
