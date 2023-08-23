import 'package:flutter/rendering.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

const int _maxFailedLoadAttempts = 3;

/// Must be used once before any [createInterstitialAd] or [showInterstitialAd].
/// - [adUnitId] - sets adUnitId for all [InterstitialAd] requests
/// - [minIntervalBetweenAdsInSecs] - sets minimal time interval between [InterstitialAd] requests, requests before this interval will be skipped
/// - [createAd] - loads [InterstitialAd]
/// - [loadingTicks] - times 200ms is the maximum ad loading time; default 25 (5 seconds); specifies how many times to check if the ad has been loaded before aborting
Future<void> initInterstitialAd({
  required String adUnitId,
  int? minIntervalBetweenAdsInSecs,
  bool createAd = false,
  int? loadingTicks,
}) async =>
    await _InterstitialAdSingleton.instance.init(
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
}) async =>
    await _InterstitialAdSingleton.instance.showInterstitialAd(
      skip: skip,
      onAdShowedFullScreenContent: onAdShowedFullScreenContent,
      onStartCallback: onStartCallback,
      onEndCallback: onEndCallback,
    );

/// Enables:
/// - createInterstitialAd
/// - showInterstitialAd
/// until [disableInterstitialAd]
void enableInterstitialAd() async => _InterstitialAdSingleton.instance.enable();

/// Disables:
/// - createInterstitialAd
/// - showInterstitialAd
///
/// until [enableInterstitialAd]
void disableInterstitialAd() async => _InterstitialAdSingleton.instance.disable();

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
  bool _loaded = false;
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
    } else {
      return Future.value();
    }
  }

  Future<void> createInterstitialAd() async {
    if (_disabled) {
      _disposeAd();
      return;
    }
    if (_adUnitId == null) {
      throw ArgumentError(
        "[DEV-LOG] Missing _adUnitId in InterstitialAdSingleton. Execute InterstitialAdSingleton.instance.init()",
      );
    }

    await InterstitialAd.load(
      adUnitId: _adUnitId!,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          printR('[DEV-LOG] InterstitialAd onAdLoaded');
          _interstitialAd = ad;
          _loadAttempts = 0;
          _loaded = true;
        },
        onAdFailedToLoad: (LoadAdError error) async {
          printR('[DEV-LOG] InterstitialAd onAdFailedToLoad: $error.');
          _loadAttempts += 1;
          _interstitialAd = null;
          _loaded = false;
          if (_loadAttempts < _maxFailedLoadAttempts) {
            await createInterstitialAd();
          }
        },
      ),
    );
    await waitingOnLoad();
    if (_disabled) _disposeAd();
  }

  Future<void> showInterstitialAd({
    bool? skip,
    VoidCallback? onAdShowedFullScreenContent,
    VoidCallback? onStartCallback,
    VoidCallback? onEndCallback,
  }) async {
    if (skip == true || _disabled) {
      if (_disabled) _disposeAd();
      _executeCallback(onStartCallback);
      _executeCallback(onEndCallback);
      return;
    }

    final int secsAfterLastAd =
        _lastAdDismissTime != null ? DateTime.now().difference(_lastAdDismissTime!).inSeconds : 0;
    if (_minIntervalBetweenAdsInSecs != null &&
        secsAfterLastAd < _minIntervalBetweenAdsInSecs! &&
        secsAfterLastAd != 0) {
      if (_interstitialAd == null) createInterstitialAd();

      _executeCallback(onStartCallback);
      _executeCallback(onEndCallback);
      return;
    }

    if (_interstitialAd == null) {
      printR('[DEV-LOG] Warning: attempt to show interstitial before loaded.');
      _executeCallback(onStartCallback);
      _executeCallback(onEndCallback);
      createInterstitialAd();
      return;
    }

    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        printR('[DEV-LOG] InterstitialAd onAdShowedFullScreenContent');
        _executeCallback(onAdShowedFullScreenContent);
        _executeCallback(onStartCallback);
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        printR('[DEV-LOG] InterstitialAd onAdDismissedFullScreenContent');
        _lastAdDismissTime = DateTime.now();
        _executeCallback(onEndCallback);
        ad.dispose();
        _loaded = false;
        _interstitialAd = null;
        createInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (
        InterstitialAd ad,
        AdError error,
      ) {
        printR(
          '[DEV-LOG] InterstitialAd onAdFailedToShowFullScreenContent: $error',
        );
        ad.dispose();
        _loaded = false;
        _executeCallback(onStartCallback);
        _executeCallback(onEndCallback);
        createInterstitialAd();
      },
    );
    await _interstitialAd?.setImmersiveMode(true);
    await _interstitialAd?.show();
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
          if (tick >= _loadingTicks) {
            printY("[DEV-LOG] InterstitialAd loading timed out after ${(_loadingTicks * 0.2).toStringAsFixed(1)}s.");
            _interstitialAd?.dispose();
            return;
          }
        },
      ).then((_) => (!_loaded && tick < _loadingTicks) || _disabled),
    );
    if (tick < _loadingTicks) printY("[DEV-LOG] InterstitialAd loaded after ${(tick * 0.2).toStringAsFixed(1)}s");
  }

  Future<void> _disposeAd() async {
    await _interstitialAd?.dispose();
    _loaded = false;
    _interstitialAd = null;
  }
}
