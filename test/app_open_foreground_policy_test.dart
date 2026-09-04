import 'package:flutter_api/src/app_open_foreground_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late AppOpenForegroundPolicy policy;

  setUp(() {
    now = DateTime(2026, 9, 4, 10);
    policy = AppOpenForegroundPolicy(now: () => now);
  });

  bool returnFromBackground() {
    policy.markBackgrounded();
    return policy.allowsForegroundShow();
  }

  group('background gate', () {
    test('allows only a resumed that follows paused', () {
      expect(policy.allowsForegroundShow(), isFalse);
      expect(returnFromBackground(), isTrue);
      expect(policy.allowsForegroundShow(), isFalse);
    });
  });

  group('scope', () {
    test('swallows the resumed emitted inside it and nothing after', () {
      final scope = policy.beginScope();
      expect(policy.isSuppressed, isTrue);
      expect(returnFromBackground(), isFalse);
      scope.end();

      expect(policy.isSuppressed, isFalse);
      expect(returnFromBackground(), isTrue);
    });

    test('ending before its resumed arms only a short grace', () {
      final scope = policy.beginScope();
      scope.end();

      now = now.add(const Duration(seconds: 2));
      expect(returnFromBackground(), isFalse);
      expect(returnFromBackground(), isTrue);
    });

    test('grace expires so a later genuine return is not eaten', () {
      final scope = policy.beginScope();
      scope.end();

      now = now.add(const Duration(seconds: 10));
      expect(returnFromBackground(), isTrue);
    });

    test('nested scopes suppress until the last one ends', () {
      final outer = policy.beginScope();
      final inner = policy.beginScope();
      expect(returnFromBackground(), isFalse);
      inner.end();
      expect(returnFromBackground(), isFalse);
      outer.end();

      expect(returnFromBackground(), isTrue);
    });

    test('a nested scope does not inherit the foreground of the outer one', () {
      // Interstitial dismissed, then the purchase sheet opens before the
      // interstitial scope is closed: the purchase must still get its own
      // grace for the `resumed` that closing the sheet emits.
      final interstitial = policy.beginScope();
      expect(returnFromBackground(), isFalse);
      final purchase = policy.beginScope();
      interstitial.end();
      purchase.end();

      now = now.add(const Duration(seconds: 3));
      expect(returnFromBackground(), isFalse);
    });

    test('the grace of a nested scope expires like any other', () {
      final interstitial = policy.beginScope();
      expect(returnFromBackground(), isFalse);
      final purchase = policy.beginScope();
      interstitial.end();
      purchase.end();

      now = now.add(const Duration(seconds: 4));
      expect(returnFromBackground(), isTrue);
    });

    test('a nested scope that saw its own foreground arms no grace', () {
      final interstitial = policy.beginScope();
      final purchase = policy.beginScope();
      expect(returnFromBackground(), isFalse);
      interstitial.end();
      purchase.end();

      expect(returnFromBackground(), isTrue);
    });

    test('a forgotten scope expires after its timeout', () {
      policy.beginScope(timeout: const Duration(minutes: 10));
      now = now.add(const Duration(minutes: 11));

      expect(policy.isSuppressed, isFalse);
      expect(returnFromBackground(), isTrue);
    });

    test('end is idempotent and reports activity', () {
      final scope = policy.beginScope();
      expect(scope.isActive, isTrue);
      scope.end();
      scope.end();
      expect(scope.isActive, isFalse);
      // Only the short grace for a late resumed remains.
      expect(policy.isSuppressed, isTrue);
      now = now.add(const Duration(seconds: 4));
      expect(policy.isSuppressed, isFalse);
    });
  });

  group('one-shot', () {
    test('is consumed by any resumed, also one without paused', () {
      policy.suppressNextForeground();
      expect(policy.allowsForegroundShow(), isFalse);
      expect(returnFromBackground(), isTrue);
    });

    test('longer request wins over a shorter pending one', () {
      policy.suppressNextForeground(timeout: const Duration(seconds: 3));
      policy.suppressNextForeground(timeout: const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 1));

      expect(returnFromBackground(), isFalse);
    });

    test('expires and no longer blocks', () {
      policy.suppressNextForeground(timeout: const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 5, seconds: 1));

      expect(policy.isSuppressed, isFalse);
      expect(returnFromBackground(), isTrue);
    });
  });

  group('fullscreen ad interval', () {
    test('blocks within the interval and allows after it', () {
      policy.minIntervalSinceFullscreenAd = const Duration(minutes: 2);
      policy.recordFullscreenAdShown();

      now = now.add(const Duration(minutes: 1));
      expect(returnFromBackground(), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(returnFromBackground(), isTrue);
    });

    test('is disabled at zero', () {
      policy.recordFullscreenAdShown();
      expect(returnFromBackground(), isTrue);
    });
  });

  test('reset clears everything', () {
    policy.beginScope();
    policy.suppressNextForeground();
    policy.recordFullscreenAdShown();
    policy.reset();

    expect(policy.isSuppressed, isFalse);
    expect(policy.lastFullscreenAdAt, isNull);
  });
}
