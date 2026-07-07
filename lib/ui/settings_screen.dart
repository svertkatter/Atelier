import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../providers/settings_providers.dart';
import '../providers/vault_providers.dart';
import 'shell/mode_header.dart';
import 'theme/app_theme.dart';
import 'theme/theme_toggle.dart';

/// Settings screen: vault root folder, pandoc path, CrossRef contact email,
/// CiNii Research app ID. Also serves as the first-run setup screen when no
/// vault root is configured yet (see DESIGN.md「8. Phase 1」).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _pickVaultRoot(BuildContext context, WidgetRef ref) async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Atelier Vault フォルダを選択（iCloud Drive 上を推奨）',
    );
    if (path == null) return;
    await ref.read(vaultConfigProvider.notifier).setRoot(path);
    ref.invalidate(vaultScanProvider);
  }

  Future<void> _pickPandocPath(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'pandoc 実行ファイルを選択',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    await ref.read(appSettingsProvider.notifier).setManualPandocPath(path);
    ref.invalidate(pandocPathProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(vaultConfigProvider);
    final settingsAsync = ref.watch(appSettingsProvider);
    final pandocAsync = ref.watch(pandocPathProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ModeHeader(
              title: '設定',
              subtitle: 'Atelier の外観と外部ツールを整えます',
              small: true,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(28, 4, 28, 28),
                children: [
                  // ---- Appearance ----
                  _Section(
              title: '外観',
              icon: Icons.palette_outlined,
              description: 'テーマはシステム設定に追従、またはライト／ダークに固定できます。',
              child: const Align(
                alignment: Alignment.centerLeft,
                child: ThemeModeSelector(),
              ),
            ),

            // ---- Vault root ----
            _Section(
              title: 'Vault フォルダ',
              icon: Icons.folder_special_outlined,
              child: configAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('読み込み失敗: $e'),
                data: (config) {
                  if (config == null) {
                    return _InlineNotice(
                      tone: _NoticeTone.warning,
                      message:
                          'Vault が未設定です。iCloud Drive 上のフォルダ（例: iCloud Drive/Atelier）を選択してください。'
                          '選択すると styles/ library/ projects/ が自動作成されます。',
                      action: FilledButton.icon(
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Vault フォルダを選択'),
                        onPressed: () => _pickVaultRoot(context, ref),
                      ),
                    );
                  }
                  return _PathRow(
                    path: config.rootPath,
                    onChange: () => _pickVaultRoot(context, ref),
                  );
                },
              ),
            ),

            // ---- pandoc ----
            _Section(
              title: 'pandoc',
              icon: Icons.terminal_outlined,
              description: 'docx 出力に使用します（Mac / Windows）。',
              child: pandocAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('検出失敗: $e'),
                data: (path) => path == null
                    ? _InlineNotice(
                        tone: _NoticeTone.warning,
                        message: 'pandoc が見つかりません（docx 出力は無効です）。',
                        action: OutlinedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('手動指定'),
                          onPressed: () => _pickPandocPath(context, ref),
                        ),
                      )
                    : _PathRow(
                        path: path,
                        changeLabel: '手動指定',
                        onChange: () => _pickPandocPath(context, ref),
                      ),
              ),
            ),

            // ---- CrossRef / CiNii ----
            _Section(
              title: 'メタデータ API',
              icon: Icons.cloud_outlined,
              description: 'CrossRef / CiNii Research からメタデータを取得する際の設定です。',
              child: settingsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('読み込み失敗: $e'),
                data: (settings) => _MetadataSettingsForm(settings: settings),
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
}

/// A titled settings group: icon + heading + optional description, then its
/// body. Groups are separated by tone/whitespace rather than heavy cards.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.description,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Text(title,
                  style: theme.extension<AtelierType>()!.displaySmall),
            ],
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                description!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A read-only path with a change button, used for the vault root and pandoc.
class _PathRow extends StatelessWidget {
  const _PathRow({
    required this.path,
    required this.onChange,
    this.changeLabel = '変更',
  });

  final String path;
  final VoidCallback onChange;
  final String changeLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            path,
            maxLines: 2,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.folder_open, size: 18),
          label: Text(changeLabel),
          onPressed: onChange,
        ),
      ],
    );
  }
}

enum _NoticeTone { warning }

/// An inline notice block (message + optional action), tinted by [tone].
class _InlineNotice extends StatelessWidget {
  const _InlineNotice({
    required this.tone,
    required this.message,
    this.action,
  });

  final _NoticeTone tone;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = switch (tone) {
      _NoticeTone.warning => scheme.errorContainer.withValues(alpha: 0.5),
    };
    final fg = switch (tone) {
      _NoticeTone.warning => scheme.onErrorContainer,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: fg)),
          if (action != null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: action!),
          ],
        ],
      ),
    );
  }
}

/// CrossRef contact email (polite pool) + CiNii Research app ID fields.
class _MetadataSettingsForm extends ConsumerStatefulWidget {
  const _MetadataSettingsForm({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_MetadataSettingsForm> createState() =>
      _MetadataSettingsFormState();
}

class _MetadataSettingsFormState extends ConsumerState<_MetadataSettingsForm> {
  late final TextEditingController _emailController;
  late final TextEditingController _ciniiController;

  @override
  void initState() {
    super.initState();
    _emailController =
        TextEditingController(text: widget.settings.crossrefContactEmail);
    _ciniiController =
        TextEditingController(text: widget.settings.ciniiAppId ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    _ciniiController.dispose();
    super.dispose();
  }

  Future<void> _saveEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    await ref.read(appSettingsProvider.notifier).setCrossrefContactEmail(email);
    ref.invalidate(metadataLookupProvider);
  }

  Future<void> _saveCiniiAppId() async {
    final appId = _ciniiController.text.trim();
    await ref.read(appSettingsProvider.notifier).setCiniiAppId(appId);
    ref.invalidate(metadataLookupProvider);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'CrossRef 連絡先メールアドレス（polite pool）',
            helperText: 'CrossRef へのリクエストに含まれます',
          ),
          onSubmitted: (_) => _saveEmail(),
          onEditingComplete: _saveEmail,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _saveEmail, child: const Text('保存')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ciniiController,
          decoration: const InputDecoration(
            labelText: 'CiNii Research アプリケーション ID（任意）',
          ),
          onSubmitted: (_) => _saveCiniiAppId(),
          onEditingComplete: _saveCiniiAppId,
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(onPressed: _saveCiniiAppId, child: const Text('保存')),
        ),
      ],
    );
  }
}
