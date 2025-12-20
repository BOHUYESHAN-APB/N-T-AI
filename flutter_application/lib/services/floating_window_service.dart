import 'dart:ui';

/// 浮窗服务基础接口
abstract class FloatingWindowService {
  /// 初始化浮窗服务
  Future<void> initialize();

  /// 更新后端 URL
  void updateBackendUrl(String url);

  /// 设置窗口关闭回调
  void setOnCloseCallback(VoidCallback callback);

  /// 创建浮窗
  /// [modelPath] - Live2D 模型路径
  /// [width] - 窗口宽度
  /// [height] - 窗口高度
  Future<void> createFloatingWindow({
    required String modelPath,
    required double width,
    required double height,
  });

  /// 显示浮窗
  Future<void> showFloatingWindow();

  /// 隐藏浮窗
  Future<void> hideFloatingWindow();

  /// 关闭浮窗
  Future<void> closeFloatingWindow();

  /// 检查浮窗是否可见
  Future<bool> isFloatingWindowVisible();

  /// 设置浮窗位置
  /// [x, y] - 相对于屏幕的坐标
  Future<void> setPosition(double x, double y);

  /// 设置浮窗大小
  /// [width, height] - 浮窗尺寸
  Future<void> setSize(double width, double height);

  /// 设置浮窗始终在顶层
  /// [alwaysOnTop] - 是否始终在顶层
  Future<void> setAlwaysOnTop(bool alwaysOnTop);

  /// 执行 JavaScript
  Future<void> executeJavaScript(String js);

  /// 释放资源
  Future<void> dispose();
}
