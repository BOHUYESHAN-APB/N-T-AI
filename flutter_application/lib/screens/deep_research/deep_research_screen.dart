import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'widgets/sidebar.dart';
import 'widgets/mode_selector.dart';
// import 'widgets/case_showcase.dart';
import 'widgets/process_step_widget.dart';
import 'widgets/artifact_card_widget.dart';
import 'widgets/deep_research_config_dialog.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../settings/settings_scope.dart';
import '../../core/services/chat_history_service.dart';

class DeepResearchScreen extends StatefulWidget {
  const DeepResearchScreen({super.key});

  @override
  State<DeepResearchScreen> createState() => _DeepResearchScreenState();
}

class _DeepResearchScreenState extends State<DeepResearchScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _inputScrollController = ScrollController();
  bool _isTaskActive = false;
  bool _isLoading = false;
  String? _currentSessionId;
  bool _isPreviewPaneVisible = true;
  double _previewPaneWidth = 520;
  String _lastPrimaryQuery = "";
  
  // Task State
  List<Map<String, dynamic>> _processSteps = []; // {title, desc, status, logs}
  List<Map<String, String>> _artifacts = []; // {title, type, size}
  final Map<String, List<Map<String, dynamic>>> _resourcesByStep = {}; // stepTitle -> resources
  final Map<String, Map<String, String>> _artifactPreviews = {}; // title -> {format, html}
  String? _followupArtifactPath;
  String? _followupArtifactTitle;
  StreamSubscription<String>? _sseSubscription;
  
  // Clarification State
  bool _isClarificationNeeded = false;
  String _clarificationQuestion = "";
  final TextEditingController _clarificationController = TextEditingController();
  List<Map<String, dynamic>> _clarificationQuestions = [];
  final Map<String, dynamic> _clarificationAnswers = {};
  final Map<String, TextEditingController> _clarificationTextControllers = {};
  final Map<String, TextEditingController> _clarificationOtherControllers = {};
  Timer? _clarificationTimer;
  int _clarificationSecondsLeft = 0;
  bool _isClarificationCountdownPaused = false;

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _stopClarificationCountdown();
    _inputController.dispose();
    _inputScrollController.dispose();
    _clarificationController.dispose();
    for (final c in _clarificationTextControllers.values) {
      c.dispose();
    }
    for (final c in _clarificationOtherControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetClarificationForm() {
    for (final c in _clarificationTextControllers.values) {
      c.dispose();
    }
    for (final c in _clarificationOtherControllers.values) {
      c.dispose();
    }
    _clarificationTextControllers.clear();
    _clarificationOtherControllers.clear();
    _clarificationAnswers.clear();
    _clarificationQuestions = [];
    _clarificationController.clear();
  }

  List<Map<String, dynamic>> _normalizeClarificationQuestions(dynamic raw, String fallbackText) {
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((q) => Map<String, dynamic>.from(q))
          .where((q) => q.isNotEmpty)
          .toList();
    }

    if (raw is String && raw.trim().isNotEmpty) {
      return [
        {
          "id": "free_text",
          "type": "long_text",
          "title": "请补充必要信息",
          "placeholder": "可以写一段话，包含用途/受众/时间范围/格式要求等",
        }
      ];
    }

    if (fallbackText.trim().isNotEmpty) {
      return [
        {
          "id": "free_text",
          "type": "long_text",
          "title": "请补充必要信息",
          "placeholder": fallbackText,
        }
      ];
    }

    return [
      {
        "id": "free_text",
        "type": "long_text",
        "title": "请补充必要信息",
        "placeholder": "",
      }
    ];
  }

  List<Map<String, String>> _normalizeOptions(dynamic rawOptions) {
    if (rawOptions is List) {
      final opts = <Map<String, String>>[];
      for (final o in rawOptions) {
        if (o is Map) {
          final label = o['label']?.toString() ?? o['value']?.toString() ?? '';
          final value = o['value']?.toString() ?? label;
          if (label.trim().isEmpty) continue;
          opts.add({"label": label, "value": value});
        } else if (o is String) {
          final t = o.trim();
          if (t.isEmpty) continue;
          opts.add({"label": t, "value": t});
        }
      }
      return opts;
    }
    return [];
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _stopStreaming() async {
    try {
      await _sseSubscription?.cancel();
    } catch (_) {}
    _sseSubscription = null;
    _stopClarificationCountdown();
  }

  void _startClarificationCountdown({int seconds = 60}) {
    _clarificationTimer?.cancel();
    _clarificationSecondsLeft = seconds;
    _isClarificationCountdownPaused = false;
    _clarificationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_isClarificationNeeded) {
        timer.cancel();
        return;
      }

      if (_clarificationSecondsLeft <= 1) {
        timer.cancel();
        _autoDecideClarification();
        return;
      }

      _safeSetState(() {
        _clarificationSecondsLeft -= 1;
      });
    });
  }

  void _stopClarificationCountdown() {
    _clarificationTimer?.cancel();
    _clarificationTimer = null;
    _clarificationSecondsLeft = 0;
    _isClarificationCountdownPaused = false;
  }

  void _pauseClarificationCountdown() {
    if (!_isClarificationNeeded) return;
    if (_isClarificationCountdownPaused) return;
    _clarificationTimer?.cancel();
    _clarificationTimer = null;
    _isClarificationCountdownPaused = true;
  }

  Future<void> _autoDecideClarification() async {
    if (!_isClarificationNeeded) return;
    await _submitClarificationAnswer("用户60秒未响应，请基于现有信息自行补全缺失项并继续执行。");
  }

  Future<void> _submitTask({String? overrideQuery}) async {
    final query = (overrideQuery ?? _inputController.text).trim();
    if (query.isEmpty) return;

    final settings = SettingsScope.of(context).settings;
    final baseUrl = settings.pythonBackendUrl;

    await _stopStreaming();

    _safeSetState(() {
      _isLoading = true;
      _isTaskActive = true;
      _isClarificationNeeded = false; // Reset clarification state
      _resetClarificationForm();
      if (overrideQuery == null) {
        _lastPrimaryQuery = query;
      }
      _inputController.clear();
      _processSteps = [];
      if (_currentSessionId == null) {
        _artifacts = [];
        _artifactPreviews.clear();
        _followupArtifactPath = null;
        _followupArtifactTitle = null;
      }
      _resourcesByStep.clear();
    });

    try {
      // Collect selected model configs
      final plannerId = settings.deepResearch.plannerProviderId;
      final researcherId = settings.deepResearch.researcherProviderId;
      final writerId = settings.deepResearch.writerProviderId;

      // Helper to get provider details
      Map<String, dynamic>? getProviderConfig(String? id) {
        // If id is null (Follow Main Brain), use the active provider
        final targetId = id ?? settings.activeProviderId;
        if (targetId == null) return null;

        try {
          final p = settings.providers.firstWhere((p) => p.id == targetId);
          return {
            "api_key": p.apiKey,
            "base_url": p.baseUrl,
            "model": p.model,
            "provider": p.kind.name,
          };
        } catch (_) {
          return null;
        }
      }

      final modelConfigOverride = {
        "planner": getProviderConfig(plannerId),
        "researcher": getProviderConfig(researcherId),
        "writer": getProviderConfig(writerId),
      };

      final request = http.Request('POST', Uri.parse('$baseUrl/api/deep-research/task'));
      request.headers.addAll({
        'Content-Type': 'application/json',
        'X-Target-Api-Key': settings.ai.apiKey, 
        'X-Target-Base-Url': settings.ai.baseUrl,
      });
      request.body = jsonEncode({
        'query': query,
        'session_id': _currentSessionId,
        'model_config_override': modelConfigOverride,
        'context_files': (_followupArtifactPath != null && _followupArtifactTitle != null)
            ? [
                {
                  "path": _followupArtifactPath,
                  "title": _followupArtifactTitle,
                }
              ]
            : [],
      });

      final streamedResponse = await request.send();

      _sseSubscription = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith("data: ")) {
              final jsonStr = line.substring(6);
              if (jsonStr == "[DONE]") return;
              
              try {
                final event = jsonDecode(jsonStr);
                
                // Capture session ID if provided in event (e.g. step_start or a specific event)
                // Assuming backend might send it, or we infer it.
                // Currently backend doesn't explicitly send session_id back in events, 
                // but deep_research_routes.py returns DeepResearchResponse which has task_id (session_id).
                // However, we are using StreamingResponse now.
                // We should probably have the first event be "metadata" with session_id.
                // Or we can rely on the fact that we sent null and backend created one, 
                // BUT we don't get it back easily in stream unless we add a new event type.
                // Let's assume for now we don't get it back, so multi-turn is tricky without backend change.
                // WAIT! I can update backend to send session_id in the first event!
                
                if (event['type'] == 'metadata' && event['session_id'] != null) {
                   _currentSessionId = event['session_id'];
                   final title = event['title']?.toString() ?? "未命名研究";
                   ChatHistoryService().createSession(title, id: _currentSessionId, type: 'research');
                }
                
                _handleEvent(event);
              } catch (e) {
                debugPrint("Error parsing SSE event: $e");
              }
            }
          }, onDone: () {
            _safeSetState(() {
              _isLoading = false;
              _inputController.clear();
            });
          }, onError: (e) {
             _safeSetState(() {
                _processSteps.add({
                  "title": "Error",
                  "desc": "Connection error: $e",
                  "status": "failed",
                  "logs": []
                });
             });
          });

    } catch (e) {
      _safeSetState(() {
         // Handle error
      });
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    _safeSetState(() {
      final sessionId = event['session_id']?.toString();
      if (sessionId != null && sessionId.trim().isNotEmpty) {
        _currentSessionId = sessionId.trim();
      }
      switch (event['type']) {
        case 'step_start':
          final title = event['title']?.toString() ?? "";
          final existingIndex = _processSteps.lastIndexWhere((s) => s['title'] == title);
          if (existingIndex != -1) {
            _processSteps[existingIndex]['desc'] = event['desc'];
            _processSteps[existingIndex]['status'] = event['status'];
          } else {
            _processSteps.add({
              "title": title,
              "desc": event['desc'],
              "status": event['status'],
              "logs": <String>[]
            });
          }
          _resourcesByStep.putIfAbsent(title, () => []);
          break;
        case 'log':
          if (_processSteps.isNotEmpty) {
            // Find step by title or use last
            final stepIndex = _processSteps.lastIndexWhere((s) => s['title'] == event['step_title']);
            if (stepIndex != -1) {
              final logs = _processSteps[stepIndex]['logs'];
              if (logs is List) {
                logs.add(event['content']);
              } else {
                _processSteps[stepIndex]['logs'] = [event['content']];
              }
            }
          }
          break;
        case 'resource':
          final stepTitle = event['step_title']?.toString() ?? "";
          if (stepTitle.isEmpty) break;
          _resourcesByStep.putIfAbsent(stepTitle, () => []);
          final data = (event['data'] is Map<String, dynamic>) ? (event['data'] as Map<String, dynamic>) : <String, dynamic>{};
          _resourcesByStep[stepTitle]!.add({
            "kind": event['kind']?.toString() ?? "",
            ...data,
          });
          break;
        case 'plan_review':
          final rawSteps = event['steps'];
          final existingByTitle = <String, Map<String, dynamic>>{};
          for (final s in _processSteps) {
            final t = s['title']?.toString() ?? '';
            if (t.trim().isEmpty) continue;
            existingByTitle[t] = Map<String, dynamic>.from(s);
          }

          final steps = <String>[];
          if (rawSteps is List) {
            for (final item in rawSteps) {
              final step = item?.toString().trim() ?? '';
              if (step.isEmpty) continue;
              if (!steps.contains(step)) {
                steps.add(step);
              }
            }
          }

          final analysisStep = existingByTitle['任务分析'];
          if (analysisStep != null && !steps.contains('任务分析')) {
            steps.insert(0, '任务分析');
          }

          _processSteps.clear();
          _resourcesByStep.clear();

          for (final step in steps) {
            final existing = existingByTitle[step];
            if (existing != null) {
              final logs = existing['logs'];
              if (logs is! List) {
                existing['logs'] = <String>[];
              }
              existing['title'] = step;
              existing['desc'] = existing['desc'] ?? "Waiting to start...";
              existing['status'] = existing['status'] ?? 'pending';
              _processSteps.add(existing);
            } else {
              _processSteps.add({
                "title": step,
                "desc": "Waiting to start...",
                "status": "pending",
                "logs": <String>[]
              });
            }
            _resourcesByStep[step] = [];
          }
          break;
        case 'step_complete':
           final stepIndex = _processSteps.lastIndexWhere((s) => s['title'] == event['title']);
           if (stepIndex != -1) {
              _processSteps[stepIndex]['status'] = 'completed';
           }
           break;
        case 'artifact':
            _artifacts.add({
              "title": event['data']['title'],
              "type": event['data']['type'],
              "size": event['data']['size'],
              "path": event['data']['path'] // Store path for download
            });
            break;
        case 'artifact_preview':
          final data = (event['data'] is Map) ? Map<String, dynamic>.from(event['data']) : <String, dynamic>{};
          final title = data['title']?.toString() ?? '';
          final html = data['html']?.toString() ?? '';
          if (title.trim().isEmpty || html.trim().isEmpty) break;
          _artifactPreviews[title] = {
            "format": data['format']?.toString() ?? '',
            "html": html,
          };
          break;
        case 'final_result':
          _processSteps.add({
            "title": "完成",
            "desc": event['content']?.toString() ?? "研究任务成功完成。",
            "status": "completed",
            "logs": []
          });
          _isLoading = false;
          break;
        case 'clarification':
          final seconds = int.tryParse(event['auto_decide_seconds']?.toString() ?? '') ?? 60;
          final title = event['title']?.toString();
          final content = event['content']?.toString();
          final questions = _normalizeClarificationQuestions(event['questions'], content ?? '');
          _resetClarificationForm();
          _isClarificationNeeded = true;
          _clarificationQuestion = title ?? (content ?? "");
          _clarificationQuestions = questions;
          _clarificationSecondsLeft = seconds;
          _isLoading = false; // Stop loading to allow user input
          _startClarificationCountdown(seconds: seconds);
          break;
        case 'error':
          _processSteps.add({
            "title": "Error",
            "desc": event['content']?.toString() ?? "Unknown error",
            "status": "failed",
            "logs": []
          });
          _isLoading = false;
          break;
       }
     });
   }

  Uri _artifactUrlFromPath(String path) {
    final settings = SettingsScope.of(context).settings;
    final baseUrl = settings.pythonBackendUrl;
    final filename = path.split(r'\').last.split('/').last;
    return Uri.parse('$baseUrl/static/reports/$filename');
  }

  bool _isPreviewableInWebview(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return ['pdf', 'html', 'htm', 'png', 'jpg', 'jpeg', 'gif', 'txt'].contains(ext);
  }

  Future<void> _previewArtifact(String? path) async {
    if (path == null) return;
    final filename = path.split(r'\').last.split('/').last;
    final url = _artifactUrlFromPath(path);

    if (!_isPreviewableInWebview(filename)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("暂不支持预览该格式：$filename，请使用下载")),
      );
      return;
    }

    if (Platform.isWindows) {
      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowWidth: 980,
          windowHeight: 720,
          title: filename,
        ),
      );
      webview.launch(url.toString());
      return;
    }

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    }
  }

  Future<void> _downloadArtifact(String? path) async {
    if (path == null) return;

    final filename = path.split(r'\').last.split('/').last;
    final url = _artifactUrlFromPath(path);

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存文件',
      fileName: filename,
    );
    if (savePath == null) return;

    try {
      final resp = await http.get(url);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final file = File(savePath);
      await file.writeAsBytes(resp.bodyBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("已保存：$savePath")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("下载失败：$e")),
        );
      }
    }
  }

  void _setFollowupArtifact({required String title, required String? path}) {
    if (path == null) return;
    _safeSetState(() {
      _followupArtifactPath = path;
      _followupArtifactTitle = title;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("已设置追问依据：$title（提交新问题将基于此文件继续修改）")),
    );
  }

   @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          DeepResearchSidebar(
            onSessionSelected: (sessionId) {
              _stopStreaming();
              _safeSetState(() {
                if (sessionId == null) {
                  // New Project
                  _currentSessionId = null;
                  _isTaskActive = false;
                  _isLoading = false;
                  _isClarificationNeeded = false;
                  _processSteps = [];
                  _artifacts = [];
                  _inputController.clear();
                } else {
                  // Load Session (Placeholder for now, just sets ID and active)
                  // TODO: Load actual steps from DB if persisted
                  _currentSessionId = sessionId;
                  _isTaskActive = true;
                  _isLoading = false;
                  _isClarificationNeeded = false;
                  // For demo/prototype, we might not have steps saved, so we clear or show placeholder
                  _processSteps = []; 
                  _artifacts = [];
                }
              });
            },
          ),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isTaskActive ? _buildSplitView() : _buildInitialView(),
                ),
                // Input Area is always visible but style changes
                _buildBottomInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSplitView() {
    final theme = Theme.of(context);
    
    if (!_isPreviewPaneVisible) {
      return Stack(
        children: [
          Positioned.fill(child: _buildActiveTaskView()),
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: _buildPreviewRestoreStrip(theme),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const dividerWidth = 6.0;
        const minLeft = 320.0;
        const minRight = 340.0;

        final total = constraints.maxWidth;
        final available = total - dividerWidth;
        if (available <= 0) {
          return const SizedBox.shrink();
        }

        final minRightEffective = minRight > available ? available : minRight;
        final minLeftEffective = minLeft > available ? available : minLeft;
        final maxRight = (available - minLeftEffective).clamp(0.0, available);
        final rightUpper = maxRight < minRightEffective ? minRightEffective : maxRight;
        final right = _previewPaneWidth.clamp(minRightEffective, rightUpper);
        final left = (available - right).clamp(0.0, available);

        return Row(
          children: [
            SizedBox(
              width: left,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: theme.dividerColor.withAlpha(26))),
                ),
                child: _buildActiveTaskView(),
              ),
            ),
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) {
                  _safeSetState(() {
                    final next = _previewPaneWidth - details.delta.dx;
                    _previewPaneWidth = next.clamp(minRightEffective, rightUpper);
                  });
                },
                child: Container(
                  width: dividerWidth,
                  color: theme.colorScheme.surface,
                  child: Center(
                    child: Container(
                      width: 1,
                      color: theme.dividerColor.withAlpha(64),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: right,
              child: _buildPreviewPane(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPreviewRestoreStrip(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final completed = _processSteps.where((s) => s['status'] == 'completed').length;
    final total = _processSteps.isEmpty ? 1 : _processSteps.length;
    final percent = ((completed / total) * 100).toInt();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _safeSetState(() => _isPreviewPaneVisible = true),
        child: Container(
          width: 34,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh,
            border: Border(left: BorderSide(color: theme.dividerColor.withAlpha(38))),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Icon(Icons.open_in_full, size: 18, color: colorScheme.primary),
              const SizedBox(height: 8),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  "面板",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  "$percent%",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewPane() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return DefaultTabController(
      length: 3,
      child: Container(
        color: colorScheme.surfaceContainer,
        child: Column(
          children: [
            // Top Tab Bar
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(bottom: BorderSide(color: theme.dividerColor.withAlpha(26))),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showText = constraints.maxWidth >= 260;
                  return Row(
                    children: [
                      Expanded(
                        child: TabBar(
                          isScrollable: !showText,
                          labelColor: colorScheme.primary,
                          unselectedLabelColor: colorScheme.onSurfaceVariant,
                          indicatorSize: TabBarIndicatorSize.label,
                          tabs: [
                            Tab(
                              icon: const Icon(Icons.public, size: 18),
                              text: showText ? "资源浏览" : null,
                            ),
                            Tab(
                              icon: const Icon(Icons.folder_open, size: 18),
                              text: showText ? "生成文件" : null,
                            ),
                            Tab(
                              icon: const Icon(Icons.preview, size: 18),
                              text: showText ? "可视化" : null,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: "隐藏面板",
                        onPressed: () => _safeSetState(() => _isPreviewPaneVisible = false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  );
                },
              ),
            ),
            
            Expanded(
              child: TabBarView(
                children: [
                  // Tab 1: Browser / Resources Log
                  _buildResourcesView(),
                  // Tab 2: Artifacts
                  _buildArtifactsView(),
                  // Tab 3: Visual Preview
                  _buildVisualPreviewView(),
                ],
              ),
            ),
            
            // Bottom Progress Bar (Manus style)
            if (_isTaskActive) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(top: BorderSide(color: theme.dividerColor.withAlpha(26))),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 4, offset: const Offset(0, -2))
                  ]
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _processSteps.isNotEmpty ? _processSteps.last['title'] ?? "Processing..." : "Ready",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          "${(_processSteps.where((s) => s['status'] == 'completed').length / (_processSteps.isEmpty ? 1 : _processSteps.length) * 100).toInt()}%",
                          style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _processSteps.isEmpty 
                          ? 0 
                          : _processSteps.where((s) => s['status'] == 'completed').length / _processSteps.length,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 6,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResourcesView() {
    final theme = Theme.of(context);
    if (_resourcesByStep.isEmpty || _resourcesByStep.values.every((v) => v.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.public_off, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(51)),
            const SizedBox(height: 16),
            Text("暂无浏览记录", style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withAlpha(128))),
          ],
        ),
      );
    }

    final stepTitlesInOrder = _processSteps
        .map((s) => s['title']?.toString() ?? "")
        .where((t) => t.isNotEmpty && (_resourcesByStep[t]?.isNotEmpty ?? false))
        .toList();
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: stepTitlesInOrder.length,
      itemBuilder: (context, index) {
        final stepTitle = stepTitlesInOrder[index];
        final resources = _resourcesByStep[stepTitle] ?? const [];
        if (resources.isEmpty) {
          return const SizedBox.shrink();
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(64),
          child: ExpansionTile(
            title: Text(
              stepTitle,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              "${resources.length} 条记录",
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            children: [
              ...resources.map((r) {
                final kind = (r['kind'] ?? '').toString();
                final title = (r['title'] ?? r['query'] ?? r['url'] ?? '').toString();
                final url = (r['url'] ?? '').toString();
                final snippet = (r['snippet'] ?? '').toString();
                final icon = kind == 'visit' ? Icons.link : Icons.search;
                return ListTile(
                  dense: true,
                  leading: Icon(icon, size: 16, color: kind == 'visit' ? Colors.blueAccent : Colors.orangeAccent),
                  title: Text(
                    title,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: snippet.isNotEmpty
                      ? Text(
                          snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : (url.isNotEmpty ? Text(url, maxLines: 1, overflow: TextOverflow.ellipsis) : null),
                  onTap: url.isNotEmpty
                      ? () async {
                          final uri = Uri.tryParse(url);
                          if (uri != null) {
                            await launchUrl(uri);
                          }
                        }
                      : null,
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildArtifactsView() {
     if (_artifacts.isEmpty) {
     return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_off, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(51)),
            const SizedBox(height: 16),
            Text("暂无生成文件", style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(128))),
          ],
        ),
      );
    }
    
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            ..._artifacts.map((artifact) {
              final title = artifact['title']!;
              return ArtifactCardWidget(
                title: title,
                type: artifact['type']!,
                size: artifact['size']!,
                onDownload: () => _downloadArtifact(artifact['path']),
                onPreview: () => _previewArtifact(artifact['path']),
                onUseAsContext: () => _setFollowupArtifact(title: title, path: artifact['path']),
              );
            }),
          ],
        ),
      ],
    );
  }

  Future<void> _openHtmlPreview(String title) async {
    final entry = _artifactPreviews[title];
    if (entry == null) return;
    final htmlText = (entry["html"] ?? "").trim();
    if (htmlText.isEmpty) return;

    final uri = Uri.dataFromString(
      htmlText,
      mimeType: "text/html",
      encoding: utf8,
    );

    if (Platform.isWindows) {
      final webview = await WebviewWindow.create(
        configuration: CreateConfiguration(
          windowWidth: 1100,
          windowHeight: 760,
          title: "预览 - $title",
        ),
      );
      webview.launch(uri.toString());
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    }
  }

  Widget _buildVisualPreviewView() {
    final theme = Theme.of(context);

    if (_artifactPreviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.preview, size: 44, color: theme.colorScheme.onSurfaceVariant.withAlpha(102)),
            const SizedBox(height: 12),
            Text(
              "暂无可视化预览",
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final titles = _artifactPreviews.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: titles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final title = titles[index];
        final format = (_artifactPreviews[title]?["format"] ?? "").toUpperCase();
        return ListTile(
          leading: const Icon(Icons.article_outlined, size: 18),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: format.isEmpty ? null : Text(format),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: () => _openHtmlPreview(title),
        );
      },
    );
  }

  Widget _buildInitialView() {
    return const SingleChildScrollView(
      child: Column(
        children: [
          ModeSelector(),
          SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildActiveTaskView() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 1. Process Timeline
        ..._processSteps.asMap().entries.map((entry) {
          final step = entry.value;
          return ProcessStepWidget(
            stepNumber: entry.key + 1,
            title: step['title'],
            description: step['desc'],
            status: step['status'],
            logs: (step['logs'] as List<dynamic>?)?.cast<String>(),
          );
        }),
        
        if (_isClarificationNeeded) ...[
          _buildClarificationCard(theme),
        ],

        if (_artifacts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            "生成产物",
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              ..._artifacts.map((artifact) {
                final title = artifact['title']!;
                return ArtifactCardWidget(
                  title: title,
                  type: artifact['type']!,
                  size: artifact['size']!,
                  onDownload: () => _downloadArtifact(artifact['path']),
                  onPreview: () => _previewArtifact(artifact['path']),
                  onUseAsContext: () => _setFollowupArtifact(title: title, path: artifact['path']),
                );
              }),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _submitClarification() async {
    final answer = _buildClarificationAnswerPayload();
    if (answer.trim().isEmpty) {
      await _submitClarificationAnswer(
        "用户未填写任何补充信息，请基于现有信息自行补全缺失项并继续执行。",
      );
      return;
    }
    await _submitClarificationAnswer(answer);
  }

  Future<void> _submitClarificationAnswer(String answer) async {
    _stopClarificationCountdown();
    _clarificationController.clear();
    _resetClarificationForm();

    _safeSetState(() {
      _isClarificationNeeded = false;
      _processSteps.add({
        "title": "用户反馈",
        "desc": "补充信息已提交",
        "status": "completed",
        "logs": []
      });
    });

    final primary = _lastPrimaryQuery.trim().isEmpty ? "（原始需求缺失）" : _lastPrimaryQuery.trim();
    final mergedQuery = "原始需求:\n$primary\n\n补充信息:\n$answer\n\n未填写项请AI自行补全，并继续执行。";
    await _submitTask(overrideQuery: mergedQuery);
  }

  String _buildClarificationAnswerPayload() {
    final lines = <String>[];

    for (final q in _clarificationQuestions) {
      final id = q['id']?.toString() ?? '';
      if (id.isEmpty) continue;

      final type = q['type']?.toString() ?? 'single_choice';
      final title = q['title']?.toString() ?? q['label']?.toString() ?? '';
      final label = title.trim().isEmpty ? "问题 $id" : title.trim();

      if (type == 'single_choice') {
        final selected = _clarificationAnswers[id]?.toString();
        if (selected == null || selected.trim().isEmpty) continue;

        final options = _normalizeOptions(q['options']);
        final selectedLabel = options.firstWhere(
          (o) => (o['value'] ?? '') == selected,
          orElse: () => {"label": selected, "value": selected},
        )['label']!;

        if (selected == 'other') {
          final other = _clarificationOtherControllers[id]?.text.trim();
          final text = (other == null || other.isEmpty) ? selectedLabel : "$selectedLabel：$other";
          lines.add("- $label：$text");
        } else {
          lines.add("- $label：$selectedLabel");
        }
      } else if (type == 'multi_choice') {
        final raw = _clarificationAnswers[id];
        if (raw is! List) continue;
        final values = raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
        if (values.isEmpty) continue;

        final options = _normalizeOptions(q['options']);
        final labels = values.map((v) {
          return options.firstWhere(
            (o) => (o['value'] ?? '') == v,
            orElse: () => {"label": v, "value": v},
          )['label']!;
        });

        lines.add("- $label：${labels.join('、')}");
      } else if (type == 'short_text' || type == 'long_text') {
        final text = _clarificationTextControllers[id]?.text.trim();
        if (text == null || text.isEmpty) continue;
        lines.add("- $label：$text");
      }
    }

    final extra = _clarificationController.text.trim();
    if (extra.isNotEmpty) {
      lines.add("- 补充说明：$extra");
    }

    return lines.join("\n").trim();
  }

  Widget _buildClarificationCard(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer.withAlpha(77),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.tertiary.withAlpha(128)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.live_help, color: colorScheme.tertiary),
              const SizedBox(width: 8),
              Text(
                "需要补充信息",
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.tertiary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_clarificationQuestion.trim().isNotEmpty) ...[
            Text(_clarificationQuestion, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 8),
          Text(
            _isClarificationCountdownPaused ? "倒计时已暂停" : "${_clarificationSecondsLeft}s 后自动决策",
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          ..._clarificationQuestions.map((q) => _buildClarificationQuestion(theme, q)),
          const SizedBox(height: 16),
          Text("补充说明（可选）", style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _clarificationController,
            onTap: _pauseClarificationCountdown,
            decoration: const InputDecoration(
              hintText: "可以用一段文字补充背景、口径、偏好等...",
              border: OutlineInputBorder(),
              filled: true,
            ),
            maxLines: 5,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _submitClarificationAnswer(
                  "用户选择跳过补充信息，请基于现有信息自行补全缺失项并继续执行。",
                ),
                child: const Text("跳过，由AI自行决策"),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _submitClarification,
                icon: const Icon(Icons.check),
                label: const Text("提交问卷"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClarificationQuestion(ThemeData theme, Map<String, dynamic> q) {
    final id = q['id']?.toString() ?? '';
    final type = q['type']?.toString() ?? 'single_choice';
    final title = q['title']?.toString() ?? q['label']?.toString() ?? '';
    final placeholder = q['placeholder']?.toString() ?? '';
    final otherPlaceholder = q['other_placeholder']?.toString() ?? '';

    Widget body = const SizedBox.shrink();

    if (type == 'single_choice') {
      final options = _normalizeOptions(q['options']);
      final groupValue = _clarificationAnswers[id]?.toString();
      body = Column(
        children: [
          ...options.map((o) {
            final value = o['value'] ?? '';
            return RadioListTile<String>(
              value: value,
              groupValue: groupValue,
              onChanged: (val) {
                if (val == null) return;
                _pauseClarificationCountdown();
                _safeSetState(() {
                  _clarificationAnswers[id] = val;
                });
              },
              title: Text(o['label'] ?? '', style: theme.textTheme.bodyMedium),
              dense: true,
              contentPadding: EdgeInsets.zero,
            );
          }),
          if (groupValue == 'other') ...[
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: TextField(
                controller: _clarificationOtherControllers.putIfAbsent(id, () => TextEditingController()),
                onTap: _pauseClarificationCountdown,
                decoration: InputDecoration(
                  hintText: otherPlaceholder.isEmpty ? "请输入其他选项..." : otherPlaceholder,
                  border: const OutlineInputBorder(),
                  filled: true,
                ),
                maxLines: 2,
              ),
            ),
          ],
        ],
      );
    } else if (type == 'multi_choice') {
      final options = _normalizeOptions(q['options']);
      final selected = (_clarificationAnswers[id] is List)
          ? (_clarificationAnswers[id] as List).map((e) => e.toString()).toSet()
          : <String>{};

      body = Column(
        children: [
          ...options.map((o) {
            final value = o['value'] ?? '';
            final checked = selected.contains(value);
            return CheckboxListTile(
              value: checked,
              onChanged: (val) {
                _pauseClarificationCountdown();
                _safeSetState(() {
                  final set = selected;
                  if (val == true) {
                    set.add(value);
                  } else {
                    set.remove(value);
                  }
                  _clarificationAnswers[id] = set.toList();
                });
              },
              title: Text(o['label'] ?? '', style: theme.textTheme.bodyMedium),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            );
          }),
        ],
      );
    } else {
      final controller = _clarificationTextControllers.putIfAbsent(id, () => TextEditingController());
      body = TextField(
        controller: controller,
        onTap: _pauseClarificationCountdown,
        decoration: InputDecoration(
          hintText: placeholder.isEmpty ? "请输入..." : placeholder,
          border: const OutlineInputBorder(),
          filled: true,
        ),
        maxLines: type == 'short_text' ? 2 : 5,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.trim().isNotEmpty) ...[
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _buildBottomInputArea() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor.withAlpha(31))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_followupArtifactTitle != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor.withAlpha(31)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 16, color: colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "追问依据：${_followupArtifactTitle!}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
                            ),
                          ),
                          IconButton(
                            tooltip: "清除",
                            onPressed: () => _safeSetState(() {
                              _followupArtifactPath = null;
                              _followupArtifactTitle = null;
                            }),
                            icon: Icon(Icons.close, size: 18, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {},
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(153),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter): () {
                            // Insert newline on simple Enter
                            final value = _inputController.value;
                            final selection = value.selection;
                            final start = selection.start < 0 ? value.text.length : selection.start;
                            final end = selection.end < 0 ? value.text.length : selection.end;
                            final newText = value.text.replaceRange(start, end, '\n');
                            _inputController.value = TextEditingValue(
                              text: newText,
                              selection: TextSelection.collapsed(offset: start + 1),
                            );
                          },
                          const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                            // Submit on Ctrl+Enter
                            final value = _inputController.value;
                            if (_isLoading) return;
                            if (_inputController.text.trim().isEmpty) return;
                            _submitTask();
                          },
                        },
                        child: Scrollbar(
                          controller: _inputScrollController,
                          thumbVisibility: true,
                          child: TextField(
                            controller: _inputController,
                            scrollController: _inputScrollController,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 1,
                            maxLines: null,
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              hintText: "输入后续问题或开始新任务... (Enter 换行, Ctrl+Enter 发送)",
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant.withAlpha(204),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _isLoading ? null : _submitTask,
                  icon: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.send, color: colorScheme.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withAlpha(31))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           // Breadcrumb or Status
           Row(
             children: [
              if (_isTaskActive) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () {
                    _stopStreaming();
                    _safeSetState(() {
                      _isTaskActive = false;
                      _isLoading = false;
                      _isClarificationNeeded = false;
                    });
                  },
                ),
              ],
              Text(
                _isTaskActive ? "进行中的任务 #${_currentSessionId?.substring(0, 4) ?? '...'}" : "深度研究中心",
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
           
           Row(
             children: [
                Container(
                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                 decoration: BoxDecoration(
                   color: colorScheme.surfaceContainerHighest,
                   borderRadius: BorderRadius.circular(20),
                 ),
                 child: Row(
                   children: [
                     Icon(Icons.psychology, size: 16, color: colorScheme.primary),
                     const SizedBox(width: 8),
                     Text(
                       "DeepSeek-R1 (当前模型)",
                       style: theme.textTheme.bodySmall?.copyWith(
                         color: colorScheme.onSurface,
                         fontWeight: FontWeight.w500,
                       ),
                     ),
                   ],
                 ),
               ),
               const SizedBox(width: 12),
               IconButton(
                 icon: const Icon(Icons.settings),
                 tooltip: "配置智能体",
                 onPressed: () {
                   showDialog(
                     context: context,
                     builder: (context) => const DeepResearchConfigDialog(),
                   );
                 },
               ),
             ],
           ),
        ],
      ),
    );
  }
}
