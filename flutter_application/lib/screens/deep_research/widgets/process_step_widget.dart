import 'package:flutter/material.dart';

class ProcessStepWidget extends StatefulWidget {
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
  State<ProcessStepWidget> createState() => _ProcessStepWidgetState();
}

class _ProcessStepWidgetState extends State<ProcessStepWidget> {
  late bool _isExpanded;
  bool _isLogsExpanded = false;

  @override
  void initState() {
    super.initState();
    // Default expanded if running or failed
    _isExpanded = widget.status == 'running' || widget.status == 'failed';
  }

  @override
  void didUpdateWidget(ProcessStepWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.status != oldWidget.status) {
      if (widget.status == 'running' || widget.status == 'failed') {
        _isExpanded = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color statusColor;
    IconData statusIcon;
    Color bgColor;

    switch (widget.status) {
      case "running":
        statusColor = colorScheme.primary;
        statusIcon = Icons.sync;
        bgColor = colorScheme.primaryContainer.withOpacity(0.1);
        break;
      case "completed":
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        bgColor = Colors.green.withOpacity(0.05);
        break;
      case "failed":
        statusColor = colorScheme.error;
        statusIcon = Icons.error;
        bgColor = colorScheme.errorContainer.withOpacity(0.1);
        break;
      default:
        statusColor = colorScheme.outline;
        statusIcon = Icons.circle_outlined;
        bgColor = Colors.transparent;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.status == 'running' 
              ? statusColor.withOpacity(0.3) 
              : Colors.transparent,
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: 24,
                    height: 24,
                    child: widget.status == "running"
                        ? CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          )
                        : Icon(statusIcon, size: 24, color: statusColor),
                  ),
                  const SizedBox(width: 12),
                  // Title
                  Expanded(
                    child: Text(
                      "步骤 ${widget.stepNumber}: ${widget.title}",
                      style: TextStyle(
                        color: theme.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Chevron
                  Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: colorScheme.outline,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          
          // Expanded Content
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        widget.description,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  
                  // Logs Section
                  if (widget.logs != null && widget.logs!.isNotEmpty) ...[
                    const Divider(height: 16),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isLogsExpanded = !_isLogsExpanded;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.terminal,
                              size: 14,
                              color: colorScheme.secondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '执行日志 (${widget.logs!.length})',
                              style: TextStyle(
                                color: colorScheme.secondary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                             Icon(
                              _isLogsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              size: 16,
                              color: colorScheme.secondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isLogsExpanded)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: widget.logs!.length,
                          itemBuilder: (context, index) {
                            final log = widget.logs![index];
                            return SelectableText(
                              "> $log",
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
