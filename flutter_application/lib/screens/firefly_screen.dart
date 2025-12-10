import 'package:flutter/services.dart'; // Add this import for LogicalKeyboardKey
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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

class FireflyScreen extends StatefulWidget {
  const FireflyScreen({Key? key}) : super(key: key);

  @override
  State<FireflyScreen> createState() => _FireflyScreenState();
}

class _FireflyScreenState extends State<FireflyScreen> {
  final BrainService _brain = BrainService();
  final LLMService _llmService = LLMService();
  final ChatHistoryService _chatHistory = ChatHistoryService();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  Uint8List? _pendingImageBytes;
  late final ExpressionController _faceController;
  bool _historyOpen = false; // 左侧历史与功能面板

  // Multi-session state
  List<ChatSession> _sessions = [];
  String? _currentSessionId;
  List<Map<String, dynamic>> _messages =
      []; // {role: user/assistant, content: text, created_at: DateTime}
  bool _isLoading = false;
  Completer<void>? _interruptCompleter;

  StreamSubscription? _historySubscription;
  StreamSubscription? _faceSubscription;

  // Floating window service
  FloatingWindowService? _floatingWindowService;
  bool _floatingWindowEnabled = false;
  bool _miniExpanded = false;
  // Mini-window control state
  Timer? _floatingControlsHideTimer;
  bool _floatingControlsVisible = false;
  final Live2DController _live2dController = Live2DController();

