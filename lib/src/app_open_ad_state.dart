import 'ad_load_gate.dart';

/// State machine shared by the App Open Ad lifecycle and its unit tests.
///
/// It deliberately has no dependency on Google Mobile Ads so a late native
/// callback can be rejected after consent or premium/no-ads invalidates it.
class AppOpenAdState {
  factory AppOpenAdState({
    Duration maxCacheDuration = const Duration(hours: 4),
    DateTime Function()? now,
  }) => AppOpenAdState._(maxCacheDuration, now ?? DateTime.now);

  AppOpenAdState._(this._maxCacheDuration, this._now);

  final AdLoadGate _loadGate = AdLoadGate();
  final Duration _maxCacheDuration;
  final DateTime Function() _now;

  bool _isLoading = false;
  bool _isReady = false;
  bool _isShowing = false;
  bool _ignoreNextForeground = false;
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
    _ignoreNextForeground = true;
    return true;
  }

  void finishShow() => _isShowing = false;

  /// Suppresses App Open Ad showing for the next foreground event.
  void suppressNextForeground() => _ignoreNextForeground = true;

  /// Returns true only for a foreground event eligible to show an App Open Ad.
  bool shouldShowOnForeground() {
    if (_ignoreNextForeground) {
      _ignoreNextForeground = false;
      return false;
    }
    return canUseAds && isReady && !_isShowing;
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
