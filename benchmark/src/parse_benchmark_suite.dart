import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

import 'benchmark_contract.dart';

final class ParseBenchmarkSuite extends BenchmarkSuite<void> {
  const ParseBenchmarkSuite(super.runner, this.fixtures);

  final BenchmarkFixtures fixtures;

  @override
  void run() {
    for (final entry in <String, Uint8List>{
      'abp-small': fixtures.small,
      'abp-medium': fixtures.medium,
      'abp-large': fixtures.large,
      'hosts': fixtures.hosts,
      'domain-list': fixtures.domainList,
    }.entries) {
      final setupRules = FilterListParserFactory.resolve(
        entry.value,
      ).parse(entry.value).toList(growable: false);
      final networkCount = setupRules
          .where((rule) => rule is NetworkBlockRule || rule is NetworkExceptionRule)
          .length;
      runner.measureSync(
        id: 'parse.${entry.key}',
        suite: 'parse',
        fixture: entry.key,
        scenario: 'factory resolve and fully consume parser',
        samples: entry.key == 'abp-large' ? 5 : 7,
        operation: () {
          final rules = FilterListParserFactory.resolve(
            entry.value,
          ).parse(entry.value).toList(growable: false);
          return rules.length;
        },
        ruleCounts: {'parsed': setupRules.length, 'network': networkCount},
        metrics: {'inputBytes': entry.value.length},
      );
      checkBenchmarkInvariant(setupRules.isNotEmpty, '${entry.key} produced no rules.');
    }
  }
}
