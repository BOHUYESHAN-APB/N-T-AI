import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'widgets/sidebar.dart';
import 'widgets/mode_selector.dart';
import 'widgets/case_showcase.dart';
import 'widgets/process_step_widget.dart';
import 'widgets/artifact_card_widget.dart';
import 'widgets/deep_research_config_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../settings/settings_scope.dart';

class DeepResearchScreen extends StatefulWidget {
  const DeepResearchScreen({super.key});

  @override
  State<DeepResearchScreen> createState() => _DeepResearchScreenState();
}

class _DeepResearchScreenState extends State<DeepResearchScreen> {
  final TextEditingController _inputController = TextEditingController();
  bool _isTaskActive = false;
  bool _isLoading = false;
  String? _currentSessionId;
  
  // Task State
  List<Map<String, dynamic>> _processSteps = []; // {title, desc, status, logs}
  List<Map<String, String>> _artifacts = []; // {title, type, size}

  Future<void> _submitTask() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _isTaskActive = true;
      if (_currentSessionId == null) {
        // New session, clear previous steps
        _processSteps = [];
        _artifacts = [];
      } else {
        // Continue session, keep artifacts, maybe add separator in UI?
        // For now, we just append new steps.
      }
    });

    try {
      final settings = SettingsScope.of(context).settings;
      final baseUrl = settings.pythonBackendUrl; 
      
      // Collect selected model configs
      final plannerId = settings.deepResearch.plannerProviderId;
      final researcherId = settings.deepResearch.researcherProviderId;
      final writerId = settings.deepResearch.writerProviderId;

      // Helper to get provider details
      Map<String, dynamic>? getProviderConfig(String? id) {
        if (id == null) return null; // Use backend default
        try {
          final p = settings.providers.firstWhere((p) => p.id == id);
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
      });

      final streamedResponse = await request.send();

      streamedResponse.stream
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
                }
                
                _handleEvent(event);
              } catch (e) {
                debugPrint("Error parsing SSE event: $e");
              }
            }
          }, onDone: () {
            setState(() {
              _isLoading = false;
              _inputController.clear();
            });
          }, onError: (e) {
             setState(() {
                _processSteps.add({
                  "title": "Error",
                  "desc": "Connection error: $e",
                  "status": "failed",
                  "logs": []
                });
             });
          });

    } catch (e) {
      setState(() {
         // Handle error
      });
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    setState(() {
      switch (event['type']) {
        case 'step_start':
          _processSteps.add({
            "title": event['title'],
            "desc": event['desc'],
            "status": event['status'],
            "logs": []
          });
          break;
        case 'log':
          if (_processSteps.isNotEmpty) {
            // Find step by title or use last
            final stepIndex = _processSteps.lastIndexWhere((s) => s['title'] == event['step_title']);
            if (stepIndex != -1) {
               _processSteps[stepIndex]['logs'].add(event['content']);
            }
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
       }
     });
   }

  Future<void> _downloadArtifact(String? path) async {
    if (path == null) return;
    
    final settings = SettingsScope.of(context).settings;
    final baseUrl = settings.pythonBackendUrl; 
    
    // Construct download URL
    // Backend path is like "backend/app/static/reports/..." or absolute
    // We need to serve it via static mount
    // Assuming backend mounts "app/static" at "/static"
    
    String filename = path.split(r'\').last.split('/').last; // Handle both separators
    final url = Uri.parse('$baseUrl/static/reports/$filename');
    
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text("Could not launch $url")),
       );
    }
  }

   @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Row(
        children: [
          const DeepResearchSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _isTaskActive ? _buildActiveTaskView() : _buildInitialView(),
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

  Widget _buildInitialView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const ModeSelector(),
          const SizedBox(height: 40),
          const CaseShowcase(),
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
        }).toList(),

        if (_artifacts.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            "Generated Artifacts",
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _artifacts.map((artifact) {
               return ArtifactCardWidget(
                 title: artifact['title']!,
                 type: artifact['type']!,
                 size: artifact['size']!,
                 onDownload: () => _downloadArtifact(artifact['path']),
                 onPreview: () => _downloadArtifact(artifact['path']), // Preview via browser for now
               );
             }).toList(),
          ),
        ],
        
        // Spacer for bottom input
        const SizedBox(height: 100), 
      ],
    );
  }

  Widget _buildBottomInputArea() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor.withOpacity(0.12))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {},
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withOpacity(0.6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _inputController,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: "Ask follow-up or start new task...",
                  hintStyle: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
                onSubmitted: (_) => _isLoading ? null : _submitTask(),
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
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.12))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           // Breadcrumb or Status
           Row(
             children: [
               if (_isTaskActive) 
                 IconButton(
                  icon: const Icon(Icons.arrow_back),
                   onPressed: () => setState(() => _isTaskActive = false),
                 ),
               Text(
                 _isTaskActive ? "Active Session #1024" : "Deep Research Hub",
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
                     Text(
                       "DeepSeek-R1",
                       style: theme.textTheme.bodySmall?.copyWith(
                         color: colorScheme.onSurfaceVariant,
                       ),
                     ),
                     SizedBox(width: 4),
                     Icon(Icons.arrow_drop_down, color: colorScheme.onSurfaceVariant, size: 16),
                   ],
                 ),
               ),
               const SizedBox(width: 12),
               IconButton(
                 icon: const Icon(Icons.settings),
                 tooltip: "Configure Agents",
                 onPressed: () {
                   showDialog(
                     context: context,
                     builder: (context) => const DeepResearchConfigDialog(),
                   );
                 },
               ),
               IconButton(
                 icon: const Icon(Icons.close),
                 onPressed: () => Navigator.of(context).pop(),
               ),
             ],
           ),
        ],
      ),
    );
  }
}
