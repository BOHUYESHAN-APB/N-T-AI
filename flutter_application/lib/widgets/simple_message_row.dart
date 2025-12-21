import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../plugins/plugin_manager.dart';
import '../theme/chat_colors.dart';

class SimpleMessageRow extends StatelessWidget {
  final ChatMessage message;
  const SimpleMessageRow({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chat = theme.extension<ChatColors>();
    final isMine = message.isMine;
    final kind = message.kind;
    final alignRight = isMine || kind == ChatMessageKind.sttHeard;
    final textColor = alignRight ? (chat?.mineText ?? theme.colorScheme.onSurface) : (chat?.otherText ?? theme.colorScheme.onSurface);
    final borderColor = switch (kind) {
      ChatMessageKind.assistant => Colors.red.withValues(alpha: 0.5),
      ChatMessageKind.user => Colors.blue.withValues(alpha: 0.5),
      ChatMessageKind.sttHeard => Colors.purple.withValues(alpha: 0.5),
      ChatMessageKind.pluginSummary => Colors.green.withValues(alpha: 0.45),
      ChatMessageKind.system => theme.colorScheme.outline.withValues(alpha: 0.3),
      _ => theme.colorScheme.outline.withValues(alpha: 0.2),
    };
    final bgColor = switch (kind) {
      ChatMessageKind.assistant => Colors.red.withValues(alpha: 0.06),
      ChatMessageKind.user => Colors.blue.withValues(alpha: 0.06),
      ChatMessageKind.sttHeard => Colors.purple.withValues(alpha: 0.06),
      ChatMessageKind.system => theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      _ => theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
    };
    final outerPadding = EdgeInsets.fromLTRB(8, 6, kind == ChatMessageKind.sttHeard ? 56 : 8, 6);

    if (kind == ChatMessageKind.pluginSummary) {
      final enabled = globalPluginManager.enabledPlugins.any((p) => p.isDanmakuPlugin);
      if (!enabled) return const SizedBox.shrink();
      return Padding(
        padding: outerPadding,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Text(
                message.text,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurface, height: 1.35),
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: outerPadding,
      child: Column(
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (message.text.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: textColor,
                  height: 1.35,
                  fontFamilyFallback: const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'],
                ),
                textAlign: alignRight ? TextAlign.right : TextAlign.left,
              ),
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
        ],
      ),
    );
  }
}
