import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

import 'benchmark_contract.dart';

final class CompileBenchmarkSuite extends BenchmarkSuite<int> {
  const CompileBenchmarkSuite(super.runner, this.fixtures);

  final BenchmarkFixtures fixtures;

  @override
  int run() {
    final smallRules = FilterListParserFactory.resolve(
      fixtures.small,
    ).parse(fixtures.small).toList(growable: false);
    final mediumRules = FilterListParserFactory.resolve(
      fixtures.medium,
    ).parse(fixtures.medium).toList(growable: false);
    final mediumNetworkRules = mediumRules
        .where((rule) => rule is NetworkBlockRule || rule is NetworkExceptionRule)
        .toList(growable: false);
    final uniqueMedium = FilterDeduplicator.deduplicate(mediumRules);

    runner.measureSync(
      id: 'compile.deduplicate-medium',
      suite: 'compile',
      fixture: 'abp-medium',
      scenario: 'deduplicate parsed rules',
      operation: () => FilterDeduplicator.deduplicate(mediumRules).length,
      ruleCounts: {'parsed': mediumRules.length, 'unique': uniqueMedium.length},
      metrics: {'inputBytes': fixtures.medium.length},
    );

    final mergedUnique = FilterDeduplicator.mergeAndDeduplicate([smallRules, mediumRules]);
    runner.measureSync(
      id: 'compile.merge-deduplicate',
      suite: 'compile',
      fixture: 'abp-small+medium',
      scenario: 'merge and deduplicate subscriptions',
      operation: () => FilterDeduplicator.mergeAndDeduplicate([smallRules, mediumRules]).length,
      ruleCounts: {'parsed': smallRules.length + mediumRules.length, 'unique': mergedUnique.length},
      metrics: {'inputBytes': fixtures.small.length + fixtures.medium.length},
    );

    final dispatch = TokenDispatchCompiler.compile(mediumNetworkRules);
    runner.measureSync(
      id: 'compile.token-dispatch-medium',
      suite: 'compile',
      fixture: 'abp-medium',
      scenario: 'TokenDispatchCompiler.compile',
      operation: () {
        final result = TokenDispatchCompiler.compile(mediumNetworkRules);
        return result.table.length + result.fallbackRules.length;
      },
      ruleCounts: {
        'network': mediumNetworkRules.length,
        'tokenBuckets': dispatch.table.length,
        'fallback': dispatch.fallbackRules.length,
      },
    );

    final trie = HostnameTrieCompiler();
    var trieAccepted = 0;
    for (final rule in mediumNetworkRules) {
      if (trie.tryAddRule(rule)) trieAccepted++;
    }
    final builtTrie = trie.build();
    runner.measureSync(
      id: 'compile.hostname-trie-medium',
      suite: 'compile',
      fixture: 'abp-medium',
      scenario: 'tryAddRule and build',
      samples: 5,
      operation: () {
        final compiler = HostnameTrieCompiler();
        mediumNetworkRules.forEach(compiler.tryAddRule);
        final result = compiler.build();
        return result.buffer.length + result.rules.length;
      },
      ruleCounts: {
        'network': mediumNetworkRules.length,
        'trieAccepted': trieAccepted,
        'trieRules': builtTrie.rules.length,
      },
      metrics: {'trieWords': builtTrie.buffer.length},
    );

    return mediumNetworkRules.length;
  }
}
