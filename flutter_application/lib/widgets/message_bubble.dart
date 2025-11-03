import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';
import '../theme/chat_colors.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
  final theme = Theme.of(context);
  final chat = theme.extension<ChatColors>();
    final isMine = message.isMine;
  final bg = isMine
    ? (chat?.mineBubbleBg ?? theme.colorScheme.primary)
    : (chat?.otherBubbleBg ?? theme.colorScheme.surface);
  final txt = isMine
    ? (chat?.mineText ?? theme.colorScheme.onPrimary)
    : (chat?.otherText ?? theme.colorScheme.onSurface);

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(14),
      topRight: const Radius.circular(14),
      bottomLeft: Radius.circular(isMine ? 14 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 14),
    );

    final maxW = MediaQuery.of(context).size.width;
    final bubbleMax = maxW > 1200 ? 560.0 : maxW * 0.62;

    return Row(
      mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: bubbleMax),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: radius,
              border: Border.all(color: isMine ? (chat?.mineBorder ?? Colors.transparent) : (chat?.otherBorder ?? Colors.transparent)),
            ),
            child: Column(
              crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (message.text.isNotEmpty)
                  Builder(builder: (context) {
                    final settings = SettingsScope.of(context).settings;
                    String? fam;
                    if (settings.decoUseBubbles && settings.decoFamily != DecorativeFontFamily.none) {
                      fam = settings.decoFamily == DecorativeFontFamily.fzg ? 'FZG' : 'nfdcs';
                    } else {
                      fam = null; // 使用全局（MiSans 或系统）
                    }
                    return Text(
                      message.text,
                      style: TextStyle(
                        color: txt,
                        height: 1.35,
                        fontFamily: fam,
                        fontFamilyFallback: const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'],
                      ),
                    );
                  }),
                if (message.attachments.isNotEmpty) ...[
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final att in message.attachments)
                        _AttachmentChip(att: att, isMine: isMine, txtColor: txt),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  message.time,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMine ? (chat?.timeMine ?? txt.withValues(alpha: 0.7)) : (chat?.timeOther ?? txt.withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  final Attachment att;
  final bool isMine;
  final Color txtColor;

  const _AttachmentChip({required this.att, required this.isMine, required this.txtColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chat = theme.extension<ChatColors>();
    final bg = isMine
        ? (chat?.attachmentMineBg ?? txtColor.withValues(alpha: 0.12))
        : (chat?.attachmentOtherBg ?? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9));
    final icon = _iconForMime(att.mime ?? att.name);
    final sizeStr = att.size != null ? _fmtBytes(att.size!) : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: txtColor.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Builder(builder: (context) {
              final settings = SettingsScope.of(context).settings;
              String? fam;
              if (settings.decoUseBubbles && settings.decoFamily != DecorativeFontFamily.none) {
                fam = settings.decoFamily == DecorativeFontFamily.fzg ? 'FZG' : 'nfdcs';
              } else {
                fam = null;
              }
              return Text(
                sizeStr.isEmpty ? att.name : '${att.name} · $sizeStr',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: txtColor,
                  fontFamily: fam,
                  fontFamilyFallback: const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  static IconData _iconForMime(String v) {
    final s = v.toLowerCase();
    if (s.endsWith('.png') || s.endsWith('.jpg') || s.endsWith('.jpeg') || s.startsWith('image/')) return Icons.image_outlined;
    if (s.endsWith('.mp4') || s.startsWith('video/')) return Icons.videocam_outlined;
    if (s.endsWith('.mp3') || s.startsWith('audio/')) return Icons.audiotrack;
    if (s.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (s.endsWith('.zip') || s.endsWith('.rar') || s.endsWith('.7z')) return Icons.archive_outlined;
    if (s.endsWith('.doc') || s.endsWith('.docx')) return Icons.description_outlined;
    if (s.endsWith('.xls') || s.endsWith('.xlsx')) return Icons.grid_on_outlined;
    if (s.endsWith('.ppt') || s.endsWith('.pptx')) return Icons.slideshow_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _fmtBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    double v = bytes.toDouble();
    var idx = 0;
    while (v >= 1024 && idx < units.length - 1) {
      v /= 1024;
      idx++;
    }
    return idx == 0 ? '${bytes}B' : '${v.toStringAsFixed(1)}${units[idx]}';
  }
}
