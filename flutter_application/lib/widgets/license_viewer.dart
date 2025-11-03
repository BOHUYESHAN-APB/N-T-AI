import 'package:flutter/material.dart';

class LicenseViewer extends StatelessWidget {
  final String title;
  final String assetPath;
  const LicenseViewer({super.key, required this.title, required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: DefaultAssetBundle.of(context).loadString(assetPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('加载失败: ${snapshot.error}'));
          }
          final text = snapshot.data ?? '';
          return Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
            ),
          );
        },
      ),
    );
  }
}
