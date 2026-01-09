import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import '../settings/settings_controller.dart';
import '../settings/settings.dart';

class ControlWindowBridge {
  static final WindowMethodChannel _channel = WindowMethodChannel(
    'ntai/main_control',
    mode: ChannelMode.unidirectional,
  );

  static Future<void> register(SettingsController controller) async {
    await _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'get_state':
          return _snapshot(controller.settings);
        case 'apply_setting':
          final args = call.arguments;
          if (args is Map) {
            await _applySetting(controller, args.cast<String, dynamic>());
            return _snapshot(controller.settings);
          }
          throw PlatformException(
            code: 'INVALID_ARGUMENTS',
            message: 'apply_setting expects a map payload',
          );
        default:
          throw MissingPluginException('Unknown method: ${call.method}');
      }
    });
  }

  static Map<String, dynamic> _snapshot(AppSettings settings) {
    return {
      'enableTts': settings.enableTts,
      'enableStt': settings.enableStt,
      'autoMicListening': settings.autoMicListening,
      'sttViaBackendLoopback': settings.sttViaBackendLoopback,
      'autoVoiceChannelListening': settings.autoVoiceChannelListening,
      'enableScreenCapture': settings.enableScreenCapture,
      'primaryMode': settings.primaryMode.name,
      'liveMode': settings.liveMode.name,
      'enablePythonBackend': settings.enablePythonBackend,
      'backendUrl': settings.pythonBackendUrl,
    };
  }

  static Future<void> _applySetting(
    SettingsController controller,
    Map<String, dynamic> payload,
  ) async {
    final key = payload['key']?.toString() ?? '';
    final value = payload['value'];
    switch (key) {
      case 'enableTts':
        await controller.setEnableTts(value == true);
        return;
      case 'enableStt':
        await controller.setEnableStt(value == true);
        return;
      case 'autoMicListening':
        await controller.setAutoMicListening(value == true);
        return;
      case 'sttViaBackendLoopback':
        await controller.setSttViaBackendLoopback(value == true);
        return;
      case 'autoVoiceChannelListening':
        await controller.setAutoVoiceChannelListening(value == true);
        return;
      case 'enableScreenCapture':
        await controller.setEnableScreenCapture(value == true);
        return;
      case 'primaryMode':
        await controller.setPrimaryMode(_parsePrimaryMode(value?.toString()));
        return;
      case 'liveMode':
        await controller.setLiveMode(_parseLiveMode(value?.toString()));
        return;
      default:
        throw PlatformException(
          code: 'UNKNOWN_SETTING',
          message: 'Unknown setting key: $key',
        );
    }
  }

  static PrimaryModeOption _parsePrimaryMode(String? value) {
    switch (value) {
      case 'live':
        return PrimaryModeOption.live;
      case 'assistant':
      default:
        return PrimaryModeOption.assistant;
    }
  }

  static LiveModeOption _parseLiveMode(String? value) {
    switch (value) {
      case 'watch':
        return LiveModeOption.watch;
      case 'coPlay':
        return LiveModeOption.coPlay;
      case 'autoPlay':
        return LiveModeOption.autoPlay;
      default:
        return LiveModeOption.watch;
    }
  }
}
