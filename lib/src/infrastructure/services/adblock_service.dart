import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Orchestrates the ad-blocking components, including background updates,
/// isolate management, and rule evaluation.
///
/// Generally used as a long-lived instance (singleton) provided to WebView instances.
class AdblockService {
  /// Creates an [AdblockService] instance.
  AdblockService() : _useForTesting = false;
  AdblockService._forTest() : _useForTesting = true;

  final bool _useForTesting;

  late final FilterIsolateManager _isolateManager;
  final FilterEngineRef _engineRef = FilterEngineRef(CompiledFilterEngine.empty());

  final _ruleCountController = StreamController<int>.broadcast();

  bool _isEnabled = true;

  FilterRepositoryImpl? _repository;
  InjectionOrchestrator? _orchestrator;
  WebViewObserver? _observer;
  TrafficInterceptor? _trafficInterceptor;

  final List<FilterSubscription> _subscriptions = [];
  FilterHttpOptions _httpOptions = const FilterHttpOptions();
  final Map<String, Timer> _updateTimers = {};

  /// The platforms supported by this ad-blocking service.
  static const List<TargetPlatform> supportedPlatforms = [
    TargetPlatform.android,
    TargetPlatform.windows,
  ];

  /// Whether the ad-blocker is currently enabled.
  ///
  /// Turning this off will bypass request interception and script injection.
  bool get isEnabled => _isEnabled;

  /// Enables or disables the ad-blocker globally.
  set isEnabled(bool value) {
    if (_isEnabled != value) {
      _isEnabled = value;
    }
  }

  /// Whether the filter engine is loaded and ready to evaluate requests.
  final ValueNotifier<bool> isReady = ValueNotifier(false);

  /// The number of currently active rules.
  int get ruleCount => _engineRef.current.totalRules;

  /// Stream of rule count updates.
  Stream<int> get ruleCountStream => _ruleCountController.stream;

  /// The active filter repository, if ready.
  FilterRepository? get repository => _repository;

  /// The active injection orchestrator, if ready.
  InjectionOrchestrator? get orchestrator => _orchestrator;

  /// The traffic interceptor to be used in WebView instances, if ready.
  TrafficInterceptor? get trafficInterceptor => _trafficInterceptor;

  /// The current list of filter subscriptions.
  List<FilterSubscription> get subscriptions => List.unmodifiable(_subscriptions);

  /// Initializes the service by parsing subscriptions and starting the background worker isolate.
  ///
  /// - **[subscriptions]**: A list of [FilterSubscription] objects defining which
  ///   filter lists to load and keep updated. Each subscription contains a URL and
  ///   update settings.
  ///
  /// - **[httpOptions]**: Configuration for fetching filter lists over the network,
  ///   including timeouts, headers, and caching behavior.
  ///
  /// - **[observer]**: An optional [WebViewObserver] that receives events and errors
  ///   from the ad-blocker. Use this for logging, analytics, or UI updates.
  ///
  ///   > Performance Note: The observer's methods are called synchronously on the
  ///   main thread during request interception. Keep implementations lightweight
  ///   (e.g., simple logging). For heavy operations like database writes or
  ///   network calls, use [StreamWebViewObserver] which safely delegates work
  ///   to background listeners without blocking the ad-blocking engine.
  ///
  /// - **[storagePath]**: Optional custom directory path for storing downloaded
  ///   filter lists and compiled engine caches. If not provided, defaults to
  ///   the application's support directory.
  Future<void> init({
    required List<FilterSubscription> subscriptions,
    FilterHttpOptions httpOptions = const FilterHttpOptions(),
    WebViewObserver? observer,
    String? storagePath,
  }) async {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;

    _subscriptions
      ..clear()
      ..addAll(subscriptions);
    _httpOptions = httpOptions;
    _observer = observer;

    final baseDir = storagePath ?? (await getApplicationSupportDirectory()).path;

    _isolateManager = FilterIsolateManager(
      onEngineReady: _onEngineReady,
      onWorkerEvent: (event) => _observer?.onEvent(event),
      onWorkerError: (error) => _observer?.onError(error),
    );

    await _isolateManager.spawn(
      storagePath: baseDir,
      useTestClient: _useForTesting,
    );

    _isolateManager.sendSubscriptions(
      subscriptions: _subscriptions,
      httpOptions: _httpOptions,
    );

    _setupTimers();
  }

  void _onEngineReady(
    CompiledFilterEngine engine,
    bool fromCache,
    int totalRules,
    Duration compilationTime,
  ) {
    _engineRef.update(engine);
    _ruleCountController.add(engine.totalRules);

    if (_repository == null) {
      _repository = FilterRepositoryImpl(
        matcher: FilterMatcher(_engineRef),
        engineRef: _engineRef,
        observer: _observer,
      );
      _orchestrator = InjectionOrchestrator(_repository!);
      _trafficInterceptor = TrafficInterceptorFactory.create(_repository!);
    } else {
      unawaited(_trafficInterceptor?.onEngineUpdated());
    }

    isReady.value = true;
    _observer?.onEvent(
      fromCache
          ? EngineRestoredFromCache(
              totalRules: totalRules,
              compilationTime: compilationTime,
            )
          : EngineCompiled(
              totalRules: totalRules,
              compilationTime: compilationTime,
            ),
    );
  }

  /// Replaces the current filter subscriptions with [newSubscriptions] and requests an update.
  void updateSubscriptions(List<FilterSubscription> newSubscriptions) {
    isReady.value = false;
    _subscriptions
      ..clear()
      ..addAll(newSubscriptions);

    _setupTimers();

    _isolateManager.sendSubscriptions(
      subscriptions: _subscriptions,
      httpOptions: _httpOptions,
    );
  }

  /// Sends a command to clear the local filter cache. The isolate will delete downloaded files and compiled engines.
  void clearCache() {
    _isolateManager.sendClearCacheCommand();
  }

  void _setupTimers() {
    for (final timer in _updateTimers.values) {
      timer.cancel();
    }
    _updateTimers.clear();

    final grouped = <Duration, List<FilterSubscription>>{};
    for (final sub in _subscriptions) {
      final interval = sub.updateInterval;
      if (interval != null) {
        grouped.putIfAbsent(interval, () => []).add(sub);
      }
    }

    for (final entry in grouped.entries) {
      final interval = entry.key;
      final subs = entry.value;

      _updateTimers[interval.toString()] = Timer.periodic(interval, (_) {
        _isolateManager.sendSubscriptions(
          subscriptions: subs,
          httpOptions: _httpOptions,
        );
      });
    }
  }

  /// Disposes the service and its resources.
  void dispose() {
    unawaited(_ruleCountController.close());
    isReady.dispose();
    for (final timer in _updateTimers.values) {
      timer.cancel();
    }
    _updateTimers.clear();
    _isolateManager.dispose();

    // Dispose observer if it supports it
    final observer = _observer;
    if (observer is StreamWebViewObserver) observer.dispose();
  }
}

@internal
extension TestAdblockService on AdblockService {
  /// Creates an [AdblockService] instance configured for testing with a mock filter engine.
  @visibleForTesting
  static AdblockService create() => AdblockService._forTest();
}
