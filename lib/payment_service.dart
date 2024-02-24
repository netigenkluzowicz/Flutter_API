import 'dart:async';
import 'dart:io';

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

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (PurchaseDetails purchaseDetails in purchaseDetailsList) {
      printY("[DEV-LOG] [PaymentService] ${purchaseDetails.productID} ${purchaseDetails.status}");

      if (purchaseDetails.status == PurchaseStatus.pending) {
        _setPending();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          _isBuying = false;
          _handleError(purchaseDetails.error);
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          final bool valid = await _verifyPurchase(purchaseDetails);
          _isBuying = false;
          if (valid) {
            _deliverProduct(purchaseDetails);
          } else {
            _handleInvalidPurchase(purchaseDetails);
            return;
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
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    printY("\n");
    printY("VERIFY PURCHASE");
    printY("> productID ${purchaseDetails.productID} purchaseID ${purchaseDetails.purchaseID}");
    printY("> status ${purchaseDetails.status}");
    printY("> transactionDate ${purchaseDetails.transactionDate}");
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
