// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'N-T-AI (Firefly)';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get tabGeneral => 'General';

  @override
  String get tabProviders => 'Providers';

  @override
  String get tabAgents => 'Agents';

  @override
  String get tabCapabilities => 'Capabilities';

  @override
  String get tabData => 'Data';

  @override
  String get tabAbout => 'About';

  @override
  String get chatPlaceholder => 'Say something to Firefly...';

  @override
  String get greetingMissingKey =>
      'Hello! I am Firefly. Please configure an AI provider in Settings -> Providers first!';

  @override
  String get greetingNormal =>
      'Hello! I am Firefly, nice to meet you. What would you like to chat about today?';

  @override
  String get quickActionAttachImage => 'Attach Image';

  @override
  String get quickActionCompress => 'Compress Context';

  @override
  String get quickActionNewChat => 'New Chat';

  @override
  String get quickActionMemory => 'Memory';

  @override
  String get quickActionExpression => 'Toggle Expression';

  @override
  String get historyTitle => 'Chat History';

  @override
  String get modelTitle => 'Model';

  @override
  String get tokensLabel => 'Tokens: ';

  @override
  String get aboutLegal => 'Legal & Copyright';

  @override
  String get aboutFeedback => 'Feedback & Support';

  @override
  String get aboutReportIssue => 'Report Issue / Feature Request';

  @override
  String get aboutDisclaimer =>
      'Disclaimer:\n1. This software is for learning and research purposes only.\n2. AI generated content is random and does not represent the developer\'s views.\n3. Font copyrights belong to their respective owners.\n4. Please contact us if you find any infringing content.';

  @override
  String get btnCancel => 'Cancel';

  @override
  String get btnSave => 'Save';

  @override
  String get aboutProjectExpansionTitle => 'Project';

  @override
  String get aboutProjectExpansion =>
      'NTAI stands for Neural Tactical AI — a neural-network driven, tactical agent framework focused on multi-agent coordination, task planning and conversational intelligence. \'Astra-Me\' refers to the platform/system, while \'Firefly\' (the assistant persona) refers to the user-facing AI.';

  @override
  String get msgCompressing => 'Compressing context...';

  @override
  String get errImagePick => 'Failed to pick image: ';

  @override
  String get generalBasicSettings => 'Basic Settings';

  @override
  String get generalAutoConnectBackend => 'Auto-connect Backend';

  @override
  String get generalAutoConnectBackendSubtitle =>
      'Automatically check and connect to the configured Python backend';

  @override
  String get generalAutoStartBackend => 'Auto-start Backend';

  @override
  String get generalAutoStartBackendSubtitle =>
      'Automatically start local backend process (Windows release & localhost)';

  @override
  String get generalBackendStatus => 'Backend Status';

  @override
  String get backendStatusConnected => 'Connected';

  @override
  String get backendStatusInitializing => 'Connecting';

  @override
  String get backendStatusIncompatible => 'Incompatible';

  @override
  String get backendStatusDisconnected => 'Disconnected';

  @override
  String get backendStatusAutoConnectOff => 'Auto-connect off';

  @override
  String get backendStatusBackendDisabled => 'Disabled';

  @override
  String get generalUserNickname => 'User Nickname';

  @override
  String get generalNicknameNotSet => 'Not set (Firefly will decide)';

  @override
  String get generalSetNickname => 'Set Nickname';

  @override
  String get generalNicknameHint => 'e.g., Master, Brother, Sister...';

  @override
  String get generalAppearance => 'Appearance & Theme';

  @override
  String get generalLanguage => 'Language';

  @override
  String get generalTheme => 'Theme Mode';

  @override
  String get generalThemeSystem => 'System';

  @override
  String get generalThemeLight => 'Light';

  @override
  String get generalThemeDark => 'Dark';

  @override
  String get generalPalette => 'Color Palette';

  @override
  String get generalPaletteNeutral => 'Neutral (White/Black)';

  @override
  String get generalPaletteGreen => 'Green';

  @override
  String get generalPaletteBlue => 'Blue';

  @override
  String get generalPaletteOrange => 'Orange';

  @override
  String get generalUiMode => 'UI Style';

  @override
  String get generalUiModeAuto => 'Auto';

  @override
  String get generalUiModeBubble => 'Bubble (Beautiful)';

  @override
  String get generalUiModeSimple => 'Simple (Performance)';

  @override
  String get generalChatBg => 'Chat Background';

  @override
  String get generalChatBgNone => 'Solid/None';

  @override
  String get generalChatBgLavender => 'Lavender Gradient';

  @override
  String get generalFontSettings => 'Font Settings';

  @override
  String get generalBaseFont => 'Base Font';

  @override
  String get generalBaseFontSystem => 'System';

  @override
  String get generalBaseFontMiSans => 'Prefer MiSans';

  @override
  String get generalDecoFont => 'Decorative Font';

  @override
  String get generalDecoFontNone => 'None';

  @override
  String get generalDecoUseTitles => 'Use for Titles';

  @override
  String get generalDecoUseBubbles => 'Use for Chat Bubbles';

  @override
  String get generalFontPreview => 'Font Preview';

  @override
  String get generalFontPreviewTitle => 'Title Sample: Firefly';

  @override
  String get generalFontPreviewText =>
      'This is a chat bubble sample.\n1234567890';

  @override
  String get generalTextScale => 'Text Scale';

  @override
  String get generalQuickActions => 'Quick Actions';

  @override
  String get generalQuickActionsInput => 'Input Area Buttons';

  @override
  String get generalQuickActionsEmpty => 'No active buttons';

  @override
  String get generalEdit => 'Edit';

  @override
  String get generalEditQuickActions => 'Edit Quick Actions';

  @override
  String get qaAttachImage => 'Attach Image';

  @override
  String get qaCompress => 'Compress Context';

  @override
  String get qaNewChat => 'New Chat';

  @override
  String get qaMemory => 'Memory';

  @override
  String get qaExpressionToggle => 'Toggle Expression';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get generalCharacterModel => 'Character Model';

  @override
  String get generalManageModels => 'Manage Live2D models';

  @override
  String get generalEnableLive2D => 'Enable Live2D';

  @override
  String get generalShowLive2D => 'Show Live2D character in chat';

  @override
  String get generalShowLive2DHome => 'Show Live2D on Home';

  @override
  String get generalShowLive2DHomeSubtitle =>
      'Show Live2D character in main chat view';

  @override
  String get generalFloatingWindow => 'Floating Window';

  @override
  String get generalFloatingWindowSubtitle =>
      'Create independent window (OBS compatible)';

  @override
  String get generalLive2dDebug => 'Live2D Debug';

  @override
  String get generalLive2dDebugSubtitle => 'Show debug info on Live2D page';

  @override
  String get generalExpressionSync => 'Expression Sync';

  @override
  String get generalExpressionIsland => 'Show Expression Island';

  @override
  String get generalExpressionIslandSubtitle =>
      'Show dynamic expression island (independent of Live2D)';

  @override
  String get generalVoiceInteraction => 'Voice Interaction';

  @override
  String get generalEnableTts => 'Enable TTS';

  @override
  String get generalEnableTtsSubtitle => 'Allow model to speak responses';

  @override
  String get generalEnableStt => 'Enable STT';

  @override
  String get generalEnableSttSubtitle => 'Allow voice input';

  @override
  String get generalChatMode => 'Chat Mode';

  @override
  String get generalChatModePersona => 'Persona';

  @override
  String get generalChatModePersonaDesc => 'Bubbles, natural conversation';

  @override
  String get generalChatModeStandard => 'Standard';

  @override
  String get generalChatModeStandardDesc => 'Strict Markdown, productivity';

  @override
  String get generalRestartOnboarding => 'Restart Onboarding';

  @override
  String get generalRestartOnboardingSubtitle =>
      'Reset assistant persona and system prompt';
}
