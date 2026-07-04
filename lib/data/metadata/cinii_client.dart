import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/csl_metadata.dart';
import 'metadata_source.dart';

/// CiNii Research OpenSearch API client.
///
/// Current API surface (confirmed against https://support.nii.ac.jp/en/cir/r_opensearch,
/// July 2026): base `https://cir.nii.ac.jp/opensearch/articles`, `format=json`
/// returns a JSON-LD document with a top-level `items` array. Each item is
/// Dublin Core / PRISM–flavored:
///
/// ```json
/// {
///   "items": [
///     {
///       "@id": "https://cir.nii.ac.jp/crid/...",
///       "title": "...",
///       "dc:creator": ["田中 太郎", "鈴木 花子"],
///       "prism:publicationName": "情報処理学会論文誌",
///       "prism:volume": "65",
///       "prism:number": "2",
///       "prism:publicationDate": "2024",
///       "dc:identifier": ["...", "..."]
///     }
///   ]
/// }
/// ```
///
/// IMPORTANT: this is CiNii **Research** (`cir.nii.ac.jp`), which superseded
/// the old CiNii Articles (`ci.nii.ac.jp`) `naid`-based endpoints. Per
/// DESIGN.md「6.」, the legacy `naid` API is deprecated and must not be used.
/// `appid` (an application ID issued by NII) is required for production use;
/// [appId] is threaded through so it can be configured, but requests without
/// one still work against the public endpoint at reduced rate limits during
/// development.
class CiniiClient {
  CiniiClient({http.Client? httpClient, this.appId})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  /// NII-issued application ID (optional; configurable in Settings).
  final String? appId;

  static const String _base = 'https://cir.nii.ac.jp/opensearch/articles';

  /// Search by free-text query (title/keywords) or a CiNii CRID/ID/URL.
  /// Returns the first (best) match, or null if nothing found.
  Future<MetadataLookupResult?> search(String query) async {
    final citationId = _extractCrid(query) ?? _slugify(query);
    final uri = Uri.parse(_base).replace(queryParameters: {
      'q': query,
      'format': 'json',
      'count': '1',
      if (appId != null && appId!.isNotEmpty) 'appid': appId!,
    });

    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode != 200) {
      throw CiniiException('CiNii Research returned HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw CiniiException('CiNii Research response was not valid JSON: $e');
    }

    final items = body['items'];
    if (items is! List || items.isEmpty) return null;
    final first = items.first;
    if (first is! Map) return null;

    final metadata =
        normalize(first.cast<String, dynamic>(), fallbackId: citationId);
    return MetadataLookupResult(metadata: metadata, source: MetadataSource.cinii);
  }

  /// Convert a raw CiNii Research OpenSearch item into [CslMetadata].
  static CslMetadata normalize(Map<String, dynamic> item,
      {required String fallbackId}) {
    final title = item['title']?.toString();

    final creators = item['dc:creator'];
    final authors = <CslName>[];
    if (creators is List) {
      for (final c in creators) {
        final name = c?.toString().trim();
        if (name != null && name.isNotEmpty) {
          // CiNii creator strings are full display names (often Japanese,
          // "family given" with a space, or organizations); keep literal
          // rather than guessing a family/given split.
          authors.add(CslName(literal: name));
        }
      }
    } else if (creators is String && creators.trim().isNotEmpty) {
      authors.add(CslName(literal: creators.trim()));
    }

    List<List<int>>? dateParts;
    final pubDate = item['prism:publicationDate']?.toString();
    if (pubDate != null && pubDate.isNotEmpty) {
      dateParts = _parseDateParts(pubDate);
    }

    final ciniiUrl = (item['@id'] ?? item['link'])?.toString();
    final crid = _extractCrid(ciniiUrl ?? '') ?? fallbackId;

    String? doi;
    final identifiers = item['dc:identifier'];
    if (identifiers is List) {
      for (final id in identifiers) {
        final s = id?.toString() ?? '';
        final match = RegExp(r'10\.\d{4,9}/\S+').firstMatch(s);
        if (match != null) {
          doi = match.group(0);
          break;
        }
      }
    }

    return CslMetadata(
      id: crid,
      type: 'article-journal',
      title: title,
      authors: authors,
      issuedDateParts: dateParts,
      containerTitle: item['prism:publicationName']?.toString(),
      volume: item['prism:volume']?.toString(),
      issue: item['prism:number']?.toString(),
      doi: doi,
      url: ciniiUrl,
      extra: <String, dynamic>{
        if (crid.isNotEmpty) 'cinii_id': crid,
      },
    );
  }

  static List<List<int>> _parseDateParts(String date) {
    final parts = date.split('-');
    final ints = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) break;
      ints.add(n);
    }
    return ints.isEmpty ? [] : [ints];
  }

  /// Extract a CiNii CRID (e.g. `1050282677628470784`) from a CiNii Research
  /// URL such as `https://cir.nii.ac.jp/crid/1050282677628470784`.
  static String? _extractCrid(String text) {
    final match = RegExp(r'crid/(\d+)').firstMatch(text);
    return match?.group(1);
  }

  static String _slugify(String text) {
    final ascii = text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    return ascii.isEmpty ? 'cinii' : ascii.toLowerCase();
  }

  void close() => _client.close();
}

class CiniiException implements Exception {
  CiniiException(this.message);
  final String message;

  @override
  String toString() => 'CiniiException: $message';
}
