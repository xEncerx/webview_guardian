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
    return buildScriptFromRules(repo.getScriptletRules(hostname))?.source;
  }

  /// Builds a scriptlet user script from already selected rules.
  ({String source, List<ScriptletRule> injectedRules})? buildScriptFromRules(
    List<ScriptletRule> rules,
  ) {
    final scriptlets = <String>[];
    final injectedRules = <ScriptletRule>[];

    for (final rule in rules) {
      final scriptletBody = ScriptletLibrary.instance.buildScript(rule.scriptletName, rule.args);
      if (scriptletBody != null && scriptletBody.isNotEmpty) {
        scriptlets.add(scriptletBody);
        injectedRules.add(rule);
      }
    }

    if (scriptlets.isEmpty) return null;

    final buffer = StringBuffer()
      ..writeln('(function() {')
      ..writeln("'use strict';");

    scriptlets.forEach(buffer.writeln);

    buffer.writeln('})();');
    return (source: buffer.toString(), injectedRules: injectedRules);
  }
}
