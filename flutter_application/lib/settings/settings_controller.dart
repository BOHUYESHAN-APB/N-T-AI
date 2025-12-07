import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings.dart';
import '../services/ai_client.dart';

class SettingsController extends ChangeNotifier {
  static const _kThemeMode = 'settings.themeMode';
  static const _kLocale = 'settings.locale';
  static const _kDensity = 'settings.density';
  static const _kTextScale = 'settings.textScale';
  static const _kChatBg = 'settings.chatBg';
  static const _kAiProvider = 'settings.ai.provider';
  static const _kAiBaseUrl = 'settings.ai.baseUrl';
  static const _kAiApiKey = 'settings.ai.apiKey';
  static const _kAiModel = 'settings.ai.model';
  static const _kAiProviders = 'settings.ai.providers';
  static const _kAiActiveId = 'settings.ai.activeId';
  static const _kAiActiveVisionId = 'settings.ai.activeVisionId';
  static const _kUseMainVisionIfCapable = 'settings.vision.useMainIfCapable';
  static const _kVisionFallbackAgent = 'settings.vision.fallbackAgent';
  static const _kAiRotationEnabled = 'settings.ai.rotationEnabled';
  static const _kAgentEnabled = 'settings.agent.enabled';
  static const _kAgentEnableBrowser = 'settings.agent.enableBrowser';
  static const _kAgentEnableSearchRetry = 'settings.agent.enableSearchRetry';
  static const _kEnableNoteAccess = 'settings.agent.enableNoteAccess';
  static const _kAgentShowThoughts = 'settings.agent.showThoughts';
  static const _kAgentMcpServers = 'settings.agent.mcpServers';
  static const _kEnableExpressionAgent = 'settings.agent.expression.enabled';
  static const _kShowExpressionFace = 'settings.ui.showExpressionFace';
  static const _kEnableLive2D = 'settings.ui.enableLive2D';
  static const _kShowLive2D = 'settings.ui.showLive2D';
  static const _kUserNickname = 'settings.user.nickname';
  static const _kLearningProbability = 'settings.user.learningProbability';
  static const _kPalette = 'settings.ui.palette';
  // Vision settings
  static const _kVisionPrompt = 'settings.vision.promptTemplate';
  static const _kVisionPrefLen = 'settings.vision.preferredLength';
  static const _kVisionMaxLen = 'settings.vision.maxLength';
  static const _kExpressionProviderId = 'settings.expression.activeProviderId';
  static const _kSearchProviderId = 'settings.agent.searchProviderId';
  static const _kQuickActions = 'settings.ui.quickActions';
  static const _kAgents = 'settings.agents';
  static const _kEnablePythonBackend = 'settings.backend.enabled';
  static const _kPythonBackendUrl = 'settings.backend.url';
  static const _kEnableDeepResearch = 'settings.backend.deepResearch';
  static const _kSearchRegion = 'settings.agent.searchRegion';
  static const _kSystemPrompt = 'settings.ai.systemPrompt';
  static const _kAssistantName = 'settings.ai.assistantName';
  static const _kIsFirstRun = 'settings.app.isFirstRun';
  static const _kEnableTts = 'settings.audio.enableTts';
  static const _kEnableStt = 'settings.audio.enableStt';
  // Legacy font mode key (for migration only)
  static const _kFontMode = 'settings.ui.fontMode';
  // New font settings keys
  static const _kBaseFontMode = 'settings.ui.baseFontMode';
  static const _kDecoFamily = 'settings.ui.decoFamily';
  static const _kDecoUseTitles = 'settings.ui.decoUseTitles';
  static const _kDecoUseBubbles = 'settings.ui.decoUseBubbles';
  static const _kUiMode = 'settings.ui.uiMode';
  static const _kChatMode = 'settings.ui.chatMode';

  late SharedPreferences _prefs;
  AppSettings _settings = const AppSettings();
  int _rotationIndex = 0; // 内存轮换游标

