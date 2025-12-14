import 'package:flutter/material.dart';

enum ThemeModeOption { system, light, dark }

enum LocaleOption { system, zh, en }

enum DensityOption { compact, normal, spacious }

enum ChatBgOption { none, lavender }

enum AiProvider { local, openai, custom }

enum OrchestrationMode { client, server }

// 配色方案：简约（中性）、绿色、蓝色、橙色
enum PaletteOption { neutral, green, blue, orange }

// 对话界面样式：自动（根据设备/尺寸做轻量判断）、气泡（丰富动效与圆角）、简洁（更省资源）
enum UIModeOption { auto, bubble, simple }

// 字体模式：系统默认、优先 MiSans、FZG 用于标题
// 基础字体模式：是否全局优先 MiSans
enum BaseFontModeOption { system, miSansPreferred }

// 装饰字体家族：用于标题/聊天气泡等可选应用
enum DecorativeFontFamily { none, fzg, nfdcs }

// 搜索区域偏好
enum SearchRegionOption { auto, cn, global }

// 聊天模式：拟人（分段气泡、自然） vs 标准（Markdown严格、单气泡、生产力）
enum ChatModeOption { persona, standard }

enum PersonaLevelOption { basic, advanced, full }

class AiSettings {
  final AiProvider provider;
  final String baseUrl; // 对于 openai 可留空（使用默认），custom 需要填写
  final String apiKey; // 对于 local 可留空
  final String model; // 例如 gpt-4o, llama3.1:8b 等

  const AiSettings({
    this.provider = AiProvider.local,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
  });

  AiSettings copyWith({
    AiProvider? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) => AiSettings(
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
  );
}

class AgentConfig {
  final String id;
  final String name;
  final String? providerId; // reference to AiProviderConfig.id
  final String description;
  final bool enabled;
  final Map<String, dynamic> meta; // arbitrary agent-specific settings

  const AgentConfig({
    required this.id,
    required this.name,
    this.providerId,
    this.description = '',
    this.enabled = true,
    this.meta = const {},
  });

  factory AgentConfig.fromJson(Map<String, dynamic> json) => AgentConfig(
    id: json['id'] as String,
    name: json['name'] as String,
    providerId: json['providerId'] as String?,
    description: json['description'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    meta: (json['meta'] as Map?)?.cast<String, dynamic>() ?? {},
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'providerId': providerId,
    'description': description,
    'enabled': enabled,
    'meta': meta,
  };

  AgentConfig copyWith({
    String? name,
    String? providerId,
    String? description,
    bool? enabled,
    Map<String, dynamic>? meta,
  }) => AgentConfig(
    id: id,
    name: name ?? this.name,
    providerId: providerId ?? this.providerId,
    description: description ?? this.description,
    enabled: enabled ?? this.enabled,
    meta: meta ?? this.meta,
  );
}

enum AiProviderCategory { llm, tts, stt, motion, image, video }

class AiProviderConfig {
  final String id;
  final String name;
  final AiProvider kind;
  final String baseUrl;
  final String apiKey;
  final String model;
  final bool isRoot; // 是否为预置根配置（不可删除，但可编辑）
  final bool enabled; // 是否启用（参与轮换）
  final OrchestrationMode orchestrationMode; // 编排模式：客户端(默认) or 服务端
  final AiProviderCategory category; // 模型类别
  final int dailyLimit; // 每日调用次数限制 (0为不限)
  final int usageCount; // 今日已调用次数
  final String lastUsageDate; // 上次调用日期 (YYYY-MM-DD)
  final Map<String, dynamic> meta; // 额外元数据
  final List<String> capabilities; // 模型能力标签: text, image, audio, video

  const AiProviderConfig({
    required this.id,
    required this.name,
    required this.kind,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.isRoot = false,
    this.enabled = true,
    this.orchestrationMode = OrchestrationMode.client,
    this.category = AiProviderCategory.llm,
    this.dailyLimit = 0,
    this.usageCount = 0,
    this.lastUsageDate = '',
    this.meta = const {},
    this.capabilities = const [],
  });

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) =>
      AiProviderConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: AiProvider.values.firstWhere(
          (e) => e.name == json['kind'],
          orElse: () => AiProvider.local,
        ),
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        isRoot: json['isRoot'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
        orchestrationMode: OrchestrationMode.values.firstWhere(
          (e) => e.name == (json['orchestrationMode'] as String? ?? 'client'),
          orElse: () => OrchestrationMode.client,
        ),
        category: AiProviderCategory.values.firstWhere(
          (e) => e.name == (json['category'] as String? ?? 'llm'),
          orElse: () => AiProviderCategory.llm,
        ),
        dailyLimit: json['dailyLimit'] as int? ?? 0,
        usageCount: json['usageCount'] as int? ?? 0,
        lastUsageDate: json['lastUsageDate'] as String? ?? '',
        meta: (json['meta'] as Map?)?.cast<String, dynamic>() ?? {},
        capabilities: (json['capabilities'] as List?)?.cast<String>() ?? [],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'isRoot': isRoot,
    'enabled': enabled,
    'orchestrationMode': orchestrationMode.name,
    'category': category.name,
    'dailyLimit': dailyLimit,
    'usageCount': usageCount,
    'lastUsageDate': lastUsageDate,
    'meta': meta,
    'capabilities': capabilities,
  };

