import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'interstitial_ad.dart';
import 'utils.dart';

const bool kInitialPremiumUser = false;

/// - idle
/// - pending
/// - completed
/// - canceled
/// - errored
enum PaymentStatus { idle, pending, completed, canceled, errored }

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
    printW("[DEV-LOG] PaymentService constructor");
    if (kInitialPremiumUser) {
      disableInterstitialAd();
    } else {
      enableInterstitialAd();
    }

    _boughtProductIdsStreamController = StreamController<List<String>>()..add(boughtProductIds);
    _paymentStatusStreamController = StreamController<PaymentStatus>()..add(PaymentStatus.idle);

    _subscription = _inAppPurchase.purchaseStream.listen(
      _listenToPurchaseUpdated,
      onDone: () {
        printY("[DEV-LOG] [PaymentService listener] onDone");
        _subscription.cancel();
      },
      onError: (error) {
        printR("[DEV-LOG] [PaymentService listener] onError");
        printR(error);
        // handle error here.
      },
    );
  }

  PaymentVerifyCallback _verifyPurchaseCallbackAlwaysTrue = (_) => Future<bool>.value(true);

  bool _productIdsProvided = false;
  Set<String> _activeProductIds = {};
  Set<String> _iosSubscriptionProductIds = {};
  Set<String> _allProductIds = {};
  Set<String> _premiumProductIds = {};
  int _restoringOnStartTicks = 5;

  // PurchaseDetails.purchaseID changes between app launches so cannot be used
  String? _cachedProductId;
  DateTime? _premiumExpiration;
  DateTime? _lastReceiptValidation;
  Duration _receiptValidationChecking = Duration(hours: 1);
  Duration get receiptValidationChecking => _receiptValidationChecking;
  Duration _iosSubscriptionExtension = Duration(days: 0);
  Duration get iosSubscriptionExtension => _iosSubscriptionExtension;

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
    Duration? iosSubscriptionExtension,
    PaymentVerifyCallback? verifyPurchaseCallback,
    int restoringOnStartTicks = 5,
  }) async {
    _activeProductIds = activeProductIds;
    _iosSubscriptionProductIds = iosSubscriptionProductIds;
    _allProductIds = allProductIds;
    _premiumProductIds = premiumProductIds;
    _restoringOnStartTicks = restoringOnStartTicks;
    if (verifyPurchaseCallback != null) _verifyPurchaseCallbackAlwaysTrue = verifyPurchaseCallback;
    _receiptValidationChecking = receiptValidationChecking ?? _receiptValidationChecking;
    _iosSubscriptionExtension = iosSubscriptionExtension ?? _iosSubscriptionExtension;
    _productIdsProvided = true;
    if (Platform.isIOS) {
      final prefs = await SharedPreferences.getInstance();
      final int? premiumExpirationMillis = prefs.getInt(_premiumExpirationMillisKey);
      _premiumExpiration = premiumExpirationMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(premiumExpirationMillis, isUtc: true);
      final int? lastReceiptValidationMillis = prefs.getInt(_lastReceiptValidationMillisKey);
      _lastReceiptValidation = lastReceiptValidationMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastReceiptValidationMillis, isUtc: true);
      _cachedProductId = prefs.getString(_cachedProductIdKey);
      printY(
        "[DEV-LOG] [PaymentService] lastReceiptValidation:$_lastReceiptValidation premiumExpiration:$_premiumExpiration cachedProductId:$_cachedProductId",
      );
      if (_cachedProductId != null && _premiumExpiration!.isAfter(DateTime.now())) {
        printY("[DEV-LOG] [PaymentService] deliverCachedProduct cachedProductId:$_cachedProductId");
        _deliverCachedProduct(_cachedProductId!);
      }
    }
  }

  late StreamSubscription<List<PurchaseDetails>> _subscription;

  /// flag to wait for
  bool _restoreExecuted = false;
  List<ProductDetails> _allProducts = <ProductDetails>[];
  List<String> _notFoundIds = <String>[];
  final List<PurchaseDetails> _purchases = <PurchaseDetails>[];
  bool _isAvailable = false;
  bool _purchasePending = false;
  bool _loading = true;
  bool _isBuying = false;
  String? _queryProductError;

  bool get premiumUser => _filterPremiumPurchases(_purchases).isNotEmpty;
  List<ProductDetails> get activeProducts => _filterActiveProducts(_allProducts);
  List<String> get notFoundIds => _notFoundIds;
  List<PurchaseDetails> get purchases => _purchases;
  List<String> get boughtProductIds => _purchases.map((p) => p.productID).toList();
  bool get isAvailable => _isAvailable;
  bool get purchasePending => _purchasePending;
  bool get loading => _loading;
  String? get queryProductError => _queryProductError;

  late StreamController<List<String>> _boughtProductIdsStreamController;
  late StreamController<PaymentStatus> _paymentStatusStreamController;
  Stream<List<String>> get boughtProductIdsStream => _boughtProductIdsStreamController.stream;
  Stream<PaymentStatus> get paymentStatusStream => _paymentStatusStreamController.stream;

  ProductDetails? trialProductById(String id) {
    final List<ProductDetails> prods = _allProducts.where((p) => p.id == id).toList();
    if (Platform.isIOS && prods.length == 1) return prods[0];
    if (prods.length == 2) return prods[0];
    return null;
  }

  ProductDetails? productById(String id) {
    final List<ProductDetails> prods = _allProducts.where((p) => p.id == id).toList();
    if (prods.length == 2) return prods[1];
    if (prods.length == 1) return prods[0];
    return null;
  }

  final _inAppPurchase = InAppPurchase.instance;

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    if (purchaseDetailsList.isEmpty) return;

    for (PurchaseDetails p in purchaseDetailsList) {
      if (_iosSubscriptionProductIds.contains(p.productID)) continue;
      printR("[DEV-LOG] [PaymentService] transactionDate: ${p.transactionDate} ${p.status} ${p.productID}");
      switch (p.status) {
        case PurchaseStatus.pending:
          _setPending();
          break;
        case PurchaseStatus.error:
          _isBuying = false;
          _handleError(p.error);
          break;

        case PurchaseStatus.canceled:
          _isBuying = false;
          _paymentStatusStreamController.add(PaymentStatus.canceled);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _isBuying = false;
          if (!boughtProductIds.contains(p.productID)) {
            if (Platform.isIOS && _iosSubscriptionProductIds.contains(p.productID)) {
              // verification below after list sorting
              break;
            }
            final valid = await _verifyPurchase(p);
            if (valid) {
              _deliverProduct(p);
            } else {
              _handleInvalidPurchase(p);
              break;
            }
          } else {
            _paymentStatusStreamController.add(PaymentStatus.completed);
          }
          break;
      }
    }

    if (purchaseDetailsList.length > 1) {
      purchaseDetailsList.sort((a, b) {
        DateTime dateA = parseTransactionDate(a.transactionDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
        DateTime dateB = parseTransactionDate(b.transactionDate) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return dateB.compareTo(dateA);
      });
    }

    if (kDebugMode) {
      for (PurchaseDetails x in purchaseDetailsList) {
        printY(
          "[DEV-LOG] [PaymentService]> ${x.productID} ${parseTransactionDate(x.transactionDate)} ${x.pendingCompletePurchase} ${x.purchaseID}",
        );
      }
    }

    final PurchaseDetails? iosSubPurchaseDetails = _getIosPurchaseToRemoteValidation(purchaseDetailsList);

    if (iosSubPurchaseDetails != null) {
      _isBuying = false;
      if (!boughtProductIds.contains(iosSubPurchaseDetails.productID)) {
        final valid = await _verifyIosSubscriptionPurchase(iosSubPurchaseDetails);
        if (valid) {
          _deliverProduct(iosSubPurchaseDetails);
        } else {
          _handleInvalidPurchase(iosSubPurchaseDetails);
        }
      } else {
        _paymentStatusStreamController.add(PaymentStatus.completed);
      }
    }

    for (PurchaseDetails p in purchaseDetailsList) {
      if (p.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(p);
      }
    }
  }

  PurchaseDetails? _getIosPurchaseToRemoteValidation(List<PurchaseDetails> sortedPurchaseDetailsList) {
    List<PurchaseDetails> filtered = sortedPurchaseDetailsList
        .where(
          (purchaseDetails) =>
              _iosSubscriptionProductIds.contains(purchaseDetails.productID) &&
              (purchaseDetails.status == PurchaseStatus.purchased || purchaseDetails.status == PurchaseStatus.restored),
        )
        .toList();

    if (filtered.isEmpty) return null;
    return filtered.first;
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

  Future<bool> _verifyIosSubscriptionPurchase(PurchaseDetails purchaseDetails) async {
    if (Platform.isIOS && _iosSubscriptionProductIds.contains(purchaseDetails.productID)) {
      printY(
        "[DEV-LOG] [PaymentService] purchaseID${purchaseDetails.purchaseID} _premiumExpiration $_premiumExpiration",
      );
      final now = DateTime.now();
      bool subscriptionExtended = false;
      if (_lastReceiptValidation != null &&
          DateTime.now().difference(_lastReceiptValidation!) < _receiptValidationChecking &&
          _premiumExpiration != null) {
        if (_premiumExpiration!.isAfter(now)) {
          printY(
            "[DEV-LOG] [PaymentService] ${purchaseDetails.productID} verified from local db ${now.difference(_lastReceiptValidation!)}",
          );
          return true;
        } else if (_premiumExpiration!.isAfter(now.subtract(_iosSubscriptionExtension))) {
          subscriptionExtended = true;
          printY(
            "[DEV-LOG] [PaymentService] ${purchaseDetails.productID} verified from local db ${now.difference(_lastReceiptValidation!)}",
          );
        }
      }

      // refresh payment verification but approve payment if it expired before subscription extension
      final bool expiredOrExtended = false || subscriptionExtended;
      try {
        const String url = 'https://apis.netigen.eu/api/payments/appstore2';
        final int beforeFetch = DateTime.now().millisecondsSinceEpoch;

        // TODO: add localVerification
        // printY("localVerificationData: ${purchaseDetails.verificationData.localVerificationData}");
        // final Map<String, dynamic> localVerificationData = json.decode(
        //   purchaseDetails.verificationData.localVerificationData,
        // );
        // final DateTime expiresDate = DateTime.fromMillisecondsSinceEpoch(localVerificationData["expiresDate"]);
        // printR("expiresDate $expiresDate expired:${now.isAfter(expiresDate)} now:$now");
        // if (now.isAfter(expiresDate)) return false;

        final response = await http.post(
          Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'jws': purchaseDetails.verificationData.serverVerificationData}),
        );

        if (response.statusCode == 200) {
          final responseData = jsonDecode(response.body);
          printW(
            '[DEV-LOG] [PaymentService] payment verification response $responseData in ${DateTime.now().millisecondsSinceEpoch - beforeFetch}ms',
          );
          final DateTime expirationTime = DateTime.fromMillisecondsSinceEpoch(
            int.parse(responseData['data']['expiresDateMs']),
            isUtc: true,
          );
          final bool notExpired = now.isBefore(expirationTime);
          if (kDebugMode) {
            printY(
              '[DEV-LOG] [PaymentService] ${notExpired ? "notExpired" : "expired"} ${now.toIso8601String()}(now) ${notExpired ? "<" : ">"} ${expirationTime.toIso8601String()}(exp) ${purchaseDetails.purchaseID}',
            );
          }
          _storePremiumExpiration(
            cachedProductId: purchaseDetails.productID,
            premiumExpiration: expirationTime,
            lastReceiptValidation: now,
          );
          return notExpired || subscriptionExtended;
        } else {
          if (response.statusCode == 400) {
            _storePremiumExpiration(cachedProductId: null, premiumExpiration: null, lastReceiptValidation: null);
          }
          printY('[DEV-LOG] [PaymentService] payment verification ${response.statusCode} ${response.body}');
          return expiredOrExtended;
        }
      } catch (e) {
        printR("[DEV-LOG] [PaymentService] payment verification error: $e");
        return expiredOrExtended;
      }
    }
    return false;
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    if (kDebugMode) {
      printY("\n");
      printY(
        "[DEV-LOG] [PaymentService] VERIFY PURCHASE purchaseID ${purchaseDetails.purchaseID} productID ${purchaseDetails.productID} status ${purchaseDetails.status} ${purchaseDetails.transactionDate}",
      );
      printY(
        "[DEV-LOG] [PaymentService] transactionDate ${parseTransactionDate(purchaseDetails.transactionDate)} pendingCompletePurchase ${purchaseDetails.pendingCompletePurchase}\n",
      );
    }

    if (Platform.isIOS && _iosSubscriptionProductIds.contains(purchaseDetails.productID)) {
      return false;
    }

    // android
    final bool verified = await _verifyPurchaseCallbackAlwaysTrue(purchaseDetails);
    return verified;
    // return Future<bool>.value(true);
  }

  void _deliverProduct(PurchaseDetails purchaseDetails) {
    disableInterstitialAd();
    _purchases.add(purchaseDetails);
    _boughtProductIdsStreamController.add(boughtProductIds);
    _paymentStatusStreamController.add(PaymentStatus.completed);
  }

  void _deliverCachedProduct(String productId) {
    disableInterstitialAd();
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
    _boughtProductIdsStreamController.add(boughtProductIds);
    _paymentStatusStreamController.add(PaymentStatus.completed);
  }

  void _handleError(IAPError? error) {
    printR("[DEV-LOG] [PaymentService] _handleError code:${error?.code} message:${error?.message}");
    _paymentStatusStreamController.add(PaymentStatus.errored);
  }

  void _handleInvalidPurchase(PurchaseDetails purchaseDetails) {
    _paymentStatusStreamController.add(PaymentStatus.errored);
    printY("[DEV-LOG] [PaymentService] _handleInvalidPurchase (NOT IMPLEMENTED) ${purchaseDetails.productID}");
  }

  void _setPending() {
    _purchasePending = true;
    _paymentStatusStreamController.add(PaymentStatus.pending);
  }

  bool _delegateSet = false;

  Future<void> loadProducts() async {
    if (!_productIdsProvided) {
      throw ArgumentError(
        "[DEV-LOG] [PaymentService] ERROR: Product ids not provided. Use PaymentService.initParameters",
      );
    }
    _isAvailable = await _inAppPurchase.isAvailable();
    if (!_isAvailable) {
      _loading = false;
      return;
    }

    if (Platform.isIOS && !_delegateSet) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.setDelegate(ExamplePaymentQueueDelegate());
      _delegateSet = true;
    }

    final response = await _inAppPurchase.queryProductDetails(_allProductIds);

    if (response.error != null) {
      printR(response.error);
      _loading = false;
      _queryProductError = response.error!.message;
      _allProducts = response.productDetails;
      _notFoundIds = response.notFoundIDs;
      return;
    }

    _allProducts = response.productDetails;
    _notFoundIds = response.notFoundIDs;
    printM("productDetails: ${_allProducts.length}");
    printM("notFoundIDs: ${_notFoundIds.length}");
    for (var element in _allProducts) {
      printM("${element.id} ${element.price}");
    }
  }

  /// return bool if restore is successfull
  Future<bool> restorePurchases() async {
    if (!_productIdsProvided) {
      throw ArgumentError(
        "[DEV-LOG] [PaymentService] ERROR: Product ids not provided. Use PaymentService.initParameters",
      );
    }
    try {
      printY("[DEV-LOG] PaymentService.restorePurchases STARTED with products: ${_allProducts.length}");
      final start = DateTime.now().millisecondsSinceEpoch;
      await _inAppPurchase.restorePurchases();
      final end = DateTime.now().millisecondsSinceEpoch;
      printY("[DEV-LOG] PaymentService.restorePurchases took ${end - start}ms");
      return true;
    } catch (e) {
      printY(e);
      if (e is SKError) printR("restorePurchases ${e.code} ${e.domain} ${e.userInfo}");
      return false;
    }
  }

  void dispose() {
    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      iosPlatformAddition.setDelegate(null);
    }
    _subscription.cancel();
    _boughtProductIdsStreamController.close();
    _paymentStatusStreamController.close();
  }

  /// wait for PurchaseStatus.restored no longer than _restoringOnStartTicks * 100ms
  Future<void> waitForPurchaseRestoring() async {
    printY("[DEV-LOG] PaymentService.checkPremiumUserOnStart STARTED");
    int tick = 0;
    final start = DateTime.now().millisecondsSinceEpoch;
    await Future.doWhile(
      () => Future.delayed(const Duration(milliseconds: 100), () {
        tick++;
        printY("[DEV-LOG] waiting for checkPremiumUserOnStart ${tick * 100}ms");
        if (tick >= _restoringOnStartTicks) _restoreExecuted = true;
      }).then((_) => !_restoreExecuted),
    );
    final end = DateTime.now().millisecondsSinceEpoch;

    printY("[DEV-LOG] PaymentService.checkPremiumUserOnStart took ${end - start}ms");
  }

  Future<void> reloadPurchases() async {
    try {
      final int time1 = DateTime.now().millisecondsSinceEpoch;
      await loadProducts();
      await restorePurchases();
      final int time2 = DateTime.now().millisecondsSinceEpoch;
      printY("[DEV-LOG] reloadPurchases in ${time2 - time1}ms");
    } catch (e) {
      printY(e);
      if (e is SKError) printR("reloadPurchases ${e.code} ${e.domain} ${e.userInfo}");
    }
  }

  void buyNonConsumable(ProductDetails productDetails) {
    if (!_isBuying) {
      _isBuying = true;
      try {
        printY("buyNonConsumable: $productDetails");
        _inAppPurchase.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: productDetails));
      } catch (e) {
        _isBuying = false;
        printR("[DEV-LOG] [PaymentService] buyNonConsumable.error $e");
      }
    } else {
      printY("[DEV-LOG] [PaymentService] _isBuying:$_isBuying");
    }
  }

  bool get hasProducts => _filterActiveProducts(_allProducts).isNotEmpty;

  List<ProductDetails> _filterActiveProducts(List<ProductDetails> products) =>
      products.where((element) => _activeProductIds.contains(element.id)).toList();

  List<PurchaseDetails> _filterPremiumPurchases(List<PurchaseDetails> purchases) =>
      purchases.where((element) => _premiumProductIds.contains(element.productID)).toList();

  final String _cachedProductIdKey = "cachedProductId";
  final String _premiumExpirationMillisKey = "premiumExpirationMillis";
  final String _lastReceiptValidationMillisKey = "lastReceiptValidationMillis";
  Future<void> _storePremiumExpiration({
    required String? cachedProductId,
    required DateTime? premiumExpiration,
    required DateTime? lastReceiptValidation,
  }) async {
    _cachedProductId = cachedProductId;
    _premiumExpiration = premiumExpiration;
    _lastReceiptValidation = lastReceiptValidation;
    final prefs = await SharedPreferences.getInstance();
    if (premiumExpiration == null) {
      prefs.remove(_premiumExpirationMillisKey);
    } else {
      prefs.setInt(_premiumExpirationMillisKey, premiumExpiration.millisecondsSinceEpoch);
    }
    if (lastReceiptValidation == null) {
      prefs.remove(_lastReceiptValidationMillisKey);
    } else {
      prefs.setInt(_lastReceiptValidationMillisKey, lastReceiptValidation.millisecondsSinceEpoch);
    }
    if (cachedProductId == null) {
      prefs.remove(_cachedProductIdKey);
    } else {
      prefs.setString(_cachedProductIdKey, cachedProductId);
    }
  }
}

/// Example implementation of the
/// [`SKPaymentQueueDelegate`](https://developer.apple.com/documentation/storekit/skpaymentqueuedelegate?language=objc).
///
/// The payment queue delegate can be implementated to provide information
/// needed to complete transactions.
class ExamplePaymentQueueDelegate implements SKPaymentQueueDelegateWrapper {
  @override
  bool shouldContinueTransaction(SKPaymentTransactionWrapper transaction, SKStorefrontWrapper storefront) {
    return true;
  }

  @override
  bool shouldShowPriceConsent() {
    return true;
  }
}
