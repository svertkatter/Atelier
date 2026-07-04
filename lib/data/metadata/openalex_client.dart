import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/csl_metadata.dart';
import 'metadata_source.dart';

/// OpenAlex API client (`GET /works/doi:{doi}`). No API key required.
///
/// Used per DESIGN.md「6.」as a supplement/fallback when CrossRef fails or
/// returns thin metadata. OpenAlex's shape differs from CSL-JSON
/// (`display_name`, `authorships[].author.display_name`,
/// `primary_location.source.display_name`, `biblio.{volume,issue,first_page,
/// last_page}`), so this client normalizes into the same [CslMetadata] used
/// everywhere else.
class OpenAlexClient {
  OpenAlexClient({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://api.openalex.org/works/doi:';

  /// Fetch and normalize metadata for [doi]. Returns null on 404/not-found;
  /// throws [OpenAlexException] on other HTTP or parse failures.
  Future<MetadataLookupResult?> fetchByDoi(String doi) async {
    final cleaned = _cleanDoi(doi);
    // Same rationale as CrossRef: keep '/' unescaped in the DOI suffix.
    final uri = Uri.parse('$_base$cleaned');
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw OpenAlexException('OpenAlex returned HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw OpenAlexException('OpenAlex response was not valid JSON: $e');
    }

    final metadata = normalize(body, citationId: cleaned);
    return MetadataLookupResult(
        metadata: metadata, source: MetadataSource.openalex);
  }

  /// Convert a raw OpenAlex work object into [CslMetadata].
  static CslMetadata normalize(Map<String, dynamic> work,
      {required String citationId}) {
    final title = (work['title'] ?? work['display_name'])?.toString();

    final authorships = work['authorships'];
    final authors = <CslName>[];
    if (authorships is List) {
      for (final a in authorships) {
        if (a is Map) {
          final author = a['author'];
          final displayName = author is Map ? author['display_name'] : null;
          final rawName = a['raw_author_name'];
          final name = (displayName ?? rawName)?.toString();
          if (name == null || name.trim().isEmpty) continue;
          authors.add(_splitDisplayName(name));
        }
      }
    }

    List<List<int>>? dateParts;
    final year = work['publication_year'];
    if (year is int) {
      dateParts = [
        [year]
      ];
    }
    final publicationDate = work['publication_date']?.toString();
    if (publicationDate != null && publicationDate.length >= 10) {
      final parts = publicationDate.split('-');
      if (parts.length == 3) {
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y != null && m != null && d != null) {
          dateParts = [
            [y, m, d]
          ];
        }
      }
    }

    String? containerTitle;
    final primaryLocation = work['primary_location'];
    if (primaryLocation is Map) {
      final source = primaryLocation['source'];
      if (source is Map) {
        containerTitle = source['display_name']?.toString();
      }
    }

    String? volume, issue, page;
    final biblio = work['biblio'];
    if (biblio is Map) {
      volume = biblio['volume']?.toString();
      issue = biblio['issue']?.toString();
      final first = biblio['first_page']?.toString();
      final last = biblio['last_page']?.toString();
      if (first != null && first.isNotEmpty) {
        page = (last != null && last.isNotEmpty && last != first)
            ? '$first-$last'
            : first;
      }
    }

    String? doi = work['doi']?.toString();
    if (doi != null) {
      doi = doi.replaceFirst(
          RegExp(r'^https?://(dx\.)?doi\.org/', caseSensitive: false), '');
    }

    return CslMetadata(
      id: citationId,
      type: _mapType(work['type']?.toString()),
      title: title,
      authors: authors,
      issuedDateParts: dateParts,
      containerTitle: containerTitle,
      volume: volume,
      issue: issue,
      page: page,
      doi: doi ?? citationId,
      url: work['id']?.toString(),
      abstractText: _reconstructAbstract(work['abstract_inverted_index']),
    );
  }

  /// OpenAlex types roughly map to CSL types; default to `article-journal`
  /// for the common `article` type and pass through others unchanged.
  static String? _mapType(String? openAlexType) {
    if (openAlexType == null) return null;
    if (openAlexType == 'article') return 'article-journal';
    return openAlexType;
  }

  /// OpenAlex encodes abstracts as an inverted index (word -> positions) to
  /// avoid copyright issues with raw text. Reconstruct plain text from it.
  static String? _reconstructAbstract(Object? invertedIndex) {
    if (invertedIndex is! Map) return null;
    final positions = <int, String>{};
    for (final entry in invertedIndex.entries) {
      final word = entry.key.toString();
      final idxList = entry.value;
      if (idxList is List) {
        for (final idx in idxList) {
          if (idx is int) positions[idx] = word;
        }
      }
    }
    if (positions.isEmpty) return null;
    final maxIndex = positions.keys.reduce((a, b) => a > b ? a : b);
    final words = List<String>.generate(
        maxIndex + 1, (i) => positions[i] ?? '');
    final text = words.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? null : text;
  }

  /// OpenAlex authorships give a single display name (no family/given split).
  /// Heuristic: last whitespace-separated token is the family name for
  /// Western order; kept as literal when ambiguous (e.g. Japanese names,
  /// single-word names) so we never guess wrong and lose information.
  static CslName _splitDisplayName(String name) {
    final trimmed = name.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length < 2) {
      return CslName(literal: trimmed);
    }
    // Keep as literal; OpenAlex names are not reliably family/given ordered
    // (this matters especially for Japanese author names), so we preserve the
    // full string rather than mis-split it.
    return CslName(literal: trimmed);
  }

  static String _cleanDoi(String doi) {
    var s = doi.trim();
    s = s.replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^doi:', caseSensitive: false), '');
    return s;
  }

  void close() => _client.close();
}

class OpenAlexException implements Exception {
  OpenAlexException(this.message);
  final String message;

  @override
  String toString() => 'OpenAlexException: $message';
}
