import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/expressive_face.dart';
import '../services/expression_service.dart';

class ExpressionDemoScreen extends StatefulWidget {
  const ExpressionDemoScreen({Key? key}) : super(key: key);

  @override
  State<ExpressionDemoScreen> createState() => _ExpressionDemoScreenState();
}

class _ExpressionDemoScreenState extends State<ExpressionDemoScreen> {
  late ExpressionController controller;
  final TextEditingController _jsonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    controller = ExpressionController();
    _jsonController.text = jsonEncode(ExpressionService.toMap(ExpressionData.neutral()));
  }

  @override
  void dispose() {
    controller.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  void applyJson() {
    try {
      final m = jsonDecode(_jsonController.text) as Map<String, dynamic>;
      final expr = ExpressionService.fromMap(m);
      controller.setExpression(expr);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON 解析失败')));
    }
  }

  void applyPreset(ExpressionData e) {
    controller.setExpression(e);
    _jsonController.text = jsonEncode(ExpressionService.toMap(e));
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = controller.value;
    return Scaffold(
      appBar: AppBar(title: const Text('表情演示')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Center(child: ExpressiveFace(controller: controller, size: 260)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              ElevatedButton(onPressed: () => applyPreset(ExpressionData.neutral()), child: const Text('中性')),
              ElevatedButton(
                  onPressed: () => applyPreset(
                        ExpressionData(
                          mouth: 0.9,
                          eyes: 1.0,
                          eyebrow: 0.6,
                          blush: 0.5,
                          pupilX: 0.0,
                          pupilY: 0.0,
                          headTilt: -0.05,
                          faceColor: const Color(0xFFFFF0A0),
                        ),
                      ),
                  child: const Text('开心')),
              ElevatedButton(
                  onPressed: () => applyPreset(
                        ExpressionData(
                          mouth: -0.8,
                          eyes: 0.7,
                          eyebrow: -0.5,
                          blush: 0.0,
                          pupilX: 0.0,
                          pupilY: 0.0,
                          headTilt: 0.03,
                          faceColor: const Color(0xFFFFE066),
                        ),
                      ),
                  child: const Text('伤心')),
              ElevatedButton(
                  onPressed: () => applyPreset(
                        ExpressionData(
                          mouth: 0.2,
                          eyes: 1.0,
                          eyebrow: 0.9,
                          blush: 0.6,
                          pupilX: 0.0,
                          pupilY: -0.1,
                          headTilt: -0.12,
                          faceColor: const Color(0xFFFFE066),
                        ),
                      ),
                  child: const Text('惊讶')),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('当前表达（JSON）'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _jsonController,
                      maxLines: 4,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      inputFormatters: [FilteringTextInputFormatter.deny(RegExp('[\n]'))],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(onPressed: applyJson, child: const Text('应用 JSON')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: _jsonController.text));
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制')));
                            },
                            child: const Text('复制')),
                      ],
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    _slider('嘴（-1:哀 - 1:笑）', current.mouth, -1, 1, (v) => controller.setExpression(current.copyWith(mouth: v))),
                    _slider('眼睛开度（0:闭 1:睁）', current.eyes, 0, 1, (v) => controller.setExpression(current.copyWith(eyes: v))),
                    _slider('眉毛 (-1..1)', current.eyebrow, -1, 1, (v) => controller.setExpression(current.copyWith(eyebrow: v))),
                    _slider('腮红 (0..1)', current.blush, 0, 1, (v) => controller.setExpression(current.copyWith(blush: v))),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
