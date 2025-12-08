import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Live2D 广播服务
/// 将表情/动作指令广播到后端 WebSocket，所有 Live2D 客户端都会收到
class Live2DBroadcastService {
  static final Live2DBroadcastService _instance =
      Live2DBroadcastService._internal();
  factory Live2DBroadcastService() => _instance;
  Live2DBroadcastService._internal();

  String _backendUrl = 'http://localhost:8000';
  bool _enabled = false;

  /// 设置后端 URL
  void setBackendUrl(String url) {
    _backendUrl = url;
  }

  /// 启用/禁用广播
  void setEnabled(bool enabled) {
    _enabled = enabled;
    debugPrint('[Live2DBroadcast] Enabled: $enabled');
  }

  bool get isEnabled => _enabled;

  /// 广播表情参数
  Future<void> broadcastExpression({
    required double mouth,
    required double eyes,
    required double eyebrow,
    required double blush,
    required double pupilX,
    required double pupilY,
    required double headTilt,
  }) async {
    if (!_enabled) return;

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/api/live2d/broadcast/expression'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'mouth': mouth,
          'eyes': eyes,
          'eyebrow': eyebrow,
          'blush': blush,
          'pupilX': pupilX,
          'pupilY': pupilY,
          'headTilt': headTilt,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          '[Live2DBroadcast] Expression broadcast failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[Live2DBroadcast] Expression broadcast error: $e');
    }
  }

  /// 广播动作请求
  Future<void> broadcastMotion({
    required String userText,
    required String aiText,
  }) async {
    if (!_enabled) return;

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/api/live2d/broadcast/motion'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userText': userText, 'aiText': aiText}),
      );

      if (response.statusCode != 200) {
        debugPrint(
          '[Live2DBroadcast] Motion broadcast failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[Live2DBroadcast] Motion broadcast error: $e');
    }
  }

  /// 获取当前连接数
  Future<int> getConnectionCount() async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/api/live2d/connections'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['count'] as int? ?? 0;
      }
    } catch (e) {
      debugPrint('[Live2DBroadcast] Get connections error: $e');
    }
    return 0;
  }
}
