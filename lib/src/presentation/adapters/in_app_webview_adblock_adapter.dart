import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/infrastructure/services/adblock_service.dart';

/// Adapts [AdblockService] to [InAppWebView] settings and callbacks.
///
/// Create one adapter per [InAppWebView] instance. The adapter stores per-WebView
/// script injection state and must not be shared between tabs or widgets.
final class InAppWebViewAdblockAdapter {
  /// Creates an [InAppWebViewAdblockAdapter] instance.
  InAppWebViewAdblockAdapter({
    required AdblockService adblockService,
    InAppWebViewSettings? baseSettings,
    Uri? initialUrl,
  }) : _adblockService = adblockService,
       _initialHost = initialUrl?.host,
       initialSettings = _buildSettings(baseSettings);

  final AdblockService _adblockService;
  final String? _initialHost;

  List<UserScript>? _initialScripts;
  String? _initialPreloadedHost;
  String? _lastInjectedHost;

  /// Settings that should be passed to `InAppWebView.initialSettings`.
  final InAppWebViewSettings initialSettings;

  /// Scripts that should be passed to `InAppWebView.initialUserScripts`.
  List<UserScript> get initialUserScripts => _initialScripts ??= _buildInitialScripts();

  /// Callback that should be passed to `InAppWebView.shouldInterceptRequest`.
  FutureOr<WebResourceResponse?> Function(
    InAppWebViewController controller,
    WebResourceRequest request,
  )?
  get shouldInterceptRequest => _shouldInterceptRequest;

  /// Callback that should be passed to `InAppWebView.shouldOverrideUrlLoading`.
  Future<NavigationActionPolicy> Function(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  )?
  get shouldOverrideUrlLoading => _shouldOverrideUrlLoading;

  static InAppWebViewSettings _buildSettings(InAppWebViewSettings? baseSettings) {
    final customSchemes = _mergeCustomSchemes(baseSettings?.resourceCustomSchemes);

    return (baseSettings?.copy() ?? InAppWebViewSettings())
      ..transparentBackground = true
      ..useShouldInterceptRequest = true
      ..useShouldOverrideUrlLoading = true
      ..mixedContentMode = MixedContentMode.MIXED_CONTENT_NEVER_ALLOW
      ..thirdPartyCookiesEnabled = false
      ..allowsLinkPreview = false
      ..resourceCustomSchemes = customSchemes;
  }

  static List<String> _mergeCustomSchemes(List<String>? baseSchemes) {
    final schemes = [...?baseSchemes];
    if (!schemes.contains('adblock')) {
      schemes.add('adblock');
    }
    return schemes;
  }

  FutureOr<WebResourceResponse?> _shouldInterceptRequest(
    InAppWebViewController controller,
    WebResourceRequest request,
  ) {
    if (!_canUseAdblock) return null;

    final intercept = _adblockService.trafficInterceptor?.shouldInterceptRequest;
    if (intercept == null) return null;

    return intercept(controller, request);
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    if (navigationAction.isForMainFrame) {
      final url = navigationAction.request.url;
      if (url != null) {
        await _applyInjections(controller, url.host);
      }
    }

    return NavigationActionPolicy.ALLOW;
  }

  /// Applies host-specific scripts when a page starts loading.
  Future<void> onLoadStart(InAppWebViewController controller, WebUri? url) async {
    if (url == null) return;
    await _applyInjections(controller, url.host);
  }

  List<UserScript> _getScriptsForHost(String? hostname) {
    if (hostname == null) return [];
    if (!_canBuildInjections) return [];

    return _adblockService.orchestrator!.buildUserScripts(hostname);
  }

  bool get _canUseAdblock {
    if (!_adblockService.isEnabled || !_adblockService.isReady.value) return false;
    return _adblockService.ruleCount > 0;
  }

  bool get _canBuildInjections => _canUseAdblock && _adblockService.orchestrator != null;

  List<UserScript> _buildInitialScripts() {
    final scripts = _getScriptsForHost(_initialHost);
    if (scripts.isNotEmpty) {
      _initialPreloadedHost = _initialHost;
    }
    return scripts;
  }

  Future<void> _applyInjections(InAppWebViewController controller, String hostname) async {
    if (_lastInjectedHost == hostname) return;
    if (_initialPreloadedHost == hostname) {
      _initialPreloadedHost = null;
      return;
    }
    if (!_canBuildInjections) return;

    final scripts = _getScriptsForHost(hostname);

    await controller.removeAllUserScripts();
    for (final script in scripts) {
      await controller.addUserScript(userScript: script);
    }
    _lastInjectedHost = hostname;
  }

  /// Releases adapter-owned state.
  void dispose() {
    _initialScripts = null;
    _initialPreloadedHost = null;
    _lastInjectedHost = null;
  }
}
