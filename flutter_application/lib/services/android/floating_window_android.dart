import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../core/services/backend_service.dart';
import '../floating_window_service.dart';

/// Android 平台浮窗实现
class FloatingWindowAndroid implements FloatingWindowService {
  String backendUrl;
  static const platform = MethodChannel('com.bohuyeshan.ntai/floating_window');
  bool _isInitialized = false;
  bool _isVisible = false;
  StreamSubscription? _urlSubscription;

  FloatingWindowAndroid({required this.backendUrl});

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Subscribe to backend URL changes
      _urlSubscription = BackendService().urlStream.listen((url) {
        debugPrint('[FloatingWindowAndroid] Received backend URL update: $url');
        updateBackendUrl(url);
      });

      // Ensure we have the latest URL
      final currentUrl = BackendService().backendUrl;
      if (currentUrl != backendUrl) {
         backendUrl = currentUrl;
      }

      // 检查权限和初始化
      await platform.invokeMethod('initialize', {'backendUrl': backendUrl});
      _isInitialized = true;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Initialize failed: $e');
      rethrow;
    }
  }

  @override
  void updateBackendUrl(String url) {
    backendUrl = url;
    if (_isInitialized) {
        // Try to update backend URL on native side if needed
        // For now, we just update the local property which will be used 
        // if we re-initialize or if other methods use it.
        // If Android native side needs dynamic update, we should add a method there.
        platform.invokeMethod('updateBackendUrl', {'backendUrl': url}).catchError((e) {
           debugPrint('[FloatingWindowAndroid] Update backend URL failed (optional): $e');
        });
    }
  }

  @override
  void setOnCloseCallback(VoidCallback callback) {
    // Android implementation currently doesn't support external close callback
    // TODO: Implement MethodChannel callback from Android native side
  }

  @override
  Future<void> createFloatingWindow({
    required String modelPath,
    required double width,
    required double height,
  }) async {
    if (!_isInitialized) {
      throw StateError('FloatingWindowAndroid not initialized');
    }

    try {
      await platform.invokeMethod('createFloatingWindow', {
        'modelPath': modelPath,
        'width': width,
        'height': height,
      });
      _isVisible = true;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Create window failed: $e');
      rethrow;
    }
  }

  @override
  Future<void> showFloatingWindow() async {
    try {
      await platform.invokeMethod('showFloatingWindow');
      _isVisible = true;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Show window failed: $e');
    }
  }

  @override
  Future<void> hideFloatingWindow() async {
    try {
      await platform.invokeMethod('hideFloatingWindow');
      _isVisible = false;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Hide window failed: $e');
    }
  }

  @override
  Future<void> closeFloatingWindow() async {
    try {
      await platform.invokeMethod('closeFloatingWindow');
      _isVisible = false;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Close window failed: $e');
    }
  }

  @override
  Future<bool> isFloatingWindowVisible() async {
    try {
      final result = await platform.invokeMethod<bool>(
        'isFloatingWindowVisible',
      );
      return result ?? _isVisible;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Check visibility failed: $e');
      return _isVisible;
    }
  }

  @override
  Future<void> setPosition(double x, double y) async {
    try {
      await platform.invokeMethod('setPosition', {'x': x, 'y': y});
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Set position failed: $e');
    }
  }

  @override
  Future<void> setSize(double width, double height) async {
    try {
      await platform.invokeMethod('setSize', {
        'width': width,
        'height': height,
      });
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Set size failed: $e');
    }
  }

  @override
  Future<void> setAlwaysOnTop(bool alwaysOnTop) async {
    try {
      await platform.invokeMethod('setAlwaysOnTop', {
        'alwaysOnTop': alwaysOnTop,
      });
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Set always on top failed: $e');
    }
  }

  @override
  Future<void> executeJavaScript(String js) async {
    try {
      await platform.invokeMethod('executeJavaScript', {'code': js});
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Execute JS failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      _isInitialized = false;
      await platform.invokeMethod('dispose');
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Dispose failed: $e');
    }
  }

  /// 请求悬浮窗权限
  Future<bool> requestFloatingWindowPermission() async {
    try {
      final result = await platform.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Request permission failed: $e');
      return false;
    }
  }

  /// 检查悬浮窗权限
  Future<bool> hasFloatingWindowPermission() async {
    try {
      final result = await platform.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      debugPrint('[FloatingWindowAndroid] Check permission failed: $e');
      return false;
    }
  }
}
