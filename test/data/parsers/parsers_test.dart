import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

const String easyListHeader = r'''
[Adblock Plus 2.0]
! Version: 202604011753
! Title: EasyList
! Last modified: 01 Apr 2026 17:53 UTC
! Expires: 4 days (update frequency)
! Commit: 373d7f511258722e60233b4901db0c66cc11689c
! *** easylist:template_header.txt ***
! 
! Please report any unblocked adverts or problems
! in the forums (https://forums.lanik.us/)
! or via e-mail (easylist@protonmail.com).
! 
! Homepage: https://easylist.to/
! Licence: https://easylist.to/pages/licence.html
! GitHub issues: https://github.com/easylist/easylist/issues
! GitHub pull requests: https://github.com/easylist/easylist/pulls
! 
! -----------------------General advert blocking filters-----------------------!
! *** easylist:easylist/easylist_general_block.txt ***
&rb=&uuid=$third-party
&subaffid=%$subdocument,third-party
-ad-manager/$~stylesheet
-ad-sidebar.$image
-ad.jpg.pagespeed.$image
-ads-manager/$domain=~wordpress.org
-ads/assets/$script,domain=~web-ads.org
-assets/ads.$~script
''';
const String hostsHeader = '''
# AdAway default blocklist
# Blocking mobile ad providers and some analytics providers
#
# Project home page:
# https://github.com/AdAway/adaway.github.io/
#
# Fetch the latest version of this file:
# https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt
#
# License:
# CC Attribution 3.0 (http://creativecommons.org/licenses/by/3.0/)
#
# Contributions by:
# Kicelo, Dominik Schuermann.
# Further changes and contributors maintained in the commit history at
# https://github.com/AdAway/adaway.github.io/commits/master
#
# Contribute:
# Create an issue at https://github.com/AdAway/adaway.github.io/issues
#

127.0.0.1  localhost
::1  localhost

# [163.com]
127.0.0.1 analytics.163.com
''';
const String domainListHeader = '''
# Title: HaGeZi's Pro DNS Blocklist
# Description: Big broom - Cleans the Internet and protects your privacy! Blocks Ads, Affiliate, Tracking, Metrics, Telemetry, Phishing, Malware, Scam, Fake, Crytojacking and other "Crap".
# Homepage: https://github.com/hagezi/dns-blocklists
# License: https://github.com/hagezi/dns-blocklists/blob/main/LICENSE
# Issues: https://github.com/hagezi/dns-blocklists/issues
# Disclaimer: https://github.com/hagezi/dns-blocklists/blob/main/README.md#disclaimer
# Expires: 1 day
# Last modified: 01 Apr 2026 10:23 UTC
# Version: 2026.0401.1023.52
# Syntax: Domains (including possible subdomains)
# Number of entries: 390349
#
0.beer
0.club
0.fashion
''';

