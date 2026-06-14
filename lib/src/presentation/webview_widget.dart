import 'dart:async';
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
  final String initialUrl;

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
  late final InAppWebViewSettings _settings;
  late final InAppWebViewController _controller;
  PullToRefreshController? _pullToRefreshController;

  late final WebUri _initialUri;
  String? _initialHost;
  String? _lastInjectedHost;

  @override
  void initState() {
    super.initState();
    _settings = InAppWebViewSettings(
      isInspectable: kDebugMode,
      mediaPlaybackRequiresUserGesture: false,
      transparentBackground: true,
      useShouldInterceptRequest: true,
      mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
      thirdPartyCookiesEnabled: false,
      allowsLinkPreview: false,
      resourceCustomSchemes: ['adblock'],
      // // Disable Hybrid Composition on Android to prevent visual glitches
      // // and "Renderer process crash" when closing the WebView.
      // useHybridComposition: defaultTargetPlatform != TargetPlatform.android,
    );

    _initialUri = WebUri(widget.initialUrl);
    try {
      _initialHost = _initialUri.host;
    } on Exception catch (_) {
      _initialHost = null;
    }
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
      initialUserScripts: UnmodifiableListView(_getInitialScripts()),
      gestureRecognizers: widget.gestureRecognizers,
      onWebViewCreated: (controller) {
        _controller = controller;
        widget.onWebViewCreated?.call(WebViewController(controller));
      },
      shouldInterceptRequest: _shouldInterceptRequest,
      onLoadStart: (controller, url) async {
        widget.onLoadStart?.call(url);

        if (url != null) {
          await _applyInjections(controller, url.host);
        }
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

  FutureOr<WebResourceResponse?> _shouldInterceptRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) {
    final service = widget.adblockService;
    if (service == null || !service.isEnabled || !service.isReady.value) {
      return null;
    }
    if (service.ruleCount == 0) return null;

    final intercept = service.trafficInterceptor?.shouldInterceptRequest;
    if (intercept == null) return null;

    return intercept(controller, request);
  }

  List<UserScript> _getScriptsForHost(String? hostname) {
    if (hostname == null) return [];

    if (!_canBuildInjections) return [];

    return widget.adblockService!.orchestrator!.buildUserScripts(hostname);
  }

  bool get _canBuildInjections {
    final service = widget.adblockService;
    if (service == null || !service.isEnabled || !service.isReady.value) return false;
    if (service.ruleCount == 0) return false;

    return service.orchestrator != null;
  }

  List<UserScript> _getInitialScripts() {
    final scripts = _getScriptsForHost(_initialHost);
    if (scripts.isNotEmpty) {
      _lastInjectedHost = _initialHost;
    }
    return scripts;
  }

  Future<void> _applyInjections(InAppWebViewController controller, String hostname) async {
    if (_lastInjectedHost == hostname) return;
    if (!_canBuildInjections) return;

    final scripts = _getScriptsForHost(hostname);

    await controller.removeAllUserScripts();
    for (final script in scripts) {
      await controller.addUserScript(userScript: script);
    }
    _lastInjectedHost = hostname;
  }
}
