import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// A phone- and tablet-safe anchored adaptive banner.
///
/// Set [enabled] only after UMP's `canRequestAds` is true and the user is not
/// premium. Failed and removed ads are always disposed.
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadForCurrentWidth();
  }

  @override
  void didUpdateWidget(covariant AdaptiveBannerAd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
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
    if (!widget.enabled) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (width <= 0 || width == _requestedWidth) return;
    _requestedWidth = width;
    unawaited(_load(width));
  }

  Future<void> _load(int width) async {
    _disposeBanner();
    final generation = _loadGeneration;

    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || generation != _loadGeneration || size == null) return;

    late final BannerAd banner;
    banner = BannerAd(
      adUnitId: widget.adUnitId,
      request: widget.request,
      size: size,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || generation != _loadGeneration || !widget.enabled) {
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
    _disposeBanner();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banner = _bannerAd;
    if (!widget.enabled || banner == null) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: banner.size.width.toDouble(),
      height: banner.size.height.toDouble(),
      child: AdWidget(ad: banner),
    );
  }
}
