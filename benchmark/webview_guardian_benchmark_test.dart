import 'package:flutter_test/flutter_test.dart';

import 'src/webview_guardian_benchmark_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('webview_guardian benchmark suite', runWebViewGuardianBenchmarks);
}
