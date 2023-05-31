import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'utils.dart';

const int _maxFailedLoadAttempts = 3;

Future<void> initInterstitialAd({
  required String adUnitId,
  int? minIntervalBetweenAdsInSecs,
  bool createAd = false,
}) async =>
    await _InterstitialAdSingleton.instance.init(
      adUnitId: adUnitId,
      minIntervalBetweenAdsInSecs: minIntervalBetweenAdsInSecs,
      createAd: createAd,
    );

Future<void> createInterstitialAd() async =>
    await _InterstitialAdSingleton.instance.createInterstitialAd();

/// **onStartCallback**:
/// - [FullScreenContentCallback.onAdShowedFullScreenContent]
///
/// **onEndCallback**:
/// - [FullScreenContentCallback.onAdDismissedFullScreenContent]
///
/// **onStartCallback** and then **onEndCallback** when:
/// - [skip] == true (ex. user is premium)
/// - ad is not loaded
/// - last ad was before [_InterstitialAdSingleton._minIntervalBetweenAdsInSecs]
/// - ad is not loaded
/// - [FullScreenContentCallback.onAdFailedToShowFullScreenContent]
Future<void> showInterstitialAd({
  bool? skip,
  Future<void> Function()? onAdShowedFullScreenContent,
  Future<void> Function()? onStartCallback,
  Future<void> Function()? onEndCallback,
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
void enableInterstitialAd() async =>
    _InterstitialAdSingleton.instance.enable();

/// Disables:
/// - createInterstitialAd 
/// - showInterstitialAd
void disableInterstitialAd() async =>
    _InterstitialAdSingleton.instance.disable();

class _InterstitialAdSingleton {
  // make this a singleton class
  _InterstitialAdSingleton._();
  static final _InterstitialAdSingleton instance = _InterstitialAdSingleton._();

  static const AdRequest request = AdRequest();

  InterstitialAd? _interstitialAd;
  int _loadAttempts = 0;
  bool _callbackRunning = false;
  DateTime? _lastAdDismissTime;
  String? _adUnitId;
  int? _minIntervalBetweenAdsInSecs;
  bool _loaded = false;
  bool _disabled = false;

  void disable() => _disabled = true;
  void enable() => _disabled = false;

  Future<void> init({
    required String adUnitId,
    int? minIntervalBetweenAdsInSecs,
    bool createAd = false,
  }) async {
    _adUnitId = adUnitId;
    _minIntervalBetweenAdsInSecs = minIntervalBetweenAdsInSecs;
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
    Future<void> Function()? onAdShowedFullScreenContent,
    Future<void> Function()? onStartCallback,
    Future<void> Function()? onEndCallback,
  }) async {
    if (skip == true || _disabled) {
      if (_disabled) _disposeAd();
      await _executeCallback(onStartCallback);
      await _executeCallback(onEndCallback);
      return;
    }

    final int secsAfterLastAd = _lastAdDismissTime != null
        ? DateTime.now().difference(_lastAdDismissTime!).inSeconds
        : 0;
    if (_minIntervalBetweenAdsInSecs != null &&
        secsAfterLastAd < _minIntervalBetweenAdsInSecs! &&
        secsAfterLastAd != 0) {
      if (_interstitialAd == null) createInterstitialAd();

      await _executeCallback(onStartCallback);
      await _executeCallback(onEndCallback);
      return;
    }

    if (_interstitialAd == null) {
      printR('[DEV-LOG] Warning: attempt to show interstitial before loaded.');
      await _executeCallback(onStartCallback);
      await _executeCallback(onEndCallback);
      createInterstitialAd();
      return;
    }

    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (InterstitialAd ad) async {
        printR('[DEV-LOG] InterstitialAd onAdShowedFullScreenContent');
        await _executeCallback(onAdShowedFullScreenContent);
        await _executeCallback(onStartCallback);
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) async {
        printR('[DEV-LOG] InterstitialAd onAdDismissedFullScreenContent');
        _lastAdDismissTime = DateTime.now();
        await _executeCallback(onEndCallback);
        ad.dispose();
        _loaded = false;
        _interstitialAd = null;
        createInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (
        InterstitialAd ad,
        AdError error,
      ) async {
        printR(
          '[DEV-LOG] InterstitialAd onAdFailedToShowFullScreenContent: $error',
        );
        ad.dispose();
        _loaded = false;
        await _executeCallback(onStartCallback);
        await _executeCallback(onEndCallback);
        createInterstitialAd();
      },
    );
    await _interstitialAd!.setImmersiveMode(true);
    await _interstitialAd!.show();
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
            _interstitialAd?.dispose();
            return;
          }
        },
      ).then((_) => (!_loaded && tick < 25) || _disabled),
    );
  }

  Future<void> _disposeAd() async {
    await _interstitialAd?.dispose();
    _loaded = false;
    _interstitialAd = null;
  }
}
