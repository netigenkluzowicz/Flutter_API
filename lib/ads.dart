import 'package:google_mobile_ads/google_mobile_ads.dart';

class Ads {
  static BannerAd createBannerAd({
    required AdSize size,
    required String adUnitId,
    required BannerAdListener listener,
  }) {
    return BannerAd(
      size: size,
      adUnitId: adUnitId,
      listener: listener,
      request: const AdRequest(),
    );
  }

  static void createInterstitialAd({
    required String adUnitId,
    required InterstitialAdLoadCallback adLoadCallBack,
  }) {
    InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: adLoadCallBack);
  }

  static void createRewardedAd(
      {required String adUnitId,
      required RewardedAdLoadCallback rewardedAdLoadCallback}) {
    RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: rewardedAdLoadCallback);
  }
}
