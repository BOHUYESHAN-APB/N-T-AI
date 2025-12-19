import 'package:flutter/material.dart';
import '../plugins/plugin_manager.dart';
import '../plugins/base_plugin.dart';

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
                                    SnackBar(content: Text('已启用 ${plugin.name}')),
                                  );
                                }
                              }
                            },
                          ),
                          if (hasSettings)
                            IconButton(
                              icon: Icon(_expandedPluginId == plugin.id
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                              onPressed: () {
                                setState(() {
                                  if (_expandedPluginId == plugin.id) {
                                    _expandedPluginId = null;
                                  } else {
                                    _expandedPluginId = plugin.id;
                                  }
                                });
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
