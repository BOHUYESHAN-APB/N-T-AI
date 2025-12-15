import 'package:flutter/material.dart';

import '../plugins/plugin_manager.dart';

class PluginDashboardColumn extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: globalPluginManager,
      builder: (context, _) {
        final widgets = globalPluginManager.enabledPlugins
            .map((p) => p.buildDashboardWidget(context))
            .whereType<Widget>()
            .toList();

        if (widgets.isEmpty) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(8, 80, 8, 8),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).dividerColor.withOpacity(0.08),
              ),
            ),
          ),
          child: ListView(
            children: widgets
                .map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: w,
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}
