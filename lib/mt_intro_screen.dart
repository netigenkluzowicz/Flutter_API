import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'utils.dart';

class MtIntroScreen extends StatefulWidget {
  static const String route = "/flutter-api/MtIntroScreen";

  /// url of this webview
  final String introServerUrl;
  final String locale;
  final void Function(String)? onMessageReceived;

  /// pop this screen and open demo url in external browser
  final void Function() openDemoCallback;

  /// [PopScope.canPop]
  final bool canPop;

  /// [PopScope.onPopInvokedWithResult] with BuildContext
  final void Function(BuildContext context, bool didPop)? onPopInvoked;

  final void Function(BuildContext context)? initStateAction;

  const MtIntroScreen({
    super.key,
    required this.introServerUrl,
    required this.locale,
    this.onMessageReceived,
    required this.openDemoCallback,
    this.canPop = true,
    this.onPopInvoked,
    this.initStateAction,
  });

  @override
  State<MtIntroScreen> createState() => _MtIntroScreenState();
}

class _MtIntroScreenState extends State<MtIntroScreen> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();

    if (widget.initStateAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.initStateAction!(context);
      });
    }

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
        'MUSIC_THEORY_CHANNEL',
        onMessageReceived: (JavaScriptMessage message) {
          if (widget.onMessageReceived != null) {
            widget.onMessageReceived!(message.message);
          }
          if (message.message.contains('EXIT')) {
            Navigator.of(context).pop();
          } else if (message.message.contains('OPEN_IN_BROWSER')) {
            widget.openDemoCallback();
          }
        },
      )
      ..loadRequest(Uri.parse(widget.introServerUrl));

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
    return PopScope(
      canPop: widget.canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (widget.onPopInvoked != null) {
          widget.onPopInvoked!(context, didPop);
        }
      },
      child: Scaffold(
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
      ),
    );
  }
}
