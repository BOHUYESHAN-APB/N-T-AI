import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_application/l10n/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'home_shell.dart';
import 'theme/app_theme.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_scope.dart';
import 'licenses/register_licenses.dart';
import 'services/logger_service.dart';
import 'services/live2d_broadcast_service.dart';
import 'services/diagnostics_service.dart';
import 'utils/http_overrides.dart';

import 'package:desktop_webview_window/desktop_webview_window.dart';

Future<void> main(List<String> args) async {
  if (runWebViewTitleBarWidget(args)) {
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  
  // Allow self-signed certificates for local development/usage
  HttpOverrides.global = SelfSignedHttpOverrides();
  
  logger.info("Starting N-T-AI Application...");

  if (defaultTargetPlatform == TargetPlatform.windows || 
      defaultTargetPlatform == TargetPlatform.linux || 
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final controller = SettingsController();
  await controller.load();
  await LoggerService().init(maxErrors: controller.settings.logMaxErrors, backendUrl: controller.settings.pythonBackendUrl);
  
  // Print Dashboard URL for user visibility
  debugPrint("==================================================");
  debugPrint("后台管理面板地址: ${controller.settings.pythonBackendUrl}/dashboard");
  debugPrint("==================================================");
  
  // Run Diagnostics (Fire and forget to avoid blocking startup)
  DiagnosticsService().runDiagnostics(controller.settings.pythonBackendUrl);

  // Propagate configured backend URL to services that need it
  try {
    Live2DBroadcastService().setBackendUrl(controller.settings.pythonBackendUrl);
  } catch (_) {}
  await registerThirdPartyLicenses();
  runApp(NTApp(controller: controller));
}

class NTApp extends StatelessWidget {
  final SettingsController controller;
  const NTApp({Key? key, required this.controller}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SettingsScope(
      controller: controller,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return MaterialApp(
            title: 'N-T-AI Prototype',
            theme: AppTheme.fromSettings(controller.settings, isDark: false),
            darkTheme: AppTheme.fromSettings(controller.settings, isDark: true),
            themeMode: controller.themeMode,
            locale: controller.locale,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('zh'), // Chinese first
              Locale('en'), // English
            ],
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(controller.settings.textScale)),
                child: child!,
              );
            },
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
