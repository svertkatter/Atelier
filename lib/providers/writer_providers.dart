import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/project_store.dart';
import '../data/styles_bootstrap.dart';
import '../models/project.dart';
import 'vault_providers.dart';

/// A [ProjectStore] bound to the current vault config, or null if no vault.
final projectStoreProvider = FutureProvider<ProjectStore?>((ref) async {
  final config = await ref.watch(vaultConfigProvider.future);
  if (config == null) return null;
  return ProjectStore(config);
});

/// The projects found on disk (Writer picker source).
final writerProjectsProvider = FutureProvider<List<Project>>((ref) async {
  final store = await ref.watch(projectStoreProvider.future);
  if (store == null) return const <Project>[];
  return store.listProjects();
});

/// The `.csl` styles available in the vault (for the project style picker).
final availableStylesProvider = FutureProvider<List<String>>((ref) async {
  final config = await ref.watch(vaultConfigProvider.future);
  if (config == null) return const <String>[];
  return StylesBootstrap.listAvailable(config);
});

/// The currently selected project folder in the Writer, or null.
final selectedProjectProvider =
    NotifierProvider<SelectedProjectNotifier, String?>(
        SelectedProjectNotifier.new);

class SelectedProjectNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? folder) => state = folder;
}
