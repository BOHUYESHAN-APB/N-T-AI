import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/character_service.dart';
import '../../widgets/glass.dart';

class CharacterManagerScreen extends StatefulWidget {
  const CharacterManagerScreen({Key? key}) : super(key: key);

  @override
  State<CharacterManagerScreen> createState() => _CharacterManagerScreenState();
}

class _CharacterManagerScreenState extends State<CharacterManagerScreen> {
  final CharacterService _service = CharacterService();
  List<CharacterModel> _models = [];
  bool _isLoading = true;
  String? _selectedModelPath;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final models = await _service.listModels();
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getString('settings.character.modelPath');
    
    if (mounted) {
      setState(() {
        _models = models;
        _selectedModelPath = current;
        _isLoading = false;
      });
    }
  }

  Future<void> _upload() async {
    final success = await _service.uploadModel();
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload successful')));
        _loadData();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed')));
      }
    }
  }

  Future<void> _selectModel(CharacterModel model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings.character.modelPath', model.path);
    setState(() {
      _selectedModelPath = model.path;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Selected ${model.name}')));
  }

  Future<void> _deleteModel(CharacterModel model) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Model'),
        content: Text('Are you sure you want to delete "${model.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _service.deleteModel(model.path);
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Model deleted')));
          _loadData();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete model')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Character Manager')),
      floatingActionButton: FloatingActionButton(
        onPressed: _upload,
        child: const Icon(Icons.upload),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _models.length,
              itemBuilder: (context, index) {
                final model = _models[index];
                final isSelected = model.path == _selectedModelPath;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Glass(
                    padding: const EdgeInsets.all(0),
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: Icon(Icons.person, color: isSelected ? Theme.of(context).colorScheme.primary : null),
                      title: Text(model.name),
                      subtitle: Text(model.path, style: const TextStyle(fontSize: 10)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected) const Icon(Icons.check_circle, color: Colors.green),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteModel(model),
                          ),
                        ],
                      ),
                      onTap: () => _selectModel(model),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
