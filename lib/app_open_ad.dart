import 'dart:async' show Completer, unawaited;

import 'package:flutter/foundation.dart' show VoidCallback, kDebugMode;
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/app_open_ad_state.dart';
import 'src/app_open_foreground_policy.dart';
import 'utils.dart';

export 'src/app_open_foreground_policy.dart' show AppOpenSuppression;

/// Outcome of a non-blocking App Open Ad attempt.
enum AppOpenAdShowResult { shown, unavailable, failed }

/// Configures the App Open Ad format and attaches the app lifecycle observer.
///
/// Loading and showing remain blocked until [setAppOpenAdsAllowed] receives
/// true after UMP consent and Mobile Ads initialization.
/// The optional fullscreen callbacks are retained for ads shown automatically
/// when the application returns to the foreground.
///
/// An automatic App Open is shown only for a `resumed` that follows `paused`
/// (a genuine switch back to the app), never while a suppression scope is
/// active (another fullscreen ad, a purchase, the UMP form, or an application
/// scope from [runWithoutAppOpenAd]), and only when at least
/// [minIntervalSinceFullscreenAd] passed since the last fullscreen ad of any
/// format. Zero keeps the historical behaviour.
void initAppOpenAd({
  required String adUnitId,
  AdRequest request = const AdRequest(),
  Duration maxCacheDuration = const Duration(hours: 4),
  Duration minIntervalSinceFullscreenAd = Duration.zero,
  VoidCallback? onAdShowedFullScreenContent,
  VoidCallback? onAdDismissedFullScreenContent,
  VoidCallback? onAdFailedToShowFullScreenContent,
}) => _AppOpenAdSingleton.instance.init(
  adUnitId: adUnitId,
  request: request,
  maxCacheDuration: maxCacheDuration,
  minIntervalSinceFullscreenAd: minIntervalSinceFullscreenAd,
  onAdShowedFullScreenContent: onAdShowedFullScreenContent,
  onAdDismissedFullScreenContent: onAdDismissedFullScreenContent,
  onAdFailedToShowFullScreenContent: onAdFailedToShowFullScreenContent,
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

/// Shows a preloaded App Open Ad and reports whether it was actually shown.
///
/// Unlike [showAppOpenAd], this completes after a shown fullscreen ad is
/// dismissed or fails. If no valid ad is already ready, it starts a preload
/// and completes immediately with [AppOpenAdShowResult.unavailable].
Future<AppOpenAdShowResult> tryShowAppOpenAd() =>
    _AppOpenAdSingleton.instance.tryShow();

/// Enables App Open Ad requests only after UMP reports `canRequestAds`.
void setAppOpenAdsAllowed(bool value) =>
    _AppOpenAdSingleton.instance.setAdsRequestAllowed(value);

/// Disables App Open Ads for premium/no-ads users and disposes cached ads.
void disableAppOpenAd() => _AppOpenAdSingleton.instance.disable();

/// Re-enables App Open Ads after an explicit no-ads disable.
void enableAppOpenAd() => _AppOpenAdSingleton.instance.enable();

/// Skips automatic App Open Ad showing for the next app foreground event.
///
/// Intended for fire-and-forget launches whose return the app cannot observe
/// (system settings, an external browser). The suppression is consumed by the
/// next foreground event or expires after [timeout], so a launch that never
/// produces a `resumed` cannot swallow a later genuine return from background.
/// Prefer [runWithoutAppOpenAd] or [beginAppOpenSuppression] when the
/// operation exposes a completion. Other fullscreen ads, purchases and the UMP
/// privacy form are suppressed by the package itself.
void suppressNextAppOpenOnForeground({
  Duration timeout = AppOpenForegroundPolicy.defaultOneShotTimeout,
}) => _AppOpenAdSingleton.instance.suppressNextForeground(timeout: timeout);

/// Suppresses automatic App Open Ads until [AppOpenSuppression.end] or
/// [timeout], whichever comes first. Nested scopes are allowed.
AppOpenSuppression beginAppOpenSuppression({
  Duration timeout = AppOpenForegroundPolicy.defaultScopeTimeout,
}) => AppOpenForegroundPolicy.instance.beginScope(timeout: timeout);

/// Runs [action] so that no `resumed` emitted during it (or shortly after it)
/// shows an App Open Ad. Use it around a permission request, a share sheet,
/// or any other system UI opened from the app.
Future<T> runWithoutAppOpenAd<T>(
  Future<T> Function() action, {
  Duration timeout = AppOpenForegroundPolicy.defaultScopeTimeout,
}) async {
  final suppression = beginAppOpenSuppression(timeout: timeout);
  try {
    return await action();
  } finally {
    suppression.end();
  }
}

/// Detaches the lifecycle observer and disposes the cached App Open Ad.
void disposeAppOpenAd() => _AppOpenAdSingleton.instance.dispose();

class _AppOpenAdSingleton with WidgetsBindingObserver {
  _AppOpenAdSingleton._();
  static final instance = _AppOpenAdSingleton._();

  AppOpenAdState _state = AppOpenAdState(
    foregroundPolicy: AppOpenForegroundPolicy.instance,
  );
  AppOpenAd? _appOpenAd;
  String? _adUnitId;
  AdRequest _request = const AdRequest();
  VoidCallback? _onLifecycleAdShowedFullScreenContent;
  VoidCallback? _onLifecycleAdDismissedFullScreenContent;
  VoidCallback? _onLifecycleAdFailedToShowFullScreenContent;
  bool _lifecycleAttached = false;
  bool _disabled = false;

  void init({
    required String adUnitId,
    required AdRequest request,
    required Duration maxCacheDuration,
    required Duration minIntervalSinceFullscreenAd,
    required VoidCallback? onAdShowedFullScreenContent,
    required VoidCallback? onAdDismissedFullScreenContent,
    required VoidCallback? onAdFailedToShowFullScreenContent,
  }) {
    _disposeCachedAd();
    // The policy is shared and survives re-initialization so scopes opened
    // by other formats or the application stay valid.
    AppOpenForegroundPolicy.instance.minIntervalSinceFullscreenAd =
        minIntervalSinceFullscreenAd;
    _state = AppOpenAdState(
      maxCacheDuration: maxCacheDuration,
      foregroundPolicy: AppOpenForegroundPolicy.instance,
    );
    _state.setDisabled(_disabled);
    _adUnitId = adUnitId;
    _request = request;
    _onLifecycleAdShowedFullScreenContent = onAdShowedFullScreenContent;
    _onLifecycleAdDismissedFullScreenContent = onAdDismissedFullScreenContent;
    _onLifecycleAdFailedToShowFullScreenContent =
        onAdFailedToShowFullScreenContent;
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

  void suppressNextForeground({required Duration timeout}) =>
      _state.suppressNextForeground(timeout: timeout);

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
    await _show(
      onAdShowedFullScreenContent: onAdShowedFullScreenContent,
      onAdDismissedFullScreenContent: onAdDismissedFullScreenContent,
      onAdFailedToShowFullScreenContent: onAdFailedToShowFullScreenContent,
    );
  }

  Future<AppOpenAdShowResult> tryShow() {
    final completer = Completer<AppOpenAdShowResult>();
    _show(
      onAdShowedFullScreenContent: () {},
      onAdDismissedFullScreenContent: () {
        if (!completer.isCompleted) {
          completer.complete(AppOpenAdShowResult.shown);
        }
      },
      onAdFailedToShowFullScreenContent: () {
        if (!completer.isCompleted) {
          completer.complete(AppOpenAdShowResult.failed);
        }
      },
      onUnavailable: () {
        if (!completer.isCompleted) {
          completer.complete(AppOpenAdShowResult.unavailable);
        }
      },
    );
    return completer.future;
  }

  Future<void> _show({
    VoidCallback? onAdShowedFullScreenContent,
    VoidCallback? onAdDismissedFullScreenContent,
    VoidCallback? onAdFailedToShowFullScreenContent,
    VoidCallback? onUnavailable,
  }) async {
    if (_state.isExpired && _appOpenAd != null) {
      _disposeCachedAd();
    }
    // Captured like in [create] so a re-initialization while this ad is on
    // screen cannot leave the suppression scope of the old state open.
    final state = _state;
    final ad = _appOpenAd;
    if (ad == null || !state.beginShow()) {
      // An optional App Open configuration may intentionally be absent for a
      // launch. Do not turn that into an unhandled asynchronous error.
      if (_adUnitId != null) unawaited(create());
      onUnavailable?.call();
      return;
    }

    _appOpenAd = null;
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdShowedFullScreenContent: (ad) {
        _infoLog('onAdShowedFullScreenContent');
        state.recordShown();
        onAdShowedFullScreenContent?.call();
      },
      onAdDismissedFullScreenContent: (ad) {
        _infoLog('onAdDismissedFullScreenContent');
        state.finishShow();
        ad.dispose();
        onAdDismissedFullScreenContent?.call();
        _preloadIfAllowed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _errorLog('onAdFailedToShowFullScreenContent: $error');
        state.finishShow();
        ad.dispose();
        onAdFailedToShowFullScreenContent?.call();
        _preloadIfAllowed();
      },
    );

    try {
      await ad.show();
    } catch (error) {
      state.finishShow();
      ad.dispose();
      _errorLog('show error: $error');
      onAdFailedToShowFullScreenContent?.call();
      _preloadIfAllowed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _state.markBackgrounded();
      return;
    }
    if (state == AppLifecycleState.resumed && _state.shouldShowOnForeground()) {
      unawaited(
        show(
          onAdShowedFullScreenContent: _onLifecycleAdShowedFullScreenContent,
          onAdDismissedFullScreenContent:
              _onLifecycleAdDismissedFullScreenContent,
          onAdFailedToShowFullScreenContent:
              _onLifecycleAdFailedToShowFullScreenContent,
        ),
      );
    }
  }

  void dispose() {
    if (_lifecycleAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleAttached = false;
    }
    _state.setAdsRequestAllowed(false);
    _disposeCachedAd();
    // The foreground policy is shared with the interstitial, rewarded,
    // payment and consent code, so disposing this format must not clear
    // scopes those own. Call [AppOpenForegroundPolicy.reset] explicitly if a
    // full library teardown is really intended.
    _adUnitId = null;
    _onLifecycleAdShowedFullScreenContent = null;
    _onLifecycleAdDismissedFullScreenContent = null;
    _onLifecycleAdFailedToShowFullScreenContent = null;
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
