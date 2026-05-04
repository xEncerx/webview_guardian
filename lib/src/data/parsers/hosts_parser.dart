import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Parser for Hosts files (e.g. from StevenBlack/hosts).
class HostsParser implements FilterListParser {
  @override
  FilterListFormat get supportedFormat => FilterListFormat.hosts;

  // Pre-calculated byte arrays for fast matching (without trailing space)
  static const _zeroIp = [48, 46, 48, 46, 48, 46, 48]; // '0.0.0.0'
  static const _localIp = [49, 50, 55, 46, 48, 46, 48, 46, 49]; // '127.0.0.1'

  @override
  Iterable<FilterRule> parse(Uint8List rawBytes) sync* {
    var start = 0;

    for (var i = 0; i <= rawBytes.length; i++) {
      if (i == rawBytes.length || rawBytes[i] == 10) {
        var lineEnd = i;
        if (lineEnd > start && rawBytes[lineEnd - 1] == 13) lineEnd--;

        if (lineEnd <= start) {
          start = i + 1;
          continue;
        }

        // Skip full-line comments ('#' = 35)
        if (rawBytes[start] == 35) {
          start = i + 1;
          continue;
        }

        var domainStart = -1;
        if (_startsWith(rawBytes, start, lineEnd, _zeroIp)) {
          domainStart = start + _zeroIp.length;
        } else if (_startsWith(rawBytes, start, lineEnd, _localIp)) {
          domainStart = start + _localIp.length;
        }

        if (domainStart != -1) {
          // Must be followed by space (32) or tab (9)
          if (domainStart < lineEnd &&
              (rawBytes[domainStart] == 32 || rawBytes[domainStart] == 9)) {
            // Skip all whitespaces between IP and domain
            while (domainStart < lineEnd &&
                (rawBytes[domainStart] == 32 || rawBytes[domainStart] == 9)) {
              domainStart++;
            }
          } else {
            domainStart = -1; // Invalid IP match (e.g. 127.0.0.10)
          }
        }

        if (domainStart == -1 || domainStart >= lineEnd) {
          start = i + 1;
          continue;
        }

        // Handle inline comments and trailing whitespaces
        var domainEnd = domainStart;
        while (domainEnd < lineEnd) {
          final b = rawBytes[domainEnd];
          if (b == 32 || b == 9 || b == 35) break; // Stop at space, tab, or #
          domainEnd++;
        }

        if (domainEnd <= domainStart) {
          start = i + 1;
          continue;
        }

        String domain;
        if (rawBytes.isAsciiOnly(domainStart, domainEnd)) {
          domain = rawBytes.getAsciiString(domainStart, domainEnd);
        } else {
          domain = Utf8.decode(rawBytes, domainStart, domainEnd - domainStart).toPunycodeHost();
        }

        yield NetworkBlockRule(pattern: '||$domain^');

        start = i + 1;
      }
    }
  }

  bool _startsWith(Uint8List bytes, int start, int end, List<int> prefix) {
    if (end - start < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[start + i] != prefix[i]) return false;
    }
    return true;
  }
}
