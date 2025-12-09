import 'package:flutter/material.dart';
import '../../../settings/settings_scope.dart';
import '../../../settings/settings_controller.dart';
import '../../../settings/settings.dart';

class AgentsTab extends StatefulWidget {
  const AgentsTab({Key? key}) : super(key: key);

  @override
  State<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<AgentsTab> {
  @override
  Widget build(BuildContext context) {
    final ctrl = SettingsScope.of(context);
    final agents = ctrl.settings.agents;
    final providers = ctrl.providers;

    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        const Text(
          '配置独立 Agent，用于分离任务（表情/视觉/自定义）',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        // --- Special Agents Configuration Section ---
        _buildSpecialAgentsSection(ctrl, providers),
        const Divider(height: 32),

        const Text(
          '自定义 Agent 列表',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),

        if (agents.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('暂无自定义 Agent', style: TextStyle(color: Colors.grey)),
            ),
          ),

        ...agents.map((a) {
          final provider = a.providerId == null
              ? null
              : ctrl.getProviderById(a.providerId!);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(a.name),
              subtitle: Text(
                a.description.isNotEmpty
                    ? a.description
                    : (provider != null
                          ? '关联 provider: ${provider.name}'
                          : '未关联 provider'),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showEditDialog(ctrl, providers, a),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('删除 Agent'),
                          content: Text('确定删除 Agent "${a.name}" 吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(d, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(d, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) {
                        await ctrl.removeAgent(a.id);
                        if (mounted) setState(() {});
                      }
                    },
                  ),
                ],
              ),
            ),
          );
        }).toList(),

        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _showEditDialog(ctrl, providers, null),
              icon: const Icon(Icons.add),
              label: const Text('新建 Agent'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => _showImportTemplate(ctrl, providers),
              child: const Text('从 Provider 套用模板'),
            ),
          ],
        ),
        const SizedBox(height: 40), // Extra padding for bottom
      ],
    );
  }

  Widget _buildSpecialAgentsSection(
    SettingsController ctrl,
    List<AiProviderConfig> providers,
  ) {
    // Helper to get provider name
    String getProviderName(String? id) {
      if (id == null) return '跟随主脑 (默认)';
      final p = ctrl.getProviderById(id);
      return p?.name ?? '未知平台';
    }

    return Card(
      elevation: 0,
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '能力分流 (Capabilities)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Vision Agent
            ListTile(
              leading: const Icon(Icons.image_search),
              title: const Text('视觉识别 (Vision)'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前: ${getProviderName(ctrl.settings.activeVisionProviderId)}',
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '说明：当主模型不支持视觉输入时，系统会自动调用此 Agent 对图片进行描述，并将描述文本传回给主模型。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProviderSelector(
                context,
                ctrl,
                providers,
                '选择视觉服务商',
                ctrl.settings.activeVisionProviderId,
                (id) => ctrl.setActiveVisionProvider(id),
              ),
            ),

            // Expression Agent
            ListTile(
              leading: const Icon(Icons.face),
              title: const Text('拟人表情 (Expression)'),
              subtitle: Text(
                '当前: ${getProviderName(ctrl.settings.activeExpressionProviderId)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProviderSelector(
                context,
                ctrl,
                providers,
                '选择表情推理服务商',
                ctrl.settings.activeExpressionProviderId,
                (id) => ctrl.setActiveExpressionProvider(id),
              ),
            ),

            // Search Agent (New)
            ListTile(
              leading: const Icon(Icons.public),
              title: const Text('联网搜索 (Web Search)'),
              subtitle: Text(
                '当前: ${getProviderName(ctrl.settings.activeSearchProviderId)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProviderSelector(
                context,
                ctrl,
                providers,
                '选择搜索总结服务商',
                ctrl.settings.activeSearchProviderId,
                (id) => ctrl.setActiveSearchProvider(id),
              ),
            ),

            // Motion Agent (Live2D)
            ListTile(
              leading: const Icon(Icons.directions_run),
              title: const Text('动作决策 (Motion)'),
              subtitle: Text(
                '当前: ${getProviderName(ctrl.settings.activeMotionProviderId)}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProviderSelector(
                context,
                ctrl,
                providers,
                '选择动作决策服务商',
                ctrl.settings.activeMotionProviderId,
                (id) => ctrl.setActiveMotionProvider(id),
              ),
            ),

            // Live2D Model Config
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('Live2D 模型配置'),
              subtitle: Text(
                ctrl.settings.live2dModelPath.isEmpty
                    ? '未配置 (使用默认)'
                    : ctrl.settings.live2dModelPath,
              ),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final controller = TextEditingController(
                  text: ctrl.settings.live2dModelPath,
                );
                final newPath = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('配置 Live2D 模型路径'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: '模型路径 (相对于 static/live2d)',
                            hintText:
                                '例如: mao_pro_zh/mao_pro_zh/runtime/mao_pro.model3.json',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '提示：请确保后端 static/live2d 目录下存在该文件。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                );
                if (newPath != null) {
                  ctrl.setLive2dModelPath(newPath);
                }
              },
            ),

            // Search Retry Toggle
            SwitchListTile(
              secondary: const Icon(Icons.replay, color: Colors.grey),
              title: const Text('搜索重试 (Search Retry)'),
              subtitle: const Text('当搜索结果不佳时自动重试 (消耗更多 Token)'),
              value: ctrl.settings.enableSearchRetry,
              onChanged: (val) => ctrl.setEnableSearchRetry(val),
            ),
          ],
        ),
      ),
    );
  }

  void _showProviderSelector(
    BuildContext context,
    SettingsController ctrl,
    List<AiProviderConfig> providers,
    String title,
    String? currentId,
    Function(String?) onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('跟随主脑 (默认)'),
            subtitle: const Text('使用当前对话的主模型'),
            trailing: currentId == null ? const Icon(Icons.check) : null,
            onTap: () {
              onSelect(null);
              Navigator.pop(ctx);
            },
          ),
          const Divider(),
          ...providers.map(
            (p) => ListTile(
              leading: Icon(
                p.kind == AiProvider.local
                    ? Icons.computer
                    : Icons.cloud_outlined,
              ),
              title: Text(p.name),
              subtitle: Text(p.model),
              trailing: currentId == p.id ? const Icon(Icons.check) : null,
              onTap: () {
                onSelect(p.id);
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showImportTemplate(
    SettingsController ctrl,
    List<AiProviderConfig> providers,
  ) async {
    if (providers.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('尚无可用 Provider')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) {
        String? sel;
        return StatefulBuilder(
          builder: (ctx2, setLocalState) {
            return AlertDialog(
              title: const Text('从 Provider 套用模板'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButton<String>(
                      isExpanded: true,
                      value: sel,
                      hint: const Text('选择一个 Provider 作为模板'),
                      items: [
                        for (final p in providers)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) {
                        sel = v;
                        setLocalState(() {});
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '说明：套用模板将引用 Provider 的 baseUrl 与 apiKey（不复制），并自动填充模型建议。你可在保存时修改模型字段。',
                      style: TextStyle(fontSize: 12),
                    ),
                    if (sel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Builder(
                          builder: (_) {
                            final p = ctrl.getProviderById(sel!);
                            if (p == null) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Base URL: ${p.baseUrl}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '默认模型: ${p.model}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            );
                          },
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
                FilledButton(
                  onPressed: () {
                    if (sel == null) return;
                    final p = ctrl.getProviderById(sel!);
                    if (p == null) return;
                    final id = 'agent_${DateTime.now().millisecondsSinceEpoch}';
                    final newAgent = AgentConfig(
                      id: id,
                      name: '${p.name} Agent',
                      providerId: p.id,
                      description: '基于 ${p.name} 的模板',
                      enabled: true,
                      meta: {'suggestedModel': p.model},
                    );
                    ctrl.addOrUpdateAgent(newAgent);
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                  child: const Text('套用并新建'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditDialog(
    SettingsController ctrl,
    List<AiProviderConfig> providers,
    AgentConfig? existing,
  ) {
    final id = existing?.id ?? 'agent_${DateTime.now().millisecondsSinceEpoch}';
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final descCtl = TextEditingController(text: existing?.description ?? '');
    String? selectedProvider = existing?.providerId;
    bool enabledVal = existing?.enabled ?? true;
    final modelCtl = TextEditingController(
      text: existing?.meta['suggestedModel']?.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setLocalState) {
            void updateProvider(String? v) {
              selectedProvider = v;
              // 若用户未填写建议模型，则自动填充 provider 的默认模型
              if (v != null && modelCtl.text.trim().isEmpty) {
                final p = ctrl.getProviderById(v);
                if (p != null && (p.model?.isNotEmpty ?? false)) {
                  modelCtl.text = p.model!;
                }
              }
              setLocalState(() {});
            }

            return AlertDialog(
              title: Text(existing == null ? '新建 Agent' : '编辑 Agent'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtl,
                        decoration: const InputDecoration(labelText: '显示名称'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descCtl,
                        decoration: const InputDecoration(labelText: '描述/备注'),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('关联 Provider：'),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButton<String?>(
                              isExpanded: true,
                              value: selectedProvider,
                              hint: const Text('不关联（独立 Agent）'),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('不关联'),
                                ),
                                for (final p in providers)
                                  DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.name),
                                  ),
                              ],
                              onChanged: (v) => updateProvider(v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: modelCtl,
                        decoration: const InputDecoration(
                          labelText: '建议模型（可覆盖）',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: enabledVal,
                        onChanged: (nv) {
                          enabledVal = nv;
                          setLocalState(() {});
                        },
                        title: const Text('启用'),
                      ),
                      const SizedBox(height: 6),
                      if (selectedProvider != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '套用 Provider 信息（只作引用，不会复制或展示敏感信息）',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 6),
                              Builder(
                                builder: (_) {
                                  final p = ctrl.getProviderById(
                                    selectedProvider!,
                                  );
                                  if (p == null) return const SizedBox.shrink();
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Base URL: ${p.baseUrl}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        '默认模型: ${p.model}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton(
                                        onPressed: () {
                                          // 允许用户手动将 provider 默认模型复制到建议模型
                                          final p2 = ctrl.getProviderById(
                                            selectedProvider!,
                                          );
                                          if (p2 != null &&
                                              (p2.model?.isNotEmpty ?? false)) {
                                            modelCtl.text = p2.model!;
                                            setLocalState(() {});
                                          }
                                        },
                                        child: const Text(
                                          '自动填充为 Provider 默认模型',
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final nameVal = nameCtl.text.trim();
                    if (nameVal.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('请填写显示名称')));
                      return;
                    }
                    if (selectedProvider != null &&
                        ctrl.getProviderById(selectedProvider!) == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('选择的 Provider 不存在')),
                      );
                      return;
                    }
                    final newAgent = AgentConfig(
                      id: id,
                      name: nameVal,
                      providerId: selectedProvider,
                      description: descCtl.text.trim(),
                      enabled: enabledVal,
                      meta: {'suggestedModel': modelCtl.text.trim()},
                    );
                    await ctrl.addOrUpdateAgent(newAgent);
                    Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
