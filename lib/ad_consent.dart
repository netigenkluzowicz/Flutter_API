import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

typedef ConsentCallback = FutureOr<void> Function();

/// - [consentInfo]
/// - [resetConsent]
class AdConsent {
  static final _emptyParams = ConsentRequestParameters();

  static ConsentRequestParameters params({
    DebugGeography? debugGeography,
    bool? tagForUnderAgeOfConsent,
    List<String>? testIdentifiers,
  }) => ConsentRequestParameters(
    tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
    consentDebugSettings: (kDebugMode && (debugGeography != null || testIdentifiers != null))
        ? ConsentDebugSettings(debugGeography: debugGeography, testIdentifiers: testIdentifiers)
        : null,
  );

  /// - [action] called when consentForm is closed or unavailable (pass completer.complete())
  /// - [onError] called on Consent error or tracking status is supported and not authorized
  Future<TrackingStatus> consentInfo({
    ConsentCallback? onError,
    ConsentCallback? action,
    ConsentRequestParameters? params,
  }) async {
    if (!Platform.isIOS) {
      await _consentInfo(onError: onError, action: action, params: params);
      return TrackingStatus.notSupported;
    }
    TrackingStatus status = await AppTrackingTransparency.trackingAuthorizationStatus;
    _infoLog("trackingAuthorizationStatus:$status");
    if (status == TrackingStatus.notDetermined) {
      status = await AppTrackingTransparency.requestTrackingAuthorization();
      _infoLog("requestTrackingAuthorization:$status");
    }
    if (status == TrackingStatus.authorized || status == TrackingStatus.notSupported) {
      await _consentInfo(onError: onError, action: action, params: params);
    } else if (onError != null) {
      onError();
    }
    return status;
  }

  Future<void> _consentInfo({
    ConsentCallback? onError,
    ConsentCallback? action,
    ConsentRequestParameters? params,
  }) async {
    ConsentInformation.instance.requestConsentInfoUpdate(
      params ?? _emptyParams,
      () async {
        final bool available = await ConsentInformation.instance.isConsentFormAvailable();
        _infoLog("ConsentFormAvailable:$available");
        if (available) {
          _loadForm(action: action, onError: onError);
        } else {
          if (action != null) {
            action();
          }
        }
      },
      (FormError formError) {
        _errorLog("_consentInfo errorCode:${formError.errorCode} message:${formError.message}");
        if (onError != null) {
          onError();
        }
      },
    );
  }

  void _loadForm({ConsentCallback? action, ConsentCallback? onError}) {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show((formError) async {
            if (action != null) {
              await action();
            }
          });
        } else if (action != null) {
          await action();
        }
      },
      (FormError formError) {
        _errorLog("_loadForm errorCode:${formError.errorCode} message:${formError.message}");
        if (onError != null) {
          onError();
        }
      },
    );
  }

  /// - [action] called when consentForm is dismissed, unavailable or after openAppSettings on iOS,
  /// could be used to pop screen that was pushed during waiting on consentForm
  /// (consentForm isn't showed immediately after calling [resetConsent]);
  void resetConsent({ConsentRequestParameters? params, ConsentCallback? action, ConsentCallback? onError}) {
    AppTrackingTransparency.requestTrackingAuthorization().then((TrackingStatus status) {
      _infoLog("trackingStatus:$status");
      if (status == TrackingStatus.authorized || status == TrackingStatus.notSupported) {
        _resetConsent(params: params, action: action, onError: onError);
      } else if (status == TrackingStatus.denied) {
        if (action != null) action();
        AppSettings.openAppSettings();
      }
    });
  }

  void _resetConsent({ConsentRequestParameters? params, ConsentCallback? action, ConsentCallback? onError}) {
    ConsentInformation.instance.requestConsentInfoUpdate(
      params ?? _emptyParams,
      () async {
        final bool available = await ConsentInformation.instance.isConsentFormAvailable();
        _infoLog("isConsentFormAvailable:$available");
        if (available) {
          _loadFormAgain(action: action, onError: onError);
        } else if (action != null) {
          action();
        }
      },
      (FormError formError) {
        _errorLog("_resetConsent errorCode:${formError.errorCode} message:${formError.message}");
        if (onError != null) {
          onError();
        }
      },
    );
  }

  void _loadFormAgain({ConsentCallback? action, ConsentCallback? onError}) {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        final ConsentStatus status = await ConsentInformation.instance.getConsentStatus();
        _infoLog("$status");
        if ([ConsentStatus.notRequired, ConsentStatus.required, ConsentStatus.obtained].contains(status)) {
          consentForm.show((formError) {
            if (action != null) {
              action();
            }
          });
        } else if (action != null) {
          action();
        }
      },
      (FormError formError) {
        _errorLog("_loadFormAgain errorCode:${formError.errorCode} message:${formError.message}");
        if (onError != null) {
          onError();
        }
      },
    );
  }
}

void _infoLog(Object? object) {
  if (!kDebugMode) return;
  printY("[AdConsent] $object");
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR("[AdConsent] ⚠️ ERROR $object");
}
