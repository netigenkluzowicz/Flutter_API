import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_consent.dart';
import 'interstitial_ad.dart';
import 'payment_service.dart';
import 'rewarded_ad.dart';
import 'utils.dart';

/// - [mainInitialize] - jobs during native splash (should be overridden),
///   - [initAdsParameters]
///   - [initPurchases]
/// - [afterSplashInitialize] - jobs after native splash (should be overridden),
///   - [showConsent]
///   - [initDoneStream]
///   - [initDone]
mixin class InitialServiceMixin {
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

  bool _adsConfigured = false;
  bool _mobileAdsInitialized = false;
  bool _adsCanRequest = false;
  bool _privacyOptionsRequired = false;
  List<String> _testDeviceIds = const [];

  /// True only after a fresh UMP update allows ad requests and the Mobile Ads
  /// SDK has been initialized.
  bool get adsCanRequest => _adsCanRequest;

  /// Drives a visible "Privacy choices" entry point in app settings.
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  final StreamController<bool> _initDone = StreamController<bool>.broadcast();
  bool _isInitDone = false;

  /// helpful in detecting when to display app content after [afterSplashInitialize]
  Stream<bool> get initDoneStream => _initDone.stream;
  bool get isInitDone => _isInitDone;

  void initDone() {
    if (_isInitDone) return;
    _isInitDone = true;
    _initDone.add(true);
  }

  @protected
  void safeComplete(Completer c) {
    if (!c.isCompleted) c.complete();
  }

  Future<void> _waitForAdStart() async {
    final Completer<void> completer = Completer<void>();
    try {
      await showInterstitialAd(onStartCallback: () => safeComplete(completer));
    } catch (e) {
      _errorLog("waitForAdStart error: $e");
      safeComplete(completer);
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
  Future<void> showConsent({
    bool skipConsentAndAd = false,
    bool showAdAfterConsent = false,
    required List<String>? testDeviceIds,
  }) async {
    if (skipConsentAndAd) {
      _adsCanRequest = false;
      setInterstitialAdsAllowed(false);
      setRewardedAdsAllowed(false);
      return;
    }

    try {
      final sw = Stopwatch()..start();
      final result = await AdConsent().requestConsent(
        params: AdConsent.params(testIdentifiers: testDeviceIds),
      );
      _consentTime = sw.elapsedMilliseconds;
      _privacyOptionsRequired = result.privacyOptionsRequired;
      _adsCanRequest = result.canRequestAds;
      setInterstitialAdsAllowed(_adsCanRequest);
      setRewardedAdsAllowed(_adsCanRequest);

      if (!_adsCanRequest) return;
      if (!_adsConfigured) {
        throw StateError(
          'Ads are not configured. Call initAdsParameters() first.',
        );
      }

      await _initializeMobileAds();

      final afterConsent = sw.elapsedMilliseconds;
      if (showAdAfterConsent) {
        await createInterstitialAd();
      } else {
        unawaited(createInterstitialAd());
      }
      final afterCreate = sw.elapsedMilliseconds;

      if (showAdAfterConsent) {
        await _waitForAdStart();
      }

      final afterShow = sw.elapsedMilliseconds;
      _createAdTime = afterCreate - afterConsent;
      _showAdTime = afterShow - afterCreate;
    } catch (e) {
      _adsCanRequest = false;
      setInterstitialAdsAllowed(false);
      setRewardedAdsAllowed(false);
      _errorLog("showConsent error: $e");
    }
  }

  /// - ticks: times 200ms is the maximum ad loading time; 15 means 3 seconds; specifies how many times to check if the ad has been loaded before aborting
  Future<void> initAdsParameters({
    required String interstitialAdUnitId,
    required String rewardedAdUnitId,
    int loadingTicksInterstitialAd = 15,
    int loadingTicksRewardedAd = 25,
    int minIntervalBetweenInterstitialAdsInSecs = 60,
    required List<String> testDeviceIds,
    int? maxFailedLoadAttempts,
  }) async {
    final sw = Stopwatch()..start();
    try {
      _testDeviceIds = List.unmodifiable(testDeviceIds);
      initRewardedAd(
        adUnitId: rewardedAdUnitId,
        loadingTicks: loadingTicksRewardedAd,
        maxFailedLoadAttempts: maxFailedLoadAttempts,
      );
      _adsConfigured = true;
      initInterstitialAd(
        adUnitId: interstitialAdUnitId,
        loadingTicks: loadingTicksInterstitialAd,
        minIntervalBetweenAdsInSecs: minIntervalBetweenInterstitialAdsInSecs,
        maxFailedLoadAttempts: maxFailedLoadAttempts,
      );
    } catch (e) {
      _errorLog("._initAds error: $e");
    }
    _adsInitTime = sw.elapsedMilliseconds;
  }

  Future<void> _initializeMobileAds() async {
    if (_mobileAdsInitialized) return;
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: _testDeviceIds),
    );
    await MobileAds.instance.initialize();
    _mobileAdsInitialized = true;
  }

  /// - [activeProductIds] - all products that could be bought in app at this moment
  /// - [allProductIds] - all products to restoring (also depracated)
  /// - [iosSubscriptionProductIds] - all ios subscription products (validated by our server)
  /// - [premiumProductIds] - all products where [premiumUser] == true
  /// - [restoringOnStartTicks] - times 100ms is the maximum time of purchases restoring on start; 5 means 500ms
  /// ---
  /// - [PaymentService.initParameters]
  /// - [PaymentService.loadProducts]
  /// - [PaymentService.restorePurchases]
  /// - [PaymentService.waitForPurchaseRestoring]
  Future<void> initPurchases({
    required Set<String> activeProductIds,
    required Set<String> iosSubscriptionProductIds,
    required Set<String> allProductIds,
    required Set<String> premiumProductIds,
    Duration? receiptValidationChecking,
    Duration? iosSubscriptionExtension,
    required PaymentVerifyCallback verifyPurchaseCallback,
    bool verifyIosSubscriptionsLocally = false,
    int restoringOnStartTicks = 30,
  }) async {
    final sw = Stopwatch()..start();
    int time1 = sw.elapsedMilliseconds;
    int time2 = time1, time3 = time1, time4 = time1;
    if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android) {
      time1 = sw.elapsedMilliseconds;
      try {
        await PaymentService.instance.initParameters(
          activeProductIds: activeProductIds,
          iosSubscriptionProductIds: iosSubscriptionProductIds,
          allProductIds: allProductIds,
          premiumProductIds: premiumProductIds,
          verifyPurchaseCallback: verifyPurchaseCallback,
          verifyIosSubscriptionsLocally: verifyIosSubscriptionsLocally,
          receiptValidationChecking: receiptValidationChecking,
          iosSubscriptionExtension: iosSubscriptionExtension,
          restoringOnStartTicks: restoringOnStartTicks,
        );
        await PaymentService.instance.loadProducts();
        time2 = sw.elapsedMilliseconds;
        await PaymentService.instance.restorePurchases();
        time3 = sw.elapsedMilliseconds;
        await PaymentService.instance.waitForPurchaseRestoring();
        time4 = sw.elapsedMilliseconds;
      } catch (e) {
        _errorLog("_initPurchases error: $e");
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
  /// - [initAdsParameters] (consent and optional ad must be shown after splash [afterSplashInitialize] by [showConsent])
  /// - database,
  /// - screen orientation,
  /// - firebase features,
  /// -
  Future<void> mainInitialize() async {
    const String androidInterstitalTestId =
        'ca-app-pub-3940256099942544/1033173712';
    const String iOSInterstitalTestId =
        'ca-app-pub-3940256099942544/4411468910';
    const String androidRewardedTestId =
        'ca-app-pub-3940256099942544/5224354917';
    const String iOSRewardedTestId = 'ca-app-pub-3940256099942544/1712485313';

    await Future.wait<void>([
      initPurchases(
        activeProductIds: {},
        iosSubscriptionProductIds: {},
        allProductIds: {},
        premiumProductIds: {},
        verifyPurchaseCallback: (_) => Future<bool>.value(true),
        receiptValidationChecking: null,
        iosSubscriptionExtension: null,
      ),
      initAdsParameters(
        interstitialAdUnitId: Platform.isIOS
            ? iOSInterstitalTestId
            : androidInterstitalTestId,
        rewardedAdUnitId: Platform.isIOS
            ? iOSRewardedTestId
            : androidRewardedTestId,
        testDeviceIds: [],
      ),
    ]);
  }

  /// Execute it after splash dropping. Should be overwritten and contain [showConsent].
  Future<void> afterSplashInitialize() async {
    await showConsent(
      skipConsentAndAd: false,
      showAdAfterConsent: false,
      testDeviceIds: [],
    );
    initDone();
  }
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR("[InitialServiceMixin] ⚠️ ERROR $object");
}
