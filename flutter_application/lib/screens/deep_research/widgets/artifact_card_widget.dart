import 'package:flutter/material.dart';

class ArtifactCardWidget extends StatelessWidget {
  final String title;
  final String type; // "PPT", "DOC", "PDF", "XLS"
  final String size;
  final VoidCallback? onDownload;
  final VoidCallback? onPreview;
  final VoidCallback? onUseAsContext;

  const ArtifactCardWidget({
    super.key,
    required this.title,
    required this.type,
    this.size = "2.4 MB",
    this.onDownload,
    this.onPreview,
    this.onUseAsContext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    Color typeColor;
    IconData typeIcon;

    switch (type.toUpperCase()) {
      case "PPT":
      case "PPTX":
        typeColor = Colors.redAccent;
        typeIcon = Icons.slideshow;
        break;
      case "DOC":
      case "DOCX":
        typeColor = Colors.blueAccent;
        typeIcon = Icons.description;
        break;
      case "XLS":
      case "XLSX":
      case "CSV":
        typeColor = Colors.green;
        typeIcon = Icons.table_chart;
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.insert_drive_file;
    }

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withAlpha(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withAlpha(51),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, color: typeColor, size: 24),
              ),
              const Spacer(),
              if (onUseAsContext != null)
                IconButton(
                  tooltip: "设为追问依据",
                  onPressed: onUseAsContext,
                  icon: Icon(Icons.link, color: colorScheme.onSurfaceVariant, size: 18),
                ),
              Icon(Icons.more_vert, color: colorScheme.onSurfaceVariant, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            "${type.toUpperCase()} • $size",
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPreview,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(color: colorScheme.outline.withAlpha(77)),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text("预览/打开", style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: onDownload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                    elevation: 0,
                  ),
                  child: const Icon(Icons.download, size: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
