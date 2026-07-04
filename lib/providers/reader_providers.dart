import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The citation key (library folder) currently open in the Reader, or null
/// when nothing is selected (shows the empty state).
final selectedPaperProvider =
    NotifierProvider<SelectedPaperNotifier, String?>(SelectedPaperNotifier.new);

class SelectedPaperNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? folder) => state = folder;
}
