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
/// CiNii ID/URL      -> CRID? -> CiNii Research lookupByCrid (direct)
///                             -> (no CRID, or that fails) -> opensearch free-text
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
        return _lookupCinii(detected.value);
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

  /// A CRID (e.g. from a `cir.nii.ac.jp/crid/...` URL) must go through the
  /// direct-lookup endpoint first: the opensearch/articles endpoint used by
  /// [CiniiClient.search] is a free-text search and returns zero matches for
  /// a bare CRID number. Only fall back to the free-text search when no CRID
  /// could be extracted (e.g. a legacy `naid/...` URL) or the direct lookup
  /// fails outright (network error, 404, unexpected shape).
  Future<MetadataLookupResult?> _lookupCinii(String text) async {
    final crid = CiniiClient.extractCrid(text);
    if (crid != null) {
      try {
        final direct = await _cinii.lookupByCrid(crid);
        if (direct != null) return direct;
      } catch (_) {
        // Fall through to the opensearch free-text fallback below.
      }
    }
    return _cinii.search(text);
  }

  void close() {
    _crossref.close();
    _openAlex.close();
    _cinii.close();
    _jstage.close();
  }
}
