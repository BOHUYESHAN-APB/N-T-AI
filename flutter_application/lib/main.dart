import 'package:flutter/material.dart';
import 'home_shell.dart';

void main() {
  runApp(const NTApp());
}

class NTApp extends StatelessWidget {
  const NTApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'N-T-AI Prototype',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
