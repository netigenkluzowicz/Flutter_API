import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter_api/flutter_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('premium finishes without consent or ads', () async {
    final ads = _FakeAds();
    var consentCalls = 0;
    final coordinator = StartupAdsCoordinator.withConsentRequester(
      premiumCheck: () async => true,
      requestConsent: ({params, requestTrackingAuthorization = true}) async {
        consentCalls++;
        return _consent(canRequestAds: true);
      },
      adsPlatform: ads,
    );

    final result = await coordinator.run(allowAppOpen: true);

    expect(result.premiumUser, isTrue);
    expect(result.completionReason, StartupAdsCompletionReason.premiumUser);
    expect(consentCalls, 0);
    expect(ads.disableCalls, 1);
    expect(ads.preloadCalls, 0);
  });

  test(
    'consent happens before ads and false consent finishes immediately',
    () async {
      final events = <String>[];
      final ads = _FakeAds(events: events);
      final coordinator = StartupAdsCoordinator.withConsentRequester(
        premiumCheck: () => false,
        requestConsent: ({params, requestTrackingAuthorization = true}) async {
          events.add('consent');
          return _consent(canRequestAds: false);
        },
        adsPlatform: ads,
      );

      final result = await coordinator.run(allowAppOpen: true);

      expect(result.canRequestAds, isFalse);
      expect(result.privacyOptionsRequired, isTrue);
      expect(
        result.completionReason,
        StartupAdsCompletionReason.consentCannotRequestAds,
      );
      expect(events, ['consent', 'disable']);
      expect(ads.preloadCalls, 0);
    },
  );

  test(
    'app-open disabled completes after consent without attempting it',
    () async {
      final ads = _FakeAds();
      final coordinator = _coordinator(ads);

      final result = await coordinator.run(allowAppOpen: false);

      expect(result.canRequestAds, isTrue);
      expect(result.appOpenAttempted, isFalse);
      expect(
        result.completionReason,
        StartupAdsCompletionReason.appOpenNotAllowed,
      );
      expect(ads.enableCalls, 1);
      expect(ads.preloadCalls, 0);
    },
  );

  test('unavailable App Open does not wait for its preload', () async {
    final ads = _FakeAds(outcome: AppOpenAdShowResult.unavailable);
    final result = await _coordinator(ads).run(allowAppOpen: true);

    expect(result.appOpenAttempted, isTrue);
    expect(result.appOpenShown, isFalse);
    expect(
      result.completionReason,
      StartupAdsCompletionReason.appOpenUnavailable,
    );
    expect(ads.preloadCalls, 1);
  });

  test('shown and failed App Open both finish the stage', () async {
    final shown = await _coordinator(
      _FakeAds(outcome: AppOpenAdShowResult.shown),
    ).run(allowAppOpen: true);
    final failed = await _coordinator(
      _FakeAds(outcome: AppOpenAdShowResult.failed),
    ).run(allowAppOpen: true);

    expect(shown.appOpenShown, isTrue);
    expect(shown.completionReason, StartupAdsCompletionReason.appOpenShown);
    expect(failed.appOpenShown, isFalse);
    expect(failed.completionReason, StartupAdsCompletionReason.appOpenFailed);
  });

  test('repeated runs share one startup operation', () async {
    final ads = _FakeAds();
    final coordinator = _coordinator(ads);

    final results = await Future.wait([
      coordinator.run(allowAppOpen: false),
      coordinator.run(allowAppOpen: true),
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(ads.enableCalls, 1);
  });
}

StartupAdsCoordinator _coordinator(_FakeAds ads) =>
    StartupAdsCoordinator.withConsentRequester(
      premiumCheck: () async => false,
      requestConsent: ({params, requestTrackingAuthorization = true}) async =>
          _consent(canRequestAds: true),
      adsPlatform: ads,
    );

AdConsentResult _consent({required bool canRequestAds}) => AdConsentResult(
  canRequestAds: canRequestAds,
  consentStatus: ConsentStatus.obtained,
  privacyOptionsRequirementStatus: PrivacyOptionsRequirementStatus.required,
  trackingStatus: TrackingStatus.notSupported,
);

class _FakeAds implements StartupAdsPlatform {
  _FakeAds({this.outcome = AppOpenAdShowResult.unavailable, this._events});

  final AppOpenAdShowResult outcome;
  final List<String>? _events;
  int disableCalls = 0;
  int enableCalls = 0;
  int preloadCalls = 0;

  @override
  void disableAdsForPremium() {
    disableCalls++;
    _events?.add('disable');
  }

  @override
  void enableAdsAfterConsent() {
    enableCalls++;
    _events?.add('enable');
  }

  @override
  Future<void> preloadAppOpen() async {
    preloadCalls++;
  }

  @override
  Future<AppOpenAdShowResult> tryShowReadyAppOpen() async => outcome;
}
