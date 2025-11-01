import 'package:flutter/material.dart';
import '../data/mock_data.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final notes = noteDocuments;
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final n = notes[index];
        return ListTile(
          title: Text(n.title),
          subtitle: Text(n.preview),
          leading: const Icon(Icons.note),
          onTap: () {},
        );
      },
    );
  }
}
