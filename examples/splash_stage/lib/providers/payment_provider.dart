import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_api/flutter_api.dart';

class PaymentProvider extends ChangeNotifier {
  //default value for all users
  bool isPremium = false;

  final InAppPurchase _iap = InAppPurchase.instance;

  //if store is avaliable on device
  late bool _avaliable;

  //Products for sale
  List<ProductDetails> _products = [];

  //Past purchases
  final List<PurchaseDetails> _purchases = [];

  late StreamSubscription _subscription;

  Future<void> _getProducts() async {
    Set<String> ids = {
      'pl.netigen.bestloupe.noads',
      'pl.netigen.bestloupe.noadspromotion'
    };
    ProductDetailsResponse response = await _iap.queryProductDetails(ids);
    _products = response.productDetails;
    notifyListeners();
  }

  Future<void> _getPastPurchases() async {
    //this will trigger listener if user made purchases in the past
    _iap.restorePurchases();
  }

  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (var element in purchaseDetailsList) {
      if (element.status == PurchaseStatus.pending) {
        //handle situation when user pressed button to start purchase, (on iOS it takes more time, android have almost immediately response) maybe show some loading spinners
      } else if (element.status == PurchaseStatus.error) {
        //handle errors
      } else if (element.status == PurchaseStatus.canceled) {
        //handle situation when user canceled payment
      } else if (element.status == PurchaseStatus.purchased ||
          element.status == PurchaseStatus.restored) {
        //if purchase or restored, make sure to give users what they payed for
        //Do not override _purchases list if it is not empty! just make sure to add new products to existing list
        //NOT TO DO: _purchases = [elements];
        //DO: _purchases.add(element);
        _purchases.add(element);
        isPremium = true;
        notifyListeners();
      }
    }
  }

  //buy product, call it from some kind of button
  void buyProduct() async {
    _avaliable = await _iap.isAvailable();
    if (_avaliable) {
      final PurchaseParam purchaseParam = PurchaseParam(
          productDetails: _products.firstWhere(
              (element) => element.id == 'pl.netigen.bestloupe.noads'));
      await InAppPurchase.instance
          .buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  //call this function at launch of your app
  void initialize() async {
    _avaliable = await _iap.isAvailable();
    if (_avaliable) {
      await _getProducts();
      await _getPastPurchases();
      //it's listening to every changes in purchases e.g. buy new product, restore old products.
      //everytime when change will occur, then function is triggered
      //remember to always cancel listeners to avoid memmory leaks
      _subscription = _iap.purchaseStream.listen(
        (purchaseDetailsList) {
          _listenToPurchaseUpdated(purchaseDetailsList);
        },
        onDone: () => _subscription.cancel(),
        onError: (error) => debugPrint(error),
      );
    }
  }
}
