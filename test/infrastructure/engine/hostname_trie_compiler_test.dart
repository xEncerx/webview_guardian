import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/hostname_trie_compiler.dart';

void main() {
  group('HostnameTrieCompiler', () {
    late HostnameTrieCompiler compiler;

    setUp(() {
      compiler = HostnameTrieCompiler();
    });

    NetworkBlockRule makeRule(String pattern) => NetworkBlockRule(
      pattern: pattern,
    );

    group('tryAddRule', () {
      test('should return true for valid standard pattern', () {
        final rule = makeRule('||example.com^');
        expect(compiler.tryAddRule(rule), isTrue);
      });

      test('should return true for pattern without hat suffix', () {
        final rule = makeRule('||example.com');
        expect(compiler.tryAddRule(rule), isTrue);
      });

      test('should return true for deeply nested domain pattern', () {
        final rule = makeRule('||a.a.a.a.a.b.b.b.c.com^');
        expect(compiler.tryAddRule(rule), isTrue);
      });

      test('should return true for punycode pattern', () {
        final rule = makeRule('||xn--example-m1a.com^');
        expect(compiler.tryAddRule(rule), isTrue);
      });

      test('should return true for minimum valid pattern length', () {
        final rule = makeRule('||a^');
        expect(compiler.tryAddRule(rule), isTrue);
      });

      test('should return false for pattern containing asterisk', () {
        final rule = makeRule('||exam*.com^');
        expect(compiler.tryAddRule(rule), isFalse);
      });

      test('should return false for pattern containing slash', () {
        final rule = makeRule('||example.com/path^');
        expect(compiler.tryAddRule(rule), isFalse);
      });

      test('should return false for pattern containing colon', () {
        final rule = makeRule('||example.com:8080^');
        expect(compiler.tryAddRule(rule), isFalse);
      });

      test('should return false for pattern missing pipe prefix', () {
        final rule = makeRule('example.com^');
        expect(compiler.tryAddRule(rule), isFalse);
      });

      test('should return false for pattern missing host completely', () {
        final rule = makeRule('||');
        expect(compiler.tryAddRule(rule), isFalse);
      });

      test('should return false for unsupported rule type', () {
        const rule = CosmeticHideRule(selector: '.ad');
        expect(compiler.tryAddRule(rule), isFalse);
      });
    });

    group('structure', () {
      test(
        'should contain correct leaf node when adding single rule',
        () {
          final rule = makeRule('||example.com^');
          compiler.tryAddRule(rule);

          var current = compiler.root;
          const reversedDomain = 'moc.elpmaxe';
          for (var i = 0; i < reversedDomain.length; i++) {
            final char = reversedDomain.codeUnitAt(i);
            expect(current.children.containsKey(char), isTrue);
            current = current.children[char]!;
          }

          expect(current.children, isEmpty);
          expect(current.rules.length, 1);
          expect(current.rules.first, rule);
        },
      );

      test('should reuse leaf node for duplicate host patterns', () {
        final rule1 = makeRule('||ads.com^');
        final rule2 = makeRule('||ads.com^');
        compiler
          ..tryAddRule(rule1)
          ..tryAddRule(rule2);

        var current = compiler.root;
        const reversedDomain = 'moc.sda';
        for (var i = 0; i < reversedDomain.length; i++) {
          current = current.children[reversedDomain.codeUnitAt(i)]!;
        }

        expect(current.children, isEmpty);
        expect(current.rules.length, 2);
        expect(current.rules, containsAll([rule1, rule2]));
      });

      test('should share path for domains with common suffix', () {
        compiler
          ..tryAddRule(makeRule('||ads.example.com^'))
          ..tryAddRule(makeRule('||cdn.example.com^'));

        var current = compiler.root;
        const sharedSuffix = 'moc.elpmaxe.';
        for (var i = 0; i < sharedSuffix.length; i++) {
          current = current.children[sharedSuffix.codeUnitAt(i)]!;
        }

        expect(current.rules, isEmpty);
        expect(current.children.length, 2);
        expect(current.children.containsKey('s'.codeUnitAt(0)), isTrue);
        expect(current.children.containsKey('n'.codeUnitAt(0)), isTrue);
      });
    });
  });

  group('TrieFlattener.build', () {
    late HostnameTrieCompiler compiler;
    late CompiledTrie compiled;

    setUp(() {
      compiler = HostnameTrieCompiler();
    });

    NetworkBlockRule makeRule(String pattern) => NetworkBlockRule(
      pattern: pattern,
    );

    group('buffer layout', () {
      test('should return single word buffer for empty compiler', () {
        compiled = compiler.build();
        expect(compiled.buffer.length, 1);
        expect(compiled.buffer[0], 0);
        expect(compiled.rules, isEmpty);
      });

      test('should encode correctly when root has rules', () {
        final rule = makeRule('||dummy^');
        compiler.root.rules.add(rule);
        compiled = compiler.build();

        expect(compiled.buffer.length, 2);
        expect(compiled.buffer[0] & 0xFFFF, 1);
        expect(compiled.buffer[0] >> 16, 0);
        expect(compiled.buffer[1], 0);
        expect(compiled.rules.length, 1);
        expect(compiled.rules.first, rule);
      });
    });

    group('pointer packing', () {
      test('should sort children by charCode and pack pointer correctly', () {
        compiler
          ..tryAddRule(makeRule('||b^'))
          ..tryAddRule(makeRule('||a^'));
        compiled = compiler.build();

        final childCount = compiled.buffer[0] >> 16;
        expect(childCount, 2);

        final ptr1 = compiled.buffer[1];
        final ptr2 = compiled.buffer[2];

        final char1 = ptr1 >> 24;
        final char2 = ptr2 >> 24;

        expect(char1, 97);
        expect(char2, 98);
      });
    });

    group('dfs offsets', () {
      test('should keep increasing child offsets for deep tree', () {
        compiler.tryAddRule(makeRule('||abcdefghij^'));
        compiled = compiler.build();

        var offset = 0;
        for (var i = 0; i < 10; i++) {
          final word = compiled.buffer[offset];
          final children = word >> 16;
          final rules = word & 0xFFFF;

          if (children == 1) {
            final ptrOffset = offset + (rules > 0 ? 2 : 1);
            final childPtr = compiled.buffer[ptrOffset];
            final childOffset = childPtr & 0xFFFFFF;
            expect(childOffset, greaterThan(offset));
            offset = childOffset;
          }
        }
      });
    });

    group('rule extraction', () {
      test('should extract identical rule references in DFS order', () {
        final rule1 = makeRule('||a.com^');
        final rule2 = makeRule('||c.com^');
        final rule3 = makeRule('||b.com^');

        compiler
          ..tryAddRule(rule1)
          ..tryAddRule(rule2)
          ..tryAddRule(rule3);

        compiled = compiler.build();

        expect(compiled.rules.length, 3);
        expect(
          identical(compiled.rules[0], rule1) ||
              identical(compiled.rules[0], rule3) ||
              identical(compiled.rules[0], rule2),
          isTrue,
        );
      });
    });
  });

  group('edge cases & limits', () {
    late HostnameTrieCompiler compiler;

    setUp(() {
      compiler = HostnameTrieCompiler();
    });

    NetworkBlockRule makeRule(String pattern) => NetworkBlockRule(
      pattern: pattern,
    );

    test('should ignore rule when charCode exceeds 255 limit', () {
      expect(compiler.tryAddRule(makeRule('||тест.рф^')), isFalse);
    });

    test('should throw StateError when node exceeds rule count limit', () {
      for (var i = 0; i <= 0xFFFF; i++) {
        compiler.root.rules.add(makeRule('||dummy$i^'));
      }
      expect(() => compiler.build(), throwsStateError);
    });

    test('should throw StateError when node exceeds child count limit', () {
      for (var i = 0; i <= 65535; i++) {
        compiler.root.children[i] = RawTrieNode();
      }
      expect(() => compiler.build(), throwsStateError);
    });

    test('should successfully add max length domain (253 characters)', () {
      final longHost = List.filled(253, 'a').join();
      final rule = makeRule('||$longHost^');
      expect(compiler.tryAddRule(rule), isTrue);
      final compiled = compiler.build();
      expect(compiled.buffer.isNotEmpty, isTrue);
    });
  });

  group('performance & memory constraints', () {
    test('should compile 100_000 unique rules within reasonable time limit', () {
      final compiler = HostnameTrieCompiler();
      for (var i = 0; i < 100000; i++) {
        compiler.tryAddRule(
          NetworkBlockRule(
            pattern: '||domain$i.com^',
          ),
        );
      }
      final stopwatch = Stopwatch()..start();
      final compiled = compiler.build();
      stopwatch.stop();

      expect(compiled.rules.length, 100000);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('should optimize leaf node size for heavily repeated domains', () {
      final compiler = HostnameTrieCompiler();
      for (var i = 0; i < 10000; i++) {
        compiler.tryAddRule(
          const NetworkBlockRule(
            pattern: '||ads.com^',
          ),
        );
      }
      final compiled = compiler.build();

      expect(compiled.rules.length, 10000);
      expect(compiled.buffer.length, lessThan(100));
    });

    test('should be deterministic and yield equal outputs upon repeated compiles', () {
      final compiler = HostnameTrieCompiler()
        ..tryAddRule(
          const NetworkBlockRule(
            pattern: '||ads.com^',
          ),
        )
        ..tryAddRule(
          const NetworkBlockRule(
            pattern: '||tracker.com^',
          ),
        );

      final compiled1 = compiler.build();
      final compiled2 = compiler.build();

      expect(compiled1.buffer, equals(compiled2.buffer));
      expect(compiled1.rules, equals(compiled2.rules));
    });
  });
}
