import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';
import '../models/memory.dart';
import 'llm_service.dart';

class MemoryService {
  static Database? _database;
  final LLMService _llmService = LLMService();
  final Uuid _uuid = const Uuid();
  
  // Broadcast stream to notify listeners of database changes
  static final StreamController<void> _updateController = StreamController.broadcast();
  Stream<void> get updateStream => _updateController.stream;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('astra_me.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> backupTo(String destinationPath) async {
    final dbPath = await getDatabasesPath();
    final srcPath = join(dbPath, 'astra_me.db');
    final File src = File(srcPath);
    if (await src.exists()) {
      await src.copy(destinationPath);
    } else {
      throw Exception('Database file not found');
    }
  }

  Future<void> restoreFrom(String sourcePath) async {
    await close();
    final dbPath = await getDatabasesPath();
    final destPath = join(dbPath, 'astra_me.db');
    final File src = File(sourcePath);
    if (await src.exists()) {
      await src.copy(destPath);
    } else {
      throw Exception('Source file not found');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE memories (
        id TEXT PRIMARY KEY,
        content TEXT NOT NULL,
        category TEXT NOT NULL,
        embedding TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        importance REAL NOT NULL
      )
    ''');
  }

  Future<void> saveMemory(String content, String category) async {
    List<double> embedding = [];
    try {
      embedding = await _llmService.getEmbedding(content);
    } catch (e) {
      print("Warning: Failed to generate embedding for memory: $e");
      // Continue saving without embedding (or with empty one)
      // Note: Retrieval based on cosine similarity will ignore this memory
      // unless we implement a keyword fallback.
    }

    try {
      final memory = Memory(
        id: _uuid.v4(),
        content: content,
        category: category,
        embedding: embedding,
        createdAt: DateTime.now(),
      );

      final db = await database;
      await db.insert('memories', memory.toMap());
      print("Memory saved: $content");
      _updateController.add(null); // Notify listeners
    } catch (e) {
      print("Error saving memory to DB: $e");
    }
  }

  Future<void> deleteMemory(String id) async {
    final db = await database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
    _updateController.add(null);
  }

  Future<void> clearAll() async {
    final db = await database;
    await db.delete('memories');
    _updateController.add(null);
  }

  Future<List<Memory>> retrieveRelevant(String query, {int limit = 5}) async {
    List<double> queryEmbedding = [];
    try {
      queryEmbedding = await _llmService.getEmbedding(query);
    } catch (e) {
      print("Embedding failed: $e");
    }

    final db = await database;

    // If embedding failed or is empty, fallback to keyword search
    if (queryEmbedding.isEmpty) {
      print("Fallback to keyword search for: $query");
      final List<Map<String, dynamic>> maps = await db.query(
        'memories',
        where: 'content LIKE ?',
        whereArgs: ['%${query}%'],
        limit: limit,
        orderBy: 'created_at DESC'
      );
      return maps.map((e) => Memory.fromMap(e)).toList();
    }
      
    final List<Map<String, dynamic>> maps = await db.query('memories');
    List<Memory> allMemories = maps.map((e) => Memory.fromMap(e)).toList();
      
    // Calculate Cosine Similarity locally
    var scoredMemories = allMemories.map((memory) {
      // If memory has no embedding, skip it (or treat as 0 score)
      if (memory.embedding.isEmpty) return MapEntry(memory, 0.0);
      double score = _cosineSimilarity(queryEmbedding, memory.embedding);
      return MapEntry(memory, score);
    }).toList();

    // Sort by score descending
    scoredMemories.sort((a, b) => b.value.compareTo(a.value));

    // Take top N
    return scoredMemories.take(limit).map((e) => e.key).toList();
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
