import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, VoidCallback;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

const int _maxFailedLoadAttempts = 3;

/// Must be used once before any [createInterstitialAd] or [showInterstitialAd].
/// - [adUnitId] - sets adUnitId for all [InterstitialAd] requests
/// - [minIntervalBetweenAdsInSecs] - sets minimal time interval between [InterstitialAd] requests, requests before this interval will be skipped, cannot be lower than 2s
/// - [createAd] - loads [InterstitialAd]
/// - [loadingTicks] - times 200ms is the maximum ad loading time; default 25 (5 seconds); specifies how many times to check if the ad has been loaded before aborting
Future<void> initInterstitialAd({
  required String adUnitId,
  int? minIntervalBetweenAdsInSecs,
  bool createAd = false,
  int? loadingTicks,
}) async => await _InterstitialAdSingleton.instance.init(
  adUnitId: adUnitId,
  minIntervalBetweenAdsInSecs: minIntervalBetweenAdsInSecs,
  createAd: createAd,
  loadingTicks: loadingTicks,
);

/// Loads an [InterstitialAd]. Stopped after 5s.
Future<void> createInterstitialAd() async => await _InterstitialAdSingleton.instance.createInterstitialAd();

/// **[skip]**
///
/// Order of callbacks if exucuted on the same event ex. (ad shows full screen content):
///
/// **[onAdShowedFullScreenContent]** called when:
/// - an ad shows full screen content [FullScreenContentCallback.onAdShowedFullScreenContent]
///
/// **[onStartCallback]** called when:
/// - an ad shows full screen content [FullScreenContentCallback.onAdShowedFullScreenContent],
/// - when ad fails to show full screen content [FullScreenContentCallback.onAdFailedToShowFullScreenContent],
/// - [skip] == true (ex. user is premium),
/// - ad is not loaded,
/// - last ad was before [_InterstitialAdSingleton._minIntervalBetweenAdsInSecs],
///
/// **[onEndCallback]** called when:
/// - when an ad dismisses full screen content [FullScreenContentCallback.onAdDismissedFullScreenContent],
/// - [skip] == true (ex. user is premium),
/// - ad is not loaded,
/// - last ad was before [_InterstitialAdSingleton._minIntervalBetweenAdsInSecs],
Future<void> showInterstitialAd({
  bool? skip,
  VoidCallback? onAdShowedFullScreenContent,
  VoidCallback? onStartCallback,
  VoidCallback? onEndCallback,
}) async => await _InterstitialAdSingleton.instance.showInterstitialAd(
  skip: skip,
  onAdShowedFullScreenContent: onAdShowedFullScreenContent,
  onStartCallback: onStartCallback,
  onEndCallback: onEndCallback,
);

/// Enables:
/// - createInterstitialAd
/// - showInterstitialAd
/// until [disableInterstitialAd]
void enableInterstitialAd() => _InterstitialAdSingleton.instance.enable();

/// Disables:
/// - createInterstitialAd
/// - showInterstitialAd
///
/// until [enableInterstitialAd]
void disableInterstitialAd() => _InterstitialAdSingleton.instance.disable();

class _InterstitialAdSingleton {
  // make this a singleton class
  _InterstitialAdSingleton._();
  static final _InterstitialAdSingleton instance = _InterstitialAdSingleton._();

  static const AdRequest request = AdRequest();

  InterstitialAd? _interstitialAd;
  int _loadAttempts = 0;
  DateTime? _lastAdDismissTime;
  String? _adUnitId;
  int? _minIntervalBetweenAdsInSecs;
  bool _isReady = false;
  bool _disabled = false;
  int _loadingTicks = 25;

  void disable() => _disabled = true;
  void enable() => _disabled = false;

  Future<void> init({
    required String adUnitId,
    int? minIntervalBetweenAdsInSecs,
    bool createAd = false,
    int? loadingTicks,
  }) async {
    _adUnitId = adUnitId;
    _minIntervalBetweenAdsInSecs = minIntervalBetweenAdsInSecs;
    if (loadingTicks != null) _loadingTicks = loadingTicks;
    if (createAd == true) {
      await createInterstitialAd();
    }
  }

