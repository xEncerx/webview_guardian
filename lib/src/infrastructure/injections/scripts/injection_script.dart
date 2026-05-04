import 'package:webview_guardian/src/domain/domain.dart';

/// Defines the JavaScript context where the script should be injected.
enum InjectionWorld {
  /// The main page context, sharing variables with the website.
  page,

  /// An isolated context, preventing interference with the website's scripts.
  isolated,
}

/// Defines when the script should be injected into the page lifecycle.
enum InjectionTiming {
  /// Inject as soon as the document begins loading.
  atDocumentStart,

  /// Inject after the document has finished parsing.
  atDocumentEnd,
}

/// Base abstraction for generating JS/CSS strings to inject.
abstract class InjectionScript {
  /// The world in which the script should be executed.
  InjectionWorld get world;

  /// The timing at which the script should be injected.
  InjectionTiming get timing;

  /// Returns the raw script string, or null if nothing to inject.
  String? buildScript(String hostname, FilterRepository repo);
}
