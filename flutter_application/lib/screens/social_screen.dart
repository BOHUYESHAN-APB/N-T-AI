import 'package:flutter/material.dart';
import '../data/mock_data.dart';
import '../settings/settings_scope.dart';
import '../settings/settings.dart';

class SocialScreen extends StatelessWidget {
  const SocialScreen({Key? key}) : super(key: key);

  String _initials(String name) {
    if (name.trim().isEmpty) return '?';
    final trimmed = name.trim();
    // 简化：取首字（适配中英文场景）
    return trimmed.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final posts = socialPosts;
    final density = SettingsScope.of(context).settings.density;
    final pad = switch (density) {
      DensityOption.compact => const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      DensityOption.normal => const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      DensityOption.spacious => const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    };
    return ListView.builder(
      padding: pad,
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final p = posts[index];
        return Card(
          child: ListTile(
            leading: CircleAvatar(child: Text(_initials(p.author))),
            title: Text(p.author, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(p.text),
            ),
            onTap: () {},
          ),
        );
      },
    );
  }
}
