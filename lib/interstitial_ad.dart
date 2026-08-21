import 'dart:async' show Completer, TimeoutException, unawaited;
import 'dart:math';

import 'package:flutter/foundation.dart' show kDebugMode, VoidCallback;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/ad_load_gate.dart';
import 'utils.dart';

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
  int? maxFailedLoadAttempts,
}) async => await _InterstitialAdSingleton.instance.init(
  adUnitId: adUnitId,
  minIntervalBetweenAdsInSecs: minIntervalBetweenAdsInSecs,
  createAd: createAd,
  loadingTicks: loadingTicks,
  maxFailedLoadAttempts: maxFailedLoadAttempts,
);

/// Loads an [InterstitialAd]. Stopped after 5s.
Future<void> createInterstitialAd() async =>
    await _InterstitialAdSingleton.instance.createInterstitialAd();

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

void setPersonalizedInterstitialAds(bool value) =>
    _InterstitialAdSingleton.instance._setPersonalizedAds(value);

/// Enables ad loading only after UMP reports that ads may be requested.
void setInterstitialAdsAllowed(bool value) =>
    _InterstitialAdSingleton.instance.setAdsRequestAllowed(value);

class _InterstitialAdSingleton {
  // make this a singleton class
  _InterstitialAdSingleton._();
  static final _InterstitialAdSingleton instance = _InterstitialAdSingleton._();

  AdRequest _request = const AdRequest();
  bool _npa = false;

  void _setPersonalizedAds(bool value) {
    _npa = !value;
    _request = AdRequest(nonPersonalizedAds: _npa);
  }

  InterstitialAd? _interstitialAd;
  String? _adUnitId;
  int? _minIntervalBetweenAdsInSecs;

  final _loadGate = AdLoadGate();
  bool _isLoading = false;
  bool _isReady = false;
  bool _reloadAfterCurrentLoad = false;
  Completer<void>? _activeLoadCompleter;

  int _loadingTicks = 25;
  int _maxFailedLoadAttempts = 2;
  int _loadAttempts = 0;

  DateTime? _lastAdDismissTime;

  void disable() {
    _loadGate.setDisabled(true);
    _activeLoadCompleter?.complete();
    _disposeAdSync(_interstitialAd);
  }

  void enable() => _loadGate.setDisabled(false);

  void setAdsRequestAllowed(bool value) {
    _loadGate.setRequestAllowed(value);
    if (!value) {
      _activeLoadCompleter?.complete();
      _disposeAdSync(_interstitialAd);
    }
  }

  Future<void> init({
    required String adUnitId,
    int? minIntervalBetweenAdsInSecs,
    bool createAd = false,
    int? loadingTicks,
    int? maxFailedLoadAttempts,
  }) async {
    _adUnitId = adUnitId;
    _minIntervalBetweenAdsInSecs = minIntervalBetweenAdsInSecs;
    if (loadingTicks != null) {
      _loadingTicks = loadingTicks;
    }
    if (maxFailedLoadAttempts != null) {
      _maxFailedLoadAttempts = maxFailedLoadAttempts;
    }
    if (createAd) {
      await createInterstitialAd();
    }
  }

