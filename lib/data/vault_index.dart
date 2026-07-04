import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/paper.dart';
import '../models/project.dart';
import 'meta_md.dart';
import 'vault_config.dart';

/// Result of a scan/rebuild pass.
class VaultScanResult {
  const VaultScanResult({
    required this.papersIndexed,
    required this.papersRemoved,
    required this.projectsIndexed,
    required this.projectsRemoved,
    this.errors = const <String>[],
  });

  final int papersIndexed;
  final int papersRemoved;
  final int projectsIndexed;
  final int projectsRemoved;
  final List<String> errors;
}

/// The local SQLite index (`vault.sqlite`).
///
/// Rules (per CLAUDE.md):
/// - The DB is an index only; files (meta.md/project.json) are the source of
///   truth. Deleting the DB and rescanning must fully reconstruct it.
/// - The DB lives in Application Support (local, never synced). This class does
///   not decide that path; the caller passes [dbPath] (or uses in-memory for
///   tests).
class VaultIndex {
  VaultIndex._(this._db);

  final Database _db;

  Database get db => _db;

  /// Open (creating if needed) the index at [dbPath]. Pass null for an
  /// in-memory database (tests).
  static Future<VaultIndex> open({String? dbPath}) async {
    final db = await databaseFactory.openDatabase(
      dbPath ?? inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) async {
          await d.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
      ),
    );
    return VaultIndex._(db);
  }

  static Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE papers (
        id            TEXT PRIMARY KEY,   -- citation key
        folder        TEXT NOT NULL,
        title         TEXT,
        author        TEXT,               -- denormalized author display
        year          INTEGER,
        container     TEXT,
        tags          TEXT,               -- space/semicolon-joined
        source        TEXT,
        doi           TEXT,
        cinii_id      TEXT,
        mtime         INTEGER,            -- meta.md mtime (ms since epoch)
        size          INTEGER             -- meta.md size in bytes
      )
    ''');
    await db.execute('''
      CREATE TABLE projects (
        id            TEXT PRIMARY KEY,
        folder        TEXT NOT NULL,
        name          TEXT,
        csl           TEXT,
        refs          TEXT,               -- comma-joined citation keys
        mtime         INTEGER,
        size          INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_papers_year ON papers(year)');
    await db.execute('CREATE INDEX idx_papers_title ON papers(title)');
  }

  Future<void> close() => _db.close();

  /// Wipe all indexed rows (used for a forced full rebuild).
  Future<void> clear() async {
    await _db.delete('papers');
    await _db.delete('projects');
  }

  /// Scan the vault [config] and reconcile the index.
  ///
  /// Differential: a paper/project is re-parsed only if its meta.md /
  /// project.json mtime or size differs from the indexed row. Rows whose
  /// source folder no longer exists are removed. This is safe to run on an
  /// empty DB (→ full rebuild).
  Future<VaultScanResult> scan(VaultConfig config) async {
    final errors = <String>[];
    var papersIndexed = 0;
    var papersRemoved = 0;
    var projectsIndexed = 0;
    var projectsRemoved = 0;

    // ---- Papers ----
    final seenPaperIds = <String>{};
    final libraryDir = Directory(config.libraryDir);
    if (await libraryDir.exists()) {
      await for (final entity in libraryDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final folder = p.basename(entity.path);
        final metaFile = File(config.metaMdPath(folder));
        if (!await metaFile.exists()) continue;

        try {
          final stat = await metaFile.stat();
          final mtime = stat.modified.millisecondsSinceEpoch;
          final size = stat.size;

          final existing = await _db.query(
            'papers',
            columns: ['id', 'mtime', 'size'],
            where: 'folder = ?',
            whereArgs: [folder],
          );

          if (existing.isNotEmpty &&
              existing.first['mtime'] == mtime &&
              existing.first['size'] == size) {
            seenPaperIds.add(existing.first['id'] as String);
            continue; // unchanged
          }

          final content = await metaFile.readAsString();
          final paper = MetaMd.parse(content, folderName: folder);
          await _upsertPaper(paper, folder, mtime, size);
          seenPaperIds.add(paper.id);
          papersIndexed++;
        } catch (e) {
          errors.add('paper "$folder": $e');
        }
      }
    }
    // Remove papers whose folders vanished.
    final indexedPapers =
        await _db.query('papers', columns: ['id']);
    for (final row in indexedPapers) {
      final id = row['id'] as String;
      if (!seenPaperIds.contains(id)) {
        await _db.delete('papers', where: 'id = ?', whereArgs: [id]);
        papersRemoved++;
      }
    }

    // ---- Projects ----
    final seenProjectIds = <String>{};
    final projectsDir = Directory(config.projectsDir);
    if (await projectsDir.exists()) {
      await for (final entity in projectsDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final folder = p.basename(entity.path);
        final projFile = File(config.projectJsonPath(folder));
        if (!await projFile.exists()) continue;

        try {
          final stat = await projFile.stat();
          final mtime = stat.modified.millisecondsSinceEpoch;
          final size = stat.size;

          final existing = await _db.query(
            'projects',
            columns: ['id', 'mtime', 'size'],
            where: 'folder = ?',
            whereArgs: [folder],
          );
          if (existing.isNotEmpty &&
              existing.first['mtime'] == mtime &&
              existing.first['size'] == size) {
            seenProjectIds.add(existing.first['id'] as String);
            continue;
          }

          final content = await projFile.readAsString();
          final project = Project.parse(content).copyWith(folderName: folder);
          await _upsertProject(project, folder, mtime, size);
          seenProjectIds.add(project.id);
          projectsIndexed++;
        } catch (e) {
          errors.add('project "$folder": $e');
        }
      }
    }
    final indexedProjects =
        await _db.query('projects', columns: ['id']);
    for (final row in indexedProjects) {
      final id = row['id'] as String;
      if (!seenProjectIds.contains(id)) {
        await _db.delete('projects', where: 'id = ?', whereArgs: [id]);
        projectsRemoved++;
      }
    }

    return VaultScanResult(
      papersIndexed: papersIndexed,
      papersRemoved: papersRemoved,
      projectsIndexed: projectsIndexed,
      projectsRemoved: projectsRemoved,
      errors: errors,
    );
  }

  Future<void> _upsertPaper(
      Paper paper, String folder, int mtime, int size) async {
    await _db.insert(
      'papers',
      {
        'id': paper.id,
        'folder': folder,
        'title': paper.metadata.title,
        'author': paper.metadata.authorDisplay,
        'year': paper.metadata.year,
        'container': paper.metadata.containerTitle,
        'tags': paper.tags.join('; '),
        'source': paper.source,
        'doi': paper.doi ?? paper.metadata.doi,
        'cinii_id': paper.ciniiId,
        'mtime': mtime,
        'size': size,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _upsertProject(
      Project project, String folder, int mtime, int size) async {
    await _db.insert(
      'projects',
      {
        'id': project.id,
        'folder': folder,
        'name': project.name,
        'csl': project.csl,
        'refs': project.refs.join(','),
        'mtime': mtime,
        'size': size,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All indexed papers as summary rows, ordered by year desc then title.
  Future<List<Map<String, Object?>>> allPapers() => _db.query(
        'papers',
        orderBy: 'year DESC, title ASC',
      );

  /// All indexed projects.
  Future<List<Map<String, Object?>>> allProjects() =>
      _db.query('projects', orderBy: 'name ASC');

  /// Search papers by a substring across title, author, container, and tags.
  Future<List<Map<String, Object?>>> searchPapers(String query) {
    final like = '%$query%';
    return _db.query(
      'papers',
      where:
          'title LIKE ? OR author LIKE ? OR container LIKE ? OR tags LIKE ?',
      whereArgs: [like, like, like, like],
      orderBy: 'year DESC, title ASC',
    );
  }
}
