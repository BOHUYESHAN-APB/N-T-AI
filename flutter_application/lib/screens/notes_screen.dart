import 'package:flutter/material.dart';
import '../core/models/note.dart';
import '../core/services/note_service.dart';
import 'note_editor_screen.dart';
import 'whiteboard_screen.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final NoteService _noteService = NoteService();
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
    _noteService.updateStream.listen((_) => _loadNotes());
  }

  Future<void> _loadNotes() async {
    final notes = await _noteService.getAllNotes();
    if (mounted) {
      setState(() {
        _notes = notes;
        _isLoading = false;
      });
    }
  }

  void _createNewNote() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Text Note'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NoteEditorScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.brush),
              title: const Text('Whiteboard (Excalidraw)'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WhiteboardScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openNote(Note note) {
    if (note.type == 'whiteboard') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => WhiteboardScreen(note: note)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NoteEditorScreen(note: note)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final density = SettingsScope.of(context).settings.density;
    final pad = switch (density) {
      DensityOption.compact => const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      DensityOption.normal => const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      DensityOption.spacious => const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    };

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notes.isEmpty) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text('No notes yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'notes_fab',
          onPressed: _createNewNote,
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      body: ListView.builder(
        padding: pad,
        itemCount: _notes.length,
        itemBuilder: (context, index) {
          final n = _notes[index];
          final isWhiteboard = n.type == 'whiteboard';
          return Card(
            child: ListTile(
              leading: Icon(isWhiteboard ? Icons.brush : Icons.description_outlined),
              title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  n.summary.isNotEmpty ? "Summary: ${n.summary}" : (isWhiteboard ? "Whiteboard Sketch" : n.content),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              onTap: () => _openNote(n),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'notes_fab',
        onPressed: _createNewNote,
        child: const Icon(Icons.add),
      ),
    );
  }
}
