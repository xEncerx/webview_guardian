import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:webview_guardian/src/data/data.dart';
import 'package:webview_guardian/src/domain/domain.dart';
import 'package:webview_guardian/src/infrastructure/infrastructure.dart';

void main() {
  group('FilterIsolateManager Integration', () {
    late Directory tempDir;
    late File testFilterFile;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('filter_isolate_test_');

      // We will point the test client to this file
      testFilterFile = File('${tempDir.path}/test_filter.txt')
        ..writeAsStringSync(r'''
[Adblock Plus 2.0]
! Title: EasyList Test

||ads.example.com^
||tracker.com^$script,third-party
@@||good.com^
example.com##.banner-ad
''');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should spawn isolate, run pipeline, compile engine and save to file', () async {
      final completer = Completer<CompiledFilterEngine>();
      final errors = <WebViewError>[];
      final events = <WebViewEvent>[];

      final manager = FilterIsolateManager(
        onEngineReady: (engine, fromCache, totalRules, time) {
          completer.complete(engine);
        },
        onWorkerEvent: events.add,
        onWorkerError: errors.add,
      );

      await manager.spawn(storagePath: tempDir.path, useTestClient: true);

      manager.sendSubscriptions(
        subscriptions: [
          FilterSubscription(
            url: testFilterFile.path,
          ),
        ],
        httpOptions: const FilterHttpOptions(),
      );

      final engine = await completer.future.timeout(const Duration(seconds: 5));

      expect(engine, isNotNull);
      expect(errors, isEmpty);
      expect(engine.cosmeticHideRules.containsKey('example.com'), isTrue);

      final engineFile = File('${tempDir.path}/adblocker/compiled_filter_engine.bin');
      expect(engineFile.existsSync(), isTrue, reason: 'Engine file should be written to disk');

      final filterListsDir = Directory('${tempDir.path}/adblocker/filter_lists');
      expect(filterListsDir.existsSync(), isTrue);
      expect(filterListsDir.listSync().isNotEmpty, isTrue);

      manager.dispose();
    });

    test('runBuildJob should complete and release the worker for the next job', () async {
      final engines = <CompiledFilterEngine>[];
      final manager = FilterIsolateManager(
        onEngineReady: (engine, _, _, _) => engines.add(engine),
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      await manager.runBuildJob(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
        storagePath: tempDir.path,
        useTestClient: true,
      );
      await manager.runBuildJob(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
        storagePath: tempDir.path,
        useTestClient: true,
      );

      expect(engines, hasLength(2));
    });

    test('dispose should complete the active build job with cancellation error', () async {
      final manager = FilterIsolateManager(
        onEngineReady: (_, _, _, _) {},
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      final job = manager.runBuildJob(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
        storagePath: tempDir.path,
        useTestClient: true,
      );

      manager.dispose();

      await expectLater(
        job.timeout(const Duration(seconds: 5)),
        throwsA(isA<FilterIsolateJobCancelled>()),
      );
    });

    test('dispose should complete the active clear cache job with cancellation error', () async {
      final manager = FilterIsolateManager(
        onEngineReady: (_, _, _, _) {},
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      final job = manager.runClearCacheJob(
        storagePath: tempDir.path,
        useTestClient: true,
      );

      manager.dispose();

      await expectLater(
        job.timeout(const Duration(seconds: 5)),
        throwsA(isA<FilterIsolateJobCancelled>()),
      );
    });

    test('concurrent runBuildJob rejection should be a failed future', () async {
      final manager = FilterIsolateManager(
        onEngineReady: (_, _, _, _) {},
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      final activeJob = manager.runBuildJob(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
        storagePath: tempDir.path,
        useTestClient: true,
      );
      final rejectedJob = manager.runBuildJob(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
        storagePath: tempDir.path,
        useTestClient: true,
      );

      await expectLater(rejectedJob, throwsA(isA<StateError>()));

      manager.dispose();
      await expectLater(activeJob, throwsA(isA<FilterIsolateJobCancelled>()));
    });

    test('runBuildJob should complete after terminal cache restore failure', () async {
      final errors = <WebViewError>[];
      final invalidStoragePath = File('${tempDir.path}/not_a_directory')..writeAsStringSync('x');
      final manager = FilterIsolateManager(
        onEngineReady: (_, _, _, _) {},
        onWorkerEvent: (_) {},
        onWorkerError: errors.add,
      );

      await expectLater(
        manager
            .runBuildJob(
              subscriptions: [FilterSubscription(url: testFilterFile.path)],
              httpOptions: const FilterHttpOptions(),
              storagePath: invalidStoragePath.path,
              useTestClient: true,
            )
            .timeout(const Duration(seconds: 5)),
        completes,
      );

      expect(errors.whereType<CacheRestoreFailed>(), isNotEmpty);

      await manager.runBuildJob(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
        storagePath: tempDir.path,
        useTestClient: true,
      );
    });

    test('should restore engine from cache on second run (Cold Start Cache Hit)', () async {
      // --- RUN 1: Download and compile ---
      final completer1 = Completer<(CompiledFilterEngine, bool, int)>();
      final manager1 = FilterIsolateManager(
        onEngineReady: (engine, fromCache, totalRules, _) =>
            completer1.complete((engine, fromCache, totalRules)),
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      await manager1.spawn(storagePath: tempDir.path, useTestClient: true);
      manager1.sendSubscriptions(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
      );

      final result1 = await completer1.future.timeout(const Duration(seconds: 5));
      expect(result1.$2, isFalse, reason: 'First run should NOT be from cache');
      final originalRuleCount = result1.$3;
      expect(originalRuleCount, greaterThan(0));
      manager1.dispose();

      // Wait a moment for ports to close
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // --- RUN 2: Restore from cache ---
      final completer2 = Completer<(CompiledFilterEngine, bool, int)>();
      final manager2 = FilterIsolateManager(
        onEngineReady: (engine, fromCache, totalRules, _) =>
            completer2.complete((engine, fromCache, totalRules)),
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      await manager2.spawn(storagePath: tempDir.path, useTestClient: true);
      manager2.sendSubscriptions(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
      );

      final result2 = await completer2.future.timeout(const Duration(seconds: 5));
      expect(result2.$2, isTrue, reason: 'Second run SHOULD be restored from cache');
      expect(result2.$3, equals(originalRuleCount));
      manager2.dispose();
    });

    test(
      'should restore cached engine when subscription source is unavailable but cache exists',
      () async {
        final completer1 = Completer<(CompiledFilterEngine, bool, int)>();
        final manager1 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer1.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: (_) {},
        );

        await manager1.spawn(storagePath: tempDir.path, useTestClient: true);
        manager1.sendSubscriptions(
          subscriptions: [FilterSubscription(url: testFilterFile.path)],
          httpOptions: const FilterHttpOptions(),
        );

        final result1 = await completer1.future.timeout(const Duration(seconds: 5));
        expect(result1.$2, isFalse);
        manager1.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 100));
        await testFilterFile.delete();

        final completer2 = Completer<(CompiledFilterEngine, bool, int)>();
        final errors = <WebViewError>[];
        final manager2 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer2.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: errors.add,
        );

        await manager2.spawn(storagePath: tempDir.path, useTestClient: true);
        manager2.sendSubscriptions(
          subscriptions: [FilterSubscription(url: testFilterFile.path)],
          httpOptions: const FilterHttpOptions(),
        );

        final result2 = await completer2.future.timeout(const Duration(seconds: 5));
        expect(errors.whereType<FilterFetchFailed>(), isNotEmpty);
        expect(result2.$2, isTrue);
        expect(result2.$3, result1.$3);

        manager2.dispose();
      },
    );

    test(
      'should not restore cached engine for a changed subscription set after fetch failure',
      () async {
        final completer1 = Completer<(CompiledFilterEngine, bool, int)>();
        final manager1 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer1.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: (_) {},
        );

        await manager1.spawn(storagePath: tempDir.path, useTestClient: true);
        manager1.sendSubscriptions(
          subscriptions: [FilterSubscription(url: testFilterFile.path)],
          httpOptions: const FilterHttpOptions(),
        );

        final result1 = await completer1.future.timeout(const Duration(seconds: 5));
        expect(result1.$2, isFalse, reason: 'Initial run should compile the one-list engine');
        manager1.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final missingFilterFile = File('${tempDir.path}/missing_filter.txt');
        final completer2 = Completer<(CompiledFilterEngine, bool, int)>();
        final errors = <WebViewError>[];
        final manager2 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer2.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: errors.add,
        );

        await manager2.spawn(storagePath: tempDir.path, useTestClient: true);
        manager2.sendSubscriptions(
          subscriptions: [
            FilterSubscription(url: testFilterFile.path),
            FilterSubscription(url: missingFilterFile.path),
          ],
          httpOptions: const FilterHttpOptions(),
        );

        final result2 = await completer2.future.timeout(const Duration(seconds: 5));

        expect(errors.whereType<FilterFetchFailed>(), isNotEmpty);
        expect(
          result2.$2,
          isFalse,
          reason: 'A one-list engine cache must not be restored for a two-list subscription set',
        );

        manager2.dispose();
      },
    );

    test(
      'should not cache and restore a partial engine after repeated subscription fetch failures',
      () async {
        final completer1 = Completer<(CompiledFilterEngine, bool, int)>();
        final manager1 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer1.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: (_) {},
        );

        await manager1.spawn(storagePath: tempDir.path, useTestClient: true);
        manager1.sendSubscriptions(
          subscriptions: [FilterSubscription(url: testFilterFile.path)],
          httpOptions: const FilterHttpOptions(),
        );

        await completer1.future.timeout(const Duration(seconds: 5));
        manager1.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final missingFilterFile = File('${tempDir.path}/missing_filter.txt');
        final failedSubscriptions = [
          FilterSubscription(url: testFilterFile.path),
          FilterSubscription(url: missingFilterFile.path),
        ];

        final completer2 = Completer<(CompiledFilterEngine, bool, int)>();
        final manager2 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer2.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: (_) {},
        );

        await manager2.spawn(storagePath: tempDir.path, useTestClient: true);
        manager2.sendSubscriptions(
          subscriptions: failedSubscriptions,
          httpOptions: const FilterHttpOptions(),
        );

        final result2 = await completer2.future.timeout(const Duration(seconds: 5));
        expect(result2.$2, isFalse, reason: 'First failed update may compile but must not restore');
        manager2.dispose();

        await Future<void>.delayed(const Duration(milliseconds: 100));

        final completer3 = Completer<(CompiledFilterEngine, bool, int)>();
        final manager3 = FilterIsolateManager(
          onEngineReady: (engine, fromCache, totalRules, _) =>
              completer3.complete((engine, fromCache, totalRules)),
          onWorkerEvent: (_) {},
          onWorkerError: (_) {},
        );

        await manager3.spawn(storagePath: tempDir.path, useTestClient: true);
        manager3.sendSubscriptions(
          subscriptions: failedSubscriptions,
          httpOptions: const FilterHttpOptions(),
        );

        final result3 = await completer3.future.timeout(const Duration(seconds: 5));
        expect(
          result3.$2,
          isFalse,
          reason: 'Repeated failures must not restore a cached partial engine',
        );

        manager3.dispose();
      },
    );

    test(
      'should ignore concurrent sendSubscriptions calls (isPipelineRunning protection)',
      () async {
        final completer = Completer<void>();
        var readyCount = 0;

        final manager = FilterIsolateManager(
          onEngineReady: (_, _, _, _) {
            readyCount++;
            if (!completer.isCompleted) completer.complete();
          },
          onWorkerEvent: (_) {},
          onWorkerError: (_) {},
        );

        await manager.spawn(storagePath: tempDir.path, useTestClient: true);

        // Send two requests back-to-back
        manager
          ..sendSubscriptions(
            subscriptions: [FilterSubscription(url: testFilterFile.path)],
            httpOptions: const FilterHttpOptions(),
          )
          ..sendSubscriptions(
            subscriptions: [FilterSubscription(url: testFilterFile.path)],
            httpOptions: const FilterHttpOptions(),
          );

        // Wait for the first one to complete
        await completer.future.timeout(const Duration(seconds: 5));

        // Give a little extra time to see if a second response arrives incorrectly
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(readyCount, 1, reason: 'Engine should only be compiled and returned once');
        manager.dispose();
      },
    );

    test('should rebuild engine if a subscription is removed (orphan cleanup)', () async {
      // RUN 1: Add TWO subscriptions
      final completer1 = Completer<(CompiledFilterEngine, bool, int)>();
      final manager1 = FilterIsolateManager(
        onEngineReady: (engine, fromCache, totalRules, _) =>
            completer1.complete((engine, fromCache, totalRules)),
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      final secondFilterFile = File('${tempDir.path}/second_filter.txt')
        ..writeAsStringSync('''
[Adblock Plus 2.0]
||anotherexample.com^
''');

      await manager1.spawn(storagePath: tempDir.path, useTestClient: true);
      manager1.sendSubscriptions(
        subscriptions: [
          FilterSubscription(url: testFilterFile.path),
          FilterSubscription(url: secondFilterFile.path),
        ],
        httpOptions: const FilterHttpOptions(),
      );

      final result1 = await completer1.future.timeout(const Duration(seconds: 5));
      expect(result1.$2, isFalse, reason: 'First run should not be from cache');
      final totalRulesWithTwoLists = result1.$3;
      manager1.dispose();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // RUN 2: Provide only ONE subscription
      final completer2 = Completer<(CompiledFilterEngine, bool, int)>();
      final manager2 = FilterIsolateManager(
        onEngineReady: (engine, fromCache, totalRules, _) =>
            completer2.complete((engine, fromCache, totalRules)),
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      await manager2.spawn(storagePath: tempDir.path, useTestClient: true);
      manager2.sendSubscriptions(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
      );

      final result2 = await completer2.future.timeout(const Duration(seconds: 5));

      // Should recompile (NOT from cache) because an orphan was deleted
      expect(result2.$2, isFalse, reason: 'Should recompile because a list was removed');
      expect(result2.$3, lessThan(totalRulesWithTwoLists), reason: 'Should have fewer rules now');

      manager2.dispose();
    });

    test('should emit WebViewEvents (e.g., FilterListFetchStarted) to observer', () async {
      final completer = Completer<void>();
      final events = <WebViewEvent>[];

      final manager = FilterIsolateManager(
        onEngineReady: (_, _, _, _) {
          completer.complete();
        },
        onWorkerEvent: events.add,
        onWorkerError: (_) {},
      );

      await manager.spawn(storagePath: tempDir.path, useTestClient: true);
      manager.sendSubscriptions(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
      );

      await completer.future.timeout(const Duration(seconds: 5));

      expect(events, isNotEmpty, reason: 'Should have received events');

      // Verify FilterListFetchStarted was emitted
      final fetchStartedEvents = events.where(
        (e) => e.runtimeType.toString() == 'FilterListFetchStarted',
      );
      expect(
        fetchStartedEvents,
        isNotEmpty,
        reason: 'FilterListFetchStarted should be in the events list',
      );

      manager.dispose();
    });

    test('should clear cache when sendClearCacheCommand is called', () async {
      final completer = Completer<CompiledFilterEngine>();
      final manager = FilterIsolateManager(
        onEngineReady: (engine, _, _, _) => completer.complete(engine),
        onWorkerEvent: (_) {},
        onWorkerError: (_) {},
      );

      await manager.spawn(storagePath: tempDir.path, useTestClient: true);
      manager.sendSubscriptions(
        subscriptions: [FilterSubscription(url: testFilterFile.path)],
        httpOptions: const FilterHttpOptions(),
      );

      await completer.future.timeout(const Duration(seconds: 5));

      final engineFile = File('${tempDir.path}/adblocker/compiled_filter_engine.bin');
      final filterListsDir = Directory('${tempDir.path}/adblocker/filter_lists');

      expect(engineFile.existsSync(), isTrue);
      expect(filterListsDir.existsSync(), isTrue);
      expect(filterListsDir.listSync().isNotEmpty, isTrue);

      manager.sendClearCacheCommand();

      // Wait for isolate to process the command
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(engineFile.existsSync(), isFalse, reason: 'Engine file should be deleted');
      expect(
        filterListsDir.existsSync(),
        isFalse,
        reason: 'Filter lists directory should be deleted',
      );

      manager.dispose();
    });
  });
}
