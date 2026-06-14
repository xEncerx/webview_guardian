import 'package:meta/meta.dart';
import 'package:webview_guardian/src/domain/domain.dart';

bool _setEquals<T>(Set<T>? a, Set<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Represents a filter rule that can be applied to web content.
sealed class FilterRule {
  const FilterRule();
}

/// The rule weight is a heuristic value used to prioritize rules during matching. Higher weight means higher priority.
extension RuleWeight on FilterRule {
  /// Assigns a weight to the rule for prioritization during matching.
  int get ruleWeight {
    return switch (this) {
      final NetworkExceptionRule r => r.isImportant ? 4 : 2,
      final NetworkBlockRule r => r.isImportant ? 3 : 1,
      _ => 0,
    };
  }
}

/// A rule that blocks network requests matching a specific pattern and resource types.
@immutable
final class NetworkBlockRule extends FilterRule {
  /// Creates a [NetworkBlockRule] instance.
  const NetworkBlockRule({
    required this.pattern,
    this.resourceTypes = const {},
    this.isThirdPartyOnly = false,
    this.isImportant = false,
    this.isMatchCase = false,
    this.includeDomains,
    this.excludeDomains,
  });

  /// The pattern to match against network requests.
  final String pattern;

  /// The types of resources to which this rule applies.
  final Set<ResourceType> resourceTypes;

  /// Whether this rule should only apply to third-party requests.
  final bool isThirdPartyOnly;

  /// Whether this rule is marked as important, which may give it higher precedence over other rules.
  final bool isImportant;

  /// Whether URL matching should be case-sensitive.
  final bool isMatchCase;

  /// A set of domains for which this rule should be applied, even if they are not third-party.
  final Set<String>? includeDomains;

  /// A set of domains for which this rule should not be applied, even if they are third-party.
  final Set<String>? excludeDomains;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkBlockRule &&
          pattern == other.pattern &&
          isThirdPartyOnly == other.isThirdPartyOnly &&
          isImportant == other.isImportant &&
          isMatchCase == other.isMatchCase &&
          _setEquals(resourceTypes, other.resourceTypes) &&
          _setEquals(includeDomains, other.includeDomains) &&
          _setEquals(excludeDomains, other.excludeDomains));

  @override
  int get hashCode => pattern.hashCode ^ isImportant.hashCode ^ isMatchCase.hashCode;
}

/// A rule that allows network requests matching a specific pattern and resource types, overriding block rules.
@immutable
final class NetworkExceptionRule extends FilterRule {
  /// Creates a [NetworkExceptionRule] instance.
  const NetworkExceptionRule({
    required this.pattern,
    this.resourceTypes = const {},
    this.isThirdPartyOnly = false,
    this.isImportant = false,
    this.isMatchCase = false,
    this.includeDomains,
    this.excludeDomains,
  });

  /// The pattern to match against network requests.
  final String pattern;

  /// The types of resources to which this rule applies.
  final Set<ResourceType> resourceTypes;

  /// Whether this rule should only apply to third-party requests.
  final bool isThirdPartyOnly;

  /// Whether this rule is marked as important, which may give it higher precedence over other rules.
  final bool isImportant;

  /// Whether URL matching should be case-sensitive.
  final bool isMatchCase;

  /// A set of domains for which this rule should be applied, even if they are not third-party.
  final Set<String>? includeDomains;

  /// A set of domains for which this rule should not be applied, even if they are third-party.

  final Set<String>? excludeDomains;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NetworkExceptionRule &&
          pattern == other.pattern &&
          isThirdPartyOnly == other.isThirdPartyOnly &&
          isImportant == other.isImportant &&
          isMatchCase == other.isMatchCase &&
          _setEquals(resourceTypes, other.resourceTypes) &&
          _setEquals(includeDomains, other.includeDomains) &&
          _setEquals(excludeDomains, other.excludeDomains));

  @override
  int get hashCode => pattern.hashCode ^ isImportant.hashCode ^ isMatchCase.hashCode;
}

/// A rule that hides elements on a webpage matching a specific CSS selector.
@immutable
final class CosmeticHideRule extends FilterRule {
  /// Creates a [CosmeticHideRule] instance.
  const CosmeticHideRule({
    required this.selector,
    this.domains,
  });

  /// The domains for which this rule should be applied. null = global rule.
  final List<String>? domains;

  /// The CSS selector to match elements that should be hidden.
  final String selector;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CosmeticHideRule &&
          selector == other.selector &&
          _listEquals(domains, other.domains));

  @override
  int get hashCode => selector.hashCode;
}

/// A rule that prevents hiding elements on a webpage matching a specific CSS selector.
@immutable
final class CosmeticExceptionRule extends FilterRule {
  /// Creates a [CosmeticExceptionRule] instance.
  const CosmeticExceptionRule({
    required this.selector,
    this.domains,
  });

  /// The domains for which this rule should be applied. null = global rule.
  final List<String>? domains;

  /// The CSS selector to match elements that should not be hidden.
  final String selector;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CosmeticExceptionRule &&
          selector == other.selector &&
          _listEquals(domains, other.domains));

  @override
  int get hashCode => selector.hashCode ^ (domains?.first.hashCode ?? 0);
}

/// A rule that injects a scriptlet into a webpage.
@immutable
final class ScriptletRule extends FilterRule {
  /// Creates a [ScriptletRule] instance.
  const ScriptletRule({
    required this.scriptletName,
    this.domains,
    this.args = const [],
  });

  /// The domains for which this rule should be applied. null = global rule.
  final List<String>? domains;

  /// The name of the scriptlet to inject.
  final String scriptletName;

  /// Arguments to pass to the scriptlet.
  final List<String> args;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScriptletRule &&
          scriptletName == other.scriptletName &&
          _listEquals(args, other.args) &&
          _listEquals(domains, other.domains));

  @override
  int get hashCode => scriptletName.hashCode ^ (domains?.first.hashCode ?? 0);
}

/// A rule that injects custom CSS into a webpage.
@immutable
final class CssInjectRule extends FilterRule {
  /// Creates a [CssInjectRule] instance.
  const CssInjectRule({
    required this.css,
    this.domain,
  });

  /// The domain for which this rule should be applied.
  final String? domain;

  /// The CSS code to inject into the webpage.
  final String css;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CssInjectRule && domain == other.domain && css == other.css);

  @override
  int get hashCode => css.hashCode;
}
