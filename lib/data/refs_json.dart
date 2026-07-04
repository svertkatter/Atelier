import 'dart:convert';

import '../models/csl_metadata.dart';
import '../models/paper.dart';

/// Builds `refs.json` — a CSL-JSON array — from a set of papers' metadata.
///
/// This is a pure data transform (YAML frontmatter -> JSON array). No citation
/// logic lives here; pandoc performs all CSL formatting downstream.
class RefsJson {
  /// Convert an ordered list of [CslMetadata] into a CSL-JSON array.
  static List<Map<String, dynamic>> build(List<CslMetadata> metadata) =>
      metadata.map((m) => m.toJson()).toList();

  /// Convenience: build from papers.
  static List<Map<String, dynamic>> fromPapers(List<Paper> papers) =>
      build(papers.map((p) => p.metadata).toList());

  /// Select, in [refs] order, the metadata for the given citation keys from
  /// [available], then serialize. Missing keys are skipped (caller may warn).
  static List<Map<String, dynamic>> forRefs(
    List<String> refs,
    Map<String, CslMetadata> available,
  ) {
    final result = <Map<String, dynamic>>[];
    for (final key in refs) {
      final meta = available[key];
      if (meta != null) result.add(meta.toJson());
    }
    return result;
  }

  /// Serialize a CSL-JSON array to pretty-printed text.
  static String serialize(List<Map<String, dynamic>> array) =>
      const JsonEncoder.withIndent('  ').convert(array);
}
