import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart';
import '../core/services/expression_agent_service.dart';
// import '../widgets/expressive_face.dart'; // For ExpressionData
import 'live2d_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';

class CharacterDisplay extends StatefulWidget {
  final String backendUrl; // e.g. http://localhost:8000
  final ExpressionAgentService? expressionAgent;
  final Live2DController? controller;
  final bool floatingUi;
  final bool showControls;

  const CharacterDisplay({
    Key? key,
    required this.backendUrl,
    this.expressionAgent,
    this.controller,
    this.floatingUi = false,
    this.showControls = true,
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

  // StreamSubscription? _expressionSub; // Removed
  // StreamSubscription? _motionSub;     // Removed

  @override
  void initState() {
    super.initState();
    // Delay WebView initialization to avoid blocking the main thread during startup
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _initWebView();
      }
    });

    // NOTE: We no longer listen to streams here for local injection.
    // Instead, we rely on the Unified WebSocket Broadcast (handled by ExpressionAgentService -> Backend -> WebSocket).
    // This ensures consistent behavior across Sidebar, Mini Window, and Floating Window modes.
    // However, we still need to inject the *initial* expression state once the view loads.

    // Attach controller
    if (widget.controller != null) {
      widget.controller!.attach((js) async {
        _runJavascript(js);
      });
    }
  }

  @override
  void dispose() {
    // _expressionSub and _motionSub are removed
    if (widget.controller != null) {
      widget.controller!.detach();
    }
    if (Platform.isWindows) {
      try {
        _windowsController.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<String> _getModelUrl() async {
    final prefs = await SharedPreferences.getInstance();
    // Default to empty if no model is selected. User must upload/select one.
    String path = prefs.getString('settings.character.modelPath') ?? '';
    
    // Auto-select if empty by fetching list from backend
    if (path.isEmpty) {
      try {
        final uri = Uri.parse('${widget.backendUrl}/v1/models/list');
        final resp = await http.get(uri);
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final models = json['models'] as List;
          if (models.isNotEmpty) {
            // Auto-pick the first one
            final first = models.first;
            path = first['path']; // e.g. /static/live2d/Name/file.model3.json
            await prefs.setString('settings.character.modelPath', path);
            print('[CharacterDisplay] Auto-selected model: $path');
          } else {
             print('[CharacterDisplay] No models found on backend.');
          }
        }
      } catch (e) {
        print('[CharacterDisplay] Failed to auto-select model: $e');
      }
    }

    final params = <String>[];
    params.add('model=${Uri.encodeComponent(path)}');
    if (kDebugMode) params.add('debug=true');
    if (widget.floatingUi) params.add('floating=true');
    params.add('controls=${widget.showControls}');
    final query = params.join('&');
    return '${widget.backendUrl}/static/live2d/index.html?$query';
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
      if (!_windowsController.value.isInitialized) {
        await _windowsController.initialize();
      }
      await _windowsController.setBackgroundColor(Colors.transparent);
      await _windowsController.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.deny,
      );
      await _windowsController.loadUrl(url);

      if (mounted) {
        setState(() {
          _isWindowsInitialized = true;
        });
        _runJavascript("window.LIVE2D_DISABLE_WEBSOCKET_AUDIO = true; window.LIVE2D_EXTERNAL_AUDIO_MUTED = true;");
        _injectInitialExpression();
      }
    } catch (e) {
      print("Error initializing Windows WebView: $e");
      if (mounted) {
        // Show error in UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Live2D WebView Init Failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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
            _runJavascript("window.LIVE2D_DISABLE_WEBSOCKET_AUDIO = true; window.LIVE2D_EXTERNAL_AUDIO_MUTED = true;");
            _injectInitialExpression();
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
    if (mounted) setState(() {});
  }


  void _injectInitialExpression() {
    if (widget.expressionAgent == null) return;
    final data = widget.expressionAgent!.current;

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

    print('[CharacterDisplay] Injecting initial expression: $jsonStr');
    _runJavascript(js);
  }

  // _onMotionRequest is removed as we use WebSocket broadcast now.

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
