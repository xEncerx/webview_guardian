import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/extensions/extensions.dart';

/// Helper function to encode a 5-character string into a 40-bit integer
/// for readable test assertions.
int _encode(String s) {
  assert(s.length == 5, 'Only 5-character strings can be encoded into a single token.');
  var token = 0;
  for (var i = 0; i < 5; i++) {
    token = ((token << 8) | s.codeUnitAt(i)) & 0xFFFFFFFFFF;
  }
  return token;
}

void main() {
  group('TokenExtractor.extractTokensAsInt', () {
    test('extracts correct overlapping tokens from a standard string', () {
      final tokens = 'abcdef'.extractTokensAsInt();

      expect(tokens.length, 2);
      expect(tokens, contains(_encode('abcde')));
      expect(tokens, contains(_encode('bcdef')));
    });

    test('returns empty set when string is shorter than 5 characters', () {
      final tokens = 'abcd'.extractTokensAsInt();

      expect(tokens, isEmpty);
    });

    test('converts uppercase characters to lowercase automatically', () {
      final tokens = 'AdBan'.extractTokensAsInt();

      expect(tokens.length, 1);
      expect(tokens, contains(_encode('adban')));
    });

    test('prevents duplicate tokens in the resulting set', () {
      // "aaaaaa" -> "aaaaa" and "aaaaa"
      final tokens = 'aaaaaa'.extractTokensAsInt();

      expect(tokens.length, 1);
      expect(tokens, contains(_encode('aaaaa')));
    });

    test('resets sequence counter on non-alphanumeric characters', () {
      // The dot should break the sequence. "abcd" is 4 chars (ignored).
      // "efghi" is 5 chars (valid).
      final tokens = 'abcd.efghi'.extractTokensAsInt();

      expect(tokens.length, 1);
      expect(tokens, contains(_encode('efghi')));
    });

    test('handles complex urls with multiple separators and duplicates', () {
      final tokens = 'https://ads.google.com/ads.js'.extractTokensAsInt();

      expect(
        tokens,
        containsAll([
          _encode('https'),
          _encode('googl'),
          _encode('oogle'),
        ]),
      );
      // Should not contain anything crossing the dots or slashes
      expect(tokens.contains(_encode('sgoog')), isFalse);
      // Should handle the duplicate 'ads' gracefully (though 'ads.js' is only 3+2 chars,
      // so neither 'ads' yields a token here. 'https' and 'google' are the only ones).
    });
  });

  group('TokenExtractor.anyTokenMatches', () {
    test('iterates through all valid tokens if callback returns false', () {
      final seenTokens = <int>[];

      final result = 'abcdef'.anyTokenMatches((token) {
        seenTokens.add(token);
        return false;
      });

      expect(result, isFalse);
      expect(seenTokens.length, 2);
      expect(seenTokens[0], _encode('abcde'));
      expect(seenTokens[1], _encode('bcdef'));
    });

    test('short-circuits and stops iteration immediately when callback returns true', () {
      var iterations = 0;

      final result = 'abcdef'.anyTokenMatches((token) {
        iterations++;
        // Short-circuit on the first token ('abcde')
        return true;
      });

      expect(result, isTrue);
      expect(iterations, 1); // Should not evaluate 'bcdef'
    });

    test('returns false immediately without executing callback if string is too short', () {
      var callbackExecuted = false;

      final result = 'abc'.anyTokenMatches((token) {
        callbackExecuted = true;
        return true;
      });

      expect(result, isFalse);
      expect(callbackExecuted, isFalse);
    });

    test('handles case insensitivity during on-the-fly iteration', () {
      int? capturedToken;

      final result = 'ExAmP'.anyTokenMatches((token) {
        capturedToken = token;
        return true;
      });

      expect(result, isTrue);
      expect(capturedToken, _encode('examp'));
    });

    test('skips tokens broken by special characters during iteration', () {
      final seenTokens = <int>[];

      // "1234-56789" -> "1234" is dropped, "56789" is valid.
      final result = '1234-56789'.anyTokenMatches((token) {
        seenTokens.add(token);
        return false;
      });

      expect(result, isFalse);
      expect(seenTokens.length, 1);
      expect(seenTokens.first, _encode('56789'));
    });
  });
}
