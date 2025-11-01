import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../widgets/message_bubble.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: chatMessages.length,
      itemBuilder: (context, index) {
        final msg = chatMessages[index];
        return Column(
          crossAxisAlignment:
              msg.isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            MessageBubble(message: msg),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
