import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Interface for intercepting traffic in WebView. Implemented separately for each platform.
abstract class TrafficInterceptor {
  /// For Android/Windows: method that the widget should pass to InAppWebView.shouldInterceptRequest.
  ///
  /// For iOS returns null (since Content Blocker is used there).
  FutureOr<WebResourceResponse?> Function(
    InAppWebViewController controller,
    WebResourceRequest request,
  )?
  get shouldInterceptRequest;

  /// Called when the engine is compiled/updated.
  ///
  /// Android/Windows - does nothing (they have dynamic EngineRef).
  Future<void> onEngineUpdated();
}
