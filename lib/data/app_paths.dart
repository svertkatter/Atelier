import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves local (non-synced) application paths.
///
/// vault.sqlite MUST live here (Application Support), never inside the vault
/// root which is on iCloud Drive.
class AppPaths {
  /// Absolute path to `.../Application Support/Atelier/vault.sqlite`.
  static Future<String> vaultDbPath() async {
    final dir = await getApplicationSupportDirectory();
    final atelierDir = Directory(p.join(dir.path, 'Atelier'));
    if (!await atelierDir.exists()) {
      await atelierDir.create(recursive: true);
    }
    return p.join(atelierDir.path, 'vault.sqlite');
  }
}
