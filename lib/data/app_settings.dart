import 'package:shared_preferences/shared_preferences.dart';

/// App-level settings that are not vault-scoped: CrossRef polite-pool
/// contact, CiNii Research app ID, and the manual pandoc path override.
/// Persisted via SharedPreferences (local to the machine, like vault.sqlite —
/// these are tool/API configuration, not vault content, so they are not
/// synced through iCloud).
class AppSettings {
  const AppSettings({
    required this.crossrefContactEmail,
    required this.ciniiAppId,
    required this.manualPandocPath,
  });

  final String crossrefContactEmail;
  final String? ciniiAppId;
  final String? manualPandocPath;

  static const _crossrefEmailKey = 'atelier.crossref_contact_email';
  static const _ciniiAppIdKey = 'atelier.cinii_app_id';
  static const _pandocPathKey = 'atelier.manual_pandoc_path';

  static const String defaultCrossrefContactEmail = 'alice241102@gmail.com';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      crossrefContactEmail:
          prefs.getString(_crossrefEmailKey) ?? defaultCrossrefContactEmail,
      ciniiAppId: prefs.getString(_ciniiAppIdKey),
      manualPandocPath: prefs.getString(_pandocPathKey),
    );
  }

  Future<AppSettings> copyWithSaved({
    String? crossrefContactEmail,
    String? ciniiAppId,
    String? manualPandocPath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final next = AppSettings(
      crossrefContactEmail: crossrefContactEmail ?? this.crossrefContactEmail,
      ciniiAppId: ciniiAppId ?? this.ciniiAppId,
      manualPandocPath: manualPandocPath ?? this.manualPandocPath,
    );
    await prefs.setString(_crossrefEmailKey, next.crossrefContactEmail);
    if (next.ciniiAppId != null) {
      await prefs.setString(_ciniiAppIdKey, next.ciniiAppId!);
    }
    if (next.manualPandocPath != null) {
      await prefs.setString(_pandocPathKey, next.manualPandocPath!);
    }
    return next;
  }
}
