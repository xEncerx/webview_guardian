import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Orchestrates the building of UserScripts based on current host.
class InjectionOrchestrator {
  /// Creates an [InjectionOrchestrator] instance.
  InjectionOrchestrator(
    this._repository, {
    WebViewObserver? observer,
    WebViewObservabilityOptions observabilityOptions = const WebViewObservabilityOptions(),
  }) : _observer = observer,
       _observabilityOptions = observabilityOptions;

  final FilterRepository _repository;
  final WebViewObserver? _observer;
  final WebViewObservabilityOptions _observabilityOptions;
  final CosmeticCSSScript _cosmeticCssScript = CosmeticCSSScript();
  final MutationObserverScript _mutationObserverScript = MutationObserverScript();
  final ScriptletInjectionScript _scriptletInjectionScript = ScriptletInjectionScript();

  /// Builds a list of [UserScript]s for the given hostname by aggregating all applicable [InjectionScript]s.
  List<UserScript> buildUserScripts(String hostname) {
    final userScripts = <UserScript>[];

    final cosmeticRules = _repository.getCosmeticRules(hostname);
    final cssSource = _cosmeticCssScript.buildScriptFromRules(cosmeticRules);
    final observerSource = _mutationObserverScript.buildScriptFromRules(cosmeticRules);
    var cosmeticScriptBuilt = false;

    if (cssSource != null && cssSource.isNotEmpty) {
      userScripts.add(_buildUserScript(_cosmeticCssScript, cssSource));
      cosmeticScriptBuilt = true;
    }
    if (observerSource != null && observerSource.isNotEmpty) {
      userScripts.add(_buildUserScript(_mutationObserverScript, observerSource));
      cosmeticScriptBuilt = true;
    }

    if (cosmeticScriptBuilt && _observabilityOptions.emitCosmeticInjections) {
      for (final rule in cosmeticRules) {
        _observer?.onEvent(CosmeticCssInjected(hostname: hostname, selector: rule.selector));
      }
    }

    final scriptletResult = _scriptletInjectionScript.buildScriptFromRules(
      _repository.getScriptletRules(hostname),
    );
    if (scriptletResult != null && scriptletResult.source.isNotEmpty) {
      userScripts.add(_buildUserScript(_scriptletInjectionScript, scriptletResult.source));
      if (_observabilityOptions.emitScriptletInjections) {
        for (final rule in scriptletResult.injectedRules) {
          _observer?.onEvent(
            ScriptletInjected(hostname: hostname, scriptletName: rule.scriptletName),
          );
        }
      }
    }

    return userScripts;
  }

  UserScript _buildUserScript(InjectionScript script, String source) {
    return UserScript(
      source: source,
      injectionTime: switch (script.timing) {
        InjectionTiming.atDocumentStart => UserScriptInjectionTime.AT_DOCUMENT_START,
        InjectionTiming.atDocumentEnd => UserScriptInjectionTime.AT_DOCUMENT_END,
      },
      contentWorld: switch (script.world) {
        InjectionWorld.page => ContentWorld.DEFAULT_CLIENT,
        InjectionWorld.isolated => ContentWorld.world(name: 'Guardian'),
      },
    );
  }
}
