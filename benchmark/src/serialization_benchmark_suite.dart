import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

import 'benchmark_contract.dart';

final class SerializationBenchmarkSuite extends BenchmarkSuite<void> {
  const SerializationBenchmarkSuite(super.runner, this.engine);

  final CompiledFilterEngine engine;

  @override
  void run() {
    final serializer = EngineSerializer();
    final serialized = serializer.serialize(engine);
    final restored = serializer.deserialize(serialized);
    checkBenchmarkInvariant(
      restored.totalRules == engine.totalRules,
      'Serialized engine rule count changed.',
    );
    _checkSemanticEquivalence(engine, restored);
    runner
      ..measureSync(
        id: 'serialize.mixed-engine',
        suite: 'serialize',
        fixture: 'abp-large+hosts+controlled',
        scenario: 'EngineSerializer.serialize',
        samples: 5,
        operation: () => serializer.serialize(engine).length,
        ruleCounts: {'engine': engine.totalRules},
        metrics: {'serializedBytes': serialized.length},
      )
      ..measureSync(
        id: 'serialize.deserialize-mixed-engine',
        suite: 'serialize',
        fixture: 'abp-large+hosts+controlled',
        scenario: 'EngineSerializer.deserialize',
        operation: () => serializer.deserialize(serialized).totalRules,
        ruleCounts: {'engine': engine.totalRules},
        metrics: {'serializedBytes': serialized.length},
      );
  }
}

void _checkSemanticEquivalence(CompiledFilterEngine original, CompiledFilterEngine restored) {
  final originalRef = FilterEngineRef(original);
  final restoredRef = FilterEngineRef(restored);
  final originalMatcher = FilterMatcher(originalRef);
  final restoredMatcher = FilterMatcher(restoredRef);
  for (final url in [
    'https://bench-trie.invalid/ad.js',
    'https://guardian-clean.invalid/bench-token-unique.js',
    'https://bench-priority.invalid/ad.js',
    'https://guardian-clean.invalid/app.js',
  ]) {
    final uri = Uri.parse(url);
    final request = NetworkRequest(
      url: url,
      host: uri.host,
      sourceHost: 'publisher.invalid',
      resourceType: ResourceType.script,
    );
    checkBenchmarkInvariant(
      originalMatcher.matchNetworkRequest(request).runtimeType ==
          restoredMatcher.matchNetworkRequest(request).runtimeType,
      'Serialized engine changed matcher decision for $url.',
    );
  }

  final originalRepository = FilterRepositoryImpl(
    matcher: originalMatcher,
    engineRef: originalRef,
    observer: null,
  );
  final restoredRepository = FilterRepositoryImpl(
    matcher: restoredMatcher,
    engineRef: restoredRef,
    observer: null,
  );
  checkBenchmarkInvariant(
    _cosmeticSelectors(originalRepository) == _cosmeticSelectors(restoredRepository),
    'Serialized engine changed cosmetic selection.',
  );
  checkBenchmarkInvariant(
    _scriptlets(originalRepository) == _scriptlets(restoredRepository),
    'Serialized engine changed scriptlet selection.',
  );
  checkBenchmarkInvariant(
    _css(originalRepository) == _css(restoredRepository),
    'Serialized engine changed CSS selection.',
  );
}

String _cosmeticSelectors(FilterRepositoryImpl repository) => repository
    .getCosmeticRuleSet('bench.example')
    .allRules
    .map((rule) => '${rule.selector}|${rule.includeDomains}|${rule.excludeDomains}')
    .join('\n');

String _scriptlets(FilterRepositoryImpl repository) => repository
    .getScriptletRules('bench.example')
    .map((rule) => '${rule.scriptletName}|${rule.domains}|${rule.args}')
    .join('\n');

String _css(FilterRepositoryImpl repository) => repository
    .getCssInjectRules('bench.example')
    .map((rule) => '${rule.css}|${rule.includeDomains}|${rule.excludeDomains}')
    .join('\n');
