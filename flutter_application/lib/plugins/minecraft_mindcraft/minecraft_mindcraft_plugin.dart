import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../settings/settings_scope.dart';
import '../base_plugin.dart';

class MinecraftMindcraftPlugin extends BasePlugin with ChangeNotifier {
  MinecraftMindcraftPlugin() {
    hostController = TextEditingController();
    portController = TextEditingController();
    initMessageController = TextEditingController();
    minecraftVersionController = TextEditingController();
    agentNameController = TextEditingController();
    agentModelController = TextEditingController();
    msEmailController = TextEditingController();
    msPasswordController = TextEditingController();
    mindServerPortController = TextEditingController();
  }

  late TextEditingController hostController;
  late TextEditingController portController;
  late TextEditingController initMessageController;
  late TextEditingController minecraftVersionController;
  late TextEditingController agentNameController;
  late TextEditingController agentModelController;
  late TextEditingController msEmailController;
  late TextEditingController msPasswordController;
  late TextEditingController mindServerPortController;

  String authMethod = 'offline';
  bool loadMemory = false;
  String? agentProviderId;
  String language = 'zh';

  List<String> _logs = [];
  String? _msAuthCode;
  String? _msAuthUrl;
  Timer? _statusTimer;
  bool _statusInFlight = false;
  static const int _maxLogLines = 200;
  int _lastLogCount = 0;
  String? _lastLogTail;
  String? _lastMsAuthCode;
  String? _lastMsAuthUrl;

  // 添加对 notifyListeners 的包装以兼容 BasePlugin
  void _notify() {
    notifyListeners();
  }

  // 内部 setState 模拟
  void _updateState(VoidCallback fn) {
    fn();
    notifyListeners();
  }

  @override
  String get id => 'Minecraft-mindcraft';

  @override
  String get name => 'Minecraft MindCraft';

  @override
  String get description => '基于 MindCraft 的高级 Minecraft 智能代理插件（版本随 MindCraft 原始项目更新，适配 1.21.6）。';

  @override
  IconData get icon => Icons.videogame_asset;

  @override
  Future<void> onInit() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    hostController.text = prefs.getString('${prefix}host') ?? '127.0.0.1';
    portController.text = prefs.getString('${prefix}port') ?? '-1';
    initMessageController.text = prefs.getString('${prefix}initMessage') ?? '你好！我是你的 AI 助手。';
    minecraftVersionController.text = prefs.getString('${prefix}minecraftVersion') ?? 'auto';
    agentNameController.text = prefs.getString('${prefix}agentName') ?? 'andy';
    agentModelController.text = prefs.getString('${prefix}agentModel') ?? '';
    msEmailController.text = prefs.getString('${prefix}msEmail') ?? '';
    msPasswordController.text = prefs.getString('${prefix}msPassword') ?? '';
    mindServerPortController.text = prefs.getString('${prefix}mindServerPort') ?? '8080';
    authMethod = prefs.getString('${prefix}authMethod') ?? 'offline';
    loadMemory = prefs.getBool('${prefix}loadMemory') ?? false;
    agentProviderId = prefs.getString('${prefix}agentProviderId');
    language = prefs.getString('${prefix}language') ?? 'zh';
    autoStart = prefs.getBool('${prefix}autoStart') ?? false;

