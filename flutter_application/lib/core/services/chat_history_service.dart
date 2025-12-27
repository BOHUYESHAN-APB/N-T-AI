import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

class ChatSession {
  final String id;
  final String title;
  final String type; // 'chat' or 'research'
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    this.type = 'chat',
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'type': type,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory ChatSession.fromMap(Map<String, dynamic> map) => ChatSession(
    id: map['id'],
    title: map['title'],
    type: map['type'] ?? 'chat',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at']),
  );
}

class ChatMessage {
  final String id;
  final String sessionId;
  final String role;
  final String content;
  final String? source;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.source,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'role': role,
    'content': content,
    'source': source,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'],
    sessionId: map['session_id'],
    role: map['role'],
    content: map['content'],
    source: map['source'],
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
  );
}

class ChatHistoryService {
  static Database? _database;
  final Uuid _uuid = const Uuid();
  
  // Broadcast stream for updates
  static final StreamController<void> _updateController = StreamController.broadcast();
  Stream<void> get updateStream => _updateController.stream;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('astra_chat.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 3, 
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE sessions ADD COLUMN type TEXT DEFAULT "chat"');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE messages ADD COLUMN source TEXT');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        type TEXT DEFAULT "chat",
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        source TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<ChatSession> createSession(String title, {String type = 'chat', String? id}) async {
    final db = await database;
    final session = ChatSession(
      id: id ?? _uuid.v4(),
      title: title,
      type: type,
      updatedAt: DateTime.now(),
    );
    await db.insert('sessions', session.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    _updateController.add(null);
    return session;
  }

  Future<List<ChatSession>> getSessions({String? type}) async {
    final db = await database;
    final where = type != null ? 'type = ?' : null;
    final args = type != null ? [type] : null;
    
    final maps = await db.query(
      'sessions', 
      where: where,
      whereArgs: args,
      orderBy: 'updated_at DESC'
    );
    return maps.map((e) => ChatSession.fromMap(e)).toList();
  }

  Future<void> deleteSession(String id) async {
    final db = await database;
    await db.delete('sessions', where: 'id = ?', whereArgs: [id]);
    await db.delete('messages', where: 'session_id = ?', whereArgs: [id]);
    _updateController.add(null);
  }

  Future<void> updateSessionTitle(String id, String title) async {
    final db = await database;
    await db.update(
      'sessions',
      {'title': title, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    _updateController.add(null);
  }

  Future<void> addMessage(
    String sessionId,
    String role,
    String content, {
    String? source,
  }) async {
    final db = await database;
    final msg = ChatMessage(
      id: _uuid.v4(),
      sessionId: sessionId,
      role: role,
      content: content,
      source: source,
      createdAt: DateTime.now(),
    );
    await db.insert('messages', msg.toMap());
    
    // Update session timestamp
    await db.update(
      'sessions',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    _updateController.add(null);
  }

  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final db = await database;
    final maps = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return maps.map((e) => ChatMessage.fromMap(e)).toList();
  }

  Future<void> deleteMessagesFrom(String sessionId, DateTime fromDate) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'session_id = ? AND created_at >= ?',
      whereArgs: [sessionId, fromDate.millisecondsSinceEpoch],
    );
    _updateController.add(null);
  }
}
