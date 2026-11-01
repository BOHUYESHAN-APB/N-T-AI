import 'dart:convert';

class WindowType {
  static const String main = 'main';
  static const String live2d = 'live2d';
  static const String control = 'control';
}

class WindowArgs {
  final String type;
  final Map<String, dynamic> data;

  const WindowArgs({required this.type, required this.data});

  static WindowArgs fromString(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const WindowArgs(type: WindowType.main, data: {});
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final type = (decoded['type'] ?? WindowType.main).toString();
        final data = decoded['data'];
        if (data is Map) {
          return WindowArgs(
            type: type,
            data: data.cast<String, dynamic>(),
          );
        }
        return WindowArgs(type: type, data: const {});
      }
    } catch (_) {}
    return const WindowArgs(type: WindowType.main, data: {});
  }

  static String encode(String type, [Map<String, dynamic>? data]) {
    return jsonEncode({'type': type, 'data': data ?? {}});
  }
}
