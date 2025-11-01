import 'package:flutter/material.dart';
import '../data/mock_data.dart';

class SocialScreen extends StatelessWidget {
  const SocialScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final posts = socialPosts;
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final p = posts[index];
        return Card(
          child: ListTile(
            title: Text(p.author),
            subtitle: Text(p.text),
            leading: const CircleAvatar(child: Icon(Icons.person)),
          ),
        );
      },
    );
  }
}
