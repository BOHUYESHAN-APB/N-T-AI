import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  LogLevel _minLevel = LogLevel.info;

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
  }

  int _toDevLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug: return 500;
      case LogLevel.info: return 800;
      case LogLevel.warning: return 900;
      case LogLevel.error: return 1000;
    }
  }
}

final logger = LoggerService();
