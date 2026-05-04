import 'dart:isolate';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Base class for commands sent from the main isolate to customize the worker isolate behavior.
sealed class WorkerCommand {
  const WorkerCommand();
}

/// Command to initialize the worker isolate with essential setup data like the cache directory.
final class InitCommand extends WorkerCommand {
  /// Creates an [InitCommand] instance.
  const InitCommand({required this.subscriptions, required this.httpOptions});

  /// A list of filter subscriptions to parse and utilize.
  final List<FilterSubscription> subscriptions;

  /// HTTP options that may be needed for fetching filter lists or related resources.
  final FilterHttpOptions httpOptions;
}

/// Command to clear the worker isolate's cache.
///
/// Completely removes the compiled engine and loaded raw rules.
final class ClearCacheCommand extends WorkerCommand {
  /// Creates a [ClearCacheCommand] instance.
  const ClearCacheCommand();
}

/// Command to cleanly terminate the worker isolate and release its resources.
final class ShutdownCommand extends WorkerCommand {}

// --- Responses sent from Worker Isolate to Main Isolate ---

/// Base class for responses sent from the worker isolate back to the main isolate.
sealed class WorkerResponse {
  const WorkerResponse();
}

/// Acknowledgment indicating the worker isolate has completed its initialization and is ready to process requests.
final class WorkerReady extends WorkerResponse {
  /// Creates a [WorkerReady] instance.
  const WorkerReady(this.sendPort);

  /// The [SendPort] through which the worker isolate will communicate back to the main isolate.
  final SendPort sendPort;
}

/// Response containing the compiled engine bytes, total rules processed, and the time taken for compilation.
final class EngineCompiledResponse extends WorkerResponse {
  /// Creates an [EngineCompiledResponse] instance.
  const EngineCompiledResponse({
    required this.engineBytes,
    required this.totalRules,
    required this.compilationTime,
  });

  /// The compiled engine bytes that can be transferred back to the main isolate for use in the main isolate.
  final TransferableTypedData engineBytes;

  /// The total number of rules processed during compilation.
  final int totalRules;

  /// The duration it took to compile the engine, useful for performance monitoring and debugging.
  final Duration compilationTime;
}

/// Response containing the cached engine bytes and the time taken to restore it from cache.
final class EngineCacheRestored extends WorkerResponse {
  /// Creates an [EngineCacheRestored] instance.
  const EngineCacheRestored({
    required this.engineBytes,
    required this.compilationTime,
    required this.totalRules,
  });

  /// The cached engine bytes that were successfully restored, which can be transferred back to the main isolate for use.
  final TransferableTypedData engineBytes;

  /// The duration it took to restore the engine from cache, useful for performance monitoring and debugging.
  final Duration compilationTime;

  /// The total number of rules that were cached.
  final int totalRules;
}

/// Acknowledgment indicating the worker isolate has completed its shutdown sequence.
final class ShutdownAck extends WorkerResponse {}
