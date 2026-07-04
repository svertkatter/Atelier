import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/vault_config.dart';
import '../providers/reader_providers.dart';

/// Reader mode: displays the selected library paper's `paper.pdf`.
///
/// Phase 1 scope only (see DESIGN.md「8. Phase 1」): plain PDF display with
/// pdfrx's built-in page navigation/zoom. Highlighting/clips.json overlay is
/// Phase 2.
class ReaderScreen extends ConsumerWidget {
  const ReaderScreen({super.key, required this.config});

  final VaultConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedPaperProvider);
    if (selected == null) {
      return const _EmptyReaderView();
    }

    final pdfPath = config.paperPdfPath(selected);
    if (!File(pdfPath).existsSync()) {
      return Center(
        child: Text('PDF が見つかりません: $pdfPath'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'ライブラリへ戻る',
                icon: const Icon(Icons.close),
                onPressed: () =>
                    ref.read(selectedPaperProvider.notifier).select(null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: PdfViewer.file(
            pdfPath,
            // Key forces a fresh viewer (and controller) when the selected
            // paper changes, so page position/zoom don't leak across papers.
            key: ValueKey(pdfPath),
            params: const PdfViewerParams(),
          ),
        ),
      ],
    );
  }
}

class _EmptyReaderView extends StatelessWidget {
  const _EmptyReaderView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'ライブラリで論文を選択すると、ここに表示されます。',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
