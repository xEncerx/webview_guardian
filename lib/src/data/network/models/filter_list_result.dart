import 'dart:typed_data';

/// A class representing the result of fetching a filter list.
final class FilterFetchResult {
  /// Creates a [FilterFetchResult] instance.
  const FilterFetchResult({
    required this.bytes,
    required this.etag,
  });

  /// The raw bytes of the fetched filter list.
  final Uint8List bytes;

  /// The entity tag of the fetched filter list.
  final String? etag;
}

/// A class representing the result of checking the metadata of a filter list.
final class FilterHeadResult {
  /// Creates a [FilterHeadResult] instance.
  const FilterHeadResult({
    required this.etag,
  });

  /// The entity tag of the filter list.
  final String? etag;
}
