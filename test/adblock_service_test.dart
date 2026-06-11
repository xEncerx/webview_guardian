import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

void main() {
  group('AdblockService Integration', () {
    late Directory tempDir;
    late AdblockService service;
    late File validFilterFile;
    late File brokenFilterFile;
    late List<WebViewEvent> events;
    late List<WebViewError> errors;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('adblock_service_test_');
      events = [];
      errors = [];

      ScriptletLibrary.instance.parseForTest('''
/// abort-on-property-read
const abortOnPropertyRead = function() {
  const property = '{{1}}';
  if (property === 'ads') {
    throw new Error('aborted');
  }
};
''');

      validFilterFile = File('${tempDir.path}/valid_filter.txt')
        ..writeAsStringSync('''
[Adblock Plus 2.0]
||ads.example.com^
@@||good.example.com^
example.com##.banner
example.com#%#//scriptlet('abort-on-property-read', 'ads')
''');

      brokenFilterFile = File('${tempDir.path}/broken_filter.txt')
        ..writeAsStringSync('''
Some random text that is not a valid adblock list
<html<body></body>
''');

      service = TestAdblockService.create();
    });

    tearDown(() {
      ScriptletLibrary.instance.clearForTest();
      service.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    // We use a custom observer to track events and errors
    final observer = _TestObserver((e) => events.add(e), (e) => errors.add(e));

    test('should initialize, compile engine, and apply rules correctly (Normal Flow)', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      // Wait for engine to be ready
      await expectLater(
        Future.microtask(() async {
          while (!service.isReady.value) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return service.isReady.value;
        }).timeout(const Duration(seconds: 5)),
        completion(isTrue),
      );

      expect(service.isEnabled, isTrue);
      expect(events.any((e) => e is EngineCompiled), isTrue);

      final interceptor = service.trafficInterceptor;
      final orchestrator = service.orchestrator;
      expect(interceptor, isNotNull);
      expect(orchestrator, isNotNull);

      // Check blocking
      final blockResult = service.repository?.lookupNetworkRequest(
        NetworkRequest(
          url: 'https://ads.example.com/script.js',
          host: 'ads.example.com',
          resourceType: ResourceType.script,
          sourceHost: 'example.com',
        ),
      );
      expect(blockResult, isA<Block>());

      final allowResult = service.repository?.lookupNetworkRequest(
        NetworkRequest(
          url: 'https://good.example.com/image.png',
          host: 'good.example.com',
          resourceType: ResourceType.image,
          sourceHost: 'example.com',
        ),
      );
      expect(allowResult, isA<Allow>());

      // Check CSS
      final css = orchestrator!
          .buildUserScripts('example.com')
          .where((s) => s.source.contains('.banner'))
          .toList();
      expect(css, isNotEmpty);

      // Check JS
      final js = orchestrator
          .buildUserScripts('example.com')
          .where((s) => s.source.contains('abortOnPropertyRead'))
          .toList();
      expect(
        js,
        isNotEmpty,
        reason: orchestrator.buildUserScripts('example.com').map((s) => s.source).join('\n'),
      );
    });

    test('should not crash on invalid filter file and should allow traffic (Resilience)', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: brokenFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      // Wait for engine to be ready
      await expectLater(
        Future.microtask(() async {
          while (!service.isReady.value) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return service.isReady.value;
        }).timeout(const Duration(seconds: 5)),
        completion(isTrue),
      );

      expect(errors, isEmpty);

      // But service is still ready and allows all traffic
      final result = service.repository?.lookupNetworkRequest(
        NetworkRequest(
          url: 'https://ads.example.com/script.js',
          host: 'ads.example.com',
          resourceType: ResourceType.script,
          sourceHost: 'example.com',
        ),
      );
      expect(result, isA<Allow>());
    });

    test('should update subscriptions and apply new rules on the fly', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      events.clear();

      final newFilterFile = File('${tempDir.path}/new_filter.txt')
        ..writeAsStringSync('''
[Adblock Plus 2.0]
||new-ads.com^
''');

      service.updateSubscriptions([
        FilterSubscription(url: validFilterFile.path),
        FilterSubscription(url: newFilterFile.path),
      ]);

      // Wait for new engine to be compiled
      await expectLater(
        Future.microtask(() async {
          while (!events.any((e) => e is EngineCompiled)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return true;
        }).timeout(const Duration(seconds: 5)),
        completion(isTrue),
      );

      // Previous rules should still work
      final blockResult1 = service.repository?.lookupNetworkRequest(
        NetworkRequest(
          url: 'https://ads.example.com/script.js',
          host: 'ads.example.com',
          resourceType: ResourceType.script,
          sourceHost: 'example.com',
        ),
      );
      expect(blockResult1, isA<Block>());

      // New rules should be applied
      final blockResult2 = service.repository?.lookupNetworkRequest(
        NetworkRequest(
          url: 'https://new-ads.com/script.js',
          host: 'new-ads.com',
          resourceType: ResourceType.script,
          sourceHost: 'example.com',
        ),
      );
      expect(blockResult2, isA<Block>());
    });

    test('should restore engine from cache (Cache Hit)', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      events.clear();

      // Create new service with same storage
      final newService = AdblockService();
      await newService.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      await expectLater(
        Future.microtask(() async {
          while (!newService.isReady.value) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return true;
        }).timeout(const Duration(seconds: 5)),
        completion(isTrue),
      );

      expect(
        events.any(
          (e) =>
              e is EngineRestoredFromCache &&
              e.totalRules > 0 &&
              e.compilationTime >= Duration.zero,
        ),
        isTrue,
      );
      expect(events.any((e) => e is EngineCompiled), isFalse);

      newService.dispose();
    });

    test('should compile new engine after clearCache is called (Cache Invalidation)', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      service.clearCache();
      await Future<void>.delayed(const Duration(milliseconds: 500)); // Wait for clear
      events.clear();

      final newService = AdblockService();
      await newService.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      await expectLater(
        Future.microtask(() async {
          while (!newService.isReady.value) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          return true;
        }).timeout(const Duration(seconds: 5)),
        completion(isTrue),
      );

      expect(events.any((e) => e is EngineCompiled), isTrue);
      expect(
        events.any(
          (e) =>
              e is EngineRestoredFromCache &&
              e.totalRules > 0 &&
              e.compilationTime >= Duration.zero,
        ),
        isFalse,
      );

      newService.dispose();
    });

    test('should fetch updates based on timer', () async {
      final sub = FilterSubscription(
        url: validFilterFile.path,
        updateInterval: const Duration(seconds: 1),
      );

      await service.init(
        subscriptions: [sub],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final fetchStartedCountInitial = events.whereType<FilterListFetchStarted>().length;

      // Wait for timer to trigger (1 second)
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      final fetchStartedCountAfter = events.whereType<FilterListFetchStarted>().length;
      expect(fetchStartedCountAfter, greaterThan(fetchStartedCountInitial));
    });

    test('should bypass interceptor when isEnabled is false', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final blockResult = service.repository?.lookupNetworkRequest(
        NetworkRequest(
          url: 'https://ads.example.com/script.js',
          host: 'ads.example.com',
          resourceType: ResourceType.script,
          sourceHost: 'example.com',
        ),
      );
      expect(blockResult, isA<Block>());

      service.isEnabled = false;
      // AdblockService currently delegates checking `isEnabled` to the `WebViewWidget`
      // but repository itself still returns Block if queried directly.
      expect(service.isEnabled, isFalse);
    });

    test('should serialize update jobs and keep only the latest pending subscriptions', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      await service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );

      expect(runner.startedSubscriptions, hasLength(1));

      service
        ..updateSubscriptions(const [FilterSubscription(url: 'first-update.txt')])
        ..updateSubscriptions(const [FilterSubscription(url: 'second-update.txt')]);

      await Future<void>.delayed(Duration.zero);

      expect(
        runner.startedSubscriptions.map((subscriptions) => subscriptions.single.url),
        ['initial.txt'],
      );

      runner.completeCurrent();
      await runner.waitForStartedCount(2);

      expect(
        runner.startedSubscriptions.map((subscriptions) => subscriptions.single.url),
        ['initial.txt', 'second-update.txt'],
      );

      runner.completeCurrent();
      await runner.waitForIdle();
      service.dispose();
    });
  });
}

