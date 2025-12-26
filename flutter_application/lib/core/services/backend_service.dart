import 'dart:async';
import 'dart:convert';
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
  String get backendUrl => _backendUrl;
  bool _enabled = false;
  Timer? _healthCheckTimer;
  Timer? _serverInfoPollTimer;
  final Map<String, int> _lastLogMs = {};
  
  // Stream to notify UI about connection status changes
  final _statusController = StreamController<BackendStatus>.broadcast();
  Stream<BackendStatus> get statusStream => _statusController.stream;

  final _urlController = StreamController<String>.broadcast();
  Stream<String> get urlStream => _urlController.stream;

  BackendStatus _currentStatus = BackendStatus.disconnected;
  BackendStatus get currentStatus => _currentStatus;

  String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'http://localhost:23456';
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  Future<bool> _isCompatibleBackend(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      debugPrint('[BackendService] Checking compatibility: $uri');
      final resp = await http.get(uri).timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) {
        debugPrint('[BackendService] Health check failed: Status ${resp.statusCode}');
        return false;
      }
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final isCompatible = body is Map && body['service']?.toString() == 'nt-ai-backend';
      if (!isCompatible) {
         debugPrint('[BackendService] Health check failed: Incompatible response $body');
      }
      return isCompatible;
    } catch (e) {
      debugPrint('[BackendService] Health check failed: $e');
      return false;
    }
  }

  /// Initialize the backend service.
  /// On Windows, this will attempt to start the local backend server.
  /// On Android, it will check connection to the configured URL.
  Future<void> init(
    String configuredUrl, {
    required bool enabled,
    bool autoStartLocal = false,
  }) async {
    _backendUrl = _normalizeBaseUrl(configuredUrl);
    if (!enabled) {
      _enabled = false;
      _isConnected = false;
      _stopHealthCheck();
      _updateStatus(BackendStatus.disconnected);
      return;
    }

    _enabled = true;
    _updateStatus(BackendStatus.initializing);

    // 1. First, try to connect to the configured URL directly.
    // If the user has manually started a backend (e.g. on port 23456) and configured it,
    // we should prioritize that over starting a new instance or reading stale server_info.json.
    if (await _isCompatibleBackend(_backendUrl)) {
      debugPrint('[BackendService] Successfully connected to configured backend at $_backendUrl');
      _updateStatus(BackendStatus.connected);
      _isConnected = true;
      // Start health check to maintain status
      _startHealthCheck();
      return;
    } else {
      debugPrint('[BackendService] Initial connection to $_backendUrl failed.');
    }

    // 2. If connection failed and auto-start is enabled, try to start local backend.
    // We allow this in Debug mode too if the user explicitly enabled the switch.
    if (autoStartLocal && Platform.isWindows) {
      final uri = Uri.tryParse(configuredUrl);
      final port = uri?.port ?? 23456;
      
      // Heuristic: If port is custom (not 23456 or legacy 8000), do not auto-start bundled backend.
      // This prevents the bundled backend from overriding a manually configured backend that might just be slow to start.
      if (port != 23456 && port != 8000 && (port < 8000 || port > 8020)) {
         debugPrint('[BackendService] Configured port $port suggests custom backend. Skipping auto-start of bundled backend.');
         _startHealthCheck();
         return;
      }

      final host = uri?.host.toLowerCase() ?? '';
      final isLocalhost = host.isEmpty || host == 'localhost' || host == '127.0.0.1';
      if (isLocalhost) {
        await _startLocalBackend();
      }
    }
    
    // Start periodic health check
    _startHealthCheck();
  }

  /// Updates the configured backend URL (e.g. from Settings).
  void updateUrl(String newUrl) {
    final normalized = _normalizeBaseUrl(newUrl);
    if (_backendUrl != normalized) {
      _backendUrl = normalized;
      _urlController.add(_backendUrl);
    }
    // Trigger immediate check
    if (_enabled) {
      checkConnection();
    }
  }

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) {
      _isConnected = false;
      _stopHealthCheck();
      _updateStatus(BackendStatus.disconnected);
      return;
    }
    _updateStatus(BackendStatus.initializing);
    _startHealthCheck();
  }

  /// Attempts to start the bundled Python backend on Windows.
  Future<void> _startLocalBackend() async {
    // Debug 模式下，严禁启动同级 server.exe，防止混淆 (用户反馈构建脚本可能导致 server 文件夹残留)
    if (kDebugMode) {
       debugPrint('[BackendService] Debug mode: Skipping local backend startup to avoid conflict with development backend.');
       return; 
    }

    // Dynamic Port Logic:
    // We do NOT strictly check port 23456 anymore, because the backend is now smart enough to auto-select a port (23456-23466).
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
           if (await _isCompatibleBackend(url)) {
             debugPrint('[BackendService] Found existing active backend at $url');
             _updateUrlAndNotify(url);
             _updateStatus(BackendStatus.connected);
             return;
           } else {
             debugPrint('[BackendService] Stale or incompatible server_info.json found. Restarting...');
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
        environment: {'DISABLE_PORT_SCAN': 'true'},
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
             final now = DateTime.now().millisecondsSinceEpoch;
             final last = _lastLogMs['server_info_stdout'] ?? 0;
             if (now - last > 2000) {
               _lastLogMs['server_info_stdout'] = now;
               debugPrint('[BackendService] Detected backend URL from stdout: $url');
             }
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
      _serverInfoPollTimer?.cancel();
      _serverInfoPollTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
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
                final now = DateTime.now().millisecondsSinceEpoch;
                final last = _lastLogMs['server_info_file'] ?? 0;
                if (now - last > 2000) {
                  _lastLogMs['server_info_file'] = now;
                  debugPrint('[BackendService] Detected backend URL from file: $url');
                }
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
    final normalized = _normalizeBaseUrl(url);
    if (_backendUrl != normalized) {
      _backendUrl = normalized;
      debugPrint('[BackendService] Backend URL updated to: $url');
      // Also update shared prefs so other services pick it up
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('settings.backend.url', url);
        // Force update SettingsController if it's already initialized
        // This is a bit of a hack, ideally SettingsController should listen to BackendService
        // But since we don't have direct access to the controller instance here easily without GetIt/Provider context,
        // we rely on the preference update.
        // HOWEVER, SettingsController usually loads once. We need to tell the UI to refresh.
        // Let's rely on the stream.
      });
      _urlController.add(_backendUrl);
      // Notify internal listeners
      checkConnection();
    }
  }

  /// Periodically checks if the backend is reachable.
  void _startHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkConnection();
    });
    // Check immediately
    checkConnection();
  }

  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }

  Future<void> checkConnection() async {
    if (!_enabled) return;
    try {
      final uri = Uri.parse('$_backendUrl/health'); // Assuming /health or root exists
      // Use a short timeout
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        final compatible = body is Map && body['service']?.toString() == 'nt-ai-backend';
        if (compatible) {
          _isConnected = true;
          _updateStatus(BackendStatus.connected);
        } else {
          _isConnected = false;
          _updateStatus(BackendStatus.incompatible);
        }
      } else {
        _isConnected = false;
        _updateStatus(BackendStatus.disconnected);
        _tryRecoverConnection();
      }
    } catch (e) {
      _isConnected = false;
      _updateStatus(BackendStatus.disconnected);
      _tryRecoverConnection();
    }
  }

  /// Tries to recover connection by checking server_info.json for a new port
  Future<void> _tryRecoverConnection() async {
    if (!Platform.isWindows) return;
    try {
      File? serverInfoFile;
      
      // In Debug mode, prioritize development paths because the build process might copy 'server' folder
      // to the build output, causing the app to find the stale bundled backend info instead of the live dev backend.
      if (kDebugMode) {
         final devCandidates = [
           '../backend/server_info.json',
           '../../backend/server_info.json',
           '../../../backend/server_info.json',
           'server_info.json',
         ];
         for (final p in devCandidates) {
           final f = File(p);
           if (await f.exists()) {
             serverInfoFile = f;
             final now = DateTime.now().millisecondsSinceEpoch;
             final last = _lastLogMs['server_info_found'] ?? 0;
             if (now - last > 3000) {
               _lastLogMs['server_info_found'] = now;
               debugPrint('[BackendService] Debug mode: Found server_info.json at ${f.path}');
             }
             break;
           }
         }
      }

      // If not found (or not in debug mode), try bundled locations
      if (serverInfoFile == null) {
        // 1. 尝试通过 server.exe 定位 server_info.json (标准打包结构)
        String? exePath;
        final appDir = p.dirname(Platform.resolvedExecutable);
        final candidateExes = [
          p.join(appDir, 'server', 'server.exe'),
          p.join(Directory.current.path, 'server', 'server.exe'),
          p.join(Directory.current.path, 'flutter_application', 'server', 'server.exe'),
        ];

        for (final path in candidateExes) {
          if (await File(path).exists()) {
            exePath = path;
            break;
          }
        }

        if (exePath != null) {
           serverInfoFile = File(p.join(p.dirname(exePath), 'server_info.json'));
        }
      }

      // 2. 如果仍未找到，尝试其他常见位置 (最后的兜底)
      if (serverInfoFile == null || !await serverInfoFile.exists()) {
         final candidates = [
           'server_info.json',                 
           '../backend/server_info.json',      
           '../server_info.json',              
           'server/server_info.json',          
           '../../backend/server_info.json',   
         ];
         
         for (final c in candidates) {
           final f = File(c);
           if (await f.exists()) {
             serverInfoFile = f;
             break;
           }
         }
      }

      if (serverInfoFile != null && await serverInfoFile.exists()) {
        final content = await serverInfoFile.readAsString();
        final info = jsonDecode(content);
        final url = info['url'] as String;
        if (url != _backendUrl) {
           final now = DateTime.now().millisecondsSinceEpoch;
           final last = _lastLogMs['server_info_recovered'] ?? 0;
           if (now - last > 3000) {
             _lastLogMs['server_info_recovered'] = now;
             debugPrint('[BackendService] Recovered: Backend moved to $url (found in ${serverInfoFile.path})');
           }
           _updateUrlAndNotify(url);
        }
      }
    } catch (e) {
      debugPrint('[BackendService] Recovery check failed: $e');
    }
  }

  void _updateStatus(BackendStatus status) {
    if (_currentStatus == status) return;
    _currentStatus = status;
    _statusController.add(status);
  }

  /// Stop the backend process if we started it.
  void dispose() {
    _stopHealthCheck();
    _serverInfoPollTimer?.cancel();
    _serverInfoPollTimer = null;
    _backendProcess?.kill();
    _statusController.close();
    _urlController.close();
  }
}

enum BackendStatus {
  initializing,
  connected,
  incompatible,
  disconnected,
}
