import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/library_import.dart';
import '../data/meta_md.dart';
import '../data/metadata/metadata_source.dart';
import '../data/vault_config.dart';
import '../models/csl_metadata.dart';
import '../models/paper.dart';
import '../providers/reader_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/vault_providers.dart';

/// Library mode: paper list (search), PDF import flow, and manual metadata
/// editing. Phase 1c scope — no highlighting yet (Phase 2).
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

  Future<void> _startImport() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'PDF を選択',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => _ImportDialog(config: widget.config, pdfPath: path),
    );
    ref.invalidate(vaultScanProvider);
    ref.invalidate(papersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final papersAsync = ref.watch(papersProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('ライブラリ', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('PDF をインポート'),
                onPressed: _startImport,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'タイトル・著者・タグで検索',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: papersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('読み込み失敗: $e')),
              data: (allPapers) {
                final index = ref.watch(vaultIndexProvider).value;
                if (_query.trim().isEmpty || index == null) {
                  return _PaperList(rows: allPapers, config: widget.config, ref: ref);
                }
                return FutureBuilder<List<Map<String, Object?>>>(
                  future: index.searchPapers(_query.trim()),
                  builder: (context, snapshot) {
                    final rows = snapshot.data ?? const <Map<String, Object?>>[];
                    return _PaperList(rows: rows, config: widget.config, ref: ref);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PaperList extends StatelessWidget {
  const _PaperList({required this.rows, required this.config, required this.ref});

  final List<Map<String, Object?>> rows;
  final VaultConfig config;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Center(child: Text('論文がありません。「PDF をインポート」から追加してください。'));
    }
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final row = rows[i];
        final id = (row['id'] ?? '').toString();
        final title = (row['title'] ?? '').toString();
        final author = (row['author'] ?? '').toString();
        final year = row['year'];
        final tags = (row['tags'] ?? '').toString();
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(title.isEmpty ? id : title),
          subtitle: Text([
            if (author.isNotEmpty) author,
            if (year != null) '($year)',
            if (tags.isNotEmpty) tags,
          ].join('  ')),
          trailing: IconButton(
            tooltip: 'メタデータを編集',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editMetadata(context, id),
          ),
          onTap: () {
            ref.read(selectedPaperProvider.notifier).select(id);
          },
        );
      },
    );
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
}

/// PDF import flow: DOI/CiNii/J-STAGE input -> metadata lookup (DESIGN.md「6.」
/// priority chain) -> confirm/edit form -> write library/{key}/.
///
/// PDF text extraction for automatic DOI detection was evaluated and skipped
/// for Phase 1c (see the implementation report); the user pastes the DOI or
/// other identifier manually here.
class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.config, required this.pdfPath});

  final VaultConfig config;
  final String pdfPath;

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
  final String pdfPath;
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
    setState(() => _saving = true);
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
      await importer.importPaper(
        sourcePdfPath: widget.pdfPath,
        metadata: metadata,
        tags: tags,
        source: widget.source.id,
        doi: metadata.doi,
        existingKeys: existingKeys,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
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