  @override
  void initState() {
    super.initState();
    _faceController = ExpressionController();
    // Bind expression stream to UI controller (best-effort)
    _faceSubscription = _brain.expressionAgent.bind(_faceController);
    _loadSessions();
    _historySubscription = _chatHistory.updateStream.listen((_) {
      if (mounted) _loadSessions();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkFirstRun();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check floating window setting and update accordingly
    final settings = SettingsScope.of(context).settings;
    _updateFloatingWindow(settings.enableFloatingWindow, settings.pythonBackendUrl);
    
    // Unify Broadcast Logic: Enable if ANY Live2D mode is active
    // This ensures Sidebar and Mini Window also receive WebSocket events
    final anyLive2D = settings.enableFloatingWindow || 
                      settings.showLive2D || 
                      settings.showLive2DMiniWindow;
    _brain.expressionAgent.setBroadcastEnabled(anyLive2D);
  }

  Future<void> _updateFloatingWindow(bool enabled, String backendUrl) async {
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

  void _interruptGeneration() {
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
    _floatingWindowService?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _faceController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final sessions = await _chatHistory.getSessions();
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

    // If empty, add greeting (but don't save it to DB yet to keep it clean)
    if (_messages.isEmpty) {
      _checkApiKey();
    }

    // Update Brain context
    _brain.setContext(
      _messages
          .map(
            (m) => {
              'role': m['role'].toString(),
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

  Future<void> _checkApiKey() async {
    final key = await _llmService.getApiKey();
    final l10n = AppLocalizations.of(context)!;
    if (key == null || key.isEmpty) {
      if (mounted) {
        setState(() {
          _messages.add(<String, dynamic>{
            'role': 'assistant',
            'content': l10n.greetingMissingKey,
          });
        });
      }
    } else {
      // Add initial greeting
      setState(() {
        _messages.add(<String, dynamic>{
          'role': 'assistant',
          'content': l10n.greetingNormal,
        });
      });
    }
  }

  AiProviderConfig? _resolveAudioProvider(AiProviderCategory category) {
    final providers = SettingsScope.of(context).providers;

    // 1. Try to find explicit provider
    final explicit = providers.firstWhere(
      (p) => p.category == category && p.enabled,
      orElse: () => AiProviderConfig(id: '', name: '', kind: AiProvider.local),
    );
    if (explicit.id.isNotEmpty) return explicit;

    // 2. Fallback: Check if Backend is enabled
    final settings = SettingsScope.of(context).settings;
    if (settings.enablePythonBackend) {
      // Try to find an LLM provider to borrow the API Key (e.g. SiliconFlow)
      final llmProvider = providers.firstWhere(
        (p) =>
            p.category == AiProviderCategory.llm &&
            p.enabled &&
            (p.baseUrl.contains('siliconflow') ||
                p.name.toLowerCase().contains('silicon')),
        orElse: () =>
            AiProviderConfig(id: '', name: '', kind: AiProvider.local),
      );

      String apiKey = llmProvider.id.isNotEmpty ? llmProvider.apiKey : '';

      return AiProviderConfig(
        id: 'backend_proxy_${category.name}',
        name: 'Backend Proxy (${category.name})',
        kind: AiProvider.openai,
        baseUrl: 'http://localhost:8000/api',
        apiKey: apiKey,
        model: category == AiProviderCategory.stt
            ? 'FunAudioLLM/SenseVoiceSmall'
            : 'FunAudioLLM/CosyVoice2-0.5B',
        category: category,
        enabled: true,
      );
    }

    return null;
  }

  Future<void> _handleVoiceInput(String path) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final sttProvider = _resolveAudioProvider(AiProviderCategory.stt);

      if (sttProvider == null) {
        throw Exception('未配置 STT 服务 (No STT Provider)');
      }

      final text = await _brain.transcribe(path, sttProvider);
      if (text.isNotEmpty) {
        _controller.text = text;
        _sendMessage();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('语音输入失败: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImageBytes == null) return;
    if (_currentSessionId == null) await _createNewSession();

    setState(() {
      // Explicitly cast to Map<String, dynamic> to match _messages definition
      _messages.add(<String, dynamic>{
        'role': 'user',
        'content': _pendingImageBytes != null
            ? (text.isNotEmpty ? '$text\n[已附加图片]' : '[已附加图片]')
            : text,
        'created_at': DateTime.now(),
      });
      _isLoading = true;
      _interruptCompleter = Completer<void>(); // Initialize completer
      _controller.clear();
    });
    _scrollToBottom();

    // Save user message
    await _chatHistory.addMessage(
      _currentSessionId!,
      'user',
      text.isEmpty ? '[图片]' : text,
    );

    // Update session title if it's the first message
    if (_messages.length <= 2) {
      // Simple heuristic: use first 10 chars
      final title = text.length > 15 ? '${text.substring(0, 15)}...' : text;
      await _chatHistory.updateSessionTitle(_currentSessionId!, title);
      _loadSessions(); // Refresh list
    }

    try {
      final settings = SettingsScope.of(context).settings;
      String response;

      // Define the generation task
      Future<String> generationTask() async {
        if (_pendingImageBytes != null) {
          // Trigger background learning (Autonomous Meme Learning)
          final bytesToLearn = Uint8List.fromList(_pendingImageBytes!);
          unawaited(_brain.analyzeAndLearnMeme(bytesToLearn));

          // Try direct vision with active model
          try {
            final s = SettingsScope.of(context).settings;
            // Vision selection strategy: use main if capable; else use selected vision provider; else fallback
            final useMainIfCapable = s.useMainVisionIfCapable;
            final mainVisionCapable = await _llmService
                .isActiveModelVisionCapable();
            final selectedVisionProviderId =
                s.activeVisionProviderId; // null means follow main

            if (useMainIfCapable && mainVisionCapable) {
              final defaultHint =
                  '${s.visionPromptTemplate}\n长度建议约${s.visionPreferredLength}字，最多${s.visionMaxLength}字。';
              return await _llmService.chatWithImage(
                messages: _messages
                    .map(
                      (m) => {
                        'role': m['role'].toString(),
                        'content': m['content'].toString(),
                      },
                    )
                    .toList(),
                imageBytes: _pendingImageBytes!,
                prompt: text.isNotEmpty ? text : defaultHint,
                usageType: 'main',
              );
            } else if (selectedVisionProviderId != null &&
                selectedVisionProviderId.isNotEmpty) {
              final defaultHint =
                  '${s.visionPromptTemplate}\n长度建议约${s.visionPreferredLength}字，最多${s.visionMaxLength}字。';
              return await _llmService.chatWithImage(
                messages: _messages
                    .map(
                      (m) => {
                        'role': m['role'].toString(),
                        'content': m['content'].toString(),
                      },
                    )
                    .toList(),
                imageBytes: _pendingImageBytes!,
                prompt: text.isNotEmpty ? text : defaultHint,
                usageType: 'main',
                providerIdOverride: selectedVisionProviderId,
              );
            } else {
              // Fallback: insert helper guidance to switch to a vision-capable model
              final helper =
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
            );
          }
        } else {
          final provider = SettingsScope.of(
            context,
          ).selectProviderForNextCall(category: AiProviderCategory.llm);

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
          );

          if (provider != null) {
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

      response = result as String;

      if (mounted) {
        final cleanedResponse = _stripExpressionBlocks(response);

        if (settings.chatMode == ChatModeOption.standard) {
          setState(() {
            _isLoading = false;
            _pendingImageBytes = null;
            _messages.add(<String, dynamic>{
              'role': 'assistant',
              'content': cleanedResponse,
              'created_at': DateTime.now(),
            });
          });
          _scrollToBottom();
          await _chatHistory.addMessage(
            _currentSessionId!,
            'assistant',
            cleanedResponse,
          );

          // Trigger Motion Agent
          if (settings.enableLive2D) {
            _brain.expressionAgent.requestMotion(text, cleanedResponse);
          }

          // Trigger TTS
          if (settings.enableTts) {
            final ttsProvider = _resolveAudioProvider(AiProviderCategory.tts);
            if (ttsProvider != null) {
              _brain.speak(cleanedResponse, ttsProvider);
            }
          }
        } else {
          final parts = cleanedResponse.split('[SPLIT]');

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

          // Trigger TTS
          if (settings.enableTts) {
            final ttsProvider = _resolveAudioProvider(AiProviderCategory.tts);
            if (ttsProvider != null) {
              _brain.speak(cleanedResponse, ttsProvider);
            }
          }
        }
      }
    } catch (e) {
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

  void _editMessage(int index) async {
    if (_currentSessionId == null) return;
    final msg = _messages[index];
    if (msg['role'] != 'user') return;

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
    final settingsController = SettingsScope.of(context);
    final settings = settingsController.settings;
    final quickActions = settings.quickActions;
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
        // Left Sidebar (History)
        if (_historyOpen)
          SizedBox(width: 300, child: _buildHistoryPanel(context, l10n)),

        // Main Chat Area
        Expanded(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildHeader(context, settings, titleFontFamily),
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
              // Top-left toggle button for history
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
              // Dynamic Island (Expression) - 表情系统与 Live2D 互斥
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
              // Mini Live2D overlay (left-side arrow + expandable controls)
              if (settings.enableLive2D && settings.showLive2DMiniWindow)
                _buildLive2DMiniWindowOverlay(context, settings),
            ],
          ),
        ),

        // Right Sidebar (Live2D)
        if (settings.enableLive2D &&
            settings.showLive2D &&
            !settings.enableFloatingWindow)
          Container(
            width: 400,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).dividerColor.withOpacity(0.1),
                ),
              ),
            ),
            child: CharacterDisplay(
              backendUrl: settings.pythonBackendUrl,
              expressionAgent: _brain.expressionAgent,
              controller: _live2dController,
              floatingUi: true,
              showControls: true, // 明确启用侧边栏的悬浮工具栏
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

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
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
      top: 12,
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
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 8, offset: const Offset(0,4)),
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
                          Future<void> _evalJs(String js) async {
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
                                                    _evalJs("if(window.live2dManager) { window.live2dManager.mouseTrackingEnabled = $val; }");
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
                    color: Colors.black.withOpacity(0.3),
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
    return Container(
      height: 80,
      alignment: Alignment.center,
      child: (!settings.showExpressionFace)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48.0,
                ), // Avoid overlap with menu button
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      settings.assistantName,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        fontFamily: titleFontFamily,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Astra-Me',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        color: Theme.of(context).colorScheme.outline,
                        fontFamily: titleFontFamily,
                      ),
                    ),
                    Text(
                      'Project N-T-AI',
                      style: TextStyle(
                        fontSize: 8,
                        letterSpacing: 3.0,
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withOpacity(0.5),
                        fontFamily: titleFontFamily,
                      ),
                    ),
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
        final isUser = msg['role'] == 'user';
        final time = msg['created_at'] as DateTime?;
        final timeStr = time != null
            ? DateFormat('yyyy:MM:dd:HH:mm:ss').format(time)
            : '';

        return RepaintBoundary(
          child: MessageBubble(
            message: ChatMessage(
              id: index.toString(),
              text: msg['content'],
              isMine: isUser,
              time: timeStr,
            ),
          ),
        );
      },
    );
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
                  return Center(
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
                    ).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
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
              ...quickActions.map((id) {
                IconData icon;
                String tooltip;
                VoidCallback onTap;
                switch (id) {
                  case 'attach_image':
                    icon = Icons.image_outlined;
                    tooltip = l10n.quickActionAttachImage;
                    onTap = _attachImage;
                    break;
                  case 'compress':
                    icon = Icons.cleaning_services_outlined;
                    tooltip = l10n.quickActionCompress;
                    onTap = () async {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.msgCompressing)),
                      );
                      await _brain.compressContext();
                    };
                    break;
                  case 'new_chat':
                    icon = Icons.add_comment_outlined;
                    tooltip = l10n.quickActionNewChat;
                    onTap = _createNewSession;
                    break;
                  case 'memory':
                    icon = Icons.memory;
                    tooltip = l10n.quickActionMemory;
                    onTap = () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MemoryManagerScreen(
                            heroTag: 'memory_fab_sidebar',
                          ),
                        ),
                      );
                    };
                    break;
                  case 'expression_toggle':
                    icon = settings.showExpressionFace
                        ? Icons.emoji_emotions
                        : Icons.emoji_emotions_outlined;
                    tooltip = l10n.quickActionExpression;
                    onTap = () {
                      settingsController.setShowExpressionFace(
                        !settings.showExpressionFace,
                      );
                    };
                    break;
                  default:
                    icon = Icons.extension;
                    tooltip = id;
                    onTap = () {};
                    break;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: IconButton(
                    icon: Icon(icon),
                    tooltip: tooltip,
                    onPressed: onTap,
                  ),
                );
              }).toList(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: IconButton(
                  icon: Icon(
                    settings.enableTts
                        ? Icons.record_voice_over
                        : Icons.voice_over_off,
                  ),
                  tooltip: settings.enableTts ? 'TTS On' : 'TTS Off',
                  onPressed: () {
                    settingsController.setEnableTts(!settings.enableTts);
                  },
                  color: settings.enableTts
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  _isLoading ? Icons.stop_circle_outlined : Icons.send,
                ),
                onPressed: _isLoading ? _interruptGeneration : _sendMessage,
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
                  Text(
                    l10n.historyTitle,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
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
          // Bottom area of history panel (Model switcher etc)
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.modelTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _ModelSwitcher(settingsController: SettingsScope.of(context)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 简单行动 Chip
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
    final minW = 160.0;
    final text = _status.length > 24 ? _status.substring(0, 24) + '…' : _status;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      constraints: BoxConstraints(minWidth: minW, maxWidth: 340),
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

// 模型切换组件
class _ModelSwitcher extends StatelessWidget {
  final SettingsController settingsController;
  const _ModelSwitcher({required this.settingsController});
  @override
  Widget build(BuildContext context) {
    final providers = settingsController.providers;
    final activeId = settingsController.activeProviderId;
    final visionId = settingsController.settings.activeVisionProviderId;
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: providers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final p = providers[i];
          final isActive = p.id == activeId;
          final isVision = visionId != null && p.id == visionId;
          return GestureDetector(
            onTap: () => settingsController.setActiveProvider(p.id),
            onLongPress: () => settingsController.setActiveVisionProvider(
              isVision ? null : p.id,
            ),
            child: Glass(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              borderRadius: BorderRadius.circular(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isVision)
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Icon(Icons.visibility, size: 14),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    p.model.isNotEmpty ? p.model : '未配置模型',
                    style: const TextStyle(fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.baseUrl.split('//').last.split('/').first,
                    style: TextStyle(
                      fontSize: 9,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isVision ? '长按取消视觉中枢' : '长按设为视觉',
                    style: const TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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
      print('Recording Error: $e');
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
      print('Stop Recording Error: $e');
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
