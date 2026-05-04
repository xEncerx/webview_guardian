import 'dart:collection';
import 'dart:typed_data';

import 'package:webview_guardian/src/domain/domain.dart';

/// A trie-based compiler for hostname-based filter rules.
class RawTrieNode {
  /// Maps ASCII character codes to child nodes. Only valid hostname characters are expected.
  final children = HashMap<int, RawTrieNode>();

  /// List of filter rules that match at this node (i.e., for the hostname represented by the path to this node).
  final rules = <FilterRule>[];
}

/// Compiles hostname-based filter rules into a trie structure for matching.
class HostnameTrieCompiler {
  /// The root of the trie. Each path from the root to a node represents a reversed hostname pattern.
  final root = RawTrieNode();

  /// Attempts to add a filter rule to the trie.
  ///
  /// Returns true if the rule was successfully added, false if it was invalid.
  bool tryAddRule(FilterRule rule) {
    final pattern = switch (rule) {
      final NetworkBlockRule r => r.pattern,
      final NetworkExceptionRule r => r.pattern,
      _ => null,
    };

    if (pattern == null) return false;

    final len = pattern.length;
    // Checks for "||" prefix and minimum length of 3 (to allow at least one character after "||")
    if (len < 3 || pattern.codeUnitAt(0) != 124 || pattern.codeUnitAt(1) != 124) {
      return false;
    }

    const start = 2;
    var end = len - 1;

    // Check for optional "^" suffix and adjust end index accordingly
    if (pattern.codeUnitAt(end) == 94) end--;

    // Validate that the pattern does not contain '*', '/', or ':'
    for (var i = start; i <= end; i++) {
      final char = pattern.codeUnitAt(i);
      if (char > 0xFF || char == 42 || char == 47 || char == 58) {
        return false;
      }
    }

    // Insert the rule into the trie in reverse order (from end to start)
    var current = root;
    for (var i = end; i >= start; i--) {
      final char = pattern.codeUnitAt(i);
      current = current.children.putIfAbsent(char, RawTrieNode.new);
    }

    current.rules.add(rule);

    return true;
  }
}

/// The result of compiling the hostname trie, represented as a record containing a buffer and a list of rules.
typedef CompiledTrie = ({Uint32List buffer, List<FilterRule> rules});

/// Extension method to convert the raw trie structure into a compact buffer.
extension TrieFlattener on HostnameTrieCompiler {
  /// Compiles the raw object-based Trie into a flat memory buffer.
  CompiledTrie build() {
    final builder = _Uint32Builder();
    final rules = <FilterRule>[];

    _writeNode(root, builder, rules);

    return (
      buffer: builder.toBytes(),
      rules: rules,
    );
  }

  /// Recursively writes the node into the buffer using DFS.
  ///
  /// Returns the offset index where the node was written.
  int _writeNode(RawTrieNode node, _Uint32Builder builder, List<FilterRule> rulesList) {
    final offset = builder.length;
    final childCount = node.children.length;
    final ruleCount = node.rules.length;

    if (childCount > 0xFFFF) {
      throw StateError('Exceeded maximum children per node (65535).');
    }
    if (ruleCount > 0xFFFF) {
      throw StateError('Exceeded maximum rules per node (65535).');
    }

    builder.add((childCount << 16) | ruleCount);

    if (ruleCount > 0) {
      builder.add(rulesList.length);
      rulesList.addAll(node.rules);
    }

    final childrenStart = builder.length;
    for (var i = 0; i < childCount; i++) {
      builder.add(0);
    }

    final sortedEntries = node.children.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));

    for (var i = 0; i < childCount; i++) {
      final entry = sortedEntries[i];
      final charCode = entry.key;

      if (charCode > 0xFF) {
        throw StateError('Character code exceeds 8-bit limit: $charCode');
      }

      // DFS: write child and get its memory offset
      final childOffset = _writeNode(entry.value, builder, rulesList);

      if (childOffset > 0xFFFFFF) {
        throw StateError('Trie buffer exceeded maximum offset size of 16M words.');
      }

      // Pack the charCode and offset into a single 32-bit word
      builder.set(childrenStart + i, (charCode << 24) | childOffset);
    }

    return offset;
  }
}

/// A zero-allocation builder for Uint32List that doubles capacity instead of reallocating on every add.
class _Uint32Builder {
  _Uint32Builder([int initialCapacity = 1024 * 1024]) : _buffer = Uint32List(initialCapacity);

  Uint32List _buffer;
  int _length = 0;

  void add(int value) {
    if (_length == _buffer.length) {
      final newBuffer = Uint32List(_buffer.length * 2)..setRange(0, _buffer.length, _buffer);
      _buffer = newBuffer;
    }
    _buffer[_length++] = value;
  }

  void set(int index, int value) {
    _buffer[index] = value;
  }

  int get length => _length;

  Uint32List toBytes() {
    return Uint32List.sublistView(_buffer, 0, _length);
  }
}
