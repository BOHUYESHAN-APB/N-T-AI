import 'package:flutter/material.dart';
import 'dart:convert';
import '../widgets/expressive_face.dart';

class ExpressionService {
  // Map from loose model-provided map to ExpressionData, with clamping and defaults.
  static ExpressionData fromMap(Map<String, dynamic> m) {
    double _toDouble(Object? v, double fallback) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      try {
        return double.parse(v.toString());
      } catch (_) {
        return fallback;
      }
    }

    // Mouth: -1 (frown) .. 1 (big smile). Keep model-provided semantics.
    final mouth = _toDouble(m['mouth'] ?? m['smile'] ?? m['mouth_curvature'], 0.0).clamp(-1.0, 1.0);
    final eyes = _toDouble(m['eyes'] ?? m['eye_open'] ?? m['eye'], 1.0).clamp(0.0, 1.0);
    // Eyebrow: -1 (down) .. 1 (up). Keep model-provided semantics.
    final eyebrow = _toDouble(m['eyebrow'] ?? m['brow'] ?? m['eyebrow_tilt'], 0.0).clamp(-1.0, 1.0);
    final blush = _toDouble(m['blush'] ?? m['cheeks'] ?? 0.0, 0.0).clamp(0.0, 1.0);
    final pupilX = _toDouble(m['pupil_x'] ?? m['look_x'] ?? 0.0, 0.0).clamp(-1.0, 1.0);
    final pupilY = _toDouble(m['pupil_y'] ?? m['look_y'] ?? 0.0, 0.0).clamp(-1.0, 1.0);
    final headTilt = _toDouble(m['head_tilt'] ?? 0.0, 0.0).clamp(-0.5, 0.5);

    Color faceColor = ExpressionData.neutral().faceColor;
    if (m.containsKey('face_color')) {
      try {
        final s = m['face_color'].toString();
        if (s.startsWith('#')) {
          final hex = int.parse(s.substring(1), radix: 16);
          faceColor = Color(0xFF000000 | hex);
        }
      } catch (_) {}
    }

    final result = ExpressionData(
      mouth: mouth,
      eyes: eyes,
      eyebrow: eyebrow,
      blush: blush,
      pupilX: pupilX,
      pupilY: pupilY,
      headTilt: headTilt,
      faceColor: faceColor,
    );

    // Debug: log mapping from incoming map to ExpressionData for diagnosis.
    try {
      // ignore: avoid_print
      print('[ExpressionService] mapped from ${m} -> mouth:${result.mouth}, eyebrow:${result.eyebrow}, eyes:${result.eyes}');
    } catch (_) {}

    return result;
  }

  static Map<String, dynamic> toMap(ExpressionData e) => {
        'mouth': e.mouth,
        'eyes': e.eyes,
        'eyebrow': e.eyebrow,
        'blush': e.blush,
        'pupil_x': e.pupilX,
        'pupil_y': e.pupilY,
        'head_tilt': e.headTilt,
        'face_color': '#${e.faceColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
      };

  /// Try to extract an expression payload from assistant text.
  /// Supports formats:
  /// - Code fence JSON with either { ... } or { "expression": { ... } }
  /// - Inline JSON after keyword 'expression:'
  /// - Heuristic mapping for common Chinese emotion words
  static Map<String, dynamic>? tryExtractExpressionPayload(String text) {
    // 1) Code fence ```json ... ```
    final fenceJson = _extractBetween(text, '```json', '```') ?? _extractBetween(text, '```', '```');
    if (fenceJson != null) {
      final m = _safeJsonMap(fenceJson);
      if (m != null) {
        if (m.containsKey('expression') && m['expression'] is Map<String, dynamic>) {
          return (m['expression'] as Map).cast<String, dynamic>();
        }
        return m; // assume it's directly the payload
      }
    }
    // 2) Inline after 'expression:'
    final idx = text.toLowerCase().indexOf('expression:');
    if (idx != -1) {
      final snippet = text.substring(idx + 'expression:'.length).trim();
      // find first '{' ... last '}'
      final start = snippet.indexOf('{');
      final end = snippet.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        final jsonStr = snippet.substring(start, end + 1);
        final m = _safeJsonMap(jsonStr);
        if (m != null) return m;
      }
    }
    // 3) Heuristic mapping
    final h = _heuristicFromText(text);
    if (h != null) return h;
    return null;
  }

  static Map<String, dynamic>? _safeJsonMap(String src) {
    try {
      final v = jsonDecode(src);
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  static String? _extractBetween(String src, String begin, String end) {
    final s = src.indexOf(begin);
    if (s == -1) return null;
    final e = src.indexOf(end, s + begin.length);
    if (e == -1) return null;
    return src.substring(s + begin.length, e);
  }

  static Map<String, dynamic>? _heuristicFromText(String text) {
    final t = text.replaceAll(RegExp(r'\s+'), '');
    Map<String, dynamic>? payload;
    if (RegExp(r'(笑|开心|高兴|愉快|喜悦)').hasMatch(t)) {
      payload = {
        'mouth': 0.85,
        'eyes': 1.0,
        'eyebrow': 0.5,
        'blush': 0.4,
        'pupil_x': 0.0,
        'pupil_y': -0.05,
        'head_tilt': -0.06,
      };
    } else if (RegExp(r'(难过|伤心|沮丧|委屈)').hasMatch(t)) {
      payload = {
        'mouth': -0.75,
        'eyes': 0.85,
        'eyebrow': -0.5,
        'blush': 0.0,
        'pupil_x': 0.0,
        'pupil_y': 0.1,
        'head_tilt': 0.03,
      };
    } else if (RegExp(r'(惊讶|震惊|哇)').hasMatch(t)) {
      payload = {
        'mouth': 0.2,
        'eyes': 1.0,
        'eyebrow': 0.9,
        'blush': 0.35,
        'pupil_x': 0.0,
        'pupil_y': -0.1,
        'head_tilt': -0.12,
      };
    } else if (RegExp(r'(生气|愤怒|气死)').hasMatch(t)) {
      payload = {
        'mouth': -0.2,
        'eyes': 0.95,
        'eyebrow': -0.8,
        'blush': 0.2,
        'pupil_x': 0.15,
        'pupil_y': 0.0,
        'head_tilt': 0.06,
      };
    }
    return payload;
  }
}
