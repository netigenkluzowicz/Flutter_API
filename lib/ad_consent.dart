import 'package:google_mobile_ads/google_mobile_ads.dart';

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

  /// - [action] called when consentForm is dismissed or unavailable
  Future<void> consentInfo({
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
      (error) {
        if (onError != null) {
          onError();
        }
        throw (error.message);
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
        if (onError != null) {
          onError();
        }

        throw (formError.message);
      },
    );
  }

  /// - [action] called when consentForm is dismissed or unavailable,
  /// could be used to pop screen that was pushed during waiting on consentForm
  /// (consentForm isn't showed immediately after calling [resetConsent]);
  void resetConsent({
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
      (error) {
        if (onError != null) {
          onError();
        }
        throw (error.message);
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
        if (onError != null) {
          onError();
        }
      },
    );
  }
}
