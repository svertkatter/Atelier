import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/csl_metadata.dart';
import '../models/paper.dart';
import 'meta_md.dart';
import 'metadata/citation_key.dart';
import 'vault_config.dart';

/// Creates `library/{citation-key}/` from a picked PDF + resolved metadata:
/// copies the PDF as `paper.pdf` and writes `meta.md` (via [MetaMd]).
///
/// Kept separate from the UI so the folder-creation/copy logic is unit
/// testable without file_picker or widget scaffolding.
class LibraryImport {
  const LibraryImport(this.config);

  final VaultConfig config;

  /// Import a paper: [sourcePdfPath] is copied into the new library folder as
  /// `paper.pdf`; [metadata]/[tags]/[source] become the meta.md frontmatter.
  /// [existingKeys] is used to disambiguate the citation key (see
  /// [CitationKey.generate]).
  ///
  /// Returns the created [Paper] (with `folderName` set to the final,
  /// disambiguated key).
  Future<Paper> importPaper({
    required String sourcePdfPath,
    required CslMetadata metadata,
    List<String> tags = const <String>[],
    String? source,
    String? doi,
    String? ciniiId,
    Set<String> existingKeys = const <String>{},
  }) async {
    final key = metadata.id.isNotEmpty && !existingKeys.contains(metadata.id)
        ? metadata.id
        : CitationKey.generate(metadata, existingKeys: existingKeys);

    final finalMetadata = metadata.id == key
        ? metadata
        : CslMetadata(
            id: key,
            type: metadata.type,
            title: metadata.title,
            authors: metadata.authors,
            issuedDateParts: metadata.issuedDateParts,
            containerTitle: metadata.containerTitle,
            volume: metadata.volume,
            issue: metadata.issue,
            page: metadata.page,
            doi: metadata.doi,
            url: metadata.url,
            publisher: metadata.publisher,
            abstractText: metadata.abstractText,
            extra: metadata.extra,
          );

    final folderDir = Directory(p.join(config.libraryDir, key));
    await folderDir.create(recursive: true);

    final destPdf = File(config.paperPdfPath(key));
    await File(sourcePdfPath).copy(destPdf.path);

    final paper = Paper(
      metadata: finalMetadata,
      tags: tags,
      source: source,
      doi: doi ?? finalMetadata.doi,
      ciniiId: ciniiId,
      folderName: key,
    );
    await File(config.metaMdPath(key)).writeAsString(MetaMd.serialize(paper));

    return paper;
  }

  /// Overwrite meta.md for an existing library entry (manual metadata edit).
  Future<void> saveMetadata(Paper paper) async {
    final folder = paper.effectiveFolderName;
    final file = File(config.metaMdPath(folder));
    await file.parent.create(recursive: true);
    await file.writeAsString(MetaMd.serialize(paper));
  }
}
