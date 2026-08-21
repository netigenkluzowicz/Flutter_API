import 'dart:async';
import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart'
    show InAppPurchaseStoreKitPlatformAddition, AppStoreProduct2Details;
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart'
    show SK2Product, SK2ProductType;
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart'
    show
        SKError,
        SKPaymentQueueDelegateWrapper,
        SKPaymentTransactionWrapper,
        SKStorefrontWrapper;

import 'app_open_ad.dart';
import 'src/entitlement_ledger.dart';
import 'interstitial_ad.dart';
import 'rewarded_ad.dart';
import 'subscription_offer_selector.dart';
import 'utils.dart';

const bool kInitialPremiumUser = false;

/// - idle
/// - pending
/// - completed
/// - canceled
/// - errored
enum PaymentStatus { idle, pending, completed, canceled, errored }

/// Additional entitlement states, kept separate from [PaymentStatus] so
/// existing status listeners retain their historical contract.
enum PaymentEntitlementEventType {
  granted,
  restored,
  invalidVerification,
  expired,
  revoked,
  verificationError,
}

class PaymentEntitlementEvent {
  const PaymentEntitlementEvent({
    required this.productId,
    required this.type,
    required this.isSubscription,
  });

  final String productId;
  final PaymentEntitlementEventType type;
  final bool isSubscription;
}

enum RestorePurchasesResultStatus {
  inProgress,
  restored,
  noPurchases,
  invalidVerification,
  failed,
  timedOut,
}

/// Detailed outcome of a restore request. [restorePurchases] intentionally
/// keeps its legacy meaning: it only reports whether the store request began.
class RestorePurchasesResult {
  const RestorePurchasesResult({
    required this.status,
    this.hasVerifiedPremium = false,
    this.error,
  });

  final RestorePurchasesResultStatus status;
  final bool hasVerifiedPremium;
  final Object? error;
}

typedef PaymentVerifyCallback = Future<bool> Function(PurchaseDetails);

/// - **[initParameters] - must be done first**
/// - [_listenToPurchaseUpdated]
/// - [_verifyPurchase]
/// - [loadProducts]
/// - [restorePurchases]
/// - [dispose]
/// - [waitForPurchaseRestoring]
/// - [reloadPurchases]
class PaymentService {
  // make this a singleton class
  static final PaymentService instance = PaymentService._();
  PaymentService._() {
    _infoLog("constructor");
    if (kInitialPremiumUser) {
      disableInterstitialAd();
      disableRewardedAd();
      disableAppOpenAd();
    } else {
      enableInterstitialAd();
    }
    _boughtProductIdsStreamController =
        StreamController<List<String>>.broadcast()
          ..add(boughtProductIds.toList());
    _paymentStatusStreamController = StreamController<PaymentStatus>.broadcast()
      ..add(PaymentStatus.idle);
  }

  late PaymentVerifyCallback _verifyPurchaseCallback;

  bool _productIdsProvided = false;
  Set<String> _activeProductIds = {};
  Set<String> _iosSubscriptionProductIds = {};
  Set<String> _allProductIds = {};
  Set<String> _premiumProductIds = {};
  int _restoringOnStartTicks = 30;
  bool _verifyIosSubscriptionsLocally = false;

  // PurchaseDetails.purchaseID changes between app launches so cannot be used
  String? _cachedProductId;
  DateTime? _premiumExpiration;
  DateTime? _lastReceiptValidation;
  Duration _receiptValidationChecking = Duration(hours: 1);
  Duration _verificationTimeout = const Duration(seconds: 30);
  Duration get receiptValidationChecking => _receiptValidationChecking;
  Duration _iosSubscriptionExtension = Duration(days: 0);
  Duration get iosSubscriptionExtension => _iosSubscriptionExtension;

  final _secure = const FlutterSecureStorage();
  final EntitlementLedger<PurchaseDetails> _entitlements = EntitlementLedger();
  Timer? _entitlementRevalidationTimer;
  bool _entitlementRevalidationInProgress = false;
  int _entitlementLifecycleGeneration = 0;
  Completer<void> _entitlementLifecycleStop = Completer<void>();
  bool _disposed = false;
  Completer<RestorePurchasesResult>? _restoreResultCompleter;
  Timer? _restoreResultTimer;
  Future<void> _restoreWithResultQueue = Future<void>.value();

