import 'package:flutter/material.dart';
import '../../../settings/settings_scope.dart';
import '../../memory_manager_screen.dart';

class DataTab extends StatelessWidget {
  const DataTab({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = SettingsScope.of(context);
    final backendEnabled = settingsController.settings.enablePythonBackend;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, '记忆管理'),
        backendEnabled
            ? ListTile(
                leading: const Icon(Icons.memory),
                title: const Text('打开记忆管理页面'),
                subtitle: const Text('由 Python 后端统一管理长期记忆'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MemoryManagerScreen(),
                    ),
                  );
                },
              )
            : ListTile(
                leading: const Icon(Icons.cloud_off, color: Colors.grey),
                title: const Text(
                  '需要启用 Python 后端',
                  style: TextStyle(color: Colors.grey),
                ),
                subtitle: const Text('请在“能力”页开启后端后再尝试'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请先在“能力”页启用 Python 后端')),
                  );
                },
              ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

}
