import 'dart:async';

import 'package:webview_guardian/src/domain/domain.dart';

/// A WebViewObserver implementation that broadcasts events and errors to multiple delegates via streams.
///
/// Useful when multiple components need to react to events (e.g., logging + UI updates) or when implementing complex processing logic that could block the main thread.
class StreamWebViewObserver implements WebViewObserver {
  /// Creates a [StreamWebViewObserver] instance.
  ///
  /// - [delegates] is the list of observers that will receive events and errors emitted by this observer.
  ///
  /// The caller owns this observer and should call [dispose] when it is no longer needed.
  StreamWebViewObserver({required List<WebViewObserver> delegates}) : _delegates = delegates {
    for (final delegate in _delegates) {
      _eventController.stream.listen(delegate.onEvent);
      _errorController.stream.listen(delegate.onError);
    }
  }
  final List<WebViewObserver> _delegates;

  final _eventController = StreamController<WebViewEvent>.broadcast();
  final _errorController = StreamController<WebViewError>.broadcast();

  /// Stream of WebView events emitted by the ad-blocker.
  ///
  /// The stream is closed when [dispose] is called. Events received after disposal are
  /// ignored.
  Stream<WebViewEvent> get events => _eventController.stream;

  /// Stream of WebView errors emitted by the ad-blocker.
  ///
  /// The stream is closed when [dispose] is called. Errors received after disposal are
  /// ignored.
  Stream<WebViewError> get errors => _errorController.stream;

  @override
  void onEvent(WebViewEvent event) {
    if (_eventController.isClosed) return;
    _eventController.add(event);
  }

  @override
  void onError(WebViewError error) {
    if (_errorController.isClosed) return;
    _errorController.add(error);
  }

  /// Disposes the observer and its resources.
  void dispose() {
    if (!_eventController.isClosed) unawaited(_eventController.close());
    if (!_errorController.isClosed) unawaited(_errorController.close());
  }
}
