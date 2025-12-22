import 'package:flutter/material.dart';
import '../core/services/remote_memory_service.dart';

class MemoryManagerScreen extends StatefulWidget {
  const MemoryManagerScreen({super.key});

  @override
  State<MemoryManagerScreen> createState() => _MemoryManagerScreenState();
}

class _MemoryManagerScreenState extends State<MemoryManagerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RemoteMemoryService _memoryService = RemoteMemoryService();

  // State for Memories
  List<RemoteMemory> _memories = [];
  bool _loadingMemories = false;
  String? _memoriesError;

  // State for Jargon
  List<RemoteJargon> _jargons = [];
  bool _loadingJargons = false;
  String? _jargonsError;

  // State for Persons
  List<RemotePerson> _persons = [];
  bool _loadingPersons = false;
  String? _personsError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadMemories();
    _loadJargons();
    _loadPersons();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMemories() async {
    if (!mounted) return;
    setState(() {
      _loadingMemories = true;
      _memoriesError = null;
    });
    try {
      final memories = await _memoryService.fetchMemories();
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loadingMemories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingMemories = false;
        _memoriesError = e.toString();
      });
    }
  }

  Future<void> _loadJargons() async {
    if (!mounted) return;
    setState(() {
      _loadingJargons = true;
      _jargonsError = null;
    });
    try {
      final jargons = await _memoryService.fetchJargon();
      if (!mounted) return;
      setState(() {
        _jargons = jargons;
        _loadingJargons = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingJargons = false;
        _jargonsError = e.toString();
      });
    }
  }

  Future<void> _loadPersons() async {
    if (!mounted) return;
    setState(() {
      _loadingPersons = true;
      _personsError = null;
    });
    try {
      final persons = await _memoryService.fetchPersons();
      if (!mounted) return;
      setState(() {
        _persons = persons;
        _loadingPersons = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPersons = false;
        _personsError = e.toString();
      });
    }
  }

  Future<void> _deleteMemory(RemoteMemory memory) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记忆'),
        content: Text('确定要删除记忆 "${memory.content}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _memoryService.deleteMemory(memory.id);
        _loadMemories();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteJargon(RemoteJargon jargon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除术语'),
        content: Text('确定要删除术语 "${jargon.term}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _memoryService.deleteJargon(jargon.id);
        _loadJargons();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _deletePerson(RemotePerson person) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除人物'),
        content: Text('确定要删除人物 "${person.userId}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _memoryService.deletePerson(person.userId);
        _loadPersons();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: $e')),
          );
        }
      }
    }
  }

  void _showMemoryEditDialog({RemoteMemory? memory}) {
    final isNew = memory == null;
    final contentController = TextEditingController(text: memory?.content);
    final userIdController = TextEditingController(text: memory?.userId ?? 'default_user');
    final categoryController = TextEditingController(text: memory?.category ?? 'other');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? '新建记忆' : '编辑记忆'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isNew)
                TextField(
                  controller: userIdController,
                  decoration: const InputDecoration(labelText: '用户 ID'),
                ),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(labelText: '内容'),
                maxLines: 3,
              ),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: '类别'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final content = contentController.text.trim();
              if (content.isEmpty) return;

              try {
                if (isNew) {
                  await _memoryService.createMemory(
                    userId: userIdController.text.trim(),
                    content: content,
                    category: categoryController.text.trim(),
                  );
                } else {
                  await _memoryService.updateMemory(
                    id: memory.id,
                    content: content,
                    category: categoryController.text.trim(),
                  );
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                _loadMemories();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('保存失败: $e')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showJargonEditDialog({RemoteJargon? jargon}) {
    final isNew = jargon == null;
    final termController = TextEditingController(text: jargon?.term);
    final definitionController = TextEditingController(text: jargon?.definition);
    final exampleController = TextEditingController(text: jargon?.contextExample);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? '新建术语' : '编辑术语'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: termController,
                decoration: const InputDecoration(labelText: '术语名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: definitionController,
                decoration: const InputDecoration(labelText: '定义/解释'),
                maxLines: 3,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: exampleController,
                decoration: const InputDecoration(labelText: '用法示例'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final term = termController.text.trim();
              final definition = definitionController.text.trim();
              if (term.isEmpty) return;

              try {
                if (isNew) {
                  await _memoryService.createJargon(
                    term: term,
                    definition: definition,
                    contextExample: exampleController.text.trim(),
                  );
                } else {
                  await _memoryService.updateJargon(
                    id: jargon.id,
                    term: term,
                    definition: definition,
                    contextExample: exampleController.text.trim(),
                  );
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                _loadJargons();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('保存失败: $e')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _showPersonEditDialog({RemotePerson? person}) {
    final isNew = person == null;
    final userIdController = TextEditingController(text: person?.userId);
    final nicknameController = TextEditingController(text: person?.nickname);
    final assistantNameController = TextEditingController(text: person?.assistantName);
    final systemPromptController = TextEditingController(text: person?.systemPrompt);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isNew ? '配置人物' : '编辑人物'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: userIdController,
                decoration: const InputDecoration(labelText: 'User ID'),
                enabled: isNew,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nicknameController,
                decoration: const InputDecoration(labelText: '昵称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: assistantNameController,
                decoration: const InputDecoration(labelText: '助理名称'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: systemPromptController,
                decoration: const InputDecoration(labelText: 'System Prompt'),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final userId = userIdController.text.trim();
              if (userId.isEmpty) return;

              try {
                await _memoryService.updatePerson(
                  userId: userId,
                  nickname: nicknameController.text.trim(),
                  assistantName: assistantNameController.text.trim(),
                  systemPrompt: systemPromptController.text.trim(),
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                _loadPersons();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('保存失败: $e')),
                );
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆管理'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '记忆'),
            Tab(text: '术语'),
            Tab(text: '人物'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMemoryList(),
          _buildJargonList(),
          _buildPersonList(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          switch (_tabController.index) {
            case 0:
              _showMemoryEditDialog();
              break;
            case 1:
              _showJargonEditDialog();
              break;
            case 2:
              _showPersonEditDialog();
              break;
          }
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildMemoryList() {
    if (_loadingMemories) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_memoriesError != null) {
      return _buildErrorState(_memoriesError!, _loadMemories);
    }
    if (_memories.isEmpty) {
      return _buildEmptyState('暂无记忆');
    }

    return RefreshIndicator(
      onRefresh: _loadMemories,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _memories.length,
        itemBuilder: (context, index) {
          final memory = _memories[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text(memory.content),
              subtitle: Text(
                '用户: ${memory.userId} • 类别: ${memory.category}\n时间: ${memory.createdAt}',
                style: const TextStyle(fontSize: 12),
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showMemoryEditDialog(memory: memory),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteMemory(memory),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildJargonList() {
    if (_loadingJargons) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_jargonsError != null) {
      return _buildErrorState(_jargonsError!, _loadJargons);
    }
    if (_jargons.isEmpty) {
      return _buildEmptyState('暂无术语');
    }

    return RefreshIndicator(
      onRefresh: _loadJargons,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _jargons.length,
        itemBuilder: (context, index) {
          final jargon = _jargons[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text(jargon.term, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(jargon.definition),
                  if (jargon.contextExample != null && jargon.contextExample!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '示例: ${jargon.contextExample}',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showJargonEditDialog(jargon: jargon),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deleteJargon(jargon),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPersonList() {
    if (_loadingPersons) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_personsError != null) {
      return _buildErrorState(_personsError!, _loadPersons);
    }
    if (_persons.isEmpty) {
      return _buildEmptyState('暂无人物');
    }

    return RefreshIndicator(
      onRefresh: _loadPersons,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _persons.length,
        itemBuilder: (context, index) {
          final person = _persons[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                '${person.userId}${person.nickname != null ? " (${person.nickname})" : ""}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (person.assistantName != null)
                    Text('助理: ${person.assistantName}'),
                  if (person.systemPrompt != null)
                    Text(
                      'Prompt: ${person.systemPrompt}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  Text('感知次数: ${person.knowTimes}'),
                ],
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _showPersonEditDialog(person: person),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _deletePerson(person),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(message, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, VoidCallback onRetry) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              '加载失败',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
