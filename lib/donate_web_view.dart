import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'utils.dart';

class DonateWebView extends StatefulWidget {
  final String serverUrl;
  final String locale;
  final String option0;
  final String option1;
  final String option2;
  final void Function(String)? onMessageReceived;
  final double height;

  const DonateWebView({
    super.key,
    required this.serverUrl,
    required this.locale,
    required this.option0,
    required this.option1,
    required this.option2,
    this.onMessageReceived,
    this.height = 622.0,
  });

  @override
  State<DonateWebView> createState() => _DonateWebviewState();
}

class _DonateWebviewState extends State<DonateWebView> {
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

    final String url = '${widget.serverUrl}?platform=flutter&locale=${widget.locale}'
        '&options[0]=${widget.option0}&options[1]=${widget.option1}&options[2]=${widget.option2}';
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
        'DONATE_CHANNEL',
        onMessageReceived: (JavaScriptMessage message) {
          if (widget.onMessageReceived != null) {
            widget.onMessageReceived!(message.message);
          }
          if (message.message.contains('EXIT')) {
            Navigator.of(context).pop();
          }
        },
      )
      ..loadRequest(Uri.parse(url));

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
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: (_controller != null)
          ? WebViewWidget(
              controller: _controller!,
            )
          : Center(
              child:
                  kIsWeb || Platform.isAndroid ? const CircularProgressIndicator() : const CupertinoActivityIndicator(),
            ),
    );
  }
}
