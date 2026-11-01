import 'package:flutter/material.dart';
import 'package:flutter_application/widgets/character_display.dart';
import 'package:flutter_application/core/services/expression_agent_service.dart';
import 'package:flutter_application/widgets/live2d_controller.dart';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 独立浮窗窗口入口（仅显示 Live2D）
class FloatingWindowEntry extends StatefulWidget {
  final String backendUrl;
  final bool showTitleBar;
  final bool showControls;
  final double? initialWidth;
  final double? initialHeight;

  const FloatingWindowEntry({
    super.key,
    required this.backendUrl,
    this.showTitleBar = true,
    this.showControls = true,
    this.initialWidth,
    this.initialHeight,
  });

  @override
  State<FloatingWindowEntry> createState() => _FloatingWindowEntryState();
}

class _FloatingWindowEntryState extends State<FloatingWindowEntry> {
  final ExpressionAgentService _expressionAgent = ExpressionAgentService();
  final Live2DController _live2dController = Live2DController();
  late String _backendUrl;
  Key _webKey = const ValueKey('live2d-window');

  @override
  void initState() {
    super.initState();
    _backendUrl = widget.backendUrl;
    _webKey = ValueKey('live2d-${widget.backendUrl}');
    _initWindow();
    _initWindowChannel();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();

    final width = widget.initialWidth ?? 400;
    final height = widget.initialHeight ?? 600;

    // 配置窗口属性（标题栏由 Flutter 自定义）
    WindowOptions windowOptions = WindowOptions(
      size: Size(width, height),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: !widget.showTitleBar,
      titleBarStyle: TitleBarStyle.hidden, // 隐藏原生标题栏，使用自定义
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (!widget.showTitleBar) {
        await windowManager.setAsFrameless();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  Future<void> _initWindowChannel() async {
    try {
      final controller = await WindowController.fromCurrentEngine();
      await controller.setWindowMethodHandler((call) async {
        switch (call.method) {
          case 'execute_js':
            final args = call.arguments;
            if (args is Map && args['js'] != null) {
              await _live2dController.executeJs(args['js'].toString());
            }
            return true;
          case 'reload':
            await _live2dController.reload();
            return true;
          case 'set_backend_url':
            final args = call.arguments;
            if (args is Map && args['url'] != null) {
              final nextUrl = args['url'].toString();
              if (nextUrl.isNotEmpty && nextUrl != _backendUrl) {
                setState(() {
                  _backendUrl = nextUrl;
                  _webKey = ValueKey('live2d-$nextUrl');
                });
              }
            }
            return true;
          case 'window_close':
            try {
              await windowManager.close();
            } catch (_) {
              try {
                await windowManager.destroy();
              } catch (_) {}
            }
            return true;
          case 'set_size':
            final args = call.arguments;
            if (args is Map) {
              final w = (args['width'] as num?)?.toDouble();
              final h = (args['height'] as num?)?.toDouble();
              if (w != null && h != null) {
                await windowManager.setSize(Size(w, h));
              }
            }
            return true;
          case 'set_position':
            final args = call.arguments;
            if (args is Map) {
              final x = (args['x'] as num?)?.toDouble();
              final y = (args['y'] as num?)?.toDouble();
              if (x != null && y != null) {
                await windowManager.setPosition(Offset(x, y));
              }
            }
            return true;
          case 'set_always_on_top':
            final args = call.arguments;
            if (args is Map) {
              final flag = args['value'] == true;
              await windowManager.setAlwaysOnTop(flag);
            }
            return true;
          default:
            return null;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _expressionAgent.dispose();
    _live2dController.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useTransparentBg = !widget.showTitleBar;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(), // 使用亮色主题以配合白色标题栏
      home: Scaffold(
        backgroundColor: useTransparentBg ? Colors.transparent : Colors.white,
        body: Stack(
          children: [
            Column(
              children: [
                // 自定义标题栏（白色背景）
                if (widget.showTitleBar) _buildCustomTitleBar(),
                // Live2D 内容区域
                Expanded(
                  child: CharacterDisplay(
                    key: _webKey,
                    backendUrl: _backendUrl,
                    expressionAgent: _expressionAgent,
                    controller: _live2dController,
                    floatingUi: true,
                    showControls: widget.showControls, // 悬浮控件仅保留气泡/字幕/刷新
                  ),
                ),
              ],
            ),
            if (!widget.showTitleBar)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 28,
                child: DragToMoveArea(
                  child: Container(color: Colors.transparent),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 自定义标题栏（白色背景，可拖动窗口，带关闭按钮）
  Widget _buildCustomTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        // 拖动窗口
        windowManager.startDragging();
      },
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.animation, size: 18, color: Colors.grey[700]),
            const SizedBox(width: 8),
            Text(
              'Live2D',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, size: 18, color: Colors.grey[600]),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () async {
                try {
                  await windowManager.close();
                } catch (_) {
                  try {
                    await windowManager.destroy();
                  } catch (_) {}
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
