import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class Questionnaire {
  static Widget webViewQuestionnaireController({
    required BuildContext context,
    required String version,
    required String locale,
    required String packageName,
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
      ..setBackgroundColor(Colors.white)
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
          'https://apis.netigen.eu/survey-webview?packageName=$packageName&appVersion=v$version&platform=android&locale=$locale'));
    return Scaffold(
      body: SafeArea(
          bottom: Platform.isIOS ? true : false,
          top: Platform.isIOS ? true : false,
          child: WebViewWidget(controller: controller)),
    );
  }
}
