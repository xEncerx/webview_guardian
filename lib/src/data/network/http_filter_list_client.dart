import 'dart:io';
import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/entities/filter_subscription.dart';

/// An HTTP implementation of [FilterListClient].
class HttpFilterListClient implements FilterListClient {
  /// Creates a [HttpFilterListClient] instance.
  HttpFilterListClient(this._options) {
    _client = HttpClient()..connectionTimeout = _options.connectTimeout;
    if (_options.proxy != null) {
      _configureProxy(_options.proxy!);
    }
  }

  final FilterHttpOptions _options;
  late final HttpClient _client;

  @override
  Future<FilterFetchResult> fetch(FilterSubscription subscription) async {
    final request = await _client.getUrl(Uri.parse(subscription.url));
    _applyHeaders(request);

    final response = await request.close().timeout(_options.receiveTimeout);

    final builder = BytesBuilder(copy: false);
    await response.forEach(builder.add).timeout(_options.receiveTimeout);

    return FilterFetchResult(
      bytes: builder.takeBytes(),
      etag: response.headers.value('etag'),
    );
  }

  @override
  Future<FilterHeadResult> head(FilterSubscription subscription) async {
    final request = await _client.headUrl(Uri.parse(subscription.url));
    _applyHeaders(request);

    final response = await request.close().timeout(_options.receiveTimeout);
    await response.drain<void>();

    return FilterHeadResult(
      etag: response.headers.value('etag'),
    );
  }

  void _applyHeaders(HttpClientRequest request) {
    request.headers.set(
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    );
    for (final entry in _options.headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  void _configureProxy(String proxyUrl) {
    final uri = Uri.tryParse(proxyUrl);
    if (uri == null) return;

    final host = uri.host;
    final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);

    final proxyType = switch (uri.scheme.toLowerCase()) {
      'socks4' => 'SOCKS4',
      'socks5' => 'SOCKS5',
      'socks' => 'SOCKS5',
      'http' => 'HTTP',
      'https' => 'HTTPS',
      _ => 'DIRECT',
    };

    _client.findProxy = (url) => '$proxyType $host:$port';

    if (uri.userInfo.isNotEmpty) {
      final parts = uri.userInfo.split(':');
      final username = parts[0];
      final password = parts.length > 1 ? parts.sublist(1).join(':') : '';

      _client
        ..addProxyCredentials(
          host,
          port,
          'Basic',
          HttpClientBasicCredentials(username, password),
        )
        // Fallback for proxies with non-standard or unknown realm names.
        // Without this, if the realm doesn't match 'Basic', the 407 challenge
        // won't find the pre-registered credentials and the request will fail.
        ..authenticateProxy = (host, port, scheme, realm) async {
          _client.addProxyCredentials(
            host,
            port,
            realm ?? 'Basic',
            HttpClientBasicCredentials(username, password),
          );
          return true;
        };
    }
  }
}
