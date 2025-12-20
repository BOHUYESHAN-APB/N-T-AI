import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_application/l10n/app_localizations.dart';
import '../../../settings/settings_scope.dart';
import '../../../settings/settings.dart';
import '../../first_run_dialog.dart';
import '../../../core/services/brain_service.dart';
import '../../../core/services/backend_service.dart';
import '../character_manager_screen.dart';

class GeneralTab extends StatelessWidget {
  const GeneralTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final s = controller.settings;
    final l10n = AppLocalizations.of(context)!;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _buildSectionHeader(context, l10n.generalBasicSettings),
        SwitchListTile(
          secondary: const Icon(Icons.link),
          title: Text(l10n.generalAutoConnectBackend),
          subtitle: Text(l10n.generalAutoConnectBackendSubtitle),
          value: s.autoConnectBackend,
          onChanged: (v) => controller.setAutoConnectBackend(v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.play_circle_outline),
          title: Text(l10n.generalAutoStartBackend),
          subtitle: Text(l10n.generalAutoStartBackendSubtitle),
          value: s.autoStartBackend,
          onChanged: (v) => controller.setAutoStartBackend(v),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: Text(l10n.generalBackendStatus),
          subtitle: Text(s.pythonBackendUrl),
          trailing: StreamBuilder<BackendStatus>(
            stream: BackendService().statusStream,
            initialData: BackendService().currentStatus,
            builder: (context, snapshot) {
              final status = snapshot.data ?? BackendStatus.disconnected;
              String text;
              if (!s.enablePythonBackend) {
                text = l10n.backendStatusBackendDisabled;
              } else if (!s.autoConnectBackend) {
                text = l10n.backendStatusAutoConnectOff;
              } else {
                text = switch (status) {
                  BackendStatus.connected => l10n.backendStatusConnected,
                  BackendStatus.initializing => l10n.backendStatusInitializing,
                  BackendStatus.incompatible => l10n.backendStatusIncompatible,
                  BackendStatus.disconnected => l10n.backendStatusDisconnected,
                };
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text),
                  const SizedBox(width: 8),
                  const Icon(Icons.edit_outlined, size: 16),
                ],
              );
            },
          ),
          onTap: () async {
            final ctl = TextEditingController(text: s.pythonBackendUrl);
            final newUrl = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(l10n.generalBackendStatus),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ctl,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: 'http://localhost:23456',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Default: http://localhost:23456\nRemote: http://IP:PORT',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, ctl.text),
                    child: Text(l10n.commonSave),
                  ),
                ],
              ),
            );
            if (newUrl != null && newUrl.isNotEmpty) {
              controller.setPythonBackendUrl(newUrl);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.face),
          title: Text(l10n.generalUserNickname),
          subtitle: Text(
            s.userNickname.isEmpty
                ? l10n.generalNicknameNotSet
                : s.userNickname,
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () async {
            final ctl = TextEditingController(text: s.userNickname);
            final newName = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(l10n.generalSetNickname),
                content: TextField(
                  controller: ctl,
                  decoration: InputDecoration(
                    hintText: l10n.generalNicknameHint,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, ctl.text),
                    child: Text(l10n.commonSave),
                  ),
                ],
              ),
            );
            if (newName != null) {
              controller.setUserNickname(newName);
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(l10n.generalCharacterModel),
          subtitle: Text(l10n.generalManageModels),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CharacterManagerScreen()),
            );
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.animation),
          title: Text(l10n.generalEnableLive2D),
          subtitle: Text(l10n.generalShowLive2D),
          value: s.enableLive2D,
          onChanged: (v) => controller.setEnableLive2D(v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.visibility),
          title: Text(l10n.generalShowLive2DHome),
          subtitle: Text(l10n.generalShowLive2DHomeSubtitle),
          value: s.showLive2D,
          onChanged: s.enableLive2D ? (v) => controller.setShowLive2D(v) : null,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.open_in_new),
          title: Text(l10n.generalFloatingWindow),
          subtitle: Text(l10n.generalFloatingWindowSubtitle),
          value: s.enableFloatingWindow,
          onChanged: s.enableLive2D
              ? (v) => controller.setEnableFloatingWindow(v)
              : null,
        ),
        // Live2D Debug removed as requested
        SwitchListTile(
          secondary: const Icon(Icons.face_retouching_natural),
          title: Text(l10n.generalExpressionIsland),
          subtitle: Text(l10n.generalExpressionIslandSubtitle),
          value: s.showExpressionFace && s.enableExpressionAgent,
          onChanged: (v) {
            controller.setShowExpressionFace(v);
            controller.setEnableExpressionAgent(v);
          },
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(context, l10n.generalVoiceInteraction),
        SwitchListTile(
          secondary: const Icon(Icons.record_voice_over),
          title: Text(l10n.generalEnableTts),
          subtitle: Text(l10n.generalEnableTtsSubtitle),
          value: s.enableTts,
          onChanged: (v) => controller.setEnableTts(v),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.hearing),
          title: Text(l10n.generalEnableStt),
          subtitle: Text(l10n.generalEnableSttSubtitle),
          value: s.enableStt,
          onChanged: (v) => controller.setEnableStt(v),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(context, l10n.generalAppearance),
        ListTile(
          title: Text(l10n.generalLanguage),
          trailing: DropdownButton<LocaleOption>(
            value: s.locale,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setLocale(v);
            },
            items: [
              DropdownMenuItem(
                value: LocaleOption.system,
                child: Text(l10n.generalThemeSystem),
              ),
              const DropdownMenuItem(
                value: LocaleOption.zh,
                child: Text('简体中文'),
              ),
              const DropdownMenuItem(
                value: LocaleOption.en,
                child: Text('English'),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(l10n.generalTheme),
          trailing: DropdownButton<ThemeModeOption>(
            value: s.themeMode,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setThemeMode(v);
            },
            items: [
              DropdownMenuItem(
                value: ThemeModeOption.system,
                child: Text(l10n.generalThemeSystem),
              ),
              DropdownMenuItem(
                value: ThemeModeOption.light,
                child: Text(l10n.generalThemeLight),
              ),
              DropdownMenuItem(
                value: ThemeModeOption.dark,
                child: Text(l10n.generalThemeDark),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(l10n.generalPalette),
          trailing: DropdownButton<PaletteOption>(
            value: s.palette,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setPalette(v);
            },
            items: [
              DropdownMenuItem(
                value: PaletteOption.neutral,
                child: Text(l10n.generalPaletteNeutral),
              ),
              DropdownMenuItem(
                value: PaletteOption.green,
                child: Text(l10n.generalPaletteGreen),
              ),
              DropdownMenuItem(
                value: PaletteOption.blue,
                child: Text(l10n.generalPaletteBlue),
              ),
              DropdownMenuItem(
                value: PaletteOption.orange,
                child: Text(l10n.generalPaletteOrange),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(l10n.generalUiMode),
          trailing: DropdownButton<UIModeOption>(
            value: s.uiMode,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setUiMode(v);
            },
            items: [
              DropdownMenuItem(
                value: UIModeOption.auto,
                child: Text(l10n.generalUiModeAuto),
              ),
              DropdownMenuItem(
                value: UIModeOption.bubble,
                child: Text(l10n.generalUiModeBubble),
              ),
              DropdownMenuItem(
                value: UIModeOption.simple,
                child: Text(l10n.generalUiModeSimple),
              ),
            ],
          ),
        ),
        ListTile(
            title: const Text('聊天模式 (Chat Mode)'),
            subtitle: Text(
              s.chatMode == ChatModeOption.persona
                  ? '拟人 (Persona) - 分段气泡，自然对话'
                  : '标准 (Standard) - 严格Markdown，生产力',
            ),
            trailing: DropdownButton<ChatModeOption>(
              value: s.chatMode,
              underline: const SizedBox(),
              onChanged: (v) {
                if (v != null) controller.setChatMode(v);
              },
              items: const [
                DropdownMenuItem(
                  value: ChatModeOption.persona,
                  child: Text('拟人 (Persona)'),
                ),
                DropdownMenuItem(
                  value: ChatModeOption.standard,
                  child: Text('标准 (Standard)'),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('人格深度 (Persona Level)'),
            subtitle: Text(
              s.personaLevel == PersonaLevelOption.basic
                  ? '基础 (Basic) - 仅设定身份'
                  : s.personaLevel == PersonaLevelOption.advanced
                      ? '进阶 (Advanced) - 包含性格与记忆'
                      : '完整 (Full) - 包含完整数字生命设定与交互',
            ),
            trailing: DropdownButton<PersonaLevelOption>(
              value: s.personaLevel,
              underline: const SizedBox(),
              onChanged: (v) {
                if (v != null) controller.setPersonaLevel(v);
              },
              items: const [
                DropdownMenuItem(
                  value: PersonaLevelOption.basic,
                  child: Text('基础 (Basic)'),
                ),
                DropdownMenuItem(
                  value: PersonaLevelOption.advanced,
                  child: Text('进阶 (Advanced)'),
                ),
                DropdownMenuItem(
                  value: PersonaLevelOption.full,
                  child: Text('完整 (Full)'),
                ),
              ],
            ),
          ),
          ListTile(
          title: Text(l10n.generalChatBg),
          trailing: DropdownButton<ChatBgOption>(
            value: s.chatBg,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setChatBg(v);
            },
            items: [
              DropdownMenuItem(
                value: ChatBgOption.none,
                child: Text(l10n.generalChatBgNone),
              ),
              DropdownMenuItem(
                value: ChatBgOption.lavender,
                child: Text(l10n.generalChatBgLavender),
              ),
            ],
          ),
        ),
        ListTile(
          title: const Text('用户气泡颜色 (User Bubble)'),
          trailing: _ColorCircle(
            color: s.userBubbleColor != null
                ? Color(s.userBubbleColor!)
                : Theme.of(context).colorScheme.primary,
            onTap: () => _showColorPicker(
              context,
              s.userBubbleColor,
              (c) => controller.setUserBubbleColor(c?.value),
            ),
          ),
        ),
        ListTile(
          title: const Text('AI 气泡颜色 (AI Bubble)'),
          trailing: _ColorCircle(
            color: s.aiBubbleColor != null
                ? Color(s.aiBubbleColor!)
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            onTap: () => _showColorPicker(
              context,
              s.aiBubbleColor,
              (c) => controller.setAiBubbleColor(c?.value),
            ),
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(context, l10n.generalFontSettings),
        ListTile(
          title: Text(l10n.generalBaseFont),
          trailing: DropdownButton<BaseFontModeOption>(
            value: s.baseFontMode,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setBaseFontMode(v);
            },
            items: [
              DropdownMenuItem(
                value: BaseFontModeOption.system,
                child: Text(l10n.generalBaseFontSystem),
              ),
              DropdownMenuItem(
                value: BaseFontModeOption.miSansPreferred,
                child: Text(l10n.generalBaseFontMiSans),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(l10n.generalDecoFont),
          trailing: DropdownButton<DecorativeFontFamily>(
            value: s.decoFamily,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setDecoFamily(v);
            },
            items: [
              DropdownMenuItem(
                value: DecorativeFontFamily.none,
                child: Text(l10n.generalDecoFontNone),
              ),
              const DropdownMenuItem(
                value: DecorativeFontFamily.fzg,
                child: Text('FZG'),
              ),
              const DropdownMenuItem(
                value: DecorativeFontFamily.nfdcs,
                child: Text('nfdcs'),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: Text(l10n.generalDecoUseTitles),
          value: s.decoUseTitles,
          onChanged: (v) => controller.setDecoUseTitles(v),
        ),
        SwitchListTile(
          title: Text(l10n.generalDecoUseBubbles),
          value: s.decoUseBubbles,
          onChanged: (v) => controller.setDecoUseBubbles(v),
        ),

        // Font Preview Area
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Card(
            elevation: 0,
            color: Theme.of(
              context,
            ).colorScheme.surfaceVariant.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.preview,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.generalFontPreview,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.generalFontPreviewTitle,
                    style: TextStyle(
                      fontSize: 20 * s.textScale,
                      fontWeight: FontWeight.bold,
                      fontFamily:
                          s.decoUseTitles &&
                              s.decoFamily != DecorativeFontFamily.none
                          ? (s.decoFamily == DecorativeFontFamily.fzg
                                ? 'FZG'
                                : 'NFDCS')
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomRight: const Radius.circular(12),
                        bottomLeft: Radius.circular(
                          s.uiMode == UIModeOption.bubble ? 2 : 12,
                        ),
                      ),
                    ),
                    child: Text(
                      l10n.generalFontPreviewText,
                      style: TextStyle(
                        fontSize: 16 * s.textScale,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontFamily:
                            s.decoUseBubbles &&
                                s.decoFamily != DecorativeFontFamily.none
                            ? (s.decoFamily == DecorativeFontFamily.fzg
                                  ? 'FZG'
                                  : 'NFDCS')
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        ListTile(
          title: Text(l10n.generalTextScale),
          subtitle: Slider(
            value: s.textScale,
            min: 0.9,
            max: 1.4,
            divisions: 10,
            label: s.textScale.toStringAsFixed(2),
            onChanged: (v) => controller.setTextScale(v),
          ),
          trailing: Text(s.textScale.toStringAsFixed(2)),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(context, l10n.generalQuickActions),
        ListTile(
          title: Text(l10n.generalQuickActionsInput),
          subtitle: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in s.quickActions)
                Chip(
                  label: Text(_getQuickActionLabel(id, l10n)),
                  avatar: Icon(_getQuickActionIcon(id), size: 16),
                ),
              if (s.quickActions.isEmpty)
                Text(
                  l10n.generalQuickActionsEmpty,
                  style: const TextStyle(fontSize: 12),
                ),
            ],
          ),
          trailing: FilledButton.tonal(
            onPressed: () => _showQuickActionsDialog(context, controller),
            child: Text(l10n.generalEdit),
          ),
        ),

        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Persona & Onboarding'),
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: const Text('Restart Onboarding Wizard / 重新运行向导'),
          subtitle: const Text('Reset assistant persona and system prompt'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => FirstRunDialog(
                settingsController: controller,
                brain: BrainService(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  String _getQuickActionLabel(String id, AppLocalizations l10n) {
    return switch (id) {
      'attach_image' => l10n.qaAttachImage,
      'compress' => l10n.qaCompress,
      'new_chat' => l10n.qaNewChat,
      'memory' => l10n.qaMemory,
      'expression_toggle' => l10n.qaExpressionToggle,
      _ => id,
    };
  }

  IconData _getQuickActionIcon(String id) {
    return switch (id) {
      'attach_image' => Icons.image_outlined,
      'compress' => Icons.cleaning_services_outlined,
      'new_chat' => Icons.add_comment_outlined,
      'memory' => Icons.memory,
      'expression_toggle' => Icons.emoji_emotions_outlined,
      _ => Icons.extension,
    };
  }

  void _showQuickActionsDialog(BuildContext context, dynamic controller) {
    final s = controller.settings;
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) {
        final all = [
          'attach_image',
          'compress',
          'new_chat',
          'memory',
          'expression_toggle',
        ];
        final selected = List<String>.from(s.quickActions);
        return StatefulBuilder(
          builder: (ctx2, setStateDialog) => AlertDialog(
            title: Text(l10n.generalEditQuickActions),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final id in all)
                      CheckboxListTile(
                        value: selected.contains(id),
                        title: Text(_getQuickActionLabel(id, l10n)),
                        dense: true,
                        onChanged: (v) {
                          setStateDialog(() {
                            if (v == true && !selected.contains(id)) {
                              selected.add(id);
                            } else if (v == false) {
                              selected.remove(id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  controller.setQuickActions(selected);
                  Navigator.pop(ctx);
                },
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ColorCircle extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ColorCircle({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showColorPicker(
  BuildContext context,
  int? currentColorValue,
  Function(Color?) onColorSelected,
) async {
  final colors = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey,
    Colors.black,
    Colors.white,
  ];

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('选择颜色'),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
             GestureDetector(
              onTap: () {
                onColorSelected(null); // Reset to default
                Navigator.pop(ctx);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey),
                ),
                child: const Icon(Icons.format_color_reset, size: 20),
              ),
            ),
            ...colors.map(
              (c) => GestureDetector(
                onTap: () {
                  onColorSelected(c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: currentColorValue == c.value
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
