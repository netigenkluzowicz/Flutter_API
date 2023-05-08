import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

import './screens/fake_splashscreen.dart';
import './providers/payment_provider.dart';

//initialize admob in main
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PaymentProvider(),
      child: MaterialApp(
        title: 'Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        // create fake splash screen to make data flow easier (in widget), make sure to
        // create same UI as NatvieSplashScreen for smooth transition
        home: const FakeSplashscreen(),
      ),
    );
  }
}
