import 'dart:typed_data';

import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/engine/compiled_filter_engine.dart';

/// A serializer for converting [CompiledFilterEngine] to and from binary data.
class EngineSerializer {
  static const int _typeNetworkBlock = 1;
  static const int _typeNetworkException = 2;
  static const int _typeCosmeticHide = 3;
  static const int _typeCosmeticException = 4;
  static const int _typeScriptlet = 5;
  static const int _typeCssInject = 6;
  static const int _typeNetworkBlockMatchCase = 7;
  static const int _typeNetworkExceptionMatchCase = 8;
  static const int _typeNetworkBlockFirstParty = 9;
  static const int _typeNetworkExceptionFirstParty = 10;
  static const int _typeNetworkBlockFirstPartyMatchCase = 11;
  static const int _typeNetworkExceptionFirstPartyMatchCase = 12;

  /// Serializes the given [CompiledFilterEngine] into a [Uint8List].
  Uint8List serialize(CompiledFilterEngine engine) {
    final writer = BinaryWriter()..writeInt32(engine.totalRules);

    // 1. Build Rule Pool
    final rulePool = <FilterRule>{}
      ..addAll(engine.trieRules)
      ..addAll(engine.tokenDispatchTable.values.expand((e) => e))
      ..addAll(engine.fallbackRules)
      ..addAll(engine.cosmeticHideRules.values.expand((e) => e))
      ..addAll(engine.cosmeticExceptionRules.values.expand((e) => e))
      ..addAll(engine.scriptletRules.values.expand((e) => e))
      ..addAll(engine.cssInjectRules.values.expand((e) => e));

    final ruleList = rulePool.toList(growable: false);
    final ruleToIndex = <FilterRule, int>{};
    for (var i = 0; i < ruleList.length; i++) {
      ruleToIndex[ruleList[i]] = i;
    }

    // 2. Write Rule Pool
    writer.writeInt32(ruleList.length);
    for (final rule in ruleList) {
      _writeRule(writer, rule);
    }

    // 3. Write Uint32List
    writer.writeUint32List(engine.trieBuffer);

    // 4. Write Data Structures using Rule Indices
    _writeRuleIndexList(writer, engine.trieRules, ruleToIndex);

    writer.writeInt32(engine.tokenDispatchTable.length);
    for (final entry in engine.tokenDispatchTable.entries) {
      writer.writeInt64(entry.key);
      _writeRuleIndexList(writer, entry.value, ruleToIndex);
    }

    _writeRuleIndexList(writer, engine.fallbackRules.toList(), ruleToIndex);

    writer.writeInt32(engine.cosmeticHideRules.length);
    for (final entry in engine.cosmeticHideRules.entries) {
      writer.writeString(entry.key);
      _writeRuleIndexList(writer, entry.value, ruleToIndex);
    }

    writer.writeInt32(engine.cosmeticExceptionRules.length);
    for (final entry in engine.cosmeticExceptionRules.entries) {
      writer.writeString(entry.key);
      _writeRuleIndexList(writer, entry.value, ruleToIndex);
    }

    writer.writeInt32(engine.scriptletRules.length);
    for (final entry in engine.scriptletRules.entries) {
      writer.writeString(entry.key);
      _writeRuleIndexList(writer, entry.value, ruleToIndex);
    }

    writer.writeInt32(engine.cssInjectRules.length);
    for (final entry in engine.cssInjectRules.entries) {
      writer.writeString(entry.key);
      _writeRuleIndexList(writer, entry.value, ruleToIndex);
    }

    return writer.toBytes();
  }

