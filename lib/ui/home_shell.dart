import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shell_providers.dart';
import '../providers/vault_providers.dart';
import 'library_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'shell/title_bar.dart';
import 'theme/app_theme.dart';
import 'theme/theme_toggle.dart';
import 'writer_screen.dart';

/// The app shell.
///
/// Atelier's policy —「整える・読む・書く」— *is* the navigation: the three
/// primary modes are presented as verbs (set in mincho display type) in a
/// custom sidebar, under an integrated title bar with custom window chrome.
/// The selected mode lives in [selectedModeProvider] so other screens can
/// drive navigation (e.g. tapping a paper row auto-switches to the Reader).
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(vaultConfigProvider);
    final selected = ref.watch(selectedModeProvider);

    void select(AppMode mode) =>
        ref.read(selectedModeProvider.notifier).select(mode);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            select(AppMode.library),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            select(AppMode.reader),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            select(AppMode.writer),
        const SingleActivator(LogicalKeyboardKey.comma, control: true): () =>
            select(AppMode.settings),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              const AtelierTitleBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 1000;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AtelierSidebar(
                          selected: selected,
                          onSelect: select,
                          compact: compact,
                        ),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.012),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(selected),
                              child: _buildMode(configAsync, selected),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMode(AsyncValue<dynamic> configAsync, AppMode selected) {
    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (config) {
        // Settings is always reachable (needed for first-run setup).
        if (selected == AppMode.settings) return const SettingsScreen();
        if (config == null) return const _NoVaultView();
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
    );
  }
}

/// Sidebar entry metadata: the verb, its small-caps English sublabel, icon.
class _ModeEntry {
  const _ModeEntry(this.mode, this.verb, this.sub, this.icon, this.iconFilled);

  final AppMode mode;
  final String verb;
  final String sub;
  final IconData icon;
  final IconData iconFilled;
}

const _entries = <_ModeEntry>[
  _ModeEntry(AppMode.library, '整える', 'LIBRARY',
      Icons.collections_bookmark_outlined, Icons.collections_bookmark),
  _ModeEntry(AppMode.reader, '読む', 'READER', Icons.menu_book_outlined,
      Icons.menu_book),
  _ModeEntry(
      AppMode.writer, '書く', 'WRITER', Icons.edit_outlined, Icons.edit),
];

/// The verb-led sidebar. Wide (200px) with verbs + sublabels, collapsing to a
/// slim icon rail below 1000px of window width.
class _AtelierSidebar extends StatelessWidget {
  const _AtelierSidebar({
    required this.selected,
    required this.onSelect,
    required this.compact,
  });

  final AppMode selected;
  final ValueChanged<AppMode> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: compact ? 64 : 200,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 14),
          for (final entry in _entries)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: _ModeItem(
                entry: entry,
                selected: selected == entry.mode,
                compact: compact,
                onTap: () => onSelect(entry.mode),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(10),
            child: compact
                ? Column(
                    children: [
                      const ThemeToggleButton(),
                      const SizedBox(height: 2),
                      _SettingsButton(
                        selected: selected == AppMode.settings,
                        onTap: () => onSelect(AppMode.settings),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SettingsButton(
                        selected: selected == AppMode.settings,
                        onTap: () => onSelect(AppMode.settings),
                      ),
                      const ThemeToggleButton(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModeItem extends StatefulWidget {
  const _ModeItem({
    required this.entry,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final _ModeEntry entry;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_ModeItem> createState() => _ModeItemState();
}

class _ModeItemState extends State<_ModeItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = Theme.of(context).extension<AtelierType>()!;
    final selected = widget.selected;

    final bg = selected
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : _hover
            ? scheme.surfaceContainerHigh
            : Colors.transparent;
    final iconColor = selected ? scheme.primary : scheme.onSurfaceVariant;

    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: widget.compact ? 44 : 52,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Stack(
            children: [
              // Terracotta accent bar on the selected item — a brush of ink.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                left: 0,
                top: selected ? 10 : 22,
                bottom: selected ? 10 : 22,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 160),
                  opacity: selected ? 1 : 0,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              widget.compact
                  ? Center(
                      child: Icon(
                        selected ? widget.entry.iconFilled : widget.entry.icon,
                        size: 21,
                        color: iconColor,
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? widget.entry.iconFilled
                                : widget.entry.icon,
                            size: 20,
                            color: iconColor,
                          ),
                          const SizedBox(width: 12),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.entry.verb,
                                style: type.verb.copyWith(
                                  fontSize: 15,
                                  color: selected
                                      ? scheme.onSurface
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                widget.entry.sub,
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w600,
                                  color: (selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant)
                                      .withValues(alpha: 0.8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ],
          ),
        ),
      ),
    );

    return widget.compact
        ? Tooltip(
            message: '${widget.entry.verb}（${widget.entry.sub}）',
            waitDuration: const Duration(milliseconds: 400),
            child: item,
          )
        : item;
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '設定（Ctrl+,）',
      isSelected: selected,
      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
      style: selected
          ? IconButton.styleFrom(backgroundColor: scheme.primaryContainer)
          : null,
      icon: Icon(selected ? Icons.settings : Icons.settings_outlined),
      onPressed: onTap,
    );
  }
}

class _NoVaultView extends StatelessWidget {
  const _NoVaultView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final type = Theme.of(context).extension<AtelierType>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_special_outlined,
                  size: 52, color: scheme.primary),
              const SizedBox(height: 24),
              Text('アトリエをひらく', style: type.displaySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Vault フォルダが未設定です。「設定」から iCloud Drive 上の Atelier フォルダを指定してください。',
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
