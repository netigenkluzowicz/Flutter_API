import 'package:app_settings/app_settings.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

/// - [consentInfo]
/// - [resetConsent]
class AdConsent {
  final _emptyParams = ConsentRequestParameters();

  static ConsentRequestParameters params({
    DebugGeography? debugGeography,
    bool? tagForUnderAgeOfConsent,
    List<String>? testIdentifiers,
  }) =>
      ConsentRequestParameters(
        tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
        consentDebugSettings: ConsentDebugSettings(
          debugGeography: debugGeography,
          testIdentifiers: testIdentifiers,
        ),
      );

  /// - [action] called when consentForm is closed or unavailable (pass completer.complete())
  /// - [onError] called on Consent error or tracking status is supported and not authorized
  Future<void> consentInfo({
    Function? onError,
    Function? action,
    ConsentRequestParameters? params,
  }) async {
    final TrackingStatus status = await AppTrackingTransparency.requestTrackingAuthorization();
    printY("[DEV-LOG] AdConsent trackingStatus:$status");
    if (status == TrackingStatus.authorized || status == TrackingStatus.notSupported) {
      await _consentInfo(
        onError: onError,
        action: action,
        params: params,
      );
    } else if (onError != null) {
      onError();
    }
  }

  Future<void> _consentInfo({
    Function? onError,
    Function? action,
    ConsentRequestParameters? params,
  }) async {
    ConsentInformation.instance.requestConsentInfoUpdate(
      params ?? _emptyParams,
      () async {
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          _loadForm(action: action, onError: onError);
        } else {
          if (action != null) {
            action();
          }
        }
      },
      (FormError formError) {
        printR(
          "[DEV-LOG] flutter_api AdConsent().consentInfo errorCode:${formError.errorCode} message:${formError.message}",
        );
        if (onError != null) {
          onError();
        }
      },
    );
  }

  void _loadForm({
    Function? action,
    Function? onError,
  }) {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show(
            (formError) async {
              if (action != null) {
                await action();
              }
            },
          );
        } else if (action != null) {
          await action();
        }
      },
      (FormError formError) {
        printR(
          "[DEV-LOG] flutter_api AdConsent()._loadForm errorCode:${formError.errorCode} message:${formError.message}",
        );
        if (onError != null) {
          onError();
        }
      },
    );
  }

  /// - [action] called when consentForm is dismissed, unavailable or after openAppSettings on iOS,
  /// could be used to pop screen that was pushed during waiting on consentForm
  /// (consentForm isn't showed immediately after calling [resetConsent]);
  void resetConsent({
    ConsentRequestParameters? params,
    Function? action,
    Function? onError,
  }) {
    AppTrackingTransparency.requestTrackingAuthorization().then((TrackingStatus status) {
      printY("[DEV-LOG] AdConsent trackingStatus:$status");
      if (status == TrackingStatus.authorized || status == TrackingStatus.notSupported) {
        _resetConsent(
          params: params,
          action: action,
          onError: onError,
        );
      } else if (status == TrackingStatus.denied) {
        if (action != null) action();
        AppSettings.openAppSettings();
      }
    });
  }

  void _resetConsent({
    ConsentRequestParameters? params,
    Function? action,
    Function? onError,
  }) {
    ConsentInformation.instance.requestConsentInfoUpdate(
      params ?? _emptyParams,
      () async {
        if (await ConsentInformation.instance.isConsentFormAvailable()) {
          _loadFormAgain(action: action, onError: onError);
        } else if (action != null) {
          action();
        }
      },
      (FormError formError) {
        printR(
          "[DEV-LOG] flutter_api AdConsent().resetConsent errorCode:${formError.errorCode} message:${formError.message}",
        );
        if (onError != null) {
          onError();
        }
      },
    );
  }

  void _loadFormAgain({
    Function? action,
    Function? onError,
  }) {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.notRequired || status == ConsentStatus.obtained) {
          consentForm.show(
            (formError) {
              if (action != null) {
                action();
              }
            },
          );
        } else if (action != null) {
          action();
        }
      },
      (FormError formError) {
        printR(
          "[DEV-LOG] flutter_api AdConsent()._loadFormAgain errorCode:${formError.errorCode} message:${formError.message}",
        );
        if (onError != null) {
          onError();
        }
      },
    );
  }
}
