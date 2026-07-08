import 'dart:async';
import 'dart:isolate';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// Called when a new [CompiledFilterEngine] becomes available, either freshly
/// compiled from filter lists or restored from the on-disk cache.
///
/// [fromCache] is `true` when the engine was restored from `compiled_filter_engine.bin`
/// without recompilation.
typedef OnEngineReady =
    void Function(
      CompiledFilterEngine engine,
      bool fromCache,
      int totalRules,
      Duration compilationTime,
    );

/// Called when the worker isolate emits a [WebViewEvent] via [IsolateWebViewObserver].
typedef OnWorkerEvent = void Function(WebViewEvent event);

/// Called when the worker isolate emits a [WebViewError] via [IsolateWebViewObserver].
typedef OnWorkerError = void Function(WebViewError error);

/// Error used when a worker job is cancelled by disposing the manager.
final class FilterIsolateJobCancelled implements Exception {
  /// Creates a cancellation error for the active worker job.
  const FilterIsolateJobCancelled();
}

typedef _PendingInit = ({
  List<FilterSubscription> subscriptions,
  FilterHttpOptions httpOptions,
});

/// Executes filter worker jobs.
abstract interface class FilterJobRunner {
  /// Runs a single build/update job in a worker isolate.
  Future<void> runBuildJob({
    required List<FilterSubscription> subscriptions,
    required FilterHttpOptions httpOptions,
    String? storagePath,
    bool useTestClient = false,
  });

  /// Runs a single cache clear job in a worker isolate.
  Future<void> runClearCacheJob({String? storagePath, bool useTestClient = false});

  /// Releases any currently active worker resources.
  void dispose();
}

/// Manages the lifecycle and communication with the filter parser worker isolate.
class FilterIsolateManager implements FilterJobRunner {
  /// Creates a [FilterIsolateManager] instance.
  FilterIsolateManager({
    required OnEngineReady onEngineReady,
    required OnWorkerEvent onWorkerEvent,
    required OnWorkerError onWorkerError,
  }) : _onEngineReady = onEngineReady,
       _onWorkerEvent = onWorkerEvent,
       _onWorkerError = onWorkerError;

  final OnEngineReady _onEngineReady;
  final OnWorkerEvent _onWorkerEvent;
  final OnWorkerError _onWorkerError;

  ReceivePort? _receivePort;
  ReceivePort? _errorPort;
  Isolate? _isolate;
  SendPort? _workerSendPort;
  Completer<void>? _activeJob;
  bool _completeOnCacheClear = false;

  // Held until WorkerReady arrives - sent immediately after
  _PendingInit? _pendingInit;
  bool _pendingClearCacheCommand = false;

  /// Spawns the worker isolate and sets up communication channels.
  Future<void> spawn({String? storagePath, bool useTestClient = false}) async {
    _disposeWorkerResources();
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();
    _receivePort = receivePort;
    _errorPort = errorPort;
    final isolate = await Isolate.spawn(
      filterParserWorkerEntry,
      (
        sendPort: receivePort.sendPort,
        storagePath: storagePath,
        useTestClient: useTestClient,
      ),
      errorsAreFatal: false,
      onError: errorPort.sendPort,
      debugName: 'FilterParserWorker',
    );

    if (_receivePort != receivePort || _errorPort != errorPort) {
      isolate.kill();
      return;
    }

    _isolate = isolate;

    errorPort.listen((message) {
      if (message is List && message.length == 2) {
        final error = message[0];
        final stackTrace = message[1];
        final workerError = IsolateCrashError('Isolate crashed', cause: '$error\n$stackTrace');
        _onWorkerError(workerError);
        final activeJob = _activeJob;
        _activeJob = null;
        if (activeJob != null && !activeJob.isCompleted) {
          activeJob.completeError(workerError);
        }
        dispose();
      }
    });

    receivePort.listen(_handleMessage);
  }

  @override
  Future<void> runBuildJob({
    required List<FilterSubscription> subscriptions,
    required FilterHttpOptions httpOptions,
    String? storagePath,
    bool useTestClient = false,
  }) {
    if (_activeJob != null) {
      return Future<void>.error(StateError('Filter isolate job is already running.'));
    }

    final completer = Completer<void>();
    _activeJob = completer;
    unawaited(
      spawn(storagePath: storagePath, useTestClient: useTestClient)
          .then((_) {
            if (_activeJob != completer || completer.isCompleted) return;
            sendSubscriptions(subscriptions: subscriptions, httpOptions: httpOptions);
          })
          // ignore: avoid_types_on_closure_parameters
          .onError((Object error, StackTrace stackTrace) {
            if (_activeJob == completer) _activeJob = null;
            if (!completer.isCompleted) completer.completeError(error, stackTrace);
          }),
    );
    return completer.future;
  }

