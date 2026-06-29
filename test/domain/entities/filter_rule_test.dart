import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';

void main() {
  group('FilterRule identity', () {
    test('network block and exception rules keep distinct identity', () {
      const blockRule = NetworkBlockRule(pattern: '||example.com^');
      const exceptionRule = NetworkExceptionRule(pattern: '||example.com^');

      expect(blockRule, isNot(exceptionRule));
      expect(blockRule.hashCode, isNot(exceptionRule.hashCode));
    });

    test('cosmetic hide and exception rules keep distinct identity', () {
      const hideRule = CosmeticHideRule(selector: '.ad', domains: ['example.com']);
      const exceptionRule = CosmeticExceptionRule(selector: '.ad', domains: ['example.com']);

      expect(hideRule, isNot(exceptionRule));
      expect(hideRule.hashCode, isNot(exceptionRule.hashCode));
    });
  });
}
