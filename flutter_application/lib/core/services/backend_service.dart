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
  String? _backendWorkDir;
  int? _managedPid;
  bool _isConnected = false;
  String _backendUrl = 'http://localhost:23456';
  String get backendUrl => _backendUrl;
  bool get isConnected => _isConnected;
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
    if (autoStartLocal && Platform.isWindows) {
      final uri = Uri.tryParse(configuredUrl);
      final port = uri?.port ?? 23456;
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

  Future<BackendActionResult> startLocalBackend({bool allowDebug = false}) async {
    _enabled = true;
    _updateStatus(BackendStatus.initializing);

    if (!Platform.isWindows && !allowDebug) {
      return const BackendActionResult(
        false,
        '当前平台不支持自动启动后端',
      );
    }

    if (_isConnected) {
      return const BackendActionResult(true, '后端已连接');
    }

    final started = await _startLocalBackend(allowDebug: allowDebug);
    _startHealthCheck();

    if (!started) {
      return const BackendActionResult(false, '未找到可启动的后端程序');
    }

    return const BackendActionResult(true, '已发送启动请求');
  }

  Future<BackendActionResult> stopLocalBackend() async {
    bool stopped = false;

    if (_backendProcess != null) {
      final pid = _backendProcess?.pid;
      if (pid != null) {
        stopped = await _terminatePid(pid);
      } else {
        stopped = _backendProcess!.kill();
      }
    }

    if (!stopped && _managedPid != null) {
      stopped = await _terminatePid(_managedPid!);
    }

    if (!stopped) {
      final pid = await _readServerInfoPid();
      if (pid != null) {
        stopped = await _terminatePid(pid);
      }
    }

    if (!stopped) {
      return const BackendActionResult(false, '未找到可停止的后端进程');
    }

    _backendProcess = null;
    _managedPid = null;
    _isConnected = false;
    _updateStatus(BackendStatus.disconnected);
    return const BackendActionResult(true, '已发送停止请求');
  }

  Future<bool> _terminatePid(int pid) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run(
          'taskkill',
          ['/PID', '$pid', '/T', '/F'],
        );
        return result.exitCode == 0;
      }
      return Process.killPid(pid);
    } catch (e) {
      debugPrint('[BackendService] Failed to kill PID $pid: $e');
      return false;
    }
  }

  Future<String?> _resolveBundledServerExe() async {
    final appDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(appDir, 'server.exe'),
      p.join(appDir, 'server', 'server.exe'),
    ];

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  Future<String?> _resolvePythonBackendEntry() async {
    final candidates = [
      p.join(Directory.current.path, 'backend', 'serve.py'),
      p.join(Directory.current.path, '..', 'backend', 'serve.py'),
      p.join(Directory.current.path, '..', '..', 'backend', 'serve.py'),
    ];

    for (final path in candidates) {
      if (await File(path).exists()) {
        return path;
      }
    }
    return null;
  }

  Future<File?> _locateServerInfoFile() async {
    final candidates = <String>[];
    if (_backendWorkDir != null && _backendWorkDir!.isNotEmpty) {
      candidates.add(p.join(_backendWorkDir!, 'server_info.json'));
    }
    candidates.addAll([
      'server_info.json',
      'server/server_info.json',
      'backend/server_info.json',
      'flutter_application/server/server_info.json',
      '../backend/server_info.json',
      '../server_info.json',
      '../../backend/server_info.json',
    ]);

    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file;
      }
    }

    final exePath = await _resolveBundledServerExe();
    if (exePath != null) {
      final file = File(p.join(p.dirname(exePath), 'server_info.json'));
      if (await file.exists()) {
        return file;
      }
    }

    return null;
  }

  Future<int?> _readServerInfoPid() async {
    try {
      final file = await _locateServerInfoFile();
      if (file == null) return null;
      final content = await file.readAsString();
      final info = jsonDecode(content);
      if (info is Map) {
        final rawPid = info['pid'];
        if (rawPid is int) return rawPid;
        if (rawPid is num) return rawPid.toInt();
        if (rawPid is String) return int.tryParse(rawPid);
      }
      return null;
    } catch (e) {
      debugPrint('[BackendService] Failed to read server_info.json PID: $e');
      return null;
    }
  }

  /// Attempts to start the bundled backend on Windows.
  Future<bool> _startLocalBackend({bool allowDebug = false}) async {
    if (kDebugMode && !allowDebug) {
      debugPrint('[BackendService] Debug mode: skipping bundled backend autostart.');
      return false;
    }

    // Dynamic Port Logic:
    // We do NOT strictly check port 23456 anymore, because the backend is now smart enough to auto-select a port (23456-23466).
    // Instead, we will:
    // 1. Try to read 'server_info.json' first to see if a valid backend is already alive.
    // 2. If alive, use that URL.
    // 3. If not, start the process.
    // 4. Watch for 'server_info.json' update or stdout to get the actual port.

    try {
      final usePython = kDebugMode || allowDebug;
      final exePath = usePython ? null : await _resolveBundledServerExe();
      final pythonEntry = usePython ? await _resolvePythonBackendEntry() : null;

      if (usePython && pythonEntry == null) {
        debugPrint('[BackendService] Debug mode: backend/serve.py not found. Assuming remote/manual backend.');
        return false;
      }

      if (!usePython && exePath == null) {
        debugPrint('[BackendService] Bundled server.exe not found. Assuming remote/manual backend.');
        return false;
      }

      final backendWorkDir =
          exePath != null ? p.dirname(exePath) : p.dirname(pythonEntry!);
      _backendWorkDir = backendWorkDir;
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
             _isConnected = true;
             return true;
           } else {
             debugPrint('[BackendService] Stale or incompatible server_info.json found. Restarting...');
           }
        } catch (e) {
          debugPrint('[BackendService] Error reading server_info.json: $e');
        }
      }

      if (exePath != null) {
        debugPrint('[BackendService] Starting local backend (bundled): $exePath');
      } else {
        debugPrint('[BackendService] Starting local backend (python): python $pythonEntry');
      }
      
      // 2. Start the process
      if (exePath != null) {
        _backendProcess = await Process.start(
          exePath,
          [],
          mode: ProcessStartMode.normal, // Use normal mode to capture stdout/stderr
          workingDirectory: backendWorkDir,
        );
      } else {
        _backendProcess = await Process.start(
          'python',
          [pythonEntry!],
          mode: ProcessStartMode.normal,
          workingDirectory: backendWorkDir,
          runInShell: true,
        );
      }

      _managedPid = _backendProcess?.pid;
      
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

      return true;
    } catch (e) {
      debugPrint('[BackendService] Failed to start local backend: $e');
      return false;
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
        const allowDynamicPort = !kDebugMode;
        final portOk = (() {
          try {
            final u = Uri.parse(url);
            return allowDynamicPort || u.port == 23456;
          } catch (_) {
            return false;
          }
        })();
        if (portOk && url != _backendUrl) {
           if (!allowDynamicPort || await _isCompatibleBackend(url)) {
             final now = DateTime.now().millisecondsSinceEpoch;
             final last = _lastLogMs['server_info_recovered'] ?? 0;
             if (now - last > 3000) {
               _lastLogMs['server_info_recovered'] = now;
               debugPrint('[BackendService] Recovered: Backend moved to $url (found in ${serverInfoFile.path})');
             }
             _updateUrlAndNotify(url);
           } else {
             final now = DateTime.now().millisecondsSinceEpoch;
             final last = _lastLogMs['server_info_ignored'] ?? 0;
             if (now - last > 3000) {
               _lastLogMs['server_info_ignored'] = now;
               debugPrint('[BackendService] Ignored server_info URL $url (incompatible backend). Keeping $_backendUrl');
             }
           }
        } else if (!portOk) {
           final now = DateTime.now().millisecondsSinceEpoch;
           final last = _lastLogMs['server_info_ignored'] ?? 0;
           if (now - last > 3000) {
             _lastLogMs['server_info_ignored'] = now;
             debugPrint('[BackendService] Ignored server_info URL $url (non-fixed port). Keeping $_backendUrl');
           }
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

class BackendActionResult {
  final bool success;
  final String message;

  const BackendActionResult(this.success, this.message);
}