  AiProviderConfig copyWith({
    String? name,
    AiProvider? kind,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? isRoot,
    bool? enabled,
    OrchestrationMode? orchestrationMode,
    AiProviderCategory? category,
    int? dailyLimit,
    int? usageCount,
    String? lastUsageDate,
    Map<String, dynamic>? meta,
    List<String>? capabilities,
  }) => AiProviderConfig(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    isRoot: isRoot ?? this.isRoot,
    enabled: enabled ?? this.enabled,
    orchestrationMode: orchestrationMode ?? this.orchestrationMode,
    category: category ?? this.category,
    dailyLimit: dailyLimit ?? this.dailyLimit,
    usageCount: usageCount ?? this.usageCount,
    lastUsageDate: lastUsageDate ?? this.lastUsageDate,
    meta: meta ?? this.meta,
    capabilities: capabilities ?? this.capabilities,
  );
}

class McpServerConfig {
  final String id;
  final String name;
  final String command; // e.g. "npx" or "python"
  final List<String> args; // e.g. ["-m", "mcp_server"]
  final Map<String, String> env;
  final bool enabled;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
    this.enabled = true,
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        command: json['command'] as String,
        args: (json['args'] as List?)?.map((e) => e as String).toList() ?? [],
        env: (json['env'] as Map?)?.cast<String, String>() ?? {},
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'args': args,
    'env': env,
    'enabled': enabled,
  };

  McpServerConfig copyWith({
    String? name,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    bool? enabled,
  }) => McpServerConfig(
    id: id,
    name: name ?? this.name,
    command: command ?? this.command,
    args: args ?? this.args,
    env: env ?? this.env,
    enabled: enabled ?? this.enabled,
  );
}

class AppSettings {
  final ThemeModeOption themeMode;
  final LocaleOption locale;
  final DensityOption density;
  final double textScale; // 0.9 ~ 1.4
  final ChatBgOption chatBg;
  final PaletteOption palette; // 配色方案
  final UIModeOption uiMode; // 对话界面样式
  final ChatModeOption chatMode; // 聊天模式
  final PersonaLevelOption personaLevel; // 人格等级
  // 字体
  final BaseFontModeOption baseFontMode; // 基础字体（是否优先 MiSans）
  final DecorativeFontFamily decoFamily; // 装饰字体家族（FZG / nfdcs / none）
  final bool decoUseTitles; // 装饰字体用于标题
  final bool decoUseBubbles; // 装饰字体用于聊天气泡
  final AiSettings ai;
  final List<AiProviderConfig> providers; // 多供应商配置
  final String? activeProviderId; // 选中的 provider id
  final String? activeVisionProviderId; // 视觉中枢选中的 provider id（为空表示跟随主脑）
  final String? activeExpressionProviderId; // 表情推理选中的 provider id
  final String? activeSearchProviderId; // 搜索总结选中的 provider id
  final String? activeMotionProviderId; // Live2D 动作决策选中的 provider id
  final String live2dModelPath; // Live2D 模型路径
  final bool rotationEnabled; // 启用多平台轮换
  final bool agentEnabled; // 是否启用 Agent 智能体模式 (多模型协作)
  final bool useMainVisionIfCapable; // 主脑具备视觉则优先使用主脑
  final bool visionFallbackToAgent; // 无视觉时是否自动走 Agent 提示词路径
  // Expression/Avatar controls
  final bool enableExpressionAgent; // 是否启用表情 Agent 并发调用
  final bool showExpressionFace; // 是否在聊天顶部显示动态表情 (Simple Face)
  final bool enableLive2D; // 是否启用 Live2D 渲染 (WebView)
  final bool showLive2D; // 是否在主界面显示 Live2D 形象
  final bool showLive2DMiniWindow; // 是否在右上角显示内置小窗
  final bool enableFloatingWindow; // 是否启用独立悬浮窗显示 Live2D
  final bool live2dDebug; // 是否显示 Live2D 调试信息

  // Agent Tools Configuration
  final bool enableBrowser; // 启用浏览器工具
  final bool enableSearchRetry; // 启用搜索重试 (防止 Token 浪费)
  final bool enableNoteAccess; // 启用笔记读取权限
  final bool showAgentThoughts; // 显示 Agent 思考过程
  final List<McpServerConfig> mcpServers; // MCP 服务器列表
  final List<AgentConfig> agents; // 独立 Agent 配置

