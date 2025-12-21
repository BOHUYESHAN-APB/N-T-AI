import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../../settings/settings_scope.dart';
import '../../../settings/settings.dart';

class ProvidersTab extends StatefulWidget {
  const ProvidersTab({Key? key}) : super(key: key);

  @override
  State<ProvidersTab> createState() => _ProvidersTabState();
}

class _ProvidersTabState extends State<ProvidersTab> {
  String? _selectedId;
  bool _showDetailOnMobile = false;
  final TextEditingController _nameCtl = TextEditingController();
  final TextEditingController _baseCtl = TextEditingController();
  final TextEditingController _keyCtl = TextEditingController();
  final TextEditingController _modelCtl = TextEditingController();
  final TextEditingController _contextLenCtl = TextEditingController();
  final TextEditingController _dailyLimitCtl = TextEditingController();
  String? _lastForProvider;
  List<String> _fetchedModels = []; // Store models fetched from API

  static const List<Map<String, dynamic>> _providerPresets = [
    {
      'name': 'DeepSeek',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.deepseek.com/v1',
      'model': 'deepseek-chat',
      'helpUrl': 'https://platform.deepseek.com/api_keys',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'OpenAI',
      'kind': AiProvider.openai,
      'baseUrl': 'https://api.openai.com/v1',
      'model': 'gpt-4o-mini',
      'helpUrl': 'https://platform.openai.com/api-keys',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'SiliconFlow (TTS)',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.siliconflow.cn/v1',
      'model': 'fishaudio/fish-speech-1.5',
      'helpUrl': 'https://cloud.siliconflow.cn/account/ak',
      'category': AiProviderCategory.tts,
    },
    {
      'name': 'SiliconFlow (STT)',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.siliconflow.cn/v1',
      'model': 'FunAudioLLM/SenseVoiceSmall',
      'helpUrl': 'https://cloud.siliconflow.cn/account/ak',
      'category': AiProviderCategory.stt,
    },
    {
      'name': 'Windows 系统语音识别 (离线)',
      'kind': AiProvider.local,
      'baseUrl': '',
      'model': '',
      'helpUrl': '',
      'category': AiProviderCategory.stt,
      'meta': {'local_stt': 'windows_speech', 'language': 'zh-CN'},
    },
    {
      'name': 'SiliconFlow (Image)',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.siliconflow.cn/v1',
      'model': 'black-forest-labs/FLUX.1-dev',
      'helpUrl': 'https://cloud.siliconflow.cn/account/ak',
      'category': AiProviderCategory.image,
    },
    {
      'name': 'GLM · 智谱',
      'kind': AiProvider.custom,
      'baseUrl': 'https://open.bigmodel.cn/api/paas/v4',
      'model': 'glm-4',
      'helpUrl': 'https://open.bigmodel.cn/usercenter/apikeys',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'SiliconFlow (LLM)',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.siliconflow.cn/v1',
      'model': 'deepseek-ai/DeepSeek-V3',
      'helpUrl': 'https://cloud.siliconflow.cn/account/ak',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'OpenRouter',
      'kind': AiProvider.custom,
      'baseUrl': 'https://openrouter.ai/api/v1',
      'model': 'openai/gpt-3.5-turbo',
      'helpUrl': 'https://openrouter.ai/keys',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'Groq',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.groq.com/openai/v1',
      'model': 'llama3-8b-8192',
      'helpUrl': 'https://console.groq.com/keys',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'Kimi · Moonshot',
      'kind': AiProvider.custom,
      'baseUrl': 'https://api.moonshot.cn/v1',
      'model': 'moonshot-v1-8k',
      'helpUrl': 'https://platform.moonshot.cn/console/api-keys',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'LM Studio (本地)',
      'kind': AiProvider.local,
      'baseUrl': 'http://127.0.0.1:1234/v1',
      'model': 'local-model',
      'helpUrl': 'https://lmstudio.ai/',
      'category': AiProviderCategory.llm,
    },
    {
      'name': 'Ollama (本地)',
      'kind': AiProvider.local,
      'baseUrl': 'http://127.0.0.1:11434/v1',
      'model': 'llama3',
      'helpUrl': 'https://ollama.com/',
      'category': AiProviderCategory.llm,
    },
  ];

