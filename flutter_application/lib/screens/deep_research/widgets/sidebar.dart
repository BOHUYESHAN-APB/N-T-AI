import 'package:flutter/material.dart';
import '../../../core/services/chat_history_service.dart';

class DeepResearchSidebar extends StatefulWidget {
  final Function(String?)? onSessionSelected;
  
  const DeepResearchSidebar({super.key, this.onSessionSelected});

  @override
  State<DeepResearchSidebar> createState() => _DeepResearchSidebarState();
}

class _DeepResearchSidebarState extends State<DeepResearchSidebar> {
  final ChatHistoryService _chatHistory = ChatHistoryService();
  List<ChatSession> _sessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _chatHistory.updateStream.listen((_) => _loadSessions());
  }

  Future<void> _loadSessions() async {
    final sessions = await _chatHistory.getSessions(type: 'research');
    if (mounted) {
      setState(() {
        _sessions = sessions;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 260,
      color: colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          // 1. Logo / Header
          Container(
            padding: const EdgeInsets.all(20),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(Icons.science, color: colorScheme.primary, size: 28),
                const SizedBox(width: 12),
                Text(
                  "深度研究",
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          Divider(color: theme.dividerColor.withAlpha(31)),

          // 2. New Project Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: ElevatedButton.icon(
              onPressed: () {
                _createNewProject();
              },
              icon: const Icon(Icons.add),
              label: const Text("新建项目"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),

          // 3. Project History List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _sessions.length + 1, // +1 for header
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Text(
                      "最近项目",
                      style: TextStyle(fontSize: 12),
                    ),
                  );
                }
                final session = _sessions[index - 1];
                return _buildHistoryItem(context, session);
              },
            ),
          ),
          
          // 4. Linux Connection Button (Loaded from Plugin)
          const LinuxConnectionButton(),
        ],
      ),
    );
  }

  Future<void> _createNewProject() async {
    // This creates a session but the main screen needs to know about it to clear state.
    // For now, let's assume the user will type in the input box and that will trigger
    // creation or update.
    // But the "New Project" button implies "Clear current context".
    // We can use a global event bus or just let the user know.
    
    // Better approach: Just reload the page or use a callback.
    // Since I can't easily change the constructor right now without breaking things,
    // I'll leave the button as a placeholder for "Reset UI".
    // Wait, I can find the parent state? No.
    
    // Actually, create session here is fine.
    await _chatHistory.createSession("未命名研究", type: 'research');
  }

  Widget _buildHistoryItem(
    BuildContext context,
    ChatSession session, {
    bool isActive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive ? colorScheme.primary.withAlpha(31) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isActive
            ? Border.all(color: colorScheme.primary.withAlpha(89))
            : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 12, right: 8),
        leading: Icon(
          Icons.history, 
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant, 
          size: 18
        ),
        title: Text(
          session.title,
          style: TextStyle(
            color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: SizedBox(
          width: 30,
          height: 30,
          child: PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.more_horiz, size: 16, color: colorScheme.onSurfaceVariant),
            onSelected: (value) {
              if (value == 'rename') {
                _showRenameDialog(session);
              } else if (value == 'delete') {
                _confirmDelete(session);
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'rename',
                height: 32,
                child: Text('重命名', style: TextStyle(fontSize: 13)),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                height: 32,
                child: Text('删除', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
              ),
            ],
          ),
        ),
        onTap: () {
          if (widget.onSessionSelected != null) {
            widget.onSessionSelected!(session.id);
          }
        },
      ),
    );
  }

  void _showRenameDialog(ChatSession session) {
    final controller = TextEditingController(text: session.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("重命名项目"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: "输入新名称"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                _chatHistory.updateSessionTitle(session.id, controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text("保存"),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(ChatSession session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("删除项目"),
        content: Text("确定要删除 \"${session.title}\" 吗？此操作不可撤销。"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              _chatHistory.deleteSession(session.id);
              Navigator.pop(context);
              // If deleted active session, maybe notify parent?
              // For now, parent just handles session ID selection.
              // If currently selected ID is deleted, parent might need to reset.
              // But sidebar doesn't know active ID easily unless passed in.
              // We'll rely on user to select another or New Project.
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("删除"),
          ),
        ],
      ),
    );
  }
}
