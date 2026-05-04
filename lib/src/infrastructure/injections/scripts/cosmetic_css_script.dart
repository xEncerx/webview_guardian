import 'dart:convert';

import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Generates a script that injects CSS to hide elements via CosmeticHideRule.
class CosmeticCSSScript implements InjectionScript {
  @override
  InjectionWorld get world => InjectionWorld.isolated;

  // We inject at Document Start to prevent flicker, using DOMContentLoaded
  // or immediate style injection if head exists.
  @override
  InjectionTiming get timing => InjectionTiming.atDocumentStart;

  @override
  String? buildScript(String hostname, FilterRepository repo) {
    final rules = repo.getCosmeticRules(hostname);
    if (rules.isEmpty) return null;

    final cssRules = rules.map((r) => '${r.selector} { display: none !important; }').join(r'\n');
    final cssJson = jsonEncode(cssRules);

    // Create a style element and inject it into the head
    return '''
(function() {
  const css = $cssJson;
  const style = document.createElement('style');
  style.type = 'text/css';
  style.textContent = css;

  const inject = function() {
    if (document.head) {
      document.head.appendChild(style);
    } else if (document.documentElement) {
      document.documentElement.appendChild(style);
    } else {
      requestAnimationFrame(inject);
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
    // Also try immediately
    requestAnimationFrame(inject);
  } else {
    inject();
  }
})();
''';
  }
}
