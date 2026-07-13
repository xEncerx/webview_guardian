import 'dart:io';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// A test implementation of [FilterListClient] that reads from the local file system.
class TestFilterListClient implements FilterListClient {
  @override
  Future<FilterFetchResult> fetch(FilterSubscription subscription) async {
    final file = File(subscription.url);
    if (!file.existsSync()) {
      throw Exception('Test file not found: ${subscription.url}');
    }
    final bytes = await file.readAsBytes();
    return FilterFetchResult(
      bytes: bytes,
      etag: 'test_etag_${file.lastModifiedSync().millisecondsSinceEpoch}',
    );
  }

  @override
  Future<FilterHeadResult> head(FilterSubscription subscription) async {
    final file = File(subscription.url);
    if (!file.existsSync()) {
      return const FilterHeadResult(etag: null);
    }
    return FilterHeadResult(
      etag: 'test_etag_${file.lastModifiedSync().millisecondsSinceEpoch}',
    );
  }

  @override
  Future<void> dispose() async {}
}
