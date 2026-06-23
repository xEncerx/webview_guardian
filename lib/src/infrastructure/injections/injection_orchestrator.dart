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
    CosmeticFilteringOptions cosmeticFilteringOptions = const CosmeticFilteringOptions(),
  }) : _observer = observer,
       _observabilityOptions = observabilityOptions,
       _cosmeticFilteringOptions = cosmeticFilteringOptions;

  final FilterRepository _repository;
  final WebViewObserver? _observer;
  final WebViewObservabilityOptions _observabilityOptions;
  final CosmeticFilteringOptions _cosmeticFilteringOptions;
  final CosmeticCSSScript _cosmeticCssScript = CosmeticCSSScript();
  final MutationObserverScript _mutationObserverScript = MutationObserverScript();
  final ScriptletInjectionScript _scriptletInjectionScript = ScriptletInjectionScript();

  /// Builds a list of [UserScript]s for the given hostname by aggregating all applicable [InjectionScript]s.
  List<UserScript> buildUserScripts(String hostname) {
    final userScripts = <UserScript>[];

    final cosmeticRuleSet = _repository.getCosmeticRuleSet(hostname);
    final cssRules = _cssRulesFor(cosmeticRuleSet);
    final observerRules = _observerRulesFor(cosmeticRuleSet);
    final cssSource = _cosmeticCssScript.buildScriptFromRules(cssRules);
    final observerSource = _mutationObserverScript.buildScriptFromRules(observerRules);
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
      final seenSelectors = <String>{};
      for (final rule in [...cssRules, ...observerRules]) {
        if (!seenSelectors.add(rule.selector)) continue;
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

  List<CosmeticHideRule> _cssRulesFor(CosmeticRuleSet ruleSet) {
    return switch (_cosmeticFilteringOptions.genericRuleMode) {
      GenericCosmeticRuleMode.off => ruleSet.domainSpecificRules,
      GenericCosmeticRuleMode.performance => [
        ...ruleSet.domainSpecificRules,
        ...ruleSet.genericRules.take(_cosmeticFilteringOptions.genericCssRuleLimit),
      ],
      GenericCosmeticRuleMode.full => ruleSet.allRules,
    };
  }

  List<CosmeticHideRule> _observerRulesFor(CosmeticRuleSet ruleSet) {
    return switch (_cosmeticFilteringOptions.genericRuleMode) {
      GenericCosmeticRuleMode.full => ruleSet.allRules,
      GenericCosmeticRuleMode.off ||
      GenericCosmeticRuleMode.performance => ruleSet.domainSpecificRules,
    };
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
