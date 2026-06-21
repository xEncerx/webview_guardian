import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

void main() {
  group('FilterRepositoryImpl observability', () {
    FilterRepositoryImpl repositoryFor({
      required CompiledFilterEngine engine,
      required _RecordingObserver observer,
      WebViewObservabilityOptions observabilityOptions = const WebViewObservabilityOptions(),
    }) {
      final engineRef = FilterEngineRef(engine);

      return FilterRepositoryImpl(
        matcher: FilterMatcher(engineRef),
        engineRef: engineRef,
        observer: observer,
        observabilityOptions: observabilityOptions,
      );
    }

    test('emits blocked request events with default options', () {
      final observer = _RecordingObserver();
      final repository = repositoryFor(
        engine: _engineWithFallbackRules({const NetworkBlockRule(pattern: 'ads.js')}),
        observer: observer,
      );

      final decision = repository.lookupNetworkRequest(_request('https://cdn.example/ads.js'));

      expect(decision, isA<Block>());
      expect(observer.events, hasLength(1));
      expect(observer.events.single, isA<RequestBlocked>());
    });

    test('does not emit blocked request events when disabled', () {
      final observer = _RecordingObserver();
      final repository = repositoryFor(
        engine: _engineWithFallbackRules({const NetworkBlockRule(pattern: 'ads.js')}),
        observer: observer,
        observabilityOptions: const WebViewObservabilityOptions(emitBlockedRequests: false),
      );

      final decision = repository.lookupNetworkRequest(_request('https://cdn.example/ads.js'));

      expect(decision, isA<Block>());
      expect(observer.events.whereType<RequestBlocked>(), isEmpty);
    });

    test('does not emit allowed request events with default options', () {
      final observer = _RecordingObserver();
      final repository = repositoryFor(
        engine: _engineWithFallbackRules(const {}),
        observer: observer,
      );

      final decision = repository.lookupNetworkRequest(_request('https://cdn.example/app.js'));

      expect(decision, isA<Allow>());
      expect(observer.events.whereType<RequestAllowed>(), isEmpty);
    });

    test('emits allowed request events when explicitly enabled', () {
      final observer = _RecordingObserver();
      final repository = repositoryFor(
        engine: _engineWithFallbackRules(const {}),
        observer: observer,
        observabilityOptions: const WebViewObservabilityOptions(emitAllowedRequests: true),
      );

      final decision = repository.lookupNetworkRequest(_request('https://cdn.example/app.js'));

      expect(decision, isA<Allow>());
      expect(observer.events, hasLength(1));
      expect(observer.events.single, isA<RequestAllowed>());
    });

    test('does not emit cosmetic injection events when disabled', () {
      const rule = CosmeticHideRule(selector: '.ad');
      final observer = _RecordingObserver();
      final repository = repositoryFor(
        engine: _engineWithCosmeticRules({
          'example.com': [rule],
        }),
        observer: observer,
        observabilityOptions: const WebViewObservabilityOptions(emitCosmeticInjections: false),
      );

      expect(repository.getCosmeticRules('example.com'), [rule]);
      expect(observer.events.whereType<CosmeticCssInjected>(), isEmpty);
    });

    test('does not emit scriptlet injection events when disabled', () {
      const rule = ScriptletRule(scriptletName: 'abort-on-property-read');
      final observer = _RecordingObserver();
      final repository = repositoryFor(
        engine: _engineWithScriptletRules({
          'example.com': [rule],
        }),
        observer: observer,
        observabilityOptions: const WebViewObservabilityOptions(emitScriptletInjections: false),
      );

      expect(repository.getScriptletRules('example.com'), [rule]);
      expect(observer.events.whereType<ScriptletInjected>(), isEmpty);
    });
  });

  group('FilterRepositoryImpl cosmetic rules', () {
    FilterRepositoryImpl repositoryFor({
      required Map<String, List<CosmeticHideRule>> hideRules,
      Map<String, List<CosmeticExceptionRule>> exceptionRules = const {},
    }) {
      final engineRef = FilterEngineRef(
        CompiledFilterEngine(
          totalRules:
              hideRules.values.fold<int>(0, (sum, rules) => sum + rules.length) +
              exceptionRules.values.fold<int>(0, (sum, rules) => sum + rules.length),
          trieBuffer: Uint32List(1),
          trieRules: const [],
          tokenDispatchTable: const {},
          fallbackRules: const {},
          cosmeticHideRules: hideRules,
          cosmeticExceptionRules: exceptionRules,
          scriptletRules: const {},
          cssInjectRules: const {},
        ),
      );

      return FilterRepositoryImpl(
        matcher: FilterMatcher(engineRef),
        engineRef: engineRef,
        observer: null,
      );
    }

    test('does not return hide rules excluded for the hostname or its parent', () {
      const rule = CosmeticHideRule(
        selector: '.ad',
        includeDomains: ['example.com'],
        excludeDomains: ['sub.example.com'],
      );
      final repository = repositoryFor(
        hideRules: {
          'example.com': [rule],
        },
      );

      expect(repository.getCosmeticRules('example.com'), [rule]);
      expect(repository.getCosmeticRules('sub.example.com'), isEmpty);
      expect(repository.getCosmeticRules('deep.sub.example.com'), isEmpty);
    });

    test('does not apply excluded exception rules to suppress hide rules', () {
      const hideRule = CosmeticHideRule(selector: '.ad');
      const exceptionRule = CosmeticExceptionRule(
        selector: '.ad',
        includeDomains: ['example.com'],
        excludeDomains: ['sub.example.com'],
      );
      final repository = repositoryFor(
        hideRules: {
          '*': [hideRule],
        },
        exceptionRules: {
          'example.com': [exceptionRule],
        },
      );

      expect(repository.getCosmeticRules('example.com'), isEmpty);
      expect(repository.getCosmeticRules('sub.example.com'), [hideRule]);
    });
  });
}

