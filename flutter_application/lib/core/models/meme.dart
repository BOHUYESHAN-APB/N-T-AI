import 'dart:convert';

class Meme {
  final String id;
  final String path;
  final String tags; // Description/Keywords
  final List<double> embedding;
  final int usageCount;
  final DateTime createdAt;

  Meme({
    required this.id,
    required this.path,
    required this.tags,
    required this.embedding,
    this.usageCount = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'tags': tags,
      'embedding': jsonEncode(embedding),
      'usage_count': usageCount,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  factory Meme.fromMap(Map<String, dynamic> map) {
    return Meme(
      id: map['id'],
      path: map['path'],
      tags: map['tags'],
      embedding: List<double>.from(jsonDecode(map['embedding'])),
      usageCount: map['usage_count'] ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
    );
  }
}