  /// - [activeProductIds] - all products that could be bought in app at this moment
  /// - [allProductIds] - all products to restoring (also depracated)
  /// - [iosSubscriptionProductIds] - all ios subscription products (validated by our server)
  /// - [premiumProductIds] - all products where [premiumUser] == true
  /// - [restoringOnStartTicks] - times 100ms is the maximum time of purchases restoring on start; 5 means 500ms
  Future<void> initParameters({
    required Set<String> activeProductIds,
    required Set<String> iosSubscriptionProductIds,
    required Set<String> allProductIds,
    required Set<String> premiumProductIds,
    Duration? receiptValidationChecking,
    Duration verificationTimeout = const Duration(seconds: 30),
    Duration? iosSubscriptionExtension,
    required PaymentVerifyCallback verifyPurchaseCallback,
    bool verifyIosSubscriptionsLocally = false,
    int restoringOnStartTicks = 30,
  }) async {
    if (_disposed) {
      throw StateError('PaymentService has been disposed.');
    }
    _entitlementRevalidationTimer?.cancel();
    if (!_entitlementLifecycleStop.isCompleted) {
      _entitlementLifecycleStop.complete();
    }
    _entitlementLifecycleStop = Completer<void>();
    _entitlementLifecycleGeneration += 1;
    _activeProductIds = activeProductIds;
    _iosSubscriptionProductIds = iosSubscriptionProductIds;
    _allProductIds = allProductIds;
    _premiumProductIds = premiumProductIds;
    _restoringOnStartTicks = restoringOnStartTicks;
    _verifyPurchaseCallback = verifyPurchaseCallback;
    _verifyIosSubscriptionsLocally = verifyIosSubscriptionsLocally;
    _receiptValidationChecking =
        receiptValidationChecking ?? _receiptValidationChecking;
    _verificationTimeout = verificationTimeout;
    _iosSubscriptionExtension =
        iosSubscriptionExtension ?? _iosSubscriptionExtension;
    _productIdsProvided = true;

    if (Platform.isIOS && _verifyIosSubscriptionsLocally) {
      final results = await Future.wait<String?>([
        _secure.read(key: _premiumExpirationMillisKey),
        _secure.read(key: _lastReceiptValidationMillisKey),
        _secure.read(key: _cachedProductIdKey),
      ]);
      _premiumExpiration = results[0] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              int.parse(results[0]!),
              isUtc: true,
            );
      _lastReceiptValidation = results[1] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              int.parse(results[1]!),
              isUtc: true,
            );
      _cachedProductId = results[2];

