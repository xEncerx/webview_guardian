import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/injections/injections.dart';

class MockFilterRepository extends Mock implements FilterRepository {}

void main() {
  group('ScriptletLibrary', () {
    setUp(ScriptletLibrary.instance.clearForTest);

    test('should parse scriptlets correctly and handle aliases', () {
      const raw = '''
/// test-scriptlet.js
/// alias ts.js
(function() {
  const arg1 = '{{1}}';
  const arg2 = '{{2}}';
  console.log(arg1, arg2);
})();

/// another-scriptlet.js
(function() {
  console.log('hello');
})();
''';
      ScriptletLibrary.instance.parseForTest(raw);

      final script1 = ScriptletLibrary.instance.buildScript('test-scriptlet.js', ['val1', 'val2']);
      expect(script1, contains("const arg1 = 'val1';"));
      expect(script1, contains("const arg2 = 'val2';"));

      final scriptAlias = ScriptletLibrary.instance.buildScript('ts.js', ['val1', 'val2']);
      expect(scriptAlias, equals(script1));

      final script2 = ScriptletLibrary.instance.buildScript('another-scriptlet.js', []);
      expect(script2, contains("console.log('hello');"));
    });

    test('should properly escape string arguments', () {
      const raw = '''
/// test-escape.js
const val = '{{1}}';
''';
      ScriptletLibrary.instance.parseForTest(raw);

      final script = ScriptletLibrary.instance.buildScript('test-escape.js', [r"don't break\it"]);
      expect(script, contains(r"const val = 'don\'t break\\it';"));
    });

    test('should remove remaining {{n}} tokens if fewer arguments are provided', () {
      const raw = '''
/// test-missing.js
const val1 = '{{1}}';
const val2 = '{{2}}';
''';
      ScriptletLibrary.instance.parseForTest(raw);

      final script = ScriptletLibrary.instance.buildScript('test-missing.js', ['val1']);
      expect(script, contains("const val1 = 'val1';"));
      expect(script, contains("const val2 = '';"));
    });

    test('should return null if scriptlet does not exist', () {
      ScriptletLibrary.instance.parseForTest('/// existing.js\nconsole.log(1);');
      expect(ScriptletLibrary.instance.buildScript('not-existing.js', []), isNull);
    });
  });

  group('InjectionScript implementations', () {
    late MockFilterRepository mockRepo;

    setUp(() {
      mockRepo = MockFilterRepository();
    });

    group('CosmeticCSSScript', () {
      final script = CosmeticCSSScript();

      test('should return null if no rules exist', () {
        when(() => mockRepo.getCosmeticRules('example.com')).thenReturn([]);
        expect(script.buildScript('example.com', mockRepo), isNull);
      });

      test('should build a valid style injection script with correct selectors', () {
        when(() => mockRepo.getCosmeticRules('example.com')).thenReturn([
          const CosmeticHideRule(selector: '.ad-banner'),
          const CosmeticHideRule(selector: '#sponsored'),
        ]);

        final result = script.buildScript('example.com', mockRepo);
        expect(result, isNotNull);
        expect(
          result,
          contains(
            r'".ad-banner { display: none !important; }\\n#sponsored { display: none !important; }"',
          ),
        );
        expect(result, contains("document.createElement('style')"));
        expect(result, contains('appendChild(style)'));
      });

      test('JSON-encodes quotes and backslashes in ready-to-inject CSS', () {
        final result = script.buildScriptFromCss(r'body::before { content: "C:\path"; }');

        expect(result, contains(r'const css = "body::before { content: \"C:\\path\"; }";'));
      });

      test('has proper timing and world', () {
        expect(script.timing, InjectionTiming.atDocumentStart);
        expect(script.world, InjectionWorld.isolated);
      });
    });

    group('MutationObserverScript', () {
      final script = MutationObserverScript();

      test('should return null if no rules exist', () {
        when(() => mockRepo.getCosmeticRules('example.com')).thenReturn([]);
        expect(script.buildScript('example.com', mockRepo), isNull);
      });

      test('should build a valid mutation observer script', () {
        when(
          () => mockRepo.getCosmeticRules('example.com'),
        ).thenReturn([const CosmeticHideRule(selector: '.dynamic-ad')]);

        final result = script.buildScript('example.com', mockRepo);
        expect(result, isNotNull);
        expect(result, contains('const rawSelectors = [".dynamic-ad"];'));
        expect(result, contains('new MutationObserver'));
        expect(result, contains("style.setProperty('display', 'none', 'important')"));
      });

      test('has proper timing and world', () {
        expect(script.timing, InjectionTiming.atDocumentEnd);
        expect(script.world, InjectionWorld.isolated);
      });
    });

    group('ScriptletInjectionScript', () {
      final script = ScriptletInjectionScript();

      setUp(() {
        ScriptletLibrary.instance.clearForTest();
        ScriptletLibrary.instance.parseForTest('/// block-ga.js\nconsole.log("ga-blocked {{1}}");');
      });

      test('should return null if no scriptlet rules exist', () {
        when(() => mockRepo.getScriptletRules('example.com')).thenReturn([]);
        expect(script.buildScript('example.com', mockRepo), isNull);
      });

      test('should build an IIFE wrapping the specific scriptlet', () {
        when(() => mockRepo.getScriptletRules('example.com')).thenReturn([
          const ScriptletRule(scriptletName: 'block-ga.js', args: ['arg1']),
        ]);

        final result = script.buildScript('example.com', mockRepo);
        expect(result, isNotNull);
        expect(result, contains('(function() {'));
        expect(result, contains("'use strict';"));
        expect(result, contains('console.log("ga-blocked arg1");'));
      });

      test('has proper timing and world', () {
        expect(script.timing, InjectionTiming.atDocumentStart);
        expect(script.world, InjectionWorld.page);
      });
    });
  });

  group('InjectionOrchestrator', () {
    late MockFilterRepository mockRepo;
    late InjectionOrchestrator orchestrator;

    setUp(() {
      mockRepo = MockFilterRepository();
      when(() => mockRepo.getCssInjectRules(any())).thenReturn([]);
      orchestrator = InjectionOrchestrator(mockRepo);
      ScriptletLibrary.instance.clearForTest();
      ScriptletLibrary.instance.parseForTest('/// fake-scriptlet.js\nconsole.log();');
    });

    test('default mode caps generic CSS rules and keeps all domain-specific rules', () {
      final genericRules = List.generate(
        CosmeticFilteringOptions.defaultGenericCssRuleLimit + 1,
        (index) => CosmeticHideRule(selector: '.generic-$index'),
      );
      const domainRule = CosmeticHideRule(selector: '.domain-ad');
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        CosmeticRuleSet(domainSpecificRules: const [domainRule], genericRules: genericRules),
      );
      when(() => mockRepo.getScriptletRules('example.com')).thenReturn([]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      final cssSource = userScripts.singleWhere((script) {
        return script.injectionTime == UserScriptInjectionTime.AT_DOCUMENT_START;
      }).source;
      expect(cssSource, contains('.domain-ad { display: none !important; }'));
      expect(cssSource, contains('.generic-0 { display: none !important; }'));
      expect(cssSource, contains('.generic-2999 { display: none !important; }'));
      expect(cssSource, isNot(contains('.generic-3000 { display: none !important; }')));
    });

    test('default mode excludes generic rules from MutationObserver', () {
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(
          domainSpecificRules: [CosmeticHideRule(selector: '.domain-ad')],
          genericRules: [CosmeticHideRule(selector: 'a[href^="http://olivka.biz/"]')],
        ),
      );
      when(() => mockRepo.getScriptletRules('example.com')).thenReturn([]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      final observerSource = userScripts.singleWhere((script) {
        return script.injectionTime == UserScriptInjectionTime.AT_DOCUMENT_END;
      }).source;
      expect(observerSource, contains('.domain-ad'));
      expect(observerSource, isNot(contains('olivka.biz')));
    });

    test('full mode includes all generic rules in CSS and MutationObserver', () {
      orchestrator = InjectionOrchestrator(
        mockRepo,
        cosmeticFilteringOptions: const CosmeticFilteringOptions(
          genericRuleMode: GenericCosmeticRuleMode.full,
        ),
      );
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(
          domainSpecificRules: [CosmeticHideRule(selector: '.domain-ad')],
          genericRules: [CosmeticHideRule(selector: '.generic-ad')],
        ),
      );
      when(() => mockRepo.getScriptletRules('example.com')).thenReturn([]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      final sources = userScripts.map((script) => script.source).join('\n');
      expect(sources, contains('.domain-ad'));
      expect(sources, contains('.generic-ad { display: none !important; }'));
      expect(sources, contains('const rawSelectors = [".domain-ad",".generic-ad"];'));
    });

    test('off mode excludes generic rules and keeps domain-specific rules', () {
      orchestrator = InjectionOrchestrator(
        mockRepo,
        cosmeticFilteringOptions: const CosmeticFilteringOptions(
          genericRuleMode: GenericCosmeticRuleMode.off,
        ),
      );
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(
          domainSpecificRules: [CosmeticHideRule(selector: '.domain-ad')],
          genericRules: [CosmeticHideRule(selector: '.generic-ad')],
        ),
      );
      when(() => mockRepo.getScriptletRules('example.com')).thenReturn([]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      final sources = userScripts.map((script) => script.source).join('\n');
      expect(sources, contains('.domain-ad'));
      expect(sources, isNot(contains('.generic-ad')));
    });

    test('should build user scripts for valid rules', () {
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(domainSpecificRules: [CosmeticHideRule(selector: '.banner')]),
      );
      when(
        () => mockRepo.getScriptletRules('example.com'),
      ).thenReturn([const ScriptletRule(scriptletName: 'fake-scriptlet.js')]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      expect(userScripts.length, 3); // CSS, MutationObserver, Scriptlet

      final cssScript = userScripts[0];
      expect(cssScript.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(cssScript.contentWorld.name, 'Guardian');

      final observerScript = userScripts[1];
      expect(observerScript.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_END);
      expect(observerScript.contentWorld.name, 'Guardian');

      final scriptletScript = userScripts[2];
      expect(scriptletScript.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
      expect(scriptletScript.contentWorld, ContentWorld.DEFAULT_CLIENT);
    });

    test('combines cosmetic hides and raw CSS injection without wrapping injected CSS', () {
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(domainSpecificRules: [CosmeticHideRule(selector: '.banner')]),
      );
      when(
        () => mockRepo.getCssInjectRules('example.com'),
      ).thenReturn([const CssInjectRule(css: 'body { overflow: auto !important; }')]);
      when(() => mockRepo.getScriptletRules('example.com')).thenReturn([]);

      final documentStartScripts = orchestrator
          .buildUserScripts('example.com')
          .where((script) => script.injectionTime == UserScriptInjectionTime.AT_DOCUMENT_START)
          .toList();

      expect(documentStartScripts, hasLength(1));
      expect(documentStartScripts.single.source, contains('.banner { display: none !important; }'));
      expect(documentStartScripts.single.source, contains('body { overflow: auto !important; }'));
      expect(
        documentStartScripts.single.source,
        isNot(contains('body { overflow: auto !important; } { display: none !important; }')),
      );
    });

    test('emits injection events for built user scripts without duplicating cosmetic rules', () {
      final observer = _RecordingObserver();
      orchestrator = InjectionOrchestrator(mockRepo, observer: observer);
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(domainSpecificRules: [CosmeticHideRule(selector: '.banner')]),
      );
      when(
        () => mockRepo.getScriptletRules('example.com'),
      ).thenReturn([const ScriptletRule(scriptletName: 'fake-scriptlet.js')]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      expect(userScripts.length, 3);
      final cosmeticEvents = observer.events.whereType<CosmeticCssInjected>();
      expect(cosmeticEvents, hasLength(1));
      expect(cosmeticEvents.single.selector, '.banner');
      final scriptletEvents = observer.events.whereType<ScriptletInjected>();
      expect(scriptletEvents, hasLength(1));
      expect(scriptletEvents.single.scriptletName, 'fake-scriptlet.js');
    });

    test('respects disabled injection event options when user scripts are built', () {
      final observer = _RecordingObserver();
      orchestrator = InjectionOrchestrator(
        mockRepo,
        observer: observer,
        observabilityOptions: const WebViewObservabilityOptions(
          emitCosmeticInjections: false,
          emitScriptletInjections: false,
        ),
      );
      when(() => mockRepo.getCosmeticRuleSet('example.com')).thenReturn(
        const CosmeticRuleSet(domainSpecificRules: [CosmeticHideRule(selector: '.banner')]),
      );
      when(
        () => mockRepo.getScriptletRules('example.com'),
      ).thenReturn([const ScriptletRule(scriptletName: 'fake-scriptlet.js')]);

      final userScripts = orchestrator.buildUserScripts('example.com');

      expect(userScripts.length, 3);
      expect(observer.events.whereType<CosmeticCssInjected>(), isEmpty);
      expect(observer.events.whereType<ScriptletInjected>(), isEmpty);
    });

    test('should return empty list if no rules are generated', () {
      when(() => mockRepo.getCosmeticRuleSet('clean-site.com')).thenReturn(const CosmeticRuleSet());
      when(() => mockRepo.getScriptletRules('clean-site.com')).thenReturn([]);

      final userScripts = orchestrator.buildUserScripts('clean-site.com');
      expect(userScripts, isEmpty);
    });
  });
}

final class _RecordingObserver implements WebViewObserver {
  final events = <WebViewEvent>[];
  final errors = <WebViewError>[];

  @override
  void onEvent(WebViewEvent event) => events.add(event);

  @override
  void onError(WebViewError error) => errors.add(error);
}
