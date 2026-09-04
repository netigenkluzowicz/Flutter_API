import 'ad_load_gate.dart';
import 'app_open_foreground_policy.dart';

/// State machine shared by the App Open Ad lifecycle and its unit tests.
///
/// It deliberately has no dependency on Google Mobile Ads so a late native
/// callback can be rejected after consent or premium/no-ads invalidates it.
/// Foreground decisions are delegated to [AppOpenForegroundPolicy], which
/// outlives this state across [initAppOpenAd] calls.
class AppOpenAdState {
  factory AppOpenAdState({
    Duration maxCacheDuration = const Duration(hours: 4),
    DateTime Function()? now,
    AppOpenForegroundPolicy? foregroundPolicy,
  }) {
    final clock = now ?? DateTime.now;
    return AppOpenAdState._(
      maxCacheDuration,
      clock,
      foregroundPolicy ?? AppOpenForegroundPolicy(now: clock),
    );
  }

  AppOpenAdState._(this._maxCacheDuration, this._now, this.foregroundPolicy);

  final AdLoadGate _loadGate = AdLoadGate();
  final Duration _maxCacheDuration;
  final DateTime Function() _now;

  /// Policy deciding whether a `resumed` event may show an App Open Ad.
  final AppOpenForegroundPolicy foregroundPolicy;

  bool _isLoading = false;
  bool _isReady = false;
  bool _isShowing = false;
  AppOpenSuppression? _showSuppression;
  int? _activeLoadGeneration;
  DateTime? _loadedAt;

  bool get canUseAds => _loadGate.canUseAds;
  bool get isLoading => _isLoading;
  bool get isShowing => _isShowing;
  bool get isReady => _isReady && !isExpired;
  bool get isExpired =>
      _loadedAt == null || _now().difference(_loadedAt!) >= _maxCacheDuration;

  void setAdsRequestAllowed(bool value) {
    _loadGate.setRequestAllowed(value);
    if (!value) _invalidateAd();
  }

  void setDisabled(bool value) {
    _loadGate.setDisabled(value);
    if (value) _invalidateAd();
  }

  /// Starts one load and returns its generation, or null if loading is unsafe.
  int? beginLoad() {
    if (!canUseAds || _isLoading || isReady || _isShowing) return null;
    _isLoading = true;
    _activeLoadGeneration = _loadGate.generation;
    return _activeLoadGeneration;
  }

  /// Marks an ad as loaded only when its request remains current.
  bool completeLoad(int loadGeneration) {
    if (_activeLoadGeneration != loadGeneration) return false;
    _isLoading = false;
    _activeLoadGeneration = null;
    if (!_loadGate.isCurrent(loadGeneration)) return false;
    _loadedAt = _now();
    _isReady = true;
    return true;
  }

  void failLoad(int loadGeneration) {
    if (_activeLoadGeneration != loadGeneration) return;
    _isLoading = false;
    _activeLoadGeneration = null;
  }

  /// Reserves the loaded ad so it cannot be shown twice concurrently.
  bool beginShow() {
    if (!canUseAds || !isReady || _isShowing) return false;
    _isReady = false;
    _loadedAt = null;
    _isShowing = true;
    // A resume emitted while returning from the ad must not show its preload.
    _showSuppression = foregroundPolicy.beginScope();
    return true;
  }

  /// Records the impression for the fullscreen-ad interval.
  void recordShown() => foregroundPolicy.recordFullscreenAdShown();

  void finishShow() {
    _isShowing = false;
    _showSuppression?.end();
    _showSuppression = null;
  }

  /// Records a `paused` lifecycle event.
  void markBackgrounded() => foregroundPolicy.markBackgrounded();

  /// Suppresses App Open Ad showing for the next foreground event.
  void suppressNextForeground({
    Duration timeout = AppOpenForegroundPolicy.defaultOneShotTimeout,
  }) => foregroundPolicy.suppressNextForeground(timeout: timeout);

  /// Returns true only for a foreground event eligible to show an App Open Ad.
  ///
  /// The policy is always consulted first so it consumes its one-shot and
  /// background markers even when no ad is ready.
  bool shouldShowOnForeground() {
    final allowed = foregroundPolicy.allowsForegroundShow();
    return allowed && canUseAds && isReady && !_isShowing;
  }

  void clearLoadedAd() {
    _isReady = false;
    _loadedAt = null;
  }

  void _invalidateAd() {
    _isLoading = false;
    _activeLoadGeneration = null;
    clearLoadedAd();
  }
}
