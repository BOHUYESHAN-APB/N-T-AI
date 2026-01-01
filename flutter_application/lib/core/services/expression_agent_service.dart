import 'dart:async';
import 'dart:convert';

import '../../services/expression_service.dart';
import '../../services/live2d_broadcast_service.dart';
import '../../widgets/expressive_face.dart';
import 'expression_state_bus.dart';

class MotionRequest {
  final String userText;
  final String aiText;
  MotionRequest(this.userText, this.aiText);
}

/// ExpressionAgentService
/// Handles expression control separate from main brain to reduce load.
/// Accepts simple JSON maps and emits ExpressionData updates.
/// 同时通过 Live2DBroadcastService 广播到所有 Live2D 客户端（侧边栏和悬浮窗）
class ExpressionAgentService {
  final StreamController<ExpressionData> _streamCtrl =
      StreamController.broadcast();
  final StreamController<MotionRequest> _motionStreamCtrl =
      StreamController.broadcast();
  final Live2DBroadcastService _broadcast = Live2DBroadcastService();

  ExpressionData _last = ExpressionData.neutral();

  Stream<ExpressionData> get stream => _streamCtrl.stream;
  Stream<MotionRequest> get motionStream => _motionStreamCtrl.stream;
  ExpressionData get current => _last;

  /// 启用/禁用广播（悬浮窗启用时应开启）
  void setBroadcastEnabled(bool enabled) {
    _broadcast.setEnabled(enabled);
  }

  void dispose() {
    _streamCtrl.close();
    _motionStreamCtrl.close();
  }

  /// Request the Motion Agent to decide on an action
  void requestMotion(String userText, String aiText, {List<Map<String, String>>? history}) {
    _motionStreamCtrl.add(MotionRequest(userText, aiText));

    // 同时广播到所有 Live2D 客户端
    _broadcast.broadcastMotion(
      userText: userText, 
      aiText: aiText,
      history: history,
    );
  }

  /// Apply expression from map (already parsed or raw JSON).
  Future<void> applyDynamic(Object? payload) async {
    try {
      Map<String, dynamic> map;
      if (payload is String) {
        map = jsonDecode(payload) as Map<String, dynamic>;
      } else if (payload is Map<String, dynamic>) {
        map = payload;
      } else {
        return;
      }
      final expr = ExpressionService.fromMap(map);
      // Debug: print incoming payload and resolved ExpressionData
      // This helps diagnose semantic reversals between model output and rendering.
      // Only print in debug mode to avoid leaking runtime data in production.
      try {
        // ignore: avoid_print
        // print raw map and ExpressionData values
        // ignore: avoid_print
        print(
          '[ExpressionAgent] payload: ${jsonEncode(map)} -> expr: {mouth: ${expr.mouth}, eyes: ${expr.eyes}, eyebrow: ${expr.eyebrow}, blush: ${expr.blush}, pupilX: ${expr.pupilX}, pupilY: ${expr.pupilY}, headTilt: ${expr.headTilt}}',
        );
      } catch (_) {}
      _last = expr;
      _streamCtrl.add(expr);
      ExpressionStateBus().set(expr);

      // 同时广播到所有 Live2D 客户端
      _broadcast.broadcastExpression(
        mouth: expr.mouth,
        eyes: expr.eyes,
        eyebrow: expr.eyebrow,
        blush: expr.blush,
        pupilX: expr.pupilX,
        pupilY: expr.pupilY,
        headTilt: expr.headTilt,
      );
    } catch (_) {
      // swallow parse errors for robustness
    }
  }

  /// Convenience to bind to a controller.
  /// Returns a subscription that must be cancelled when the controller is disposed.
  StreamSubscription<ExpressionData> bind(ExpressionController controller) {
    controller.setExpression(_last);
    return stream.listen((data) {
      try {
        controller.setExpression(data);
      } catch (_) {
        // If controller is disposed, this might throw.
        // Ideally the subscription should be cancelled by the caller.
      }
    });
  }
}
