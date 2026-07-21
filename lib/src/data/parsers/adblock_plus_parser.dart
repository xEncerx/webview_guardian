import 'dart:typed_data';

import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';

/// A parser for the Adblock Plus filter list format.
class AdblockPlusParser implements FilterListParser {
  @override
  FilterListFormat get supportedFormat => FilterListFormat.adblockPlus;

  @override
  Iterable<FilterRule> parse(Uint8List rawBytes) sync* {
    var offset = 0;
    while (offset < rawBytes.length) {
      var end = rawBytes.indexOfLineEnd(offset);
      if (end == -1) end = rawBytes.length;

      final rule = _parseLine(rawBytes, offset, end);
      if (rule != null) {
        yield rule;
      }

      offset = end + 1;
      if (offset < rawBytes.length &&
          rawBytes[end] == 13 /* \r */ &&
          rawBytes[offset] == 10 /* \n */ ) {
        offset++;
      }
    }
  }

  FilterRule? _parseLine(Uint8List bytes, int start, int end) {
    if (start >= end) return null;

    final firstByte = bytes[start];
    // Fast byte-level skip for comments (!) and metadata ([).
    if (firstByte == 33 /* ! */ || firstByte == 91 /* [ */ ) return null;

    final line = bytes.isAsciiOnly(start, end)
        ? bytes.getAsciiString(start, end)
        : Utf8.decode(bytes, start, end - start);

    return _processStringLine(line.trim());
  }

  FilterRule? _processStringLine(String line) {
    if (line.isEmpty) return null;

    // Regular expressions break Token Dispatch O(1) complexity. Dropped to maintain <1ms latency.
    if (line.startsWith('/') && line.endsWith('/') && line.length > 2) return null;

    if (line.contains(r'#$#')) return _parseCssInject(line);

    // HTML filtering requires modifying response body before browser parsing,
    // which breaks streaming and is unsupported by Android's shouldInterceptRequest.
    if (line.contains(r'$$') || line.contains('##^') || line.contains(r'$@$')) {
      return null;
    }

    if (_hasCosmeticOrScriptletSyntax(line)) {
      return _parseCosmeticOrScriptlet(line);
    }

    return _parseNetworkRule(line);
  }

  bool _hasCosmeticOrScriptletSyntax(String line) {
    return line.contains('##+js(') ||
        line.contains('#%#//scriptlet(') ||
        line.contains('#@#') ||
        line.contains('#@?#') ||
        line.contains(r'#@$#') ||
        line.contains('#@%#//scriptlet(') ||
        line.contains(r'#$#') ||
        line.contains('#?#') ||
        line.contains('##');
  }

  FilterRule? _parseCosmeticOrScriptlet(String line) {
    // Procedural cosmetics require MutationObserver + custom JS engine.
    // Dropped to avoid layout thrashing and scrolling freezes on mobile.
    // Includes uBO and ABP specific aliases.
    if (line.contains(':has(') ||
        line.contains(':-abp-has(') ||
        line.contains(':has-text(') ||
        line.contains(':contains(') ||
        line.contains(':-abp-contains(') ||
        line.contains(':matches-css(') ||
        line.contains(':-abp-properties(') ||
        line.contains(':matches-property(') ||
        line.contains(':matches-prop(') ||
        line.contains(':matches-attr(') ||
        line.contains(':xpath(') ||
        line.contains(':upward(') ||
        line.contains(':nth-ancestor(') ||
        line.contains(':min-text-length(') ||
        line.contains(':watch-attr(') ||
        line.contains(':style(')) {
      return null;
    }

    if (line.contains('##+js(')) {
      return _parseScriptlet(line, '##+js(');
    }
    if (line.contains('#%#//scriptlet(')) {
      return _parseScriptlet(line, '#%#//scriptlet(');
    }
    if (line.contains('#@#')) {
      return _parseCosmetic(line, '#@#', isException: true);
    }
    if (line.contains('##')) {
      return _parseCosmetic(line, '##', isException: false);
    }

    return null;
  }

