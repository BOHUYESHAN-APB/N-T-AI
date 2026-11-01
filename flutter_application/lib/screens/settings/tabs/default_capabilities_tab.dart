import 'package:flutter/material.dart';
import '../../../settings/settings_scope.dart';
import '../../../settings/settings.dart';
import '../../../settings/settings_controller.dart';
import '../../memory_manager_screen.dart'; // For Data section

class DefaultCapabilitiesTab extends StatefulWidget {
  const DefaultCapabilitiesTab({super.key});

  @override
  State<DefaultCapabilitiesTab> createState() => _DefaultCapabilitiesTabState();
}

class _DefaultCapabilitiesTabState extends State<DefaultCapabilitiesTab> {
  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final providers = controller.providers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, '思维与交互 (Cognition)'),
        SwitchListTile(
          title: const Text('启用思维链 (Thinking Mode)'),
          subtitle: const Text('让模型展示推理过程 (需要模型支持，如 DeepSeek-R1)'),
          value: settings.showAgentThoughts,
          onChanged: (v) => controller.setAgentShowThoughts(v),
          secondary: const Icon(Icons.psychology),
        ),
        SwitchListTile(
          title: const Text('搭话模式 (后端心跳)'),
          subtitle: const Text('由后端心跳触发主动对话 (消耗 Tokens)'),
          value: settings.ai.initiativeMode,
          onChanged: (v) =>
              controller.updateAiSettings(settings.ai.copyWith(initiativeMode: v)),
          secondary: const Icon(Icons.record_voice_over),
        ),

        const Divider(height: 32),
        
        // --- Merged Agents Logic ---
        _buildSectionHeader(context, '能力分流 (Capabilities)'),
        const Text(
          '配置独立 Agent，用于分离任务（视觉/工具/自定义）',
          style: TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        
        // Reusing the Special Agents Section logic from AgentsTab
        // We need to access the controller methods.
        // To avoid code duplication, we can extract this widget or copy it here.
        // For simplicity in this refactor, I'll copy the simplified logic.
        
        _buildCapabilityTile(
          context,
          icon: Icons.image_search,
          title: '视觉识别 (Vision)',
          currentId: settings.activeVisionProviderId,
          controller: controller,
          onTap: () => _showProviderSelector(
            context,
            controller,
            providers,
            '选择视觉服务商',
            settings.activeVisionProviderId,
            (id) => controller.setActiveVisionProvider(id),
          ),
        ),
        _buildCapabilityTile(
          context,
          icon: Icons.directions_run,
          title: '动作决策 (Motion)',
          currentId: settings.activeMotionProviderId,
          controller: controller,
          onTap: () => _showProviderSelector(
            context,
            controller,
            providers,
            '选择动作决策服务商',
            settings.activeMotionProviderId,
            (id) => controller.setActiveMotionProvider(id),
          ),
        ),
        _buildCapabilityTile(
          context,
          icon: Icons.construction,
          title: '工具调用 (Tool Calling)',
          currentId: settings.activeToolCallingProviderId,
          controller: controller,
          onTap: () => _showProviderSelector(
            context,
            controller,
            providers,
            '选择工具调用服务商',
            settings.activeToolCallingProviderId,
            (id) => controller.setActiveToolCallingProvider(id),
          ),
        ),
        _buildCapabilityTile(
          context,
          icon: Icons.manage_search,
          title: '深度研究 (Deep Research)',
          currentId: settings.activeDeepResearchProviderId,
          controller: controller,
          onTap: () => _showProviderSelector(
            context,
            controller,
            providers,
            '选择深度研究服务商',
            settings.activeDeepResearchProviderId,
            (id) => controller.setActiveDeepResearchProvider(id),
          ),
        ),
        _buildCapabilityTile(
          context,
          icon: Icons.hub,
          title: '向量嵌入 (Embedding)',
          currentId: settings.activeEmbeddingProviderId,
          controller: controller,
          onTap: () => _showProviderSelector(
            context,
            controller,
            providers,
            '选择 Embedding 服务商',
            settings.activeEmbeddingProviderId,
            (id) => controller.updateActiveEmbeddingProviderId(id),
          ),
        ),
        _buildCapabilityTile(
          context,
          icon: Icons.auto_fix_high,
          title: '语音修正 (Speech Refine)',
          currentId: settings.activeSpeechRefinerProviderId,
          controller: controller,
          onTap: () => _showProviderSelector(
            context,
            controller,
            providers,
            '选择语音修正服务商',
            settings.activeSpeechRefinerProviderId,
            (id) => controller.setActiveSpeechRefinerProvider(id),
          ),
        ),

        const Divider(height: 32),
        _buildSectionHeader(context, '视觉中枢 (Vision)'),
        SwitchListTile(
          title: const Text('启用定时屏幕截取'),
          subtitle: const Text('每隔一段时间自动截取屏幕并让 AI 分析（环境感知）'),
          value: settings.enableScreenCapture,
          onChanged: (v) => controller.setEnableScreenCapture(v),
          secondary: Icon(
            Icons.screen_search_desktop_outlined,
            color: settings.enableScreenCapture
                ? Theme.of(context).colorScheme.primary
                : Colors.grey,
          ),
        ),
        if (settings.enableScreenCapture) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('截取间隔（秒）'),
                    Text(
                      settings.screenCaptureInterval > 0
                          ? '当前: ${settings.screenCaptureInterval}s'
                          : '随机 10–50 秒（偏左正态）',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(
                    text: settings.screenCaptureInterval.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '输入截取间隔（0=随机）',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed == null) return;
                    controller.setScreenCaptureInterval(parsed);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('注入间隔（秒）'),
                    Text(
                      '当前: ${settings.screenCaptureInjectInterval}s',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: TextEditingController(
                    text: settings.screenCaptureInjectInterval.toString(),
                  ),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '输入注入间隔（建议 30/60 秒）',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed == null) return;
                    controller.setScreenCaptureInjectInterval(parsed);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: TextEditingController(
                text: settings.screenCaptureIdleSeconds.toString(),
              ),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '空闲注入阈值（秒，0=不限制）',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) {
                final parsed = int.tryParse(v.trim());
                if (parsed == null) return;
                controller.setScreenCaptureIdleSeconds(parsed);
              },
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: TextEditingController(
                text: settings.screenAnalysisPrompt,
              ),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '屏幕分析提示词',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => controller.setScreenAnalysisPrompt(v.trim()),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: TextEditingController(
                text: settings.screenInjectionPrompt,
              ),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '消息注入提示词',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (v) => controller.setScreenInjectionPrompt(v.trim()),
            ),
          ),
        ],

        const Divider(height: 32),
        _buildSectionHeader(context, '数据管理 (Data)'),
        ListTile(
          leading: const Icon(Icons.memory),
          title: const Text('记忆数据库'),
          subtitle: Text(settings.enablePythonBackend 
              ? '管理长期记忆与知识库' 
              : '需启用 Python 后端以使用此功能'),
          trailing: const Icon(Icons.chevron_right),
          enabled: settings.enablePythonBackend,
          onTap: settings.enablePythonBackend ? () {
             Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MemoryManagerScreen(),
                ),
              );
          } : null,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCapabilityTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String? currentId,
    required SettingsController controller,
    required VoidCallback onTap,
  }) {
    final p = currentId == null ? null : controller.getProviderById(currentId);
    final subtitle = p?.name ?? '跟随主脑 (默认)';

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('当前: $subtitle'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
            leading: const Icon(Icons.psychology_outlined),
            title: const Text('跟随主脑 (默认)'),
            subtitle: const Text('使用当前活跃的对话服务商'),
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
}
