import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/csl_metadata.dart';
import 'metadata_source.dart';

/// CrossRef REST API client (`GET /works/{doi}`).
///
/// CrossRef's response is CSL-JSON–shaped already (see
/// https://github.com/CrossRef/rest-api-doc), so normalization is mostly a
/// direct mapping via [CslMetadata.fromJson] with two adjustments:
/// - `title`/`container-title` are arrays in the CrossRef response but plain
///   strings in the CSL-JSON we store; we take the first element.
/// - CrossRef always answers in English metadata (no ja/en split), so no
///   bilingual handling is needed here (unlike CiNii/J-STAGE).
///
/// Per DESIGN.md「6.」CrossRef is polite-pool, so the User-Agent must include a
/// contact `mailto:`. [contactEmail] is the CrossRef contact address (user
/// configurable in Settings; defaults to the app owner's address).
class CrossrefClient {
  CrossrefClient({
    http.Client? httpClient,
    this.contactEmail = 'alice241102@gmail.com',
  }) : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// Contact email included in the polite-pool User-Agent.
  final String contactEmail;

  static const String _base = 'https://api.crossref.org/works';

  /// Fetch and normalize metadata for [doi]. Returns null on 404/not-found;
  /// throws [CrossrefException] on other HTTP or parse failures.
  Future<MetadataLookupResult?> fetchByDoi(String doi) async {
    final cleaned = _cleanDoi(doi);
    // DOIs contain '/', which is a valid path separator for CrossRef (it must
    // NOT be percent-encoded to %2F, or the API 404s), so build the path
    // manually rather than via Uri.encodeComponent.
    final uri = Uri.parse('$_base/$cleaned');
    final response = await _client.get(
      uri,
      headers: {
        'User-Agent':
            'Atelier/1.0 (https://github.com/; mailto:$contactEmail)',
        'Accept': 'application/json',
      },
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw CrossrefException(
          'CrossRef returned HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw CrossrefException('CrossRef response was not valid JSON: $e');
    }

    final message = body['message'];
    if (message is! Map<String, dynamic>) {
      throw CrossrefException('CrossRef response missing "message"');
    }

    final metadata = normalize(message, citationId: cleaned);
    return MetadataLookupResult(
        metadata: metadata, source: MetadataSource.crossref);
  }

  /// Convert a raw CrossRef `message` object into [CslMetadata].
  /// Exposed statically so tests can feed fixture JSON without HTTP.
  static CslMetadata normalize(Map<String, dynamic> message,
      {required String citationId}) {
    final titles = message['title'];
    final title = (titles is List && titles.isNotEmpty)
        ? titles.first.toString()
        : null;

    final containerTitles = message['container-title'];
    final containerTitle = (containerTitles is List && containerTitles.isNotEmpty)
        ? containerTitles.first.toString()
        : null;

    final authorsRaw = message['author'];
    final authors = <CslName>[];
    if (authorsRaw is List) {
      for (final a in authorsRaw) {
        if (a is Map) {
          authors.add(CslName(
            family: a['family']?.toString(),
            given: a['given']?.toString(),
          ));
        }
      }
    }

    List<List<int>>? dateParts;
    final issued = message['issued'];
    if (issued is Map) {
      final dp = issued['date-parts'];
      if (dp is List) {
        dateParts = dp
            .whereType<List>()
            .map((row) => row
                .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
                .toList())
            .toList();
      }
    }

    return CslMetadata(
      id: citationId,
      type: message['type']?.toString(),
      title: title,
      authors: authors,
      issuedDateParts: dateParts,
      containerTitle: containerTitle,
      volume: message['volume']?.toString(),
      issue: message['issue']?.toString(),
      page: message['page']?.toString(),
      doi: (message['DOI'] ?? citationId).toString(),
      url: message['URL']?.toString(),
      publisher: message['publisher']?.toString(),
      abstractText: _stripJatsTags(message['abstract']?.toString()),
    );
  }

  /// CrossRef abstracts are sometimes wrapped in JATS `<jats:p>` tags; strip
  /// simple tags so meta.md stays plain text. Best-effort, not a full parser.
  static String? _stripJatsTags(String? raw) {
    if (raw == null) return null;
    final stripped = raw.replaceAll(RegExp(r'<[^>]+>'), '').trim();
    return stripped.isEmpty ? null : stripped;
  }

  static String _cleanDoi(String doi) {
    var s = doi.trim();
    s = s.replaceFirst(RegExp(r'^https?://(dx\.)?doi\.org/', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^doi:', caseSensitive: false), '');
    return s;
  }

  void close() => _client.close();
}

class CrossrefException implements Exception {
  CrossrefException(this.message);
  final String message;

  @override
  String toString() => 'CrossrefException: $message';
}