  FilterRule? _parseCosmetic(String line, String separator, {required bool isException}) {
    final parts = line.split(separator);
    if (parts.length != 2) return null;

    final domainsPart = parts[0];
    final selector = parts[1].trim();

    if (selector.isEmpty) return null;

    final domains = _parseCosmeticDomains(domainsPart);

    return isException
        ? CosmeticExceptionRule(
            selector: selector,
            includeDomains: domains.includeDomains,
            excludeDomains: domains.excludeDomains,
          )
        : CosmeticHideRule(
            selector: selector,
            includeDomains: domains.includeDomains,
            excludeDomains: domains.excludeDomains,
          );
  }

  ({List<String>? includeDomains, List<String>? excludeDomains}) _parseCosmeticDomains(
    String domainsPart,
  ) {
    if (domainsPart.isEmpty) return (includeDomains: null, excludeDomains: null);

    final includes = <String>[];
    final excludes = <String>[];
    for (final rawDomain in domainsPart.split(',')) {
      final domain = rawDomain.trim();
      if (domain.isEmpty) continue;
      if (domain.startsWith('~')) {
        final excludedDomain = domain.substring(1).trim();
        if (excludedDomain.isNotEmpty) excludes.add(excludedDomain);
      } else {
        includes.add(domain);
      }
    }

    return (
      includeDomains: includes.isEmpty ? null : includes,
      excludeDomains: excludes.isEmpty ? null : excludes,
    );
  }

  FilterRule? _parseScriptlet(String line, String separator) {
    final parts = line.split(separator);
    if (parts.length != 2) return null;

    final domainsPart = parts[0];
    final body = parts[1];

    if (!body.endsWith(')')) return null;
    final argsStr = body.substring(0, body.length - 1);

    final args = argsStr
        .split(',')
        .map((e) {
          var s = e.trim();
          if (s.length >= 2 &&
              ((s.startsWith("'") && s.endsWith("'")) || (s.startsWith('"') && s.endsWith('"')))) {
            s = s.substring(1, s.length - 1);
          }
          return s;
        })
        .where((e) => e.isNotEmpty)
        .toList();
    if (args.isEmpty) return null;

    List<String>? domains;
    if (domainsPart.isNotEmpty) {
      domains = domainsPart.split(',').map((d) => d.trim()).where((d) => d.isNotEmpty).toList();
      if (domains.isEmpty) domains = null;
    }

    return ScriptletRule(scriptletName: args.first, domains: domains, args: args.sublist(1));
  }

  FilterRule? _parseCssInject(String line) {
    final separatorIndex = line.indexOf(r'#$#');
    if (separatorIndex == -1) return null;

    final css = line.substring(separatorIndex + 3).trim();
    if (css.isEmpty) return null;

    final domains = _parseCosmeticDomains(line.substring(0, separatorIndex));
    return CssInjectRule(
      css: css,
      includeDomains: domains.includeDomains,
      excludeDomains: domains.excludeDomains,
      domain: domains.includeDomains?.length == 1 ? domains.includeDomains!.first : null,
    );
  }

  FilterRule? _parseNetworkRule(String line) {
    final isException = line.startsWith('@@');
    final patternPart = isException ? line.substring(2) : line;

    final dollarIdx = patternPart.lastIndexOf(r'$');
    var pattern = patternPart;
    var optionsPart = '';

    if (dollarIdx != -1) {
      pattern = patternPart.substring(0, dollarIdx);
      optionsPart = patternPart.substring(dollarIdx + 1);
    }

    if (pattern.isEmpty) return null;

    final options = _parseNetworkOptions(optionsPart);
    if (options == null) return null;

    final (
      :types,
      isThirdPartyOnly: isThirdParty,
      isFirstPartyOnly: isFirstParty,
      :isImportant,
      :isMatchCase,
      includeDomains: include,
      excludeDomains: exclude,
    ) = options;

    if (isException) {
      return NetworkExceptionRule(
        pattern: pattern,
        resourceTypes: types,
        isThirdPartyOnly: isThirdParty,
        isFirstPartyOnly: isFirstParty,
        isImportant: isImportant,
        isMatchCase: isMatchCase,
        includeDomains: include,
        excludeDomains: exclude,
      );
    } else {
      return NetworkBlockRule(
        pattern: pattern,
        resourceTypes: types,
        isThirdPartyOnly: isThirdParty,
        isFirstPartyOnly: isFirstParty,
        isImportant: isImportant,
        isMatchCase: isMatchCase,
        includeDomains: include,
        excludeDomains: exclude,
      );
    }
  }

