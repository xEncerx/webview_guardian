import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';

Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

NetworkRequest _request(String url, {required String sourceUrl}) {
  final uri = Uri.parse(url);
  return NetworkRequest(
    url: uri.toString(),
    host: uri.host,
    sourceHost: Uri.parse(sourceUrl).host,
    resourceType: ResourceType.script,
  );
}

// Extension to help test individual rules easily.
extension EngineSerializerTestExt on EngineSerializer {
  FilterRule testRuleRoundTrip(FilterRule rule) {
    final engine = CompiledFilterEngine(
      totalRules: 1,
      trieBuffer: Uint32List(0),
      trieRules: [rule], // Store it here to test round-trip without affecting other rules
      tokenDispatchTable: {},
      fallbackRules: {},
      cosmeticHideRules: {},
      cosmeticExceptionRules: {},
      scriptletRules: {},
      cssInjectRules: {},
    );
    final bytes = serialize(engine);
    final restoredEngine = deserialize(bytes);
    return restoredEngine.trieRules.first;
  }
}

void main() {
  group('BinaryWriter & BinaryReader Unit Tests', () {
    test('writeUint8 and readUint8 handle valid boundaries', () {
      final writer = BinaryWriter()
        ..writeUint8(0)
        ..writeUint8(255);

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readUint8(), 0);
      expect(reader.readUint8(), 255);
    });

    test('writeUint8 and readUint8 handle overflow (256 becomes 0)', () {
      final writer = BinaryWriter()..writeUint8(256);

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readUint8(), 0);
    });

    test('writeInt32 and readInt32 handle positive, zero, negative and boundaries', () {
      final writer = BinaryWriter()
        ..writeInt32(0)
        ..writeInt32(100)
        ..writeInt32(-1)
        ..writeInt32(2147483647) // MAX_INT32
        ..writeInt32(-2147483648); // MIN_INT32

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readInt32(), 0);
      expect(reader.readInt32(), 100);
      expect(reader.readInt32(), -1);
      expect(reader.readInt32(), 2147483647);
      expect(reader.readInt32(), -2147483648);
    });

    test('writeBool and readBool handle true and false', () {
      final writer = BinaryWriter()
        ..writeBool(true)
        ..writeBool(false)
        ..writeBool(true);

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readBool(), isTrue);
      expect(reader.readBool(), isFalse);
      expect(reader.readBool(), isTrue);
    });

    test('writeString and readString handle ASCII, empty, and multi-byte UTF-8', () {
      final writer = BinaryWriter()
        ..writeString('ascii')
        ..writeString('')
        ..writeString('кириллица');

      // 64KB string
      final longString = 'A' * 65535;
      writer.writeString(longString);

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readString(), 'ascii');
      expect(reader.readString(), '');
      expect(reader.readString(), 'кириллица');
      expect(reader.readString(), longString);
    });

    test('writeNullableString and readNullableString handle null and strings', () {
      final writer = BinaryWriter()
        ..writeNullableString(null)
        ..writeNullableString('value');

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readNullableString(), isNull);
      expect(reader.readNullableString(), 'value');
    });

    test('writeStringList and readStringList handle populated and empty lists', () {
      final writer = BinaryWriter()
        ..writeStringList(['a', 'b', 'c'])
        ..writeStringList([]);

      final reader = BinaryReader(writer.toBytes());
      expect(reader.readStringList(), ['a', 'b', 'c']);
      expect(reader.readStringList(), isEmpty);
    });

    test(
      'writeNullableStringSet and readNullableStringSet handle null, populated, and empty sets',
      () {
        final writer = BinaryWriter()
          ..writeNullableStringSet(null)
          ..writeNullableStringSet({'a', 'b'})
          ..writeNullableStringSet({});

        final reader = BinaryReader(writer.toBytes());
        expect(reader.readNullableStringSet(), isNull);
        expect(reader.readNullableStringSet(), {'a', 'b'});
        expect(reader.readNullableStringSet(), isEmpty);
      },
    );

    test(
      'writeUint32List and readUint32List handle normal, empty, single element, and reallocation bounds',
      () {
        final writer = BinaryWriter();
        final list100 = Uint32List.fromList(List.generate(100, (i) => i));
        writer
          ..writeUint32List(list100)
          ..writeUint32List(Uint32List(0))
          ..writeUint32List(Uint32List.fromList([42]));

        // List provoking potential reallocation based on typical buffer sizes
        final largeList = Uint32List.fromList(List.generate(20000, (i) => i));
        writer.writeUint32List(largeList);

        final reader = BinaryReader(writer.toBytes());
        expect(reader.readUint32List(), list100);
        expect(reader.readUint32List(), isEmpty);
        expect(reader.readUint32List(), [42]);
        expect(reader.readUint32List(), largeList);
      },
    );

    test('writeUint8List and readUint8List handle large lists', () {
      final writer = BinaryWriter();
      const numBytes = 10 * 1024 * 1024;
      for (var i = 0; i < numBytes; i++) {
        writer.writeUint8(i % 256);
      }

      final bytes = writer.toBytes();
      expect(bytes.length, numBytes);
      expect(bytes.last, (numBytes - 1) % 256);
    });
  });

  group('FilterRule Serialization Unit Tests', () {
    late EngineSerializer serializer;

    setUp(() {
      serializer = EngineSerializer();
    });

    test('NetworkBlockRule serialized and deserialized accurately with all fields populated', () {
      const rule = NetworkBlockRule(
        pattern: 'example.com',
        resourceTypes: {ResourceType.script, ResourceType.image},
        isThirdPartyOnly: true,
        isImportant: true,
        isMatchCase: true,
        includeDomains: {'a.com', 'b.com'},
        excludeDomains: {'c.com'},
      );

      final deserialized = serializer.testRuleRoundTrip(rule) as NetworkBlockRule;

      expect(deserialized.pattern, rule.pattern);
      expect(deserialized.resourceTypes, rule.resourceTypes);
      expect(deserialized.isThirdPartyOnly, isTrue);
      expect(deserialized.isImportant, isTrue);
      expect(deserialized.isMatchCase, isTrue);
      expect(deserialized.includeDomains, rule.includeDomains);
      expect(deserialized.excludeDomains, rule.excludeDomains);
    });

    test('NetworkBlockRule preserves first-party-only matching after round trip', () {
      final rule = AdblockPlusParser().parse(_bytes(r'||ads.com^$1p')).single;

      final deserialized = serializer.testRuleRoundTrip(rule);

      expect(
        deserialized.matchesRequest(
          _request('https://ads.com/script.js', sourceUrl: 'https://ads.com'),
        ),
        isTrue,
      );
      expect(
        deserialized.matchesRequest(
          _request('https://ads.com/script.js', sourceUrl: 'https://example.com'),
        ),
        isFalse,
      );
    });

    test('NetworkExceptionRule preserves first-party-only matching after round trip', () {
      final rule = AdblockPlusParser().parse(_bytes(r'@@||ads.com^$first-party')).single;

      final deserialized = serializer.testRuleRoundTrip(rule);

      expect(deserialized, isA<NetworkExceptionRule>());
      expect(
        deserialized.matchesRequest(
          _request('https://ads.com/script.js', sourceUrl: 'https://ads.com'),
        ),
        isTrue,
      );
      expect(
        deserialized.matchesRequest(
          _request('https://ads.com/script.js', sourceUrl: 'https://example.com'),
        ),
        isFalse,
      );
    });

    test(
      'NetworkBlockRule serialized and deserialized accurately with empty collections and nulls',
      () {
        const rule = NetworkBlockRule(
          pattern: 'example.com',
        );

        final deserialized = serializer.testRuleRoundTrip(rule) as NetworkBlockRule;

        expect(deserialized.pattern, rule.pattern);
        expect(deserialized.resourceTypes, isEmpty);
        expect(deserialized.isThirdPartyOnly, isFalse);
        expect(deserialized.isImportant, isFalse);
        expect(deserialized.isMatchCase, isFalse);
        expect(deserialized.includeDomains, isNull);
        expect(deserialized.excludeDomains, isNull);
      },
    );

    test('NetworkExceptionRule serialized and deserialized accurately', () {
      const rule = NetworkExceptionRule(
        pattern: 'exception.com',
        resourceTypes: {ResourceType.document},
        isImportant: true,
        isMatchCase: true,
      );

      final deserialized = serializer.testRuleRoundTrip(rule) as NetworkExceptionRule;

      expect(deserialized.pattern, rule.pattern);
      expect(deserialized.resourceTypes, {ResourceType.document});
      expect(deserialized.isThirdPartyOnly, isFalse);
      expect(deserialized.isImportant, isTrue);
      expect(deserialized.isMatchCase, isTrue);
    });

    test('CosmeticHideRule serialized and deserialized accurately with null or empty domains', () {
      const rule1 = CosmeticHideRule(selector: '.ad-banner');
      const rule2 = CosmeticHideRule(selector: '#sponsored', domains: []);

      final deserialized1 = serializer.testRuleRoundTrip(rule1) as CosmeticHideRule;
      final deserialized2 = serializer.testRuleRoundTrip(rule2) as CosmeticHideRule;

      expect(deserialized1.selector, rule1.selector);
      expect(deserialized1.domains, isNull);

      expect(deserialized2.selector, rule2.selector);
      expect(deserialized2.domains, isEmpty);
    });

    test('CosmeticHideRule preserves include and exclude domains after round trip', () {
      const rule = CosmeticHideRule(
        selector: '.ad-banner',
        includeDomains: ['example.com'],
        excludeDomains: ['sub.example.com'],
      );

      final deserialized = serializer.testRuleRoundTrip(rule) as CosmeticHideRule;

      expect(deserialized.selector, rule.selector);
      expect(deserialized.domains, ['example.com']);
      expect(deserialized.includeDomains, rule.includeDomains);
      expect(deserialized.excludeDomains, rule.excludeDomains);
    });

    test('CosmeticExceptionRule serialized and deserialized accurately', () {
      const rule = CosmeticExceptionRule(selector: '.safe-banner', domains: ['safe.com']);

      final deserialized = serializer.testRuleRoundTrip(rule) as CosmeticExceptionRule;

      expect(deserialized.selector, rule.selector);
      expect(deserialized.domains, rule.domains);
    });

    test('CosmeticExceptionRule preserves include and exclude domains after round trip', () {
      const rule = CosmeticExceptionRule(
        selector: '.safe-banner',
        includeDomains: ['example.com'],
        excludeDomains: ['sub.example.com'],
      );

      final deserialized = serializer.testRuleRoundTrip(rule) as CosmeticExceptionRule;

      expect(deserialized.selector, rule.selector);
      expect(deserialized.domains, ['example.com']);
      expect(deserialized.includeDomains, rule.includeDomains);
      expect(deserialized.excludeDomains, rule.excludeDomains);
    });

    test(
      'ScriptletRule serialized and deserialized accurately including multiple args and null domains',
      () {
        const rule = ScriptletRule(
          scriptletName: 'prevent-popups',
          args: ['arg1', 'arg2', 'arg3', 'arg4', 'arg5'],
        );
        const ruleEmptyArgs = ScriptletRule(
          scriptletName: 'noop',
          domains: ['example.com'],
        );

        final deserialized = serializer.testRuleRoundTrip(rule) as ScriptletRule;
        final deserializedEmpty = serializer.testRuleRoundTrip(ruleEmptyArgs) as ScriptletRule;

        expect(deserialized.scriptletName, rule.scriptletName);
        expect(deserialized.args, rule.args);
        expect(deserialized.domains, isNull);

        expect(deserializedEmpty.args, isEmpty);
        expect(deserializedEmpty.domains, ['example.com']);
      },
    );

    test(
      'CssInjectRule serialized and deserialized accurately handling quotes, special chars, and null domain',
      () {
        const rule = CssInjectRule(
          css: 'body { content: "fake!"; background: url("data:image/png;base64,..."); }',
        );

        final deserialized = serializer.testRuleRoundTrip(rule) as CssInjectRule;

        expect(deserialized.css, rule.css);
        expect(deserialized.domain, isNull);
      },
    );
  });

  group('EngineSerializer Integration Tests', () {
    late EngineSerializer serializer;

    setUp(() {
      serializer = EngineSerializer();
    });

    test('serializes and deserializes engine with zero rules without errors', () {
      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytes = serializer.serialize(engine);
      final deserialized = serializer.deserialize(bytes);

      expect(deserialized.trieBuffer, isEmpty);
      expect(deserialized.trieRules, isEmpty);
      expect(deserialized.tokenDispatchTable, isEmpty);
      expect(deserialized.fallbackRules, isEmpty);
      expect(deserialized.cosmeticHideRules, isEmpty);
      expect(deserialized.cosmeticExceptionRules, isEmpty);
      expect(deserialized.scriptletRules, isEmpty);
      expect(deserialized.cssInjectRules, isEmpty);
    });

    test('serializes and deserializes engine with only trieRules', () {
      const rule = NetworkBlockRule(pattern: 'trie-pattern');
      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List.fromList([1, 2, 3]),
        trieRules: [rule],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytes = serializer.serialize(engine);
      final deserialized = serializer.deserialize(bytes);

      expect(deserialized.trieBuffer, [1, 2, 3]);
      expect(deserialized.trieRules.length, 1);
      expect((deserialized.trieRules.first as NetworkBlockRule).pattern, 'trie-pattern');
      expect(deserialized.tokenDispatchTable, isEmpty);
    });

    test(
      'serializes and deserializes engine with tokenDispatchTable accurately handling 0-key and large buckets',
      () {
        const rule = NetworkBlockRule(pattern: 'token-pattern');
        final engine = CompiledFilterEngine(
          totalRules: 0,
          trieBuffer: Uint32List(0),
          trieRules: [],
          tokenDispatchTable: {
            0: [rule],
            999: List.generate(500, (i) => rule),
          },
          fallbackRules: {},
          cosmeticHideRules: {},
          cosmeticExceptionRules: {},
          scriptletRules: {},
          cssInjectRules: {},
        );

        final bytes = serializer.serialize(engine);
        final deserialized = serializer.deserialize(bytes);

        expect(deserialized.tokenDispatchTable.containsKey(0), isTrue);
        expect(deserialized.tokenDispatchTable[0]!.first, isA<NetworkBlockRule>());
        expect(deserialized.tokenDispatchTable[999]!.length, 500);
      },
    );

    test('preserves real 40-bit token dispatch keys after round trip', () {
      final key = 'banner'.extractTokensAsInt().first;
      const rule = NetworkBlockRule(pattern: 'banner');
      final engine = CompiledFilterEngine(
        totalRules: 1,
        trieBuffer: Uint32List(0),
        trieRules: [],
        tokenDispatchTable: {
          key: [rule],
        },
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final deserialized = serializer.deserialize(serializer.serialize(engine));

      expect(key, greaterThan(0xFFFFFFFF));
      expect(deserialized.tokenDispatchTable, contains(key));
      expect(deserialized.tokenDispatchTable[key]!.single, isA<NetworkBlockRule>());
    });

    test('serializes and deserializes engine with fallbackRules accurately', () {
      const rule = NetworkBlockRule(pattern: 'fallback');
      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [],
        tokenDispatchTable: {},
        fallbackRules: {rule},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytes = serializer.serialize(engine);
      final deserialized = serializer.deserialize(bytes);

      expect(deserialized.fallbackRules.length, 1);
      expect((deserialized.fallbackRules.first as NetworkBlockRule).pattern, 'fallback');
    });

    test(
      'serializes and deserializes engine with cosmeticHideRules and cosmeticExceptionRules accurately handling "*" and multiple domains',
      () {
        const hideRule = CosmeticHideRule(selector: '.hide');
        const exceptionRule = CosmeticExceptionRule(selector: '.hide');
        final engine = CompiledFilterEngine(
          totalRules: 0,
          trieBuffer: Uint32List(0),
          trieRules: [],
          tokenDispatchTable: {},
          fallbackRules: {},
          cosmeticHideRules: {
            '*': [hideRule],
            'a.com': [hideRule, hideRule],
          },
          cosmeticExceptionRules: {
            '*': [exceptionRule],
            'b.com': [exceptionRule, exceptionRule, exceptionRule],
          },
          scriptletRules: {},
          cssInjectRules: {},
        );

        final bytes = serializer.serialize(engine);
        final deserialized = serializer.deserialize(bytes);

        expect(deserialized.cosmeticHideRules['*']!.length, 1);
        expect(deserialized.cosmeticHideRules['a.com']!.length, 2);

        expect(deserialized.cosmeticExceptionRules['*']!.length, 1);
        expect(deserialized.cosmeticExceptionRules['b.com']!.length, 3);
      },
    );

    test('serializes and deserializes fully populated engine', () {
      const networkRule = NetworkBlockRule(pattern: 'net');
      const cosmeticRule = CosmeticHideRule(selector: '.cls');
      const cosmeticExceptionRule = CosmeticExceptionRule(selector: '.cls');
      const scriptletRule = ScriptletRule(scriptletName: 'sc');
      const cssRule = CssInjectRule(css: 'body{}');

      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List.fromList([4, 5]),
        trieRules: [networkRule],
        tokenDispatchTable: {
          1: [networkRule],
        },
        fallbackRules: {networkRule},
        cosmeticHideRules: {
          '*': [cosmeticRule],
        },
        cosmeticExceptionRules: {
          '*': [cosmeticExceptionRule],
        },
        scriptletRules: {
          '*': [scriptletRule],
        },
        cssInjectRules: {
          '*': [cssRule],
        },
      );

      final bytes = serializer.serialize(engine);
      final deserialized = serializer.deserialize(bytes);

      expect(deserialized.trieRules, isNotEmpty);
      expect(deserialized.tokenDispatchTable, isNotEmpty);
      expect(deserialized.fallbackRules, isNotEmpty);
      expect(deserialized.cosmeticHideRules, isNotEmpty);
      expect(deserialized.cosmeticExceptionRules, isNotEmpty);
      expect(deserialized.scriptletRules, isNotEmpty);
      expect(deserialized.cssInjectRules, isNotEmpty);
    });

    test('rule pool deduplication: structural size of sharing same rule vs duplicates', () {
      const rule1 = NetworkBlockRule(pattern: 'rule1');
      const rule2 = NetworkBlockRule(pattern: 'rule2');
      const rule3 = NetworkBlockRule(pattern: 'rule3');
      const sharedRule = NetworkBlockRule(pattern: 'shared');

      final engineWithDuplicates = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [rule1, rule2, rule3],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final engineWithShared = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [sharedRule, sharedRule, sharedRule],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytesWithDuplicates = serializer.serialize(engineWithDuplicates);
      final bytesWithShared = serializer.serialize(engineWithShared);

      expect(bytesWithShared.length, lessThan(bytesWithDuplicates.length));
    });

    test('rule pool keeps first-party-only rule distinct from unconstrained rule', () {
      final rules = AdblockPlusParser()
          .parse(_bytes('||ads.com^\n||ads.com^\$first-party'))
          .cast<NetworkBlockRule>()
          .toList();
      final engine = CompiledFilterEngine(
        totalRules: rules.length,
        trieBuffer: Uint32List(0),
        trieRules: rules,
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final restored = serializer.deserialize(serializer.serialize(engine));

      expect(restored.trieRules, hasLength(2));
      expect(
        restored.trieRules.where(
          (rule) => rule.matchesRequest(
            _request('https://ads.com/script.js', sourceUrl: 'https://example.com'),
          ),
        ),
        hasLength(1),
      );
    });

    test('maintains identical object references via rule pool deduplication across sections', () {
      const sharedRule = NetworkBlockRule(pattern: 'shared');

      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [sharedRule],
        tokenDispatchTable: {
          1: [sharedRule],
        },
        fallbackRules: {sharedRule},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytes = serializer.serialize(engine);
      final deserialized = serializer.deserialize(bytes);

      final trieRuleRef = deserialized.trieRules.first;
      final dispatchRuleRef = deserialized.tokenDispatchTable[1]!.first;
      final fallbackRuleRef = deserialized.fallbackRules.first;

      expect(identical(trieRuleRef, dispatchRuleRef), isTrue);
      expect(identical(dispatchRuleRef, fallbackRuleRef), isTrue);
    });

    test('deserialized fallback candidates preserve precedence pruning behavior', () {
      final trieCompiler = HostnameTrieCompiler()
        ..tryAddRule(const NetworkBlockRule(pattern: '||ads.com^'));
      final trie = trieCompiler.build();
      final engine = CompiledFilterEngine(
        totalRules: 3,
        trieBuffer: trie.buffer,
        trieRules: trie.rules,
        tokenDispatchTable: {},
        fallbackRules: {
          const NetworkBlockRule(pattern: '/[/'),
          const NetworkExceptionRule(pattern: 'script.js', isImportant: true),
        },
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final restored = serializer.deserialize(serializer.serialize(engine));
      final matcher = FilterMatcher(FilterEngineRef(restored));

      expect(
        () => matcher.matchNetworkRequest(
          _request('https://ads.com/script.js', sourceUrl: 'https://publisher.com'),
        ),
        returnsNormally,
      );
      expect(
        matcher.matchNetworkRequest(
          _request('https://ads.com/script.js', sourceUrl: 'https://publisher.com'),
        ),
        isA<Allow>(),
      );
    });

    test('trieBuffer deserialization returns a view into original bytes (zero-copy)', () {
      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List.fromList([10, 20, 30]),
        trieRules: [],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytes = serializer.serialize(engine);
      final deserialized = serializer.deserialize(bytes);

      expect(deserialized.trieBuffer.offsetInBytes, greaterThan(0));
      expect(deserialized.trieBuffer, [10, 20, 30]);
    });

    test(
      'mutating one deserialized trieBuffer does not affect independently deserialized engine',
      () {
        final engine = CompiledFilterEngine(
          totalRules: 0,
          trieBuffer: Uint32List.fromList([10, 20, 30]),
          trieRules: [],
          tokenDispatchTable: {},
          fallbackRules: {},
          cosmeticHideRules: {},
          cosmeticExceptionRules: {},
          scriptletRules: {},
          cssInjectRules: {},
        );

        final bytes = serializer.serialize(engine);
        final engine1 = serializer.deserialize(bytes);
        final engine2 = serializer.deserialize(Uint8List.fromList(bytes));

        engine1.trieBuffer[0] = 99;

        expect(engine2.trieBuffer[0], 10);
      },
    );
  });

  group('Performance & Stress Tests', () {
    late EngineSerializer serializer;

    setUp(() {
      serializer = EngineSerializer();
    });

    CompiledFilterEngine buildEngine(int totalRules) {
      final networkCount = (totalRules * 0.7).toInt();
      final cosmeticCount = (totalRules * 0.2).toInt();
      final fallbackCount = totalRules - networkCount - cosmeticCount;

      final networkRules = List.generate(
        networkCount,
        (i) => NetworkBlockRule(pattern: 'pattern$i.com'),
      );
      final cosmeticHideRules = List.generate(
        cosmeticCount,
        (i) => CosmeticHideRule(selector: '.ad$i'),
      );
      final cosmeticMap = <String, List<CosmeticHideRule>>{};
      for (var i = 0; i < cosmeticHideRules.length; i++) {
        final domain = 'domain${i % 2000}.com';
        cosmeticMap.putIfAbsent(domain, () => []).add(cosmeticHideRules[i]);
      }
      final fallbackRules = List.generate(
        fallbackCount,
        (i) => NetworkBlockRule(pattern: '*ad$i*'),
      );

      return CompiledFilterEngine(
        totalRules: totalRules,
        trieBuffer: Uint32List(1000),
        trieRules: networkRules,
        tokenDispatchTable: {
          for (var i = 0; i < networkRules.length; i += 10) i: [networkRules[i]],
        },
        fallbackRules: fallbackRules.toSet(),
        cosmeticHideRules: cosmeticMap,
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );
    }

    test('serializes 100,000 rules within 500ms', () {
      final engine = buildEngine(100_000);

      final stopwatch = Stopwatch()..start();
      serializer.serialize(engine);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('serializes and deserializes 100,000 rules full cycle within 1000ms', () {
      final engine = buildEngine(100_000);

      final stopwatch = Stopwatch()..start();
      final bytes = serializer.serialize(engine);
      serializer.deserialize(bytes);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('binary output size for 100,000 rules is below 3MB', () {
      final engine = buildEngine(100_000);

      final bytes = serializer.serialize(engine);
      final sizeInMb = bytes.lengthInBytes / (1024 * 1024);
      expect(sizeInMb, lessThan(3));
    });

    test('repeated serialization/deserialization cycles do not degrade or bloat size', () {
      const rule = NetworkBlockRule(pattern: 'repeat');
      var engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [rule],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      var initialSize = -1;
      for (var i = 0; i < 10; i++) {
        final bytes = serializer.serialize(engine);
        if (initialSize == -1) {
          initialSize = bytes.length;
        } else {
          expect(bytes.length, initialSize);
        }
        engine = serializer.deserialize(bytes);
      }
    });

    test('deserialization of an existing binary acts quickly under 100ms mimicking cold start', () {
      final engine = buildEngine(100_000);

      final bytes = serializer.serialize(engine);

      final stopwatch = Stopwatch()..start();
      serializer.deserialize(bytes);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });
  });

  group('Edge Cases & Corrupted Data Tests', () {
    late EngineSerializer serializer;

    setUp(() {
      serializer = EngineSerializer();
    });

    test('deserialization of empty buffer throws FormatException, not RangeError', () {
      expect(
        () => serializer.deserialize(Uint8List(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('deserialization of truncated binary buffer throws FormatException', () {
      const rule = NetworkBlockRule(pattern: 'truncate');
      final engine = CompiledFilterEngine(
        totalRules: 0,
        trieBuffer: Uint32List(0),
        trieRules: [rule],
        tokenDispatchTable: {},
        fallbackRules: {},
        cosmeticHideRules: {},
        cosmeticExceptionRules: {},
        scriptletRules: {},
        cssInjectRules: {},
      );

      final bytes = serializer.serialize(engine);
      final truncatedBytes = bytes.view(0, bytes.length - 10);

      expect(
        () => serializer.deserialize(truncatedBytes),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'deserialization of random noise bytes safely throws FormatException without crashing',
      () {
        final randomBytes = Uint8List.fromList(List.generate(100, (i) => i * 13 % 256));

        expect(
          () => serializer.deserialize(randomBytes),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('rule with completely empty string pattern saves and restores properly', () {
      const rule = NetworkBlockRule(pattern: '');

      final deserialized = serializer.testRuleRoundTrip(rule) as NetworkBlockRule;

      expect(deserialized.pattern, '');
    });

    test('rule with extreme 65535 byte pattern string saves and restores safely', () {
      final longString = 'A' * 65535;
      final rule = NetworkBlockRule(pattern: longString);

      final deserialized = serializer.testRuleRoundTrip(rule) as NetworkBlockRule;

      expect(deserialized.pattern, longString);
    });

    test(
      'TrieBuffer handles Uint32List consisting of zeros safely, specifically charCode 0 node',
      () {
        final engine = CompiledFilterEngine(
          totalRules: 0,
          trieBuffer: Uint32List.fromList([0, 0, 0, 0, 0]),
          trieRules: [],
          tokenDispatchTable: {},
          fallbackRules: {},
          cosmeticHideRules: {},
          cosmeticExceptionRules: {},
          scriptletRules: {},
          cssInjectRules: {},
        );

        final bytes = serializer.serialize(engine);
        final deserialized = serializer.deserialize(bytes);

        expect(deserialized.trieBuffer.every((element) => element == 0), isTrue);
        expect(deserialized.trieBuffer.length, 5);
      },
    );
  });
}
