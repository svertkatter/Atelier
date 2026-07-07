import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's top-level mode (mirrors the NavigationRail destinations in
/// [HomeShell]). Promoted to a Riverpod provider (rather than local
/// `_HomeShellState` state) so other screens — e.g. tapping a paper row in
/// the Library — can drive navigation into the Reader themselves.
enum AppMode { library, reader, writer, settings }

final selectedModeProvider =
    NotifierProvider<SelectedModeNotifier, AppMode>(SelectedModeNotifier.new);

class SelectedModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() => AppMode.library;

  void select(AppMode mode) => state = mode;
}
