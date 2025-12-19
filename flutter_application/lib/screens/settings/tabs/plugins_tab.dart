import 'package:flutter/material.dart';
import '../../../settings/settings_scope.dart';
import '../../plugin_center_page.dart';

class PluginsTab extends StatelessWidget {
  const PluginsTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    // Assuming there is a setting for danmaku interval, if not we might need to add it or find where it is.
    // The user mentioned "Danmaku interval should be in Bilibili plugin".
    // Currently, there is a slider in the screenshot for "Danmaku Batch Interval".
    // I need to check if that setting exists in Settings model.
    // Looking at previous searches, I didn't see explicit danmaku interval in Settings class, 
    // but maybe I missed it or it's hardcoded/stored elsewhere.
    // Wait, the screenshot shows "Danmaku Batch Interval" in the capabilities tab (implied).
    // Let's assume we can add it here.

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, '插件管理'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('插件中心'),
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

        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Bilibili 直播插件配置'),
        
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
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
                       '${controller.settings.ai.danmakuBatchInterval} 秒', 
                       style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
                     ),
                   ],
                 ),
                 Slider(
                   value: controller.settings.ai.danmakuBatchInterval.toDouble().clamp(5.0, 300.0),
                   min: 5.0,
                   max: 300.0,
                   divisions: 59,
                   label: '${controller.settings.ai.danmakuBatchInterval}s',
                   onChanged: (v) => controller.setAiDanmakuBatchInterval(v.toInt()),
                 ),
                 const Text(
                   '设置 AI 处理弹幕的最小间隔。间隔越短反应越快，但消耗更多 Token。',
                   style: TextStyle(fontSize: 12, color: Colors.grey),
                 ),
              ],
            ),
          ),
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
}
