import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'src/banner_ad_gate.dart';

/// Enables banner loading only after UMP reports that ads may be requested.
///
/// Called by `showConsent` and the startup ads platform, like
/// [setInterstitialAdsAllowed] for the other formats.
void setBannerAdsAllowed(bool value) =>
    BannerAdGate.instance.setRequestAllowed(value);

/// Disables banner ads for premium/no-ads users and disposes mounted banners.
void disableBannerAd() => BannerAdGate.instance.setDisabled(true);

/// Re-enables banner ads after an explicit no-ads disable.
void enableBannerAd() => BannerAdGate.instance.setDisabled(false);

/// A phone- and tablet-safe anchored adaptive banner.
///
/// [enabled] is the application's decision to show a banner in this place. The
/// library decides on its own whether an ad may be requested at all, through
/// [setBannerAdsAllowed] / [disableBannerAd]; a mounted banner disposes itself
/// as soon as consent is withdrawn. Failed and removed ads are always
/// disposed.
class AdaptiveBannerAd extends StatefulWidget {
  const AdaptiveBannerAd({
    super.key,
    required this.adUnitId,
    required this.enabled,
    this.request = const AdRequest(),
    this.onLoaded,
    this.onFailedToLoad,
  });

  final String adUnitId;
  final bool enabled;
  final AdRequest request;
  final VoidCallback? onLoaded;
  final ValueChanged<LoadAdError>? onFailedToLoad;

  @override
  State<AdaptiveBannerAd> createState() => _AdaptiveBannerAdState();
}

class _AdaptiveBannerAdState extends State<AdaptiveBannerAd> {
  BannerAd? _bannerAd;
  int? _requestedWidth;
  int _loadGeneration = 0;

  bool get _canLoad => widget.enabled && BannerAdGate.instance.value;

  @override
  void initState() {
    super.initState();
    BannerAdGate.instance.addListener(_onGateChanged);
  }

  void _onGateChanged() {
    if (!mounted) return;
    if (BannerAdGate.instance.value) {
      _loadForCurrentWidth();
    } else {
      setState(_disposeBanner);
      _requestedWidth = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadForCurrentWidth();
  }

  @override
  void didUpdateWidget(covariant AdaptiveBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canLoad) {
      _disposeBanner();
      _requestedWidth = null;
      return;
    }

    if (!oldWidget.enabled ||
        oldWidget.adUnitId != widget.adUnitId ||
        oldWidget.request != widget.request) {
      _requestedWidth = null;
      _loadForCurrentWidth();
    }
  }

  void _loadForCurrentWidth() {
    if (!_canLoad) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width <= 0 || width == _requestedWidth) return;
    _requestedWidth = width;
    unawaited(_load(width));
  }

  Future<void> _load(int width) async {
    _disposeBanner();
    final generation = _loadGeneration;
    final gateGeneration = BannerAdGate.instance.generation;

    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted ||
        generation != _loadGeneration ||
        size == null ||
        !_canLoad ||
        !BannerAdGate.instance.isCurrent(gateGeneration)) {
      return;
    }

    late final BannerAd banner;
    banner = BannerAd(
      adUnitId: widget.adUnitId,
      request: widget.request,
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted ||
              generation != _loadGeneration ||
              !_canLoad ||
              !BannerAdGate.instance.isCurrent(gateGeneration)) {
            ad.dispose();
            return;
          }
          setState(() => _bannerAd = banner);
          widget.onLoaded?.call();
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (generation == _loadGeneration) {
            if (mounted) setState(() => _bannerAd = null);
            widget.onFailedToLoad?.call(error);
          }
        },
      ),
    );
    await banner.load();
  }

  void _disposeBanner() {
    _loadGeneration++;
    _bannerAd?.dispose();
    _bannerAd = null;
  }

  @override
  void dispose() {
    BannerAdGate.instance.removeListener(_onGateChanged);
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _bannerAd;
    if (!_canLoad || banner == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: banner.size.width.toDouble(),
      height: banner.size.height.toDouble(),
      child: AdWidget(ad: banner),
    );
  }
}
