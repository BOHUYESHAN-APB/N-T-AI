import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Service responsible for managing the Python backend process and connection.
class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  Process? _backendProcess;
  bool _isConnected = false;
  String _backendUrl = 'http://localhost:8000';
  
  // Stream to notify UI about connection status changes
  final _statusController = StreamController<BackendStatus>.broadcast();
  Stream<BackendStatus> get statusStream => _statusController.stream;

  BackendStatus _currentStatus = BackendStatus.disconnected;
  BackendStatus get currentStatus => _currentStatus;

  /// Initialize the backend service.
  /// On Windows, this will attempt to start the local backend server.
  /// On Android, it will check connection to the configured URL.
  Future<void> init(String configuredUrl) async {
    _backendUrl = configuredUrl;
    _updateStatus(BackendStatus.initializing);

    if (Platform.isWindows) {
      await _startLocalBackend();
    }
    
    // Start periodic health check
    _startHealthCheck();
  }

  /// Updates the configured backend URL (e.g. from Settings).
  void updateUrl(String newUrl) {
    _backendUrl = newUrl;
    // Trigger immediate check
    checkConnection();
  }

  /// Attempts to start the bundled Python backend on Windows.
  Future<void> _startLocalBackend() async {
    try {
      // 1. Locate the server executable
      // In development: flutter_application/server/server.exe
      // In MSIX/Release: <AppDir>/server/server.exe
      
      // Use Platform.resolvedExecutable to get the directory of the running EXE
      // This is safer than Directory.current which depends on how the app is launched
      final appDir = p.dirname(Platform.resolvedExecutable);
      String exePath = p.join(appDir, 'server', 'server.exe');
      
      // Handle MSIX install location if needed (usually Directory.current is correct for simple bundling)
      // Check if file exists
      if (!await File(exePath).exists()) {
        // Fallback for dev environment where we might be running from source
        // and Platform.resolvedExecutable points to the dart runner
        exePath = p.join(Directory.current.path, 'server', 'server.exe');
      }
      
      if (!await File(exePath).exists()) {
        // Fallback for dev environment (one level up)
        exePath = p.join(Directory.current.path, '..', 'server', 'server.exe');
      }

      if (!await File(exePath).exists()) {
        debugPrint('[BackendService] Server executable not found at $exePath. Assuming remote/manual backend.');
        return;
      }

      debugPrint('[BackendService] Starting local backend: $exePath');
      
      // 2. Start the process
      _backendProcess = await Process.start(
        exePath,
        [],
        mode: ProcessStartMode.normal, // Use normal mode to capture stdout/stderr
        workingDirectory: p.dirname(exePath),
      );
      
      debugPrint('[BackendService] Backend process started with PID: ${_backendProcess?.pid}');
      
      // Monitor stdout/stderr
      _backendProcess?.stdout.listen((data) {
        debugPrint('[Backend Server] ${String.fromCharCodes(data)}');
      });
      _backendProcess?.stderr.listen((data) {
        debugPrint('[Backend Server Error] ${String.fromCharCodes(data)}');
      });

    } catch (e) {
      debugPrint('[BackendService] Failed to start local backend: $e');
    }
  }

  /// Periodically checks if the backend is reachable.
  void _startHealthCheck() {
    Timer.periodic(const Duration(seconds: 5), (timer) {
      checkConnection();
    });
    // Check immediately
    checkConnection();
  }

  Future<void> checkConnection() async {
    try {
      final uri = Uri.parse('$_backendUrl/health'); // Assuming /health or root exists
      // Use a short timeout
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        if (!_isConnected) {
          _isConnected = true;
          _updateStatus(BackendStatus.connected);
          debugPrint('[BackendService] Connected to $_backendUrl');
        }
      } else {
        if (_isConnected) {
          _isConnected = false;
          _updateStatus(BackendStatus.disconnected);
          debugPrint('[BackendService] Disconnected (Status ${response.statusCode})');
        }
      }
    } catch (e) {
      if (_isConnected) {
        _isConnected = false;
        _updateStatus(BackendStatus.disconnected);
        debugPrint('[BackendService] Connection lost: $e');
      }
    }
  }

  void _updateStatus(BackendStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  /// Stop the backend process if we started it.
  void dispose() {
    _backendProcess?.kill();
    _statusController.close();
  }
}

enum BackendStatus {
  initializing,
  connected,
  disconnected,
}
