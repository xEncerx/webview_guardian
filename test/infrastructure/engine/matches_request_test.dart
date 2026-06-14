import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';

NetworkRequest _req(
  String url, {
  String sourceUrl = 'https://example.com',
  ResourceType resourceType = ResourceType.document,
}) {
  final uri = Uri.parse(url);
  return NetworkRequest(
    url: uri.toString(),
    host: uri.host,
    sourceHost: Uri.parse(sourceUrl).host,
    resourceType: resourceType,
  );
}

NetworkBlockRule _block(
  String pattern, {
  Set<ResourceType>? resourceTypes,
  bool isThirdPartyOnly = false,
  Set<String>? includeDomains,
  Set<String>? excludeDomains,
}) {
  return NetworkBlockRule(
    pattern: pattern,
    resourceTypes: resourceTypes ?? const {},
    isThirdPartyOnly: isThirdPartyOnly,
    includeDomains: includeDomains ?? const {},
    excludeDomains: excludeDomains ?? const {},
  );
}

NetworkExceptionRule _exception(String pattern) {
  return NetworkExceptionRule(
    pattern: pattern,
    includeDomains: const {},
    excludeDomains: const {},
  );
}

void main() {
  group('FilterRuleMatcher base rule types', () {
    test('should match NetworkBlockRule', () {
      final rule = _block('banner');
      expect(rule.matchesRequest(_req('https://example.com/banner.jpg')), isTrue);
    });

    test('should match NetworkExceptionRule', () {
      final rule = _exception('banner');
      expect(rule.matchesRequest(_req('https://example.com/banner.jpg')), isTrue);
    });

    test('should always return false for CosmeticHideRule', () {
      const rule = CosmeticHideRule(selector: '.ad');
      expect(rule.matchesRequest(_req('https://example.com/')), isFalse);
    });

    test('should always return false for ScriptletRule', () {
      const rule = ScriptletRule(scriptletName: 'test');
      expect(rule.matchesRequest(_req('https://example.com/')), isFalse);
    });

    test('should always return false for CssInjectRule', () {
      const rule = CssInjectRule(domain: 'example.com', css: 'body { display: none; }');
      expect(rule.matchesRequest(_req('https://example.com/')), isFalse);
    });
  });

  group('FilterRuleMatcher network parameters', () {
    test('should drop when resource types do not match', () {
      final rule = _block('banner', resourceTypes: {ResourceType.script, ResourceType.image});

      expect(
        rule.matchesRequest(_req('https://test.com/banner', resourceType: ResourceType.image)),
        isTrue,
      );
      expect(rule.matchesRequest(_req('https://test.com/banner')), isFalse);
    });

    test('should drop when third-party modifier requires third-party request', () {
      final rule = _block('banner', isThirdPartyOnly: true);

      expect(
        rule.matchesRequest(_req('https://ads.com/banner')),
        isTrue,
      );

      expect(
        rule.matchesRequest(_req('https://example.com/banner')),
        isFalse,
      );
    });

    test('should drop when domain is not in includeDomains', () {
      final rule = _block('banner', includeDomains: {'target.com', 'test.com'});

      expect(
        rule.matchesRequest(_req('https://ads.com/banner', sourceUrl: 'https://test.com')),
        isTrue,
      );
      expect(
        rule.matchesRequest(_req('https://ads.com/banner', sourceUrl: 'https://sub.test.com')),
        isTrue,
      );
      expect(
        rule.matchesRequest(_req('https://ads.com/banner', sourceUrl: 'https://other.com')),
        isFalse,
      );
    });

    test('should drop when domain is in excludeDomains', () {
      final rule = _block('banner', excludeDomains: {'excluded.com'});

      expect(
        rule.matchesRequest(_req('https://ads.com/banner', sourceUrl: 'https://other.com')),
        isTrue,
      );
      expect(
        rule.matchesRequest(_req('https://ads.com/banner', sourceUrl: 'https://excluded.com')),
        isFalse,
      );
      expect(
        rule.matchesRequest(_req('https://ads.com/banner', sourceUrl: 'https://sub.excluded.com')),
        isFalse,
      );
    });
  });

  group('FilterRuleMatcher ADP syntax matching', () {
    test('should match simple substring', () {
      final rule = _block('ad-banner');
      expect(rule.matchesRequest(_req('https://test.com/ad-banner.jpg')), isTrue);
      expect(rule.matchesRequest(_req('https://test.com/ad-image.jpg')), isFalse);
    });

    test('should match exact start anchor (|)', () {
      final rule = _block('|https://example.com');
      expect(rule.matchesRequest(_req('https://example.com/ad')), isTrue);
      expect(rule.matchesRequest(_req('http://example.com/ad')), isFalse);
      expect(rule.matchesRequest(_req('https://test.com/?url=https://example.com')), isFalse);
    });

    test('should match exact end anchor (|)', () {
      final rule = _block('banner.gif|');
      expect(rule.matchesRequest(_req('https://test.com/banner.gif')), isTrue);
      expect(rule.matchesRequest(_req('https://test.com/banner.gif?q=1')), isFalse);
    });

    test('should match exact boundary anchor (|pattern|)', () {
      final rule = _block('|https://example.com/|');
      expect(rule.matchesRequest(_req('https://example.com/')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com/index.html')), isFalse);
    });

    test('should match domain anchor (||)', () {
      final rule = _block('||ads.example.com');
      expect(rule.matchesRequest(_req('http://ads.example.com/banner')), isTrue);
      expect(rule.matchesRequest(_req('https://ads.example.com/banner')), isTrue);
      expect(rule.matchesRequest(_req('https://sub.ads.example.com/banner')), isTrue);

      expect(rule.matchesRequest(_req('https://notads.example.com/banner')), isFalse);
      expect(rule.matchesRequest(_req('https://example.com/banner')), isFalse);
    });

    test('should restrict domain anchor matching to the request authority', () {
      final rule = _block('||example.com^');

      expect(rule.matchesRequest(_req('https://example.com/ad.js')), isTrue);
      expect(rule.matchesRequest(_req('https://sub.example.com/ad.js')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com:8080/ad.js')), isTrue);
      expect(rule.matchesRequest(_req('https://user:pass@example.com/ad.js')), isTrue);

      expect(rule.matchesRequest(_req('https://site.test?u=sub.example.com')), isFalse);
      expect(rule.matchesRequest(_req('https://site.test#u=sub.example.com')), isFalse);
      expect(rule.matchesRequest(_req('https://sub.example.com@site.test/ad.js')), isFalse);
    });

    test('should match domain anchor with path (||)', () {
      final rule = _block('||example.com/ads/');
      expect(rule.matchesRequest(_req('https://example.com/ads/banner.jpg')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com/images/banner.jpg')), isFalse);
    });

    test('should match separator (^)', () {
      final rule = _block('example.com^');

      expect(rule.matchesRequest(_req('https://example.com/ad')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com:8080/ad')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com?track=1')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com')), isTrue);

      expect(rule.matchesRequest(_req('https://example.company.com')), isFalse);
      expect(rule.matchesRequest(_req('https://example.com1.com')), isFalse);
    });

    test('should match wildcards (*)', () {
      final rule = _block('ad/*/*.jpg');
      expect(rule.matchesRequest(_req('https://test.com/ad/123/banner.jpg')), isTrue);
      expect(rule.matchesRequest(_req('https://test.com/ad/nested/path/image.jpg')), isTrue);

      expect(rule.matchesRequest(_req('https://test.com/ad/banner.jpg')), isFalse);
      expect(rule.matchesRequest(_req('https://test.com/ad/123/banner.png')), isFalse);
    });

    test('should match complex pattern with wildcards and anchors', () {
      final rule = _block('||example.com/ad/*^banner|');
      expect(rule.matchesRequest(_req('https://example.com/ad/123/test?banner')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com/ad/123/test?banner=1')), isFalse);
    });

    test('should match regular expressions (/.../)', () {
      final rule = _block(r'/banner\d+\.jpg/');
      expect(rule.matchesRequest(_req('https://test.com/banner123.jpg')), isTrue);
      expect(rule.matchesRequest(_req('https://test.com/banner.jpg')), isFalse);
    });
  });

  group('FilterRuleMatcher complex edge cases', () {
    test('should respect mixed include and exclude domains correctly', () {
      final rule = _block(
        'analytics.js',
        includeDomains: {'example.com', 'test.com'},
        excludeDomains: {'sub.example.com', 'safe.test.com'},
      );

      expect(
        rule.matchesRequest(
          _req('https://tracker.com/analytics.js'),
        ),
        isTrue,
      );
      expect(
        rule.matchesRequest(
          _req('https://tracker.com/analytics.js', sourceUrl: 'https://sub.example.com'),
        ),
        isFalse,
      );
      expect(
        rule.matchesRequest(
          _req('https://tracker.com/analytics.js', sourceUrl: 'https://safe.test.com'),
        ),
        isFalse,
      );
      expect(
        rule.matchesRequest(
          _req('https://tracker.com/analytics.js', sourceUrl: 'https://other.com'),
        ),
        isFalse,
      );
    });

    test('should respect exclude domains when no include domains are provided', () {
      final rule = _block('popups.js', excludeDomains: {'trusted.com'});

      expect(
        rule.matchesRequest(_req('https://ads.com/popups.js', sourceUrl: 'https://random.com')),
        isTrue,
      );
      expect(
        rule.matchesRequest(_req('https://ads.com/popups.js', sourceUrl: 'https://trusted.com')),
        isFalse,
      );
      expect(
        rule.matchesRequest(
          _req('https://ads.com/popups.js', sourceUrl: 'https://sub.trusted.com'),
        ),
        isFalse,
      );
    });

    test('should match strict sub-resource paths ignoring false prefix hits', () {
      final rule = _block('/api/ads^');

      expect(rule.matchesRequest(_req('https://example.com/api/ads?id=1')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com/api/ads/banner')), isTrue);
      expect(rule.matchesRequest(_req('https://example.com/api/adservices')), isFalse);
    });

    test('should handle multiple consecutive wildcards safely (performance edge case)', () {
      final rule = _block('||tracker.com/ad***banner*');

      expect(rule.matchesRequest(_req('https://tracker.com/ad/123/banner.jpg')), isTrue);
      expect(rule.matchesRequest(_req('https://tracker.com/adbanner')), isTrue);
      expect(rule.matchesRequest(_req('https://tracker.com/ad/banner/img')), isTrue);
      expect(rule.matchesRequest(_req('https://tracker.com/ad123')), isFalse);
    });

    test('should handle exception rule properly overriding third-party and domain limits', () {
      final rule = _exception('||trusted-ads.com^');

      expect(rule.matchesRequest(_req('https://trusted-ads.com/script.js')), isTrue);
      expect(rule.matchesRequest(_req('https://sub.trusted-ads.com/script.js')), isTrue);
      expect(rule.matchesRequest(_req('https://not-trusted-ads.com/script.js')), isFalse);
    });

    test('should not confuse separator (^) with literal characters in URL', () {
      final rule = _block('example.com^');

      // ^ means separator (port, path, query, end of string), not literal ^
      expect(rule.matchesRequest(_req('https://example.com^literal.com')), isFalse);
      expect(rule.matchesRequest(_req('https://example.com/path')), isTrue);
    });
  });
}
