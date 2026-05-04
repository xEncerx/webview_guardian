import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Parser for plain domain lists (one domain per line).
class DomainListParser implements FilterListParser {
  @override
  FilterListFormat get supportedFormat => FilterListFormat.domainList;

  @override
  Iterable<FilterRule> parse(Uint8List rawBytes) sync* {
    var start = 0;

    for (var i = 0; i <= rawBytes.length; i++) {
      if (i == rawBytes.length || rawBytes[i] == 10) {
        // 10 = \n
        var lineEnd = i;
        if (lineEnd > start && rawBytes[lineEnd - 1] == 13) lineEnd--; // 13 = \r

        // Level 1: Skip empty
        if (lineEnd <= start) {
          start = i + 1;
          continue;
        }

        // Level 2: Skip comments ('#' = 35)
        if (rawBytes[start] == 35) {
          start = i + 1;
          continue;
        }

        // Level 3: Strict Validation
        var isValid = true;
        for (var j = start; j < lineEnd; j++) {
          final b = rawBytes[j];
          // Fast reject: any space (32) or slash (47) invalidates the entire line
          if (b == 32 || b == 47) {
            isValid = false;
            break;
          }
        }

        if (!isValid) {
          start = i + 1;
          continue;
        }

        // Level 4: Allocation & Punycode Normalization
        String domain;
        if (rawBytes.isAsciiOnly(start, lineEnd)) {
          domain = rawBytes.getAsciiString(start, lineEnd);
        } else {
          domain = Utf8.decode(rawBytes, start, lineEnd - start).toPunycodeHost();
        }

        // Level 5: Yield Rule
        yield NetworkBlockRule(pattern: '||$domain^');

        start = i + 1;
      }
    }
  }
}
