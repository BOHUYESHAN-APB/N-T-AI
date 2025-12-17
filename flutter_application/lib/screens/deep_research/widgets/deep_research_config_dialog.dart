import 'package:flutter/material.dart';
import '../../../../settings/settings.dart';
import '../../../../settings/settings_scope.dart';

class DeepResearchConfigDialog extends StatelessWidget {
  const DeepResearchConfigDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsController = SettingsScope.of(context);
    final settings = settingsController.settings;
    final providers = settings.providers;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E2E),
      title: const Text(
        "深度研究配置",
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "为特定研究角色配置模型。将复用主设置中的提供商配置。",
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              
              // Planner
              _buildModelSelector(
                context,
                "Planner Agent (规划者)",
                "负责任务拆解与策略规划。",
                settings.deepResearch.plannerProviderId,
                providers,
                (val) {
                  settingsController.updateDeepResearchSettings(
                    settings.deepResearch.copyWith(plannerProviderId: val),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Researcher
              _buildModelSelector(
                context,
                "Researcher Agent (研究员)",
                "负责执行搜索、分析与数据提取。",
                settings.deepResearch.researcherProviderId,
                providers,
                (val) {
                  settingsController.updateDeepResearchSettings(
                    settings.deepResearch.copyWith(researcherProviderId: val),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Writer
              _buildModelSelector(
                context,
                "Writer Agent (作家)",
                "负责生成最终报告与文档。",
                settings.deepResearch.writerProviderId,
                providers,
                (val) {
                  settingsController.updateDeepResearchSettings(
                    settings.deepResearch.copyWith(writerProviderId: val),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("关闭"),
        ),
      ],
    );
  }

  Widget _buildModelSelector(
    BuildContext context,
    String label,
    String desc,
    String? selectedId,
    List<AiProviderConfig> providers,
    ValueChanged<String?> onChanged,
  ) {
    // Flatten models list
    final List<DropdownMenuItem<String>> items = [
      const DropdownMenuItem(
        value: null,
        child: Text("使用默认 (跟随主脑)", style: TextStyle(color: Colors.white70)),
      ),
    ];

    for (var provider in providers) {
      items.add(DropdownMenuItem(
        value: provider.id,
        child: Text(
          "${provider.name} (${provider.kind.name})",
          style: const TextStyle(color: Colors.white),
          overflow: TextOverflow.ellipsis,
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedId,
              isExpanded: true,
              dropdownColor: const Color(0xFF2A2A35),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