  bool _isLoading = false;
  Future<void> createInterstitialAd() async {
    if (_disabled) {
      await _disposeAdAsync();
      return;
    }
    if (_adUnitId == null) {
      throw ArgumentError(
        "Missing _adUnitId in InterstitialAdSingleton. Execute InterstitialAdSingleton.instance.init()",
      );
    }
    if (!_isLoading) {
      _isLoading = true;
      try {
        await InterstitialAd.load(
          adUnitId: _adUnitId!,
          request: request,
          adLoadCallback: InterstitialAdLoadCallback(
            onAdLoaded: (InterstitialAd ad) {
              _infoLog('onAdLoaded');
              _interstitialAd = ad;
              _loadAttempts = 0;
              _isReady = true;
              _isLoading = false;
            },
            onAdFailedToLoad: (LoadAdError error) async {
              _loadAttempts += 1;
              _errorLog('onAdFailedToLoad(failed attempt:$_loadAttempts) $error');
              if (_disabled) {
                await _disposeAdAsync();
                _isLoading = false;
                return;
              }
              _disposeAdSync(_interstitialAd);
              if (_loadAttempts < _maxFailedLoadAttempts) {
                await Future.delayed(Duration(milliseconds: 200));
                _isLoading = false;
                createInterstitialAd();
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
    if (_disabled) await _disposeAdAsync();
  }

  Future<void> showInterstitialAd({
    bool? skip,
    VoidCallback? onAdShowedFullScreenContent,
    VoidCallback? onStartCallback,
    VoidCallback? onEndCallback,
  }) async {
    if (skip == true || _disabled) {
      _executeCallback(onStartCallback);
      _executeCallback(onEndCallback);
      if (_disabled) await _disposeAdAsync();
      return;
    }

    if (_minIntervalBetweenAdsInSecs != null && _lastAdDismissTime != null) {
      final int secsAfterLastAd = DateTime.now().difference(_lastAdDismissTime!).inSeconds;
      final int effectiveMinInterval = max(_minIntervalBetweenAdsInSecs!, 2);
      if (secsAfterLastAd < effectiveMinInterval) {
        _executeCallback(onStartCallback);
        _executeCallback(onEndCallback);
        if (_interstitialAd == null) createInterstitialAd();
        return;
      }
    }

    if (_interstitialAd == null) {
      _errorLog('attempt to show ad before loaded.');
      _executeCallback(onStartCallback);
      _executeCallback(onEndCallback);
      createInterstitialAd();
      return;
    }

    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        _infoLog('onAdShowedFullScreenContent');
        _executeCallback(onAdShowedFullScreenContent);
        _executeCallback(onStartCallback);
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        _infoLog('onAdDismissedFullScreenContent');
        _lastAdDismissTime = DateTime.now();
        _executeCallback(onEndCallback);
        _disposeAdSync(ad);
        createInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        _errorLog('onAdFailedToShowFullScreenContent: $error');
        _disposeAdSync(ad);
        // intentionally
        _executeCallback(onStartCallback);
        _executeCallback(onEndCallback);
        createInterstitialAd();
      },
    );

    if (_interstitialAd != null) {
      await _interstitialAd!.setImmersiveMode(true);
      await _interstitialAd!.show();
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

      while (!_isReady && !_disabled && tick < _loadingTicks) {
        await Future.delayed(tickInterval);
        tick++;
      }

      final waitedSeconds = (tick * 0.2).toStringAsFixed(1);

      if (_isReady) {
        _infoLog('loaded after ${waitedSeconds}s (failed attempts:$_loadAttempts)');
      } else {
        _infoLog(
          'loading timed out after '
          '${(_loadingTicks * 0.2).toStringAsFixed(1)}s (failed attempts:$_loadAttempts)',
        );
      }
      _waitingForLoad = false;
    }
  }

  Future<void> _disposeAdAsync() async {
    await _interstitialAd?.dispose();
    _isReady = false;
    _interstitialAd = null;
  }

  void _disposeAdSync(Ad? ad) {
    ad?.dispose();
    _isReady = false;
    _interstitialAd = null;
  }
}

void _infoLog(Object? object) {
  if (!kDebugMode) return;
  printY("[InterstitialAd] $object");
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR("[InterstitialAd] ⚠️ ERROR $object");
}
