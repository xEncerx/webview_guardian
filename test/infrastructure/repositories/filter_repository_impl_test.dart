import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

void main() {
  group('FilterRepositoryImpl cosmetic rules', () {
    FilterRepositoryImpl repositoryFor({
      required Map<String, List<CosmeticHideRule>> hideRules,
      Map<String, List<CosmeticExceptionRule>> exceptionRules = const {},
    }) {
      final engineRef = FilterEngineRef(
        CompiledFilterEngine(
          totalRules:
              hideRules.values.fold<int>(0, (sum, rules) => sum + rules.length) +
              exceptionRules.values.fold<int>(0, (sum, rules) => sum + rules.length),
          trieBuffer: Uint32List(1),
          trieRules: const [],
          tokenDispatchTable: const {},
          fallbackRules: const {},
          cosmeticHideRules: hideRules,
          cosmeticExceptionRules: exceptionRules,
          scriptletRules: const {},
          cssInjectRules: const {},
        ),
      );

      return FilterRepositoryImpl(
        matcher: FilterMatcher(engineRef),
        engineRef: engineRef,
        observer: null,
      );
    }

    test('does not return hide rules excluded for the hostname or its parent', () {
      const rule = CosmeticHideRule(
        selector: '.ad',
        includeDomains: ['example.com'],
        excludeDomains: ['sub.example.com'],
      );
      final repository = repositoryFor(
        hideRules: {
          'example.com': [rule],
        },
      );

      expect(repository.getCosmeticRules('example.com'), [rule]);
      expect(repository.getCosmeticRules('sub.example.com'), isEmpty);
      expect(repository.getCosmeticRules('deep.sub.example.com'), isEmpty);
    });

    test('does not apply excluded exception rules to suppress hide rules', () {
      const hideRule = CosmeticHideRule(selector: '.ad');
      const exceptionRule = CosmeticExceptionRule(
        selector: '.ad',
        includeDomains: ['example.com'],
        excludeDomains: ['sub.example.com'],
      );
      final repository = repositoryFor(
        hideRules: {
          '*': [hideRule],
        },
        exceptionRules: {
          'example.com': [exceptionRule],
        },
      );

      expect(repository.getCosmeticRules('example.com'), isEmpty);
      expect(repository.getCosmeticRules('sub.example.com'), [hideRule]);
    });
  });
}