    if (isEnabled) {
      _startStatusTimer();
    }
  }

  Future<void> _saveLocalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    await prefs.setString('${prefix}host', hostController.text);
    await prefs.setString('${prefix}port', portController.text);
    await prefs.setString('${prefix}initMessage', initMessageController.text);
    await prefs.setString('${prefix}minecraftVersion', minecraftVersionController.text);
    await prefs.setString('${prefix}agentName', agentNameController.text);
    await prefs.setString('${prefix}agentModel', agentModelController.text);
    await prefs.setString('${prefix}msEmail', msEmailController.text);
    await prefs.setString('${prefix}msPassword', msPasswordController.text);
    await prefs.setString('${prefix}mindServerPort', mindServerPortController.text);
    await prefs.setString('${prefix}authMethod', authMethod);
    await prefs.setBool('${prefix}loadMemory', loadMemory);
    await prefs.setString('${prefix}language', language);
    await prefs.setBool('${prefix}autoStart', autoStart);
    if (agentProviderId != null) {
      await prefs.setString('${prefix}agentProviderId', agentProviderId!);
    }
  }

  Future<bool> syncConfigToBackend(BuildContext context) async {
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final backendUrl = settings.pythonBackendUrl.replaceAll(RegExp(r'/$'), '');
    final providers = controller.providers;

    String effectiveModel = agentModelController.text.trim();
    String? agentApiKey;
    String? agentBaseUrl;

    if (agentProviderId == 'main-brain') {
      // Resolve Main Brain config from active provider
      dynamic selectedProvider = controller.activeProviderConfig;
      
      if (selectedProvider != null) {
        agentApiKey = selectedProvider.apiKey;
        agentBaseUrl = selectedProvider.baseUrl;
        
        // If the model is not specified in the text field, use the provider's model
        if (effectiveModel.isEmpty) {
          effectiveModel = selectedProvider.model ?? '';
        }
        
        // If the base URL is local (pointing to backend), keep it. 
        // Otherwise, this will allow the plugin to connect directly to the provider,
        // bypassing the backend proxy issues.
      } else {
        // Fallback to internal placeholder if something goes wrong
        effectiveModel = 'main-brain';
        agentApiKey = 'sk-ntai-internal';
        agentBaseUrl = '$backendUrl/api/v1';
      }
    } else {
      // Find the provider config
      dynamic selectedProvider;
      if (agentProviderId != null && agentProviderId!.isNotEmpty) {
        try {
          selectedProvider = providers.firstWhere((p) => p.id == agentProviderId);
        } catch (_) {
          selectedProvider = controller.activeProviderConfig;
        }
      } else {
        selectedProvider = controller.activeProviderConfig;
      }

      if (selectedProvider != null) {
        agentApiKey = selectedProvider.apiKey;
        agentBaseUrl = selectedProvider.baseUrl;
        if (effectiveModel.isEmpty) {
          effectiveModel = selectedProvider.model ?? '';
        }
      }
    }

    final config = {
      "minecraft_version": minecraftVersionController.text,
      "host": hostController.text,
      "port": int.tryParse(portController.text) ?? -1,
      "auth": authMethod,
      "mindserver_port": int.tryParse(mindServerPortController.text) ?? 8080,
      "ms_email": msEmailController.text,
      "ms_password": msPasswordController.text,
      "load_memory": loadMemory,
      "init_message": initMessageController.text,
      "language": language,
      "agent_name": agentNameController.text,
      "agent_model": effectiveModel,
      "agent_api_key": agentApiKey,
      "agent_base_url": agentBaseUrl,
      "auto_start": autoStart,
    };

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'config': config}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error syncing config: $e');
      return false;
    }
  }

  @override
  Future<void> onEnable() async {
    await super.onEnable();
    _startStatusTimer();
  }

  @override
  Future<void> onDisable() async {
    await super.onDisable();
    _statusTimer?.cancel();
  }

  void _startStatusTimer() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (isEnabled) {
        _fetchStatus();
      }
    });
  }

  Future<void> _fetchStatus() async {
    if (_statusInFlight) return;
    _statusInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // 使用 SharedPreferences 中存储的后端地址
      String backendUrl = prefs.getString('settings.backend.url') ?? 'http://127.0.0.1:23456';
      backendUrl = backendUrl.replaceAll(RegExp(r'/$'), '');
      
      final response = await http.get(
        Uri.parse('$backendUrl/api/v1/plugins/$id/status'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawLogs = List<String>.from(data['logs'] ?? []);
        final trimmedLogs = rawLogs.length > _maxLogLines
            ? rawLogs.sublist(rawLogs.length - _maxLogLines)
            : rawLogs;
        final nextMsAuthCode = data['ms_auth_code'];
        final nextMsAuthUrl = data['ms_auth_url'];
        final tail = trimmedLogs.isNotEmpty ? trimmedLogs.last : null;
        final changed = trimmedLogs.length != _lastLogCount ||
            tail != _lastLogTail ||
            nextMsAuthCode != _lastMsAuthCode ||
            nextMsAuthUrl != _lastMsAuthUrl;

        if (!changed) return;

        _logs = trimmedLogs;
        _msAuthCode = nextMsAuthCode;
        _msAuthUrl = nextMsAuthUrl;
        _lastLogCount = trimmedLogs.length;
        _lastLogTail = tail;
        _lastMsAuthCode = nextMsAuthCode;
        _lastMsAuthUrl = nextMsAuthUrl;
        _notify();
      }
    } catch (e) {
      print('Error fetching Minecraft status: $e');
    } finally {
      _statusInFlight = false;
    }
  }

  @override
  Widget buildSettingsWidget(BuildContext context) {
    final providers = SettingsScope.of(context).providers;

    return AnimatedBuilder(
      animation: this,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('服务器连接'),
              const Text('支持版本: Java Edition（版本随 MindCraft 原始项目更新，适配 v1.21.6）', 
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: hostController,
                decoration: const InputDecoration(labelText: '服务器地址 (Host)', hintText: '127.0.0.1'),
              ),
              TextField(
                controller: portController,
                decoration: const InputDecoration(labelText: '端口 (Port)', hintText: '-1 (自动检测)'),
                keyboardType: TextInputType.number,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: minecraftVersionController,
                      decoration: const InputDecoration(labelText: 'MC 版本', hintText: 'auto 或 1.21.6'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: mindServerPortController,
                      decoration: const InputDecoration(labelText: '管理端口', hintText: '8080'),
                    ),
                  ),
                ],
              ),
              DropdownButtonFormField<String>(
                value: authMethod,
                decoration: const InputDecoration(labelText: '登录方式'),
                items: const [
                  DropdownMenuItem(value: 'offline', child: Text('离线模式 (Offline)')),
                  DropdownMenuItem(value: 'microsoft', child: Text('微软登录 (Microsoft)')),
                ],
                onChanged: (v) => _updateState(() => authMethod = v!),
              ),
              if (authMethod == 'microsoft') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: msEmailController,
                        decoration: const InputDecoration(labelText: '微软邮箱 (可选)', hintText: 'example@outlook.com'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: msPasswordController,
                        decoration: const InputDecoration(labelText: '密码 (可选)', hintText: '******'),
                        obscureText: true,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8, left: 4),
                  child: Text('注：填写账号密码可尝试自动登录，留空则使用验证码登录。', 
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 16),
              _buildSectionTitle('AI 代理配置'),
              DropdownButtonFormField<String?>(
                value: agentProviderId,
                decoration: const InputDecoration(labelText: 'AI 服务商'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('使用系统当前激活的服务商')),
                  const DropdownMenuItem(value: 'main-brain', child: Text('主脑 (代理到主系统的 LLM 设置)')),
                  ...providers.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))),
                ],
                onChanged: (v) => _updateState(() => agentProviderId = v),
              ),
              TextField(
                controller: agentNameController,
                decoration: const InputDecoration(labelText: 'AI 代理名称 (必须与游戏内角色名一致)', hintText: 'andy'),
              ),
              TextField(
                controller: agentModelController,
                decoration: const InputDecoration(labelText: '模型名称', hintText: '留空则使用服务商默认模型'),
              ),
              TextField(
                controller: initMessageController,
                decoration: const InputDecoration(labelText: '初始化消息'),
              ),
              SwitchListTile(
                title: const Text('加载记忆 (Load Memory)'),
                value: loadMemory,
                onChanged: (v) => _updateState(() => loadMemory = v),
              ),
              SwitchListTile(
                title: const Text('启动时自动开启 (Auto Start)'),
                subtitle: const Text('当后端服务启动时，自动初始化并运行此插件'),
                value: autoStart,
                onChanged: (v) => _updateState(() => autoStart = v),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _saveLocalConfig();
                        final success = await syncConfigToBackend(context);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(success ? '配置已同步并尝试重启插件' : '同步失败，请检查后端连接')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.blue.withOpacity(0.1),
                      ),
                      icon: const Icon(Icons.sync),
                      label: const Text('同步配置并重启插件'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _openWebUI(),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('管理页面'),
                  ),
                ],
              ),
              if (authMethod == 'microsoft') ...[
                const SizedBox(height: 24),
                _buildSectionTitle('微软登录验证流程'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _msAuthCode != null ? Colors.orange.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                    border: Border.all(color: _msAuthCode != null ? Colors.orange : Colors.grey),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_msAuthCode == null) ...[
                        const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 12),
                            Expanded(child: Text('等待后端捕获验证码...\n请确保已点击“同步配置”且插件正在启动。', style: TextStyle(color: Colors.grey))),
                          ],
                        ),
                      ] else ...[
                        const Text('第一步：复制下方 8 位验证码', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: Center(
                            child: SelectableText(
                              _msAuthCode!,
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                                letterSpacing: 4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('第二步：点击下方按钮前往微软页面输入代码', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _launchUrl(_msAuthUrl),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.vpn_key),
                          label: const Text('前往微软验证页面'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildSectionTitle('实时运行日志'),
              Container(
                height: 300,
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    final log = _logs[_logs.length - 1 - index];
                    return Text(
                      log,
                      style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _openWebUI(),
                icon: const Icon(Icons.open_in_browser),
                label: const Text('打开 MindCraft 管理界面'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _launchUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openWebUI() async {
    final port = mindServerPortController.text.trim();
    final effectivePort = port.isEmpty ? '8080' : port;
    final uri = Uri.parse('http://localhost:$effectivePort/index.html');
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
