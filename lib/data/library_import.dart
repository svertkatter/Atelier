import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/csl_metadata.dart';
import '../models/paper.dart';
import 'meta_md.dart';
import 'metadata/citation_key.dart';
import 'vault_config.dart';

/// Creates `library/{citation-key}/` from resolved metadata (+ an optional
/// picked PDF, copied in as `paper.pdf`) and writes `meta.md` (via [MetaMd]).
///
/// Kept separate from the UI so the folder-creation/copy logic is unit
/// testable without file_picker or widget scaffolding.
class LibraryImport {
  const LibraryImport(this.config);

  final VaultConfig config;

  /// A citation key must be a bare filesystem-safe token: ASCII letters,
  /// digits, `_`/`-`, starting with a letter. DOIs (`10.1038/nphys1170`) and
  /// CiNii CRIDs (bare digit strings) do NOT match this and must always go
  /// through [CitationKey.generate] instead — using them verbatim as a
  /// `library/{key}/` folder name either nests a spurious subfolder (DOI's
  /// `/`) or collides with other numeric ids, and both break the vault index
  /// scan (which only looks at library/'s immediate children).
  static final RegExp _safeKeyPattern = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');

  /// Import a paper: if [sourcePdfPath] is given, it is copied into the new
  /// library folder as `paper.pdf`; when null, the entry is metadata-only
  /// (DESIGN.md「4-1.」URL/DOI import without a PDF — a PDF can be attached
  /// later via [attachPdf]). [metadata]/[tags]/[source] become the meta.md
  /// frontmatter. [existingKeys] is used to disambiguate the citation key
  /// (see [CitationKey.generate]).
  ///
  /// Returns the created [Paper] (with `folderName` set to the final,
  /// disambiguated key).
  Future<Paper> importPaper({
    String? sourcePdfPath,
    required CslMetadata metadata,
    List<String> tags = const <String>[],
    String? source,
    String? doi,
    String? ciniiId,
    Set<String> existingKeys = const <String>{},
  }) async {
    final lowerExisting = existingKeys.map((k) => k.toLowerCase()).toSet();
    final candidateId = metadata.id;
    final isUsableAsIs = candidateId.isNotEmpty &&
        _safeKeyPattern.hasMatch(candidateId) &&
        !lowerExisting.contains(candidateId.toLowerCase());

    final key = isUsableAsIs
        ? candidateId
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

    if (sourcePdfPath != null) {
      final destPdf = File(config.paperPdfPath(key));
      await File(sourcePdfPath).copy(destPdf.path);
    }

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

  /// Copy [sourcePdfPath] into an existing `library/{key}/` as `paper.pdf`
  /// (DESIGN.md「4-1./4-2.」"PDFを添付" — attaching a PDF after a metadata-only
  /// import). Overwrites an existing paper.pdf if present.
  Future<void> attachPdf({
    required String key,
    required String sourcePdfPath,
  }) async {
    final destPdf = File(config.paperPdfPath(key));
    await destPdf.parent.create(recursive: true);
    await File(sourcePdfPath).copy(destPdf.path);
  }
}
