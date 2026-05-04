import 'dart:typed_data';

import 'package:webview_guardian/src/domain/domain.dart';

/// Different filter list formats supported by the parsers.
enum FilterListFormat {
  /// Adblock Plus / uBlock Origin style filter list with support for various rule types and options.
  adblockPlus,

  /// Hosts file format with lines like 0.0.0.0 or 127.0.0.1 followed by a domain.
  hosts,

  /// Plain domain list with one domain per line, no comments or options.
  domainList,
}

/// Interface for filter list parsers. Each parser should implement this to parse a specific format of filter list.
abstract class FilterListParser {
  /// The specific filter list format that this parser supports.
  FilterListFormat get supportedFormat;

  /// Parses the raw bytes of a filter list and yields [FilterRule]s.
  Iterable<FilterRule> parse(Uint8List rawBytes);
}
