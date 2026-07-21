---
name: working-with-webview-guardian-benchmarks
description: Use when running, comparing, interpreting, reviewing, or diagnosing performance benchmarks in webview_guardian, including benchmark result JSON, baselines, p50, p95, ops/s, delta, cache, lookup, build, serialization, or injection regressions.
---

# Working with WebView Guardian Benchmarks

## Core Rule

A performance claim requires the same environment, unchanged workload metrics, and a repeatable change. `Improved` and `Regressed` are invalid when counts or bytes changed. A green benchmark proves behavioral invariants only; it has no timing thresholds.

Read `benchmark/README.md` before working. Run from the package root with Flutter, serially, without coverage or live network access.

## Choose the Workflow

| Request | Required action |
|---|---|
| Run benchmarks | Run once and report results without a performance verdict |
| Compare with baseline | Validate comparability, then run with `BENCHMARK_BASELINE` |
| Decide whether performance changed | Run at least three comparisons; require a consistent direction |
| Find a bottleneck | Correlate changed IDs, workload metrics, and worker timing before inspecting code |

## Preflight

1. Read the current package version from `pubspec.yaml`.
2. Store local JSON only in `benchmark/results/` using `webview_guardian-<version>-<label>.json`.
3. Never overwrite a baseline unless the user explicitly requests it.
4. Compare only runs from the same physical machine, OS, Flutter/Dart version, power mode, and otherwise-idle conditions. Windows and WSL/Linux results are not comparable.
5. Verify `schemaVersion`, fixture hashes, rule counts, and workload metrics. If fixture validation fails, create a legitimate new baseline; never bypass it.

## Commands

Replace `<version>` with the version from `pubspec.yaml`.

```bash
flutter test --no-pub -j 1 --timeout none -r expanded benchmark

BENCHMARK_OUTPUT=benchmark/results/webview_guardian-<version>-baseline.json \
flutter test --no-pub -j 1 --timeout none -r expanded benchmark

BENCHMARK_BASELINE=benchmark/results/webview_guardian-<baseline-version>-baseline.json \
BENCHMARK_OUTPUT=benchmark/results/webview_guardian-<version>-current-1.json \
flutter test --no-pub -j 1 --timeout none -r expanded benchmark
```

Use `current-1`, `current-2`, and `current-3` for repeated comparisons. Result files are local and ignored by Git. After an optimization, also run the normal suite with `flutter test`.

## Reading Results

| Field | Interpretation |
|---|---|
| `p50 us/op` | Median operation time; lower is better |
| `p95 us/op` | Noise/tail indicator, not a production SLA |
| `ops/s` | Inverse of p50; higher is better |
| `delta` | Positive is slower; negative is faster |
| `ruleCounts` | Actual rules processed |
| `metrics` | Bytes, buckets, scripts, hosts, requests, and other workload dimensions |

Worker rows have three independent samples and no p95. Other p95 values come from only five or seven samples. Never compare raw ops/s when one operation represents different work: mixed lookup handles six requests, while representative-host injection handles four hosts.

If counts or bytes changed, the workload changed. Raw timing is `Not comparable`, even when its direction repeats. Report the workload change separately; only a justified normalized metric can support a performance claim.

## Bottleneck Map

| Changed IDs | Suspect |
|---|---|
| `parse.*` | Format detection, parser, allocations |
| `compile.deduplicate-*` | Equality, hashing, sets |
| `compile.token-dispatch-*` | Token extraction/table construction |
| `compile.hostname-trie-*` | Trie construction |
| Cold and raw-cache-miss worker rows | Parsing, compilation, engine assembly, serialization |
| Cold only | Source read or raw-cache write |
| Cache restore plus deserialize | Engine deserialization |
| Cache restore with stable deserialize | Cache validation, hashing, isolate lifecycle |
| Stable `workerMicros` but slower wall p50 | Isolate spawn, transfer, main-isolate handling |
| One lookup path | Its trie, token, fallback, request, or observer path |
| Injection repository selection | Domain chain, exceptions, deduplication |
| Stable selection but slower orchestrator | CSS/JS/scriptlet source generation |
| Full mode only | Generic cosmetics or MutationObserver scaling |

Start with the narrowest regressed row. Use broader worker rows to confirm impact. Profile only when stage benchmarks cannot isolate the cost; do not guess from an aggregate worker result.

## Verdict Contract

Use exactly one verdict: `Improved`, `Regressed`, `Inconclusive`, or `Not comparable`.

A final `Improved` or `Regressed` verdict requires three comparable runs with a consistent direction and unchanged `ruleCounts` and workload `metrics`. Use `Inconclusive` for noisy same-work runs. Use `Not comparable` whenever environment or workload differs materially; repeatability does not override this rule.

Report:

1. Baseline/current environment and package versions.
2. Evidence table with ID, baseline p50, current p50, deltas across runs, and workload changes.
3. Most likely bottleneck and evidence excluding alternatives.
4. Commands and normal-test status.
5. Limits: debug/JIT host-side measurements only.

Never claim native WebView startup, platform-channel, JavaScript execution, DOM mutation, rendering, network-download, or release/AOT performance from this suite. Phrase injection findings as host-side `UserScript` generation.

## Red Flags

- Using `dart test`, coverage, or parallel benchmark workers
- Treating a green exit code as a performance pass
- Comparing Windows with WSL/Linux or different machines
- Drawing a conclusion from one run
- Ignoring changed rule counts, serialized bytes, or generated source bytes
- Comparing ops/s for differently sized operations
- Replacing a baseline or fixtures to make deltas disappear
- Optimizing before narrowing the responsible stage
