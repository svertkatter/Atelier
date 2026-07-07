import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_providers.dart';
import '../providers/vault_providers.dart';
import 'library_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'theme/theme_toggle.dart';
import 'writer_screen.dart';

/// The app shell: Library / Reader / Writer modes plus Settings, behind a
/// refined [NavigationRail]. When no vault root is configured, every mode
/// except Settings shows a prompt to configure one first (Settings is always
/// reachable so first-run setup is possible).
///
/// The selected mode lives in [selectedModeProvider] (not local State) so
/// other screens can navigate here directly — e.g. tapping a paper row in the
/// Library auto-switches to the Reader (DESIGN.md「4-2.」自動遷移).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _modes = [AppMode.library, AppMode.reader, AppMode.writer];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(vaultConfigProvider);
    final selected = ref.watch(selectedModeProvider);
    final railIndex = _modes.indexOf(selected);

    return Scaffold(
      body: Row(
        children: [
          _AtelierRail(
            selectedIndex: railIndex >= 0 ? railIndex : null,
            settingsSelected: selected == AppMode.settings,
            onSelect: (mode) =>
                ref.read(selectedModeProvider.notifier).select(mode),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: configAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
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

/// The left navigation rail: an Atelier wordmark, the three primary modes, and
/// — pinned to the bottom — a quick appearance toggle and Settings.
class _AtelierRail extends StatelessWidget {
  const _AtelierRail({
    required this.selectedIndex,
    required this.settingsSelected,
    required this.onSelect,
  });

  final int? selectedIndex;
  final bool settingsSelected;
  final ValueChanged<AppMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) => onSelect(HomeShell._modes[i]),
      labelType: NavigationRailLabelType.all,
      groupAlignment: -0.85,
      leading: const Padding(
        padding: EdgeInsets.only(top: 8, bottom: 12),
        child: _Wordmark(),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.auto_stories_outlined),
          selectedIcon: Icon(Icons.auto_stories),
          label: Text('Library'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.menu_book_outlined),
          selectedIcon: Icon(Icons.menu_book),
          label: Text('Reader'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.draw_outlined),
          selectedIcon: Icon(Icons.draw),
          label: Text('Writer'),
        ),
      ],
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ThemeToggleButton(),
                const SizedBox(height: 4),
                IconButton(
                  tooltip: '設定',
                  isSelected: settingsSelected,
                  color: settingsSelected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  style: settingsSelected
                      ? IconButton.styleFrom(
                          backgroundColor: scheme.primaryContainer)
                      : null,
                  icon: Icon(settingsSelected
                      ? Icons.settings
                      : Icons.settings_outlined),
                  onPressed: () => onSelect(AppMode.settings),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact "A" mark used at the top of the navigation rail.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Atelier',
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          'A',
          style: TextStyle(
            color: scheme.onPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _NoVaultView extends StatelessWidget {
  const _NoVaultView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_special_outlined,
                  size: 56, color: scheme.primary),
              const SizedBox(height: 20),
              Text(
                'Vault フォルダが未設定です',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '「設定」から iCloud Drive 上の Atelier フォルダを指定してください。',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
