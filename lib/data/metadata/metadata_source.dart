import '../../models/csl_metadata.dart';

/// Where a [CslMetadata] fetch result came from. Persisted in meta.md's
/// `source:` frontmatter field (see DESIGN.md meta.md structure and
/// DESIGN.md「6. メタデータ取得フロー」for the priority chain).
enum MetadataSource {
  crossref,
  openalex,
  cinii,
  jstage,
  manual;

  /// The string stored in meta.md frontmatter (`source: crossref` etc.).
  String get id => switch (this) {
        MetadataSource.crossref => 'crossref',
        MetadataSource.openalex => 'openalex',
        MetadataSource.cinii => 'cinii',
        MetadataSource.jstage => 'jstage',
        MetadataSource.manual => 'manual',
      };
}

/// Result of a metadata lookup: the normalized CSL metadata plus which API
/// produced it (so callers can record `source:` and decide whether to try the
/// next fallback in the priority chain).
class MetadataLookupResult {
  const MetadataLookupResult({
    required this.metadata,
    required this.source,
  });

  final CslMetadata metadata;
  final MetadataSource source;

  /// True when the result looks "thin" (missing title or authors) and a
  /// fallback/supplemental source should still be tried (DESIGN.md: CrossRef
  /// failure/thin info -> OpenAlex supplement).
  bool get isThin =>
      metadata.title == null ||
      metadata.title!.trim().isEmpty ||
      metadata.authors.isEmpty;
}
