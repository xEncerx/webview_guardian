import 'package:meta/meta.dart';
import 'package:webview_guardian/src/domain/observability/webview_event.dart';

/// Controls which high-volume repository observability events are emitted.
@immutable
class WebViewObservabilityOptions {
  /// Creates [WebViewObservabilityOptions] instance.
  const WebViewObservabilityOptions({
    this.emitBlockedRequests = true,
    this.emitAllowedRequests = false,
    this.emitCosmeticInjections = true,
    this.emitScriptletInjections = true,
  });

  /// Whether to emit [RequestBlocked] events.
  final bool emitBlockedRequests;

  /// Whether to emit [RequestAllowed] events.
  ///
  /// Disabled by default.
  final bool emitAllowedRequests;

  /// Whether to emit [CosmeticCssInjected] events.
  final bool emitCosmeticInjections;

  /// Whether to emit [ScriptletInjected] events.
  final bool emitScriptletInjections;
}
