/// Base class for all webview observability events.
sealed class WebViewEvent {
  /// Creates a [WebViewEvent] instance.
  const WebViewEvent();
}

/// Response indicating that the fetch of a filter list has started.
final class FilterListFetchStarted extends WebViewEvent {
  /// Creates a [FilterListFetchStarted] instance.
  const FilterListFetchStarted(this.url);

  /// The FilterSubscription for which the filter list fetch has started, useful for tracking progress in the main isolate.
  final String url;
}

/// Event indicating that the filter engine was successfully compiled.
final class EngineCompiled extends WebViewEvent {
  /// Creates a [EngineCompiled] instance.
  const EngineCompiled({
    required this.totalRules,
    required this.compilationTime,
  });

  /// The total number of rules compiled into the engine.
  final int totalRules;

  /// The time taken to compile the filtering engine.
  final Duration compilationTime;
}

/// Event indicating that the filter engine was restored from cache.
final class EngineRestoredFromCache extends WebViewEvent {
  /// Creates an [EngineRestoredFromCache] instance.
  const EngineRestoredFromCache({
    required this.totalRules,
    required this.compilationTime,
  });

  /// The total number of rules that were loaded from cache.
  final int totalRules;

  /// The time taken to restore the engine from cache.
  final Duration compilationTime;
}

/// Event indicating that the filter cache was completely cleared.
final class FilterCacheCleared extends WebViewEvent {
  /// Creates a [FilterCacheCleared] instance.
  const FilterCacheCleared();
}

/// Event indicating that a filter list matched the cached version and was not re-downloaded.
final class FilterCacheMatch extends WebViewEvent {
  /// Creates a [FilterCacheMatch] instance.
  const FilterCacheMatch(this.url);

  /// The URL of the filter list that matched the cache.
  final String url;
}

/// Event indicating that a network request was blocked by the filtering engine.
final class RequestBlocked extends WebViewEvent {
  /// Creates a [RequestBlocked] instance.
  const RequestBlocked(this.url);

  /// The URL of the blocked request.
  final String url;
}

/// Event indicating that a network request was allowed by the filtering engine.
final class RequestAllowed extends WebViewEvent {
  /// Creates a [RequestAllowed] instance.
  const RequestAllowed(this.url);

  /// The URL of the allowed request.
  final String url;
}

/// Event indicating that a scriptlet was injected into the page.
final class ScriptletInjected extends WebViewEvent {
  /// Creates a [ScriptletInjected] instance.
  const ScriptletInjected({
    required this.hostname,
    required this.scriptletName,
  });

  /// The hostname where the scriptlet was injected.
  final String hostname;

  /// The name of the injected scriptlet.
  final String scriptletName;
}

/// Event indicating that cosmetic CSS was injected into the page.
final class CosmeticCssInjected extends WebViewEvent {
  /// Creates a [CosmeticCssInjected] instance.
  const CosmeticCssInjected({
    required this.hostname,
    required this.selector,
  });

  /// The hostname where the CSS was injected.
  final String hostname;

  /// The CSS selector that was injected.
  final String selector;
}
