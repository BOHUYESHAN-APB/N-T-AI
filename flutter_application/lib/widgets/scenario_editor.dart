import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                '场景与目标配置',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '当前场景说明 (AI 会感知此上下文)',
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contextController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '例如：正在直播玩 Minecraft，有嘉宾“小明”连麦...',
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
              _TemplateChip(
                label: '直播模式',
                onTap: () {
                  setState(() {
                    _contextController.text = '当前正在直播，氛围轻松愉快，多与弹幕互动。';
                    _tasks = ['欢迎新进直播间的观众', '回复有趣的弹幕', '保持直播热度'];
                  });
                  _save();
                },
              ),
              _TemplateChip(
                label: '游戏解说',
                onTap: () {
                  setState(() {
                    _contextController.text = '正在玩游戏，我是解说/助手，观察画面并评论。';
                    _tasks = ['分析当前局势', '吐槽操作失误', '分享游戏小知识'];
                  });
                  _save();
                },
              ),
              _TemplateChip(
                label: '连麦/协作',
                onTap: () {
                  setState(() {
                    _contextController.text = '正在与其他人连麦交流。';
                    _tasks = ['有礼貌地回应他人', '引导话题讨论', '不要抢话'];
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
