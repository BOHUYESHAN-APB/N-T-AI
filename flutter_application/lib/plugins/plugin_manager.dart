import 'package:flutter/material.dart';
import 'base_plugin.dart';
import 'bilibili_live/bilibili_live_plugin.dart';

class PluginManager extends ChangeNotifier {
  final Map<String, BasePlugin> _plugins = {};

  bool _initialized = false;

  PluginManager();

  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _registerDefaultPlugins();
  }

  void _registerDefaultPlugins() {
    registerPlugin(BilibiliLivePlugin());
  }

  void registerPlugin(BasePlugin plugin) {
    if (_plugins.containsKey(plugin.id)) {
      return;
    }
    _plugins[plugin.id] = plugin;
    plugin.onInit();
    notifyListeners();
  }

  BasePlugin? getPlugin(String id) => _plugins[id];

  List<BasePlugin> get allPlugins => _plugins.values.toList();
  List<BasePlugin> get enabledPlugins =>
      _plugins.values.where((p) => p.isEnabled).toList();

  Future<void> togglePlugin(String id, bool enabled) async {
    final plugin = _plugins[id];
    if (plugin != null) {
      if (enabled) {
        await plugin.onEnable();
      } else {
        await plugin.onDisable();
      }
      notifyListeners();
    }
  }
}

final PluginManager globalPluginManager = PluginManager();
