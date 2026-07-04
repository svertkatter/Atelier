import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../providers/settings_providers.dart';
import '../providers/vault_providers.dart';

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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Text('設定', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),

          // ---- Vault root ----
          Text('Vault フォルダ', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          configAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('読み込み失敗: $e'),
            data: (config) {
              if (config == null) {
                return Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'Vault が未設定です。iCloud Drive 上のフォルダ（例: iCloud Drive/Atelier）を選択してください。\n'
                            '選択すると styles/ library/ projects/ が自動作成されます。'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Vault フォルダを選択'),
                          onPressed: () => _pickVaultRoot(context, ref),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(child: Text(config.rootPath)),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open),
                    label: const Text('変更'),
                    onPressed: () => _pickVaultRoot(context, ref),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // ---- pandoc ----
          Text('pandoc', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          pandocAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('検出失敗: $e'),
            data: (path) => Row(
              children: [
                Expanded(
                  child: Text(path == null
                      ? 'pandoc が見つかりません（docx 出力は無効です）'
                      : '検出済み: $path'),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('手動指定'),
                  onPressed: () => _pickPandocPath(context, ref),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ---- CrossRef / CiNii ----
          Text('メタデータ API', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          settingsAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('読み込み失敗: $e'),
            data: (settings) => _MetadataSettingsForm(settings: settings),
          ),
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
