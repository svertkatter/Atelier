import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart' as afe;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/draft_markdown.dart';
import '../data/pandoc_export.dart';
import '../data/project_store.dart';
import '../data/vault_config.dart';
import '../models/project.dart';
import '../providers/vault_providers.dart';
import '../providers/writer_providers.dart';
import 'shell/mode_header.dart';
import 'theme/app_theme.dart';

/// Writer mode: pick/create a project, edit draft.md in a true WYSIWYG editor
/// (appflowy_editor 6.x), insert `@` citations as inline chips, and export a
/// citation-resolved docx via pandoc.
///
/// WYSIWYG requirements honored here:
/// - `#` / `**` markers are never shown: blocks render as styled headings,
///   lists, quotes, code; typing markdown shortcuts (e.g. `# ` + space)
///   converts to the styled block via appflowy's standard character shortcuts.
/// - `[@key]` citations render as chips (author+year label, tinted background)
///   via [afe.EditorStyle.desktop]'s textSpanDecorator. The chip's visible
///   label lives in the delta text; the key lives in the `citation` attribute,
///   which is the sole source for serialization (lossless round trip).
/// - `@` typed in the editor opens the citation picker
///   ([afe.CharacterShortcutEvent]); Esc/cancel falls back to a literal `@`.
/// - draft.md (standard Markdown) stays the source of truth. The editor
///   document is serialized through [DraftMarkdown.encode] on save; internal
///   JSON is never persisted.
class WriterScreen extends ConsumerWidget {
  const WriterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(vaultConfigProvider);
    return configAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('エラー: $e')),
      data: (config) {
        if (config == null) {
          return const Center(child: Text('先に Vault フォルダを設定してください。'));
        }
        final selected = ref.watch(selectedProjectProvider);
        if (selected == null) {
          return _ProjectPicker(config: config);
        }
        return _DraftEditor(config: config, folder: selected);
      },
    );
  }
}

/// Lets the user choose an existing project or create a new one.
class _ProjectPicker extends ConsumerWidget {
  const _ProjectPicker({required this.config});

  final VaultConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectsAsync = ref.watch(writerProjectsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModeHeader(
          title: '書く',
          subtitle: 'プロジェクト — 原稿を書き、引用を整え、docx に出力する',
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新規プロジェクト'),
              onPressed: () => _createProject(context, ref),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
            child: projectsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('読み込み失敗: $e')),
              data: (projects) {
                if (projects.isEmpty) {
                  return _EmptyProjectsView(
                    onCreate: () => _createProject(context, ref),
                  );
                }
                return ListView.separated(
                  itemCount: projects.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 8, endIndent: 8),
                  itemBuilder: (context, i) {
                    final proj = projects[i];
                    return _ProjectRow(
                      name: proj.name,
                      subtitle:
                          '参照 ${proj.refs.length} 件 · スタイル: ${proj.csl ?? "(既定)"}',
                      onTap: () => ref
                          .read(selectedProjectProvider.notifier)
                          .select(proj.effectiveFolderName),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _createProject(BuildContext context, WidgetRef ref) async {
    final store = await ref.read(projectStoreProvider.future);
    if (store == null) return;
    final styles = await ref.read(availableStylesProvider.future);
    if (!context.mounted) return;

    final result = await showDialog<_NewProjectData>(
      context: context,
      builder: (context) => _NewProjectDialog(styles: styles),
    );
    if (result == null || result.name.trim().isEmpty) return;

    final proj = await store.create(name: result.name.trim(), csl: result.csl);
    ref.invalidate(writerProjectsProvider);
    ref.read(selectedProjectProvider.notifier).select(proj.effectiveFolderName);
  }
}

/// A project entry in the picker: hover-lifts and reveals a chevron, matching
/// the library's row language.
class _ProjectRow extends StatefulWidget {
  const _ProjectRow({
    required this.name,
    required this.subtitle,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_ProjectRow> createState() => _ProjectRowState();
}

class _ProjectRowState extends State<_ProjectRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _hover ? scheme.surfaceContainerHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.edit_note_outlined, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _hover ? 1 : 0.35,
                child: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the Writer has no projects yet.
class _EmptyProjectsView extends StatelessWidget {
  const _EmptyProjectsView({required this.onCreate});

  final VoidCallback onCreate;

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
              child: Icon(Icons.edit_note_outlined,
                  size: 46, color: scheme.primary),
            ),
            const SizedBox(height: 24),
            Text('プロジェクトがありません', style: type.displaySmall),
            const SizedBox(height: 8),
            Text(
              '「新規プロジェクト」から執筆を始めましょう。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新規プロジェクト'),
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewProjectData {
  const _NewProjectData(this.name, this.csl);
  final String name;
  final String? csl;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog({required this.styles});
  final List<String> styles;

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _controller = TextEditingController();
  String? _csl;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新規プロジェクト'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'プロジェクト名'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _csl,
            decoration: const InputDecoration(labelText: '引用スタイル (CSL)'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('(既定 / 未設定)'),
              ),
              for (final s in widget.styles)
                DropdownMenuItem<String?>(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _csl = v),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, _NewProjectData(_controller.text, _csl)),
          child: const Text('作成'),
        ),
      ],
    );
  }
}

/// The draft editor: true WYSIWYG (appflowy_editor) with source-mode toggle,
/// save, `@` citation suggestion, and docx export.
class _DraftEditor extends ConsumerStatefulWidget {
  const _DraftEditor({required this.config, required this.folder});

