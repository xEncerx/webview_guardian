import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

/// A reference to a [CompiledFilterEngine] that can be updated with a new instance.
final class FilterEngineRef {
  /// Creates a [FilterEngineRef] instance.
  FilterEngineRef(this._engine);

  CompiledFilterEngine _engine;

  /// The current filter engine.
  CompiledFilterEngine get current => _engine;

  /// Updates the filter engine with a new instance.
  // ignore: use_setters_to_change_properties
  void update(CompiledFilterEngine newEngine) => _engine = newEngine;
}
