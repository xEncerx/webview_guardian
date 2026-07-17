# Benchmarks

Run the full suite serially from the package root:

```sh
flutter test --no-pub -j 1 --timeout none -r expanded benchmark
```

Write local machine-readable results under `benchmark/results/`. Include the current package version
from `pubspec.yaml` in every filename, then compare a later run with the baseline:

```sh
BENCHMARK_OUTPUT=benchmark/results/webview_guardian-<version>-baseline.json flutter test --no-pub -j 1 --timeout none -r expanded benchmark
```

```sh
BENCHMARK_BASELINE=benchmark/results/webview_guardian-<version>-baseline.json BENCHMARK_OUTPUT=benchmark/results/webview_guardian-<version>-current-1.json flutter test --no-pub -j 1 --timeout none -r expanded benchmark
```

The results directory is intentionally ignored by Git. Do not overwrite a baseline unless replacing
it is the explicit goal.

The suite measures host-side parsing, compilation, worker engine builds and cache paths,
serialization, network matching, repository selection, and user-script generation. It does not
measure native WebView startup, JavaScript execution, DOM mutation, rendering, or network download
speed. Results have no timing thresholds; only correctness invariants fail the test.

Synchronous microbenchmarks normally collect seven warmed samples; the most expensive operations
collect five. Worker and cache scenarios collect three samples, each from an independently created,
prepared, and deleted temporary directory. The table always shows sample count. P95 uses linear
interpolation over per-operation batch averages, not individual operation latency, and is reported
only for five or more samples. Worker rows remain at three independent samples and show `-` in the
table and `null` in JSON rather than presenting their maximum as a reliable p95. JSON stores those
raw batch-average samples in the additive `sampleMicrosPerOp` field.

Fixtures are fixed snapshots from [NoADS_RU](https://github.com/Zalexanninev15/NoADS_RU) at commit
`55cf7c89f7564ad23cba86bec33516cd4ac87cb2`, used under the vendored MIT `LICENSE`. Exact URLs,
Git blob IDs, byte sizes, and SHA-256 hashes are recorded in `fixtures/noads_ru/SOURCE.json`.
Benchmark runtime performs no live network access.

JSON uses `schemaVersion: 1`; nullable statistics and `medianDeltaPercent` are always present.
Generated controlled-filter and domain-list content is hashed alongside vendored fixtures. Before
emitting deltas, comparison requires the same available environment identity, fixture hashes,
complete result-row set, suite/fixture/scenario/sample/iteration metadata, rule counts, and stable
workload metrics. Timing diagnostics such as `workerMicros` do not define workload identity.

These are debug/JIT measurements. Use repeated serial runs on the same otherwise-idle machine for
comparisons; numbers are not portable across machines or Flutter/Dart versions. Do not run under
coverage, which materially changes timings.
