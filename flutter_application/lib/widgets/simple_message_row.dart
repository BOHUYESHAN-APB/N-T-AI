import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../theme/chat_colors.dart';

class SimpleMessageRow extends StatelessWidget {
  final ChatMessage message;
  const SimpleMessageRow({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chat = theme.extension<ChatColors>();
    final isMine = message.isMine;
    final textColor = isMine ? (chat?.mineText ?? theme.colorScheme.onSurface) : (chat?.otherText ?? theme.colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Column(
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty)
            Text(
              message.text,
              style: TextStyle(
                color: textColor,
                height: 1.35,
                // 保持与气泡版一致的回退链，尽量避免缺字
                fontFamilyFallback: const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'],
              ),
              textAlign: isMine ? TextAlign.right : TextAlign.left,
            ),
          if (message.attachments.isNotEmpty) ...[
            if (message.text.isNotEmpty) const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final att in message.attachments)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.insert_drive_file_outlined, size: 16, color: textColor.withValues(alpha: 0.8)),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            att.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textColor, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            message.time,
            style: TextStyle(fontSize: 10, color: textColor.withValues(alpha: 0.7)),
          ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}
