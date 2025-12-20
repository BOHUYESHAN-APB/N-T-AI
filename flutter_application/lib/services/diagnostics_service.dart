import 'dart:async';
import 'dart:io';
// import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:desktop_webview_window/desktop_webview_window.dart';
// import 'package:webview_windows/webview_windows.dart';
import 'logger_service.dart';

class DiagnosticsService {
  static final DiagnosticsService _instance = DiagnosticsService._internal();
  factory DiagnosticsService() => _instance;
  DiagnosticsService._internal();

  final Completer<void> _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  bool _isWebViewAvailable = false;
  String _backendStatus = "Unknown";
  String _pluginStatus = "Unknown";

  bool get isWebViewAvailable => _isWebViewAvailable;

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    final base = trimmed.isEmpty ? 'http://localhost:23456' : trimmed;
    return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  }

  Future<void> runDiagnostics(String backendUrl) async {
    logger.info("Starting System Diagnostics...");

    // 1. Check Backend Connectivity
    try {
      final baseUrl = _normalizeBaseUrl(backendUrl);
      final uri = Uri.parse('$baseUrl/static/live2d/index.html');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200 || response.statusCode == 304) {
        _backendStatus = "Connected (HTTP ${response.statusCode})";
        logger.info("[Diagnostics] Backend: $_backendStatus");
      } else {
        _backendStatus = "Error (HTTP ${response.statusCode})";
        logger.warning("[Diagnostics] Backend: $_backendStatus");
      }
    } catch (e) {
      _backendStatus = "Unreachable ($e)";
      logger.error("[Diagnostics] Backend: $_backendStatus");
    }

    // 2. Check WebView2 Runtime & Plugin (Windows only)
    if (Platform.isWindows) {
      try {
        _isWebViewAvailable = await WebviewWindow.isWebviewAvailable();
        _pluginStatus = _isWebViewAvailable ? "Available" : "Not Available";
        logger.info("[Diagnostics] WebView2 (desktop_webview_window): $_pluginStatus");
      } catch (e) {
        _isWebViewAvailable = false;
        _pluginStatus = "Check Failed: $e";
        logger.error("[Diagnostics] WebView2 Check Error: $e");
      }
    } else {
      _pluginStatus = "Skipped (Not Windows)";
    }
    
    logger.info("Diagnostics Complete.");
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
  }
}
