import 'dart:math';

import 'package:flutter/material.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';
import 'about_screen.dart';

class SystemScreen extends StatefulWidget {
  const SystemScreen({Key? key}) : super(key: key);

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  String? _selectedId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ctrl = SettingsScope.of(context);
    final providers = ctrl.providers;
    if (_selectedId == null && providers.isNotEmpty) _selectedId = ctrl.activeProviderId ?? providers.first.id;
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
                setState(() => _selectedId = p.id);
                controller.setActiveProvider(p.id);
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
  final nameCtl = TextEditingController(text: cfg.name);
  final baseCtl = TextEditingController(text: cfg.baseUrl);
  final keyCtl = TextEditingController(text: cfg.apiKey);
  final modelCtl = TextEditingController(text: cfg.defaultModel);
      final rpmCtl = TextEditingController(text: cfg.rpm == null ? '' : cfg.rpm.toString());

      final modelOptions = {
        ...{for (final s in _suggestionsFor(cfg.kind)) s: true}.keys,
        ...?cfg.modelCatalog,
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
              TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '显示名称')),
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
              TextField(controller: baseCtl, decoration: const InputDecoration(labelText: 'Base URL（可选）'), onSubmitted: (v) => controller.setProviderField(cfg.id, baseUrl: v)),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Base URL 是根路径'),
                const SizedBox(width: 8),
                Switch(value: cfg.isRoot, onChanged: (v) async { await controller.addOrUpdateProvider(cfg.copyWith(isRoot: v)); if (!mounted) return; setState(() {}); }),
                const SizedBox(width: 8),
                const Expanded(child: Text('开启：视为 .../v1 或 .../v4，将自动追加 /chat/completions；关闭：视为完整接口路径')),
              ]),
              const SizedBox(height: 8),
              TextField(controller: keyCtl, decoration: const InputDecoration(labelText: 'API Key（可选）'), obscureText: true, onSubmitted: (v) => controller.setProviderField(cfg.id, apiKey: v)),
              const SizedBox(height: 8),
              // 模型下拉（建议 + 已获取）
              if (modelOptions.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  value: modelOptions.contains(cfg.defaultModel) && cfg.defaultModel.isNotEmpty ? cfg.defaultModel : null,
                  decoration: const InputDecoration(labelText: '模型（建议/已获取）'),
                  isExpanded: true,
                  items: [
                    for (final m in modelOptions) DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    modelCtl.text = v;
                    await controller.setProviderField(cfg.id, defaultModel: v);
                    if (!mounted) return; setState(() {});
                  },
                ),
                const SizedBox(height: 8),
              ],
              TextField(controller: modelCtl, decoration: const InputDecoration(labelText: '默认模型（可手填覆盖）'), onSubmitted: (v) => controller.setProviderField(cfg.id, defaultModel: v)),
              const SizedBox(height: 8),
              Row(children: [
                FilledButton.tonal(onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    final models = await controller.fetchModelsForProvider(cfg.id);
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('已获取 ${models.length} 个模型')));
                    setState(() {});
                  } catch (e) {
                    if (!mounted) return;
                    messenger.showSnackBar(SnackBar(content: Text('获取模型失败: $e')));
                  }
                }, child: const Text('获取模型')),
                const SizedBox(width: 12),
                const Text('加入轮换'),
                const SizedBox(width: 6),
                Switch(value: cfg.rotate, onChanged: (v) async { await controller.setProviderRotate(cfg.id, v); if (!mounted) return; setState(() {}); }),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: rpmCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '每分钟请求上限 (RPM)'),
                    onSubmitted: (v) {
                      final n = int.tryParse(v.trim());
                      controller.setProviderRpm(cfg.id, n);
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton.tonal(onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await controller.addOrUpdateProvider(cfg.copyWith(name: nameCtl.text.trim(), baseUrl: baseCtl.text.trim(), apiKey: keyCtl.text.trim(), defaultModel: modelCtl.text.trim()));
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
                  child: const Text('Aa 这是一段预览文本 Preview • 预览 • プレビュー • 미리보기 0123456789\n标题示例 Title Sample\n聊天示例：你好，这是一个聊天气泡。'),
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
