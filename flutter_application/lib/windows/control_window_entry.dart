import 'dart:async';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';

class ControlWindowEntry extends StatefulWidget {
  final String backendUrl;

  const ControlWindowEntry({
    super.key,
    required this.backendUrl,
  });

  @override
  State<ControlWindowEntry> createState() => _ControlWindowEntryState();
}

class _ControlWindowEntryState extends State<ControlWindowEntry> {
  static const WindowMethodChannel _channel = WindowMethodChannel(
    'ntai/main_control',
    mode: ChannelMode.unidirectional,
  );

  ControlState _state = const ControlState();
  String? _error;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _initWindow();
    _loadState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadState(silent: true);
    });
  }

  Future<void> _initWindow() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(320, 560),
      center: false,
      backgroundColor: Colors.white,
      titleBarStyle: TitleBarStyle.hidden,
      skipTaskbar: false,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadState({bool silent = false}) async {
    try {
      final result = await _channel.invokeMethod('get_state');
      if (result is Map) {
        setState(() {
          _state = ControlState.fromMap(result.cast<String, dynamic>());
          _error = null;
        });
      }
    } catch (e) {
      if (!silent) {
        setState(() {
          _error = '无法获取主窗口状态：$e';
        });
      }
    }
  }

  Future<void> _applySetting(String key, dynamic value) async {
    try {
      final result = await _channel.invokeMethod('apply_setting', {
        'key': key,
        'value': value,
      });
      if (result is Map) {
        setState(() {
          _state = ControlState.fromMap(result.cast<String, dynamic>());
          _error = null;
        });
      }
    } catch (e) {
      setState(() {
        _error = '设置失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _buildTitleBar(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ),
                  _sectionTitle('语音'),
                  SwitchListTile(
                    title: const Text('TTS 语音播放'),
                    value: _state.enableTts,
                    onChanged: (v) => _applySetting('enableTts', v),
                  ),
                  SwitchListTile(
                    title: const Text('STT 语音识别'),
                    value: _state.enableStt,
                    onChanged: (v) => _applySetting('enableStt', v),
                  ),
                  SwitchListTile(
                    title: const Text('自动麦克风监听'),
                    subtitle: const Text('默认设备，和回环采集互斥'),
                    value: _state.autoMicListening,
                    onChanged: _state.enableStt
                        ? (v) => _applySetting('autoMicListening', v)
                        : null,
                  ),
                  const Divider(height: 16),
                  _sectionTitle('语音频道'),
                  SwitchListTile(
                    title: const Text('回环采集（语音频道）'),
                    subtitle: Text(
                      _state.enablePythonBackend
                          ? '后端进程设备'
                          : '后端未启用，暂不可用',
                    ),
                    value: _state.sttViaBackendLoopback,
                    onChanged: _state.enablePythonBackend && _state.enableStt
                        ? (v) => _applySetting('sttViaBackendLoopback', v)
                        : null,
                  ),
                  SwitchListTile(
                    title: const Text('自动语音频道监听'),
                    value: _state.autoVoiceChannelListening,
                    onChanged: (_state.sttViaBackendLoopback &&
                            _state.enablePythonBackend &&
                            _state.enableStt)
                        ? (v) =>
                            _applySetting('autoVoiceChannelListening', v)
                        : null,
                  ),
                  const Divider(height: 16),
                  _sectionTitle('屏幕'),
                  SwitchListTile(
                    title: const Text('屏幕截取'),
                    value: _state.enableScreenCapture,
                    onChanged: (v) => _applySetting('enableScreenCapture', v),
                  ),
                  const Divider(height: 16),
                  _sectionTitle('模式'),
                  _buildModeSelector(),
                  const SizedBox(height: 8),
                  Text(
                    '后台地址：${_state.backendUrl.isEmpty ? widget.backendUrl : _state.backendUrl}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) {
        windowManager.startDragging();
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.tune, size: 16),
            const SizedBox(width: 8),
            const Text(
              '桌宠控制窗',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => _loadState(),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () => windowManager.hide(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, top: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          value: _state.primaryMode,
          decoration: const InputDecoration(
            labelText: '主模式',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'assistant', child: Text('助理模式')),
            DropdownMenuItem(value: 'live', child: Text('直播模式')),
          ],
          onChanged: (value) {
            if (value == null) return;
            _applySetting('primaryMode', value);
          },
        ),
        if (_state.primaryMode == 'live') ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _state.liveMode,
            decoration: const InputDecoration(
              labelText: '直播子模式',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'watch', child: Text('你玩，AI看')),
              DropdownMenuItem(value: 'coPlay', child: Text('你玩 + AI玩')),
              DropdownMenuItem(value: 'autoPlay', child: Text('AI玩，你看')),
            ],
            onChanged: (value) {
              if (value == null) return;
              _applySetting('liveMode', value);
            },
          ),
        ],
      ],
    );
  }
}

class ControlState {
  final bool enableTts;
  final bool enableStt;
  final bool autoMicListening;
  final bool sttViaBackendLoopback;
  final bool autoVoiceChannelListening;
  final bool enableScreenCapture;
  final String primaryMode;
  final String liveMode;
  final bool enablePythonBackend;
  final String backendUrl;

  const ControlState({
    this.enableTts = false,
    this.enableStt = false,
    this.autoMicListening = false,
    this.sttViaBackendLoopback = false,
    this.autoVoiceChannelListening = false,
    this.enableScreenCapture = false,
    this.primaryMode = 'assistant',
    this.liveMode = 'watch',
    this.enablePythonBackend = false,
    this.backendUrl = '',
  });

  factory ControlState.fromMap(Map<String, dynamic> map) {
    return ControlState(
      enableTts: map['enableTts'] == true,
      enableStt: map['enableStt'] == true,
      autoMicListening: map['autoMicListening'] == true,
      sttViaBackendLoopback: map['sttViaBackendLoopback'] == true,
      autoVoiceChannelListening: map['autoVoiceChannelListening'] == true,
      enableScreenCapture: map['enableScreenCapture'] == true,
      primaryMode: (map['primaryMode'] ?? 'assistant').toString(),
      liveMode: (map['liveMode'] ?? 'watch').toString(),
      enablePythonBackend: map['enablePythonBackend'] == true,
      backendUrl: (map['backendUrl'] ?? '').toString(),
    );
  }
}
