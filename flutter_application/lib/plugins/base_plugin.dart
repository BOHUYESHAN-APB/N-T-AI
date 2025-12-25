import 'package:flutter/material.dart';

/// Abstract base class for all frontend plugins.
/// Plugins can provide UI components, settings, and handle events.
abstract class BasePlugin {
  String get id;
  String get name;
  String get description;
  IconData get icon;

  bool get isDanmakuPlugin => false;

  /// Whether the plugin is currently enabled
  bool isEnabled = false;

  /// Whether the plugin should auto-start on backend startup
  bool autoStart = true;

  /// Called when the app starts or plugin is loaded
  Future<void> onInit();

  /// Called when the plugin is enabled by user
  Future<void> onEnable() async {
    isEnabled = true;
    debugPrint('[$name] Plugin enabled');
  }

  /// Called when the plugin is disabled by user
  Future<void> onDisable() async {
    isEnabled = false;
    debugPrint('[$name] Plugin disabled');
  }

  /// Optional: Provide a settings widget for this plugin (detailed configuration)
  Widget? buildSettingsWidget(BuildContext context) => null;

  /// Optional: Provide a quick settings widget (switches, sliders) to show in the list
  Widget? buildQuickSettings(BuildContext context) => null;

  /// Optional: Provide a widget to be displayed in the main dashboard/overlay
  Widget? buildDashboardWidget(BuildContext context) => null;

  /// Called to sync configuration with backend (if applicable)
  Future<void> onSync(BuildContext context) async {}
}
