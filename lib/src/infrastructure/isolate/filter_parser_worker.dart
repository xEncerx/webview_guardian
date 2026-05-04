/// -_-
// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

const _wildcardDomains = ['*'];

/// Arguments passed to the filter parser worker isolate on startup.
typedef WorkerInitArgs = ({SendPort sendPort, String? storagePath, bool useTestClient});

/// Main entry point for the filter parser worker isolate.
@pragma('vm:entry-point')
void filterParserWorkerEntry(Object message) {
  final args = message as WorkerInitArgs;
  final initPort = args.sendPort;

  final receivePort = ReceivePort();
  final observer = IsolateWebViewObserver(initPort);
  final storage = FilterStorage(overridePath: args.storagePath);
  var isPipelineRunning = false;

  initPort.send(WorkerReady(receivePort.sendPort));

  receivePort.listen((message) {
    switch (message) {
      case InitCommand(:final subscriptions, :final httpOptions):
        if (isPipelineRunning) return;
        isPipelineRunning = true;
        unawaited(
          _runPipeline(
            subscriptions: subscriptions,
            httpOptions: httpOptions,
            storage: storage,
            replyPort: initPort,
            observer: observer,
            useTestClient: args.useTestClient,
          ).whenComplete(() => isPipelineRunning = false),
        );
      case ClearCacheCommand():
        unawaited(_clearWorkerCache(storage, observer));
      case ShutdownCommand():
        initPort.send(ShutdownAck());
        receivePort.close();
      default:
        break;
    }
  });
}

/// Clears the worker isolate's cache by deleting all stored filter lists and compiled engine bytes.
Future<void> _clearWorkerCache(FilterStorage storage, IsolateWebViewObserver observer) async {
  // TODO: emit success/error events back to main isolate with clear cache size info
  await storage.clearFilterListsCache();
  observer.onEvent(const FilterCacheCleared());
}

/// Executes the main pipeline for handling filter subscriptions.
///
/// Fetches rules, deduplicates them, builds domains, and compiles the filter engine.
Future<void> _runPipeline({
  required List<FilterSubscription> subscriptions,
  required FilterHttpOptions httpOptions,
  required FilterStorage storage,
  required SendPort replyPort,
  required IsolateWebViewObserver observer,
  required bool useTestClient,
}) async {
  final stopwatch = Stopwatch()..start();

  try {
    // Check ETags and fetch updated filter lists if needed.
    final filtersChanged = await _checkAndFetchFilters(
      subscriptions: subscriptions,
      httpOptions: httpOptions,
      storage: storage,
      observer: observer,
      useTestClient: useTestClient,
    );

    // If no changes detected and cached engine exists, load and return it immediately without rebuilding.
    if (!filtersChanged) {
      final cachedEngineBytes = await _loadCachedEngine(storage);
      if (cachedEngineBytes != null) {
        stopwatch.stop();
        final totalRules = BinaryReader(cachedEngineBytes).readInt32();
        replyPort.send(
          EngineCacheRestored(
            engineBytes: TransferableTypedData.fromList([cachedEngineBytes]),
            compilationTime: stopwatch.elapsed,
            totalRules: totalRules,
          ),
        );
        return;
      }
    }

    // If there no cached engine or filters have changed, run _parseAndBuildEngine pipeline to build new engine.
    final newEngine = await _parseAndBuildEngine(subscriptions: subscriptions, storage: storage);
    await storage.saveEngineBytes(newEngine.bytes);

    stopwatch.stop();
    replyPort.send(
      EngineCompiledResponse(
        engineBytes: TransferableTypedData.fromList([newEngine.bytes]),
        totalRules: newEngine.totalRules,
        compilationTime: stopwatch.elapsed,
      ),
    );
  } catch (e, st) {
    observer.onError(EngineBuildFailed('Engine rebuild failed', cause: '$e\n$st'));

    // If engine build fails, attempt to load cached engine as fallback to avoid leaving main isolate without any engine.
    try {
      final fallbackEngineBytes = await _loadCachedEngine(storage);
      if (fallbackEngineBytes != null) {
        stopwatch.stop();
        final totalRules = BinaryReader(fallbackEngineBytes).readInt32();
        replyPort.send(
          EngineCacheRestored(
            engineBytes: TransferableTypedData.fromList([fallbackEngineBytes]),
            compilationTime: stopwatch.elapsed,
            totalRules: totalRules,
          ),
        );
      } else {
        observer.onError(
          const CacheRestoreFailed('No fallback engine available to restore'),
        );
      }
    } catch (fallbackError, fallbackSt) {
      // If loading cached engine also fails, there's not much we can do. Report this critical failure back to main isolate.
      observer.onError(
        CacheRestoreFailed('Failed to load fallback engine', cause: '$fallbackError\n$fallbackSt'),
      );
    }
  }
}

