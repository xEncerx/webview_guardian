// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_guardian/webview_guardian.dart';
import 'package:webview_guardian_example/src/app_controller.dart';

class BrowserTab extends StatefulWidget {
  const BrowserTab({required this.controller, super.key});

  final AppController controller;

  @override
  State<BrowserTab> createState() => _BrowserTabState();
}

class _BrowserTabState extends State<BrowserTab> {
  static final Uri _initialUrl = Uri.parse('https://example.com');

  final _addressController = TextEditingController(text: _initialUrl.toString());
  WebViewController? _webViewController;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 1,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _canGoBack
                            ? () {
                                unawaited(_webViewController?.goBack());
                              }
                            : null,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      IconButton(
                        tooltip: 'Forward',
                        onPressed: _canGoForward
                            ? () {
                                unawaited(_webViewController?.goForward());
                              }
                            : null,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                      IconButton(
                        tooltip: 'Reload',
                        onPressed: () {
                          unawaited(_webViewController?.reload());
                        },
                        icon: const Icon(Icons.refresh),
                      ),
                      IconButton(
                        tooltip: 'Stop loading',
                        onPressed: () {
                          unawaited(_webViewController?.stopLoading());
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            labelText: 'Address',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          onSubmitted: _loadAddress,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          unawaited(_loadAddress(_addressController.text));
                        },
                        child: const Text('Go'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              WebView(
                initialUrl: _initialUrl,
                adblockService: widget.controller.adblockService,
                enablePullToRefresh: true,
                onWebViewCreated: (controller) {
                  _webViewController = controller;
                  unawaited(_refreshNavigationState());
                },
                onLoadStart: _handleUrlChanged,
                onLoadStop: _handleUrlChanged,
                onUpdateVisitedHistory: (url, _) => _handleUrlChanged(url),
                onProgressChanged: (progress) => setState(() => _progress = progress),
                onReceivedError: (url, _) => _handleUrlChanged(url),
              ),
              if (_progress > 0 && _progress < 100)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: _progress / 100,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadAddress(String value) async {
    final url = _normalizeUrl(value);
    _addressController.text = url;
    await _webViewController?.loadUrl(url);
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) return trimmed;

    return 'https://$trimmed';
  }

  void _handleUrlChanged(Uri? url) {
    if (url != null) {
      _addressController.text = url.toString();
    }
    unawaited(_refreshNavigationState());
  }

  Future<void> _refreshNavigationState() async {
    final controller = _webViewController;
    if (controller == null || !mounted) return;

    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;

    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }
}
