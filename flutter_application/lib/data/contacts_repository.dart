import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'mock_data.dart';

class ContactsRepository {
  static const _kContacts = 'contacts.list.json';

  static Future<List<Contact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kContacts);
    if (raw == null) {
      // 初次使用：用内置样例初始化
      final list = List<Contact>.from(contacts);
      await save(list);
      return list;
    }
    try {
      final List data = jsonDecode(raw);
      return data.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return List<Contact>.from(contacts);
    }
  }

  static Future<void> save(List<Contact> list) async {
    final prefs = await SharedPreferences.getInstance();
    final data = list.map(_toJson).toList();
    await prefs.setString(_kContacts, jsonEncode(data));
  }

  static Map<String, dynamic> _toJson(Contact c) => {
        'id': c.id,
        'name': c.name,
        'type': c.type.name,
        'avatarEmoji': c.avatarEmoji,
        'pinned': c.pinned,
        'note': c.note,
      };

  static Contact _fromJson(Map<String, dynamic> e) => Contact(
        id: e['id'] as String,
        name: e['name'] as String? ?? '',
        type: _typeFrom(e['type'] as String? ?? 'other'),
        avatarEmoji: e['avatarEmoji'] as String?,
        pinned: e['pinned'] as bool? ?? false,
        note: e['note'] as String?,
      );

  static ContactType _typeFrom(String s) {
    switch (s) {
      case 'ai':
        return ContactType.ai;
      case 'human':
        return ContactType.human;
      default:
        return ContactType.other;
    }
  }

  static List<Contact> sortDisplay(List<Contact> list) {
    final l = [...list];
    l.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      // AI 放前
      if (a.type != b.type) return a.type == ContactType.ai ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return l;
  }
}
