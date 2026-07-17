// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

final class BenchmarkResult {
  BenchmarkResult({
    required this.id,
    required this.suite,
    required this.fixture,
    required this.scenario,
    required this.samples,
    required this.iterations,
    required this.medianMicrosPerOp,
    required this.p95MicrosPerOp,
    required this.opsPerSecond,
    required this.sampleMicrosPerOp,
    this.ruleCounts = const {},
    this.metrics = const {},
  });

  final String id;
  final String suite;
  final String fixture;
  final String scenario;
  final int samples;
  final int iterations;
  final double medianMicrosPerOp;
  final double? p95MicrosPerOp;
  final double opsPerSecond;
  final List<double> sampleMicrosPerOp;
  final Map<String, int> ruleCounts;
  final Map<String, Object?> metrics;
  double? medianDeltaPercent;

  Map<String, Object?> toJson() => {
    'id': id,
    'suite': suite,
    'fixture': fixture,
    'scenario': scenario,
    'samples': samples,
    'iterations': iterations,
    'medianMicrosPerOp': medianMicrosPerOp,
    'p95MicrosPerOp': p95MicrosPerOp,
    'opsPerSecond': opsPerSecond,
    'sampleMicrosPerOp': sampleMicrosPerOp,
    'ruleCounts': ruleCounts,
    'metrics': metrics,
    'medianDeltaPercent': medianDeltaPercent,
  };
}

final class BenchmarkRunner {
  BenchmarkRunner() {
    ticksToMicroseconds(0);
  }

  final results = <BenchmarkResult>[];
  final _baselineResults = <String, Map<String, dynamic>>{};
  int _sink = 0;
  bool _baselineLoaded = false;
  bool _hasBaseline = false;

  BenchmarkResult measureSync({
    required String id,
    required String suite,
    required String fixture,
    required String scenario,
    required int Function() operation,
    int samples = 7,
    int iterations = 1,
    int warmupIterations = 1,
    Map<String, int> ruleCounts = const {},
    Map<String, Object?> metrics = const {},
  }) {
    for (var i = 0; i < warmupIterations; i++) {
      _sink ^= operation();
    }

    final sampleMicros = <double>[];
    for (var sample = 0; sample < samples; sample++) {
      final stopwatch = Stopwatch()..start();
      for (var iteration = 0; iteration < iterations; iteration++) {
        _sink ^= operation();
      }
      stopwatch.stop();
      sampleMicros.add(
        ticksToMicroseconds(stopwatch.elapsedTicks) / iterations,
      );
    }

    return addSamples(
      id: id,
      suite: suite,
      fixture: fixture,
      scenario: scenario,
      sampleMicros: sampleMicros,
      iterations: iterations,
      ruleCounts: ruleCounts,
      metrics: metrics,
    );
  }

  BenchmarkResult addSamples({
    required String id,
    required String suite,
    required String fixture,
    required String scenario,
    required List<double> sampleMicros,
    int iterations = 1,
    Map<String, int> ruleCounts = const {},
    Map<String, Object?> metrics = const {},
  }) {
    if (sampleMicros.isEmpty) throw ArgumentError.value(sampleMicros, 'sampleMicros');
    final sorted = [...sampleMicros]..sort();
    final median = _percentile(sorted, 0.5);
    final p95 = sorted.length < 5 ? null : _percentile(sorted, 0.95);
    final result = BenchmarkResult(
      id: id,
      suite: suite,
      fixture: fixture,
      scenario: scenario,
      samples: sampleMicros.length,
      iterations: iterations,
      medianMicrosPerOp: median,
      p95MicrosPerOp: p95,
      opsPerSecond: median == 0 ? 0 : Duration.microsecondsPerSecond / median,
      sampleMicrosPerOp: List.unmodifiable(sampleMicros),
      ruleCounts: ruleCounts,
      metrics: metrics,
    );
    results.add(result);
    return result;
  }

  void loadBaseline({required Map<String, String> fixtureHashes, String? baselinePath}) {
    if (_baselineLoaded) return;
    _baselineLoaded = true;
    final path = baselinePath ?? Platform.environment['BENCHMARK_BASELINE'];
    if (path == null || path.isEmpty) return;
    _hasBaseline = true;
    final document = jsonDecode(File(path).readAsStringSync());
    if (document is! Map<String, dynamic>) {
      throw const FormatException('Benchmark baseline must be a JSON object.');
    }
    if (document['schemaVersion'] != 1) {
      throw FormatException(
        'Incompatible benchmark baseline schemaVersion: '
        '${document['schemaVersion']} (expected 1).',
      );
    }
    final environment = document['environment'];
    if (environment is! Map<String, dynamic>) {
      throw const FormatException('Benchmark baseline must contain environment metadata.');
    }
    final currentEnvironment = _environmentIdentity();
    for (final entry in currentEnvironment.entries) {
      if (environment[entry.key] != entry.value) {
        throw StateError(
          'Benchmark baseline environment ${entry.key} does not match: '
          '${environment[entry.key]} != ${entry.value}.',
        );
      }
    }
    final rawHashes = environment['fixtureHashes'];
    if (rawHashes is! Map<String, dynamic>) {
      throw const FormatException('Benchmark baseline must contain fixture hashes.');
    }
    final baselineHashes = <String, String>{};
    for (final entry in rawHashes.entries) {
      if (entry.value is! String) {
        throw const FormatException('Benchmark baseline fixture hashes must be strings.');
      }
      baselineHashes[entry.key] = entry.value as String;
    }
    if (baselineHashes.length != fixtureHashes.length ||
        fixtureHashes.entries.any((entry) => baselineHashes[entry.key] != entry.value)) {
      throw StateError('Benchmark baseline fixture hashes do not match current fixtures.');
    }
    final baselineResults = document['results'];
    if (baselineResults is! List<dynamic>) {
      throw const FormatException('Benchmark baseline must contain a results array.');
    }
    for (final value in baselineResults) {
      if (value is! Map<String, dynamic> || value['id'] is! String) {
        throw const FormatException('Benchmark baseline results must have string IDs.');
      }
      final median = value['medianMicrosPerOp'];
      if (median is! num || !median.isFinite || median <= 0) {
        throw const FormatException('Benchmark baseline medians must be positive finite numbers.');
      }
      final id = value['id'] as String;
      if (_baselineResults.containsKey(id)) {
        throw FormatException('Benchmark baseline contains duplicate result ID: $id.');
      }
      _baselineResults[id] = value;
    }
  }

