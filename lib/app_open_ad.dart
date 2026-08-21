import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show VoidCallback, kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/app_open_ad_state.dart';
import 'utils.dart';

/// Configures the App Open Ad format and attaches the app lifecycle observer.
///
/// Loading and showing remain blocked until [setAppOpenAdsAllowed] receives
/// true after UMP consent and Mobile Ads initialization.
void initAppOpenAd({
  required String adUnitId,
  AdRequest request = const AdRequest(),
  Duration maxCacheDuration = const Duration(hours: 4),
}) => _AppOpenAdSingleton.instance.init(
  adUnitId: adUnitId,
  request: request,
  maxCacheDuration: maxCacheDuration,
);

/// Preloads an App Open Ad when consent and no-ads state allow it.
Future<void> createAppOpenAd() => _AppOpenAdSingleton.instance.create();

/// Shows the preloaded App Open Ad, if one is currently valid.
///
/// When the ad is unavailable or expired this method only starts a preload;
/// it never delays application startup waiting for an ad response.
Future<void> showAppOpenAd({
  VoidCallback? onAdShowedFullScreenContent,
  VoidCallback? onAdDismissedFullScreenContent,
  VoidCallback? onAdFailedToShowFullScreenContent,
}) => _AppOpenAdSingleton.instance.show(
  onAdShowedFullScreenContent: onAdShowedFullScreenContent,
  onAdDismissedFullScreenContent: onAdDismissedFullScreenContent,
  onAdFailedToShowFullScreenContent: onAdFailedToShowFullScreenContent,
);

/// Enables App Open Ad requests only after UMP reports `canRequestAds`.
void setAppOpenAdsAllowed(bool value) =>
    _AppOpenAdSingleton.instance.setAdsRequestAllowed(value);

/// Disables App Open Ads for premium/no-ads users and disposes cached ads.
void disableAppOpenAd() => _AppOpenAdSingleton.instance.disable();

/// Re-enables App Open Ads after an explicit no-ads disable.
void enableAppOpenAd() => _AppOpenAdSingleton.instance.enable();

/// Detaches the lifecycle observer and disposes the cached App Open Ad.
void disposeAppOpenAd() => _AppOpenAdSingleton.instance.dispose();

class _AppOpenAdSingleton with WidgetsBindingObserver {
  _AppOpenAdSingleton._();
  static final instance = _AppOpenAdSingleton._();

  AppOpenAdState _state = AppOpenAdState();
  AppOpenAd? _appOpenAd;
  String? _adUnitId;
  AdRequest _request = const AdRequest();
  bool _lifecycleAttached = false;
  bool _disabled = false;

  void init({
    required String adUnitId,
    required AdRequest request,
    required Duration maxCacheDuration,
  }) {
    _disposeCachedAd();
    _state = AppOpenAdState(maxCacheDuration: maxCacheDuration);
    _state.setDisabled(_disabled);
    _adUnitId = adUnitId;
    _request = request;
    if (!_lifecycleAttached) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleAttached = true;
    }
  }

  void setAdsRequestAllowed(bool value) {
    _state.setAdsRequestAllowed(value);
    if (!value) _disposeCachedAd();
  }

  void disable() {
    _disabled = true;
    _state.setDisabled(true);
    _disposeCachedAd();
  }

  void enable() {
    _disabled = false;
    _state.setDisabled(false);
  }

  Future<void> create() async {
    if (_state.isExpired && _appOpenAd != null) {
      _disposeCachedAd();
    }
    final state = _state;
    final loadGeneration = state.beginLoad();
    if (loadGeneration == null) return;
    final adUnitId = _adUnitId;
    if (adUnitId == null) {
      state.failLoad(loadGeneration);
      throw ArgumentError('Missing App Open Ad unit ID. Call initAppOpenAd().');
    }

    try {
      await AppOpenAd.load(
        adUnitId: adUnitId,
        request: _request,
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (ad) {
            if (!identical(state, _state) ||
                !state.completeLoad(loadGeneration)) {
              ad.dispose();
              return;
            }
            _appOpenAd = ad;
            _infoLog('onAdLoaded');
          },
          onAdFailedToLoad: (error) {
            state.failLoad(loadGeneration);
            _errorLog('onAdFailedToLoad: $error');
          },
        ),
      );
    } catch (error) {
      state.failLoad(loadGeneration);
      _errorLog('load error: $error');
    }
  }

  Future<void> show({
    VoidCallback? onAdShowedFullScreenContent,
    VoidCallback? onAdDismissedFullScreenContent,
    VoidCallback? onAdFailedToShowFullScreenContent,
  }) async {
    if (_state.isExpired && _appOpenAd != null) {
      _disposeCachedAd();
    }
    final ad = _appOpenAd;
    if (ad == null || !_state.beginShow()) {
      unawaited(create());
      return;
    }

    _appOpenAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (ad) {
        _infoLog('onAdShowedFullScreenContent');
        onAdShowedFullScreenContent?.call();
      },
      onAdDismissedFullScreenContent: (ad) {
        _infoLog('onAdDismissedFullScreenContent');
        _state.finishShow();
        ad.dispose();
        onAdDismissedFullScreenContent?.call();
        _preloadIfAllowed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _errorLog('onAdFailedToShowFullScreenContent: $error');
        _state.finishShow();
        ad.dispose();
        onAdFailedToShowFullScreenContent?.call();
        _preloadIfAllowed();
      },
    );

    try {
      await ad.show();
    } catch (error) {
      _state.finishShow();
      ad.dispose();
      _errorLog('show error: $error');
      onAdFailedToShowFullScreenContent?.call();
      _preloadIfAllowed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _state.shouldShowOnForeground()) {
      unawaited(show());
    }
  }

  void dispose() {
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
    _state.setAdsRequestAllowed(false);
    _disposeCachedAd();
    _adUnitId = null;
  }

  void _preloadIfAllowed() {
    if (_state.canUseAds) unawaited(create());
  }

  void _disposeCachedAd() {
    _appOpenAd?.dispose();
    _appOpenAd = null;
    _state.clearLoadedAd();
  }
}

void _infoLog(Object? object) {
  if (!kDebugMode) return;
  printY('[AppOpenAd] $object');
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR('[AppOpenAd] ⚠️ ERROR $object');
}
