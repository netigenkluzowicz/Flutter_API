import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobConsent {
  final params = ConsentRequestParameters();

  //you can use this function e.g. at splashscreen stage, this will check if form is avaliable,
  Future<void> consentInfo({Function? showAd}) async {
    ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        loadForm(showAd: showAd);
      }
    }, (error) {
      print(error.message);
    });
  }

  //load form and check if form is needed, then show it
  void loadForm({Function? showAd}) {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show(
            (formError) {
              if (showAd != null) {
                showAd();
              }
              loadForm();
            },
          );
        } else {
          if (showAd != null) {
            showAd();
          }
        }
      },
      (FormError formError) {
        print(formError.message);
      },
    );
  }

  //reset consent
  void resetConsent() {
    ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        loadFormAgain();
      }
    }, (error) {
      print(error.message);
    });
  }

  //load form to reset users choices
  void loadFormAgain() {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.notRequired ||
            status == ConsentStatus.obtained) {
          consentForm.show(
            (formError) {},
          );
        }
      },
      (FormError formError) {},
    );
  }
}