  AppSettings get settings => _settings;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final themeIdx = _prefs.getInt(_kThemeMode);
    final localeIdx = _prefs.getInt(_kLocale);
    final densityIdx = _prefs.getInt(_kDensity);
    final textScale = _prefs.getDouble(_kTextScale) ?? 1.0;
    final chatBgIdx = _prefs.getInt(_kChatBg);
  final paletteIdx = _prefs.getInt(_kPalette);
  final aiProviderIdx = _prefs.getInt(_kAiProvider);
    // New font settings
    final baseFontIdx = _prefs.getInt(_kBaseFontMode);
    final decoFamilyIdx = _prefs.getInt(_kDecoFamily);
    final decoUseTitles = _prefs.getBool(_kDecoUseTitles);
    final decoUseBubbles = _prefs.getBool(_kDecoUseBubbles);
    // Legacy font mode (to migrate)
    final legacyFontModeIdx = _prefs.getInt(_kFontMode);
    // UI mode
    final uiModeIdx = _prefs.getInt(_kUiMode);
    final chatModeIdx = _prefs.getInt(_kChatMode);
    final aiBaseUrl = _prefs.getString(_kAiBaseUrl) ?? '';
    final aiApiKey = _prefs.getString(_kAiApiKey) ?? '';
    final aiModel = _prefs.getString(_kAiModel) ?? '';
    final visionPrompt = _prefs.getString(_kVisionPrompt) ?? '请用中文用一段话描述这张图片的内容。若有文字请概括其要点。以主题和直观感受为主，避免分点与多段，仅输出纯文本。';
    final visionPrefLen = _prefs.getInt(_kVisionPrefLen) ?? 120;
    final visionMaxLen = _prefs.getInt(_kVisionMaxLen) ?? 500;
    final quickActionsRaw = _prefs.getString(_kQuickActions);
    final enableTts = _prefs.getBool(_kEnableTts) ?? false;
    final enableStt = _prefs.getBool(_kEnableStt) ?? false;

    // load legacy single-AI settings then attempt to load providers list
    final providersRaw = _prefs.getString(_kAiProviders);
    final activeId = _prefs.getString(_kAiActiveId);
    final rotationEnabled = _prefs.getBool(_kAiRotationEnabled) ?? false;
    final activeVisionId = _prefs.getString(_kAiActiveVisionId);
    final useMainVisionIfCapable = _prefs.getBool(_kUseMainVisionIfCapable) ?? true;
    final visionFallbackAgent = _prefs.getBool(_kVisionFallbackAgent) ?? true;
    final agentEnabled = _prefs.getBool(_kAgentEnabled) ?? false;
    final enableExpressionAgent = _prefs.getBool(_kEnableExpressionAgent) ?? false;
    final showExpressionFace = _prefs.getBool(_kShowExpressionFace) ?? true;
    final enableLive2D = _prefs.getBool(_kEnableLive2D) ?? true;
    final showLive2D = _prefs.getBool(_kShowLive2D) ?? true;
    final activeExpressionProviderId = _prefs.getString(_kExpressionProviderId);
    final activeSearchProviderId = _prefs.getString(_kSearchProviderId);
    final enableBrowser = _prefs.getBool(_kAgentEnableBrowser) ?? false;
    final enableSearchRetry = _prefs.getBool(_kAgentEnableSearchRetry) ?? true;
    final enableNoteAccess = _prefs.getBool(_kEnableNoteAccess) ?? false;
    final showAgentThoughts = _prefs.getBool(_kAgentShowThoughts) ?? false;
    final userNickname = _prefs.getString(_kUserNickname) ?? '';
    final learningProbability = _prefs.getDouble(_kLearningProbability) ?? 1.0;
    List<String> quickActions = ['attach_image','compress','new_chat'];
    if (quickActionsRaw != null && quickActionsRaw.isNotEmpty) {
      try {
        final List data = jsonDecode(quickActionsRaw) as List;
        quickActions = data.map((e) => e.toString()).toList();
      } catch (_) {}
    }
    
    final mcpServersRaw = _prefs.getString(_kAgentMcpServers);
    final enablePythonBackend = _prefs.getBool(_kEnablePythonBackend) ?? false;
    final pythonBackendUrl = _prefs.getString(_kPythonBackendUrl) ?? 'http://localhost:8000';
    final enableDeepResearch = _prefs.getBool(_kEnableDeepResearch) ?? false;
    final searchRegionIdx = _prefs.getInt(_kSearchRegion);
    final systemPrompt = _prefs.getString(_kSystemPrompt) ?? '';
    final assistantName = _prefs.getString(_kAssistantName) ?? 'Firefly';
    final isFirstRun = _prefs.getBool(_kIsFirstRun) ?? true;

