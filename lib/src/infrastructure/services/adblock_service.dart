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
  final List<Timer> _updateTimers = [];
  String? _storagePath;
  late final _AdblockJobCoordinator _jobs = _AdblockJobCoordinator(
    runBuildJob: _runBuildJob,
    runClearCacheJob: _runClearCacheJob,
    onCacheInvalidated: _resetEngine,
    isDisposed: () => _isDisposed,
  );
  bool _isDisposed = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _acceptsCommands = false;
  var _latestBuildVersion = 0;
  int? _runningBuildVersion;

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
  }) {
    _ensureNotDisposed();
    if (_isInitialized || _isInitializing) {
      throw StateError('AdblockService is already initialized.');
    }
    _isInitializing = true;
    return _init(
      subscriptions: subscriptions,
      httpOptions: httpOptions,
      observer: observer,
      storagePath: storagePath,
    );
  }

  Future<void> _init({
    required List<FilterSubscription> subscriptions,
    required FilterHttpOptions httpOptions,
    required WebViewObserver? observer,
    required String? storagePath,
  }) async {
    PlatformInAppWebViewController.debugLoggingSettings.enabled = false;

    try {
      _subscriptions
        ..clear()
        ..addAll(subscriptions);
      _httpOptions = httpOptions;
      _observer = observer;

      _storagePath = storagePath ?? (await getApplicationSupportDirectory()).path;
      if (_isDisposed) return;

      _jobRunner ??= FilterIsolateManager(
        onEngineReady: _onEngineReady,
        onWorkerEvent: (event) => _observer?.onEvent(event),
        onWorkerError: (error) => _observer?.onError(error),
      );
      _acceptsCommands = true;

      await _scheduleBuildJob(_subscriptions);

      if (_isDisposed) return;

      _isInitialized = true;
      _setupTimers();
    } finally {
      _isInitializing = false;
    }
  }

  void _onEngineReady(
    CompiledFilterEngine engine,
    bool fromCache,
    int totalRules,
    Duration compilationTime,
  ) {
    if (_isDisposed || _runningBuildVersion != _latestBuildVersion) return;

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
  Future<void> updateSubscriptions(List<FilterSubscription> newSubscriptions) {
    _ensureReadyForCommand();
    isReady.value = false;
    _subscriptions
      ..clear()
      ..addAll(newSubscriptions);

    _setupTimers();

    return _scheduleBuildJob(_subscriptions);
  }

  /// Sends a command to clear the local filter cache. The isolate will delete downloaded files and compiled engines.
  Future<void> clearCache() {
    _ensureReadyForCommand();
    return _scheduleClearCacheJob();
  }

  void _resetEngine() {
    _latestBuildVersion++;
    _engineRef.update(CompiledFilterEngine.empty());
    _ruleCountController.add(0);
    unawaited(_trafficInterceptor?.onEngineUpdated());
  }

  Future<void> _scheduleBuildJob(List<FilterSubscription> subscriptions) {
    _latestBuildVersion++;
    return _jobs.scheduleBuild(
      _AdblockBuildJob(
        subscriptions: List<FilterSubscription>.unmodifiable(subscriptions),
        httpOptions: _httpOptions,
        storagePath: _storagePath,
        useTestClient: _useForTesting,
        version: _latestBuildVersion,
      ),
    );
  }

  Future<void> _runBuildJob(_AdblockBuildJob job) async {
    final effectiveVersion = job.version < _latestBuildVersion
        ? ++_latestBuildVersion
        : job.version;
    _runningBuildVersion = effectiveVersion;
    try {
      await _jobRunner!.runBuildJob(
        subscriptions: job.subscriptions,
        httpOptions: job.httpOptions,
        storagePath: job.storagePath,
        useTestClient: job.useTestClient,
      );
    } on Object catch (error, stackTrace) {
      _observer?.onError(
        IsolateCrashError('Filter worker job failed', cause: '$error\n$stackTrace'),
      );
    } finally {
      if (_runningBuildVersion == effectiveVersion) _runningBuildVersion = null;
    }
  }

  Future<void> _scheduleClearCacheJob() {
    return _jobs.scheduleClearCache();
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

  void _setupTimers() {
    for (final timer in _updateTimers) {
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
      final subs = List<FilterSubscription>.unmodifiable(entry.value);

      _updateTimers.add(
        Timer.periodic(interval, (_) {
          unawaited(_scheduleBuildJob(subs));
        }),
      );
    }
  }

  void _ensureReadyForCommand() {
    _ensureNotDisposed();
    if (!_isInitialized && !_acceptsCommands) {
      throw StateError('AdblockService must be initialized before use.');
    }
  }

  void _ensureNotDisposed() {
    if (_isDisposed) throw StateError('AdblockService has been disposed.');
  }

  /// Disposes the service and its resources.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _acceptsCommands = false;
    unawaited(_ruleCountController.close());
    isReady.dispose();
    for (final timer in _updateTimers) {
      timer.cancel();
    }
    _updateTimers.clear();
    _jobRunner?.dispose();
    _jobs.dispose();
  }
}

