import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';


const int _maxFailedLoadAttempts = 3;

void initRewardedAd({
  required String adUnitId,
}) async =>
    _RewardedAdSingleton.instance.init(
      adUnitId: adUnitId,
    );

Future<void> showRewardedAd({
  required Future<void> Function() onUserEarnedReward,
  bool? freeReward,
  Future<void> Function()? onFailed,
}) async =>
    await _RewardedAdSingleton.instance.showRewardedAd(
      onUserEarnedReward: onUserEarnedReward,
      freeReward: freeReward,
      onAdFailedToShowFullScreenContent: onFailed,
    );

class _RewardedAdSingleton {
  // make this a singleton class
  _RewardedAdSingleton._();
  static final _RewardedAdSingleton instance = _RewardedAdSingleton._();

  static const AdRequest request = AdRequest();

  RewardedAd? _rewardedAd;
  int _loadAttempts = 0;
  bool _callbackRunning = false;
  String? _adUnitId;
  bool _loaded = false;

  void init({
    required String adUnitId,
  }) async {
    _adUnitId = adUnitId;
  }

  Future<void> _createRewardedAd() async {
    if (_adUnitId == null) {
      throw ArgumentError(
        "[DEV-LOG] Missing _adUnitId in _RewardedAdSingleton. Execute _RewardedAdSingleton.instance.init()",
      );
    }
    await RewardedAd.load(
      adUnitId: _adUnitId!,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          printR('[DEV-LOG] RewardedAd onAdLoaded');
          _rewardedAd = ad;
          _loadAttempts = 0;
          _loaded = true;
        },
        onAdFailedToLoad: (LoadAdError error) async {
          printR('[DEV-LOG] RewardedAd onAdFailedToLoad: $error.');
          _loadAttempts += 1;
          _rewardedAd = null;
          _loaded = false;
          if (_loadAttempts < _maxFailedLoadAttempts) {
            await _createRewardedAd();
          }
        },
      ),
    );
    await waitingOnLoad();
  }

  Future<void> showRewardedAd({
    required Future<void> Function() onUserEarnedReward,
    bool? freeReward,
    Future<void> Function()? onAdFailedToShowFullScreenContent,
  }) async {
    if (freeReward == true) {
      await onUserEarnedReward();
      return;
    }

    await _createRewardedAd();

    if (_rewardedAd == null) {
      printR('[DEV-LOG] Warning: attempt to show interstitial before loaded.');
      await _executeCallback(onAdFailedToShowFullScreenContent);
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdFailedToShowFullScreenContent: (
        RewardedAd ad,
        AdError error,
      ) async {
        printR(
          '[DEV-LOG] RewardedAd onAdFailedToShowFullScreenContent: $error',
        );
        ad.dispose();
        await _executeCallback(onAdFailedToShowFullScreenContent);
      },
    );

    await _rewardedAd!.setImmersiveMode(true);
    await _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem __) async {
        printR('[DEV-LOG] RewardedAd onUserEarnedReward');
        ad.dispose();
        _loaded = false;
        _rewardedAd = null;
        await onUserEarnedReward();
      },
    );
  }

  _executeCallback(Future<void> Function()? cb) async {
    final hasCb = cb != null;
    if (hasCb && !_callbackRunning) {
      _callbackRunning = true;
      await cb();
      _callbackRunning = false;
    }
  }

  Future<void> waitingOnLoad() async {
    int tick = 0;

    await Future.doWhile(
      () => Future.delayed(
        const Duration(milliseconds: 200),
        () {
          tick++;
          printY(
            "[DEV-LOG] loading of ad step ${(tick * 0.2).toStringAsFixed(1)}s",
          );
          if (tick >= 25) {
            printY("[DEV-LOG] fullscreen ad disposed after 5s");
            _rewardedAd?.dispose();
            return;
          }
        },
      ).then((_) => !_loaded && tick < 25),
    );
  }
}