  // Python Backend / Neural Hub Settings
  final bool enablePythonBackend; // 是否启用 Python 后端
  final String pythonBackendUrl; // Python 后端地址
  final bool enableDeepResearch; // 是否启用深度研究 (全自动闭环模式)
  final SearchRegionOption searchRegion; // 搜索区域偏好

  // User Preferences
  final String userNickname;
  final double learningProbability;

  // Vision (multimodal) defaults
  final String visionPromptTemplate; // 默认视觉提示词
  final int visionPreferredLength; // 建议长度（字数）
  final int visionMaxLength; // 最大长度（字数）
  // Quick action buttons (identifiers) to show near input
  final List<String> quickActions;

  // Assistant Identity
  final String assistantName; // 助手名称
  final String systemPrompt; // 自定义系统提示词 (Persona)
  final bool isFirstRun; // 是否首次运行 (用于显示引导页)
  final bool enableTts; // 启用语音合成输出
  final bool enableStt; // 启用语音识别输入
  final int logMaxErrors; // 最近错误日志条数

  const AppSettings({
    this.themeMode = ThemeModeOption.system,
    this.locale = LocaleOption.system,
    this.density = DensityOption.normal,
    this.textScale = 1.0,
    // 默认关闭紫色背景，采用素雅配色
    this.chatBg = ChatBgOption.none,
    this.palette = PaletteOption.neutral,
    this.uiMode = UIModeOption.auto,
    this.chatMode = ChatModeOption.persona,
    this.personaLevel = PersonaLevelOption.full,
    this.baseFontMode = BaseFontModeOption.miSansPreferred,
    this.decoFamily = DecorativeFontFamily.none,
    this.decoUseTitles = false,
    this.decoUseBubbles = false,
    this.ai = const AiSettings(),
    this.providers = const [],
    this.activeProviderId,
    this.activeVisionProviderId,
    this.activeExpressionProviderId,
    this.activeSearchProviderId,
    this.activeMotionProviderId,
    this.live2dModelPath = '',
    this.rotationEnabled = false,
    this.agentEnabled = true,
    this.useMainVisionIfCapable = true,
    this.visionFallbackToAgent = true,
    this.enableExpressionAgent = false,
    this.showExpressionFace = true,
    this.enableLive2D = true, // Default to true
    this.showLive2D = true, // Default to true
    this.showLive2DMiniWindow = false,
    this.enableFloatingWindow = false, // Default to false
    this.live2dDebug = false, // 默认关闭调试信息
    this.enableBrowser = false,
    this.enableSearchRetry = true,
    this.enableNoteAccess = false,
    this.showAgentThoughts = false,
    this.mcpServers = const [],
    this.agents = const [],
    this.enablePythonBackend = false,
    this.pythonBackendUrl = 'http://localhost:8000',
    this.enableDeepResearch = false,
    this.searchRegion = SearchRegionOption.auto,
    this.userNickname = '',
    this.learningProbability = 1.0,
    this.visionPromptTemplate =
        '请用中文用一段话描述这张图片的内容。若有文字请概括其要点。以主题和直观感受为主，避免分点与多段，仅输出纯文本。',
    this.visionPreferredLength = 120,
    this.visionMaxLength = 500,
    this.quickActions = const ['attach_image', 'compress', 'new_chat'],
    this.assistantName = 'Firefly',
    this.systemPrompt = '', // Empty means use default from prompts.dart
    this.isFirstRun = true,
    this.enableTts = false,
    this.enableStt = false,
    this.logMaxErrors = 5,
  });
  AppSettings copyWith({
    ThemeModeOption? themeMode,
    LocaleOption? locale,
    DensityOption? density,
    double? textScale,
    ChatBgOption? chatBg,
    PaletteOption? palette,
    UIModeOption? uiMode,
    ChatModeOption? chatMode,
    PersonaLevelOption? personaLevel,
    BaseFontModeOption? baseFontMode,
    DecorativeFontFamily? decoFamily,
    bool? decoUseTitles,
    bool? decoUseBubbles,
    AiSettings? ai,
    List<AiProviderConfig>? providers,
    String? activeProviderId,
    String? activeVisionProviderId,
    String? activeExpressionProviderId,
    String? activeSearchProviderId,
    String? activeMotionProviderId,
    String? live2dModelPath,
    bool? rotationEnabled,
    bool? agentEnabled,
    bool? useMainVisionIfCapable,
    bool? visionFallbackToAgent,
    bool? enableExpressionAgent,
    bool? showExpressionFace,
    bool? enableLive2D,
    bool? showLive2D,
    bool? showLive2DMiniWindow,
    bool? enableFloatingWindow,
    bool? live2dDebug,
    bool? enableBrowser,
    bool? enableSearchRetry,
    bool? enableNoteAccess,
    bool? showAgentThoughts,
    List<McpServerConfig>? mcpServers,
    List<AgentConfig>? agents,
    bool? enablePythonBackend,
    String? pythonBackendUrl,
    bool? enableDeepResearch,
    SearchRegionOption? searchRegion,
    String? userNickname,
    double? learningProbability,
    String? visionPromptTemplate,
    int? visionPreferredLength,
    int? visionMaxLength,
    List<String>? quickActions,
    String? assistantName,
    String? systemPrompt,
    bool? isFirstRun,
    bool? enableTts,
    bool? enableStt,
    int? logMaxErrors,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    locale: locale ?? this.locale,
    density: density ?? this.density,
    textScale: textScale ?? this.textScale,
    chatBg: chatBg ?? this.chatBg,
    palette: palette ?? this.palette,
    uiMode: uiMode ?? this.uiMode,
    chatMode: chatMode ?? this.chatMode,
    personaLevel: personaLevel ?? this.personaLevel,
    baseFontMode: baseFontMode ?? this.baseFontMode,
    decoFamily: decoFamily ?? this.decoFamily,
    decoUseTitles: decoUseTitles ?? this.decoUseTitles,
    decoUseBubbles: decoUseBubbles ?? this.decoUseBubbles,
    ai: ai ?? this.ai,
    providers: providers ?? this.providers,
    activeProviderId: activeProviderId ?? this.activeProviderId,
    activeVisionProviderId:
        activeVisionProviderId ?? this.activeVisionProviderId,
    activeExpressionProviderId:
        activeExpressionProviderId ?? this.activeExpressionProviderId,
    activeSearchProviderId:
        activeSearchProviderId ?? this.activeSearchProviderId,
    activeMotionProviderId:
        activeMotionProviderId ?? this.activeMotionProviderId,
    live2dModelPath: live2dModelPath ?? this.live2dModelPath,
    rotationEnabled: rotationEnabled ?? this.rotationEnabled,
    agentEnabled: agentEnabled ?? this.agentEnabled,
    useMainVisionIfCapable:
        useMainVisionIfCapable ?? this.useMainVisionIfCapable,
    visionFallbackToAgent: visionFallbackToAgent ?? this.visionFallbackToAgent,
    enableExpressionAgent: enableExpressionAgent ?? this.enableExpressionAgent,
    showExpressionFace: showExpressionFace ?? this.showExpressionFace,
    enableLive2D: enableLive2D ?? this.enableLive2D,
    showLive2D: showLive2D ?? this.showLive2D,
    showLive2DMiniWindow: showLive2DMiniWindow ?? this.showLive2DMiniWindow,
    enableFloatingWindow: enableFloatingWindow ?? this.enableFloatingWindow,
    live2dDebug: live2dDebug ?? this.live2dDebug,
    enableBrowser: enableBrowser ?? this.enableBrowser,
    enableSearchRetry: enableSearchRetry ?? this.enableSearchRetry,
    enableNoteAccess: enableNoteAccess ?? this.enableNoteAccess,
    showAgentThoughts: showAgentThoughts ?? this.showAgentThoughts,
    mcpServers: mcpServers ?? this.mcpServers,
    agents: agents ?? this.agents,
    enablePythonBackend: enablePythonBackend ?? this.enablePythonBackend,
    pythonBackendUrl: pythonBackendUrl ?? this.pythonBackendUrl,
    enableDeepResearch: enableDeepResearch ?? this.enableDeepResearch,
    searchRegion: searchRegion ?? this.searchRegion,
    userNickname: userNickname ?? this.userNickname,
    learningProbability: learningProbability ?? this.learningProbability,
    visionPromptTemplate: visionPromptTemplate ?? this.visionPromptTemplate,
    visionPreferredLength: visionPreferredLength ?? this.visionPreferredLength,
    visionMaxLength: visionMaxLength ?? this.visionMaxLength,
    quickActions: quickActions ?? this.quickActions,
    assistantName: assistantName ?? this.assistantName,
    systemPrompt: systemPrompt ?? this.systemPrompt,
    isFirstRun: isFirstRun ?? this.isFirstRun,
    enableTts: enableTts ?? this.enableTts,
    enableStt: enableStt ?? this.enableStt,
    logMaxErrors: logMaxErrors ?? this.logMaxErrors,
  );

  ThemeMode get materialThemeMode => switch (themeMode) {
    ThemeModeOption.light => ThemeMode.light,
    ThemeModeOption.dark => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Locale? get materialLocale => switch (locale) {
    LocaleOption.zh => const Locale('zh'),
    LocaleOption.en => const Locale('en'),
    _ => null,
  };
}
