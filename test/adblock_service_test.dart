import 'dart:async';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
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

    test('awaiting init returns after the first engine is ready', () async {
      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      expect(service.isReady.value, isTrue);
      expect(service.repository, isNotNull);
      expect(service.orchestrator, isNotNull);
      expect(service.trafficInterceptor, isNotNull);
    });

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

    test('should apply global cosmetic and scriptlet rules to any hostname', () async {
      final globalFilterFile = File('${tempDir.path}/global_filter.txt')
        ..writeAsStringSync('''
[Adblock Plus 2.0]
##.global-ad
#%#//scriptlet('abort-on-property-read', 'ads')
''');

      await service.init(
        subscriptions: [FilterSubscription(url: globalFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final userScripts = service.orchestrator!.buildUserScripts('unrelated-site.test');

      expect(userScripts.where((script) => script.source.contains('.global-ad')), isNotEmpty);
      expect(
        userScripts.where((script) => script.source.contains('abortOnPropertyRead')),
        isNotEmpty,
      );
    });

    test('should inject parsed CSS rules at document start', () async {
      final cssFilterFile = File('${tempDir.path}/css_filter.txt')
        ..writeAsStringSync(r'''
[Adblock Plus 2.0]
example.com#$#body { overflow: auto !important; }
''');

      await service.init(
        subscriptions: [FilterSubscription(url: cssFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      final cssScripts = service.orchestrator!
          .buildUserScripts('sub.example.com')
          .where((script) => script.injectionTime == UserScriptInjectionTime.AT_DOCUMENT_START)
          .toList();

      expect(cssScripts, hasLength(1));
      expect(cssScripts.single.source, contains('body { overflow: auto !important; }'));
      expect(
        cssScripts.single.source,
        isNot(contains('body { overflow: auto !important; } { display: none !important; }')),
      );
    });

    test('should apply global cosmetic exception rules to domain-specific hides', () async {
      final globalExceptionFilterFile = File('${tempDir.path}/global_exception_filter.txt')
        ..writeAsStringSync('''
[Adblock Plus 2.0]
example.com##.sponsored
#@#.sponsored
''');

      await service.init(
        subscriptions: [FilterSubscription(url: globalExceptionFilterFile.path)],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final userScripts = service.orchestrator!.buildUserScripts('example.com');

      expect(userScripts.where((script) => script.source.contains('.sponsored')), isEmpty);
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

      await service.updateSubscriptions([
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

      await service.clearCache();
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

    test('clearCache clears active in-memory rules without removing subscriptions', () async {
      final subscription = FilterSubscription(url: validFilterFile.path);

      await service.init(
        subscriptions: [subscription],
        storagePath: tempDir.path,
        observer: observer,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(service.subscriptions, [subscription]);
      expect(service.ruleCount, greaterThan(0));
      expect(
        service.repository?.lookupNetworkRequest(
          NetworkRequest(
            url: 'https://ads.example.com/script.js',
            host: 'ads.example.com',
            resourceType: ResourceType.script,
            sourceHost: 'example.com',
          ),
        ),
        isA<Block>(),
      );
      expect(
        service.orchestrator!
            .buildUserScripts('example.com')
            .where((script) => script.source.contains('.banner')),
        isNotEmpty,
      );

      await service.clearCache();

      expect(service.subscriptions, [subscription]);
      expect(service.ruleCount, 0);
      expect(
        service.repository?.lookupNetworkRequest(
          NetworkRequest(
            url: 'https://ads.example.com/script.js',
            host: 'ads.example.com',
            resourceType: ResourceType.script,
            sourceHost: 'example.com',
          ),
        ),
        isA<Allow>(),
      );
      expect(
        service.orchestrator!
            .buildUserScripts('example.com')
            .where((script) => script.source.contains('.banner')),
        isEmpty,
      );
    });

    test('clearCache ignores active build results that complete after clearing', () async {
      final cacheCleared = Completer<void>();
      final ruleCountsAfterClear = <int>[];
      var clearRequested = false;

      final raceObserver = _TestObserver((event) {
        events.add(event);
        if (clearRequested && event is FilterCacheCleared && !cacheCleared.isCompleted) {
          cacheCleared.complete();
        }
      }, (error) => errors.add(error));

      await service.init(
        subscriptions: [FilterSubscription(url: validFilterFile.path)],
        storagePath: tempDir.path,
        observer: raceObserver,
      );

      while (!service.isReady.value) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      events.clear();
      final ruleCountSubscription = service.ruleCountStream.listen((count) {
        if (clearRequested) ruleCountsAfterClear.add(count);
      });
      unawaited(service.updateSubscriptions([FilterSubscription(url: validFilterFile.path)]));
      clearRequested = true;
      final clearFuture = service.clearCache();

      await cacheCleared.future.timeout(const Duration(seconds: 5));
      await ruleCountSubscription.cancel();
      await clearFuture;

      expect(ruleCountsAfterClear.where((count) => count > 0), isEmpty);
      expect(service.ruleCount, 0);
      expect(
        service.orchestrator!
            .buildUserScripts('example.com')
            .where(
              (script) =>
                  script.source.contains('.banner') ||
                  script.source.contains('abortOnPropertyRead'),
            ),
        isEmpty,
      );
    });

    test('should fetch updates based on timer', () async {
      final sub = FilterSubscription(
        url: validFilterFile.path,
        updateInterval: const Duration(seconds: 1),
      );

      await service.init(subscriptions: [sub], storagePath: tempDir.path, observer: observer);

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

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);

      expect(runner.startedSubscriptions, hasLength(1));

      final firstUpdate = service.updateSubscriptions(const [
        FilterSubscription(url: 'first-update.txt'),
      ]);
      final secondUpdate = service.updateSubscriptions(const [
        FilterSubscription(url: 'second-update.txt'),
      ]);

      await Future<void>.delayed(Duration.zero);

      expect(runner.startedSubscriptions.map((subscriptions) => subscriptions.single.url), [
        'initial.txt',
      ]);

      runner.completeCurrent();
      await runner.waitForStartedCount(2);
      await initFuture;

      expect(await _isCompleted(firstUpdate), isFalse);
      expect(await _isCompleted(secondUpdate), isFalse);

      expect(runner.startedSubscriptions.map((subscriptions) => subscriptions.single.url), [
        'initial.txt',
        'second-update.txt',
      ]);

      runner.completeCurrent();
      await firstUpdate;
      await secondUpdate;
      await runner.waitForIdle();
      service.dispose();
    });

    test('updateSubscriptions snapshots options and storage path for each build', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        httpOptions: const FilterHttpOptions(headers: {'x-request': 'initial'}),
        storagePath: 'initial-storage',
      );
      await runner.waitForStartedCount(1);

      final updateFuture = service.updateSubscriptions(const [
        FilterSubscription(url: 'updated.txt'),
      ]);

      runner.completeCurrent();
      await runner.waitForStartedCount(2);
      await initFuture;

      expect(runner.startedStoragePaths, ['initial-storage', 'initial-storage']);
      expect(runner.startedHttpOptions.map((options) => options.headers['x-request']), [
        'initial',
        'initial',
      ]);

      runner.completeCurrent();
      await updateFuture;
      await runner.waitForIdle();
      service.dispose();
    });

    test('updateHttpOptions updates options used by the next subscription update', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);
      const initialOptions = FilterHttpOptions(headers: {'x-request': 'initial'});
      const updatedOptions = FilterHttpOptions(
        headers: {'x-request': 'runtime'},
        proxy: 'socks5://127.0.0.1:1080',
      );

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        httpOptions: initialOptions,
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);
      runner.completeCurrent();
      await initFuture;
      await runner.waitForIdle();

      expect(service.httpOptions, same(initialOptions));

      await service.updateHttpOptions(updatedOptions);

      expect(service.httpOptions, same(updatedOptions));
      expect(runner.startedSubscriptions, hasLength(1));

      final updateFuture = service.updateSubscriptions(const [
        FilterSubscription(url: 'updated.txt'),
      ]);
      await runner.waitForStartedCount(2);

      expect(runner.startedSubscriptions.last.single.url, 'updated.txt');
      expect(runner.startedHttpOptions.last, same(updatedOptions));

      runner.completeCurrent();
      await updateFuture;
      await runner.waitForIdle();
      service.dispose();
    });

    test(
      'updateHttpOptions with refreshFilters schedules rebuild with current subscriptions',
      () async {
        final runner = _ControllableFilterJobRunner();
        final service = AdblockService.createForTest(jobRunner: runner);
        const updatedOptions = FilterHttpOptions(headers: {'x-request': 'runtime'});

        final initFuture = service.init(
          subscriptions: const [FilterSubscription(url: 'initial.txt')],
          storagePath: tempDir.path,
        );
        await runner.waitForStartedCount(1);
        runner.completeCurrent();
        await initFuture;
        await runner.waitForIdle();

        final refreshFuture = service.updateHttpOptions(updatedOptions, refreshFilters: true);
        await runner.waitForStartedCount(2);

        expect(runner.startedOperations, ['build:initial.txt', 'build:initial.txt']);
        expect(runner.startedHttpOptions.last, same(updatedOptions));
        expect(service.isReady.value, isFalse);

        runner.completeCurrent();
        await refreshFuture;
        await runner.waitForIdle();
        service.dispose();
      },
    );

    test('updateHttpOptions with refreshFilters replaces pending build options', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);
      const updatedOptions = FilterHttpOptions(headers: {'x-request': 'runtime'});

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);

      final updateFuture = service.updateSubscriptions(const [
        FilterSubscription(url: 'pending-update.txt'),
      ]);
      final refreshFuture = service.updateHttpOptions(updatedOptions, refreshFilters: true);

      await Future<void>.delayed(Duration.zero);
      expect(runner.startedOperations, ['build:initial.txt']);

      runner.completeCurrent();
      await runner.waitForStartedCount(2);
      await initFuture;

      expect(runner.startedOperations, ['build:initial.txt', 'build:pending-update.txt']);
      expect(runner.startedHttpOptions.last, same(updatedOptions));
      expect(await _isCompleted(updateFuture), isFalse);
      expect(await _isCompleted(refreshFuture), isFalse);

      runner.completeCurrent();
      await updateFuture;
      await refreshFuture;
      await runner.waitForIdle();
      service.dispose();
    });

    test('clearCache runs before pending subscription update', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);

      final updateFuture = service.updateSubscriptions(const [
        FilterSubscription(url: 'pending-update.txt'),
      ]);
      final clearFuture = service.clearCache();

      await Future<void>.delayed(Duration.zero);
      expect(runner.startedOperations, ['build:initial.txt']);

      runner.completeCurrent();
      await runner.waitForStartedCount(2);
      await initFuture;

      expect(runner.startedOperations, ['build:initial.txt', 'clear', 'build:pending-update.txt']);

      expect(await _isCompleted(clearFuture), isTrue);
      expect(await _isCompleted(updateFuture), isFalse);

      runner.completeCurrent();
      await updateFuture;
      await runner.waitForIdle();
      service.dispose();
    });

    test('clearCache future completes after clear job completes', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);
      runner.completeCurrent();
      await initFuture;
      await runner.waitForIdle();

      runner.holdNextClear();
      final clearFuture = service.clearCache();
      await Future<void>.delayed(Duration.zero);

      expect(runner.startedOperations.last, 'clear');
      expect(await _isCompleted(clearFuture), isFalse);

      runner.completeCurrentClear();
      await clearFuture;
      service.dispose();
    });

    test('throws when used before init or after dispose', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      expect(
        () => service.updateSubscriptions(const [FilterSubscription(url: 'update.txt')]),
        throwsStateError,
      );
      expect(() => service.updateHttpOptions(const FilterHttpOptions()), throwsStateError);
      expect(service.clearCache, throwsStateError);

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);
      runner.completeCurrent();
      await initFuture;
      service.dispose();

      expect(
        () => service.init(
          subscriptions: const [FilterSubscription(url: 'again.txt')],
          storagePath: tempDir.path,
        ),
        throwsStateError,
      );
      expect(
        () => service.updateSubscriptions(const [FilterSubscription(url: 'update.txt')]),
        throwsStateError,
      );
      expect(() => service.updateHttpOptions(const FilterHttpOptions()), throwsStateError);
      expect(service.clearCache, throwsStateError);
      service.dispose();
    });

    test('dispose does not dispose caller-owned stream observer', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);
      final observer = StreamWebViewObserver(delegates: const []);
      final events = <WebViewEvent>[];
      final subscription = observer.events.listen(events.add);

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        observer: observer,
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);
      runner.completeCurrent();
      await initFuture;
      service.dispose();

      observer.onEvent(const FilterCacheCleared());
      await Future<void>.delayed(Duration.zero);

      expect(events, [const FilterCacheCleared()]);

      await subscription.cancel();
      observer.dispose();
    });

    test('dispose completes active init future and prevents timers from starting', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      final initFuture = service.init(
        subscriptions: const [
          FilterSubscription(url: 'initial.txt', updateInterval: Duration(milliseconds: 1)),
        ],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);

      service.dispose();

      expect(await _isCompleted(initFuture), isTrue);

      runner.completeCurrent();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(runner.startedOperations, ['build:initial.txt']);
    });

    test('dispose prevents pending jobs from starting', () async {
      final runner = _ControllableFilterJobRunner();
      final service = AdblockService.createForTest(jobRunner: runner);

      final initFuture = service.init(
        subscriptions: const [FilterSubscription(url: 'initial.txt')],
        storagePath: tempDir.path,
      );
      await runner.waitForStartedCount(1);

      unawaited(service.updateSubscriptions(const [FilterSubscription(url: 'pending-update.txt')]));
      unawaited(service.clearCache());
      service.dispose();

      runner.completeCurrent();
      await initFuture;
      await Future<void>.delayed(Duration.zero);

      expect(runner.startedOperations, ['build:initial.txt']);
    });
  });
}

