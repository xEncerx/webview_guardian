import 'package:flutter/foundation.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Instantiates the appropriate [TrafficInterceptor] depending on the platform.
class TrafficInterceptorFactory {
  /// We pass the ready [FilterRepository] directly to the intercepted platform adapter.
  static TrafficInterceptor create(FilterRepository repository) {
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows => WindowsInterceptorAdapter(repository),
      TargetPlatform.android => AndroidInterceptorAdapter(repository),
      _ => throw UnsupportedError('Unsupported platform: $defaultTargetPlatform'),
    };
  }
}