  /// Deserializes a [CompiledFilterEngine] from the given [Uint8List].
  CompiledFilterEngine deserialize(Uint8List bytes) {
    try {
      final reader = BinaryReader(bytes);

      final totalRules = reader.readInt32();

      // 1. Read Rule Pool
      final poolSize = reader.readInt32();
      if (poolSize < 0 || poolSize > bytes.length) {
        throw FormatException('Invalid rule pool size: $poolSize');
      }
      final rulePool = List<FilterRule>.generate(
        poolSize,
        (_) => _readRule(reader),
        growable: false,
      );

      List<T> readRuleIndexList<T extends FilterRule>() {
        final length = reader.readInt32();
        final list = <T>[];
        for (var i = 0; i < length; i++) {
          final index = reader.readInt32();
          list.add(rulePool[index] as T);
        }
        return list;
      }

      // 2. Read Uint32List
      final trieBuffer = reader.readUint32List();

      // 3. Read Data Structures mapping back from Rule Pool
      final trieRules = readRuleIndexList<FilterRule>();

      final tokenDispatchTableLength = reader.readInt32();
      final tokenDispatchTable = <int, List<FilterRule>>{};
      for (var i = 0; i < tokenDispatchTableLength; i++) {
        final key = reader.readInt64();
        final rules = readRuleIndexList<FilterRule>();
        tokenDispatchTable[key] = rules;
      }

      final fallbackRules = readRuleIndexList<FilterRule>().toSet();

      final cosmeticHideRulesLength = reader.readInt32();
      final cosmeticHideRules = <String, List<CosmeticHideRule>>{};
      for (var i = 0; i < cosmeticHideRulesLength; i++) {
        final key = reader.readString();
        final rules = readRuleIndexList<CosmeticHideRule>();
        cosmeticHideRules[key] = rules;
      }

      final cosmeticExceptionRulesLength = reader.readInt32();
      final cosmeticExceptionRules = <String, List<CosmeticExceptionRule>>{};
      for (var i = 0; i < cosmeticExceptionRulesLength; i++) {
        final key = reader.readString();
        final rules = readRuleIndexList<CosmeticExceptionRule>();
        cosmeticExceptionRules[key] = rules;
      }

      final scriptletRulesLength = reader.readInt32();
      final scriptletRules = <String, List<ScriptletRule>>{};
      for (var i = 0; i < scriptletRulesLength; i++) {
        final key = reader.readString();
        final rules = readRuleIndexList<ScriptletRule>();
        scriptletRules[key] = rules;
      }

      final cssInjectRulesLength = reader.readInt32();
      final cssInjectRules = <String, List<CssInjectRule>>{};
      for (var i = 0; i < cssInjectRulesLength; i++) {
        final key = reader.readString();
        final rules = readRuleIndexList<CssInjectRule>();
        cssInjectRules[key] = rules;
      }

      return CompiledFilterEngine(
        totalRules: totalRules,
        trieBuffer: trieBuffer,
        trieRules: trieRules,
        tokenDispatchTable: tokenDispatchTable,
        fallbackRules: fallbackRules,
        cosmeticHideRules: cosmeticHideRules,
        cosmeticExceptionRules: cosmeticExceptionRules,
        scriptletRules: scriptletRules,
        cssInjectRules: cssInjectRules,
      );

      /// Catching RangeError which can occur if the binary data is truncated or malformed, and rethrowing as FormatException for clarity.
      // ignore: avoid_catching_errors
    } on RangeError catch (e) {
      throw FormatException('Truncated or invalid binary data: $e');
    }
  }

  void _writeRuleIndexList(
    BinaryWriter writer,
    List<FilterRule> rules,
    Map<FilterRule, int> ruleToIndex,
  ) {
    writer.writeInt32(rules.length);
    for (final rule in rules) {
      writer.writeInt32(ruleToIndex[rule]!);
    }
  }

