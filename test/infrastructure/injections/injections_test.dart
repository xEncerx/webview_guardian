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
        when(() => mockRepo.getCosmeticRules('example.com')).thenReturn([
          const CosmeticHideRule(selector: '.dynamic-ad'),
        ]);

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
      orchestrator = InjectionOrchestrator(mockRepo);
      ScriptletLibrary.instance.clearForTest();
      ScriptletLibrary.instance.parseForTest('/// fake-scriptlet.js\nconsole.log();');
    });

    test('should build user scripts for valid rules', () {
      when(() => mockRepo.getCosmeticRules('example.com')).thenReturn([
        const CosmeticHideRule(selector: '.banner'),
      ]);
      when(() => mockRepo.getScriptletRules('example.com')).thenReturn([
        const ScriptletRule(scriptletName: 'fake-scriptlet.js'),
      ]);

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

    test('should return empty list if no rules are generated', () {
      when(() => mockRepo.getCosmeticRules('clean-site.com')).thenReturn([]);
      when(() => mockRepo.getScriptletRules('clean-site.com')).thenReturn([]);

      final userScripts = orchestrator.buildUserScripts('clean-site.com');
      expect(userScripts, isEmpty);
    });
  });
}
