import 'csl_metadata.dart';

/// A single library entry, corresponding to `library/{citation-key}/`.
///
/// The folder holds `paper.pdf` and `meta.md`. [metadata] is parsed from the
/// YAML frontmatter of meta.md; [aiSummary] and [userNote] are the body
/// sections ("## AI要約" / "## 自分のメモ").
class Paper {
  const Paper({
    required this.metadata,
    this.tags = const <String>[],
    this.source,
    this.doi,
    this.ciniiId,
    this.aiSummary,
    this.userNote,
    this.folderName,
  });

  final CslMetadata metadata;

  /// User/auto tags (frontmatter `tags`).
  final List<String> tags;

  /// Where the metadata came from: `crossref`, `openalex`, `cinii`, `jstage`,
  /// `manual`.
  final String? source;

  /// DOI (frontmatter `doi`), may duplicate [CslMetadata.doi].
  final String? doi;

  /// CiNii identifier (frontmatter `cinii_id`).
  final String? ciniiId;

  /// Body section "## AI要約".
  final String? aiSummary;

  /// Body section "## 自分のメモ".
  final String? userNote;

  /// The `library/{folderName}/` directory name. Defaults to the citation key.
  final String? folderName;

  /// Citation key = CSL-JSON id.
  String get id => metadata.id;

  /// Effective folder name: explicit override or the citation key.
  String get effectiveFolderName => folderName ?? metadata.id;

  Paper copyWith({
    CslMetadata? metadata,
    List<String>? tags,
    String? source,
    String? doi,
    String? ciniiId,
    String? aiSummary,
    String? userNote,
    String? folderName,
  }) =>
      Paper(
        metadata: metadata ?? this.metadata,
        tags: tags ?? this.tags,
        source: source ?? this.source,
        doi: doi ?? this.doi,
        ciniiId: ciniiId ?? this.ciniiId,
        aiSummary: aiSummary ?? this.aiSummary,
        userNote: userNote ?? this.userNote,
        folderName: folderName ?? this.folderName,
      );
}
