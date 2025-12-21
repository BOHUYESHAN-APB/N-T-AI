import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'llm_service.dart';
import 'memory_service.dart';
import '../prompts/prompts.dart';
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
  final MemoryService _memoryService = MemoryService();
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

  bool _looksLikeWav(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x41 &&
        bytes[10] == 0x56 &&
        bytes[11] == 0x45;
  }

  Future<void> _broadcastTtsBytes(Uint8List bytes) async {
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
          body: jsonEncode({'audio': base64Encode(bytes)}),
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          final clientCount = json['clients'] as int;
          if (clientCount > 0) {
            print('[BrainService] Audio broadcasted to $clientCount Live2D clients.');
          } else {
            print('[BrainService] No Live2D clients connected for audio broadcast.');
          }
        } else {
          print('[BrainService] Audio broadcast failed: ${response.statusCode}');
        }
      } catch (e) {
        print('[BrainService] Audio broadcast error: $e');
      }
    }());
  }

  Future<void> _playTtsBytes(Uint8List bytes) async {
    _ttsController.add(bytes);

    final tempDir = await getTemporaryDirectory();
    final ext = _looksLikeWav(bytes) ? 'wav' : 'mp3';
    final tempFile = File('${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await tempFile.writeAsBytes(bytes);
    try {
      _audioPlayer ??= AudioPlayer();
      final completer = Completer<void>();
      StreamSubscription<void>? sub;
      sub = _audioPlayer!.onPlayerComplete.listen((_) {
        sub?.cancel();
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      await _audioPlayer!.play(DeviceFileSource(tempFile.path));
      await completer.future;
    } catch (e) {
      debugPrint('AudioPlayer error (ignored): $e');
    }
    await _broadcastTtsBytes(bytes);
  }

  Future<void> speak(String text, AiProviderConfig ttsProvider) async {
    // CRITICAL: TTS MUST BE PERFORMED IN THE FRONTEND.
    // Do NOT move this logic to the backend. 
    // The Live2D model relies on local audio playback for precise Lip-Sync.
    // Backend generation + Network streaming introduces latency that breaks sync.
    
    final cleanText = text.replaceAll(RegExp(r'\（.*?\）|\(.*?\)|\[.*?\]'), '').trim();
    if (cleanText.isEmpty) return;

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

      final bytes = await AiClient.generateSpeech(
        config: ttsProvider,
        text: cleanText,
        voice: ttsProvider.meta['voice'] as String?,
        responseFormat: ttsViaBackendDevice ? 'wav' : 'mp3',
      );

      if (_ttsStopped || _ttsSessionId != sessionId) {
        return;
      }

      if (ttsViaBackendDevice && enablePythonBackend) {
        try {
          await http
              .post(
                Uri.parse('$backendBase/api/audio/play'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'audio_b64': base64Encode(bytes),
                  'format': 'wav',
                  'device_role': 'input',
                  if (ttsBackendDeviceIndex != null)
                    'device_index': ttsBackendDeviceIndex,
                }),
              )
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        _ttsController.add(bytes);
        await _broadcastTtsBytes(bytes);
        return;
      }

      await _playTtsBytes(bytes);
    } catch (e) {
      print('TTS Error: $e');
    }
  }

  Future<void> speakChunks(List<String> parts, AiProviderConfig ttsProvider) async {
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

      final tasks = <Future<Uint8List>>[];
      for (final part in cleanedParts) {
        tasks.add(AiClient.generateSpeech(
          config: ttsProvider,
          text: part,
          voice: ttsProvider.meta['voice'] as String?,
          responseFormat: ttsViaBackendDevice ? 'wav' : 'mp3',
        ));
      }

      final results = await Future.wait(tasks);

      if (_ttsStopped || _ttsSessionId != sessionId) {
        return;
      }

      for (final bytes in results) {
        if (_ttsStopped || _ttsSessionId != sessionId) {
          break;
        }
        if (ttsViaBackendDevice && enablePythonBackend) {
          try {
            await http
                .post(
                  Uri.parse('$backendBase/api/audio/play'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'audio_b64': base64Encode(bytes),
                    'format': 'wav',
                    'device_role': 'input',
                    if (ttsBackendDeviceIndex != null)
                      'device_index': ttsBackendDeviceIndex,
                  }),
                )
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
          _ttsController.add(bytes);
          await _broadcastTtsBytes(bytes);
          continue;
        }
        await _playTtsBytes(bytes);
      }
    } catch (e) {
      print('TTS Error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    _ttsStopped = true;
    _ttsSessionId++;
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
    return await AiClient.transcribe(config: sttProvider, filePath: filePath);
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
        .timeout(const Duration(seconds: 10));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('回环采集失败: HTTP ${resp.statusCode}');
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

  // Initiative Mode Stream
  final _initiativeController = StreamController<AiResponse>.broadcast();
  Stream<AiResponse> get initiativeStream => _initiativeController.stream;

  List<String> _danmakuBuffer = [];
  Timer? _initiativeTimer;
  bool _isProcessing = false;
  bool _initiativeLoopRequested = false;

  void feedDanmaku(String content) {
    _danmakuBuffer.add(content);
    if (_danmakuBuffer.length > 50) {
      _danmakuBuffer.removeAt(0);
    }
  }

  void startInitiativeLoop() {
    _initiativeLoopRequested = true;
    _initiativeTimer?.cancel();
    debugPrint("[BrainService] Starting Initiative Loop...");
    
    SharedPreferences.getInstance().then((prefs) {
      if (!_initiativeLoopRequested) return;
      final interval = prefs.getInt('settings.ai.danmakuBatchInterval') ?? 20;
      final safeInterval = interval < 5 ? 5 : interval;
      
      _initiativeTimer = Timer.periodic(Duration(seconds: safeInterval), (timer) async {
        if (!_initiativeLoopRequested) return;
        final prefs = await SharedPreferences.getInstance();
        final enabled = prefs.getBool('settings.ai.initiativeMode') ?? false;
        
        if (!enabled) return;
        if (_isProcessing) return;
        if (_danmakuBuffer.isEmpty) return;

        // Simple rate limiting/cooldown could be added here
        
        await _runInitiativeCheck();
      });
    });
  }

  void stopInitiativeLoop() {
    _initiativeLoopRequested = false;
    _initiativeTimer?.cancel();
    debugPrint("[BrainService] Stopping Initiative Loop...");
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
    out = out.replaceAllMapped(
      RegExp(r'(?<!\])\(([^)]*)\)', dotAll: true),
      (m) {
        final inner = m.group(1) ?? '';
        final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(inner);
        if (hasCjk && inner.trim().length <= 40) return '';
        return m.group(0) ?? '';
      },
    );
    return out
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<void> _runInitiativeCheck() async {
    _isProcessing = true;
    try {
      // Snapshot and clear buffer (or keep sliding window)
      // We take last 10 messages for context
      final recent = _danmakuBuffer.length > 15 
          ? _danmakuBuffer.sublist(_danmakuBuffer.length - 15) 
          : List<String>.from(_danmakuBuffer);
      
      // Don't clear buffer immediately to allow context continuity, 
      // but maybe clear it if we speak to avoid repetition.
      
      final contextText = recent.join("\n");
      final prompt = """
[Initiative Mode]
Here are the recent comments from the audience (Danmaku):
$contextText

Based on these comments, do you want to proactively say something to the audience?
- If yes, provide a natural, engaging response (as the streamer/character).
- If no (e.g., comments are boring or you just spoke), reply with exactly: NO_ACTION
- Keep it short and conversational.
""";

      final messages = <Map<String, String>>[];

      final prefs = await SharedPreferences.getInstance();
      final allowEmojis = prefs.getBool('settings.ai.allowEmojis') ?? false;
      if (!allowEmojis) {
        messages.add({'role': 'system', 'content': '要求：回复中不要使用任何 emoji/表情符号/颜文字，只输出纯文本。'});
      }
      
      // 1. Add context first (if available) to provide conversation history
      if (_context.isNotEmpty) {
        messages.addAll(_context.sublist(max(0, _context.length - 2)));
      }

      // 2. Add the initiative prompt as a USER message at the end
      // This ensures the backend receives a valid user input to respond to.
      messages.add({'role': 'user', 'content': prompt});

      final response = await _llmService.chat(messages, usageType: 'initiative', temperature: 0.7);

      var content = response.content;
      if (!allowEmojis) {
        content = _stripEmojis(content);
      }

      if (content.trim() != "NO_ACTION") {
        debugPrint("[BrainService] Initiative Triggered: ${response.content}");
        
        // Add to local context
        _context.add({'role': 'assistant', 'content': content});
        
        // Emit to UI
        _initiativeController.add(AiResponse(
          content: content,
          emotion: response.emotion,
          reasoningContent: response.reasoningContent,
          toolCalls: response.toolCalls,
        ));
        
        // Clear buffer after speaking to avoid reacting to same comments?
        // Or just clear the ones we used.
        _danmakuBuffer.clear(); 
      }
    } catch (e) {
      debugPrint("[BrainService] Initiative Error: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<AiResponse> processMessage(String userMessage, {
    bool agentEnabled = false, 
    bool enableBrowser = false,
    bool enableNoteAccess = false,
    String userNickname = '',
    double learningProbability = 1.0,
    bool enableExpressionAgent = true,
    String? systemPromptOverride,
    Map<String, dynamic>? sidecarCommands, // concurrent side agents payload
    AiProviderConfig? providerOverride,
    String? sessionId,
  }) async {
    _statusController.add("Thinking...");
    
    String finalResponse = "";
    late final AiResponse serverResponse;
    
    // Determine dynamic temperature
    final dynamicTemperature = _determineTemperature(userMessage);
    debugPrint("[BRAIN] Dynamic Temperature: $dynamicTemperature");
    
    // 0. Check Orchestration Mode
    final providerConfig = providerOverride ?? await _llmService.getActiveProviderConfig();
    final prefs = await SharedPreferences.getInstance();
    final allowEmojis = prefs.getBool('settings.ai.allowEmojis') ?? false;
    final suppressInnerMonologue =
        prefs.getBool('settings.chat.suppressInnerMonologue') ?? false;
    final backendEnabled = prefs.getBool('settings.backend.enabled') ?? false;
    final isServerMode = backendEnabled;

    debugPrint("[BRAIN] Process Message Start");
    debugPrint("[BRAIN] Backend Enabled: $backendEnabled");
    debugPrint("[BRAIN] Provider Mode: ${providerConfig?.orchestrationMode}");
    debugPrint("[BRAIN] Selected Mode: ${isServerMode ? 'SERVER' : 'CLIENT'}");

    // Early Motion Agent Trigger: Allow Motion Agent to perceive user input simultaneously/before Main Brain
    // This supports the "Smart Motion Agent" architecture where the agent reacts to user input autonomously.
    if (enableExpressionAgent) {
      unawaited(() async {
        try {
          debugPrint("[BRAIN] Triggering early motion request for user input...");
          // Send user message with empty AI response initially, plus context history
          _expressionAgent.requestMotion(
            userMessage, 
            "", 
            history: List.from(_context), // Pass copy of current history (excluding current msg)
          );
        } catch (e) {
          debugPrint("[BRAIN] Early motion request failed: $e");
        }
      }());
    }

    // 1. Add User Message to Context
    if (_context.isEmpty || _context.last['content'] != userMessage) {
       _context.add({'role': 'user', 'content': userMessage});
    }
    
    // Limit context size for LLM
    if (_context.length > 20) {
      _context = _context.sublist(_context.length - 20);
    }

    _statusController.add(isServerMode ? "Connecting to Neural Backend..." : "Connecting to AI Provider...");
    debugPrint("[BRAIN] Entering ${isServerMode ? 'Server' : 'Client'} Mode");
    debugPrint("[BRAIN] enableBrowser: $enableBrowser");
    debugPrint("[BRAIN] User message: ${userMessage.length > 50 ? userMessage.substring(0, 50) + '...' : userMessage}");
    try {
      List<Map<String, String>> messages = List.from(_context);
      if (!allowEmojis) {
        messages = [
          {'role': 'system', 'content': '要求：回复中不要使用任何 emoji/表情符号/颜文字，只输出纯文本。'},
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
      );
      String response = aiResponse.content;
      if (!allowEmojis) {
        response = _stripEmojis(response);
      }
      if (suppressInnerMonologue) {
        response = _stripInnerMonologue(response);
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
    final showExpressionFace = prefs.getBool('settings.ui.showExpressionFace') ?? true;
    final showLive2D = prefs.getBool('settings.ui.showLive2D') ?? false;
    // Future: final showLive3D = prefs.getBool('settings.ui.showLive3D') ?? false;

    String capabilitiesText = "";
    if (showExpressionFace) {
       capabilitiesText = """
**表情系统限制**：
*   你当前连接的是【简易表情系统】。
*   你只能展示基本的静态表情（如开心、悲伤、生气、惊讶）。
*   **请务必不要**描述复杂的身体动作（如“挥手”、“转圈”、“左右看”），因为你的形象无法执行这些动作。
*   请专注于语言本身的表达。
""";
    } else if (showLive2D) {
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

    // 6. Background Learning (Fire and Forget)
    if (learningProbability > 0 && (learningProbability >= 1.0 || Random().nextDouble() < learningProbability)) {
      _statusController.add("Learning...");
      _learnFromInteraction(userMessage, finalResponse);
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
      // Keep the last 2 messages (current turn)
      final recent = _context.sublist(_context.length - 2);
      final toCompress = _context.sublist(0, _context.length - 2);
      
      // Convert to string
      final historyText = toCompress.map((m) => "${m['role']}: ${m['content']}").join("\n");
      
      // Ask LLM to summarize
      final summaryResponse = await _llmService.chat([
        {'role': 'system', 'content': "Summarize the following conversation history into a concise paragraph. Preserve key facts and user preferences."},
        {'role': 'user', 'content': historyText}
      ], usageType: 'system');
      final summary = summaryResponse.content;

      // Replace context with summary + recent
      _context = [
        {'role': 'system', 'content': "Previous conversation summary: $summary"},
        ...recent
      ];
      
      // Note: Original messages are already saved in ChatHistoryService (SQLite),
      // so we don't need to duplicate them here. The user's requirement for "temporary memory"
      // is satisfied by the persistent chat history which acts as the raw log.
      
    } catch (e) {
      print("Compression failed: $e");
    }
  }

  Future<void> _learnFromInteraction(String userMessage, String assistantResponse) async {
    try {
      // Ask LLM to extract facts
      // We use a separate short context for learning to save tokens
      final analysisResponse = await _llmService.chat([
        {'role': 'system', 'content': MEMORY_EXTRACTION_PROMPT},
        {'role': 'user', 'content': "User: $userMessage\nAssistant: $assistantResponse"}
      ], usageType: 'system');
      String analysisJson = analysisResponse.content;

      // Clean up JSON if needed (remove markdown code blocks)
      final start = analysisJson.indexOf('{');
      final end = analysisJson.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        analysisJson = analysisJson.substring(start, end + 1);
      } else if (analysisJson.contains("```json")) {
        analysisJson = analysisJson.split("```json")[1].split("```")[0];
      } else if (analysisJson.contains("```")) {
        analysisJson = analysisJson.split("```")[1].split("```")[0];
      }

      final data = jsonDecode(analysisJson);
      if (data['should_save'] == true) {
        await _memoryService.saveMemory(
          data['memory_content'],
          data['category'] ?? 'other',
        );
        if (kDebugMode) {
          print("Learned: ${data['memory_content']}");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("Learning failed: $e");
      }
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
        print("Image too large ($width x $height), skipping meme learning.");
        _statusController.add("Image too large for meme.");
        await Future.delayed(Duration(seconds: 1));
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
          print("Meme detected: $description (Reason: ${data['reason']}) - Client side save disabled.");
        }
      } else {
        _statusController.add("Image analyzed (Not a meme)");
        if (kDebugMode) {
          print("Skipped meme learning: ${data['reason']}");
        }
      }
      
      await Future.delayed(Duration(seconds: 1));
      _statusController.add("");
    } catch (e) {
      print("Meme learning failed: $e");
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