class _ControllableFilterJobRunner implements FilterJobRunner {
  final startedSubscriptions = <List<FilterSubscription>>[];
  final startedOperations = <String>[];
  final startedHttpOptions = <FilterHttpOptions>[];
  final startedStoragePaths = <String?>[];
  final _startedController = StreamController<int>.broadcast();
  Completer<void>? _current;
  Completer<void>? _currentClear;
  var _holdNextClear = false;

  @override
  Future<void> runBuildJob({
    required List<FilterSubscription> subscriptions,
    required FilterHttpOptions httpOptions,
    String? storagePath,
    bool useTestClient = false,
  }) {
    if (_current != null) throw StateError('Jobs must not run in parallel');
    startedSubscriptions.add(List.of(subscriptions));
    startedHttpOptions.add(httpOptions);
    startedStoragePaths.add(storagePath);
    startedOperations.add('build:${subscriptions.single.url}');
    _startedController.add(startedSubscriptions.length);
    _current = Completer<void>();
    return _current!.future.whenComplete(() => _current = null);
  }

  @override
  Future<void> runClearCacheJob({String? storagePath, bool useTestClient = false}) async {
    if (_current != null) throw StateError('Jobs must not run in parallel');
    if (_currentClear != null) throw StateError('Clear jobs must not run in parallel');
    startedOperations.add('clear');
    if (!_holdNextClear) return;
    _holdNextClear = false;
    _currentClear = Completer<void>();
    await _currentClear!.future.whenComplete(() => _currentClear = null);
  }

  @override
  void dispose() {}

  void completeCurrent() {
    final current = _current;
    if (current == null || current.isCompleted) return;
    current.complete();
  }

  void holdNextClear() {
    _holdNextClear = true;
  }

  void completeCurrentClear() {
    final current = _currentClear;
    if (current == null || current.isCompleted) return;
    current.complete();
  }

  Future<void> waitForStartedCount(int count) async {
    if (startedSubscriptions.length >= count) return;
    await _startedController.stream.firstWhere((startedCount) => startedCount >= count);
  }

  Future<void> waitForIdle() async {
    while (_current != null || _currentClear != null) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

Future<bool> _isCompleted(Future<void> future) async {
  var completed = false;
  unawaited(future.whenComplete(() => completed = true));
  await Future<void>.delayed(Duration.zero);
  return completed;
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
