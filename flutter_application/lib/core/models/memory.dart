class Memory {
  final String id;
  final String content;
  final String category; // preference, identity, experience, plan, other
  final List<double> embedding;
  final DateTime createdAt;
  final double importance;

  Memory({
    required this.id,
    required this.content,
    required this.category,
    required this.embedding,
    required this.createdAt,
    this.importance = 1.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'content': content,
      'category': category,
      'embedding': embedding.join(','), // Simple serialization
      'created_at': createdAt.millisecondsSinceEpoch,
      'importance': importance,
    };
  }

  factory Memory.fromMap(Map<String, dynamic> map) {
    final embeddingStr = map['embedding'] as String;
    List<double> embeddingList = [];
    if (embeddingStr.isNotEmpty) {
      try {
        embeddingList = embeddingStr.split(',').map((e) => double.tryParse(e) ?? 0.0).toList();
      } catch (e) {
        // Ignore parse errors
      }
    }
    
    return Memory(
      id: map['id'],
      content: map['content'],
      category: map['category'],
      embedding: embeddingList,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      importance: map['importance'],
    );
  }
}
