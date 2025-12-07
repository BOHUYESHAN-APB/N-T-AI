import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/services/memory_service.dart';
import '../../../settings/settings_scope.dart';
import '../../memory_remote_manager_screen.dart';

class DataTab extends StatelessWidget {
  const DataTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final memoryService = MemoryService();
    final settingsController = SettingsScope.of(context);
    final backendEnabled = settingsController.settings.enablePythonBackend;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, '本地记忆数据库 (SQLite)'),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('导出本地备份'),
          subtitle: const Text('将本地记忆数据库导出为 .db 文件 (不包含 Python 后端数据)'),
          onTap: () => _exportDatabase(context, memoryService),
        ),
        ListTile(
          leading: const Icon(Icons.download),
          title: const Text('恢复本地备份'),
          subtitle: const Text('从 .db 文件恢复本地记忆 (将覆盖当前本地数据)'),
          onTap: () => _importDatabase(context, memoryService),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.delete_forever, color: Colors.red),
          title: const Text('清空本地记忆', style: TextStyle(color: Colors.red)),
          subtitle: const Text('此操作不可逆，仅删除本地存储的记忆'),
          onTap: () => _confirmClear(context, memoryService),
        ),
        const SizedBox(height: 24),
        _buildSectionHeader(context, 'Python 后端记忆'),
        backendEnabled
            ? ListTile(
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('管理后端记忆'),
                subtitle: const Text('在应用内直接查看、编辑、删除服务器记忆'),
                trailing: const Icon(Icons.open_in_new),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RemoteMemoryManagerScreen(),
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

  Future<void> _exportDatabase(
    BuildContext context,
    MemoryService service,
  ) async {
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: '选择保存位置',
        fileName:
            'astra_memory_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.db',
        type: FileType.any,
      );

      if (outputFile != null) {
        await service.backupTo(outputFile);
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('备份成功: $outputFile')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _importDatabase(
    BuildContext context,
    MemoryService service,
  ) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认恢复'),
            content: const Text('恢复备份将覆盖当前所有记忆数据，且不可撤销。确定要继续吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('覆盖恢复'),
              ),
            ],
          ),
        );

        if (confirm == true) {
          await service.restoreFrom(path);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('恢复成功，请重启应用以确保数据加载正确')),
            );
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmClear(
    BuildContext context,
    MemoryService service,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空本地记忆'),
        content: const Text('确定要删除所有本地记忆吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await service.clearAll();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('本地记忆已清空')));
      }
    }
  }
}
