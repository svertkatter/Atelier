import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'platform/database_init.dart';
import 'providers/settings_providers.dart';
import 'ui/home_shell.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows/desktop require the FFI sqflite factory.
  initDatabaseFactory();

  // Custom window chrome (Windows only for now): hide the native title bar;
  // AtelierTitleBar provides drag-to-move and caption buttons instead.
  if (!kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(860, 560),
      center: true,
      title: 'Atelier',
      titleBarStyle: TitleBarStyle.hidden,
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }));
  }

  runApp(const ProviderScope(child: AtelierApp()));
}

class AtelierApp extends ConsumerWidget {
  const AtelierApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Atelier',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeShell(),
    );
  }
}
