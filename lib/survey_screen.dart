import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'utils.dart';

class SurveyScreen extends StatefulWidget {
  static const String route = "/flutter-api/SurveyScreen";

  final String serverUrl;
  final String locale;
  final void Function(String)? onMessageReceived;

  /// [PopScope.canPop]
  final bool canPop;
  final Color? backgroundColor;

  /// [PopScope.onPopInvokedWithResult] with BuildContext
  final void Function(BuildContext context, bool didPop)? onPopInvoked;

  final void Function(BuildContext context)? initStateAction;

  const SurveyScreen({
    super.key,
    required this.serverUrl,
    required this.locale,
    this.onMessageReceived,
    this.canPop = true,
    this.onPopInvoked,
    this.initStateAction,
    this.backgroundColor,
  });

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  WebViewController? _controller;

  @override
  dispose() {
    _controller?.clearCache();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initStateAction != null) {
        widget.initStateAction!(context);
      }
      initController();
    });
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

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);

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
          onHttpAuthRequest: (request) {
            printR("[DEV-LOG] onHttpAuthRequest host:${request.host}");
          },
          onHttpError: (error) {
            printR(
              "[DEV-LOG] onHttpError statusCode:${error.response?.statusCode} ${error.response?.uri}",
            );
          },
        ),
      )
      ..addJavaScriptChannel(
        'SURVEY_CHANNEL',
        onMessageReceived: (JavaScriptMessage message) {
          if (widget.onMessageReceived != null) {
            widget.onMessageReceived!(message.message);
          }
          if (message.message.contains('QUIT_YES') ||
              message.message.contains('EXIT')) {
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
      (controller.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
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
        backgroundColor:
            widget.backgroundColor ?? Theme.of(context).colorScheme.surface,
        body: SafeArea(
          child: (_controller != null)
              ? WebViewWidget(controller: _controller!)
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
