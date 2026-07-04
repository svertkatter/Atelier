import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import 'vault_config.dart';

/// Copies bundled preset `.csl` styles into the vault's `styles/` folder on
/// first setup. The `.csl` files themselves are never parsed on the Dart side —
/// they are opaque data handed to pandoc downstream.
class StylesBootstrap {
  const StylesBootstrap._();

  /// Preset CSL files bundled as assets (asset path -> destination file name).
  static const Map<String, String> presets = <String, String>{
    'assets/styles/apa.csl': 'apa.csl',
    'assets/styles/ieee.csl': 'ieee.csl',
  };

  /// Copy any preset that is not already present in `styles/`. Existing files
  /// (including user-added or edited styles) are never overwritten. Returns the
  /// list of destination file names that were newly written.
  static Future<List<String>> ensurePresets(VaultConfig config) async {
    final stylesDir = Directory(config.stylesDir);
    if (!await stylesDir.exists()) {
      await stylesDir.create(recursive: true);
    }
    final written = <String>[];
    for (final entry in presets.entries) {
      final dest = File(p.join(config.stylesDir, entry.value));
      if (await dest.exists()) continue;
      try {
        final data = await rootBundle.loadString(entry.key);
        await dest.writeAsString(data);
        written.add(entry.value);
      } catch (_) {
        // Asset missing at runtime (e.g. tests without a bundle): skip.
      }
    }
    return written;
  }

  /// List the `.csl` file names currently in the vault's `styles/` folder.
  static Future<List<String>> listAvailable(VaultConfig config) async {
    final dir = Directory(config.stylesDir);
    if (!await dir.exists()) return const <String>[];
    final result = <String>[];
    await for (final e in dir.list(followLinks: false)) {
      if (e is File && p.extension(e.path).toLowerCase() == '.csl') {
        result.add(p.basename(e.path));
      }
    }
    result.sort();
    return result;
  }
}
