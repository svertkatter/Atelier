import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_delete.dart';
import '../data/library_import.dart';
import '../data/meta_md.dart';
import '../data/metadata/metadata_source.dart';
import '../data/project_store.dart';
import '../data/vault_config.dart';
import '../models/csl_metadata.dart';
import '../models/paper.dart';
import '../models/project.dart';
import '../providers/reader_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/shell_providers.dart';
import '../providers/vault_providers.dart';
import '../providers/writer_providers.dart';
import 'shell/mode_header.dart';
import 'theme/app_theme.dart';

/// Library mode: paper list (search), PDF/URL-DOI import flows, delete,
/// "add to project", and manual metadata editing.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, required this.config});

  final VaultConfig config;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 200), () => setState(() => _query = value));
  }

  Future<void> _startPdfImport() =>
      startPdfImport(context, ref, widget.config);

  /// URL/DOI-only import (DESIGN.md「4-1./8.」): no PDF is required up front;
  /// a PDF can be attached later from the Reader.
  Future<void> _startUrlImport() =>
      startUrlImport(context, ref, widget.config);

  @override
  Widget build(BuildContext context) {
    final papersAsync = ref.watch(papersProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModeHeader(
          title: '整える',
          subtitle: 'ライブラリ — 論文の保管と整理',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.link, size: 18),
              label: const Text('URL/DOI'),
              onPressed: _startUrlImport,
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('PDF をインポート'),
              onPressed: _startPdfImport,
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A light, borderless search — an icon and a fill, nothing more.
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'タイトル・著者・タグで検索',
                    fillColor: scheme.surfaceContainerLow,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: scheme.primary, width: 1.4),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: papersAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('読み込み失敗: $e')),
                    data: (allPapers) {
                      final index = ref.watch(vaultIndexProvider).value;
                      if (_query.trim().isEmpty || index == null) {
                        return _PaperList(
                          rows: allPapers,
                          config: widget.config,
                          ref: ref,
                          onImport: _startPdfImport,
                        );
                      }
                      return FutureBuilder<List<Map<String, Object?>>>(
                        future: index.searchPapers(_query.trim()),
                        builder: (context, snapshot) {
                          final rows =
                              snapshot.data ?? const <Map<String, Object?>>[];
                          return _PaperList(
                            rows: rows,
                            config: widget.config,
                            ref: ref,
                            onImport: _startPdfImport,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Starts the PDF import flow (file picker → metadata lookup → confirm). Shared
/// by the Library screen and the command palette so both reach the same dialog.
Future<void> startPdfImport(
    BuildContext context, WidgetRef ref, VaultConfig config) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'PDF を選択',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (result == null || result.files.isEmpty) return;
  final path = result.files.single.path;
  if (path == null) return;
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (context) => _ImportDialog(config: config, pdfPath: path),
  );
  ref.invalidate(vaultScanProvider);
  ref.invalidate(papersProvider);
}

/// Starts the URL/DOI-only import flow (no PDF up front — DESIGN.md「4-1./8.」).
Future<void> startUrlImport(
    BuildContext context, WidgetRef ref, VaultConfig config) async {
  await showDialog<void>(
    context: context,
    builder: (context) => _ImportDialog(config: config, pdfPath: null),
  );
  ref.invalidate(vaultScanProvider);
  ref.invalidate(papersProvider);
}

class _PaperList extends StatelessWidget {
  const _PaperList({
    required this.rows,
    required this.config,
    required this.ref,
    required this.onImport,
  });

  final List<Map<String, Object?>> rows;
  final VaultConfig config;
  final WidgetRef ref;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return _EmptyLibraryView(onImport: onImport);
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 8, endIndent: 8),
      itemBuilder: (context, i) {
        final row = rows[i];
        final id = (row['id'] ?? '').toString();
        final title = (row['title'] ?? '').toString();
        final author = (row['author'] ?? '').toString();
        final year = row['year'];
        final tags = (row['tags'] ?? '')
            .toString()
            .split(RegExp(r'[,\s、]+'))
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        final hasPdf = File(config.paperPdfPath(id)).existsSync();
        return _PaperRow(
          id: id,
          title: title.isEmpty ? id : title,
          author: author,
          year: year,
          tags: tags,
          hasPdf: hasPdf,
          onOpen: () {
            ref.read(selectedPaperProvider.notifier).select(id);
            ref.read(selectedModeProvider.notifier).select(AppMode.reader);
          },
          onAction: (action) => _handleAction(context, action, id),
        );
      },
    );
  }

  void _handleAction(BuildContext context, String action, String id) {
    switch (action) {
      case 'edit':
        _editMetadata(context, id);
      case 'addProject':
        _addToProject(context, id);
      case 'delete':
        _delete(context, id);
    }
  }

  Future<void> _editMetadata(BuildContext context, String folder) async {
    final file = File(config.metaMdPath(folder));
    if (!await file.exists()) return;
    final content = await file.readAsString();
    final paper = MetaMd.parse(content, folderName: folder);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _EditMetadataDialog(config: config, paper: paper),
    );
    ref.invalidate(vaultScanProvider);
    ref.invalidate(papersProvider);
  }

  Future<void> _addToProject(BuildContext context, String key) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _AddToProjectDialog(config: config, paperKey: key),
    );
  }

  Future<void> _delete(BuildContext context, String key) async {
    final deleter = LibraryDelete(config);
    final referencing = await deleter.projectsReferencing(key);
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _DeleteConfirmDialog(paperKey: key, referencingProjects: referencing),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await deleter.delete(key);
      ref.invalidate(vaultScanProvider);
      ref.invalidate(papersProvider);
      ref.invalidate(projectsProvider);
      ref.invalidate(writerProjectsProvider);
      messenger.showSnackBar(SnackBar(content: Text('$key を削除しました')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    }
  }
}

