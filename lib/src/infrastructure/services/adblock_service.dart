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
  AdblockService._forTest({FilterJobRunner? jobRunner})
    : _useForTesting = true,
      _jobRunner = jobRunner;

  /// Creates an [AdblockService] instance with a custom job runner for testing.
  @visibleForTesting
  factory AdblockService.createForTest({required FilterJobRunner jobRunner}) =>
      AdblockService._forTest(jobRunner: jobRunner);

  final bool _useForTesting;

  FilterJobRunner? _jobRunner;
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
  String? _storagePath;
  Future<void>? _activeJob;
  int? _activeBuildGeneration;
  int _cacheClearGeneration = 0;
  List<FilterSubscription>? _pendingSubscriptions;
  bool _pendingClearCache = false;
  bool _isDisposed = false;

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

    _storagePath = storagePath ?? (await getApplicationSupportDirectory()).path;

    _jobRunner ??= FilterIsolateManager(
      onEngineReady: _onEngineReady,
      onWorkerEvent: (event) => _observer?.onEvent(event),
      onWorkerError: (error) => _observer?.onError(error),
    );

    await _scheduleBuildJob(_subscriptions);

    _setupTimers();
  }

  void _onEngineReady(
    CompiledFilterEngine engine,
    bool fromCache,
    int totalRules,
    Duration compilationTime,
  ) {
    if (_activeBuildGeneration != _cacheClearGeneration) return;

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

    unawaited(_scheduleBuildJob(_subscriptions));
  }

  /// Sends a command to clear the local filter cache. The isolate will delete downloaded files and compiled engines.
  void clearCache() {
    _scheduleClearCacheJob();
  }

  void _resetEngine() {
    _engineRef.update(CompiledFilterEngine.empty());
    _ruleCountController.add(0);
    unawaited(_trafficInterceptor?.onEngineUpdated());
  }

  Future<void> _scheduleBuildJob(List<FilterSubscription> subscriptions) {
    final snapshot = List<FilterSubscription>.of(subscriptions);
    if (_activeJob != null) {
      _pendingSubscriptions = snapshot;
      return _activeJob!;
    }

    _activeBuildGeneration = _cacheClearGeneration;
    final job = _runBuildJob(snapshot).whenComplete(_runPendingJobIfNeeded);
    _activeJob = job;
    return job;
  }

  Future<void> _runBuildJob(List<FilterSubscription> subscriptions) async {
    try {
      await _jobRunner!.runBuildJob(
        subscriptions: subscriptions,
        httpOptions: _httpOptions,
        storagePath: _storagePath,
        useTestClient: _useForTesting,
      );
    } on Object catch (error, stackTrace) {
      _observer?.onError(
        IsolateCrashError('Filter worker job failed', cause: '$error\n$stackTrace'),
      );
    }
  }

  void _scheduleClearCacheJob() {
    _cacheClearGeneration++;
    _resetEngine();

    if (_activeJob != null) {
      _pendingClearCache = true;
      return;
    }

    _activeBuildGeneration = null;
    _activeJob = _runClearCacheJob().whenComplete(_runPendingJobIfNeeded);
  }

  Future<void> _runClearCacheJob() async {
    try {
      await _jobRunner!.runClearCacheJob(
        storagePath: _storagePath,
        useTestClient: _useForTesting,
      );
    } on Object catch (error, stackTrace) {
      _observer?.onError(
        IsolateCrashError('Filter worker job failed', cause: '$error\n$stackTrace'),
      );
    }
  }

  void _runPendingJobIfNeeded() {
    _activeJob = null;
    _activeBuildGeneration = null;
    if (_isDisposed) return;

    if (_pendingClearCache) {
      _pendingClearCache = false;
      _scheduleClearCacheJob();
      return;
    }

    final pendingSubscriptions = _pendingSubscriptions;
    if (pendingSubscriptions == null) return;
    _pendingSubscriptions = null;
    unawaited(_scheduleBuildJob(pendingSubscriptions));
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
        unawaited(_scheduleBuildJob(subs));
      });
    }
  }

  /// Disposes the service and its resources.
  void dispose() {
    _isDisposed = true;
    unawaited(_ruleCountController.close());
    isReady.dispose();
    for (final timer in _updateTimers.values) {
      timer.cancel();
    }
    _updateTimers.clear();
    _jobRunner?.dispose();

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
