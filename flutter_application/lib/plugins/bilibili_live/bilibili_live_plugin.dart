import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';

import '../../services/diagnostics_service.dart';
import '../base_plugin.dart';
import '../../settings/settings_scope.dart';

class BilibiliLivePlugin extends BasePlugin {
  BilibiliLivePlugin() {
    roomIdController = TextEditingController();
    appIdController = TextEditingController();
    accessKeyIdController = TextEditingController();
    accessKeySecretController = TextEditingController();
    agentModelController = TextEditingController();
    customDanmakuUrlController = TextEditingController();
    customScUrlController = TextEditingController();
    customConfigUrlController = TextEditingController();
    sessDataController = TextEditingController();
    biliJctController = TextEditingController();
    buvid3Controller = TextEditingController();
  }

  late TextEditingController roomIdController;
  late TextEditingController appIdController;
  late TextEditingController accessKeyIdController;
  late TextEditingController accessKeySecretController;
  late TextEditingController agentModelController;
  late TextEditingController customDanmakuUrlController;
  late TextEditingController customScUrlController;
  late TextEditingController customConfigUrlController;
  late TextEditingController sessDataController;
  late TextEditingController biliJctController;
  late TextEditingController buvid3Controller;

  int batchSize = 20;
  int intervalSeconds = 5;
  int scDelaySeconds = 0; // Delay before processing SC
  String? agentProviderId;
  String themePreset = 'default';
  bool enableDanmakuWindow = false;
  bool enableScWindow = false;
  bool allowAiEmojis = false;
  bool useCustomUrl = false;

  Webview? _danmakuWebview;
  Webview? _scWebview;
  Webview? _configWebview;

  @override
  String get id => 'bilibili_live';

  @override
  String get name => 'Bilibili Live';

  @override
  String get description =>
      'Native integration for Bilibili Live Danmaku and Super Chats.';

  @override
  IconData get icon => Icons.live_tv;

  @override
  bool get isDanmakuPlugin => true;

  String _normalizeBackendUrl(String raw) {
    final trimmed = raw.trim();
    final base = trimmed.isEmpty ? 'http://localhost:23456' : trimmed;
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  String _normalizeRoomId(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    final match = RegExp(r'(\d+)').firstMatch(s);
    return match?.group(1) ?? '';
  }

  @override
  Future<void> onInit() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    roomIdController.text =
        _normalizeRoomId(prefs.getString('${prefix}roomId') ?? '');
    appIdController.text = prefs.getString('${prefix}appId') ?? '';
    accessKeyIdController.text = prefs.getString('${prefix}accessKeyId') ?? '';
    accessKeySecretController.text =
        prefs.getString('${prefix}accessKeySecret') ?? '';
    agentModelController.text = prefs.getString('${prefix}agentModel') ?? '';
    batchSize = prefs.getInt('${prefix}batchSize') ?? 20;
    intervalSeconds = prefs.getInt('${prefix}intervalSeconds') ?? 5;
    scDelaySeconds = prefs.getInt('${prefix}scDelaySeconds') ?? 0;
    agentProviderId = prefs.getString('${prefix}agentProviderId');
    themePreset = prefs.getString('${prefix}themePreset') ?? 'default';
    enableDanmakuWindow =
        prefs.getBool('${prefix}enableDanmakuWindow') ?? false;
    enableScWindow = prefs.getBool('${prefix}enableScWindow') ?? false;
    allowAiEmojis = prefs.getBool('${prefix}allowAiEmojis') ?? false;
    useCustomUrl = prefs.getBool('${prefix}useCustomUrl') ?? false;
    customDanmakuUrlController.text =
        prefs.getString('${prefix}customDanmakuUrl') ?? '';
    customScUrlController.text = prefs.getString('${prefix}customScUrl') ?? '';
    customConfigUrlController.text =
        prefs.getString('${prefix}customConfigUrl') ?? '';
    sessDataController.text = prefs.getString('${prefix}sessData') ?? '';
    biliJctController.text = prefs.getString('${prefix}biliJct') ?? '';
    buvid3Controller.text = prefs.getString('${prefix}buvid3') ?? '';
  }

