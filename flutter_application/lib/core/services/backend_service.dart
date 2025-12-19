import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for managing the Python backend process and connection.
class BackendService {
  static final BackendService _instance = BackendService._internal();
  factory BackendService() => _instance;
  BackendService._internal();

  Process? _backendProcess;
  bool _isConnected = false;
  String _backendUrl = 'http://localhost:23456';
  
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

  /// Checks if a local port is in use.
  Future<bool> _isPortInUse(int port) async {
    try {
      final socket = await Socket.connect('localhost', port, timeout: const Duration(milliseconds: 200));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Attempts to start the bundled Python backend on Windows.
  Future<void> _startLocalBackend() async {
    // Force enable backend, ignoring potentially stale settings
    const enabled = true; 
    
    if (!enabled) {
      debugPrint('[BackendService] Backend disabled in settings.');
      return;
    }

    // Dynamic Port Logic:
    // We do NOT strictly check port 8000 anymore, because the backend is now smart enough to auto-select a port (8000-8010).
    // Instead, we will:
    // 1. Try to read 'server_info.json' first to see if a valid backend is already alive.
    // 2. If alive, use that URL.
    // 3. If not, start the process.
    // 4. Watch for 'server_info.json' update or stdout to get the actual port.

    try {
      final appDir = p.dirname(Platform.resolvedExecutable);
      
      // Locate 'server_info.json' - usually in the same dir as the executable or current dir
      // Since we don't know exactly where the backend writes it (relative to CWD), we assume CWD of the backend.
      // But we haven't started it yet.
      // Let's first try to locate the executable to know the CWD.
      
      String exePath = p.join(appDir, 'server', 'server.exe');
      if (!await File(exePath).exists()) {
        // Fallbacks...
        final curDir = Directory.current.path;
        exePath = p.join(curDir, 'server', 'server.exe');
      }
      if (!await File(exePath).exists()) {
         exePath = p.join(Directory.current.path, 'flutter_application', 'server', 'server.exe');
         if (!await File(exePath).exists()) {
             exePath = r'd:\-Users-\Documents\GitHub\N-T-AI\flutter_application\server\server.exe';
         }
      }

      if (!await File(exePath).exists()) {
        debugPrint('[BackendService] Server executable not found at $exePath. Assuming remote/manual backend.');
        return;
      }
      
      final backendWorkDir = p.dirname(exePath);
      final serverInfoFile = File(p.join(backendWorkDir, 'server_info.json'));

      // Check if already running by reading server_info.json
      if (await serverInfoFile.exists()) {
        try {
           final content = await serverInfoFile.readAsString();
           final info = jsonDecode(content);
           final url = info['url'] as String;
           // Verify health
           final uri = Uri.parse('$url/health');
           try {
             final resp = await http.get(uri).timeout(const Duration(milliseconds: 500));
             if (resp.statusCode == 200) {
               debugPrint('[BackendService] Found existing active backend at $url');
               _updateUrlAndNotify(url);
               _updateStatus(BackendStatus.connected);
               return; // Already running and healthy
             }
           } catch (_) {
             debugPrint('[BackendService] Stale server_info.json found. Restarting...');
           }
        } catch (e) {
          debugPrint('[BackendService] Error reading server_info.json: $e');
        }
      }

      debugPrint('[BackendService] Starting local backend: $exePath');
      
      // 2. Start the process
      _backendProcess = await Process.start(
        exePath,
        [],
        mode: ProcessStartMode.normal, // Use normal mode to capture stdout/stderr
        workingDirectory: backendWorkDir,
      );
      
      debugPrint('[BackendService] Backend process started with PID: ${_backendProcess?.pid}');
      
      // Monitor stdout/stderr to capture [SERVER_INFO] or just wait for file
      _backendProcess?.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[Backend Server] $data');
        if (data.contains('[SERVER_INFO]')) {
           try {
             final jsonStr = data.split('[SERVER_INFO]')[1].trim();
             final info = jsonDecode(jsonStr);
             final url = info['url'];
             debugPrint('[BackendService] Detected backend URL from stdout: $url');
             _updateUrlAndNotify(url);
           } catch (e) {
             debugPrint('[BackendService] Failed to parse SERVER_INFO: $e');
           }
        }
      });
      
      _backendProcess?.stderr.listen((data) {
        debugPrint('[Backend Server Error] ${String.fromCharCodes(data)}');
      });
      
      // Polling for server_info.json as a backup if stdout parsing fails or is delayed
      int attempts = 0;
      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        attempts++;
        if (attempts > 20 || _isConnected) { // Stop after 10 seconds or if connected
          timer.cancel();
          return;
        }
        
        if (await serverInfoFile.exists()) {
          try {
             final content = await serverInfoFile.readAsString();
             final info = jsonDecode(content);
             final url = info['url'];
             if (url != _backendUrl) {
                debugPrint('[BackendService] Detected backend URL from file: $url');
                _updateUrlAndNotify(url);
                timer.cancel();
             }
          } catch (_) {}
        }
      });

    } catch (e) {
      debugPrint('[BackendService] Failed to start local backend: $e');
    }
  }

  void _updateUrlAndNotify(String url) {
    if (_backendUrl != url) {
      _backendUrl = url;
      // Also update shared prefs so other services pick it up
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('settings.backend.url', url);
        // Also update SettingsController via global scope if possible, but simpler to just set pref
        // because SettingsController listens to prefs or reloads.
        // Actually, SettingsController might need a reload. 
        // For now, we rely on services using BackendService singleton or reading prefs.
      });
      // Notify internal listeners
      checkConnection();
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
