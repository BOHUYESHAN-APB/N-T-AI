import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import '../models/meme.dart';
import 'llm_service.dart';

class MemeService {
  static Database? _database;
  final LLMService _llmService = LLMService();
  final Uuid _uuid = const Uuid();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('astra_me.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onOpen: (db) async {
      // Ensure table exists even if DB was created by MemoryService
      await db.execute('''
        CREATE TABLE IF NOT EXISTS memes (
          id TEXT PRIMARY KEY,
          path TEXT NOT NULL,
          tags TEXT NOT NULL,
          embedding TEXT NOT NULL,
          usage_count INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
    });
  }

  Future<void> saveMeme(String path, String description) async {
    List<double> embedding = [];
    try {
      embedding = await _llmService.getEmbedding(description);
    } catch (e) {
      print("Warning: Failed to generate embedding for meme: $e");
      // Fallback: use zero vector or skip? 
      // For now, we'll skip saving if we can't search it, or use a dummy vector.
      // Better to just return or throw.
      return;
    }

    try {
      final meme = Meme(
        id: _uuid.v4(),
        path: path,
        tags: description,
        embedding: embedding,
        createdAt: DateTime.now(),
      );

      final db = await database;
      await db.insert('memes', meme.toMap());
      print("Meme saved: $description");
    } catch (e) {
      print("Error saving meme to DB: $e");
    }
  }

  Future<void> saveMemeFromBytes(Uint8List bytes, String description) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final memeDir = Directory(join(appDir.path, 'memes'));
      if (!await memeDir.exists()) {
        await memeDir.create(recursive: true);
      }
      final filename = '${_uuid.v4()}.png';
      final file = File(join(memeDir.path, filename));
      await file.writeAsBytes(bytes);
      
      await saveMeme(file.path, description);
    } catch (e) {
      print("Error saving meme file: $e");
    }
  }

  Future<List<Meme>> searchMemes(String query, {int limit = 3}) async {
    try {
      final queryEmbedding = await _llmService.getEmbedding(query);
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query('memes');
      
      if (maps.isEmpty) return [];

      List<Meme> allMemories = maps.map((e) => Meme.fromMap(e)).toList();
      
      var scored = allMemories.map((meme) {
        double score = _cosineSimilarity(queryEmbedding, meme.embedding);
        return MapEntry(meme, score);
      }).toList();

      // Sort by score descending
      scored.sort((a, b) => b.value.compareTo(a.value));

      // Filter by threshold (e.g. 0.7) to avoid irrelevant memes
      // But for "fun", maybe lower threshold.
      return scored.where((e) => e.value > 0.6).take(limit).map((e) => e.key).toList();
    } catch (e) {
      print("Error searching memes: $e");
      return [];
    }
  }

  Future<void> incrementUsage(String id) async {
    final db = await database;
    await db.rawUpdate('UPDATE memes SET usage_count = usage_count + 1 WHERE id = ?', [id]);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}
