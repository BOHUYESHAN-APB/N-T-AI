import 'package:flutter/material.dart';

class SystemScreen extends StatelessWidget {
  const SystemScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.settings, size: 64),
            SizedBox(height: 12),
            Text('System / Settings', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('This is a prototype shell for settings and system info.'),
          ],
        ),
      ),
    );
  }
}