  @override
  Future<void> runClearCacheJob({String? storagePath, bool useTestClient = false}) {
    if (_activeJob != null) {
      return Future<void>.error(StateError('Filter isolate job is already running.'));
    }

    final completer = Completer<void>();
    _activeJob = completer;
    _completeOnCacheClear = true;
    unawaited(
      spawn(storagePath: storagePath, useTestClient: useTestClient)
          .then((_) {
            if (_activeJob != completer || completer.isCompleted) return;
            sendClearCacheCommand();
          })
          // ignore: avoid_types_on_closure_parameters
          .onError((Object error, StackTrace stackTrace) {
            if (_activeJob == completer) {
              _activeJob = null;
              _completeOnCacheClear = false;
            }
            if (!completer.isCompleted) completer.completeError(error, stackTrace);
          }),
    );
    return completer.future;
  }

  /// Sends filter subscriptions and HTTP options to the worker isolate for processing.
  void sendSubscriptions({
    required List<FilterSubscription> subscriptions,
    required FilterHttpOptions httpOptions,
  }) {
    final port = _workerSendPort;
    if (port == null) {
      // Worker not ready yet - queue the command
      _pendingInit = (subscriptions: subscriptions, httpOptions: httpOptions);
      return;
    }
    port.send(InitCommand(subscriptions: subscriptions, httpOptions: httpOptions));
  }

  /// Sends a command to clear the worker isolate's cache.
  void sendClearCacheCommand() {
    final port = _workerSendPort;
    if (port == null) {
      _pendingClearCacheCommand = true;
      return;
    }
    port.send(const ClearCacheCommand());
  }

  /// Sends a shutdown command to the worker isolate and cleans up resources.
  @override
  void dispose() {
    _cancelActiveJob();
    _disposeWorkerResources();
  }

  void _disposeWorkerResources() {
    _workerSendPort?.send(ShutdownCommand());
    _receivePort?.close();
    _errorPort?.close();
    _isolate?.kill();
    _receivePort = null;
    _errorPort = null;
    _isolate = null;
    _workerSendPort = null;
    _pendingInit = null;
    _pendingClearCacheCommand = false;
  }

  void _handleMessage(dynamic message) {
    switch (message) {
      case WorkerReady(:final sendPort):
        _workerSendPort = sendPort;
        final pending = _pendingInit;
        if (pending != null) {
          _pendingInit = null;
          sendPort.send(
            InitCommand(
              subscriptions: pending.subscriptions,
              httpOptions: pending.httpOptions,
            ),
          );
        }
        if (_pendingClearCacheCommand) {
          _pendingClearCacheCommand = false;
          sendPort.send(const ClearCacheCommand());
        }

      case EngineCompiledResponse(:final engineBytes, :final totalRules, :final compilationTime):
        final engine = EngineSerializer().deserialize(engineBytes.materialize().asUint8List());
        _onEngineReady(engine, false, totalRules, compilationTime);
        _completeActiveJob();

      case EngineCacheRestored(:final engineBytes, :final compilationTime, :final totalRules):
        final engine = EngineSerializer().deserialize(engineBytes.materialize().asUint8List());
        _onEngineReady(engine, true, totalRules, compilationTime);
        _completeActiveJob();

      case WebViewEvent():
        _onWorkerEvent(message);
        if (_completeOnCacheClear && message is FilterCacheCleared) {
          _completeOnCacheClear = false;
          _completeActiveJob();
        }

      case WebViewError():
        _onWorkerError(message);
        if (message is CacheRestoreFailed) {
          _completeOnCacheClear = false;
          _completeActiveJob();
        }

      case ShutdownAck():
        _receivePort?.close();
    }
  }

  void _completeActiveJob() {
    final activeJob = _activeJob;
    if (activeJob == null) return;
    _activeJob = null;
    if (!activeJob.isCompleted) activeJob.complete();
    dispose();
  }

  void _cancelActiveJob() {
    final activeJob = _activeJob;
    _activeJob = null;
    _completeOnCacheClear = false;
    if (activeJob == null || activeJob.isCompleted) return;
    activeJob.completeError(const FilterIsolateJobCancelled());
  }
}
