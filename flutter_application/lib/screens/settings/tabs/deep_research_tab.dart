import 'package:flutter/material.dart';
import '../../../settings/settings.dart';
import '../../../settings/settings_scope.dart';

class DeepResearchTab extends StatelessWidget {
  const DeepResearchTab({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = SettingsScope.of(context);
    final settings = controller.settings;
    final providers = settings.providers;
    final deep = settings.deepResearch;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSectionHeader(context, '深度研究 (Deep Research)'),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.science_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '角色模型配置',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            '为规划 / 研究 / 写作分配不同的模型配置',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildRoleSelector(
                  context,
                  label: 'Planner Agent',
                  description: '负责任务拆解与策略规划',
                  value: deep.plannerProviderId,
                  providers: providers,
                  onChanged: (v) => controller.updateDeepResearchSettings(
                    deep.copyWith(plannerProviderId: v),
                  ),
                ),
                const SizedBox(height: 12),
                _buildRoleSelector(
                  context,
                  label: 'Researcher Agent',
                  description: '负责检索、分析与信息提炼',
                  value: deep.researcherProviderId,
                  providers: providers,
                  onChanged: (v) => controller.updateDeepResearchSettings(
                    deep.copyWith(researcherProviderId: v),
                  ),
                ),
                const SizedBox(height: 12),
                _buildRoleSelector(
                  context,
                  label: 'Writer Agent',
                  description: '负责报告撰写与结构化输出',
                  value: deep.writerProviderId,
                  providers: providers,
                  onChanged: (v) => controller.updateDeepResearchSettings(
                    deep.copyWith(writerProviderId: v),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.manage_search,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '研究策略配置',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const Text(
                            '控制研究的深度与广度',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                // Depth Selector
                DropdownButtonFormField<String>(
                  value: deep.searchDepth,
                  decoration: const InputDecoration(
                    labelText: '研究深度 (Search Depth)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low - 快速概览 (1-3步)')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium - 标准报告 (3-5步)')),
                    DropdownMenuItem(value: 'high', child: Text('High - 深度挖掘 (5-8步)')),
                    DropdownMenuItem(value: 'professional', child: Text('Professional - 专家综述 (迭代循环)')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      controller.updateDeepResearchSettings(
                          deep.copyWith(searchDepth: v));
                    }
                  },
                ),
                const SizedBox(height: 16),
                // Max Steps Slider
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('最大步数限制: ${deep.maxSteps}'),
                        const Tooltip(
                          message: "最大允许的思考步骤数，防止任务无限循环",
                          child: Icon(Icons.info_outline, size: 16, color: Colors.grey),
                        )
                      ],
                    ),
                    Slider(
                      value: deep.maxSteps.toDouble(),
                      min: 1,
                      max: 20,
                      divisions: 19,
                      label: deep.maxSteps.toString(),
                      onChanged: (v) => controller.updateDeepResearchSettings(
                        deep.copyWith(maxSteps: v.toInt()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSelector(
    BuildContext context, {
    required String label,
    required String description,
    required String? value,
    required List<AiProviderConfig> providers,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: value,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('跟随主脑'),
            ),
            for (final p in providers)
              DropdownMenuItem<String?>(
                value: p.id,
                child: Text('${p.name} (${p.kind.name})'),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}
