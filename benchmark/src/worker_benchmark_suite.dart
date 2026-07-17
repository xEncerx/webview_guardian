import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

import 'benchmark_contract.dart';
import 'benchmark_support.dart';

final class WorkerBenchmarkSuite extends BenchmarkSuite<CompiledFilterEngine> {
  const WorkerBenchmarkSuite(super.runner, this.fixtures);

  final BenchmarkFixtures fixtures;

  @override
  Future<CompiledFilterEngine> run() async {
    const samples = 3;
    final controlled = fixtures.controlled;
    late CompiledFilterEngine mixedEngine;

    Future<List<_BuildMeasurement>> sampleBuild(
      String name,
      Future<_BuildMeasurement> Function(Directory directory) prepareAndBuild,
    ) async {
      final measurements = <_BuildMeasurement>[];
      for (var sample = 0; sample < samples; sample++) {
        final directory = await Directory.systemTemp.createTemp('webview_guardian_bench_$name');
        try {
          measurements.add(await prepareAndBuild(directory));
        } finally {
          if (directory.existsSync()) await directory.delete(recursive: true);
        }
      }
      return measurements;
    }

    final mediumCold = await sampleBuild('medium_cold_', (directory) async {
      final source = await _writeSource(directory, 'medium.txt', fixtures.medium);
      return _build(directory, [source]);
    });
    _recordBuild(
      id: 'worker.medium-cold',
      fixture: 'abp-medium',
      scenario: 'cold build',
      results: mediumCold,
      expectedFromCache: false,
      inputBytes: fixtures.medium.length,
    );

    final restore = await sampleBuild('mixed_restore_', (directory) async {
      final sources = [
        await _writeSource(directory, 'medium.txt', fixtures.medium),
        await _writeSource(directory, 'hosts.txt', fixtures.hosts),
        await _writeSource(directory, 'controlled.txt', controlled),
      ];
      final primed = await _build(directory, sources);
      _expectDecision(primed.engine, 'https://bench-trie.invalid/ad.js', blocked: true);
      return _build(directory, sources);
    });
    _recordBuild(
      id: 'worker.mixed-cache-restore',
      fixture: 'abp-medium+hosts+controlled',
      scenario: 'unchanged mixed-subscription compiled cache restore',
      results: restore,
      expectedFromCache: true,
      inputBytes: fixtures.medium.length + fixtures.hosts.length + controlled.length,
      expectedDecisions: const {
        'https://bench-trie.invalid/ad.js': true,
        'https://bench-priority.invalid/ad.js': false,
      },
    );

    final identityMiss = await sampleBuild('identity_miss_', (directory) async {
      final source = await _writeSource(directory, 'medium.txt', fixtures.medium);
      await _build(directory, [source]);
      return _build(directory, [source.copyWith(updateInterval: const Duration(hours: 12))]);
    });
    _recordBuild(
      id: 'worker.medium-raw-cache-identity-miss',
      fixture: 'abp-medium',
      scenario: 'raw-list cache hit with compiled identity miss',
      results: identityMiss,
      expectedFromCache: false,
      inputBytes: fixtures.medium.length,
    );

    final mixed = await sampleBuild('mixed_cold_', (directory) async {
      final sources = <FilterSubscription>[
        await _writeSource(directory, 'large.txt', fixtures.large),
        await _writeSource(directory, 'hosts.txt', fixtures.hosts),
        await _writeSource(directory, 'controlled.txt', controlled),
      ];
      return _build(directory, sources);
    });
    mixedEngine = mixed.first.engine;
    _recordBuild(
      id: 'worker.mixed-cold',
      fixture: 'abp-large+hosts+controlled',
      scenario: 'cold mixed build',
      results: mixed,
      expectedFromCache: false,
      inputBytes: fixtures.large.length + fixtures.hosts.length + controlled.length,
    );

    final addSubscription = await sampleBuild('add_subscription_', (directory) async {
      final medium = await _writeSource(directory, 'medium.txt', fixtures.medium);
      final before = await _build(directory, [medium]);
      _expectDecision(before.engine, 'https://0.avmarket.rs/ad.js', blocked: false);
      final hosts = await _writeSource(directory, 'hosts.txt', fixtures.hosts);
      return _build(directory, [medium, hosts]);
    });
    _recordBuild(
      id: 'worker.add-subscription',
      fixture: 'abp-medium+hosts',
      scenario: 'one URL cached before adding another subscription',
      results: addSubscription,
      expectedFromCache: false,
      inputBytes: fixtures.medium.length + fixtures.hosts.length,
      expectedDecisions: const {'https://0.avmarket.rs/ad.js': true},
    );

    const changedLine = '\n||bench-source-changed.invalid^\n';
    final changed = await sampleBuild('source_changed_', (directory) async {
      final sources = [
        await _writeSource(directory, 'small.txt', fixtures.small),
        await _writeSource(directory, 'hosts.txt', fixtures.hosts),
        await _writeSource(directory, 'controlled.txt', controlled),
      ];
      final before = await _build(directory, sources);
      _expectDecision(before.engine, 'https://bench-source-changed.invalid/ad.js', blocked: false);
      final file = File(sources.last.url);
      final previousModified = file.lastModifiedSync();
      await file.writeAsString(changedLine, mode: FileMode.append);
      await file.setLastModified(previousModified.add(const Duration(seconds: 2)));
      return _build(directory, sources);
    });
    _recordBuild(
      id: 'worker.source-changed',
      fixture: 'abp-small+hosts+controlled',
      scenario: 'one of three copied sources changed after prime',
      results: changed,
      expectedFromCache: false,
      inputBytes:
          fixtures.small.length +
          fixtures.hosts.length +
          controlled.length +
          utf8.encode(changedLine).length,
      expectedDecisions: const {'https://bench-source-changed.invalid/ad.js': true},
      metrics: const {'changedContent': changedLine},
    );

    final unavailable = await sampleBuild('source_unavailable_', (directory) async {
      final sources = [
        await _writeSource(directory, 'small.txt', fixtures.small),
        await _writeSource(directory, 'controlled.txt', controlled),
      ];
      final before = await _build(directory, sources);
      _expectDecision(before.engine, 'https://bench-trie.invalid/ad.js', blocked: true);
      await File(sources.last.url).delete();
      return _build(directory, sources, allowFetchFailure: true);
    });
    _recordBuild(
      id: 'worker.source-unavailable',
      fixture: 'abp-small+controlled',
      scenario: 'cached source unavailable after prime',
      results: unavailable,
      expectedFromCache: true,
      inputBytes: fixtures.small.length + controlled.length,
      expectedDecisions: const {'https://bench-trie.invalid/ad.js': true},
    );

    final orphan = await sampleBuild('orphan_', (directory) async {
      final small = await _writeSource(directory, 'small.txt', fixtures.small);
      final overlay = await _writeSource(directory, 'controlled.txt', controlled);
      final before = await _build(directory, [small, overlay]);
      _expectDecision(before.engine, 'https://bench-trie.invalid/ad.js', blocked: true);
      return _build(directory, [small]);
    });
    _recordBuild(
      id: 'worker.subscription-removed',
      fixture: 'abp-small',
      scenario: 'subscription removed and orphan cache cleanup',
      results: orphan,
      expectedFromCache: false,
      inputBytes: fixtures.small.length,
      expectedDecisions: const {'https://bench-trie.invalid/ad.js': false},
    );

    final clearMicros = <double>[];
    for (var sample = 0; sample < samples; sample++) {
      final directory = await Directory.systemTemp.createTemp('webview_guardian_bench_clear_');
      try {
        final source = await _writeSource(directory, 'small.txt', fixtures.small);
        await _build(directory, [source]);
        final errors = <WebViewError>[];
        final manager = FilterIsolateManager(
          onEngineReady: (_, _, _, _) {},
          onWorkerEvent: (_) {},
          onWorkerError: errors.add,
        );
        final stopwatch = Stopwatch()..start();
        try {
          await manager.runClearCacheJob(storagePath: directory.path, useTestClient: true);
        } finally {
          stopwatch.stop();
          manager.dispose();
        }
        checkBenchmarkInvariant(errors.isEmpty, 'Cache clear worker errors: $errors');
        clearMicros.add(ticksToMicroseconds(stopwatch.elapsedTicks));

        await File(source.url).delete();
        final postClearBuild = await _build(directory, [source], allowFetchFailure: true);
        checkBenchmarkInvariant(
          !postClearBuild.fromCache,
          'Build after cache clear restored compiled cache.',
        );
        checkBenchmarkInvariant(
          postClearBuild.totalRules == 0,
          'Build after cache clear restored raw filter rules.',
        );
        checkBenchmarkInvariant(
          postClearBuild.fetchFailureCount > 0,
          'Unavailable source did not report a fetch failure after cache clear.',
        );
      } finally {
        if (directory.existsSync()) await directory.delete(recursive: true);
      }
    }
    runner.addSamples(
      id: 'worker.cache-clear',
      suite: 'worker',
      fixture: 'abp-small',
      scenario: 'clear independently primed cache',
      sampleMicros: clearMicros,
      metrics: {'inputBytes': fixtures.small.length, 'postClearColdBuilds': samples},
    );

    checkBenchmarkInvariant(mixedEngine.totalRules > 0, 'Mixed worker engine is empty.');
    return mixedEngine;
  }

