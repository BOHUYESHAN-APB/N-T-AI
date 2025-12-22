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

class RemoteJargon {
  final int id;
  final String term;
  final String definition;
  final String? contextExample;
  final bool isVerified;

  RemoteJargon({
    required this.id,
    required this.term,
    required this.definition,
    this.contextExample,
    required this.isVerified,
  });

  factory RemoteJargon.fromJson(Map<String, dynamic> json) {
    return RemoteJargon(
      id: json['id'] as int,
      term: json['term'] as String? ?? '',
      definition: json['definition'] as String? ?? '',
      contextExample: json['context_example'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
    );
  }
}

class RemotePerson {
  final int? id;
  final String userId;
  final String? nickname;
  final String? assistantName;
  final String? systemPrompt;
  final int knowTimes;
  final DateTime? createdAt;

  RemotePerson({
    this.id,
    required this.userId,
    this.nickname,
    this.assistantName,
    this.systemPrompt,
    this.knowTimes = 0,
    this.createdAt,
  });

  factory RemotePerson.fromJson(Map<String, dynamic> json) {
    return RemotePerson(
      id: json['id'] as int?,
      userId: json['user_id'] as String? ?? 'unknown',
      nickname: json['nickname'] as String?,
      assistantName: json['assistant_name'] as String?,
      systemPrompt: json['system_prompt'] as String?,
      knowTimes: json['know_times'] as int? ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
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
        prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
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

  // --- Jargon API ---

  Future<List<RemoteJargon>> fetchJargon({int limit = 100}) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/jargon/all?limit=$limit');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('拉取术语失败: ${resp.body}');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(resp.bodyBytes));
    return data
        .map((e) => RemoteJargon.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RemoteJargon> createJargon({
    required String term,
    required String definition,
    String? contextExample,
    bool isVerified = true,
  }) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/jargon');
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'term': term,
        'definition': definition,
        'context_example': contextExample,
        'is_verified': isVerified,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('创建术语失败: ${resp.body}');
    }
    return RemoteJargon.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<RemoteJargon> updateJargon({
    required int id,
    String? term,
    String? definition,
    String? contextExample,
    bool? isVerified,
  }) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/jargon/$id');
    final resp = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (term != null) 'term': term,
        if (definition != null) 'definition': definition,
        if (contextExample != null) 'context_example': contextExample,
        if (isVerified != null) 'is_verified': isVerified,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('更新术语失败: ${resp.body}');
    }
    return RemoteJargon.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> deleteJargon(int id) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/jargon/$id');
    final resp = await http.delete(uri);
    if (resp.statusCode != 200) {
      throw Exception('删除术语失败: ${resp.body}');
    }
  }

  // --- Person API ---

  Future<List<RemotePerson>> fetchPersons({int limit = 50}) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/person/all?limit=$limit');
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('拉取用户信息失败: ${resp.body}');
    }
    final List<dynamic> data = jsonDecode(utf8.decode(resp.bodyBytes));
    return data
        .map((e) => RemotePerson.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<RemotePerson> updatePerson({
    required String userId,
    String? nickname,
    String? assistantName,
    String? systemPrompt,
  }) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/person/$userId');
    final resp = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (nickname != null) 'nickname': nickname,
        if (assistantName != null) 'assistant_name': assistantName,
        if (systemPrompt != null) 'system_prompt': systemPrompt,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('更新用户信息失败: ${resp.body}');
    }
    return RemotePerson.fromJson(
      jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> deletePerson(String userId) async {
    final base = await _requireBackendUrl();
    final uri = Uri.parse('$base/v1/person/$userId');
    final resp = await http.delete(uri);
    if (resp.statusCode != 200) {
      throw Exception('删除用户信息失败: ${resp.body}');
    }
  }
}
