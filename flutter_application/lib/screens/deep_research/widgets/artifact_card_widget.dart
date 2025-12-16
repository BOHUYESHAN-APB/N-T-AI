import 'package:flutter/material.dart';

class ArtifactCardWidget extends StatelessWidget {
  final String title;
  final String type; // "PPT", "DOC", "PDF", "XLS"
  final String size;
  final VoidCallback? onDownload;
  final VoidCallback? onPreview;

  const ArtifactCardWidget({
    super.key,
    required this.title,
    required this.type,
    this.size = "2.4 MB",
    this.onDownload,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
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
        color: const Color(0xFF2A2A35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, color: typeColor, size: 24),
              ),
              const Spacer(),
              const Icon(Icons.more_vert, color: Colors.white30, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            "$type • $size",
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPreview,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white12),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text("Preview", style: TextStyle(fontSize: 12)),
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
          )
        ],
      ),
    );
  }
}
