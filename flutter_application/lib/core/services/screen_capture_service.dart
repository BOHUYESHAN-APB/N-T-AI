import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
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
  Timer? _timer;
  bool _isProcessing = false;

  // Callback to inject the awareness message into the current session
  Function(String description)? onAwarenessGenerated;

  void start(AppSettings settings) {
    stop();
    if (!settings.enableScreenCapture) return;

    logger.info('ScreenCaptureService started with interval: ${settings.screenCaptureInterval}s');
    _timer = Timer.periodic(Duration(seconds: settings.screenCaptureInterval), (timer) {
      _captureAndAnalyze(settings);
    });
    
    // Also trigger one immediately
    _captureAndAnalyze(settings);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    logger.info('ScreenCaptureService stopped');
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
            {'role': 'system', 'content': settings.screenAnalysisPrompt},
          ],
          imageBytes: imageBytes,
          prompt: '请分析这张屏幕截图。',
          usageType: 'vision',
          providerIdOverride: settings.activeVisionProviderId, // Use vision specific provider if configured
        );

        if (description.isNotEmpty && onAwarenessGenerated != null) {
          final injectedMessage = '${settings.screenInjectionPrompt}\n$description';
          onAwarenessGenerated!(injectedMessage);
        }
        
        // Clean up
        await file.delete();
      }
    } catch (e) {
      logger.error('ScreenCaptureService error: $e');
    } finally {
      _isProcessing = false;
    }
  }
}
