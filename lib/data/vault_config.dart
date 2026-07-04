import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and resolves the user-chosen vault root (an iCloud Drive folder,
/// or any path the user picks) and knows the fixed subfolder layout.
///
/// The vault root itself lives on a sync layer (iCloud). vault.sqlite does NOT
/// live here — it is kept in Application Support (see [VaultIndex]).
class VaultConfig {
  VaultConfig(this.rootPath);

  static const String _prefsKey = 'atelier.vault_root';

  /// Absolute path to the vault root (contains styles/, library/, projects/).
  final String rootPath;

  String get stylesDir => p.join(rootPath, 'styles');
  String get libraryDir => p.join(rootPath, 'library');
  String get projectsDir => p.join(rootPath, 'projects');

  /// `library/{folder}/meta.md`.
  String metaMdPath(String folder) =>
      p.join(libraryDir, folder, 'meta.md');

  /// `library/{folder}/paper.pdf`.
  String paperPdfPath(String folder) =>
      p.join(libraryDir, folder, 'paper.pdf');

  /// `projects/{folder}/project.json`.
  String projectJsonPath(String folder) =>
      p.join(projectsDir, folder, 'project.json');

  /// Load the saved vault root, or null if not yet configured.
  static Future<VaultConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefsKey);
    if (path == null || path.isEmpty) return null;
    return VaultConfig(path);
  }

  /// Persist [rootPath] as the vault root.
  static Future<VaultConfig> save(String rootPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, rootPath);
    return VaultConfig(rootPath);
  }

  /// Ensure the standard subfolders (styles/, library/, projects/) exist.
  /// Safe to call repeatedly. Returns this config.
  Future<VaultConfig> ensureScaffold() async {
    for (final dir in [stylesDir, libraryDir, projectsDir]) {
      final d = Directory(dir);
      if (!await d.exists()) {
        await d.create(recursive: true);
      }
    }
    return this;
  }
}
