import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/memory_service.dart';
import '../core/models/memory.dart';
import '../settings/settings_scope.dart';
import 'memory_remote_manager_screen.dart';

class MemoryManagerScreen extends StatefulWidget {
  final String? heroTag;
  const MemoryManagerScreen({Key? key, this.heroTag}) : super(key: key);

  @override
  State<MemoryManagerScreen> createState() => _MemoryManagerScreenState();
}

class _MemoryManagerScreenState extends State<MemoryManagerScreen> {
  final MemoryService _memoryService = MemoryService();
  List<Memory> _memories = [];
  bool _isLoading = true;
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _loadMemories();
    _subscription = _memoryService.updateStream.listen((_) {
      if (mounted) _loadMemories();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _loadMemories() async {
    // Don't show loading spinner for background updates to avoid flickering
    // setState(() => _isLoading = true); 
    final db = await _memoryService.database;
    final List<Map<String, dynamic>> maps = await db.query('memories', orderBy: 'created_at DESC');
    if (mounted) {
      setState(() {
        _memories = maps.map((e) => Memory.fromMap(e)).toList();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteMemory(String id) async {
    await _memoryService.deleteMemory(id);
    // _loadMemories is called automatically via stream
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清除'),
        content: const Text('确定要删除所有记忆吗？此操作不可恢复。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirm == true) {
      await _memoryService.clearAll();
    }
  }

  Future<void> _addMemory() async {
    final controller = TextEditingController();
    final categoryController = TextEditingController(text: 'other');
    
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: '记忆内容', hintText: '例如：用户喜欢吃苹果'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: '分类 (preference, identity, etc.)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _memoryService.saveMemory(controller.text, categoryController.text);
                if (mounted) Navigator.pop(context);
                // _loadMemories(); // Handled by stream
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _openRemoteMemoryManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RemoteMemoryManagerScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context).settings;
    final isBackendEnabled = settings.enablePythonBackend;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理'),
        actions: [
          if (isBackendEnabled)
            TextButton.icon(
              onPressed: _openRemoteMemoryManager,
              icon: const Icon(Icons.cloud_sync_outlined),
              label: const Text('Python后端管理'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.primary),
            ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: '一键清除',
            onPressed: _clearAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: widget.heroTag ?? 'memory_fab',
        onPressed: _addMemory,
        child: const Icon(Icons.add),
        tooltip: '快速添加',
      ),
      body: Column(
        children: [
          if (isBackendEnabled)
            Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前已启用 Python 后端。下方的列表仅显示本地缓存的记忆。要管理后端的高级记忆（如长期记忆、向量库），请点击右上角的“Python后端管理”。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _memories.isEmpty
                    ? const Center(child: Text('暂无记忆'))
                    : ListView.builder(
                        itemCount: _memories.length,
                        itemBuilder: (context, index) {
                          final memory = _memories[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            child: ListTile(
                              title: Text(memory.content),
                              subtitle: Text('${memory.category} · ${memory.createdAt.toString().split('.')[0]}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteMemory(memory.id),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