      _infoLog(
        "lastReceiptValidation:$_lastReceiptValidation premiumExpiration:$_premiumExpiration cachedProductId:$_cachedProductId",
      );
      if (_cachedProductId != null &&
          _premiumExpiration != null &&
          _premiumExpiration!.isAfter(
            DateTime.now().subtract(_iosSubscriptionExtension),
          )) {
        _infoLog("deliverCachedProduct cachedProductId:$_cachedProductId");
        _deliverCachedProduct(_cachedProductId!);
      } else if (_cachedProductId != null || _premiumExpiration != null) {
        await _clearCachedPremium();
      }
    }

    //TODO: IMPORTANT purchaseStream.listen on ios returns a series of arrays of length one at a time for one purchased but renewed subscription
    _subscription ??= _inAppPurchase.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () {
        _infoLog("purchaseStream.onDone");
        _completeInitialRestoring(source: "onDone");
      },
      onError: (error) {
        _errorLog("purchaseStream.onError $error");
        _completeInitialRestoring(source: "onError");
      },
    );

    if (Platform.isIOS && !_delegateSet) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase
              .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.setDelegate(SKPaymentQueueDelegate());
      _delegateSet = true;
    }
    _scheduleEntitlementRevalidation();
  }

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  final Completer<void> _stopWaitingForInitialRestoringCompleter =
      Completer<void>();
  List<ProductDetails> _allProducts = <ProductDetails>[];
  final List<ProductDetails> _iosTrialProducts = <ProductDetails>[];
  List<String> _notFoundIds = <String>[];
  final List<PurchaseDetails> _purchases = <PurchaseDetails>[];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  bool _isBuying = false;
  String? _queryProductError;

  bool get premiumUser => _filterPremiumPurchases(_purchases).isNotEmpty;
  List<ProductDetails> get activeProducts =>
      _filterActiveProducts(_allProducts);
  Set<String> get iosTrialProductsIds =>
      _iosTrialProducts.map((p) => p.id).toSet();
  List<String> get notFoundIds => _notFoundIds;
  List<PurchaseDetails> get purchases => _purchases;
  Set<String> get boughtProductIds =>
      _purchases.map((p) => p.productID).toSet();
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  bool get loading => _loading;
  String? get queryProductError => _queryProductError;

  late StreamController<List<String>> _boughtProductIdsStreamController;
  late StreamController<PaymentStatus> _paymentStatusStreamController;
  late final StreamController<PaymentEntitlementEvent>
  _entitlementEventStreamController =
      StreamController<PaymentEntitlementEvent>.broadcast();
  late final StreamController<RestorePurchasesResult>
  _restorePurchasesResultStreamController =
      StreamController<RestorePurchasesResult>.broadcast();
  Stream<List<String>> get boughtProductIdsStream =>
      _boughtProductIdsStreamController.stream;
  Stream<PaymentStatus> get paymentStatusStream =>
      _paymentStatusStreamController.stream;
  Stream<PaymentEntitlementEvent> get entitlementEventStream =>
      _entitlementEventStreamController.stream;
  Stream<RestorePurchasesResult> get restorePurchasesResultStream =>
      _restorePurchasesResultStreamController.stream;

  ProductDetails? trialProductById(
    String id, {
    String? basePlanId,
    String? offerTag,
  }) {
    final products = _allProducts.where((product) => product.id == id).toList();
    if (Platform.isIOS) {
      if (products.isNotEmpty && iosTrialProductsIds.contains(id)) {
        return products.first;
      } else {
        return null;
      }
    }

    return _androidSubscriptionProduct(
      products,
      basePlanId: basePlanId,
      offerTag: offerTag,
      requiresFreeTrial: true,
    );
  }

  ProductDetails? productById(String id, {String? basePlanId}) {
    final products = _allProducts.where((product) => product.id == id).toList();
    if (!Platform.isAndroid) {
      return products.isEmpty ? null : products.first;
    }

    return _androidSubscriptionProduct(
          products,
          basePlanId: basePlanId,
          requiresFreeTrial: false,
        ) ??
        (products.isEmpty ? null : products.first);
  }

  ProductDetails? _androidSubscriptionProduct(
    List<ProductDetails> products, {
    String? basePlanId,
    String? offerTag,
    required bool requiresFreeTrial,
  }) {
    final candidates = <SubscriptionOfferCandidate<ProductDetails>>[];
    for (final product in products.whereType<GooglePlayProductDetails>()) {
      final index = product.subscriptionIndex;
      final offers = product.productDetails.subscriptionOfferDetails;
      if (index == null || offers == null || index >= offers.length) continue;

      final offer = offers[index];
      candidates.add(
        SubscriptionOfferCandidate(
          value: product,
          basePlanId: offer.basePlanId,
          offerId: offer.offerId,
          offerTags: offer.offerTags,
          hasFreeTrial: offer.pricingPhases.any(
            (phase) => phase.priceAmountMicros == 0,
          ),
        ),
      );
    }
    return selectSubscriptionOffer(
      candidates,
      basePlanId: basePlanId,
      offerTag: offerTag,
      requiresFreeTrial: requiresFreeTrial,
    );
  }

  final _inAppPurchase = InAppPurchase.instance;

  Future<void> _listenToPurchaseUpdated(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    if (_disposed) return;
    if (purchaseDetailsList.isEmpty) {
      _infoLog("purchaseDetailsList empty");
      _completeRestoreResult(
        const RestorePurchasesResult(
          status: RestorePurchasesResultStatus.noPurchases,
        ),
      );
      _completeInitialRestoring(source: "empty purchase update");
      return;
    }

    if (purchaseDetailsList.length > 1) {
      purchaseDetailsList.sort((a, b) {
        DateTime dateA =
            parseTransactionDate(a.transactionDate) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        DateTime dateB =
            parseTransactionDate(b.transactionDate) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
    }

    if (kDebugMode) {
      for (PurchaseDetails x in purchaseDetailsList) {
        _infoLog(
          ">>> ${x.productID} ${parseTransactionDate(x.transactionDate)} ${x.pendingCompletePurchase} ${x.purchaseID}",
        );
      }
    }

    for (PurchaseDetails p in purchaseDetailsList) {
      _infoLog(
        "transactionDate: ${p.transactionDate} ${p.status} ${p.productID}",
      );
      switch (p.status) {
        case PurchaseStatus.pending:
          _setPending();
          break;
        case PurchaseStatus.error:
          _purchasePending = false;
          _isBuying = false;
          _handleError(p.error);
          _completeRestoreResult(
            RestorePurchasesResult(
              status: RestorePurchasesResultStatus.failed,
              error: p.error,
            ),
          );
          break;

        case PurchaseStatus.canceled:
          _purchasePending = false;
          _isBuying = false;
          _paymentStatusStreamController.add(PaymentStatus.canceled);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _purchasePending = false;
          _isBuying = false;
          if (!boughtProductIds.contains(p.productID) ||
              _isSubscriptionProductId(p.productID)) {
            if (Platform.isIOS &&
                _iosSubscriptionProductIds.contains(p.productID)) {
              // verification below after list sorting
              break;
            }
            final outcome = await _verifyPurchase(p);
            _handleVerificationOutcome(p, outcome);
          } else {
            _paymentStatusStreamController.add(PaymentStatus.completed);
          }
          break;
      }
    }

    if (Platform.isIOS) {
      final DateTime now = DateTime.now();
      final List iosPurchasesToValidation = _getIosPurchasesToValidation(
        purchaseDetailsList,
      );
      for (PurchaseDetails p in iosPurchasesToValidation) {
        if (_verifyIosSubscriptionsLocally) {
          try {
            final Map<String, dynamic> iosData = jsonDecode(
              p.verificationData.localVerificationData,
            );
            final DateTime expirationTime = DateTime.fromMillisecondsSinceEpoch(
              iosData["expiresDate"],
            );
            if (expirationTime.isAfter(
              now.subtract(_iosSubscriptionExtension),
            )) {
              if (_disposed) return;
              _infoLog(
                "${p.productID} verified from localVerificationData $expirationTime",
              );
              _deliverProduct(p);
              await _storePremiumExpiration(
                cachedProductId: p.productID,
                premiumExpiration: expirationTime,
                lastReceiptValidation: now,
              );
            } else {
              _removeEntitlement(
                p.productID,
                eventType: PaymentEntitlementEventType.expired,
              );
              await _clearCachedPremium(emitEvent: false);
            }
          } catch (e) {
            _errorLog(e);
          }
        } else {
          final outcome = await _verifyPurchase(p);
          _handleVerificationOutcome(p, outcome);
        }
      }
    }

    for (PurchaseDetails p in purchaseDetailsList) {
      if (Platform.isIOS || (Platform.isAndroid && p.pendingCompletePurchase)) {
        await _inAppPurchase.completePurchase(p);
      }
    }
  }

  List<PurchaseDetails> _getIosPurchasesToValidation(
    List<PurchaseDetails> sortedPurchaseDetailsList,
  ) {
    if (sortedPurchaseDetailsList.isEmpty) return [];
    final List<PurchaseDetails> filtered = sortedPurchaseDetailsList
        .where(
          (purchaseDetails) =>
              _iosSubscriptionProductIds.contains(purchaseDetails.productID) &&
              (purchaseDetails.status == PurchaseStatus.purchased ||
                  purchaseDetails.status == PurchaseStatus.restored),
        )
        .toList();
    return filtered;
  }

  DateTime? parseTransactionDate(String? rawDate) {
    if (rawDate == null) return null;

    final millis = int.tryParse(rawDate);
    if (millis != null) {
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }

    try {
      return DateTime.parse(rawDate);
    } catch (_) {
      return null;
    }
  }

  Future<EntitlementVerificationOutcome> _verifyPurchase(
    PurchaseDetails purchaseDetails,
  ) async {
    if (kDebugMode) {
      debugPrint("\n");
      _infoLog(
        "VERIFY PURCHASE purchaseID ${purchaseDetails.purchaseID} productID ${purchaseDetails.productID} status ${purchaseDetails.status} ${purchaseDetails.transactionDate}",
      );
      _infoLog(
        "transactionDate ${parseTransactionDate(purchaseDetails.transactionDate)} pendingCompletePurchase ${purchaseDetails.pendingCompletePurchase}\n",
      );
    }

    return EntitlementVerifier<PurchaseDetails>(
      timeout: _verificationTimeout,
    ).verify(purchaseDetails, _verifyPurchaseCallback);
  }

  void _handleVerificationOutcome(
    PurchaseDetails purchaseDetails,
    EntitlementVerificationOutcome outcome,
  ) {
    if (_disposed) return;
    switch (outcome) {
      case EntitlementVerificationOutcome.verified:
        _deliverProduct(purchaseDetails);
        break;
      case EntitlementVerificationOutcome.invalid:
        _handleInvalidPurchase(purchaseDetails);
        if (purchaseDetails.status == PurchaseStatus.restored) {
          _completeRestoreResult(
            const RestorePurchasesResult(
              status: RestorePurchasesResultStatus.invalidVerification,
            ),
          );
        }
        break;
      case EntitlementVerificationOutcome.error:
        _handleVerificationError(purchaseDetails, outcome);
        _paymentStatusStreamController.add(PaymentStatus.errored);
        if (purchaseDetails.status == PurchaseStatus.restored) {
          _completeRestoreResult(
            RestorePurchasesResult(
              status: RestorePurchasesResultStatus.failed,
              error: StateError(
                'Purchase verification failed: ${purchaseDetails.productID}',
              ),
            ),
          );
        }
        break;
      case EntitlementVerificationOutcome.timedOut:
        _handleVerificationError(purchaseDetails, outcome);
        _paymentStatusStreamController.add(PaymentStatus.errored);
        if (purchaseDetails.status == PurchaseStatus.restored) {
          _completeRestoreResult(
            const RestorePurchasesResult(
              status: RestorePurchasesResultStatus.timedOut,
            ),
          );
        }
        break;
    }
  }

  void _handleVerificationError(
    PurchaseDetails purchaseDetails,
    EntitlementVerificationOutcome outcome,
  ) {
    _errorLog('Purchase verification $outcome: ${purchaseDetails.productID}');
    _addEntitlementEvent(
      PaymentEntitlementEvent(
        productId: purchaseDetails.productID,
        type: PaymentEntitlementEventType.verificationError,
        isSubscription: _isSubscriptionProductId(purchaseDetails.productID),
      ),
    );
  }

  void _deliverProduct(PurchaseDetails purchaseDetails) {
    if (_disposed) return;
    disableInterstitialAd();
    disableRewardedAd();
    disableAppOpenAd();
    _purchasePending = false;
    final wasEntitled = _entitlements.contains(purchaseDetails.productID);
    _purchases.removeWhere(
      (purchase) => purchase.productID == purchaseDetails.productID,
    );
    _purchases.add(purchaseDetails);
    final isSubscription = _isSubscriptionProductId(purchaseDetails.productID);
    _entitlements.grant(
      productId: purchaseDetails.productID,
      purchase: purchaseDetails,
      isSubscription: isSubscription,
      verifiedAt: DateTime.now(),
    );
    if (!wasEntitled) {
      _boughtProductIdsStreamController.add(boughtProductIds.toList());
    }
    _paymentStatusStreamController.add(PaymentStatus.completed);
    _isBuying = false;
    if (!wasEntitled) {
      _addEntitlementEvent(
        PaymentEntitlementEvent(
          productId: purchaseDetails.productID,
          type: purchaseDetails.status == PurchaseStatus.restored
              ? PaymentEntitlementEventType.restored
              : PaymentEntitlementEventType.granted,
          isSubscription: isSubscription,
        ),
      );
    }
    if (purchaseDetails.status == PurchaseStatus.restored && premiumUser) {
      _completeRestoreResult(
        const RestorePurchasesResult(
          status: RestorePurchasesResultStatus.restored,
          hasVerifiedPremium: true,
        ),
      );
    }
    _scheduleEntitlementRevalidation();
    _completeInitialRestoring(source: "_deliverProduct");
  }

  void _deliverCachedProduct(String productId) {
    if (_disposed) return;
    disableInterstitialAd();
    disableRewardedAd();
    disableAppOpenAd();
    _purchasePending = false;
    final wasEntitled = _entitlements.contains(productId);
    _purchases.removeWhere((purchase) => purchase.productID == productId);
    _purchases.add(
      PurchaseDetails(
        productID: productId,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'cachedPurchase',
          serverVerificationData: 'cachedPurchase',
          source: 'cachedPurchase',
        ),
        transactionDate: '',
        status: PurchaseStatus.restored,
      ),
    );
    _entitlements.grant(
      productId: productId,
      purchase: _purchases.last,
      isSubscription: true,
      verifiedAt: DateTime.now(),
    );
    if (!wasEntitled) {
      _boughtProductIdsStreamController.add(boughtProductIds.toList());
    }
    _paymentStatusStreamController.add(PaymentStatus.completed);
    _isBuying = false;
    if (!wasEntitled) {
      _addEntitlementEvent(
        PaymentEntitlementEvent(
          productId: productId,
          type: PaymentEntitlementEventType.restored,
          isSubscription: true,
        ),
      );
    }
    _scheduleEntitlementRevalidation();
    _completeInitialRestoring(source: "_deliverCachedProduct");
  }

  void _handleError(IAPError? error) {
    _purchasePending = false;
    _isBuying = false;
    _errorLog("_handleError $error");
    _paymentStatusStreamController.add(PaymentStatus.errored);
  }

  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    _purchasePending = false;
    _isBuying = false;
    _paymentStatusStreamController.add(PaymentStatus.errored);
    _addEntitlementEvent(
      PaymentEntitlementEvent(
        productId: purchaseDetails.productID,
        type: PaymentEntitlementEventType.invalidVerification,
        isSubscription: _isSubscriptionProductId(purchaseDetails.productID),
      ),
    );
    _removeEntitlement(purchaseDetails.productID);
    _errorLog("Purchase verification failed: ${purchaseDetails.productID}");
  }

  void _setPending() {
    _purchasePending = true;
    _paymentStatusStreamController.add(PaymentStatus.pending);
  }

  bool _delegateSet = false;

  Future<void> loadProducts() async {
    if (!_productIdsProvided) {
      throw ArgumentError(
        "Product ids not provided. Use PaymentService.initParameters",
      );
    }
    _loading = true;
    _queryProductError = null;
    try {
      _isAvailable = await _inAppPurchase.isAvailable();
      if (!_isAvailable) return;

      final response = await _inAppPurchase.queryProductDetails(_allProductIds);

      _allProducts = response.productDetails;
      _notFoundIds = response.notFoundIDs;
      _iosTrialProducts.clear();
      if (Platform.isIOS) {
        await _loadIosTrialProducts(response.productDetails);
      }

      if (response.error != null) {
        _queryProductError = response.error!.message;
        _handleError(response.error);
        return;
      }

      _infoLog("productDetails: ${_allProducts.length}");
      _infoLog("notFoundIDs: ${_notFoundIds.length}");
      for (final element in _allProducts) {
        _infoLog("${element.id} ${element.price}");
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _loadIosTrialProducts(
    List<ProductDetails> productDetails,
  ) async {
    if (!Platform.isIOS) return;
    await Future.wait(
      productDetails.map((p) async {
        try {
          if (p is AppStoreProduct2Details) {
            if (p.sk2Product.type != SK2ProductType.autoRenewable) return;
            final eligible = await SK2Product.isIntroductoryOfferEligible(p.id);
            if (eligible) _iosTrialProducts.add(p);
          }
        } on PlatformException catch (e) {
          _errorLog('_loadIosTrialProducts $e');
        }
      }),
    );
  }

  void _completeInitialRestoring({
    bool timeout = false,
    required String source,
  }) {
    if (!_stopWaitingForInitialRestoringCompleter.isCompleted) {
      _infoLog("_completeInitialRestoring: $source");
      _initialRestoringTimeouted = timeout;
      _stopWaitingForInitialRestoringCompleter.complete();
    }
  }

  bool get initialRestoringTimeouted => _initialRestoringTimeouted;
  bool _initialRestoringTimeouted = false;

  /// Returns whether the store accepted the restore request. For the verified
  /// entitlement outcome, use [restorePurchasesWithResult] or
  /// [restorePurchasesResultStream].
  Future<bool> restorePurchases() async {
    if (_disposed) return false;
    _startRestoreResultTracking();
    return _requestRestorePurchases();
  }

  Future<bool> _requestRestorePurchases() async {
    if (!_productIdsProvided) {
      throw ArgumentError(
        "[PaymentService] ERROR: Product ids not provided. Use PaymentService.initParameters",
      );
    }
    try {
      _infoLog(
        "restorePurchases STARTED with products: ${_allProducts.length}",
      );
      final start = DateTime.now().millisecondsSinceEpoch;
      await _inAppPurchase.restorePurchases();
      final end = DateTime.now().millisecondsSinceEpoch;
      _infoLog("restorePurchases took ${end - start}ms");
      return true;
    } catch (e) {
      _completeInitialRestoring(source: "restorePurchases error");
      _completeRestoreResult(
        RestorePurchasesResult(
          status: RestorePurchasesResultStatus.failed,
          error: e,
        ),
      );
      _errorLog(e);
      if (e is SKError) {
        _errorLog("restorePurchases ${e.code} ${e.domain} ${e.userInfo}");
      }
      return false;
    }
  }

  /// Waits for the store updates triggered by a restore request and reports
  /// whether a *verified* premium entitlement was restored.
  Future<RestorePurchasesResult> restorePurchasesWithResult({
    Duration? timeout,
  }) {
    final resultCompleter = Completer<RestorePurchasesResult>();
    _restoreWithResultQueue = _restoreWithResultQueue.then((_) async {
      await _runRestorePurchasesWithResult(
        timeout,
        resultCompleter: resultCompleter,
      );
    });
    return resultCompleter.future;
  }

  Future<void> _runRestorePurchasesWithResult(
    Duration? timeout, {
    required Completer<RestorePurchasesResult> resultCompleter,
  }) async {
    if (_disposed) {
      resultCompleter.complete(
        RestorePurchasesResult(
          status: RestorePurchasesResultStatus.failed,
          error: StateError('PaymentService has been disposed.'),
        ),
      );
      return;
    }
    final activeCycle = _restoreResultCompleter;
    if (activeCycle != null && !activeCycle.isCompleted) {
      await activeCycle.future;
    }
    if (_disposed) {
      resultCompleter.complete(
        RestorePurchasesResult(
          status: RestorePurchasesResultStatus.failed,
          error: StateError('PaymentService has been disposed.'),
        ),
      );
      return;
    }
    _startRestoreResultTracking(timeout: timeout, forceNew: true);
    final cycleCompleter = _restoreResultCompleter!;
    unawaited(
      cycleCompleter.future.then((result) {
        if (!resultCompleter.isCompleted) resultCompleter.complete(result);
      }),
    );
    try {
      await _requestRestorePurchases();
    } catch (error) {
      _completeRestoreResult(
        RestorePurchasesResult(
          status: RestorePurchasesResultStatus.failed,
          error: error,
        ),
      );
    }
    await cycleCompleter.future;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _entitlementLifecycleGeneration += 1;
    if (!_entitlementLifecycleStop.isCompleted) {
      _entitlementLifecycleStop.complete();
    }
    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase
              .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      iosPlatformAddition.setDelegate(null);
      _delegateSet = false;
    }
    _subscription?.cancel();
    _entitlementRevalidationTimer?.cancel();
    _restoreResultTimer?.cancel();
    _completeRestoreResult(
      RestorePurchasesResult(
        status: RestorePurchasesResultStatus.failed,
        error: StateError('PaymentService has been disposed.'),
      ),
    );
    _boughtProductIdsStreamController.close();
    _paymentStatusStreamController.close();
    _entitlementEventStreamController.close();
    _restorePurchasesResultStreamController.close();
  }

  /// wait for PurchaseStatus.restored no longer than _restoringOnStartTicks * 100ms
  Future<void> waitForPurchaseRestoring() async {
    if (_stopWaitingForInitialRestoringCompleter.isCompleted) return;
    final limit = Duration(milliseconds: _restoringOnStartTicks * 100);
    try {
      await _stopWaitingForInitialRestoringCompleter.future.timeout(limit);
    } on TimeoutException {
      _completeInitialRestoring(timeout: true, source: "timeout");
    }
  }

  Future<void> reloadPurchases() async {
    try {
      final int time1 = DateTime.now().millisecondsSinceEpoch;
      await loadProducts();
      await restorePurchases();
      final int time2 = DateTime.now().millisecondsSinceEpoch;
      _infoLog("reloadPurchases in ${time2 - time1}ms");
    } catch (e) {
      _errorLog(e);
      if (e is SKError) {
        _errorLog("reloadPurchases ${e.code} ${e.domain} ${e.userInfo}");
      }
    }
  }

  Future<void> buyNonConsumable(ProductDetails productDetails) async {
    if (_isBuying) {
      _infoLog('_isBuying:$_isBuying');
      return;
    }

    _isBuying = true;
    try {
      _infoLog(
        "buyNonConsumable: ${productDetails.runtimeType} ${productDetails.id}",
      );
      final purchaseParam = productDetails is GooglePlayProductDetails
          ? GooglePlayPurchaseParam(
              productDetails: productDetails,
              offerToken: productDetails.offerToken,
            )
          : PurchaseParam(productDetails: productDetails);
      final started = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      if (!started) {
        _isBuying = false;
        _paymentStatusStreamController.add(PaymentStatus.errored);
      }
    } catch (e) {
      _isBuying = false;
      if (e is PlatformException) {
        if (e.code.contains('cancelled')) {
          _paymentStatusStreamController.add(PaymentStatus.canceled);
        } else {
          _paymentStatusStreamController.add(PaymentStatus.errored);
        }
      }
      _errorLog("buyNonConsumable $e");
    }
  }

  bool get hasProducts => _filterActiveProducts(_allProducts).isNotEmpty;

  List<ProductDetails> _filterActiveProducts(List<ProductDetails> products) =>
      products
          .where((element) => _activeProductIds.contains(element.id))
          .toList();

  List<PurchaseDetails> _filterPremiumPurchases(
    List<PurchaseDetails> purchases,
  ) => purchases
      .where((element) => _premiumProductIds.contains(element.productID))
      .toList();

  bool _isSubscriptionProductId(String productId) {
    if (_iosSubscriptionProductIds.contains(productId)) return true;
    return _allProducts.whereType<GooglePlayProductDetails>().any(
      (product) =>
          product.id == productId &&
          product.productDetails.subscriptionOfferDetails != null,
    );
  }

  void _startRestoreResultTracking({Duration? timeout, bool forceNew = false}) {
    if (_restoreResultCompleter != null &&
        !_restoreResultCompleter!.isCompleted &&
        !forceNew) {
      return;
    }
    _restoreResultTimer?.cancel();
    _restoreResultCompleter = Completer<RestorePurchasesResult>();
    _restorePurchasesResultStreamController.add(
      const RestorePurchasesResult(
        status: RestorePurchasesResultStatus.inProgress,
      ),
    );
    _restoreResultTimer = Timer(
      timeout ?? Duration(milliseconds: _restoringOnStartTicks * 100),
      () => _completeRestoreResult(
        const RestorePurchasesResult(
          status: RestorePurchasesResultStatus.timedOut,
        ),
      ),
    );
  }

  void _completeRestoreResult(RestorePurchasesResult result) {
    final completer = _restoreResultCompleter;
    if (completer == null || completer.isCompleted) return;
    _restoreResultTimer?.cancel();
    completer.complete(result);
    if (!_restorePurchasesResultStreamController.isClosed) {
      _restorePurchasesResultStreamController.add(result);
    }
  }

  void _scheduleEntitlementRevalidation() {
    _entitlementRevalidationTimer?.cancel();
    if (_disposed ||
        _entitlementRevalidationInProgress ||
        !_entitlements.records.any((record) => record.isSubscription)) {
      return;
    }
    final generation = _entitlementLifecycleGeneration;
    _entitlementRevalidationTimer = Timer(_receiptValidationChecking, () {
      if (_disposed || generation != _entitlementLifecycleGeneration) return;
      unawaited(_revalidateEntitlements(generation));
    });
  }

  /// Re-checks only verified subscriptions. One-time non-consumables stay
  /// active after their original successful verification.
  Future<void> revalidateEntitlements() =>
      _revalidateEntitlements(_entitlementLifecycleGeneration);

  Future<void> _revalidateEntitlements(int generation) async {
    if (_disposed ||
        _entitlementRevalidationInProgress ||
        generation != _entitlementLifecycleGeneration) {
      return;
    }
    _entitlementRevalidationInProgress = true;
    final now = DateTime.now();
    final due = _entitlements
        .subscriptionsDueForVerification(now, _receiptValidationChecking)
        .toList();
    try {
      for (final record in due) {
        final outcome = await Future.any<EntitlementVerificationOutcome?>([
          _verifyPurchase(record.purchase),
          _entitlementLifecycleStop.future.then((_) => null),
        ]);
        if (outcome == null) return;
        if (_disposed || generation != _entitlementLifecycleGeneration) return;
        if (outcome == EntitlementVerificationOutcome.error ||
            outcome == EntitlementVerificationOutcome.timedOut) {
          _handleVerificationError(record.purchase, outcome);
        }
        switch (outcome) {
          case EntitlementVerificationOutcome.verified:
            _entitlements.grant(
              productId: record.productId,
              purchase: record.purchase,
              isSubscription: true,
              verifiedAt: DateTime.now(),
            );
            break;
          case EntitlementVerificationOutcome.invalid:
            _removeEntitlement(record.productId);
            break;
          case EntitlementVerificationOutcome.error:
          case EntitlementVerificationOutcome.timedOut:
            // A transport/backend failure is not a negative verification.
            // Keep the last verified entitlement and retry on the next cycle.
            break;
        }
      }
    } finally {
      _entitlementRevalidationInProgress = false;
      if (!_disposed) {
        _scheduleEntitlementRevalidation();
      }
    }
  }

  void _removeEntitlement(
    String productId, {
    PaymentEntitlementEventType eventType = PaymentEntitlementEventType.revoked,
  }) {
    if (_disposed) return;
    final record = _entitlements.revoke(productId);
    if (record == null) return;
    _purchases.removeWhere((purchase) => purchase.productID == productId);
    _boughtProductIdsStreamController.add(boughtProductIds.toList());
    _addEntitlementEvent(
      PaymentEntitlementEvent(
        productId: productId,
        type: eventType,
        isSubscription: record.isSubscription,
      ),
    );
    if (!premiumUser) {
      // The ad services retain the UMP request gate, so enabling a format here
      // never bypasses withdrawn or unavailable consent.
      enableInterstitialAd();
      enableRewardedAd();
      enableAppOpenAd();
    }
  }

  void _addEntitlementEvent(PaymentEntitlementEvent event) {
    if (!_disposed && !_entitlementEventStreamController.isClosed) {
      _entitlementEventStreamController.add(event);
    }
  }

  static const String _cachedProductIdKey = "cachedProductId";
  static const String _premiumExpirationMillisKey = "premiumExpirationMillis";
  static const String _lastReceiptValidationMillisKey =
      "lastReceiptValidationMillis";
  Future<void> _storePremiumExpiration({
    required String cachedProductId,
    required DateTime premiumExpiration,
    required DateTime lastReceiptValidation,
  }) async {
    _cachedProductId = cachedProductId;
    _premiumExpiration = premiumExpiration;
    _lastReceiptValidation = lastReceiptValidation;

    final List<Future<void>> futures = [
      _secure.write(
        key: _premiumExpirationMillisKey,
        value: premiumExpiration.millisecondsSinceEpoch.toString(),
      ),
      _secure.write(
        key: _lastReceiptValidationMillisKey,
        value: lastReceiptValidation.millisecondsSinceEpoch.toString(),
      ),
      _secure.write(key: _cachedProductIdKey, value: cachedProductId),
    ];

    await Future.wait(futures);
  }

  Future<void> _clearCachedPremium({bool emitEvent = true}) async {
    final expiredProductId = _cachedProductId;
    _cachedProductId = null;
    _premiumExpiration = null;
    _lastReceiptValidation = null;
    await Future.wait([
      _secure.delete(key: _premiumExpirationMillisKey),
      _secure.delete(key: _lastReceiptValidationMillisKey),
      _secure.delete(key: _cachedProductIdKey),
    ]);
    if (emitEvent && expiredProductId != null) {
      _addEntitlementEvent(
        PaymentEntitlementEvent(
          productId: expiredProductId,
          type: PaymentEntitlementEventType.expired,
          isSubscription: true,
        ),
      );
    }
  }
}

/// [`SKPaymentQueueDelegate`](https://developer.apple.com/documentation/storekit/skpaymentqueuedelegate?language=objc).
///
/// The payment queue delegate can be implementated to provide information
/// needed to complete transactions.
///
/// source: (https://github.com/flutter/packages/blob/main/packages/in_app_purchase/in_app_purchase_storekit/example/lib/example_payment_queue_delegate.dart)
class SKPaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(
    SKPaymentTransactionWrapper transaction,
    SKStorefrontWrapper storefront,
  ) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return true;
  }
}

void _infoLog(Object? object) {
  if (!kDebugMode) return;
  printY("[PaymentService] $object");
}

void _errorLog(Object? object) {
  if (!kDebugMode) return;
  printR("[PaymentService] ⚠️ ERROR $object");
}
