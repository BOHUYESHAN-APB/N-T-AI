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
  static const int _minIntervalSeconds = 10;
  static const int _maxIntervalSeconds = 50;
  static const double _meanIntervalSeconds = 20.0;
  static const double _stdDevIntervalSeconds = 8.0;
  final Random _rng = Random();
  Timer? _timer;
  bool _isProcessing = false;
  bool _enabled = false;

  // Callback to inject the awareness message into the current session
  Function(String description)? onAwarenessGenerated;

  void start(AppSettings settings) {
    stop();
    if (!settings.enableScreenCapture) return;
    _enabled = true;
    logger.info('ScreenCaptureService started with random interval: ${_minIntervalSeconds}s-${_maxIntervalSeconds}s');
    _scheduleNext(settings);
  }

  void stop() {
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    logger.info('ScreenCaptureService stopped');
  }

  void _scheduleNext(AppSettings settings) {
    if (!_enabled) return;
    final delaySeconds = _nextIntervalSeconds();
    logger.info('Next screen capture in ${delaySeconds.toStringAsFixed(1)}s');
    _timer = Timer(
      Duration(milliseconds: (delaySeconds * 1000).round()),
      () => _captureAndAnalyze(settings),
    );
  }

  double _nextIntervalSeconds() {
    final value = _gaussian(_meanIntervalSeconds, _stdDevIntervalSeconds);
    if (value < _minIntervalSeconds) return _minIntervalSeconds.toDouble();
    if (value > _maxIntervalSeconds) return _maxIntervalSeconds.toDouble();
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

  String _buildScreenInjectionPrompt(AppSettings settings) {
    final base = settings.screenInjectionPrompt;
    if (settings.primaryMode != PrimaryModeOption.live) {
      return base;
    }
    return '$base（直播）';
  }

  Future<void> _captureAndAnalyze(AppSettings settings) async {
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

        // Call vision model
        final description = await _llmService.chatWithImage(
          messages: [
            {'role': 'system', 'content': _buildScreenAnalysisPrompt(settings)},
          ],
          imageBytes: imageBytes,
          prompt: '请分析这张屏幕截图。',
          usageType: 'vision',
          providerIdOverride: settings.activeVisionProviderId, // Use vision specific provider if configured
        );

        if (description.isNotEmpty && onAwarenessGenerated != null) {
          final injectedMessage =
              '${_buildScreenInjectionPrompt(settings)}\n$description';
          onAwarenessGenerated!(injectedMessage);
        }
        
        // Clean up
        await file.delete();
      }
    } catch (e) {
      logger.error('ScreenCaptureService error: $e');
    } finally {
      _isProcessing = false;
      _scheduleNext(settings);
    }
  }
}
