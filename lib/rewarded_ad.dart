import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show VoidCallback, kDebugMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/ad_load_gate.dart';
import 'utils.dart';

/// Must be used once before any [showRewardedAd].
/// Sets [adUnitId] for RewardedAd.
/// - [loadingTicks] - times 200ms is the maximum ad loading time; default 25 (5 seconds); specifies how many times to check if the ad has been loaded before aborting
void initRewardedAd({
  required String adUnitId,
  int? loadingTicks,
  int? maxFailedLoadAttempts,
}) => _RewardedAdSingleton.instance.init(
  adUnitId: adUnitId,
  loadingTicks: loadingTicks,
  maxFailedLoadAttempts: maxFailedLoadAttempts,
);

/// Loads and shows a RewardedAd.
/// Loading is stopped after 5s.
///
/// - [onUserEarnedReward] will be invoked when the user earns a reward.
/// - [freeReward] execute onUserEarnedReward without creating and showing RewardedAd
/// - [onFailed] called when ad fails to show full screen content.
/// - [onDismissedWithoutReward] is called when the user closes the ad without
///   earning a reward.
Future<void> showRewardedAd({
  required VoidCallback onUserEarnedReward,
  bool? freeReward,
  VoidCallback? onFailed,
  VoidCallback? onDismissedWithoutReward,
}) async => await _RewardedAdSingleton.instance.showRewardedAd(
  onUserEarnedReward: onUserEarnedReward,
  freeReward: freeReward,
  onAdFailedToShowFullScreenContent: onFailed,
  onDismissedWithoutReward: onDismissedWithoutReward,
);

/// Enables rewarded ads until [disableRewardedAd] is called.
void enableRewardedAd() => _RewardedAdSingleton.instance.enable();

/// Disables rewarded ad loading and showing, and disposes any loaded ad.
void disableRewardedAd() => _RewardedAdSingleton.instance.disable();

void setPersonalizedRewardedAds(bool value) =>
    _RewardedAdSingleton.instance._setPersonalizedAds(value);

/// Enables ad loading only after UMP reports that ads may be requested.
void setRewardedAdsAllowed(bool value) =>
    _RewardedAdSingleton.instance.setAdsRequestAllowed(value);

class _RewardedAdSingleton {
  // make this a singleton class
  _RewardedAdSingleton._();
  static final _RewardedAdSingleton instance = _RewardedAdSingleton._();

  AdRequest _request = const AdRequest();
  bool _npa = false;

  void _setPersonalizedAds(bool value) {
    _npa = !value;
    _request = AdRequest(nonPersonalizedAds: _npa);
  }

  RewardedAd? _rewardedAd;
  int _loadAttempts = 0;
  String? _adUnitId;
  bool _isReady = false;
  final _loadGate = AdLoadGate();
  int _loadingTicks = 25;
  int _maxFailedLoadAttempts = 2;

  void setAdsRequestAllowed(bool value) {
    _loadGate.setRequestAllowed(value);
    if (!value) _disposeAd(_rewardedAd);
  }

  void disable() {
    _loadGate.setDisabled(true);
    _disposeAd(_rewardedAd);
  }

  void enable() => _loadGate.setDisabled(false);

  void init({
    required String adUnitId,
    int? loadingTicks,
    int? maxFailedLoadAttempts,
  }) {
    _adUnitId = adUnitId;
    _maxFailedLoadAttempts = maxFailedLoadAttempts ?? _maxFailedLoadAttempts;
    if (loadingTicks != null) _loadingTicks = loadingTicks;
  }

  bool _isLoading = false;
  Future<void> _createRewardedAd() async {
    if (!_loadGate.canUseAds) return;
    if (_adUnitId == null) {
      throw ArgumentError(
        "Missing _adUnitId in _RewardedAdSingleton. Execute _RewardedAdSingleton.instance.init()",
      );
    }
    if (!_isLoading) {
      _isLoading = true;
      final loadGeneration = _loadGate.generation;
      try {
        await RewardedAd.load(
          adUnitId: _adUnitId!,
          request: _request,
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (RewardedAd ad) {
              if (!_loadGate.isCurrent(loadGeneration)) {
                ad.dispose();
                return;
              }
              _infoLog('onAdLoaded');
              _rewardedAd = ad;
              _loadAttempts = 0;
              _isReady = true;
              _isLoading = false;
            },
            onAdFailedToLoad: (LoadAdError error) async {
              if (!_loadGate.isCurrent(loadGeneration)) return;
              _loadAttempts += 1;
              _errorLog('onAdFailedToLoad(attempt:$_loadAttempts) $error');
              _disposeAd(_rewardedAd);
              if (shouldRetryAdLoad(
                failedAttempts: _loadAttempts,
                maxFailedLoadAttempts: _maxFailedLoadAttempts,
              )) {
                await Future.delayed(const Duration(milliseconds: 200));
                _isLoading = false;
                unawaited(_createRewardedAd());
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
      await _waitForLoad(loadGeneration);
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
    VoidCallback? onDismissedWithoutReward,
  }) async {
    if (freeReward == true) {
      onUserEarnedReward();
      return;
    }

    if (!_loadGate.canUseAds) {
      _executeCallback(onAdFailedToShowFullScreenContent);
      return;
    }

    if (_rewardedAd == null) await _createRewardedAd();
    _loadAttempts = 0;

    if (_rewardedAd == null) {
      _errorLog('attempt to show RewardedAd before loaded.');
      _executeCallback(onAdFailedToShowFullScreenContent);
      return;
    }

    final ad = _rewardedAd!;
    _rewardedAd = null;
    _isReady = false;
    var rewardEarned = false;

    await ad.setImmersiveMode(true);

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        _errorLog('onAdFailedToShowFullScreenContent: $error');
        _disposeAd(ad);
        _executeCallback(onAdFailedToShowFullScreenContent);
        _preloadIfAllowed();
      },
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        _disposeAd(ad);
        if (!rewardEarned) {
          _executeCallback(onDismissedWithoutReward);
        }
        _preloadIfAllowed();
      },
    );

    ad.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem _) {
        rewardEarned = true;
        onUserEarnedReward();
        _infoLog('onUserEarnedReward');
      },
    );
  }

  void _executeCallback(VoidCallback? cb) {
    if (cb != null) {
      cb();
    }
  }

  bool _waitingForLoad = false;

  /// Waits for ad loading for up to 5s. Then stops loading.
  void _preloadIfAllowed() {
    if (_loadGate.canUseAds && _adUnitId != null && !_isLoading) {
      unawaited(_createRewardedAd());
    }
  }

  Future<void> _waitForLoad(int loadGeneration) async {
    if (!_waitingForLoad) {
      _waitingForLoad = true;
      const tickInterval = Duration(milliseconds: 200);
      var tick = 0;

      while (_loadGate.isCurrent(loadGeneration) &&
          !_isReady &&
          tick < _loadingTicks) {
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
