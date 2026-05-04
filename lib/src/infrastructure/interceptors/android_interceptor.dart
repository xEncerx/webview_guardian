import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Adapter that implements [TrafficInterceptor] for Android using InAppWebView's shouldInterceptRequest.
class AndroidInterceptorAdapter implements TrafficInterceptor {
  /// Creates an [AndroidInterceptorAdapter] instance.
  AndroidInterceptorAdapter(FilterRepository filterRepository)
    : _filterRepository = filterRepository;

  final FilterRepository _filterRepository;

  Uri _currentMainFrameUri = Uri();

  @override
  Future<void> onEngineUpdated() async {
    // No action needed for Android when the engine is updated.
  }

  @override
  FutureOr<WebResourceResponse?> Function(
    InAppWebViewController controller,
    WebResourceRequest request,
  )?
  get shouldInterceptRequest => _intercept;

  WebResourceResponse? _intercept(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) {
    final uri = request.url.uriValue;
    final isMainFrame = request.isForMainFrame ?? false;

    if (isMainFrame) _currentMainFrameUri = uri;

    final netRequest = NetworkRequest(
      url: uri.toString(),
      host: uri.host,
      resourceType: request.getResourceType(isMainFrame),
      sourceHost: _currentMainFrameUri.host,
    );

    final decision = _filterRepository.lookupNetworkRequest(netRequest);

    return switch (decision) {
      Block() => WebResourceResponse(
        statusCode: 200,
        reasonPhrase: 'Forbidden',
        data: Uint8List(0),
      ),
      // TODO: implement redirect logic in future.
      Allow() => null,
    };
  }
}
