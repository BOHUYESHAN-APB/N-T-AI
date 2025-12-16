import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:uuid/uuid.dart';
import '../core/models/note.dart';
import '../core/services/note_service.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? note;

  const NoteEditorScreen({super.key, this.note});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _noteService = NoteService();
  bool _isDirty = false;
  bool _isPreviewEnabled = false;

  @override
  void initState() {
    super.initState();
    if (widget.note != null) {
      _titleController.text = widget.note!.title;
      _contentController.text = widget.note!.content;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _saveNote() async {
    if (_titleController.text.isEmpty && _contentController.text.isEmpty) return;

    final now = DateTime.now();
    final note = Note(
      id: widget.note?.id ?? const Uuid().v4(),
      title: _titleController.text.isEmpty ? 'Untitled' : _titleController.text,
      content: _contentController.text,
      summary: widget.note?.summary ?? '', // Service will update this
      createdAt: widget.note?.createdAt ?? now,
      updatedAt: now,
    );

    await _noteService.saveNote(note);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _deleteNote() async {
    if (widget.note != null) {
      await _noteService.deleteNote(widget.note!.id);
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.note == null ? 'New Note' : 'Edit Note'),
        actions: [
          IconButton(
            icon: Icon(_isPreviewEnabled ? Icons.visibility_off : Icons.visibility),
            tooltip: _isPreviewEnabled ? '关闭预览' : '预览 Markdown',
            onPressed: () {
              setState(() {
                _isPreviewEnabled = !_isPreviewEnabled;
              });
            },
          ),
          if (widget.note != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _deleteNote,
            ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveNote,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
                hintStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              onChanged: (_) => _isDirty = true,
            ),
            const Divider(),
            Expanded(
              child: _isPreviewEnabled
                  ? Column(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _contentController,
                            decoration: const InputDecoration(
                              hintText: '支持 Markdown 语法，开始输入内容...',
                              border: InputBorder.none,
                            ),
                            maxLines: null,
                            expands: true,
                            onChanged: (_) => _isDirty = true,
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _contentController,
                            builder: (context, value, _) {
                              final text = value.text;
                              if (text.isEmpty) {
                                return const Center(
                                  child: Text(
                                    '预览区域：当前没有内容',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }
                              return Markdown(
                                data: text,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              );
                            },
                          ),
                        ),
                      ],
                    )
                  : TextField(
                      controller: _contentController,
                      decoration: const InputDecoration(
                        hintText: 'Start typing...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      expands: true,
                      onChanged: (_) => _isDirty = true,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
