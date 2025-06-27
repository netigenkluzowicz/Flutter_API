import 'package:flutter/foundation.dart' show VoidCallback, kDebugMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

const int _maxFailedLoadAttempts = 3;

/// Must be used once before any [showRewardedAd].
/// Sets [adUnitId] for RewardedAd.
/// - [loadingTicks] - times 200ms is the maximum ad loading time; default 25 (5 seconds); specifies how many times to check if the ad has been loaded before aborting
void initRewardedAd({required String adUnitId, int? loadingTicks}) =>
    _RewardedAdSingleton.instance.init(adUnitId: adUnitId, loadingTicks: loadingTicks);

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
}) async => await _RewardedAdSingleton.instance.showRewardedAd(
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
  bool _isReady = false;
  int _loadingTicks = 25;

  void init({required String adUnitId, int? loadingTicks}) {
    _adUnitId = adUnitId;
    if (loadingTicks != null) _loadingTicks = loadingTicks;
  }

  bool _isLoading = false;
  Future<void> _createRewardedAd() async {
    if (_adUnitId == null) {
      throw ArgumentError("Missing _adUnitId in _RewardedAdSingleton. Execute _RewardedAdSingleton.instance.init()");
    }
    if (!_isLoading) {
      _isLoading = true;
      try {
        await RewardedAd.load(
          adUnitId: _adUnitId!,
          request: request,
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (RewardedAd ad) {
              _infoLog('onAdLoaded');
              _rewardedAd = ad;
              _loadAttempts = 0;
              _isReady = true;
              _isLoading = false;
            },
            onAdFailedToLoad: (LoadAdError error) async {
              _loadAttempts += 1;
              _errorLog('onAdFailedToLoad(attempt:$_loadAttempts) $error');
              _disposeAd(_rewardedAd);
              if (_loadAttempts < _maxFailedLoadAttempts) {
                await Future.delayed(Duration(milliseconds: 200));
                _isLoading = false;
                _createRewardedAd();
              } else {
                _isLoading = false;
              }
            },
          ),
        );
      } catch (e) {
        _errorLog(e);
      } finally {
        _isLoading = false;
      }
      await _waitForLoad();
    }
  }

  void _disposeAd(Ad? ad) {
    ad?.dispose();
    _rewardedAd = null;
    _isReady = false;
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

    if (_rewardedAd == null) await _createRewardedAd();
    _loadAttempts = 0;

    if (_rewardedAd == null) {
      _errorLog('attempt to show RewardedAd before loaded.');
      _executeCallback(onAdFailedToShowFullScreenContent);
      return;
    }

    await _rewardedAd!.setImmersiveMode(true);

    _rewardedAd?.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        _errorLog('onAdFailedToShowFullScreenContent: $error');
        _disposeAd(ad);
        _executeCallback(onAdFailedToShowFullScreenContent);
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        _disposeAd(ad);
      },
    );

    if (_rewardedAd != null) {
      _rewardedAd!.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem _) {
          onUserEarnedReward();
          _infoLog('onUserEarnedReward');
        },
      );
    }
  }

  void _executeCallback(VoidCallback? cb) {
    if (cb != null) {
      cb();
    }
  }

  bool _waitingForLoad = false;

  /// Waits for ad loading for up to 5s. Then stops loading.
  Future<void> _waitForLoad() async {
    if (!_waitingForLoad) {
      _waitingForLoad = true;
      const tickInterval = Duration(milliseconds: 200);
      var tick = 0;

      while (!_isReady && tick < _loadingTicks) {
        await Future.delayed(tickInterval);
        tick++;
      }

      final waitedSeconds = (tick * 0.2).toStringAsFixed(1);

      if (_isReady) {
        _infoLog('loaded after ${waitedSeconds}s');
      } else {
        _infoLog(
          'loading timed out after '
          '${(_loadingTicks * 0.2).toStringAsFixed(1)}s.',
        );
      }
      _waitingForLoad = false;
    }
  }
}

void _infoLog(Object? object) {
  if (!kDebugMode) return;
  printY("[RewardedAd] $object");
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR("[RewardedAd] ⚠️ ERROR $object");
}