/// Checks ETags and fetches updated filter lists if they have changed.
///
/// Returns a boolean indicating whether any filters were updated or missing.
Future<bool> _checkAndFetchFilters({
  required List<FilterSubscription> subscriptions,
  required FilterHttpOptions httpOptions,
  required FilterStorage storage,
  required IsolateWebViewObserver observer,
  required bool useTestClient,
}) async {
  final client = useTestClient ? TestFilterListClient() : HttpFilterListClient(httpOptions);

  final futures = subscriptions.map((sub) async {
    observer.onEvent(FilterListFetchStarted(sub.url));

    try {
      final etag = (await client.head(sub)).etag;
      final cachedEtag = (await storage.loadFilterList(sub.url))?.etag;

      // Skip fetching this list if cached ETag matches current ETag
      if (etag != null && cachedEtag != null && etag == cachedEtag) {
        observer.onEvent(FilterCacheMatch(sub.url));
        return false;
      }

      // Parse list and save to cache if changes occurred
      final response = await client.fetch(sub);
      await storage.saveFilterList(
        url: sub.url,
        etag: response.etag ?? DateTime.now().microsecondsSinceEpoch.toString(),
        bytes: response.bytes,
      );
      return true;
    } catch (e, st) {
      observer.onError(FilterFetchFailed('Failed: ${sub.url}', cause: '$e\n$st'));
      return false;
    }
  });

  final results = await Future.wait(futures);

  final orphansDeleted = await storage.cleanupOrphanedFilterLists(
    subscriptions.map((s) => s.url).toList(),
  );

  return orphansDeleted || results.any((changed) => changed);
}

/// Loads and validates the cached compiled filter engine bytes from disk.
Future<Uint8List?> _loadCachedEngine(FilterStorage storage) async {
  final cached = await storage.loadEngineBytes();
  if (cached == null) return null;
  return cached;
}

typedef _CompilerResult = ({Uint8List bytes, int totalRules});

/// Parses local filter lists and builds the full compiled engine byte array.
Future<_CompilerResult> _parseAndBuildEngine({
  required List<FilterSubscription> subscriptions,
  required FilterStorage storage,
}) async {
  final allParsed = <Iterable<FilterRule>>[];

  for (final sub in subscriptions) {
    final rawBytes = (await storage.loadFilterList(sub.url))?.data;
    if (rawBytes == null) continue;

    final parser = FilterListParserFactory.resolve(rawBytes);
    allParsed.add(parser.parse(rawBytes));
  }

  // 1. Merge and deduplicate to get flat rule list
  final deduped = FilterDeduplicator.mergeAndDeduplicate(allParsed);

  // 2. Separate rules by type
  final networkRules = <FilterRule>[];
  final cosmeticHideRules = <String, List<CosmeticHideRule>>{};
  final cosmeticExceptionRules = <String, List<CosmeticExceptionRule>>{};
  final scriptletRules = <String, List<ScriptletRule>>{};
  final cssInjectRules = <String, List<CssInjectRule>>{};

  for (final rule in deduped) {
    switch (rule) {
      case NetworkBlockRule():
      case NetworkExceptionRule():
        networkRules.add(rule);
      case CosmeticHideRule():
        final domains = rule.domains ?? _wildcardDomains;
        for (final domain in domains) {
          cosmeticHideRules.putIfAbsent(domain, () => []).add(rule);
        }
      case CosmeticExceptionRule():
        final domains = rule.domains ?? _wildcardDomains;
        for (final domain in domains) {
          cosmeticExceptionRules.putIfAbsent(domain, () => []).add(rule);
        }
      case ScriptletRule():
        final domains = rule.domains ?? _wildcardDomains;
        for (final domain in domains) {
          scriptletRules.putIfAbsent(domain, () => []).add(rule);
        }
      case CssInjectRule():
        final domain = rule.domain ?? _wildcardDomains[0];
        cssInjectRules.putIfAbsent(domain, () => []).add(rule);
    }
  }

  // 3. Compile Token Dispatch Table for network rules
  final dispatchResult = TokenDispatchCompiler.compile(networkRules);

  // 4. Compile Hostname Trie for ||domain^ rules
  final trieCompiler = HostnameTrieCompiler();
  networkRules.forEach(trieCompiler.tryAddRule);
  final trieResult = trieCompiler.build();

  // 5. Build final compiled engine instance
  final compiledEngine = CompiledFilterEngine(
    totalRules: deduped.length,
    trieBuffer: trieResult.buffer,
    trieRules: trieResult.rules,
    tokenDispatchTable: dispatchResult.table,
    fallbackRules: dispatchResult.fallbackRules,
    cosmeticHideRules: cosmeticHideRules,
    cosmeticExceptionRules: cosmeticExceptionRules,
    scriptletRules: scriptletRules,
    cssInjectRules: cssInjectRules,
  );

  // 6. Serialize to bytes
  final engineBytes = EngineSerializer().serialize(compiledEngine);

  return (bytes: engineBytes, totalRules: deduped.length);
}
