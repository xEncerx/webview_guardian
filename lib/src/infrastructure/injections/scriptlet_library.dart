import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;

import 'package:meta/meta.dart';

/// Parses and manages a library of scriptlets (like uBO's scriptlets.js).
class ScriptletLibrary {
  ScriptletLibrary._();

  /// Singleton instance of the ScriptletLibrary.
  static final ScriptletLibrary instance = ScriptletLibrary._();

  final Map<String, String> _scriptlets = {};
  bool _isLoaded = false;

  /// Parses raw scriptlet code for testing purposes.
  @visibleForTesting
  void parseForTest(String raw) {
    _parse(raw);
    _isLoaded = true;
  }

  /// Clears the loaded scriptlets for testing purposes.
  @visibleForTesting
  void clearForTest() {
    _scriptlets.clear();
    _isLoaded = false;
  }

  /// Loads the scriptlet library from assets. Should be called during app initialization.
  Future<void> load() async {
    if (_isLoaded) return;
    try {
      final rawStr = await rootBundle.loadString('packages/webview_guardian/assets/scriptlets.js');
      _parse(rawStr);
      _isLoaded = true;
    } on Exception {
      // Ignore if not found, we just won't inject scriptlets.
    }
  }

  void _parse(String raw) {
    final lines = raw.split('\n');
    String? currentName;
    final aliases = <String>[];
    final buffer = StringBuffer();

    for (final line in lines) {
      if (line.startsWith('/// ')) {
        final name = line.substring(4).trim();
        if (name.startsWith('alias ')) {
          aliases.add(name.substring(6).trim());
        } else {
          // Save previous block
          if (currentName != null && buffer.isNotEmpty) {
            final body = buffer.toString().trim();
            _scriptlets[currentName] = body;
            for (final alias in aliases) {
              _scriptlets[alias] = body;
            }
          }

          currentName = name;
          aliases.clear();
          buffer.clear();
        }
      } else if (currentName != null &&
          !line.startsWith('// <<<<') &&
          !line.startsWith('// >>>>')) {
        buffer.writeln(line);
      }
    }

    // Save last block
    if (currentName != null && buffer.isNotEmpty) {
      final body = buffer.toString().trim();
      _scriptlets[currentName] = body;
      for (final alias in aliases) {
        _scriptlets[alias] = body;
      }
    }
  }

  /// Returns the raw scriptlet code, replacing {{1}}, {{2}} etc with arguments.
  String? buildScript(String name, List<String> args) {
    if (!_isLoaded) return null;

    final body = _scriptlets[name];
    if (body == null) return null;

    var injected = body;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      // Basic escaping to prevent breaking the JS syntax if the arg contains quotes.
      // uBO scriptlets expect single-quoted string context: const target = '{{1}}';
      // So we escape single quotes and backslashes.
      final escapedArg = arg.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      injected = injected.replaceAll('{{${i + 1}}}', escapedArg);
    }

    // Replace any remaining {{n}} with empty strings
    return injected.replaceAll(RegExp(r'\{\{\d+\}\}'), '');
  }
}
