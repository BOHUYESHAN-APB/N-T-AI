import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/services/remote_memory_service.dart';

class RemoteMemoryManagerScreen extends StatefulWidget {
  const RemoteMemoryManagerScreen({super.key});

  @override
  State<RemoteMemoryManagerScreen> createState() =>
      _RemoteMemoryManagerScreenState();
}

class _RemoteMemoryManagerScreenState extends State<RemoteMemoryManagerScreen> {
  final RemoteMemoryService _service = RemoteMemoryService();
  final DateFormat _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  List<RemoteMemory> _memories = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.fetchMemories(limit: 100);
      if (!mounted) return;
      setState(() {
        _memories = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _showEditDialog({RemoteMemory? memory}) async {
    final userController = TextEditingController(
      text: memory?.userId ?? 'default_user',
    );
    final contentController = TextEditingController(
      text: memory?.content ?? '',
    );
    final categoryController = TextEditingController(
      text: memory?.category ?? 'other',
    );
    final scopeController = TextEditingController(
      text: memory?.scope ?? 'long_term',
    );
    final sourceController = TextEditingController(
      text: memory?.source ?? '',
    );
    final weightController = TextEditingController(
      text: (memory?.weight ?? 1.0).toString(),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(memory == null ? '新增记忆' : '编辑记忆 #${memory.id}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userController,
                decoration: const InputDecoration(labelText: 'User ID'),
              ),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: '类别'),
              ),
              TextField(
                controller: scopeController,
                decoration: const InputDecoration(labelText: '范围 (scope)'),
              ),
              TextField(
                controller: sourceController,
                decoration: const InputDecoration(labelText: '来源 (source)'),
              ),
              TextField(
                controller: weightController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '权重'),
              ),
              TextField(
                controller: contentController,
                maxLines: 5,
                decoration: const InputDecoration(labelText: '内容'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(memory == null ? '创建' : '保存'),
          ),
        ],
      ),
    );

    if (result != true) return;

    try {
      final weight = double.tryParse(weightController.text) ?? 1.0;
      final scopeValue = scopeController.text.trim();
      final sourceValue = sourceController.text.trim();
      if (memory == null) {
        await _service.createMemory(
          userId: userController.text.trim(),
          content: contentController.text.trim(),
          category: categoryController.text.trim(),
          scope: scopeValue.isNotEmpty ? scopeValue : 'long_term',
          source: sourceValue.isNotEmpty ? sourceValue : null,
          weight: weight,
        );
      } else {
        await _service.updateMemory(
          id: memory.id,
          content: contentController.text.trim(),
          category: categoryController.text.trim(),
          scope: scopeValue.isNotEmpty ? scopeValue : null,
          source: sourceValue.isNotEmpty ? sourceValue : null,
          weight: weight,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(memory == null ? '创建成功' : '更新成功')));
      await _loadMemories();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteMemory(RemoteMemory memory) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除记忆 #${memory.id}?'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.deleteMemory(memory.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('删除成功')));
      await _loadMemories();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('后端记忆管理'),
        actions: [
          IconButton(onPressed: _loadMemories, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadMemories,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _memories.length,
                itemBuilder: (context, index) {
                  final memory = _memories[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          memory.category.isNotEmpty
                              ? memory.category[0].toUpperCase()
                              : '?',
                        ),
                      ),
                      title: Text(
                        memory.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '用户: ${memory.userId} | 类别: ${memory.category} | 范围: ${memory.scope} | 权重: ${memory.weight.toStringAsFixed(1)}',
                          ),
                          if (memory.source != null && memory.source!.isNotEmpty)
                            Text('来源: ${memory.source}'),
                          Text('创建: ${_dateFormat.format(memory.createdAt)}'),
                        ],
                      ),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showEditDialog(memory: memory),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            onPressed: () => _deleteMemory(memory),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(_error ?? '未知错误', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadMemories, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
