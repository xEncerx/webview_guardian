/// -_-
// ignore_for_file: avoid_catches_without_on_clauses

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

const _wildcardDomains = ['*'];
const _engineCacheFormatVersion = 5;
const _filterParserVersion = 3;
typedef _FetchResult = ({bool filtersChanged, Map<String, CachedFilterListMetadata> metadataByUrl});
typedef _SubscriptionFetchResult = ({bool changed, CachedFilterListMetadata? metadata});

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
    final fetchResult = await _checkAndFetchFilters(
      subscriptions: subscriptions,
      httpOptions: httpOptions,
      storage: storage,
      observer: observer,
      useTestClient: useTestClient,
    );
    final cacheIdentity = await _buildEngineCacheIdentity(
      subscriptions: subscriptions,
      metadataByUrl: fetchResult.metadataByUrl,
    );
    final hasAllSubscriptionData = _hasAllSubscriptionData(
      subscriptions: subscriptions,
      metadataByUrl: fetchResult.metadataByUrl,
    );

    // If no changes detected and cached engine exists, load and return it immediately without rebuilding.
    if (!fetchResult.filtersChanged && hasAllSubscriptionData) {
      final cachedEngineBytes = await _loadCachedEngine(storage, cacheIdentity: cacheIdentity);
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
    if (hasAllSubscriptionData) {
      await storage.saveEngineBytes(newEngine.bytes, cacheIdentity: cacheIdentity);
    }

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
      final metadataByUrl = await _loadSubscriptionMetadata(
        subscriptions: subscriptions,
        storage: storage,
      );
      final cacheIdentity = await _buildEngineCacheIdentity(
        subscriptions: subscriptions,
        metadataByUrl: metadataByUrl,
      );
      final hasAllSubscriptionData = _hasAllSubscriptionData(
        subscriptions: subscriptions,
        metadataByUrl: metadataByUrl,
      );
      final fallbackEngineBytes = hasAllSubscriptionData
          ? await _loadCachedEngine(storage, cacheIdentity: cacheIdentity)
          : null;
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
        observer.onError(const CacheRestoreFailed('No fallback engine available to restore'));
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
Future<_FetchResult> _checkAndFetchFilters({
  required List<FilterSubscription> subscriptions,
  required FilterHttpOptions httpOptions,
  required FilterStorage storage,
  required IsolateWebViewObserver observer,
  required bool useTestClient,
}) async {
  final client = useTestClient ? TestFilterListClient() : HttpFilterListClient(httpOptions);

  try {
    Future<_SubscriptionFetchResult> fetchSubscription(FilterSubscription sub) async {
      observer.onEvent(FilterListFetchStarted(sub.url));

      try {
        final cachedMetadata = await _loadCachedMetadataForMatchingHead(
          client: client,
          storage: storage,
          subscription: sub,
        );
        if (cachedMetadata != null) {
          observer.onEvent(FilterCacheMatch(sub.url));
          return (changed: false, metadata: cachedMetadata);
        }
      } catch (_) {
        // Some hosts/CDNs do not support HEAD reliably; GET remains the authoritative fetch.
      }

      try {
        // Parse list and save to cache if changes occurred
        final response = await client.fetch(sub);
        await storage.saveFilterList(
          url: sub.url,
          etag: response.etag ?? DateTime.now().microsecondsSinceEpoch.toString(),
          bytes: response.bytes,
        );
        final updatedMetadata = await storage.loadFilterListMetadata(sub.url);
        return (changed: true, metadata: updatedMetadata);
      } catch (e, st) {
        observer.onError(FilterFetchFailed('Failed: ${sub.url}', cause: '$e\n$st'));
        final cachedMetadata = await storage.loadFilterListMetadata(sub.url);
        return (changed: false, metadata: cachedMetadata);
      }
    }

    final results = <_SubscriptionFetchResult>[];
    for (var start = 0; start < subscriptions.length; start += httpOptions.maxConcurrentDownloads) {
      results.addAll(
        await Future.wait(
          subscriptions.skip(start).take(httpOptions.maxConcurrentDownloads).map(fetchSubscription),
        ),
      );
    }
    final metadataByUrl = <String, CachedFilterListMetadata>{};
    for (var i = 0; i < subscriptions.length; i++) {
      final metadata = results[i].metadata;
      if (metadata != null) metadataByUrl[subscriptions[i].url] = metadata;
    }

    final orphansDeleted = await storage.cleanupOrphanedFilterLists(
      subscriptions.map((s) => s.url).toList(),
    );

    return (
      filtersChanged: orphansDeleted || results.any((result) => result.changed),
      metadataByUrl: metadataByUrl,
    );
  } finally {
    await client.dispose();
  }
}

Future<CachedFilterListMetadata?> _loadCachedMetadataForMatchingHead({
  required FilterListClient client,
  required FilterStorage storage,
  required FilterSubscription subscription,
}) async {
  final etag = (await client.head(subscription)).etag;
  final cachedMetadata = await storage.loadFilterListMetadata(subscription.url);

  if (etag != null && cachedMetadata != null && etag == cachedMetadata.etag) {
    return cachedMetadata;
  }

  return null;
}

Future<Map<String, CachedFilterListMetadata>> _loadSubscriptionMetadata({
  required List<FilterSubscription> subscriptions,
  required FilterStorage storage,
}) async {
  final metadataByUrl = <String, CachedFilterListMetadata>{};
  for (final subscription in subscriptions) {
    final metadata = await storage.loadFilterListMetadata(subscription.url);
    if (metadata != null) metadataByUrl[subscription.url] = metadata;
  }
  return metadataByUrl;
}

bool _hasAllSubscriptionData({
  required List<FilterSubscription> subscriptions,
  required Map<String, CachedFilterListMetadata> metadataByUrl,
}) {
  for (final subscription in subscriptions) {
    if (!metadataByUrl.containsKey(subscription.url)) return false;
  }
  return true;
}

/// Loads and validates the cached compiled filter engine bytes from disk.
Future<Uint8List?> _loadCachedEngine(FilterStorage storage, {required String cacheIdentity}) async {
  final cached = await storage.loadEngineBytes(cacheIdentity: cacheIdentity);
  if (cached == null) return null;
  return cached;
}

Future<String> _buildEngineCacheIdentity({
  required List<FilterSubscription> subscriptions,
  required Map<String, CachedFilterListMetadata> metadataByUrl,
}) async =>
    buildEngineCacheIdentityForTesting(subscriptions: subscriptions, metadataByUrl: metadataByUrl);

/// Builds the compiled-engine cache identity from subscription metadata only.
@visibleForTesting
String buildEngineCacheIdentityForTesting({
  required List<FilterSubscription> subscriptions,
  required Map<String, CachedFilterListMetadata> metadataByUrl,
}) {
  final entries = <Map<String, Object?>>[];

  for (final subscription in subscriptions) {
    final metadata = metadataByUrl[subscription.url];
    entries.add({
      'url': subscription.url,
      'updateIntervalMicroseconds': subscription.updateInterval?.inMicroseconds,
      'filterSha256': metadata?.payloadSha256,
      'filterLength': metadata?.payloadLength,
    });
  }

  entries.sort((a, b) {
    final urlComparison = (a['url']! as String).compareTo(b['url']! as String);
    if (urlComparison != 0) return urlComparison;
    final aInterval = a['updateIntervalMicroseconds'] as int?;
    final bInterval = b['updateIntervalMicroseconds'] as int?;
    return (aInterval ?? -1).compareTo(bInterval ?? -1);
  });

  final payload = jsonEncode({
    'engineCacheFormatVersion': _engineCacheFormatVersion,
    'filterParserVersion': _filterParserVersion,
    'subscriptions': entries,
  });

  return sha256.convert(utf8.encode(payload)).toString();
}

typedef _CompilerResult = ({Uint8List bytes, int totalRules});

/// Parses local filter lists and builds the full compiled engine byte array.
Future<_CompilerResult> _parseAndBuildEngine({
  required List<FilterSubscription> subscriptions,
  required FilterStorage storage,
}) async {
  final deduped = <FilterRule>{};

  for (final sub in subscriptions) {
    final rawBytes = (await storage.loadFilterList(sub.url))?.data;
    if (rawBytes == null) continue;

    final parser = FilterListParserFactory.resolve(rawBytes);
    deduped.addAll(FilterDeduplicator.deduplicate(parser.parse(rawBytes)));
  }

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
        final domains = rule.domains ?? _wildcardDomains;
        for (final domain in domains) {
          cssInjectRules.putIfAbsent(domain, () => []).add(rule);
        }
    }
  }

  // 3. Compile the hostname trie and retain non-complete candidates for token dispatch.
  final trieCompiler = HostnameTrieCompiler();
  final dispatchRules = <FilterRule>[];
  for (final rule in networkRules) {
    final isTrieCandidate = trieCompiler.tryAddRule(rule);
    if (!isTrieCandidate || !HostnameTrieCompiler.isTrieComplete(rule)) {
      dispatchRules.add(rule);
    }
  }
  final trieResult = trieCompiler.build();

  // 4. Compile Token Dispatch Table for rules not fully covered by the trie.
  final dispatchResult = TokenDispatchCompiler.compile(dispatchRules);

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
