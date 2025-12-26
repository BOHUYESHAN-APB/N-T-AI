import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../data/mock_data.dart';
import '../plugins/plugin_manager.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';
import '../theme/chat_colors.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // Special handling for Plugin Messages (Centered)
    if (message.role == 'chat_summary') {
      final enabled = globalPluginManager.enabledPlugins.any((p) => p.isDanmakuPlugin);
      if (!enabled) return const SizedBox.shrink();
      final theme = Theme.of(context);
      final cs = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B5E20).withValues(alpha: 0.2) : const Color(0xFFF0FFF0),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.green.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.45),
              width: 1.0,
            ),
            boxShadow: [
               BoxShadow(
                 color: Colors.black.withValues(alpha: 0.05), 
                 blurRadius: 4, 
                 offset: const Offset(0, 2)
               ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.insights, size: 14, color: isDark ? Colors.green[300] : Colors.green.withValues(alpha: 0.9)),
                  const SizedBox(width: 6),
                  Text(
                    "弹幕总结 · 来源: Bilibili直播插件",
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.bold, 
                      color: isDark ? Colors.green[300] : Colors.green.withValues(alpha: 0.9),
                      letterSpacing: 1.0
                    )
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 13, 
                  color: isDark ? Colors.green[100] : cs.onSurface,
                  height: 1.4
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (message.role == 'chat_minecraft') {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D47A1).withValues(alpha: 0.18) : const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF64B5F6).withValues(alpha: 0.35) : const Color(0xFF90CAF9),
              width: 1.0,
            ),
            boxShadow: [
               BoxShadow(
                 color: Colors.black.withValues(alpha: 0.05), 
                 blurRadius: 4, 
                 offset: const Offset(0, 2)
               ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.games, size: 14, color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0)),
                  const SizedBox(width: 6),
                  Text(
                    "来自于MC插件",
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.bold, 
                      color: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0),
                      letterSpacing: 1.0
                    )
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 13, 
                  color: isDark ? Colors.blue[50] : theme.colorScheme.onSurface,
                  height: 1.4
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (message.role == 'chat_voice_channel') {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A237E).withValues(alpha: 0.18) : const Color(0xFFE8EAF6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? const Color(0xFF7986CB).withValues(alpha: 0.35) : const Color(0xFF9FA8DA),
              width: 1.0,
            ),
            boxShadow: [
               BoxShadow(
                 color: Colors.black.withValues(alpha: 0.05), 
                 blurRadius: 4, 
                 offset: const Offset(0, 2)
               ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.record_voice_over, size: 14, color: isDark ? const Color(0xFF9FA8DA) : const Color(0xFF283593)),
                  const SizedBox(width: 6),
                  Text(
                    "来自于语音频道",
                    style: TextStyle(
                      fontSize: 11, 
                      fontWeight: FontWeight.bold, 
                      color: isDark ? const Color(0xFF9FA8DA) : const Color(0xFF283593),
                      letterSpacing: 1.0
                    )
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: TextStyle(
                  fontSize: 13, 
                  color: isDark ? Colors.indigo[50] : theme.colorScheme.onSurface,
                  height: 1.4
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (message.role == 'chat_normal') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 24),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900]!.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.grey[800]! : Colors.grey.withValues(alpha: 0.3)),
            boxShadow: [
               BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
            ],
          ),
          child: Text(
            message.text,
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (message.role == 'chat_sc') {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark 
                ? [const Color(0xFF5D4037), const Color(0xFF3E2723)] // Darker Gold/Brown
                : [const Color(0xFFFFF3CD), const Color(0xFFFFECB3)], // Gold/Yellow
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF8D6E63) : const Color(0xFFFFEEBA)),
            boxShadow: [
               BoxShadow(
                 color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.2), 
                 blurRadius: 6, 
                 offset: const Offset(0, 3)
               ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
               Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   Icon(Icons.star, size: 12, color: isDark ? Colors.amber[200] : const Color(0xFF856404)),
                   const SizedBox(width: 4),
                   Text(
                     "SUPER CHAT", 
                     style: TextStyle(
                       fontSize: 10, 
                       fontWeight: FontWeight.bold, 
                       color: isDark ? Colors.amber[200] : const Color(0xFF856404), 
                       letterSpacing: 1.5
                     )
                   ),
                   const SizedBox(width: 4),
                   Icon(Icons.star, size: 12, color: isDark ? Colors.amber[200] : const Color(0xFF856404)),
                 ],
               ),
               const SizedBox(height: 4),
               Text(
                message.text,
                style: TextStyle(
                  fontSize: 14, 
                  fontWeight: FontWeight.w600, 
                  color: isDark ? Colors.amber[100] : const Color(0xFF856404)
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final chat = theme.extension<ChatColors>();
    final isMine = message.isMine;
    final settings = SettingsScope.of(context).settings;
    final kind = message.kind;

    // Helper to get Color from int
    Color? getColor(int? argb) => argb != null ? Color(argb) : null;

    final userOverride = getColor(settings.userBubbleColor);
    final aiOverride = getColor(settings.aiBubbleColor);

    final isDark = theme.brightness == Brightness.dark;

    // Colors
    final bgMine = userOverride ?? chat?.mineBubbleBg ?? theme.colorScheme.primary;
    final bgOther = aiOverride ?? chat?.otherBubbleBg ?? theme.colorScheme.surface;
    
    final txtMine = userOverride != null 
        ? (userOverride.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        : (chat?.mineText ?? theme.colorScheme.onPrimary);
    final txtOther = aiOverride != null
        ? (aiOverride.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        : (chat?.otherText ?? theme.colorScheme.onSurface);

    final isSttHeard = kind == ChatMessageKind.sttHeard;
    final alignRight = isMine || isSttHeard;
    final maxW = MediaQuery.of(context).size.width;
    final bubbleMax = maxW > 1200 ? 560.0 : maxW * 0.75;
    final borderColor = switch (kind) {
      ChatMessageKind.assistant => Colors.red.withValues(alpha: isDark ? 0.3 : 0.45),
      ChatMessageKind.user => Colors.blue.withValues(alpha: isDark ? 0.3 : 0.45),
      ChatMessageKind.sttHeard => Colors.purple.withValues(alpha: isDark ? 0.3 : 0.45),
      ChatMessageKind.system => theme.colorScheme.outline.withValues(alpha: isDark ? 0.2 : 0.35),
      _ => theme.colorScheme.outline.withValues(alpha: isDark ? 0.15 : 0.25),
    };
    final bubbleBg = isSttHeard 
        ? (isDark ? const Color(0xFF4527A0).withValues(alpha: 0.4) : const Color(0xFFEDE7F6)) 
        : (isMine ? bgMine : bgOther);
    final bubbleTxt = isSttHeard 
        ? (isDark ? Colors.deepPurple[100]! : theme.colorScheme.onSurface) 
        : (isMine ? txtMine : txtOther);
    final outerPadding = EdgeInsets.fromLTRB(
      8,
      6,
      kind == ChatMessageKind.sttHeard ? 56 : 8,
      6,
    );

    // Parse content into blocks (Text or Image)
    final suppressInnerMonologue = !isMine && !isSttHeard && settings.suppressInnerMonologue;
    final enableThoughtParsing = !isMine && !isSttHeard && !settings.suppressInnerMonologue;
    final blocks = _parseMessageBlocks(
      message.text,
      isMine: alignRight,
      enableThoughtParsing: enableThoughtParsing,
      suppressInnerMonologue: suppressInnerMonologue,
    );

    return Padding(
      padding: outerPadding,
      child: Column(
        crossAxisAlignment: alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (isSttHeard)
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0, left: 8.0, right: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF4527A0).withValues(alpha: 0.5) : const Color(0xFFEDE7F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.deepPurple.withValues(alpha: 0.3) : Colors.deepPurple.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic, size: 12, color: isDark ? Colors.deepPurple[200] : Colors.deepPurple),
                    const SizedBox(width: 6),
                    Text(
                      "麦克风来源",
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.deepPurple[100] : Colors.deepPurple[700]),
                    ),
                  ],
                ),
              ),
            ),
          if (!isSttHeard && isMine)
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0, left: 8.0, right: 8.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1565C0).withValues(alpha: 0.5) : const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isDark ? Colors.blue.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.keyboard_alt, size: 12, color: isDark ? Colors.blue[200] : Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      "文字输入",
                      style: TextStyle(fontSize: 10, color: isDark ? Colors.blue[100] : Colors.blue[700]),
                    ),
                  ],
                ),
              ),
            ),
          // Render each block
          for (final block in blocks)
            if (block['type'] == 'image')
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bubbleMax),
                    child: _buildImageWidget(context, block['content'] as String),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Row(
                  mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end, // Align tail to bottom
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tail for Other (Left)
                    if (!alignRight)
                      CustomPaint(
                        painter: _TailPainter(color: bubbleBg, isMine: false),
                        size: const Size(8, 16),
                      ),

                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: bubbleMax),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                          decoration: BoxDecoration(
                            color: bubbleBg,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: Radius.circular(alignRight ? 16 : 4),
                              bottomRight: Radius.circular(alignRight ? 4 : 16),
                            ),
                            border: Border.all(color: borderColor, width: 1.0),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Reasoning Content (DeepSeek)
                              if (!isMine && !isSttHeard && message.reasoningContent != null && message.reasoningContent!.isNotEmpty)
                                _buildReasoningBlock(context, message.reasoningContent!),
                              
                              // Tool Calls
                              if (!isMine && !isSttHeard && message.toolCalls != null && message.toolCalls!.isNotEmpty)
                                _buildToolCallsBlock(context, message.toolCalls!),

                              _buildContent(context, block['segments'] as List<Map<String, dynamic>>, bubbleTxt, alignRight),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Tail for Mine (Right)
                    if (alignRight)
                      CustomPaint(
                        painter: _TailPainter(color: bubbleBg, isMine: true),
                        size: const Size(8, 16),
                      ),
                  ],
                ),
              ),

          // Attachments
          if (message.attachments.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: alignRight ? WrapAlignment.end : WrapAlignment.start,
              children: [
                for (final att in message.attachments)
                  _AttachmentChip(att: att, isMine: alignRight, txtColor: bubbleTxt),
              ],
            ),
          ],

          // Footer (Time & Actions)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.time,
                  style: TextStyle(
                    fontSize: 10,
                    color: alignRight ? (chat?.timeMine ?? bubbleTxt.withValues(alpha: 0.7)) : (chat?.timeOther ?? bubbleTxt.withValues(alpha: 0.7)),
                  ),
                ),
                if (!isMine && !isSttHeard) ...[
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.copy, size: 14, onTap: () => _copyText(context, message.text)),
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.thumb_up_outlined, size: 14, onTap: () {}), // Placeholder
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.thumb_down_outlined, size: 14, onTap: () {}), // Placeholder
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.refresh, size: 14, onTap: () {}), // Placeholder
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Map<String, dynamic>> segments, Color baseColor, bool isMine) {
    return Builder(builder: (context) {
      final settings = SettingsScope.of(context).settings;
      String? fam;
      if (settings.decoUseBubbles && settings.decoFamily != DecorativeFontFamily.none) {
        fam = settings.decoFamily == DecorativeFontFamily.fzg ? 'FZG' : 'nfdcs';
      } else {
        fam = null;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: segments.map((seg) {
          final text = seg['text'] as String;
          final isThought = seg['isThought'] as bool;
          
          if (isThought) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 4, top: 2),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isMine 
                    ? Colors.black.withValues(alpha: 0.1) 
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                text,
                style: TextStyle(
                  color: baseColor.withValues(alpha: 0.9),
                  fontStyle: FontStyle.italic,
                  fontSize: 13,
                  fontFamily: fam,
                  fontFamilyFallback: const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'],
                ),
              ),
            );
          } else {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: SelectableText(
                text,
                style: TextStyle(
                  color: baseColor,
                  fontSize: 15,
                  fontFamily: fam,
                  fontFamilyFallback: const ['MiSansVF', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans SC', 'Segoe UI', 'Roboto'],
                ),
              ),
            );
          }
        }).toList(),
      );
    });
  }

  Widget _buildImageWidget(BuildContext context, String path) {
    Widget imageWidget;
    if (path.startsWith('http')) {
      final Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      };
      
      if (path.contains('baidu.com') || path.contains('bcebos.com')) {
        headers['Referer'] = 'https://baike.baidu.com/';
      } else if (path.contains('sinaimg.cn')) {
        headers['Referer'] = 'https://weibo.com/';
      }

      imageWidget = Image.network(
        path,
        headers: headers,
        errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
        loadingBuilder: (c, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return SizedBox(
            height: 150,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
      );
    } else {
      imageWidget = Image.file(
        File(path),
        errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 48, color: Colors.grey),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ImageViewerScreen(imagePath: path),
          ),
        );
      },
      child: Hero(
        tag: path,
        child: imageWidget,
      ),
    );
  }

  void _copyText(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制内容'), duration: Duration(seconds: 1)));
  }

  Widget _buildReasoningBlock(BuildContext context, String reasoning) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ExpansionTile(
        title: const Text(
          "Thinking Process",
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
        ),
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        dense: true,
        initiallyExpanded: true,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border(left: BorderSide(color: Colors.grey.shade400, width: 3)),
            ),
            child: Text(
              reasoning,
              style: TextStyle(
                fontSize: 12, 
                fontStyle: FontStyle.italic, 
                color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.black87
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolCallsBlock(BuildContext context, List<dynamic> toolCalls) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: toolCalls.map<Widget>((tool) {
          final func = tool['function'];
          final name = func['name'];
          final args = func['arguments'];
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark ? Colors.blue[900]!.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isDark ? Colors.blue[700]!.withValues(alpha: 0.4) : Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.build, size: 14, color: isDark ? Colors.blue[200] : Colors.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Called: $name($args)",
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.blue[200] : Colors.blue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Map<String, dynamic>> _parseMessageBlocks(
    String text, {
    required bool isMine,
    required bool enableThoughtParsing,
    required bool suppressInnerMonologue,
  }) {
    // 1. Split by [IMAGE: ...] tags
    final regex = RegExp(r'\[IMAGE(?:_\d+)?:?\s*(.*?)\]', dotAll: true);
    final matches = regex.allMatches(text);
    final List<Map<String, dynamic>> blocks = [];
    int lastEnd = 0;

    void addTextBlock(String t) {
      if (t.trim().isEmpty) return;
      var normalized = isMine ? t : t.replaceAll('[SPLIT]', '\n\n');
      if (suppressInnerMonologue) {
        normalized = _stripInnerMonologueText(normalized);
      }
      if (normalized.trim().isEmpty) return;
      blocks.add({
        'type': 'text',
        'content': normalized,
        'segments': _parseTextSegments(normalized, enableThoughtParsing: enableThoughtParsing),
      });
    }

    for (final match in matches) {
      if (match.start > lastEnd) {
        addTextBlock(text.substring(lastEnd, match.start));
      }
      
      // Extract URL
      String url = match.group(1) ?? '';
      if (url.isNotEmpty) {
        blocks.add({
          'type': 'image',
          'content': url.trim(),
        });
      }
      
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      addTextBlock(text.substring(lastEnd));
    }
    
    // If empty, add original text as block
    if (blocks.isEmpty && text.isNotEmpty) {
      addTextBlock(text);
    }
    
    return blocks;
  }

  String _stripInnerMonologueText(String text) {
    var out = text.replaceAll(RegExp(r'（[^）]*）', dotAll: true), '');
    out = out.replaceAllMapped(
      RegExp(r'(?<!\])\(([^)]*)\)', dotAll: true),
      (m) {
        final inner = m.group(1) ?? '';
        final hasCjk = RegExp(r'[\u4e00-\u9fff]').hasMatch(inner);
        if (hasCjk && inner.trim().length <= 40) return '';
        return m.group(0) ?? '';
      },
    );
    out = out
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return out;
  }

  List<Map<String, dynamic>> _parseTextSegments(String text, {required bool enableThoughtParsing}) {
    if (!enableThoughtParsing) {
      return [
        {'text': text.trim(), 'isThought': false}
      ];
    }
    final regex = RegExp(r'(\（.*?\）|\(.*?\))', dotAll: true);
    final matches = regex.allMatches(text);
    final List<Map<String, dynamic>> result = [];
    int lastEnd = 0;

    void addText(String t, bool isThought) {
      if (t.trim().isEmpty) return;
      result.add({'text': t.trim(), 'isThought': isThought});
    }

    for (final m in matches) {
      if (m.start > lastEnd) {
        addText(text.substring(lastEnd, m.start), false);
      }
      String thought = text.substring(m.start, m.end);
      if (thought.startsWith('(') && thought.endsWith(')')) {
        thought = thought.substring(1, thought.length - 1);
      } else if (thought.startsWith('（') && thought.endsWith('）')) {
        thought = thought.substring(1, thought.length - 1);
      }
      addText(thought, true);
      lastEnd = m.end;
    }
    if (lastEnd < text.length) {
      addText(text.substring(lastEnd), false);
    }
    if (result.isEmpty && text.isNotEmpty) {
      result.add({'text': text, 'isThought': false});
    }

    final List<Map<String, dynamic>> normalized = [];
    for (final seg in result) {
      final text = seg['text'] as String;
      final isThought = seg['isThought'] as bool;
      if (isThought && text.contains('\n')) {
        final parts = text.split(RegExp(r'\n+'));
        for (final p in parts) {
          final t = p.trim();
          if (t.isEmpty) continue;
          normalized.add({'text': t, 'isThought': true});
        }
      } else {
        normalized.add(seg);
      }
    }
    return normalized;
  }
}

class _TailPainter extends CustomPainter {
  final Color color;
  final bool isMine;

  _TailPainter({required this.color, required this.isMine});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (isMine) {
      // Right tail
      path.moveTo(0, size.height - 12);
      path.lineTo(size.width, size.height - 6);
      path.lineTo(0, size.height);
      path.close();
    } else {
      // Left tail
      path.moveTo(size.width, size.height - 12);
      path.lineTo(0, size.height - 6);
      path.lineTo(size.width, size.height);
      path.close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(icon, size: size, color: Colors.grey),
      ),
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

class _ImageViewerScreen extends StatelessWidget {
  final String imagePath;

  const _ImageViewerScreen({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (imagePath.startsWith('http')) {
      final Map<String, String> headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      };
      
      if (imagePath.contains('baidu.com') || imagePath.contains('bcebos.com')) {
        headers['Referer'] = 'https://baike.baidu.com/';
      } else if (imagePath.contains('sinaimg.cn')) {
        headers['Referer'] = 'https://weibo.com/';
      }

      imageWidget = Image.network(
        imagePath,
        headers: headers,
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 48, color: Colors.white),
      );
    } else {
      imageWidget = Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 48, color: Colors.white),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4,
          child: Hero(
            tag: imagePath,
            child: imageWidget,
          ),
        ),
      ),
    );
  }
}
