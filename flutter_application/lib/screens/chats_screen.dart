import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../data/mock_data.dart';
import '../widgets/message_bubble.dart';
import '../widgets/simple_message_row.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../widgets/glass.dart';
import '../data/storage.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';
import '../services/ai_client.dart';
import '../services/rate_limiter.dart';
import '../data/contacts_storage.dart';
import '../data/contacts_repository.dart';
import '../theme/chat_colors.dart';
import '../plugins/plugin_manager.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({Key? key}) : super(key: key);

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}
class _ChatsScreenState extends State<ChatsScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _controller = TextEditingController();

  List<ChatMessage> _messages = [];
  List<Contact> _contacts = const [];
  late Contact _current;

  bool _aiBusy = false;
  StreamSubscription<AiChunk>? _aiSub;
  AiContactConfig? _aiCfg; // per-contact config
  bool _showDetails = false; // 右侧详情面板（默认隐藏）

  String _safeFileName(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '未命名';
    return trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<void> _exportConversation() async {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final fileName = '聊天记录_${_safeFileName(_current.name)}_$stamp.json';
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出对话日志',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null || path.isEmpty) return;

    final data = <String, dynamic>{
      'conversation': <String, dynamic>{
        'id': _current.id,
        'name': _current.name,
        'type': _current.type.name,
      },
      'exportedAt': now.toIso8601String(),
      'messages': _messages
          .map(
            (m) => <String, dynamic>{
              'id': m.id,
              'time': m.time,
              'isMine': m.isMine,
              'kind': m.kind.name,
              if (m.role != null) 'role': m.role,
              'text': m.text,
              'attachments': m.attachments
                  .map(
                    (a) => <String, dynamic>{
                      'name': a.name,
                      'path': a.path,
                      if (a.size != null) 'size': a.size,
                      if (a.mime != null) 'mime': a.mime,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    };
    final jsonText = const JsonEncoder.withIndent('  ').convert(data);
    await File(path).writeAsString(jsonText);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导出到: $path')));
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();
    globalPluginManager.ensureInitialized();
    // 初始加载联系人与会话
    _initContacts();
  }

  Future<void> _initContacts() async {
    final list = await ContactsRepository.load();
    final sorted = ContactsRepository.sortDisplay(list);
    setState(() {
      _contacts = sorted;
      _current = sorted.isNotEmpty ? sorted.first : const Contact(id: 'default', name: '默认', type: ContactType.other);
    });
    // 加载当前联系人的 AI 专属配置
    _aiCfg = await ContactsStorage.loadAiConfig(_current.id);
    // 加载会话
    await _loadFor(_current);
  }

  Future<void> _loadFor(Contact c) async {
    final list = await ChatStorage.loadMessagesFor(c.id);
    if (!mounted) return;
    setState(() => _messages = list);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _aiSub?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_aiBusy) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final userMsg = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      text: text,
      isMine: true,
      time: '$hh:$mm',
    );
    setState(() {
      _messages.add(userMsg);
      _controller.clear();
    });
    await ChatStorage.saveMessagesFor(_current.id, _messages);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    if (_current.type == ContactType.ai) {
      await _sendToAi();
    }
  }

  Future<void> _sendToAi() async {
    final ctrl = SettingsScope.of(context);
    final picked = ctrl.selectProviderForNextCall();
    if (picked == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('没有可用的 AI 平台，请在系统设置中添加或启用')));
      return;
    }
    final settings = ctrl.resolveFromConfig(picked);
    // 构造对话历史
    final List<AiMessage> msgs = [];
    if (_aiCfg?.systemPrompt != null && _aiCfg!.systemPrompt!.isNotEmpty) {
      msgs.add(AiMessage(role: 'system', content: _aiCfg!.systemPrompt!));
    }
    for (final m in _messages) {
      if (m.text.isEmpty) continue; // 忽略纯附件消息
      msgs.add(AiMessage(role: m.isMine ? 'user' : 'assistant', content: m.text));
    }

    // 先插入一个空的助手消息，随后逐步填充
    final assistantId = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _aiBusy = true;
      _messages.add(ChatMessage(id: assistantId, text: '', isMine: false, time: '')); // time 可在结束时更新
    });
    final aiIndex = _messages.length - 1;
    try {
      // 限速（如果设置了 rpm）— 已移除 rpm 字段，按默认限速策略
      await RateLimiterManager.instance.waitIfNeeded(picked.id);
      final stream = AiClient.streamChatEvents(
        ai: settings,
        messages: msgs,
        modelOverride: _aiCfg?.model,
        baseUrlIsRoot: picked.isRoot,
        userId: _current.id,
      );
      // 计数一次请求
      RateLimiterManager.instance.record(picked.id);
      _aiSub?.cancel();
      _aiSub = stream.listen((chunk) {
        if (!mounted) return;
        setState(() {
          final cur = _messages[aiIndex];
          String newText = cur.text;
          String? newReasoning = cur.reasoningContent;

          if (chunk.content != null) {
            newText += chunk.content!;
          }
          if (chunk.reasoning != null) {
            newReasoning = (newReasoning ?? '') + chunk.reasoning!;
          }

          _messages[aiIndex] = ChatMessage(
            id: cur.id,
            text: newText,
            isMine: false,
            time: cur.time,
            reasoningContent: newReasoning,
          );
        });
      }, onDone: () async {
        if (!mounted) return;
        final end = DateTime.now();
        final hh = end.hour.toString().padLeft(2, '0');
        final mm = end.minute.toString().padLeft(2, '0');
        setState(() {
          _aiBusy = false;
          final cur = _messages[aiIndex];
          _messages[aiIndex] = ChatMessage(
            id: cur.id,
            text: cur.text,
            isMine: false,
            time: '$hh:$mm',
            reasoningContent: cur.reasoningContent,
          );
        });
        await ChatStorage.saveMessagesFor(_current.id, _messages);
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        _aiSub = null;
      }, onError: (e) async {
        if (!mounted) return;
        setState(() {
          _aiBusy = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI 响应失败: $e')));
        _aiSub = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI 发送失败: $e')));
    }
  }

  void _cancelAi() {
    _aiSub?.cancel();
    _aiSub = null;
    setState(() => _aiBusy = false);
  }

  Future<void> _pickAttachments() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null || result.files.isEmpty) return;
      final files = result.files;
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      setState(() {
        _messages.add(ChatMessage(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          text: _controller.text.trim(),
          isMine: true,
          time: '$hh:$mm',
          attachments: files
              .map((f) => Attachment(
                    name: f.name,
                    path: f.path ?? '',
                    size: f.size,
                    mime: f.extension != null ? '.${f.extension}' : null,
                  ))
              .toList(),
        ));
        _controller.clear();
      });
      ChatStorage.saveMessagesFor(_current.id, _messages);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择附件失败: $e')),
      );
    }
  }

  // 小工具：联系人类型徽标
  Widget _contactBadge(Contact c) {
    final theme = Theme.of(context);
    final chat = Theme.of(context).extension<ChatColors>();
    Color bg;
    String label;
    switch (c.type) {
      case ContactType.ai:
        bg = chat?.badgeBg ?? theme.colorScheme.primary.withValues(alpha: 0.1);
        label = 'AI';
        break;
      case ContactType.human:
        bg = chat?.badgeBg ?? theme.colorScheme.tertiary.withValues(alpha: 0.12);
        label = '真人';
        break;
      default:
        bg = chat?.badgeBg ?? theme.colorScheme.secondary.withValues(alpha: 0.12);
        label = '其他';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: chat?.badgeText ?? theme.colorScheme.onSurface, fontSize: 12)),
    );
  }

  // 新建联系人对话框，返回更新后的联系人列表
  Future<List<Contact>?> _createContactDialog(BuildContext ctx) async {
    final nameCtl = TextEditingController();
    ContactType type = ContactType.human;
    String emoji = '👤';
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: const Text('新建联系人'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('类型：'),
                const SizedBox(width: 8),
                DropdownButton<ContactType>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: ContactType.ai, child: Text('AI')),
                    DropdownMenuItem(value: ContactType.human, child: Text('真人')),
                    DropdownMenuItem(value: ContactType.other, child: Text('其他')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      type = v;
                    }
                  },
                ),
                const Spacer(),
                TextButton(
                  onPressed: () async {
                    final picked = await showModalBottomSheet<String>(
                      context: dctx,
                      showDragHandle: true,
                      builder: (ctx2) {
                        final emojis = _commonEmojis;
                        final cross = MediaQuery.of(ctx2).size.width ~/ 44;
                        return SizedBox(
                          height: 300,
                          child: GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cross.clamp(6, 10),
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                            itemCount: emojis.length,
                            itemBuilder: (c, i) => InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.pop(c, emojis[i]),
                              child: Center(child: Text(emojis[i], style: const TextStyle(fontSize: 22))),
                            ),
                          ),
                        );
                      },
                    );
                    if (picked != null) {
                      emoji = picked;
                    }
                  },
                  child: Text('头像 $emoji'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('创建')),
        ],
      ),
    );
    if (ok == true) {
      final id = 'c_${DateTime.now().millisecondsSinceEpoch}';
      final newContact = Contact(id: id, name: nameCtl.text.trim().isEmpty ? '新联系人' : nameCtl.text.trim(), type: type, avatarEmoji: emoji);
      final updated = [..._contacts, newContact];
      await ContactsRepository.save(updated);
      return updated;
    }
    return null;
  }

  Future<void> _pickContact() async {
    final selected = await showModalBottomSheet<Contact>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final all = _contacts;
        final controller = TextEditingController();
        ContactType? filter; // null=全部
        List<Contact> filtered = all;
        void apply() {
          final kw = controller.text.trim().toLowerCase();
          filtered = all.where((c) {
            final typeOk = filter == null || c.type == filter;
            final kwOk = kw.isEmpty || c.name.toLowerCase().contains(kw);
            return typeOk && kwOk;
          }).toList();
        }
        apply();
        return StatefulBuilder(builder: (ctx, setS) {
          Widget chip(ContactType? t, String label) {
            final selected = filter == t;
            final th = Theme.of(ctx);
            final bg = th.colorScheme.surfaceVariant.withValues(alpha: th.brightness == Brightness.dark ? 0.35 : 0.9);
            final sel = th.colorScheme.primaryContainer;
            final txt = selected ? th.colorScheme.onPrimaryContainer : th.colorScheme.onSurface;
            return ChoiceChip(
              label: Text(label, style: TextStyle(color: txt)),
              selected: selected,
              backgroundColor: bg,
              selectedColor: sel,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: th.dividerColor.withValues(alpha: 0.2)),
              onSelected: (_) => setS(() {
                filter = t;
                apply();
              }),
            );
          }
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('联系人', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search),
                            hintText: '搜索联系人…',
                          ),
                          onChanged: (_) => setS(() {
                            apply();
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () async {
                          final created = await _createContactDialog(ctx);
                          if (created != null) {
                            setState(() {
                              _contacts = ContactsRepository.sortDisplay(created);
                            });
                            setS(() {
                              apply();
                            });
                          }
                        },
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('新建'),
                      )
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    chip(null, '全部'),
                    chip(ContactType.ai, 'AI'),
                    chip(ContactType.human, '真人'),
                    chip(ContactType.other, '其他'),
                  ]),
                  const Divider(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in filtered)
                          ListTile(
                            leading: Text(c.avatarEmoji ?? '👤', style: const TextStyle(fontSize: 20)),
                            title: Text(c.name),
                            subtitle: c.note == null ? null : Text(c.note!),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _contactBadge(c),
                                IconButton(
                                  tooltip: c.pinned ? '取消置顶' : '置顶',
                                  icon: Icon(c.pinned ? Icons.push_pin : Icons.push_pin_outlined),
                                  onPressed: () async {
                                    final updated = [..._contacts];
                                    final idx = updated.indexWhere((x) => x.id == c.id);
                                    if (idx != -1) {
                                      updated[idx] = updated[idx].copyWith(pinned: !updated[idx].pinned);
                                      await ContactsRepository.save(updated);
                                      setState(() => _contacts = ContactsRepository.sortDisplay(updated));
                                      setS(() => apply());
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: '删除',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (dctx) => AlertDialog(
                                        title: const Text('删除联系人'),
                                        content: const Text('同时删除该联系人的会话记录，确定删除？'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('取消')),
                                          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('删除')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      final updated = [..._contacts]..removeWhere((x) => x.id == c.id);
                                      await ContactsRepository.save(updated);
                                      await ChatStorage.removeConversation(c.id);
                                      setState(() => _contacts = ContactsRepository.sortDisplay(updated));
                                      setS(() => apply());
                                      if (_current.id == c.id && _contacts.isNotEmpty) {
                                        setState(() {
                                          _current = _contacts.first;
                                        });
                                        _loadFor(_current);
                                      }
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () => Navigator.of(ctx).pop(c),
                          ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        });
      },
    );
    if (selected != null) {
      final cfg = await ContactsStorage.loadAiConfig(selected.id);
      setState(() {
        _current = selected;
        _aiCfg = cfg;
      });
      _loadFor(_current);
    }
  }

  Future<void> _openAiConfig() async {
    if (_current.type != ContactType.ai) return;
    final modelCtl = TextEditingController(text: _aiCfg?.model ?? '');
    final promptCtl = TextEditingController(text: _aiCfg?.systemPrompt ?? '');
    final updated = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AI 对话设置（仅当前联系人）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtl,
                decoration: const InputDecoration(labelText: '模型覆盖（可选）', hintText: '如 gpt-4o, llama3.1:8b, qwen2.5'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtl,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: '系统提示（可选）', hintText: '为此 AI 联系人设置专属系统 Prompt'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('保存'),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    if (updated == true) {
      final cfg = AiContactConfig(
        model: modelCtl.text.trim().isEmpty ? null : modelCtl.text.trim(),
        systemPrompt: promptCtl.text.trim().isEmpty ? null : promptCtl.text.trim(),
      );
      await ContactsStorage.saveAiConfig(_current.id, cfg);
      if (!mounted) return;
      setState(() => _aiCfg = cfg);
    }
  }

  void _showEmojiPanel() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (ctx) {
        final emojis = _commonEmojis;
        final crossAxisCount = MediaQuery.of(ctx).size.width ~/ 44; // approx size
        return SizedBox(
          height: 300,
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount.clamp(6, 10),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: emojis.length,
            itemBuilder: (context, i) {
              final e = emojis[i];
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).pop(e),
                child: Center(
                  child: Text(e, style: const TextStyle(fontSize: 24)),
                ),
              );
            },
          ),
        );
      },
    );
    if (picked != null) _insertEmoji(picked);
  }

  void _insertEmoji(String emoji) {
    final sel = _controller.selection;
    final text = _controller.text;
    if (!sel.isValid) {
      _controller.text += emoji;
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
      return;
    }
    final start = sel.start;
    final end = sel.end;
    final newText = text.replaceRange(start, end, emoji);
    _controller.text = newText;
    final newPos = start + emoji.length;
    _controller.selection = TextSelection.fromPosition(TextPosition(offset: newPos));
  }
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWide = size.width >= 900;
    final isThreePane = size.width >= 1100; // 类似微信的三段式布局
    final settings = SettingsScope.of(context).settings;
    if (_contacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 移除：本地函数 _pickContact，改为使用类方法 _pickContact

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Glass(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _showDetails = !_showDetails),
              child: Tooltip(
                message: _showDetails ? '隐藏详情' : '显示详情',
                child: CircleAvatar(child: Text(_current.avatarEmoji ?? '👤')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_current.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  _contactBadge(_current),
                ],
              ),
            ),
            IconButton(
              onPressed: _pickContact,
              tooltip: '切换对话对象',
              icon: const Icon(Icons.switch_account),
            ),
            if (_current.type == ContactType.ai)
              IconButton(
                onPressed: _openAiConfig,
                tooltip: 'AI 设置',
                icon: const Icon(Icons.tune_outlined),
              ),
            IconButton(
              onPressed: _exportConversation,
              tooltip: '导出对话日志',
              icon: const Icon(Icons.file_download_outlined),
            ),
          ],
        ),
      ),
    );

    final inputBar = SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(isWide ? 16 : 12, 6, isWide ? 16 : 12, 12),
        child: Glass(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          borderRadius: BorderRadius.circular(28),
          child: Row(
            children: [
              // Emoji 面板
              IconButton(
                tooltip: '表情',
                onPressed: _showEmojiPanel,
                icon: const Icon(Icons.emoji_emotions_outlined),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '说点什么…',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              // 附件选择
              IconButton(
                tooltip: '附件',
                onPressed: _pickAttachments,
                icon: const Icon(Icons.attach_file),
              ),
              SizedBox(
                height: 44,
                width: 44,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                  ),
                  onPressed: _aiBusy ? _cancelAi : _send,
                  child: _aiBusy
                      ? const Icon(Icons.stop_circle_outlined)
                      : const Icon(Icons.send_rounded),
                ),
              )
            ],
          ),
        ),
      ),
    );

    final bg = switch (settings.chatBg) {
      // 即便用户保留旧设置的 lavender，也替换为更素雅的淡灰渐变
      ChatBgOption.lavender => const LinearGradient(
          colors: [Color(0xFFF7F8F9), Color(0xFFF0F1F2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ChatBgOption.none => null,
    };

    final basePadding = switch (settings.density) {
      DensityOption.compact => const EdgeInsets.fromLTRB(8, 8, 8, 0),
      DensityOption.normal => const EdgeInsets.fromLTRB(12, 12, 12, 0),
      DensityOption.spacious => const EdgeInsets.fromLTRB(18, 18, 18, 0),
    };

    bool _shouldUseBubbleUI() {
      final mode = settings.uiMode;
      if (mode == UIModeOption.bubble) return true;
      if (mode == UIModeOption.simple) return false;
      // Auto: 轻量级判断
      final platform = defaultTargetPlatform;
      final mq = MediaQuery.of(context);
      final shortest = mq.size.shortestSide;
      final dpr = mq.devicePixelRatio;
      final isDesktop = platform == TargetPlatform.windows || platform == TargetPlatform.linux || platform == TargetPlatform.macOS;
      if (isDesktop) return true; // 桌面默认气泡
      if (kIsWeb) return mq.size.width >= 600; // Web 小屏降级
      final isMobile = platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      if (isMobile) {
        // 低分屏 + 极小屏走简洁模式，其余走气泡
        final lowEnd = (dpr <= 1.0 && shortest < 360) || shortest < 320;
        return !lowEnd;
      }
      return true;
    }

    Widget _animated(Widget child, String keyId) {
      return TweenAnimationBuilder<double>(
        key: ValueKey(keyId),
        tween: Tween(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        builder: (c, v, _) => Opacity(
          opacity: ((v - 0.9) * 10).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child),
        ),
      );
    }

    final useBubble = _shouldUseBubbleUI();

    if (!isThreePane) {
      return Container(
        decoration: bg == null ? null : BoxDecoration(gradient: bg),
        child: Column(
          children: [
            header,
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: basePadding,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  final child = GestureDetector(
                    onLongPress: () => _showMessageMenu(context, msg, index),
                    onSecondaryTapDown: (d) => _showMessageMenu(context, msg, index, position: d.globalPosition),
                    child: useBubble ? MessageBubble(message: msg) : SimpleMessageRow(message: msg),
                  );
                  return _animated(child, msg.id);
                },
              ),
            ),
            inputBar,
          ],
        ),
      );
    }

    // 三段式：左（联系人）- 中（消息）- 右（信息）
    final searchCtl = TextEditingController();
    ContactType? filter;
    List<Contact> filtered() {
      final kw = searchCtl.text.trim().toLowerCase();
      return _contacts.where((c) {
        final typeOk = filter == null || c.type == filter;
        final kwOk = kw.isEmpty || c.name.toLowerCase().contains(kw);
        return typeOk && kwOk;
      }).toList();
    }

    Widget leftPane() => Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Glass(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: searchCtl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索联系人…',
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<ContactType?>(
                    tooltip: '筛选',
                    icon: const Icon(Icons.filter_list),
                    onSelected: (v) => setState(() => filter = v),
                    itemBuilder: (c) => [
                      CheckedPopupMenuItem(
                        value: null,
                        checked: filter == null,
                        child: const Text('全部'),
                      ),
                      CheckedPopupMenuItem(
                        value: ContactType.ai,
                        checked: filter == ContactType.ai,
                        child: const Text('AI'),
                      ),
                      CheckedPopupMenuItem(
                        value: ContactType.human,
                        checked: filter == ContactType.human,
                        child: const Text('真人'),
                      ),
                      CheckedPopupMenuItem(
                        value: ContactType.other,
                        checked: filter == ContactType.other,
                        child: const Text('其他'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    children: [
                      for (final c in filtered())
                        ListTile(
                          leading: Text(c.avatarEmoji ?? '👤', style: const TextStyle(fontSize: 20)),
                          title: Text(c.name, overflow: TextOverflow.ellipsis),
                          trailing: _contactBadge(c),
                          selected: _current.id == c.id,
                          onTap: () async {
                            final cfg = await ContactsStorage.loadAiConfig(c.id);
                            setState(() {
                              _current = c;
                              _aiCfg = cfg;
                            });
                            _loadFor(_current);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    Widget centerPane() => Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 6, 12),
          child: Column(
            children: [
              header,
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: basePadding,
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final child = GestureDetector(
                      onLongPress: () => _showMessageMenu(context, msg, index),
                      onSecondaryTapDown: (d) => _showMessageMenu(context, msg, index, position: d.globalPosition),
                      child: useBubble ? MessageBubble(message: msg) : SimpleMessageRow(message: msg),
                    );
                    return _animated(child, msg.id);
                  },
                ),
              ),
              inputBar,
            ],
          ),
        );

    Widget rightPane() => Padding(
          padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
          child: Glass(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('详情'),
                const SizedBox(height: 8),
                Row(children: [
                  CircleAvatar(child: Text(_current.avatarEmoji ?? '👤')),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_current.name, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
                const SizedBox(height: 8),
                _contactBadge(_current),
                const SizedBox(height: 12),
                if (_current.type == ContactType.ai)
                  FilledButton.tonal(
                    onPressed: _openAiConfig,
                    child: const Text('AI 设置'),
                  ),
              ],
            ),
          ),
        );

    return Container(
      decoration: bg == null ? null : BoxDecoration(gradient: bg),
      child: Row(
        children: [
          SizedBox(width: 260, child: leftPane()),
          Expanded(child: centerPane()),
          if (_showDetails) SizedBox(width: 300, child: rightPane()),
        ],
      ),
    );
  }

  void _showMessageMenu(BuildContext context, ChatMessage msg, int index, {Offset? position}) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = position ?? overlay.size.center(Offset.zero);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'copy', child: Text('复制')),
        PopupMenuItem(value: 'delete', child: Text('删除')),
      ],
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'copy':
        final content = msg.text.isNotEmpty
            ? msg.text
            : (msg.attachments.isNotEmpty ? msg.attachments.map((e) => e.name).join(', ') : '');
        if (content.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: content));
        }
        break;
      case 'delete':
        setState(() {
          _messages.removeAt(index);
        });
        ChatStorage.saveMessagesFor(_current.id, _messages);
        break;
    }
  }
}

const List<String> _commonEmojis = [
  '😀','😃','😄','😁','😆','🥹','🥳','😉','😊','😇','🙂','🙃','😋','😌','😍','🥰','😘','😗','😙','😚',
  '😜','🤪','😝','🫠','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😶‍🌫️','🙄','😏','😣','😥','😮','🤤',
  '😪','😫','😴','😌','😛','😓','😕','🙁','☹️','😟','😢','😭','😤','😠','😡','🤬','🤯','😳','🥺','😬',
  '🤝','👍','👎','👏','🙏','💪','🫶','🤝','💯','🔥','✨','🎉','🥂','🍻','🍺','🍵','🍫','🍕','🍔','🍟','🍰','🍜','🍎','🍇',
  '📎','📁','🖼️','🎵','🎬','📄','🗂️','🗜️','🧪','⚙️','🧭','💡','🧠','📌','📍'
];
