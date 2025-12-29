import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../settings/settings_controller.dart';
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
    modHostController = TextEditingController();
    modPortController = TextEditingController();
    modTokenController = TextEditingController();
    headfulQuickTextController = TextEditingController();
    headfulActionController = TextEditingController();
    headfulCraftItemController = TextEditingController();
    headfulCraftCountController = TextEditingController(text: '1');
    headfulPlanGoalController = TextEditingController();
    headfulRagUserIdController = TextEditingController();
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
  late TextEditingController modHostController;
  late TextEditingController modPortController;
  late TextEditingController modTokenController;
  late TextEditingController headfulQuickTextController;
  late TextEditingController headfulActionController;
  late TextEditingController headfulCraftItemController;
  late TextEditingController headfulCraftCountController;
  late TextEditingController headfulPlanGoalController;
  late TextEditingController headfulRagUserIdController;

  String controlMode = 'headless'; // headless: 现有无头；headful: Fabric 模组
  String authMethod = 'offline';
  bool loadMemory = false;
  String? agentProviderId;
  String language = 'zh';
  int modEventIntervalMs = 200;
  int modScanRadius = 16;
  bool modVisionStream = false;
  bool headfulPlanUseRag = true;
  bool headfulPlanUseMindcraftDocs = true;

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
  String? _backendControlMode;
  bool? _headfulReady;
  Map<String, dynamic>? _headfulState;
  String? _lastHeadfulStateSig;
  bool? _lastHeadfulReady;
  String? _lastBackendControlMode;
  Map<String, dynamic>? _headfulPlan;
  String? _lastHeadfulPlanSig;

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
    final headlessPrefix = '${prefix}headless.';
    final headfulPrefix = '${prefix}headful.';
    controlMode = prefs.getString('${prefix}mode') ?? 'headless';

    // headless（兼容旧字段）
    hostController.text =
        prefs.getString('${headlessPrefix}host') ?? prefs.getString('${prefix}host') ?? '127.0.0.1';
    portController.text =
        prefs.getString('${headlessPrefix}port') ?? prefs.getString('${prefix}port') ?? '-1';
    initMessageController.text =
        prefs.getString('${headlessPrefix}initMessage') ?? prefs.getString('${prefix}initMessage') ?? '你好！我是你的 AI 助手。';
    minecraftVersionController.text =
        prefs.getString('${headlessPrefix}minecraftVersion') ?? prefs.getString('${prefix}minecraftVersion') ?? 'auto';
    agentNameController.text =
        prefs.getString('${headlessPrefix}agentName') ?? prefs.getString('${prefix}agentName') ?? 'andy';
    agentModelController.text =
        prefs.getString('${headlessPrefix}agentModel') ?? prefs.getString('${prefix}agentModel') ?? '';
    msEmailController.text =
        prefs.getString('${headlessPrefix}msEmail') ?? prefs.getString('${prefix}msEmail') ?? '';
    msPasswordController.text =
        prefs.getString('${headlessPrefix}msPassword') ?? prefs.getString('${prefix}msPassword') ?? '';
    mindServerPortController.text =
        prefs.getString('${headlessPrefix}mindServerPort') ?? prefs.getString('${prefix}mindServerPort') ?? '8080';
    authMethod = prefs.getString('${headlessPrefix}authMethod') ?? prefs.getString('${prefix}authMethod') ?? 'offline';
    loadMemory = prefs.getBool('${headlessPrefix}loadMemory') ?? prefs.getBool('${prefix}loadMemory') ?? false;
    agentProviderId = prefs.getString('${headlessPrefix}agentProviderId') ?? prefs.getString('${prefix}agentProviderId');
    language = prefs.getString('${headlessPrefix}language') ?? prefs.getString('${prefix}language') ?? 'zh';
    autoStart = prefs.getBool('${prefix}autoStart') ?? false;

    // headful（模组通讯）
    modHostController.text = prefs.getString('${headfulPrefix}host') ?? '127.0.0.1';
    modPortController.text = prefs.getString('${headfulPrefix}port') ?? '8765';
    modTokenController.text = prefs.getString('${headfulPrefix}token') ?? '';
    modEventIntervalMs = prefs.getInt('${headfulPrefix}eventIntervalMs') ?? 200;
    modScanRadius = prefs.getInt('${headfulPrefix}scanRadius') ?? 16;
    modVisionStream = prefs.getBool('${headfulPrefix}visionStream') ?? false;
    headfulRagUserIdController.text = prefs.getString('${headfulPrefix}ragUserId') ?? '';

    if (isEnabled) {
      _startStatusTimer();
    }
  }

  Future<void> _saveLocalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    final headlessPrefix = '${prefix}headless.';
    final headfulPrefix = '${prefix}headful.';
    await prefs.setString('${prefix}mode', controlMode);
    // headless 存储（兼容旧字段）
    await prefs.setString('${headlessPrefix}host', hostController.text);
    await prefs.setString('${headlessPrefix}port', portController.text);
    await prefs.setString('${headlessPrefix}initMessage', initMessageController.text);
    await prefs.setString('${headlessPrefix}minecraftVersion', minecraftVersionController.text);
    await prefs.setString('${headlessPrefix}agentName', agentNameController.text);
    await prefs.setString('${headlessPrefix}agentModel', agentModelController.text);
    await prefs.setString('${headlessPrefix}msEmail', msEmailController.text);
    await prefs.setString('${headlessPrefix}msPassword', msPasswordController.text);
    await prefs.setString('${headlessPrefix}mindServerPort', mindServerPortController.text);
    await prefs.setString('${headlessPrefix}authMethod', authMethod);
    await prefs.setBool('${headlessPrefix}loadMemory', loadMemory);
    await prefs.setString('${headlessPrefix}language', language);
    // 兼容旧字段存一份
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
    // headful 存储
    await prefs.setString('${headfulPrefix}host', modHostController.text);
    await prefs.setString('${headfulPrefix}port', modPortController.text);
    await prefs.setString('${headfulPrefix}token', modTokenController.text);
    await prefs.setInt('${headfulPrefix}eventIntervalMs', modEventIntervalMs);
    await prefs.setInt('${headfulPrefix}scanRadius', modScanRadius);
    await prefs.setBool('${headfulPrefix}visionStream', modVisionStream);
    await prefs.setString('${headfulPrefix}ragUserId', headfulRagUserIdController.text);
    await prefs.setBool('${prefix}autoStart', autoStart);
    if (agentProviderId != null) {
      await prefs.setString('${prefix}agentProviderId', agentProviderId!);
    }
  }

  Future<bool> syncConfigToBackend(SettingsController controller) async {
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

    final headfulConfig = {
      "host": modHostController.text.trim().isEmpty ? "127.0.0.1" : modHostController.text.trim(),
      "port": int.tryParse(modPortController.text) ?? 8765,
      "token": modTokenController.text.trim(),
      "event_interval_ms": modEventIntervalMs,
      "scan_radius": modScanRadius,
      "vision_stream": modVisionStream,
    };

    final config = {
      "control_mode": controlMode,
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
      "rag_user_id": headfulRagUserIdController.text.trim(),
      "auto_start": autoStart,
      "headful": headfulConfig,
    };

    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'config': config}),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error syncing config: $e');
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
        final nextBackendControlMode = data['control_mode']?.toString();
        final nextHeadfulReady = data['headful_ready'];
        final nextHeadfulStateRaw = data['headful_state'];
        final nextHeadfulPlanRaw = data['headful_plan'];
        Map<String, dynamic>? nextHeadfulState;
        if (nextHeadfulStateRaw is Map<String, dynamic>) {
          nextHeadfulState = nextHeadfulStateRaw;
        } else if (nextHeadfulStateRaw is Map) {
          nextHeadfulState = Map<String, dynamic>.from(nextHeadfulStateRaw);
        }
        Map<String, dynamic>? nextHeadfulPlan;
        if (nextHeadfulPlanRaw is Map<String, dynamic>) {
          nextHeadfulPlan = nextHeadfulPlanRaw;
        } else if (nextHeadfulPlanRaw is Map) {
          nextHeadfulPlan = Map<String, dynamic>.from(nextHeadfulPlanRaw);
        }
        final nextHeadfulStateSig = nextHeadfulState == null ? null : jsonEncode(nextHeadfulState);
        final nextHeadfulPlanSig = nextHeadfulPlan == null ? null : jsonEncode(nextHeadfulPlan);
        final tail = trimmedLogs.isNotEmpty ? trimmedLogs.last : null;
        final changed = trimmedLogs.length != _lastLogCount ||
            tail != _lastLogTail ||
            nextMsAuthCode != _lastMsAuthCode ||
            nextMsAuthUrl != _lastMsAuthUrl ||
            nextBackendControlMode != _lastBackendControlMode ||
            nextHeadfulReady != _lastHeadfulReady ||
            nextHeadfulStateSig != _lastHeadfulStateSig ||
            nextHeadfulPlanSig != _lastHeadfulPlanSig;

        if (!changed) return;

        _logs = trimmedLogs;
        _msAuthCode = nextMsAuthCode;
        _msAuthUrl = nextMsAuthUrl;
        _backendControlMode = nextBackendControlMode;
        _headfulReady = nextHeadfulReady is bool ? nextHeadfulReady : null;
        _headfulState = nextHeadfulState;
        _headfulPlan = nextHeadfulPlan;
        _lastLogCount = trimmedLogs.length;
        _lastLogTail = tail;
        _lastMsAuthCode = nextMsAuthCode;
        _lastMsAuthUrl = nextMsAuthUrl;
        _lastBackendControlMode = nextBackendControlMode;
        _lastHeadfulReady = _headfulReady;
        _lastHeadfulStateSig = nextHeadfulStateSig;
        _lastHeadfulPlanSig = nextHeadfulPlanSig;
        _notify();
      }
    } catch (e) {
      debugPrint('Error fetching Minecraft status: $e');
    } finally {
      _statusInFlight = false;
    }
  }

  Future<void> _sendHeadfulQuickMessage(BuildContext context) async {
    final message = headfulQuickTextController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入要发送的聊天或指令')),
      );
      return;
    }
    final controller = SettingsScope.of(context);
    final backendUrl = controller.settings.pythonBackendUrl.replaceAll(RegExp(r'/$'), '');
    final agentName = agentNameController.text.trim().isEmpty ? 'agent' : agentNameController.text.trim();
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/send_message'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'agent': agentName,
          'message': message,
          'sender': 'frontend',
        }),
      );
      if (!context.mounted) return;
      final ok = response.statusCode == 200;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '已发送' : '发送失败: ${response.statusCode}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    }
  }

  Future<void> _sendHeadfulActionJson(BuildContext context) async {
    final raw = headfulActionController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入动作 JSON')),
      );
      return;
    }
    Map<String, dynamic> action;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Action must be a JSON object');
      }
      action = decoded;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('动作 JSON 无效: $e')),
      );
      return;
    }
    await _sendHeadfulAction(context, action);
  }

  Future<void> _sendHeadfulAction(BuildContext context, Map<String, dynamic> action) async {
    if (!action.containsKey('type')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('动作 JSON 缺少 type 字段')),
      );
      return;
    }
    final controller = SettingsScope.of(context);
    final backendUrl = controller.settings.pythonBackendUrl.replaceAll(RegExp(r'/$'), '');
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/headful_action'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action}),
      );
      if (!context.mounted) return;
      final ok = response.statusCode == 200;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '动作已发送' : '动作发送失败: ${response.statusCode}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('动作发送失败: $e')),
      );
    }
  }

  Future<void> _sendHeadfulSkill(
    BuildContext context,
    String skill, {
    Map<String, dynamic>? params,
  }) async {
    final controller = SettingsScope.of(context);
    final backendUrl = controller.settings.pythonBackendUrl.replaceAll(RegExp(r'/$'), '');
    final payloadParams = Map<String, dynamic>.from(params ?? {});
    if (!payloadParams.containsKey('rag_user_id') ||
        (payloadParams['rag_user_id'] is String && (payloadParams['rag_user_id'] as String).trim().isEmpty)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final sessionId = prefs.getString('chat.currentSessionId');
        if (sessionId != null && sessionId.trim().isNotEmpty) {
          payloadParams['rag_user_id'] = sessionId.trim();
        }
      } catch (_) {}
    }
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/headful_skill'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'skill': skill,
          'params': payloadParams,
        }),
      );
      if (!context.mounted) return;
      final ok = response.statusCode == 200;
      String message = ok ? '技能已发送' : '技能失败: ${response.statusCode}';
      if (!ok) {
        try {
          final data = jsonDecode(response.body);
          final detail = data is Map<String, dynamic> ? data['detail'] : null;
          if (detail != null) {
            message = '技能失败: $detail';
          }
        } catch (_) {}
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('技能发送失败: $e')),
      );
    }
  }

  double _stateNumber(String key, double fallback) {
    final state = _headfulState;
    if (state == null) return fallback;
    final val = state[key];
    if (val is num) return val.toDouble();
    return fallback;
  }

  double _normalizeYaw(double yaw) {
    var value = yaw % 360;
    if (value < 0) value += 360;
    return value;
  }

  double _clampPitch(double pitch) {
    final clamped = pitch.clamp(-90.0, 90.0);
    return clamped is num ? clamped.toDouble() : pitch;
  }

  String _formatHeadfulPlanAction(dynamic action) {
    if (action is! Map) return action.toString();
    final type = action['type']?.toString() ?? 'unknown';
    switch (type) {
      case 'equip':
        return '装备: ${action['sourceSlot']} -> ${action['target']}';
      case 'moveStack':
        return '移动堆叠: ${action['fromSlot']} -> ${action['toSlot']}';
      case 'moveOne':
        return '移动单个: ${action['fromSlot']} -> ${action['toSlot']}';
      case 'quickMove':
        return '快速移动: ${action['slot']}';
      case 'clickSlot':
        return '点击槽位: ${action['slot']} action=${action['action']} btn=${action['button'] ?? 0}';
      case 'openInventory':
        return '打开背包';
      case 'closeScreen':
        return '关闭界面';
      case 'screenSnapshot':
        return '刷新快照';
      case 'wait':
        return '等待 ${action['ms']}ms';
      default:
        return jsonEncode(action);
    }
  }

  void _showHeadfulPlanDialog(BuildContext context) {
    final plan = _headfulPlan;
    showDialog(
      context: context,
      builder: (dialogContext) {
        final actionsRaw = plan?['actions'];
        final actions = actionsRaw is List ? actionsRaw : <dynamic>[];
        final reason = plan?['reason']?.toString();
        final planner = plan?['planner']?.toString();
        final planText = plan?['plan_text']?.toString();
        final warningsRaw = plan?['warnings'];
        final warnings = warningsRaw is List
            ? warningsRaw.map((w) => w.toString()).toList()
            : <String>[];
        final traceRaw = plan?['trace'];
        final trace = traceRaw is List ? traceRaw : <dynamic>[];
        final autoError = plan?['auto_error']?.toString();
        final autoSubsteps = plan?['auto_substeps'];

        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.article_outlined),
                      const SizedBox(width: 8),
                      const Text(
                        '规划窗口',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan == null ? '暂无规划' : '规划器：${planner ?? "--"}',
                    style: const TextStyle(color: Colors.black87),
                  ),
                  if (reason != null && reason.isNotEmpty)
                    Text('原因：$reason'),
                  if (autoError != null && autoError.isNotEmpty)
                    Text('自动合成异常：$autoError', style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (planText != null && planText.isNotEmpty) ...[
                            const Text('文本计划', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            SelectableText(
                              planText,
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          const Text('步骤', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          if (actions.isEmpty)
                            const Text('暂无可执行步骤')
                          else
                            ...actions.asMap().entries.map(
                                  (entry) => Text(
                                    '${entry.key + 1}. ${_formatHeadfulPlanAction(entry.value)}',
                                    style: const TextStyle(fontFamily: 'monospace'),
                                  ),
                                ),
                          if (autoSubsteps is List && autoSubsteps.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('自动合成子步骤', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            ...autoSubsteps.map((step) => Text(step.toString())),
                          ],
                          if (warnings.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('警告：${warnings.join('；')}', style: const TextStyle(color: Colors.orange)),
                          ],
                          if (trace.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('回退链路', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            ...trace.map((entry) {
                              if (entry is! Map) return Text(entry.toString());
                              final plannerName = entry['planner']?.toString() ?? '--';
                              final stepCount = entry['actions']?.toString() ?? '--';
                              final entryReason = entry['reason']?.toString();
                              final entryError = entry['error']?.toString();
                              final parts = <String>[
                                plannerName,
                                'steps=$stepCount',
                                if (entryReason != null && entryReason.isNotEmpty) entryReason,
                                if (entryError != null && entryError.isNotEmpty) 'error=$entryError',
                              ];
                              return Text(parts.join(' | '));
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendHeadfulLookDelta(BuildContext context, double deltaYaw, double deltaPitch) async {
    final baseYaw = _stateNumber('yaw', 0);
    final basePitch = _stateNumber('pitch', 0);
    final yaw = _normalizeYaw(baseYaw + deltaYaw);
    final pitch = _clampPitch(basePitch + deltaPitch);
    await _sendHeadfulAction(context, {
      'type': 'look',
      'yaw': yaw,
      'pitch': pitch,
    });
  }

  Future<void> _sendHeadfulLookSmoothDelta(
    BuildContext context,
    double deltaYaw,
    double deltaPitch, {
    int durationMs = 400,
  }) async {
    final baseYaw = _stateNumber('yaw', 0);
    final basePitch = _stateNumber('pitch', 0);
    final yaw = _normalizeYaw(baseYaw + deltaYaw);
    final pitch = _clampPitch(basePitch + deltaPitch);
    await _sendHeadfulAction(context, {
      'type': 'lookSmooth',
      'yaw': yaw,
      'pitch': pitch,
      'durationMs': durationMs,
    });
  }

  @override
  Widget buildSettingsWidget(BuildContext context) {
    final providers = SettingsScope.of(context).providers;

    return AnimatedBuilder(
      animation: this,
      builder: (context, _) {
        String fmtNum(dynamic v, {int digits = 2}) {
          if (v is num) {
            return v.toStringAsFixed(digits);
          }
          return '--';
        }

        Widget buildHeadfulStatusCard() {
          final backendMode = _backendControlMode ?? controlMode;
          final modeMismatch = _backendControlMode != null && _backendControlMode != controlMode;
          final ready = _headfulReady == true;
          final state = _headfulState;
          final posText = state == null
              ? '--'
              : '${fmtNum(state['x'])}, ${fmtNum(state['y'])}, ${fmtNum(state['z'])}';
          final yawText = state == null ? '--' : fmtNum(state['yaw'], digits: 1);
          final pitchText = state == null ? '--' : fmtNum(state['pitch'], digits: 1);
          final hpText = state == null ? '--' : fmtNum(state['health'], digits: 1);
          final foodText = state == null ? '--' : fmtNum(state['hunger'], digits: 0);
          final dimText = state == null ? '--' : (state['dimension']?.toString() ?? '--');
          final focusedText = state == null ? '--' : ((state['focused'] == true) ? '是' : '否');

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ready ? '模组连接：已连接' : '模组连接：未连接',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: ready ? Colors.green : Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  modeMismatch ? '后端模式：$backendMode（本地选择：$controlMode）' : '后端模式：$backendMode',
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Text('位置：$posText  视角：$yawText/$pitchText'),
                Text('血量：$hpText  饥饿：$foodText'),
                Text('维度：$dimText  窗口焦点：$focusedText'),
              ],
            ),
          );
        }

        Widget buildHeadfulPlanSummary(BuildContext context) {
          final plan = _headfulPlan;
          final goal = plan?['goal']?.toString() ?? '--';
          final reason = plan?['reason']?.toString();
          final planner = plan?['planner']?.toString();
          final actionsRaw = plan?['actions'];
          final actions = actionsRaw is List ? actionsRaw : <dynamic>[];
          final executed = plan?['executed'];
          final summary = plan == null
              ? '暂无规划'
              : '步骤 ${actions.length}，${executed != null ? "已执行 $executed" : "未执行"}';

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '规划摘要',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text('目标：$goal'),
                      if (planner != null && planner.isNotEmpty) Text('规划器：$planner'),
                      if (reason != null && reason.isNotEmpty) Text('原因：$reason'),
                      Text(summary),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: plan == null ? null : () => _showHeadfulPlanDialog(context),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('查看详情'),
                ),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('运行模式'),
              DropdownButtonFormField<String>(
                value: controlMode,
                decoration: const InputDecoration(labelText: '选择运行模式'),
                items: const [
                  DropdownMenuItem(value: 'headless', child: Text('无头 (MindCraft/mineflayer)')),
                  DropdownMenuItem(value: 'headful', child: Text('有头 (Fabric 模组通讯)')),
                ],
                onChanged: (v) => _updateState(() => controlMode = v ?? 'headless'),
              ),
              const SizedBox(height: 12),
              if (controlMode == 'headful') ...[
                _buildSectionTitle('模组通讯（本地客户端）'),
                const Text('绑定 127.0.0.1，需在本地运行 Fabric 模组提供的 WS/HTTP。', style: TextStyle(color: Colors.green)),
                const SizedBox(height: 8),
                buildHeadfulStatusCard(),
                const SizedBox(height: 12),
                TextField(
                  controller: modHostController,
                  decoration: const InputDecoration(labelText: '模组 Host', hintText: '127.0.0.1'),
                ),
                TextField(
                  controller: modPortController,
                  decoration: const InputDecoration(labelText: '模组端口', hintText: '8765'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: modTokenController,
                  decoration: const InputDecoration(labelText: '访问口令 (可选)', hintText: '为空则不校验'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: modEventIntervalMs.toString(),
                        decoration: const InputDecoration(labelText: '事件频率 ms', hintText: '200'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => modEventIntervalMs = int.tryParse(v) ?? 200,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: modScanRadius.toString(),
                        decoration: const InputDecoration(labelText: '扫描半径', hintText: '16'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => modScanRadius = int.tryParse(v) ?? 16,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  title: const Text('启用视觉流 (预留)'),
                  subtitle: const Text('预留画面/特征流通道，后续接入视觉解析'),
                  value: modVisionStream,
                  onChanged: (v) => _updateState(() => modVisionStream = v),
                ),
                TextField(
                  controller: headfulRagUserIdController,
                  decoration: const InputDecoration(
                    labelText: 'RAG 用户 ID (可选)',
                    hintText: '留空则使用 AI 代理名称',
                  ),
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('Headful 快捷控制'),
                const Text('用于本地模组调试，可发送聊天/指令或动作 JSON。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: headfulQuickTextController,
                  decoration: const InputDecoration(labelText: '聊天/指令', hintText: '你好 或 /time set day'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulQuickMessage(context),
                      icon: const Icon(Icons.send),
                      label: const Text('发送聊天/指令'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => headfulQuickTextController.clear(),
                      icon: const Icon(Icons.clear),
                      label: const Text('清空输入'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: headfulActionController,
                  minLines: 3,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: '动作 JSON',
                    hintText: '{"type":"moveTo","x":0,"y":64,"z":0,"speed":0.25}',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulActionJson(context),
                      icon: const Icon(Icons.bolt),
                      label: const Text('发送动作'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => headfulActionController.text =
                          '{"type":"moveTo","x":0,"y":64,"z":0,"speed":0.25}',
                      icon: const Icon(Icons.code),
                      label: const Text('填充示例'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        headfulActionController.text = '{"type":"stopMove"}';
                        _sendHeadfulActionJson(context);
                      },
                      icon: const Icon(Icons.stop),
                      label: const Text('停止移动'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('预置动作'),
                const Text('用于快速测试移动输入（模拟方向键）。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'move',
                        'forward': 1,
                        'durationMs': 500,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_up),
                      label: const Text('前进'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'move',
                        'forward': -1,
                        'durationMs': 500,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      label: const Text('后退'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'move',
                        'strafe': -1,
                        'durationMs': 500,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_left),
                      label: const Text('左移'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'move',
                        'strafe': 1,
                        'durationMs': 500,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_right),
                      label: const Text('右移'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'move',
                        'jump': true,
                        'durationMs': 250,
                      }),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('跳跃'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'move',
                        'forward': 1,
                        'sprint': true,
                        'durationMs': 800,
                      }),
                      icon: const Icon(Icons.directions_run),
                      label: const Text('冲刺前进'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'stopMove',
                      }),
                      icon: const Icon(Icons.stop),
                      label: const Text('停步'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('持续按键'),
                const Text('用于长时间按住（需要手动释放）。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'forward',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_up),
                      label: const Text('按住前进'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'back',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_down),
                      label: const Text('按住后退'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'left',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_left),
                      label: const Text('按住左移'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'right',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.keyboard_arrow_right),
                      label: const Text('按住右移'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'sprint',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.directions_run),
                      label: const Text('按住疾跑'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'sneak',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.south),
                      label: const Text('按住潜行'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'attack',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.gavel),
                      label: const Text('按住攻击'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'setKey',
                        'key': 'use',
                        'pressed': true,
                      }),
                      icon: const Icon(Icons.pan_tool_alt),
                      label: const Text('按住使用'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'releaseAllKeys',
                      }),
                      icon: const Icon(Icons.stop),
                      label: const Text('释放全部'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('轻触按键'),
                const Text('用于触发单次按键行为。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'tapKey',
                        'key': 'attack',
                        'durationMs': 120,
                      }),
                      icon: const Icon(Icons.flash_on),
                      label: const Text('短按攻击'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'tapKey',
                        'key': 'use',
                        'durationMs': 120,
                      }),
                      icon: const Icon(Icons.touch_app),
                      label: const Text('短按使用'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'tapKey',
                        'key': 'drop',
                        'durationMs': 120,
                      }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('丢弃手持'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'tapKey',
                        'key': 'swap',
                        'durationMs': 120,
                      }),
                      icon: const Icon(Icons.sync_alt),
                      label: const Text('交换副手'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('界面/容器'),
                const Text('打开/关闭界面或请求容器快照。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'openInventory',
                      }),
                      icon: const Icon(Icons.inventory_2),
                      label: const Text('打开背包'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'closeScreen',
                      }),
                      icon: const Icon(Icons.close),
                      label: const Text('关闭界面'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'screenSnapshot',
                      }),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('容器快照'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulSkill(context, 'set_debug', params: {
                        'enabled': true,
                        'chat': false,
                      }),
                      icon: const Icon(Icons.bug_report),
                      label: const Text('开启调试'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulSkill(context, 'set_debug', params: {
                        'enabled': false,
                      }),
                      icon: const Icon(Icons.bug_report_outlined),
                      label: const Text('关闭调试'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('背包/容器技能'),
                const Text('自动装备、热键整理与容器转移（基础版）。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulSkill(context, 'auto_equip'),
                      icon: const Icon(Icons.shield),
                      label: const Text('自动装备'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulSkill(context, 'auto_sort_hotbar'),
                      icon: const Icon(Icons.view_week),
                      label: const Text('整理热键栏'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulSkill(context, 'container_transfer',
                          params: {'direction': 'to_inventory'}),
                      icon: const Icon(Icons.move_to_inbox),
                      label: const Text('容器 -> 背包'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulSkill(context, 'container_transfer',
                          params: {'direction': 'to_container'}),
                      icon: const Icon(Icons.outbox),
                      label: const Text('背包 -> 容器'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: headfulCraftItemController,
                        decoration: const InputDecoration(
                          labelText: '合成目标',
                          hintText: 'diamond_pickaxe',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: headfulCraftCountController,
                        decoration: const InputDecoration(
                          labelText: '数量',
                          hintText: '1',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        final item = headfulCraftItemController.text.trim();
                        final count = int.tryParse(headfulCraftCountController.text.trim()) ?? 1;
                        if (item.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入合成目标')),
                          );
                          return;
                        }
                        _sendHeadfulSkill(context, 'craft_from_container', params: {
                          'item': item,
                          'count': count,
                          'smart_pickup': true,
                          'precise_pickup': true,
                          'multi_container': true,
                          'search_radius': modScanRadius,
                          'container_radius': modScanRadius,
                          'table_radius': modScanRadius,
                        });
                      },
                      icon: const Icon(Icons.build),
                      label: const Text('执行合成'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('AI 步骤规划'),
                const Text('主脑规划背包/容器操作步骤，可选择是否直接执行。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                TextField(
                  controller: headfulPlanGoalController,
                  decoration: const InputDecoration(
                    labelText: '规划目标',
                    hintText: '例如：装备铁套并把盾牌放到副手',
                  ),
                ),
                SwitchListTile(
                  title: const Text('启用 RAG 知识检索'),
                  subtitle: const Text('使用向量库补充游戏知识（如果已构建）'),
                  value: headfulPlanUseRag,
                  onChanged: (v) => _updateState(() => headfulPlanUseRag = v),
                ),
                SwitchListTile(
                  title: const Text('使用 MindCraft 文档'),
                  subtitle: const Text('复用 MindCraft 文档记忆（首次使用会索引）'),
                  value: headfulPlanUseMindcraftDocs,
                  onChanged: (v) => _updateState(() => headfulPlanUseMindcraftDocs = v),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        final goal = headfulPlanGoalController.text.trim();
                        if (goal.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入规划目标')),
                          );
                          return;
                        }
                        _sendHeadfulSkill(context, 'plan', params: {
                          'goal': goal,
                          'use_rag': headfulPlanUseRag,
                          'rag_user_id': headfulRagUserIdController.text.trim(),
                          'use_mindcraft_docs': headfulPlanUseMindcraftDocs,
                        });
                      },
                      icon: const Icon(Icons.psychology),
                      label: const Text('仅规划'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final goal = headfulPlanGoalController.text.trim();
                        if (goal.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('请输入规划目标')),
                          );
                          return;
                        }
                        _sendHeadfulSkill(context, 'plan_execute', params: {
                          'goal': goal,
                          'use_rag': headfulPlanUseRag,
                          'rag_user_id': headfulRagUserIdController.text.trim(),
                          'use_mindcraft_docs': headfulPlanUseMindcraftDocs,
                        });
                      },
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('规划并执行'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                buildHeadfulPlanSummary(context),
                const SizedBox(height: 12),
                _buildSectionTitle('视角控制'),
                const Text('根据当前视角做相对调整，需要状态已刷新。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulLookDelta(context, -45, 0),
                      icon: const Icon(Icons.rotate_left),
                      label: const Text('左转 45°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookDelta(context, 45, 0),
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('右转 45°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookDelta(context, 180, 0),
                      icon: const Icon(Icons.replay),
                      label: const Text('回头 180°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookDelta(context, 0, -15),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('抬头 15°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookDelta(context, 0, 15),
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('低头 15°'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('平滑视角'),
                const Text('缓慢转向，减少画面抖动。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulLookSmoothDelta(context, -90, 0, durationMs: 600),
                      icon: const Icon(Icons.rotate_left),
                      label: const Text('平滑左转 90°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookSmoothDelta(context, 90, 0, durationMs: 600),
                      icon: const Icon(Icons.rotate_right),
                      label: const Text('平滑右转 90°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookSmoothDelta(context, 180, 0, durationMs: 800),
                      icon: const Icon(Icons.replay),
                      label: const Text('平滑回头 180°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookSmoothDelta(context, 0, -20, durationMs: 500),
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('平滑抬头 20°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulLookSmoothDelta(context, 0, 20, durationMs: 500),
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('平滑低头 20°'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'stopLook',
                      }),
                      icon: const Icon(Icons.pause),
                      label: const Text('停止平滑'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('交互快捷键'),
                const Text('对准方块/实体后使用，可快速验证交互。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'attackTarget',
                      }),
                      icon: const Icon(Icons.gavel),
                      label: const Text('攻击目标'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'useTarget',
                      }),
                      icon: const Icon(Icons.pan_tool_alt),
                      label: const Text('使用/交互'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'stopInput',
                      }),
                      icon: const Icon(Icons.pause),
                      label: const Text('停止输入'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSectionTitle('热键栏'),
                const Text('快速切换 1-9 号槽位。', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(9, (i) {
                    final slot = i;
                    return OutlinedButton(
                      onPressed: () => _sendHeadfulAction(context, {
                        'type': 'hotbar',
                        'slot': slot,
                      }),
                      child: Text('${i + 1}'),
                    );
                  }),
                ),
                const SizedBox(height: 12),
              ],
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
                        final controller = SettingsScope.of(context);
                        await _saveLocalConfig();
                        if (!context.mounted) return;
                        final success = await syncConfigToBackend(controller);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(success ? '配置已同步并尝试重启插件' : '同步失败，请检查后端连接')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.blue.withValues(alpha: 0.1),
                      ),
                      icon: const Icon(Icons.sync),
                      label: const Text('同步配置并重启插件'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: controlMode == 'headless' ? () => _openWebUI() : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    ),
                    icon: const Icon(Icons.open_in_browser),
                    label: Text(controlMode == 'headless' ? 'MindCraft 管理页面' : 'Headful 模式无需管理页面'),
                  ),
                ],
              ),
              if (authMethod == 'microsoft') ...[
                const SizedBox(height: 24),
                _buildSectionTitle('微软登录验证流程'),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _msAuthCode != null
                        ? Colors.orange.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
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
                            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
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
              if (controlMode == 'headless')
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
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.blueGrey,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
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