  void _syncControllersFrom(AiProviderConfig cfg) {
    _nameCtl.text = cfg.name;
    _baseCtl.text = cfg.baseUrl;
    _keyCtl.text = cfg.apiKey;
    _modelCtl.text = cfg.model;
    _contextLenCtl.text = (cfg.meta['context_length'] ?? 128000).toString();
    _dailyLimitCtl.text = cfg.dailyLimit.toString();
    _lastForProvider = cfg.id;
    _fetchedModels = []; // Reset fetched models when switching provider
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

  Future<void> _showAddProviderDialog(BuildContext context, dynamic controller) async {
    await showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('选择平台预设'),
        children: [
          ..._providerPresets.map((preset) => SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: Row(
              children: [
                Icon(preset['kind'] == AiProvider.local ? Icons.computer : Icons.cloud_outlined, size: 20),
                const SizedBox(width: 12),
                Text(preset['name'] as String, style: const TextStyle(fontSize: 16)),
              ],
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final id = 'p_${DateTime.now().millisecondsSinceEpoch}';
              final presetMeta = (preset['meta'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
              final newP = AiProviderConfig(
                id: id,
                name: preset['name'] as String,
                kind: preset['kind'] as AiProvider,
                baseUrl: (preset['baseUrl'] as String?) ?? '',
                model: (preset['model'] as String?) ?? '',
                enabled: true,
                category: preset['category'] as AiProviderCategory? ?? AiProviderCategory.llm,
                meta: presetMeta,
              );
              await controller.addOrUpdateProvider(newP);
              if (!mounted) return;
              setState(() => _selectedId = id);
            },
          )),
          const Divider(),
          SimpleDialogOption(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            child: const Row(
              children: [
                Icon(Icons.edit_outlined, size: 20),
                SizedBox(width: 12),
                Text('自定义平台', style: TextStyle(fontSize: 16)),
              ],
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final id = 'p_${DateTime.now().millisecondsSinceEpoch}';
              final newP = AiProviderConfig(id: id, name: '新平台', kind: AiProvider.custom, enabled: true);
              await controller.addOrUpdateProvider(newP);
              if (!mounted) return;
              setState(() => _selectedId = id);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final providers = controller.providers;
    
    // Group providers by category
    final grouped = <AiProviderCategory, List<AiProviderConfig>>{};
    for (var p in providers) {
      grouped.putIfAbsent(p.category, () => []).add(p);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 700;

        if (isMobile && _showDetailOnMobile && _selectedId != null) {
          return _buildDetailPanel(context, controller, providers, isMobile: true);
        }

        final listWidget = Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('平台列表', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showAddProviderDialog(context, controller),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final cat in AiProviderCategory.values)
                    if (grouped.containsKey(cat)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          _getCategoryLabel(cat),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ...grouped[cat]!.map((p) => ListTile(
                        selected: !isMobile && p.id == _selectedId,
                        leading: Icon(_getCategoryIcon(cat)),
                        title: Text(p.name),
                        subtitle: Text(
                          '${p.kind.name}${p.enabled ? '' : ' (禁用)'}${p.dailyLimit > 0 ? ' • ${p.usageCount}/${p.dailyLimit}' : ''}',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() {
                            _selectedId = p.id;
                            _syncControllersFrom(p);
                            if (isMobile) {
                              _showDetailOnMobile = true;
                            }
                          });
                        },
                      )),
                      const Divider(),
                    ],
                ],
              ),
            ),
          ],
        );

        if (isMobile) {
          return listWidget;
        }

        return Row(
          children: [
            // Left List
            SizedBox(
              width: 280,
              child: listWidget,
            ),
            const VerticalDivider(width: 1),
            // Right Details
            Expanded(
              child: _selectedId == null
                  ? const Center(child: Text('请选择或添加一个平台'))
                  : _buildDetailPanel(context, controller, providers),
            ),
          ],
        );
      },
    );
  }
  
  String _getCategoryLabel(AiProviderCategory cat) {
    switch (cat) {
      case AiProviderCategory.llm: return 'LLM (大语言模型)';
      case AiProviderCategory.tts: return 'TTS (语音合成)';
      case AiProviderCategory.stt: return 'STT (语音识别)';
      case AiProviderCategory.motion: return 'Motion (动作驱动)';
      case AiProviderCategory.image: return 'Image (图像生成)';
      case AiProviderCategory.video: return 'Video (视频生成)';
    }
  }
  
  IconData _getCategoryIcon(AiProviderCategory cat) {
    switch (cat) {
      case AiProviderCategory.llm: return Icons.psychology;
      case AiProviderCategory.tts: return Icons.record_voice_over;
      case AiProviderCategory.stt: return Icons.hearing;
      case AiProviderCategory.motion: return Icons.directions_run;
      case AiProviderCategory.image: return Icons.image;
      case AiProviderCategory.video: return Icons.videocam;
    }
  }

  Widget _buildDetailPanel(BuildContext context, dynamic controller, List<AiProviderConfig> providers, {bool isMobile = false}) {
    final cfg = providers.firstWhere((p) => p.id == _selectedId, orElse: () => providers.first);
    if (_lastForProvider != cfg.id) {
      _syncControllersFrom(cfg);
    }

    final modelOptions = _fetchedModels.isNotEmpty 
        ? _fetchedModels 
        : _suggestionsFor(cfg.kind, cfg.category);
    
    // Find matching preset for help URL
    final preset = _providerPresets.firstWhere(
      (p) => p['baseUrl'] == cfg.baseUrl || (cfg.name.contains(p['name']) && p['kind'] == cfg.kind),
      orElse: () => {},
    );
    final helpUrl = preset['helpUrl'] as String?;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  if (isMobile) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _showDetailOnMobile = false),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      '编辑平台: ${cfg.name}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                if (!isMobile) ...[
                  FilledButton.tonal(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final msg = await controller.testProvider(cfg.id);
                        // Try to fetch models if test succeeds
                        try {
                          final models = await controller.fetchModels(cfg.id);
                          if (models.isNotEmpty) {
                             setState(() {
                               _fetchedModels = models;
                             });
                          }
                        } catch (_) {} // Ignore model fetch error
                        
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text(msg)));
                      } catch (e) {
                        if (!mounted) return;
                        messenger.showSnackBar(SnackBar(content: Text('测试失败: $e')));
                      }
                    },
                    child: const Text('测试连接'),
                  ),
                  const SizedBox(width: 8),
                ],
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final ok = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                      title: const Text('删除平台'),
                      content: Text('确定删除 ${cfg.name} ?'),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')), FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('删除'))],
                    ));
                    if (ok == true) {
                      await controller.removeProvider(cfg.id);
                      if (!mounted) return;
                      setState(() {
                        final all = controller.providers;
                        _selectedId = all.isNotEmpty ? all.first.id : null;
                        if (isMobile) _showDetailOnMobile = false;
                      });
                    }
                  },
                ),
              ],
            ),
          ],
        ),
        if (isMobile) ...[
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                final msg = await controller.testProvider(cfg.id);
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text(msg)));
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(SnackBar(content: Text('测试失败: $e')));
              }
            },
            child: const Text('测试连接'),
          ),
        ],
        const SizedBox(height: 24),
        TextField(controller: _nameCtl, decoration: const InputDecoration(labelText: '显示名称', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        DropdownButtonFormField<AiProviderCategory>(
          value: cfg.category,
          decoration: const InputDecoration(labelText: '功能分类', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: AiProviderCategory.llm, child: Text('LLM (主脑/对话)')),
            DropdownMenuItem(value: AiProviderCategory.tts, child: Text('TTS (语音合成)')),
            DropdownMenuItem(value: AiProviderCategory.stt, child: Text('STT (语音识别)')),
            DropdownMenuItem(value: AiProviderCategory.motion, child: Text('Motion (动作驱动)')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await controller.addOrUpdateProvider(cfg.copyWith(category: v));
            if (!mounted) return;
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<AiProvider>(
          value: cfg.kind,
          decoration: const InputDecoration(labelText: '平台类型', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: AiProvider.local, child: Text('本地/离线')),
            DropdownMenuItem(value: AiProvider.openai, child: Text('OpenAI')),
            DropdownMenuItem(value: AiProvider.custom, child: Text('自定义（兼容 OpenAI 风格）')),
          ],
          onChanged: (v) async {
            if (v == null) return;
            await controller.addOrUpdateProvider(cfg.copyWith(kind: v));
            if (!mounted) return;
            setState(() {});
          },
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 8),
        if (cfg.category == AiProviderCategory.llm)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('自动追加 /chat/completions', style: TextStyle(fontSize: 14)),
            subtitle: const Text('开启后视为根路径，关闭则视为完整接口路径', style: TextStyle(fontSize: 12)),
            value: cfg.isRoot,
            onChanged: (v) async { await controller.addOrUpdateProvider(cfg.copyWith(isRoot: v)); if (!mounted) return; setState(() {}); },
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _baseCtl,
          decoration: const InputDecoration(labelText: 'API Base URL', border: OutlineInputBorder()),
          onSubmitted: (v) => controller.setProviderField(cfg.id, baseUrl: v),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _keyCtl,
                decoration: const InputDecoration(labelText: 'API Key', border: OutlineInputBorder()),
                obscureText: true,
                onSubmitted: (v) => controller.setProviderField(cfg.id, apiKey: v),
              ),
            ),
            if (helpUrl != null) ...[
              const SizedBox(width: 12),
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('获取 Key'),
                  onPressed: () async {
                    if (helpUrl.contains('siliconflow')) {
                      // SiliconFlow special handling for referral
                      await showDialog(
                        context: context,
                        builder: (ctx) => SimpleDialog(
                          title: const Text('获取 SiliconFlow API Key'),
                          children: [
                            SimpleDialogOption(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('注册账号 (支持开发者)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  Text('使用推广链接注册，赠送 2000万 Tokens，同时支持我们', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                final uri = Uri.parse('https://cloud.siliconflow.cn/i/oiWI8xjZ');
                                if (await canLaunchUrl(uri)) await launchUrl(uri);
                              },
                            ),
                            const Divider(),
                            SimpleDialogOption(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                              child: const Text('注册账号 (普通入口)', style: TextStyle(fontSize: 16)),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                final uri = Uri.parse('https://cloud.siliconflow.cn/login');
                                if (await canLaunchUrl(uri)) await launchUrl(uri);
                              },
                            ),
                            const Divider(),
                            SimpleDialogOption(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                              child: const Text('已有账号，去控制台', style: TextStyle(fontSize: 16)),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                final uri = Uri.parse('https://cloud.siliconflow.cn/account/ak');
                                if (await canLaunchUrl(uri)) await launchUrl(uri);
                              },
                            ),
                          ],
                        ),
                      );
                    } else {
                      final uri = Uri.parse(helpUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    }
                  },
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        if (cfg.category == AiProviderCategory.tts) ...[
          const Text('参考音频 (Voice Cloning)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (cfg.meta['voice'] != null)
             Text('当前 Voice ID: ${cfg.meta['voice']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('上传参考音频'),
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(type: FileType.audio);
              if (result != null && result.files.single.path != null) {
                 final path = result.files.single.path!;
                 final nameCtl = TextEditingController(text: 'voice_${DateTime.now().millisecondsSinceEpoch}');
                 final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                   title: const Text('上传音频'),
                   content: Column(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       TextField(controller: nameCtl, decoration: const InputDecoration(labelText: '自定义名称')),
                       const SizedBox(height: 8),
                       const Text('将上传到 SiliconFlow 并获取 Voice ID'),
                     ],
                   ),
                   actions: [
                     TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                     FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('上传')),
                   ],
                 ));
                 
                 if (ok == true) {
                   try {
                     final uri = await controller.uploadReferenceAudio(cfg.id, path, nameCtl.text);
                     if (!mounted) return;
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传成功: $uri')));
                     setState(() {});
                   } catch (e) {
                     if (!mounted) return;
                     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('上传失败: $e')));
                   }
                 }
              }
            },
          ),
          const SizedBox(height: 16),
        ],
        if (modelOptions.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            value: modelOptions.contains(cfg.model) && cfg.model.isNotEmpty ? cfg.model : null,
            decoration: const InputDecoration(labelText: '推荐模型', border: OutlineInputBorder()),
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
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _modelCtl,
          decoration: const InputDecoration(labelText: '模型名称 (Model ID)', border: OutlineInputBorder()),
          onSubmitted: (v) => controller.setProviderField(cfg.id, model: v),
        ),
        const SizedBox(height: 16),
        if (cfg.category == AiProviderCategory.llm) ...[
          TextField(
            controller: _contextLenCtl,
            decoration: const InputDecoration(
              labelText: '上下文长度 (Tokens)',
              border: OutlineInputBorder(),
              helperText: '用于80%阈值触发上下文压缩的粗略判断',
            ),
            keyboardType: TextInputType.number,
            onSubmitted: (v) async {
              final n = int.tryParse(v.trim());
              final meta = Map<String, dynamic>.from(cfg.meta);
              if (n != null && n > 0) {
                meta['context_length'] = n;
              } else {
                meta.remove('context_length');
              }
              await controller.addOrUpdateProvider(cfg.copyWith(meta: meta));
              if (!mounted) return;
              setState(() {});
            },
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _dailyLimitCtl,
          decoration: const InputDecoration(
            labelText: '每日调用限制 (次)', 
            border: OutlineInputBorder(),
            helperText: '0 表示不限制。不同模型分词逻辑不同，Token 统计存在误差，故仅统计调用次数。',
          ),
          keyboardType: TextInputType.number,
          onSubmitted: (v) async {
             final limit = int.tryParse(v) ?? 0;
             await controller.addOrUpdateProvider(cfg.copyWith(dailyLimit: limit));
          },
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Text('启用此平台'),
            Switch(value: cfg.enabled, onChanged: (v) async { await controller.setProviderEnabled(cfg.id, v); if (!mounted) return; setState(() {}); }),
            const SizedBox(width: 24),
            const Text('参与轮换'),
            Switch(value: controller.rotationEnabled, onChanged: (v) => controller.setRotationEnabled(v)),
          ],
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            FilledButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final meta = Map<String, dynamic>.from(cfg.meta);
                if (cfg.category == AiProviderCategory.llm) {
                  final n = int.tryParse(_contextLenCtl.text.trim());
                  if (n != null && n > 0) {
                    meta['context_length'] = n;
                  } else {
                    meta.remove('context_length');
                  }
                }
                await controller.addOrUpdateProvider(cfg.copyWith(
                  name: _nameCtl.text.trim(),
                  baseUrl: _baseCtl.text.trim(),
                  apiKey: _keyCtl.text.trim(),
                  model: _modelCtl.text.trim(),
                  dailyLimit: int.tryParse(_dailyLimitCtl.text) ?? 0,
                  meta: meta,
                ));
                if (!mounted) return;
                messenger.showSnackBar(const SnackBar(content: Text('已保存')));
              },
              child: const Text('保存修改'),
            ),
            const SizedBox(width: 16),
            if (controller.activeProviderId != cfg.id && cfg.category == AiProviderCategory.llm)
              OutlinedButton(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await controller.setActiveProvider(cfg.id);
                  if (!mounted) return;
                  messenger.showSnackBar(const SnackBar(content: Text('已设为主脑')));
                },
                child: const Text('设为主脑'),
              ),
          ],
        ),
      ],
    );
  }

  List<String> _suggestionsFor(AiProvider kind, AiProviderCategory category) {
    if (category == AiProviderCategory.tts) {
      return const [
        'FunAudioLLM/CosyVoice2-0.5B', 
        'fishaudio/fish-speech-1.5', 
        'RVC/v2',
        'fnlp/MOSS-TTSD-v0.5',
      ];
    }
    if (category == AiProviderCategory.stt) {
      return const [
        'FunAudioLLM/SenseVoiceSmall', 
        'TeleAI/TeleSpeechASR',
        'openai/whisper-large-v3'
      ];
    }
    if (category == AiProviderCategory.image) {
      return const [
        'black-forest-labs/FLUX.1-dev',
        'black-forest-labs/FLUX.1-schnell',
        'stabilityai/stable-diffusion-3-medium',
        'stabilityai/stable-diffusion-xl-base-1.0',
      ];
    }
    
    switch (kind) {
      case AiProvider.openai:
        return const ['gpt-4o', 'gpt-4o-mini', 'o4-mini', 'gpt-4.1-mini', 'text-embedding-3-small'];
      case AiProvider.local:
        return const ['llama-3.1-8b-instruct', 'llama-3.1-70b-instruct', 'qwen2.5-7b-instruct', 'mistral-7b-instruct', 'phi-3.1-mini'];
      case AiProvider.custom:
        return const ['deepseek-chat', 'deepseek-reasoner', 'glm-4', 'glm-4-air', 'glm-4-flash', 'openrouter/auto', 'mixtral-8x7b-32768', 'llama-3.1-70b-versatile'];
    }
  }
}