    List<McpServerConfig> mcpServers = [];
    if (mcpServersRaw != null && mcpServersRaw.isNotEmpty) {
      try {
        final List data = jsonDecode(mcpServersRaw) as List;
        mcpServers = data.map((e) => McpServerConfig.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        mcpServers = [];
      }
    }

    List<AiProviderConfig> providers = [];
    if (providersRaw != null && providersRaw.isNotEmpty) {
      try {
        final List data = jsonDecode(providersRaw) as List;
        providers = data.map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        providers = [];
      }
    }

    // If no providers persisted, migrate legacy single ai settings into a default provider
    if (providers.isEmpty) {
      // Seed only minimal presets to avoid clutter (User Feedback)
      providers = [
        AiProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek',
          kind: AiProvider.custom,
          baseUrl: 'https://api.deepseek.com/v1',
          model: 'deepseek-chat',
          isRoot: true,
          enabled: true,
          category: AiProviderCategory.llm,
          capabilities: ['text'],
        ),
        AiProviderConfig(
          id: 'openai',
          name: 'OpenAI',
          kind: AiProvider.openai,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          isRoot: true,
          enabled: true,
          category: AiProviderCategory.llm,
          capabilities: ['text'],
        ),
        AiProviderConfig(
          id: 'siliconflow_llm',
          name: 'SiliconFlow (LLM)',
          kind: AiProvider.custom,
          baseUrl: 'https://api.siliconflow.cn/v1',
          model: 'deepseek-ai/DeepSeek-V3',
          isRoot: true,
          enabled: true,
          category: AiProviderCategory.llm,
          capabilities: ['text'],
        ),
        AiProviderConfig(
          id: 'siliconflow_stt',
          name: 'SiliconFlow (STT)',
          kind: AiProvider.custom,
          baseUrl: 'https://api.siliconflow.cn/v1',
          model: 'FunAudioLLM/SenseVoiceSmall',
          isRoot: true,
          enabled: true,
          category: AiProviderCategory.stt,
          capabilities: ['audio'],
        ),
        AiProviderConfig(
          id: 'siliconflow_tts',
          name: 'SiliconFlow (TTS)',
          kind: AiProvider.custom,
          baseUrl: 'https://api.siliconflow.cn/v1',
          model: 'fishaudio/fish-speech-1.5',
          isRoot: true,
          enabled: true,
          category: AiProviderCategory.tts,
          capabilities: ['audio'],
        ),
        AiProviderConfig(
          id: 'siliconflow_image',
          name: 'SiliconFlow (Image)',
          kind: AiProvider.custom,
          baseUrl: 'https://api.siliconflow.cn/v1',
          model: 'black-forest-labs/FLUX.1-dev',
          isRoot: true,
          enabled: true,
          category: AiProviderCategory.image,
          capabilities: ['image'],
        ),
      ];

      // If legacy single settings exist, add a migrated entry and set active to it
      String defaultActive = 'deepseek'; // Default to DeepSeek
      final hasLegacy = (aiBaseUrl.isNotEmpty || aiApiKey.isNotEmpty || aiModel.isNotEmpty || aiProviderIdx != null);
      if (hasLegacy) {
        final migrated = AiProviderConfig(
          id: 'migrated',
          name: '迁移的配置',
          kind: AiProvider.values[safeIndex(aiProviderIdx, AiProvider.values.length, fallback: AiProvider.local.index)],
          baseUrl: aiBaseUrl,
          apiKey: aiApiKey,
          model: aiModel,
          isRoot: !(aiBaseUrl.contains('/chat/completions')), // heuristic
          enabled: true,
        );
        providers.insert(0, migrated);
        defaultActive = 'migrated';
      }
      await _prefs.setString(_kAiProviders, jsonEncode(providers.map((p) => p.toJson()).toList()));
      await _prefs.setString(_kAiActiveId, activeId ?? defaultActive);
    } else {
      // Fixup: Ensure known providers have default models if empty (migration for existing users)
      bool needsUpdate = false;
      for (var i = 0; i < providers.length; i++) {
        final p = providers[i];
        if (p.model.isEmpty) {
          String? newModel;
          if (p.id == 'deepseek') newModel = 'deepseek-chat';
          else if (p.id == 'openai') newModel = 'gpt-4o-mini';
          else if (p.id == 'glm_cn' || p.id == 'glm_global') newModel = 'glm-4';
          else if (p.id == 'siliconflow') newModel = 'deepseek-ai/DeepSeek-V2-Chat';
          else if (p.id == 'kimi') newModel = 'moonshot-v1-8k';
          
          if (newModel != null) {
            providers[i] = p.copyWith(model: newModel);
            needsUpdate = true;
          }
        }
      }
      if (needsUpdate) {
         await _prefs.setString(_kAiProviders, jsonEncode(providers.map((e) => e.toJson()).toList()));
      }
    }

