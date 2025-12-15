import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_windows/webview_windows.dart';
import 'logger_service.dart';

class DiagnosticsService {
  static final DiagnosticsService _instance = DiagnosticsService._internal();
  factory DiagnosticsService() => _instance;
  DiagnosticsService._internal();

  bool _isWebViewAvailable = false;
  String _backendStatus = "Unknown";
  String _pluginStatus = "Unknown";

  bool get isWebViewAvailable => _isWebViewAvailable;

  Future<void> runDiagnostics(String backendUrl) async {
    logger.info("Starting System Diagnostics...");

    // 1. Check Backend Connectivity
    try {
      final uri = Uri.parse('$backendUrl/static/live2d/index.html');
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
        final webview = WebviewController();
        // Add timeout to prevent hanging if runtime is stuck
        await webview.initialize().timeout(const Duration(seconds: 5));
        _isWebViewAvailable = true;
        _pluginStatus = "Initialized Successfully";
        logger.info("[Diagnostics] WebView2: $_pluginStatus");
        await webview.dispose();
      } on MissingPluginException catch (e) {
        _isWebViewAvailable = false;
        _pluginStatus = "MissingPluginException: ${e.message}";
        logger.error("[Diagnostics] WebView2 Plugin Failed: $_pluginStatus");
        logger.error("CRITICAL: The native plugin 'webview_windows' is not linked. Please rebuild the app.");
      } on PlatformException catch (e) {
        _isWebViewAvailable = false;
        _pluginStatus = "PlatformException: ${e.message}";
        logger.error("[Diagnostics] WebView2 Runtime Error: $_pluginStatus");
        if (e.message?.contains("WebView2 Runtime") ?? false) {
           logger.error("CRITICAL: Microsoft Edge WebView2 Runtime is missing. Please install it.");
        }
      } catch (e) {
        _isWebViewAvailable = false;
        _pluginStatus = "Unknown Error: $e";
        logger.error("[Diagnostics] WebView2 Generic Error: $e");
      }
    } else {
      _pluginStatus = "Skipped (Not Windows)";
    }
    
    logger.info("Diagnostics Complete.");
  }
}
