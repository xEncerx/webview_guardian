/// A class holding HTTP options for fetching filter lists.
final class FilterHttpOptions {
  /// Creates a [FilterHttpOptions] instance.
  const FilterHttpOptions({
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 60),
    this.headers = const {},
    this.proxy,
    this.maxFilterListBytes = 32 * 1024 * 1024,
    this.maxConcurrentDownloads = 4,
  }) : assert(maxFilterListBytes > 0, 'maxFilterListBytes must be positive'),
       assert(maxConcurrentDownloads > 0, 'maxConcurrentDownloads must be positive');

  /// The maximum duration to wait for a connection to be established.
  final Duration connectTimeout;

  /// The maximum duration to wait for a response.
  final Duration receiveTimeout;

  /// The headers to include in the request.
  final Map<String, String> headers;

  /// The proxy URL to use for the request.
  ///
  /// Only `http://` proxy URLs are supported.
  final String? proxy;

  /// The maximum number of bytes accepted from one filter-list response.
  ///
  /// Defaults to 32 MiB.
  final int maxFilterListBytes;

  /// The maximum number of filter-list subscription workflows run concurrently.
  ///
  /// Defaults to 4.
  final int maxConcurrentDownloads;
}
