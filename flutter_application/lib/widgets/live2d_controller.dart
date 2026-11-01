import 'package:flutter/foundation.dart';

/// Controller to interact with the Live2D character in CharacterDisplay
class Live2DController {
  // Function to execute JS, set by the CharacterDisplay state
  Future<void> Function(String js)? _executeJs;

  void attach(Future<void> Function(String js) executeJs) {
    _executeJs = executeJs;
  }

  void detach() {
    _executeJs = null;
  }

  Future<void> executeJs(String js) async {
    if (_executeJs != null) {
      try {
        await _executeJs!(js);
      } catch (e) {
        debugPrint('[Live2DController] JS execution failed: $e');
      }
    } else {
      debugPrint('[Live2DController] Controller not attached');
    }
  }

  Future<void> reload() async {
    await executeJs("window.location.reload();");
  }

  Future<void> toggleLock() async {
    await executeJs("window.dispatchEvent(new CustomEvent('live2d-lock-click'));");
  }

  Future<void> setMouseTracking(bool enabled) async {
    await executeJs("if(window.live2dManager) { window.live2dManager.mouseTrackingEnabled = $enabled; }");
  }
}
