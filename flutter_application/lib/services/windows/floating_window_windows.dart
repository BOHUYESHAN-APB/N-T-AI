import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import '../floating_window_service.dart';

/// Windows 平台浮窗实现（使用 desktop_webview_window 独立 WebView 窗口）
class FloatingWindowWindows implements FloatingWindowService {
  /// 最大允许的浮窗数量
  static const int maxFloatingWindows = 2;

  /// 当前活跃的浮窗实例集合
  static final Set<FloatingWindowWindows> _activeInstances = {};

  /// 获取当前活跃的浮窗数量
  static int get activeCount => _activeInstances.length;

  final String backendUrl;
  bool _isInitialized = false;
  bool _isVisible = false;
  Webview? _webview;

  FloatingWindowWindows({required this.backendUrl});

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
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

      // 构建 Live2D URL，从设置读取调试开关
      final debug = prefs.getBool('settings.ui.live2dDebug') ?? false;
      final url =
          '$backendUrl/static/live2d/index.html?model=$modelPath&debug=$debug&floating=true';

      // 创建独立 WebView 窗口（隐藏标题栏和工具栏，只显示纯 WebView 内容）
      _webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowWidth: width.toInt(),
          windowHeight: height.toInt(),
          title: 'Live2D',
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
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('floating.window.enabled', false);
        });
      });

      _isVisible = true;
      debugPrint(
        '[FloatingWindowWindows] WebView window created with URL: $url',
      );
    } catch (e) {
      debugPrint('[FloatingWindowWindows] Create window failed: $e');
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
    await closeFloatingWindow();
    _isInitialized = false;
  }
}
