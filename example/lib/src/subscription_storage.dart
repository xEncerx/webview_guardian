// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SubscriptionStorage {
  static const _fileName = 'subscriptions.json';
  static const _subscriptionsKey = 'subscriptions';

  Future<Directory> ensureAdblockDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final adblockDirectory = Directory('${supportDirectory.path}${Platform.pathSeparator}adblock');

    if (!adblockDirectory.existsSync()) {
      await adblockDirectory.create(recursive: true);
    }

    return adblockDirectory;
  }

  Future<List<String>> load(Directory adblockDirectory) async {
    final file = _file(adblockDirectory);
    if (!file.existsSync()) return const [];

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) return const [];

    final subscriptions = decoded[_subscriptionsKey];
    if (subscriptions is! List<Object?>) return const [];

    return subscriptions.whereType<String>().where((url) => url.trim().isNotEmpty).toList();
  }

  Future<void> save(Directory adblockDirectory, List<String> urls) async {
    final file = _file(adblockDirectory);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({_subscriptionsKey: urls}),
    );
  }

  File _file(Directory adblockDirectory) {
    return File('${adblockDirectory.path}${Platform.pathSeparator}$_fileName');
  }
}
