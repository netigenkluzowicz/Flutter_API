import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';

class Questionnaire {
  static WebViewController webViewController({
    required BuildContext context,
    required String version,
    required String locale,
    Function? onMessageReceived,
  }) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('SURVEY_CHANNEL',
          onMessageReceived: (JavaScriptMessage message) {
        onMessageReceived;
        if (message.message.contains('QUIT_YES') ||
            //message.message.contains('FETCHING_ERROR') ||
            message.message.contains('EXIT')) {
          Navigator.of(context).pop();
        }
      })
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {},
          onPageFinished: (String url) {},
          onWebResourceError: (WebResourceError error) {},
        ),
      )
      ..loadRequest(Uri.parse(
          'https://apis.netigen.eu/survey-webview?packageName=pl.netigen.bestloupe&appVersion=v$version&platform=android&locale=$locale'));
    return controller;
  }
}
