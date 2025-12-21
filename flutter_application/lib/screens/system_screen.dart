import 'dart:math';
import 'package:flutter/material.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';
import 'about_screen.dart';
import 'memory_manager_screen.dart';
import 'agents_screen.dart';
import 'tools_configuration_screen.dart';
import 'package:file_picker/file_picker.dart';
import '../core/services/llm_service.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({Key? key}) : super(key: key);

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  String? _selectedId;
  // Persist editors to avoid losing unsaved text on rebuilds
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _baseCtl = TextEditingController();
  final TextEditingController _keyCtl = TextEditingController();
  final TextEditingController _modelCtl = TextEditingController();
  String? _lastForProvider;

  void _syncControllersFrom(AiProviderConfig cfg) {
    _nameCtl.text = cfg.name;
    _baseCtl.text = cfg.baseUrl;
    _keyCtl.text = cfg.apiKey;
    _modelCtl.text = cfg.model;
    _lastForProvider = cfg.id;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = SettingsScope.of(context);
    final providers = ctrl.providers;
    if (_selectedId == null && providers.isNotEmpty) {
      _selectedId = ctrl.activeProviderId ?? providers.first.id;
      final cfg = providers.firstWhere((p) => p.id == _selectedId, orElse: () => providers.first);
      _syncControllersFrom(cfg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final providers = controller.providers;
    final width = MediaQuery.of(context).size.width;

    Widget leftList() {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // Agent Cluster Configuration Section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Agent 集群配置', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            elevation: controller.settings.agentEnabled ? 2 : 0,
            color: controller.settings.agentEnabled ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3) : null,
            child: SwitchListTile(
              secondary: Icon(Icons.auto_awesome, color: controller.settings.agentEnabled ? Theme.of(context).colorScheme.primary : null),
              title: const Text('启用 Agent 模式', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('开启后 Firefly 将具备自主思考、视觉识别与工具调用能力'),
              value: controller.settings.agentEnabled,
              onChanged: (v) => controller.setAgentEnabled(v),
            ),
          ),
          // Expression & Emotion Section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('表情与情绪推理', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.emoji_emotions_outlined),
                  title: const Text('启用表情 Agent 调用'),
                  subtitle: const Text('单独调用轻量模型或关键词推理出表情，不占主脑上下文'),
                  value: controller.settings.enableExpressionAgent,
                  onChanged: (v) => controller.setEnableExpressionAgent(v),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.face_retouching_natural_outlined),
                  title: const Text('显示动态表情（灵动岛）'),
                  value: controller.settings.showExpressionFace,
                  onChanged: (v) => controller.setShowExpressionFace(v),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      const Text('推理模型：'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: controller.settings.activeExpressionProviderId ?? 'follow_main',
                          items: [
                            const DropdownMenuItem(value: 'follow_main', child: Text('跟随主脑（共享模型）')),
                            for (final p in providers) DropdownMenuItem(value: p.id, child: Text('${p.name} · ${p.model.isEmpty ? '未配置模型' : p.model}')),
                          ],
                          onChanged: (v) async {
                            if (v == null) return;
                            if (v == 'follow_main') {
                              await controller.setActiveExpressionProvider(null);
                            } else {
                              await controller.setActiveExpressionProvider(v);
                            }
                            if (!mounted) return; setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.25)),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: const Text(
                      '架构说明：主脑生成完整回复后，独立“表情推理”层以关键词或轻量模型二次分析情绪（愉悦/思考/关怀等），再由渲染层驱动画面。这样可避免在主脑提示中插入 JSON，降低 Token 成本。建议选择 7B~8B 或 mini 系列模型。',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.psychology),
            title: const Text('主脑 (Main Brain)'),
            subtitle: Text(providers.firstWhere((p) => p.id == controller.activeProviderId, orElse: () => providers.first).name),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请在下方列表选择一个平台作为主脑')));
            },
          ),
          ListTile(
            leading: Icon(Icons.visibility, color: controller.settings.agentEnabled ? null : Colors.grey),
            title: Text('视觉中枢 (Vision)', style: TextStyle(color: controller.settings.agentEnabled ? null : Colors.grey)),
            subtitle: Text('跟随主脑 (默认)', style: TextStyle(color: controller.settings.agentEnabled ? null : Colors.grey)),
            trailing: const Icon(Icons.chevron_right),
            enabled: controller.settings.agentEnabled,
            onTap: () {
              if (controller.settings.agentEnabled) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('高级集群功能开发中...')));
              }
            },
          ),
          ListTile(
            leading: Icon(Icons.construction, color: controller.settings.agentEnabled ? null : Colors.grey),
            title: Text('工具箱 (Tools)', style: TextStyle(color: controller.settings.agentEnabled ? null : Colors.grey)),
            subtitle: Text(
              controller.settings.agentEnabled 
                ? '已启用: ${controller.settings.enableBrowser ? "Browser" : ""} ${controller.settings.mcpServers.where((e) => e.enabled).length} MCP'
                : '已禁用',
              style: TextStyle(color: controller.settings.agentEnabled ? null : Colors.grey)
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: controller.settings.agentEnabled,
            onTap: () {
              if (controller.settings.agentEnabled) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ToolsConfigurationScreen()));
              }
            },
          ),
          SwitchListTile(
            secondary: Icon(Icons.visibility_outlined, color: controller.settings.agentEnabled ? null : Colors.grey),
            title: Text('显示思考过程', style: TextStyle(color: controller.settings.agentEnabled ? null : Colors.grey)),
            subtitle: Text('在对话框上方显示 Agent 的实时状态', style: TextStyle(color: controller.settings.agentEnabled ? null : Colors.grey)),
            value: controller.settings.showAgentThoughts,
            onChanged: controller.settings.agentEnabled ? (v) => controller.setAgentShowThoughts(v) : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.voice_over_off),
            title: const Text('禁用心里描写'),
            subtitle: const Text('不显示括号内旁白/动作，并提示主脑不要输出'),
            value: controller.settings.suppressInnerMonologue,
            onChanged: (v) => controller.setSuppressInnerMonologue(v),
          ),
          
          const Divider(),
          // Vision configuration
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('视觉（多模态）配置', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vision Source selection
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 8, children: [
                    const Text('视觉来源：'),
                    DropdownButton<String>(
                      value: controller.settings.activeVisionProviderId ?? 'follow_main',
                      items: [
                        const DropdownMenuItem(value: 'follow_main', child: Text('跟随主脑（优先使用主脑视觉）')),
                        for (final p in providers) DropdownMenuItem(value: p.id, child: Text('专用：${p.name}')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        if (v == 'follow_main') {
                          await controller.setActiveVisionProvider(null);
                        } else {
                          await controller.setActiveVisionProvider(v);
                        }
                        if (!mounted) return; setState(() {});
                      },
                    ),
                  ]),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('主脑具备视觉优先使用：'),
                        const SizedBox(width: 6),
                        Switch(value: controller.settings.useMainVisionIfCapable, onChanged: (v) => controller.setUseMainVisionIfCapable(v)),
                      ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('无视觉时自动走 Agent：'),
                        const SizedBox(width: 6),
                        Switch(value: controller.settings.visionFallbackToAgent, onChanged: (v) => controller.setVisionFallbackToAgent(v)),
                      ]),
                    ],
                  ),
                  const Divider(),
                  TextField(
                    controller: TextEditingController(text: controller.settings.visionPromptTemplate),
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: '默认视觉提示词（用于无用户提示时）',
                      hintText: '用于视觉模型的默认说明，例如一段话描述图片、中文、不要分点、纯文本等',
                    ),
                    onSubmitted: (v) => controller.setVisionPromptTemplate(v.trim()),
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('建议字数：${controller.settings.visionPreferredLength}'),
                          Slider(
                            value: controller.settings.visionPreferredLength.toDouble(),
                            min: 60,
                            max: 200,
                            divisions: 14,
                            label: controller.settings.visionPreferredLength.toString(),
                            onChanged: (v) => controller.setVisionPreferredLength(v.round()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('最大字数：${controller.settings.visionMaxLength}'),
                          Slider(
                            value: controller.settings.visionMaxLength.toDouble(),
                            min: 200,
                            max: 500,
                            divisions: 6,
                            label: controller.settings.visionMaxLength.toString(),
                            onChanged: (v) => controller.setVisionMaxLength(v.round()),
                          ),
                        ],
                      ),
                    ),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonal(
                      onPressed: () async {
                        final picker = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
                        if (picker == null || picker.files.first.bytes == null) return;
                        final bytes = picker.files.first.bytes!;
                        final llm = LLMService();
                        final s = controller.settings;
                        final hint = '${s.visionPromptTemplate}\n长度建议约${s.visionPreferredLength}字，最多${s.visionMaxLength}字。';
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final result = await llm.chatWithImage(
                            messages: const [ {'role':'system','content':'你是一个擅长中文描述的图像助手。'} ],
                            imageBytes: bytes,
                            prompt: hint,
                            usageType: 'tool',
                            providerIdOverride: controller.settings.activeVisionProviderId,
                          );
                          if (!mounted) return;
                          showDialog(context: context, builder: (ctx) => AlertDialog(
                            title: const Text('视觉测试结果'),
                            content: SingleChildScrollView(child: Text(result)),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))],
                          ));
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(content: Text('视觉测试失败：$e')));
                        }
                      },
                      child: const Text('测试视觉'),
                    ),
                  )
                ],
              ),
            ),
          ),
          const Divider(),
          
          // Memory Management Section
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('记忆数据库'),
            subtitle: const Text('管理 Firefly 的长期记忆'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MemoryManagerScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_remote),
            title: const Text('Agent 管理'),
            subtitle: const Text('管理独立的 Agent（表情/视觉/自定义）配置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AgentsScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.face),
            title: const Text('用户昵称'),
            subtitle: Text(controller.settings.userNickname.isEmpty ? '未设置 (Firefly 将自行决定)' : controller.settings.userNickname),
            onTap: () async {
              final ctl = TextEditingController(text: controller.settings.userNickname);
              final newName = await showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('设置昵称'),
                  content: TextField(
                    controller: ctl,
                    decoration: const InputDecoration(hintText: '例如：主人、哥哥、姐姐...'),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(context, ctl.text), child: const Text('保存')),
                  ],
                ),
              );
              if (newName != null) {
                controller.setUserNickname(newName);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.psychology_alt),
            title: const Text('记忆学习率'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前: ${(controller.settings.learningProbability * 100).toInt()}%'),
                Slider(
                  value: controller.settings.learningProbability,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: '${(controller.settings.learningProbability * 100).toInt()}%',
                  onChanged: (v) => controller.setLearningProbability(v),
                ),
              ],
            ),
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('AI 服务商列表', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          for (final p in providers)
            ListTile(
              selected: p.id == _selectedId,
              leading: Icon(p.kind == AiProvider.local ? Icons.computer : Icons.cloud_outlined),
              title: Text(p.name),
              subtitle: Text(p.kind.name + (p.enabled ? '' : ' (禁用)')),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                      title: const Text('删除平台'),
                      content: Text('删除后将无法使用该平台配置，确定删除 ${p.name} ?'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除'))],
                    ));
                    if (ok == true) {
                      await controller.removeProvider(p.id);
                      if (!mounted) return;
                      setState(() {
                        final all = controller.providers;
                        _selectedId = all.isNotEmpty ? all.first.id : null;
                      });
                    }
                  },
                ),
                Switch(value: p.enabled, onChanged: (v) => controller.setProviderEnabled(p.id, v)),
              ]),
              onTap: () {
                setState(() {
                  _selectedId = p.id;
                  final cfg = providers.firstWhere((e) => e.id == p.id, orElse: () => providers.first);
                  _syncControllersFrom(cfg);
                });
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('添加平台'),
            onTap: () async {
              final id = 'p_${DateTime.now().millisecondsSinceEpoch}';
              final newP = AiProviderConfig(id: id, name: '新平台', kind: AiProvider.custom, enabled: true);
              await controller.addOrUpdateProvider(newP);
              if (!mounted) return;
              setState(() => _selectedId = id);
            },
          )
        ],
      );
    }

    List<String> _suggestionsFor(AiProvider kind) {
      switch (kind) {
        case AiProvider.openai:
          return const [
            'gpt-4o', 'gpt-4o-mini', 'o4-mini', 'gpt-4.1-mini', 'text-embedding-3-small'
          ];
        case AiProvider.local:
          return const [
            'llama-3.1-8b-instruct', 'llama-3.1-70b-instruct', 'qwen2.5-7b-instruct', 'mistral-7b-instruct', 'phi-3.1-mini'
          ];
        case AiProvider.custom:
          return const [
            'deepseek-chat', 'deepseek-reasoner', 'glm-4', 'glm-4-air', 'glm-4-flash', 'openrouter/auto', 'mixtral-8x7b-32768', 'llama-3.1-70b-versatile'
          ];
      }
    }

    Widget rightPanel() {
      if (_selectedId == null) return const Center(child: Text('请先添加或选择一个平台'));
      final cfg = providers.firstWhere((p) => p.id == _selectedId, orElse: () => providers.first);
      if (_lastForProvider != cfg.id) {
        // Selection changed from outside; sync once.
        _syncControllersFrom(cfg);
      }
      // final rpmCtl = TextEditingController(text: cfg.rpm == null ? '' : cfg.rpm.toString());

      final modelOptions = {
        ...{for (final s in _suggestionsFor(cfg.kind)) s: true}.keys,
        // ...?cfg.modelCatalog,
      }.toList();

      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('平台：${cfg.name}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Row(children: [
                  Row(children: [
                    const Text('启用轮换'),
                    const SizedBox(width: 6),
                    Switch(value: controller.rotationEnabled, onChanged: (v) => controller.setRotationEnabled(v)),
                  ]),
                  const SizedBox(width: 12),
                  FilledButton(onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      final msg = await controller.testProvider(cfg.id);
                      if (!mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text(msg)));
                    } catch (e) {
                      if (!mounted) return;
                      messenger.showSnackBar(SnackBar(content: Text('测试失败: $e')));
                    }
                  }, child: const Text('测试连接'))
                ])
              ]),
              const SizedBox(height: 12),
              TextField(controller: _nameCtl, decoration: const InputDecoration(labelText: '显示名称')),
              const SizedBox(height: 8),
              DropdownButton<AiProvider>(value: cfg.kind, onChanged: (v) async {
                if (v == null) return;
                await controller.addOrUpdateProvider(cfg.copyWith(kind: v));
                if (!mounted) return;
                setState(() {});
              }, items: const [
                DropdownMenuItem(value: AiProvider.local, child: Text('本地/离线')),
                DropdownMenuItem(value: AiProvider.openai, child: Text('OpenAI')),
                DropdownMenuItem(value: AiProvider.custom, child: Text('自定义（兼容 OpenAI 风格）')),
              ],),
              const SizedBox(height: 8),
              TextField(controller: _baseCtl, decoration: const InputDecoration(labelText: 'Base URL（可选）'), onSubmitted: (v) => controller.setProviderField(cfg.id, baseUrl: v)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                const Text('Base URL 是根路径'),
                Switch(value: cfg.isRoot, onChanged: (v) async { await controller.addOrUpdateProvider(cfg.copyWith(isRoot: v)); if (!mounted) return; setState(() {}); }),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: const Text('开启：视为 .../v1 或 .../v4，将自动追加 /chat/completions；关闭：视为完整接口路径'),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _keyCtl, decoration: const InputDecoration(labelText: 'API Key（可选）'), obscureText: true, onSubmitted: (v) => controller.setProviderField(cfg.id, apiKey: v)),
              const SizedBox(height: 8),
              // 模型下拉（建议 + 已获取）
              if (modelOptions.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: modelOptions.contains(cfg.model) && cfg.model.isNotEmpty ? cfg.model : null,
                  decoration: const InputDecoration(labelText: '模型（建议/已获取）'),
                  isExpanded: true,
                  items: [
                    for (final m in modelOptions) DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    _modelCtl.text = v;
                    await controller.setProviderField(cfg.id, model: v);
                    if (!mounted) return; setState(() {});
                  },
                ),
                const SizedBox(height: 8),
              ],
              TextField(controller: _modelCtl, decoration: const InputDecoration(labelText: '默认模型（可手填覆盖）'), onSubmitted: (v) => controller.setProviderField(cfg.id, model: v)),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton.tonal(onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    // final models = await controller.fetchModelsForProvider(cfg.id);
                    if (!mounted) return;
                    messenger.showSnackBar(const SnackBar(content: Text('获取模型功能暂未适配新结构')));
                    setState(() {});
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('获取模型失败: $e')));
                  }
                }, child: const Text('获取模型')),
                const SizedBox(width: 12),
                const Text('加入轮换'),
                const SizedBox(width: 6),
                Switch(value: cfg.enabled, onChanged: (v) async { await controller.setProviderEnabled(cfg.id, v); if (!mounted) return; setState(() {}); }),
                const SizedBox(width: 12),
                // SizedBox(
                //   width: 160,
                //   child: TextField(
                //     controller: rpmCtl,
                //     keyboardType: TextInputType.number,
                //     decoration: const InputDecoration(labelText: '每分钟请求上限 (RPM)'),
                //     onSubmitted: (v) {
                //       final n = int.tryParse(v.trim());
                //       controller.setProviderRpm(cfg.id, n);
                //     },
                //   ),
                // ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.tonal(onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await controller.addOrUpdateProvider(cfg.copyWith(name: _nameCtl.text.trim(), baseUrl: _baseCtl.text.trim(), apiKey: _keyCtl.text.trim(), model: _modelCtl.text.trim()));
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(content: Text('已保存')));
                }, child: const Text('保存')),
                const SizedBox(width: 12),
                FilledButton(onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await controller.setActiveProvider(cfg.id);
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(content: Text('设为当前')));
                }, child: const Text('设为当前')),
              ])
            ],
          ),
      );
    }

    Widget appearancePanel() {
      final s = controller.settings;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.palette_outlined),
              title: Text('外观与主题', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
            Row(children: [
              const SizedBox(width: 16),
              const Text('主题模式：'),
              const SizedBox(width: 8),
              DropdownButton<ThemeModeOption>(
                value: s.themeMode,
                onChanged: (v) {
                  if (v != null) controller.setThemeMode(v);
                },
                items: const [
                  DropdownMenuItem(value: ThemeModeOption.system, child: Text('跟随系统')),
                  DropdownMenuItem(value: ThemeModeOption.light, child: Text('浅色')),
                  DropdownMenuItem(value: ThemeModeOption.dark, child: Text('深色')),
                ],
              ),
              const SizedBox(width: 24),
              const Text('配色方案：'),
              const SizedBox(width: 8),
              DropdownButton<PaletteOption>(
                value: s.palette,
                onChanged: (v) {
                  if (v != null) controller.setPalette(v);
                },
                items: const [
                  DropdownMenuItem(value: PaletteOption.neutral, child: Text('简约（白/黑）')),
                  DropdownMenuItem(value: PaletteOption.green, child: Text('绿色系')),
                  DropdownMenuItem(value: PaletteOption.blue, child: Text('蓝色系')),
                  DropdownMenuItem(value: PaletteOption.orange, child: Text('橙色系')),
                ],
              ),
              const SizedBox(width: 24),
              const Text('对话界面：'),
              const SizedBox(width: 8),
              DropdownButton<UIModeOption>(
                value: s.uiMode,
                onChanged: (v) {
                  if (v != null) controller.setUiMode(v);
                },
                items: const [
                  DropdownMenuItem(value: UIModeOption.auto, child: Text('自动')),
                  DropdownMenuItem(value: UIModeOption.bubble, child: Text('气泡（更美观）')),
                  DropdownMenuItem(value: UIModeOption.simple, child: Text('简洁（更省资源）')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                const Text('聊天背景：'),
                const SizedBox(width: 8),
                DropdownButton<ChatBgOption>(
                  value: s.chatBg,
                  onChanged: (v) {
                    if (v != null) controller.setChatBg(v);
                  },
                  items: const [
                    DropdownMenuItem(value: ChatBgOption.none, child: Text('纯色/无')),
                    DropdownMenuItem(value: ChatBgOption.lavender, child: Text('淡灰渐变')),
                  ],
                ),
              ]),
            ),
              const Divider(height: 24),
              const ListTile(
                leading: Icon(Icons.font_download_outlined),
                title: Text('字体与字号', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('基础字体：'),
                      const SizedBox(width: 8),
                      DropdownButton<BaseFontModeOption>(
                        value: s.baseFontMode,
                        onChanged: (v) {
                          if (v != null) controller.setBaseFontMode(v);
                        },
                        items: const [
                          DropdownMenuItem(value: BaseFontModeOption.system, child: Text('跟随系统')),
                          DropdownMenuItem(value: BaseFontModeOption.miSansPreferred, child: Text('优先 MiSans（全局默认）')),
                        ],
                      ),
                      const SizedBox(width: 24),
                      const Text('装饰字体：'),
                      const SizedBox(width: 8),
                      DropdownButton<DecorativeFontFamily>(
                        value: s.decoFamily,
                        onChanged: (v) {
                          if (v != null) controller.setDecoFamily(v);
                        },
                        items: const [
                          DropdownMenuItem(value: DecorativeFontFamily.none, child: Text('无')),
                          DropdownMenuItem(value: DecorativeFontFamily.fzg, child: Text('FZG')),
                          DropdownMenuItem(value: DecorativeFontFamily.nfdcs, child: Text('nfdcs')),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('装饰字体作用域：'),
                      const SizedBox(width: 8),
                      Row(children: [
                        const Text('标题'),
                        const SizedBox(width: 6),
                        Switch(value: s.decoUseTitles, onChanged: (v) => controller.setDecoUseTitles(v)),
                      ]),
                      const SizedBox(width: 12),
                      Row(children: [
                        const Text('聊天气泡'),
                        const SizedBox(width: 6),
                        Switch(value: s.decoUseBubbles, onChanged: (v) => controller.setDecoUseBubbles(v)),
                      ]),
                      const Spacer(),
                      const Text('字号缩放：'),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 0,
                        child: SizedBox(
                          width: 220,
                          child: Slider(
                            value: s.textScale,
                            min: 0.9,
                            max: 1.4,
                            divisions: 10,
                            label: s.textScale.toStringAsFixed(2),
                            onChanged: (v) => controller.setTextScale(v),
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.4)),
                  ),
                  child: Builder(
                    builder: (context) {
                      final baseFam = (s.baseFontMode == BaseFontModeOption.miSansPreferred) ? 'MiSansVF' : null;
                      final decoFam = (s.decoFamily == DecorativeFontFamily.fzg)
                          ? 'FZG'
                          : (s.decoFamily == DecorativeFontFamily.nfdcs)
                              ? 'nfdcs'
                              : null;
                      final fallback = const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'];
                      final titleFam = (s.decoUseTitles && decoFam != null) ? decoFam : baseFam;
                      final bubbleFam = (s.decoUseBubbles && decoFam != null) ? decoFam : baseFam;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aa 这是一段预览文本 Preview • 预览 • プレビュー • 미리보기 0123456789',
                            style: TextStyle(
                              fontSize: 13 * s.textScale,
                              fontFamily: baseFam,
                              fontFamilyFallback: fallback,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '标题示例 Title Sample',
                            style: TextStyle(
                              fontSize: 18 * s.textScale,
                              fontWeight: FontWeight.w700,
                              fontFamily: titleFam,
                              fontFamilyFallback: fallback,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '聊天示例：你好，这是一个聊天气泡。',
                              style: TextStyle(
                                fontSize: 14 * s.textScale,
                                fontFamily: bubbleFam,
                                fontFamilyFallback: fallback,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()));
                  },
                  icon: const Icon(Icons.info_outline),
                  label: const Text('关于 / 许可证'),
                ),
              ),
              const Divider(height: 28),
              // Quick Actions configuration panel
              const ListTile(
                leading: Icon(Icons.flash_on_outlined),
                title: Text('输入区快捷按钮', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final id in s.quickActions)
                          Chip(
                            label: Text(switch (id) {
                              'attach_image' => '附加图片',
                              'compress' => '压缩上下文',
                              'new_chat' => '新对话',
                              'memory' => '记忆库',
                              'expression_toggle' => '切换表情',
                              _ => id,
                            }),
                            avatar: Icon(switch (id) {
                              'attach_image' => Icons.image_outlined,
                              'compress' => Icons.cleaning_services_outlined,
                              'new_chat' => Icons.add_comment_outlined,
                              'memory' => Icons.memory,
                              'expression_toggle' => Icons.emoji_emotions_outlined,
                              _ => Icons.extension,
                            }, size: 16),
                          ),
                        if (s.quickActions.isEmpty)
                          const Text('暂无已启用快捷按钮，可点击下方“编辑”配置。', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonal(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (ctx) {
                              final all = ['attach_image','compress','new_chat','memory','expression_toggle'];
                              final selected = List<String>.from(s.quickActions);
                              return AlertDialog(
                                title: const Text('编辑快捷按钮'),
                                content: SizedBox(
                                  width: 360,
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        for (final id in all)
                                          StatefulBuilder(
                                            builder: (ctx2, setStateDialog) => CheckboxListTile(
                                              value: selected.contains(id),
                                              title: Text(switch (id) {
                                                'attach_image' => '附加图片',
                                                'compress' => '压缩上下文',
                                                'new_chat' => '新对话',
                                                'memory' => '记忆库',
                                                'expression_toggle' => '切换表情面板',
                                                _ => id,
                                              }),
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
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                                  FilledButton(onPressed: () { controller.setQuickActions(selected); Navigator.pop(ctx); }, child: const Text('保存')),
                                ],
                              );
                            },
                          );
                        },
                        child: const Text('编辑'),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text('提示：这些按钮显示在聊天输入框右侧，可快速执行常用操作。', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // 统一外层纵向滚动，避免子区域被挤压后无法滚动
    return LayoutBuilder(builder: (ctx, cons) {
      final isWide = cons.maxWidth >= 1100;
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: [
            appearancePanel(),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: min(320, width * 0.28),
                    decoration: BoxDecoration(border: Border(right: BorderSide(color: Theme.of(context).dividerColor))),
                    child: Column(children: [
                      const ListTile(leading: Icon(Icons.hub_outlined), title: Text('平台列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                      leftList(),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const ListTile(leading: Icon(Icons.smart_toy_outlined), title: Text('AI 接入 / API 配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
                          rightPanel(),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            else ...[
              // 窄屏：纵向堆叠，整体一条滚动
              const ListTile(leading: Icon(Icons.hub_outlined), title: Text('平台列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              leftList(),
              const SizedBox(height: 8),
              const ListTile(leading: Icon(Icons.smart_toy_outlined), title: Text('AI 接入 / API 配置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              rightPanel(),
            ],
          ],
        ),
      );
    });
  }
}
