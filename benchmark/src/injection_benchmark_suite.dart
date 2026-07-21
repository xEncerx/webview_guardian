import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

import 'benchmark_contract.dart';

final class InjectionBenchmarkSuite extends BenchmarkSuite<void> {
  const InjectionBenchmarkSuite(super.runner, this.engine);

  final CompiledFilterEngine engine;

  @override
  void run() {
    final engineRef = FilterEngineRef(engine);
    final matcher = FilterMatcher(engineRef);
    final repository = FilterRepositoryImpl(matcher: matcher, engineRef: engineRef, observer: null);
    const hosts = ['yandex.ru', 'mail.ru', 'vk.com', 'guardian-clean.invalid'];

    final cosmeticCounts = <String, int>{};
    final scriptletCounts = <String, int>{};
    final cssCounts = <String, int>{};
    for (final host in hosts) {
      cosmeticCounts[host] = repository.getCosmeticRuleSet(host).allRules.length;
      scriptletCounts[host] = repository.getScriptletRules(host).length;
      cssCounts[host] = repository.getCssInjectRules(host).length;
    }

    runner
      ..measureSync(
        id: 'injection.repository-cosmetic-selection',
        suite: 'injection',
        fixture: 'mixed-engine',
        scenario: 'getCosmeticRuleSet across representative hosts',
        iterations: 50,
        warmupIterations: 10,
        operation: () {
          var count = 0;
          for (final host in hosts) {
            count += repository.getCosmeticRuleSet(host).allRules.length;
          }
          return count;
        },
        ruleCounts: {'engine': engine.totalRules},
        metrics: cosmeticCounts,
      )
      ..measureSync(
        id: 'injection.repository-scriptlet-selection',
        suite: 'injection',
        fixture: 'mixed-engine',
        scenario: 'getScriptletRules across representative hosts',
        iterations: 100,
        warmupIterations: 20,
        operation: () {
          var count = 0;
          for (final host in hosts) {
            count += repository.getScriptletRules(host).length;
          }
          return count;
        },
        ruleCounts: {'engine': engine.totalRules},
        metrics: scriptletCounts,
      )
      ..measureSync(
        id: 'injection.repository-css-selection',
        suite: 'injection',
        fixture: 'mixed-engine',
        scenario: 'getCssInjectRules across representative hosts',
        iterations: 100,
        warmupIterations: 20,
        operation: () {
          var count = 0;
          for (final host in hosts) {
            count += repository.getCssInjectRules(host).length;
          }
          return count;
        },
        ruleCounts: {'engine': engine.totalRules},
        metrics: cssCounts,
      );

    final controlledRules = repository.getCosmeticRuleSet('bench.example');
    checkBenchmarkInvariant(
      controlledRules.genericRules.length >= 3000,
      'Controlled generic rule set is too small.',
    );
    checkBenchmarkInvariant(
      controlledRules.allRules.where((rule) => rule.selector == '.bench-duplicate').length == 1,
      'Duplicate selector was not removed.',
    );
    checkBenchmarkInvariant(
      controlledRules.allRules.every((rule) => rule.selector != '.bench-excepted'),
      'Cosmetic exception was not applied.',
    );
    checkBenchmarkInvariant(
      repository.getScriptletRules('bench.example').length >= 4,
      'Scriptlet rules are missing.',
    );
    checkBenchmarkInvariant(
      repository.getCssInjectRules('bench.example').isNotEmpty,
      'Custom CSS rule is missing.',
    );

    for (final mode in GenericCosmeticRuleMode.values) {
      final orchestrator = InjectionOrchestrator(
        repository,
        cosmeticFilteringOptions: CosmeticFilteringOptions(genericRuleMode: mode),
      );
      final scripts = orchestrator.buildUserScripts('bench.example');
      checkBenchmarkInvariant(scripts.isNotEmpty, 'No scripts generated in ${mode.name} mode.');
      runner.measureSync(
        id: 'injection.orchestrator-${mode.name}',
        suite: 'injection',
        fixture: 'mixed-engine+controlled',
        scenario: 'InjectionOrchestrator.buildUserScripts ${mode.name}',
        iterations: 5,
        operation: () {
          final built = orchestrator.buildUserScripts('bench.example');
          var consumed = built.length;
          for (final script in built) {
            consumed += script.source.length;
          }
          return consumed;
        },
        ruleCounts: {
          'engine': engine.totalRules,
          'domainCosmetic': controlledRules.domainSpecificRules.length,
          'genericCosmetic': controlledRules.genericRules.length,
          'scriptlet': repository.getScriptletRules('bench.example').length,
          'css': repository.getCssInjectRules('bench.example').length,
        },
        metrics: _scriptMetrics(scripts),
      );
    }

    final productionOrchestrator = InjectionOrchestrator(repository);
    final productionScripts = <UserScript>[];
    for (final host in hosts) {
      productionScripts.addAll(productionOrchestrator.buildUserScripts(host));
    }
    runner.measureSync(
      id: 'injection.orchestrator-real-hosts',
      suite: 'injection',
      fixture: 'mixed-engine',
      scenario: 'host-side InjectionOrchestrator default mode across representative hosts',
      iterations: 5,
      operation: () {
        var consumed = 0;
        for (final host in hosts) {
          final scripts = productionOrchestrator.buildUserScripts(host);
          consumed += scripts.length;
          for (final script in scripts) {
            consumed += script.source.length;
          }
        }
        return consumed;
      },
      ruleCounts: {'engine': engine.totalRules},
      metrics: {'hostsPerOperation': hosts.length, ..._scriptMetrics(productionScripts)},
    );
  }
}

Map<String, Object?> _scriptMetrics(List<UserScript> scripts) {
  var sourceBytes = 0;
  var documentStart = 0;
  var documentEnd = 0;
  final worlds = <String>{};
  for (final script in scripts) {
    sourceBytes += utf8.encode(script.source).length;
    if (script.injectionTime == UserScriptInjectionTime.AT_DOCUMENT_START) {
      documentStart++;
    } else {
      documentEnd++;
    }
    worlds.add(script.contentWorld.name);
  }
  return {
    'userScripts': scripts.length,
    'sourceUtf8Bytes': sourceBytes,
    'documentStart': documentStart,
    'documentEnd': documentEnd,
    'contentWorlds': worlds.toList()..sort(),
  };
}