void main() {
  group('HostsParser', () {
    late HostsParser parser;

    setUp(() {
      parser = HostsParser();
    });

    test('should parse valid IPv4 boundaries (0.0.0.0 and 127.0.0.1)', () {
      final bytes = _bytes('0.0.0.0 example.com\n127.0.0.1 redirect.org');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 2);

      final rule1 = rules[0];
      expect(rule1, isA<NetworkBlockRule>());
      expect((rule1 as NetworkBlockRule).pattern, '||example.com^');

      final rule2 = rules[1];
      expect(rule2, isA<NetworkBlockRule>());
      expect((rule2 as NetworkBlockRule).pattern, '||redirect.org^');
    });

    test('should ignore comments starting with hash', () {
      final bytes = _bytes(
        '# This is a comment\n0.0.0.0 valid.com\n# 127.0.0.1 ignored.com',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect((rule as NetworkBlockRule).pattern, '||valid.com^');
    });

    test('should ignore empty lines and whitespace-only lines', () {
      final bytes = _bytes('   \n\n127.0.0.1 actual.com\n \t \n');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect((rule as NetworkBlockRule).pattern, '||actual.com^');
    });

    test('should ignore invalid IP addresses and non-conforming hosts formats', () {
      final bytes = _bytes(
        '1.1.1.1 not-allowed.com\n256.0.0.1 bad-ip.com\n0.0.0.0   \n127.0.1.1 something.com\njust-domain.com',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules, isEmpty);
    });

    test('should correctly parse both Windows CRLF and Unix LF line endings', () {
      final bytes = _bytes(
        '0.0.0.0 win.com\r\n127.0.0.1 unix.com\n0.0.0.0 mixed.com\r\n',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 3);
      expect((rules[0] as NetworkBlockRule).pattern, '||win.com^');
      expect((rules[1] as NetworkBlockRule).pattern, '||unix.com^');
      expect((rules[2] as NetworkBlockRule).pattern, '||mixed.com^');
    });
  });

  group('DomainListParser', () {
    late DomainListParser parser;

    setUp(() {
      parser = DomainListParser();
    });

    test('should parse standard naked domains', () {
      final bytes = _bytes('example.com\nsub.example.co.uk');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 2);

      final rule1 = rules[0];
      expect(rule1, isA<NetworkBlockRule>());
      expect((rule1 as NetworkBlockRule).pattern, '||example.com^');

      final rule2 = rules[1];
      expect(rule2, isA<NetworkBlockRule>());
      expect((rule2 as NetworkBlockRule).pattern, '||sub.example.co.uk^');
    });

    test('should ignore inline comments', () {
      final bytes = _bytes('# My Domains\nexample.com\n# something.com');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect((rule as NetworkBlockRule).pattern, '||example.com^');
    });

    test('should ignore empty or whitespace-only lines', () {
      final bytes = _bytes('\n   \nexample.org\n\n');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect((rule as NetworkBlockRule).pattern, '||example.org^');
    });

    test('should fast reject invalid garbage with spaces or slashes', () {
      final bytes = _bytes(
        'valid.com\nmy  domain.com\npath/example.com\nhttp://website.com',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect((rule as NetworkBlockRule).pattern, '||valid.com^');
    });
  });

  group('AdblockPlusParser', () {
    late AdblockPlusParser parser;

    setUp(() {
      parser = AdblockPlusParser();
    });

    test('should fast reject metadata and general comments', () {
      final bytes = _bytes(
        '! Title: Test List\n[Adblock Plus 2.0]\n! Checksum: xyza\n! TimeUpdated: 2026',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules, isEmpty);
    });

    test('should fast reject regular expressions', () {
      final bytes = _bytes('/ad-[0-9]\\.js/\n/^https?:\\/\\/(.*\\.)?ads\\.com\\//');
      final rules = parser.parse(bytes).toList();

      expect(rules, isEmpty);
    });

    test('should fast reject uBO procedural cosmetic rules', () {
      final bytes = _bytes(
        'example.com#?#div:-abp-has(a)\nwebsite.com#@?#tr:has-text(Promoted)',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules, isEmpty);
    });

    test('should fast reject unsupported network modifiers like csp or removeparam', () {
      final bytes = _bytes(
        'tests.com\$csp=script-src\nwebsite.com\$removeparam=utm_source\n||bad.net^\$document,csp=1\n||another.com^\$script,removeparam',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules, isEmpty);
    });

    test('should correctly parse standard blocking rules', () {
      final bytes = _bytes('||ads.example.com^');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect(rule, isA<NetworkBlockRule>());
      expect((rule as NetworkBlockRule).pattern, '||ads.example.com^');
    });

    test('should correctly parse exception rules', () {
      final bytes = _bytes('@@||good.com^');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect(rule, isA<NetworkExceptionRule>());
      expect((rule as NetworkExceptionRule).pattern, '||good.com^');
    });

    test(r'should preserve $match-case on block and exception network rules', () {
      final bytes = _bytes(
        r'||example.com/AdBanner.js$match-case'
        '\n'
        r'@@||example.com/AllowedAd.js$match-case',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 2);

      expect(rules[0], isA<NetworkBlockRule>());
      expect((rules[0] as NetworkBlockRule).pattern, '||example.com/AdBanner.js');
      expect((rules[0] as NetworkBlockRule).isMatchCase, isTrue);

      expect(rules[1], isA<NetworkExceptionRule>());
      expect((rules[1] as NetworkExceptionRule).pattern, '||example.com/AllowedAd.js');
      expect((rules[1] as NetworkExceptionRule).isMatchCase, isTrue);
    });

    test(r'should correctly parse rules with $important modifier', () {
      final bytes = _bytes(
        'mastarti.com/stats/\$important\n'
        'vio.to/stat_date/\$important\n'
        'streamguard.cc/stats/\$important\n'
        'alforenao.com/stats/\n'
        '||streamango.com/log\n'
        '||streamtojupiter.me/stats/\n'
        '://*.*.com/xj/\$important\n'
        r'@@||ads.com^$important',
      );
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 8);

      expect(rules[0], isA<NetworkBlockRule>());
      expect((rules[0] as NetworkBlockRule).pattern, 'mastarti.com/stats/');
      expect((rules[0] as NetworkBlockRule).isImportant, isTrue);

      expect(rules[1], isA<NetworkBlockRule>());
      expect((rules[1] as NetworkBlockRule).pattern, 'vio.to/stat_date/');
      expect((rules[1] as NetworkBlockRule).isImportant, isTrue);

      expect(rules[2], isA<NetworkBlockRule>());
      expect((rules[2] as NetworkBlockRule).pattern, 'streamguard.cc/stats/');
      expect((rules[2] as NetworkBlockRule).isImportant, isTrue);

      expect(rules[3], isA<NetworkBlockRule>());
      expect((rules[3] as NetworkBlockRule).pattern, 'alforenao.com/stats/');
      expect((rules[3] as NetworkBlockRule).isImportant, isFalse);

      expect(rules[4], isA<NetworkBlockRule>());
      expect((rules[4] as NetworkBlockRule).pattern, '||streamango.com/log');
      expect((rules[4] as NetworkBlockRule).isImportant, isFalse);

      expect(rules[5], isA<NetworkBlockRule>());
      expect((rules[5] as NetworkBlockRule).pattern, '||streamtojupiter.me/stats/');
      expect((rules[5] as NetworkBlockRule).isImportant, isFalse);

      expect(rules[6], isA<NetworkBlockRule>());
      expect((rules[6] as NetworkBlockRule).pattern, '://*.*.com/xj/');
      expect((rules[6] as NetworkBlockRule).isImportant, isTrue);

      expect(rules[7], isA<NetworkExceptionRule>());
      expect((rules[7] as NetworkExceptionRule).pattern, '||ads.com^');
      expect((rules[7] as NetworkExceptionRule).isImportant, isTrue);
    });
    test('should correctly parse network modifiers parsing (third-party, domains)', () {
      final bytes = _bytes(r'||ads.com^$script,third-party,domain=a.com|~b.com');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 1);
      final rule = rules.first;
      expect(rule, isA<NetworkBlockRule>());
      final blockRule = rule as NetworkBlockRule;

      expect(blockRule.pattern, '||ads.com^');
      expect(blockRule.isThirdPartyOnly, isTrue);
      // ResourceType.script check depends on precise internal mapping.
      // Ignoring direct resourceTypes enum match to maintain abstraction unless exposed.

      expect(blockRule.includeDomains, isNotNull);
      expect(blockRule.includeDomains, contains('a.com'));

      expect(blockRule.excludeDomains, isNotNull);
      expect(blockRule.excludeDomains, contains('b.com'));
    });

    test('should correctly parse cosmetic hiding rules', () {
      final bytes = _bytes('example.com##.banner-ad\n##.sponsored-post');
      final rules = parser.parse(bytes).toList();

      expect(rules.length, 2);

      final rule1 = rules[0];
      expect(rule1, isA<CosmeticHideRule>());
      final hideRule1 = rule1 as CosmeticHideRule;
      expect(hideRule1.domains, equals(['example.com']));
      expect(hideRule1.selector, '.banner-ad');

      final rule2 = rules[1];
      expect(rule2, isA<CosmeticHideRule>());
      final hideRule2 = rule2 as CosmeticHideRule;
      expect(hideRule2.domains, isNull);
      expect(hideRule2.selector, '.sponsored-post');
    });

    test('should correctly parse inverted resource types and large exclude domain list', () {
      final bytes = _bytes(
        r'://ads.$~image,~xmlhttprequest,domain=~ads.8designers.com|~ads.ac.uk|~ads.adstream.com.ro|~ads.allegro.pl|~ads.am|~ads.amazon|~ads.apple.com|~ads.atmosphere.copernicus.eu|~ads.axon.ai|~ads.band|~ads.bestprints.biz|~ads.bikepump.com|~ads.brave.com|~ads.buscaempresas.co|~ads.business.bell.ca|~ads.cafebazaar.ir|~ads.chewy.com|~ads.colombiaonline.com|~ads.comeon.com|~ads.cvut.cz|~ads.doordash.com|~ads.dosocial.ge|~ads.dosocial.me|~ads.elevateplatform.co.uk|~ads.ferrarichat.com|~ads.finance|~ads.flytant.com|~ads.fund|~ads.google.cn|~ads.google.com|~ads.gree.net|~ads.gurkerl.at|~ads.harvard.edu|~ads.instacart.com|~ads.jiosaavn.com|~ads.kaipoke.biz|~ads.kifli.hu|~ads.knuspr.de|~ads.listonic.com|~ads.luarmor.net|~ads.magalu.com|~ads.mercadolibre.com.ar|~ads.mercadolibre.com.cl|~ads.mercadolibre.com.co|~ads.mercadolibre.com.ec|~ads.mercadolibre.com.mx|~ads.mercadolibre.com.pe|~ads.mercadolibre.com.ve|~ads.mercadolivre.com.br|~ads.mgid.com|~ads.microsoft.com|~ads.midwayusa.com|~ads.misskey.io|~ads.mobilebet.com|~ads.mojagazetka.com|~ads.msstate.edu|~ads.mst.dk|~ads.mt|~ads.naver.com|~ads.nc|~ads.nipr.ac.jp|~ads.olx.pl|~ads.palmettostatearmory.com|~ads.pinterest.com|~ads.realizeperformance.com|~ads.remix.es|~ads.rohlik.cz|~ads.rohlik.group|~ads.route.cc|~ads.safi-gmbh.ch|~ads.scotiabank.com|~ads.selfip.com|~ads.shopee.cn|~ads.shopee.co.th|~ads.shopee.com.br|~ads.shopee.com.mx|~ads.shopee.com.my|~ads.shopee.kr|~ads.shopee.ph|~ads.shopee.pl|~ads.shopee.sg|~ads.shopee.tw|~ads.shopee.vn|~ads.siriusxmmedia.com|~ads.smartnews.com|~ads.snapchat.com|~ads.socialtheater.com|~ads.sociogram.com|~ads.spotify.com|~ads.studyplus.co.jp|~ads.taboola.com|~ads.tiktok.com|~ads.tuver.ru|~ads.twitter.com|~ads.typepad.jp|~ads.umd.edu|~ads.us.tiktok.com|~ads.viksaffiliates.com|~ads.vk.com|~ads.vk.ru|~ads.watson.ch|~ads.wildberries.ru|~ads.woori.team|~ads.x.com|~ads.yandex|~reempresa.org',
      );

      final rules = parser.parse(bytes).toList();
      expect(rules.length, 1);

      final rule = rules.first;
      expect(rule, isA<NetworkBlockRule>());

      final r = rule as NetworkBlockRule;

      expect(r.pattern, '://ads.');
      expect(r.isThirdPartyOnly, false);
      expect(r.resourceTypes, isNot(contains(ResourceType.image)));
      expect(r.resourceTypes, isNot(contains(ResourceType.xmlHttpRequest)));
      expect(r.resourceTypes, contains(ResourceType.script));
      expect(r.resourceTypes, contains(ResourceType.stylesheet));
      expect(r.resourceTypes, contains(ResourceType.font));
      expect(r.resourceTypes, contains(ResourceType.media));
      expect(r.resourceTypes, contains(ResourceType.websocket));
      expect(r.resourceTypes, contains(ResourceType.document));
      expect(r.resourceTypes, contains(ResourceType.other));

      expect(r.includeDomains, isNull);

      expect(r.excludeDomains, isNotNull);
      expect(r.excludeDomains!.length, 106);

      expect(
        r.excludeDomains,
        containsAll([
          'ads.8designers.com',
          'ads.google.com',
          'ads.apple.com',
          'ads.spotify.com',
          'ads.tiktok.com',
          'ads.twitter.com',
          'ads.vk.com',
          'ads.yandex',
          'reempresa.org',
        ]),
      );
    });

    group('Edge cases and specific modifiers', () {
      test('should completely drop rules with badfilter modifier', () {
        final bytes = _bytes('||example.com^\$script,badfilter\n@@||test.com^\$badfilter');
        final rules = parser.parse(bytes).toList();

        expect(rules, isEmpty);
      });

      test('should drop rules with first-party or ~third-party modifiers', () {
        final bytes = _bytes(
          '||ads.com^\$first-party\n||tracker.com^\$~third-party\n||analytics.com^\$1p',
        );
        final rules = parser.parse(bytes).toList();

        expect(rules, isEmpty);
      });

      test(r'should parse rule with $all modifier as all resource types', () {
        final bytes = _bytes(r'||evil.com^$all');
        final rules = parser.parse(bytes).toList();

        expect(rules.length, 1);
        final rule = rules.first as NetworkBlockRule;
        expect(rule.resourceTypes, containsAll(ResourceType.values));
      });

      test('should handle windows CRLF line endings correctly', () {
        final bytes = _bytes('||ads.com^\r\n||tracker.com^\r\n@@||good.com^\r\n');
        final rules = parser.parse(bytes).toList();

        expect(rules.length, 3);
        expect((rules[0] as NetworkBlockRule).pattern, '||ads.com^');
        expect((rules[1] as NetworkBlockRule).pattern, '||tracker.com^');
        expect((rules[2] as NetworkExceptionRule).pattern, '||good.com^');
      });

      test('should handle empty lines and whitespaces gracefully', () {
        final bytes = _bytes('\n\n  \n||ads.com^\n\n');
        final rules = parser.parse(bytes).toList();

        expect(rules.length, 1);
        expect((rules.first as NetworkBlockRule).pattern, '||ads.com^');
      });

      test('should drop unsupported HTML filtering rules', () {
        final bytes = _bytes(
          'example.com\$\$script[tag-content="alert"]\nexample.com##^script:has-text(ad)\nexample.com\$@\$div.ad',
        );
        final rules = parser.parse(bytes).toList();

        expect(rules, isEmpty);
      });
    });

    group('AdGuard specific syntaxes', () {
      test('should parse AdGuard scriptlet syntax', () {
        final bytes = _bytes("example.com#%#//scriptlet('abort-on-property-read', 'ga')");
        final rules = parser.parse(bytes).toList();

        expect(rules.length, 1);
        final rule = rules.first as ScriptletRule;
        expect(rule.domains, ['example.com']);
        expect(rule.scriptletName, 'abort-on-property-read');
        expect(rule.args, ['ga']);
      });

      test('should parse AdGuard CSS injection syntax', () {
        final bytes = _bytes(r'example.com#$#body { background: #000 !important; }');
        final rules = parser.parse(bytes).toList();

        expect(rules.length, 1);
        final rule = rules.first as CssInjectRule;
        expect(rule.domain, 'example.com');
        expect(rule.css, 'body { background: #000 !important; }');
      });
    });

    group('CosmeticHideRule — multi-domain', () {
      test('single domain produces List with one entry', () {
        final rules = parser.parse(_bytes('example.com##.banner')).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, ['example.com']);
        expect(rule.selector, '.banner');
      });

      test('multiple comma-separated domains are split correctly', () {
        final rules = parser
            .parse(_bytes('finvtech.com,herstage.com,sportynew.com##.ads-wrapper'))
            .toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, ['finvtech.com', 'herstage.com', 'sportynew.com']);
        expect(rule.selector, '.ads-wrapper');
      });

      test('global rule (no domain) has null domains', () {
        final rules = parser.parse(_bytes('##.global-banner')).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, isNull);
        expect(rule.selector, '.global-banner');
      });

      test('attribute selector with ^= is parsed correctly', () {
        final rules = parser
            .parse(_bytes('##a[href^="https://paid.outbrain.com/network/redir?"]'))
            .toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, isNull);
        expect(rule.selector, 'a[href^="https://paid.outbrain.com/network/redir?"]');
      });

      test('attribute selector with onmousedown is parsed correctly', () {
        final rules = parser
            .parse(_bytes('##a[onmousedown^="this.href=\'https://paid.outbrain.com/\'"]'))
            .toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, isNull);
        expect(rule.selector, contains('onmousedown'));
      });

      test('multiple domains with complex attribute selector', () {
        final rules = parser
            .parse(
              _bytes(
                'ukrinform.de,ukrinform.es,ukrinform.fr##[style^="min-height: 280px;"]',
              ),
            )
            .toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, ['ukrinform.de', 'ukrinform.es', 'ukrinform.fr']);
        expect(rule.selector, '[style^="min-height: 280px;"]');
      });

      test('domains are trimmed of whitespace', () {
        final rules = parser.parse(_bytes('site1.com , site2.com ## .ad')).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticHideRule;
        expect(rule.domains, ['site1.com', 'site2.com']);
      });
    });

    group('CosmeticExceptionRule — #@#', () {
      test('single domain exception is parsed', () {
        final rules = parser.parse(_bytes('guloggratis.dk#@##adcontent')).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticExceptionRule;
        expect(rule.domains, ['guloggratis.dk']);
        expect(rule.selector, '#adcontent');
      });

      test('multiple domains in exception rule', () {
        final rules = parser.parse(_bytes('mafagames.com,telkomsel.com#@##adsContainer')).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticExceptionRule;
        expect(rule.domains, ['mafagames.com', 'telkomsel.com']);
        expect(rule.selector, '#adsContainer');
      });

      test('exception with attribute selector', () {
        final rules = parser
            .parse(_bytes('mypillow.com#@#[href^="http://mypillow.com/"] > img'))
            .toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticExceptionRule;
        expect(rule.domains, ['mypillow.com']);
        expect(rule.selector, '[href^="http://mypillow.com/"] > img');
      });

      test('exception with many domains', () {
        const line = 'basinnow.com,e-jpccs.jp,oxfordlearnersdictionaries.com#@##advertise';
        final rules = parser.parse(_bytes(line)).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticExceptionRule;
        expect(rule.domains, [
          'basinnow.com',
          'e-jpccs.jp',
          'oxfordlearnersdictionaries.com',
        ]);
        expect(rule.selector, '#advertise');
      });

      test('#@# is not confused with ## rule', () {
        const lines = 'example.com##.banner\nexample.com#@#.banner';
        final rules = parser.parse(_bytes(lines)).toList();

        expect(rules.length, 2);
        expect(rules[0], isA<CosmeticHideRule>());
        expect(rules[1], isA<CosmeticExceptionRule>());
      });

      test('global cosmetic exception (no domain) has null domains', () {
        final rules = parser.parse(_bytes('#@#.global-ad')).toList();

        expect(rules.length, 1);
        final rule = rules.first as CosmeticExceptionRule;
        expect(rule.domains, isNull);
        expect(rule.selector, '.global-ad');
      });
    });

    group('ScriptletRule — multi-domain', () {
      test('single domain scriptlet', () {
        final rules = parser.parse(_bytes('example.com##+js(nowebrtc)')).toList();

        expect(rules.length, 1);
        final rule = rules.first as ScriptletRule;
        expect(rule.domains, ['example.com']);
        expect(rule.scriptletName, 'nowebrtc');
      });

      test('multiple domains in scriptlet rule', () {
        final rules = parser
            .parse(_bytes('site1.com,site2.com,site3.com##+js(set-constant, adsbygoogle, [])'))
            .toList();

        expect(rules.length, 1);
        final rule = rules.first as ScriptletRule;
        expect(rule.domains, ['site1.com', 'site2.com', 'site3.com']);
        expect(rule.scriptletName, 'set-constant');
        expect(rule.args, ['adsbygoogle', '[]']);
      });

      test('scriptlet with no domain has null domains', () {
        final rules = parser.parse(_bytes('##+js(nowebrtc)')).toList();

        expect(rules.length, 1);
        final rule = rules.first as ScriptletRule;
        expect(rule.domains, isNull);
      });
    });

    group('Procedural cosmetics — dropped', () {
      test('single domain #?# rule is dropped', () {
        final rules = parser
            .parse(
              _bytes(
                'argos.co.uk#?#[data-test^="component-slider-slide-"]:has-text(SPONSORED)',
              ),
            )
            .toList();

        expect(rules, isEmpty);
      });

      test('multi-domain #?# with complex has-text is dropped', () {
        const line =
            'atlanticsuperstore.ca,fortinos.ca,loblaws.ca#?#.container > ul > li:has(.badge:has-text(/Sponsored/))';
        final rules = parser.parse(_bytes(line)).toList();

        expect(rules, isEmpty);
      });
    });
  });

  group('FilterListParserFactory', () {
    test('should resolve AdblockPlusParser when given realEasyListHeader', () {
      final header = _bytes(easyListHeader);
      final dynamic parser = FilterListParserFactory.resolve(header);

      expect(parser, isA<AdblockPlusParser>());
    });

    test('should resolve HostsParser when given realHostsHeader', () {
      final header = _bytes(hostsHeader);
      final dynamic parser = FilterListParserFactory.resolve(header);

      expect(parser, isA<HostsParser>());
    });

    test('should resolve DomainListParser when given realDomainListHeader', () {
      final header = _bytes(domainListHeader);
      final dynamic parser = FilterListParserFactory.resolve(header);

      expect(parser, isA<DomainListParser>());
    });

    test('should fallback to AdblockPlusParser when given unidentified headers', () {
      final header = _bytes('some random unidentifiable garbage header');
      final dynamic parser = FilterListParserFactory.resolve(header);

      expect(parser, isA<AdblockPlusParser>());
    });
  });
}
