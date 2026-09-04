import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart'
    show ConsentRequestParameters;
import 'ad_consent.dart';
import 'adaptive_banner_ad.dart';
import 'app_open_ad.dart';
import 'interstitial_ad.dart';
import 'rewarded_ad.dart';

typedef StartupConsentRequester =
    Future<AdConsentResult> Function({
      ConsentRequestParameters? params,
      bool requestTrackingAuthorization,
    });

/// Why the advertising part of application startup finished.
enum StartupAdsCompletionReason {
  premiumUser,
  consentCannotRequestAds,
  appOpenNotAllowed,
  appOpenUnavailable,
  appOpenShown,
  appOpenFailed,
  consentFailed,
}

/// Immutable outcome of [StartupAdsCoordinator.run].
///
/// A null [consentResult] means the user was premium or UMP itself failed.
class StartupAdsResult {
  const StartupAdsResult({
    required this.premiumUser,
    required this.canRequestAds,
    required this.appOpenAttempted,
    required this.appOpenShown,
    required this.completionReason,
    this.consentResult,
    this.error,
  });

  final bool premiumUser;
  final AdConsentResult? consentResult;
  final bool canRequestAds;
  final bool appOpenAttempted;
  final bool appOpenShown;
  final StartupAdsCompletionReason completionReason;
  final Object? error;

  bool get privacyOptionsRequired =>
      consentResult?.privacyOptionsRequired ?? false;
}

/// Small adapter for the ad formats that startup policy may enable or disable.
///
/// An application normally uses [StartupAdsCoordinator.mobileAds]. Supplying this
/// interface makes startup policy deterministic to test and supports apps with
/// their own ad wrappers.
///
/// Banners are not part of this interface: they have no preload or try-show
/// stage, so a mounted banner reacts to `setBannerAdsAllowed` /
/// `disableBannerAd` on its own instead of going through the coordinator.
abstract interface class StartupAdsPlatform {
  FutureOr<void> enableAdsAfterConsent();
  FutureOr<void> disableAdsForPremium();
  FutureOr<void> preloadAppOpen();
  Future<AppOpenAdShowResult> tryShowReadyAppOpen();
}

class _MobileAdsStartupPlatform implements StartupAdsPlatform {
  const _MobileAdsStartupPlatform();

  @override
  void disableAdsForPremium() {
    setAppOpenAdsAllowed(false);
    setInterstitialAdsAllowed(false);
    setRewardedAdsAllowed(false);
    setBannerAdsAllowed(false);
    disableAppOpenAd();
    disableInterstitialAd();
    disableRewardedAd();
    disableBannerAd();
  }

  @override
  void enableAdsAfterConsent() {
    enableAppOpenAd();
    enableInterstitialAd();
    enableRewardedAd();
    enableBannerAd();
    setAppOpenAdsAllowed(true);
    setInterstitialAdsAllowed(true);
    setRewardedAdsAllowed(true);
    setBannerAdsAllowed(true);
  }

  @override
  Future<void> preloadAppOpen() => createAppOpenAd();

  @override
  Future<AppOpenAdShowResult> tryShowReadyAppOpen() => tryShowAppOpenAd();
}

/// Coordinates only the ad-related part of startup; it never presents UI such
/// as a paywall. The application decides what happens after [run] completes.
///
/// [run] waits for a premium check, UMP, and a fullscreen App Open Ad only
/// when an already-loaded ad is shown. It never waits for an ad network load.
class StartupAdsCoordinator {
  factory StartupAdsCoordinator({
    required FutureOr<bool> Function() premiumCheck,
    AdConsent? consent,
    StartupAdsPlatform? adsPlatform,
  }) => StartupAdsCoordinator._(
    premiumCheck,
    (consent ?? AdConsent()).requestConsent,
    adsPlatform ?? const _MobileAdsStartupPlatform(),
  );

  /// Test-friendly variant accepting the same operation as
  /// [AdConsent.requestConsent].
  factory StartupAdsCoordinator.withConsentRequester({
    required FutureOr<bool> Function() premiumCheck,
    required StartupConsentRequester requestConsent,
    required StartupAdsPlatform adsPlatform,
  }) => StartupAdsCoordinator._(premiumCheck, requestConsent, adsPlatform);

