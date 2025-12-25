import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application/l10n/app_localizations.dart';
import '../core/services/brain_service.dart';
import '../widgets/expressive_face.dart';
import '../widgets/character_display.dart';
import '../widgets/live2d_controller.dart';
import '../widgets/glass.dart';
import '../widgets/message_bubble.dart';
import '../widgets/scenario_editor.dart';
import '../data/mock_data.dart'; // Import for ChatMessage
import '../settings/settings_controller.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';
import '../core/services/llm_service.dart';
import '../core/services/chat_history_service.dart' hide ChatMessage;
import 'memory_manager_screen.dart'; // Import MemoryManagerScreen
import 'settings/settings_screen.dart'; // Import SettingsScreen
import 'first_run_dialog.dart'; // Import FirstRunDialog
import '../services/floating_window_factory.dart'; // Import FloatingWindowService
import '../services/floating_window_service.dart'; // Import FloatingWindowService interface
import '../core/services/websocket_service.dart'; // Import WebSocketService
import '../plugins/plugin_manager.dart'; // Import PluginManager
import '../services/logger_service.dart';

class FireflyScreen extends StatefulWidget {
  const FireflyScreen({super.key});

  @override
  State<FireflyScreen> createState() => _FireflyScreenState();
}

class _FireflyScreenState extends State<FireflyScreen> {
  final BrainService _brain = BrainService();
  final LLMService _llmService = LLMService();
  final WebSocketService _wsService = WebSocketService();
  final ChatHistoryService _chatHistory = ChatHistoryService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Uint8List? _pendingImageBytes;
  late final ExpressionController _faceController;
  bool _historyOpen = false; // 左侧历史与功能面板

  String? _latestDanmakuSummary;
  DateTime? _latestDanmakuSummaryAt;

  // Multi-session state
  List<ChatSession> _sessions = [];
  String? _currentSessionId;
  List<Map<String, dynamic>> _messages =
      []; // {role: user/assistant, content: text, created_at: DateTime}
  bool _isLoading = false;
  bool _isLoopbackCapturing = false;
  bool _showMinecraftPOV = false;
  Completer<void>? _interruptCompleter;

  StreamSubscription? _historySubscription;
  StreamSubscription? _faceSubscription;
  StreamSubscription? _ttsSubscription;
  StreamSubscription? _wsSubscription;
  StreamSubscription? _initiativeSubscription;

  // Floating window service
  FloatingWindowService? _floatingWindowService;
  bool _floatingWindowEnabled = false;
  bool _miniExpanded = false;
  // Mini-window control state
  Timer? _floatingControlsHideTimer;
  bool _floatingControlsVisible = false;
  final Live2DController _live2dController = Live2DController();
  bool _lastEnableTts = false;
  bool _initiativeLoopActive = false;
  bool _autoMicListeningActive = false; // 是否处于自动麦克风监听状态
  final AudioRecorder _autoMicRecorder = AudioRecorder(); // 专用于自动监听的录制器

