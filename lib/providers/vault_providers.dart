import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_paths.dart';
import '../data/styles_bootstrap.dart';
import '../data/vault_config.dart';
import '../data/vault_index.dart';

/// The configured vault root, or null if the user has not chosen one yet.
///
/// Loaded once from SharedPreferences; can be overridden after the user picks
/// or creates a vault folder.
final vaultConfigProvider =
    AsyncNotifierProvider<VaultConfigNotifier, VaultConfig?>(
        VaultConfigNotifier.new);

class VaultConfigNotifier extends AsyncNotifier<VaultConfig?> {
  @override
  Future<VaultConfig?> build() => VaultConfig.load();

  /// Choose (and persist) a new vault root, scaffolding its subfolders.
  Future<void> setRoot(String rootPath) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final config = await VaultConfig.save(rootPath);
      await config.ensureScaffold();
      // Seed preset CSL styles on first setup (never overwrites existing).
      await StylesBootstrap.ensurePresets(config);
      return config;
    });
  }
}

/// The open vault index (SQLite). Rebuilds when the vault config changes.
final vaultIndexProvider = FutureProvider<VaultIndex>((ref) async {
  final dbPath = await AppPaths.vaultDbPath();
  final index = await VaultIndex.open(dbPath: dbPath);
  ref.onDispose(index.close);
  return index;
});

/// Runs a scan of the current vault into the index and returns the result.
final vaultScanProvider = FutureProvider<VaultScanResult?>((ref) async {
  final config = await ref.watch(vaultConfigProvider.future);
  if (config == null) return null;
  final index = await ref.watch(vaultIndexProvider.future);
  return index.scan(config);
});

/// All indexed papers (summary rows), refreshed after a scan.
final papersProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
  await ref.watch(vaultScanProvider.future);
  final index = await ref.watch(vaultIndexProvider.future);
  return index.allPapers();
});

/// All indexed projects, refreshed after a scan.
final projectsProvider =
    FutureProvider<List<Map<String, Object?>>>((ref) async {
  await ref.watch(vaultScanProvider.future);
  final index = await ref.watch(vaultIndexProvider.future);
  return index.allProjects();
});
