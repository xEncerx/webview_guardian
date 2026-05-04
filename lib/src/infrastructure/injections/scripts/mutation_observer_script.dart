import 'dart:convert';

import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Generates a script that applies dynamic MutationObserver to hide dynamically loaded ads.
class MutationObserverScript implements InjectionScript {
  @override
  InjectionWorld get world => InjectionWorld.isolated;

  @override
  InjectionTiming get timing => InjectionTiming.atDocumentEnd;

  @override
  String? buildScript(String hostname, FilterRepository repo) {
    final rules = repo.getCosmeticRules(hostname);
    if (rules.isEmpty) return null;

    final selectors = rules.map((r) => r.selector).toList();
    final selectorsJson = jsonEncode(selectors);

    return '''
(function() {
  const rawSelectors = $selectorsJson;
  const validSelectors = [];
  
  for (let i = 0; i < rawSelectors.length; i++) {
    try {
      document.querySelector(rawSelectors[i]);
      validSelectors.push(rawSelectors[i]);
    } catch (e) {
      // Invalid selector, ignore
    }
  }
  
  if (validSelectors.length === 0) return;
  const selectors = validSelectors.join(', ');
  
  const hideElements = function() {
    const elements = document.querySelectorAll(selectors);
    for (let i = 0; i < elements.length; i++) {
      const el = elements[i];
      if (el.style.display !== 'none') {
        el.style.setProperty('display', 'none', 'important');
      }
    }
  };

  const observer = new MutationObserver((mutations) => {
    let shouldCheck = false;
    for (let i = 0; i < mutations.length; i++) {
      if (mutations[i].addedNodes.length > 0) {
        shouldCheck = true;
        break;
      }
    }
    if (shouldCheck) hideElements();
  });

  observer.observe(document.documentElement || document.body, {
    childList: true,
    subtree: true
  });

  hideElements();
})();
''';
  }
}
