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
typedef _PendingInit = ({
  List<FilterSubscription> subscriptions,
  FilterHttpOptions httpOptions,
});

/// Manages the lifecycle and communication with the filter parser worker isolate.
class FilterIsolateManager {
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

  late final ReceivePort _receivePort;
  late final ReceivePort _errorPort;
  late final Isolate _isolate;
  SendPort? _workerSendPort;

  // Held until WorkerReady arrives - sent immediately after
  _PendingInit? _pendingInit;

  /// Spawns the worker isolate and sets up communication channels.
  Future<void> spawn({String? storagePath, bool useTestClient = false}) async {
    _receivePort = ReceivePort();
    _errorPort = ReceivePort();
    _isolate = await Isolate.spawn(
      filterParserWorkerEntry,
      (
        sendPort: _receivePort.sendPort,
        storagePath: storagePath,
        useTestClient: useTestClient,
      ),
      errorsAreFatal: false,
      onError: _errorPort.sendPort,
      debugName: 'FilterParserWorker',
    );

    _errorPort.listen((message) {
      if (message is List && message.length == 2) {
        final error = message[0];
        final stackTrace = message[1];
        _onWorkerError(IsolateCrashError('Isolate crashed', cause: '$error\n$stackTrace'));
      }
    });

    _receivePort.listen(_handleMessage);
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
    _workerSendPort?.send(const ClearCacheCommand());
  }

  /// Sends a shutdown command to the worker isolate and cleans up resources.
  void dispose() {
    _workerSendPort?.send(ShutdownCommand());
    _receivePort.close();
    _errorPort.close();
    _isolate.kill();
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

      case EngineCompiledResponse(:final engineBytes, :final totalRules, :final compilationTime):
        final engine = EngineSerializer().deserialize(engineBytes.materialize().asUint8List());
        _onEngineReady(engine, false, totalRules, compilationTime);

      case EngineCacheRestored(:final engineBytes, :final compilationTime, :final totalRules):
        final engine = EngineSerializer().deserialize(engineBytes.materialize().asUint8List());
        _onEngineReady(engine, true, totalRules, compilationTime);

      case WebViewEvent():
        _onWorkerEvent(message);

      case WebViewError():
        _onWorkerError(message);

      case ShutdownAck():
        _receivePort.close();
    }
  }
}
