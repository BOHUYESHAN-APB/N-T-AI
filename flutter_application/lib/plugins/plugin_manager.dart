import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'base_plugin.dart';
import 'bilibili_live/bilibili_live_plugin.dart';

class PluginManager extends ChangeNotifier {
  final Map<String, BasePlugin> _plugins = {};

  bool _initialized = false;

  PluginManager();

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    await _registerDefaultPlugins();
  }

  Future<void> _registerDefaultPlugins() async {
    await registerPlugin(BilibiliLivePlugin());
  }

  Future<void> registerPlugin(BasePlugin plugin) async {
    if (_plugins.containsKey(plugin.id)) {
      return;
    }
    _plugins[plugin.id] = plugin;
    await plugin.onInit();
    final enabled = await _loadEnabled(plugin.id);
    if (enabled) {
      await plugin.onEnable();
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
      } else {
        await plugin.onDisable();
      }
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
}

final PluginManager globalPluginManager = PluginManager();
