import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../screens/first_screen.dart';
import '../providers/payment_provider.dart';
import '../helpers/ad_mob_consent.dart';
import '../helpers/ad_mob_service.dart';

class FakeSplashscreen extends StatefulWidget {
  const FakeSplashscreen({super.key});

  @override
  State<FakeSplashscreen> createState() => _FakeSplashscreenState();
}

class _FakeSplashscreenState extends State<FakeSplashscreen> {
  InterstitialAd? _interstitialAd;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    //start loading ad into memmory
    _createInterstitialAd();
    //initialize payments (find out if user is premium / have bought some items)
    Provider.of<PaymentProvider>(context, listen: false).initialize();
    //unfortunetly I am waiting here for 3 sec for purchase listener actions, feel free to improve this element!
    Future.delayed(Duration(seconds: 3), () {
      //show initial consent and fullscreen ad
      _showConsent();
    });
  }

  void _showConsent() {
    if (Provider.of<PaymentProvider>(context, listen: false).isPremium) {
      //if user is premium skip showing consent and ad
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => FirstScreen(),
      ));
    } else {
      //show consent then ad
      AdMobConsent().consentInfo(showAd: showInitialAd);
    }
  }

  void showInitialAd() {
    if (_interstitialAd != null) {
      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => FirstScreen(),
          ));
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          Navigator.pop(context);
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => FirstScreen(),
          ));
        },
      );
      _interstitialAd!.show();
    }
  }

  //
  void _createInterstitialAd() {
    InterstitialAd.load(
        adUnitId: AdMobService.interstitialAdUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) => _interstitialAd = ad,
          onAdFailedToLoad: (error) => _interstitialAd = null,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              //make splash screen look cooler, we can do it bcs of using widget instead of NativeSplashScreen
              LottieBuilder.network(
                  'https://assets3.lottiefiles.com/packages/lf20_rWaqBk.json'),
              const Text('Fake Splash'),
              const SizedBox(),
            ],
          ),
        ),
      ),
    );
  }
}
