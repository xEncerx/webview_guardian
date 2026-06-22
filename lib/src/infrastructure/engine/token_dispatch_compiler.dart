import 'dart:collection';

import 'package:webview_guardian/src/domain/domain.dart';

/// Model for a token-based dispatch table, where each token maps to a list of filter rules that contain that token.
typedef TokenDispatchTable = ({
  HashMap<int, List<FilterRule>> table,
  Set<FilterRule> fallbackRules,
});

/// A compiler that builds a token-based dispatch table for network filter rules.
class TokenDispatchCompiler {
  /// Compiles the given filter rules into a dispatch table based on token frequency.
  static TokenDispatchTable compile(Iterable<FilterRule> rules) {
    final histogram = HashMap<int, int>();
    final candidates = <_TokenDispatchCandidate>[];

    // Pass 1: Build frequency histogram of all valid tokens
    for (final rule in rules) {
      final pattern = switch (rule) {
        final NetworkBlockRule r => r.pattern,
        final NetworkExceptionRule r => r.pattern,
        _ => null,
      };

      if (pattern == null) continue;

      final tokens = pattern.extractTokensAsInt();
      candidates.add((rule: rule, tokens: tokens));

      for (final token in tokens) {
        histogram[token] = (histogram[token] ?? 0) + 1;
      }
    }

    final table = HashMap<int, List<FilterRule>>();
    final fallbackRules = <FilterRule>{};

    // Pass 2: Distribute rules to buckets based on the least frequent token
    for (final candidate in candidates) {
      final (:rule, :tokens) = candidate;

      if (tokens.isEmpty) {
        fallbackRules.add(rule);
        continue;
      }

      var minFreq = 0x7FFFFFFF;
      var bestToken = 0;

      for (final token in tokens) {
        final freq = histogram[token]!;
        if (freq < minFreq) {
          minFreq = freq;
          bestToken = token;
        }
      }

      table.putIfAbsent(bestToken, () => <FilterRule>[]).add(rule);
    }

    return (table: table, fallbackRules: fallbackRules);
  }
}

typedef _TokenDispatchCandidate = ({
  FilterRule rule,
  Set<int> tokens,
});
