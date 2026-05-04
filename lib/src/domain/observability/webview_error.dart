/// Base class for all webview related errors.
sealed class WebViewError {
  /// Creates a [WebViewError] instance.
  const WebViewError(this.message, {this.cause});

  /// A descriptive message detailing the error.
  final String message;

  /// The underlying cause of the error, if any.
  final Object? cause;
}

/// Error thrown when fetching a filter list fails.
final class FilterFetchFailed extends WebViewError {
  /// Creates a [FilterFetchFailed] instance.
  const FilterFetchFailed(super.message, {super.cause});
}

/// Error thrown when restoring a filter cache fails.
final class CacheRestoreFailed extends WebViewError {
  /// Creates a [CacheRestoreFailed] instance.
  const CacheRestoreFailed(super.message, {super.cause});
}

/// Error thrown when building the filtering engine fails.
final class EngineBuildFailed extends WebViewError {
  /// Creates a [EngineBuildFailed] instance.
  const EngineBuildFailed(super.message, {super.cause});
}

/// Error thrown when initializing the filtering engine fails.
final class EngineInitFailed extends WebViewError {
  /// Creates a [EngineInitFailed] instance.
  const EngineInitFailed(super.message, {super.cause});
}

/// Error thrown when the filtering isolate crashes.
final class IsolateCrashError extends WebViewError {
  /// Creates a [IsolateCrashError] instance.
  const IsolateCrashError(super.message, {super.cause});
}
