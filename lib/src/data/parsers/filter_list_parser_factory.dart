import 'dart:convert';
import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// Factory to detect filter list format and return the appropriate parser.
class FilterListParserFactory {
  /// Detects the filter list format by inspecting the first few lines of the raw bytes.
  static FilterListParser resolve(Uint8List rawBytes) {
    final checkLength = rawBytes.length > 8192 ? 8192 : rawBytes.length;
    final headerView = rawBytes.view(0, checkLength);

    final headerText = ascii.decode(headerView, allowInvalid: true);
    final lines = headerText.split('\n');

    var validDomainLines = 0;

    for (var i = 0; i < lines.length && i < 50; i++) {
      final line = lines[i].trim();

      if (line.isEmpty) continue;

      // 1. Adblock Plus / uBlock Origin
      if (line.startsWith('[Adblock') ||
          line.startsWith('! Title:') ||
          line.startsWith('! Version:') ||
          line.startsWith('! ') ||
          line.startsWith('||') ||
          line.startsWith('@@||')) {
        return AdblockPlusParser();
      }

      // 2. Hosts-файла
      if (line.startsWith('0.0.0.0') || line.startsWith('127.0.0.1')) {
        return HostsParser();
      }

      // 3. Plain Domain List
      if (!line.startsWith('#') && !line.contains(' ') && line.contains('.')) {
        validDomainLines++;
      }
    }

    // If we found lines that look like domains but didn't find ABP or Hosts markers, then it's a simple domain list.
    if (validDomainLines > 0) {
      return DomainListParser();
    }

    // Fallback: If the file is completely unrecognized, default to ABP parser which has a "Fast Reject" logic to skip garbage without crashing.
    return AdblockPlusParser();
  }
}
