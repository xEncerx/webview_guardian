/// -_-
// ignore_for_file: parameter_assignments

import 'package:webview_guardian/src/domain/domain.dart';

/// Extension to match network requests against filter rules.
extension FilterRuleMatcher on FilterRule {
  /// Checks whether the network request matches this filter rule.
  bool matchesRequest(NetworkRequest request) {
    return switch (this) {
      final NetworkBlockRule rule => _matchNetworkParams(
        rule.pattern,
        rule.resourceTypes,
        rule.isThirdPartyOnly,
        rule.includeDomains,
        rule.excludeDomains,
        request,
      ),
      final NetworkExceptionRule rule => _matchNetworkParams(
        rule.pattern,
        rule.resourceTypes,
        rule.isThirdPartyOnly,
        rule.includeDomains,
        rule.excludeDomains,
        request,
      ),
      _ => false,
    };
  }
}

bool _matchNetworkParams(
  String pattern,
  Set<ResourceType>? resourceTypes,
  bool isThirdPartyOnly,
  Set<String>? includeDomains,
  Set<String>? excludeDomains,
  NetworkRequest request,
) {
  if (resourceTypes != null &&
      resourceTypes.isNotEmpty &&
      !resourceTypes.contains(request.resourceType)) {
    return false;
  }

  if (isThirdPartyOnly && !request.isThirdParty) {
    return false;
  }
  final sourceHost = request.sourceHost;
  if (includeDomains != null && includeDomains.isNotEmpty) {
    var included = false;
    for (final domain in includeDomains) {
      if (sourceHost == domain || sourceHost.isSubdomainOf(domain)) {
        included = true;
        break;
      }
    }
    if (!included) return false;
  }
  if (excludeDomains != null && excludeDomains.isNotEmpty) {
    for (final domain in excludeDomains) {
      if (sourceHost == domain || sourceHost.isSubdomainOf(domain)) {
        return false;
      }
    }
  }
  return _matchAdblockPattern(pattern, request.url);
}

/// An Adblock Plus pattern matcher.
bool _matchAdblockPattern(String pattern, String url) {
  if (pattern.isEmpty) return false;
  final pLen = pattern.length;
  final uLen = url.length;
  // 1. Regular Expression Fast Path
  if (pLen > 2 &&
      pattern.codeUnitAt(0) == 47 /* / */ &&
      pattern.codeUnitAt(pLen - 1) == 47 /* / */ ) {
    return RegExp(pattern.substring(1, pLen - 1)).hasMatch(url);
  }
  var pIdx = 0;
  var uIdx = 0;
  // 2. Exact Match Anchor (startsWith)
  if (pattern.codeUnitAt(0) == 124 /* | */ && pLen > 1 && pattern.codeUnitAt(1) != 124 /* | */ ) {
    pIdx = 1;
    return _matchRecursive(pattern, url, pIdx, uIdx, pLen, uLen);
  }
  // 3. Domain Anchor (||)
  if (pLen >= 2 && pattern.codeUnitAt(0) == 124 /* | */ && pattern.codeUnitAt(1) == 124 /* | */ ) {
    pIdx = 2;
    // Fast-forward URL to just after `://`
    final schemeIdx = url.indexOf('://');
    if (schemeIdx != -1) {
      uIdx = schemeIdx + 3;
    }

    if (_matchRecursive(pattern, url, pIdx, uIdx, pLen, uLen)) return true;

    // Try matching after dots in the domain name
    while (uIdx < uLen && url.codeUnitAt(uIdx) != 47 /* / */ ) {
      if (url.codeUnitAt(uIdx) == 46 /* . */ ) {
        if (_matchRecursive(pattern, url, pIdx, uIdx + 1, pLen, uLen)) return true;
      }
      uIdx++;
    }
    return false;
  }
  // 4. Default Anywhere Match (with sliding window)
  while (uIdx < uLen) {
    if (_matchRecursive(pattern, url, pIdx, uIdx, pLen, uLen)) {
      return true;
    }
    uIdx++;
  }
  return false;
}

/// Recursively traverses string indices to handle wildcards and separators.
bool _matchRecursive(String pattern, String url, int pIdx, int uIdx, int pLen, int uLen) {
  while (pIdx < pLen) {
    final pChar = pattern.codeUnitAt(pIdx);
    // Wildcard (*)
    if (pChar == 42 /* * */ ) {
      while (pIdx + 1 < pLen && pattern.codeUnitAt(pIdx + 1) == 42 /* * */ ) {
        pIdx++;
      }
      if (pIdx == pLen - 1) return true; // Ends with *, matches rest

      pIdx++;

      while (uIdx <= uLen) {
        if (_matchRecursive(pattern, url, pIdx, uIdx, pLen, uLen)) {
          return true;
        }
        uIdx++;
      }
      return false;
    }
    // Separator (^)
    if (pChar == 94 /* ^ */ ) {
      if (uIdx >= uLen) {
        if (pIdx == pLen - 1) return true;
        if (pIdx == pLen - 2 && pattern.codeUnitAt(pIdx + 1) == 124 /* | */ ) return true;
        return false;
      }

      final uChar = url.codeUnitAt(uIdx);
      if (_isSeparator(uChar)) {
        pIdx++;
        uIdx++;
        continue;
      }
      return false;
    }
    // End anchor (|)
    if (pChar == 124 /* | */ && pIdx == pLen - 1) {
      return uIdx == uLen;
    }
    // Exact Character Match
    if (uIdx >= uLen || pattern.codeUnitAt(pIdx) != url.codeUnitAt(uIdx)) {
      return false;
    }
    pIdx++;
    uIdx++;
  }
  return true;
}

bool _isSeparator(int codeUnit) {
  // Letters
  if (codeUnit >= 97 && codeUnit <= 122) return false; // a-z
  if (codeUnit >= 65 && codeUnit <= 90) return false; // A-Z
  // Digits
  if (codeUnit >= 48 && codeUnit <= 57) return false; // 0-9
  // Allowable non-separators
  if (codeUnit == 95 || codeUnit == 45 || codeUnit == 46 || codeUnit == 37) return false; // _ - . %
  return true;
}
