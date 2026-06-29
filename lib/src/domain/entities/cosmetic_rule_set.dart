import 'package:meta/meta.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Cosmetic rules split by their source bucket after exceptions are applied.
@immutable
final class CosmeticRuleSet {
  /// Creates a [CosmeticRuleSet].
  const CosmeticRuleSet({
    this.domainSpecificRules = const [],
    this.genericRules = const [],
  });

  /// Rules indexed under a concrete domain bucket.
  final List<CosmeticHideRule> domainSpecificRules;

  /// Rules indexed under a global bucket such as `*` or the empty domain.
  final List<CosmeticHideRule> genericRules;

  /// All selected cosmetic rules, preserving domain-specific priority before generic rules.
  List<CosmeticHideRule> get allRules => [
    ...domainSpecificRules,
    ...genericRules,
  ];
}
