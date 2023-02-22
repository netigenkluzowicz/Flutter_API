import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConsent {
  final params = ConsentRequestParameters();

  Future<void> consentInfo() async {
    ConsentInformation.instance.requestConsentInfoUpdate(params, () async {
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        loadForm();
      }
    }, (error) {
      throw (error.message);
    });
  }

  void loadForm() {
    ConsentForm.loadConsentForm(
      (ConsentForm consentForm) async {
        var status = await ConsentInformation.instance.getConsentStatus();
        if (status == ConsentStatus.required) {
          consentForm.show(
            (formError) {
              loadForm();
            },
          );
        }
      },
      (FormError formError) {
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
