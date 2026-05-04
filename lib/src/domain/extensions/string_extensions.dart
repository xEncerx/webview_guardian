/// Extensions for String related to URL parsing.
extension UrlParsing on String {
  /// Checks if the current string is a subdomain of the given parent domain.
  bool isSubdomainOf(String parentDomain) {
    if (length < parentDomain.length) return false;
    if (length == parentDomain.length) return this == parentDomain;

    if (!endsWith(parentDomain)) return false;

    final separatorIndex = length - parentDomain.length - 1;
    return codeUnitAt(separatorIndex) == 0x2E;
  }

  /// Converts the string to a Punycode host if it contains non-ASCII characters.
  String toPunycodeHost() {
    for (var i = 0; i < length; i++) {
      if (codeUnitAt(i) > 127) {
        return Uri.parse('http://$this').host;
      }
    }
    return this;
  }
}

/// Extensions for String related to token extraction for filter rules.
extension TokenExtractor on String {
  /// Extracts tokens from the string and returns them as a set of integers.
  Set<int> extractTokensAsInt() {
    final tokens = <int>{};
    var currentToken = 0;
    var currentSequenceLen = 0;

    for (var i = 0; i < length; i++) {
      var charCode = codeUnitAt(i);

      // Change uppercase letters to lowercase
      if (charCode >= 65 && charCode <= 90) charCode |= 0x20;

      final isAlphaNum =
          (charCode >= 97 && charCode <= 122) || // a-z
          (charCode >= 48 && charCode <= 57); // 0-9

      if (isAlphaNum) {
        // Shift the old bytes to the left by 8 bits (freeing up space) and insert the new character using OR.
        // Mask with 0xFFFFFFFFFF to keep only the last 5 bytes (40 bits).
        currentToken = ((currentToken << 8) | charCode) & 0xFFFFFFFFFF;
        currentSequenceLen++;

        if (currentSequenceLen >= 5) tokens.add(currentToken);
      } else {
        currentToken = 0;
        currentSequenceLen = 0;
      }
    }

    return tokens;
  }

  /// Checks if any token extracted from the string matches the provided condition.
  bool anyTokenMatches(bool Function(int token) onTokenMatch) {
    var currentToken = 0;
    var currentSequenceLen = 0;

    for (var i = 0; i < length; i++) {
      var charCode = codeUnitAt(i);

      // Change uppercase letters to lowercase
      if (charCode >= 65 && charCode <= 90) charCode |= 0x20;

      final isAlphaNum =
          (charCode >= 97 && charCode <= 122) || // a-z
          (charCode >= 48 && charCode <= 57); // 0-9

      if (isAlphaNum) {
        // Shift the old bytes to the left by 8 bits (freeing up space) and insert the new character using OR.
        // Mask with 0xFFFFFFFFFF to keep only the last 5 bytes (40 bits).
        currentToken = ((currentToken << 8) | charCode) & 0xFFFFFFFFFF;
        currentSequenceLen++;

        if (currentSequenceLen >= 5) {
          if (onTokenMatch(currentToken)) {
            return true;
          }
        }
      } else {
        currentSequenceLen = 0;
        currentToken = 0;
      }
    }
    return false;
  }
}

/// Extensions for String related to domain extraction from URLs.
extension DomainExtractor on String {
  /// Extracts base domain (eTLD+1) using a heuristic for country-code TLDs.
  /// Used for fast zero-allocation third-party checks.
  String getBaseDomain() {
    final host = this;
    final lastDot = host.lastIndexOf('.');
    if (lastDot == -1) return host;

    final secondLastDot = host.lastIndexOf('.', lastDot - 1);
    if (secondLastDot == -1) return host;

    // Check length of second-level domain (SLD) to guess if it's a ccTLD
    final sldLen = lastDot - secondLastDot - 1;
    if (sldLen <= 3) {
      final thirdLastDot = host.lastIndexOf('.', secondLastDot - 1);
      if (thirdLastDot != -1) {
        return host.substring(thirdLastDot + 1);
      }
      return host;
    }
    return host.substring(secondLastDot + 1);
  }
}