  final VaultConfig config;
  final String folder;

  @override
  ConsumerState<_DraftEditor> createState() => _DraftEditorState();
}

class _DraftEditorState extends ConsumerState<_DraftEditor> {
  ProjectStore? _store;
  Project? _project;

  afe.EditorState? _editorState;
  StreamSubscription<afe.EditorTransactionValue>? _txnSub;

  final _sourceController = TextEditingController();
  bool _sourceMode = false;
  bool _loading = true;
  bool _dirty = false;
  String? _statusMessage;

  /// citation key -> display label (author+year), built from the vault index.
  Map<String, String> _citationLabels = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _txnSub?.cancel();
    _sourceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = await ref.read(projectStoreProvider.future);
    if (store == null) return;
    final project = await store.load(widget.folder);
    if (project == null) return;
    final markdown = await store.readDraft(project);

    // Build the citation label map from the vault index once per load.
    final index = await ref.read(vaultIndexProvider.future);
    final rows = await index.allPapers();
    final labels = <String, String>{};
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      labels[id] = _labelFor(row);
    }

    if (!mounted) return;
    setState(() {
      _store = store;
      _project = project;
      _citationLabels = labels;
      _sourceController.text = markdown;
      _setEditorFromMarkdown(markdown);
      _loading = false;
    });
  }

  /// Author+year chip label for a paper index row, e.g. `田中 太郎 (2024)`.
  static String _labelFor(Map<String, Object?> row) {
    final id = (row['id'] ?? '').toString();
    final author = (row['author'] ?? '').toString();
    final year = row['year'];
    final first = author.split(';').first.trim();
    if (first.isEmpty) return id;
    return year != null ? '$first ($year)' : first;
  }

  String _chipLabel(String key) => _citationLabels[key] ?? key;

  // ---------------------------------------------------------------------
  // Markdown <-> editor state
  // ---------------------------------------------------------------------

  void _setEditorFromMarkdown(String markdown) {
    _txnSub?.cancel();
    final doc = DraftMarkdown.decode(markdown);
    _applyCitationLabels(doc.root);
    final state = afe.EditorState(document: doc);
    _txnSub = state.transactionStream.listen((_) {
      if (!_dirty && mounted) setState(() => _dirty = true);
    });
    _editorState = state;
  }

  /// Replace each citation run's display text with its author+year label.
  /// The `citation` attribute (the serialization source) is left untouched, so
  /// this is purely cosmetic and the round trip stays lossless.
  void _applyCitationLabels(afe.Node node) {
    final delta = node.delta;
    if (delta != null) {
      var changed = false;
      final rebuilt = afe.Delta();
      for (final op in delta) {
        if (op is afe.TextInsert) {
          final key = op.attributes?[DraftMarkdown.citationKey];
          if (key is String && key.isNotEmpty) {
            final label = _chipLabel(key);
            if (label != op.text) changed = true;
            rebuilt.insert(label, attributes: op.attributes);
            continue;
          }
          rebuilt.insert(op.text, attributes: op.attributes);
        }
      }
      if (changed) {
        node.updateAttributes({afe.blockComponentDelta: rebuilt.toJson()});
      }
    }
    for (final child in node.children) {
      _applyCitationLabels(child);
    }
  }

  /// Serialize whichever surface is active into canonical Markdown.
  String _currentMarkdown() {
    if (_sourceMode) {
      // Normalize the raw text through the converter so saved output is the
      // stable normal form.
      return DraftMarkdown.encode(
          DraftMarkdown.decode(_sourceController.text));
    }
    final state = _editorState;
    if (state == null) {
      return DraftMarkdown.encode(
          DraftMarkdown.decode(_sourceController.text));
    }
    return DraftMarkdown.encode(state.document);
  }

  Future<void> _save() async {
    final store = _store;
    final project = _project;
    if (store == null || project == null) return;
    final markdown = _currentMarkdown();
    await store.writeDraft(project, markdown);
    if (!mounted) return;
    setState(() {
      if (_sourceMode) {
        _sourceController.text = markdown;
      }
      _dirty = false;
      _statusMessage = '保存しました';
    });
  }

  void _toggleSourceMode() {
    setState(() {
      if (_sourceMode) {
        // Leaving source mode: rebuild the WYSIWYG document from the text.
        _setEditorFromMarkdown(_sourceController.text);
      } else {
        // Entering source mode: serialize the document into standard MD.
        final state = _editorState;
        if (state != null) {
          _sourceController.text = DraftMarkdown.encode(state.document);
        }
      }
      _sourceMode = !_sourceMode;
    });
  }

  // ---------------------------------------------------------------------
  // Citations
  // ---------------------------------------------------------------------

  /// Show the picker and insert a citation chip at the current selection.
  /// [fallbackLiteralAt] inserts a literal `@` when the picker is dismissed
  /// (used by the `@` shortcut so typing `@` still works for plain text).
  Future<void> _pickAndInsertCitation({bool fallbackLiteralAt = false}) async {
    final index = await ref.read(vaultIndexProvider.future);
    if (!mounted) return;
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => _CitationSearchDialog(search: index.searchPapers),
    );

    if (selected == null) {
      if (fallbackLiteralAt) await _insertPlainText('@');
      return;
    }
    final key = (selected['id'] ?? '').toString();
    if (key.isEmpty) return;

    // Remember the label and auto-add the key to project refs.
    _citationLabels = {..._citationLabels, key: _labelFor(selected)};
    final store = _store;
    var project = _project;
    if (store != null && project != null) {
      project = await store.ensureRef(project, key);
      if (mounted) setState(() => _project = project);
    }

    if (_sourceMode) {
      _spliceIntoSource('[@$key]');
      return;
    }
    await _insertCitationChip(key);
  }

  /// Insert a citation run (label text + `citation` attribute) followed by a
  /// plain space at the current WYSIWYG selection.
  Future<void> _insertCitationChip(String key) async {
    final state = _editorState;
    if (state == null) return;
    final selection = state.selection;
    if (selection == null || !selection.isCollapsed) return;
    final node = state.getNodeAtPath(selection.end.path);
    if (node == null || node.delta == null) return;

    final label = _chipLabel(key);
    final offset = selection.end.offset;
    final tr = state.transaction
      ..insertText(node, offset, label,
          attributes: {DraftMarkdown.citationKey: key})
      ..insertText(node, offset + label.length, ' ');
    await state.apply(tr);
    if (mounted && !_dirty) setState(() => _dirty = true);
  }

  /// Insert plain text at the current WYSIWYG selection (used for the literal
  /// `@` fallback).
  Future<void> _insertPlainText(String text) async {
    final state = _editorState;
    if (state == null) return;
    final selection = state.selection;
    if (selection == null || !selection.isCollapsed) return;
    final node = state.getNodeAtPath(selection.end.path);
    if (node == null || node.delta == null) return;
    final tr = state.transaction
      ..insertText(node, selection.end.offset, text);
    await state.apply(tr);
  }

  void _spliceIntoSource(String token) {
    final sel = _sourceController.selection;
    final text = _sourceController.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final newText = text.replaceRange(start, end, token);
    setState(() {
      _sourceController.text = newText;
      _sourceController.selection =
          TextSelection.collapsed(offset: start + token.length);
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------

  Future<void> _export() async {
    final store = _store;
    var project = _project;
    if (store == null || project == null) return;
    await _save();
    project = await store.load(widget.folder) ?? project;

    setState(() => _statusMessage = '出力中…');
    final result =
        await PandocExport.exportDocx(project: project, config: widget.config);
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        final missing = result.missingKeys.isEmpty
            ? ''
            : '（未解決の参照: ${result.missingKeys.join(", ")}）';
        _statusMessage = '出力完了: ${result.outputPath}$missing';
      } else {
        _statusMessage = '出力失敗: ${result.message}';
      }
    });
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final project = _project;
    final canExport = PandocExport.isSupportedPlatform;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            const _SaveIntent(),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
            const _SaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveIntent: CallbackAction<_SaveIntent>(
            onInvoke: (_) {
              _save();
              return null;
            },
          ),
        },
        child: Column(
          children: [
            _buildToolbar(context, project, canExport),
            const Divider(height: 1),
            Expanded(child: _buildBody(context)),
            if (_statusMessage != null)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  border: Border(
                    top: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(
      BuildContext context, Project? project, bool canExport) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = theme.extension<AtelierType>()!;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'プロジェクト選択に戻る',
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                ref.read(selectedProjectProvider.notifier).select(null),
          ),
          const SizedBox(width: 6),
          // The mode verb, in mincho, keeps the editing view rooted in「書く」.
          Text('書く',
              style: type.verb.copyWith(fontSize: 15, color: scheme.primary)),
          const SizedBox(width: 12),
          Container(width: 1, height: 18, color: scheme.outlineVariant),
          const SizedBox(width: 12),
          Flexible(
            child: Text(project?.name ?? widget.folder,
                style: theme.textTheme.titleMedium,
                overflow: TextOverflow.ellipsis),
          ),
          if (_dirty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: '未保存の変更があります',
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.tertiary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          const Spacer(),
          TextButton.icon(
            icon: Icon(_sourceMode ? Icons.wysiwyg : Icons.code),
            label: Text(_sourceMode ? 'WYSIWYG' : 'ソース'),
            onPressed: _toggleSourceMode,
          ),
          TextButton.icon(
            icon: const Icon(Icons.alternate_email),
            label: const Text('引用'),
            onPressed: () => _pickAndInsertCitation(),
          ),
          TextButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: const Text('保存'),
            onPressed: _save,
          ),
          if (canExport)
            FilledButton.icon(
              icon: const Icon(Icons.description),
              label: const Text('docx 出力'),
              onPressed: _export,
            ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_sourceMode) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _sourceController,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontFamily: 'monospace', height: 1.4),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '標準 Markdown（ソースモード）',
          ),
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
        ),
      );
    }

    final state = _editorState;
    if (state == null) {
      return const Center(child: Text('エディタを初期化できませんでした'));
    }
    return AtelierDraftEditor(
      editorState: state,
      onCitationTrigger: () =>
          _pickAndInsertCitation(fallbackLiteralAt: true),
    );
  }
}

