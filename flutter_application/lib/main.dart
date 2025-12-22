import 'dart:io';
import 'dart:async';
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
import 'core/services/backend_service.dart';
import 'utils/http_overrides.dart';

import 'package:desktop_webview_window/desktop_webview_window.dart';

// Simple file logger for Release mode debugging
void logToFile(String message) {
  try {
    final file = File('startup_log.txt');
    final timestamp = DateTime.now().toIso8601String();
    file.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
  } catch (e) {
    // Ignore logging errors
  }
}

Future<void> main(List<String> args) async {
  logToFile("Application Starting...");

  if (runWebViewTitleBarWidget(args)) {
    logToFile("Exiting due to WebViewTitleBarWidget");
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  
  // Allow self-signed certificates for local development/usage
  HttpOverrides.global = SelfSignedHttpOverrides();
  
  logger.info("Starting N-T-AI Application...");
  logToFile("Logger initialized");

  if (defaultTargetPlatform == TargetPlatform.windows || 
      defaultTargetPlatform == TargetPlatform.linux || 
      defaultTargetPlatform == TargetPlatform.macOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    logToFile("Sqflite initialized");
  }

  runZonedGuarded(() async {
    try {
      logToFile("Loading Settings...");
      final controller = SettingsController();
      await controller.load();
      logToFile("Settings loaded. Backend URL: ${controller.settings.pythonBackendUrl}");

      await LoggerService().init(maxErrors: controller.settings.logMaxErrors, backendUrl: controller.settings.pythonBackendUrl);
      
      // Initialize Backend Service (Starts local backend on Windows, checks connection)
      try {
        logToFile("Initializing BackendService...");
        await BackendService().init(
          controller.settings.pythonBackendUrl,
          enabled: controller.settings.enablePythonBackend &&
              controller.settings.autoConnectBackend,
          autoStartLocal: controller.settings.autoStartBackend,
        );
        logToFile("BackendService initialized");
      } catch (e, stack) {
        logToFile("Failed to initialize BackendService: $e\n$stack");
        logger.error("Failed to initialize BackendService", e, stack);
      }

      // Print Dashboard URL for user visibility
      debugPrint("==================================================");
      debugPrint("后台管理面板地址: ${controller.settings.pythonBackendUrl}/dashboard");
      debugPrint("==================================================");
      
      // Run Diagnostics (Fire and forget to avoid blocking startup)
      if (controller.settings.autoConnectBackend) {
        DiagnosticsService().runDiagnostics(controller.settings.pythonBackendUrl);
      }

      // Propagate configured backend URL to services that need it
      try {
        Live2DBroadcastService().setBackendUrl(controller.settings.pythonBackendUrl);
      } catch (_) {}
      await registerThirdPartyLicenses();
      
      logToFile("Running App...");
      runApp(NTApp(controller: controller));
    } catch (e, stack) {
      logToFile("Critical Error during startup: $e\n$stack");
      debugPrint("Critical Error during startup: $e");
      debugPrint(stack.toString());
      runApp(ErrorApp(error: e, stackTrace: stack));
    }
  }, (error, stack) {
    logToFile("Uncaught error: $error\n$stack");
    debugPrint("Uncaught error: $error");
    debugPrint(stack.toString());
  });
}

class ErrorApp extends StatelessWidget {
  final Object error;
  final StackTrace? stackTrace;
  
  const ErrorApp({super.key, required this.error, this.stackTrace});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 24),
                const Text(
                  'Application Failed to Start',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 400),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      '$error\n\n$stackTrace',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NTApp extends StatelessWidget {
  final SettingsController controller;
  const NTApp({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    logToFile("NTApp.build started");
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
