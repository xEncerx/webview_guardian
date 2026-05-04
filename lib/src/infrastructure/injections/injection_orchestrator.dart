import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Orchestrates the building of UserScripts based on current host.
class InjectionOrchestrator {
  /// Creates an [InjectionOrchestrator] instance.
  InjectionOrchestrator(this._repository);

  final FilterRepository _repository;
  final List<InjectionScript> _scripts = [
    CosmeticCSSScript(),
    MutationObserverScript(),
    ScriptletInjectionScript(),
  ];

  /// Builds a list of [UserScript]s for the given hostname by aggregating all applicable [InjectionScript]s.
  List<UserScript> buildUserScripts(String hostname) {
    final userScripts = <UserScript>[];

    for (final script in _scripts) {
      final source = script.buildScript(hostname, _repository);
      if (source != null && source.isNotEmpty) {
        userScripts.add(
          UserScript(
            source: source,
            injectionTime: switch (script.timing) {
              InjectionTiming.atDocumentStart => UserScriptInjectionTime.AT_DOCUMENT_START,
              InjectionTiming.atDocumentEnd => UserScriptInjectionTime.AT_DOCUMENT_END,
            },
            contentWorld: switch (script.world) {
              InjectionWorld.page => ContentWorld.DEFAULT_CLIENT,
              InjectionWorld.isolated => ContentWorld.world(name: 'Guardian'),
            },
          ),
        );
      }
    }

    return userScripts;
  }
}
