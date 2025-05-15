import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';

import 'interstitial_ad.dart';
import 'utils.dart';

const bool kInitialPremiumUser = false;

/// - idle
/// - pending
/// - completed
/// - canceled
/// - errored
enum PaymentStatus {
  idle,
  pending,
  completed,
  canceled,
  errored,
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

  PaymentVerifyCallback _verifyPurchaseCallback = (_) => Future<bool>.value(true);

  bool _productIdsProvided = false;
  Set<String> _activeProductIds = {};
  Set<String> _allProductIds = {};
  Set<String> _premiumProductIds = {};
  int _restoringOnStartTicks = 5;

  /// - [activeProductIds] - all products that could be bought in app at this moment
  /// - [allProductIds] - all products to restoring (also depracated)
  /// - [premiumProductIds] - all products where [premiumUser] == true
  /// - [restoringOnStartTicks] - times 100ms is the maximum time of purchases restoring on start; 5 means 500ms
  void initParameters({
    required Set<String> activeProductIds,
    required Set<String> allProductIds,
    required Set<String> premiumProductIds,
    PaymentVerifyCallback? verifyPurchaseCallback,
    int restoringOnStartTicks = 5,
  }) {
    _activeProductIds = activeProductIds;
    _allProductIds = allProductIds;
    _premiumProductIds = premiumProductIds;
    _restoringOnStartTicks = restoringOnStartTicks;
    if (verifyPurchaseCallback != null) _verifyPurchaseCallback = verifyPurchaseCallback;
    _productIdsProvided = true;
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

  List<PurchaseDetails> _purchaseDetailsList = [];

  Future<void> completePendingPurchases() async {
    for (PurchaseDetails p in _purchaseDetailsList) {
      if (p.pendingCompletePurchase) {
        if (kDebugMode) {
          printY(
            "[DEV-LOG] [PaymentService] pendingCompletePurchase for ${DateTime.fromMillisecondsSinceEpoch(int.parse(p.transactionDate ?? "0")).toIso8601String()}",
          );
        }
        await _inAppPurchase.completePurchase(p);
      }
    }
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    _purchaseDetailsList = purchaseDetailsList;
    for (PurchaseDetails p in purchaseDetailsList) {
      if (p.status == PurchaseStatus.pending) {
        _setPending();
      }
    }
    if (purchaseDetailsList.isEmpty) return;
    if (purchaseDetailsList.length > 1) {
      purchaseDetailsList.sort((a, b) {
        int dateA = int.tryParse(a.transactionDate ?? '') ?? 0;
        int dateB = int.tryParse(b.transactionDate ?? '') ?? 0;
        return dateB.compareTo(dateA);
      });
    }
    if (kDebugMode) {
      printY(
        "[DEV-LOG] [PaymentService] ${purchaseDetailsList.map((x) => DateTime.fromMillisecondsSinceEpoch(int.parse(x.transactionDate ?? "0")).toIso8601String())}",
      );
    }
    final PurchaseDetails purchaseDetails = _getPurchasedData(purchaseDetailsList) ?? purchaseDetailsList.first;

    if (purchaseDetails.status != PurchaseStatus.pending) {
      if (purchaseDetails.status == PurchaseStatus.error) {
        _isBuying = false;
        _handleError(purchaseDetails.error);
      } else if (purchaseDetails.status == PurchaseStatus.purchased ||
          purchaseDetails.status == PurchaseStatus.restored) {
        if (!boughtProductIds.contains(purchaseDetails.productID)) {
          final bool valid = await _verifyPurchase(purchaseDetails);
          _isBuying = false;
          if (valid) {
            _deliverProduct(purchaseDetails);
          } else {
            _handleInvalidPurchase(purchaseDetails);
            return;
          }
        } else {
          _isBuying = false;
          _paymentStatusStreamController.add(PaymentStatus.completed);
        }
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        _isBuying = false;
        _paymentStatusStreamController.add(PaymentStatus.canceled);
      }
      if (purchaseDetails.pendingCompletePurchase) {
        printY("[DEV-LOG] [PaymentService] pendingCompletePurchase START ${purchaseDetails.productID}");
        final start = DateTime.now().millisecondsSinceEpoch;
        await _inAppPurchase.completePurchase(purchaseDetails);
        final end = DateTime.now().millisecondsSinceEpoch;
        printY("[DEV-LOG] [PaymentService] pendingCompletePurchase COMPLETED in  ${end - start}ms");
      }
    }
  }

  PurchaseDetails? _getPurchasedData(List<PurchaseDetails> sortedPurchaseDetailsList) {
    List<PurchaseDetails> filtered = sortedPurchaseDetailsList
        .where((purchaseDetails) =>
            purchaseDetails.status == PurchaseStatus.purchased || purchaseDetails.status == PurchaseStatus.restored)
        .toList();

    if (filtered.isEmpty) return null;
    return filtered.first;
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    printY("\n");
    printY("VERIFY PURCHASE");
    printY("> productID ${purchaseDetails.productID} purchaseID ${purchaseDetails.purchaseID}");
    printY("> status ${purchaseDetails.status}");
    printY(
      "> transactionDate ${DateTime.fromMillisecondsSinceEpoch(int.tryParse(purchaseDetails.transactionDate ?? "0") ?? 0)}",
    );
    printY("> pendingCompletePurchase ${purchaseDetails.pendingCompletePurchase}\n");
    // printY("> verificationData local ${purchaseDetails.verificationData.localVerificationData}\n");
    // IMPORTANT!! Always verify a purchase before delivering the product.
    // For the purpose of an example, we directly return true.

    // if (purchaseDetails.productID == FullAccessPaymentIds.trial &&
    //     purchaseDetails.status == PurchaseStatus.purchased &&
    //     !UserSessionService.instance.trialConsumed) {
    //   await HiveService.i.consumeTrial();
    //   await ApiTrial().consume();
    // }

    if (Platform.isIOS) {
      const String url = 'https://apis.netigen.eu/api/payments/appstore';
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'receipt': purchaseDetails.verificationData.serverVerificationData,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        printY('[DEV-LOG] [PaymentService] $responseData');
        final bool notExpired = DateTime.now()
            .isBefore(DateTime.fromMillisecondsSinceEpoch(int.parse(responseData['data']['expiresDateMs'])));
        if (kDebugMode) {
          printY(
            '[DEV-LOG] [PaymentService] ${DateTime.now().toIso8601String()}${notExpired ? ">" : "<"}${DateTime.fromMillisecondsSinceEpoch(int.parse(responseData['data']['expiresDateMs'])).toIso8601String()}',
          );
        }
        return notExpired;
      } else {
        printY('[DEV-LOG] [PaymentService] ${response.statusCode} ${response.body}');
        return false;
      }
    }

    final bool verified = await _verifyPurchaseCallback(purchaseDetails);
    return verified;

    // return Future<bool>.value(true);
  }

