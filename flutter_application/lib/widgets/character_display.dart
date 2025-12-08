import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../core/services/expression_agent_service.dart';
import '../widgets/expressive_face.dart'; // For ExpressionData

import 'package:shared_preferences/shared_preferences.dart';

class CharacterDisplay extends StatefulWidget {
  final String backendUrl; // e.g. http://localhost:8000
  final ExpressionAgentService? expressionAgent;

  const CharacterDisplay({
    Key? key,
    required this.backendUrl,
    this.expressionAgent,
  }) : super(key: key);

  @override
  State<CharacterDisplay> createState() => _CharacterDisplayState();
}

class _CharacterDisplayState extends State<CharacterDisplay> {
  // Mobile controller
  WebViewController? _mobileController;

  // Windows controller
  final _windowsController = WebviewController();
  bool _isWindowsInitialized = false;

  StreamSubscription? _expressionSub;
  StreamSubscription? _motionSub;

  @override
  void initState() {
    super.initState();
    _initWebView();

    if (widget.expressionAgent != null) {
      _expressionSub = widget.expressionAgent!.stream.listen(
        _onExpressionUpdate,
      );
      _motionSub = widget.expressionAgent!.motionStream.listen(
        _onMotionRequest,
      );
    }
  }

  Future<String> _getModelUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to empty if no model is selected. User must upload/select one.
    final path = prefs.getString('settings.character.modelPath') ?? '';
    // 从设置读取调试开关，默认关闭
    final debug = prefs.getBool('settings.ui.live2dDebug') ?? false;
    return '${widget.backendUrl}/static/live2d/index.html?model=$path&debug=$debug';
  }

  Future<void> _initWebView() async {
    final url = await _getModelUrl();
    if (Platform.isWindows) {
      _initWindowsWebView(url);
    } else {
      _initMobileWebView(url);
    }
  }

  Future<void> _initWindowsWebView(String url) async {
    try {
      await _windowsController.initialize();
      await _windowsController.setBackgroundColor(Colors.transparent);
      await _windowsController.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.deny,
      );
      await _windowsController.loadUrl(url);

      if (mounted) {
        setState(() {
          _isWindowsInitialized = true;
        });
      }
    } catch (e) {
      print("Error initializing Windows WebView: $e");
    }
  }

  void _initMobileWebView(String url) {
    _mobileController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) {
            print('Page finished loading: $url');
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _expressionSub?.cancel();
    _motionSub?.cancel();
    if (Platform.isWindows) {
      _windowsController.dispose();
    }
    super.dispose();
  }

  void _onExpressionUpdate(ExpressionData data) {
    // Convert ExpressionData to JSON for JS
    final map = {
      'mouth': data.mouth,
      'eyes': data.eyes,
      'eyebrow': data.eyebrow,
      'blush': data.blush,
      'pupilX': data.pupilX,
      'pupilY': data.pupilY,
      'headTilt': data.headTilt,
    };
    final jsonStr = jsonEncode(map);
    final js =
        "if (window.live2dManager) window.live2dManager.updateParameters($jsonStr);";

    _runJavascript(js);
  }

  void _onMotionRequest(MotionRequest req) {
    // Escape strings for JS
    final u = jsonEncode(req.userText);
    final a = jsonEncode(req.aiText);
    final js =
        "if (window.LanLan1 && window.LanLan1.askMotionAgent) window.LanLan1.askMotionAgent($u, $a);";

    print('[CharacterDisplay] Triggering Motion Agent: $u');
    _runJavascript(js);
  }

  void _runJavascript(String js) {
    if (Platform.isWindows && _isWindowsInitialized) {
      _windowsController.executeScript(js);
    } else if (_mobileController != null) {
      _mobileController!.runJavaScript(js);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a transparent container to avoid black flash
    return Container(
      color: Colors.transparent,
      child: Platform.isWindows
          ? (_isWindowsInitialized
                ? Webview(_windowsController)
                : const SizedBox()) // Don't show loader to avoid flickering
          : (_mobileController != null
                ? WebViewWidget(controller: _mobileController!)
                : const SizedBox()),
    );
  }
}
