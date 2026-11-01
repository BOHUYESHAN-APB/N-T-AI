import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../services/expression_service.dart';
import '../../widgets/expressive_face.dart';
import 'llm_service.dart';

/// ExpressionInferenceAgentService
/// Independently infers ExpressionData from plain assistant text using either:
/// 1. Lightweight heuristic (Chinese emotion keywords)
/// 2. A small override model (providerId) producing ONLY JSON {"expression": {...}}
/// Falls back silently if inference fails.
class ExpressionInferenceAgentService {
  final LLMService _llm = LLMService();

  /// Infer expression from raw text. Returns null if no emotion detected.
  Future<ExpressionData?> infer(String text, {String? providerIdOverride}) async {
    // First try heuristic for zero-cost fast path
    final heuristic = ExpressionService.tryExtractExpressionPayload(text);
    if (heuristic != null) {
      return ExpressionService.fromMap(heuristic);
    }

    // If no heuristic match and provider override given, ask small model
    if (providerIdOverride != null && providerIdOverride.isNotEmpty) {
      try {
        const sys = '你现在是一个情绪分析模块。请阅读用户与助手的对话最后一段内容（仅这一段文本），输出 JSON，不要包含解释，不要使用 markdown 代码块：\n格式: {"expression": {"mouth": -1..1, "eyes": 0..1, "eyebrow": -1..1, "blush": 0..1, "pupil_x": -1..1, "pupil_y": -1..1, "head_tilt": -0.5..0.5}}\n规则: 若无法判断情绪则输出 {"expression": {"mouth":0, "eyes":1, "eyebrow":0, "blush":0, "pupil_x":0, "pupil_y":0, "head_tilt":0}}';
        final user = text.length > 600 ? text.substring(text.length - 600) : text; // truncate last part
        final raw = await _llm.chatWithProvider([
          {'role': 'system', 'content': sys},
          {'role': 'user', 'content': user},
        ], usageType: 'expression', providerIdOverride: providerIdOverride);
        // Clean potential fences
        var cleaned = raw.trim();
        if (cleaned.startsWith('```')) {
          final idx = cleaned.indexOf('{');
          if (idx != -1) cleaned = cleaned.substring(idx);
          cleaned = cleaned.replaceAll('```', '');
        }
        Map<String, dynamic> map;
        try {
          map = jsonDecode(cleaned) as Map<String, dynamic>;
        } catch (_) {
          return null; // fail silently
        }
        if (map.containsKey('expression')) {
          final inner = map['expression'];
          if (inner is Map<String, dynamic>) {
            return ExpressionService.fromMap(inner);
          }
        }
        return ExpressionService.fromMap(map);
      } catch (e) {
        if (kDebugMode) {
          print('Expression inference model failed: $e');
        }
      }
    }
    return null;
  }
}
