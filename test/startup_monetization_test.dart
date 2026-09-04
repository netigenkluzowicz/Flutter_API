import 'package:flutter_api/flutter_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StartupMonetizationPolicy', () {
    const policy = StartupMonetizationPolicy(paywallLaunches: {1, 3, 20});

    test('routes the configured schedule', () {
      expect(policy.actionForLaunch(1), StartupMonetizationAction.paywall);
      expect(policy.actionForLaunch(2), StartupMonetizationAction.appOpen);
      expect(policy.actionForLaunch(3), StartupMonetizationAction.paywall);
      expect(policy.actionForLaunch(4), StartupMonetizationAction.appOpen);
      expect(policy.actionForLaunch(19), StartupMonetizationAction.appOpen);
      expect(policy.actionForLaunch(20), StartupMonetizationAction.paywall);
      expect(policy.actionForLaunch(21), StartupMonetizationAction.appOpen);
    });

    test('uses App Open for an empty schedule', () {
      const empty = StartupMonetizationPolicy();
      expect(empty.actionForLaunch(1), StartupMonetizationAction.appOpen);
    });

    test('supports another custom schedule', () {
      const custom = StartupMonetizationPolicy(paywallLaunches: {2, 8});
      expect(custom.actionForLaunch(2), StartupMonetizationAction.paywall);
      expect(custom.actionForLaunch(8), StartupMonetizationAction.paywall);
      expect(custom.actionForLaunch(1), StartupMonetizationAction.appOpen);
    });

    test('ignores invalid schedule entries and launch counts', () {
      const invalid = StartupMonetizationPolicy(paywallLaunches: {-1, 0, 2});
      expect(invalid.actionForLaunch(-1), StartupMonetizationAction.appOpen);
      expect(invalid.actionForLaunch(0), StartupMonetizationAction.appOpen);
      expect(invalid.actionForLaunch(2), StartupMonetizationAction.paywall);
    });
  });

  group('StartupLaunchCounter', () {
    test('first session returns and stores one', () async {
      final storage = _MemoryLaunchStorage();
      final counter = StartupLaunchCounter(storage: storage);

      expect(await counter.beginSession(), 1);
      expect(storage.values[StartupLaunchCounter.defaultStorageKey], 1);
    });

    test('a new instance increments the same store', () async {
      final storage = _MemoryLaunchStorage();

      expect(await StartupLaunchCounter(storage: storage).beginSession(), 1);
      expect(await StartupLaunchCounter(storage: storage).beginSession(), 2);
    });

    test('only increments once for one counter instance', () async {
      final storage = _MemoryLaunchStorage();
      final counter = StartupLaunchCounter(storage: storage);

      expect(await counter.beginSession(), 1);
      expect(await counter.beginSession(), 1);
      expect(storage.writeCalls, 1);
    });

    test('custom storage keys are independent', () async {
      final storage = _MemoryLaunchStorage();
      final first = StartupLaunchCounter(storage: storage, storageKey: 'first');
      final second = StartupLaunchCounter(
        storage: storage,
        storageKey: 'second',
      );

      expect(await first.beginSession(), 1);
      expect(await second.beginSession(), 1);
      expect(
        await StartupLaunchCounter(
          storage: storage,
          storageKey: 'first',
        ).beginSession(),
        2,
      );
    });

    test(
      'read errors return the documented fail-safe without crashing',
      () async {
        final counter = StartupLaunchCounter(
          storage: _ReadFailingLaunchStorage(),
        );

        expect(await counter.beginSession(), 1);
      },
    );

    test(
      'write errors return the documented fail-safe without crashing',
      () async {
        final counter = StartupLaunchCounter(
          storage: _WriteFailingLaunchStorage(),
        );

        expect(await counter.beginSession(), 1);
      },
    );
  });
}

class _MemoryLaunchStorage implements StartupLaunchStorage {
  final Map<String, int> values = <String, int>{};
  int writeCalls = 0;

  @override
  Future<int?> readLaunchCount(String storageKey) async => values[storageKey];

  @override
  Future<void> writeLaunchCount(String storageKey, int launchCount) async {
    writeCalls++;
    values[storageKey] = launchCount;
  }
}

class _ReadFailingLaunchStorage implements StartupLaunchStorage {
  @override
  Future<int?> readLaunchCount(String storageKey) =>
      throw StateError('storage unavailable');

  @override
  Future<void> writeLaunchCount(String storageKey, int launchCount) async {}
}

class _WriteFailingLaunchStorage implements StartupLaunchStorage {
  @override
  Future<int?> readLaunchCount(String storageKey) async => 4;

  @override
  Future<void> writeLaunchCount(String storageKey, int launchCount) =>
      throw StateError('storage unavailable');
}
