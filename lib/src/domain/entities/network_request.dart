import 'package:meta/meta.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Represents an intercepted network request that needs to be evaluated against the active ad-blocking rules.
@immutable
class NetworkRequest {
  /// Creates a [NetworkRequest] instance.
  NetworkRequest({
    required this.url,
    required this.host,
    required this.resourceType,
    required this.sourceHost,
  });

  /// The URL of the page that initiated the request.
  final String url;

  /// The host of the page that initiated the request.
  final String host;

  /// The category of the resource being requested.
  final ResourceType resourceType;

  /// The host of the page that initiated the request.
  final String sourceHost;

  /// Indicates whether the request is made to a domain different from the
  /// domain of the [sourceHost] (based on a zero-allocation TLD+1 heuristic).
  late final bool isThirdParty = _isThirdParty();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkRequest &&
          runtimeType == other.runtimeType &&
          url == other.url &&
          host == other.host &&
          resourceType == other.resourceType &&
          sourceHost == other.sourceHost &&
          isThirdParty == other.isThirdParty;

  @override
  int get hashCode =>
      url.hashCode ^
      host.hashCode ^
      resourceType.hashCode ^
      sourceHost.hashCode ^
      isThirdParty.hashCode;

  bool _isThirdParty() {
    if (identical(host, sourceHost)) return false;
    if (host.isEmpty || sourceHost.isEmpty) return false;
    return host.getBaseDomain() != sourceHost.getBaseDomain();
  }
}
