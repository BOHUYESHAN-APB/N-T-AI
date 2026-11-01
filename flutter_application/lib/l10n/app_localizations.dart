import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'N-T-AI (Firefly)'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @tabGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get tabGeneral;

  /// No description provided for @tabProviders.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get tabProviders;

  /// No description provided for @tabAgents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get tabAgents;

  /// No description provided for @tabCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get tabCapabilities;

  /// No description provided for @tabData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get tabData;

  /// No description provided for @tabAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get tabAbout;

  /// No description provided for @chatPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Say something to Firefly...'**
  String get chatPlaceholder;

  /// No description provided for @greetingMissingKey.
  ///
  /// In en, this message translates to:
  /// **'Hello! I am Firefly. Please configure an AI provider in Settings -> Providers first!'**
  String get greetingMissingKey;

  /// No description provided for @greetingNormal.
  ///
  /// In en, this message translates to:
  /// **'Hello! I am Firefly, nice to meet you. What would you like to chat about today?'**
  String get greetingNormal;

  /// No description provided for @quickActionAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach Image'**
  String get quickActionAttachImage;

  /// No description provided for @quickActionCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress Context'**
  String get quickActionCompress;

  /// No description provided for @quickActionNewChat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get quickActionNewChat;

  /// No description provided for @quickActionMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get quickActionMemory;

  /// No description provided for @quickActionExpression.
  ///
  /// In en, this message translates to:
  /// **'Toggle Expression'**
  String get quickActionExpression;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat History'**
  String get historyTitle;

  /// No description provided for @modelTitle.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get modelTitle;

  /// No description provided for @tokensLabel.
  ///
  /// In en, this message translates to:
  /// **'Tokens: '**
  String get tokensLabel;

  /// No description provided for @aboutLegal.
  ///
  /// In en, this message translates to:
  /// **'Legal & Copyright'**
  String get aboutLegal;

  /// No description provided for @aboutFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback & Support'**
  String get aboutFeedback;

  /// No description provided for @aboutReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report Issue / Feature Request'**
  String get aboutReportIssue;

  /// No description provided for @aboutDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer:\n1. This software is for learning and research purposes only.\n2. AI generated content is random and does not represent the developer\'s views.\n3. Font copyrights belong to their respective owners.\n4. Please contact us if you find any infringing content.'**
  String get aboutDisclaimer;

  /// No description provided for @btnCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get btnCancel;

  /// No description provided for @btnSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get btnSave;

  /// No description provided for @aboutProjectExpansionTitle.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get aboutProjectExpansionTitle;

  /// No description provided for @aboutProjectExpansion.
  ///
  /// In en, this message translates to:
  /// **'NTAI stands for Neural Tactical AI — a neural-network driven, tactical agent framework focused on multi-agent coordination, task planning and conversational intelligence. \'Astra-Me\' refers to the platform/system, while \'Firefly\' (the assistant persona) refers to the user-facing AI.'**
  String get aboutProjectExpansion;

  /// No description provided for @msgCompressing.
  ///
  /// In en, this message translates to:
  /// **'Compressing context...'**
  String get msgCompressing;

  /// No description provided for @errImagePick.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick image: '**
  String get errImagePick;

  /// No description provided for @generalBasicSettings.
  ///
  /// In en, this message translates to:
  /// **'Basic Settings'**
  String get generalBasicSettings;

  /// No description provided for @generalAutoConnectBackend.
  ///
  /// In en, this message translates to:
  /// **'Auto-connect Backend'**
  String get generalAutoConnectBackend;

  /// No description provided for @generalAutoConnectBackendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically check and connect to the configured Python backend'**
  String get generalAutoConnectBackendSubtitle;

  /// No description provided for @generalAutoStartBackend.
  ///
  /// In en, this message translates to:
  /// **'Auto-start Backend'**
  String get generalAutoStartBackend;

  /// No description provided for @generalAutoStartBackendSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically start local backend process (Windows release & localhost)'**
  String get generalAutoStartBackendSubtitle;

  /// No description provided for @generalBackendStatus.
  ///
  /// In en, this message translates to:
  /// **'Backend Status'**
  String get generalBackendStatus;

  /// No description provided for @backendStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get backendStatusConnected;

  /// No description provided for @backendStatusInitializing.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get backendStatusInitializing;

  /// No description provided for @backendStatusIncompatible.
  ///
  /// In en, this message translates to:
  /// **'Incompatible'**
  String get backendStatusIncompatible;

  /// No description provided for @backendStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get backendStatusDisconnected;

  /// No description provided for @backendStatusAutoConnectOff.
  ///
  /// In en, this message translates to:
  /// **'Auto-connect off'**
  String get backendStatusAutoConnectOff;

  /// No description provided for @backendStatusBackendDisabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get backendStatusBackendDisabled;

  /// No description provided for @generalUserNickname.
  ///
  /// In en, this message translates to:
  /// **'User Nickname'**
  String get generalUserNickname;

  /// No description provided for @generalNicknameNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set (Firefly will decide)'**
  String get generalNicknameNotSet;

  /// No description provided for @generalSetNickname.
  ///
  /// In en, this message translates to:
  /// **'Set Nickname'**
  String get generalSetNickname;

  /// No description provided for @generalNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Master, Brother, Sister...'**
  String get generalNicknameHint;

  /// No description provided for @generalAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance & Theme'**
  String get generalAppearance;

  /// No description provided for @generalLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get generalLanguage;

  /// No description provided for @generalTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get generalTheme;

  /// No description provided for @generalThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get generalThemeSystem;

  /// No description provided for @generalThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get generalThemeLight;

  /// No description provided for @generalThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get generalThemeDark;

  /// No description provided for @generalPalette.
  ///
  /// In en, this message translates to:
  /// **'Color Palette'**
  String get generalPalette;

  /// No description provided for @generalPaletteNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral (White/Black)'**
  String get generalPaletteNeutral;

  /// No description provided for @generalPaletteGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get generalPaletteGreen;

  /// No description provided for @generalPaletteBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get generalPaletteBlue;

  /// No description provided for @generalPaletteOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get generalPaletteOrange;

  /// No description provided for @generalUiMode.
  ///
  /// In en, this message translates to:
  /// **'UI Style'**
  String get generalUiMode;

  /// No description provided for @generalUiModeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get generalUiModeAuto;

  /// No description provided for @generalUiModeBubble.
  ///
  /// In en, this message translates to:
  /// **'Bubble (Beautiful)'**
  String get generalUiModeBubble;

  /// No description provided for @generalUiModeSimple.
  ///
  /// In en, this message translates to:
  /// **'Simple (Performance)'**
  String get generalUiModeSimple;

  /// No description provided for @generalChatBg.
  ///
  /// In en, this message translates to:
  /// **'Chat Background'**
  String get generalChatBg;

  /// No description provided for @generalChatBgNone.
  ///
  /// In en, this message translates to:
  /// **'Solid/None'**
  String get generalChatBgNone;

  /// No description provided for @generalChatBgLavender.
  ///
  /// In en, this message translates to:
  /// **'Lavender Gradient'**
  String get generalChatBgLavender;

  /// No description provided for @generalFontSettings.
  ///
  /// In en, this message translates to:
  /// **'Font Settings'**
  String get generalFontSettings;

  /// No description provided for @generalBaseFont.
  ///
  /// In en, this message translates to:
  /// **'Base Font'**
  String get generalBaseFont;

  /// No description provided for @generalBaseFontSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get generalBaseFontSystem;

  /// No description provided for @generalBaseFontMiSans.
  ///
  /// In en, this message translates to:
  /// **'Prefer MiSans'**
  String get generalBaseFontMiSans;

  /// No description provided for @generalDecoFont.
  ///
  /// In en, this message translates to:
  /// **'Decorative Font'**
  String get generalDecoFont;

  /// No description provided for @generalDecoFontNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get generalDecoFontNone;

  /// No description provided for @generalDecoUseTitles.
  ///
  /// In en, this message translates to:
  /// **'Use for Titles'**
  String get generalDecoUseTitles;

  /// No description provided for @generalDecoUseBubbles.
  ///
  /// In en, this message translates to:
  /// **'Use for Chat Bubbles'**
  String get generalDecoUseBubbles;

  /// No description provided for @generalFontPreview.
  ///
  /// In en, this message translates to:
  /// **'Font Preview'**
  String get generalFontPreview;

  /// No description provided for @generalFontPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Title Sample: Firefly'**
  String get generalFontPreviewTitle;

  /// No description provided for @generalFontPreviewText.
  ///
  /// In en, this message translates to:
  /// **'This is a chat bubble sample.\n1234567890'**
  String get generalFontPreviewText;

  /// No description provided for @generalTextScale.
  ///
  /// In en, this message translates to:
  /// **'Text Scale'**
  String get generalTextScale;

  /// No description provided for @generalQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get generalQuickActions;

  /// No description provided for @generalQuickActionsInput.
  ///
  /// In en, this message translates to:
  /// **'Input Area Buttons'**
  String get generalQuickActionsInput;

  /// No description provided for @generalQuickActionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No active buttons'**
  String get generalQuickActionsEmpty;

  /// No description provided for @generalEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get generalEdit;

  /// No description provided for @generalEditQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Edit Quick Actions'**
  String get generalEditQuickActions;

  /// No description provided for @qaAttachImage.
  ///
  /// In en, this message translates to:
  /// **'Attach Image'**
  String get qaAttachImage;

  /// No description provided for @qaCompress.
  ///
  /// In en, this message translates to:
  /// **'Compress Context'**
  String get qaCompress;

  /// No description provided for @qaNewChat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get qaNewChat;

  /// No description provided for @qaMemory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get qaMemory;

  /// No description provided for @qaExpressionToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle Expression'**
  String get qaExpressionToggle;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @generalCharacterModel.
  ///
  /// In en, this message translates to:
  /// **'Character Model'**
  String get generalCharacterModel;

  /// No description provided for @generalManageModels.
  ///
  /// In en, this message translates to:
  /// **'Manage Live2D models'**
  String get generalManageModels;

  /// No description provided for @generalEnableLive2D.
  ///
  /// In en, this message translates to:
  /// **'Enable Live2D'**
  String get generalEnableLive2D;

  /// No description provided for @generalShowLive2D.
  ///
  /// In en, this message translates to:
  /// **'Show Live2D character in chat'**
  String get generalShowLive2D;

  /// No description provided for @generalShowLive2DHome.
  ///
  /// In en, this message translates to:
  /// **'Show Live2D on Home'**
  String get generalShowLive2DHome;

  /// No description provided for @generalShowLive2DHomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show Live2D character in main chat view'**
  String get generalShowLive2DHomeSubtitle;

  /// No description provided for @generalFloatingWindow.
  ///
  /// In en, this message translates to:
  /// **'Floating Window'**
  String get generalFloatingWindow;

  /// No description provided for @generalFloatingWindowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create independent window (OBS compatible)'**
  String get generalFloatingWindowSubtitle;

  /// No description provided for @generalLive2dDebug.
  ///
  /// In en, this message translates to:
  /// **'Live2D Debug'**
  String get generalLive2dDebug;

  /// No description provided for @generalLive2dDebugSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show debug info on Live2D page'**
  String get generalLive2dDebugSubtitle;

  /// No description provided for @generalExpressionSync.
  ///
  /// In en, this message translates to:
  /// **'Expression Sync'**
  String get generalExpressionSync;

  /// No description provided for @generalExpressionIsland.
  ///
  /// In en, this message translates to:
  /// **'Show Expression Island'**
  String get generalExpressionIsland;

  /// No description provided for @generalExpressionIslandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show dynamic expression island (independent of Live2D)'**
  String get generalExpressionIslandSubtitle;

  /// No description provided for @generalVoiceInteraction.
  ///
  /// In en, this message translates to:
  /// **'Voice Interaction'**
  String get generalVoiceInteraction;

  /// No description provided for @generalEnableTts.
  ///
  /// In en, this message translates to:
  /// **'Enable TTS'**
  String get generalEnableTts;

  /// No description provided for @generalEnableTtsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow model to speak responses'**
  String get generalEnableTtsSubtitle;

  /// No description provided for @generalEnableStt.
  ///
  /// In en, this message translates to:
  /// **'Enable STT'**
  String get generalEnableStt;

  /// No description provided for @generalEnableSttSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow voice input'**
  String get generalEnableSttSubtitle;

  /// No description provided for @generalChatMode.
  ///
  /// In en, this message translates to:
  /// **'Chat Mode'**
  String get generalChatMode;

  /// No description provided for @generalChatModePersona.
  ///
  /// In en, this message translates to:
  /// **'Persona'**
  String get generalChatModePersona;

  /// No description provided for @generalChatModePersonaDesc.
  ///
  /// In en, this message translates to:
  /// **'Bubbles, natural conversation'**
  String get generalChatModePersonaDesc;

  /// No description provided for @generalChatModeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get generalChatModeStandard;

  /// No description provided for @generalChatModeStandardDesc.
  ///
  /// In en, this message translates to:
  /// **'Strict Markdown, productivity'**
  String get generalChatModeStandardDesc;

  /// No description provided for @generalRestartOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Restart Onboarding'**
  String get generalRestartOnboarding;

  /// No description provided for @generalRestartOnboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reset assistant persona and system prompt'**
  String get generalRestartOnboardingSubtitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
