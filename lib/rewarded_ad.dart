import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

const int _maxFailedLoadAttempts = 3;

/// Must be used once before any [showRewardedAd].
/// Sets [adUnitId] for RewardedAd.
void initRewardedAd({required String adUnitId}) => _RewardedAdSingleton.instance.init(adUnitId: adUnitId);

/// Loads and shows RewardedAd. IMPORTANT: New RewardedAd isn't loaded after closing previous.
/// Loading is stopped after 5s.
///
/// - [onUserEarnedReward] will be invoked when the user earns a reward.
/// - [freeReward] execute onUserEarnedReward without creating and showing RewardedAd
/// - [onFailed] called when ad fails to show full screen content.
Future<void> showRewardedAd({
  required VoidCallback onUserEarnedReward,
  bool? freeReward,
  VoidCallback? onFailed,
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
  String? _adUnitId;
  bool _loaded = false;

  void init({required String adUnitId}) {
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
    required VoidCallback onUserEarnedReward,
    bool? freeReward,
    VoidCallback? onAdFailedToShowFullScreenContent,
  }) async {
    if (freeReward == true) {
      onUserEarnedReward();
      return;
    }

    await _createRewardedAd();

    if (_rewardedAd == null) {
      printR('[DEV-LOG] Warning: attempt to show RewardedAd before loaded.');
      _executeCallback(onAdFailedToShowFullScreenContent);
      return;
    }

    await _rewardedAd!.setImmersiveMode(true);
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdFailedToShowFullScreenContent: (
        RewardedAd ad,
        AdError error,
      ) {
        printR(
          '[DEV-LOG] RewardedAd onAdFailedToShowFullScreenContent: $error',
        );
        ad.dispose();
        _executeCallback(onAdFailedToShowFullScreenContent);
      },
    );

    await _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem __) {
        printR('[DEV-LOG] RewardedAd onUserEarnedReward');
        ad.dispose();
        _loaded = false;
        _rewardedAd = null;
        onUserEarnedReward();
      },
    );
  }

  _executeCallback(VoidCallback? cb) {
    if (cb != null) {
      cb();
    }
  }

  /// Waits for ad loading for up to 5s. Then stops loading.
  Future<void> waitingOnLoad() async {
    int tick = 0;

    await Future.doWhile(
      () => Future.delayed(
        const Duration(milliseconds: 200),
        () {
          tick++;
          if (tick >= 25) {
            printY("[DEV-LOG] RewardedAd loading timed out after after 5s.");
            _rewardedAd?.dispose();
            return;
          }
        },
      ).then((_) => !_loaded && tick < 25),
    );
    if (tick < 25) printY("[DEV-LOG] RewardedAd loaded after ${(tick * 0.2).toStringAsFixed(1)}s");
  }
}
