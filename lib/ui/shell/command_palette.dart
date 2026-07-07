import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/reader_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/shell_providers.dart';
import '../../providers/vault_providers.dart';
import '../library_screen.dart' show startPdfImport, startUrlImport;
import '../theme/app_theme.dart';

/// Opens the Ctrl+K command palette. The palette itself is side-effect free:
/// it returns the chosen [_PaletteResult], and this launcher runs it against a
/// live (still-mounted) context so import dialogs and navigation land cleanly.
Future<void> showCommandPalette(BuildContext context, WidgetRef ref) async {
  final result = await showDialog<_PaletteResult>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (_) => const CommandPalette(),
  );
  if (result == null || !context.mounted) return;
  await result.run(context, ref);
}

/// The deferred effect of choosing a palette entry, executed by the launcher
/// after the palette has closed.
class _PaletteResult {
  const _PaletteResult(this.run);
  final Future<void> Function(BuildContext context, WidgetRef ref) run;
}

/// A single palette entry — a fixed action or a paper search hit.
class _Item {
  const _Item({
    required this.icon,
    required this.label,
    required this.result,
    this.sub,
    this.trailing,
    this.keywords = const <String>[],
    this.isPaper = false,
  });

  final IconData icon;
  final String label;

  /// Secondary line (paper author, or an action gloss).
  final String? sub;

  /// Trailing accent — the mincho year on paper rows.
  final String? trailing;
  final List<String> keywords;
  final bool isPaper;
  final _PaletteResult result;

  bool matches(String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    if (label.toLowerCase().contains(needle)) return true;
    for (final k in keywords) {
      if (k.toLowerCase().contains(needle)) return true;
    }
    return false;
  }
}

