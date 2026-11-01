import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../settings/settings.dart';
import '../settings/settings_scope.dart';

class ToolsConfigurationScreen extends StatefulWidget {
  const ToolsConfigurationScreen({super.key});

  @override
  State<ToolsConfigurationScreen> createState() => _ToolsConfigurationScreenState();
}

class _ToolsConfigurationScreenState extends State<ToolsConfigurationScreen> {
  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final s = controller.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('工具箱配置')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('内置工具', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.public),
            title: const Text('Web Browser'),
            subtitle: const Text('允许 Agent 访问互联网进行搜索和浏览'),
            value: s.enableBrowser,
            onChanged: (v) => controller.setEnableBrowser(v),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                const Expanded(child: Text('MCP 服务器 (Model Context Protocol)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _editMcpServer(context, null),
                  tooltip: '添加 MCP 服务器',
                ),
              ],
            ),
          ),
          if (s.mcpServers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('暂无配置的 MCP 服务器', style: TextStyle(color: Colors.grey)),
            ),
          for (final server in s.mcpServers)
            ListTile(
              leading: const Icon(Icons.dns),
              title: Text(server.name),
              subtitle: Text('${server.command} ${server.args.join(" ")}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: server.enabled,
                    onChanged: (v) => controller.updateMcpServer(server.copyWith(enabled: v)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _editMcpServer(context, server),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => controller.removeMcpServer(server.id),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _editMcpServer(BuildContext context, McpServerConfig? existing) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final cmdCtrl = TextEditingController(text: existing?.command ?? '');
    final argsCtrl = TextEditingController(text: existing?.args.join(' ') ?? '');
    final envCtrl = TextEditingController(text: existing?.env.entries.map((e) => '${e.key}=${e.value}').join('\n') ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? '添加 MCP 服务器' : '编辑 MCP 服务器'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称', hintText: '例如: Filesystem Server'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: cmdCtrl,
                decoration: const InputDecoration(labelText: '命令 (Command)', hintText: '例如: npx, python, docker'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: argsCtrl,
                decoration: const InputDecoration(labelText: '参数 (Arguments)', hintText: '空格分隔，例如: -m mcp_server'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: envCtrl,
                decoration: const InputDecoration(labelText: '环境变量 (Environment)', hintText: 'KEY=VALUE (每行一个)'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.isEmpty || cmdCtrl.text.isEmpty) return;
              
              final env = <String, String>{};
              for (final line in envCtrl.text.split('\n')) {
                final parts = line.split('=');
                if (parts.length >= 2) {
                  env[parts[0].trim()] = parts.sublist(1).join('=').trim();
                }
              }

              final newServer = McpServerConfig(
                id: existing?.id ?? const Uuid().v4(),
                name: nameCtrl.text,
                command: cmdCtrl.text,
                args: argsCtrl.text.split(' ').where((e) => e.isNotEmpty).toList(),
                env: env,
                enabled: existing?.enabled ?? true,
              );

              final controller = SettingsScope.of(context);
              if (existing == null) {
                controller.addMcpServer(newServer);
              } else {
                controller.updateMcpServer(newServer);
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
