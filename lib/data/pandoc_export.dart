import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/csl_metadata.dart';
import '../models/project.dart';
import 'meta_md.dart';
import 'refs_json.dart';
import 'vault_config.dart';

/// Locates the pandoc executable and runs docx export for a project.
///
/// All CSL/citation formatting is delegated to pandoc (`--citeproc`). No
/// citation logic lives on the Dart side — we only assemble refs.json (a pure
/// YAML->JSON transform) and build the command line.
class PandocExport {
  const PandocExport._();

  /// User-overridable manual path (set from settings). Checked first when set.
  static String? manualPandocPath;

  /// Resolve the pandoc executable, or null if not found. Order:
  /// 1. [manualPandocPath] (user setting)
  /// 2. `pandoc` on PATH
  /// 3. WinGet Links shim (`%LOCALAPPDATA%\Microsoft\WinGet\Links\pandoc.exe`)
  /// 4. WinGet Packages install glob
  static Future<String?> resolveExecutable() async {
    // 1. Manual override.
    final manual = manualPandocPath;
    if (manual != null && manual.isNotEmpty && await File(manual).exists()) {
      return manual;
    }

    // 2. PATH.
    final onPath = await _which('pandoc');
    if (onPath != null) return onPath;

    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local != null && local.isNotEmpty) {
        // 3. WinGet Links shim.
        final shim =
            p.join(local, 'Microsoft', 'WinGet', 'Links', 'pandoc.exe');
        if (await File(shim).exists()) return shim;

        // 4. WinGet Packages install (version-suffixed folder).
        final pkgRoot = Directory(p.join(local, 'Microsoft', 'WinGet',
            'Packages'));
        final found = await _findPandocUnder(pkgRoot);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Search a directory tree for `pandoc.exe` (Windows WinGet Packages).
  static Future<String?> _findPandocUnder(Directory root) async {
    if (!await root.exists()) return null;
    try {
      await for (final entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File &&
            p.basename(entity.path).toLowerCase() == 'pandoc.exe') {
          return entity.path;
        }
      }
    } catch (_) {
      // Ignore permission errors while scanning.
    }
    return null;
  }

  /// Cross-platform `which`/`where` using the appropriate lookup tool.
  static Future<String?> _which(String name) async {
    try {
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, [name]);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        if (out.isNotEmpty) {
          return out.split(RegExp(r'[\r\n]+')).first.trim();
        }
      }
    } catch (_) {
      // where/which not available.
    }
    return null;
  }

  /// True on platforms where pandoc export is supported (desktop only).
  static bool get isSupportedPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Build refs.json content for [project] by reading each referenced paper's
  /// meta.md. Missing keys are collected into [missingKeys] (if provided).
  ///
  /// Returns the pretty-printed refs.json text.
  static Future<String> buildRefsJson(
    Project project,
    VaultConfig config, {
    List<String>? missingKeys,
  }) async {
    final available = <String, CslMetadata>{};
    for (final key in project.refs) {
      final metaPath = config.metaMdPath(key);
      final file = File(metaPath);
      if (!await file.exists()) {
        missingKeys?.add(key);
        continue;
      }
      try {
        final paper = MetaMd.parse(await file.readAsString(), folderName: key);
        available[paper.id] = paper.metadata;
      } catch (_) {
        missingKeys?.add(key);
      }
    }
    final array = RefsJson.forRefs(project.refs, available);
    return RefsJson.serialize(array);
  }

  /// Assemble the pandoc argument list for a docx export.
  ///
  /// Pure/deterministic so it can be unit-tested without running pandoc.
  /// `--citeproc` is always included so pandoc resolves citations via CSL.
  static List<String> buildArgs({
    required String draftPath,
    required String refsJsonPath,
    String? cslPath,
    required String outputPath,
  }) {
    return <String>[
      draftPath,
      '--citeproc',
      '--bibliography=$refsJsonPath',
      if (cslPath != null && cslPath.isNotEmpty) '--csl=$cslPath',
      '-o',
      outputPath,
    ];
  }

  /// Full export flow for [project]: build refs.json, write it next to draft.md,
  /// resolve the CSL, run pandoc, produce output.docx in the project folder.
  ///
  /// Returns a [PandocResult] describing success/failure. Throws nothing; all
  /// failure modes are represented in the result.
  static Future<PandocResult> exportDocx({
    required Project project,
    required VaultConfig config,
  }) async {
    if (!isSupportedPlatform) {
      return const PandocResult.failure('この OS では出力できません（デスクトップ専用）');
    }

    final exe = await resolveExecutable();
    if (exe == null) {
      return const PandocResult.failure(
          'pandoc が見つかりません。インストールするか設定でパスを指定してください。');
    }

    final projectDir = p.join(config.projectsDir, project.effectiveFolderName);
    final draftPath = p.join(projectDir, 'draft.md');
    if (!await File(draftPath).exists()) {
      return PandocResult.failure('draft.md が見つかりません: $draftPath');
    }

    final missing = <String>[];
    final refsText = await buildRefsJson(project, config, missingKeys: missing);
    final refsPath = p.join(projectDir, 'refs.json');
    await File(refsPath).writeAsString(refsText);

    String? cslPath;
    if (project.csl != null && project.csl!.isNotEmpty) {
      final candidate = p.join(config.stylesDir, project.csl);
      if (await File(candidate).exists()) {
        cslPath = candidate;
      }
    }

    final outputPath = p.join(projectDir, 'output.docx');
    final args = buildArgs(
      draftPath: draftPath,
      refsJsonPath: refsPath,
      cslPath: cslPath,
      outputPath: outputPath,
    );

    try {
      final result = await Process.run(exe, args, workingDirectory: projectDir);
      if (result.exitCode != 0) {
        return PandocResult.failure(
          'pandoc がエラー終了しました (${result.exitCode})',
          stderr: (result.stderr ?? '').toString(),
        );
      }
      return PandocResult.success(outputPath, missingKeys: missing);
    } catch (e) {
      return PandocResult.failure('pandoc の実行に失敗しました: $e');
    }
  }
}

/// Outcome of a pandoc export.
class PandocResult {
  const PandocResult._({
    required this.ok,
    this.outputPath,
    this.message,
    this.stderr,
    this.missingKeys = const <String>[],
  });

  const PandocResult.success(String outputPath,
      {List<String> missingKeys = const <String>[]})
      : this._(ok: true, outputPath: outputPath, missingKeys: missingKeys);

  const PandocResult.failure(String message, {String? stderr})
      : this._(ok: false, message: message, stderr: stderr);

  final bool ok;
  final String? outputPath;
  final String? message;
  final String? stderr;

  /// Referenced citation keys whose meta.md was missing/unreadable.
  final List<String> missingKeys;
}
