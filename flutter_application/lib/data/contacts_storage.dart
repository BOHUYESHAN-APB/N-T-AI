import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AiContactConfig {
  final String? model; // 覆盖全局模型
  final String? systemPrompt; // 系统提示

  const AiContactConfig({this.model, this.systemPrompt});

  Map<String, dynamic> toJson() => {
        'model': model,
        'systemPrompt': systemPrompt,
      };

  static AiContactConfig fromJson(Map<String, dynamic> json) => AiContactConfig(
        model: json['model'] as String?,
        systemPrompt: json['systemPrompt'] as String?,
      );
}

class ContactsStorage {
  static String _key(String contactId) => 'contacts.aiConfig.' + contactId;

  static Future<AiContactConfig?> loadAiConfig(String contactId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(contactId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AiContactConfig.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveAiConfig(String contactId, AiContactConfig cfg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(contactId), jsonEncode(cfg.toJson()));
  }

  static Future<void> removeAiConfig(String contactId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(contactId));
  }
}
