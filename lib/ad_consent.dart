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
    final completer = Completer<void>();
    FutureOr<void> done([FutureOr<void> Function()? cb]) async {
      if (cb != null) await cb();
      if (!completer.isCompleted) completer.complete();
    }

    TrackingStatus status = TrackingStatus.notSupported;

    if (Platform.isIOS) {
      status = await AppTrackingTransparency.trackingAuthorizationStatus;
      _infoLog("trackingAuthorizationStatus:$status");
      if (status == TrackingStatus.notDetermined) {
        status = await AppTrackingTransparency.requestTrackingAuthorization();
        _infoLog("requestTrackingAuthorization:$status");
      }
    }

    await _consentInfo(params: params, action: () => done(action), onError: () => done(onError));

    await completer.future;
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
        final before = await ConsentInformation.instance.getConsentStatus();
        if (before == ConsentStatus.required) {
          consentForm.show((formError) async {
            if (formError != null) _errorLog("show error: ${formError.message}");
            await action?.call();
          });
        } else {
          await action?.call();
        }
      },
      (FormError formError) async {
        _errorLog("_loadForm errorCode:${formError.errorCode} message:${formError.message}");
        await onError?.call();
      },
    );
  }

  /// - [action] called when consentForm is dismissed, unavailable or after openAppSettings on iOS,
  /// could be used to pop screen that was pushed during waiting on consentForm
  /// (consentForm isn't showed immediately after calling [resetConsent]);
  void resetConsent({ConsentRequestParameters? params, ConsentCallback? action, ConsentCallback? onError}) {
    if (!Platform.isIOS) {
      _resetConsent(params: params, action: action, onError: onError);
      return;
    }
    AppTrackingTransparency.requestTrackingAuthorization().then((TrackingStatus status) {
      _infoLog("trackingStatus:$status");
      if (status == TrackingStatus.authorized || status == TrackingStatus.notSupported) {
        _resetConsent(params: params, action: action, onError: onError);
      } else if (status == TrackingStatus.denied || status == TrackingStatus.restricted) {
        action?.call();
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
        final ConsentStatus before = await ConsentInformation.instance.getConsentStatus();
        _infoLog("before: $before");
        if ([ConsentStatus.notRequired, ConsentStatus.required, ConsentStatus.obtained].contains(before)) {
          consentForm.show((formError) async {
            if (formError != null) _errorLog("show error: ${formError.message}");
            await action?.call();
          });
        } else {
          await action?.call();
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