CompiledFilterEngine _engineWithFallbackRules(Set<FilterRule> fallbackRules) {
  return CompiledFilterEngine(
    totalRules: fallbackRules.length,
    trieBuffer: Uint32List(1),
    trieRules: const [],
    tokenDispatchTable: const {},
    fallbackRules: fallbackRules,
    cosmeticHideRules: const {},
    cosmeticExceptionRules: const {},
    scriptletRules: const {},
    cssInjectRules: const {},
  );
}

CompiledFilterEngine _engineWithCosmeticRules(Map<String, List<CosmeticHideRule>> hideRules) {
  return CompiledFilterEngine(
    totalRules: hideRules.values.fold<int>(0, (sum, rules) => sum + rules.length),
    trieBuffer: Uint32List(1),
    trieRules: const [],
    tokenDispatchTable: const {},
    fallbackRules: const {},
    cosmeticHideRules: hideRules,
    cosmeticExceptionRules: const {},
    scriptletRules: const {},
    cssInjectRules: const {},
  );
}

CompiledFilterEngine _engineWithScriptletRules(Map<String, List<ScriptletRule>> scriptletRules) {
  return CompiledFilterEngine(
    totalRules: scriptletRules.values.fold<int>(0, (sum, rules) => sum + rules.length),
    trieBuffer: Uint32List(1),
    trieRules: const [],
    tokenDispatchTable: const {},
    fallbackRules: const {},
    cosmeticHideRules: const {},
    cosmeticExceptionRules: const {},
    scriptletRules: scriptletRules,
    cssInjectRules: const {},
  );
}

NetworkRequest _request(String url) {
  return NetworkRequest(
    url: url,
    host: Uri.parse(url).host,
    resourceType: ResourceType.script,
    sourceHost: 'example.com',
  );
}

final class _RecordingObserver implements WebViewObserver {
  final events = <WebViewEvent>[];
  final errors = <WebViewError>[];

  @override
  void onEvent(WebViewEvent event) => events.add(event);

  @override
  void onError(WebViewError error) => errors.add(error);
}
