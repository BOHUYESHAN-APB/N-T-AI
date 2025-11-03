import 'package:flutter/material.dart';
import 'home_shell.dart';
import 'theme/app_theme.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_scope.dart';
import 'licenses/register_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = SettingsController();
  await controller.load();
  await registerThirdPartyLicenses();
  runApp(NTApp(controller: controller));
}

class NTApp extends StatelessWidget {
  final SettingsController controller;
  const NTApp({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'N-T-AI Prototype',
          theme: AppTheme.fromSettings(controller.settings, isDark: false),
          darkTheme: AppTheme.fromSettings(controller.settings, isDark: true),
          themeMode: controller.themeMode,
          debugShowCheckedModeBanner: false,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(controller.settings.textScale)),
              child: child!,
            );
          },
          home: SettingsScope(
            controller: controller,
            child: const HomeShell(),
          ),
        );
      },
    );
  }
}