  StartupAdsCoordinator._(
    this._premiumCheck,
    this._requestConsent,
    this._adsPlatform,
  );

  final FutureOr<bool> Function() _premiumCheck;
  final StartupConsentRequester _requestConsent;
  final StartupAdsPlatform _adsPlatform;
  Future<StartupAdsResult>? _run;

  /// Uses the package's App Open, interstitial, and rewarded implementations.
  /// Configure App Open with [initAppOpenAd] before calling this method; setup
  /// itself is safe before consent because it does not request an ad.
  factory StartupAdsCoordinator.mobileAds({
    required FutureOr<bool> Function() premiumCheck,
    AdConsent? consent,
  }) => StartupAdsCoordinator(premiumCheck: premiumCheck, consent: consent);

  /// Runs once per coordinator instance. Concurrent or repeated calls return
  /// the same result and never duplicate consent UI or an App Open attempt.
  Future<StartupAdsResult> run({
    required bool allowAppOpen,
    ConsentRequestParameters? consentParameters,
    bool requestTrackingAuthorization = true,
  }) => _run ??= _runOnce(
    allowAppOpen: allowAppOpen,
    consentParameters: consentParameters,
    requestTrackingAuthorization: requestTrackingAuthorization,
  );

  Future<StartupAdsResult> _runOnce({
    required bool allowAppOpen,
    required ConsentRequestParameters? consentParameters,
    required bool requestTrackingAuthorization,
  }) async {
    if (await _premiumCheck()) {
      await _adsPlatform.disableAdsForPremium();
      return const StartupAdsResult(
        premiumUser: true,
        canRequestAds: false,
        appOpenAttempted: false,
        appOpenShown: false,
        completionReason: StartupAdsCompletionReason.premiumUser,
      );
    }

    late final AdConsentResult consentResult;
    try {
      consentResult = await _requestConsent(
        params: consentParameters,
        requestTrackingAuthorization: requestTrackingAuthorization,
      );
    } on Object catch (error) {
      await _adsPlatform.disableAdsForPremium();
      return StartupAdsResult(
        premiumUser: false,
        canRequestAds: false,
        appOpenAttempted: false,
        appOpenShown: false,
        completionReason: StartupAdsCompletionReason.consentFailed,
        error: error,
      );
    }

    if (!consentResult.canRequestAds) {
      await _adsPlatform.disableAdsForPremium();
      return StartupAdsResult(
        premiumUser: false,
        consentResult: consentResult,
        canRequestAds: false,
        appOpenAttempted: false,
        appOpenShown: false,
        completionReason: StartupAdsCompletionReason.consentCannotRequestAds,
      );
    }

    await _adsPlatform.enableAdsAfterConsent();
    if (!allowAppOpen) {
      return StartupAdsResult(
        premiumUser: false,
        consentResult: consentResult,
        canRequestAds: true,
        appOpenAttempted: false,
        appOpenShown: false,
        completionReason: StartupAdsCompletionReason.appOpenNotAllowed,
      );
    }

    // Preloading is deliberately unawaited: a cold-start network load must
    // never delay the application's transition to its own paywall/content.
    unawaited(Future<void>.sync(_adsPlatform.preloadAppOpen));
    final outcome = await _adsPlatform.tryShowReadyAppOpen();
    return StartupAdsResult(
      premiumUser: false,
      consentResult: consentResult,
      canRequestAds: true,
      appOpenAttempted: true,
      appOpenShown: outcome == AppOpenAdShowResult.shown,
      completionReason: switch (outcome) {
        AppOpenAdShowResult.shown => StartupAdsCompletionReason.appOpenShown,
        AppOpenAdShowResult.unavailable =>
          StartupAdsCompletionReason.appOpenUnavailable,
        AppOpenAdShowResult.failed => StartupAdsCompletionReason.appOpenFailed,
      },
    );
  }
}
