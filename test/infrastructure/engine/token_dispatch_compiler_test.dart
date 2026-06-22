import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';

int _encode(String value) {
  assert(value.length == 5, 'Only 5-character tokens can be encoded.');
  var token = 0;
  for (var i = 0; i < value.length; i++) {
    token = ((token << 8) | value.codeUnitAt(i)) & 0xFFFFFFFFFF;
  }
  return token;
}

void main() {
  group('TokenDispatchCompiler.compile', () {
    test('buckets network rules by least frequent token and preserves fallbacks', () {
      const rareRule = NetworkBlockRule(pattern: 'common-rarex');
      const commonRule = NetworkExceptionRule(pattern: 'common');
      const noTokenRule = NetworkBlockRule(pattern: 'abcd');
      const cosmeticRule = CosmeticHideRule(selector: '.ad');

      final compiled = TokenDispatchCompiler.compile([
        rareRule,
        commonRule,
        noTokenRule,
        cosmeticRule,
      ]);

      expect(compiled.table[_encode('rarex')], [rareRule]);
      expect(compiled.table[_encode('commo')], [commonRule]);
      expect(compiled.fallbackRules, {noTokenRule});
      expect(
        compiled.table.values.expand((rules) => rules),
        isNot(contains(cosmeticRule)),
      );
      expect(compiled.fallbackRules, isNot(contains(cosmeticRule)));
    });
  });
}