  Future<void> report({required Map<String, String> fixtureHashes}) async {
    loadBaseline(fixtureHashes: fixtureHashes);
    applyBaselineDeltas();

    print('| ID | samples | p50 us/op | p95 batch-average us/op | ops/s | delta |');
    print('|---|---:|---:|---:|---:|---:|');
    for (final result in results) {
      final delta = result.medianDeltaPercent;
      final p95 = result.p95MicrosPerOp;
      print(
        '| ${result.id} | ${result.samples} | ${result.medianMicrosPerOp.toStringAsFixed(2)} '
        '| ${p95?.toStringAsFixed(2) ?? '-'} '
        '| ${result.opsPerSecond.toStringAsFixed(1)} '
        '| ${delta == null ? '-' : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%'} |',
      );
    }

    final outputPath = Platform.environment['BENCHMARK_OUTPUT'];
    if (outputPath == null || outputPath.isEmpty) return;
    final document = <String, Object?>{
      'schemaVersion': 1,
      'environment': {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        ..._environmentIdentity(),
        'fixtureHashes': fixtureHashes,
        'benchmarkSink': _sink,
      },
      'results': results.map((result) => result.toJson()).toList(growable: false),
    };
    await File(
      outputPath,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(document)}\n');
  }

  void applyBaselineDeltas() {
    if (!_hasBaseline) return;
    final currentById = <String, BenchmarkResult>{};
    for (final result in results) {
      if (currentById.containsKey(result.id)) {
        throw StateError('Current benchmark contains duplicate result ID: ${result.id}.');
      }
      currentById[result.id] = result;
    }
    final missing = _baselineResults.keys.where((id) => !currentById.containsKey(id)).toList();
    final extra = currentById.keys.where((id) => !_baselineResults.containsKey(id)).toList();
    if (missing.isNotEmpty || extra.isNotEmpty) {
      throw StateError('Benchmark result rows differ; missing: $missing, extra: $extra.');
    }

    for (final result in results) {
      final baseline = _baselineResults[result.id]!;
      _checkRowField(result.id, 'suite', baseline['suite'], result.suite);
      _checkRowField(result.id, 'fixture', baseline['fixture'], result.fixture);
      _checkRowField(result.id, 'scenario', baseline['scenario'], result.scenario);
      _checkRowField(result.id, 'samples', baseline['samples'], result.samples);
      _checkRowField(result.id, 'iterations', baseline['iterations'], result.iterations);
      _checkRowField(result.id, 'ruleCounts', baseline['ruleCounts'], result.ruleCounts);
      _checkRowField(
        result.id,
        'metrics',
        _stableMetrics(baseline['metrics']),
        _stableMetrics(result.metrics),
      );
    }
    for (final result in results) {
      final baseline = (_baselineResults[result.id]!['medianMicrosPerOp']! as num).toDouble();
      result.medianDeltaPercent = (result.medianMicrosPerOp - baseline) * 100 / baseline;
    }
  }
}

Map<String, Object> _environmentIdentity() => {
  'dartVersion': Platform.version,
  'os': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'processorCount': Platform.numberOfProcessors,
};

Object? _stableMetrics(Object? metrics) {
  if (metrics is! Map) return metrics;
  return Map.fromEntries(
    metrics.entries
        .where((entry) => entry.key != 'workerMicros')
        .map(
          (entry) => MapEntry(entry.key, _stableMetrics(entry.value)),
        ),
  );
}

void _checkRowField(String id, String field, Object? baseline, Object? current) {
  if (!_deepEquals(baseline, current)) {
    throw StateError('Benchmark baseline row $id has incompatible $field: $baseline != $current.');
  }
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.entries.every(
          (entry) => right.containsKey(entry.key) && _deepEquals(entry.value, right[entry.key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        Iterable<int>.generate(
          left.length,
        ).every((index) => _deepEquals(left[index], right[index]));
  }
  return left == right;
}

double _percentile(List<double> sorted, double percentile) {
  final index = (sorted.length - 1) * percentile;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sorted[lower];
  return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
}

final double _stopwatchTicksPerMicrosecond = _calibrateStopwatchTicks();

double ticksToMicroseconds(int ticks) => ticks / _stopwatchTicksPerMicrosecond;

double _calibrateStopwatchTicks() {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsedMicroseconds < 10000) {}
  stopwatch.stop();
  return stopwatch.elapsedTicks / stopwatch.elapsedMicroseconds;
}
