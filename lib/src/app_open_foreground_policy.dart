/// Decides whether a foreground (`resumed`) event may show an App Open Ad.
///
/// AdMob allows App Open Ads only "when the user opens or switches back to an
/// app" and forbids ads "immediately before or after app open ads". A Flutter
/// `resumed` event is emitted for many other reasons: a permission dialog, a
/// share sheet, the store purchase sheet, the UMP privacy form, system
/// settings, or the activity of another fullscreen ad. This policy filters
/// those events in one place so applications do not have to.
///
/// It has no Flutter or Google Mobile Ads dependency so it can be unit tested.
class AppOpenForegroundPolicy {
  AppOpenForegroundPolicy({
    DateTime Function()? now,
    this.minIntervalSinceFullscreenAd = Duration.zero,
    this.lateForegroundGrace = defaultLateForegroundGrace,
  }) : _now = now ?? DateTime.now;

  /// Shared instance used by App Open, interstitial, rewarded and payment code.
  static final AppOpenForegroundPolicy instance = AppOpenForegroundPolicy();

  /// Upper bound of a scope whose owner never calls [AppOpenSuppression.end].
  static const Duration defaultScopeTimeout = Duration(minutes: 10);

  /// Default validity of [suppressNextForeground].
  static const Duration defaultOneShotTimeout = Duration(minutes: 5);

  /// After a scope ends, a `resumed` arriving within this window is still
  /// treated as the return from that scope (native callbacks may precede
  /// the lifecycle event).
  static const Duration defaultLateForegroundGrace = Duration(seconds: 3);

  final DateTime Function() _now;

  /// Minimum time between the last fullscreen ad impression (App Open,
  /// interstitial or rewarded) and an automatic App Open on foreground.
  /// Zero keeps the historical behaviour.
  Duration minIntervalSinceFullscreenAd;

  /// See [defaultLateForegroundGrace].
  Duration lateForegroundGrace;

  final Map<int, DateTime> _scopes = <int, DateTime>{};
  int _nextScopeId = 0;
  bool _backgrounded = false;
  bool _foregroundSeenInScope = false;
  DateTime? _oneShotUntil;
  DateTime? _lastFullscreenAdAt;

  /// Time of the last fullscreen ad impression recorded by any format.
  DateTime? get lastFullscreenAdAt => _lastFullscreenAdAt;

  /// True while any scope or a valid one-shot suppression is active.
  bool get isSuppressed {
    _purgeExpiredScopes();
    return _scopes.isNotEmpty || _oneShotValid;
  }

  /// Records that the app reached `paused`, i.e. it really left the screen.
  /// Only a `resumed` following this is a "switch back to the app".
  void markBackgrounded() => _backgrounded = true;

  /// Records an impression of any fullscreen ad for
  /// [minIntervalSinceFullscreenAd].
  void recordFullscreenAdShown() => _lastFullscreenAdAt = _now();

  /// Suppresses App Open on foreground for the lifetime of the returned
  /// scope. Use it around an operation that opens something over the app:
  /// another fullscreen ad, a store purchase, a permission or share sheet.
  ///
  /// The scope ends with [AppOpenSuppression.end] or after [timeout].
  AppOpenSuppression beginScope({Duration timeout = defaultScopeTimeout}) {
    _purgeExpiredScopes();
    final id = _nextScopeId++;
    _scopes[id] = _now().add(timeout);
    return AppOpenSuppression._(this, id);
  }

  /// Suppresses the next foreground event, for at most [timeout].
  ///
  /// Intended for fire-and-forget launches (system settings, an external
  /// browser) whose return the app cannot observe. Prefer [beginScope] when
  /// the operation exposes a completion.
  void suppressNextForeground({Duration timeout = defaultOneShotTimeout}) {
    final until = _now().add(timeout);
    final current = _oneShotUntil;
    if (current == null || current.isBefore(until)) _oneShotUntil = until;
  }

  /// Evaluates one `resumed` event and consumes the state it needs.
  ///
  /// Returns true only for a foreground event that is a genuine return from
  /// background, not suppressed, and outside [minIntervalSinceFullscreenAd].
  /// Callers still check that an ad is loaded and allowed.
  bool allowsForegroundShow() {
    final wasBackgrounded = _backgrounded;
    _backgrounded = false;
    _purgeExpiredScopes();

    if (_scopes.isNotEmpty) {
      _foregroundSeenInScope = true;
      return false;
    }

    final oneShotUntil = _oneShotUntil;
    if (oneShotUntil != null) {
      _oneShotUntil = null;
      if (!_now().isAfter(oneShotUntil)) return false;
    }

    if (!wasBackgrounded) return false;

    final lastAd = _lastFullscreenAdAt;
    if (lastAd != null &&
        minIntervalSinceFullscreenAd > Duration.zero &&
        _now().difference(lastAd) < minIntervalSinceFullscreenAd) {
      return false;
    }
    return true;
  }

  /// Clears every scope, one-shot and impression time. Used on dispose.
  void reset() {
    _scopes.clear();
    _backgrounded = false;
    _foregroundSeenInScope = false;
    _oneShotUntil = null;
    _lastFullscreenAdAt = null;
  }

  bool get _oneShotValid {
    final until = _oneShotUntil;
    if (until == null) return false;
    if (_now().isAfter(until)) {
      _oneShotUntil = null;
      return false;
    }
    return true;
  }

  void _endScope(int id) {
    if (_scopes.remove(id) == null) return;
    _purgeExpiredScopes();
    if (_scopes.isNotEmpty) return;
    final seen = _foregroundSeenInScope;
    _foregroundSeenInScope = false;
    // The lifecycle `resumed` for this scope may still be on its way.
    if (!seen && lateForegroundGrace > Duration.zero) {
      suppressNextForeground(timeout: lateForegroundGrace);
    }
  }

  void _purgeExpiredScopes() {
    if (_scopes.isEmpty) return;
    final now = _now();
    _scopes.removeWhere((_, expiresAt) => now.isAfter(expiresAt));
    if (_scopes.isEmpty) _foregroundSeenInScope = false;
  }
}

/// Handle of one suppression scope from [AppOpenForegroundPolicy.beginScope].
class AppOpenSuppression {
  AppOpenSuppression._(this._policy, this._id);

  final AppOpenForegroundPolicy _policy;
  final int _id;
  bool _ended = false;

  bool get isActive => !_ended && _policy._scopes.containsKey(_id);

  /// Ends the scope. Safe to call more than once.
  void end() {
    if (_ended) return;
    _ended = true;
    _policy._endScope(_id);
  }
}
