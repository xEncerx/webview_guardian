import 'dart:collection';

import 'package:webview_guardian/src/domain/domain.dart';

/// A utility class for deduplicating filter rules based on their content.
class FilterDeduplicator {
  /// Deduplicates the given [rules] by their content, preserving the order of first occurrence.
  static LinkedHashSet<FilterRule> deduplicate(Iterable<FilterRule> rules) {
    return LinkedHashSet<FilterRule>.of(rules);
  }

  /// Merges multiple lists of [FilterRule]s and deduplicates them by their content, preserving the order of first occurrence.
  static LinkedHashSet<FilterRule> mergeAndDeduplicate(
    List<Iterable<FilterRule>> parsedSubscriptions,
  ) {
    final allRules = parsedSubscriptions.expand((s) => s);
    return deduplicate(allRules);
  }
}
