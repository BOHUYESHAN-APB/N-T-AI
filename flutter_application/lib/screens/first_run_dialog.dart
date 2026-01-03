import 'package:flutter/material.dart';
import '../core/services/brain_service.dart';
import '../settings/settings.dart';
import '../settings/settings_controller.dart';

class FirstRunDialog extends StatefulWidget {
  final SettingsController settingsController;
  final BrainService brain;

  const FirstRunDialog({super.key, required this.settingsController, required this.brain});

  @override
  State<FirstRunDialog> createState() => _FirstRunDialogState();
}

class _FirstRunDialogState extends State<FirstRunDialog> {
  final TextEditingController _nameController = TextEditingController(text: 'Firefly');
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;
  String _selectedType = 'Anime Character (动漫角色)';
  String? _selectedMainProviderId;
  String? _selectedVisionProviderId;
  String? _selectedEmbeddingProviderId;

  final List<String> _personaTypes = [
    'Anime Character (动漫角色)',
    'Professional Assistant (专业助手)',
    'Coding Mentor (编程导师)',
    'Creative Writer (创意作家)',
    'Psychological Counselor (心理咨询师)',
    'Game NPC (游戏角色)',
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill with existing system prompt if any, or default
    _promptController.text = widget.settingsController.settings.systemPrompt;
    if (widget.settingsController.settings.assistantName.isNotEmpty) {
      _nameController.text = widget.settingsController.settings.assistantName;
    }
    final settings = widget.settingsController.settings;
    _selectedMainProviderId = settings.activeProviderId;
    _selectedVisionProviderId = settings.activeVisionProviderId;
    _selectedEmbeddingProviderId = settings.activeEmbeddingProviderId;
    final llmProviders = _getLlmProviders();
    final embeddingProviders = _getEmbeddingProviders();
    if (_selectedMainProviderId == null && llmProviders.isNotEmpty) {
      _selectedMainProviderId = llmProviders.first.id;
    } else if (_selectedMainProviderId != null &&
        !llmProviders.any((p) => p.id == _selectedMainProviderId)) {
      _selectedMainProviderId = llmProviders.isNotEmpty ? llmProviders.first.id : null;
    }
    if (_selectedVisionProviderId != null &&
        !llmProviders.any((p) => p.id == _selectedVisionProviderId)) {
      _selectedVisionProviderId = null;
    }
    if (_selectedEmbeddingProviderId != null &&
        !embeddingProviders.any((p) => p.id == _selectedEmbeddingProviderId)) {
      _selectedEmbeddingProviderId = null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generatePersona() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isGenerating = true);
    try {
      if (_selectedMainProviderId != null &&
          _selectedMainProviderId != widget.settingsController.activeProviderId) {
        await widget.settingsController.setActiveProvider(_selectedMainProviderId!);
      }
      final persona = await widget.brain.generatePersonaFromWeb(name, type: _selectedType);
      if (mounted) {
        _promptController.text = persona;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _useDefaultPersona() async {
    _nameController.text = 'Firefly';
    _promptController.text = ''; // Empty means default
    await _finish();
  }

  Future<void> _finish() async {
    await widget.settingsController.setAssistantName(_nameController.text.trim());
    await widget.settingsController.setSystemPrompt(_promptController.text.trim());
    if (_selectedMainProviderId != null) {
      await widget.settingsController.setActiveProvider(_selectedMainProviderId!);
    }
    await widget.settingsController.setActiveVisionProvider(_selectedVisionProviderId);
    await widget.settingsController.updateActiveEmbeddingProviderId(_selectedEmbeddingProviderId);
    await widget.settingsController.setIsFirstRun(false);
    if (mounted) Navigator.of(context).pop();
  }

  List<AiProviderConfig> _getLlmProviders() {
    return widget.settingsController.providers
        .where((p) => p.category == AiProviderCategory.llm)
        .toList();
  }

  List<AiProviderConfig> _getEmbeddingProviders() {
    return widget.settingsController.providers
        .where((p) => p.category == AiProviderCategory.embedding)
        .toList();
  }

  bool _isVisionRecommended(AiProviderConfig p) {
    final llmClass = p.meta['llm_class'];
    if (llmClass is String && llmClass.toLowerCase() == 'vllm') {
      return true;
    }
    if (p.capabilities.contains('image')) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final llmProviders = _getLlmProviders();
    final embeddingProviders = _getEmbeddingProviders();
    final visionProviders = List<AiProviderConfig>.from(llmProviders)
      ..sort((a, b) {
        final aReco = _isVisionRecommended(a);
        final bReco = _isVisionRecommended(b);
        if (aReco != bReco) return aReco ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final hasLlm = llmProviders.isNotEmpty;
    final hasEmbedding = embeddingProviders.isNotEmpty;
    final mainValue = hasLlm && llmProviders.any((p) => p.id == _selectedMainProviderId)
        ? _selectedMainProviderId
        : null;
    final visionValue = visionProviders.any((p) => p.id == _selectedVisionProviderId)
        ? _selectedVisionProviderId
        : null;
    final embeddingValue =
        embeddingProviders.any((p) => p.id == _selectedEmbeddingProviderId)
            ? _selectedEmbeddingProviderId
            : null;
    final canGeneratePersona = !_isGenerating && mainValue != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Welcome / 欢迎', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text('Let\'s set up your AI Assistant identity.\n请设置您的 AI 助手身份。', style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 24),
              
              // Name Input
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Assistant Name / 助手名称',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Firefly, Miku, Jarvis...',
                ),
              ),
              const SizedBox(height: 16),
              
              // Type Selection
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Persona Type / 人设类型',
                  border: OutlineInputBorder(),
                ),
                items: _personaTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedType = v);
                },
              ),
              const SizedBox(height: 16),

              // Generate Button
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: canGeneratePersona ? _generatePersona : null,
                      icon: _isGenerating 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.auto_awesome),
                      label: const Text('Auto-Generate Persona (Web Search) / 自动生成人设'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '需要已配置可用的 LLM，并开启网络访问。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              
              // Prompt Input
              TextField(
                controller: _promptController,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'System Prompt / 系统提示词',
                  border: OutlineInputBorder(),
                  hintText: 'Define the personality, tone, and rules for the AI...',
                ),
              ),
              const SizedBox(height: 24),
              Text('Model Setup / 模型配置', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                '建议至少配置：一个对话 LLM、一个视觉 VLLM、一个 Embedding 模型。',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 12),
              if (!hasLlm) ...[
                const Text(
                  '未检测到 LLM 服务商，请先到 设置 -> 平台 添加。',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ] else ...[
                DropdownButtonFormField<String>(
                  value: mainValue,
                  decoration: const InputDecoration(
                    labelText: 'Main LLM / 主对话模型',
                    border: OutlineInputBorder(),
                  ),
                  items: llmProviders
                      .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedMainProviderId = v),
                ),
              ],
              const SizedBox(height: 12),
              if (visionProviders.isEmpty) ...[
                const Text(
                  '未检测到可用的视觉模型（VLLM）。如需视觉能力，请在平台列表中新建 VLLM。',
                  style: TextStyle(color: Colors.orange),
                ),
              ] else ...[
                DropdownButtonFormField<String?>(
                  value: visionValue,
                  decoration: const InputDecoration(
                    labelText: 'Vision / 视觉模型 (建议 VLLM)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('跟随主对话模型 (默认)'),
                    ),
                    ...visionProviders.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(_isVisionRecommended(p) ? '${p.name} (VLLM)' : p.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedVisionProviderId = v),
                ),
              ],
              const SizedBox(height: 12),
              if (!hasEmbedding) ...[
                const Text(
                  '未检测到 Embedding 服务商。若使用记忆/检索，请补充配置。',
                  style: TextStyle(color: Colors.orange),
                ),
              ] else ...[
                DropdownButtonFormField<String?>(
                  value: embeddingValue,
                  decoration: const InputDecoration(
                    labelText: 'Embedding / 向量嵌入模型',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('暂不设置'),
                    ),
                    ...embeddingProviders.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.name),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedEmbeddingProviderId = v),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'Live2D 模型需用户自行导入（设置 -> 角色/Live2D）。',
                  style: TextStyle(color: Colors.blueGrey),
                ),
              ),
              const SizedBox(height: 24),
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _useDefaultPersona,
                    child: const Text('Use Default (Firefly) / 使用默认 Firefly'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _finish,
                    child: const Text('Start Journey / 开始旅程'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
