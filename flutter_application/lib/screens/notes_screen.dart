import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final notes = noteDocuments;
    final density = SettingsScope.of(context).settings.density;
    final pad = switch (density) {
      DensityOption.compact => const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      DensityOption.normal => const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      DensityOption.spacious => const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    };
    return ListView.builder(
      padding: pad,
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final n = notes[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(n.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            onTap: () {},
          ),
        );
      },
    );
  }
}
