import 'dart:io';
import '../settings/settings.dart';
import 'floating_window_service.dart';
import 'android/floating_window_android.dart';
import 'windows/floating_window_windows.dart';

/// 浮窗服务工厂
class FloatingWindowServiceFactory {
  static FloatingWindowService? _instance;

  /// 获取平台特定的浮窗服务实例
  static FloatingWindowService getInstance({required String backendUrl}) {
    if (_instance != null) {
      return _instance!;
    }

    if (Platform.isWindows) {
      _instance = FloatingWindowWindows(backendUrl: backendUrl);
    } else if (Platform.isAndroid) {
      _instance = FloatingWindowAndroid(backendUrl: backendUrl);
    } else {
      throw UnsupportedError('Floating window not supported on this platform');
    }

    return _instance!;
  }

  /// 重置实例（用于测试）
  static void reset() {
    _instance = null;
  }

  /// 检查当前平台是否支持浮窗
  static bool isSupported() {
    return Platform.isWindows || Platform.isAndroid;
  }

  /// 获取平台名称
  static String getPlatform() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isAndroid) return 'Android';
    return 'Unknown';
  }
}
