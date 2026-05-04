import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';

/// Evaluates network requests against filter rules.
class FilterMatcher {
  /// Creates a [FilterMatcher] instance.
  const FilterMatcher(this._engineRef);

  /// Engine containing compiled trie, tokens, and fallback rules.
  final FilterEngineRef _engineRef;

  /// Matches a network request against all filter rules to determine the appropriate action.
  FilterDecision matchNetworkRequest(NetworkRequest request) {
    FilterRule? bestMatch;
    var highestWeight = 0;

    // 1. Hostname Trie Search (Domain Rules)
    final host = request.host;
    final buffer = _engineRef.current.trieBuffer;
    final trieRules = _engineRef.current.trieRules;

    var offset = 0;

    for (var i = host.length - 1; i >= -1; i--) {
      final word0 = buffer[offset];
      final ruleCount = word0 & 0xFFFF;

      if (ruleCount > 0) {
        // Check if the consumed suffix is a strict domain boundary ('/' equivalent or '.').
        // i == -1 means the entire string was consumed.
        if (i == -1 || host.codeUnitAt(i) == 0x2E) {
          // 0x2E == '.'

          final rulesStartIndex = buffer[offset + 1];
          for (var r = 0; r < ruleCount; r++) {
            final rule = trieRules[rulesStartIndex + r];
            if (rule.matchesRequest(request)) {
              final w = rule.ruleWeight;
              if (w > highestWeight) {
                bestMatch = rule;
                highestWeight = w;
                if (highestWeight == 4) return const Allow();
              }
            }
          }
        }
      }

      if (i == -1) break; // Host exhausted, no children to check

      final childCount = word0 >> 16;
      if (childCount == 0) break; // Leaf node, no path forward

      final charToFind = host.codeUnitAt(i);
      final childrenStart = offset + 1 + (ruleCount > 0 ? 1 : 0);

      // Binary search for the child node character
      var found = false;
      var low = 0;
      var high = childCount - 1;

      while (low <= high) {
        final mid = (low + high) >> 1;
        final childWord = buffer[childrenStart + mid];
        final childChar = childWord >> 24;

        if (childChar == charToFind) {
          offset = childWord & 0xFFFFFF; // Mask 24 bits for childOffset
          found = true;
          break;
        } else if (childChar < charToFind) {
          low = mid + 1;
        } else {
          high = mid - 1;
        }
      }

      if (!found) break; // Branch missed, suffix not blocked by Trie
    }

    // 2. Token Dispatch (Search by 5-character patterns inside URL)
    request.url.anyTokenMatches((token) {
      final rulesBucket = _engineRef.current.tokenDispatchTable[token];
      if (rulesBucket != null) {
        for (var r = 0; r < rulesBucket.length; r++) {
          final rule = rulesBucket[r];
          if (rule.matchesRequest(request)) {
            final w = rule.ruleWeight;
            if (w > highestWeight) {
              bestMatch = rule;
              highestWeight = w;
              if (highestWeight == 4) return true; // Stop searching
            }
          }
        }
      }
      return false; // Continue searching
    });

    if (highestWeight == 4) return const Allow();

    // 3. Fallback Rules (All rules not in Trie or Tokens)
    for (final rule in _engineRef.current.fallbackRules) {
      if (rule.matchesRequest(request)) {
        final w = rule.ruleWeight;
        if (w > highestWeight) {
          bestMatch = rule;
          highestWeight = w;
          if (highestWeight == 4) return const Allow();
        }
      }
    }

    // 4. Final Decision
    if (bestMatch is NetworkBlockRule) {
      return const Block();
    }

    // Allow the request if no valid rules matched or an exception matched
    return const Allow();
  }
}