  Future<void> createInterstitialAd() async {
    if (!_loadGate.canUseAds) {
      await _disposeAdAsync();
      return;
    }
    if (_adUnitId == null) {
      throw ArgumentError(
        "Missing _adUnitId in _InterstitialAdSingleton. Execute initInterstitialAd()",
      );
    }
    if (_isLoading) {
      _reloadAfterCurrentLoad = true;
      return;
    }
    if (_interstitialAd != null && _isReady) return;

    _isLoading = true;
    _isReady = false;
    _loadAttempts = 0;
    final loadGeneration = _loadGate.generation;

    final maxTotal = Duration(milliseconds: _loadingTicks * 200);
    final sw = Stopwatch()..start();

    while (_loadGate.isCurrent(loadGeneration) &&
        !_isReady &&
        _loadAttempts < _maxFailedLoadAttempts &&
        sw.elapsed < maxTotal) {
      final completer = Completer<void>();
      _activeLoadCompleter = completer;

      InterstitialAd.load(
        adUnitId: _adUnitId!,
        request: _request,
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            if (!_loadGate.isCurrent(loadGeneration)) {
              ad.dispose();
              if (!completer.isCompleted) completer.complete();
              return;
            }
            _infoLog('onAdLoaded');
            _interstitialAd = ad;
            _isReady = true;
            if (!completer.isCompleted) completer.complete();
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (!_loadGate.isCurrent(loadGeneration)) {
              if (!completer.isCompleted) completer.complete();
              return;
            }
            _loadAttempts += 1;
            _errorLog('onAdFailedToLoad (attempt: $_loadAttempts): $error');
            _disposeAdSync(_interstitialAd);
            if (!completer.isCompleted) completer.complete();
          },
        ),
      );

      final remaining = maxTotal - sw.elapsed;
      if (remaining <= Duration.zero) break;
      try {
        await completer.future.timeout(remaining);
      } on TimeoutException {
        break;
      } finally {
        if (identical(_activeLoadCompleter, completer)) {
          _activeLoadCompleter = null;
        }
      }

      if (!_isReady &&
          _loadGate.isCurrent(loadGeneration) &&
          _loadAttempts < _maxFailedLoadAttempts) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    _isLoading = false;

    if (!_loadGate.isCurrent(loadGeneration)) {
      await _disposeAdAsync();
    } else if (_isReady) {
      _infoLog('Ad ready after attempts: $_loadAttempts');
    } else {
      _infoLog('Ad not ready after max attempts: $_maxFailedLoadAttempts');
    }

    if (_reloadAfterCurrentLoad && _loadGate.canUseAds) {
      _reloadAfterCurrentLoad = false;
      unawaited(createInterstitialAd());
    }
  }

  Future<void> showInterstitialAd({
    bool? skip,
    VoidCallback? onAdShowedFullScreenContent,
    VoidCallback? onStartCallback,
    VoidCallback? onEndCallback,
  }) async {
    final c = Completer<void>();
    void start() {
      onStartCallback?.call();
    }

    void end() {
      onEndCallback?.call();
      if (!c.isCompleted) c.complete();
    }

    if (skip == true || !_loadGate.canUseAds) {
      start();
      end();
      if (!_loadGate.canUseAds) await _disposeAdAsync();
      return c.future;
    }

    if (_minIntervalBetweenAdsInSecs != null && _lastAdDismissTime != null) {
      final int secsAfterLastAd = DateTime.now()
          .difference(_lastAdDismissTime!)
          .inSeconds;
      final int effectiveMinInterval = max(_minIntervalBetweenAdsInSecs!, 2);
      if (secsAfterLastAd < effectiveMinInterval) {
        start();
        end();
        if (_interstitialAd == null) createInterstitialAd();
        return c.future;
      }
    }

    if (_interstitialAd == null) {
      _errorLog('attempt to show ad before loaded.');
      start();
      end();
      createInterstitialAd();
      return c.future;
    }

    _interstitialAd
        ?.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdShowedFullScreenContent: (InterstitialAd ad) {
        _infoLog('onAdShowedFullScreenContent');
        onAdShowedFullScreenContent?.call();
        start();
      },
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        _infoLog('onAdDismissedFullScreenContent');
        _lastAdDismissTime = DateTime.now();
        end();
        _disposeAdSync(ad);
        createInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        _errorLog('onAdFailedToShowFullScreenContent: $error');
        _disposeAdSync(ad);
        // intentionally
        start();
        end();
        createInterstitialAd();
      },
    );

    if (_interstitialAd != null) {
      await _interstitialAd!.setImmersiveMode(true);
      _isReady = false;
      await _interstitialAd!.show();
    }
    return c.future;
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
