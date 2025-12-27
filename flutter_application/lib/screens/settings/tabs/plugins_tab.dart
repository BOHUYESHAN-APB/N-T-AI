import 'package:flutter/material.dart';
import '../../plugin_center_page.dart';
import '../../../plugins/plugin_manager.dart';
import '../../../plugins/base_plugin.dart';

class PluginsTab extends StatefulWidget {
  const PluginsTab({super.key});

  @override
  State<PluginsTab> createState() => _PluginsTabState();
}

class _PluginsTabState extends State<PluginsTab> {
  @override
  void initState() {
    super.initState();
    globalPluginManager.ensureInitialized();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: globalPluginManager,
      builder: (context, _) {
        final plugins = globalPluginManager.allPlugins;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader(context, '插件管理'),
            if (plugins.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('暂无可用插件'),
                ),
              )
            else
              ...plugins.map((plugin) => _buildPluginCard(context, plugin)),
          ],
        );
      },
    );
  }

  Widget _buildPluginCard(BuildContext context, BasePlugin plugin) {
    final quickSettings = plugin.buildQuickSettings(context);
    final hasFullSettings = plugin.buildSettingsWidget(context) != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(plugin.icon, color: plugin.isEnabled ? Theme.of(context).colorScheme.primary : null),
        title: Text(plugin.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(plugin.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Switch(
          value: plugin.isEnabled,
          onChanged: (v) async {
            await globalPluginManager.togglePlugin(plugin.id, v);
            if (!context.mounted) return;
            if (v) {
              await plugin.onSync(context);
            }
            if (!context.mounted) return;
            setState(() {});
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.power_settings_new, size: 20),
                const SizedBox(width: 8),
                const Text('启动软件时自动开启'),
                const Spacer(),
                Switch(
                  value: plugin.autoStart,
                  onChanged: (v) async {
                    await globalPluginManager.toggleAutoStart(plugin.id, v);
                    if (!context.mounted) return;
                    // 同步到后端
                    await plugin.onSync(context);
                    if (!context.mounted) return;
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          if (quickSettings != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: quickSettings,
            ),
          if (hasFullSettings)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PluginDetailPage(plugin: plugin),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('详细配置'),
                ),
              ),
            ),
        ],
      ),
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
}
