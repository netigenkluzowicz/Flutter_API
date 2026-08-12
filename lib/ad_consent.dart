import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

typedef ConsentCallback = FutureOr<void> Function();

/// Immutable snapshot of the current UMP and ATT state.
///
/// [canRequestAds] is the only value callers should use to decide whether an
/// ad may be loaded. UMP forwards the user's consent choices to Google Mobile
/// Ads, so applications should not infer personalization from geography.
class AdConsentResult {
  const AdConsentResult({
    required this.canRequestAds,
    required this.consentStatus,
    required this.privacyOptionsRequirementStatus,
    required this.trackingStatus,
    this.error,
  });

  final bool canRequestAds;
  final ConsentStatus consentStatus;
  final PrivacyOptionsRequirementStatus privacyOptionsRequirementStatus;
  final TrackingStatus trackingStatus;
  final FormError? error;

  bool get privacyOptionsRequired =>
      privacyOptionsRequirementStatus ==
      PrivacyOptionsRequirementStatus.required;
}

/// Coordinates Google UMP consent and, optionally, iOS ATT authorization.
class AdConsent {
  static final ConsentRequestParameters _emptyParams =
      ConsentRequestParameters();

  static ConsentRequestParameters params({
    DebugGeography? debugGeography,
    bool? tagForUnderAgeOfConsent,
    List<String>? testIdentifiers,
  }) => ConsentRequestParameters(
    tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
    consentDebugSettings:
        kDebugMode &&
            (debugGeography != null || testIdentifiers?.isNotEmpty == true)
        ? ConsentDebugSettings(
            debugGeography: debugGeography,
            testIdentifiers: testIdentifiers,
          )
        : null,
  );

  /// Requests fresh consent information on every app launch and displays the
  /// UMP form when required.
  ///
  /// ATT is requested only after the UMP flow and only when UMP allows ads.
  Future<AdConsentResult> requestConsent({
    ConsentRequestParameters? params,
    bool requestTrackingAuthorization = true,
  }) async {
    FormError? error = await _requestConsentInfoUpdate(params ?? _emptyParams);

    error ??= await _loadAndShowConsentFormIfRequired();

    var canRequestAds = await ConsentInformation.instance.canRequestAds();
    var trackingStatus = TrackingStatus.notSupported;

    if (Platform.isIOS) {
      trackingStatus =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (requestTrackingAuthorization &&
          canRequestAds &&
          trackingStatus == TrackingStatus.notDetermined) {
        trackingStatus =
            await AppTrackingTransparency.requestTrackingAuthorization();
      }
      _infoLog('trackingAuthorizationStatus: $trackingStatus');
    }

    final result = await _snapshot(
      trackingStatus: trackingStatus,
      error: error,
    );
    canRequestAds = result.canRequestAds;
    _infoLog(
      'consentStatus: ${result.consentStatus}, '
      'canRequestAds: $canRequestAds, '
      'privacyOptions: ${result.privacyOptionsRequirementStatus}',
    );
    return result;
  }

  /// Displays Google's privacy options form from an always-accessible settings
  /// entry point when UMP marks it as required.
  Future<AdConsentResult> showPrivacyOptionsForm() async {
    final completer = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm((formError) {
      if (!completer.isCompleted) {
        completer.complete(formError);
      }
    });

    final error = await completer.future;
    if (error != null) {
      _errorLog(
        'showPrivacyOptionsForm errorCode:${error.errorCode} '
        'message:${error.message}',
      );
    }
    return _snapshot(error: error);
  }

  Future<bool> get privacyOptionsRequired async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  Future<bool> get canRequestAds => ConsentInformation.instance.canRequestAds();

  /// Test-only helper. Never expose this as a production privacy action.
  Future<void> resetForTesting() async {
    if (!kDebugMode) {
      throw StateError('Consent reset is available only in debug builds.');
    }
    await ConsentInformation.instance.reset();
  }

  /// Compatibility wrapper for applications using the pre-3.44 API.
  @Deprecated('Use requestConsent(), which returns the complete consent state.')
  Future<TrackingStatus> consentInfo({
    ConsentCallback? onError,
    ConsentCallback? action,
    ConsentRequestParameters? params,
  }) async {
    final result = await requestConsent(params: params);
    if (result.error != null) {
      await onError?.call();
    } else {
      await action?.call();
    }
    return result.trackingStatus;
  }

  /// Compatibility wrapper. The production action is now the official UMP
  /// privacy options form, not a consent reset.
  @Deprecated('Use showPrivacyOptionsForm().')
  void resetConsent({
    ConsentRequestParameters? params,
    ConsentCallback? action,
    ConsentCallback? onError,
  }) {
    showPrivacyOptionsForm().then((result) async {
      if (result.error != null) {
        await onError?.call();
      } else {
        await action?.call();
      }
    });
  }

  Future<FormError?> _requestConsentInfoUpdate(
    ConsentRequestParameters params,
  ) {
    final completer = Completer<FormError?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () {
        if (!completer.isCompleted) completer.complete();
      },
      (formError) {
        _errorLog(
          'requestConsentInfoUpdate errorCode:${formError.errorCode} '
          'message:${formError.message}',
        );
        if (!completer.isCompleted) completer.complete(formError);
      },
    );
    return completer.future;
  }

  Future<FormError?> _loadAndShowConsentFormIfRequired() {
    final completer = Completer<FormError?>();
    ConsentForm.loadAndShowConsentFormIfRequired((formError) {
      if (formError != null) {
        _errorLog(
          'loadAndShowConsentFormIfRequired errorCode:${formError.errorCode} '
          'message:${formError.message}',
        );
      }
      if (!completer.isCompleted) completer.complete(formError);
    });
    return completer.future;
  }

  Future<AdConsentResult> _snapshot({
    TrackingStatus trackingStatus = TrackingStatus.notSupported,
    FormError? error,
  }) async {
    final values = await Future.wait<Object>([
      ConsentInformation.instance.canRequestAds(),
      ConsentInformation.instance.getConsentStatus(),
      ConsentInformation.instance.getPrivacyOptionsRequirementStatus(),
    ]);

    return AdConsentResult(
      canRequestAds: values[0] as bool,
      consentStatus: values[1] as ConsentStatus,
      privacyOptionsRequirementStatus:
          values[2] as PrivacyOptionsRequirementStatus,
      trackingStatus: trackingStatus,
      error: error,
    );
  }
}

void _infoLog(Object? object) {
  if (!kDebugMode) return;
  printY('[AdConsent] $object');
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR('[AdConsent] ⚠️ ERROR $object');
}
