import 'package:webview_guardian/src/domain/domain.dart';

/// An interface for observing webview events and errors.
abstract interface class WebViewObserver {
  /// Called when a webview event occurs.
  void onEvent(WebViewEvent event);

  /// Called when a webview error occurs.
  void onError(WebViewError error);
}