@internal
extension TestAdblockService on AdblockService {
  /// Creates an [AdblockService] instance configured for testing with a mock filter engine.
  @visibleForTesting
  static AdblockService create() => AdblockService._forTest();
}

final class _AdblockJobCoordinator {
  _AdblockJobCoordinator({
    required this.runBuildJob,
    required this.runClearCacheJob,
    required this.onCacheInvalidated,
    required this.isDisposed,
  });

  final Future<void> Function(_AdblockBuildJob job) runBuildJob;
  final Future<void> Function() runClearCacheJob;
  final void Function() onCacheInvalidated;
  final bool Function() isDisposed;

  Future<void>? _activeJob;
  List<Completer<void>> _activeCompleters = [];
  _AdblockBuildJob? _pendingBuild;
  final List<Completer<void>> _pendingBuildCompleters = [];
  final List<Completer<void>> _pendingClearCompleters = [];
  bool _pendingClearCache = false;

  Future<void> scheduleBuild(_AdblockBuildJob job) {
    final completer = Completer<void>();
    final activeJob = _activeJob;
    if (activeJob != null) {
      _pendingBuild = job;
      _pendingBuildCompleters.add(completer);
      return completer.future;
    }

    _startBuild(job, [completer]);
    return completer.future;
  }

  Future<void> scheduleClearCache() {
    final completer = Completer<void>();
    onCacheInvalidated();

    if (_activeJob != null) {
      _pendingClearCache = true;
      _pendingClearCompleters.add(completer);
      return completer.future;
    }

    _startClearCache([completer]);
    return completer.future;
  }

  void dispose() {
    for (final completer in _pendingBuildCompleters) {
      if (!completer.isCompleted) completer.complete();
    }
    for (final completer in _pendingClearCompleters) {
      if (!completer.isCompleted) completer.complete();
    }
    for (final completer in _activeCompleters) {
      if (!completer.isCompleted) completer.complete();
    }
    _pendingBuild = null;
    _pendingBuildCompleters.clear();
    _pendingClearCompleters.clear();
    _activeCompleters = [];
    _pendingClearCache = false;
  }

  void _startBuild(_AdblockBuildJob buildJob, List<Completer<void>> completers) {
    final job = Future<void>.sync(() => runBuildJob(buildJob));
    _activeJob = job;
    _activeCompleters = completers;
    unawaited(_completeJob(job, completers));
  }

  void _startClearCache(List<Completer<void>> completers) {
    final job = Future<void>.sync(runClearCacheJob);
    _activeJob = job;
    _activeCompleters = completers;
    unawaited(_completeJob(job, completers));
  }

  Future<void> _completeJob(Future<void> job, List<Completer<void>> completers) async {
    try {
      await job;
      for (final completer in completers) {
        if (!completer.isCompleted) completer.complete();
      }
    } on Object catch (error, stackTrace) {
      for (final completer in completers) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    } finally {
      _startNextPendingJob();
    }
  }

  void _startNextPendingJob() {
    _activeJob = null;
    _activeCompleters = [];
    if (isDisposed()) return;

    if (_pendingClearCache) {
      _pendingClearCache = false;
      final completers = List<Completer<void>>.of(_pendingClearCompleters);
      _pendingClearCompleters.clear();
      _startClearCache(completers);
      return;
    }

    final pendingBuild = _pendingBuild;
    if (pendingBuild == null) return;
    final completers = List<Completer<void>>.of(_pendingBuildCompleters);
    _pendingBuild = null;
    _pendingBuildCompleters.clear();
    _startBuild(pendingBuild, completers);
  }
}

final class _AdblockBuildJob {
  const _AdblockBuildJob({
    required this.subscriptions,
    required this.httpOptions,
    required this.storagePath,
    required this.useTestClient,
    required this.version,
  });

  final List<FilterSubscription> subscriptions;
  final FilterHttpOptions httpOptions;
  final String? storagePath;
  final bool useTestClient;
  final int version;
}
