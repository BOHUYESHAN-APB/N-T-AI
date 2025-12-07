import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../core/models/note.dart';
import '../core/services/note_service.dart';

class WhiteboardScreen extends StatefulWidget {
  final Note? note;
  const WhiteboardScreen({Key? key, this.note}) : super(key: key);

  @override
  State<WhiteboardScreen> createState() => _WhiteboardScreenState();
}

class _WhiteboardScreenState extends State<WhiteboardScreen> {
  final _controller = WebviewController();
  final _noteService = NoteService();
  bool _isInitialized = false;
  bool _hasInjected = false;

  @override
  void initState() {
    super.initState();
    _initWebview();
  }

  Future<String> _prepareAssets() async {
    // Load asset manifest to find all excalidraw files
    final manifestContent = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifestMap = json.decode(manifestContent);
    
    final excalidrawAssets = manifestMap.keys
        .where((key) => key.startsWith('assets/excalidraw/'))
        .toList();

    final appDir = await getApplicationSupportDirectory();
    final excalidrawDir = Directory(p.join(appDir.path, 'excalidraw'));
    
    if (!await excalidrawDir.exists()) {
      await excalidrawDir.create(recursive: true);
    }

    for (final assetPath in excalidrawAssets) {
      final relativePath = assetPath.substring('assets/excalidraw/'.length);
      final targetFile = File(p.join(excalidrawDir.path, relativePath));
      
      if (!await targetFile.parent.exists()) {
        await targetFile.parent.create(recursive: true);
      }
      
      final data = await rootBundle.load(assetPath);
      await targetFile.writeAsBytes(data.buffer.asUint8List());
    }

    return p.join(excalidrawDir.path, 'index.html');
  }

  Future<void> _initWebview() async {
    try {
      await _controller.initialize();
      _controller.url.listen((url) {});
      _controller.loadingState.listen((state) async {
        if (state == LoadingState.navigationCompleted) {
          if (!_hasInjected) {
            _hasInjected = true;
            await _injectContent();
          }
        }
      });

      final indexPath = await _prepareAssets();
      final fileUri = Uri.file(indexPath).toString();
      await _controller.loadUrl(fileUri);

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print("Error initializing webview: $e");
    }
  }

  Future<void> _injectContent() async {
    final content = widget.note?.content ?? '';
    
    // Wait for Excalidraw to be ready
    int attempts = 0;
    while (attempts < 20) {
      final isReady = await _controller.executeScript("!!window.excalidrawAPI");
      if (isReady == true) break;
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (content.isNotEmpty && widget.note?.type == 'whiteboard') {
      final safeContent = content.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
      
      await _controller.executeScript("""
        try {
          const data = JSON.parse('$safeContent');
          window.excalidrawAPI.updateScene(data);
        } catch (e) {
          console.error('Error loading content', e);
        }
      """);
    } else {
       await _controller.executeScript("window.excalidrawAPI.resetScene();");
    }
  }

  Future<void> _saveAndExit() async {
    try {
      final script = """
        (function() {
            const elements = window.excalidrawAPI.getSceneElements();
            const appState = window.excalidrawAPI.getAppState();
            const files = window.excalidrawAPI.getFiles();
            return JSON.stringify({ elements, appState, files });
        })();
      """;
      
      final result = await _controller.executeScript(script);
      String content = result.toString();
      
      if (content == "null") content = "";
      
      final now = DateTime.now();
      final note = Note(
        id: widget.note?.id ?? const Uuid().v4(),
        title: widget.note?.title ?? 'Whiteboard ${now.month}/${now.day} ${now.hour}:${now.minute}',
        content: content,
        summary: widget.note?.summary ?? '',
        type: 'whiteboard',
        createdAt: widget.note?.createdAt ?? now,
        updatedAt: now,
      );

      await _noteService.saveNote(note);
      
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Whiteboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveAndExit,
          ),
        ],
      ),
      body: _isInitialized
          ? Webview(
              _controller,
              permissionRequested: (url, kind, isUserInitiated) async {
                return WebviewPermissionDecision.allow;
              },
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