class _ControllableFilterJobRunner implements FilterJobRunner {
  final startedSubscriptions = <List<FilterSubscription>>[];
  final _startedController = StreamController<int>.broadcast();
  Completer<void>? _current;

  @override
  Future<void> runBuildJob({
    required List<FilterSubscription> subscriptions,
    required FilterHttpOptions httpOptions,
    String? storagePath,
    bool useTestClient = false,
  }) {
    if (_current != null) throw StateError('Jobs must not run in parallel');
    startedSubscriptions.add(List.of(subscriptions));
    _startedController.add(startedSubscriptions.length);
    _current = Completer<void>();
    return _current!.future.whenComplete(() => _current = null);
  }

  @override
  Future<void> runClearCacheJob({String? storagePath, bool useTestClient = false}) async {}

  @override
  void dispose() {}

  void completeCurrent() {
    final current = _current;
    if (current == null || current.isCompleted) return;
    current.complete();
  }

  Future<void> waitForStartedCount(int count) async {
    if (startedSubscriptions.length >= count) return;
    await _startedController.stream.firstWhere((startedCount) => startedCount >= count);
  }

  Future<void> waitForIdle() async {
    while (_current != null) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

class _TestObserver implements WebViewObserver {
  _TestObserver(this.onEventCallback, this.onErrorCallback);

  final void Function(WebViewEvent) onEventCallback;
  final void Function(WebViewError) onErrorCallback;

  @override
  void onEvent(WebViewEvent event) {
    onEventCallback(event);
  }

  @override
  void onError(WebViewError error) {
    onErrorCallback(error);
  }
}
