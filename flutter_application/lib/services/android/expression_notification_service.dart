import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/services/expression_state_bus.dart';
import '../../widgets/expressive_face.dart';

class ExpressionNotificationService {
  ExpressionNotificationService._internal();
  static final ExpressionNotificationService _instance =
      ExpressionNotificationService._internal();
  factory ExpressionNotificationService() => _instance;

  static const MethodChannel _channel =
      MethodChannel('com.bohuyeshan.ntai/notification');

  StreamSubscription<ExpressionData>? _subscription;
  bool _started = false;

  Future<void> start() async {
    if (_started || !Platform.isAndroid) return;
    _started = true;

    try {
      await _channel.invokeMethod('initExpressionNotification');
    } catch (e) {
      debugPrint('[ExpressionNotification] init failed: $e');
    }

    _subscription = ExpressionStateBus().stream.listen(_updateNotification);

    // Push current state once so the notification is present immediately.
    _updateNotification(ExpressionStateBus().latest);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    try {
      await _channel.invokeMethod('clearExpressionNotification');
    } catch (e) {
      debugPrint('[ExpressionNotification] clear failed: $e');
    }
  }

  Future<void> _updateNotification(ExpressionData data) async {
    if (!Platform.isAndroid) return;
    final face = _mapFace(data);
    final payload = <String, String>{
      'title': 'N-T-AI',
      'content': 'Expression: $face',
      'face': face,
    };
    try {
      await _channel.invokeMethod('updateExpressionNotification', payload);
    } catch (e) {
      debugPrint('[ExpressionNotification] update failed: $e');
    }
  }

  String _mapFace(ExpressionData data) {
    if (data.mouth >= 0.6) return ':D';
    if (data.mouth >= 0.2) return ':)';
    if (data.mouth <= -0.6) return 'T_T';
    if (data.mouth <= -0.2) return ':(';
    if (data.eyebrow >= 0.5) return '>:(';
    if (data.eyes <= 0.3) return '-_-';
    if (data.blush >= 0.5) return 'o///o';
    return ':|';
  }
}
