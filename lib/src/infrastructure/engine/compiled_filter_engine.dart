import 'dart:typed_data';

import 'package:webview_guardian/src/domain/domain.dart';

/// Compiled filter engine that holds the optimized data structures for efficient rule matching.
class CompiledFilterEngine {
  /// Creates a [CompiledFilterEngine] instance.
  CompiledFilterEngine({
    required this.totalRules,
    required this.trieBuffer,
    required this.trieRules,
    required this.tokenDispatchTable,
    required this.fallbackRules,
    required this.cosmeticHideRules,
    required this.cosmeticExceptionRules,
    required this.scriptletRules,
    required this.cssInjectRules,
  });

  /// Creates an empty [CompiledFilterEngine] instance.
  factory CompiledFilterEngine.empty() {
    return CompiledFilterEngine(
      totalRules: 0,
      trieBuffer: Uint32List(1),
      trieRules: const [],
      tokenDispatchTable: const {},
      fallbackRules: const {},
      cosmeticHideRules: const {},
      cosmeticExceptionRules: const {},
      scriptletRules: const {},
      cssInjectRules: const {},
    );
  }

  /// The total number of rules that were compiled into this engine.
  final int totalRules;

  /// Compressed domain tree (Hostname Trie).
  final Uint32List trieBuffer;

  /// Flat list of rules for Trie.
  final List<FilterRule> trieRules;

  /// Dispatch table for token-based rules.
  final Map<int, List<FilterRule>> tokenDispatchTable;

  /// Fallback rules that are not included in the token dispatch.
  final Set<FilterRule> fallbackRules;

  /// Cosmetic hide rules.
  final Map<String, List<CosmeticHideRule>> cosmeticHideRules;

  /// Cosmetic exception rules.
  final Map<String, List<CosmeticExceptionRule>> cosmeticExceptionRules;

  /// Scriptlets (JS injections, API mocks).
  final Map<String, List<ScriptletRule>> scriptletRules;

  /// Custom CSS injections.
  final Map<String, List<CssInjectRule>> cssInjectRules;
}
