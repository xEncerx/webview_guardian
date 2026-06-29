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

int _setHash<T>(Set<T>? set) => set == null ? 0 : Object.hashAllUnordered(set);

int _listHash<T>(List<T>? list) => list == null ? 0 : Object.hashAll(list);

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

@immutable
sealed class _NetworkRule extends FilterRule {
  const _NetworkRule({
    required this.pattern,
    this.resourceTypes = const {},
    this.isThirdPartyOnly = false,
    this.isFirstPartyOnly = false,
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

  /// Whether this rule should only apply to first-party requests.
  final bool isFirstPartyOnly;

  /// Whether this rule is marked as important, which may give it higher precedence over other rules.
  final bool isImportant;

  /// Whether URL matching should be case-sensitive.
  final bool isMatchCase;

  /// A set of source domains where this network rule may apply.
  final Set<String>? includeDomains;

  /// A set of source domains where this network rule must not apply.
  final Set<String>? excludeDomains;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _NetworkRule &&
          other.runtimeType == runtimeType &&
          pattern == other.pattern &&
          isThirdPartyOnly == other.isThirdPartyOnly &&
          isFirstPartyOnly == other.isFirstPartyOnly &&
          isImportant == other.isImportant &&
          isMatchCase == other.isMatchCase &&
          _setEquals(resourceTypes, other.resourceTypes) &&
          _setEquals(includeDomains, other.includeDomains) &&
          _setEquals(excludeDomains, other.excludeDomains));

  @override
  int get hashCode => Object.hash(
    runtimeType,
    pattern,
    _setHash(resourceTypes),
    isThirdPartyOnly,
    isFirstPartyOnly,
    isImportant,
    isMatchCase,
    _setHash(includeDomains),
    _setHash(excludeDomains),
  );
}

/// A rule that blocks network requests matching a specific pattern and resource types.
@immutable
final class NetworkBlockRule extends _NetworkRule {
  /// Creates a [NetworkBlockRule] instance.
  const NetworkBlockRule({
    required super.pattern,
    super.resourceTypes,
    super.isThirdPartyOnly,
    super.isFirstPartyOnly,
    super.isImportant,
    super.isMatchCase,
    super.includeDomains,
    super.excludeDomains,
  });
}

/// A rule that allows network requests matching a specific pattern and resource types, overriding block rules.
@immutable
final class NetworkExceptionRule extends _NetworkRule {
  /// Creates a [NetworkExceptionRule] instance.
  const NetworkExceptionRule({
    required super.pattern,
    super.resourceTypes,
    super.isThirdPartyOnly,
    super.isFirstPartyOnly,
    super.isImportant,
    super.isMatchCase,
    super.includeDomains,
    super.excludeDomains,
  });
}

@immutable
sealed class _CosmeticRule extends FilterRule {
  const _CosmeticRule({
    required this.selector,
    List<String>? domains,
    List<String>? includeDomains,
    this.excludeDomains,
  }) : includeDomains = includeDomains ?? domains;

  /// The hostnames where this cosmetic rule may apply. null = global rule.
  final List<String>? includeDomains;

  /// The hostnames where this cosmetic rule must not apply.
  final List<String>? excludeDomains;

  /// Alias for [includeDomains], retained for indexing call sites.
  List<String>? get domains => includeDomains;

  /// The CSS selector this cosmetic rule targets.
  final String selector;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CosmeticRule &&
          other.runtimeType == runtimeType &&
          selector == other.selector &&
          _listEquals(includeDomains, other.includeDomains) &&
          _listEquals(excludeDomains, other.excludeDomains));

  @override
  int get hashCode => Object.hash(
    runtimeType,
    selector,
    _listHash(includeDomains),
    _listHash(excludeDomains),
  );
}

/// A rule that hides elements on a webpage matching a specific CSS selector.
@immutable
final class CosmeticHideRule extends _CosmeticRule {
  /// Creates a [CosmeticHideRule] instance.
  const CosmeticHideRule({
    required super.selector,
    super.domains,
    super.includeDomains,
    super.excludeDomains,
  });
}

/// A rule that prevents hiding elements on a webpage matching a specific CSS selector.
@immutable
final class CosmeticExceptionRule extends _CosmeticRule {
  /// Creates a [CosmeticExceptionRule] instance.
  const CosmeticExceptionRule({
    required super.selector,
    super.domains,
    super.includeDomains,
    super.excludeDomains,
  });
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