  ({
    Set<ResourceType> types,
    bool isThirdPartyOnly,
    bool isFirstPartyOnly,
    bool isImportant,
    bool isMatchCase,
    Set<String>? includeDomains,
    Set<String>? excludeDomains,
  })?
  _parseNetworkOptions(String optionsStr) {
    if (optionsStr.isEmpty) {
      return (
        types: <ResourceType>{},
        isThirdPartyOnly: false,
        isFirstPartyOnly: false,
        isImportant: false,
        isMatchCase: false,
        includeDomains: null,
        excludeDomains: null,
      );
    }

    final types = <ResourceType>{};
    final excludedTypes = <ResourceType>{};
    var hasPositiveTypes = false;
    var isThirdPartyOnly = false;
    var isFirstPartyOnly = false;
    var isImportant = false;
    var isMatchCase = false;
    Set<String>? includeDomains;
    Set<String>? excludeDomains;

    final parts = optionsStr.split(',');
    for (var p in parts) {
      p = p.trim();
      if (p.isEmpty) continue;

      if (p == 'badfilter' ||
          p.startsWith('replace=') ||
          p.startsWith('csp=') ||
          p.startsWith('removeparam') ||
          p.startsWith('queryprune') ||
          p.startsWith('uritransform=') ||
          p.startsWith('urltransform=')) {
        return null;
      }

      if (p == 'important') {
        isImportant = true;
      } else if (p == 'match-case') {
        isMatchCase = true;
      } else if (p == 'third-party' || p == '3p') {
        isThirdPartyOnly = true;
      } else if (p == '~third-party' || p == 'first-party' || p == '1p') {
        isFirstPartyOnly = true;
      } else if (p.startsWith('domain=') || p.startsWith('from=')) {
        final domStr = p.substring(p.indexOf('=') + 1);
        final domParts = domStr.split('|');
        for (var d in domParts) {
          d = d.trim();
          if (d.isEmpty) continue;
          if (d.startsWith('~')) {
            excludeDomains ??= {};
            excludeDomains.add(d.substring(1));
          } else {
            includeDomains ??= {};
            includeDomains.add(d);
          }
        }
      } else if (p == 'all') {
        types.addAll(ResourceType.values);
        hasPositiveTypes = true;
      } else if (p.startsWith('~')) {
        final typeStr = p.substring(1);
        final type = _parseResourceType(typeStr);
        if (type != null) {
          excludedTypes.add(type);
        }
      } else {
        final type = _parseResourceType(p);
        if (type == null) return null;
        types.add(type);
        hasPositiveTypes = true;
      }
    }

    if (excludedTypes.isNotEmpty && !hasPositiveTypes) {
      types.addAll(ResourceType.values);
    }
    types.removeAll(excludedTypes);

    if (isFirstPartyOnly && isThirdPartyOnly) return null;

    return (
      types: types,
      isThirdPartyOnly: isThirdPartyOnly,
      isFirstPartyOnly: isFirstPartyOnly,
      isImportant: isImportant,
      isMatchCase: isMatchCase,
      includeDomains: includeDomains,
      excludeDomains: excludeDomains,
    );
  }

  ResourceType? _parseResourceType(String typeStr) {
    return switch (typeStr) {
      'script' => ResourceType.script,
      'image' => ResourceType.image,
      'stylesheet' || 'css' => ResourceType.stylesheet,
      'subdocument' || 'frame' => ResourceType.subdocument,
      'xmlhttprequest' || 'xhr' => ResourceType.xmlHttpRequest,
      'websocket' => ResourceType.websocket,
      'font' => ResourceType.font,
      'media' => ResourceType.media,
      'document' || 'doc' => ResourceType.document,
      'other' => ResourceType.other,
      _ => null,
    };
  }
}
