import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Generates IIFE strings from ScriptletLibrary for ScriptletRules.
class ScriptletInjectionScript implements InjectionScript {
  @override
  InjectionWorld get world => InjectionWorld.page; // Must run in page context

  @override
  InjectionTiming get timing => InjectionTiming.atDocumentStart;

  @override
  String? buildScript(String hostname, FilterRepository repo) {
    final rules = repo.getScriptletRules(hostname);
    final scriptlets = <String>[];

    for (final rule in rules) {
      final scriptletBody = ScriptletLibrary.instance.buildScript(rule.scriptletName, rule.args);
      if (scriptletBody != null && scriptletBody.isNotEmpty) {
        scriptlets.add(scriptletBody);
      }
    }

    if (scriptlets.isEmpty) return null;

    final buffer = StringBuffer()
      ..writeln('(function() {')
      ..writeln("'use strict';");

    scriptlets.forEach(buffer.writeln);

    buffer.writeln('})();');
    return buffer.toString();
  }
}
