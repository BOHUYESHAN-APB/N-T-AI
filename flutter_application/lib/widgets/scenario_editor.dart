import 'package:flutter/material.dart';
import '../settings/settings.dart';
import '../settings/settings_scope.dart';

class ScenarioEditor extends StatefulWidget {
  const ScenarioEditor({super.key});

  @override
  State<ScenarioEditor> createState() => _ScenarioEditorState();
}

class _ScenarioEditorState extends State<ScenarioEditor> {
  late TextEditingController _contextController;
  late List<String> _tasks;
  final TextEditingController _newTaskController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = SettingsScope.of(context).settings;
    _contextController = TextEditingController(text: settings.scenarioContext);
    _tasks = List.from(settings.scenarioTasks);
  }

  @override
  void dispose() {
    _contextController.dispose();
    _newTaskController.dispose();
    super.dispose();
  }

  void _save() {
    final controller = SettingsScope.of(context);
    controller.setScenarioContext(_contextController.text);
    controller.setScenarioTasks(_tasks);
  }

  String _modeLabel(AppSettings settings) {
    if (settings.primaryMode == PrimaryModeOption.assistant) {
      return '助理模式';
    }
    return switch (settings.liveMode) {
      LiveModeOption.watch => '直播：你玩、AI看',
      LiveModeOption.coPlay => '直播：你玩+AI玩',
      LiveModeOption.autoPlay => '直播：AI玩、你看',
    };
  }

  String _modeHint(AppSettings settings) {
    if (settings.primaryMode == PrimaryModeOption.assistant) {
      return '以个人助理为主，偏任务/攻略/聊天，可记录用户偏好。';
    }
    return switch (settings.liveMode) {
      LiveModeOption.watch => '只解说与搞效果，不参与操作。',
      LiveModeOption.coPlay => '解说+互动，强化人格效果。',
      LiveModeOption.autoPlay => '自主任务模式，人工少干预。',
    };
  }

  List<_TemplateItem> _buildTemplates(AppSettings settings) {
    if (settings.primaryMode == PrimaryModeOption.assistant) {
      return const [
        _TemplateItem(
          label: '游戏攻略/助手',
          context: '正在玩游戏，需要攻略、提示与解说，风格简洁实用。',
          tasks: ['给出关键提示', '指出可优化操作', '不要打断用户'],
        ),
        _TemplateItem(
          label: '轻松闲聊',
          context: '当前是轻松聊天，语气自然但不过度表演。',
          tasks: ['保持简短', '避免夸张表演', '可补充有趣知识'],
        ),
      ];
    }

    return const [
      _TemplateItem(
        label: '直播：你玩AI看',
        context: '当前在直播，由玩家操作，AI只解说与搞效果。',
        tasks: ['简洁解说', '适当吐槽', '不主动指挥操作'],
      ),
      _TemplateItem(
        label: '直播：你玩+AI玩',
        context: '当前在直播，AI参与互动与部分操作，需强化人格。',
        tasks: ['解说自己在做的事', '与观众互动', '保持节目效果'],
      ),
      _TemplateItem(
        label: '直播：AI玩你看',
        context: '当前在直播，AI自主规划任务并执行，观众为主。',
        tasks: ['保持任务进度', '适当节目效果', '必要时自检纠错'],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = SettingsScope.of(context).settings;
    final templates = _buildTemplates(settings);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '情况说明与目标配置',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  settings.primaryMode == PrimaryModeOption.assistant
                      ? Icons.support_agent_outlined
                      : Icons.live_tv_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _modeLabel(settings),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _modeHint(settings),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '当前情况说明 (AI 会感知此上下文)',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contextController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: settings.primaryMode == PrimaryModeOption.assistant
                  ? '例如：正在玩 Minecraft，需要攻略和提示...'
                  : '例如：正在直播玩 Minecraft，有观众互动...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
            ),
            onChanged: (_) => _save(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '待办任务 / 目标 (TodoList)',
                style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
              ),
              Text(
                '${_tasks.length} 项',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '• ${_tasks[index]}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          setState(() => _tasks.removeAt(index));
                          _save();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTaskController,
                  decoration: InputDecoration(
                    hintText: '添加新任务...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      setState(() => _tasks.add(val.trim()));
                      _newTaskController.clear();
                      _save();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () {
                  if (_newTaskController.text.trim().isNotEmpty) {
                    setState(() => _tasks.add(_newTaskController.text.trim()));
                    _newTaskController.clear();
                    _save();
                  }
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Templates
          Text(
            '快捷模板',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in templates)
                _TemplateChip(
                  label: t.label,
                  onTap: () {
                    setState(() {
                      _contextController.text = t.context;
                      _tasks = List.from(t.tasks);
                    });
                    _save();
                  },
                ),
              _TemplateChip(
                label: '清空状态',
                onTap: () {
                  setState(() {
                    _contextController.clear();
                    _tasks.clear();
                  });
                  _save();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _TemplateChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _TemplateChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _TemplateItem {
  final String label;
  final String context;
  final List<String> tasks;

  const _TemplateItem({
    required this.label,
    required this.context,
    required this.tasks,
  });
}
