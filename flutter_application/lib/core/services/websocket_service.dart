import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class WebSocketService {
  WebSocket? _webSocket;
  final StreamController<Map<String, dynamic>> _messageController = StreamController.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  
  bool _isConnected = false;
  Timer? _reconnectTimer;
  String? _lastUrl;

  void connect(String url) async {
    // Avoid duplicate connection to same URL
    if (_isConnected && _lastUrl == url) return;
    if (_isConnected) {
      await _webSocket?.close();
    }
    
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
      _isConnected = true;
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
          _scheduleReconnect();
        },
        onError: (e) {
          debugPrint('[WebSocket] Error: $e');
          _isConnected = false;
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[WebSocket] Connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_lastUrl != null) connect(_lastUrl!);
    });
  }
  
  void dispose() {
    _reconnectTimer?.cancel();
    _webSocket?.close();
    _messageController.close();
  }
}
