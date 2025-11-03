import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'mock_data.dart';

class ChatStorage {
  static const _kChatMessages = 'chat.messages.json';
  static String _keyFor(String conversationId) => 'chat.messages.' + conversationId + '.json';

  static Future<List<ChatMessage>> loadMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kChatMessages);
    if (raw == null) return List<ChatMessage>.from(chatMessages);
    try {
      final List data = jsonDecode(raw);
      return data.map((e) {
        final List atts = (e['attachments'] as List?) ?? const [];
        return ChatMessage(
          id: e['id'] as String,
          text: e['text'] as String? ?? '',
          isMine: e['isMine'] as bool? ?? false,
          time: e['time'] as String? ?? '',
          attachments: atts.map((a) => Attachment(
            name: a['name'] as String? ?? '',
            path: a['path'] as String? ?? '',
            size: (a['size'] is int) ? a['size'] as int : (a['size'] is double) ? (a['size'] as double).toInt() : null,
            mime: a['mime'] as String?,
          )).toList(),
        );
      }).toList();
    } catch (_) {
      return List<ChatMessage>.from(chatMessages);
    }
  }

  static Future<void> saveMessages(List<ChatMessage> msgs) async {
    final prefs = await SharedPreferences.getInstance();
    final data = msgs.map((m) => {
          'id': m.id,
          'text': m.text,
          'isMine': m.isMine,
          'time': m.time,
          'attachments': m.attachments
              .map((a) => {
                    'name': a.name,
                    'path': a.path,
                    'size': a.size,
                    'mime': a.mime,
                  })
              .toList(),
        }).toList();
    await prefs.setString(_kChatMessages, jsonEncode(data));
  }

  // 新：按会话（联系人）读取
  static Future<List<ChatMessage>> loadMessagesFor(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(conversationId));
    if (raw == null) return List<ChatMessage>.from(chatMessages);
    try {
      final List data = jsonDecode(raw);
      return data
          .map((e) => ChatMessage(
                id: e['id'] as String,
                text: e['text'] as String? ?? '',
                isMine: e['isMine'] as bool? ?? false,
                time: e['time'] as String? ?? '',
                attachments: ((e['attachments'] as List?) ?? const [])
                    .map((a) => Attachment(
                          name: a['name'] as String? ?? '',
                          path: a['path'] as String? ?? '',
                          size: (a['size'] is int)
                              ? a['size'] as int
                              : (a['size'] is double)
                                  ? (a['size'] as double).toInt()
                                  : null,
                          mime: a['mime'] as String?,
                        ))
                    .toList(),
              ))
          .toList();
    } catch (_) {
      return List<ChatMessage>.from(chatMessages);
    }
  }

  // 新：按会话（联系人）保存
  static Future<void> saveMessagesFor(String conversationId, List<ChatMessage> msgs) async {
    final prefs = await SharedPreferences.getInstance();
    final data = msgs
        .map((m) => {
              'id': m.id,
              'text': m.text,
              'isMine': m.isMine,
              'time': m.time,
              'attachments': m.attachments
                  .map((a) => {
                        'name': a.name,
                        'path': a.path,
                        'size': a.size,
                        'mime': a.mime,
                      })
                  .toList(),
            })
        .toList();
    await prefs.setString(_keyFor(conversationId), jsonEncode(data));
  }

  static Future<void> removeConversation(String conversationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFor(conversationId));
  }
}
