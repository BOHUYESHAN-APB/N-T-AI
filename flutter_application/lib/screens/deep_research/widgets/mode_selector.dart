import 'package:flutter/material.dart';

class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            "Use massive tools to complete various tasks",
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 40),
          Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              _buildModeCard(context, Icons.auto_awesome, "General", colorScheme.primary, isSelected: true),
              _buildModeCard(context, Icons.description, "Document", colorScheme.secondary),
              _buildModeCard(context, Icons.slideshow, "PPT Mode", colorScheme.tertiary),
              _buildModeCard(context, Icons.table_chart, "Excel Mode", Colors.green),
              _buildModeCard(context, Icons.language, "Web Mode", Colors.purpleAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(
    BuildContext context,
    IconData icon,
    String label,
    Color color, {
    bool isSelected = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? color : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
