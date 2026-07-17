import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

import 'benchmark_contract.dart';

final class LookupBenchmarkSuite extends BenchmarkSuite<void> {
  const LookupBenchmarkSuite(super.runner, this.engine);

  final CompiledFilterEngine engine;

  @override
  void run() {
    final matcher = FilterMatcher(FilterEngineRef(engine));
    final emptyMatcher = FilterMatcher(FilterEngineRef(CompiledFilterEngine.empty()));
    final disabledObserver = _RecordingObserver();
    final enabledObserver = _RecordingObserver();
    final defaultNoObserverRepository = FilterRepositoryImpl(
      matcher: matcher,
      engineRef: FilterEngineRef(engine),
      observer: null,
    );
    final disabledObserverRepository = FilterRepositoryImpl(
      matcher: matcher,
      engineRef: FilterEngineRef(engine),
      observer: disabledObserver,
      observabilityOptions: const WebViewObservabilityOptions(emitBlockedRequests: false),
    );
    final enabledObserverRepository = FilterRepositoryImpl(
      matcher: matcher,
      engineRef: FilterEngineRef(engine),
      observer: enabledObserver,
    );
    final cases = <String, NetworkRequest>{
      'fallback-miss': _request('https://guardian-clean.invalid/assets/app.js'),
      'hosts-hit': _request('https://0.avmarket.rs/ad.js'),
      'hosts-subdomain-hit': _request('https://sub.0.avmarket.rs/ad.js'),
      'token-hit': _request('https://guardian-clean.invalid/bench-token-unique.js'),
      'important-exception': _request('https://bench-priority.invalid/ad.js'),
      'fallback-hit': _request('https://guardian-clean.invalid/path/b~m/file.js'),
    };
    final expected = <String, Type>{
      'fallback-miss': Allow,
      'hosts-hit': Block,
      'hosts-subdomain-hit': Block,
      'token-hit': Block,
      'important-exception': Allow,
      'fallback-hit': Block,
    };
    for (final entry in cases.entries) {
      checkBenchmarkInvariant(
        matcher.matchNetworkRequest(entry.value).runtimeType == expected[entry.key],
        'Unexpected lookup result for ${entry.key}.',
      );
    }

    final emptyRequest = cases['fallback-miss']!;
    checkBenchmarkInvariant(
      emptyMatcher.matchNetworkRequest(emptyRequest) is Allow,
      'Empty engine did not allow.',
    );
    runner.measureSync(
      id: 'lookup.empty-allow',
      suite: 'lookup',
      fixture: 'empty-engine',
      scenario: 'direct matcher empty allow',
      iterations: 2000,
      warmupIterations: 200,
      operation: () => emptyMatcher.matchNetworkRequest(emptyRequest) is Allow ? 1 : 0,
    );

    for (final name in [
      'fallback-miss',
      'hosts-hit',
      'hosts-subdomain-hit',
      'token-hit',
      'important-exception',
      'fallback-hit',
    ]) {
      final request = cases[name]!;
      runner.measureSync(
        id: 'lookup.direct-$name',
        suite: 'lookup',
        fixture: 'mixed-engine',
        scenario: 'direct FilterMatcher reused request',
        iterations: 500,
        warmupIterations: 100,
        operation: () => matcher.matchNetworkRequest(request) is Block ? 1 : 0,
        ruleCounts: {'engine': engine.totalRules},
      );
    }

    final pageBurst =
        <
          ({
            String url,
            String host,
            String sourceHost,
            ResourceType resourceType,
            Type decision,
          })
        >[
          (
            url: 'https://0.avmarket.rs/ad.js',
            host: '0.avmarket.rs',
            sourceHost: 'publisher.invalid',
            resourceType: ResourceType.script,
            decision: Block,
          ),
          (
            url: 'https://sub.0.avmarket.rs/pixel.gif?slot=top',
            host: 'sub.0.avmarket.rs',
            sourceHost: 'news.avmarket.rs',
            resourceType: ResourceType.image,
            decision: Block,
          ),
          (
            url: 'https://guardian-clean.invalid/assets/bench-token-unique.js?v=2',
            host: 'guardian-clean.invalid',
            sourceHost: 'publisher.invalid',
            resourceType: ResourceType.script,
            decision: Block,
          ),
          (
            url: 'https://bench-trie.invalid/api/collect',
            host: 'bench-trie.invalid',
            sourceHost: 'bench-trie.invalid',
            resourceType: ResourceType.xmlHttpRequest,
            decision: Block,
          ),
          (
            url: 'https://bench-priority.invalid/ad.js',
            host: 'bench-priority.invalid',
            sourceHost: 'publisher.invalid',
            resourceType: ResourceType.script,
            decision: Allow,
          ),
          (
            url: 'wss://guardian-clean.invalid/live?channel=bench',
            host: 'guardian-clean.invalid',
            sourceHost: 'guardian-clean.invalid',
            resourceType: ResourceType.websocket,
            decision: Allow,
          ),
        ];
    var mixedBlockCount = 0;
    for (final item in pageBurst) {
      final decision = defaultNoObserverRepository.lookupNetworkRequest(
        NetworkRequest(
          url: item.url,
          host: item.host,
          sourceHost: item.sourceHost,
          resourceType: item.resourceType,
        ),
      );
      checkBenchmarkInvariant(
        decision.runtimeType == item.decision,
        'Unexpected page-burst decision for ${item.url}.',
      );
      if (decision is Block) mixedBlockCount++;
    }
    checkBenchmarkInvariant(
      mixedBlockCount == 4,
      'Mixed lookup workload expected four blocked requests.',
    );
    runner
      ..measureSync(
        id: 'lookup.repository-page-burst',
        suite: 'lookup',
        fixture: 'mixed-engine',
        scenario: 'host-side repository page burst with fresh requests',
        iterations: 100,
        warmupIterations: 20,
        operation: () {
          var blocked = 0;
          for (final item in pageBurst) {
            final request = NetworkRequest(
              url: item.url,
              host: item.host,
              sourceHost: item.sourceHost,
              resourceType: item.resourceType,
            );
            if (defaultNoObserverRepository.lookupNetworkRequest(request) is Block) blocked++;
          }
          return blocked;
        },
        ruleCounts: {'engine': engine.totalRules},
        metrics: {
          'requestsPerOperation': pageBurst.length,
          'blocked': mixedBlockCount,
          'allowed': pageBurst.length - mixedBlockCount,
          'workload': pageBurst
              .map(
                (item) =>
                    '${item.resourceType.name}|${item.sourceHost}|${item.url}|${item.decision}',
              )
              .toList(growable: false),
        },
      )
      ..measureSync(
        id: 'lookup.direct-fresh-request',
        suite: 'lookup',
        fixture: 'mixed-engine',
        scenario: 'direct FilterMatcher fresh NetworkRequest',
        iterations: 500,
        warmupIterations: 100,
        operation: () {
          final request = NetworkRequest(
            url: 'https://guardian-clean.invalid/bench-token-unique.js',
            host: 'guardian-clean.invalid',
            sourceHost: 'publisher.invalid',
            resourceType: ResourceType.script,
          );
          return matcher.matchNetworkRequest(request) is Block ? 1 : 0;
        },
        ruleCounts: {'engine': engine.totalRules},
      );

    final blockedRequest = cases['hosts-hit']!;
    checkBenchmarkInvariant(
      defaultNoObserverRepository.lookupNetworkRequest(blockedRequest) is Block,
      'Default no-observer repository did not block.',
    );
    runner.measureSync(
      id: 'lookup.repository-default-no-observer',
      suite: 'lookup',
      fixture: 'mixed-engine',
      scenario: 'default observability options with no observer configured',
      iterations: 500,
      warmupIterations: 100,
      operation: () =>
          defaultNoObserverRepository.lookupNetworkRequest(blockedRequest) is Block ? 1 : 0,
      ruleCounts: {'engine': engine.totalRules},
    );
    checkBenchmarkInvariant(
      disabledObserverRepository.lookupNetworkRequest(blockedRequest) is Block &&
          disabledObserver.events.isEmpty,
      'Disabled blocked-request observation emitted an event.',
    );
    runner.measureSync(
      id: 'lookup.repository-observation-disabled',
      suite: 'lookup',
      fixture: 'mixed-engine',
      scenario: 'observer configured with blocked-request observation disabled',
      iterations: 500,
      warmupIterations: 100,
      operation: () =>
          disabledObserverRepository.lookupNetworkRequest(blockedRequest) is Block ? 1 : 0,
      ruleCounts: {'engine': engine.totalRules},
    );
    enabledObserverRepository.lookupNetworkRequest(blockedRequest);
    final sentinelEvent = enabledObserver.events.single;
    checkBenchmarkInvariant(
      sentinelEvent is RequestBlocked && sentinelEvent.url == blockedRequest.url,
      'Enabled observer emitted the wrong event type or URL.',
    );
    enabledObserver.events.clear();
    runner.measureSync(
      id: 'lookup.repository-observation-enabled',
      suite: 'lookup',
      fixture: 'mixed-engine',
      scenario: 'observer configured with default blocked-request observation enabled',
      iterations: 500,
      warmupIterations: 100,
      operation: () =>
          enabledObserverRepository.lookupNetworkRequest(blockedRequest) is Block ? 1 : 0,
      ruleCounts: {'engine': engine.totalRules},
    );
    checkBenchmarkInvariant(
      enabledObserver.events.every(
        (event) => event is RequestBlocked && event.url == blockedRequest.url,
      ),
      'Enabled observer benchmark emitted an invalid event.',
    );
  }
}

NetworkRequest _request(String url) {
  final uri = Uri.parse(url);
  return NetworkRequest(
    url: url,
    host: uri.host,
    sourceHost: 'publisher.invalid',
    resourceType: ResourceType.script,
  );
}

final class _RecordingObserver implements WebViewObserver {
  final events = <WebViewEvent>[];

  @override
  void onError(WebViewError error) {}

  @override
  void onEvent(WebViewEvent event) => events.add(event);
}
