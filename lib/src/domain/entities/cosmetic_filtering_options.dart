import 'package:meta/meta.dart';

/// Controls how generic cosmetic rules are applied to WebView injections.
enum GenericCosmeticRuleMode {
  /// Do not apply generic cosmetic rules. Domain-specific rules still apply.
  off,

  /// Apply a capped set of generic CSS rules and keep MutationObserver domain-specific only.
  performance,

  /// Apply all generic rules to CSS and MutationObserver.
  full,
}

/// Performance options for cosmetic filtering injections.
@immutable
final class CosmeticFilteringOptions {
  /// Creates [CosmeticFilteringOptions] instance.
  const CosmeticFilteringOptions({
    this.genericRuleMode = GenericCosmeticRuleMode.performance,
    this.genericCssRuleLimit = defaultGenericCssRuleLimit,
  }) : assert(genericCssRuleLimit >= 0, 'genericCssRuleLimit must be non-negative');

  /// Default cap for generic CSS rules in [GenericCosmeticRuleMode.performance].
  static const int defaultGenericCssRuleLimit = 3000;

  /// How generic cosmetic rules should be applied.
  final GenericCosmeticRuleMode genericRuleMode;

  /// Maximum generic CSS rules per host in [GenericCosmeticRuleMode.performance].
  final int genericCssRuleLimit;
}
