import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_application/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import '../../../services/logger_service.dart';
import '../../../settings/settings_scope.dart';
import '../../../settings/settings.dart';
import '../../first_run_dialog.dart';
import '../../../core/services/brain_service.dart';
import '../../../core/services/backend_service.dart';
import '../character_manager_screen.dart';

class GeneralTab extends StatefulWidget {
  const GeneralTab({super.key});

  @override
  State<GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<GeneralTab> {
  bool _didInit = false;
  bool _loadingAudioDevices = false;
  String? _audioDevicesError;
  List<Map<String, dynamic>> _inputDevices = const [];
  List<Map<String, dynamic>> _outputDevices = const [];
  int? _defaultInputDeviceIndex;
  int? _defaultOutputDeviceIndex;
  Map<int, String> _hostApiNames = const {};
  bool _testingAudio = false;

  String _findDeviceNameByIndex(int? idx, List<Map<String, dynamic>> devices) {
    if (idx == null) return '未指定';
    for (final d in devices) {
      final di = d['_index'];
      if (di is int && di == idx) {
        final name = (d['name'] ?? '').toString().trim();
        return name.isEmpty ? '设备#$idx' : name;
      }
    }
    return '设备#$idx';
  }

  Future<void> _showRecentErrorsDialog() async {
    final items = logger.getRecentErrors();
    String formatTs(dynamic ts) {
      try {
        final v = (ts is num) ? ts.toDouble() : double.tryParse(ts.toString()) ?? 0.0;
        final dt = DateTime.fromMillisecondsSinceEpoch((v * 1000).round());
        final mm = dt.month.toString().padLeft(2, '0');
        final dd = dt.day.toString().padLeft(2, '0');
        final hh = dt.hour.toString().padLeft(2, '0');
        final mi = dt.minute.toString().padLeft(2, '0');
        final ss = dt.second.toString().padLeft(2, '0');
        return '${dt.year}-$mm-$dd $hh:$mi:$ss';
      } catch (_) {
        return '';
      }
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('最近错误（本机）'),
        content: SizedBox(
          width: 560,
          child: items.isEmpty
              ? const Text('暂无错误记录')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final it in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SelectableText(
                            '${formatTs(it['timestamp'])}  ${it['level'] ?? ''}\n'
                            '${it['message'] ?? ''}'
                            '${(it['exception'] ?? '').toString().trim().isEmpty ? '' : '\n${it['exception']}'}',
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await logger.clearRecentErrors();
              if (!context.mounted) return;
              Navigator.pop(context);
              if (!mounted) return;
              setState(() {});
            },
            child: const Text('清空'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  AiProviderConfig? _resolveAudioProvider(AiProviderCategory category) {
    final providers = SettingsScope.of(context).providers;

    final explicit = providers.firstWhere(
      (p) =>
          p.category == category &&
          p.enabled &&
          p.baseUrl.isNotEmpty &&
          p.apiKey.isNotEmpty,
      orElse: () => const AiProviderConfig(
        id: '',
        name: '',
        kind: AiProvider.local,
      ),
    );
    if (explicit.id.isNotEmpty) return explicit;

    if (category == AiProviderCategory.stt) {
      final local = providers.firstWhere(
        (p) =>
            p.category == category &&
            p.enabled &&
            p.kind == AiProvider.local &&
            (p.meta['local_stt']?.toString() == 'windows_speech'),
        orElse: () => const AiProviderConfig(
          id: '',
          name: '',
          kind: AiProvider.local,
        ),
      );
      if (local.id.isNotEmpty) return local;
    }

    return null;
  }

  List<DropdownMenuItem<int?>> _buildInputDeviceItems(String defaultLabel) {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(
          defaultLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    ];
    final seen = <int>{};
    for (final d in _inputDevices) {
      final idx = (d['_index'] as int?) ?? -1;
      if (idx < 0) continue;
      if (seen.contains(idx)) continue;
      seen.add(idx);
      items.add(
        DropdownMenuItem<int?>(
          value: idx,
          child: Text(
            _formatInputDeviceLabel(d),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      );
    }
    return items;
  }

  List<DropdownMenuItem<int?>> _buildOutputDeviceItems(String defaultLabel) {
    final items = <DropdownMenuItem<int?>>[
      DropdownMenuItem<int?>(
        value: null,
        child: Text(
          defaultLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
        ),
      ),
    ];
    final seen = <int>{};
    for (final d in _outputDevices) {
      final idx = (d['_index'] as int?) ?? -1;
      if (idx < 0) continue;
      if (seen.contains(idx)) continue;
      seen.add(idx);
      items.add(
        DropdownMenuItem<int?>(
          value: idx,
          child: Text(
            _formatOutputDeviceLabel(d),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      );
    }
    return items;
  }

  List<DropdownMenuItem<String?>> _buildProviderItems(
    AiProviderCategory category,
    String defaultLabel,
  ) {
    final providers = SettingsScope.of(context).providers;
    final items = <DropdownMenuItem<String?>>[
      DropdownMenuItem<String?>(
        value: null,
        child: Text(defaultLabel),
      ),
    ];

    for (final p in providers) {
      if (p.category == category && p.enabled) {
        items.add(
          DropdownMenuItem<String?>(
            value: p.id,
            child: Text(p.name),
          ),
        );
      }
    }
    return items;
  }

  String _formatInputDeviceLabel(Map<String, dynamic> d) {
    final idx = (d['_index'] as int?) ?? -1;
    final nameRaw = (d['name'] ?? '').toString().trim();
    final name = nameRaw.isEmpty ? '(未命名设备)' : nameRaw;

    final hostApiIndex = (d['hostapi'] is num) ? (d['hostapi'] as num).toInt() : null;
    final hostApiName = (hostApiIndex != null) ? _hostApiNames[hostApiIndex] : null;

    final maxIn = (d['max_input_channels'] is num)
        ? (d['max_input_channels'] as num).toInt()
        : 0;
    final defaultSr = (d['default_samplerate'] is num)
        ? (d['default_samplerate'] as num).toInt()
        : null;

    final tags = <String>[];
    final lowerName = name.toLowerCase();
    final isVirtual = lowerName.contains('virtual') ||
        lowerName.contains('cable') ||
        lowerName.contains('vb-audio') ||
        lowerName.contains('voicemeeter') ||
        lowerName.contains('loopback') ||
        lowerName.contains('blackhole');
    if (isVirtual) {
      tags.add('虚拟');
    }
    if (hostApiName != null && hostApiName.trim().isNotEmpty) {
      tags.add(hostApiName.trim());
    }
    if (maxIn > 0) {
      tags.add('输入${maxIn}ch');
    }
    if (defaultSr != null && defaultSr > 0) {
      tags.add('${defaultSr}Hz');
    }

    final tagText = tags.isEmpty ? '' : '〔${tags.join(' / ')}〕';
    final defaultText =
        (_defaultInputDeviceIndex != null && idx == _defaultInputDeviceIndex)
            ? '（默认输入）'
            : '';
    return '[$idx] $name $tagText$defaultText'.trim();
  }

  String _formatOutputDeviceLabel(Map<String, dynamic> d) {
    final idx = (d['_index'] as int?) ?? -1;
    final nameRaw = (d['name'] ?? '').toString().trim();
    final name = nameRaw.isEmpty ? '(未命名设备)' : nameRaw;

    final hostApiIndex = (d['hostapi'] is num) ? (d['hostapi'] as num).toInt() : null;
    final hostApiName = (hostApiIndex != null) ? _hostApiNames[hostApiIndex] : null;

    final maxOut = (d['max_output_channels'] is num)
        ? (d['max_output_channels'] as num).toInt()
        : 0;
    final defaultSr = (d['default_samplerate'] is num)
        ? (d['default_samplerate'] as num).toInt()
        : null;

    final tags = <String>[];
    final lowerName = name.toLowerCase();
    final isVirtual = lowerName.contains('virtual') ||
        lowerName.contains('cable') ||
        lowerName.contains('vb-audio') ||
        lowerName.contains('voicemeeter') ||
        lowerName.contains('loopback') ||
        lowerName.contains('blackhole');
    if (isVirtual) {
      tags.add('虚拟');
    }
    if (hostApiName != null && hostApiName.trim().isNotEmpty) {
      tags.add(hostApiName.trim());
    }
    if (maxOut > 0) {
      tags.add('输出${maxOut}ch');
    }
    if (defaultSr != null && defaultSr > 0) {
      tags.add('${defaultSr}Hz');
    }

    final tagText = tags.isEmpty ? '' : '〔${tags.join(' / ')}〕';
    final defaultText =
        (_defaultOutputDeviceIndex != null && idx == _defaultOutputDeviceIndex)
            ? '（默认输出）'
            : '';
    return '[$idx] $name $tagText$defaultText'.trim();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInit) return;
    _didInit = true;
    _refreshAudioDevices();
  }

  Future<void> _refreshAudioDevices() async {
    final controller = SettingsScope.of(context);
    final s = controller.settings;

    if (!s.enablePythonBackend) {
      if (mounted) {
        setState(() {
          _inputDevices = const [];
          _outputDevices = const [];
          _defaultInputDeviceIndex = null;
          _audioDevicesError = null;
          _loadingAudioDevices = false;
        });
      }
      return;
    }

    final backendBase =
        s.pythonBackendUrl.endsWith('/') ? s.pythonBackendUrl.substring(0, s.pythonBackendUrl.length - 1) : s.pythonBackendUrl;

    if (mounted) {
      setState(() {
        _loadingAudioDevices = true;
        _audioDevicesError = null;
      });
    }

    try {
      final resp = await http
          .get(Uri.parse('$backendBase/api/audio/devices'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final rawDevices =
          (data is Map ? (data['devices'] as List?) : null) ?? const [];
      final rawHostApis =
          (data is Map ? (data['hostapis'] as List?) : null) ?? const [];
      final defaultIn = (data is Map && data['default'] is Map)
          ? ((data['default'] as Map)['input'] as num?)?.toInt()
          : null;
      final defaultOut = (data is Map && data['default'] is Map)
          ? ((data['default'] as Map)['output'] as num?)?.toInt()
          : null;

      final hostApiNames = <int, String>{};
      for (var i = 0; i < rawHostApis.length; i++) {
        final h = rawHostApis[i];
        if (h is! Map) continue;
        final name = (h['name'] ?? '').toString();
        if (name.isNotEmpty) {
          hostApiNames[i] = name;
        }
      }

      final inputDevices = <Map<String, dynamic>>[];
      final outputDevices = <Map<String, dynamic>>[];
      for (var i = 0; i < rawDevices.length; i++) {
        final d = rawDevices[i];
        if (d is! Map) continue;
        final map = Map<String, dynamic>.from(d);
        final maxIn = (map['max_input_channels'] is num)
            ? (map['max_input_channels'] as num).toInt()
            : 0;
        final maxOut = (map['max_output_channels'] is num)
            ? (map['max_output_channels'] as num).toInt()
            : 0;
        if (maxIn > 0) {
          map['_index'] = i;
          inputDevices.add(map);
        }
        if (maxOut > 0) {
          map['_index'] = i;
          outputDevices.add(map);
        }
      }

      if (!mounted) return;
      setState(() {
        _inputDevices = inputDevices;
        _outputDevices = outputDevices;
        _defaultInputDeviceIndex = defaultIn;
        _defaultOutputDeviceIndex = defaultOut;
        _hostApiNames = hostApiNames;
        _loadingAudioDevices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inputDevices = const [];
        _outputDevices = const [];
        _defaultInputDeviceIndex = null;
        _defaultOutputDeviceIndex = null;
        _hostApiNames = const {};
        _audioDevicesError = e.toString();
        _loadingAudioDevices = false;
      });
    }
  }

  String _formatHttpFailure(http.Response resp, {String prefix = ''}) {
    String body = '';
    try {
      body = utf8.decode(resp.bodyBytes).trim();
    } catch (_) {
      body = (resp.body).toString().trim();
    }
    if (body.length > 1200) body = body.substring(0, 1200);
    final p = prefix.isEmpty ? '' : '$prefix: ';
    return body.isEmpty ? '${p}HTTP ${resp.statusCode}' : '${p}HTTP ${resp.statusCode} - $body';
  }

  Future<void> _testLoopbackLevel() async {
    final controller = SettingsScope.of(context);
    final s = controller.settings;
    if (!s.enablePythonBackend) return;
    if (_testingAudio) return;
    setState(() => _testingAudio = true);
    try {
      final backendBase = s.pythonBackendUrl.endsWith('/')
          ? s.pythonBackendUrl.substring(0, s.pythonBackendUrl.length - 1)
          : s.pythonBackendUrl;

      final resp = await http
          .post(
            Uri.parse('$backendBase/api/audio/loopback/measure'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'duration_seconds': 1.0,
              if (s.sttLoopbackDeviceIndex != null)
                'device_index': s.sttLoopbackDeviceIndex,
              'samplerate': 48000,
              'channels': 2,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (!mounted) return;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = _formatHttpFailure(resp, prefix: '回环检测失败');
        logger.error('$msg（backend=$backendBase, device=${s.sttLoopbackDeviceIndex ?? 'default'}）');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final stats = (data is Map ? data['stats'] : null) as Map?;
      final used = (stats?['used'] as Map?) ?? const {};
      final level = (stats?['level'] as Map?) ?? const {};
      final dev = (stats?['device'] as Map?) ?? const {};

      final rms = (level['rms'] ?? 0).toString();
      final peak = (level['peak'] ?? 0).toString();
      final silent = (level['is_silent'] == true);
      final usedSr = (used['samplerate'] ?? '').toString();
      final devName = (dev['name'] ?? '未知设备').toString();
      logger.info(
        '回环电平结果: silent=$silent rms=$rms peak=$peak sr=$usedSr device="$devName" idx=${s.sttLoopbackDeviceIndex ?? 'default'}',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            silent
                ? '回环电平：静音（RMS=$rms, Peak=$peak, SR=$usedSr）\n$devName'
                : '回环电平：RMS=$rms, Peak=$peak, SR=$usedSr\n$devName',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      logger.error(
        '回环检测失败（backend=${s.pythonBackendUrl}, device=${s.sttLoopbackDeviceIndex ?? 'default'}）',
        e,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回环检测失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _testingAudio = false);
    }
  }

  Future<void> _testLoopbackTranscribe() async {
    final controller = SettingsScope.of(context);
    final s = controller.settings;
    if (!s.enablePythonBackend) return;
    if (_testingAudio) return;
    setState(() => _testingAudio = true);
    String? path;
    var keepFile = false;
    try {
      final sttProvider = _resolveAudioProvider(AiProviderCategory.stt);
      if (sttProvider == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未配置 STT 服务')),
        );
        return;
      }

      path = await BrainService().captureSystemLoopbackToFile(
        durationSeconds: s.sttLoopbackDurationSeconds.toDouble(),
        deviceIndex: s.sttLoopbackDeviceIndex,
        samplerate: 16000,
        channels: 1,
      );
      logger.info(
        '回环转写开始: provider=${sttProvider.name} kind=${sttProvider.kind} device=${s.sttLoopbackDeviceIndex ?? 'default'} file=$path',
      );
      final text = (await BrainService().transcribe(path, sttProvider)).trim();

      if (!mounted) return;
      if (text.isEmpty) {
        keepFile = true;
        logger.error(
          '回环转写结果为空（已保留音频文件）：provider=${sttProvider.name} device=${s.sttLoopbackDeviceIndex ?? 'default'} file=$path',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('转写结果为空（已保留音频文件用于排查）：$path'),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      logger.info('回环转写结果: len=${text.length} text="${text.length > 120 ? text.substring(0, 120) : text}"');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('转写结果：$text'),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      logger.error(
        '回环转写失败（backend=${s.pythonBackendUrl}, device=${s.sttLoopbackDeviceIndex ?? 'default'}）',
        e,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('回环转写失败: $e')),
      );
    } finally {
      try {
        if (!keepFile && path != null) {
          final f = File(path);
          if (await f.exists()) {
            await f.delete();
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _testingAudio = false);
    }
  }

  Future<void> _testTtsInjectionTone() async {
    final controller = SettingsScope.of(context);
    final s = controller.settings;
    if (!s.enablePythonBackend) return;
    if (_testingAudio) return;
    setState(() => _testingAudio = true);
    try {
      final backendBase = s.pythonBackendUrl.endsWith('/')
          ? s.pythonBackendUrl.substring(0, s.pythonBackendUrl.length - 1)
          : s.pythonBackendUrl;

      final resp = await http
          .post(
            Uri.parse('$backendBase/api/audio/debug/play-tone'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_role': 'input',
              if (s.ttsBackendDeviceIndex != null)
                'device_index': s.ttsBackendDeviceIndex,
              'frequency_hz': 880.0,
              'duration_seconds': 0.6,
              'samplerate': 48000,
              'channels': 2,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (!mounted) return;
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        final msg = _formatHttpFailure(resp, prefix: '测试音播放失败');
        logger.error('$msg（backend=$backendBase, device=${s.ttsBackendDeviceIndex ?? 'default'}）');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return;
      }

      final data = jsonDecode(utf8.decode(resp.bodyBytes));
      final used = (data is Map ? data['used'] : null) as Map?;
      final outIdx = (used?['output_device_index'] as num?)?.toInt();
      final outName = _findDeviceNameByIndex(outIdx, _outputDevices);
      final play = (data is Map ? data['play'] : null) as Map?;
      final usedSr = (play?['samplerate'] ?? '').toString();
      final usedCh = (play?['channels'] ?? '').toString();
      logger.info(
        '测试音播放成功: backend=$backendBase inputDevice=${s.ttsBackendDeviceIndex ?? 'default'} -> outputDevice=$outIdx "$outName" sr=$usedSr ch=$usedCh',
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已播放测试音（注入路径）\n输出设备=$outIdx $outName（SR=$usedSr, CH=$usedCh）',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      logger.error(
        '测试音播放失败（backend=${s.pythonBackendUrl}, device=${s.ttsBackendDeviceIndex ?? 'default'}）',
        e,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测试音播放失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _testingAudio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final s = controller.settings;
    final l10n = AppLocalizations.of(context)!;

    final safeTtsBackendDeviceIndex = (s.ttsBackendDeviceIndex != null &&
            _inputDevices.any(
              (d) => (d['_index'] as int?) == s.ttsBackendDeviceIndex,
            ))
        ? s.ttsBackendDeviceIndex
        : null;
    final safeSttLoopbackDeviceIndex = (s.sttLoopbackDeviceIndex != null &&
            _outputDevices.any(
              (d) => (d['_index'] as int?) == s.sttLoopbackDeviceIndex,
            ))
        ? s.sttLoopbackDeviceIndex
        : null;

    final basicSectionChildren = <Widget>[
      SwitchListTile(
        secondary: const Icon(Icons.link),
        title: Text(l10n.generalAutoConnectBackend),
        subtitle: Text(l10n.generalAutoConnectBackendSubtitle),
        value: s.autoConnectBackend,
        onChanged: (v) => controller.setAutoConnectBackend(v),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.play_circle_outline),
        title: Text(l10n.generalAutoStartBackend),
        subtitle: Text(l10n.generalAutoStartBackendSubtitle),
        value: s.autoStartBackend,
        onChanged: (v) => controller.setAutoStartBackend(v),
      ),
      ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: Text(l10n.generalBackendStatus),
        subtitle: Text(s.pythonBackendUrl),
        trailing: StreamBuilder<BackendStatus>(
          stream: BackendService().statusStream,
          initialData: BackendService().currentStatus,
          builder: (context, snapshot) {
            final status = snapshot.data ?? BackendStatus.disconnected;
            String text;
            if (!s.enablePythonBackend) {
              text = l10n.backendStatusBackendDisabled;
            } else if (!s.autoConnectBackend) {
              text = l10n.backendStatusAutoConnectOff;
            } else {
              text = switch (status) {
                BackendStatus.connected => l10n.backendStatusConnected,
                BackendStatus.initializing => l10n.backendStatusInitializing,
                BackendStatus.incompatible => l10n.backendStatusIncompatible,
                BackendStatus.disconnected => l10n.backendStatusDisconnected,
              };
            }
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text),
                const SizedBox(width: 8),
                const Icon(Icons.edit_outlined, size: 16),
              ],
            );
          },
        ),
        onTap: () async {
          final ctl = TextEditingController(text: s.pythonBackendUrl);
          final newUrl = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.generalBackendStatus),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctl,
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'http://localhost:23456',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Default: http://localhost:23456\nRemote: http://IP:PORT',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, ctl.text),
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          );
          if (newUrl != null && newUrl.isNotEmpty) {
            controller.setPythonBackendUrl(newUrl);
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('查看最近错误（本机）'),
        subtitle: const Text('用于排查 TTS 注入/回环/网络等失败原因'),
        onTap: _showRecentErrorsDialog,
      ),
      ListTile(
        leading: const Icon(Icons.face),
        title: Text(l10n.generalUserNickname),
        subtitle: Text(
          s.userNickname.isEmpty ? l10n.generalNicknameNotSet : s.userNickname,
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () async {
          final ctl = TextEditingController(text: s.userNickname);
          final newName = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n.generalSetNickname),
              content: TextField(
                controller: ctl,
                decoration: InputDecoration(
                  hintText: l10n.generalNicknameHint,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, ctl.text),
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          );
          if (newName != null) {
            controller.setUserNickname(newName);
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(l10n.generalCharacterModel),
        subtitle: Text(l10n.generalManageModels),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CharacterManagerScreen()),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: const Text('重新运行向导 (Onboarding Wizard)'),
        subtitle: const Text('重置助手人格与系统提示词'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => FirstRunDialog(
              settingsController: controller,
              brain: BrainService(),
            ),
          );
        },
      ),
    ];

    final uiSectionChildren = <Widget>[
      SwitchListTile(
        secondary: const Icon(Icons.animation),
        title: Text(l10n.generalEnableLive2D),
        subtitle: Text(l10n.generalShowLive2D),
        value: s.enableLive2D,
        onChanged: (v) => controller.setEnableLive2D(v),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.visibility),
        title: Text(l10n.generalShowLive2DHome),
        subtitle: Text(l10n.generalShowLive2DHomeSubtitle),
        value: s.showLive2D,
        onChanged: s.enableLive2D ? (v) => controller.setShowLive2D(v) : null,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.open_in_new),
        title: Text(l10n.generalFloatingWindow),
        subtitle: Text(l10n.generalFloatingWindowSubtitle),
        value: s.enableFloatingWindow,
        onChanged:
            s.enableLive2D ? (v) => controller.setEnableFloatingWindow(v) : null,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.link),
        title: const Text('启用 VTS 连接'),
        subtitle: const Text('同步表情到 VTube Studio（默认关闭）'),
        value: s.enableVts,
        onChanged:
            s.enablePythonBackend ? (v) => controller.setEnableVts(v) : null,
      ),
    ];

    final ttsSectionChildren = <Widget>[
      SwitchListTile(
        secondary: const Icon(Icons.record_voice_over),
        title: Text(l10n.generalEnableTts),
        subtitle: Text(l10n.generalEnableTtsSubtitle),
        value: s.enableTts,
        onChanged: (v) => controller.setEnableTts(v),
      ),
      if (s.enableTts)
        ListTile(
          leading: const Icon(Icons.speed),
          title: const Text('TTS 响应模式'),
          subtitle: const Text('“极速流式”通过流式并发提升响应速度，但受限于服务商并发额度'),
          trailing: DropdownButton<String>(
            value: s.ttsMode,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setTtsMode(v);
            },
            items: const [
              DropdownMenuItem(value: 'stream', child: Text('极速流式')),
              DropdownMenuItem(value: 'sentence', child: Text('标准稳定')),
            ],
          ),
        ),
      if (s.enableTts)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '提示：使用硅基流动 (SiliconFlow) 时，免费额度通常限制并发数为 1-2。若响应失败，请尝试切换至“标准稳定”模式。',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      SwitchListTile(
        secondary: const Icon(Icons.volume_up),
        title: const Text('TTS 注入到虚拟麦克风（后端播放）'),
        subtitle: const Text(
          '选择“虚拟麦克风（输入设备）”，后端自动匹配对应的播放端进行注入',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        value: s.ttsViaBackendDevice,
        onChanged: (s.enableTts && s.enablePythonBackend)
            ? (v) async {
                await controller.setTtsViaBackendDevice(v);
                if (v) {
                  await _refreshAudioDevices();
                }
              }
            : null,
      ),
      if (s.ttsViaBackendDevice)
        ListTile(
          leading: const Icon(Icons.mic),
          title: const Text('TTS 虚拟麦克风（输入设备）'),
          subtitle: _loadingAudioDevices
              ? const Text('正在获取设备列表…')
              : (_audioDevicesError != null
                  ? Text('获取失败：$_audioDevicesError')
                  : const Text('建议选择虚拟线的“CABLE Output（录音设备）”')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: (s.enablePythonBackend) ? _refreshAudioDevices : null,
              ),
              DropdownButton<int?>(
                value: safeTtsBackendDeviceIndex,
                underline: const SizedBox(),
                onChanged: (s.enablePythonBackend && !_loadingAudioDevices)
                    ? (v) => controller.setTtsBackendDeviceIndex(v)
                    : null,
                items: _buildInputDeviceItems('默认（系统默认输入）'),
              ),
            ],
          ),
        ),
      if (s.ttsViaBackendDevice)
        ListTile(
          leading: const Icon(Icons.music_note),
          title: const Text('测试 TTS 注入（播放测试音）'),
          subtitle: const Text('用于确认虚拟麦克风注入链路是否通畅'),
          enabled: s.enablePythonBackend && !_testingAudio,
          onTap: (s.enablePythonBackend && !_testingAudio)
              ? _testTtsInjectionTone
              : null,
        ),
      if (s.ttsViaBackendDevice || s.sttViaBackendLoopback)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Text(
            'VB-Cable 推荐：\n'
            '1) 本软件 TTS 虚拟麦克风：选择 CABLE Output（录音设备 / 输入设备）\n'
            '2) 语音软件麦克风：选择 CABLE Output（录音设备 / 输入设备）\n'
            '3) STT 回环监听：选择与语音软件“播放设备”一致的输出设备（可以是扬声器/耳机，也可以是 CABLE Input）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ];

    final sttSectionChildren = <Widget>[
      SwitchListTile(
        secondary: const Icon(Icons.hearing),
        title: Text(l10n.generalEnableStt),
        subtitle: Text(l10n.generalEnableSttSubtitle),
        value: s.enableStt,
        onChanged: (v) => controller.setEnableStt(v),
      ),
      if (s.enableStt)
        SwitchListTile(
          secondary: const Icon(Icons.mic_none),
          title: const Text('自动麦克风监听'),
          subtitle: const Text('在对话结束后自动开启麦克风录音 (运行在前端设备)'),
          value: s.autoMicListening,
          onChanged: (v) => controller.setAutoMicListening(v),
        ),
      const Divider(height: 1, indent: 72),
      SwitchListTile(
        secondary: const Icon(Icons.headphones),
        title: const Text('从系统声音识别（回环采集）'),
        subtitle: const Text('把 Discord/KOOK 的语音频道声音转成文字发给 AI'),
        value: s.sttViaBackendLoopback,
        onChanged: (s.enableStt && s.enablePythonBackend)
            ? (v) async {
                await controller.setSttViaBackendLoopback(v);
                if (v) {
                  await _refreshAudioDevices();
                }
              }
            : null,
      ),
      if (s.sttViaBackendLoopback) ...[
        SwitchListTile(
          secondary: const Icon(Icons.record_voice_over_outlined),
          title: const Text('自动语音频道监听'),
          subtitle: const Text('自动识别语音软件声音 (需回环采集已开启)'),
          value: s.autoVoiceChannelListening,
          onChanged: s.enablePythonBackend
              ? (v) => controller.setAutoVoiceChannelListening(v)
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.headphones_outlined),
          title: const Text('回环监听设备（输出设备）'),
          subtitle: _loadingAudioDevices
              ? const Text('正在获取设备列表…')
              : (_audioDevicesError != null
                  ? Text('获取失败：$_audioDevicesError')
                  : const Text('应与语音软件的“播放设备”一致')),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: (s.enablePythonBackend) ? _refreshAudioDevices : null,
              ),
              DropdownButton<int?>(
                value: safeSttLoopbackDeviceIndex,
                underline: const SizedBox(),
                onChanged: (s.enablePythonBackend && !_loadingAudioDevices)
                    ? (v) => controller.setSttLoopbackDeviceIndex(v)
                    : null,
                items: _buildOutputDeviceItems('默认（系统默认输出）'),
              ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.equalizer),
          title: const Text('测试回环监听（检测电平）'),
          subtitle: const Text('用于确认能否采集到语音软件的输出声音'),
          enabled: s.enablePythonBackend && !_testingAudio,
          onTap: (s.enablePythonBackend && !_testingAudio)
              ? _testLoopbackLevel
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.text_snippet),
          title: const Text('测试回环监听（转写）'),
          subtitle: const Text('用于确认 STT 能否把回环音频转成文字'),
          enabled: s.enablePythonBackend && !_testingAudio,
          onTap: (s.enablePythonBackend && !_testingAudio)
              ? _testLoopbackTranscribe
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.timer),
          title: const Text('回环采集时长'),
          subtitle: const Text('越长越完整，但识别更慢'),
          trailing: DropdownButton<int>(
            value: s.sttLoopbackDurationSeconds,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) {
                controller.setSttLoopbackDurationSeconds(v);
              }
            },
            items: const [
              DropdownMenuItem(value: 3, child: Text('3 秒')),
              DropdownMenuItem(value: 5, child: Text('5 秒')),
              DropdownMenuItem(value: 8, child: Text('8 秒')),
              DropdownMenuItem(value: 12, child: Text('12 秒')),
            ],
          ),
        ),
      ],
    ];

    final appearanceSectionChildren = <Widget>[
      ListTile(
        title: Text(l10n.generalLanguage),
        trailing: DropdownButton<LocaleOption>(
          value: s.locale,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setLocale(v);
          },
          items: [
            DropdownMenuItem(
              value: LocaleOption.system,
              child: Text(l10n.generalThemeSystem),
            ),
            const DropdownMenuItem(
              value: LocaleOption.zh,
              child: Text('简体中文'),
            ),
            const DropdownMenuItem(
              value: LocaleOption.en,
              child: Text('English'),
            ),
          ],
        ),
      ),
      ListTile(
        title: Text(l10n.generalTheme),
        trailing: DropdownButton<ThemeModeOption>(
          value: s.themeMode,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setThemeMode(v);
          },
          items: [
            DropdownMenuItem(
              value: ThemeModeOption.system,
              child: Text(l10n.generalThemeSystem),
            ),
            DropdownMenuItem(
              value: ThemeModeOption.light,
              child: Text(l10n.generalThemeLight),
            ),
            DropdownMenuItem(
              value: ThemeModeOption.dark,
              child: Text(l10n.generalThemeDark),
            ),
          ],
        ),
      ),
      ListTile(
        title: Text(l10n.generalPalette),
        trailing: DropdownButton<PaletteOption>(
          value: s.palette,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setPalette(v);
          },
          items: [
            DropdownMenuItem(
              value: PaletteOption.neutral,
              child: Text(l10n.generalPaletteNeutral),
            ),
            DropdownMenuItem(
              value: PaletteOption.green,
              child: Text(l10n.generalPaletteGreen),
            ),
            DropdownMenuItem(
              value: PaletteOption.blue,
              child: Text(l10n.generalPaletteBlue),
            ),
            DropdownMenuItem(
              value: PaletteOption.orange,
              child: Text(l10n.generalPaletteOrange),
            ),
          ],
        ),
      ),
      ListTile(
        title: Text(l10n.generalUiMode),
        trailing: DropdownButton<UIModeOption>(
          value: s.uiMode,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setUiMode(v);
          },
          items: [
            DropdownMenuItem(
              value: UIModeOption.auto,
              child: Text(l10n.generalUiModeAuto),
            ),
            DropdownMenuItem(
              value: UIModeOption.bubble,
              child: Text(l10n.generalUiModeBubble),
            ),
            DropdownMenuItem(
              value: UIModeOption.simple,
              child: Text(l10n.generalUiModeSimple),
            ),
          ],
        ),
      ),
      ListTile(
        title: const Text('主模式 (Primary Mode)'),
        subtitle: Text(
          s.primaryMode == PrimaryModeOption.assistant
              ? '助理优先 - 任务/对话为主'
              : '直播模式 - 节目效果优先',
        ),
        trailing: DropdownButton<PrimaryModeOption>(
          value: s.primaryMode,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setPrimaryMode(v);
          },
          items: const [
            DropdownMenuItem(
              value: PrimaryModeOption.assistant,
              child: Text('助理'),
            ),
            DropdownMenuItem(
              value: PrimaryModeOption.live,
              child: Text('直播'),
            ),
          ],
        ),
      ),
      if (s.primaryMode == PrimaryModeOption.live) ...[
        ListTile(
          title: const Text('直播子模式'),
          subtitle: Text(
            s.liveMode == LiveModeOption.watch
                ? '你玩、AI看（只解说）'
                : s.liveMode == LiveModeOption.coPlay
                    ? '你玩+AI玩（互动加强）'
                    : 'AI玩、你看（自主任务）',
          ),
          trailing: DropdownButton<LiveModeOption>(
            value: s.liveMode,
            underline: const SizedBox(),
            onChanged: (v) {
              if (v != null) controller.setLiveMode(v);
            },
            items: const [
              DropdownMenuItem(
                value: LiveModeOption.watch,
                child: Text('你玩、AI看'),
              ),
              DropdownMenuItem(
                value: LiveModeOption.coPlay,
                child: Text('你玩+AI玩'),
              ),
              DropdownMenuItem(
                value: LiveModeOption.autoPlay,
                child: Text('AI玩、你看'),
              ),
            ],
          ),
        ),
        SwitchListTile(
          title: const Text('直播模式写入记忆'),
          subtitle: const Text('允许直播内容进入记忆系统（可关闭）'),
          value: s.liveMemoryEnabled,
          onChanged: (v) => controller.setLiveMemoryEnabled(v),
        ),
      ],
      ListTile(
        title: const Text('聊天模式 (Chat Mode)'),
        subtitle: Text(
          s.chatMode == ChatModeOption.persona
              ? '拟人 (Persona) - 分段气泡，自然对话'
              : '标准 (Standard) - 严格Markdown，生产力',
        ),
        trailing: DropdownButton<ChatModeOption>(
          value: s.chatMode,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setChatMode(v);
          },
          items: const [
            DropdownMenuItem(
              value: ChatModeOption.persona,
              child: Text('拟人 (Persona)'),
            ),
            DropdownMenuItem(
              value: ChatModeOption.standard,
              child: Text('标准 (Standard)'),
            ),
          ],
        ),
      ),
      ListTile(
        title: const Text('人格深度 (Persona Level)'),
        subtitle: Text(
          s.personaLevel == PersonaLevelOption.basic
              ? '基础 (Basic) - 仅设定身份'
              : s.personaLevel == PersonaLevelOption.advanced
                  ? '进阶 (Advanced) - 包含性格与记忆'
                  : '完整 (Full) - 包含完整数字生命设定与交互',
        ),
        trailing: DropdownButton<PersonaLevelOption>(
          value: s.personaLevel,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setPersonaLevel(v);
          },
          items: const [
            DropdownMenuItem(
              value: PersonaLevelOption.basic,
              child: Text('基础 (Basic)'),
            ),
            DropdownMenuItem(
              value: PersonaLevelOption.advanced,
              child: Text('进阶 (Advanced)'),
            ),
            DropdownMenuItem(
              value: PersonaLevelOption.full,
              child: Text('完整 (Full)'),
            ),
          ],
        ),
      ),
      ListTile(
        title: Text(l10n.generalChatBg),
        trailing: DropdownButton<ChatBgOption>(
          value: s.chatBg,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setChatBg(v);
          },
          items: [
            DropdownMenuItem(
              value: ChatBgOption.none,
              child: Text(l10n.generalChatBgNone),
            ),
            DropdownMenuItem(
              value: ChatBgOption.lavender,
              child: Text(l10n.generalChatBgLavender),
            ),
          ],
        ),
      ),
      ListTile(
        title: const Text('用户气泡颜色 (User Bubble)'),
        trailing: _ColorCircle(
          color: s.userBubbleColor != null
              ? Color(s.userBubbleColor!)
              : Theme.of(context).colorScheme.primary,
          onTap: () => _showColorPicker(
            context,
            s.userBubbleColor,
            (c) => controller.setUserBubbleColor(c?.toARGB32()),
          ),
        ),
      ),
      ListTile(
        title: const Text('AI 气泡颜色 (AI Bubble)'),
        trailing: _ColorCircle(
          color: s.aiBubbleColor != null
              ? Color(s.aiBubbleColor!)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          onTap: () => _showColorPicker(
            context,
            s.aiBubbleColor,
            (c) => controller.setAiBubbleColor(c?.toARGB32()),
          ),
        ),
      ),
    ];

    final fontSectionChildren = <Widget>[
      ListTile(
        title: Text(l10n.generalBaseFont),
        trailing: DropdownButton<BaseFontModeOption>(
          value: s.baseFontMode,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setBaseFontMode(v);
          },
          items: [
            DropdownMenuItem(
              value: BaseFontModeOption.system,
              child: Text(l10n.generalBaseFontSystem),
            ),
            DropdownMenuItem(
              value: BaseFontModeOption.miSansPreferred,
              child: Text(l10n.generalBaseFontMiSans),
            ),
          ],
        ),
      ),
      ListTile(
        title: Text(l10n.generalDecoFont),
        trailing: DropdownButton<DecorativeFontFamily>(
          value: s.decoFamily,
          underline: const SizedBox(),
          onChanged: (v) {
            if (v != null) controller.setDecoFamily(v);
          },
          items: [
            DropdownMenuItem(
              value: DecorativeFontFamily.none,
              child: Text(l10n.generalDecoFontNone),
            ),
            const DropdownMenuItem(
              value: DecorativeFontFamily.fzg,
              child: Text('FZG'),
            ),
            const DropdownMenuItem(
              value: DecorativeFontFamily.nfdcs,
              child: Text('nfdcs'),
            ),
          ],
        ),
      ),
      SwitchListTile(
        title: Text(l10n.generalDecoUseTitles),
        value: s.decoUseTitles,
        onChanged: (v) => controller.setDecoUseTitles(v),
      ),
      SwitchListTile(
        title: Text(l10n.generalDecoUseBubbles),
        value: s.decoUseBubbles,
        onChanged: (v) => controller.setDecoUseBubbles(v),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
          child: Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.preview,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.generalFontPreview,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.generalFontPreviewTitle,
                  style: TextStyle(
                    fontSize: 20 * s.textScale,
                    fontWeight: FontWeight.bold,
                    fontFamily: s.decoUseTitles &&
                            s.decoFamily != DecorativeFontFamily.none
                        ? (s.decoFamily == DecorativeFontFamily.fzg
                            ? 'FZG'
                            : 'nfdcs')
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(
                        s.uiMode == UIModeOption.bubble ? 2 : 12,
                      ),
                    ),
                  ),
                  child: Text(
                    l10n.generalFontPreviewText,
                    style: TextStyle(
                      fontSize: 16 * s.textScale,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontFamily: s.decoUseBubbles &&
                              s.decoFamily != DecorativeFontFamily.none
                          ? (s.decoFamily == DecorativeFontFamily.fzg
                              ? 'FZG'
                              : 'nfdcs')
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ListTile(
        title: Text(l10n.generalTextScale),
        subtitle: Slider(
          value: s.textScale,
          min: 0.9,
          max: 1.4,
          divisions: 10,
          label: s.textScale.toStringAsFixed(2),
          onChanged: (v) => controller.setTextScale(v),
        ),
        trailing: Text(s.textScale.toStringAsFixed(2)),
      ),
    ];

    final quickActionsChildren = <Widget>[
      ListTile(
        title: Text(l10n.generalQuickActionsInput),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in s.quickActions)
              Chip(
                label: Text(_getQuickActionLabel(id, l10n)),
                avatar: Icon(_getQuickActionIcon(id), size: 16),
              ),
            if (s.quickActions.isEmpty)
              Text(
                l10n.generalQuickActionsEmpty,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: FilledButton.tonal(
          onPressed: () => _showQuickActionsDialog(context, controller),
          child: Text(l10n.generalEdit),
        ),
      ),
    ];

    final agentSectionChildren = <Widget>[
      SwitchListTile(
        secondary: const Icon(Icons.auto_fix_high),
        title: const Text('启用语音修正 (Speech Refinement)'),
        subtitle: const Text('在发送给主脑前，先由轻量模型修正 STT 的错别字和冗余词'),
        value: s.enableSpeechRefinement,
        onChanged: (v) => controller.setEnableSpeechRefinement(v),
      ),
      if (s.enableSpeechRefinement)
        ListTile(
          leading: const Icon(Icons.psychology_outlined),
          title: const Text('语音修正专用模型'),
          subtitle: const Text('建议选择 8B 左右的轻量模型以获得极速响应'),
          trailing: DropdownButton<String?>(
            value: s.activeSpeechRefinerProviderId,
            underline: const SizedBox(),
            onChanged: (v) => controller.setActiveSpeechRefinerProvider(v),
            items: _buildProviderItems(AiProviderCategory.llm, '跟随主模型'),
          ),
        ),
      const Divider(height: 1, indent: 72),
      ListTile(
        leading: const Icon(Icons.construction),
        title: const Text('工具调用专用模型 (Tool Calling)'),
        subtitle: const Text('用于处理复杂的函数调用任务，若主模型支持不佳可单独指定'),
        trailing: DropdownButton<String?>(
          value: s.activeToolCallingProviderId,
          underline: const SizedBox(),
          onChanged: (v) => controller.setActiveToolCallingProvider(v),
          items: _buildProviderItems(AiProviderCategory.llm, '跟随主模型'),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.manage_search),
        title: const Text('深度研究专用模型 (Deep Research)'),
        subtitle: const Text('用于长时异步搜索与推理任务'),
        trailing: DropdownButton<String?>(
          value: s.activeDeepResearchProviderId,
          underline: const SizedBox(),
          onChanged: (v) => controller.setActiveDeepResearchProvider(v),
          items: _buildProviderItems(AiProviderCategory.llm, '跟随主模型'),
        ),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _ExpandableSection(
          title: '基础与后端配置',
          icon: Icons.settings_outlined,
          children: basicSectionChildren,
        ),
        const SizedBox(height: 12),
        _ExpandableSection(
          title: '语音交互配置',
          icon: Icons.record_voice_over,
          children: [
            ...ttsSectionChildren,
            const Divider(height: 32, indent: 16, endIndent: 16),
            ...sttSectionChildren,
          ],
        ),
        const SizedBox(height: 12),
        _ExpandableSection(
          title: '专家模型 Agent 配置',
          icon: Icons.support_agent,
          children: agentSectionChildren,
        ),
        const SizedBox(height: 12),
        _ExpandableSection(
          title: '外观与界面配置',
          icon: Icons.palette_outlined,
          children: [
            ...uiSectionChildren,
            const Divider(height: 32, indent: 16, endIndent: 16),
            ...appearanceSectionChildren,
            const Divider(height: 32, indent: 16, endIndent: 16),
            ...fontSectionChildren,
            const Divider(height: 32, indent: 16, endIndent: 16),
            ...quickActionsChildren,
          ],
        ),
      ],
    );
  }

  String _getQuickActionLabel(String id, AppLocalizations l10n) {
    return switch (id) {
      'attach_image' => l10n.qaAttachImage,
      'compress' => l10n.qaCompress,
      'new_chat' => l10n.qaNewChat,
      'memory' => l10n.qaMemory,
      _ => id,
    };
  }

  IconData _getQuickActionIcon(String id) {
    return switch (id) {
      'attach_image' => Icons.image_outlined,
      'compress' => Icons.cleaning_services_outlined,
      'new_chat' => Icons.add_comment_outlined,
      'memory' => Icons.memory,
      _ => Icons.extension,
    };
  }

  void _showQuickActionsDialog(BuildContext context, dynamic controller) {
    final s = controller.settings;
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) {
        final all = [
          'attach_image',
          'compress',
          'new_chat',
          'memory',
        ];
        final selected = List<String>.from(s.quickActions);
        return StatefulBuilder(
          builder: (ctx2, setStateDialog) => AlertDialog(
            title: Text(l10n.generalEditQuickActions),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final id in all)
                      CheckboxListTile(
                        value: selected.contains(id),
                        title: Text(_getQuickActionLabel(id, l10n)),
                        dense: true,
                        onChanged: (v) {
                          setStateDialog(() {
                            if (v == true && !selected.contains(id)) {
                              selected.add(id);
                            } else if (v == false) {
                              selected.remove(id);
                            }
                          });
                        },
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  controller.setQuickActions(selected);
                  Navigator.pop(ctx);
                },
                child: Text(l10n.commonSave),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpandableSection extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _ExpandableSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  State<_ExpandableSection> createState() => _ExpandableSectionState();
}

class _ExpandableSectionState extends State<_ExpandableSection>
    with SingleTickerProviderStateMixin {
  late bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25);
    final border = theme.dividerColor.withValues(alpha: 0.12);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: ListTile(
            leading: Icon(widget.icon),
            title: Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: AnimatedRotation(
              turns: _expanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(Icons.expand_more),
            ),
            contentPadding: EdgeInsets.zero,
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Material(
              color: bg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: widget.children,
              ),
            ),
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeIn,
          sizeCurve: Curves.easeInOut,
        ),
      ],
    );
  }
}

class _ColorCircle extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;

  const _ColorCircle({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showColorPicker(
  BuildContext context,
  int? currentColorValue,
  Function(Color?) onColorSelected,
) async {
  final colors = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey,
    Colors.black,
    Colors.white,
  ];

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('选择颜色'),
      content: SingleChildScrollView(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
             GestureDetector(
              onTap: () {
                onColorSelected(null); // Reset to default
                Navigator.pop(ctx);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey),
                ),
                child: const Icon(Icons.format_color_reset, size: 20),
              ),
            ),
            ...colors.map(
              (c) => GestureDetector(
                onTap: () {
                  onColorSelected(c);
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: currentColorValue == c.toARGB32()
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}
