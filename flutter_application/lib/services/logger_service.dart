import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

enum LogLevel { debug, info, warning, error }

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  LogLevel _minLevel = LogLevel.info;
  int _maxErrors = 5;
  List<Map<String, dynamic>> _recentErrors = [];
  String _backendUrl = '';

  Future<void> init({int? maxErrors, String? backendUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getInt('settings.logs.maxErrors');
    _maxErrors = maxErrors ?? n ?? 5;
    if (backendUrl != null) _backendUrl = backendUrl;
    final raw = prefs.getString('settings.logs.errors');
    if (raw != null && raw.isNotEmpty) {
      try {
        final List data = jsonDecode(raw) as List;
        _recentErrors = data.cast<Map<String, dynamic>>();
      } catch (_) {}
    }
  }

  Future<void> setMaxErrors(int n) async {
    if (n <= 0) return;
    _maxErrors = n;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('settings.logs.maxErrors', n);
    if (_recentErrors.length > n) {
      _recentErrors = _recentErrors.sublist(_recentErrors.length - n);
      await _persistErrors();
    }
  }

  void setBackendUrl(String url) {
    _backendUrl = url;
  }

  List<Map<String, dynamic>> getRecentErrors() {
    return List<Map<String, dynamic>>.from(_recentErrors);
  }

  Future<void> clearRecentErrors() async {
    _recentErrors.clear();
    await _persistErrors();
  }

  Future<void> _persistErrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings.logs.errors', jsonEncode(_recentErrors));
  }

  void setLevel(LogLevel level) {
    _minLevel = level;
  }

  void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.debug, message, error, stackTrace);
  }

  void info(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.info, message, error, stackTrace);
  }

  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.warning, message, error, stackTrace);
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }

  void _log(LogLevel level, String message, [Object? error, StackTrace? stackTrace]) {
    if (level.index < _minLevel.index) return;

    final timestamp = DateTime.now().toIso8601String();
    final prefix = '[${level.name.toUpperCase()}]';
    
    if (kDebugMode) {
      developer.log(
        message,
        time: DateTime.now(),
        level: _toDevLevel(level),
        name: 'N-T-AI',
        error: error,
        stackTrace: stackTrace,
      );
      // Also print to console for visibility in some terminals
      print('$timestamp $prefix $message');
      if (error != null) print(error);
      if (stackTrace != null) print(stackTrace);
    }

    if (level == LogLevel.error) {
      final entry = {
        'timestamp': DateTime.now().millisecondsSinceEpoch.toDouble() / 1000.0,
        'level': 'ERROR',
        'message': message,
        'exception': error?.toString(),
      };
      _recentErrors.add(entry);
      if (_recentErrors.length > _maxErrors) {
        _recentErrors = _recentErrors.sublist(_recentErrors.length - _maxErrors);
      }
      _persistErrors();
      _sendToBackend();
    }
  }

  int _toDevLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return 500;
      case LogLevel.info: return 800;
      case LogLevel.warning: return 900;
      case LogLevel.error: return 1000;
    }
  }

  void _sendToBackend() {
    if (_backendUrl.isEmpty) return;
    try {
      final uri = Uri.parse('$_backendUrl/api/logs/frontend');
      final payload = jsonEncode({'errors': _recentErrors, 'max': _maxErrors});
      http.post(uri, headers: {'Content-Type': 'application/json'}, body: payload);
    } catch (_) {}
  }
}

final logger = LoggerService();
