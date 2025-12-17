import 'dart:async';
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import 'llm_service.dart';

class NoteService {
  static Database? _database;
  final LLMService _llmService = LLMService();
  
  // Broadcast stream to notify listeners of database changes
  static final StreamController<void> _updateController = StreamController.broadcast();
  Stream<void> get updateStream => _updateController.stream;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('astra_notes.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 2, 
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        summary TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'text',
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute("ALTER TABLE notes ADD COLUMN type TEXT NOT NULL DEFAULT 'text'");
    }
  }

  Future<void> saveNote(Note note) async {
    final db = await database;
    
    // Check if note exists
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [note.id],
    );

    if (maps.isNotEmpty) {
      await db.update(
        'notes',
        note.toMap(),
        where: 'id = ?',
        whereArgs: [note.id],
      );
    } else {
      await db.insert('notes', note.toMap());
    }
    
    _updateController.add(null);
    
    // Trigger background summary generation
    _generateSummary(note);
  }

  Future<void> deleteNote(String id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
    _updateController.add(null);
  }

  Future<List<Note>> getAllNotes() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('notes', orderBy: 'updatedAt DESC');
    return maps.map((e) => Note.fromMap(e)).toList();
  }

  Future<Note?> getNote(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Note.fromMap(maps.first);
    }
    return null;
  }

  Future<void> _generateSummary(Note note) async {
    String textToSummarize = note.content;

    // If whiteboard, extract text from JSON
    if (note.type == 'whiteboard') {
      try {
        final json = jsonDecode(note.content);
        if (json is Map && json.containsKey('elements')) {
          final elements = json['elements'] as List;
          final textBuffer = StringBuffer();
          for (final el in elements) {
            if (el is Map && el['type'] == 'text' && el['text'] != null) {
              textBuffer.writeln(el['text']);
            }
          }
          textToSummarize = textBuffer.toString();
        }
      } catch (e) {
        print("Error parsing whiteboard JSON: $e");
        textToSummarize = ""; // Fallback
      }
    }

    // Don't summarize if content is too short
    if (textToSummarize.trim().length < 20) {
      // For whiteboard, if no text, maybe summary is "Whiteboard Sketch"
      String simpleSummary = textToSummarize;
      if (note.type == 'whiteboard' && textToSummarize.isEmpty) {
        simpleSummary = "Whiteboard Sketch (No text)";
      }
      
      if (note.summary != simpleSummary) {
         final updatedNote = note.copyWith(summary: simpleSummary);
         await _updateNoteSummary(updatedNote);
      }
      return;
    }

    try {
      final prompt = "Please summarize the following note into a concise sentence or two (max 100 words). Keep key information.\n\nTitle: ${note.title}\nContent:\n$textToSummarize";
      
      final messages = [
        {'role': 'system', 'content': 'You are a helpful assistant that summarizes text. Output only the summary.'},
        {'role': 'user', 'content': prompt}
      ];
      
      final response = await _llmService.chat(messages, usageType: 'system');
      final summary = response.content;
      
      await _updateNoteSummary(note.copyWith(summary: summary));
      
    } catch (e) {
      print("Error generating summary: $e");
    }
  }

  Future<void> _updateNoteSummary(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      {'summary': note.summary},
      where: 'id = ?',
      whereArgs: [note.id],
    );
    _updateController.add(null);
  }
  
  // Method to get all summaries for AI context
  Future<String> getAllSummaries() async {
    final notes = await getAllNotes();
    if (notes.isEmpty) return "";
    
    final buffer = StringBuffer();
    buffer.writeln("User Notes Summary:");
    for (final note in notes) {
      buffer.writeln("- [${note.title}] (${note.type}): ${note.summary.isNotEmpty ? note.summary : 'No summary'}");
    }
    return buffer.toString();
  }
}
