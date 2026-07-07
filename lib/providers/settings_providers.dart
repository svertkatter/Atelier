import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_settings.dart';
import '../data/metadata/metadata_lookup.dart';
import '../data/pandoc_export.dart';

/// App-level settings (CrossRef contact email, CiNii app ID, manual pandoc
/// path). Local-only, not vault-scoped.
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
        AppSettingsNotifier.new);

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => AppSettings.load();

  Future<void> setCrossrefContactEmail(String email) async {
    final current = await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => current.copyWithSaved(crossrefContactEmail: email));
    // Keep pandoc's manual path in sync in case it was also just set.
  }

  Future<void> setCiniiAppId(String appId) async {
    final current = await future;
    state = const AsyncValue.loading();
    state =
        await AsyncValue.guard(() => current.copyWithSaved(ciniiAppId: appId));
  }

  Future<void> setManualPandocPath(String path) async {
    final current = await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => current.copyWithSaved(manualPandocPath: path));
    PandocExport.manualPandocPath = path;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final current = await future;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => current.copyWithSaved(themeModeName: mode.name));
  }
}

/// The persisted appearance preference as a Flutter [ThemeMode]. Resolves to
/// [ThemeMode.system] until settings have loaded (and on any unknown value).
final themeModeProvider = Provider<ThemeMode>((ref) {
  final name = ref
      .watch(appSettingsProvider)
      .maybeWhen(data: (s) => s.themeModeName, orElse: () => null);
  switch (name) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
});

/// A [MetadataLookup] configured from the current [AppSettings]. Rebuilt
/// whenever settings change so a new contact email / CiNii app ID takes
/// effect on the next lookup.
final metadataLookupProvider = FutureProvider<MetadataLookup>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  final lookup = MetadataLookup(
    crossrefContactEmail: settings.crossrefContactEmail,
    ciniiAppId: settings.ciniiAppId,
  );
  ref.onDispose(lookup.close);
  return lookup;
});

/// Resolved pandoc executable path (or null if not found), refreshed whenever
/// settings change (e.g. a new manual path is set).
final pandocPathProvider = FutureProvider<String?>((ref) async {
  final settings = await ref.watch(appSettingsProvider.future);
  PandocExport.manualPandocPath = settings.manualPandocPath;
  return PandocExport.resolveExecutable();
});