/// The Ctrl+K command palette: one input, one list. Search the library or jump
/// to a mode / import / setting — entirely from the keyboard (↑↓ to move,
/// Enter to run, Esc to close).
class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  static const double _itemExtent = 56;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _keyboardFocus = FocusNode();

  Timer? _debounce;
  String _query = '';
  List<Map<String, Object?>> _papers = const [];
  int _selected = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Fixed actions
  // ---------------------------------------------------------------------

  List<_Item> get _actions => [
        _Item(
          icon: Icons.collections_bookmark_outlined,
          label: '整える（ライブラリ）へ移動',
          keywords: const ['library', 'ライブラリ', 'せいとえる', 'move'],
          result: _navResult(AppMode.library),
        ),
        _Item(
          icon: Icons.menu_book_outlined,
          label: '読む（リーダー）へ移動',
          keywords: const ['reader', 'リーダー', 'よむ', 'move'],
          result: _navResult(AppMode.reader),
        ),
        _Item(
          icon: Icons.edit_outlined,
          label: '書く（ライター）へ移動',
          keywords: const ['writer', 'ライター', 'かく', 'move'],
          result: _navResult(AppMode.writer),
        ),
        _Item(
          icon: Icons.upload_file,
          label: 'PDF をインポート',
          keywords: const ['import', 'pdf', 'インポート'],
          result: _PaletteResult((context, ref) async {
            final config = ref.read(vaultConfigProvider).value;
            if (config == null) {
              _requireVault(context, ref);
              return;
            }
            await startPdfImport(context, ref, config);
          }),
        ),
        _Item(
          icon: Icons.link,
          label: 'URL / DOI からインポート',
          keywords: const ['url', 'doi', 'import', 'インポート'],
          result: _PaletteResult((context, ref) async {
            final config = ref.read(vaultConfigProvider).value;
            if (config == null) {
              _requireVault(context, ref);
              return;
            }
            await startUrlImport(context, ref, config);
          }),
        ),
        _Item(
          icon: Icons.brightness_6_outlined,
          label: 'テーマ切替',
          keywords: const ['theme', 'テーマ', 'dark', 'light', 'ダーク', 'ライト'],
          result: _PaletteResult((context, ref) async {
            const order = [
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ];
            final mode = ref.read(themeModeProvider);
            final next = order[(order.indexOf(mode) + 1) % order.length];
            await ref.read(appSettingsProvider.notifier).setThemeMode(next);
          }),
        ),
        _Item(
          icon: Icons.settings_outlined,
          label: '設定',
          keywords: const ['settings', '設定', 'preferences'],
          result: _navResult(AppMode.settings),
        ),
      ];

  _PaletteResult _navResult(AppMode mode) => _PaletteResult((context, ref) async {
        ref.read(selectedModeProvider.notifier).select(mode);
      });

  static void _requireVault(BuildContext context, WidgetRef ref) {
    ref.read(selectedModeProvider.notifier).select(AppMode.settings);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('先に Vault フォルダを設定してください')),
    );
  }

  // ---------------------------------------------------------------------
  // Item assembly
  // ---------------------------------------------------------------------

  List<_Item> get _items {
    final actions = _actions.where((a) => a.matches(_query)).toList();
    final papers = _papers.map((row) {
      final id = (row['id'] ?? '').toString();
      final title = (row['title'] ?? '').toString();
      final author = (row['author'] ?? '').toString();
      final year = row['year'];
      return _Item(
        icon: Icons.article_outlined,
        label: title.isEmpty ? id : title,
        sub: author.isEmpty ? '@$id' : author,
        trailing: year?.toString(),
        isPaper: true,
        result: _PaletteResult((context, ref) async {
          ref.read(selectedPaperProvider.notifier).select(id);
          ref.read(selectedModeProvider.notifier).select(AppMode.reader);
        }),
      );
    });
    return [...actions, ...papers];
  }

  // ---------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () => _search(value));
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _query = '';
        _papers = const [];
        _selected = 0;
      });
      return;
    }
    final index = await ref.read(vaultIndexProvider.future);
    final rows = await index.searchPapers(q);
    if (!mounted) return;
    setState(() {
      _query = q;
      _papers = rows;
      _selected = 0;
    });
  }

  // ---------------------------------------------------------------------
  // Keyboard
  // ---------------------------------------------------------------------

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int delta) {
    final count = _items.length;
    if (count == 0) return;
    setState(() => _selected = (_selected + delta).clamp(0, count - 1));
    _ensureVisible();
  }

  void _ensureVisible() {
    if (!_scrollController.hasClients) return;
    final target = _selected * _itemExtent;
    final offset = _scrollController.offset;
    final viewport = _scrollController.position.viewportDimension;
    if (target < offset) {
      _scrollController.animateTo(target,
          duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    } else if (target + _itemExtent > offset + viewport) {
      _scrollController.animateTo(target + _itemExtent - viewport,
          duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    }
  }

  void _execute() {
    final items = _items;
    if (items.isEmpty) return;
    final index = _selected.clamp(0, items.length - 1);
    Navigator.of(context).pop(items[index].result);
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = _items;
    if (_selected >= items.length && items.isNotEmpty) {
      _selected = items.length - 1;
    }

    return Align(
      alignment: const Alignment(0, -0.55),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Material(
            color: scheme.surfaceContainerLow,
            elevation: 16,
            borderRadius: BorderRadius.circular(12),
            surfaceTintColor: Colors.transparent,
            child: Focus(
              focusNode: _keyboardFocus,
              onKeyEvent: _onKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      style: theme.textTheme.titleMedium,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: '論文を検索、またはコマンドを実行…',
                        fillColor: scheme.surfaceContainerLowest,
                      ),
                      onChanged: _onQueryChanged,
                      onSubmitted: (_) => _execute(),
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(28),
                            child: Text(
                              '該当する項目がありません',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant),
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 360),
                            child: ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemExtent: _itemExtent,
                              itemCount: items.length,
                              itemBuilder: (context, i) => _PaletteRow(
                                item: items[i],
                                selected: i == _selected,
                                onHover: () => setState(() => _selected = i),
                                onTap: () {
                                  setState(() => _selected = i);
                                  _execute();
                                },
                              ),
                            ),
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    child: Row(
                      children: [
                        _Hint(text: '↑↓ 移動'),
                        const SizedBox(width: 14),
                        _Hint(text: 'Enter 実行'),
                        const SizedBox(width: 14),
                        _Hint(text: 'Esc 閉じる'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.item,
    required this.selected,
    required this.onHover,
    required this.onTap,
  });

  final _Item item;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = theme.extension<AtelierType>()!;
    return MouseRegion(
      onEnter: (_) => onHover(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 19,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ),
                    if (item.sub != null && item.sub!.isNotEmpty)
                      Text(
                        item.sub!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
              if (item.trailing != null && item.trailing!.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  item.trailing!,
                  style: type.displaySmall.copyWith(
                    fontSize: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            letterSpacing: 0.4,
          ),
    );
  }
}