    // Load agents
    final agentsRaw = _prefs.getString(_kAgents);
    List<AgentConfig> agents = [];
    if (agentsRaw != null && agentsRaw.isNotEmpty) {
      try {
        final List data = jsonDecode(agentsRaw) as List;
        agents = data.map((e) => AgentConfig.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {
        agents = [];
      }
    }

    // Derive font settings with migration from legacy FontModeOption if needed
    BaseFontModeOption baseFontMode = BaseFontModeOption.values[
      safeIndex(baseFontIdx, BaseFontModeOption.values.length, fallback: BaseFontModeOption.miSansPreferred.index)
    ];
    DecorativeFontFamily decoFamily = DecorativeFontFamily.values[
      safeIndex(decoFamilyIdx, DecorativeFontFamily.values.length, fallback: DecorativeFontFamily.none.index)
    ];
    bool useTitles = decoUseTitles ?? false;
    bool useBubbles = decoUseBubbles ?? false;

    // If only legacy exists, migrate once to the new fields
    final hasNewFontPrefs = baseFontIdx != null || decoFamilyIdx != null || decoUseTitles != null || decoUseBubbles != null;
    if (!hasNewFontPrefs && legacyFontModeIdx != null) {
      // Legacy mapping:
      // 0: system, 1: miSansPreferred, 2: fzgHeadings, 3: nfdcsHeadings
      switch (legacyFontModeIdx) {
        case 0:
          baseFontMode = BaseFontModeOption.system;
          decoFamily = DecorativeFontFamily.none;
          useTitles = false;
          useBubbles = false;
          break;
        case 2:
          baseFontMode = BaseFontModeOption.miSansPreferred;
          decoFamily = DecorativeFontFamily.fzg;
          useTitles = true;
          useBubbles = true;
          break;
        case 3:
          baseFontMode = BaseFontModeOption.miSansPreferred;
          decoFamily = DecorativeFontFamily.nfdcs;
          useTitles = true;
          useBubbles = true;
          break;
        case 1:
        default:
          baseFontMode = BaseFontModeOption.miSansPreferred;
          decoFamily = DecorativeFontFamily.none;
          useTitles = false;
          useBubbles = false;
      }
      // Persist migrated values
      await _prefs.setInt(_kBaseFontMode, baseFontMode.index);
      await _prefs.setInt(_kDecoFamily, decoFamily.index);
      await _prefs.setBool(_kDecoUseTitles, useTitles);
      await _prefs.setBool(_kDecoUseBubbles, useBubbles);
    }
    _settings = AppSettings(
      themeMode: ThemeModeOption.values[safeIndex(themeIdx, ThemeModeOption.values.length, fallback: ThemeModeOption.system.index)],
      locale: LocaleOption.values[safeIndex(localeIdx, LocaleOption.values.length, fallback: LocaleOption.system.index)],
      density: DensityOption.values[safeIndex(densityIdx, DensityOption.values.length, fallback: DensityOption.normal.index)],
      textScale: textScale.clamp(0.9, 1.4),
      chatBg: ChatBgOption.values[safeIndex(chatBgIdx, ChatBgOption.values.length, fallback: ChatBgOption.none.index)],
      palette: PaletteOption.values[safeIndex(paletteIdx, PaletteOption.values.length, fallback: PaletteOption.neutral.index)],
      uiMode: UIModeOption.values[safeIndex(uiModeIdx, UIModeOption.values.length, fallback: UIModeOption.auto.index)],
      chatMode: ChatModeOption.values[safeIndex(chatModeIdx, ChatModeOption.values.length, fallback: ChatModeOption.persona.index)],
      baseFontMode: baseFontMode,
      decoFamily: decoFamily,
      decoUseTitles: useTitles,
      decoUseBubbles: useBubbles,
      ai: AiSettings(
        provider: AiProvider.values[safeIndex(aiProviderIdx, AiProvider.values.length, fallback: AiProvider.local.index)],
        baseUrl: aiBaseUrl,
        apiKey: aiApiKey,
        model: aiModel,
      ),
      providers: providers,
      activeProviderId: activeId ?? providers.first.id,
      activeVisionProviderId: activeVisionId,
      rotationEnabled: rotationEnabled,
      agentEnabled: agentEnabled,
      enableExpressionAgent: enableExpressionAgent,
      showExpressionFace: showExpressionFace,
      enableLive2D: enableLive2D,
      showLive2D: showLive2D,
      enableBrowser: enableBrowser,
      enableSearchRetry: enableSearchRetry,
      enableNoteAccess: enableNoteAccess,
      showAgentThoughts: showAgentThoughts,
      mcpServers: mcpServers,
      agents: agents,
      enablePythonBackend: enablePythonBackend,
      pythonBackendUrl: pythonBackendUrl,
      enableDeepResearch: enableDeepResearch,
      searchRegion: SearchRegionOption.values[safeIndex(searchRegionIdx, SearchRegionOption.values.length, fallback: SearchRegionOption.auto.index)],
      userNickname: userNickname,
      learningProbability: learningProbability,
      useMainVisionIfCapable: useMainVisionIfCapable,
      visionPreferredLength: visionPrefLen,
      visionMaxLength: visionMaxLen,
      activeExpressionProviderId: activeExpressionProviderId,
      activeSearchProviderId: activeSearchProviderId,
      quickActions: quickActions,
      systemPrompt: systemPrompt,
      assistantName: assistantName,
      isFirstRun: isFirstRun,
      enableTts: enableTts,
      enableStt: enableStt,
    );
    notifyListeners();
  }

  Future<void> setEnableExpressionAgent(bool v) async {
    _settings = _settings.copyWith(enableExpressionAgent: v);
    await _prefs.setBool(_kEnableExpressionAgent, v);
    notifyListeners();
  }

  Future<void> setShowExpressionFace(bool v) async {
    _settings = _settings.copyWith(showExpressionFace: v);
    await _prefs.setBool(_kShowExpressionFace, v);
    notifyListeners();
  }

  Future<void> setEnableLive2D(bool v) async {
    _settings = _settings.copyWith(enableLive2D: v);
    await _prefs.setBool(_kEnableLive2D, v);
    notifyListeners();
  }

  Future<void> setShowLive2D(bool v) async {
    _settings = _settings.copyWith(showLive2D: v);
    await _prefs.setBool(_kShowLive2D, v);
    notifyListeners();
  }

  Future<void> setEnableTts(bool v) async {
    _settings = _settings.copyWith(enableTts: v);
    await _prefs.setBool(_kEnableTts, v);
    notifyListeners();
  }

  Future<void> setEnableStt(bool v) async {
    _settings = _settings.copyWith(enableStt: v);
    await _prefs.setBool(_kEnableStt, v);
    notifyListeners();
  }

  Future<void> setActiveExpressionProvider(String? id) async {
    if (id == null) {
      await _prefs.remove(_kExpressionProviderId);
    } else {
      await _prefs.setString(_kExpressionProviderId, id);
    }
    _settings = _settings.copyWith(activeExpressionProviderId: id);
    notifyListeners();
  }

  Future<void> setUiMode(UIModeOption m) async {
    _settings = _settings.copyWith(uiMode: m);
    await _prefs.setInt(_kUiMode, m.index);
    notifyListeners();
  }

  Future<void> setChatMode(ChatModeOption m) async {
    _settings = _settings.copyWith(chatMode: m);
    await _prefs.setInt(_kChatMode, m.index);
    notifyListeners();
  }

  Future<void> setActiveSearchProvider(String? id) async {
    if (id == null) {
      await _prefs.remove(_kSearchProviderId);
    } else {
      await _prefs.setString(_kSearchProviderId, id);
    }
    _settings = _settings.copyWith(activeSearchProviderId: id);
    notifyListeners();
  }

  int safeIndex(int? i, int len, {required int fallback}) {
    if (i == null) return fallback;
    if (i < 0 || i >= len) return fallback;
    return i;
  }

  Future<void> setThemeMode(ThemeModeOption mode) async {
    _settings = _settings.copyWith(themeMode: mode);
    await _prefs.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  Future<void> setLocale(LocaleOption locale) async {
    _settings = _settings.copyWith(locale: locale);
    await _prefs.setInt(_kLocale, locale.index);
    notifyListeners();
  }

  Future<void> setDensity(DensityOption d) async {
    _settings = _settings.copyWith(density: d);
    await _prefs.setInt(_kDensity, d.index);
    notifyListeners();
  }

  Future<void> setTextScale(double s) async {
    _settings = _settings.copyWith(textScale: s);
    await _prefs.setDouble(_kTextScale, s);
    notifyListeners();
  }

  Future<void> setChatBg(ChatBgOption b) async {
    _settings = _settings.copyWith(chatBg: b);
    await _prefs.setInt(_kChatBg, b.index);
    notifyListeners();
  }

  Future<void> setPalette(PaletteOption p) async {
    _settings = _settings.copyWith(palette: p);
    await _prefs.setInt(_kPalette, p.index);
    notifyListeners();
  }

  Future<void> setBaseFontMode(BaseFontModeOption m) async {
    _settings = _settings.copyWith(baseFontMode: m);
    await _prefs.setInt(_kBaseFontMode, m.index);
    notifyListeners();
  }

  Future<void> setDecoFamily(DecorativeFontFamily f) async {
    _settings = _settings.copyWith(decoFamily: f);
    await _prefs.setInt(_kDecoFamily, f.index);
    notifyListeners();
  }

  Future<void> setDecoUseTitles(bool v) async {
    _settings = _settings.copyWith(decoUseTitles: v);
    await _prefs.setBool(_kDecoUseTitles, v);
    notifyListeners();
  }

  Future<void> setDecoUseBubbles(bool v) async {
    _settings = _settings.copyWith(decoUseBubbles: v);
    await _prefs.setBool(_kDecoUseBubbles, v);
    notifyListeners();
  }

  Future<void> setAiProvider(AiProvider p) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(provider: p));
    await _prefs.setInt(_kAiProvider, p.index);
    notifyListeners();
  }

