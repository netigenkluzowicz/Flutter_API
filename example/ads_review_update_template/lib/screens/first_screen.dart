import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:in_app_update/in_app_update.dart';

import '../helpers/ad_units.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});
  @override
  State<FirstScreen> createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen> {
  int _coins = 0;
  BannerAd? _banner;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  InAppReview inAppReview = InAppReview.instance;

  void createBannerAd() {
    _banner = BannerAd(
      size: AdSize
          .fullBanner, //Use AdSize.getAnchoredAdaptiveBannerAdSize(orientation, width) instead of hardcoded dimensions
      adUnitId: AdUnits.bannerAd,
      listener: AdUnits.bannerAdListener,
      request: const AdRequest(),
    )..load();
  }

  void createInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdUnits.interstitialAd,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  void createRewardedAd() {
    RewardedAd.load(
      adUnitId: AdUnits.rewardedAd,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (error) => _rewardedAd = null,
      ),
    );
  }

  void showRewardedAd() {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          createRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          createRewardedAd();
        },
      );
      _rewardedAd!.show(
        //give user what he earn by watching rewarded ad
        onUserEarnedReward: (ad, reward) => setState(() {
          _coins = _coins + 1;
        }),
      );
      _rewardedAd = null;
    }
  }

  void checkIfReviewAvaliable() async {
    //this will call request to google api, for bttom sheet in app review, this will not allways apear.
    //google decides when this will work
    if (await inAppReview.isAvailable()) {
      inAppReview.requestReview();
    }
  }

  void inAppCheckUpdate() async {
    //Here you have different methods to show updates in app
    //more info here: https://pub.dev/packages/in_app_update

    // InAppUpdate.checkForUpdate();
    InAppUpdate.performImmediateUpdate();
    // InAppUpdate.startFlexibleUpdate();
    // InAppUpdate.completeFlexibleUpdate();
  }

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    //you should load ads in initstate of widget
    inAppCheckUpdate();
    createBannerAd();
    createInterstitialAd();
    createRewardedAd();
    checkIfReviewAvaliable();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Test ads!'),
              const Text(
                  'Here\'s how many coins you got for your rewarded ad:'),
              Text(
                _coins.toString(),
                style:
                    const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      if (_interstitialAd != null) {
                        _interstitialAd!.fullScreenContentCallback =
                            FullScreenContentCallback(
                          onAdDismissedFullScreenContent: (ad) {
                            ad.dispose();
                            createInterstitialAd();
                            //Do something after watching an ad
                          },
                          onAdShowedFullScreenContent: (ad) {
                            ad.dispose();
                            createInterstitialAd();
                            //Do something ad is shown
                          },
                          onAdFailedToShowFullScreenContent: (ad, error) {
                            ad.dispose();
                            createInterstitialAd();
                            //do something on failed to show ad
                          },
                        );
                        _interstitialAd!.show();
                        _interstitialAd = null;
                      } else {
                        //do something when variable with ad is null
                      }
                    },
                    child: const Text('Interstitial ad'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      showRewardedAd();
                    },
                    child: const Text('Rewarded ad'),
                  ),
                ],
              ),
              ElevatedButton(
                  onPressed: () {
                    //this will open (this app page) google play store / app store
                    inAppReview.openStoreListing();
                  },
                  child: const Text('Rate this app'))
            ],
          ),
        ),
        bottomNavigationBar: _banner != null
            ? SizedBox(
                height: 52,
                child: AdWidget(ad: _banner!),
              )
            : null);
  }
}
