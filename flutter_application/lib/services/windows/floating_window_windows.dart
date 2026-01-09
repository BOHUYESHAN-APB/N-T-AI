import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import '../../core/services/backend_service.dart';
import '../floating_window_service.dart';
import '../../windows/window_args.dart';

/// Windows 平台浮窗实现（使用 desktop_multi_window + Flutter Window）
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
  WindowController? _windowController;
  VoidCallback? _onCloseCallback;
  StreamSubscription? _urlSubscription;
  StreamSubscription? _windowChangedSubscription;

  FloatingWindowWindows({required this.backendUrl});

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    _urlSubscription = BackendService().urlStream.listen((url) {
      debugPrint('[FloatingWindowWindows] Received backend URL update: $url');
      updateBackendUrl(url);
    });

    _windowChangedSubscription = onWindowsChanged.listen((_) {
      _syncWindowAlive();
    });

    final currentUrl = BackendService().backendUrl;
    if (currentUrl != backendUrl) {
      updateBackendUrl(currentUrl);
    }
  }

  @override
  void updateBackendUrl(String url) {
    if (backendUrl == url) return;
    backendUrl = url;
    if (_windowController != null) {
      _windowController!.invokeMethod('set_backend_url', {'url': url});
    }
  }

  Future<void> _syncWindowAlive() async {
    if (_windowController == null) return;
    try {
      final controllers = await WindowController.getAll();
      final exists = controllers.any(
        (c) => c.windowId == _windowController!.windowId,
      );
      if (!exists) {
        _handleWindowClosed();
      }
    } catch (_) {}
  }

  void _handleWindowClosed() {
    _activeInstances.remove(this);
    _windowController = null;
    _isVisible = false;
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('floating.window.enabled', false);
    });
    if (_onCloseCallback != null) {
      _onCloseCallback!();
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
    bool showControls = false,
  }) async {
    if (!_isInitialized) {
      throw StateError('FloatingWindowWindows not initialized');
    }

    if (_windowController == null && _activeInstances.length >= maxFloatingWindows) {
      debugPrint(
        '[FloatingWindowWindows] Max floating windows limit reached ($maxFloatingWindows)',
      );
      return;
    }

    if (_windowController != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('floating.window.width', width);
        await prefs.setDouble('floating.window.height', height);
        await prefs.setBool('floating.window.enabled', true);
        if (modelPath.isNotEmpty) {
          await prefs.setString('floating.window.modelPath', modelPath);
        }
        await _windowController!.invokeMethod('set_size', {
          'width': width,
          'height': height,
        });
        await _windowController!.show();
        _isVisible = true;
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Reuse window failed: $e');
      }
      return;
    }

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

    try {
      if (_windowController != null) {
        await closeFloatingWindow();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('floating.window.width', width);
      await prefs.setDouble('floating.window.height', height);
      await prefs.setBool('floating.window.enabled', true);
      if (modelPath.isNotEmpty) {
        await prefs.setString('floating.window.modelPath', modelPath);
      }

      final args = WindowArgs.encode(
        WindowType.live2d,
        {
          'backendUrl': backendUrl,
          'width': width,
          'height': height,
          'showTitleBar': false,
          'showControls': showControls,
        },
      );

      final controller = await WindowController.create(
        WindowConfiguration(
          arguments: args,
          hiddenAtLaunch: true,
        ),
      );
      _windowController = controller;
      _activeInstances.add(this);

      await controller.show();

      _isVisible = true;
      debugPrint('[FloatingWindowWindows] Live2D window created');
    } catch (e) {
      debugPrint('[FloatingWindowWindows] Create window failed: $e');
      try {
        if (e is MissingPluginException) {
          debugPrint(
            '[FloatingWindowWindows] Missing plugin detected, skipping floating window creation.',
          );
          SharedPreferences.getInstance().then((prefs) {
            prefs.setBool('floating.window.enabled', false);
          });
          _windowController = null;
          _isVisible = false;
          return;
        }
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> showFloatingWindow() async {
    if (_windowController != null) {
      await _windowController!.show();
      _isVisible = true;
    }
  }

  @override
  Future<void> hideFloatingWindow() async {
    await closeFloatingWindow();
  }

  @override
  Future<void> closeFloatingWindow() async {
    if (_windowController != null) {
      try {
        await _windowController!.invokeMethod('window_close');
      } catch (_) {}
      _isVisible = false;
      _activeInstances.remove(this);
      _windowController = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('floating.window.enabled', false);
      debugPrint(
        '[FloatingWindowWindows] Live2D window closed (active: ${_activeInstances.length})',
      );
    }
  }

  @override
  Future<bool> isFloatingWindowVisible() async {
    return _isVisible && _windowController != null;
  }

  @override
  Future<void> setPosition(double x, double y) async {
    if (_windowController != null) {
      try {
        await _windowController!.invokeMethod('set_position', {
          'x': x,
          'y': y,
        });
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Set position failed: $e');
      }
    }
  }

  @override
  Future<void> setSize(double width, double height) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('floating.window.width', width);
      await prefs.setDouble('floating.window.height', height);
    } catch (e) {
      debugPrint('[FloatingWindowWindows] Set size failed: $e');
    }
    if (_windowController != null) {
      try {
        await _windowController!.invokeMethod('set_size', {
          'width': width,
          'height': height,
        });
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Set size failed: $e');
      }
    }
  }

  @override
  Future<void> setAlwaysOnTop(bool alwaysOnTop) async {
    if (_windowController != null) {
      try {
        await _windowController!.invokeMethod('set_always_on_top', {
          'value': alwaysOnTop,
        });
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Set always-on-top failed: $e');
      }
    }
  }

  @override
  Future<void> executeJavaScript(String js) async {
    if (_windowController != null) {
      try {
        await _windowController!.invokeMethod('execute_js', {'js': js});
      } catch (e) {
        debugPrint('[FloatingWindowWindows] Execute JS failed: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    _urlSubscription?.cancel();
    _windowChangedSubscription?.cancel();
    await closeFloatingWindow();
    _isInitialized = false;
  }
}
