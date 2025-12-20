// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '流萤';

  @override
  String get settingsTitle => '设置';

  @override
  String get tabGeneral => '通用';

  @override
  String get tabProviders => '服务商';

  @override
  String get tabAgents => '智能体';

  @override
  String get tabCapabilities => '能力';

  @override
  String get tabData => '数据';

  @override
  String get tabAbout => '关于';

  @override
  String get chatPlaceholder => '和流萤说点什么...';

  @override
  String get greetingMissingKey =>
      '你好！我是流萤。请先在“系统”页面配置 AI 服务商（推荐 DeepSeek），然后我们就可以聊天啦！';

  @override
  String get greetingNormal => '你好呀！我是流萤，很高兴见到你。今天想聊点什么呢？';

  @override
  String get quickActionAttachImage => '附加图片';

  @override
  String get quickActionCompress => '压缩上下文';

  @override
  String get quickActionNewChat => '新对话';

  @override
  String get quickActionMemory => '记忆库';

  @override
  String get quickActionExpression => '切换表情面板';

  @override
  String get historyTitle => '历史对话';

  @override
  String get modelTitle => '模型';

  @override
  String get tokensLabel => 'Tokens: ';

  @override
  String get aboutLegal => '法律与版权';

  @override
  String get aboutFeedback => '反馈与支持';

  @override
  String get aboutReportIssue => '报告问题 / 功能建议';

  @override
  String get aboutDisclaimer =>
      '免责声明：\n1. 本软件仅供学习与研究使用，严禁用于任何非法用途。\n2. 软件中集成的 AI 模型生成内容具有随机性，不代表开发者立场。\n3. 字体文件版权归原作者所有，商用请自行获取授权。\n4. 若您发现任何侵权内容，请立即联系我们进行处理。';

  @override
  String get btnCancel => '取消';

  @override
  String get btnSave => '保存';

  @override
  String get aboutProjectExpansionTitle => '项目说明';

  @override
  String get aboutProjectExpansion =>
      'NTAI 为 \'Nexus-Thinking AI\' 的缩写：一个以神经网络为核心、强调策略与任务规划、以及多智能体协同能力的 AI 框架。\n“Astra-Me” 表示系统/平台层，而“流萤”（Firefly）为面向用户的 AI 助手名称。';

  @override
  String get msgCompressing => '正在压缩上下文...';

  @override
  String get errImagePick => '选择图片失败: ';

  @override
  String get generalBasicSettings => '基本设置';

  @override
  String get generalAutoConnectBackend => '自动连接后端';

  @override
  String get generalAutoConnectBackendSubtitle => '开启后自动检测并连接配置的 Python 后端';

  @override
  String get generalAutoStartBackend => '自动启动后端';

  @override
  String get generalAutoStartBackendSubtitle =>
      '开启后在本机自动启动后端进程（Windows Release 且 localhost）';

  @override
  String get generalBackendStatus => '后端连接状态';

  @override
  String get backendStatusConnected => '已连接';

  @override
  String get backendStatusInitializing => '连接中';

  @override
  String get backendStatusIncompatible => '不兼容';

  @override
  String get backendStatusDisconnected => '未连接';

  @override
  String get backendStatusAutoConnectOff => '未自动连接';

  @override
  String get backendStatusBackendDisabled => '未启用';

  @override
  String get generalUserNickname => '用户昵称';

  @override
  String get generalNicknameNotSet => '未设置 (流萤将自行决定)';

  @override
  String get generalSetNickname => '设置昵称';

  @override
  String get generalNicknameHint => '例如：主人、哥哥、姐姐...';

  @override
  String get generalAppearance => '外观与主题';

  @override
  String get generalLanguage => '语言设置';

  @override
  String get generalTheme => '主题模式';

  @override
  String get generalThemeSystem => '跟随系统';

  @override
  String get generalThemeLight => '浅色';

  @override
  String get generalThemeDark => '深色';

  @override
  String get generalPalette => '配色方案';

  @override
  String get generalPaletteNeutral => '简约（白/黑）';

  @override
  String get generalPaletteGreen => '绿色系';

  @override
  String get generalPaletteBlue => '蓝色系';

  @override
  String get generalPaletteOrange => '橙色系';

  @override
  String get generalUiMode => '对话界面风格';

  @override
  String get generalUiModeAuto => '自动';

  @override
  String get generalUiModeBubble => '气泡（更美观）';

  @override
  String get generalUiModeSimple => '简洁（更省资源）';

  @override
  String get generalChatBg => '聊天背景';

  @override
  String get generalChatBgNone => '纯色/无';

  @override
  String get generalChatBgLavender => '淡灰渐变';

  @override
  String get generalFontSettings => '字体设置';

  @override
  String get generalBaseFont => '基础字体';

  @override
  String get generalBaseFontSystem => '跟随系统';

  @override
  String get generalBaseFontMiSans => '优先 MiSans';

  @override
  String get generalDecoFont => '装饰字体';

  @override
  String get generalDecoFontNone => '无';

  @override
  String get generalDecoUseTitles => '装饰字体用于标题';

  @override
  String get generalDecoUseBubbles => '装饰字体用于聊天气泡';

  @override
  String get generalFontPreview => '字体效果预览';

  @override
  String get generalFontPreviewTitle => '标题示例：流萤 Firefly';

  @override
  String get generalFontPreviewText =>
      '这是一个聊天气泡示例。\nThis is a chat bubble sample.\n1234567890';

  @override
  String get generalTextScale => '字号缩放';

  @override
  String get generalQuickActions => '快捷操作';

  @override
  String get generalQuickActionsInput => '输入区快捷按钮';

  @override
  String get generalQuickActionsEmpty => '暂无已启用快捷按钮';

  @override
  String get generalEdit => '编辑';

  @override
  String get generalEditQuickActions => '编辑快捷按钮';

  @override
  String get qaAttachImage => '附加图片';

  @override
  String get qaCompress => '压缩上下文';

  @override
  String get qaNewChat => '新对话';

  @override
  String get qaMemory => '记忆库';

  @override
  String get qaExpressionToggle => '切换表情';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get generalCharacterModel => '角色模型';

  @override
  String get generalManageModels => '管理 Live2D 模型';

  @override
  String get generalEnableLive2D => '启用 Live2D';

  @override
  String get generalShowLive2D => '在聊天中显示 Live2D 角色';

  @override
  String get generalShowLive2DHome => '主页显示 Live2D';

  @override
  String get generalShowLive2DHomeSubtitle => '在主聊天界面显示 Live2D 形象';

  @override
  String get generalFloatingWindow => '独立悬浮窗显示';

  @override
  String get generalFloatingWindowSubtitle => '创建独立窗口显示 Live2D（可被 OBS 捕获）';

  @override
  String get generalLive2dDebug => 'Live2D 调试模式';

  @override
  String get generalLive2dDebugSubtitle => '显示 Live2D 页面调试信息';

  @override
  String get generalExpressionSync => '表情同步';

  @override
  String get generalExpressionIsland => '显示动态表情岛';

  @override
  String get generalExpressionIslandSubtitle => '显示动态表情岛（与 Live2D 独立）';

  @override
  String get generalVoiceInteraction => '语音交互 (Voice Interaction)';

  @override
  String get generalEnableTts => '启用语音合成 (TTS)';

  @override
  String get generalEnableTtsSubtitle => '允许模型朗读回复内容';

  @override
  String get generalEnableStt => '启用语音识别 (STT)';

  @override
  String get generalEnableSttSubtitle => '允许使用语音输入';

  @override
  String get generalChatMode => '聊天模式 (Chat Mode)';

  @override
  String get generalChatModePersona => '拟人 (Persona)';

  @override
  String get generalChatModePersonaDesc => '分段气泡，自然对话';

  @override
  String get generalChatModeStandard => '标准 (Standard)';

  @override
  String get generalChatModeStandardDesc => '严格Markdown，生产力';

  @override
  String get generalRestartOnboarding => '重新运行向导';

  @override
  String get generalRestartOnboardingSubtitle => '重置助手人设与系统提示词';
}
