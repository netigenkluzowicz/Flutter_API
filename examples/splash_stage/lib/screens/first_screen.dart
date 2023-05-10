import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/payment_provider.dart';

//just simple widget to pretend first
class FirstScreen extends StatelessWidget {
  const FirstScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final purchaseData = Provider.of<PaymentProvider>(context);
    return Scaffold(
      body: Center(
          child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('is user premium: ${purchaseData.isPremium}'),
          const Text('First page'),
          ElevatedButton(
              onPressed: () {
                //will start the payment
                purchaseData.buyProduct();
              },
              child: const Text('Buy product'))
        ],
      )),
    );
  }
}
