import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/llm_service.dart';
import '../../../settings/settings_scope.dart';
import '../../../settings/settings.dart';
import '../../../settings/settings_controller.dart';
import '../../../plugins/plugin_manager.dart';
import '../../../plugins/base_plugin.dart';

class CapabilitiesTab extends StatelessWidget {
  const CapabilitiesTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final settings = controller.settings;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, 'Python 神经中枢 (Neural Hub)'),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withOpacity(0.1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.hub,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '本地 Python 后端',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            '提供高级逻辑推理、向量记忆与复杂任务处理能力',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: true, // 强制开启
                      onChanged: null, // 禁止关闭
                    ),
                  ],
                ),
                // 强制显示后端控制
                const Divider(height: 24),
                _buildBackendControls(context, controller, settings),
                
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('启用思维链 (Thinking Mode)'),
                  subtitle: const Text('让模型展示推理过程 (需要模型支持，如 DeepSeek-R1)'),
                  value: settings.ai.enableThinking,
                  onChanged: (v) => controller.updateAiSettings(settings.ai.copyWith(enableThinking: v)),
                  secondary: Icon(
                    Icons.psychology,
                    color: settings.ai.enableThinking ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ),
                SwitchListTile(
                  title: const Text('搭话模式 (Initiative Mode)'),
                  subtitle: const Text('允许 AI 主动发起对话 (消耗 Tokens)'),
                  value: settings.ai.initiativeMode,
                  onChanged: (v) => controller.updateAiSettings(settings.ai.copyWith(initiativeMode: v)),
                  secondary: Icon(
                    Icons.record_voice_over,
                    color: settings.ai.initiativeMode ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ),
                SwitchListTile(
                  title: const Text('允许 AI 使用表情'),
                  subtitle: const Text('允许 AI 回复中包含 emoji/表情符号'),
                  value: settings.ai.allowEmojis,
                  onChanged: (v) => controller.updateAiSettings(settings.ai.copyWith(allowEmojis: v)),
                  secondary: Icon(
                    Icons.emoji_emotions_outlined,
                    color: settings.ai.allowEmojis ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                ),
                if (settings.ai.initiativeMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Row(
                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
                           children: [
                             Text(
                               '弹幕批处理间隔 (Danmaku Batch Interval)', 
                               style: Theme.of(context).textTheme.bodyMedium
                             ),
                             Text(
                               '${settings.ai.danmakuBatchInterval} 秒', 
                               style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
                             ),
                           ],
                         ),
                         Slider(
                           value: settings.ai.danmakuBatchInterval.toDouble().clamp(5.0, 300.0),
                           min: 5.0,
                           max: 300.0,
                           divisions: 59,
                           label: '${settings.ai.danmakuBatchInterval}s',
                           onChanged: (v) => controller.setAiDanmakuBatchInterval(v.toInt()),
                         ),
                         const Text(
                           '设置 AI 处理弹幕的最小间隔。间隔越短反应越快，但消耗更多 Token。',
                           style: TextStyle(fontSize: 12, color: Colors.grey),
                         ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        /* --- Frontend Basic Capabilities Removed ---
        const SizedBox(height: 16),
        _buildSectionHeader(context, '基础能力 (Basic)'),
        SwitchListTile(
          title: const Text('启用 Agent 模式'),
          subtitle: const Text('允许模型使用工具（如联网搜索、时间查询等）'),
          value: settings.agentEnabled,
          onChanged: (v) => controller.setAgentEnabled(v),
          secondary: const Icon(Icons.auto_awesome),
        ),
        SwitchListTile(
          title: const Text('联网搜索'),
          subtitle: Text(
            settings.enablePythonBackend
                ? '使用后端 Agent 进行聚合搜索'
                : '请求模型使用自带联网能力 (如 Perplexity/Gemini) 或调用本地 Bing 工具',
          ),
          value: settings.enableBrowser,
          onChanged: settings.agentEnabled
              ? (v) => controller.setEnableBrowser(v)
              : null,
          secondary: Icon(
            Icons.public,
            color: settings.agentEnabled ? null : Colors.grey,
          ),
        ),
        SwitchListTile(
          title: const Text('显示思考过程'),
          subtitle: const Text('在聊天中展示 Agent 的思维链 (Chain of Thought)'),
          value: settings.showAgentThoughts,
          onChanged: (v) => controller.setAgentShowThoughts(v),
          secondary: const Icon(Icons.psychology_outlined),
        ),
        */

        const Divider(height: 32),
        _buildSectionHeader(context, '视觉中枢 (Vision)'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: settings.activeVisionProviderId ?? 'follow_main',
                  decoration: const InputDecoration(
                    labelText: '视觉来源',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'follow_main',
                      child: Text('跟随主脑（优先使用主脑视觉）'),
                    ),
                    for (final p in controller.providers)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text('专用：${p.name}'),
                      ),
                  ],
                  onChanged: (v) => controller.setActiveVisionProvider(
                    v == 'follow_main' ? null : v,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('主脑具备视觉时优先使用'),
                  value: settings.useMainVisionIfCapable,
                  onChanged: (v) => controller.setUseMainVisionIfCapable(v),
                ),
                SwitchListTile(
                  title: const Text('无视觉时自动走 Agent'),
                  value: settings.visionFallbackToAgent,
                  onChanged: (v) => controller.setVisionFallbackToAgent(v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: TextEditingController(
                    text: settings.visionPromptTemplate,
                  ),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '默认视觉提示词',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) =>
                      controller.setVisionPromptTemplate(v.trim()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text('建议字数: ${settings.visionPreferredLength}'),
                    ),
                    Expanded(child: Text('最大字数: ${settings.visionMaxLength}')),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Slider(
                        value: settings.visionPreferredLength.toDouble(),
                        min: 60,
                        max: 200,
                        divisions: 14,
                        onChanged: (v) =>
                            controller.setVisionPreferredLength(v.round()),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: settings.visionMaxLength.toDouble(),
                        min: 200,
                        max: 500,
                        divisions: 6,
                        onChanged: (v) =>
                            controller.setVisionMaxLength(v.round()),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => _testVision(context, controller),
                    child: const Text('测试视觉'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader(context, '表情 Agent'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('启用表情 Agent'),
                subtitle: const Text('分析情绪并驱动表情'),
                value: settings.enableExpressionAgent,
                onChanged: (v) => controller.setEnableExpressionAgent(v),
              ),
              SwitchListTile(
                title: const Text('显示动态表情（灵动岛）'),
                subtitle: const Text('简约圆脸表情系统'),
                value: settings.showExpressionFace,
                onChanged: (v) => controller.setShowExpressionFace(v),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  value: settings.activeExpressionProviderId ?? 'follow_main',
                  decoration: const InputDecoration(
                    labelText: '表情推理模型',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: 'follow_main',
                      child: Text('跟随主脑'),
                    ),
                    for (final p in controller.providers)
                      DropdownMenuItem(
                        value: p.id,
                        child: Text('${p.name} (${p.model})'),
                      ),
                  ],
                  onChanged: (v) => controller.setActiveExpressionProvider(
                    v == 'follow_main' ? null : v,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionHeader(context, 'Live2D 显示'),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('启用 Live2D 侧边栏'),
                subtitle: const Text('在主界面右侧显示 Live2D 角色'),
                value: settings.showLive2D,
                onChanged: (v) => controller.setShowLive2D(v),
              ),
              SwitchListTile(
                title: const Text('启用 Live2D 悬浮窗'),
                subtitle: const Text('创建独立窗口（可被 OBS 捕获）'),
                value: settings.enableFloatingWindow,
                onChanged: (v) => controller.setEnableFloatingWindow(v),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _buildSectionHeader(context, '插件中心'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('插件管理与配置'),
            subtitle: const Text('统一启用、禁用并配置各类扩展插件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PluginCenterPage(),
                ),
              );
            },
          ),
        ),

        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionHeader(context, 'MCP 服务器'),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              tooltip: '添加服务器',
              onPressed: settings.enablePythonBackend
                  ? () => _showEditServerDialog(context, controller)
                  : null, // Disable add button if backend is off
            ),
          ],
        ),

        // Warning for MCP when backend is disabled
        if (!settings.enablePythonBackend)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.errorContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.error.withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '未启用 Python 后端：无法使用非官方默认工具 (MCP)。\n请在上方开启 "本地 Python 后端" 以启用此功能。',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

        const Padding(
          padding: EdgeInsets.only(bottom: 16.0),
          child: Text(
            '配置外部 MCP 服务器以扩展 AI 的能力。支持标准输入/输出 (stdio) 协议。',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ),
        if (settings.mcpServers.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: Text('暂无配置的 MCP 服务器'),
            ),
          )
        else
          ...settings.mcpServers.map(
            (server) => _buildServerTile(
              context,
              controller,
              server,
              enabled: settings.enablePythonBackend,
            ),
          ),
      ],
    );
  }

  void _testVision(BuildContext context, SettingsController controller) async {
    final picker = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (picker == null || picker.files.first.bytes == null) return;
    final bytes = picker.files.first.bytes!;
    final llm = LLMService();
    final s = controller.settings;
    final hint =
        '${s.visionPromptTemplate}\n长度建议约${s.visionPreferredLength}字，最多${s.visionMaxLength}字。';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在请求视觉分析...')));

    try {
      final result = await llm.chatWithImage(
        messages: const [
          {'role': 'system', 'content': '你是一个擅长中文描述的图像助手。'},
        ],
        imageBytes: bytes,
        prompt: hint,
        usageType: 'tool',
        providerIdOverride: controller.settings.activeVisionProviderId,
      );
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('视觉测试结果'),
          content: SingleChildScrollView(child: Text(result)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('视觉测试失败：$e')));
    }
  }

  Widget _buildBackendControls(
    BuildContext context,
    SettingsController controller,
    AppSettings settings,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(
                  text: settings.pythonBackendUrl,
                ),
                decoration: const InputDecoration(
                  labelText: '后端地址',
                  hintText: 'http://localhost:8000',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => controller.setPythonBackendUrl(v),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: () async {
                final url = Uri.parse('${settings.pythonBackendUrl}/docs');
                if (await canLaunchUrl(url)) {
                  launchUrl(url);
                }
              },
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('API 文档'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Placeholder buttons for process management
            // In a real implementation, these would call a native bridge or shell command
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('正在尝试启动后端进程...')));
                // TODO: Implement Process.run for backend
              },
              icon: const Icon(Icons.play_arrow, color: Colors.green),
              label: const Text('启动服务'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('正在停止服务...')));
              },
              icon: const Icon(Icons.stop, color: Colors.red),
              label: const Text('停止服务'),
            ),
          ],
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

  Widget _buildServerTile(
    BuildContext context,
    SettingsController controller,
    McpServerConfig server, {
    bool enabled = true,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: enabled ? null : Theme.of(context).disabledColor.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).dividerColor.withOpacity(0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        enabled: enabled,
        title: Text(
          server.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${server.command} ${server.args.join(" ")}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: server.enabled,
              onChanged: enabled
                  ? (v) {
                      controller.updateMcpServer(server.copyWith(enabled: v));
                    }
                  : null,
            ),
            PopupMenuButton<String>(
              enabled: enabled,
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditServerDialog(context, controller, server: server);
                } else if (value == 'delete') {
                  _confirmDelete(context, controller, server);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    SettingsController controller,
    McpServerConfig server,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 MCP 服务器 "${server.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              controller.removeMcpServer(server.id);
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showEditServerDialog(
    BuildContext context,
    SettingsController controller, {
    McpServerConfig? server,
  }) {
    final isEditing = server != null;
    final nameCtrl = TextEditingController(text: server?.name ?? '');
    final cmdCtrl = TextEditingController(text: server?.command ?? '');
    final argsCtrl = TextEditingController(text: server?.args.join(' ') ?? '');
    final envCtrl = TextEditingController(
      text:
          server?.env.entries.map((e) => '${e.key}=${e.value}').join('\n') ??
          '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? '编辑 MCP 服务器' : '添加 MCP 服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '例如: Filesystem Server',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cmdCtrl,
                decoration: const InputDecoration(
                  labelText: '命令 (Command)',
                  hintText: '例如: npx, python, docker',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: argsCtrl,
                decoration: const InputDecoration(
                  labelText: '参数 (Arguments)',
                  hintText:
                      '空格分隔，例如: -y @modelcontextprotocol/server-filesystem',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: envCtrl,
                decoration: const InputDecoration(
                  labelText: '环境变量 (Environment)',
                  hintText: 'KEY=VALUE (每行一个)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isEmpty || cmdCtrl.text.isEmpty) return;

              final args = argsCtrl.text
                  .trim()
                  .split(RegExp(r'\s+'))
                  .where((e) => e.isNotEmpty)
                  .toList();

              final env = <String, String>{};
              final envLines = envCtrl.text.split('\n');
              for (final line in envLines) {
                final parts = line.split('=');
                if (parts.length >= 2) {
                  env[parts[0].trim()] = parts.sublist(1).join('=').trim();
                }
              }

              final newServer = McpServerConfig(
                id:
                    server?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                name: nameCtrl.text,
                command: cmdCtrl.text,
                args: args,
                env: env,
                enabled: server?.enabled ?? true,
              );

              if (isEditing) {
                controller.updateMcpServer(newServer);
              } else {
                controller.addMcpServer(newServer);
              }
              Navigator.pop(context);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

class PluginCenterPage extends StatefulWidget {
  const PluginCenterPage({Key? key}) : super(key: key);

  @override
  State<PluginCenterPage> createState() => _PluginCenterPageState();
}

class _PluginCenterPageState extends State<PluginCenterPage> {
  String? _expandedPluginId;

  @override
  void initState() {
    super.initState();
    globalPluginManager.ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件中心'),
      ),
      body: AnimatedBuilder(
        animation: globalPluginManager,
        builder: (context, _) {
          final plugins = globalPluginManager.allPlugins;
          if (plugins.isEmpty) {
            return const Center(
              child: Text('暂无可用插件'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plugins.length,
            itemBuilder: (context, index) {
              final plugin = plugins[index];
              final settingsWidget = plugin.buildSettingsWidget(context);
              final hasSettings = settingsWidget != null;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(plugin.icon),
                      title: Text(plugin.name),
                      subtitle: Text(plugin.description),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: plugin.isEnabled,
                            onChanged: (v) async {
                              await globalPluginManager.togglePlugin(plugin.id, v);
                              if (v) {
                                await plugin.onSync(context);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('已同步 ${plugin.name} 配置')),
                                  );
                                }
                              }
                            },
                          ),
                          if (hasSettings)
                            IconButton(
                              icon: const Icon(Icons.tune),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PluginDetailPage(plugin: plugin),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      onTap: hasSettings
                          ? () {
                              setState(() {
                                if (_expandedPluginId == plugin.id) {
                                  _expandedPluginId = null;
                                } else {
                                  _expandedPluginId = plugin.id;
                                }
                              });
                            }
                          : null,
                    ),
                    if (hasSettings && _expandedPluginId == plugin.id)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: settingsWidget,
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class PluginDetailPage extends StatelessWidget {
  final BasePlugin plugin;

  const PluginDetailPage({Key? key, required this.plugin}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final settingsWidget = plugin.buildSettingsWidget(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(plugin.name),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(plugin.icon),
              title: Text(plugin.name),
              subtitle: Text(plugin.description),
              trailing: Switch(
                value: plugin.isEnabled,
                onChanged: (v) async {
                  await globalPluginManager.togglePlugin(plugin.id, v);
                  if (v) {
                    await plugin.onSync(context);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已同步 ${plugin.name} 配置')),
                      );
                    }
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (settingsWidget != null)
            settingsWidget
          else
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text('该插件暂无可配置项'),
              ),
            ),
        ],
      ),
    );
  }
}
