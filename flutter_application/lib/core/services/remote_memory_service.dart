import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RemoteMemory {
  final int id;
  final String userId;
  final String content;
  final String category;
  final double weight;
  final DateTime createdAt;

  RemoteMemory({
    required this.id,
    required this.userId,
    required this.content,
    required this.category,
    required this.weight,
    required this.createdAt,
  });

  factory RemoteMemory.fromJson(Map<String, dynamic> json) {
    return RemoteMemory(
      id: json['id'] as int,
      userId: json['user_id'] as String? ?? 'unknown',
      content: json['content'] as String? ?? '',
      category: json['category'] as String? ?? 'other',
      weight: (json['weight'] as num?)?.toDouble() ?? 1.0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class RemoteMemoryService {
  Future<String> _requireBackendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('settings.backend.enabled') ?? false;
    if (!enabled) {
      throw Exception('请先在设置中启用 Python 后端');
    }
    final baseUrl =
        prefs.getString('settings.backend.url') ?? 'http://localhost:8000';
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  Future<List<RemoteMemory>> fetchMemories({int limit = 50}) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/memory/all?limit=$limit');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('拉取记忆失败: ${resp.body}');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(resp.bodyBytes));
    return data
        .map((e) => RemoteMemory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteMemory> createMemory({
    required String userId,
    required String content,
    String category = 'other',
    double weight = 1.0,
  }) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/memory');
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': userId,
        'content': content,
        'category': category,
        'weight': weight,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('创建失败: ${resp.body}');
    }
    return RemoteMemory.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<RemoteMemory> updateMemory({
    required int id,
    String? content,
    String? category,
    double? weight,
  }) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/memory/$id');
    final resp = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (content != null) 'content': content,
        if (category != null) 'category': category,
        if (weight != null) 'weight': weight,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('更新失败: ${resp.body}');
    }
    return RemoteMemory.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> deleteMemory(int id) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/memory/$id');
    final resp = await http.delete(uri);
    if (resp.statusCode != 200) {
      throw Exception('删除失败: ${resp.body}');
    }
  }
}
