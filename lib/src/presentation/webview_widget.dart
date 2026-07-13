import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/src.dart';

/// A wrapper around [InAppWebView] that integrates with [AdblockService].
class WebView extends StatefulWidget {
  /// If [adblockService] is provided and enabled, this widget will intercept requests
  /// and inject cosmetic rules (CSS/JS) to block ads.
  ///
  /// Auto controls the lifecycle of the inner [InAppWebViewController] and provides a simplified
  /// interface for the parent widget to interact with the web view.
  const WebView({
    required this.initialUrl,
    this.adblockService,
    this.enablePullToRefresh = false,
    this.pullToRefreshSettings,
    this.gestureRecognizers,
    this.onWebViewCreated,
    this.onLoadStart,
    this.onLoadStop,
    this.onUpdateVisitedHistory,
    this.onProgressChanged,
    this.onReceivedError,
    super.key,
  });

  /// The initial URL to load.
  final Uri initialUrl;

  /// The global adblock service. If null, the WebView operates normally without adblocking.
  final AdblockService? adblockService;

  /// Whether to enable pull-to-refresh functionality. Defaults to false.
  ///
  /// Note: Pull-to-refresh is only supported on certain platforms (e.g. Android, iOS). On unsupported platforms, this will have no effect.
  final bool enablePullToRefresh;

  /// Customization for the pull-to-refresh behavior and appearance.
  ///
  /// Only applicable if [enablePullToRefresh] is true and the current platform supports pull-to-refresh.
  ///
  /// By default, the refresh indicator will use the theme's primary color on a surface background.
  final WebViewPullToRefreshSettings? pullToRefreshSettings;

  /// Callback fired when the inner [InAppWebViewController] is ready.
  ///
  /// Provides a [WebViewController] that can be used to control the web view (e.g. loadUrl, goBack).
  ///
  /// Note: The lifecycle of the controller is managed by [WebView], you don't need to call dispose on it manually.
  final void Function(WebViewController controller)? onWebViewCreated;

  /// Callback fired when a page starts loading.
  final void Function(Uri? url)? onLoadStart;

  /// Callback fired when a page finishes loading.
  final void Function(Uri? url)? onLoadStop;

  /// Callback fired when the visited history is updated (e.g. navigation occurs).
  final void Function(Uri? url, bool? isReload)? onUpdateVisitedHistory;

  /// Callback fired when the loading progress changes.
  final void Function(int progress)? onProgressChanged;

  /// Callback fired when a resource loading error occurs.
  final void Function(Uri url, String errorDetails)? onReceivedError;

  /// Which gestures should be consumed by the web view.
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  @override
  State<WebView> createState() => _WebViewState();
}

class _WebViewState extends State<WebView> {
  late InAppWebViewSettings _settings;
  late final InAppWebViewController _controller;
  InAppWebViewAdblockAdapter? _adblockAdapter;
  PullToRefreshController? _pullToRefreshController;

  late final WebUri _initialUri;

  @override
  void initState() {
    super.initState();

    _initialUri = WebUri.uri(widget.initialUrl);
    _configureAdblockAdapter();
  }

  @override
  void didUpdateWidget(covariant WebView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.adblockService != widget.adblockService) {
      _adblockAdapter?.dispose();
      _configureAdblockAdapter();
    }
  }

  @override
  void dispose() {
    _adblockAdapter?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (widget.enablePullToRefresh && _pullToRefreshController == null) {
      // Check if the current platform supports pull-to-refresh before initializing the controller.
      final isSupported = PullToRefreshController.isClassSupported(platform: defaultTargetPlatform);
      if (!isSupported) return;

      final theme = Theme.of(context);

      _pullToRefreshController = PullToRefreshController(
        settings:
            widget.pullToRefreshSettings?.toPullToRefreshSettings() ??
            PullToRefreshSettings(
              backgroundColor: theme.colorScheme.surface,
              color: theme.colorScheme.primary,
            ),
        onRefresh: () async {
          if (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.windows) {
            await _controller.reload();
          } else if (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS) {
            final url = await _controller.getUrl();
            if (url != null) {
              await _controller.loadUrl(urlRequest: URLRequest(url: url));
            }
          }
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: _initialUri),
      initialSettings: _settings,
      pullToRefreshController: _pullToRefreshController,
      initialUserScripts: UnmodifiableListView(_adblockAdapter?.initialUserScripts ?? const []),
      gestureRecognizers: widget.gestureRecognizers,
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onWebViewCreated?.call(WebViewController(controller));
      },
      shouldInterceptRequest: _adblockAdapter?.shouldInterceptRequest,
      shouldOverrideUrlLoading: _adblockAdapter?.shouldOverrideUrlLoading,
      onLoadStart: (controller, url) async {
        widget.onLoadStart?.call(url);
        await _adblockAdapter?.onLoadStart(controller, url);
      },
      onLoadStop: (_, url) async {
        widget.onLoadStop?.call(url);
        await _pullToRefreshController?.endRefreshing();
      },
      onReceivedError: (_, request, error) async {
        widget.onReceivedError?.call(request.url, error.description);
        await _pullToRefreshController?.endRefreshing();
      },
      onUpdateVisitedHistory: (_, url, isReload) =>
          widget.onUpdateVisitedHistory?.call(url, isReload),
      onProgressChanged: (_, progress) => widget.onProgressChanged?.call(progress),
    );
  }

  InAppWebViewSettings _buildBaseSettings() {
    return InAppWebViewSettings(
      isInspectable: kDebugMode,
      mediaPlaybackRequiresUserGesture: false,
      useShouldInterceptRequest: false,
      useShouldOverrideUrlLoading: false,
      thirdPartyCookiesEnabled: null,
      transparentBackground: null,
      allowsLinkPreview: null,
      resourceCustomSchemes: null,
    );
  }

  void _configureAdblockAdapter() {
    final service = widget.adblockService;
    _adblockAdapter = service == null
        ? null
        : InAppWebViewAdblockAdapter(
            adblockService: service,
            baseSettings: _buildBaseSettings(),
            initialUrl: widget.initialUrl,
          );
    _settings = _adblockAdapter?.initialSettings ?? _buildBaseSettings();
  }
}
