import 'package:flutter/material.dart';
import '../settings/settings_scope.dart';
import '../settings/settings_controller.dart';
import '../settings/settings.dart';

class AgentsScreen extends StatefulWidget {
  const AgentsScreen({super.key});

  @override
  State<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends State<AgentsScreen> {
  @override
  Widget build(BuildContext context) {
    final ctrl = SettingsScope.of(context);
    final agents = ctrl.settings.agents;
    final providers = ctrl.providers;

    return Scaffold(
      appBar: AppBar(title: const Text('Agent 管理')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('配置独立 Agent，用于分离任务（表情/视觉/自定义）', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: agents.length,
                itemBuilder: (context, i) {
                  final a = agents[i];
                  final provider = a.providerId == null ? null : ctrl.getProviderById(a.providerId!);
                  return Card(
                    child: ListTile(
                      title: Text(a.name),
                      subtitle: Text(
                        a.description.isNotEmpty ? a.description : (provider != null ? '关联 provider: ${provider.name}' : '未关联 provider'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        // TODO: Open agent details/config
                      },
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditDialog(ctrl, providers, a)),
                        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async {
                          final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                            title: const Text('删除 Agent'),
                            content: Text('确定删除 Agent "${a.name}" 吗？'),
                            actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除'))],
                          ));
                          if (ok == true) {
                            await ctrl.removeAgent(a.id);
                            if (mounted) setState(() {});
                          }
                        }),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              FilledButton.icon(onPressed: () => _showEditDialog(ctrl, providers, null), icon: const Icon(Icons.add), label: const Text('新建 Agent')),
              const SizedBox(width: 12),
              TextButton(onPressed: () => _showImportTemplate(ctrl, providers), child: const Text('从 Provider 套用模板')),
            ])
          ],
        ),
      ),
    );
  }

  void _showImportTemplate(SettingsController ctrl, List<AiProviderConfig> providers) async {
    if (providers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('尚无可用 Provider')));
      return;
    }
    showDialog(context: context, builder: (ctx) {
      String? sel;
      return StatefulBuilder(builder: (ctx2, setLocalState) {
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
                  items: [for (final p in providers) DropdownMenuItem(value: p.id, child: Text(p.name))],
                  onChanged: (v) { sel = v; setLocalState(() {}); },
                ),
                const SizedBox(height: 8),
                const Text('说明：套用模板将引用 Provider 的 baseUrl 与 apiKey（不复制），并自动填充模型建议。你可在保存时修改模型字段。', style: TextStyle(fontSize: 12)),
                if (sel != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Builder(builder: (_) {
                      final p = ctrl.getProviderById(sel!);
                      if (p == null) return const SizedBox.shrink();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Base URL: ${p.baseUrl}', style: const TextStyle(fontSize: 12)),
                        Text('默认模型: ${p.model}', style: const TextStyle(fontSize: 12)),
                      ]);
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () {
              if (sel == null) return;
              final p = ctrl.getProviderById(sel!);
              if (p == null) return;
              final id = 'agent_${DateTime.now().millisecondsSinceEpoch}';
              final newAgent = AgentConfig(id: id, name: '${p.name} Agent', providerId: p.id, description: '基于 ${p.name} 的模板', enabled: true, meta: {'suggestedModel': p.model});
              ctrl.addOrUpdateAgent(newAgent);
              Navigator.pop(ctx);
              if (mounted) setState(() {});
            }, child: const Text('套用并新建')),
          ],
        );
      });
    });
  }

  void _showEditDialog(SettingsController ctrl, List<AiProviderConfig> providers, AgentConfig? existing) {
    final id = existing?.id ?? 'agent_${DateTime.now().millisecondsSinceEpoch}';
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final descCtl = TextEditingController(text: existing?.description ?? '');
    String? selectedProvider = existing?.providerId;
    bool enabledVal = existing?.enabled ?? true;
    final modelCtl = TextEditingController(text: existing?.meta['suggestedModel']?.toString() ?? '');

    showDialog(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx2, setLocalState) {
        void updateProvider(String? v) {
          selectedProvider = v;
          // 若用户未填写建议模型，则自动填充 provider 的默认模型
          if (v != null && modelCtl.text.trim().isEmpty) {
            final p = ctrl.getProviderById(v);
            if (p != null && p.model.isNotEmpty) {
              modelCtl.text = p.model;
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
                  TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '显示名称')),
                  const SizedBox(height: 8),
                  TextField(controller: descCtl, decoration: const InputDecoration(labelText: '描述/备注'), maxLines: 2),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Text('关联 Provider：'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButton<String?>(
                        isExpanded: true,
                        value: selectedProvider,
                        hint: const Text('不关联（独立 Agent）'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('不关联')),
                          for (final p in providers) DropdownMenuItem(value: p.id, child: Text(p.name)),
                        ],
                        onChanged: (v) => updateProvider(v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextField(controller: modelCtl, decoration: const InputDecoration(labelText: '建议模型（可覆盖）')),
                  const SizedBox(height: 8),
                  SwitchListTile(value: enabledVal, onChanged: (nv) { enabledVal = nv; setLocalState(() {}); }, title: const Text('启用')),
                  const SizedBox(height: 6),
                  if (selectedProvider != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('套用 Provider 信息（只作引用，不会复制或展示敏感信息）', style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 6),
                        Builder(builder: (_) {
                          final p = ctrl.getProviderById(selectedProvider!);
                          if (p == null) return const SizedBox.shrink();
                          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Base URL: ${p.baseUrl}', style: const TextStyle(fontSize: 12)),
                            Text('默认模型: ${p.model}', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 6),
                            TextButton(onPressed: () {
                              // 允许用户手动将 provider 默认模型复制到建议模型
                              if (p.model.isNotEmpty) {
                                modelCtl.text = p.model;
                                setLocalState(() {});
                              }
                            }, child: const Text('自动填充为 Provider 默认模型')),
                          ]);
                        })
                      ]),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(onPressed: () async {
              final nameVal = nameCtl.text.trim();
              if (nameVal.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写显示名称')));
                return;
              }
              if (selectedProvider != null && ctrl.getProviderById(selectedProvider!) == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('选择的 Provider 不存在')));
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
              if (!mounted) return;
              Navigator.of(context).pop();
              setState(() {});
            }, child: const Text('保存')),
          ],
        );
      });
    });
  }
}
