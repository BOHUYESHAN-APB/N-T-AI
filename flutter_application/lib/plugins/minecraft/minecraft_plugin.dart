import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';

import '../base_plugin.dart';

class MinecraftPlugin extends BasePlugin {
  MinecraftPlugin() {
    mindserverPortController = TextEditingController(text: '8080');
    modeController = TextEditingController(text: 'mindcraft');
  }

  late TextEditingController mindserverPortController;
  late TextEditingController modeController;
  
  String mode = 'mindcraft';
  int mindserverPort = 8080;
  Webview? _uiWebview;

  @override
  String get id => 'minecraft';

  @override
  String get name => 'Minecraft AI';

  @override
  String get description =>
      '集成 MindCraft 和 Mineflayer 机器人。支持 Web 端管理界面和 AI 代理。';

  @override
  IconData get icon => Icons.videogame_asset;

  @override
  Future<void> onInit() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    mode = prefs.getString('${prefix}mode') ?? 'mindcraft';
    mindserverPort = prefs.getInt('${prefix}mindserverPort') ?? 8080;
    
    modeController.text = mode;
    mindserverPortController.text = mindserverPort.toString();
  }

  @override
  Future<void> onEnable() async {
    await super.onEnable();
    await _syncWithBackend();
  }

  Future<void> _syncWithBackend() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
      
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'config': {
            'mode': mode,
            'mindserver_port': mindserverPort,
          }
        }),
      );
      if (response.statusCode != 200) {
        debugPrint('Failed to sync Minecraft plugin config: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error syncing Minecraft plugin config: $e');
    }
  }

  void openWebUI() async {
    if (mode != 'mindcraft') {
      return;
    }
    
    final url = 'http://localhost:$mindserverPort';
    _uiWebview = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        windowHeight: 800,
        windowWidth: 1200,
        title: "MindCraft Management UI",
      ),
    );
    _uiWebview?.launch(url);
  }

  @override
  Widget? buildSettingsWidget(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('运行模式', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButton<String>(
              value: mode,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'mindcraft', child: Text('MindCraft (高级 AI)')),
                DropdownMenuItem(value: 'mineflayer', child: Text('Mineflayer (基础机器人)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => mode = val);
                  _saveSettings();
                }
              },
            ),
            const SizedBox(height: 16),
            if (mode == 'mindcraft') ...[
              const Text('MindServer 端口', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: mindserverPortController,
                decoration: const InputDecoration(
                  hintText: '默认 8080',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final p = int.tryParse(val);
                  if (p != null) {
                    mindserverPort = p;
                    _saveSettings();
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: isEnabled ? openWebUI : null,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('打开管理界面'),
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _syncWithBackend(),
              child: const Text('同步并应用配置'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    await prefs.setString('${prefix}mode', mode);
    await prefs.setInt('${prefix}mindserverPort', mindserverPort);
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    if (!isEnabled) return null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.green),
                const SizedBox(width: 8),
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(mode, style: const TextStyle(fontSize: 10, color: Colors.green)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (mode == 'mindcraft')
              ElevatedButton(
                onPressed: openWebUI,
                child: const Text('管理机器人'),
              ),
            if (mode == 'mineflayer')
              const Text('Mineflayer 运行中...', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
