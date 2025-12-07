// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application/main.dart';
import 'package:flutter_application/settings/settings_controller.dart';

void main() {
  testWidgets('App boots and shows tabs', (tester) async {
    final controller = SettingsController();
    // 不调用 load() 也可读取默认设置，避免依赖平台插件初始化
    await tester.pumpWidget(NTApp(controller: controller));

    // 初始渲染
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Social'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
  });
}
