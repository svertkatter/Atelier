import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/settings_providers.dart';

/// Icon/label metadata for each [ThemeMode].
({IconData icon, String label}) _modeInfo(ThemeMode mode) => switch (mode) {
      ThemeMode.system => (icon: Icons.brightness_auto_outlined, label: 'システム'),
      ThemeMode.light => (icon: Icons.light_mode_outlined, label: 'ライト'),
      ThemeMode.dark => (icon: Icons.dark_mode_outlined, label: 'ダーク'),
    };

/// A compact icon button that cycles system → light → dark → system. Used in
/// the navigation rail for quick appearance switching.
class ThemeToggleButton extends ConsumerWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final info = _modeInfo(mode);
    return IconButton(
      tooltip: '外観: ${info.label}（切替）',
      icon: Icon(info.icon),
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: () {
        const order = [ThemeMode.system, ThemeMode.light, ThemeMode.dark];
        final next = order[(order.indexOf(mode) + 1) % order.length];
        ref.read(appSettingsProvider.notifier).setThemeMode(next);
      },
    );
  }
}

/// A three-way segmented control for the Settings screen's appearance section.
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: [
        for (final m in ThemeMode.values)
          ButtonSegment<ThemeMode>(
            value: m,
            icon: Icon(_modeInfo(m).icon),
            label: Text(_modeInfo(m).label),
          ),
      ],
      selected: {mode},
      onSelectionChanged: (sel) =>
          ref.read(appSettingsProvider.notifier).setThemeMode(sel.first),
    );
  }
}