  Future<void> _saveLocalConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin.$id.';
    final normalizedRoomId = _normalizeRoomId(roomIdController.text);
    if (normalizedRoomId.isNotEmpty) {
      roomIdController.text = normalizedRoomId;
    }
    await prefs.setString(
      '${prefix}roomId',
      normalizedRoomId.isNotEmpty ? normalizedRoomId : roomIdController.text.trim(),
    );
    await prefs.setString('${prefix}appId', appIdController.text.trim());
    await prefs.setString(
        '${prefix}accessKeyId', accessKeyIdController.text.trim());
    await prefs.setString(
        '${prefix}accessKeySecret', accessKeySecretController.text.trim());
    await prefs.setString(
        '${prefix}agentModel', agentModelController.text.trim());
    await prefs.setInt('${prefix}batchSize', batchSize);
    await prefs.setInt('${prefix}intervalSeconds', intervalSeconds);
    await prefs.setInt('${prefix}scDelaySeconds', scDelaySeconds);
    await prefs.setString('${prefix}themePreset', themePreset);
    await prefs.setBool('${prefix}enableDanmakuWindow', enableDanmakuWindow);
    await prefs.setBool('${prefix}enableScWindow', enableScWindow);
    await prefs.setBool('${prefix}allowAiEmojis', allowAiEmojis);
    await prefs.setBool('${prefix}useCustomUrl', useCustomUrl);
    await prefs.setString(
        '${prefix}customDanmakuUrl', customDanmakuUrlController.text.trim());
    await prefs.setString(
        '${prefix}customScUrl', customScUrlController.text.trim());
    await prefs.setString(
        '${prefix}customConfigUrl', customConfigUrlController.text.trim());
    await prefs.setString('${prefix}sessData', sessDataController.text.trim());
    await prefs.setString('${prefix}biliJct', biliJctController.text.trim());
    await prefs.setString('${prefix}buvid3', buvid3Controller.text.trim());
    if (agentProviderId != null && agentProviderId!.isNotEmpty) {
      await prefs.setString('${prefix}agentProviderId', agentProviderId!);
    } else {
      await prefs.remove('${prefix}agentProviderId');
    }
  }

  Future<bool> syncConfigToBackend(BuildContext context) async {
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final backendUrl = _normalizeBackendUrl(settings.pythonBackendUrl);
    final providers = controller.providers;

    dynamic selectedProvider;
    if (agentProviderId != null && agentProviderId!.isNotEmpty) {
      for (final p in providers) {
        if (p.id == agentProviderId) {
          selectedProvider = p;
          break;
        }
      }
    } else {
      selectedProvider = controller.activeProviderConfig;
    }

    String effectiveModel = agentModelController.text.trim();
    String? agentApiKey;
    String? agentBaseUrl;

    if (selectedProvider != null) {
      agentApiKey = selectedProvider.apiKey;
      agentBaseUrl = selectedProvider.baseUrl;
      if (effectiveModel.isEmpty) {
        effectiveModel = selectedProvider.model ?? '';
      }
    }

    final normalizedRoomId = _normalizeRoomId(roomIdController.text);
    if (normalizedRoomId.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写有效房间号 (Room ID)')),
        );
      }
      return false;
    }

    if (roomIdController.text.trim() != normalizedRoomId) {
      roomIdController.text = normalizedRoomId;
    }

    final config = <String, dynamic>{
      'room_id': normalizedRoomId,
      'app_id': appIdController.text.trim(),
      'access_key_id': accessKeyIdController.text.trim(),
      'access_key_secret': accessKeySecretController.text.trim(),
      'batch_size': batchSize,
      'interval_seconds': intervalSeconds,
      'sc_delay_seconds': scDelaySeconds,
      'enable_danmaku_window': enableDanmakuWindow,
      'enable_sc_window': enableScWindow,
      'allow_ai_emojis': allowAiEmojis,
      'sess_data': sessDataController.text.trim(),
      'bili_jct': biliJctController.text.trim(),
      'buvid3': buvid3Controller.text.trim(),
    };

    if (effectiveModel.isNotEmpty) {
      config['agent_model'] = effectiveModel;
    }
    if (agentApiKey != null && agentBaseUrl != null) {
      config['agent_api_key'] = agentApiKey;
      config['agent_base_url'] = agentBaseUrl;
    }

    final uri = Uri.parse('$backendUrl/api/v1/plugins/$id/config');
    final body = jsonEncode({
      'config': config,
    });

    try {
      final resp = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return true;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步到后端失败 (HTTP ${resp.statusCode})')),
        );
      }
      return false;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步到后端失败: $e')),
        );
      }
      return false;
    }
  }

  @override
  Future<void> onSync(BuildContext context) async {
    await syncConfigToBackend(context);
  }

  @override
  Future<void> onEnable() async {
    await super.onEnable();
    if (enableDanmakuWindow) {
      await _openDanmakuWindow(null);
    }
    if (enableScWindow) {
      await _openScWindow(null);
    }
  }

  @override
  Future<void> onDisable() async {
    await super.onDisable();
    await _closeDanmakuWindow();
    await _closeScWindow();
    await _closeConfigWindow();
  }

  Future<String> _loadBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return _normalizeBackendUrl(
      prefs.getString('settings.backend.url') ?? 'http://localhost:23456',
    );
  }

  Future<bool> _openDanmakuWindow(BuildContext? context) async {
    if (!Platform.isWindows) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台暂不支持弹幕独立窗口')),
        );
      }
      return false;
    }

    if (!DiagnosticsService().isWebViewAvailable) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Webview 环境不可用，无法打开独立窗口')),
        );
      }
      return false;
    }

    final backendUrl = await _loadBackendUrl();
    try {
      if (_danmakuWebview != null) {
        _danmakuWebview!.close();
        _danmakuWebview = null;
      }
      final webview = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          windowWidth: 460,
          windowHeight: 720,
          title: 'Bilibili Danmaku',
          titleBarTopPadding: 0,
        ),
      );
      String url;
      if (useCustomUrl && customDanmakuUrlController.text.isNotEmpty) {
        url = customDanmakuUrlController.text.trim();
      } else {
        url =
            '$backendUrl/static/bilibili/bilibili_danmaku.html?mode=danmaku&theme=$themePreset';
      }
      webview.launch(url);
      _danmakuWebview = webview;
      return true;
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建弹幕窗口失败: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _closeDanmakuWindow() async {
    if (_danmakuWebview != null) {
      try {
        _danmakuWebview!.close();
      } catch (_) {}
      _danmakuWebview = null;
    }
  }

  Future<bool> _openScWindow(BuildContext? context) async {
    if (!Platform.isWindows) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台暂不支持SC独立窗口')),
        );
      }
      return false;
    }

    if (!DiagnosticsService().isWebViewAvailable) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Webview 环境不可用，无法打开独立窗口')),
        );
      }
      return false;
    }

    final backendUrl = await _loadBackendUrl();
    try {
      if (_scWebview != null) {
        _scWebview!.close();
        _scWebview = null;
      }
      final webview = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          windowWidth: 460,
          windowHeight: 720,
          title: 'Bilibili Super Chat',
          titleBarTopPadding: 0,
        ),
      );
      String url;
      if (useCustomUrl && customScUrlController.text.isNotEmpty) {
        url = customScUrlController.text.trim();
      } else {
        url =
            '$backendUrl/static/bilibili/bilibili_danmaku.html?mode=sc&theme=$themePreset';
      }
      webview.launch(url);
      _scWebview = webview;
      return true;
    } catch (e) {
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建SC窗口失败: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _closeScWindow() async {
    if (_scWebview != null) {
      try {
        _scWebview!.close();
      } catch (_) {}
      _scWebview = null;
    }
  }

  Future<void> _closeConfigWindow() async {
    if (_configWebview != null) {
      try {
        _configWebview!.close();
      } catch (_) {}
      _configWebview = null;
    }
  }

  Future<bool> _openConfigWindow(BuildContext context) async {
    if (!Platform.isWindows) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前平台暂不支持配置独立窗口')),
        );
      }
      return false;
    }
    if (customConfigUrlController.text.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先填写自定义配置 URL')),
        );
      }
      return false;
    }
    try {
      if (_configWebview != null) {
        _configWebview!.close();
        _configWebview = null;
      }
      final webview = await WebviewWindow.create(
        configuration: const CreateConfiguration(
          windowWidth: 800,
          windowHeight: 600,
          title: 'Bilibili Config',
          titleBarTopPadding: 0,
        ),
      );
      final url = customConfigUrlController.text.trim();
      webview.launch(url);
      _configWebview = webview;
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建配置窗口失败: $e')),
        );
      }
      return false;
    }
  }

  @override
  Widget? buildQuickSettings(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Column(
          children: [
            SwitchListTile(
              title: const Text('启用弹幕窗口'),
              value: enableDanmakuWindow,
              onChanged: (v) {
                setState(() => enableDanmakuWindow = v);
                _saveLocalConfig();
              },
            ),
            SwitchListTile(
              title: const Text('启用 SC 窗口'),
              value: enableScWindow,
              onChanged: (v) {
                setState(() => enableScWindow = v);
                _saveLocalConfig();
              },
            ),
            SwitchListTile(
              title: const Text('允许 AI 使用表情'),
              value: allowAiEmojis,
              onChanged: (v) {
                setState(() => allowAiEmojis = v);
                _saveLocalConfig();
              },
            ),
            ListTile(
              title: const Text('弹幕批量间隔 (秒)'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  value: intervalSeconds.toDouble(),
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: intervalSeconds.toString(),
                  onChanged: (v) {
                    setState(() => intervalSeconds = v.toInt());
                    _saveLocalConfig();
                  },
                ),
              ),
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
        final controller = SettingsScope.of(context);
        final providers = controller.providers;
        final currentProviderId = agentProviderId ?? 'follow_main';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(icon),
              title: const Text('Bilibili Live 配置'),
              subtitle: const Text('房间号、Open Platform 密钥、弹幕汇总 Agent'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: roomIdController,
                decoration: const InputDecoration(
                  labelText: '房间号 (Room ID)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: appIdController,
                decoration: const InputDecoration(
                  labelText: '应用 ID (App ID)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: accessKeyIdController,
                decoration: const InputDecoration(
                  labelText: 'Access Key ID',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: accessKeySecretController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Access Key Secret',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('账号登录 (可选)'),
              subtitle: Text('配置 SESSDATA 和 BILI_JCT 以获取完整用户昵称 (解决"***"问题)'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: sessDataController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'SESSDATA (Cookie)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: biliJctController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'bili_jct (Cookie)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: buvid3Controller,
                decoration: const InputDecoration(
                  labelText: 'buvid3 (Cookie, 可选)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<String>(
                value: currentProviderId,
                decoration: const InputDecoration(
                  labelText: '弹幕汇总模型服务商',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'follow_main',
                    child: Text('跟随主脑'),
                  ),
                  for (final p in providers)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name),
                    ),
                ],
                onChanged: (v) {
                  setState(() {
                    if (v == null || v == 'follow_main') {
                      agentProviderId = null;
                    } else {
                      agentProviderId = v;
                    }
                  });
                },
              ),
            ),
            const Divider(),
            const ListTile(
              title: Text('弹幕处理速率控制'),
              subtitle: Text('设置 AI 处理弹幕的批处理间隔'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '批处理间隔: ${controller.settings.ai.danmakuBatchInterval} 秒',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                  Slider(
                    value: controller.settings.ai.danmakuBatchInterval.toDouble().clamp(5.0, 300.0),
                    min: 5.0,
                    max: 300.0,
                    divisions: 59,
                    label: '${controller.settings.ai.danmakuBatchInterval}s',
                    onChanged: (v) {
                      setState(() {
                        controller.setAiDanmakuBatchInterval(v.toInt());
                      });
                    },
                  ),
                  const Text(
                    '间隔越短反应越快，但消耗更多 Token。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextFormField(
                controller: agentModelController,
                decoration: const InputDecoration(
                  labelText: '弹幕汇总模型 (可选)',
                  hintText: '例如: deepseek-ai/DeepSeek-V3',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                title: const Text('允许 AI 使用表情'),
                subtitle: const Text('允许弹幕汇总 Agent 回复时使用 emoji'),
                value: allowAiEmojis,
                onChanged: (v) async {
                  setState(() {
                    allowAiEmojis = v;
                  });
                  await _saveLocalConfig();
                  if (!context.mounted) return;
                  await syncConfigToBackend(context);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('批次大小'),
                        Slider(
                          min: 5,
                          max: 50,
                          divisions: 9,
                          label: '$batchSize',
                          value: batchSize.toDouble(),
                          onChanged: (v) {
                            setState(() {
                              batchSize = v.round();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('汇总周期 (秒)'),
                        Slider(
                          min: 3,
                          max: 30,
                          divisions: 9,
                          label: '$intervalSeconds',
                          value: intervalSeconds.toDouble(),
                          onChanged: (v) {
                            setState(() {
                              intervalSeconds = v.round();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SC 回应延迟 (秒) - 0 为立即'),
                  Slider(
                    min: 0,
                    max: 60,
                    divisions: 12,
                    label: '$scDelaySeconds',
                    value: scDelaySeconds.toDouble(),
                    onChanged: (v) {
                      setState(() {
                        scDelaySeconds = v.round();
                      });
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: DropdownButtonFormField<String>(
                value: themePreset,
                decoration: const InputDecoration(
                  labelText: '窗口颜色主题',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('默认 (深蓝)')),
                  DropdownMenuItem(value: 'light', child: Text('明亮 (Light)')),
                  DropdownMenuItem(value: 'dark_gold', child: Text('黑金 (Dark Gold)')),
                  DropdownMenuItem(value: 'pink', child: Text('粉色 (Pink)')),
                  DropdownMenuItem(value: 'green', child: Text('护眼绿 (Green)')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      themePreset = v;
                    });
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                title: const Text('启用弹幕独立窗口'),
                subtitle: const Text('使用独立 Web 窗口滚动展示直播弹幕'),
                value: enableDanmakuWindow,
                onChanged: (v) async {
                  if (v) {
                    final ok = await _openDanmakuWindow(context);
                    setState(() {
                      enableDanmakuWindow = ok;
                    });
                  } else {
                    await _closeDanmakuWindow();
                    setState(() {
                      enableDanmakuWindow = false;
                    });
                  }
                  await _saveLocalConfig();
                  if (!context.mounted) return;
                  await syncConfigToBackend(context);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                title: const Text('启用 SC 独立窗口'),
                subtitle: const Text('将醒目留言以卡片形式单独展示'),
                value: enableScWindow,
                onChanged: (v) async {
                  if (v) {
                    final ok = await _openScWindow(context);
                    setState(() {
                      enableScWindow = ok;
                    });
                  } else {
                    await _closeScWindow();
                    setState(() {
                      enableScWindow = false;
                    });
                  }
                  await _saveLocalConfig();
                  if (!context.mounted) return;
                  await syncConfigToBackend(context);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SwitchListTile(
                title: const Text('高级：使用自定义 URL'),
                subtitle: const Text('使用外部链接覆盖默认的弹幕/SC窗口'),
                value: useCustomUrl,
                onChanged: (v) {
                  setState(() {
                    useCustomUrl = v;
                  });
                  _saveLocalConfig();
                },
              ),
            ),
            if (useCustomUrl) ...[
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextFormField(
                  controller: customDanmakuUrlController,
                  decoration: const InputDecoration(
                    labelText: '自定义弹幕窗口 URL',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextFormField(
                  controller: customScUrlController,
                  decoration: const InputDecoration(
                    labelText: '自定义 SC 窗口 URL',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextFormField(
                  controller: customConfigUrlController,
                  decoration: const InputDecoration(
                    labelText: '自定义配置窗口 URL (例如 blivedm 页面)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ElevatedButton(
                  onPressed: () => _openConfigWindow(context),
                  child: const Text('打开自定义配置窗口'),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _saveLocalConfig();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已保存到本地')),
                        );
                      }
                    },
                    icon: const Icon(Icons.save),
                    label: const Text('保存本地'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      await _saveLocalConfig();
                      if (!context.mounted) return;
                      final ok = await syncConfigToBackend(context);
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已同步到后端')),
                        );
                      }
                    },
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('同步到后端'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget? buildDashboardWidget(BuildContext context) {
    if (!isEnabled) return null;
    return Card(
      child: Container(
        padding: const EdgeInsets.all(8),
        height: 200,
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Bilibili Live Monitor',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            const Expanded(
              child: Center(
                child: Text('等待弹幕连接与汇总配置生效...'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
