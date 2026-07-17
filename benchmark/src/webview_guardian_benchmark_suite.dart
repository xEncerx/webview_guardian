import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

import 'benchmark_contract.dart';
import 'benchmark_support.dart';
import 'compile_benchmark_suite.dart';
import 'injection_benchmark_suite.dart';
import 'lookup_benchmark_suite.dart';
import 'parse_benchmark_suite.dart';
import 'serialization_benchmark_suite.dart';
import 'worker_benchmark_suite.dart';

Future<void> runWebViewGuardianBenchmarks() async {
  final runner = BenchmarkRunner();
  final fixtures = BenchmarkFixtures.load();
  runner.loadBaseline(fixtureHashes: fixtures.hashes);

  ParseBenchmarkSuite(runner, fixtures).run();
  final mediumNetworkRules = CompileBenchmarkSuite(runner, fixtures).run();
  await ScriptletLibrary.instance.load();
  final engine = await WorkerBenchmarkSuite(runner, fixtures).run();
  SerializationBenchmarkSuite(runner, engine).run();
  LookupBenchmarkSuite(runner, engine).run();
  InjectionBenchmarkSuite(runner, engine).run();

  checkBenchmarkInvariant(mediumNetworkRules > 0, 'Medium fixture produced no network rules.');
  await runner.report(fixtureHashes: fixtures.hashes);
}
