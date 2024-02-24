import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_api/utils.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_consent.dart';
import 'interstitial_ad.dart';
import 'payment_service.dart';
import 'rewarded_ad.dart';

/// - [mainInitilize] - jobs during native splash (should be overridden),
///   - [initAdsParameters]
///   - [initPurchases]
/// - [afterSplashInitilize] - jobs after native splash (should be overridden),
///   - [showConsentAndAd]
///   - [initDoneStream]
///   - [initDone]
mixin class InitialServiceMixin {
  // singleton
  static final InitialServiceMixin instance = InitialServiceMixin._();
  InitialServiceMixin._();

  int _consentTime = 0;
  int _createAdTime = 0;
  int _showAdTime = 0;
  int _adsInitTime = 0;
  int _productsLoadTime = 0;
  int _purchaseRestoreTime = 0;
  int _purchaseCheckPremiumTime = 0;
  int get consentTime => _consentTime;
  int get createAdTime => _createAdTime;
  int get showAdTime => _showAdTime;
  int get adsInitTime => _adsInitTime;
  int get productsLoadTime => _productsLoadTime;
  int get purchaseRestoreTime => _purchaseRestoreTime;
  int get purchaseCheckPremiumTime => _purchaseCheckPremiumTime;

  final StreamController<bool> _initDone = StreamController<bool>()..add(false);

  /// helpful in detecting when to display app content after [afterSplashInitilize]
  Stream<bool> get initDoneStream => _initDone.stream;
  void initDone() {
    _initDone.add(true);
    _initDone.close();
  }

  Future<void> _waitForConsent({
    required List<String>? testDeviceIds,
  }) async {
    final Completer<void> completer = Completer<void>();
    try {
      await AdConsent().consentInfo(
        params: AdConsent.params(testIdentifiers: testDeviceIds),
        action: () {
          completer.complete();
        },
        onError: () {
          completer.complete();
        },
      );
    } catch (e) {
      printR("[DEV-LOG] InitialServiceMixin.waitForConsent error: $e");
      completer.complete();
    }
    return completer.future;
  }

  Future<void> _waitForAdStart() async {
    final Completer<void> completer = Completer<void>();
    try {
      await showInterstitialAd(
        onStartCallback: () async {
          completer.complete();
        },
      );
    } catch (e) {
      printR("[DEV-LOG] InitialServiceMixin.waitForAdStart error: $e");
      completer.complete();
    }
    return completer.future;
  }

  /// Use after payments checking and after splash dropping.
  /// - [skipConsentAndAd] - true for premium user
  ///
  /// Uses:
  /// - [AdConsent.consentInfo]
  /// - [createInterstitialAd]
  /// - [showInterstitialAd]
  Future<void> showConsentAndAd({
    bool skipConsentAndAd = false,
    bool showAdOnStart = false,
    required List<String>? testDeviceIds,
  }) async {
    if (!skipConsentAndAd) {
      try {
        final int start = DateTime.now().millisecondsSinceEpoch;
        await _waitForConsent(testDeviceIds: testDeviceIds);
        final int afterConsent = DateTime.now().millisecondsSinceEpoch;
        if (showAdOnStart) {
          await createInterstitialAd();
        } else {
          createInterstitialAd();
        }
        final int afterCreate = DateTime.now().millisecondsSinceEpoch;
        if (showAdOnStart) {
          await _waitForAdStart();
        }
        final int afterShow = DateTime.now().millisecondsSinceEpoch;
        _consentTime = afterConsent - start;
        _createAdTime = afterCreate - afterConsent;
        _showAdTime = afterShow - afterCreate;
      } catch (e) {
        printR("[DEV-LOG] InitialService._showConsentAndAd error: $e");
      }
    }
  }

  /// - ticks: times 200ms is the maximum ad loading time; 15 means 3 seconds; specifies how many times to check if the ad has been loaded before aborting
  Future<void> initAdsParameters({
    required String interstitialAdUnitId,
    required String rewardedAdUnitId,
    int loadingTicksInterstitialAd = 15,
    int loadingTicksRewardedAd = 25,
    int minIntervalBetweenInterstitialAdsInSecs = 60,
    required List<String>? testDeviceIds,
  }) async {
    final int start = DateTime.now().millisecondsSinceEpoch;
    try {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: testDeviceIds),
      );
      initRewardedAd(
        adUnitId: rewardedAdUnitId,
        loadingTicks: loadingTicksRewardedAd,
      );
      initInterstitialAd(
        adUnitId: interstitialAdUnitId,
        loadingTicks: loadingTicksInterstitialAd,
        minIntervalBetweenAdsInSecs: minIntervalBetweenInterstitialAdsInSecs,
      );
    } catch (e) {
      printR("[DEV-LOG] InitialService._initAds error: $e");
    }
    _adsInitTime = DateTime.now().millisecondsSinceEpoch - start;
  }

  /// - [PaymentService.initParameters]
  /// - [PaymentService.loadProducts]
  /// - [PaymentService.restorePurchases]
  /// - [PaymentService.waitForPurchaseRestoring]
  Future<void> initPurchases({
    required Set<String> activeProductIds,
    required Set<String> allProductIds,
    required Set<String> premiumProductIds,
    PaymentVerifyCallback? verifyPurchaseCallback,
  }) async {
    int time1 = DateTime.now().millisecondsSinceEpoch;
    int time2 = time1, time3 = time1, time4 = time1;
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
      time1 = DateTime.now().millisecondsSinceEpoch;
      try {
        PaymentService.instance.initParameters(
          activeProductIds: activeProductIds,
          allProductIds: allProductIds,
          premiumProductIds: premiumProductIds,
          verifyPurchaseCallback: verifyPurchaseCallback,
        );
        await PaymentService.instance.loadProducts();
        time2 = DateTime.now().millisecondsSinceEpoch;
        await PaymentService.instance.restorePurchases();
        time3 = DateTime.now().millisecondsSinceEpoch;
        await PaymentService.instance.waitForPurchaseRestoring();
        time4 = DateTime.now().millisecondsSinceEpoch;
      } catch (e) {
        printR("[DEV-LOG] InitialService._initPurchases error: $e");
      }
    }
    _productsLoadTime = time2 - time1;
    _purchaseRestoreTime = time3 - time2;
    _purchaseCheckPremiumTime = time4 - time3;
  }

  /// Execute it before runApp in main().
  ///
  /// Should be overwritten to make initializations like:
  /// - [initPurchases]
  /// - [initAdsParameters] (consent and optional ad must be shown after splash [afterSplashInitilize] by [showConsentAndAd])
  /// - database,
  /// - screen orientation,
  /// - firebase features,
  /// -
  Future<void> mainInitilize() async {
    const String androidInterstitalTestId = 'ca-app-pub-3940256099942544/1033173712';
    const String iOSInterstitalTestId = 'ca-app-pub-3940256099942544/4411468910';
    const String androidRewardedTestId = 'ca-app-pub-3940256099942544/5224354917';
    const String iOSRewardedTestId = 'ca-app-pub-3940256099942544/1712485313';

    final FutureGroup<void> futureGroup = FutureGroup();
    futureGroup.add(initPurchases(
      activeProductIds: {},
      allProductIds: {},
      premiumProductIds: {},
      verifyPurchaseCallback: (_) => Future<bool>.value(true),
    ));
    futureGroup.add(initAdsParameters(
      interstitialAdUnitId: Platform.isIOS ? iOSInterstitalTestId : androidInterstitalTestId,
      rewardedAdUnitId: Platform.isIOS ? iOSRewardedTestId : androidRewardedTestId,
      testDeviceIds: [],
    ));
    futureGroup.close();
    await futureGroup.future;
  }

  /// Execute it after splash dropping. Should be overwritten and contain [showConsentAndAd].
  Future<void> afterSplashInitilize() async {
    await showConsentAndAd(
      skipConsentAndAd: false,
      testDeviceIds: [],
    );
    initDone();
  }
}
