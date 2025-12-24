import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import '../../core/services/backend_service.dart';
import '../floating_window_service.dart';

/// Windows 平台浮窗实现（使用 desktop_webview_window 独立 WebView 窗口）
class FloatingWindowWindows implements FloatingWindowService {
  /// 最大允许的浮窗数量
  static const int maxFloatingWindows = 2;

  /// 当前活跃的浮窗实例集合
  static final Set<FloatingWindowWindows> _activeInstances = {};

  /// 获取当前活跃的浮窗数量
  static int get activeCount => _activeInstances.length;

  String backendUrl;
  bool _isInitialized = false;
  bool _isVisible = false;
  Webview? _webview;
  VoidCallback? _onCloseCallback;
  String? _currentModelPath;
  StreamSubscription? _urlSubscription;

  FloatingWindowWindows({required this.backendUrl});

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // Subscribe to backend URL changes to keep the window in sync
    _urlSubscription = BackendService().urlStream.listen((url) {
      debugPrint('[FloatingWindowWindows] Received backend URL update: $url');
      updateBackendUrl(url);
    });
    
    // Ensure we have the latest URL immediately
    final currentUrl = BackendService().backendUrl;
    if (currentUrl != backendUrl) {
       updateBackendUrl(currentUrl);
    }
  }

  @override
  void updateBackendUrl(String url) {
    if (backendUrl == url) return;
    backendUrl = url;
    if (_webview != null && _currentModelPath != null) {
      _reloadWindow();
    }
  }

  Future<void> _reloadWindow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final debug = prefs.getBool('settings.live2dDebug') ?? false;
      final url =
          '$backendUrl/static/live2d/index.html?model=$_currentModelPath&debug=$debug&floating=true&controls=false';
      
      if (_webview != null) {
        _webview!.launch(url);
        debugPrint('[FloatingWindowWindows] Reloaded with URL: $url');
      }
    } catch (e) {
      debugPrint('[FloatingWindowWindows] Failed to reload window: $e');
    }
  }

  @override
  void setOnCloseCallback(VoidCallback callback) {
    _onCloseCallback = callback;
  }

  @override
  Future<void> createFloatingWindow({
    required String modelPath,
    required double width,
    required double height,
  }) async {
    if (!_isInitialized) {
      throw StateError('FloatingWindowWindows not initialized');
    }

    // 检查是否超过最大浮窗数量限制
    if (_webview == null && _activeInstances.length >= maxFloatingWindows) {
      debugPrint(
        '[FloatingWindowWindows] Max floating windows limit reached ($maxFloatingWindows)',
      );
      return; // 达到上限，不创建新窗口
    }

    // Auto-select model if path is empty (consistent with CharacterDisplay)
    if (modelPath.isEmpty) {
      try {
        final uri = Uri.parse('$backendUrl/v1/models/list');
        final resp = await http.get(uri);
        if (resp.statusCode == 200) {
          final json = jsonDecode(resp.body);
          final models = json['models'] as List;
          if (models.isNotEmpty) {
            final first = models.first;
            modelPath = first['path'];
            debugPrint('[FloatingWindowWindows] Auto-selected model: $modelPath');
          } else {
            debugPrint('[FloatingWindowWindows] No models found on backend.');
          }
        }
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Failed to auto-select model: $e');
      }
    }

    _currentModelPath = modelPath;

    try {
      // 如果当前实例已经存在浮窗，先关闭
      if (_webview != null) {
        await closeFloatingWindow();
      }

      // 保存浮窗配置到本地存储
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('floating.window.width', width);
      await prefs.setDouble('floating.window.height', height);
      await prefs.setBool('floating.window.enabled', true);
      if (modelPath.isNotEmpty) {
        await prefs.setString('floating.window.modelPath', modelPath);
      }

      // 构建 Live2D URL，根据设置决定是否开启调试
      final debug = prefs.getBool('settings.live2dDebug') ?? false;
      final url =
          '$backendUrl/static/live2d/index.html?model=$modelPath&debug=$debug&floating=true&controls=false';

      // 创建独立 WebView 窗口（隐藏标题栏和工具栏，只显示纯 WebView 内容）
      _webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowWidth: width.toInt(),
          windowHeight: height.toInt(),
          title: '', // 设置为空标题，减少标题栏布局压力
          titleBarTopPadding: 0,
          titleBarHeight: 0, // 标题栏高度为0
        ),
      );

      // 加载 Live2D 页面
      _webview!.launch(url);

      // 注册到活跃实例集合
      _activeInstances.add(this);

      // 监听窗口关闭事件
      _webview!.onClose.whenComplete(() {
        debugPrint('[FloatingWindowWindows] WebView window closed by user');
        _activeInstances.remove(this);
        _webview = null;
        _isVisible = false;
        SharedPreferences.getInstance().then((p) {
          p.setBool('floating.window.enabled', false);
        });
        // 通知外部回调
        if (_onCloseCallback != null) {
          _onCloseCallback!();
        }
      });

      // 监听来自 JS 的消息 (用于关闭窗口等交互)
      // TODO: desktop_webview_window 0.2.3 可能不支持 onMessage，暂时注释掉
      // 需要确认如何从 JS 发送消息到 Dart
      /*
      _webview!.onMessage.listen((message) {
        if (message == 'close') {
          debugPrint('[FloatingWindowWindows] Received close message from JS');
          closeFloatingWindow();
        }
      });
      */

      _isVisible = true;
      debugPrint(
        '[FloatingWindowWindows] WebView window created with URL: $url',
      );
    } catch (e) {
      debugPrint('[FloatingWindowWindows] Create window failed: $e');
      // If the desktop webview plugin is not available at runtime (MissingPluginException),
      // fail gracefully instead of rethrowing so the main app can continue running.
      try {
        if (e is MissingPluginException) {
          debugPrint('[FloatingWindowWindows] Missing plugin detected, skipping floating window creation.');
          // Persist disabled state so UI can reflect inability to create floating window
          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool('floating.window.enabled', false);
          });
          _webview = null;
          _isVisible = false;
          return;
        }
      } catch (_) {
        // ignore errors during exception handling
      }
      rethrow;
    }
  }

  @override
  Future<void> showFloatingWindow() async {
    _isVisible = true;
  }

  @override
  Future<void> hideFloatingWindow() async {
    await closeFloatingWindow();
  }

  @override
  Future<void> closeFloatingWindow() async {
    if (_webview != null) {
      try {
        _activeInstances.remove(this);
        _webview!.close();
        _webview = null;
        _isVisible = false;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('floating.window.enabled', false);
        debugPrint(
          '[FloatingWindowWindows] WebView window closed (active: ${_activeInstances.length})',
        );
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Close window failed: $e');
        _activeInstances.remove(this);
        _webview = null;
        _isVisible = false;
      }
    }
  }

  @override
  Future<bool> isFloatingWindowVisible() async {
    return _isVisible && _webview != null;
  }

  @override
  Future<void> setPosition(double x, double y) async {}

  @override
  Future<void> setSize(double width, double height) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('floating.window.width', width);
      await prefs.setDouble('floating.window.height', height);
    } catch (e) {
      debugPrint('[FloatingWindowWindows] Set size failed: $e');
    }
  }

  @override
  Future<void> setAlwaysOnTop(bool alwaysOnTop) async {}

  @override
  Future<void> executeJavaScript(String js) async {
    if (_webview != null) {
      try {
        await _webview!.evaluateJavaScript(js);
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Execute JS failed: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    _urlSubscription?.cancel();
    await closeFloatingWindow();
    _isInitialized = false;
  }
}