/// A single library entry row. Hovering lifts the background and cross-fades
/// the editorial year (mincho) into the row's actions — add-to-project, edit,
/// delete — which only surface on hover. Tapping the row opens it in the Reader.
class _PaperRow extends StatefulWidget {
  const _PaperRow({
    required this.id,
    required this.title,
    required this.author,
    required this.year,
    required this.tags,
    required this.hasPdf,
    required this.onOpen,
    required this.onAction,
  });

  final String id;
  final String title;
  final String author;
  final Object? year;
  final List<String> tags;
  final bool hasPdf;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  State<_PaperRow> createState() => _PaperRowState();
}

class _PaperRowState extends State<_PaperRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = theme.extension<AtelierType>()!;
    final year = widget.year;
    final meta = [
      if (widget.author.isNotEmpty) widget.author,
      if (widget.hasPdf == false) 'PDFなし',
    ];

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onOpen,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover ? scheme.surfaceContainerHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        meta.join('  ·  '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: widget.hasPdf
                              ? scheme.onSurfaceVariant
                              : scheme.error,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (widget.tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final tag in widget.tags) _TagChip(label: tag),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Right cluster: the editorial year gives way to the row actions
              // on hover — no reflow, just a cross-fade in a fixed gutter.
              SizedBox(
                width: 132,
                height: 40,
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: [
                    IgnorePointer(
                      ignoring: _hover,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _hover ? 0 : 1,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: year == null
                              ? const SizedBox.shrink()
                              : Text(
                                  '$year',
                                  style: type.displaySmall.copyWith(
                                    fontSize: 18,
                                    letterSpacing: 0.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      ignoring: !_hover,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _hover ? 1 : 0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            _RowAction(
                              icon: Icons.playlist_add,
                              tooltip: 'プロジェクトへ追加',
                              onTap: () => widget.onAction('addProject'),
                            ),
                            _RowAction(
                              icon: Icons.edit_outlined,
                              tooltip: 'メタデータを編集',
                              onTap: () => widget.onAction('edit'),
                            ),
                            _RowAction(
                              icon: Icons.delete_outline,
                              tooltip: '削除',
                              danger: true,
                              onTap: () => widget.onAction('delete'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact hover-revealed row action icon.
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      color: danger ? scheme.error : scheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}

/// A light text tag (`#tag`) — lighter than a Material [Chip]: a tinted fill,
/// no border, muted ink.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '#$label',
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Shown when the library has no entries: a mincho heading, guidance, and the
/// primary import action.
class _EmptyLibraryView extends StatelessWidget {
  const _EmptyLibraryView({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = theme.extension<AtelierType>()!;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.local_library_outlined,
                  size: 44, color: scheme.primary),
            ),
            const SizedBox(height: 24),
            Text('まだ論文がありません', style: type.displaySmall),
            const SizedBox(height: 8),
            Text(
              '「PDF をインポート」または「URL/DOI」から\n最初の論文を迎え入れましょう。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.upload_file, size: 18),
              label: const Text('PDF をインポート'),
              onPressed: onImport,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog for deleting a library entry: warns which projects
/// (if any) currently reference it, since their `refs` will be scrubbed too.
class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({
    required this.paperKey,
    required this.referencingProjects,
  });

  final String paperKey;
  final List<Project> referencingProjects;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('論文を削除しますか？'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$paperKey を library/ から完全に削除します。この操作は取り消せません。'),
            const SizedBox(height: 12),
            if (referencingProjects.isEmpty)
              const Text('この論文を参照しているプロジェクトはありません。')
            else ...[
              Text('この論文を参照しているプロジェクト（削除後、参照は自動で外れます）:',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              for (final project in referencingProjects)
                Text('・${project.name}'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('削除する'),
        ),
      ],
    );
  }
}

/// Lets the user add a paper to an existing project (or create a new one on
/// the spot) via [ProjectStore.ensureRef].
class _AddToProjectDialog extends ConsumerStatefulWidget {
  const _AddToProjectDialog({required this.config, required this.paperKey});

  final VaultConfig config;
  final String paperKey;

  @override
  ConsumerState<_AddToProjectDialog> createState() =>
      _AddToProjectDialogState();
}

class _AddToProjectDialogState extends ConsumerState<_AddToProjectDialog> {
  final _newProjectController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _newProjectController.dispose();
    super.dispose();
  }

  Future<void> _addToExisting(Project project) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = await ref.read(projectStoreProvider.future);
      if (store == null) throw StateError('Vault が未設定です');
      await store.ensureRef(project, widget.paperKey);
      ref.invalidate(vaultScanProvider);
      ref.invalidate(writerProjectsProvider);
      ref.invalidate(projectsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
          SnackBar(content: Text('${project.name} に追加しました')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '追加に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndAdd() async {
    final name = _newProjectController.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = await ref.read(projectStoreProvider.future);
      if (store == null) throw StateError('Vault が未設定です');
      final project = await store.create(name: name);
      await store.ensureRef(project, widget.paperKey);
      ref.invalidate(vaultScanProvider);
      ref.invalidate(writerProjectsProvider);
      ref.invalidate(projectsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text('$name を作成して追加しました')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(writerProjectsProvider);
    return AlertDialog(
      title: Text('${widget.paperKey} をプロジェクトへ追加'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 200,
              child: projectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('読み込み失敗: $e')),
                data: (projects) {
                  if (projects.isEmpty) {
                    return const Center(child: Text('プロジェクトがありません。下から新規作成できます。'));
                  }
                  return ListView.builder(
                    itemCount: projects.length,
                    itemBuilder: (context, i) {
                      final project = projects[i];
                      final already = project.refs.contains(widget.paperKey);
                      return ListTile(
                        dense: true,
                        title: Text(project.name),
                        subtitle: Text('参照 ${project.refs.length} 件'),
                        trailing: already
                            ? const Icon(Icons.check, size: 18)
                            : const Icon(Icons.add, size: 18),
                        enabled: !_busy && !already,
                        onTap: already ? null : () => _addToExisting(project),
                      );
                    },
                  );
                },
              ),
            ),
            const Divider(height: 24),
            Text('新規プロジェクトを作成して追加',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newProjectController,
                    decoration: const InputDecoration(labelText: 'プロジェクト名'),
                    onSubmitted: (_) => _createAndAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _createAndAdd,
                  child: const Text('作成して追加'),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

/// PDF/URL-DOI import flow: DOI/CiNii URL/J-STAGE URL input -> metadata lookup
/// (DESIGN.md「6.」priority chain) -> confirm/edit form -> write library/{key}/.
///
/// When [pdfPath] is null (URL/DOI-only import — DESIGN.md「4-1./8.」), the
/// resulting library entry has no `paper.pdf`; one can be attached later from
/// the Reader.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.config, required this.pdfPath});

  final VaultConfig config;
  final String? pdfPath;

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _identifierController = TextEditingController();
  bool _looking = false;
  String? _error;
  CslMetadata? _resolved;
  MetadataSource? _resolvedSource;

  @override
  void dispose() {
    _identifierController.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final text = _identifierController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _looking = true;
      _error = null;
    });
    try {
      final lookup = await ref.read(metadataLookupProvider.future);
      final result = await lookup.lookup(text);
      if (!mounted) return;
      setState(() {
        _looking = false;
        if (result == null) {
          _error = '該当するメタデータが見つかりませんでした。手動で入力してください。';
          _resolved = CslMetadata(id: '', title: '');
          _resolvedSource = MetadataSource.manual;
        } else {
          _resolved = result.metadata;
          _resolvedSource = result.source;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _looking = false;
        _error = '取得に失敗しました: $e\n手動で入力してください。';
        _resolved = CslMetadata(id: '', title: '');
        _resolvedSource = MetadataSource.manual;
      });
    }
  }

  void _skipToManual() {
    setState(() {
      _resolved = CslMetadata(id: '', title: '');
      _resolvedSource = MetadataSource.manual;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved;
    if (resolved != null) {
      return _ConfirmMetadataDialog(
        config: widget.config,
        pdfPath: widget.pdfPath,
        initialMetadata: resolved,
        source: _resolvedSource ?? MetadataSource.manual,
      );
    }

    return AlertDialog(
      title: const Text('メタデータを取得'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DOI・CiNii URL・J-STAGE URL を入力してください。',
                style: Theme.of(context).textTheme.bodySmall),
            if (widget.pdfPath == null) ...[
              const SizedBox(height: 4),
              Text('PDF は後から添付できます。',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _identifierController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'DOI / CiNii URL / J-STAGE URL',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _lookup(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _skipToManual,
          child: const Text('手動入力に進む'),
        ),
        FilledButton(
          onPressed: _looking ? null : _lookup,
          child: _looking
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('取得'),
        ),
      ],
    );
  }
}

/// Confirmation/edit form shown after a lookup (or when going straight to
/// manual entry): author/title/journal/year/volume/issue/page + tags.
class _ConfirmMetadataDialog extends ConsumerStatefulWidget {
  const _ConfirmMetadataDialog({
    required this.config,
    required this.pdfPath,
    required this.initialMetadata,
    required this.source,
  });

  final VaultConfig config;
  final String? pdfPath;
  final CslMetadata initialMetadata;
  final MetadataSource source;

  @override
  ConsumerState<_ConfirmMetadataDialog> createState() =>
      _ConfirmMetadataDialogState();
}

class _ConfirmMetadataDialogState extends ConsumerState<_ConfirmMetadataDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _familyController;
  late final TextEditingController _givenController;
  late final TextEditingController _containerController;
  late final TextEditingController _yearController;
  late final TextEditingController _volumeController;
  late final TextEditingController _issueController;
  late final TextEditingController _pageController;
  late final TextEditingController _doiController;
  late final TextEditingController _tagsController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final m = widget.initialMetadata;
    final firstAuthor = m.authors.isNotEmpty ? m.authors.first : null;
    _titleController = TextEditingController(text: m.title ?? '');
    _familyController = TextEditingController(
        text: firstAuthor?.family ?? firstAuthor?.literal ?? '');
    _givenController = TextEditingController(text: firstAuthor?.given ?? '');
    _containerController = TextEditingController(text: m.containerTitle ?? '');
    _yearController = TextEditingController(text: m.year?.toString() ?? '');
    _volumeController = TextEditingController(text: m.volume ?? '');
    _issueController = TextEditingController(text: m.issue ?? '');
    _pageController = TextEditingController(text: m.page ?? '');
    _doiController = TextEditingController(text: m.doi ?? '');
    _tagsController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _familyController.dispose();
    _givenController.dispose();
    _containerController.dispose();
    _yearController.dispose();
    _volumeController.dispose();
    _issueController.dispose();
    _pageController.dispose();
    _doiController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final year = int.tryParse(_yearController.text.trim());
      final family = _familyController.text.trim();
      final given = _givenController.text.trim();
      final metadata = CslMetadata(
        id: widget.initialMetadata.id,
        type: widget.initialMetadata.type ?? 'article-journal',
        title: _titleController.text.trim(),
        authors: family.isEmpty
            ? const <CslName>[]
            : [CslName(family: family, given: given.isEmpty ? null : given)],
        issuedDateParts: year != null
            ? [
                [year]
              ]
            : null,
        containerTitle: _containerController.text.trim().isEmpty
            ? null
            : _containerController.text.trim(),
        volume: _volumeController.text.trim().isEmpty
            ? null
            : _volumeController.text.trim(),
        issue: _issueController.text.trim().isEmpty
            ? null
            : _issueController.text.trim(),
        page: _pageController.text.trim().isEmpty
            ? null
            : _pageController.text.trim(),
        doi: _doiController.text.trim().isEmpty
            ? null
            : _doiController.text.trim(),
      );

      final index = await ref.read(vaultIndexProvider.future);
      final existingRows = await index.allPapers();
      final existingKeys =
          existingRows.map((r) => (r['id'] ?? '').toString()).toSet();

      final tags = _tagsController.text
          .split(RegExp(r'[,\s、]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final importer = LibraryImport(widget.config);
      final paper = await importer.importPaper(
        sourcePdfPath: widget.pdfPath,
        metadata: metadata,
        tags: tags,
        source: widget.source.id,
        doi: metadata.doi,
        existingKeys: existingKeys,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      final label = paper.metadata.title?.trim().isNotEmpty == true
          ? paper.metadata.title!.trim()
          : paper.effectiveFolderName;
      messenger.showSnackBar(SnackBar(content: Text('$label をライブラリに追加しました')));
    } catch (e) {
      if (mounted) setState(() => _error = '追加に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('メタデータの確認'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'タイトル'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _familyController,
                      decoration: const InputDecoration(labelText: '著者（姓）'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _givenController,
                      decoration: const InputDecoration(labelText: '著者（名）'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _containerController,
                decoration: const InputDecoration(labelText: '誌名'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _yearController,
                      decoration: const InputDecoration(labelText: '年'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _volumeController,
                      decoration: const InputDecoration(labelText: '巻'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _issueController,
                      decoration: const InputDecoration(labelText: '号'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _pageController,
                decoration: const InputDecoration(labelText: '頁'),
              ),
              TextField(
                controller: _doiController,
                decoration: const InputDecoration(labelText: 'DOI'),
              ),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(labelText: 'タグ（カンマ区切り）'),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ]
                .map((w) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: w,
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ライブラリに追加'),
        ),
      ],
    );
  }
}

/// Manual metadata edit form for an existing library entry (title/author/
/// journal/year/volume/issue/page/tags). Overwrites meta.md via
/// [LibraryImport.saveMetadata].
class _EditMetadataDialog extends ConsumerStatefulWidget {
  const _EditMetadataDialog({required this.config, required this.paper});

  final VaultConfig config;
  final Paper paper;

  @override
  ConsumerState<_EditMetadataDialog> createState() => _EditMetadataDialogState();
}

class _EditMetadataDialogState extends ConsumerState<_EditMetadataDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _familyController;
  late final TextEditingController _givenController;
  late final TextEditingController _containerController;
  late final TextEditingController _yearController;
  late final TextEditingController _tagsController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.paper.metadata;
    final firstAuthor = m.authors.isNotEmpty ? m.authors.first : null;
    _titleController = TextEditingController(text: m.title ?? '');
    _familyController = TextEditingController(
        text: firstAuthor?.family ?? firstAuthor?.literal ?? '');
    _givenController = TextEditingController(text: firstAuthor?.given ?? '');
    _containerController = TextEditingController(text: m.containerTitle ?? '');
    _yearController = TextEditingController(text: m.year?.toString() ?? '');
    _tagsController = TextEditingController(text: widget.paper.tags.join(', '));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _familyController.dispose();
    _givenController.dispose();
    _containerController.dispose();
    _yearController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final m = widget.paper.metadata;
      final year = int.tryParse(_yearController.text.trim());
      final family = _familyController.text.trim();
      final given = _givenController.text.trim();

      final updatedMetadata = CslMetadata(
        id: m.id,
        type: m.type,
        title: _titleController.text.trim(),
        authors: family.isEmpty
            ? const <CslName>[]
            : [CslName(family: family, given: given.isEmpty ? null : given)],
        issuedDateParts: year != null
            ? [
                [year]
              ]
            : m.issuedDateParts,
        containerTitle: _containerController.text.trim().isEmpty
            ? null
            : _containerController.text.trim(),
        volume: m.volume,
        issue: m.issue,
        page: m.page,
        doi: m.doi,
        url: m.url,
        publisher: m.publisher,
        abstractText: m.abstractText,
        extra: m.extra,
      );

      final tags = _tagsController.text
          .split(RegExp(r'[,\s、]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final updated =
          widget.paper.copyWith(metadata: updatedMetadata, tags: tags);
      await LibraryImport(widget.config).saveMetadata(updated);

      if (!mounted) return;
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('メタデータを編集'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'タイトル'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _familyController,
                      decoration: const InputDecoration(labelText: '著者（姓）'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _givenController,
                      decoration: const InputDecoration(labelText: '著者（名）'),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _containerController,
                decoration: const InputDecoration(labelText: '誌名'),
              ),
              TextField(
                controller: _yearController,
                decoration: const InputDecoration(labelText: '年'),
              ),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(labelText: 'タグ（カンマ区切り）'),
              ),
            ]
                .map((w) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: w,
                    ))
                .toList(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}
