import 'package:flutter/foundation.dart' show ValueNotifier;

import 'ad_load_gate.dart';

/// Central UMP/no-ads gate for the adaptive banner.
///
/// Banners are widgets, not a singleton service like the other ad formats, so
/// every mounted banner listens to this notifier and disposes its own ad the
/// moment consent is withdrawn or the format is disabled, instead of relying
/// on the hosting screen to rebuild.
///
/// Mirrors [AdLoadGate] semantics used by the interstitial, rewarded and App
/// Open formats, so a banner never requests an ad before
/// `setBannerAdsAllowed(true)`.
class BannerAdGate extends ValueNotifier<bool> {
  BannerAdGate() : super(false);

  /// Shared instance wired from `showConsent` and the startup ads platform.
  static final BannerAdGate instance = BannerAdGate();

  final AdLoadGate _gate = AdLoadGate();

  /// Bumps whenever a pending banner load must be discarded.
  int get generation => _gate.generation;

  /// False once the load that captured [generation] may no longer be used.
  bool isCurrent(int loadGeneration) => _gate.isCurrent(loadGeneration);

  /// Enables banner loading only after UMP reports that ads may be requested.
  void setRequestAllowed(bool allowed) {
    _gate.setRequestAllowed(allowed);
    value = _gate.canUseAds;
  }

  /// Disables banners for premium/no-ads users. True also invalidates any
  /// pending load, mirroring the other formats' `disable*Ad()`.
  void setDisabled(bool disabled) {
    _gate.setDisabled(disabled);
    value = _gate.canUseAds;
  }
}