  void _deliverProduct(PurchaseDetails purchaseDetails) {
    disableInterstitialAd();
    _purchases.add(purchaseDetails);
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

  Future<void> loadProducts() async {
    if (!_productIdsProvided) {
      throw ArgumentError(
          "[DEV-LOG] [PaymentService] ERROR: Product ids not provided. Use PaymentService.initParameters");
    }
    _isAvailable = await _inAppPurchase.isAvailable();
    if (!_isAvailable) {
      _loading = false;
      return;
    }

    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await iosPlatformAddition.setDelegate(ExamplePaymentQueueDelegate());
    }

    final response = await _inAppPurchase.queryProductDetails(_allProductIds);

    if (response.error != null) {
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
          "[DEV-LOG] [PaymentService] ERROR: Product ids not provided. Use PaymentService.initParameters");
    }
    try {
      printY("[DEV-LOG] PaymentService.restorePurchases STARTED with products: ${_allProducts.length}");
      final start = DateTime.now().millisecondsSinceEpoch;
      await _inAppPurchase.restorePurchases();
      final end = DateTime.now().millisecondsSinceEpoch;
      printY("[DEV-LOG] PaymentService.restorePurchases took ${end - start}ms");
      return true;
    } catch (e) {
      printY(e.toString());
      return false;
    }
  }

  void dispose() {
    if (Platform.isIOS) {
      final InAppPurchaseStoreKitPlatformAddition iosPlatformAddition =
          _inAppPurchase.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
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
      () => Future.delayed(
        const Duration(milliseconds: 100),
        () {
          tick++;
          printY("[DEV-LOG] waiting for checkPremiumUserOnStart ${tick * 100}ms");
          if (tick >= _restoringOnStartTicks) _restoreExecuted = true;
        },
      ).then((_) => !_restoreExecuted),
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
      printY(e.toString());
    }
  }

  void buyNonConsumable(ProductDetails productDetails) {
    if (!_isBuying) {
      _isBuying = true;
      _inAppPurchase.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: productDetails,
        ),
      );
    }
  }

  bool get hasProducts => _filterActiveProducts(_allProducts).isNotEmpty;

  List<ProductDetails> _filterActiveProducts(List<ProductDetails> products) =>
      products.where((element) => _activeProductIds.contains(element.id)).toList();

  List<PurchaseDetails> _filterPremiumPurchases(List<PurchaseDetails> purchases) =>
      purchases.where((element) => _premiumProductIds.contains(element.productID)).toList();
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
    return false;
  }
}
