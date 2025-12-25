import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../services/diagnostics_service.dart';
import 'base_plugin.dart';
import 'bilibili_live/bilibili_live_plugin.dart';
import 'minecraft_mindcraft/minecraft_mindcraft_plugin.dart';

class PluginManager extends ChangeNotifier {
  final Map<String, BasePlugin> _plugins = {};

  bool _initialized = false;

  PluginManager();

  Future<void> _notifyBackend(String id, bool activate) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String backendUrl = prefs.getString('settings.backend.url') ?? 'http://127.0.0.1:23456';
      backendUrl = backendUrl.replaceAll(RegExp(r'/$'), '');
      
      final endpoint = activate ? 'activate' : 'deactivate';
      final response = await http.post(
        Uri.parse('$backendUrl/api/v1/plugins/$id/$endpoint'),
      );
      
      if (response.statusCode != 200) {
        debugPrint('Failed to $endpoint plugin $id on backend: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error notifying backend for plugin $id: $e');
    }
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    // Wait for system diagnostics to complete to avoid race conditions with WebView initialization
    await DiagnosticsService().ready;
    _initialized = true;
    await _registerDefaultPlugins();
  }

  Future<void> _registerDefaultPlugins() async {
    await registerPlugin(BilibiliLivePlugin());
    await registerPlugin(MinecraftMindcraftPlugin());
  }

  Future<void> registerPlugin(BasePlugin plugin) async {
    if (_plugins.containsKey(plugin.id)) {
      return;
    }
    _plugins[plugin.id] = plugin;
    await plugin.onInit();
    final enabled = await _loadEnabled(plugin.id);
    plugin.autoStart = await _loadAutoStart(plugin.id);
    if (enabled) {
      await plugin.onEnable();
      // 如果已启用，也通知后端激活
      await _notifyBackend(plugin.id, true);
    }
    notifyListeners();
  }

  BasePlugin? getPlugin(String id) => _plugins[id];

  List<BasePlugin> get allPlugins => _plugins.values.toList();
  List<BasePlugin> get enabledPlugins =>
      _plugins.values.where((p) => p.isEnabled).toList();

  Future<void> togglePlugin(String id, bool enabled) async {
    final plugin = _plugins[id];
    if (plugin != null) {
      await _saveEnabled(id, enabled);
      if (enabled) {
        await plugin.onEnable();
        await _notifyBackend(id, true);
      } else {
        await plugin.onDisable();
        await _notifyBackend(id, false);
      }
      notifyListeners();
    }
  }

  Future<void> toggleAutoStart(String id, bool autoStart) async {
    final plugin = _plugins[id];
    if (plugin != null) {
      plugin.autoStart = autoStart;
      await _saveAutoStart(id, autoStart);
      notifyListeners();
    }
  }

  Future<bool> _loadEnabled(String id) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('plugin.$id.enabled') ?? false;
  }

  Future<void> _saveEnabled(String id, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin.$id.enabled', enabled);
  }

  Future<bool> _loadAutoStart(String id) async {
    final prefs = await SharedPreferences.getInstance();
    // 默认值：Minecraft 默认不自启，其他默认自启
    bool defaultValue = id != 'Minecraft-mindcraft';
    return prefs.getBool('plugin.$id.autoStart') ?? defaultValue;
  }

  Future<void> _saveAutoStart(String id, bool autoStart) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('plugin.$id.autoStart', autoStart);
  }
}

final PluginManager globalPluginManager = PluginManager();