  Future<void> setAiBaseUrl(String v) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(baseUrl: v));
    await _prefs.setString(_kAiBaseUrl, v);
    notifyListeners();
  }

  Future<void> setAiApiKey(String v) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(apiKey: v));
    await _prefs.setString(_kAiApiKey, v);
    notifyListeners();
  }

  Future<void> setAiModel(String v) async {
    _settings = _settings.copyWith(ai: _settings.ai.copyWith(model: v));
    await _prefs.setString(_kAiModel, v);
    notifyListeners();
  }

  Future<void> setAgentEnabled(bool v) async {
    _settings = _settings.copyWith(agentEnabled: v);
    await _prefs.setBool(_kAgentEnabled, v);
    notifyListeners();
  }
  Future<void> setEnableBrowser(bool v) async {
    _settings = _settings.copyWith(enableBrowser: v);
    await _prefs.setBool(_kAgentEnableBrowser, v);
    notifyListeners();
  }

  Future<void> setEnableSearchRetry(bool v) async {
    _settings = _settings.copyWith(enableSearchRetry: v);
    await _prefs.setBool(_kAgentEnableSearchRetry, v);
    notifyListeners();
  }

  Future<void> setEnableNoteAccess(bool v) async {
    _settings = _settings.copyWith(enableNoteAccess: v);
    await _prefs.setBool(_kEnableNoteAccess, v);
    notifyListeners();
  }

  Future<void> setAgentShowThoughts(bool enabled) async {
    await _prefs.setBool(_kAgentShowThoughts, enabled);
    _settings = _settings.copyWith(showAgentThoughts: enabled);
    notifyListeners();
  }

  Future<void> addMcpServer(McpServerConfig server) async {
    final list = List<McpServerConfig>.from(_settings.mcpServers)..add(server);
    _settings = _settings.copyWith(mcpServers: list);
    await _saveMcpServers();
    notifyListeners();
  }

  Future<void> updateMcpServer(McpServerConfig server) async {
    final list = List<McpServerConfig>.from(_settings.mcpServers);
    final index = list.indexWhere((e) => e.id == server.id);
    if (index != -1) {
      list[index] = server;
      _settings = _settings.copyWith(mcpServers: list);
      await _saveMcpServers();
      notifyListeners();
    }
  }

  Future<void> removeMcpServer(String id) async {
    final list = List<McpServerConfig>.from(_settings.mcpServers)..removeWhere((e) => e.id == id);
    _settings = _settings.copyWith(mcpServers: list);
    await _saveMcpServers();
    notifyListeners();
  }

  Future<void> _saveMcpServers() async {
    final jsonStr = jsonEncode(_settings.mcpServers.map((e) => e.toJson()).toList());
    await _prefs.setString(_kAgentMcpServers, jsonStr);
  }

  Future<void> _saveAgents() async {
    final jsonStr = jsonEncode(_settings.agents.map((e) => e.toJson()).toList());
    await _prefs.setString(_kAgents, jsonStr);
  }

  // Agent management
  Future<void> addOrUpdateAgent(AgentConfig cfg) async {
    final list = List<AgentConfig>.from(_settings.agents);
    final idx = list.indexWhere((p) => p.id == cfg.id);
    if (idx == -1) {
      list.add(cfg);
    } else {
      list[idx] = cfg;
    }
    _settings = _settings.copyWith(agents: list);
    await _saveAgents();
    notifyListeners();
  }

  Future<void> removeAgent(String id) async {
    final list = List<AgentConfig>.from(_settings.agents);
    list.removeWhere((p) => p.id == id);
    _settings = _settings.copyWith(agents: list);
    await _saveAgents();
    notifyListeners();
  }

  AgentConfig? getAgentById(String id) {
    try {
      return _settings.agents.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  // Duplicate methods removed
  ThemeMode get themeMode => _settings.materialThemeMode;
  Locale? get locale => _settings.materialLocale;

  // Providers management
  List<AiProviderConfig> get providers => _settings.providers;
  String? get activeProviderId => _settings.activeProviderId;
  bool get rotationEnabled => _settings.rotationEnabled;

  Future<void> _saveProviders(List<AiProviderConfig> list, {String? activeId}) async {
    final data = list.map((p) => p.toJson()).toList();
    await _prefs.setString(_kAiProviders, jsonEncode(data));
    if (activeId != null) await _prefs.setString(_kAiActiveId, activeId);
    _settings = _settings.copyWith(providers: list, activeProviderId: activeId ?? _settings.activeProviderId);
    notifyListeners();
  }

  Future<void> setActiveProvider(String id) async {
    await _prefs.setString(_kAiActiveId, id);
    _settings = _settings.copyWith(activeProviderId: id);
    notifyListeners();
  }

  Future<void> setRotationEnabled(bool enabled) async {
    await _prefs.setBool(_kAiRotationEnabled, enabled);
    _settings = _settings.copyWith(rotationEnabled: enabled);
    notifyListeners();
  }

  // Vision: active provider id (null => follow main)
  Future<void> setActiveVisionProvider(String? id) async {
    if (id == null) {
      await _prefs.remove(_kAiActiveVisionId);
    } else {
      await _prefs.setString(_kAiActiveVisionId, id);
    }
    _settings = _settings.copyWith(activeVisionProviderId: id);
    notifyListeners();
  }

  Future<void> setUseMainVisionIfCapable(bool v) async {
    await _prefs.setBool(_kUseMainVisionIfCapable, v);
    _settings = _settings.copyWith(useMainVisionIfCapable: v);
    notifyListeners();
  }

  Future<void> setVisionFallbackToAgent(bool v) async {
    await _prefs.setBool(_kVisionFallbackAgent, v);
    _settings = _settings.copyWith(visionFallbackToAgent: v);
    notifyListeners();
  }

  AiProviderConfig? get activeProviderConfig {
    final id = _settings.activeProviderId;
    if (id == null) {
      return _settings.providers.isNotEmpty ? _settings.providers.first : null;
    }
    for (final p in _settings.providers) {
      if (p.id == id) return p;
    }
    return _settings.providers.isNotEmpty ? _settings.providers.first : null;
  }

  AiSettings resolveActiveAi() {
    final p = activeProviderConfig;
    if (p == null) return _settings.ai;
    return AiSettings(
      provider: p.kind,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.model.isNotEmpty ? p.model : _settings.ai.model,
    );
  }

  Future<void> setProviderEnabled(String id, bool enabled) async {
    final list = List<AiProviderConfig>.from(_settings.providers);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(enabled: enabled);
      _settings = _settings.copyWith(providers: list);
      await _saveProviders(list);
      notifyListeners();
    }
  }

  Future<void> setProviderField(String id, {String? baseUrl, String? apiKey, String? model}) async {
    final list = List<AiProviderConfig>.from(_settings.providers);
    final idx = list.indexWhere((p) => p.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(baseUrl: baseUrl, apiKey: apiKey, model: model);
      _settings = _settings.copyWith(providers: list);
      await _saveProviders(list);
      notifyListeners();
    }
  }

  Future<void> addOrUpdateProvider(AiProviderConfig cfg) async {
    final list = List<AiProviderConfig>.from(_settings.providers);
    final idx = list.indexWhere((p) => p.id == cfg.id);
    if (idx == -1) {
      list.add(cfg);
    } else {
      list[idx] = cfg;
    }
    _settings = _settings.copyWith(providers: list);
    await _saveProviders(list);
    notifyListeners();
  }

  Future<void> removeProvider(String id) async {
    final list = List<AiProviderConfig>.from(_settings.providers);
    list.removeWhere((p) => p.id == id);
    
    String? nextActive = _settings.activeProviderId;
    if (_settings.activeProviderId == id) {
      nextActive = list.isNotEmpty ? list.first.id : null;
    }

    _settings = _settings.copyWith(providers: list, activeProviderId: nextActive);
    await _saveProviders(list, activeId: nextActive);
    notifyListeners();
  }

  Future<void> setProviderRotate(String id, bool rotate) async {
    // Rotation logic removed/simplified for now as 'rotate' field was removed from AiProviderConfig
    // If we want to keep rotation, we should re-add 'rotate' to AiProviderConfig or use 'enabled'
    // For now, let's assume 'enabled' means available for rotation if rotation is globally enabled
    await setProviderEnabled(id, rotate);
  }

  Future<void> setProviderRpm(String id, int? rpm) async {
    // RPM logic removed for now
  }

  AiProviderConfig? getProviderById(String id) {
    try {
      return _settings.providers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  AiSettings resolveFromConfig(AiProviderConfig p) {
    return AiSettings(
      provider: p.kind,
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.model.isNotEmpty ? p.model : _settings.ai.model,
    );
  }

  // 根据轮换策略选择下一个平台（若未启用轮换则返回当前激活平台）
  AiProviderConfig? selectProviderForNextCall({AiProviderCategory category = AiProviderCategory.llm}) {
    // 1. Filter by category and enabled status
    final pool = _settings.providers.where((p) => p.enabled && p.category == category).toList();
    
    if (pool.isEmpty) return null;

    // 2. Filter by usage limit
    final availablePool = pool.where((p) => _isUsageAllowed(p)).toList();
    
    if (availablePool.isEmpty) {
      // If all reached limit, maybe fallback to first one or return null?
      // For now, return null to indicate exhaustion
      return null;
    }

    if (_settings.rotationEnabled) {
      // Simple round-robin based on global index (might need per-category index in future)
      _rotationIndex = (_rotationIndex + 1) % availablePool.length;
      return availablePool[_rotationIndex];
    }
    
    // If rotation disabled, try to find the active one for this category
    // If activeProviderId is not in this category, just pick the first available
    final active = availablePool.firstWhere(
      (p) => p.id == _settings.activeProviderId,
      orElse: () => availablePool.first,
    );
    return active;
  }

  // Usage tracking
  Future<void> incrementUsage(String providerId) async {
    final list = List<AiProviderConfig>.from(_settings.providers);
    final idx = list.indexWhere((p) => p.id == providerId);
    if (idx != -1) {
      final p = list[idx];
      final now = DateTime.now();
      final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      
      int newCount = p.usageCount + 1;
      if (p.lastUsageDate != todayStr) {
        newCount = 1;
      }
      
      list[idx] = p.copyWith(
        usageCount: newCount,
        lastUsageDate: todayStr,
      );
      
      _settings = _settings.copyWith(providers: list);
      await _saveProviders(list);
      notifyListeners();
    }
  }

  bool _isUsageAllowed(AiProviderConfig p) {
    if (p.dailyLimit <= 0) return true;
    
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    
    if (p.lastUsageDate != todayStr) return true; // Will reset on next increment
    return p.usageCount < p.dailyLimit;
  }

  // 获取并缓存模型列表
  Future<List<String>> fetchModels(String id) async {
    final cfg = getProviderById(id);
    if (cfg == null) return const [];
    final ai = resolveFromConfig(cfg);
    final models = await AiClient.fetchModels(ai: ai, baseUrlIsRoot: cfg.isRoot);
    return models;
  }

  Future<String> testProvider(String id) async {
    final cfg = getProviderById(id);
    if (cfg == null) return '未找到配置';
    final ai = resolveFromConfig(cfg);
    final msg = await AiClient.testConnection(ai: ai, baseUrlIsRoot: cfg.isRoot);
    return msg;
  }

  Future<void> setUserNickname(String value) async {
    _settings = _settings.copyWith(userNickname: value);
    await _prefs.setString(_kUserNickname, value);
    notifyListeners();
  }

  Future<void> setLearningProbability(double value) async {
    _settings = _settings.copyWith(learningProbability: value);
    await _prefs.setDouble(_kLearningProbability, value);
    notifyListeners();
  }

  // Vision settings setters
  Future<void> setVisionPromptTemplate(String value) async {
    _settings = _settings.copyWith(visionPromptTemplate: value);
    await _prefs.setString(_kVisionPrompt, value);
    notifyListeners();
  }

  Future<void> setVisionPreferredLength(int value) async {
    _settings = _settings.copyWith(visionPreferredLength: value);
    await _prefs.setInt(_kVisionPrefLen, value);
    notifyListeners();
  }

  Future<void> setVisionMaxLength(int value) async {
    _settings = _settings.copyWith(visionMaxLength: value);
    await _prefs.setInt(_kVisionMaxLen, value);
    notifyListeners();
  }

  Future<void> setQuickActions(List<String> actions) async {
    _settings = _settings.copyWith(quickActions: actions);
    await _prefs.setString(_kQuickActions, jsonEncode(actions));
    notifyListeners();
  }

  Future<void> setEnablePythonBackend(bool v) async {
    _settings = _settings.copyWith(enablePythonBackend: v);
    await _prefs.setBool(_kEnablePythonBackend, v);
    notifyListeners();
  }

  Future<void> setPythonBackendUrl(String v) async {
    _settings = _settings.copyWith(pythonBackendUrl: v);
    await _prefs.setString(_kPythonBackendUrl, v);
    notifyListeners();
  }

  Future<void> setEnableDeepResearch(bool v) async {
    _settings = _settings.copyWith(enableDeepResearch: v);
    await _prefs.setBool(_kEnableDeepResearch, v);
    notifyListeners();
  }

  Future<void> setSearchRegion(SearchRegionOption region) async {
    _settings = _settings.copyWith(searchRegion: region);
    await _prefs.setInt(_kSearchRegion, region.index);
    notifyListeners();
  }
  Future<void> setSystemPrompt(String? value) async {
    _settings = _settings.copyWith(systemPrompt: value);
    if (value == null) {
      await _prefs.remove(_kSystemPrompt);
    } else {
      await _prefs.setString(_kSystemPrompt, value);
    }
    notifyListeners();
  }

  Future<void> setAssistantName(String value) async {
    _settings = _settings.copyWith(assistantName: value);
    await _prefs.setString(_kAssistantName, value);
    notifyListeners();
  }

  Future<void> setIsFirstRun(bool value) async {
    _settings = _settings.copyWith(isFirstRun: value);
    await _prefs.setBool(_kIsFirstRun, value);
    notifyListeners();
  }

  Future<String> uploadReferenceAudio(String providerId, String filePath, String customName, {String? text}) async {
    final provider = providers.firstWhere((p) => p.id == providerId);
    final uri = await AiClient.uploadVoice(
      config: provider,
      filePath: filePath,
      customName: customName,
      text: text,
    );
    
    final meta = Map<String, dynamic>.from(provider.meta);
    meta['voice'] = uri; // Set as current voice
    
    final voices = (meta['uploaded_voices'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    voices.add({'uri': uri, 'name': customName, 'date': DateTime.now().toIso8601String()});
    meta['uploaded_voices'] = voices;
    
    await addOrUpdateProvider(provider.copyWith(meta: meta));
    return uri;
  }
}