  Future<FilterSubscription> _writeSource(Directory directory, String name, Uint8List bytes) async {
    final file = File('${directory.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return FilterSubscription(url: file.path);
  }

  Future<_BuildMeasurement> _build(
    Directory storage,
    List<FilterSubscription> subscriptions, {
    bool allowFetchFailure = false,
  }) async {
    _BuildMeasurement? measurement;
    final errors = <WebViewError>[];
    final manager = FilterIsolateManager(
      onEngineReady: (engine, fromCache, totalRules, workerDuration) {
        measurement = _BuildMeasurement(
          engine: engine,
          fromCache: fromCache,
          totalRules: totalRules,
          workerDuration: workerDuration,
        );
      },
      onWorkerEvent: (_) {},
      onWorkerError: errors.add,
    );
    final stopwatch = Stopwatch()..start();
    try {
      await manager.runBuildJob(
        subscriptions: subscriptions,
        httpOptions: const FilterHttpOptions(),
        storagePath: storage.path,
        useTestClient: true,
      );
    } finally {
      stopwatch.stop();
      manager.dispose();
    }
    final result = measurement;
    checkBenchmarkInvariant(result != null, 'Worker completed without an engine.');
    checkBenchmarkInvariant(
      !errors.any((error) => error is EngineBuildFailed || error is CacheRestoreFailed),
      'Worker build failed: $errors',
    );
    if (!allowFetchFailure) {
      checkBenchmarkInvariant(errors.isEmpty, 'Unexpected worker errors: $errors');
    }
    result!
      ..wallMicros = ticksToMicroseconds(stopwatch.elapsedTicks)
      ..errorCount = errors.length
      ..fetchFailureCount = errors.whereType<FilterFetchFailed>().length;
    return result;
  }

  void _recordBuild({
    required String id,
    required String fixture,
    required String scenario,
    required List<_BuildMeasurement> results,
    required bool expectedFromCache,
    required int inputBytes,
    Map<String, bool> expectedDecisions = const {},
    Map<String, Object?> metrics = const {},
  }) {
    checkBenchmarkInvariant(
      results.length >= 3,
      '$id requires at least three independent samples.',
    );
    for (final result in results) {
      checkBenchmarkInvariant(
        result.fromCache == expectedFromCache,
        '$id cache state was ${result.fromCache}.',
      );
      checkBenchmarkInvariant(
        result.totalRules == result.engine.totalRules,
        '$id rule count mismatch.',
      );
      checkBenchmarkInvariant(
        result.totalRules == results.first.totalRules,
        '$id rule counts changed across samples.',
      );
      for (final decision in expectedDecisions.entries) {
        _expectDecision(result.engine, decision.key, blocked: decision.value);
      }
    }
    runner.addSamples(
      id: id,
      suite: 'worker',
      fixture: fixture,
      scenario: scenario,
      sampleMicros: results.map((result) => result.wallMicros).toList(growable: false),
      ruleCounts: {'engine': results.first.totalRules},
      metrics: {
        'inputBytes': inputBytes,
        'workerMicros': results
            .map((result) => result.workerDuration.inMicroseconds)
            .toList(growable: false),
        'fromCache': expectedFromCache,
        'workerErrors': results.fold<int>(0, (total, result) => total + result.errorCount),
        'independentSetups': results.length,
        ...metrics,
      },
    );
  }
}

void _expectDecision(CompiledFilterEngine engine, String url, {required bool blocked}) {
  final uri = Uri.parse(url);
  final decision = FilterMatcher(FilterEngineRef(engine)).matchNetworkRequest(
    NetworkRequest(
      url: url,
      host: uri.host,
      sourceHost: 'publisher.invalid',
      resourceType: ResourceType.script,
    ),
  );
  checkBenchmarkInvariant(
    (decision is Block) == blocked,
    'Expected ${blocked ? 'Block' : 'Allow'} for $url, got ${decision.runtimeType}.',
  );
}

final class _BuildMeasurement {
  _BuildMeasurement({
    required this.engine,
    required this.fromCache,
    required this.totalRules,
    required this.workerDuration,
  });

  final CompiledFilterEngine engine;
  final bool fromCache;
  final int totalRules;
  final Duration workerDuration;
  double wallMicros = 0;
  int errorCount = 0;
  int fetchFailureCount = 0;
}
