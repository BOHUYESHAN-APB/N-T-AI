import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../settings/settings.dart';

class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  final String model;
  final String type; // main, tool, memory, system

  TokenUsage({
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
    required this.model,
    required this.type,
  });
}

class AiResponse {
  final String content;
  final String? emotion;
  final String? reasoningContent;
  final List<dynamic>? toolCalls;
  
  AiResponse({
    required this.content, 
    this.emotion, 
    this.reasoningContent,
    this.toolCalls
  });
}

class LLMService {
  static const String _kAiProviders = 'settings.ai.providers';
  static const String _kAiActiveId = 'settings.ai.activeId';
  
  // Stream for token usage updates
  static final _usageController = StreamController<TokenUsage>.broadcast();
  static Stream<TokenUsage> get usageStream => _usageController.stream;

  Future<AiProviderConfig?> getActiveProviderConfig() async {
    return _getActiveProvider();
  }

  Future<AiProviderConfig?> _getActiveProvider() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Note: We no longer force 'neural_hub' here. 
    // Instead, we return the actual selected provider, and handle the routing in chat().
    
    final activeId = prefs.getString(_kAiActiveId);
    final providersRaw = prefs.getString(_kAiProviders);

    if (providersRaw == null || activeId == null) return null;

    try {
      final List data = jsonDecode(providersRaw) as List;
      final providers = data.map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>)).toList();
      return providers.firstWhere((p) => p.id == activeId, orElse: () => providers.first);
    } catch (e) {
      print("Error loading providers: $e");
      return null;
    }
  }

  Future<AiProviderConfig?> _getProviderById(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final providersRaw = prefs.getString(_kAiProviders);
    if (providersRaw == null) return null;
    try {
      final List data = jsonDecode(providersRaw) as List;
      final providers = data.map((e) => AiProviderConfig.fromJson(e as Map<String, dynamic>)).toList();
      return providers.firstWhere((p) => p.id == id, orElse: () => providers.first);
    } catch (_) {
      return null;
    }
  }

  Future<String?> getApiKey() async {
    final provider = await _getActiveProvider();
    return provider?.apiKey;
  }

  Future<bool> isActiveModelVisionCapable() async {
    final provider = await _getActiveProvider();
    if (provider == null) return false;
    return _modelSupportsVision(provider.model);
  }

  // No longer used directly, settings are managed by SettingsController
  Future<void> saveSettings(String apiKey, String baseUrl, String model) async {
    // Deprecated: Settings are now managed centrally in SystemScreen
  }

  Future<List<double>> getEmbedding(String text) async {
    final provider = await _getActiveProvider();
    if (provider == null) throw Exception("No active AI provider configured");

    final prefs = await SharedPreferences.getInstance();
    final enablePythonBackend = prefs.getBool('settings.backend.enabled') ?? false;
    final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';

    String requestUrl;
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    if (enablePythonBackend) {
      requestUrl = '$backendUrl/v1/embeddings';
      headers['X-Target-Api-Key'] = provider.apiKey;
      
      var targetBaseUrl = provider.baseUrl;
      if (targetBaseUrl.endsWith('/chat/completions')) {
        targetBaseUrl = targetBaseUrl.replaceAll('/chat/completions', '');
      }
      if (targetBaseUrl.endsWith('/')) targetBaseUrl = targetBaseUrl.substring(0, targetBaseUrl.length - 1);
      headers['X-Target-Base-Url'] = targetBaseUrl;
    } else {
      var baseUrl = provider.baseUrl;
      if (baseUrl.endsWith('/v1')) {
        // Standard OpenAI style
      } else if (baseUrl.endsWith('/chat/completions')) {
        baseUrl = baseUrl.replaceAll('/chat/completions', '');
      }
      if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      requestUrl = '$baseUrl/embeddings';
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    try {
      final response = await http.post(
        Uri.parse(requestUrl),
        headers: headers,
        body: jsonEncode({
          'input': text,
          'model': 'text-embedding-ada-002',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        
        if (data.containsKey('usage')) {
          final usage = data['usage'];
          _usageController.add(TokenUsage(
            promptTokens: usage['prompt_tokens'] ?? 0,
            completionTokens: 0,
            totalTokens: usage['total_tokens'] ?? 0,
            model: 'embedding',
            type: 'memory',
          ));
        }

        final List<dynamic> embedding = data['data'][0]['embedding'];
        return embedding.cast<double>();
      } else {
        print('Embedding API error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Embedding network error: $e');
      return [];
    }
  }

  Future<AiResponse> chat(
    List<Map<String, String>> messages, {
    String usageType = 'main',
    double temperature = 0.7,
    AiProviderConfig? providerOverride,
    String? systemPromptOverride,
    String? assistantNameOverride,
    String? sessionId,
  }) async {
    final provider = providerOverride ?? await _getActiveProvider();
    if (provider == null) throw Exception("No active AI provider configured");

    final prefs = await SharedPreferences.getInstance();
    final userNickname = prefs.getString('settings.user.nickname') ?? '';
    final enablePythonBackend = prefs.getBool('settings.backend.enabled') ?? false;
    final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
    final enableBrowser = prefs.getBool('settings.agent.enableBrowser') ?? false;  // FIX: Use correct key
    final suppressInnerMonologue = prefs.getBool('settings.chat.suppressInnerMonologue') ?? false;
    final systemPrompt = systemPromptOverride ?? (prefs.getString('settings.ai.systemPrompt') ?? '');
    final assistantName = assistantNameOverride ?? (prefs.getString('settings.ai.assistantName') ?? 'Firefly');
    
    // Parse search region from int setting (0: auto, 1: cn, 2: global)
    final searchRegionIdx = prefs.getInt('settings.agent.searchRegion');
    String searchRegion = 'zh-CN'; // Default
    if (searchRegionIdx != null) {
      if (searchRegionIdx == 2) searchRegion = 'wt-wt';
      else if (searchRegionIdx == 1) searchRegion = 'zh-CN';
      else searchRegion = 'zh-CN'; // Auto defaults to CN for now, or could be 'auto' if backend supports it
    }

    // Parse Persona Level
    final personaLevelIdx = prefs.getInt('settings.ui.personaLevel');
    String personaMode = 'full';
    if (personaLevelIdx != null) {
      if (personaLevelIdx == 0) personaMode = 'basic';
      else if (personaLevelIdx == 1) personaMode = 'advanced';
      else personaMode = 'full';
    }
    
    // Parse Chat Mode (persona vs standard)
    final chatModeIdx = prefs.getInt('settings.ui.chatMode');
    String chatMode = 'persona';
    if (chatModeIdx != null) {
      if (chatModeIdx == ChatModeOption.standard.index) {
        chatMode = 'standard';
      }
    }
    
    // Deep Research flag (backend-only orchestration mode)
    final enableDeepResearch = prefs.getBool('settings.backend.deepResearch') ?? false;
    
    // Debug logging
    debugPrint('[LLM] enablePythonBackend: $enablePythonBackend');
    debugPrint('[LLM] enableBrowser from prefs: $enableBrowser');
    debugPrint('[LLM] searchRegion: $searchRegion');
    debugPrint('[LLM] personaMode: $personaMode');
    debugPrint('[LLM] usageType: $usageType');

    // Determine actual target URL and headers
    String requestUrl;
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    if (enablePythonBackend) {
      // Route through Python Backend
      requestUrl = '$backendUrl/v1/chat/completions';
      
      // Pass the underlying provider's config to the backend
      headers['X-Target-Api-Key'] = provider.apiKey;
      if (userNickname.isNotEmpty) {
        headers['X-User-Nickname'] = Uri.encodeComponent(userNickname);
      }
      
      // Sanitize Base URL for backend (remove /chat/completions if present)
      var targetBaseUrl = provider.baseUrl;
      if (targetBaseUrl.endsWith('/chat/completions')) {
        targetBaseUrl = targetBaseUrl.replaceAll('/chat/completions', '');
      }
      if (targetBaseUrl.endsWith('/')) targetBaseUrl = targetBaseUrl.substring(0, targetBaseUrl.length - 1);
      headers['X-Target-Base-Url'] = targetBaseUrl;
      
      headers['X-Target-Model'] = provider.model;
      headers['X-Enable-Browser'] = enableBrowser.toString();
      headers['X-Search-Region'] = searchRegion;
      headers['X-Usage-Type'] = usageType;
      headers['X-Temperature'] = temperature.toString();
      headers['X-Persona-Mode'] = personaMode;
      headers['X-Chat-Mode'] = chatMode;
      headers['X-Deep-Research'] = enableDeepResearch.toString();
      headers['X-Suppress-Inner-Monologue'] = suppressInnerMonologue.toString();
      final learningProbability = prefs.getDouble('settings.user.learningProbability') ?? 1.0;
      headers['X-Learning-Probability'] = learningProbability.toString();
      if (systemPrompt.trim().isNotEmpty) {
        headers['X-System-Prompt'] = Uri.encodeComponent(systemPrompt.trim());
      }
      if (assistantName.trim().isNotEmpty) {
        headers['X-Assistant-Name'] = Uri.encodeComponent(assistantName.trim());
      }
      if (sessionId != null && sessionId.isNotEmpty) {
        headers['X-Session-Id'] = sessionId;
      }

      try {
        final providersRaw = prefs.getString('settings.ai.providers');
        if (providersRaw != null) {
          final List data = jsonDecode(providersRaw) as List;
          final List<Map<String, dynamic>> providers = data.cast<Map<String, dynamic>>();
          Map<String, dynamic>? ttsProvider;
          for (final p in providers) {
            final category = p['category'] as String? ?? 'llm';
            final enabled = p['enabled'] as bool? ?? true;
            if (enabled && category == 'tts') { ttsProvider = p; break; }
          }
          if (ttsProvider != null) {
            final ttsKey = ttsProvider['apiKey'] as String? ?? '';
            var ttsUrl = ttsProvider['baseUrl'] as String? ?? '';
            if (ttsKey.isNotEmpty) headers['X-SiliconFlow-Api-Key'] = ttsKey;
            if (ttsUrl.isNotEmpty) {
              if (ttsUrl.endsWith('/chat/completions')) {
                ttsUrl = ttsUrl.replaceAll('/chat/completions', '');
              }
              if (ttsUrl.endsWith('/')) {
                ttsUrl = ttsUrl.substring(0, ttsUrl.length - 1);
              }
              headers['X-SiliconFlow-Base-Url'] = ttsUrl;
            }
          }
        }
      } catch (_) {}
      
      // --- Vision Agent Configuration ---
      // Only send vision headers when the current request actually uses image content.
      bool hasImageTag = false;
      for (final m in messages) {
        final content = m['content'] ?? '';
        if (content.contains('[IMAGE:')) {
          hasImageTag = true;
          break;
        }
      }
      if (hasImageTag) {
        final activeVisionId = prefs.getString('settings.ai.activeVisionId');
        final visionFallbackAgent = prefs.getBool('settings.vision.fallbackAgent') ?? true;
        final visionPrompt = prefs.getString('settings.vision.promptTemplate') ?? '请用中文用一段话描述这张图片的内容。若有文字请概括其要点。以主题和直观感受为主，避免分点与多段，仅输出纯文本。';
        
        if (activeVisionId != null && activeVisionId.isNotEmpty) {
          final visionProvider = await _getProviderById(activeVisionId);
          if (visionProvider != null) {
            headers['X-Vision-Api-Key'] = visionProvider.apiKey;
            
            var visionBaseUrl = visionProvider.baseUrl;
            if (visionBaseUrl.endsWith('/chat/completions')) {
              visionBaseUrl = visionBaseUrl.replaceAll('/chat/completions', '');
            }
            if (visionBaseUrl.endsWith('/')) visionBaseUrl = visionBaseUrl.substring(0, visionBaseUrl.length - 1);
            headers['X-Vision-Base-Url'] = visionBaseUrl;
            
            headers['X-Vision-Model'] = visionProvider.model;
            headers['X-Vision-Prompt'] = Uri.encodeComponent(visionPrompt);
            headers['X-Vision-Fallback'] = visionFallbackAgent.toString();
            debugPrint('[LLM] Sending Vision Agent Config: ${visionProvider.model}');
          }
        }
      }
      
      debugPrint('[LLM] Sending X-Enable-Browser: ${enableBrowser.toString()}');
      debugPrint('[LLM] Sending X-Search-Region: $searchRegion');

      // Enable Thinking Mode (DeepSeek)
      final enableThinking = prefs.getBool('settings.ai.enableThinking') ?? false;
      headers['X-Enable-Thinking'] = enableThinking.toString();
      debugPrint('[LLM] Sending X-Enable-Thinking: $enableThinking');
      
      // Note: We don't need Authorization header for the local backend unless it requires it.
      // But we might want to pass it if the backend is secured. For now, assume local is open.
    } else {
      // Direct connection
      requestUrl = provider.baseUrl;
      if (provider.isRoot) {
         if (requestUrl.endsWith('/')) requestUrl = requestUrl.substring(0, requestUrl.length - 1);
         requestUrl = '$requestUrl/chat/completions';
      }
      headers['Authorization'] = 'Bearer ${provider.apiKey}';
    }

    final model = provider.model.isNotEmpty ? provider.model : 'gpt-3.5-turbo';
    final supportsVision = _modelSupportsVision(model);

    // Parse messages for multimodal content (images)
    final List<Map<String, dynamic>> payloadMessages = [];
    for (final m in messages) {
      final content = m['content'] ?? '';
      if (supportsVision) {
        payloadMessages.add({
          'role': m['role'],
          'content': _parseMultimodalContent(content),
        });
      } else {
        // For non-vision models, send content as plain text.
        // [IMAGE:...] tags will remain as text, which is fine.
        payloadMessages.add({
          'role': m['role'],
          'content': content,
        });
      }
    }

    final requestBody = jsonEncode({
      'model': model,
      'messages': payloadMessages,
      'temperature': temperature,
      // 'user': 'user_id' // Could pass user ID here if available
    });

    debugPrint('--- [LLM Request] ---');
    debugPrint('URL: $requestUrl');
    debugPrint('Model: $model (Vision: $supportsVision)');
    debugPrint('Headers: $headers');
    // Truncate body log if too long
    debugPrint('Body: ${requestBody.length > 2000 ? requestBody.substring(0, 2000) + '...' : requestBody}');
    debugPrint('-----------------------');

    final response = await http.post(
      Uri.parse(requestUrl),
      headers: headers,
      body: requestBody,
    );

    debugPrint('--- [LLM Response] ---');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Body: ${response.body.length > 500 ? response.body.substring(0, 500) + '...' : response.body}');
    debugPrint('------------------------');

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      
      // Track usage
      if (data.containsKey('usage')) {
        final usage = data['usage'];
        _usageController.add(TokenUsage(
          promptTokens: usage['prompt_tokens'] ?? 0,
          completionTokens: usage['completion_tokens'] ?? 0,
          totalTokens: usage['total_tokens'] ?? 0,
          model: model,
          type: usageType,
        ));
      }

      final choice = data['choices'][0];
      final message = choice['message'];
      final content = message['content'];
      final emotion = data['emotion'] as String?;
      final reasoningContent = message['reasoning_content'];
      final toolCalls = message['tool_calls'];

      return AiResponse(
        content: content, 
        emotion: emotion,
        reasoningContent: reasoningContent,
        toolCalls: toolCalls
      );
    } else {
      throw Exception('Failed to chat: ${response.body}');
    }
  }

  dynamic _parseMultimodalContent(String text) {
    final regex = RegExp(r'\[IMAGE:\s*(.*?)\]');
    if (!regex.hasMatch(text)) return text;

    final List<Map<String, dynamic>> content = [];
    final matches = regex.allMatches(text);
    int lastEnd = 0;

    for (final match in matches) {
      if (match.start > lastEnd) {
        final t = text.substring(lastEnd, match.start);
        if (t.isNotEmpty) content.add({'type': 'text', 'text': t});
      }
      final url = match.group(1)?.trim() ?? '';
      if (url.isNotEmpty) {
        content.add({
          'type': 'image_url',
          'image_url': {'url': url}
        });
      }
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      final t = text.substring(lastEnd);
      if (t.isNotEmpty) content.add({'type': 'text', 'text': t});
    }
    return content;
  }

  Future<String> chatWithProvider(List<Map<String, String>> messages, {String usageType = 'expression', String? providerIdOverride}) async {
    AiProviderConfig? provider = providerIdOverride != null ? await _getProviderById(providerIdOverride) : await _getActiveProvider();
    if (provider == null) throw Exception("No active AI provider configured");

    final apiKey = provider.apiKey;
    var baseUrl = provider.baseUrl;
    final model = provider.model.isNotEmpty ? provider.model : 'gpt-3.5-turbo';

    if (provider.isRoot) {
      if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      baseUrl = '$baseUrl/chat/completions';
    }

    final requestBody = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.4,
    });

    debugPrint('--- [LLM Provider Request ($usageType)] ---');
    debugPrint('URL: $baseUrl');
    debugPrint('Model: $model');
    debugPrint('Body: ${requestBody.length > 1000 ? requestBody.substring(0, 1000) + '...' : requestBody}');
    debugPrint('-----------------------------------------');

    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: requestBody,
    );

    debugPrint('--- [LLM Provider Response ($usageType)] ---');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Body: ${response.body.length > 500 ? response.body.substring(0, 500) + '...' : response.body}');
    debugPrint('------------------------------------------');

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data.containsKey('usage')) {
        final usage = data['usage'];
        _usageController.add(TokenUsage(
          promptTokens: usage['prompt_tokens'] ?? 0,
          completionTokens: usage['completion_tokens'] ?? 0,
          totalTokens: usage['total_tokens'] ?? 0,
          model: model,
          type: usageType,
        ));
      }
      return data['choices'][0]['message']['content'];
    } else {
      throw Exception('Failed chat (override): ${response.body}');
    }
  }

  bool _modelSupportsVision(String model) {
    final m = model.toLowerCase();
    return m.contains('gpt-4o') || m.contains('gpt-4.1') || m.contains('vision') || m.contains('-vl') || m.contains('multimodal');
  }

  Future<String> chatWithImage({
    required List<Map<String, String>> messages,
    required Uint8List imageBytes,
    String? prompt,
    String usageType = 'main',
    String? providerIdOverride,
  }) async {
    AiProviderConfig? provider = providerIdOverride != null
        ? await _getProviderById(providerIdOverride)
        : await _getActiveProvider();
    if (provider == null) throw Exception("No active AI provider configured");

    final prefs = await SharedPreferences.getInstance();
    final enablePythonBackend = prefs.getBool('settings.backend.enabled') ?? false;
    final backendUrl = prefs.getString('settings.backend.url') ?? 'http://localhost:23456';
    final enableBrowser = prefs.getBool('settings.agent.enableBrowser') ?? false;  // FIX: Use correct key
    final systemPrompt = prefs.getString('settings.ai.systemPrompt') ?? '';
    final assistantName = prefs.getString('settings.ai.assistantName') ?? 'Firefly';

    final apiKey = provider.apiKey;
    var baseUrl = provider.baseUrl;
    final model = provider.model.isNotEmpty ? provider.model : 'gpt-4o-mini';

    if (!_modelSupportsVision(model)) {
      throw Exception('当前模型不支持视觉（多模态）');
    }

    String requestUrl;
    Map<String, String> headers = {
      'Content-Type': 'application/json',
    };

    if (enablePythonBackend) {
      // Route through Python Backend (allow override to be proxied)
      requestUrl = '$backendUrl/v1/chat/completions';
      headers['X-Target-Api-Key'] = apiKey;
      
      var targetBaseUrl = baseUrl;
      if (targetBaseUrl.endsWith('/chat/completions')) {
        targetBaseUrl = targetBaseUrl.replaceAll('/chat/completions', '');
      }
      if (targetBaseUrl.endsWith('/')) targetBaseUrl = targetBaseUrl.substring(0, targetBaseUrl.length - 1);
      headers['X-Target-Base-Url'] = targetBaseUrl;
      
      headers['X-Target-Model'] = model;
      headers['X-Enable-Browser'] = enableBrowser.toString();
      headers['X-Usage-Type'] = usageType;
      if (systemPrompt.trim().isNotEmpty) {
        headers['X-System-Prompt'] = Uri.encodeComponent(systemPrompt.trim());
      }
      if (assistantName.trim().isNotEmpty) {
        headers['X-Assistant-Name'] = Uri.encodeComponent(assistantName.trim());
      }
    } else {
      // Direct connection
      requestUrl = baseUrl;
      if (provider.isRoot) {
        if (requestUrl.endsWith('/')) requestUrl = requestUrl.substring(0, requestUrl.length - 1);
        requestUrl = '$requestUrl/chat/completions';
      }
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final imageB64 = base64Encode(imageBytes);

    // Build payload messages as dynamic to allow array content for multimodal
    final List<Map<String, dynamic>> payloadMessages = [];
    for (final m in messages) {
      payloadMessages.add({
        'role': m['role'],
        'content': m['content'],
      });
    }
    payloadMessages.add({
      'role': 'user',
      'content': [
        if (prompt != null && prompt.isNotEmpty) {'type': 'text', 'text': prompt},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:image/png;base64,$imageB64'}
        }
      ]
    });

    final requestBody = jsonEncode({
      'model': model,
      'messages': payloadMessages,
      'temperature': 0.7,
    });

    debugPrint('--- [LLM Vision Request] ---');
    debugPrint('URL: $requestUrl');
    debugPrint('Model: $model');
    // Don't log full body for vision as base64 is huge
    debugPrint('Body (truncated): ${requestBody.length > 500 ? requestBody.substring(0, 500) + '... [Image Data Omitted] ...' : requestBody}');
    debugPrint('----------------------------');

    final response = await http.post(
      Uri.parse(requestUrl),
      headers: headers,
      body: requestBody,
    );

    debugPrint('--- [LLM Vision Response] ---');
    debugPrint('Status: ${response.statusCode}');
    debugPrint('Body: ${response.body.length > 500 ? response.body.substring(0, 500) + '...' : response.body}');
    debugPrint('-----------------------------');

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data.containsKey('usage')) {
        final usage = data['usage'];
        _usageController.add(TokenUsage(
          promptTokens: usage['prompt_tokens'] ?? 0,
          completionTokens: usage['completion_tokens'] ?? 0,
          totalTokens: usage['total_tokens'] ?? 0,
          model: model,
          type: usageType,
        ));
      }
      return data['choices'][0]['message']['content'];
    } else {
      throw Exception('Failed vision chat: ${response.body}');
    }
  }
}
