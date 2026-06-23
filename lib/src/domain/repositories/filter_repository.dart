import 'package:webview_guardian/src/domain/domain.dart';

/// Repository interface for managing filter rules and decisions.
abstract class FilterRepository {
  /// Looks up the appropriate filter decision for a given network request.
  FilterDecision lookupNetworkRequest(NetworkRequest request);

  /// Retrieves cosmetic hide rules applicable to the specified hostname.
  List<CosmeticHideRule> getCosmeticRules(String hostname);

  /// Retrieves cosmetic hide rules split by domain-specific and generic source buckets.
  CosmeticRuleSet getCosmeticRuleSet(String hostname);

  /// Retrieves scriptlet injection rules applicable to the specified hostname.
  List<ScriptletRule> getScriptletRules(String hostname);
}
