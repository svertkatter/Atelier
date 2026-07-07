import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform/database_init.dart';
import 'providers/settings_providers.dart';
import 'ui/home_shell.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows/desktop require the FFI sqflite factory.
  initDatabaseFactory();
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
