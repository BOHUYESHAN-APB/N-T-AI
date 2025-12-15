import 'package:flutter/material.dart';

/// Abstract base class for all frontend plugins.
/// Plugins can provide UI components, settings, and handle events.
abstract class BasePlugin {
  String get id;
  String get name;
  String get description;
  IconData get icon;

  /// Whether the plugin is currently enabled
  bool isEnabled = false;

  /// Called when the app starts or plugin is loaded
  Future<void> onInit();

  /// Called when the plugin is enabled by user
  Future<void> onEnable() async {
    isEnabled = true;
    print('[$name] Plugin enabled');
  }

  /// Called when the plugin is disabled by user
  Future<void> onDisable() async {
    isEnabled = false;
    print('[$name] Plugin disabled');
  }

  /// Optional: Provide a settings widget for this plugin
  Widget? buildSettingsWidget(BuildContext context) => null;

  /// Optional: Provide a widget to be displayed in the main dashboard/overlay
  Widget? buildDashboardWidget(BuildContext context) => null;
}
