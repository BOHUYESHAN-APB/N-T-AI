import 'package:flutter/material.dart';
import '../core/services/brain_service.dart';
import '../settings/settings_controller.dart';

class FirstRunDialog extends StatefulWidget {
  final SettingsController settingsController;
  final BrainService brain;

  const FirstRunDialog({Key? key, required this.settingsController, required this.brain}) : super(key: key);

  @override
  State<FirstRunDialog> createState() => _FirstRunDialogState();
}

class _FirstRunDialogState extends State<FirstRunDialog> {
  final TextEditingController _nameController = TextEditingController(text: 'Firefly');
  final TextEditingController _promptController = TextEditingController();
  bool _isGenerating = false;
  String _selectedType = 'Anime Character (动漫角色)';

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
    await widget.settingsController.setIsFirstRun(false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
                      onPressed: _isGenerating ? null : _generatePersona,
                      icon: _isGenerating 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                        : const Icon(Icons.auto_awesome),
                      label: const Text('Auto-Generate Persona (Web Search) / 自动生成人设'),
                    ),
                  ),
                ],
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
              
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _useDefaultPersona,
                    child: const Text('Use Default (Firefly) / 使用默认流萤'),
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
