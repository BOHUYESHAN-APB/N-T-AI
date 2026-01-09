import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'llm_service.dart';
import '../tools/agent_tool.dart';
import '../tools/clock_tool.dart';
import '../tools/web_browser_tool.dart';
import 'expression_agent_service.dart';
import 'avatar3d_agent_service.dart';
import '../../services/expression_service.dart';
import 'expression_inference_agent_service.dart';
import 'expression_state_bus.dart';
import '../../settings/settings.dart';
import '../../services/ai_client.dart';
import '../../services/logger_service.dart';

class BrainService {
  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{200D}\u{FE0E}\u{FE0F}]',
    unicode: true,
  );

  // 角色职责说明:
  // BrainService: 仅负责主对话与工具循环，不再要求模型内联输出表情 JSON；
  // ExpressionInferenceAgentService: 基于最终文本进行轻量情绪→参数推理（启发式或独立小模型）；
  // ExpressionAgentService: 只接收结构化参数并驱动 UI 表情渲染，不参与推理；
  // （这样减少主脑上下文污染与 token 开销，允许后续独立选择更小的模型用于表情推理）。
  final LLMService _llmService = LLMService();
  // Separate agents to reduce main brain load
  final ExpressionAgentService _expressionAgent = ExpressionAgentService();
  final Avatar3DAgentService _avatar3DAgent = Avatar3DAgentService();
  final ExpressionInferenceAgentService _expressionInference = ExpressionInferenceAgentService();

  // Expose agents for UI binding
  ExpressionAgentService get expressionAgent => _expressionAgent;
  Avatar3DAgentService get avatar3dAgent => _avatar3DAgent;
  
  // Status stream for UI updates
  final _statusController = StreamController<String>.broadcast();
  Stream<String> get statusStream => _statusController.stream;

  final _ttsController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get ttsStream => _ttsController.stream;

  int _ttsSessionId = 0;
  bool _ttsStopped = false;
  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;
  
  // 用于追踪后台正在进行的 TTS 任务数量
  int _activeTtsCount = 0;
  bool get isAnyTtsActive => _activeTtsCount > 0 || _isSpeaking;

  static const int _maxTtsTempFiles = 5;
  final List<File> _ttsTempFiles = [];

  // Context window (Short-term memory)
  // This is now managed by the UI/ChatHistoryService, but we keep a local buffer for the current turn
  List<Map<String, String>> _context = [];

  // Tools
  final Map<String, AgentTool> _tools = {
    'web_search': WebSearchTool(),
    'visit_page': WebPageReaderTool(),
    'get_current_time': ClockTool(),
  };

  void dispose() {
    _statusController.close();
    _expressionAgent.dispose();
    _avatar3DAgent.dispose();
    _ttsController.close();
  }

  // Update context from outside (for multi-session support)
  void setContext(List<Map<String, String>> context) {
    _context = List.from(context);
  }

  AudioPlayer? _audioPlayer;

  Future<void> _trackTtsTempFile(File file) async {
    _ttsTempFiles.add(file);
    final overflow = _ttsTempFiles.length - _maxTtsTempFiles;
    if (overflow <= 0) return;
    for (var i = 0; i < overflow; i++) {
      final old = _ttsTempFiles.removeAt(0);
      try {
        if (await old.exists()) {
          await old.delete();
        }
      } catch (_) {}
    }
  }

  bool _looksLikeWav(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final isRiff = bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46;
    final isRf64 = bytes[0] == 0x52 &&
        bytes[1] == 0x46 &&
        bytes[2] == 0x36 &&
        bytes[3] == 0x34;
    final isWave = bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45;
    return (isRiff || isRf64) && isWave;
  }

  bool _looksLikeMp3(Uint8List bytes) {
    if (bytes.length < 3) return false;
    if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
    if (bytes.length >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) {
      return true;
    }
    return false;
  }

  Uint8List _wrapPcm16LeToWav(
    Uint8List pcmBytes, {
    int sampleRate = 44100,
    int channels = 1,
  }) {
    final byteRate = sampleRate * channels * 2;
    final blockAlign = channels * 2;
    final dataSize = pcmBytes.length;
    final fileSize = 36 + dataSize;

    final header = BytesBuilder(copy: false);
    header.add(utf8.encode('RIFF'));
    header.add(_u32le(fileSize));
    header.add(utf8.encode('WAVE'));
    header.add(utf8.encode('fmt '));
    header.add(_u32le(16));
    header.add(_u16le(1));
    header.add(_u16le(channels));
    header.add(_u32le(sampleRate));
    header.add(_u32le(byteRate));
    header.add(_u16le(blockAlign));
    header.add(_u16le(16));
    header.add(utf8.encode('data'));
    header.add(_u32le(dataSize));
    header.add(pcmBytes);
    return header.takeBytes();
  }

  Uint8List _u16le(int v) => Uint8List(2)
    ..[0] = (v & 0xFF)
    ..[1] = ((v >> 8) & 0xFF);

  Uint8List _u32le(int v) => Uint8List(4)
    ..[0] = (v & 0xFF)
    ..[1] = ((v >> 8) & 0xFF)
    ..[2] = ((v >> 16) & 0xFF)
    ..[3] = ((v >> 24) & 0xFF);

  Future<void> _broadcastTtsBytes(Uint8List bytes, {String? source}) async {
    unawaited(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final backendUrl =
            prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
        final urlStr = backendUrl.endsWith('/')
            ? backendUrl.substring(0, backendUrl.length - 1)
            : backendUrl;
        final response = await http.post(
          Uri.parse('$urlStr/api/live2d/broadcast/audio'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'audio': base64Encode(bytes),
            if (source != null) 'source': source,
          }),
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final clientCount = json['clients'] as int;
          if (clientCount > 0) {
            debugPrint('[BrainService] Audio broadcasted to $clientCount Live2D clients.');
          } else {
            debugPrint('[BrainService] No Live2D clients connected for audio broadcast.');
          }
        } else {
          debugPrint('[BrainService] Audio broadcast failed: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('[BrainService] Audio broadcast error: $e');
      }
    }());
  }

  void _emitTtsSignal(Uint8List bytes, {String? source}) {
    _ttsController.add(bytes);
    unawaited(_broadcastTtsBytes(bytes, source: source));
  }

  Future<String?> _injectWavToBackend({
    required String backendBase,
    required Uint8List wavBytes,
    required int? deviceIndex,
  }) async {
    if (!_looksLikeWav(wavBytes)) {
      return '音频不是 WAV（无法注入）';
    }
    try {
      final duration = _estimateWavDuration(wavBytes);
      final timeoutSeconds =
          (duration == null ? 25 : (10 + (duration.inMilliseconds / 1000).ceil()))
              .clamp(25, 180);
      final resp = await http
          .post(
            Uri.parse('$backendBase/api/audio/play'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'audio_b64': base64Encode(wavBytes),
              'format': 'wav',
              'device_role': 'input',
              if (deviceIndex != null) 'device_index': deviceIndex,
            }),
          )
          .timeout(Duration(seconds: timeoutSeconds));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return null;
      }
      return _formatHttpFailure(resp);
    } catch (e) {
      return e.toString();
    }
  }

  Future<Uint8List?> _convertToWavViaBackend({
    required String backendBase,
    required Uint8List audioBytes,
    int? targetSampleRate,
    int? targetChannels,
    bool force = false,
  }) async {
    if (audioBytes.isEmpty) return null;
    if (_looksLikeWav(audioBytes) && !force) {
      if (targetSampleRate == null && targetChannels == null) return audioBytes;
      if (targetSampleRate != null || targetChannels != null) {
        try {
          if (audioBytes.length >= 44) {
            final bd = audioBytes.buffer
                .asByteData(audioBytes.offsetInBytes, audioBytes.length);
            final ch = bd.getUint16(22, Endian.little);
            final sr = bd.getUint32(24, Endian.little);
            if ((targetChannels == null || ch == targetChannels) &&
                (targetSampleRate == null || sr == targetSampleRate)) {
              return audioBytes;
            }
          }
        } catch (_) {}
      }
    }
    try {
      final resp = await http
          .post(
            Uri.parse('$backendBase/api/audio/convert/wav'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'audio_b64': base64Encode(audioBytes),
              if (targetSampleRate != null) 'samplerate': targetSampleRate,
              if (targetChannels != null) 'channels': targetChannels,
            }),
          )
          .timeout(const Duration(seconds: 35));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        logger.error(_formatHttpFailure(resp, prefix: '后端音频转 WAV 失败'));
        return null;
      }
      final wav = resp.bodyBytes;
      return _looksLikeWav(wav) ? wav : null;
    } catch (e) {
      logger.error('后端音频转 WAV 异常', e);
      return null;
    }
  }

  Future<Uint8List?> _getInjectionWavBytes({
    required String text,
    required AiProviderConfig ttsProvider,
    String? backendBase,
  }) async {
    final voice = ttsProvider.meta['voice'] as String?;
    const preferredSampleRates = <int>[48000, 44100, 24000];

    for (final sr in preferredSampleRates) {
      try {
        final wav = await AiClient.generateSpeech(
          config: ttsProvider,
          text: text,
          voice: voice,
          responseFormat: 'wav',
          sampleRate: sr,
        );
        if (_looksLikeWav(wav)) {
          if (backendBase != null && _needsInjectionWavResample(wav)) {
            final resampled = await _convertToWavViaBackend(
              backendBase: backendBase,
              audioBytes: wav,
              targetSampleRate: 48000,
              targetChannels: 2,
              force: true,
            );
            if (resampled != null) return resampled;
          }
          return wav;
        }
        if (wav.isNotEmpty && !_looksLikeMp3(wav) && wav.length % 2 == 0) {
          final wrapped = _wrapPcm16LeToWav(wav, sampleRate: sr);
          if (_looksLikeWav(wrapped)) {
            if (backendBase != null && _needsInjectionWavResample(wrapped)) {
              final resampled = await _convertToWavViaBackend(
                backendBase: backendBase,
                audioBytes: wrapped,
                targetSampleRate: 48000,
                targetChannels: 2,
                force: true,
              );
              if (resampled != null) return resampled;
            }
            return wrapped;
          }
        }
      } catch (_) {}
    }

    for (final sr in preferredSampleRates) {
      try {
        final pcm = await AiClient.generateSpeech(
          config: ttsProvider,
          text: text,
          voice: voice,
          responseFormat: 'pcm',
          sampleRate: sr,
        );
        if (pcm.isEmpty) continue;
        if (_looksLikeWav(pcm)) return pcm;
        if (_looksLikeMp3(pcm)) continue;
        if (pcm.length % 2 != 0) continue;
        final wrapped = _wrapPcm16LeToWav(pcm, sampleRate: sr);
        if (_looksLikeWav(wrapped)) {
          if (backendBase != null && _needsInjectionWavResample(wrapped)) {
            final resampled = await _convertToWavViaBackend(
              backendBase: backendBase,
              audioBytes: wrapped,
              targetSampleRate: 48000,
              targetChannels: 2,
              force: true,
            );
            if (resampled != null) return resampled;
          }
          return wrapped;
        }
      } catch (_) {}
    }

    if (backendBase != null) {
      try {
        final mp3 = await AiClient.generateSpeech(
          config: ttsProvider,
          text: text,
          voice: voice,
          responseFormat: 'mp3',
        );
        final converted = await _convertToWavViaBackend(
          backendBase: backendBase,
          audioBytes: mp3,
          targetSampleRate: 48000,
          targetChannels: 2,
        );
        if (converted != null) return converted;
      } catch (_) {}
    }

    return null;
  }

  Future<Uint8List> _generateSpeechBytesForPlayback({
    required AiProviderConfig ttsProvider,
    required String text,
    String? backendBase,
  }) async {
    final voice = ttsProvider.meta['voice'] as String?;
    const preferredSampleRates = <int>[44100, 24000];

    for (final sr in preferredSampleRates) {
      try {
        final wav = await AiClient.generateSpeech(
          config: ttsProvider,
          text: text,
          voice: voice,
          responseFormat: 'wav',
          sampleRate: sr,
        );
        if (_looksLikeWav(wav)) return wav;
        if (wav.isNotEmpty && !_looksLikeMp3(wav) && wav.length % 2 == 0) {
          final wrapped = _wrapPcm16LeToWav(wav, sampleRate: sr);
          if (_looksLikeWav(wrapped)) return wrapped;
        }
      } catch (_) {}
    }

    for (final sr in preferredSampleRates) {
      try {
        final pcm = await AiClient.generateSpeech(
          config: ttsProvider,
          text: text,
          voice: voice,
          responseFormat: 'pcm',
          sampleRate: sr,
        );
        if (pcm.isEmpty) continue;
        if (_looksLikeWav(pcm)) return pcm;
        if (_looksLikeMp3(pcm)) continue;
        if (pcm.length % 2 != 0) continue;
        final wrapped = _wrapPcm16LeToWav(pcm, sampleRate: sr);
        if (_looksLikeWav(wrapped)) return wrapped;
      } catch (_) {}
    }

    final mp3 = await AiClient.generateSpeech(
      config: ttsProvider,
      text: text,
      voice: voice,
      responseFormat: 'mp3',
    );
    if (backendBase != null) {
      final converted = await _convertToWavViaBackend(
        backendBase: backendBase,
        audioBytes: mp3,
      );
      if (converted != null) return converted;
      logger.error('无法通过后端转换为 WAV，回退为 MP3（Live2D 口型/注入可能受影响）');
    } else {
      logger.error('无法生成 WAV 音频，回退为 MP3（Live2D 口型/注入可能受影响）');
    }
    return mp3;
  }

  Duration? _estimateWavDuration(Uint8List bytes) {
    if (!_looksLikeWav(bytes) || bytes.length < 44) return null;
    try {
      final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
      final channels = bd.getUint16(22, Endian.little);
      final sampleRate = bd.getUint32(24, Endian.little);
      final bitsPerSample = bd.getUint16(34, Endian.little);
      final dataSize = bd.getUint32(40, Endian.little);
      final bytesPerSec = sampleRate * channels * (bitsPerSample ~/ 8);
      if (bytesPerSec <= 0 || dataSize <= 0) return null;
      final ms = (dataSize * 1000) ~/ bytesPerSec;
      if (ms <= 0) return null;
      return Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  bool _needsInjectionWavResample(Uint8List bytes) {
    if (!_looksLikeWav(bytes) || bytes.length < 44) return true;
    try {
      final bd = bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length);
      final channels = bd.getUint16(22, Endian.little);
      final sampleRate = bd.getUint32(24, Endian.little);
      final bitsPerSample = bd.getUint16(34, Endian.little);
      if (channels != 2) return true;
      if (sampleRate != 48000) return true;
      if (bitsPerSample != 16) return true;
      return false;
    } catch (_) {
      return true;
    }
  }

  Future<void> _playTtsBytes(Uint8List bytes, {Uint8List? lipsyncBytes, String? source}) async {
    final signal = lipsyncBytes ?? bytes;

    // 确保在主线程（UI线程）执行，因为 Audioplayers 插件通常需要在主线程调用平台通道
    // 如果是从 isolate 或 compute 中调用的，这里需要确保回到主线程
    
    final tempDir = await getTemporaryDirectory();
    final ext = _looksLikeWav(bytes) ? 'wav' : 'mp3';
    final tempFile = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
    
    try {
      await tempFile.writeAsBytes(bytes);
      await _trackTtsTempFile(tempFile);
      
      _audioPlayer ??= AudioPlayer();
      await _audioPlayer!.setReleaseMode(ReleaseMode.stop);

      try {
        await _audioPlayer!.stop();
      } catch (_) {}

      // 所有的 AudioPlayer 操作都包裹在 try-catch 中
      try {
        await _audioPlayer!.play(DeviceFileSource(tempFile.path));
        _emitTtsSignal(signal, source: source);
        
        // 等待播放完成或超时
        var wait = _estimateWavDuration(bytes);
        if (wait == null) {
          for (var i = 0; i < 20; i++) {
            wait = await _audioPlayer!.getDuration();
            if (wait != null && wait.inMilliseconds > 0) break;
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
        await Future.delayed((wait ?? const Duration(seconds: 30)) + const Duration(milliseconds: 150));
      } catch (e) {
        // 回退到 BytesSource
        try {
          await _audioPlayer!.stop();
        } catch (_) {}
        try {
          await _audioPlayer!.play(BytesSource(bytes));
          _emitTtsSignal(signal, source: source);
          
          var wait = _estimateWavDuration(bytes);
          if (wait == null) {
            for (var i = 0; i < 20; i++) {
              wait = await _audioPlayer!.getDuration();
              if (wait != null && wait.inMilliseconds > 0) break;
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }
          await Future.delayed((wait ?? const Duration(seconds: 30)) + const Duration(milliseconds: 150));
        } catch (e2) {
          logger.error('本机播放 TTS 失败', e2);
          logger.error('本机播放 TTS 失败（原始错误）', e);
        }
      }
    } catch (e) {
      logger.error('AudioPlayer 失败', e);
    }
  }

  Future<void> speak(String text, AiProviderConfig ttsProvider, {String? source}) async {
    // CRITICAL: TTS MUST BE PERFORMED IN THE FRONTEND.
    // Do NOT move this logic to the backend. 
    // The Live2D model relies on local audio playback for precise Lip-Sync.
    // Backend generation + Network streaming introduces latency that breaks sync.
    
    final cleanText = text.replaceAll(RegExp(r'\（.*?\）|\(.*?\)|\[.*?\]'), '').trim();
    if (cleanText.isEmpty) return;

    final sessionId = ++_ttsSessionId;
    _ttsStopped = false;
    _isSpeaking = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final ttsViaBackendDevice =
          prefs.getBool('settings.audio.ttsViaBackendDevice') ?? false;
      final ttsBackendDeviceIndex =
          prefs.getInt('settings.audio.ttsBackendDeviceIndex');
      final enablePythonBackend =
          prefs.getBool('settings.backend.enabled') ?? false;
      final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
      final backendBase = backendUrl.endsWith('/')
          ? backendUrl.substring(0, backendUrl.length - 1)
          : backendUrl;
      final convertBackendBase = enablePythonBackend ? backendBase : null;

      final injectToBackend = ttsViaBackendDevice && enablePythonBackend;
      final bytes = await _generateSpeechBytesForPlayback(
        ttsProvider: ttsProvider,
        text: cleanText,
        backendBase: convertBackendBase,
      );

      if (_ttsStopped || _ttsSessionId != sessionId) return;

      if (injectToBackend) {
        _activeTtsCount++;
        unawaited(() async {
          try {
            Uint8List? injWav;
            try {
              if (convertBackendBase != null) {
                if (_looksLikeWav(bytes)) {
                  if (_needsInjectionWavResample(bytes)) {
                    injWav = await _convertToWavViaBackend(
                      backendBase: convertBackendBase,
                      audioBytes: bytes,
                      targetSampleRate: 48000,
                      targetChannels: 2,
                      force: true,
                    );
                  } else {
                    injWav = bytes;
                  }
                } else {
                  injWav = await _convertToWavViaBackend(
                    backendBase: convertBackendBase,
                    audioBytes: bytes,
                    targetSampleRate: 48000,
                    targetChannels: 2,
                  );
                }
              }

              injWav ??= await _getInjectionWavBytes(
                text: cleanText,
                ttsProvider: ttsProvider,
                backendBase: convertBackendBase,
              );
            } catch (_) {}

            if (injWav == null) {
              logger.error('TTS 注入失败：无法获取 WAV 音频（可能不支持 wav/pcm 输出）');
              return;
            }

            if (_ttsStopped || _ttsSessionId != sessionId) return;
            final failInfo = await _injectWavToBackend(
              backendBase: backendBase,
              wavBytes: injWav,
              deviceIndex: ttsBackendDeviceIndex,
            );
            if (failInfo != null && failInfo.isNotEmpty) {
              logger.error('TTS 注入失败：$failInfo');
            }
          } finally {
            _activeTtsCount--;
          }
        }());
      }

      await _playTtsBytes(bytes, source: source);
    } catch (e) {
      logger.error('TTS 失败', e);
    } finally {
      if (_ttsSessionId == sessionId) {
        _isSpeaking = false;
      }
    }
  }

  Future<void> speakChunks(List<String> parts, AiProviderConfig ttsProvider, {String? source}) async {
    final cleanedParts = <String>[];
    for (final raw in parts) {
      final clean = raw.replaceAll(RegExp(r'\（.*?\）|\(.*?\)|\[.*?\]'), '').trim();
      if (clean.isNotEmpty) {
        cleanedParts.add(clean);
      }
    }
    if (cleanedParts.isEmpty) return;

    final sessionId = ++_ttsSessionId;
    _ttsStopped = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final ttsViaBackendDevice =
          prefs.getBool('settings.audio.ttsViaBackendDevice') ?? false;
      final ttsBackendDeviceIndex =
          prefs.getInt('settings.audio.ttsBackendDeviceIndex');
      final enablePythonBackend =
          prefs.getBool('settings.backend.enabled') ?? false;
      final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
      final backendBase = backendUrl.endsWith('/')
          ? backendUrl.substring(0, backendUrl.length - 1)
          : backendUrl;
      final convertBackendBase = enablePythonBackend ? backendBase : null;

      final injectToBackend = ttsViaBackendDevice && enablePythonBackend;

      for (final partText in cleanedParts) {
        if (_ttsStopped || _ttsSessionId != sessionId) {
          break;
        }
        final bytes = await _generateSpeechBytesForPlayback(
          ttsProvider: ttsProvider,
          text: partText,
          backendBase: convertBackendBase,
        );

        if (_ttsStopped || _ttsSessionId != sessionId) break;

        if (injectToBackend) {
          _activeTtsCount++;
          unawaited(() async {
            try {
              Uint8List? injWav;
              try {
                if (convertBackendBase != null) {
                  if (_looksLikeWav(bytes)) {
                    if (_needsInjectionWavResample(bytes)) {
                      injWav = await _convertToWavViaBackend(
                        backendBase: convertBackendBase,
                        audioBytes: bytes,
                        targetSampleRate: 48000,
                        targetChannels: 2,
                        force: true,
                      );
                    } else {
                      injWav = bytes;
                    }
                  } else {
                    injWav = await _convertToWavViaBackend(
                      backendBase: convertBackendBase,
                      audioBytes: bytes,
                      targetSampleRate: 48000,
                      targetChannels: 2,
                    );
                  }
                }

                injWav ??= await _getInjectionWavBytes(
                  text: partText,
                  ttsProvider: ttsProvider,
                  backendBase: convertBackendBase,
                );
              } catch (_) {}

              if (injWav == null) {
                logger.error('TTS 注入失败（分段）：无法获取 WAV 音频（可能不支持 wav/pcm 输出）');
                return;
              }

              if (_ttsStopped || _ttsSessionId != sessionId) return;
              final failInfo = await _injectWavToBackend(
                backendBase: backendBase,
                wavBytes: injWav,
                deviceIndex: ttsBackendDeviceIndex,
              );
              if (failInfo != null && failInfo.isNotEmpty) {
                logger.error('TTS 注入失败（分段）：$failInfo');
              }
            } finally {
              _activeTtsCount--;
            }
          }());
        }
        await _playTtsBytes(bytes, source: source);
      }
    } catch (e) {
      logger.error('TTS 失败（分段）', e);
    } finally {
      if (_ttsSessionId == sessionId) {
        _isSpeaking = false;
      }
    }
  }

  Future<void> stopSpeaking() async {
    _ttsStopped = true;
    _ttsSessionId++;
    _isSpeaking = false;
    try {
      if (_audioPlayer != null) {
        await _audioPlayer!.stop();
      }
    } catch (e) {
      debugPrint('AudioPlayer stop error (ignored): $e');
    }
  }

  Future<String> transcribe(String filePath, AiProviderConfig sttProvider) async {
    // CRITICAL: STT MUST BE PERFORMED IN THE FRONTEND.
    // Audio recording and initial processing happens locally.
    if (sttProvider.kind == AiProvider.local) {
      final engine = (sttProvider.meta['local_stt'] ?? sttProvider.meta['engine'])
          ?.toString()
          .trim();
      if (Platform.isWindows && engine == 'windows_speech') {
        final lang = (sttProvider.meta['language'] ?? '').toString().trim();
        return await _transcribeWithWindowsSpeech(filePath, language: lang);
      }
      throw Exception('本地 STT 未支持：${engine ?? 'unknown'}');
    }
    return await AiClient.transcribe(config: sttProvider, filePath: filePath);
  }

  String _toPwshEncodedCommand(String script) {
    final codeUnits = script.codeUnits;
    final bytes = <int>[];
    for (final u in codeUnits) {
      bytes.add(u & 0xFF);
      bytes.add((u >> 8) & 0xFF);
    }
    return base64Encode(bytes);
  }

  Future<String> _transcribeWithWindowsSpeech(
    String wavPath, {
    String language = '',
  }) async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Speech
$path = $env:NTAI_WAV_PATH
$langs = @()
if ($env:NTAI_STT_LANG -and $env:NTAI_STT_LANG.Trim().Length -gt 0) { $langs += $env:NTAI_STT_LANG.Trim() }
$langs += @('zh-CN', 'zh-Hans', 'en-US')
foreach ($lang in $langs) {
  try {
    $engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine([System.Globalization.CultureInfo]$lang)
    $engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
    $engine.SetInputToWaveFile($path)
    $result = $engine.Recognize()
    if ($null -ne $result -and $result.Text -and $result.Text.Trim().Length -gt 0) {
      Write-Output $result.Text
      exit 0
    }
  } catch {}
}
exit 0
''';

    final encoded = _toPwshEncodedCommand(script);
    final res = await Process.run(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded],
      runInShell: true,
      environment: {
        'NTAI_WAV_PATH': wavPath,
        'NTAI_STT_LANG': language,
      },
    );

    final out = (res.stdout ?? '').toString().trim();
    if (out.isNotEmpty) return out;
    return '';
  }

  Future<String> captureSystemLoopbackToFile({
    double durationSeconds = 5.0,
    int? deviceIndex,
    int samplerate = 48000,
    int channels = 2,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final enablePythonBackend = prefs.getBool('settings.backend.enabled') ?? false;
    if (!enablePythonBackend) {
      throw Exception('未启用 Python 后端');
    }

    final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
    final backendBase = backendUrl.endsWith('/')
        ? backendUrl.substring(0, backendUrl.length - 1)
        : backendUrl;

    final resp = await http
        .post(
          Uri.parse('$backendBase/api/audio/loopback/capture'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'duration_seconds': durationSeconds,
            if (deviceIndex != null) 'device_index': deviceIndex,
            'samplerate': samplerate,
            'channels': channels,
          }),
        )
        .timeout(
          Duration(
            seconds: (durationSeconds.ceil() + 12).clamp(10, 60),
          ),
        );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception(_formatHttpFailure(resp, prefix: '回环采集失败'));
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes));
    final b64 = (data is Map ? data['audio_b64'] : null)?.toString();
    if (b64 == null || b64.isEmpty) {
      throw Exception('回环采集失败: 无音频数据');
    }
    final bytes = base64Decode(b64);

    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}/loopback_${DateTime.now().millisecondsSinceEpoch}.wav';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  String _formatHttpFailure(http.Response resp, {String prefix = ''}) {
    String body = '';
    try {
      body = utf8.decode(resp.bodyBytes).trim();
    } catch (_) {
      body = (resp.body).toString().trim();
    }
    if (body.length > 1200) body = body.substring(0, 1200);
    final p = prefix.isEmpty ? '' : '$prefix: ';
    return body.isEmpty ? '${p}HTTP ${resp.statusCode}' : '${p}HTTP ${resp.statusCode} - $body';
  }

  // Helper to determine temperature based on user intent
  double _determineTemperature(String message) {
    final lowerMsg = message.toLowerCase();
    
    // 1. Low Temperature (0.2) - Factual, Logic, Coding, Math
    if (lowerMsg.contains('code') || lowerMsg.contains('function') || 
        lowerMsg.contains('calculate') || lowerMsg.contains('solve') || 
        lowerMsg.contains('what is') || lowerMsg.contains('who is') ||
        lowerMsg.contains('date') || lowerMsg.contains('time') ||
        lowerMsg.contains('代码') || lowerMsg.contains('怎么做') ||
        lowerMsg.contains('计算') || lowerMsg.contains('解释') ||
        lowerMsg.contains('定义') || lowerMsg.contains('是什么')) {
      return 0.2;
    }
    
    // 2. High Temperature (0.8) - Creative, Storytelling, Roleplay
    if (lowerMsg.contains('story') || lowerMsg.contains('poem') || 
        lowerMsg.contains('imagine') || lowerMsg.contains('write a') ||
        lowerMsg.contains('joke') || lowerMsg.contains('故事') ||
        lowerMsg.contains('写一首') || lowerMsg.contains('想象') ||
        lowerMsg.contains('笑话') || lowerMsg.contains('编')) {
      return 0.8;
    }
    
    // 3. Default (0.6) - Balanced
    return 0.6;
  }

  int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var ascii = 0;
    var nonAscii = 0;
    for (final unit in text.codeUnits) {
      if (unit <= 0x7F) {
        ascii++;
      } else {
        nonAscii++;
      }
    }
    final t = (ascii / 4.0) + (nonAscii / 1.6);
    return t.ceil();
  }

  int _estimateTokensForContext(List<Map<String, String>> ctx) {
    var sum = 0;
    for (final m in ctx) {
      sum += 4;
      sum += _estimateTokens('${m['role'] ?? ''}:');
      sum += _estimateTokens(m['content'] ?? '');
    }
    return sum;
  }

  int _resolveContextLengthTokens(AiProviderConfig? cfg) {
    final raw = cfg?.meta['context_length'] ?? cfg?.meta['context_length_tokens'];
    if (raw is int && raw > 0) return raw;
    if (raw is String) {
      final parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return 128000;
  }

  Future<void> _autoCompressContextIfNeeded(AiProviderConfig? cfg) async {
    final limit = _resolveContextLengthTokens(cfg);
    final threshold = (limit * 0.8).floor();
    final estimated = _estimateTokensForContext(_context);
    if (estimated < threshold) return;

    await _compressContext();

    final after = _estimateTokensForContext(_context);
    if (after < limit) return;

    final keep = min(8, _context.length);
    final tail = keep > 0 ? _context.sublist(_context.length - keep) : <Map<String, String>>[];
    _context = [
      {'role': 'system', 'content': '由于上下文过长，已截断部分历史对话。'},
      ...tail,
    ];
  }

  String _stripEmojis(String text) {
    final cleaned = text.replaceAll(_emojiRegex, '');
    return cleaned
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trimRight();
  }

  String _stripInnerMonologue(String text) {
    var out = text.replaceAll(RegExp(r'（[^）]*）', dotAll: true), '');
    out = out.replaceAll(RegExp(r'\([^)]*\)', dotAll: true), '');
    return out
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _stripMarkdown(String text) {
    var out = text;
    out = out.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    out = out.replaceAllMapped(RegExp(r'`([^`]*)`'), (m) => m.group(1) ?? '');
    out = out.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s{0,3}>\s*', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    out = out.replaceAll(RegExp(r'!\[.*?\]\(.*?\)'), '');
    out = out.replaceAllMapped(RegExp(r'\[(.*?)\]\((.*?)\)'), (m) => m.group(1) ?? '');
    out = out.replaceAll(RegExp(r'(\*\*|__)(.*?)\1'), r'$2');
    out = out.replaceAll(RegExp(r'(\*|_)(.*?)\1'), r'$2');
    return out
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<String> refineUserMessage(String rawMessage, {String? providerId}) async {
    if (rawMessage.trim().isEmpty) return rawMessage;

    try {
      final config = providerId != null 
          ? (await _llmService.getProviders()).firstWhere((p) => p.id == providerId)
          : await _llmService.getActiveProviderConfig();

      if (config == null) return rawMessage;

      final prompt = """
你是一个语音识别修正助手。请修正以下用户语音输入的错别字、标点符号，并使其更符合书面或自然的表达。
注意：
1. 只输出修正后的文本。
2. 如果文本已经很清晰，则原样返回。
3. 保持原意，不要增加多余的内容。
4. 用户的原始输入可能包含一些语气词（如“呃”、“那个”），请酌情移除。

原始输入："$rawMessage"
修正后的文本：""";

      final response = await _llmService.chat([
        {'role': 'user', 'content': prompt}
      ], usageType: 'agent', providerOverride: config, temperature: 0.3);

      final refined = response.content.trim().replaceAll('"', '');
      return refined.isNotEmpty ? refined : rawMessage;
    } catch (e) {
      debugPrint("[BRAIN] Refine error: $e");
      return rawMessage;
    }
  }

  Future<AiResponse> processMessage(String userMessage, {
    bool agentEnabled = false, 
    bool enableBrowser = false,
    bool enableNoteAccess = false,
    String userNickname = '',
    double learningProbability = 1.0,
    double? learningProbabilityOverride,
    bool enableExpressionAgent = true,
    String? systemPromptOverride,
    Map<String, dynamic>? sidecarCommands, // concurrent side agents payload
    AiProviderConfig? providerOverride,
    String? sessionId,
    bool needsRefinement = false,
    String source = 'direct', // 'direct', 'mic', 'voice_channel', 'voice', 'minecraft', 'danmaku'
  }) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 语音修正逻辑
    String processedUserMessage = userMessage;
    final enableSpeechRefinement = prefs.getBool('settings.agent.speechRefinement.enabled') ?? false;
    if (needsRefinement && enableSpeechRefinement) {
      final refinerProviderId = prefs.getString('settings.agent.speechRefinerProviderId');
      processedUserMessage = await refineUserMessage(userMessage, providerId: refinerProviderId);
      debugPrint("[BRAIN] Speech Refined: \"$userMessage\" -> \"$processedUserMessage\"");
    }

    // 1. 实现信源元数据标记 (Source Tagging)
    String taggedUserMessage = processedUserMessage;
    if (source == 'mic') {
      taggedUserMessage = "[Microphone] $processedUserMessage";
    } else if (source == 'voice_channel') {
      taggedUserMessage = "[Voice Channel/Unknown Speaker] $processedUserMessage";
    } else if (source == 'voice') {
      taggedUserMessage = "[Voice Channel] $processedUserMessage";
    } else if (source == 'minecraft') {
      taggedUserMessage = "[Minecraft] $processedUserMessage";
    } else if (source == 'danmaku') {
      taggedUserMessage = "[Danmaku] $processedUserMessage";
    }
    // 'direct' 不加前缀，保持原有逻辑

    _statusController.add("Thinking...");
    
    String finalResponse = "";
    late final AiResponse serverResponse;
    
    // Determine dynamic temperature
    final dynamicTemperature = _determineTemperature(processedUserMessage);
    debugPrint("[BRAIN] Dynamic Temperature: $dynamicTemperature");
    
    // 0. Check Orchestration Mode
    final providerConfig = providerOverride ?? await _llmService.getActiveProviderConfig();
    final prefs2 = await SharedPreferences.getInstance();
    final allowEmojis = prefs2.getBool('settings.ai.allowEmojis') ?? false;
    final scenarioContext = prefs2.getString('settings.scenario.context') ?? '';
    final scenarioTasks = prefs2.getStringList('settings.scenario.tasks') ?? [];
    final suppressInnerMonologue =
        prefs2.getBool('settings.chat.suppressInnerMonologue') ?? false;
    final strictNoMarkdown =
        prefs2.getBool('settings.chat.strictNoMarkdown') ?? false;
    final chatModeIdx = prefs2.getInt('settings.ui.chatMode');
    final isPersonaMode =
        chatModeIdx == null || chatModeIdx == ChatModeOption.persona.index;
    final backendEnabled = prefs2.getBool('settings.backend.enabled') ?? false;
    final isServerMode = backendEnabled;

    debugPrint("[BRAIN] Process Message Start (Source: $source)");
    debugPrint("[BRAIN] Backend Enabled: $backendEnabled");
    debugPrint("[BRAIN] Provider Mode: ${providerConfig?.orchestrationMode}");
    debugPrint("[BRAIN] Selected Mode: ${isServerMode ? 'SERVER' : 'CLIENT'}");

    // Early Motion Agent Trigger: Allow Motion Agent to perceive user input simultaneously/before Main Brain
    // This supports the "Smart Motion Agent" architecture where the agent reacts to user input autonomously.
    if (enableExpressionAgent) {
      unawaited(() async {
        try {
          debugPrint("[BRAIN] Triggering early motion request for user input...");
          // Send tagged user message with empty AI response initially, plus context history
          _expressionAgent.requestMotion(
            taggedUserMessage, 
            "", 
            history: List.from(_context), // Pass copy of current history (excluding current msg)
          );
        } catch (e) {
          debugPrint("[BRAIN] Early motion request failed: $e");
        }
      }());
    }

    // 1. Add Tagged User Message to Context
    if (_context.isEmpty || _context.last['content'] != taggedUserMessage) {
       _context.add({'role': 'user', 'content': taggedUserMessage});
    }
    
    if (_context.length > 200) {
      _context = _context.sublist(_context.length - 200);
    }
    await _autoCompressContextIfNeeded(providerConfig);

    _statusController.add(isServerMode ? "Connecting to Neural Backend..." : "Connecting to AI Provider...");
    debugPrint("[BRAIN] Entering ${isServerMode ? 'Server' : 'Client'} Mode");
    debugPrint("[BRAIN] enableBrowser: $enableBrowser");
    debugPrint("[BRAIN] User message: ${taggedUserMessage.length > 50 ? '${taggedUserMessage.substring(0, 50)}...' : taggedUserMessage}");
    try {
      List<Map<String, String>> messages = List.from(_context);
      
      // Inject scenario context and tasks into the system prompt
      String extraSystemInfo = "";
      if (scenarioContext.isNotEmpty) {
        extraSystemInfo += "\n[Current Scenario]: $scenarioContext";
      }
      if (scenarioTasks.isNotEmpty) {
        extraSystemInfo += "\n[Current Objectives/Tasks]:\n- ${scenarioTasks.join('\n- ')}";
      }

      if (!allowEmojis || extraSystemInfo.isNotEmpty) {
        String sysContent = "";
        if (!allowEmojis) sysContent += "要求：回复中不要使用任何 emoji/表情符号/颜文字，只输出纯文本。";
        if (extraSystemInfo.isNotEmpty) sysContent += extraSystemInfo;
        
        messages = [
          {'role': 'system', 'content': sysContent},
          ...messages,
        ];
      }

      debugPrint("[BRAIN] Sending ${messages.length} messages");
      final aiResponse = await _llmService.chat(
        messages,
        usageType: 'main',
        temperature: dynamicTemperature,
        providerOverride: providerConfig,
        sessionId: sessionId,
        learningProbabilityOverride:
            learningProbabilityOverride ?? learningProbability,
      );
      String response = aiResponse.content;
      if (!allowEmojis) {
        response = _stripEmojis(response);
      }
      if (suppressInnerMonologue) {
        response = _stripInnerMonologue(response);
      }
      if (strictNoMarkdown && isPersonaMode) {
        response = _stripMarkdown(response);
      }

      if (aiResponse.reasoningContent != null) {
        debugPrint("[BRAIN] Received Reasoning Content: ${aiResponse.reasoningContent!.length} chars");
      }

      debugPrint("[BRAIN] Received response length: ${response.length}");
      debugPrint("[BRAIN] Response contains [IMAGE: tags: ${response.contains('[IMAGE')}");
      if (response.contains('[IMAGE')) {
        final imageCount = '[IMAGE'.allMatches(response).length;
        debugPrint("[BRAIN] Found $imageCount image tags in response");
      }

      if (aiResponse.emotion != null && enableExpressionAgent) {
        final emotionMap = ExpressionService.tryExtractExpressionPayload(aiResponse.emotion!) ??
            ExpressionService.tryExtractExpressionPayload("expression: ${aiResponse.emotion}");

        if (emotionMap != null) {
          unawaited(_expressionAgent.applyDynamic(emotionMap));
        }
      }

      _context.add({'role': 'assistant', 'content': response});

      finalResponse = response;
      serverResponse = aiResponse;

      _statusController.add("");
    } catch (e) {
      _statusController.add("Request Error: $e");
      return AiResponse(content: "请求失败：$e");
    }
    
    /*
    // === CLIENT ORCHESTRATION MODE (Legacy/Standalone) ===

    // 2. Retrieve Long-term Memories (RAG)
    _statusController.add("Recalling memories...");
    List<Memory> memories = await _memoryService.retrieveRelevant(userMessage);
    String memoryContext = "";
    if (memories.isNotEmpty) {
      memoryContext = "Relevant Memories (User Facts/Preferences):\n" + 
          memories.map((m) => "- ${m.content}").join("\n");
    }

    // 2.1 Retrieve Note Summaries (if enabled)
    if (enableNoteAccess) {
      final noteSummaries = await _noteService.getAllSummaries();
      if (noteSummaries.isNotEmpty) {
        memoryContext += "\n\n$noteSummaries";
      }
    }

    // 3. Build System Prompt
    String systemPrompt = (systemPromptOverride != null && systemPromptOverride.isNotEmpty) 
        ? systemPromptOverride 
        : FIREFLY_PERSONA;
        
    // Inject Current Time to prevent hallucinations
    final now = DateTime.now();
    final timeString = "${now.year}年${now.month}月${now.day}日 ${now.hour}:${now.minute.toString().padLeft(2, '0')}";
    systemPrompt += "\n\n[System Time]: 当前时间是 $timeString。请时刻牢记这个时间点，对于任何关于时间的问题（如“今天是几号”、“现在是哪一年”），必须基于此时间回答，严禁产生幻觉或回答过去的时间。";

    systemPrompt = systemPrompt.replaceAll('{{USER_NICKNAME_SECTION}}', 
      userNickname.isNotEmpty ? "用户的昵称是：$userNickname。请在对话中自然地使用这个称呼。" : ""
    );

    // Dynamic Capabilities Injection based on active avatar system
    final showLive2D = prefs.getBool('settings.ui.showLive2D') ?? false;
    // Future: final showLive3D = prefs.getBool('settings.ui.showLive3D') ?? false;

    String capabilitiesText = "";
    if (showLive2D) {
       capabilitiesText = """
**Live2D 形象能力**：
*   你当前拥有一个灵动的【Live2D 形象】。
*   支持的动作：点头、摇头、歪头、眨眼、以及丰富的面部表情（开心、悲伤、生气、惊讶等）。
*   **高阶动作**：你可以尝试描述“左看看右看看”（观察周围）、“叹气”、“害羞”等。
*   **物理限制**：虽然你可以动，但你无法在空间中移动（如“走到你面前”），也无法与现实物体交互（如“拿起杯子”），**且无法做出复杂的手势**（如“比耶”、“点赞”）。请避免描述此类不可能的动作。
*   Motion Agent 会实时分析你的回复并驱动模型做出动作，你只需自然地在括号中描述动作即可，例如“(歪头思考) 嗯，让我想想...”。
""";
    } else {
       // Default/Text Only or 3D placeholder
       capabilitiesText = """
**形象状态**：
*   你当前处于纯文本模式或未连接可视化形象。
*   请主要通过文字内容来表达你的情感。
""";
    }
    
    systemPrompt = systemPrompt.replaceAll('{{CAPABILITIES_SECTION}}', capabilitiesText);

    // Enforce strict output format: do NOT output JSON, code fences, or structured data.
    systemPrompt += '\n\n重要：请不要在任何情况下输出 JSON、代码块、或任何机器可解析的结构化数据（例如使用 ``` 或 { }). 仅以自然语言完整回答。不要包含示例 JSON 或带有字段的代码块。';
    if (memoryContext.isNotEmpty) {
      systemPrompt += "\n\n$memoryContext";
    }

    // (Removed) Expression JSON spec injection; expression now inferred by separate agent.

    if (agentEnabled) {
      systemPrompt += "\n\n[AGENT MODE ENABLED]\n";
      systemPrompt += "You have access to the following tools:\n";
      systemPrompt += "- get_current_time: Get current date/time. No args.\n";
      if (enableBrowser) {
        systemPrompt += "- web_search: Search the internet. Args: query\n";
        systemPrompt += "- visit_page: Read a webpage. Args: url\n";
      }
      
      systemPrompt += "\nTo use a tool, your response must be ONLY the tool call in this format:\n";
      systemPrompt += "[TOOL_CALL] tool_name: arguments\n";
      systemPrompt += "Example: [TOOL_CALL] web_search: flutter dart tutorial\n";
      systemPrompt += "After receiving the tool output, you will be prompted again to continue.\n";
      systemPrompt += "If you have enough information, answer normally without the [TOOL_CALL] tag.\n";
    }

    // 4. Concurrent sidecar agents (simple fan-out)
    // This allows expression/3D avatar updates without blocking main response.
    // Expected keys: { "expression": Map|String, "avatar3d": Map }
    if (enableExpressionAgent && sidecarCommands != null) {
      unawaited(_fanOutSidecars(sidecarCommands));
    }

    // === CLIENT ORCHESTRATION MODE (DISABLED) ===
    // This entire section is disabled to force reliance on the Python Backend.
    
    // 5. Agent Loop
    int steps = 0;
    int webSearchCount = 0;
    const maxSteps = 5;
    String finalResponse = "";

    while (steps < maxSteps) {
      _statusController.add(steps == 0 ? "Thinking..." : "Reasoning (Step ${steps + 1})...");
      
      List<Map<String, String>> messages = [
        {'role': 'system', 'content': systemPrompt},
        ..._context
      ];

      // Get Response from LLM
      final aiResponse = await _llmService.chat(
        messages, 
        usageType: 'main',
        providerOverride: providerConfig,
        systemPromptOverride: systemPromptOverride,
      );
      String response = aiResponse.content;
      
      // Handle Emotion from Backend (if present)
      if (aiResponse.emotion != null && enableExpressionAgent) {
        // Map backend emotion string to ExpressionData
        // Simple heuristic mapping for now, can be improved
        final emotionMap = ExpressionService.tryExtractExpressionPayload(aiResponse.emotion!) 
                           ?? ExpressionService.tryExtractExpressionPayload("expression: ${aiResponse.emotion}");
        
        if (emotionMap != null) {
           unawaited(_expressionAgent.applyDynamic(emotionMap));
        } else {
           // Fallback: try to infer from the emotion description string directly
           // e.g. "Calm and curious" -> map to neutral/happy
           // For now, we rely on the inference agent if mapping fails, or we could add a simple keyword mapper here.
        }
      }
      
      // Check for tool call (Robust)
      final toolRegex = RegExp(r'\[TOOL_CALL\]\s*([a-zA-Z0-9_]+)\s*:\s*([^\n]*)');
      final match = toolRegex.firstMatch(response);

      if (agentEnabled && match != null) {
        final toolName = match.group(1)!.trim();
        final args = match.group(2)!.trim();
        
        // If there is text before the tool call, we should probably log it or add it to context
        // so the model remembers its train of thought.
        final preText = response.substring(0, match.start).trim();
        if (preText.isNotEmpty) {
           // We add the pre-text as a separate assistant message
           _context.add({'role': 'assistant', 'content': preText});
        }
        
        if (_tools.containsKey(toolName)) {
            if ((toolName == 'web_search' || toolName == 'visit_page') && !enableBrowser) {
               if (preText.isEmpty) _context.add({'role': 'assistant', 'content': response});
               _context.add({'role': 'user', 'content': "Tool Error: Browser is disabled."});
            } else {
               // Check Retry Limit
               if (toolName == 'web_search') {
                 if (webSearchCount > 0 && !enableSearchRetry) {
                    if (preText.isEmpty) _context.add({'role': 'assistant', 'content': response});
                    _context.add({'role': 'user', 'content': "Tool Error: Search retry is disabled by configuration. Please stop searching and answer with what you have."});
                    steps++; 
                    continue;
                 }
                 webSearchCount++;
               }

               // Execute Tool
               _statusController.add("Using tool: $toolName...");
               final tool = _tools[toolName]!;
               String output;
               try {
                 output = await tool.execute(args);
               } catch (e) {
                 output = "Error executing tool: $e";
               }
               
               // If we didn't add preText, we might want to add the tool call line itself to context
               // so the model knows it called the tool.
               // However, standard ReAct usually just appends the tool output.
               // Let's append a system message indicating the tool was called if no preText.
               if (preText.isEmpty) {
                  // _context.add({'role': 'assistant', 'content': "[Called tool: $toolName with args: $args]"});
                  // Actually, let's just add the full response if it was just the tool call.
                  _context.add({'role': 'assistant', 'content': response});
               }
               
               _context.add({'role': 'user', 'content': "Tool Output ($toolName):\n$output"});
            }
          } else {
             if (preText.isEmpty) _context.add({'role': 'assistant', 'content': response});
             _context.add({'role': 'user', 'content': "Tool Error: Tool '$toolName' not found."});
          }
        steps++;
      } else {
        // Final answer
        finalResponse = response;
        _context.add({'role': 'assistant', 'content': finalResponse});
        break;
      }
    }
    
    if (finalResponse.isEmpty && steps >= maxSteps) {
      finalResponse = "I'm sorry, I got stuck in a loop while trying to use tools.";
      _context.add({'role': 'assistant', 'content': finalResponse});
    }
    */

    // Process Memes (Resolve [MEME: tag] to [IMAGE: path])
    finalResponse = await _processMemes(finalResponse);

    // Expression inference via separate agent (after finalResponse determined)
    if (enableExpressionAgent && finalResponse.isNotEmpty) {
      unawaited(() async {
        try {
          // We rely on external settings (loaded elsewhere) for provider override;
          // here we attempt heuristic first then optional model.
          // Since BrainService does not have direct settings reference, provider override must be passed via sidecarCommands later (future) or left null now.
          final inferred = await _expressionInference.infer(finalResponse);
          if (inferred != null) {
            // Publish to expression state bus for other agents/UI to read
            try {
              final bus = ExpressionStateBus();
              bus.set(inferred);
            } catch (_) {}

            unawaited(_expressionAgent.applyDynamic(ExpressionService.toMap(inferred)));
          }
        } catch (_) {}
      }());
    }

    // 7. Auto-Compression Check
    _statusController.add(""); // Clear status
    
    // Construct AiResponse including reasoning/tool calls if available
    // Since we forced server mode, the actual AiResponse object (containing reasoning) 
    // was lost when we didn't return it immediately.
    // However, the current logic only returns `finalResponse` as content.
    // To properly support reasoning display, we should probably capture the original `aiResponse` object
    // or at least its fields.
    
    // For now, returning simple content is safe for basic function, but we might lose reasoning data
    // if we don't return the original object.
    // Let's rely on the fact that `finalResponse` contains the text content.
    // If we want to preserve reasoning, we need to capture it in the server block.
    
    // We know serverResponse is not null here because if it failed, we returned in catch block.
    return AiResponse(
      content: finalResponse,
      emotion: serverResponse.emotion,
      reasoningContent: serverResponse.reasoningContent,
      toolCalls: serverResponse.toolCalls,
    );
  }

  // Remove fenced/inlined expression payloads from a string
  // (Deprecated) stripExpressionBlocks no longer needed; JSON no longer injected.

  // Convenience: direct expression push without passing sidecar map
  Future<void> applyExpression(Object payload) => _expressionAgent.applyDynamic(payload);

  Future<void> compressContext() async {
    await _compressContext();
  }

  Future<void> _compressContext() async {
    if (_context.length < 4) return; // Too short to compress

    _statusController.add("Compressing context...");
    try {
      final keep = min(6, _context.length);
      final recent = _context.sublist(_context.length - keep);
      final toCompress = _context.sublist(0, _context.length - keep);
      
      // Convert to string
      final historyText = toCompress.map((m) => "${m['role']}: ${m['content']}").join("\n");
      
      // Ask LLM to summarize
      final summaryResponse = await _llmService.chat([
        {
          'role': 'system',
          'content': '请把以下对话历史压缩为一段简洁摘要，保留关键事实、用户偏好、未完成事项与重要约束。只输出摘要文本。',
        },
        {'role': 'user', 'content': historyText}
      ], usageType: 'system');
      final summary = summaryResponse.content;

      // Replace context with summary + recent
      _context = [
        {'role': 'system', 'content': "历史摘要：$summary"},
        ...recent
      ];
      
      // Note: Original messages are already saved in ChatHistoryService (SQLite),
      // so we don't need to duplicate them here. The user's requirement for "temporary memory"
      // is satisfied by the persistent chat history which acts as the raw log.
      
    } catch (e) {
      debugPrint("Compression failed: $e");
    }
  }

  Future<void> analyzeAndLearnMeme(Uint8List bytes) async {
    _statusController.add("Analyzing image...");
    try {
      // 0. Check Dimensions (Heuristic)
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();

      // Heuristic: If image is too large (e.g. > 4MP or > 2500px on any side), it's likely a photo/screenshot, not a meme.
      // Memes are usually smaller.
      if (width > 2500 || height > 2500) {
        debugPrint("Image too large ($width x $height), skipping meme learning.");
        _statusController.add("Image too large for meme.");
        await Future.delayed(const Duration(seconds: 1));
        _statusController.add("");
        return;
      }

      // 1. Get Analysis from Vision Model
      // Ask model to classify AND describe
      final analysisJson = await _llmService.chatWithImage(
        messages: [], 
        imageBytes: bytes,
        prompt: '''
Analyze this image. Determine if it is a "Meme" (expressive image/sticker used in chat) or a "Regular Image" (photo, screenshot, wallpaper).
Output JSON format:
{
  "type": "meme" or "image",
  "description": "keywords and emotion if meme, otherwise brief description",
  "reason": "why you think so"
}
''',
        usageType: 'vision', 
      );
      
      String cleanJson = analysisJson;
      final start = cleanJson.indexOf('{');
      final end = cleanJson.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        cleanJson = cleanJson.substring(start, end + 1);
      } else if (cleanJson.contains("```json")) {
        cleanJson = cleanJson.split("```json")[1].split("```")[0];
      } else if (cleanJson.contains("```")) {
        cleanJson = cleanJson.split("```")[1].split("```")[0];
      }

      final data = jsonDecode(cleanJson);
      
      if (data['type'] == 'meme') {
        final description = data['description'] ?? '';
        // 2. Save
        // Moved to backend: Meme learning is now handled by the Python backend via API if needed.
        // For now, client-side meme learning is disabled/deprecated as requested.
        // await _memeService.saveMemeFromBytes(bytes, description);
        
        // Alternative: Upload to backend for learning?
        // For this refactor, we just log it.
        _statusController.add("Meme detected (Backend migration pending)");
        if (kDebugMode) {
          debugPrint("Meme detected: $description (Reason: ${data['reason']}) - Client side save disabled.");
        }
      } else {
        _statusController.add("Image analyzed (Not a meme)");
        if (kDebugMode) {
          debugPrint("Skipped meme learning: ${data['reason']}");
        }
      }
      
      await Future.delayed(const Duration(seconds: 1));
      _statusController.add("");
    } catch (e) {
      debugPrint("Meme learning failed: $e");
      _statusController.add("Meme learning failed.");
    }
  }

  Future<String> _processMemes(String text) async {
    final regex = RegExp(r'\[MEME:\s*(.*?)\]');
    final matches = regex.allMatches(text);
    
    if (matches.isEmpty) return text;

    String processed = text;
    // Iterate in reverse to avoid index shifting issues
    for (final match in matches.toList().reversed) {
      final query = match.group(1)?.trim() ?? '';
      if (query.isNotEmpty) {
        // Moved to backend: Meme search is now handled by the Python backend.
        // The backend should return [IMAGE:path] directly if found.
        // If we still see [MEME:...] here, it means backend didn't process it or it's a legacy tag.
        // We'll just strip it for now to avoid showing raw tags.
        processed = processed.replaceRange(match.start, match.end, '');
        /*
        final memes = await _memeService.searchMemes(query, limit: 1);
        if (memes.isNotEmpty) {
          final path = memes.first.path;
          // Replace with [SPLIT][IMAGE:path][SPLIT] to ensure it gets its own bubble
          processed = processed.replaceRange(match.start, match.end, ' [SPLIT] [IMAGE:$path] [SPLIT] ');
          // Increment usage
          unawaited(_memeService.incrementUsage(memes.first.id));
        } else {
          // No meme found, remove the tag
          processed = processed.replaceRange(match.start, match.end, ''); 
        }
        */
      }
    }
    return processed;
  }

  Future<String> generatePersonaFromWeb(String characterName, {String? type}) async {
    _statusController.add("Searching for $characterName...");
    try {
      final searchTool = _tools['web_search'] as WebSearchTool;
      // Search specifically on Moegirl or general wiki
      final searchResults = await searchTool.execute("$characterName ${type ?? ''} 角色设定");
      
      _statusController.add("Generating persona...");
      // Ask LLM to create a system prompt based on search results
      final prompt = '''
Based on the following search results about the character "$characterName" (Type: ${type ?? 'General'}), create a detailed System Prompt (Persona) for an AI assistant to roleplay as this character.
Include:
1. Name and basic identity.
2. Personality traits (Tone, catchphrases, mannerisms).
3. Background story summary.
4. Interaction style with the user.

Search Results:
$searchResults

Output ONLY the System Prompt text. Do not include "Here is the prompt" or similar meta-text.
''';

      final response = await _llmService.chat([
        {'role': 'user', 'content': prompt}
      ], usageType: 'main'); // Use main model for better generation
      
      _statusController.add("");
      return response.content;
    } catch (e) {
      _statusController.add("Error generating persona: $e");
      return "Error: $e";
    }
  }
}
