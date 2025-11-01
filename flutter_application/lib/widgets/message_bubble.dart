import 'package:flutter/material.dart';
import '../data/mock_data.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({Key? key, required this.message}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final align = message.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bg = message.isMine ? Theme.of(context).colorScheme.primary : Colors.grey[200];
    final textColor = message.isMine ? Colors.white : Colors.black87;

    return Row(
      mainAxisAlignment:
          message.isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: align,
              children: [
                Text(message.text, style: TextStyle(color: textColor)),
                const SizedBox(height: 6),
                Text(message.time, style: TextStyle(fontSize: 10, color: textColor.withOpacity(0.85))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
