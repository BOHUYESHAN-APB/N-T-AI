import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../settings/settings_scope.dart';

/// A frontend plugin widget that provides a button to connect to the Linux environment.
class LinuxConnectionButton extends StatefulWidget {
  final VoidCallback? onTap;

  const LinuxConnectionButton({super.key, this.onTap});

  @override
  State<LinuxConnectionButton> createState() => _LinuxConnectionButtonState();
}

class _LinuxConnectionButtonState extends State<LinuxConnectionButton> {
  Map<String, dynamic>? _status;
  Map<String, dynamic>? _config;
  bool _loading = false;
  bool _configLoading = false;
  String? _backendUrl;
  bool _backendEnabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = SettingsScope.of(context).settings;
    final newUrl = settings.pythonBackendUrl.replaceAll(RegExp(r'/$'), '');
    final newEnabled = settings.enablePythonBackend;
    if (newUrl != _backendUrl || newEnabled != _backendEnabled) {
      _backendUrl = newUrl;
      _backendEnabled = newEnabled;
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    if (!_backendEnabled || _backendUrl == null || _backendUrl!.isEmpty) {
      if (mounted) {
        setState(() {
          _status = null;
          _config = null;
        });
      }
      return;
    }
    setState(() => _loading = true);
    try {
      final resp = await http.get(Uri.parse('$_backendUrl/api/linux/status'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _status = data;
          });
        }
        await _refreshConfig();
      } else {
        if (mounted) {
          setState(() {
            _status = {
              "status": "error",
              "detail": resp.body,
            };
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = {
            "status": "error",
            "detail": e.toString(),
          };
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshConfig() async {
    if (!_backendEnabled || _backendUrl == null || _backendUrl!.isEmpty) {
      return;
    }
    setState(() => _configLoading = true);
    try {
      final resp = await http.get(Uri.parse('$_backendUrl/api/linux/config'));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _config = data["config"] as Map<String, dynamic>?;
          });
        }
      }
    } catch (_) {
      // Ignore config refresh errors to avoid blocking the main status
    } finally {
      if (mounted) {
        setState(() => _configLoading = false);
      }
    }
  }

  Future<void> _updateConfig(Map<String, dynamic> updates) async {
    if (!_backendEnabled || _backendUrl == null) return;
    try {
      final resp = await http.post(
        Uri.parse('$_backendUrl/api/linux/config'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"config": updates}),
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _config = data["config"] as Map<String, dynamic>?;
          });
        }
      }
    } catch (_) {}
    await _refreshStatus();
  }

  Future<void> _connect() async {
    if (!_backendEnabled || _backendUrl == null) return;
    setState(() => _loading = true);
    try {
      final resp = await http.post(Uri.parse('$_backendUrl/api/linux/connect'));
      final Map<String, dynamic> data =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _status = data["info"] is Map<String, dynamic> ? data["info"] : _status;
        });
      }
      _showStatusDialog(message: data["message"]?.toString());
    } catch (e) {
      _showStatusDialog(message: '连接失败: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor() {
    final status = (_status?["status"] ?? "").toString();
    if (status == "ready") return Colors.green;
    if (status == "stopped") return Colors.orange;
    if (status == "not_found") return Colors.redAccent;
    if (status == "error") return Colors.redAccent;
    return Colors.grey;
  }

  String _statusLabel() {
    final type = (_status?["type"] ?? "unknown").toString();
    final status = (_status?["status"] ?? "unknown").toString();
    if (_status == null) return "未连接";
    return "$type / $status";
  }

  Future<void> _openVnc() async {
    final url = _status?["vnc_url"]?.toString();
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showStatusDialog(message: "无法打开 VNC 链接");
    }
  }

  void _showStatusDialog({String? message}) {
    showDialog(
      context: context,
      builder: (context) {
        final status = _status;
        final config = _config ?? {};
        final docker = (config["docker"] as Map?)?.cast<String, dynamic>() ?? {};
        var autoStart = config["auto_start"] == true;
        var autoStartContainer = docker["auto_start_container"] == true;
        var startOnDemand = docker["start_on_demand"] != false;
        var disableWsl = config["disable_wsl"] == true;
        final downloadUrl = docker["download_url"]?.toString() ?? "";
        final imageName = docker["image_name"]?.toString() ?? "";
        final containerName = docker["container_name"]?.toString() ?? "";
        return AlertDialog(
          title: const Text("Linux 子系统状态"),
          content: StatefulBuilder(
            builder: (context, setLocalState) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message != null) Text(message),
                    const SizedBox(height: 8),
                    Text("状态: ${status?["status"] ?? "unknown"}"),
                    Text("类型: ${status?["type"] ?? "unknown"}"),
                    if (status?["container"] != null)
                      Text("容器: ${status?["container"]}"),
                    if (status?["vnc_url"] != null)
                      Text("VNC: ${status?["vnc_url"]}"),
                    if (imageName.isNotEmpty) Text("镜像: $imageName"),
                    if (containerName.isNotEmpty) Text("容器名: $containerName"),
                    const SizedBox(height: 12),
                    const Text(
                      "启动策略",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("启动时自动启用插件"),
                      value: autoStart,
                      onChanged: (v) {
                        setLocalState(() => autoStart = v);
                        _updateConfig({"auto_start": v});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("启动时自动拉起容器"),
                      value: autoStartContainer,
                      onChanged: (v) {
                        setLocalState(() => autoStartContainer = v);
                        _updateConfig({
                          "docker": {"auto_start_container": v}
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("允许按需启动容器"),
                      value: startOnDemand,
                      onChanged: (v) {
                        setLocalState(() => startOnDemand = v);
                        _updateConfig({
                          "docker": {"start_on_demand": v}
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("禁用 WSL"),
                      value: disableWsl,
                      onChanged: (v) {
                        setLocalState(() => disableWsl = v);
                        _updateConfig({"disable_wsl": v});
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: downloadUrl),
                      decoration: const InputDecoration(
                        labelText: "系统下载链接（可选）",
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        _updateConfig({"docker": {"download_url": v.trim()}});
                      },
                    ),
                    if (_configLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _refreshStatus();
              },
              child: const Text("刷新"),
            ),
            if (status?["vnc_url"] != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _openVnc();
                },
                child: const Text("打开 VNC"),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("关闭"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: widget.onTap ??
            () async {
              if (!_backendEnabled) {
                _showStatusDialog(message: "后端未启用，无法连接 Linux 子系统");
                return;
              }
              if (_status == null) {
                await _refreshStatus();
              }
              await _connect();
            },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.terminal, size: 20, color: colorScheme.onSurface),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Linux 子系统",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    _statusLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _statusColor(),
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
