class ChatMessage {
  final String id;
  final String text;
  final bool isMine;
  final String time;

  ChatMessage({required this.id, required this.text, this.isMine = false, required this.time});
}

final List<ChatMessage> chatMessages = [
  ChatMessage(id: '1', text: '嗨！欢迎使用 N-T-AI 原型。', isMine: false, time: '09:00'),
  ChatMessage(id: '2', text: '我们现在可以聊天、笔记和发布动态。', isMine: true, time: '09:01'),
  ChatMessage(id: '3', text: '试试切换到 Notes 或 Social 页面看看。', isMine: false, time: '09:02'),
];

class NoteDocument {
  final String id;
  final String title;
  final String preview;

  NoteDocument({required this.id, required this.title, required this.preview});
}

final List<NoteDocument> noteDocuments = [
  NoteDocument(id: 'n1', title: '读书笔记：去散步', preview: '今天读到一段关于专注的文字...'),
  NoteDocument(id: 'n2', title: '灵感：塔罗卡设计', preview: '尝试将二次元风格与古典元素结合...'),
];

class SocialPost {
  final String id;
  final String author;
  final String text;

  SocialPost({required this.id, required this.author, required this.text});
}

final List<SocialPost> socialPosts = [
  SocialPost(id: 'p1', author: 'Aiko', text: '今天画了一张塔罗插画，开心~'),
  SocialPost(id: 'p2', author: 'Ken', text: '分享：如何准备本地模型的环境'),
];
