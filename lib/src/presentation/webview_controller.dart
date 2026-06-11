import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Controller for interacting with the WebView.
///
/// Exposes a limited set of operations like navigating back/forward,
/// reloading, or loading a new URL.
class WebViewController {
  /// Creates an [WebViewController] instance.
  WebViewController(this._controller);

  final InAppWebViewController _controller;

  /// Loads the given [url].
  Future<void> loadUrl(String url) async {
    await _controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  /// Navigates back in the WebView history.
  Future<void> goBack() async => _controller.goBack();

  /// Navigates forward in the WebView history.
  Future<void> goForward() async => _controller.goForward();

  /// Checks if the WebView can navigate back.
  Future<bool> canGoBack() async => _controller.canGoBack();

  /// Checks if the WebView can navigate forward.
  Future<bool> canGoForward() async => _controller.canGoForward();

  /// Reloads the current page.
  Future<void> reload() async {
    await _controller.reload();
  }

  /// Stops the current page loading.
  Future<void> stopLoading() async {
    await _controller.stopLoading();
  }

  /// Returns the current URL of the WebView.
  Future<String?> getUrl() async {
    final uri = await _controller.getUrl();
    return uri?.toString();
  }

  /// Evaluates JavaScript code within the context of the page.
  ///
  /// **NOTE:** This method shouldn't be called in the onWebViewCreated or onLoadStart events, because, in these events, the WebView is not ready to handle it yet.
  /// Instead, you should call this method, for example, inside the onLoadStop event or in any other events where you know the page is ready "enough".
  Future<dynamic> evaluateJavascript(String source) async {
    return _controller.evaluateJavascript(source: source);
  }
}
