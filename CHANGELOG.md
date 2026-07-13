## 0.3.0

### Breaking changes

- Remove the unused `id` and `lastEtag` named parameters from `FilterSubscription.copyWith`.
- Change `WebView.initialUrl` from `String` to `Uri` so callers provide a parsed initial URL.

### Added

- Support Adblock Plus `#$#` CSS injection rules globally and for domain include/exclude lists.
- Add `AdblockService.updateHttpOptions` to update filter download headers, proxy, and timeouts at runtime, with an optional immediate filter refresh.

### Fixed

- Reject network rules with unknown positive ABP modifiers instead of applying them without their intended constraints.
- Classify unknown WebView resources as `other` instead of `subdocument` without explicit HTML signals.
- Preserve every active filter subscription when a periodic rebuild runs.
- Preserve caller-owned WebView user scripts when Guardian refreshes its host-specific injections.
- Propagate terminal filter build and cache-clear failures through their public futures.
- Reject `AdblockService.init()` immediately on unsupported platforms before starting filter jobs.

### Changed

- Make periodic filter updates opt-in by defaulting `FilterSubscription.updateInterval` to `null`.

## 0.2.1

### Fixed

- Preserve 40-bit token dispatch keys during engine serialization.
- Prune fallback matching by rule precedence.

## 0.2.0

### Breaking changes

- `AdblockService.updateSubscriptions` and `AdblockService.clearCache` now return `Future<void>` and complete only after the underlying isolate job finishes.
- `RequestAllowed` observer events are now disabled by default to avoid high-volume callbacks during request interception.

### Added

- Add `WebViewObservabilityOptions` to configure emitted observer events, including blocked requests, allowed requests, cosmetic injections, and scriptlet injections.
- Add `CosmeticFilteringOptions` to control generic cosmetic rule handling for CSS injection performance.
- Add a reusable `InAppWebViewAdblockAdapter` for the WebView adblock integration layer.
- Add tests for adblock service jobs, filter storage, parser behavior, engine serialization, isolate manager behavior, repository observability, traffic interception, and WebView integration.

### Changed

- Refactor `AdblockService` job scheduling so initialization, subscription updates, and cache clearing wait for active worker jobs instead of returning before completion.
- Bind compiled engine cache entries to subscription identity and metadata so stale compiled engines are not reused for changed filter lists.
- Improve filter list cache validation by using metadata sidecars and cheaper cache checks before loading payload bytes.
- Preserve cosmetic domain exclusions and share common filter rule model logic across parsers and matchers.
- Prepare document-start injections before navigation and avoid adblock-specific WebView settings when no adblock service is attached.

### Fixed

- Clear in-memory adblock state when the cache is reset.
- Complete active filter isolate jobs when the service is disposed or cache restore fails.
- Ignore `StreamWebViewObserver` callbacks after dispose.
- Reject unsuccessful filter list HTTP responses and fall back to `GET` when `HEAD` checks fail.
- Parse hash-containing network filter rules.
- Support case-insensitive ABP network matching and first-party ABP network rules.
- Apply global cosmetic and scriptlet rules.
- Restrict domain-anchor matching to the URL authority and scope interceptor source hosts per WebView controller.
- Retry initial host injection until scripts are installed.
- Preserve the empty compiled-engine trie invariant.
- Emit injection observability from script orchestration.

### Performance

- Reduce compiled-engine builder buffer allocations with growable binary buffers.
- Avoid duplicate token extraction during dispatch compilation.
- Limit generic cosmetic CSS rules in the default performance mode and keep generic rules out of MutationObserver scripts unless full mode is enabled.

### Migration guide from 0.1.x

#### Await cache and subscription operations

`AdblockService.updateSubscriptions` and `AdblockService.clearCache` are asynchronous now. If your code previously treated them as fire-and-forget operations, update it to `await` the returned `Future<void>` before reading readiness, rule counts, cache-dependent state, or updating UI that assumes the operation is finished.

```dart
// Before 0.2.0
adblockService.clearCache();
adblockService.updateSubscriptions(subscriptions);

// 0.2.0+
await adblockService.clearCache();
await adblockService.updateSubscriptions(subscriptions);
```

#### Opt in to allowed-request observer events

Allowed request events are no longer emitted by default. If your observer depends on `RequestAllowed` events, pass `WebViewObservabilityOptions(emitAllowedRequests: true)` when initializing `AdblockService`.

```dart
await adblockService.init(
  subscriptions: subscriptions,
  observer: observer,
  observabilityOptions: const WebViewObservabilityOptions(
    emitAllowedRequests: true,
  ),
);
```

## 0.1.1
- Add a Flutter example app for Android and Windows with blocker settings, observer logs, and a browser tab.
- Improve adblock isolate lifecycle with short-lived filter jobs and safer cache-restore failure handling.
- Fix filter storage initialization by ensuring the adblocker directory is created before use.
- Add a GitHub Actions workflow to run automated tests.
- Update package dependency versions.

## 0.1.0

Initial release.
