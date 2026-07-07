import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/library_import.dart';
import '../data/vault_config.dart';
import '../providers/reader_providers.dart';
import '../providers/vault_providers.dart';
import 'shell/mode_header.dart';
import 'theme/app_theme.dart';

/// Reader mode: displays the selected library paper's `paper.pdf`, with a
/// collapsible sidebar listing every indexed paper (DESIGN.md「4-2.」).
///
/// Phase 1 scope only (see DESIGN.md「8. Phase 1」): plain PDF display with
/// pdfrx's built-in page navigation/zoom. Highlighting/clips.json overlay is
/// Phase 2.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.config});

  final VaultConfig config;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _sidebarOpen = true;

  /// The open paper's title, resolved from the index for the header subtitle.
  String? _titleFor(String? folder) {
    if (folder == null) return null;
    final rows = ref.watch(papersProvider).value;
    if (rows == null) return folder;
    for (final row in rows) {
      if ((row['id'] ?? '').toString() == folder) {
        final title = (row['title'] ?? '').toString();
        return title.isEmpty ? folder : title;
      }
    }
    return folder;
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedPaperProvider);
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _titleFor(selected) ?? '論文を選んでください';

    return Column(
      children: [
        ModeHeader(
          title: '読む',
          subtitle: subtitle,
          actions: [
            if (!_sidebarOpen)
              OutlinedButton.icon(
                icon: const Icon(Icons.menu_open, size: 18),
                label: const Text('論文一覧'),
                onPressed: () => setState(() => _sidebarOpen = true),
              ),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: Row(
            children: [
              if (_sidebarOpen)
                Container(
                  width: 272,
                  color: scheme.surfaceContainerLow,
                  child: _PaperSidebar(
                    config: widget.config,
                    selected: selected,
                    onCollapse: () => setState(() => _sidebarOpen = false),
                  ),
                ),
              if (_sidebarOpen) const VerticalDivider(width: 1),
              Expanded(
                child: Container(
                  color: scheme.surfaceContainerLowest,
                  child: selected == null
                      ? const _EmptyReaderView()
                      : _PaperViewer(config: widget.config, folder: selected),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Left panel: title/author/year for every indexed paper, highlighting the
/// currently open one. Tapping a row switches the Reader to that paper.
class _PaperSidebar extends ConsumerWidget {
  const _PaperSidebar({
    required this.config,
    required this.selected,
    required this.onCollapse,
  });

  final VaultConfig config;
  final String? selected;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final papersAsync = ref.watch(papersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Text('論文一覧',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              IconButton(
                tooltip: '一覧を閉じる',
                icon: const Icon(Icons.menu_open),
                onPressed: onCollapse,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: papersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('読み込み失敗: $e')),
            data: (rows) {
              if (rows.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('論文がありません。ライブラリで追加してください。'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  final id = (row['id'] ?? '').toString();
                  final title = (row['title'] ?? '').toString();
                  final author = (row['author'] ?? '').toString();
                  final year = row['year'];
                  final hasPdf = File(config.paperPdfPath(id)).existsSync();
                  return _SidebarPaperRow(
                    title: title.isEmpty ? id : title,
                    meta: [
                      if (author.isNotEmpty) author,
                      if (year != null) '($year)',
                      if (!hasPdf) 'PDFなし',
                    ].join('  '),
                    hasPdf: hasPdf,
                    selected: id == selected,
                    onTap: () =>
                        ref.read(selectedPaperProvider.notifier).select(id),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// A compact, hover-responsive sidebar row — the library row's light cousin.
/// Selected rows carry the terracotta left accent used across the shell.
class _SidebarPaperRow extends StatefulWidget {
  const _SidebarPaperRow({
    required this.title,
    required this.meta,
    required this.hasPdf,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String meta;
  final bool hasPdf;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarPaperRow> createState() => _SidebarPaperRowState();
}

class _SidebarPaperRowState extends State<_SidebarPaperRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final bg = selected
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : _hover
            ? scheme.surfaceContainerHigh
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Selected accent bar.
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 3,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(9, 9, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (widget.meta.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: widget.hasPdf
                                ? scheme.onSurfaceVariant
                                : scheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The main content area for a selected paper: the PDF viewer, or (when no
/// `paper.pdf` exists yet — DESIGN.md「4-1.」metadata-only imports) a prompt
/// to attach one.
class _PaperViewer extends ConsumerStatefulWidget {
  const _PaperViewer({required this.config, required this.folder});

  final VaultConfig config;
  final String folder;

  @override
  ConsumerState<_PaperViewer> createState() => _PaperViewerState();
}

class _PaperViewerState extends ConsumerState<_PaperViewer> {
  bool _attaching = false;

  Future<void> _attachPdf() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'PDF を選択',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _attaching = true);
    try {
      await LibraryImport(widget.config)
          .attachPdf(key: widget.folder, sourcePdfPath: path);
      ref.invalidate(vaultScanProvider);
      ref.invalidate(papersProvider);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pdfPath = widget.config.paperPdfPath(widget.folder);
    final hasPdf = File(pdfPath).existsSync();
    final scheme = Theme.of(context).colorScheme;

    if (!hasPdf) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.picture_as_pdf_outlined,
                      size: 40, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Text('PDF が未添付です',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(widget.folder,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        )),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: _attaching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.attach_file, size: 18),
                  label: const Text('PDF を添付'),
                  onPressed: _attaching ? null : _attachPdf,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // A thin viewer toolbar: the header already carries the title, so this
        // stays quiet — just a way back to the empty state.
        Container(
          color: scheme.surfaceContainerLow.withValues(alpha: 0.6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            children: [
              IconButton(
                tooltip: '閉じる',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(selectedPaperProvider.notifier).select(null),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  widget.folder,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PdfViewer.file(
            pdfPath,
            // Key forces a fresh viewer (and controller) when the selected
            // paper changes, so page position/zoom don't leak across papers.
            key: ValueKey(pdfPath),
            params: PdfViewerParams(
              backgroundColor: scheme.surfaceContainerLowest,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyReaderView extends StatelessWidget {
  const _EmptyReaderView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = theme.extension<AtelierType>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 52, color: scheme.onSurfaceVariant),
              const SizedBox(height: 18),
              Text('論文を選んでください', style: type.displaySmall),
              const SizedBox(height: 8),
              Text(
                '左の一覧から論文を選ぶと、ここに PDF が開きます。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