/// The WYSIWYG editing surface (appflowy_editor 6.x), extracted as a public
/// widget so it can be exercised by widget tests without the full Writer
/// scaffolding.
///
/// - Headings/lists/quotes/code render as styled blocks; `#`, `**`, `- ` etc.
///   are never displayed (markdown-shortcut typing converts on the fly).
/// - Runs carrying [DraftMarkdown.citationKey] render as chips (label text
///   with a tinted background). The span text always equals the delta text so
///   selection geometry stays exact.
/// - Typing `@` invokes [onCitationTrigger] (when provided) instead of
///   inserting the character.
class AtelierDraftEditor extends StatelessWidget {
  const AtelierDraftEditor({
    super.key,
    required this.editorState,
    this.onCitationTrigger,
    this.autoFocus = true,
  });

  final afe.EditorState editorState;

  /// Called when the user types `@` in the editor. When null, `@` inserts
  /// normally.
  final VoidCallback? onCitationTrigger;

  final bool autoFocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return afe.AppFlowyEditor(
      editorState: editorState,
      autoFocus: autoFocus,
      editorStyle: afe.EditorStyle.desktop(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
        cursorColor: theme.colorScheme.primary,
        selectionColor: theme.colorScheme.primary.withValues(alpha: 0.25),
        textStyleConfiguration: afe.TextStyleConfiguration(
          text: TextStyle(
            fontSize: 15,
            height: 1.6,
            color: theme.colorScheme.onSurface,
          ),
          code: TextStyle(
            fontFamily: 'monospace',
            fontSize: 14,
            backgroundColor: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.7),
          ),
        ),
        textSpanDecorator: _citationSpanDecorator,
      ),
      blockComponentBuilders: {
        ...afe.standardBlockComponentBuilderMap,
        // Lightweight code-block rendering: reuse the paragraph component with
        // a monospace style. The node keeps its `code` type (round-trip safe);
        // the paragraph builder only requires a non-null delta.
        DraftMarkdown.codeBlockType: afe.ParagraphBlockComponentBuilder(
          configuration: afe.standardBlockComponentConfiguration.copyWith(
            textStyle: (_, {textSpan}) => const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13.5,
              height: 1.5,
            ),
            padding: (_) => const EdgeInsets.symmetric(vertical: 6),
          ),
        ),
      },
      characterShortcutEvents: [
        if (onCitationTrigger != null) _citationShortcut,
        ...afe.standardCharacterShortcutEvents,
      ],
      commandShortcutEvents: afe.standardCommandShortcutEvents,
    );
  }

  /// The `@` character shortcut: open the citation picker instead of typing
  /// `@`. Cancel behavior (literal `@`) is handled by the callback owner.
  afe.CharacterShortcutEvent get _citationShortcut =>
      afe.CharacterShortcutEvent(
        key: 'atelier: @ citation suggestion',
        character: '@',
        handler: (editorState) async {
          final selection = editorState.selection;
          if (selection == null || !selection.isCollapsed) {
            return false; // let default '@' insertion happen
          }
          final trigger = onCitationTrigger;
          if (trigger == null) return false;
          // Fire the picker after the current key event completes.
          WidgetsBinding.instance.addPostFrameCallback((_) => trigger());
          return true; // swallow the '@'
        },
      );

  /// Render citation runs as chips: tinted background + primary color. The
  /// span text must equal the delta text so selection geometry stays correct.
  static InlineSpan _citationSpanDecorator(
    BuildContext context,
    afe.Node node,
    int index,
    afe.TextInsert text,
    TextSpan before,
    TextSpan after,
  ) {
    final key = text.attributes?[DraftMarkdown.citationKey];
    if (key is! String || key.isEmpty) {
      return afe.defaultTextSpanDecoratorForAttribute(
          context, node, index, text, before, after);
    }
    final scheme = Theme.of(context).colorScheme;
    return TextSpan(
      text: before.text,
      style: (before.style ?? const TextStyle()).copyWith(
        color: scheme.primary,
        backgroundColor: scheme.primaryContainer.withValues(alpha: 0.45),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

/// A modal that searches the vault index and returns the chosen paper row.
class _CitationSearchDialog extends StatefulWidget {
  const _CitationSearchDialog({required this.search});

  final Future<List<Map<String, Object?>>> Function(String query) search;

  @override
  State<_CitationSearchDialog> createState() => _CitationSearchDialogState();
}

class _CitationSearchDialogState extends State<_CitationSearchDialog> {
  final _controller = TextEditingController();
  List<Map<String, Object?>> _results = const [];
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _runSearch('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final rows = q.trim().isEmpty
        ? await widget.search('')
        : await widget.search(q.trim());
    if (!mounted) return;
    setState(() => _results = rows);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('引用を挿入'),
      content: SizedBox(
        width: 460,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '著者・タイトル・タグで検索',
              ),
              onChanged: _onChanged,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results.isEmpty
                  ? const Center(child: Text('該当なし'))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final row = _results[i];
                        final id = (row['id'] ?? '').toString();
                        final title = (row['title'] ?? '').toString();
                        final author = (row['author'] ?? '').toString();
                        final year = row['year'];
                        return ListTile(
                          dense: true,
                          title: Text(title.isEmpty ? id : title),
                          subtitle: Text(
                              '$author${year != null ? " ($year)" : ""} · @$id'),
                          onTap: () => Navigator.pop(context, row),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}
