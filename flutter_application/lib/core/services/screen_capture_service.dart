import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:path_provider/path_provider.dart';
import 'llm_service.dart';
import '../../settings/settings.dart';
import '../../services/logger_service.dart';

class ScreenCaptureService {
  static final ScreenCaptureService _instance = ScreenCaptureService._internal();
  factory ScreenCaptureService() => _instance;
  ScreenCaptureService._internal();

  final LLMService _llmService = LLMService();
  static const int _randomMinIntervalSeconds = 10;
  static const int _randomMaxIntervalSeconds = 50;
  static const double _meanIntervalSeconds = 20.0;
  static const double _stdDevIntervalSeconds = 8.0;
  static const int _minFixedIntervalSeconds = 5;
  final Random _rng = Random();
  Timer? _timer;
  bool _isProcessing = false;
  bool _enabled = false;

  // Callback to deliver the raw screen description
  Function(String description)? onAwarenessGenerated;

  void start(AppSettings settings) {
    stop();
    if (!settings.enableScreenCapture) return;
    _enabled = true;
    if (settings.screenCaptureInterval > 0) {
      logger.info(
        'ScreenCaptureService started with fixed interval: ${settings.screenCaptureInterval}s',
      );
    } else {
      logger.info(
        'ScreenCaptureService started with random interval: ${_randomMinIntervalSeconds}s-${_randomMaxIntervalSeconds}s',
      );
    }
    _scheduleNext(settings);
  }

  void stop() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    logger.info('ScreenCaptureService stopped');
  }

  Future<void> captureOnce(AppSettings settings) async {
    await _captureAndAnalyze(settings, reschedule: false);
  }

  void _scheduleNext(AppSettings settings) {
    if (!_enabled) return;
    final delaySeconds = _nextIntervalSeconds(settings);
    logger.info('Next screen capture in ${delaySeconds.toStringAsFixed(1)}s');
    _timer = Timer(
      Duration(milliseconds: (delaySeconds * 1000).round()),
      () => _captureAndAnalyze(settings),
    );
  }

  double _nextIntervalSeconds(AppSettings settings) {
    final fixed = settings.screenCaptureInterval;
    if (fixed > 0) {
      final clamped = fixed < _minFixedIntervalSeconds
          ? _minFixedIntervalSeconds
          : fixed;
      return clamped.toDouble();
    }
    return _nextRandomIntervalSeconds();
  }

  double _nextRandomIntervalSeconds() {
    final value = _gaussian(_meanIntervalSeconds, _stdDevIntervalSeconds);
    if (value < _randomMinIntervalSeconds) {
      return _randomMinIntervalSeconds.toDouble();
    }
    if (value > _randomMaxIntervalSeconds) {
      return _randomMaxIntervalSeconds.toDouble();
    }
    return value;
  }

  double _gaussian(double mean, double stdDev) {
    final u1 = _rng.nextDouble().clamp(1e-12, 1.0);
    final u2 = _rng.nextDouble();
    final z0 = sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
    return mean + z0 * stdDev;
  }

  String _buildScreenAnalysisPrompt(AppSettings settings) {
    final base = settings.screenAnalysisPrompt;
    if (settings.primaryMode != PrimaryModeOption.live) {
      return base;
    }

    final modeHint = switch (settings.liveMode) {
      LiveModeOption.watch =>
          '当前为“你玩、AI看”，仅解说与搞效果，不参与操作。',
      LiveModeOption.coPlay =>
          '当前为“你玩+AI玩”，需要解说并增强互动效果。',
      LiveModeOption.autoPlay =>
          '当前为“AI玩、你看”，强调任务进展与节目效果。',
    };
    return '$base\n\n[直播解说要求]: 语气可幽默夸张，突出节目效果，保持简洁。\n$modeHint';
  }

  Future<void> _captureAndAnalyze(
    AppSettings settings, {
    bool reschedule = true,
  }) async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final directory = await getTemporaryDirectory();
      final String path = '${directory.path}/screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      
      final CapturedData? capturedData = await screenCapturer.capture(
        mode: CaptureMode.screen,
        imagePath: path,
        silent: true,
      );

      if (capturedData != null && capturedData.imagePath != null) {
        final File file = File(capturedData.imagePath!);
        final Uint8List imageBytes = await file.readAsBytes();
        
        logger.info('Screenshot captured, size: ${imageBytes.length} bytes. Analyzing...');

        String? providerOverride = settings.activeVisionProviderId;
        if (settings.useMainVisionIfCapable) {
          final mainVisionCapable =
              await _llmService.isActiveModelVisionCapable();
          if (mainVisionCapable) {
            providerOverride = null;
          }
        }

        // Call vision model
        final description = await _llmService.chatWithImage(
          messages: [
            {'role': 'system', 'content': _buildScreenAnalysisPrompt(settings)},
          ],
          imageBytes: imageBytes,
          prompt: '请分析这张屏幕截图。',
          usageType: 'vision',
          providerIdOverride: providerOverride,
        );

        if (description.isNotEmpty && onAwarenessGenerated != null) {
          onAwarenessGenerated!(description);
        }
        
        // Clean up
        await file.delete();
      }
    } catch (e) {
      logger.error('ScreenCaptureService error: $e');
    } finally {
      _isProcessing = false;
      if (reschedule) {
        _scheduleNext(settings);
      }
    }
  }
}
