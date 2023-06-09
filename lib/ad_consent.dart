import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsent {
  final params = ConsentRequestParameters();

  Future<void> consentInfo({Function? onError, Function? showAd}) async {
    ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        loadForm(function: showAd ?? () {}, onError: onError ?? () {});
      } else {
        if (showAd != null) {
          showAd();
        }
      }
    }, (error) {
      if (onError != null) {
        onError();
      }
      throw (error.message);
    });
  }

  void loadForm({required Function function, required Function onError}) {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show(
            (formError) {
              function();
            },
          );
        } else {
          function();
        }
      },
      (FormError formError) {
        onError();

        throw (formError.message);
      },
    );
  }

  void resetConsent() {
    ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        loadFormAgain();
      }
    }, (error) {
      throw (error.message);
    });
  }

  void loadFormAgain() {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.notRequired || status == ConsentStatus.obtained) {
          consentForm.show(
            (formError) {},
          );
        }
      },
      (FormError formError) {},
    );
  }
}
