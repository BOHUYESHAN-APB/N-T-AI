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
        "Deep Research Configuration",
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
                "Configure models for specific research roles. Reuses providers from main Settings.",
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              
              // Planner
              _buildModelSelector(
                context,
                "Planner Agent",
                "Responsible for task decomposition and strategy.",
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
                "Researcher Agent",
                "Performs search, analysis, and data extraction.",
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
                "Writer Agent",
                "Generates final reports and documents.",
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
          child: const Text("Close"),
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
        child: Text("Use Default (Main Model)", style: TextStyle(color: Colors.white70)),
      ),
    ];

    for (var provider in providers) {
      // Assuming provider has models list or we just use provider ID for now.
      // Ideally we should select specific models, but for now let's select Providers.
      // If we want model granularity, we need to know models per provider.
      // Let's assume we select a "Provider Config" which usually maps to a model config in this app.
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
