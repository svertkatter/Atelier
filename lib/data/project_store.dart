import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/project.dart';
import 'vault_config.dart';

/// Reads and writes `projects/{name}/` folders (project.json, draft.md).
///
/// The vault index (SQLite) is only a cache; these files are the source of
/// truth. Kept separate from [VaultIndex] so the Writer can create/load a
/// project without a full rescan.
class ProjectStore {
  const ProjectStore(this.config);

  final VaultConfig config;

  /// List projects on disk (folders under `projects/` containing project.json).
  Future<List<Project>> listProjects() async {
    final dir = Directory(config.projectsDir);
    if (!await dir.exists()) return const <Project>[];
    final result = <Project>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final folder = p.basename(entity.path);
      final file = File(config.projectJsonPath(folder));
      if (!await file.exists()) continue;
      try {
        final proj =
            Project.parse(await file.readAsString()).copyWith(folderName: folder);
        result.add(proj);
      } catch (_) {
        // Skip malformed project.json.
      }
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  /// Load a single project by its folder name.
  Future<Project?> load(String folder) async {
    final file = File(config.projectJsonPath(folder));
    if (!await file.exists()) return null;
    return Project.parse(await file.readAsString())
        .copyWith(folderName: folder);
  }

  /// Create a new project folder with project.json and an empty draft.md.
  /// [folder] is sanitized; returns the created [Project].
  Future<Project> create({
    required String name,
    String? csl,
  }) async {
    final folder = _sanitizeFolder(name);
    final projectDir = Directory(p.join(config.projectsDir, folder));
    await projectDir.create(recursive: true);

    final project = Project(
      id: folder,
      name: name,
      csl: csl,
      refs: const <String>[],
      folderName: folder,
    );
    await saveProjectJson(project);

    final draft = File(p.join(projectDir.path, 'draft.md'));
    if (!await draft.exists()) {
      await draft.writeAsString('');
    }
    return project;
  }

  /// Persist project.json for [project].
  Future<void> saveProjectJson(Project project) async {
    final file = File(config.projectJsonPath(project.effectiveFolderName));
    await file.parent.create(recursive: true);
    await file.writeAsString(project.serialize());
  }

  /// Ensure [key] is present in the project's refs, persisting if newly added.
  /// Returns the (possibly updated) project.
  Future<Project> ensureRef(Project project, String key) async {
    if (project.refs.contains(key)) return project;
    final updated = project.copyWith(refs: [...project.refs, key]);
    await saveProjectJson(updated);
    return updated;
  }

  String draftPath(Project project) =>
      p.join(config.projectsDir, project.effectiveFolderName, 'draft.md');

  /// Read draft.md text (empty string if absent).
  Future<String> readDraft(Project project) async {
    final file = File(draftPath(project));
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// Write draft.md text (standard Markdown is the source of truth).
  Future<void> writeDraft(Project project, String markdown) async {
    final file = File(draftPath(project));
    await file.parent.create(recursive: true);
    await file.writeAsString(markdown);
  }

  static String _sanitizeFolder(String name) {
    var s = name.trim();
    // Replace path separators and characters illegal on Windows.
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (s.isEmpty) s = 'project';
    return s;
  }
}
