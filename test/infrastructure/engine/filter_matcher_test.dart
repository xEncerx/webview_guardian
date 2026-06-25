import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';

void main() {
  // Helper to quickly build a NetworkRequest
  NetworkRequest req(
    String url, {
    ResourceType type = ResourceType.script,
    String sourceUrl = 'http://source.com',
  }) {
    final uri = Uri.parse(url);
    return NetworkRequest(
      url: uri.toString(),
      host: uri.host,
      resourceType: type,
      sourceHost: Uri.parse(sourceUrl).host,
    );
  }

  // Helper to compile an engine with given rules
  CompiledFilterEngine buildEngine({
    List<FilterRule> trieRules = const [],
    List<FilterRule> tokenRules = const [],
    List<FilterRule> fallbackRules = const [],
  }) {
    final compiler = HostnameTrieCompiler();
    trieRules.forEach(compiler.tryAddRule);
    final compiledTrie = compiler.build();

    final tokenTable = <int, List<FilterRule>>{};
    for (final rule in tokenRules) {
      final pattern = switch (rule) {
        final NetworkBlockRule r => r.pattern,
        final NetworkExceptionRule r => r.pattern,
        _ => '',
      };
      final tokens = pattern.extractTokensAsInt();
      if (tokens.isNotEmpty) {
        final token = tokens.first;
        tokenTable.putIfAbsent(token, () => []).add(rule);
      }
    }

    return CompiledFilterEngine(
      totalRules: trieRules.length + tokenRules.length + fallbackRules.length,
      trieBuffer: compiledTrie.buffer,
      trieRules: compiledTrie.rules,
      tokenDispatchTable: tokenTable,
      fallbackRules: fallbackRules.toSet(),
      cosmeticHideRules: const {},
      cosmeticExceptionRules: const {},
      scriptletRules: const {},
      cssInjectRules: const {},
    );
  }

  group('Basic Search Algorithms (Isolation Tests)', () {
    test('Empty engine exposes a valid empty trie root', () {
      final engine = CompiledFilterEngine.empty();

      expect(engine.trieBuffer, hasLength(1));
      expect(engine.trieBuffer.single, 0);
    });

    test('Empty engine allows requests without throwing', () {
      final matcher = FilterMatcher(FilterEngineRef(CompiledFilterEngine.empty()));

      expect(
        () => matcher.matchNetworkRequest(req('https://example.com/script.js')),
        returnsNormally,
      );
      expect(
        matcher.matchNetworkRequest(req('https://example.com/script.js')),
        isA<Allow>(),
      );
    });

    test('Valid empty trie root still evaluates token rules', () {
      final engine = CompiledFilterEngine(
        totalRules: 1,
        trieBuffer: Uint32List.fromList([0]),
        trieRules: const [],
        tokenDispatchTable: {
          'banner'.extractTokensAsInt().first: [
            const NetworkBlockRule(pattern: 'banner'),
          ],
        },
        fallbackRules: const {},
        cosmeticHideRules: const {},
        cosmeticExceptionRules: const {},
        scriptletRules: const {},
        cssInjectRules: const {},
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://site.com/ad/banner.png'));

      expect(result, isA<Block>());
    });

    test('Trie: Exact domain match', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||example.com^')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://example.com/ad.js'));
      expect(result, isA<Block>());
    });

    test('Trie: Subdomain match', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||example.com^')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://ads.example.com/script.js'));
      expect(result, isA<Block>());
    });

    test('Trie: Parent domain rejection (Corner Case)', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.example.com^')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://example.com/script.js'));
      expect(result, isA<Allow>());
    });

    test('Trie: Similar domain rejection', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||example.com^')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://myexample.com/ad.js'));
      expect(result, isA<Allow>());
    });

    test('Dispatch: Token match', () {
      final engine = buildEngine(
        tokenRules: [const NetworkBlockRule(pattern: 'banner')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://site.com/ad/banner.png'));
      expect(result, isA<Block>());
    });

    test('Dispatch: Token-only rule still matches after serialization round trip', () {
      final engine = buildEngine(
        tokenRules: [const NetworkBlockRule(pattern: 'banner.js')],
      );
      final restored = EngineSerializer().deserialize(EngineSerializer().serialize(engine));
      final matcher = FilterMatcher(FilterEngineRef(restored));

      final result = matcher.matchNetworkRequest(req('https://site.test/banner.js'));

      expect(result, isA<Block>());
    });

    test('Fallback: Regular expression match', () {
      final engine = buildEngine(
        fallbackRules: [const NetworkBlockRule(pattern: r'/ad[0-9]+\.js/')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://site.com/ad42.js'));
      expect(result, isA<Block>());
    });

    test('Fallback rules are immutable after engine construction', () {
      final engine = buildEngine(
        fallbackRules: [const NetworkBlockRule(pattern: 'script.js')],
      );

      expect(
        () => engine.fallbackRules.add(
          const NetworkExceptionRule(pattern: 'script.js', isImportant: true),
        ),
        throwsUnsupportedError,
      );
    });
  });

  group('Rule Priorities (Weight System Tests)', () {
    test('Exception overrides Block', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        tokenRules: [const NetworkExceptionRule(pattern: 'ads.com/allow.js')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://ads.com/allow.js'));
      expect(result, isA<Allow>(), reason: 'Exception should override normal Block');
    });

    test('Important Block overrides Exception', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^', isImportant: true)],
        tokenRules: [const NetworkExceptionRule(pattern: 'ads.com/allow.js')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://ads.com/allow.js'));
      expect(result, isA<Block>(), reason: 'Important Block should override normal Exception');
    });

    test('Important Exception overrides Important Block', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^', isImportant: true)],
        fallbackRules: [const NetworkExceptionRule(pattern: 'allow.js', isImportant: true)],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://ads.com/allow.js'));
      expect(result, isA<Allow>(), reason: 'Important Exception should override Important Block');
    });

    test('Search continues after finding Block', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||example.com^')], // Weight 1
        tokenRules: [const NetworkExceptionRule(pattern: 'banner')], // Weight 2
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://example.com/banner/'));
      expect(result, isA<Allow>(), reason: 'Should not early exit on normal Block');
    });

    test('Trie normal block skips equal-priority fallback normal blocks', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: List<FilterRule>.generate(
          100,
          (_) => const NetworkBlockRule(pattern: '/[/'),
        ),
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        () => matcher.matchNetworkRequest(req('https://ads.com/script.js')),
        returnsNormally,
        reason: 'Equal-priority fallback blocks must not be evaluated once a trie block matched.',
      );
      expect(matcher.matchNetworkRequest(req('https://ads.com/script.js')), isA<Block>());
    });

    test('Trie normal block is overridden by fallback normal exception', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [const NetworkExceptionRule(pattern: 'allowed-path')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://ads.com/allowed-path/script.js'));

      expect(result, isA<Allow>());
    });

    test('Trie normal block remains blocked when fallback important block outranks exception', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [
          const NetworkExceptionRule(pattern: 'script.js'),
          const NetworkBlockRule(pattern: 'script.js', isImportant: true),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://ads.com/script.js'));

      expect(result, isA<Block>());
    });

    test('Trie normal block is overridden by fallback important exception', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [const NetworkExceptionRule(pattern: 'script.js', isImportant: true)],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://ads.com/script.js'));

      expect(result, isA<Allow>());
    });

    test('Token normal exception is overridden by fallback important block', () {
      final engine = buildEngine(
        tokenRules: [const NetworkExceptionRule(pattern: 'allowed-token')],
        fallbackRules: [const NetworkBlockRule(pattern: 'allowed-token', isImportant: true)],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://ads.com/allowed-token.js'));

      expect(result, isA<Block>());
    });

    test('Fallback important block skips lower-priority fallback candidates', () {
      final engine = buildEngine(
        fallbackRules: [
          const NetworkBlockRule(pattern: 'script.js', isImportant: true),
          const NetworkExceptionRule(pattern: '/[/'),
          const NetworkBlockRule(pattern: '/[/'),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        () => matcher.matchNetworkRequest(req('https://ads.com/script.js')),
        returnsNormally,
        reason: 'Lower fallback classes cannot change an important block decision.',
      );
      expect(matcher.matchNetworkRequest(req('https://ads.com/script.js')), isA<Block>());
    });
  });

  group('Fallback precedence constraints', () {
    test('Higher-priority fallback resource type constraint is honored', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [
          const NetworkExceptionRule(
            pattern: 'asset',
            resourceTypes: {ResourceType.image},
          ),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        matcher.matchNetworkRequest(req('https://ads.com/asset.png', type: ResourceType.image)),
        isA<Allow>(),
      );
      expect(
        matcher.matchNetworkRequest(req('https://ads.com/asset.js')),
        isA<Block>(),
      );
    });

    test('Higher-priority fallback party constraint is honored', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [
          const NetworkExceptionRule(pattern: 'script.js', isThirdPartyOnly: true),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        matcher.matchNetworkRequest(
          req('https://ads.com/script.js', sourceUrl: 'https://publisher.com'),
        ),
        isA<Allow>(),
      );
      expect(
        matcher.matchNetworkRequest(
          req('https://ads.com/script.js', sourceUrl: 'https://ads.com'),
        ),
        isA<Block>(),
      );
    });

    test('Higher-priority fallback include domain constraint is honored', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [
          const NetworkExceptionRule(pattern: 'script.js', includeDomains: {'publisher.com'}),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        matcher.matchNetworkRequest(
          req('https://ads.com/script.js', sourceUrl: 'https://publisher.com'),
        ),
        isA<Allow>(),
      );
      expect(
        matcher.matchNetworkRequest(
          req('https://ads.com/script.js', sourceUrl: 'https://other.com'),
        ),
        isA<Block>(),
      );
    });

    test('Higher-priority fallback exclude domain constraint is honored', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||ads.com^')],
        fallbackRules: [
          const NetworkExceptionRule(pattern: 'script.js', excludeDomains: {'blocked.com'}),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        matcher.matchNetworkRequest(
          req('https://ads.com/script.js', sourceUrl: 'https://publisher.com'),
        ),
        isA<Allow>(),
      );
      expect(
        matcher.matchNetworkRequest(
          req('https://ads.com/script.js', sourceUrl: 'https://blocked.com'),
        ),
        isA<Block>(),
      );
    });
  });

  group('Resource Type Filtering (Resource Type Tests)', () {
    test('Match by allowed resource type', () {
      final engine = buildEngine(
        trieRules: [
          const NetworkBlockRule(
            pattern: '||ads.com^',
            resourceTypes: {ResourceType.script},
          ),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(
        req('http://ads.com/1.js'),
      );
      expect(result, isA<Block>());
    });

    test('Ignore mismatching resource type', () {
      final engine = buildEngine(
        trieRules: [
          const NetworkBlockRule(
            pattern: '||ads.com^',
            resourceTypes: {ResourceType.script},
          ),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(
        req('http://ads.com/1.js', type: ResourceType.image),
      );
      expect(result, isA<Allow>());
    });

    test('Match with inverted resource types (~script means all except script)', () {
      final allExceptScript = ResourceType.values.toSet()..remove(ResourceType.script);
      final engine = buildEngine(
        trieRules: [
          NetworkBlockRule(
            pattern: '||ads.com^',
            resourceTypes: allExceptScript,
          ),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      // Should block image
      expect(
        matcher.matchNetworkRequest(req('http://ads.com/1.png', type: ResourceType.image)),
        isA<Block>(),
      );
      // Should allow script
      expect(
        matcher.matchNetworkRequest(req('http://ads.com/1.js')),
        isA<Allow>(),
      );
    });
  });

  group('Third-Party and Domain Restrictions (Context Tests)', () {
    test('Third-Party rule blocks cross-domain request', () {
      final engine = buildEngine(
        trieRules: [
          const NetworkBlockRule(pattern: '||ads.com^', isThirdPartyOnly: true),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(
        req('http://ads.com/script.js', sourceUrl: 'http://site.com'),
      );
      expect(result, isA<Block>());
    });

    test('First-Party is allowed when Third-Party is required', () {
      final engine = buildEngine(
        trieRules: [
          const NetworkBlockRule(pattern: '||site.com^', isThirdPartyOnly: true),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(
        req('http://site.com/ad.js', sourceUrl: 'http://site.com'),
      );
      expect(result, isA<Allow>());
    });

    test('Include domain restriction (domain=)', () {
      final engine = buildEngine(
        trieRules: [
          const NetworkBlockRule(pattern: '||ads.com^', includeDomains: {'a.com'}),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        matcher.matchNetworkRequest(req('http://ads.com/script.js', sourceUrl: 'http://a.com')),
        isA<Block>(),
      );
      expect(
        matcher.matchNetworkRequest(req('http://ads.com/script.js', sourceUrl: 'http://b.com')),
        isA<Allow>(),
      );
    });

    test('Exclude domain restriction (domain=~)', () {
      final engine = buildEngine(
        trieRules: [
          const NetworkBlockRule(pattern: '||ads.com^', excludeDomains: {'a.com'}),
        ],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      expect(
        matcher.matchNetworkRequest(req('http://ads.com/script.js', sourceUrl: 'http://a.com')),
        isA<Allow>(),
      );
      expect(
        matcher.matchNetworkRequest(req('http://ads.com/script.js', sourceUrl: 'http://b.com')),
        isA<Block>(),
      );
    });
  });

  group('Parsing Edge Cases (Edge Cases)', () {
    test('Hostname extraction handles non-standard ports', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||example.com^')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('http://example.com:8080/ad.js'));
      expect(result, isA<Block>());
    });

    test('URL without path is handled correctly', () {
      final engine = buildEngine(
        trieRules: [const NetworkBlockRule(pattern: '||example.com^')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://example.com'));
      expect(result, isA<Block>());
    });

    test('URL with unicode characters does not crash token matching', () {
      final engine = buildEngine(
        tokenRules: [const NetworkBlockRule(pattern: 'example')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      final result = matcher.matchNetworkRequest(req('https://example.com/путь?q=значение'));
      expect(result, isA<Block>());
    });

    test('URL shorter than 5 characters falls back safely', () {
      final engine = buildEngine(
        fallbackRules: [const NetworkBlockRule(pattern: r'/a\.c/')],
      );
      final matcher = FilterMatcher(FilterEngineRef(engine));

      // http://a.c is short. Contains only 3 characters of domain.
      final result = matcher.matchNetworkRequest(req('http://a.c/'));
      expect(result, isA<Block>());
    });
  });

  group('Stress Testing (Performance Benchmarks)', () {
    late CompiledFilterEngine massiveEngine;

    setUpAll(() {
      final trieRules = <FilterRule>[];
      final tokenRules = <FilterRule>[];
      final fallbackRules = <FilterRule>[];

      // Generate +-100k rules
      for (var i = 0; i < 90000; i++) {
        trieRules.add(NetworkBlockRule(pattern: '||tracker$i.com^'));
      }
      for (var i = 0; i < 9000; i++) {
        tokenRules.add(NetworkBlockRule(pattern: 'ad-banner-$i'));
      }
      for (var i = 0; i < 300; i++) {
        fallbackRules.add(NetworkBlockRule(pattern: '/unusual-regex-$i/'));
      }

      // Add a specific Important Exception for Best-Case scenario
      trieRules.add(const NetworkExceptionRule(pattern: '||bestcase.com^', isImportant: true));

      massiveEngine = buildEngine(
        trieRules: trieRules,
        tokenRules: tokenRules,
        fallbackRules: fallbackRules,
      );
    });

    test('Benchmark: Worst-Case Scenario (Misses everything, falls back)', () {
      final matcher = FilterMatcher(FilterEngineRef(massiveEngine));
      final request = req(
        'https://completely-safe-domain-without-matches.com/some/very/long/path/with/tokens/that/have/no/match/abcde12345/',
      );

      final stopwatch = Stopwatch()..start();
      const iterations = 10000;
      for (var i = 0; i < iterations; i++) {
        matcher.matchNetworkRequest(request);
      }
      stopwatch.stop();

      final elapsedMs = stopwatch.elapsedMilliseconds;

      expect(elapsedMs, lessThan(10000));
    });

    test('Benchmark: Best-Case Scenario (Important Exception Early Exit)', () {
      final matcher = FilterMatcher(FilterEngineRef(massiveEngine));
      final request = req('https://bestcase.com/script.js');

      final stopwatch = Stopwatch()..start();
      const iterations = 10000;
      for (var i = 0; i < iterations; i++) {
        matcher.matchNetworkRequest(request);
      }
      stopwatch.stop();

      final elapsedMs = stopwatch.elapsedMilliseconds;

      expect(elapsedMs, lessThan(100));
    });
  });
}
