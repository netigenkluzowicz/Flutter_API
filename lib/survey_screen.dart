import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info/package_info.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'utils.dart';

class SurveyScreen extends StatefulWidget {
  static const String route = "/flutter-api/SurveyScreen";

  final String serverUrl;
  final String locale;
  final Function? onMessageReceived;

  const SurveyScreen({
    super.key,
    required this.serverUrl,
    required this.locale,
    this.onMessageReceived,
  });

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();

    initController();
  }

  Future<void> initController() async {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller = WebViewController.fromPlatformCreationParams(params);

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (urlChange) {
            printR("[DEV-LOG] onUrlChange ${urlChange.url}");
          },
          onProgress: (int progress) {
            printR("[DEV-LOG] onProgress $progress");
          },
          onPageStarted: (String url) {
            printR("[DEV-LOG] onPageStarted $url");
          },
          onPageFinished: (String url) {
            printR("[DEV-LOG] onPageFinished $url");
          },
          onWebResourceError: (WebResourceError error) {
            printR(
              "[DEV-LOG] onWebResourceError code:${error.errorCode} mainFrame:${error.isForMainFrame} type:${error.errorType} desc:${error.description}",
            );
          },
        ),
      )
      ..addJavaScriptChannel(
        'SURVEY_CHANNEL',
        onMessageReceived: (JavaScriptMessage message) {
          widget.onMessageReceived;
          if (message.message.contains('QUIT_YES') || message.message.contains('EXIT')) {
            Navigator.of(context).pop();
          }
        },
      )
      ..loadRequest(
        Uri.parse(
          '${widget.serverUrl}?packageName=${packageInfo.packageName}&appVersion=v${packageInfo.version}&platform=${Platform.isAndroid ? 'android' : 'ios'}&locale=${widget.locale}',
        ),
      );

    if (controller.platform is AndroidWebViewController) {
      AndroidWebViewController.enableDebugging(true);
      (controller.platform as AndroidWebViewController).setMediaPlaybackRequiresUserGesture(false);
    }

    setState(() {
      _controller = controller;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: (_controller != null)
            ? WebViewWidget(
                controller: _controller!,
              )
            : Center(
                child: kIsWeb || Platform.isAndroid
                    ? const CircularProgressIndicator()
                    : const CupertinoActivityIndicator(),
              ),
      ),
    );
  }
}
