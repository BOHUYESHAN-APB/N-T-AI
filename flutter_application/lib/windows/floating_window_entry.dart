import 'package:flutter/material.dart';
import 'package:flutter_application/widgets/character_display.dart';
import 'package:flutter_application/core/services/expression_agent_service.dart';
import 'package:window_manager/window_manager.dart';

/// 独立浮窗窗口入口（仅显示 Live2D）
class FloatingWindowEntry extends StatefulWidget {
  final String backendUrl;
  final bool showTitleBar;

  const FloatingWindowEntry({
    Key? key,
    required this.backendUrl,
    this.showTitleBar = true,
  }) : super(key: key);

  @override
  State<FloatingWindowEntry> createState() => _FloatingWindowEntryState();
}

class _FloatingWindowEntryState extends State<FloatingWindowEntry> {
  final ExpressionAgentService _expressionAgent = ExpressionAgentService();

  @override
  void initState() {
    super.initState();
    _initWindow();
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();

    // 配置窗口属性（带标题栏，可以拖动和调整大小）
    WindowOptions windowOptions = const WindowOptions(
      size: Size(400, 600),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 隐藏原生标题栏，使用自定义
    );

    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  void dispose() {
    _expressionAgent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(), // 使用亮色主题以配合白色标题栏
      home: Scaffold(
        backgroundColor: Colors.white, // 白色背景而非透明
        body: Column(
          children: [
            // 自定义标题栏（白色背景）
            if (widget.showTitleBar) _buildCustomTitleBar(),
            // Live2D 内容区域
            Expanded(
              child: CharacterDisplay(
                backendUrl: widget.backendUrl,
                expressionAgent: _expressionAgent,
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
              color: Colors.black.withOpacity(0.1),
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
                // 关闭当前窗口
                await windowManager.close();
              },
            ),
          ],
        ),
      ),
    );
  }
}
