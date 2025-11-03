import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../settings/settings.dart';

class AiMessage {
  final String role; // user/assistant/system
  final String content;
  const AiMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
      };
}

class AiClient {
  // 查询可用模型列表（OpenAI 兼容 /models）
  static Future<List<String>> fetchModels({
    required AiSettings ai,
    bool baseUrlIsRoot = true,
  }) async {
    Uri? url;
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    // 计算基础 URL
    String base = ai.baseUrl;
    if ((ai.provider == AiProvider.openai) && base.isEmpty) {
      base = 'https://api.openai.com/v1';
    }
    if (base.isEmpty) {
      throw Exception('未配置 Base URL');
    }
    final full = baseUrlIsRoot && !base.endsWith('/models')
        ? base.replaceAll(RegExp(r"/+\$"), '') + '/models'
        : base;
    url = Uri.parse(full);

    if (ai.apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${ai.apiKey}';
    }

    final resp = await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
    final body = resp.body.trim();
    dynamic parsed;
    try {
      parsed = jsonDecode(body);
    } catch (_) {
      return const <String>[];
    }

    List<String> models = [];
    if (parsed is Map<String, dynamic>) {
      final data = parsed['data'];
      if (data is List) {
        for (final item in data) {
          if (item is Map && item['id'] is String) {
            models.add(item['id'] as String);
          } else if (item is String) {
            models.add(item);
          }
        }
      } else if (parsed['models'] is List) {
        for (final item in (parsed['models'] as List)) {
          if (item is Map && item['id'] is String) {
            models.add(item['id'] as String);
          } else if (item is String) {
            models.add(item);
          }
        }
      }
    } else if (parsed is List) {
      for (final item in parsed) {
        if (item is Map && item['id'] is String) {
          models.add(item['id'] as String);
        } else if (item is String) {
          models.add(item);
        }
      }
    }
    // 去重并排序
    final set = <String>{}..addAll(models);
    final result = set.toList()..sort();
    return result;
  }

  // 简单连通性测试：尝试获取模型列表
  static Future<String> testConnection({
    required AiSettings ai,
    bool baseUrlIsRoot = true,
  }) async {
    try {
      final models = await fetchModels(ai: ai, baseUrlIsRoot: baseUrlIsRoot);
      if (models.isEmpty) return '连接成功，但未返回模型列表';
      return '连接成功，模型数：${models.length}';
    } catch (e) {
      rethrow;
    }
  }
  // 返回助手的文本回复（非流式，最小可用）
  static Future<String> sendChat({
    required AiSettings ai,
    required List<AiMessage> messages,
    String? modelOverride,
    bool baseUrlIsRoot = true,
  }) async {
    final provider = ai.provider;
    final model = (modelOverride != null && modelOverride.isNotEmpty)
        ? modelOverride
        : (ai.model.isEmpty ? 'gpt-4o-mini' : ai.model);

    Uri? url;
    Map<String, String> headers = {'Content-Type': 'application/json'};

    if (provider == AiProvider.openai) {
      if (ai.baseUrl.isNotEmpty) {
        final base = ai.baseUrl;
        final full = baseUrlIsRoot && !base.endsWith('/chat/completions')
            ? base.replaceAll(RegExp(r"/+$"), '') + '/chat/completions'
            : base;
        url = Uri.parse(full);
      } else {
        url = Uri.parse('https://api.openai.com/v1/chat/completions');
      }
      if (ai.apiKey.isEmpty) {
        throw Exception('未配置 OpenAI API Key');
      }
      headers['Authorization'] = 'Bearer ${ai.apiKey}';
    } else if (provider == AiProvider.custom || provider == AiProvider.local) {
      if (ai.baseUrl.isEmpty) {
        throw Exception('未配置 Base URL（自定义/本地）');
      }
      final base = ai.baseUrl;
      final full = baseUrlIsRoot && !base.endsWith('/chat/completions')
          ? base.replaceAll(RegExp(r"/+$"), '') + '/chat/completions'
          : base;
      url = Uri.parse(full);
      if (ai.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${ai.apiKey}';
      }
    }

    final body = jsonEncode({
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': false,
      'temperature': 0.7,
    });

    final resp = await http
        .post(url!, headers: headers, body: body)
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // OpenAI 风格：choices[0].message.content
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = choices[0]['message'];
        if (msg is Map && msg['content'] is String) {
          return msg['content'] as String;
        }
      }
      // 兜底：如果是其他兼容实现，尝试读取 top-level content 字段
      if (data['content'] is String) return data['content'] as String;
      return '[AI] 无法解析响应';
    } else {
      throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
    }
  }

  // 流式：返回文本增量块（OpenAI 风格 SSE: text/event-stream）
  static Stream<String> streamChat({
    required AiSettings ai,
    required List<AiMessage> messages,
    String? modelOverride,
    bool baseUrlIsRoot = true,
  }) async* {
    final provider = ai.provider;
    final model = (modelOverride != null && modelOverride.isNotEmpty)
        ? modelOverride
        : (ai.model.isEmpty ? 'gpt-4o-mini' : ai.model);

    Uri? url;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
    };

    if (provider == AiProvider.openai) {
      if (ai.baseUrl.isNotEmpty) {
        final base = ai.baseUrl;
        final full = baseUrlIsRoot && !base.endsWith('/chat/completions')
            ? base.replaceAll(RegExp(r"/+$"), '') + '/chat/completions'
            : base;
        url = Uri.parse(full);
      } else {
        url = Uri.parse('https://api.openai.com/v1/chat/completions');
      }
      if (ai.apiKey.isEmpty) {
        throw Exception('未配置 OpenAI API Key');
      }
      headers['Authorization'] = 'Bearer ${ai.apiKey}';
    } else if (provider == AiProvider.custom || provider == AiProvider.local) {
      if (ai.baseUrl.isEmpty) {
        throw Exception('未配置 Base URL（自定义/本地）');
      }
      final base = ai.baseUrl;
      final full = baseUrlIsRoot && !base.endsWith('/chat/completions')
          ? base.replaceAll(RegExp(r"/+$"), '') + '/chat/completions'
          : base;
      url = Uri.parse(full);
      if (ai.apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer ${ai.apiKey}';
      }
    }

    final body = jsonEncode({
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      'temperature': 0.7,
    });

    final client = http.Client();
    try {
      final req = http.Request('POST', url!);
      req.headers.addAll(headers);
      req.body = body;
      final resp = await client.send(req).timeout(const Duration(seconds: 60));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final text = await resp.stream.bytesToString();
        throw Exception('HTTP ${resp.statusCode}: $text');
      }
      // 解析 SSE，每行以 data: 开头
      await for (final chunk in resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        final line = chunk.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('data:')) {
          final data = line.substring(5).trim();
          if (data == '[DONE]') break;
          try {
            final obj = jsonDecode(data);
            // OpenAI: choices[0].delta.content
            final choices = obj['choices'];
            if (choices is List && choices.isNotEmpty) {
              final delta = choices[0]['delta'];
              if (delta is Map && delta['content'] is String) {
                yield delta['content'] as String;
              }
            } else if (obj['content'] is String) {
              // 兼容：部分实现直接返回 content
              yield obj['content'] as String;
            }
          } catch (_) {
            // 忽略无法解析的片段
          }
        }
      }
    } finally {
      client.close();
    }
  }
}
