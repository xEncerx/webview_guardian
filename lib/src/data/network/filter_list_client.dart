import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// A client for fetching and checking filter lists over the network.
abstract class FilterListClient {
  /// Fetches the content of a filter list.
  Future<FilterFetchResult> fetch(FilterSubscription subscription);

  /// Performs a HEAD request to check the metadata of a filter list.
  Future<FilterHeadResult> head(FilterSubscription subscription);

  /// Disposes of any resources used by the client.
  Future<void> dispose();
}
