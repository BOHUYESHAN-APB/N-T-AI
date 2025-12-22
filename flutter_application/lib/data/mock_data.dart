class Attachment {
  final String name;
  final String path;
  final int? size;
  final String? mime;

  const Attachment({required this.name, required this.path, this.size, this.mime});
}

enum ContactType { ai, human, other }

enum ChatMessageKind {
  assistant,
  user,
  sttHeard,
  pluginSummary,
  system,
  other,
}

class Contact {
  final String id;
  final String name;
  final ContactType type;
  final String? avatarEmoji; // 简易头像占位
  final bool pinned;
  final String? note;

  const Contact({
    required this.id,
    required this.name,
    required this.type,
    this.avatarEmoji,
    this.pinned = false,
    this.note,
  });

  Contact copyWith({String? name, ContactType? type, String? avatarEmoji, bool? pinned, String? note}) => Contact(
        id: id,
        name: name ?? this.name,
        type: type ?? this.type,
        avatarEmoji: avatarEmoji ?? this.avatarEmoji,
        pinned: pinned ?? this.pinned,
        note: note ?? this.note,
      );
}

class ChatMessage {
  final String id;
  final String text;
  final bool isMine;
  final String? role; // 'user', 'assistant', 'chat_normal', 'chat_sc', 'system'
  final ChatMessageKind kind;
  final String time;
  final List<Attachment> attachments;
  final String? reasoningContent;
  final List<dynamic>? toolCalls;

  ChatMessage({
    required this.id,
    required this.text,
    this.isMine = false,
    this.role,
    ChatMessageKind? kind,
    required this.time,
    List<Attachment>? attachments,
    this.reasoningContent,
    this.toolCalls,
  })  : kind = kind ?? _deriveKind(isMine: isMine, role: role),
        attachments = attachments ?? const [];

  static ChatMessageKind _deriveKind({required bool isMine, required String? role}) {
    switch (role) {
      case 'assistant':
        return ChatMessageKind.assistant;
      case 'user':
        return ChatMessageKind.user;
      case 'system':
        return ChatMessageKind.system;
      case 'chat_summary':
        return ChatMessageKind.pluginSummary;
      case 'stt_heard':
        return ChatMessageKind.sttHeard;
      default:
        return isMine ? ChatMessageKind.user : ChatMessageKind.assistant;
    }
  }
}

final List<ChatMessage> chatMessages = [
  ChatMessage(id: '1', text: '嗨！欢迎使用 N-T-AI 原型。', isMine: false, time: '09:00'),
  ChatMessage(id: '2', text: '我们现在可以聊天、笔记和发布动态。', isMine: true, time: '09:01'),
  ChatMessage(id: '3', text: '试试切换到 Notes 或 Social 页面看看。', isMine: false, time: '09:02'),
];

const List<Contact> contacts = [
  Contact(id: 'ai_local', name: '本地智能体', type: ContactType.ai, avatarEmoji: '🤖', pinned: true),
  Contact(id: 'alice', name: 'Alice', type: ContactType.human, avatarEmoji: '🧑🏻‍💻'),
  Contact(id: 'system', name: '系统助手', type: ContactType.other, avatarEmoji: '🛠️'),
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
