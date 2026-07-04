import 'package:http/http.dart' as http;

import 'cinii_client.dart';
import 'crossref_client.dart';
import 'identifier_detection.dart';
import 'jstage_client.dart';
import 'metadata_source.dart';
import 'openalex_client.dart';

/// Orchestrates the metadata fetch priority chain from DESIGN.md「6.」:
///
/// ```
/// DOI detected      -> CrossRef -> (failure/thin) -> OpenAlex supplement
/// CiNii ID/URL      -> CiNii Research
/// J-STAGE URL       -> J-STAGE
/// nothing detected  -> null (caller falls back to the manual entry form)
/// ```
///
/// This class only sequences the three HTTP clients; it does not implement
/// citation-processor logic (that stays in pandoc, per CLAUDE.md).
class MetadataLookup {
  MetadataLookup({
    http.Client? httpClient,
    String crossrefContactEmail = 'alice241102@gmail.com',
    String? ciniiAppId,
  })  : _crossref = CrossrefClient(
            httpClient: httpClient, contactEmail: crossrefContactEmail),
        _openAlex = OpenAlexClient(httpClient: httpClient),
        _cinii = CiniiClient(httpClient: httpClient, appId: ciniiAppId),
        _jstage = JstageClient(httpClient: httpClient);

  final CrossrefClient _crossref;
  final OpenAlexClient _openAlex;
  final CiniiClient _cinii;
  final JstageClient _jstage;

  /// Run the full detect -> fetch -> fallback chain for free-form [input]
  /// (a pasted DOI, CiNii URL, J-STAGE URL, or plain text). Returns null if no
  /// identifier was recognized or every source failed to find a match.
  Future<MetadataLookupResult?> lookup(String input) async {
    final detected = IdentifierDetection.detect(input);
    switch (detected.kind) {
      case DetectedIdentifierKind.doi:
        return _lookupDoi(detected.value);
      case DetectedIdentifierKind.cinii:
        return _cinii.search(detected.value);
      case DetectedIdentifierKind.jstage:
        return _jstage.search(detected.value);
      case DetectedIdentifierKind.none:
        return null;
    }
  }

  /// CrossRef first; if it fails outright or returns thin metadata, try
  /// OpenAlex and prefer whichever result is non-thin (CrossRef wins ties,
  /// since it's the primary source).
  Future<MetadataLookupResult?> _lookupDoi(String doi) async {
    MetadataLookupResult? crossrefResult;
    try {
      crossrefResult = await _crossref.fetchByDoi(doi);
    } catch (_) {
      crossrefResult = null;
    }

    if (crossrefResult != null && !crossrefResult.isThin) {
      return crossrefResult;
    }

    MetadataLookupResult? openAlexResult;
    try {
      openAlexResult = await _openAlex.fetchByDoi(doi);
    } catch (_) {
      openAlexResult = null;
    }

    if (crossrefResult == null) return openAlexResult;
    if (openAlexResult == null) return crossrefResult;
    // Both present but CrossRef was thin: prefer OpenAlex only if it is
    // actually richer.
    return openAlexResult.isThin ? crossrefResult : openAlexResult;
  }

  void close() {
    _crossref.close();
    _openAlex.close();
    _cinii.close();
    _jstage.close();
  }
}
