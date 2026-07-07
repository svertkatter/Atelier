import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_providers.dart';
import '../providers/vault_providers.dart';
import 'library_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'writer_screen.dart';

/// The app shell: Library / Reader / Writer modes plus Settings, behind a
/// NavigationRail. When no vault root is configured, every mode except
/// Settings shows a prompt to configure one first (Settings is always
/// reachable so first-run setup is possible).
///
/// The selected mode lives in [selectedModeProvider] (not local State) so
/// other screens can navigate here directly — e.g. tapping a paper row in the
/// Library auto-switches to the Reader (DESIGN.md「4-2.」自動遷移).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(vaultConfigProvider);
    final selected = ref.watch(selectedModeProvider);

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selected.index,
            onDestinationSelected: (i) => ref
                .read(selectedModeProvider.notifier)
                .select(AppMode.values[i]),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.menu_book_outlined),
                selectedIcon: Icon(Icons.menu_book),
                label: Text('Reader'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.edit_outlined),
                selectedIcon: Icon(Icons.edit),
                label: Text('Writer'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: configAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (config) {
                // Settings is always reachable (needed for first-run setup).
                if (selected == AppMode.settings) return const SettingsScreen();
                if (config == null) {
                  return const _NoVaultView();
                }
                switch (selected) {
                  case AppMode.library:
                    return LibraryScreen(config: config);
                  case AppMode.reader:
                    return ReaderScreen(config: config);
                  case AppMode.writer:
                    return const WriterScreen();
                  case AppMode.settings:
                    return const SettingsScreen();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoVaultView extends StatelessWidget {
  const _NoVaultView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Vault フォルダが未設定です。\n'
          '「Settings」タブで iCloud Drive 上の Atelier フォルダを指定してください。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
