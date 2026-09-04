import 'package:flutter_api/src/app_open_ad_state.dart';
import 'package:flutter_api/src/app_open_foreground_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late AppOpenForegroundPolicy policy;
  late AppOpenAdState state;

  setUp(() {
    now = DateTime(2026, 8, 21, 12);
    policy = AppOpenForegroundPolicy(now: () => now);
    state = AppOpenAdState(now: () => now, foregroundPolicy: policy);
  });

  void loadAd() {
    state.setAdsRequestAllowed(true);
    final loadGeneration = state.beginLoad()!;
    expect(state.completeLoad(loadGeneration), isTrue);
  }

  /// A real switch back to the app: `paused` happened before `resumed`.
  bool returnFromBackground() {
    state.markBackgrounded();
    return state.shouldShowOnForeground();
  }

  test('does not load or show without consent', () {
    expect(state.beginLoad(), isNull);
    expect(state.beginShow(), isFalse);
  });

  test('premium/no-ads blocks loading and showing', () {
    state.setAdsRequestAllowed(true);
    state.setDisabled(true);

    expect(state.beginLoad(), isNull);
    expect(state.beginShow(), isFalse);
  });

  test('does not retain an ad when consent is withdrawn during loading', () {
    state.setAdsRequestAllowed(true);
    final loadGeneration = state.beginLoad()!;

    state.setAdsRequestAllowed(false);

    expect(state.completeLoad(loadGeneration), isFalse);
    expect(state.isReady, isFalse);
  });

  test('a genuine return from background shows a ready ad', () {
    loadAd();

    expect(returnFromBackground(), isTrue);
  });

  test(
    'resumed without a preceding paused is not a switch back to the app',
    () {
      loadAd();

      // Permission dialog, UMP form, iOS alert: inactive -> resumed only.
      expect(state.shouldShowOnForeground(), isFalse);
      expect(returnFromBackground(), isTrue);
    },
  );

  test('suppression skips one eligible foreground event', () {
    loadAd();

    state.suppressNextForeground();

    expect(returnFromBackground(), isFalse);
  });

  test('foreground after suppression is eligible again', () {
    loadAd();

    state.suppressNextForeground();

    expect(returnFromBackground(), isFalse);
    expect(returnFromBackground(), isTrue);
  });

  test('an unconsumed one-shot suppression expires instead of eating a real '
      'return from background', () {
    loadAd();

    // A launch that never produced `resumed` (already granted permission).
    state.suppressNextForeground(timeout: const Duration(minutes: 5));
    now = now.add(const Duration(minutes: 6));

    expect(returnFromBackground(), isTrue);
  });

  test('beginShow skips the resume after its own fullscreen ad', () {
    loadAd();

    expect(returnFromBackground(), isTrue);
    expect(state.beginShow(), isTrue);
    expect(returnFromBackground(), isFalse);
    expect(state.beginShow(), isFalse);
  });

  test('resume arriving just after the ad is dismissed is still skipped', () {
    loadAd();
    state.beginShow();
    state.finishShow();
    // The next preload is ready before the late lifecycle event.
    loadAd();
    now = now.add(const Duration(seconds: 1));

    expect(returnFromBackground(), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(returnFromBackground(), isTrue);
  });

  test('application scope suppresses every foreground event while active', () {
    loadAd();

    final scope = policy.beginScope();
    expect(returnFromBackground(), isFalse);
    expect(returnFromBackground(), isFalse);
    scope.end();

    expect(returnFromBackground(), isTrue);
  });

  test('a fullscreen ad of another format blocks App Open within the '
      'configured interval', () {
    policy.minIntervalSinceFullscreenAd = const Duration(minutes: 2);
    loadAd();

    policy.recordFullscreenAdShown();
    now = now.add(const Duration(seconds: 90));
    expect(returnFromBackground(), isFalse);

    now = now.add(const Duration(seconds: 31));
    expect(returnFromBackground(), isTrue);
  });

  test('zero interval keeps the historical behaviour', () {
    loadAd();

    policy.recordFullscreenAdShown();
    expect(returnFromBackground(), isTrue);
  });

  test('does not show an App Open Ad after its four-hour cache TTL', () {
    loadAd();
    now = now.add(const Duration(hours: 4));

    expect(state.isExpired, isTrue);
    expect(state.beginShow(), isFalse);
    expect(returnFromBackground(), isFalse);
  });

  test('dismissal leaves the state ready for the next preload', () {
    loadAd();
    state.beginShow();
    state.finishShow();

    expect(state.beginLoad(), isNotNull);
  });

  test('a failed show also leaves the state ready for the next preload', () {
    loadAd();
    state.beginShow();
    state.finishShow();

    expect(state.beginLoad(), isNotNull);
  });
}
