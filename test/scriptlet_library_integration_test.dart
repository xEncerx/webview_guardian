import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('init propagates scriptlet asset failures and can retry', () async {
    ScriptletLibrary.instance.clearForTest();
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final realAllMessagesHandler = messenger.allMessagesHandler;
    final tempDir = Directory.systemTemp.createTempSync('adblock_scriptlet_retry_test_');
    final service = TestAdblockService.create();
    void restoreAssetHandler() => messenger.allMessagesHandler = realAllMessagesHandler;
    addTearDown(() {
      restoreAssetHandler();
      service.dispose();
      ScriptletLibrary.instance.clearForTest();
      tempDir.deleteSync(recursive: true);
    });
    messenger.allMessagesHandler = (channel, handler, message) {
      if (channel == 'flutter/assets') throw Exception('scriptlet asset load failed');
      return realAllMessagesHandler?.call(channel, handler, message) ??
          handler?.call(message) ??
          messenger.delegate.send(channel, message);
    };

    await expectLater(
      service.init(subscriptions: const [], storagePath: tempDir.path),
      throwsA(isA<Exception>()),
    );
    expect(service.isReady.value, isFalse);

    restoreAssetHandler();
    await service.init(subscriptions: const [], storagePath: tempDir.path);

    expect(service.isReady.value, isTrue);
    expect(ScriptletLibrary.instance.buildScript('remove-attr', []), isNotNull);
  });

  test('init loads bundled scriptlets and resolves supported rule names', () async {
    ScriptletLibrary.instance.clearForTest();
    final tempDir = Directory.systemTemp.createTempSync('adblock_scriptlet_init_test_');
    final filterFile = File('${tempDir.path}/scriptlets.txt')
      ..writeAsStringSync('''
[Adblock Plus 2.0]
example.com#%#//scriptlet('remove-attr', 'canonical-extensionless')
example.com#%#//scriptlet('nano-sib', 'alias-extensionless')
example.com#%#//scriptlet('remove-class.js', 'canonical-explicit')
example.com#%#//scriptlet('ra.js', 'alias-explicit')
''');
    final service = TestAdblockService.create();
    addTearDown(() {
      service.dispose();
      ScriptletLibrary.instance.clearForTest();
      tempDir.deleteSync(recursive: true);
    });

    await service.init(
      subscriptions: [FilterSubscription(url: filterFile.path)],
      storagePath: tempDir.path,
    );

    final orchestrator = service.orchestrator;
    if (orchestrator == null) fail('Service initialized without an injection orchestrator.');
    final source = orchestrator
        .buildUserScripts('example.com')
        .map((script) => script.source)
        .join();
    expect(source, contains('canonical-extensionless'));
    expect(source, contains('alias-extensionless'));
    expect(source, contains('canonical-explicit'));
    expect(source, contains('alias-explicit'));
    expect(ScriptletLibrary.instance.buildScript('unknown-scriptlet', []), isNull);
    final extensionlessCanonical = ScriptletLibrary.instance.buildScript(
      'window.name-defuser',
      [],
    );
    expect(extensionlessCanonical, isNotNull);
    expect(
      ScriptletLibrary.instance.buildScript('window.name-defuser.js', []),
      extensionlessCanonical,
    );

    final finalScriptlet = ScriptletLibrary.instance.buildScript('cookie-remover.js', []);
    if (finalScriptlet == null) fail('Bundled final scriptlet was not loaded.');
    expect(
      finalScriptlet.trim(),
      endsWith('})();'),
    );
  });
}