  void _writeRule(BinaryWriter writer, FilterRule rule) {
    switch (rule) {
      case NetworkBlockRule():
        writer.writeUint8(
          rule.isFirstPartyOnly
              ? rule.isMatchCase
                    ? _typeNetworkBlockFirstPartyMatchCase
                    : _typeNetworkBlockFirstParty
              : rule.isMatchCase
              ? _typeNetworkBlockMatchCase
              : _typeNetworkBlock,
        );
        writer.writeString(rule.pattern);
        writer.writeResourceTypes(rule.resourceTypes);
        writer.writeBool(rule.isThirdPartyOnly);
        writer.writeBool(rule.isImportant);
        writer.writeNullableStringSet(rule.includeDomains);
        writer.writeNullableStringSet(rule.excludeDomains);
      case NetworkExceptionRule():
        writer.writeUint8(
          rule.isFirstPartyOnly
              ? rule.isMatchCase
                    ? _typeNetworkExceptionFirstPartyMatchCase
                    : _typeNetworkExceptionFirstParty
              : rule.isMatchCase
              ? _typeNetworkExceptionMatchCase
              : _typeNetworkException,
        );
        writer.writeString(rule.pattern);
        writer.writeResourceTypes(rule.resourceTypes);
        writer.writeBool(rule.isThirdPartyOnly);
        writer.writeBool(rule.isImportant);
        writer.writeNullableStringSet(rule.includeDomains);
        writer.writeNullableStringSet(rule.excludeDomains);
      case CosmeticHideRule():
        writer.writeUint8(_typeCosmeticHide);
        writer.writeString(rule.selector);
        writer.writeNullableStringList(rule.includeDomains);
        writer.writeNullableStringList(rule.excludeDomains);
      case CosmeticExceptionRule():
        writer.writeUint8(_typeCosmeticException);
        writer.writeString(rule.selector);
        writer.writeNullableStringList(rule.includeDomains);
        writer.writeNullableStringList(rule.excludeDomains);
      case ScriptletRule():
        writer.writeUint8(_typeScriptlet);
        writer.writeString(rule.scriptletName);
        writer.writeNullableStringList(rule.domains);
        writer.writeStringList(rule.args);
      case CssInjectRule():
        writer.writeUint8(_typeCssInject);
        writer.writeString(rule.css);
        writer.writeNullableStringList(rule.domains);
        writer.writeNullableStringList(rule.excludeDomains);
    }
  }

  FilterRule _readRule(BinaryReader reader) {
    final type = reader.readUint8();
    switch (type) {
      case _typeNetworkBlock:
      case _typeNetworkBlockMatchCase:
      case _typeNetworkBlockFirstParty:
      case _typeNetworkBlockFirstPartyMatchCase:
        return NetworkBlockRule(
          pattern: reader.readString(),
          resourceTypes: reader.readResourceTypes(),
          isThirdPartyOnly: reader.readBool(),
          isFirstPartyOnly:
              type == _typeNetworkBlockFirstParty || type == _typeNetworkBlockFirstPartyMatchCase,
          isImportant: reader.readBool(),
          isMatchCase:
              type == _typeNetworkBlockMatchCase || type == _typeNetworkBlockFirstPartyMatchCase,
          includeDomains: reader.readNullableStringSet(),
          excludeDomains: reader.readNullableStringSet(),
        );
      case _typeNetworkException:
      case _typeNetworkExceptionMatchCase:
      case _typeNetworkExceptionFirstParty:
      case _typeNetworkExceptionFirstPartyMatchCase:
        return NetworkExceptionRule(
          pattern: reader.readString(),
          resourceTypes: reader.readResourceTypes(),
          isThirdPartyOnly: reader.readBool(),
          isFirstPartyOnly:
              type == _typeNetworkExceptionFirstParty ||
              type == _typeNetworkExceptionFirstPartyMatchCase,
          isImportant: reader.readBool(),
          isMatchCase:
              type == _typeNetworkExceptionMatchCase ||
              type == _typeNetworkExceptionFirstPartyMatchCase,
          includeDomains: reader.readNullableStringSet(),
          excludeDomains: reader.readNullableStringSet(),
        );
      case _typeCosmeticHide:
        return CosmeticHideRule(
          selector: reader.readString(),
          includeDomains: reader.readNullableStringList(),
          excludeDomains: reader.readNullableStringList(),
        );
      case _typeCosmeticException:
        return CosmeticExceptionRule(
          selector: reader.readString(),
          includeDomains: reader.readNullableStringList(),
          excludeDomains: reader.readNullableStringList(),
        );
      case _typeScriptlet:
        return ScriptletRule(
          scriptletName: reader.readString(),
          domains: reader.readNullableStringList(),
          args: reader.readStringList(),
        );
      case _typeCssInject:
        final css = reader.readString();
        final includeDomains = reader.readNullableStringList();
        return CssInjectRule(
          css: css,
          includeDomains: includeDomains,
          excludeDomains: reader.readNullableStringList(),
          domain: includeDomains?.length == 1 ? includeDomains!.first : null,
        );
      default:
        throw FormatException('Unknown rule type: $type');
    }
  }
}
