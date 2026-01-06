import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../services/logger_service.dart';

class WebSocketService {
  WebSocket? _webSocket;
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  final StreamController<bool> _statusController = StreamController.broadcast();
  Stream<bool> get statusStream => _statusController.stream;
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  Timer? _reconnectTimer;
  String? _lastUrl;
  bool _disposed = false;

  bool send(Map<String, dynamic> message) {
    if (_disposed) return false;
    if (_webSocket == null || !_isConnected) return false;
    try {
      _webSocket!.add(jsonEncode(message));
      return true;
    } catch (e) {
      debugPrint('[WebSocket] Send failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_disposed) return;
    final url = _lastUrl;
    _lastUrl = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    if (_webSocket != null) {
      try {
        // 显式检查状态，避免在已关闭或关闭中时再次调用
        final socket = _webSocket!;
        _webSocket = null; // 先置空，防止重入
        
        // 尝试正常关闭
        await socket.close().timeout(
          const Duration(seconds: 1),
          onTimeout: () => throw TimeoutException('WebSocket close timeout'),
        );
        logger.info('WebSocket 连接已主动关闭: $url');
      } catch (e) {
        logger.warning('WebSocket 关闭时发生异常 (url: $url): $e');
      }
    }
    
    _isConnected = false;
    _notifyStatus();
  }

  void _notifyStatus() {
    if (_disposed) return;
    _statusController.add(_isConnected);
  }

  void connect(String url) async {
    if (_disposed) return;
    // Avoid duplicate connection to same URL
    if (_isConnected && _lastUrl == url) return;
    if (_isConnected) {
      await _webSocket?.close();
    }
    if (_disposed) return;
    
    _lastUrl = url;
    
    try {
      // Convert http/https to ws/wss
      String wsUrl = url.replaceAll('http://', 'ws://').replaceAll('https://', 'wss://');
      
      // Ensure path is correct
      if (wsUrl.endsWith('/')) {
         wsUrl += 'api/live2d/ws';
      } else if (!wsUrl.endsWith('/api/live2d/ws')) {
         wsUrl += '/api/live2d/ws';
      }
      
      debugPrint('[WebSocket] Connecting to $wsUrl');
      _webSocket = await WebSocket.connect(wsUrl);
      if (_disposed) {
        try {
          await _webSocket?.close();
        } catch (_) {}
        _webSocket = null;
        return;
      }
      _isConnected = true;
      _notifyStatus();
      debugPrint('[WebSocket] Connected');
      
      _webSocket!.listen(
        (data) {
          try {
            if (data is String) {
              final json = jsonDecode(data);
              _messageController.add(json);
            }
          } catch (e) {
            debugPrint('[WebSocket] Parse error: $e');
          }
        },
        onDone: () {
          debugPrint('[WebSocket] Disconnected');
          _isConnected = false;
          _notifyStatus();
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint('[WebSocket] Error: $e');
          _isConnected = false;
          _notifyStatus();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[WebSocket] Connection failed: $e');
      _isConnected = false;
      _notifyStatus();
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectTimer?.isActive ?? false) return;
    
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      if (_lastUrl != null) connect(_lastUrl!);
    });
  }
  
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _webSocket?.close();
    _messageController.close();
    _statusController.close();
  }
}
