import 'package:flutter_api/src/app_open_ad_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late AppOpenAdState state;

  setUp(() {
    now = DateTime(2026, 8, 21, 12);
    state = AppOpenAdState(now: () => now);
  });

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

  test('a second foreground event cannot show the same ad twice', () {
    state.setAdsRequestAllowed(true);
    final loadGeneration = state.beginLoad()!;
    expect(state.completeLoad(loadGeneration), isTrue);

    expect(state.shouldShowOnForeground(), isTrue);
    expect(state.beginShow(), isTrue);
    expect(state.shouldShowOnForeground(), isFalse);
    expect(state.beginShow(), isFalse);
  });

  test('does not show an App Open Ad after its four-hour cache TTL', () {
    state.setAdsRequestAllowed(true);
    final loadGeneration = state.beginLoad()!;
    expect(state.completeLoad(loadGeneration), isTrue);
    now = now.add(const Duration(hours: 4));

    expect(state.isExpired, isTrue);
    expect(state.beginShow(), isFalse);
  });

  test('dismissal leaves the state ready for the next preload', () {
    state.setAdsRequestAllowed(true);
    final loadGeneration = state.beginLoad()!;
    state.completeLoad(loadGeneration);
    state.beginShow();
    state.finishShow();

    expect(state.beginLoad(), isNotNull);
  });

  test('a failed show also leaves the state ready for the next preload', () {
    state.setAdsRequestAllowed(true);
    final loadGeneration = state.beginLoad()!;
    state.completeLoad(loadGeneration);
    state.beginShow();
    state.finishShow();

    expect(state.beginLoad(), isNotNull);
  });
}
