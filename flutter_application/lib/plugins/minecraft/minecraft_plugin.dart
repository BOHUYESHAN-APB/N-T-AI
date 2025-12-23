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
    mcHostController = TextEditingController(text: '127.0.0.1');
    mcPortController = TextEditingController(text: '25565');
    mcLanguageController = TextEditingController(text: 'zh');
    mcVersionController = TextEditingController(text: 'auto');
    mcUserController = TextEditingController();
    mcPassController = TextEditingController();
  }

  late TextEditingController mindserverPortController;
  late TextEditingController modeController;
  late TextEditingController mcHostController;
  late TextEditingController mcPortController;
  late TextEditingController mcLanguageController;
  late TextEditingController mcVersionController;
  late TextEditingController mcUserController;
  late TextEditingController mcPassController;
  
  String mode = 'mindcraft';
  int mindserverPort = 8080;
  String mcHost = '127.0.0.1';
  int mcPort = 25565;
  String mcAuth = 'offline';
  String mcUser = '';
  String mcPass = '';
  String mcBaseProfile = 'assistant';
  String mcLanguage = 'zh';
  String mcVersion = 'auto';
  bool allowVision = false;
  bool allowInsecureCoding = false;
  bool chatInGame = true;
  bool speak = false;

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
    mcHost = prefs.getString('${prefix}mcHost') ?? '127.0.0.1';
    mcPort = prefs.getInt('${prefix}mcPort') ?? 25565;
    mcAuth = prefs.getString('${prefix}mcAuth') ?? 'offline';
    mcUser = prefs.getString('${prefix}mcUser') ?? '';
    mcPass = prefs.getString('${prefix}mcPass') ?? '';
    mcBaseProfile = prefs.getString('${prefix}mcBaseProfile') ?? 'assistant';
    mcLanguage = prefs.getString('${prefix}mcLanguage') ?? 'zh';
    mcVersion = prefs.getString('${prefix}mcVersion') ?? 'auto';
    allowVision = prefs.getBool('${prefix}allowVision') ?? false;
    allowInsecureCoding = prefs.getBool('${prefix}allowInsecureCoding') ?? false;
    chatInGame = prefs.getBool('${prefix}chatInGame') ?? true;
    speak = prefs.getBool('${prefix}speak') ?? false;
    
    modeController.text = mode;
    mindserverPortController.text = mindserverPort.toString();
    mcHostController.text = mcHost;
    mcPortController.text = mcPort.toString();
    mcLanguageController.text = mcLanguage;
    mcVersionController.text = mcVersion;
    mcUserController.text = mcUser;
    mcPassController.text = mcPass;
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
            'mc_host': mcHost,
            'mc_port': mcPort,
            'mc_auth': mcAuth,
            'mc_user': mcUser,
            'mc_pass': mcPass,
            'mc_base_profile': mcBaseProfile,
            'mc_language': mcLanguage,
            'mc_version': mcVersion,
            'allow_vision': allowVision,
            'allow_insecure_coding': allowInsecureCoding,
            'chat_ingame': chatInGame,
            'speak': speak,
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
  Widget? buildQuickSettings(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          children: [
            SwitchListTile(
              title: const Text('启用视觉 (Allow Vision)'),
              value: allowVision,
              onChanged: (val) {
                setState(() => allowVision = val);
                _saveSettings();
              },
            ),
            SwitchListTile(
              title: const Text('不安全代码执行'),
              value: allowInsecureCoding,
              onChanged: (val) {
                setState(() => allowInsecureCoding = val);
                _saveSettings();
              },
            ),
            SwitchListTile(
              title: const Text('游戏内聊天'),
              value: chatInGame,
              onChanged: (val) {
                setState(() => chatInGame = val);
                _saveSettings();
              },
            ),
            SwitchListTile(
              title: const Text('语音输出'),
              value: speak,
              onChanged: (val) {
                setState(() => speak = val);
                _saveSettings();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget? buildSettingsWidget(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('1. 核心运行模式', Icons.settings_applications),
              _buildModeSelection(setState),
              const SizedBox(height: 24),
              
              _buildSectionHeader('2. 服务器连接设置 (通用)', Icons.lan),
              _buildCommonConnectionSettings(setState),
              const SizedBox(height: 24),

              if (mode == 'mindcraft') ...[
                _buildSectionHeader('3. MindCraft 高级 AI 配置', Icons.psychology),
                _buildMindCraftSettings(setState),
              ],
              
              if (mode == 'mineflayer') ...[
                _buildSectionHeader('3. Mineflayer 基础机器人配置', Icons.smart_toy),
                _buildMineflayerSettings(setState),
              ],

              const SizedBox(height: 32),
              _buildSyncButton(),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueAccent),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelection(StateSetter setState) {
    return Card(
      elevation: 0,
      color: Colors.blue.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.blue.withValues(alpha: 0.2))),
      child: Column(
        children: [
          RadioListTile<String>(
            title: const Text('MindCraft (自主 AI 代理)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('支持视觉、长期记忆、自主决策和任务规划。基于大模型驱动的高级 AI。'),
            value: 'mindcraft',
            groupValue: mode,
            onChanged: (val) {
              if (val != null) {
                setState(() => mode = val);
                _saveSettings();
              }
            },
          ),
          const Divider(height: 1),
          RadioListTile<String>(
            title: const Text('Mineflayer (基础脚本机器人)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('轻量级机器人，主要用于简单的自动化脚本、聊天回复或基础操作。'),
            value: 'mineflayer',
            groupValue: mode,
            onChanged: (val) {
              if (val != null) {
                setState(() => mode = val);
                _saveSettings();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommonConnectionSettings(StateSetter setState) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: mcHostController,
                decoration: const InputDecoration(
                  labelText: '服务器地址 (Host)',
                  hintText: '127.0.0.1 或 域名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.dns),
                ),
                onChanged: (val) {
                  mcHost = val;
                  _saveSettings();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextField(
                controller: mcPortController,
                decoration: const InputDecoration(
                  labelText: '端口',
                  hintText: '25565',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final p = int.tryParse(val);
                  if (p != null) {
                    mcPort = p;
                    _saveSettings();
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: mcAuth,
          decoration: const InputDecoration(
            labelText: '认证方式',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.security),
          ),
          items: const [
            DropdownMenuItem(value: 'offline', child: Text('离线模式 (Offline)')),
            DropdownMenuItem(value: 'microsoft', child: Text('微软正版账户 (Microsoft)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => mcAuth = val);
              _saveSettings();
            }
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: mcUserController,
          decoration: InputDecoration(
            labelText: mcAuth == 'offline' ? '角色名 (Username)' : '微软邮箱 (Email)',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person),
          ),
          onChanged: (val) {
            mcUser = val;
            _saveSettings();
          },
        ),
        if (mcAuth == 'microsoft') ...[
          const SizedBox(height: 16),
          TextField(
            controller: mcPassController,
            decoration: const InputDecoration(
              labelText: '微软密码 (Password)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
            obscureText: true,
            onChanged: (val) {
              mcPass = val;
              _saveSettings();
            },
          ),
        ],
      ],
    );
  }

  Widget _buildMindCraftSettings(StateSetter setState) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: mcBaseProfile,
          decoration: const InputDecoration(
            labelText: '预设配置文件',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.assignment_ind),
          ),
          items: const [
            DropdownMenuItem(value: 'assistant', child: Text('全能助手 (Assistant)')),
            DropdownMenuItem(value: 'main-brain', child: Text('主脑直连 (Main Brain)')),
            DropdownMenuItem(value: 'survival', child: Text('生存专家 (Survival)')),
            DropdownMenuItem(value: 'creative', child: Text('创造大师 (Creative)')),
            DropdownMenuItem(value: 'god_mode', child: Text('管理员模式 (God Mode)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => mcBaseProfile = val);
              _saveSettings();
            }
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: mcVersionController,
                decoration: const InputDecoration(
                  labelText: 'MC 版本',
                  hintText: 'auto / 1.21.1',
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  mcVersion = val;
                  _saveSettings();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: mcLanguageController,
                decoration: const InputDecoration(
                  labelText: '交互语言',
                  hintText: 'zh / en',
                  border: OutlineInputBorder(),
                ),
                onChanged: (val) {
                  mcLanguage = val;
                  _saveSettings();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: mindserverPortController,
          decoration: const InputDecoration(
            labelText: 'MindServer 管理端口',
            hintText: '默认 8080',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.settings_ethernet),
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
        _buildQuickSwitches(setState),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: isEnabled ? openWebUI : null,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('打开高级管理界面 (Web UI)'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildMineflayerSettings(StateSetter setState) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Mineflayer 模式目前处于基础运行状态，将执行默认的 echo 脚本。未来版本将开放更多自定义脚本配置。',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildQuickSwitches(StateSetter setState) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('启用 AI 视觉'),
            subtitle: const Text('允许机器人获取游戏截图并理解环境'),
            value: allowVision,
            onChanged: (val) {
              setState(() => allowVision = val);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('允许不安全代码'),
            subtitle: const Text('赋予 AI 直接在宿主机运行生成的脚本权限'),
            value: allowInsecureCoding,
            onChanged: (val) {
              setState(() => allowInsecureCoding = val);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('同步游戏聊天'),
            subtitle: const Text('将 AI 的思考和回复同步到 MC 游戏公屏'),
            value: chatInGame,
            onChanged: (val) {
              setState(() => chatInGame = val);
              _saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('启用语音输出'),
            subtitle: const Text('通过 TTS 让 AI 朗读其回复'),
            value: speak,
            onChanged: (val) {
              setState(() => speak = val);
              _saveSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _syncWithBackend(),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('保存并同步配置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    await prefs.setString('${prefix}mode', mode);
    await prefs.setInt('${prefix}mindserverPort', mindserverPort);
    await prefs.setString('${prefix}mcHost', mcHost);
    await prefs.setInt('${prefix}mcPort', mcPort);
    await prefs.setString('${prefix}mcAuth', mcAuth);
    await prefs.setString('${prefix}mcUser', mcUser);
    await prefs.setString('${prefix}mcPass', mcPass);
    await prefs.setString('${prefix}mcBaseProfile', mcBaseProfile);
    await prefs.setString('${prefix}mcLanguage', mcLanguage);
    await prefs.setString('${prefix}mcVersion', mcVersion);
    await prefs.setBool('${prefix}allowVision', allowVision);
    await prefs.setBool('${prefix}allowInsecureCoding', allowInsecureCoding);
    await prefs.setBool('${prefix}chatInGame', chatInGame);
    await prefs.setBool('${prefix}speak', speak);
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
                    color: Colors.green.withValues(alpha: 0.2),
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
