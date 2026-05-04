/// A class holding HTTP options for fetching filter lists.
final class FilterHttpOptions {
  /// Creates a [FilterHttpOptions] instance.
  const FilterHttpOptions({
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 60),
    this.headers = const {},
    this.proxy,
  });

  /// The maximum duration to wait for a connection to be established.
  final Duration connectTimeout;

  /// The maximum duration to wait for a response.
  final Duration receiveTimeout;

  /// The headers to include in the request.
  final Map<String, String> headers;

  /// The proxy URL to use for the request.
  final String? proxy;
}
