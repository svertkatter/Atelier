import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import 'project_store.dart';
import 'vault_config.dart';

/// Deletes a `library/{key}/` entry and scrubs it out of every project.json's
/// `refs` array.
///
/// Kept separate from [LibraryImport]/the UI so the "which projects reference
/// this paper" lookup and the delete+refs-cleanup logic are unit testable
/// without widget scaffolding (per CLAUDE.md: file I/O logic needs tests).
class LibraryDelete {
  const LibraryDelete(this.config);

  final VaultConfig config;

  /// Projects (read fresh from disk) whose `refs` currently include [key].
  /// Used by the UI to warn the user before they delete a referenced paper.
  Future<List<Project>> projectsReferencing(String key) async {
    final store = ProjectStore(config);
    final all = await store.listProjects();
    return all.where((project) => project.refs.contains(key)).toList();
  }

  /// Delete `library/{key}/` (PDF + meta.md) and remove [key] from every
  /// project.json's `refs`. Safe to call even if the folder is already gone.
  Future<void> delete(String key) async {
    final store = ProjectStore(config);
    final referencing = await projectsReferencing(key);
    for (final project in referencing) {
      final updated = project.copyWith(
        refs: project.refs.where((r) => r != key).toList(),
      );
      await store.saveProjectJson(updated);
    }

    final dir = Directory(p.join(config.libraryDir, key));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
