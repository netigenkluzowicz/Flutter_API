import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdUnits {
  //TODO: update production ids
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';

  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';

  static const String _testRewardedAdAndroid =
      'ca-app-pub-3940256099942544/5224354917';

  static const String _testRewardedAdIos =
      'ca-app-pub-3940256099942544/5224354917';

  static const String _testBannerAdAndroid =
      'ca-app-pub-3940256099942544/6300978111';

  static const String _testBannerAdIos =
      'ca-app-pub-3940256099942544/2934735716';

  static String get interstitialAd {
    if (Platform.isAndroid) {
      return _testInterstitialAndroid;
    } else if (Platform.isIOS) {
      return _testInterstitialIos;
    }

    return "";
  }

  static String get rewardedAd {
    if (Platform.isAndroid) {
      return _testRewardedAdAndroid;
    } else if (Platform.isIOS) {
      return _testRewardedAdIos;
    }
    return "";
  }

  static String get bannerAd {
    if (Platform.isAndroid) {
      return _testBannerAdAndroid;
    } else if (Platform.isIOS) {
      return _testBannerAdIos;
    }

    return "";
  }

  static final BannerAdListener bannerAdListener = BannerAdListener(
    onAdLoaded: (ad) => print(
      'Ad loaded',
    ),
    onAdFailedToLoad: (ad, error) {
      ad.dispose();
      print('Ad failed to load: $error');
    },
    onAdOpened: (ad) => print('Ad opened'),
    onAdClosed: (ad) => print('Ad closed'),
  );
}
