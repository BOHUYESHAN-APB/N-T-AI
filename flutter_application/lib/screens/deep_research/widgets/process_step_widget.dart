import 'package:flutter/material.dart';

class ProcessStepWidget extends StatelessWidget {
  final int stepNumber;
  final String title;
  final String description;
  final String status; // "pending", "running", "completed", "failed"
  final List<String>? logs;

  const ProcessStepWidget({
    super.key,
    required this.stepNumber,
    required this.title,
    required this.description,
    this.status = "pending",
    this.logs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case "running":
        statusColor = colorScheme.primary;
        statusIcon = Icons.sync;
        break;
      case "completed":
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case "failed":
        statusColor = colorScheme.error;
        statusIcon = Icons.error;
        break;
      default:
        statusColor = colorScheme.outline;
        statusIcon = Icons.circle_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline Line & Icon
          Column(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(26),
                  shape: BoxShape.circle,
                  border: Border.all(color: statusColor, width: 2),
                ),
                child: status == "running"
                    ? Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: statusColor,
                        ),
                      )
                    : Icon(statusIcon, size: 16, color: statusColor),
              ),
              // Line
              Container(
                width: 2,
                height: logs != null && logs!.isNotEmpty ? 60 : 30, // Dynamic height
                color: theme.dividerColor.withAlpha(51),
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "步骤 $stepNumber: $title",
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                if (logs != null && logs!.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(128),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: logs!
                          .map(
                            (log) => SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                "> $log",
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                                softWrap: false,
                                maxLines: 1,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