  @override
  void initState() {
    super.initState();
    // logToFile("FireflyScreen.initState started");
    globalPluginManager.ensureInitialized();
    _faceController = ExpressionController();
    // Bind expression stream to UI controller (best-effort)
    _faceSubscription = _brain.expressionAgent.bind(_faceController);
    // logToFile("FireflyScreen.initState: Agents bound");
    
    _loadSessions();
    // logToFile("FireflyScreen.initState: Sessions loaded");

    _historySubscription = _chatHistory.updateStream.listen((_) {
      if (mounted) _loadSessions();
    });

    _ttsSubscription = _brain.ttsStream.listen((bytes) {
      _handleTtsForLive2D(bytes);
    });

    _wsSubscription = _wsService.messageStream.listen(_handleWebSocketMessage);
    
    _initiativeSubscription = _brain.initiativeStream.listen((response) {
      if (!mounted) return;
      
      // Add initiative response to chat
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content': response.content,
          'created_at': DateTime.now(),
        });
      });
      _scrollToBottom();
      
      // Trigger TTS
      try {
        final rootSettings = SettingsScope.of(context).settings;
        if (!rootSettings.enableTts) {
          return;
        }
        final ttsProvider = _resolveAudioProvider(AiProviderCategory.tts);
        if (ttsProvider != null) {
          _brain.speak(response.content, ttsProvider);
        }
      } catch (e) {
        debugPrint("[Initiative] TTS Error: $e");
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // logToFile("FireflyScreen.postFrameCallback: checking first run");
      _checkFirstRun();
    });
    // logToFile("FireflyScreen.initState completed");
  }

  // Simple file logger for Release mode debugging
  void logToFile(String message) {
    try {
      final file = File('startup_log.txt');
      final timestamp = DateTime.now().toIso8601String();
      file.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
    } catch (e) {
      // Ignore logging errors
    }
  }

  String _safeFileName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '未命名';
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> _exportCurrentSession() async {
    if (_currentSessionId == null) return;
    ChatSession? session;
    for (final s in _sessions) {
      if (s.id == _currentSessionId) {
        session = s;
        break;
      }
    }
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final title = session?.title ?? '会话';
    final fileName = '聊天记录_${_safeFileName(title)}_$stamp.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出对话日志',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null || path.isEmpty) return;

    final data = <String, dynamic>{
      'session': <String, dynamic>{
        'id': _currentSessionId,
        'title': title,
      },
      'exportedAt': now.toIso8601String(),
      'messages': _messages
          .map(
            (m) => <String, dynamic>{
              'role': m['role']?.toString() ?? '',
              'content': m['content']?.toString() ?? '',
              if (m['created_at'] is DateTime) 'createdAt': (m['created_at'] as DateTime).toIso8601String(),
              if (m['reasoning_content'] != null) 'reasoningContent': m['reasoning_content'],
              if (m['tool_calls'] != null) 'toolCalls': m['tool_calls'],
            },
          )
          .toList(),
    };
    final jsonText = const JsonEncoder.withIndent('  ').convert(data);
    await File(path).writeAsString(jsonText);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到: $path')));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // logToFile("FireflyScreen.didChangeDependencies started");
    final settings = SettingsScope.of(context).settings;
    if (_lastEnableTts && !settings.enableTts) {
      _stopTtsPlayback();
    }
    _lastEnableTts = settings.enableTts;

    final initiativeMode = settings.ai.initiativeMode;
    if (initiativeMode && !_initiativeLoopActive) {
      _initiativeLoopActive = true;
      _brain.startInitiativeLoop();
    } else if (!initiativeMode && _initiativeLoopActive) {
      _initiativeLoopActive = false;
      _brain.stopInitiativeLoop();
    }
    // Check floating window setting and update accordingly
    // logToFile("FireflyScreen.didChangeDependencies: updating floating window");
    _updateFloatingWindow(settings.enableFloatingWindow, settings.pythonBackendUrl);
    
    // Unify Broadcast Logic: Enable if ANY Live2D mode is active
    // This ensures Sidebar and Mini Window also receive WebSocket events
    final anyLive2D = settings.enableFloatingWindow || 
                      settings.showLive2D || 
                      settings.showLive2DMiniWindow;
    _brain.expressionAgent.setBroadcastEnabled(anyLive2D);

    if (settings.enablePythonBackend && settings.autoConnectBackend && anyLive2D) {
      _wsService.connect(settings.pythonBackendUrl);
    } else {
      _wsService.disconnect();
    }
    
    // Auto voice channel listening trigger
    if (settings.autoVoiceChannelListening && !_isLoopbackCapturing && !_isLoading) {
      _handleLoopbackVoiceInput(isAuto: true);
    }
    // logToFile("FireflyScreen.didChangeDependencies completed");
  }

  Future<void> _updateFloatingWindow(bool enabled, String backendUrl) async {
    // Ensure service is initialized if we are enabling it or if it already exists
    if (_floatingWindowService != null) {
      _floatingWindowService!.updateBackendUrl(backendUrl);
    }

    if (enabled == _floatingWindowEnabled) return;
    _floatingWindowEnabled = enabled;

    // 启用/禁用广播（让悬浮窗通过 WebSocket 接收表情/动作指令）
    _brain.expressionAgent.setBroadcastEnabled(enabled);

    if (!FloatingWindowServiceFactory.isSupported()) return;

    if (enabled) {
      // Create floating window
      try {
        // 获取当前选择的 Live2D 模型路径
        final prefs = await SharedPreferences.getInstance();
        final modelPath = prefs.getString('settings.character.modelPath') ?? '';

        _floatingWindowService ??= FloatingWindowServiceFactory.getInstance(
          backendUrl: backendUrl,
        );
        await _floatingWindowService!.initialize();
        await _floatingWindowService!.createFloatingWindow(
          modelPath: modelPath,
          width: 400,
          height: 600,
        );
        await _floatingWindowService!.executeJavaScript(
          "window.LIVE2D_DISABLE_WEBSOCKET_AUDIO = true; window.LIVE2D_EXTERNAL_AUDIO_MUTED = true;",
        );
      } catch (e) {
        debugPrint('[FireflyScreen] Failed to create floating window: $e');
      }
    } else {
      // Close floating window
      try {
        await _floatingWindowService?.closeFloatingWindow();
      } catch (e) {
        debugPrint('[FireflyScreen] Failed to close floating window: $e');
      }
    }
  }

  Future<void> _interruptGeneration() async {
    if (_autoMicListeningActive) {
      await _stopAutoMicListening();
    }
    if (_isLoading &&
        _interruptCompleter != null &&
        !_interruptCompleter!.isCompleted) {
      _interruptCompleter!.complete();
      setState(() {
        _isLoading = false;
        _messages.add(<String, dynamic>{
          'role': 'system',
          'content': '[用户中断了生成]',
          'created_at': DateTime.now(),
        });
      });
    }
    await _stopTtsPlayback();
  }

  Future<void> _checkFirstRun() async {
    final settingsController = SettingsScope.of(context);
    if (settingsController.settings.isFirstRun) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => FirstRunDialog(
          settingsController: settingsController,
          brain: _brain,
        ),
      );
    }
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    _faceSubscription?.cancel();
    _ttsSubscription?.cancel();
    _wsSubscription?.cancel();
    _initiativeSubscription?.cancel();
    _brain.stopInitiativeLoop();
    _wsService.dispose();
    _floatingWindowService?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _faceController.dispose();
    _focusNode.dispose();
    _floatingControlsHideTimer?.cancel(); // Added back just in case
    _autoMicRecorder.dispose();
    super.dispose();
  }

  String? _latestMinecraftPOV;
  String? _minecraftAgentName;

  void _handleWebSocketMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    
    final type = msg['type'];
    final data = msg['data'];
    
    if (type == 'minecraft_pov') {
      setState(() {
        _latestMinecraftPOV = msg['image'];
        _minecraftAgentName = msg['agent'];
      });
      return;
    }
    
    String? role;
    String? content;
    
    // Handle different formats
    // Backend sends: type="chat_message", text="...", sender="chat_normal"/"chat_sc"
    if (type == 'chat_message') {
       final sender = msg['sender'];
       if (sender == 'chat_normal' || sender == 'chat_sc' || sender == 'minecraft') {
           role = sender == 'minecraft' ? 'assistant' : sender;
           content = msg['text'] ?? msg['content'];
           
           // If it's from Minecraft, prepend the agent name if needed
           if (sender == 'minecraft' && msg['senderName'] != null) {
              content = "【Minecraft】${msg['senderName']}: $content";
           }
       }
    } else if (type == 'chat_normal' || type == 'chat_sc') {
        // Legacy or direct format
        role = type;
        if (data is Map) {
           content = data['content'] ?? data['text'] ?? data.toString();
        } else {
           content = msg['content'] ?? data?.toString();
        }
    } else if (type == 'chat_summary') {
       role = 'chat_summary';
       content = msg['content'] ?? msg['text'];
    }
    
    if (role != null && content != null && content.isNotEmpty) {
            // Filter out raw Danmaku (chat_normal) from the main chat interface
            // unless it's explicitly marked as a summary or important.
            // User requested to show only summaries here.
            if (role == 'chat_normal') {
              _brain.feedDanmaku(content); // Feed raw danmaku to brain for initiative mode
              // debugPrint('[Danmaku] Ignored in main chat: $content');
              return; 
            }

            if (role == 'chat_summary') {
              setState(() {
                _latestDanmakuSummary = content;
                _latestDanmakuSummaryAt = DateTime.now();
              });
              return;
            }

            // Explicitly allow summaries or agent output
            // (role == 'assistant' is standard, 'chat_summary' might be custom)
            
            setState(() {
              _messages.add({
                'role': role,
                'content': content,
                'created_at': DateTime.now(),
              });
            });
            _scrollToBottom();

            // Trigger Brain processing for Minecraft messages
            if (msg['sender'] == 'minecraft') {
              // Feed to brain with source tag
              unawaited(_brain.processMessage(
                content,
                source: 'minecraft',
                agentEnabled: true, // Minecraft context usually implies agent interaction
              ));

              try {
                final rootSettings = SettingsScope.of(context).settings;
                if (rootSettings.enableTts) {
                  final ttsProvider = _resolveAudioProvider(AiProviderCategory.tts);
                  if (ttsProvider != null) {
                    // We speak the content but maybe without the 【Minecraft】 prefix for better TTS?
                    // Let's speak the original text if available
                    final textToSpeak = msg['text'] ?? content;
                    _brain.speak(textToSpeak, ttsProvider);
                  }
                }
              } catch (e) {
                debugPrint("[Minecraft WS] TTS Error: $e");
              }
            }
          }
  }

  Widget _buildMinecraftPOVOverlay(BuildContext context) {
    if (!_showMinecraftPOV || _latestMinecraftPOV == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 120, // Positioned above input area
      right: 16,
      child: Container(
        width: 320,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Image.memory(
              base64Decode(_latestMinecraftPOV!),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE: ${_minecraftAgentName ?? 'Bot'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                onPressed: () => setState(() => _showMinecraftPOV = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildDanmakuSummaryCard(BuildContext context) {
    return AnimatedBuilder(
      animation: globalPluginManager,
      builder: (context, _) {
        final settings = SettingsScope.of(context).settings;
        final hasDanmakuPlugin = globalPluginManager.enabledPlugins
            .any((p) => p.isDanmakuPlugin);
        final summary = _latestDanmakuSummary;
        if (!hasDanmakuPlugin || summary == null || summary.trim().isEmpty) {
          return const SizedBox.shrink();
        }

        final displaySummary = settings.ai.allowEmojis ? summary : _stripEmojis(summary);

        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final time = _latestDanmakuSummaryAt;
        final timeStr = time == null ? null : DateFormat('HH:mm:ss').format(time);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.insights,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '弹幕 Agent 汇总',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (timeStr != null)
                          Text(
                            timeStr,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      displaySummary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleTtsForLive2D(Uint8List bytes) async {
    if (!mounted) return;
    final settings = SettingsScope.of(context).settings;
    if (!settings.enableTts) return;
    final enableAnyLive2D = settings.enableFloatingWindow || settings.showLive2D || settings.showLive2DMiniWindow;
    if (!enableAnyLive2D) return;
    final b64 = base64Encode(bytes);
    final js =
        "window.LIVE2D_DISABLE_WEBSOCKET_AUDIO = true; if (window.stopExternalAudio) window.stopExternalAudio(); if (window.playAudioBase64) window.playAudioBase64('$b64');";
    try {
      await _live2dController.executeJs(js);
    } catch (_) {}
    try {
      if (settings.enableFloatingWindow && _floatingWindowService != null) {
        await _floatingWindowService!.executeJavaScript(js);
      }
    } catch (_) {}
  }

  Future<void> _stopTtsPlayback() async {
    try {
      await _brain.stopSpeaking();
    } catch (_) {}

    if (!mounted) return;
    final settings = SettingsScope.of(context).settings;
    const js = "if (window.stopExternalAudio) window.stopExternalAudio();";

    try {
      await _live2dController.executeJs(js);
    } catch (_) {}

    try {
      if (settings.enableFloatingWindow && _floatingWindowService != null) {
        await _floatingWindowService!.executeJavaScript(js);
      }
    } catch (_) {}
  }

  Future<void> _loadSessions() async {
    final sessions = await _chatHistory.getSessions(type: 'chat');
    if (mounted) {
      setState(() {
        _sessions = sessions;
      });
      // If there are saved sessions and no current session selected, pick the most recent.
      if (_sessions.isNotEmpty && _currentSessionId == null) {
        _selectSession(_sessions.first.id);
      }
      // NOTE: Do NOT auto-create a new session on startup when no sessions exist.
      // Creating sessions should be user-initiated to avoid accumulating unused history entries.
    }
  }

  Future<void> _createNewSession() async {
    final l10n = AppLocalizations.of(context)!;
    final session = await _chatHistory.createSession(
      '${l10n.quickActionNewChat} ${DateTime.now().month}/${DateTime.now().day}',
      type: 'chat',
    );
    await _loadSessions();
    await _selectSession(session.id);
  }

  Future<void> _selectSession(String sessionId) async {
    final msgs = await _chatHistory.getMessages(sessionId);
    setState(() {
      _currentSessionId = sessionId;
      // Explicitly create List<Map<String, dynamic>> to avoid runtime type issues
      _messages = msgs
          .map(
            (m) => <String, dynamic>{
              'role': m.role,
              'content': m.content,
              'created_at': m.createdAt,
            },
          )
          .toList();
    });

    // Update Brain context
    _brain.setContext(
      _messages
          .map(
            (m) => {
              'role': (m['role'] == 'stt_heard' ? 'user' : m['role']).toString(),
              'content': m['content'].toString(),
            },
          )
          .toList(),
    );

    _scrollToBottom();
  }

  Future<void> _deleteSession(String sessionId) async {
    await _chatHistory.deleteSession(sessionId);
    await _loadSessions();
    if (_currentSessionId == sessionId) {
      _currentSessionId = null;
      _messages.clear();
      if (_sessions.isNotEmpty) {
        _selectSession(_sessions.first.id);
      } else {
        _createNewSession();
      }
    }
  }

  AiProviderConfig? _resolveAudioProvider(AiProviderCategory category) {
    final providers = SettingsScope.of(context).providers;

    // 1. Try to find explicit provider with valid baseUrl + apiKey
    final explicit = providers.firstWhere(
      (p) =>
          p.category == category &&
          p.enabled &&
          p.baseUrl.isNotEmpty &&
          p.apiKey.isNotEmpty,
      orElse: () => const AiProviderConfig(id: '', name: '', kind: AiProvider.local),
    );
    if (explicit.id.isNotEmpty) return explicit;

    if (category == AiProviderCategory.stt) {
      final local = providers.firstWhere(
        (p) =>
            p.category == category &&
            p.enabled &&
            p.kind == AiProvider.local &&
            (p.meta['local_stt']?.toString() == 'windows_speech'),
        orElse: () => const AiProviderConfig(id: '', name: '', kind: AiProvider.local),
      );
      if (local.id.isNotEmpty) return local;
    }

    return null;
  }

  Future<void> _handleVoiceInput(String path, {bool fromLoopback = false}) async {
    if (!mounted) return;
    // 如果是自动监听触发的，确保状态正确
    if (_autoMicListeningActive) {
      _autoMicListeningActive = false;
    }
    setState(() => _isLoading = true);
    var keepFile = false;
    try {
      final sttProvider = _resolveAudioProvider(AiProviderCategory.stt);
      if (sttProvider == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未配置 STT 服务')),
        );
        return;
      }

      logger.info(
        '语音转写开始: fromLoopback=$fromLoopback provider=${sttProvider.name} kind=${sttProvider.kind} file=$path',
      );
      final text = (await _brain.transcribe(path, sttProvider)).trim();
      if (text.isNotEmpty) {
        logger.info(
          '语音转写完成: len=${text.length} text="${text.length > 120 ? text.substring(0, 120) : text}"',
        );
        _controller.text = text;
        _sendMessage(
          uiRole: fromLoopback ? 'stt_heard' : 'user', 
          needsRefinement: true,
          source: fromLoopback ? 'voice' : 'direct',
        );
      } else {
        keepFile = true;
        logger.error(
          '语音转写结果为空（已保留音频文件）：fromLoopback=$fromLoopback provider=${sttProvider.name} file=$path',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未识别到文字（转写结果为空，已保留音频文件）：$path')),
        );
      }
    } catch (e) {
      logger.error('语音输入失败', e);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('语音输入失败: $e')));
    } finally {
      try {
        if (!keepFile) {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLoopbackVoiceInput({bool isAuto = false}) async {
    if (!mounted) return;
    if (_isLoading || _isLoopbackCapturing) return;

    // AEC Logic: If AI is speaking, don't capture or transcribe to avoid "hearing itself"
    if (_brain.isAnyTtsActive) {
      if (isAuto) {
        // Wait and retry
        await Future.delayed(const Duration(seconds: 1));
        return _handleLoopbackVoiceInput(isAuto: true);
      }
      return;
    }
    
    // 如果正在麦克风自动监听，先停止它
    if (_autoMicListeningActive) {
      await _stopAutoMicListening();
    }
    
    if (!mounted) return;
    final settings = SettingsScope.of(context).settings;
    if (isAuto && !settings.autoVoiceChannelListening) return;

    setState(() => _isLoopbackCapturing = true);
    String? path;
    var keepFile = false;
    try {
      final sttProvider = _resolveAudioProvider(AiProviderCategory.stt);
      if (sttProvider == null) {
        throw Exception('未配置 STT 服务');
      }
      if (!settings.enablePythonBackend) {
        throw Exception('未启用 Python 后端');
      }
      if (!settings.sttViaBackendLoopback && !isAuto) {
        throw Exception('未开启回环采集，无法开启手动监听。请先在系统设置中开启“回环采集”。');
      }

      String text = '';
      try {
        path = await _brain.captureSystemLoopbackToFile(
          durationSeconds: settings.sttLoopbackDurationSeconds.toDouble(),
          deviceIndex: settings.sttLoopbackDeviceIndex,
          samplerate: 16000,
          channels: 1,
        );
        logger.info(
          '系统回环转写开始: provider=${sttProvider.name} kind=${sttProvider.kind} device=${settings.sttLoopbackDeviceIndex ?? 'default'} file=$path',
        );
        text = (await _brain.transcribe(path, sttProvider)).trim();
      } finally {
        try {
          if (path != null && !keepFile) {
            final f = File(path);
            if (await f.exists()) {
              await f.delete();
            }
          }
        } catch (_) {}
      }

      if (text.isEmpty) {
        if (!mounted) return;
        
        // 如果是自动监听模式，且结果为空，则静默重试
        if (isAuto && settings.autoVoiceChannelListening) {
          setState(() => _isLoopbackCapturing = false);
          // 稍微等待一下再重试，避免过度消耗资源
          await Future.delayed(const Duration(milliseconds: 500));
          return _handleLoopbackVoiceInput(isAuto: true);
        }

        keepFile = true;
        logger.error(
          '系统回环转写结果为空（已保留音频文件）：provider=${sttProvider.name} device=${settings.sttLoopbackDeviceIndex ?? 'default'} file=$path',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未识别到文字（转写结果为空，已保留音频文件）：$path')),
        );
        return;
      }

      logger.info(
        '系统回环转写完成: len=${text.length} text="${text.length > 120 ? text.substring(0, 120) : text}"',
      );
      _controller.text = text;
      _sendMessage(uiRole: 'stt_heard', needsRefinement: true, source: 'voice');
      
      // 成功识别并发送后，如果是自动模式，继续下一次监听循环
      if (isAuto && settings.autoVoiceChannelListening) {
        setState(() => _isLoopbackCapturing = false);
        // 稍微等待 1 秒再开始下一次，给 UI 和处理留出时间
        await Future.delayed(const Duration(seconds: 1));
        return _handleLoopbackVoiceInput(isAuto: true);
      }
    } catch (e) {
      if (!mounted) return;
      logger.error('系统回环监听失败', e);
      if (!isAuto) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('系统回环监听失败: $e')));
      } else if (settings.autoVoiceChannelListening) {
        // 自动模式下出错也尝试重试，避免因为单次错误中断监听
        await Future.delayed(const Duration(seconds: 2));
        return _handleLoopbackVoiceInput(isAuto: true);
      }
    } finally {
      if (mounted) setState(() => _isLoopbackCapturing = false);
    }
  }

  // 开始自动麦克风监听
  Future<void> _startAutoMicListening() async {
    if (!mounted || _autoMicListeningActive || _isLoading) return;

    // AEC Logic: If AI is speaking, don't start recording
    if (_brain.isAnyTtsActive) {
      // For auto-mic, we usually trigger this from a UI action or another loop.
      // If it's already active, it will be handled in the stop/process logic.
      return;
    }

    try {
      if (await _autoMicRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/auto_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
        
        await _autoMicRecorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: path,
        );
        
        setState(() => _autoMicListeningActive = true);
        logger.info('自动麦克风监听已开启: $path');
      }
    } catch (e) {
      logger.error('开启自动麦克风监听失败', e);
    }
  }

  // 停止自动麦克风监听并处理输入
  Future<void> _stopAutoMicListening() async {
    if (!_autoMicListeningActive) return;

    try {
      final path = await _autoMicRecorder.stop();
      setState(() => _autoMicListeningActive = false);
      
      if (path != null) {
        logger.info('自动麦克风监听已停止，准备处理音频: $path');
        await _handleVoiceInput(path);
      }
    } catch (e) {
      logger.error('停止自动麦克风监听失败', e);
      setState(() => _autoMicListeningActive = false);
    }
  }

  Future<void> _sendMessage({
    String uiRole = 'user', 
    bool needsRefinement = false,
    String source = 'direct',
  }) async {
    // 如果正在自动监听，先停止它
    if (_autoMicListeningActive) {
      await _stopAutoMicListening();
    }
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImageBytes == null) return;
    if (_currentSessionId == null) await _createNewSession();

    setState(() {
      // Explicitly cast to Map<String, dynamic> to match _messages definition
      _messages.add(<String, dynamic>{
        'role': uiRole,
        'content': _pendingImageBytes != null
            ? (text.isNotEmpty ? '$text\n[已附加图片]' : '[已附加图片]')
            : text,
        'created_at': DateTime.now(),
        'source': source, // Track source in message history
      });
      _isLoading = true;
      _interruptCompleter = Completer<void>(); // Initialize completer
      _controller.clear();
    });
    _scrollToBottom();

    // Save user message
    await _chatHistory.addMessage(
      _currentSessionId!,
      uiRole,
      text.isEmpty ? '[图片]' : text,
    );

    if (!mounted) return;
    final settings = SettingsScope.of(context).settings;

    // Update session title if it's the first message
    if (_messages.length <= 2) {
      // Simple heuristic: use first 10 chars
      final title = text.length > 15 ? '${text.substring(0, 15)}...' : text;
      await _chatHistory.updateSessionTitle(_currentSessionId!, title);
      _loadSessions(); // Refresh list
    }

    try {
      String response;
      logger.info(
        '发送到AI: uiRole=$uiRole session=${_currentSessionId ?? ''} textLen=${text.length} hasImage=${_pendingImageBytes != null}',
      );

      // Define the generation task
      Future<AiResponse> generationTask() async {
        if (_pendingImageBytes != null) {
          // Trigger background learning (Autonomous Meme Learning)
          final bytesToLearn = Uint8List.fromList(_pendingImageBytes!);
          unawaited(_brain.analyzeAndLearnMeme(bytesToLearn));

          // Try direct vision with active model
          try {
            if (!mounted) throw Exception('Widget unmounted');
            final s = SettingsScope.of(context).settings;
            // Vision selection strategy: use main if capable; else use selected vision provider; else fallback
            final useMainIfCapable = s.useMainVisionIfCapable;
            final mainVisionCapable = await _llmService
                .isActiveModelVisionCapable();
            
            if (!mounted) throw Exception('Widget unmounted');
            final selectedVisionProviderId =
                SettingsScope.of(context).settings.activeVisionProviderId; // null means follow main

            if (useMainIfCapable && mainVisionCapable) {
              final defaultHint =
                  '${s.visionPromptTemplate}\n长度建议约${s.visionPreferredLength}字，最多${s.visionMaxLength}字。';
              final visionMessages = _messages
                  .map(
                    (m) => {
                      'role': (m['role'] == 'stt_heard' ? 'user' : m['role']).toString(),
                      'content': m['content'].toString(),
                    },
                  )
                  .toList();
              if (!s.ai.allowEmojis) {
                visionMessages.insert(
                  0,
                  {
                    'role': 'system',
                    'content': '要求：回复中不要使用任何 emoji/表情符号/颜文字，只输出纯文本。',
                  },
                );
              }
              final content = await _llmService.chatWithImage(
                messages: visionMessages,
                imageBytes: _pendingImageBytes!,
                prompt: text.isNotEmpty ? text : defaultHint,
                usageType: 'main',
              );
              return AiResponse(content: content);
            } else if (selectedVisionProviderId != null &&
                selectedVisionProviderId.isNotEmpty) {
              final defaultHint =
                  '${s.visionPromptTemplate}\n长度建议约${s.visionPreferredLength}字，最多${s.visionMaxLength}字。';
              final visionMessages = _messages
                  .map(
                    (m) => {
                      'role':
                          (m['role'] == 'stt_heard' ? 'user' : m['role']).toString(),
                      'content': m['content'].toString(),
                    },
                  )
                  .toList();
              if (!s.ai.allowEmojis) {
                visionMessages.insert(
                  0,
                  {
                    'role': 'system',
                    'content': '要求：回复中不要使用任何 emoji/表情符号/颜文字，只输出纯文本。',
                  },
                );
              }
              final content = await _llmService.chatWithImage(
                messages: visionMessages,
                imageBytes: _pendingImageBytes!,
                prompt: text.isNotEmpty ? text : defaultHint,
                usageType: 'main',
                providerIdOverride: selectedVisionProviderId,
              );
              return AiResponse(content: content);
            } else {
              // Fallback: insert helper guidance to switch to a vision-capable model
              const helper =
                  '当前未配置视觉中枢或模型不支持视觉。建议在系统 → 视觉中枢中选择具备视觉能力的平台（如 gpt-4o、qwen2.5-vl）。我将按文字路径继续。';
              if (mounted) {
                setState(() {
                  _messages.add(<String, dynamic>{
                    'role': 'assistant',
                    'content': helper,
                    'created_at': DateTime.now(),
                  });
                });
              }
              return await _brain.processMessage(
                text.isNotEmpty ? text : '用户上传了一张图片，但当前模型不支持视觉。请仅基于现有上下文继续对话。',
                agentEnabled: settings.agentEnabled,
                enableBrowser: settings.enableBrowser,
                enableNoteAccess: settings.enableNoteAccess,
                userNickname: settings.userNickname,
                learningProbability: settings.learningProbability,
                enableExpressionAgent: settings.enableExpressionAgent,
                systemPromptOverride: settings.systemPrompt,
                sessionId: _currentSessionId,
                needsRefinement: needsRefinement,
                source: source,
              );
            }
          } catch (_) {
            // Fallback to plain text path using brain
            return await _brain.processMessage(
              text.isNotEmpty ? text : '我上传了一张图片，请结合上下文进行分析。',
              agentEnabled: settings.agentEnabled,
              enableBrowser: settings.enableBrowser,
              enableNoteAccess: settings.enableNoteAccess,
              userNickname: settings.userNickname,
              learningProbability: settings.learningProbability,
              enableExpressionAgent: settings.enableExpressionAgent,
              systemPromptOverride: settings.systemPrompt,
              sessionId: _currentSessionId,
              needsRefinement: needsRefinement,
              source: source,
            );
          }
        } else {
          if (!mounted) throw Exception('Widget unmounted');
          final provider = SettingsScope.of(
            context,
          ).selectProviderForNextCall(category: AiProviderCategory.llm);

          logger.info(
            'LLM provider选择: ${provider?.name ?? 'null'} (${provider?.id ?? ''})',
          );
          final result = await _brain.processMessage(
            text,
            agentEnabled: settings.agentEnabled,
            enableBrowser: settings.enableBrowser,
            enableNoteAccess: settings.enableNoteAccess,
            userNickname: settings.userNickname,
            learningProbability: settings.learningProbability,
            enableExpressionAgent: settings.enableExpressionAgent,
            systemPromptOverride: settings.systemPrompt,
            providerOverride: provider,
            sessionId: _currentSessionId,
            needsRefinement: needsRefinement,
            source: source,
          );

          if (provider != null && mounted) {
            await SettingsScope.of(context).incrementUsage(provider.id);
          }
          return result;
        }
      }

      // Race between generation and interrupt
      final result = await Future.any([
        generationTask(),
        _interruptCompleter!.future.then((_) => '__INTERRUPTED__'),
      ]);

      if (result == '__INTERRUPTED__') {
        return; // Stop processing
      }

      final aiResponse = result as AiResponse;
      response = aiResponse.content;
      if (response.trim().isEmpty) {
        logger.error(
          'AI 回复为空: uiRole=$uiRole session=${_currentSessionId ?? ''} textLen=${text.length}',
        );
        throw Exception('AI 回复为空');
      }

      if (mounted) {
        var cleanedResponse = _stripExpressionBlocks(response);
        if (!settings.ai.allowEmojis) {
          cleanedResponse = _stripEmojis(cleanedResponse);
        }

        if (settings.chatMode == ChatModeOption.standard) {
          final displayContent =
              cleanedResponse.replaceAll('[SPLIT]', '\n\n').trim();
          setState(() {
            _isLoading = false;
            _pendingImageBytes = null;
            _messages.add(<String, dynamic>{
              'role': 'assistant',
              'content': displayContent,
              'reasoning_content': aiResponse.reasoningContent,
              'tool_calls': aiResponse.toolCalls,
              'created_at': DateTime.now(),
            });
          });
          _scrollToBottom();
          await _chatHistory.addMessage(
            _currentSessionId!,
            'assistant',
            displayContent,
          );

          // Trigger Motion Agent
          if (settings.enableLive2D) {
            _brain.expressionAgent.requestMotion(text, displayContent);
          }

          // Trigger TTS
          if (settings.enableTts) {
            final ttsProvider = _resolveAudioProvider(AiProviderCategory.tts);
            if (ttsProvider != null) {
              _brain.speak(displayContent, ttsProvider);
            }
          }

          // 自动监听逻辑
          if (settings.autoMicListening) {
            _startAutoMicListening();
          } else if (settings.autoVoiceChannelListening) {
            _handleLoopbackVoiceInput(isAuto: true);
          }
        } else {
          final parts = _splitPersonaText(cleanedResponse);

          setState(() {
            _isLoading = false;
            _pendingImageBytes = null;
          });

          for (var i = 0; i < parts.length; i++) {
            final part = parts[i].trim();
            if (part.isEmpty) continue;

            if (i > 0) {
              // Add a small natural delay between messages
              await Future.delayed(
                Duration(milliseconds: 500 + (part.length * 20).clamp(0, 1500)),
              );
              if (!mounted) return;
            }

            setState(() {
              _messages.add(<String, dynamic>{
                'role': 'assistant',
                'content': part,
                'created_at': DateTime.now(),
              });
            });
            _scrollToBottom();
            // Save assistant message
            await _chatHistory.addMessage(
              _currentSessionId!,
              'assistant',
              part,
            );
          }

          // Trigger Motion Agent with full response
          if (settings.enableLive2D) {
            _brain.expressionAgent.requestMotion(text, cleanedResponse);
          }

          if (settings.enableTts) {
            final ttsProvider = _resolveAudioProvider(AiProviderCategory.tts);
            if (ttsProvider != null) {
              _brain.speakChunks(parts, ttsProvider);
            }
          }

          // 自动监听逻辑
          if (settings.autoMicListening) {
            _startAutoMicListening();
          } else if (settings.autoVoiceChannelListening) {
            _handleLoopbackVoiceInput(isAuto: true);
          }
        }
      }
    } catch (e) {
      logger.error('AI 生成失败', e);
      if (mounted && _isLoading) {
        // Only show error if not interrupted/cleared
        setState(() {
          _messages.add(<String, dynamic>{
            'role': 'assistant',
            'content': '呜呜，我好像出错了... ($e)',
            'created_at': DateTime.now(),
          });
          _isLoading = false;
          _pendingImageBytes = null;
        });
      }
    }
  }

  /// Remove fenced JSON/code blocks likely containing expression payloads
  /// such as ```json { "expression": { ... } } ``` or generic code fences.
  String _stripExpressionBlocks(String text) {
    // Remove triple-backtick fenced blocks entirely
    final fence = RegExp(r"```[\s\S]*?```", multiLine: true);
    var cleaned = text.replaceAll(fence, '').trim();
    // Additionally remove inline JSON starting after 'expression:' keyword
    final idx = cleaned.toLowerCase().indexOf('expression:');
    if (idx != -1) {
      final before = cleaned.substring(0, idx);
      // Try to drop following JSON braces if present
      final after = cleaned.substring(idx + 'expression:'.length);
      final endIdx = after.indexOf('}');
      if (after.contains('{') && endIdx != -1) {
        cleaned = before + after.substring(endIdx + 1);
      } else {
        cleaned = before;
      }
      cleaned = cleaned.trim();
    }
    return cleaned;
  }

  static final RegExp _emojiRegex = RegExp(
    r'[\u{1F1E6}-\u{1F1FF}\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{200D}\u{FE0E}\u{FE0F}]',
    unicode: true,
  );

  String _stripEmojis(String text) {
    final cleaned = text.replaceAll(_emojiRegex, '');
    return cleaned
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trimRight();
  }

  List<String> _splitPersonaText(String text) {
    final result = <String>[];
    final primaryParts = text.split('[SPLIT]');
    for (final raw in primaryParts) {
      var p = raw.replaceAll('\r\n', '\n').trim();
      if (p.isEmpty) continue;
      final paragraphs = p.split(RegExp(r'\n{2,}'));
      for (var para in paragraphs) {
        final t = para.trim();
        if (t.isEmpty) continue;
        result.add(t);
      }
    }
    return result;
  }

  Future<void> _attachImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res != null &&
          res.files.isNotEmpty &&
          res.files.first.bytes != null) {
        setState(() {
          _pendingImageBytes = res.files.first.bytes;
        });
        // Auto-send if no text
        if (_controller.text.trim().isEmpty) {
          _sendMessage();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${AppLocalizations.of(context)!.errImagePick}$e'),
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ignore: unused_element
  void _editMessage(int index) async {
    if (_currentSessionId == null) return;
    final msg = _messages[index];
    if (msg['role'] != 'user' && msg['role'] != 'stt_heard') return;

    final content = msg['content'] as String;
    final createdAt = msg['created_at'] as DateTime;

    // Populate controller
    _controller.text = content;

    // Remove from UI
    setState(() {
      _messages.removeRange(index, _messages.length);
    });

    // Remove from DB
    await _chatHistory.deleteMessagesFrom(_currentSessionId!, createdAt);
  }

  @override
  Widget build(BuildContext context) {
    logToFile("FireflyScreen.build started");
    final settingsController = SettingsScope.of(context);
    final settings = settingsController.settings;
    // final quickActions = settings.quickActions;
    final l10n = AppLocalizations.of(context)!;
    final screenWidth = MediaQuery.of(context).size.width;
    final historyPanelWidth = screenWidth > 360 ? 320.0 : screenWidth * 0.85;

    // Determine font family for the title
    String? titleFontFamily;
    if (settings.decoFamily == DecorativeFontFamily.fzg) {
      titleFontFamily = 'FZG';
    } else if (settings.decoFamily == DecorativeFontFamily.nfdcs) {
      titleFontFamily = 'nfdcs';
    }

    final isDesktop = screenWidth > 800; // Simple desktop check

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: isDesktop
          ? _buildDesktopLayout(
              context,
              settings,
              settingsController,
              l10n,
              titleFontFamily,
            )
          : _buildMobileLayout(
              context,
              settings,
              settingsController,
              l10n,
              titleFontFamily,
              historyPanelWidth,
            ),
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    AppSettings settings,
    SettingsController settingsController,
    AppLocalizations l10n,
    String? titleFontFamily,
  ) {
    return Row(
      children: [
        if (_historyOpen)
          SizedBox(width: 300, child: _buildHistoryPanel(context, l10n)),
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(context, settings, titleFontFamily),
                  _buildDanmakuSummaryCard(context),
                  Expanded(
                child: Stack(
                  children: [
                    if (_messages.isEmpty) _buildBackgroundGreeting(context),
                    _buildMessageList(context, settings),
                  ],
                ),
              ),
                  _buildInputArea(
                    context,
                    settings,
                    settingsController,
                    l10n,
                    settings.quickActions,
                  ),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: IconButton(
                    icon: Icon(_historyOpen ? Icons.menu_open : Icons.menu),
                    onPressed: () =>
                        setState(() => _historyOpen = !_historyOpen),
                  ),
                ),
              ),
              if (settings.showExpressionFace)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: SafeArea(
                      child: _DynamicIsland(
                        faceController: _faceController,
                        statusStream: _brain.statusStream,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: SafeArea(
                  child: _buildDisplayModeButton(
                    context,
                    settings,
                    settingsController,
                  ),
                ),
              ),
              if (settings.enableLive2D && settings.showLive2DMiniWindow)
                _buildLive2DMiniWindowOverlay(context, settings),
              _buildMinecraftPOVOverlay(context),
            ],
          ),
        ),
        if (settings.enableLive2D &&
            settings.showLive2D &&
            !settings.enableFloatingWindow)
          Container(
            width: 400,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: CharacterDisplay(
              backendUrl: settings.pythonBackendUrl,
              expressionAgent: _brain.expressionAgent,
              controller: _live2dController,
              floatingUi: true,
              showControls: true,
            ),
          ),
      ],
    );
  }

  /// 显示模式下拉菜单按钮
  Widget _buildDisplayModeButton(
    BuildContext context,
    AppSettings settings,
    SettingsController settingsController,
  ) {
    // 图标与当前激活模式一致
    IconData currentIcon;
    bool isActive;
    if (settings.showExpressionFace) {
      currentIcon = Icons.face_retouching_natural; // 表情系统模式
      isActive = true;
    } else if (settings.enableFloatingWindow) {
      currentIcon = Icons.open_in_new; // 悬浮窗模式
      isActive = true;
    } else if (settings.showLive2D) {
      currentIcon = Icons.view_sidebar; // 侧边栏模式
      isActive = true;
    } else {
      currentIcon = Icons.visibility_off; // 隐藏模式
      isActive = false;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Thinking Mode Toggle (DeepSeek)
        if (settings.agentEnabled)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  final newValue = !(settings.ai.enableThinking);
                  settingsController.updateAiSettings(settings.ai.copyWith(enableThinking: newValue));
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(newValue ? 'Thinking Mode Enabled' : 'Thinking Mode Disabled'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology, 
                        size: 20, 
                        color: (settings.ai.enableThinking) ? Colors.orange : Colors.grey
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Thinking",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: (settings.ai.enableThinking) ? Colors.orange : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Initiative Mode Toggle (搭话模式)
        if (settings.agentEnabled)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  final newValue = !settings.ai.initiativeMode;
                  settingsController.updateAiSettings(settings.ai.copyWith(initiativeMode: newValue));
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(newValue ? '搭话模式已开启' : '搭话模式已关闭'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.record_voice_over, 
                        size: 20, 
                        color: settings.ai.initiativeMode ? Colors.green : Colors.grey
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "搭话",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: settings.ai.initiativeMode ? Colors.green : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Scenario Context & Objectives Toggle (场景描述)
        Container(
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const ScenarioEditor(),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      (settings.scenarioContext.isNotEmpty || settings.scenarioTasks.isNotEmpty)
                          ? Icons.assignment
                          : Icons.assignment_outlined,
                      size: 20,
                      color: (settings.scenarioContext.isNotEmpty || settings.scenarioTasks.isNotEmpty)
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "状态描述",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (settings.scenarioContext.isNotEmpty || settings.scenarioTasks.isNotEmpty)
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: PopupMenuButton<String>(
            tooltip: '显示模式',
            padding: EdgeInsets.zero,
            icon: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(
                currentIcon,
                size: 24,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            onSelected: (value) {
              if (value == 'minecraft_pov') {
                setState(() => _showMinecraftPOV = !_showMinecraftPOV);
                return;
              }
              // Mutually exclusive logic: Disable all first
              settingsController.setShowExpressionFace(false);
              settingsController.setShowLive2D(false);
              settingsController.setEnableFloatingWindow(false);
              settingsController.setShowLive2DMiniWindow(false);

              switch (value) {
                case 'expression':
                  settingsController.setShowExpressionFace(true);
                  break;
                case 'sidebar':
                  settingsController.setShowLive2D(true);
                  break;
                case 'floating_native':
                  settingsController.setEnableFloatingWindow(true);
                  break;
                case 'floating_mini':
                  settingsController.setShowLive2DMiniWindow(true);
                  break;
                case 'hide':
                  // All disabled above
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'expression',
                child: Row(
                  children: [
                    Icon(
                      Icons.face_retouching_natural,
                      color: settings.showExpressionFace
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    const SizedBox(width: 12),
                    const Text('表情系统（灵动岛）'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'sidebar',
                child: Row(
                  children: [
                Icon(
                  Icons.view_sidebar,
                  color: settings.showLive2D && !settings.enableFloatingWindow
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                const Text('Live2D 侧边栏'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'floating_native',
            child: Row(
              children: [
                Icon(
                  Icons.open_in_new,
                  color: settings.enableFloatingWindow
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                const Text('Live2D 原生悬浮窗'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'floating_mini',
            child: Row(
              children: [
                Icon(
                  Icons.open_in_new,
                  color: settings.showLive2DMiniWindow
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                const Text('Live2D 应用内小窗'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'hide',
            child: Row(
              children: [
                Icon(
                  Icons.visibility_off,
                  color:
                      !settings.showLive2D &&
                          !settings.enableFloatingWindow &&
                          !settings.showExpressionFace
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                const SizedBox(width: 12),
                const Text('全部隐藏'),
              ],
            ),
          ),
        ],
      ),
    ),
      ],
    );
  }

  Widget _buildLive2DMiniWindowOverlay(BuildContext context, AppSettings settings) {
    const double width = 120;
    const double height = 160;
    const borderRadius = BorderRadius.all(Radius.circular(16));

    // Controls placed to the left of the mini window.
    final isAndroid = Platform.isAndroid;
    const double btnSize = 48.0;

    return Positioned(
      top: 84,
      // Shift the mini-window left to avoid overlapping the top-right menu
      right: 84,
      child: SafeArea(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MouseRegion(
              onEnter: (_) {
                if (!isAndroid) {
                  _floatingControlsHideTimer?.cancel();
                  setState(() => _floatingControlsVisible = true);
                }
              },
              onExit: (_) {
                if (!isAndroid) {
                  _floatingControlsHideTimer?.cancel();
                  _floatingControlsHideTimer = Timer(const Duration(seconds: 2), () {
                    if (mounted) setState(() => _floatingControlsVisible = false);
                  });
                }
              },
              child: GestureDetector(
                onTap: () => setState(() => _miniExpanded = !_miniExpanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: _miniExpanded || _floatingControlsVisible ? 84 : 36,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0,4)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _miniExpanded ? Icons.arrow_back_ios_new : Icons.arrow_forward_ios,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(height: 8),
                      if (_miniExpanded || _floatingControlsVisible)
                        Builder(builder: (ctx) {
                          Future<void> evalJs(String js) async {
                            try {
                              if (settings.enableFloatingWindow && _floatingWindowService != null) {
                                await _floatingWindowService!.executeJavaScript(js);
                              } else {
                                // Use CharacterDisplay controller if attached
                                // Note: controller attach is handled elsewhere when CharacterDisplay is created
                                final controller = _live2dController;
                                await controller.executeJs(js);
                              }
                            } catch (e) {
                              debugPrint('[MiniLeftBar] JS exec failed: $e');
                            }
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: btnSize,
                                height: btnSize,
                                child: IconButton(
                                  tooltip: 'Settings',
                                  icon: const Icon(Icons.settings, size: 20),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text('Live2D Settings'),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            StatefulBuilder(
                                              builder: (context, setState) {
                                                return SwitchListTile(
                                                  title: const Text('Follow Mouse'),
                                                  value: true,
                                                  onChanged: (val) {
                                                    evalJs("if(window.live2dManager) { window.live2dManager.mouseTrackingEnabled = $val; }");
                                                    Navigator.pop(context);
                                                  },
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: btnSize,
                                height: btnSize,
                                child: IconButton(
                                  tooltip: 'Lock/Unlock',
                                  icon: const Icon(Icons.lock_outline, size: 20),
                                  onPressed: () async {
                                    await _live2dController.executeJs("window.dispatchEvent(new CustomEvent('live2d-lock-click')); ");
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: btnSize,
                                height: btnSize,
                                child: IconButton(
                                  tooltip: 'Reload',
                                  icon: const Icon(Icons.refresh, size: 20),
                                  onPressed: () async {
                                    await _live2dController.executeJs("window.location.reload();");
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: btnSize,
                                height: btnSize,
                                child: IconButton(
                                  tooltip: 'Close',
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: () {
                                    final settingsController = SettingsScope.of(context);
                                    settingsController.setShowLive2DMiniWindow(false);
                                  },
                                ),
                              ),
                            ],
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: borderRadius,
                child: SizedBox(
                  width: width,
                  height: height,
                  child: CharacterDisplay(
                    backendUrl: settings.pythonBackendUrl,
                    expressionAgent: _brain.expressionAgent,
                    controller: _live2dController,
                    floatingUi: true,
                    showControls: false,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    AppSettings settings,
    SettingsController settingsController,
    AppLocalizations l10n,
    String? titleFontFamily,
    double historyPanelWidth,
  ) {
    return Stack(
      children: [
        // Live2D Character (Background Layer)
        if (settings.enableLive2D)
          Positioned(
            right: 0,
            bottom: 0,
            width: 400,
            height: 600,
            child: CharacterDisplay(
              backendUrl: settings.pythonBackendUrl,
              expressionAgent: _brain.expressionAgent,
            ),
          ),

        // 主聊天列 — 在历史面板打开时向右平移，避免被面板遮挡
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          left: _historyOpen ? historyPanelWidth : 0,
          right: 0,
          child: Column(
            children: [
              _buildHeader(context, settings, titleFontFamily),
              _buildDanmakuSummaryCard(context),
              Expanded(child: _buildMessageList(context, settings)),
              _buildInputArea(
                context,
                settings,
                settingsController,
                l10n,
                settings.quickActions,
              ),
            ],
          ),
        ),
        // 顶部居中动态岛（表情）- 与 Live2D 互斥
        if (settings.showExpressionFace)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: SafeArea(
                child: _DynamicIsland(
                  faceController: _faceController,
                  statusStream: _brain.statusStream,
                ),
              ),
            ),
          ),
        // 左上角历史按钮
        Positioned(
          top: 12,
          left: 12,
          child: SafeArea(
            child: GestureDetector(
              onTap: () => setState(() => _historyOpen = !_historyOpen),
              child: Glass(
                padding: const EdgeInsets.all(10),
                borderRadius: BorderRadius.circular(18),
                child: Icon(_historyOpen ? Icons.close : Icons.menu, size: 22),
              ),
            ),
          ),
        ),

        // 右上角显示模式下拉菜单
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            child: _buildDisplayModeButton(
              context,
              settings,
              settingsController,
            ),
          ),
        ),
        if (settings.enableLive2D && settings.showLive2DMiniWindow)
          _buildLive2DMiniWindowOverlay(context, settings),

        // 当历史面板打开时，添加一个透明遮罩，点击遮罩可关闭面板
        if (_historyOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _historyOpen = false),
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),
        // 历史与功能面板 Overlay
        AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          top: 0,
          bottom: 0,
          left: _historyOpen ? 0 : -historyPanelWidth,
          width: historyPanelWidth,
          child: _buildHistoryPanel(context, l10n),
        ),
      ],
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppSettings settings,
    String? titleFontFamily,
  ) {
    final hasScenario = settings.scenarioContext.isNotEmpty || settings.scenarioTasks.isNotEmpty;

    return Container(
      height: 80,
      alignment: Alignment.center,
      child: (!settings.showExpressionFace)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 48), // Space for menu button
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            settings.assistantName,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              fontFamily: titleFontFamily,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasScenario)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              Text(
                                hasScenario ? '场景模式激活' : 'Astra-Me',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 1.2,
                                  color: hasScenario ? Colors.green : Theme.of(context).colorScheme.outline,
                                  fontFamily: titleFontFamily,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 48), // Space for symmetry or other buttons
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildMessageList(BuildContext context, AppSettings settings) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _messages.length,
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final role = msg['role']?.toString() ?? '';
        final isUser = role == 'user' || role == 'stt_heard';
        final time = msg['created_at'] as DateTime?;
        final timeStr = time != null ? _formatMessageTimestamp(time) : '';

        return RepaintBoundary(
          child: MessageBubble(
            message: ChatMessage(
              id: index.toString(),
              text: msg['content'],
              isMine: isUser,
              role: msg['role'], // Pass role for plugin message support
              time: timeStr,
              reasoningContent: msg['reasoning_content'], // Pass reasoning if available
              toolCalls: msg['tool_calls'], // Pass tool calls if available
            ),
          ),
        );
      },
    );
  }

  Widget _buildBackgroundGreeting(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo or Icon
            Opacity(
              opacity: 0.15,
              child: Image.asset(
                'assets/images/logo.png',
                width: 120,
                height: 120,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.auto_awesome,
                  size: 80,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Greeting Title
            Text(
              l10n.appTitle,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface.withOpacity(0.4),
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            // Greeting Message
            FutureBuilder<String?>(
              future: _llmService.getApiKey(),
              builder: (context, snapshot) {
                final hasKey =
                    snapshot.hasData &&
                    snapshot.data != null &&
                    snapshot.data!.isNotEmpty;
                final message =
                    hasKey ? l10n.greetingNormal : l10n.greetingMissingKey;

                return Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                    height: 1.6,
                  ),
                );
              },
            ),
            const SizedBox(height: 48),
            // Feature hints
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildFeatureHint(Icons.chat_bubble_outline, "自然对话"),
                _buildFeatureHint(Icons.extension_outlined, "插件扩展"),
                _buildFeatureHint(Icons.face_retouching_natural, "Live2D 交互"),
                _buildFeatureHint(Icons.translate, "语音识别"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureHint(IconData icon, String label) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary.withOpacity(0.5)),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
       ),
     );
   }

  String _formatMessageTimestamp(DateTime time) {
    final now = DateTime.now();
    final sameDay =
        time.year == now.year && time.month == now.month && time.day == now.day;
    if (sameDay) return DateFormat('HH:mm').format(time);
    if (time.year != now.year) return DateFormat('yyyy-MM-dd HH:mm').format(time);
    return DateFormat('MM-dd HH:mm').format(time);
  }

  Widget _buildInputArea(
    BuildContext context,
    AppSettings settings,
    SettingsController settingsController,
    AppLocalizations l10n,
    List<String> quickActions,
  ) {
    return Column(
      children: [
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: StreamBuilder<String>(
              stream: _brain.statusStream,
              builder: (context, snapshot) {
                final status = snapshot.data ?? 'Thinking...';
                final showThoughts = SettingsScope.of(
                  context,
                ).settings.showAgentThoughts;

                if (!showThoughts) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        status,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              PopupMenuButton<String>(
                tooltip: '更多',
                onSelected: (value) async {
                  switch (value) {
                    case 'attach_image':
                      _attachImage();
                      break;
                    case 'compress':
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.msgCompressing)),
                      );
                      await _brain.compressContext();
                      break;
                    case 'new_chat':
                      _createNewSession();
                      break;
                    case 'memory':
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MemoryManagerScreen(),
                        ),
                      );
                      break;
                    case 'expression_toggle':
                      settingsController.setShowExpressionFace(
                        !settings.showExpressionFace,
                      );
                      break;
                    case 'tts_toggle':
                      settingsController.setEnableTts(!settings.enableTts);
                      break;
                    case 'auto_mic_toggle':
                      settingsController.setAutoMicListening(!settings.autoMicListening);
                      break;
                    case 'auto_loopback_toggle':
                      settingsController.setAutoVoiceChannelListening(!settings.autoVoiceChannelListening);
                      break;
                    case 'loopback':
                      await _handleLoopbackVoiceInput();
                      break;
                  }
                },
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<String>>[];

                  final hasAttachImage = quickActions.contains('attach_image');
                  final hasCompress = quickActions.contains('compress');
                  final hasNewChat = quickActions.contains('new_chat');
                  final hasMemory = quickActions.contains('memory');
                  final hasExpressionToggle =
                      quickActions.contains('expression_toggle');

                  // 自动监听快捷开关
                  if (settings.enableStt) {
                    items.add(
                      PopupMenuItem(
                        value: 'auto_mic_toggle',
                        child: Row(
                          children: [
                            Icon(
                              settings.autoMicListening
                                  ? Icons.mic
                                  : Icons.mic_none,
                              size: 18,
                              color: settings.autoMicListening ? Colors.green : null,
                            ),
                            const SizedBox(width: 10),
                            Text(settings.autoMicListening ? '关闭麦克风自动监听' : '开启麦克风自动监听'),
                          ],
                        ),
                      ),
                    );
                    if (settings.enablePythonBackend) {
                      items.add(
                        PopupMenuItem(
                          value: 'auto_loopback_toggle',
                          child: Row(
                            children: [
                              Icon(
                                settings.autoVoiceChannelListening
                                    ? Icons.hearing
                                    : Icons.hearing_outlined,
                                size: 18,
                                color: settings.autoVoiceChannelListening ? Colors.green : null,
                              ),
                              const SizedBox(width: 10),
                              Text(settings.autoVoiceChannelListening ? '关闭语音频道自动监听' : '开启语音频道自动监听'),
                            ],
                          ),
                        ),
                      );
                    }
                    items.add(const PopupMenuDivider());
                  }

                  if (hasAttachImage) {
                    items.add(
                      PopupMenuItem(
                        value: 'attach_image',
                        child: Row(
                          children: [
                            const Icon(Icons.image_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text(l10n.quickActionAttachImage),
                          ],
                        ),
                      ),
                    );
                  }

                  if (settings.enableStt &&
                      settings.sttViaBackendLoopback &&
                      settings.enablePythonBackend) {
                    items.add(
                      PopupMenuItem(
                        value: 'loopback',
                        enabled: !_isLoading && !_isLoopbackCapturing,
                        child: Row(
                          children: [
                            Icon(
                              _isLoopbackCapturing
                                  ? Icons.hearing_disabled
                                  : Icons.headphones,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _isLoopbackCapturing
                                  ? '回环采集中…'
                                  : '回环采集（系统声音）',
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (hasCompress) {
                    items.add(
                      PopupMenuItem(
                        value: 'compress',
                        child: Row(
                          children: [
                            const Icon(Icons.cleaning_services_outlined,
                                size: 18),
                            const SizedBox(width: 10),
                            Text(l10n.quickActionCompress),
                          ],
                        ),
                      ),
                    );
                  }

                  if (hasNewChat) {
                    items.add(
                      PopupMenuItem(
                        value: 'new_chat',
                        child: Row(
                          children: [
                            const Icon(Icons.add_comment_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text(l10n.quickActionNewChat),
                          ],
                        ),
                      ),
                    );
                  }

                  if (hasMemory) {
                    items.add(
                      PopupMenuItem(
                        value: 'memory',
                        child: Row(
                          children: [
                            const Icon(Icons.memory, size: 18),
                            const SizedBox(width: 10),
                            Text(l10n.quickActionMemory),
                          ],
                        ),
                      ),
                    );
                  }

                  if (hasExpressionToggle) {
                    items.add(
                      PopupMenuItem(
                        value: 'expression_toggle',
                        child: Row(
                          children: [
                            Icon(
                              settings.showExpressionFace
                                  ? Icons.emoji_emotions
                                  : Icons.emoji_emotions_outlined,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(l10n.quickActionExpression),
                          ],
                        ),
                      ),
                    );
                  }

                  items.add(const PopupMenuDivider());
                  items.add(
                    PopupMenuItem(
                      value: 'tts_toggle',
                      child: Row(
                        children: [
                          Icon(
                            settings.enableTts
                                ? Icons.record_voice_over
                                : Icons.voice_over_off,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(settings.enableTts ? 'TTS：开' : 'TTS：关'),
                        ],
                      ),
                    ),
                  );

                  return items;
                },
                icon: const Icon(Icons.add_circle_outline),
              ),
              const SizedBox(width: 6),
              _VoiceInputButton(onRecorded: _handleVoiceInput),
              const SizedBox(width: 8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () =>
                        _sendMessage(),
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): () {
                      final text = _controller.text;
                      final selection = _controller.selection;
                      final newText = text.replaceRange(
                        selection.start,
                        selection.end,
                        '\n',
                      );
                      _controller.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(
                          offset: selection.start + 1,
                        ),
                      );
                    },
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 5,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      hintText: l10n.chatPlaceholder,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  _isLoading ? Icons.stop_circle_outlined : Icons.send,
                ),
                onPressed: _isLoading ? () => _interruptGeneration() : _sendMessage,
                color: _isLoading ? Theme.of(context).colorScheme.error : null,
                tooltip: _isLoading ? 'Interrupt' : 'Send',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryPanel(BuildContext context, AppLocalizations l10n) {
    return Material(
      elevation: 16,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.historyTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: _exportCurrentSession,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final isSelected = session.id == _currentSessionId;
                return ListTile(
                  title: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    DateFormat('MM/dd HH:mm').format(session.updatedAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  selected: isSelected,
                  onTap: () {
                    _selectSession(session.id);
                    if (MediaQuery.of(context).size.width <= 800) {
                      setState(() => _historyOpen = false);
                    }
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16),
                    onPressed: () => _deleteSession(session.id),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          // Bottom area of history panel (Plugin Toggles)
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '插件控制 (Plugins)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _PluginToggles(settingsController: SettingsScope.of(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 简单行动 Chip
// ignore: unused_element
class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        borderRadius: BorderRadius.circular(20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// 动态岛组件（带状态动画与宽度自适应）
class _DynamicIsland extends StatefulWidget {
  final ExpressionController faceController;
  final Stream<String> statusStream;
  const _DynamicIsland({
    required this.faceController,
    required this.statusStream,
  });
  @override
  State<_DynamicIsland> createState() => _DynamicIslandState();
}

class _DynamicIslandState extends State<_DynamicIsland> {
  String _status = '待机';
  StreamSubscription<String>? _sub;
  @override
  void initState() {
    super.initState();
    _sub = widget.statusStream.listen((v) {
      setState(() {
        _status = v.isEmpty ? '待机' : v;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const minW = 160.0;
    final text = _status.length > 24 ? '${_status.substring(0, 24)}…' : _status;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      constraints: const BoxConstraints(minWidth: minW, maxWidth: 340),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(34)),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        borderRadius: BorderRadius.circular(28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExpressiveFace(controller: widget.faceController, size: 62),
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Text(
                text,
                key: ValueKey(text),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 插件切换组件
class _PluginToggles extends StatelessWidget {
  final SettingsController settingsController;
  const _PluginToggles({required this.settingsController});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: globalPluginManager,
      builder: (context, _) {
        final plugins = globalPluginManager.allPlugins;
        if (plugins.isEmpty) {
          return const SizedBox(
            height: 100,
            child: Center(
              child: Text('暂无插件', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          );
        }
        
        return SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: plugins.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final p = plugins[i];
              return GestureDetector(
                onTap: () {
                   final newState = !p.isEnabled;
                   globalPluginManager.togglePlugin(p.id, newState);
                   if (newState) {
                       p.onSync(context);
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(
                           content: Text('已启用并同步 ${p.name}'),
                           duration: const Duration(milliseconds: 1000),
                         ),
                       );
                   }
                },
                child: Glass(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  borderRadius: BorderRadius.circular(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        p.icon,
                        size: 24,
                        color: p.isEnabled ? Theme.of(context).colorScheme.primary : Colors.grey,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        p.name,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: p.isEnabled ? FontWeight.bold : FontWeight.normal,
                          color: p.isEnabled ? null : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        p.isEnabled ? 'ON' : 'OFF',
                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _VoiceInputButton extends StatefulWidget {
  final Function(String path) onRecorded;
  const _VoiceInputButton({required this.onRecorded});

  @override
  State<_VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<_VoiceInputButton> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path =
            '${tempDir.path}/voice_input_${DateTime.now().millisecondsSinceEpoch}.wav';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.wav),
          path: path,
        );
        setState(() => _isRecording = true);
      }
    } catch (e) {
      logger.error('Recording Error: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    try {
      final path = await _recorder.stop();
      setState(() => _isRecording = false);
      if (path != null) {
        widget.onRecorded(path);
      }
    } catch (e) {
      logger.error('Stop Recording Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => _startRecording(),
      onLongPressEnd: (_) => _stopRecording(),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isRecording
              ? Colors.red
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _isRecording ? Icons.mic : Icons.mic_none,
          color: _isRecording
              ? Colors.white
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
