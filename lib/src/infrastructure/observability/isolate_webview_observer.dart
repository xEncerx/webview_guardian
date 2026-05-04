import 'dart:isolate';

import 'package:webview_guardian/src/domain/domain.dart';

/// An implementation of [WebViewObserver] that sends events and errors back to the main isolate via a [SendPort].
class IsolateWebViewObserver implements WebViewObserver {
  /// Creates an [IsolateWebViewObserver] instance.
  IsolateWebViewObserver(this._sendPort);

  final SendPort _sendPort;

  @override
  void onEvent(WebViewEvent event) => _sendPort.send(event);

  @override
  void onError(WebViewError error) => _sendPort.send(error);
}
