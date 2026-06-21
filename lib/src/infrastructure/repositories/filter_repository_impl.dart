import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/engine.dart';

/// Implementation of [FilterRepository] that uses a [FilterMatcher] and [FilterEngineRef] to manage filter rules and decisions.
class FilterRepositoryImpl implements FilterRepository {
  /// Creates a [FilterRepositoryImpl] instance.
  const FilterRepositoryImpl({
    required FilterMatcher matcher,
    required FilterEngineRef engineRef,
    required WebViewObserver? observer,
  }) : _matcher = matcher,
       _engineRef = engineRef,
       _observer = observer;

  final FilterMatcher _matcher;
  final FilterEngineRef _engineRef;
  final WebViewObserver? _observer;

  @override
  FilterDecision lookupNetworkRequest(NetworkRequest request) {
    final decision = _matcher.matchNetworkRequest(request);

    switch (decision) {
      case Block():
        _observer?.onEvent(RequestBlocked(request.url));
      case Allow():
        _observer?.onEvent(RequestAllowed(request.url));
    }

    return decision;
  }

  @override
  List<CosmeticHideRule> getCosmeticRules(String hostname) {
    final engine = _engineRef.current;
    final domainChain = _getDomainChain(hostname).toList(growable: false);

    // Single pass: collect exception selectors and hide rules simultaneously
    final exceptionSelectors = <String>{};
    final seen = <String>{};
    final result = <CosmeticHideRule>[];

    for (final domain in domainChain) {
      engine.cosmeticExceptionRules[domain]?.forEach((ex) {
        if (!_isCosmeticRuleExcluded(hostname, ex.excludeDomains)) {
          exceptionSelectors.add(ex.selector);
        }
      });
    }

    for (final domain in domainChain) {
      engine.cosmeticHideRules[domain]?.forEach((rule) {
        if (!_isCosmeticRuleExcluded(hostname, rule.excludeDomains) &&
            !exceptionSelectors.contains(rule.selector) &&
            seen.add(rule.selector)) {
          result.add(rule);
          _observer?.onEvent(
            CosmeticCssInjected(hostname: hostname, selector: rule.selector),
          );
        }
      });
    }

    return result;
  }

  @override
  List<ScriptletRule> getScriptletRules(String hostname) {
    final engine = _engineRef.current;
    final seen = <String>{};
    final result = <ScriptletRule>[];

    for (final domain in _getDomainChain(hostname)) {
      engine.scriptletRules[domain]?.forEach((rule) {
        if (seen.add(rule.scriptletName)) {
          result.add(rule);
          _observer?.onEvent(
            ScriptletInjected(hostname: hostname, scriptletName: rule.scriptletName),
          );
        }
      });
    }

    return result;
  }

  Iterable<String> _getDomainChain(String hostname) sync* {
    // Strip www. since filter lists usually target root domains directly
    final current = hostname.startsWith('www.') ? hostname.substring(4) : hostname;

    yield current;

    var dotIndex = current.indexOf('.');
    while (dotIndex != -1 && dotIndex < current.length - 1) {
      yield current.substring(dotIndex + 1);
      dotIndex = current.indexOf('.', dotIndex + 1);
    }

    // Empty string and '*' are both used by serialized engines for global rules.
    yield '';
    yield '*';
  }

  bool _isCosmeticRuleExcluded(String hostname, List<String>? excludeDomains) {
    if (excludeDomains == null) return false;

    final normalizedHost = hostname.startsWith('www.') ? hostname.substring(4) : hostname;
    for (final domain in excludeDomains) {
      final normalizedDomain = domain.startsWith('www.') ? domain.substring(4) : domain;
      if (normalizedHost == normalizedDomain || normalizedHost.endsWith('.$normalizedDomain')) {
        return true;
      }
    }
    return false;
  }
}
