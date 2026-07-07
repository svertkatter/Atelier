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
///
/// When the user pastes a CiNii Research URL containing a CRID (e.g.
/// `https://cir.nii.ac.jp/crid/1050868284190107520`), the opensearch/articles
/// free-text endpoint above returns zero results for a bare CRID number — it
/// is a full-text search API, not a lookup-by-id API. For CRIDs, use
/// [lookupByCrid] instead, which fetches the record directly:
/// `GET https://cir.nii.ac.jp/crid/{crid}.json`. That endpoint returns a
/// differently-shaped JSON-LD record (confirmed live against
/// `https://cir.nii.ac.jp/crid/1050868284190107520.json`, July 2026):
///
/// ```json
/// {
///   "@id": "https://cir.nii.ac.jp/crid/1050868284190107520.json",
///   "@type": "Article",
///   "resourceType": "会議発表資料(conference paper)",
///   "dc:title": [{"@language": "ja", "@value": "..."}],
///   "creator": [
///     {"@type": "Researcher", "foaf:name": [{"@value": "椎原,蓮水"}]}
///   ],
///   "publication": {
///     "prism:publicationName": [{"@value": "..."}],
///     "dc:publisher": [{"@value": "情報処理学会"}],
///     "prism:publicationDate": "2025-08-18",
///     "prism:volume": "2025",
///     "prism:startingPage": "343",
///     "prism:endingPage": "347"
///   },
///   "url": [{"@id": "https://..."}],
///   "description": [{"type": "Other", "notation": [{"@value": "..."}]}]
/// }
/// ```
///
/// Notably: no top-level DOI field (many CRID records, especially conference
/// papers indexed via IRDB, simply have none); author names are
/// `"family,given"` (halfwidth comma, no space); values are wrapped in
/// `[{"@value": ...}]` (optionally with `"@language"`) rather than being bare
/// strings/arrays like the opensearch shape [normalize] handles.
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
    final citationId = extractCrid(query) ?? _slugify(query);
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

  /// Fetch a CiNii Research record directly by [crid] (the numeric CRID, not
  /// a URL) via `GET https://cir.nii.ac.jp/crid/{crid}.json`. Returns null on
  /// 404/not-found; throws [CiniiException] on other HTTP or parse failures.
  ///
  /// Prefer this over [search] whenever a CRID has been detected in the
  /// user's input (see [IdentifierDetection]/`metadata_lookup.dart`) — the
  /// opensearch endpoint 0-matches a bare CRID number since it is a free-text
  /// search, not an id lookup.
  Future<MetadataLookupResult?> lookupByCrid(String crid) async {
    final uri = Uri.parse('https://cir.nii.ac.jp/crid/$crid.json');
    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
    });

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw CiniiException(
          'CiNii Research returned HTTP ${response.statusCode}');
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw CiniiException('CiNii Research response was not valid JSON: $e');
    }

    final metadata = normalizeCridRecord(body, fallbackId: crid);
    return MetadataLookupResult(metadata: metadata, source: MetadataSource.cinii);
  }

  /// Convert a raw CiNii Research CRID JSON-LD record (as returned by
  /// `GET /crid/{crid}.json`) into [CslMetadata]. This is a different shape
  /// from the opensearch/articles item handled by [normalize] — see the
  /// class doc comment for a sample record.
  static CslMetadata normalizeCridRecord(Map<String, dynamic> record,
      {required String fallbackId}) {
    final crid = extractCrid(record['@id']?.toString() ?? '') ?? fallbackId;

    final title = _firstValue(record['dc:title'], preferLang: 'ja');

    final authors = <CslName>[];
    final creators = record['creator'];
    if (creators is List) {
      for (final c in creators) {
        if (c is Map) {
          final name = _firstValue(c['foaf:name']);
          if (name != null && name.trim().isNotEmpty) {
            authors.add(_splitJaFamilyGiven(name));
          }
        }
      }
    }

    String? containerTitle;
    String? publisher;
    String? volume;
    String? issue;
    String? page;
    List<List<int>>? dateParts;
    final publication = record['publication'];
    if (publication is Map) {
      containerTitle = _firstValue(publication['prism:publicationName']);
      publisher = _firstValue(publication['dc:publisher']);
      volume = publication['prism:volume']?.toString();
      issue = publication['prism:number']?.toString();
      final start = publication['prism:startingPage']?.toString();
      final end = publication['prism:endingPage']?.toString();
      if (start != null && start.isNotEmpty) {
        page = (end != null && end.isNotEmpty && end != start)
            ? '$start-$end'
            : start;
      }
      final pubDate = publication['prism:publicationDate']?.toString();
      if (pubDate != null && pubDate.isNotEmpty) {
        dateParts = _parseDateParts(pubDate);
      }
    }

    String? url;
    final urlList = record['url'];
    if (urlList is List && urlList.isNotEmpty && urlList.first is Map) {
      url = (urlList.first as Map)['@id']?.toString();
    }
    url ??= record['@id']?.toString();

    final abstractText = _firstValue(record['description'], nested: 'notation');

    final doi = _findDoi(record);
    final type = _mapResourceType(
        record['resourceType']?.toString(), record['@type']?.toString());

    return CslMetadata(
      id: crid,
      type: type,
      title: title,
      authors: authors,
      issuedDateParts: dateParts,
      containerTitle: containerTitle,
      volume: volume,
      issue: issue,
      page: page,
      doi: doi,
      url: url,
      publisher: publisher,
      abstractText: abstractText,
      extra: <String, dynamic>{
        if (crid.isNotEmpty) 'cinii_id': crid,
      },
    );
  }

  /// Extract a `@value` string out of the CRID JSON-LD's recurring
  /// `[{"@language": "ja", "@value": "..."}]` / `[{"@value": "..."}]` shape.
  /// When [preferLang] is given, prefers the entry whose `@language` matches
  /// it, falling back to the first entry otherwise. When [nested] is given
  /// (e.g. `description`'s `notation` sub-array), looks one level deeper.
  static String? _firstValue(Object? node,
      {String? preferLang, String? nested}) {
    if (node is! List || node.isEmpty) return null;

    Object? pick(List list) {
      if (preferLang != null) {
        for (final item in list) {
          if (item is Map && item['@language'] == preferLang) {
            return item['@value'];
          }
        }
      }
      final first = list.first;
      if (first is Map) return first['@value'];
      return first;
    }

    if (nested != null) {
      for (final item in node) {
        if (item is Map && item[nested] is List) {
          final value = pick(item[nested] as List);
          if (value != null) return value.toString();
        }
      }
      return null;
    }

    final value = pick(node);
    return value?.toString();
  }

  /// CiNii Research CRID records give creator names as `"family,given"`
  /// (halfwidth comma, no space, e.g. `"椎原,蓮水"`). Split when that pattern
  /// holds; otherwise keep the whole string as a literal name so we never
  /// lose information by guessing wrong.
  static CslName _splitJaFamilyGiven(String raw) {
    final trimmed = raw.trim();
    final commaIndex = trimmed.indexOf(',');
    if (commaIndex > 0 && commaIndex < trimmed.length - 1) {
      final family = trimmed.substring(0, commaIndex).trim();
      final given = trimmed.substring(commaIndex + 1).trim();
      if (family.isNotEmpty && given.isNotEmpty) {
        return CslName(family: family, given: given);
      }
    }
    return CslName(literal: trimmed);
  }

  /// CRID records have no dedicated DOI field; scan the identifier arrays
  /// (`productIdentifier`, `dataSourceIdentifier`) for a DOI-shaped string,
  /// the same defensive approach [normalize] uses for opensearch's
  /// `dc:identifier` list. Returns null when nothing DOI-shaped is found
  /// (common for conference papers/reports with no assigned DOI).
  static String? _findDoi(Map<String, dynamic> record) {
    final candidates = <String>[];
    void collect(Object? node) {
      if (node is Map) {
        for (final v in node.values) {
          collect(v);
        }
      } else if (node is List) {
        for (final e in node) {
          collect(e);
        }
      } else if (node is String) {
        candidates.add(node);
      }
    }

    collect(record['productIdentifier']);
    collect(record['dataSourceIdentifier']);
    final direct = record['doi'];
    if (direct != null) candidates.add(direct.toString());

    for (final candidate in candidates) {
      final match = RegExp(r'10\.\d{4,9}/\S+').firstMatch(candidate);
      if (match != null) return match.group(0);
    }
    return null;
  }

  /// Map CRID's `resourceType` (a bilingual free-text label, e.g.
  /// `"会議発表資料(conference paper)"`) and/or `@type` to a CSL type.
  /// Defaults to `article-journal` (same default [normalize] uses) when
  /// nothing more specific is recognized.
  static String? _mapResourceType(String? resourceType, String? atType) {
    final lower = resourceType?.toLowerCase() ?? '';
    if (lower.contains('conference')) return 'paper-conference';
    if (lower.contains('book')) return 'book';
    if (lower.contains('thesis') || lower.contains('dissertation')) {
      return 'thesis';
    }
    if (lower.contains('report')) return 'report';
    if (lower.contains('journal') || lower.contains('article')) {
      return 'article-journal';
    }
    return 'article-journal';
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
    final crid = extractCrid(ciniiUrl ?? '') ?? fallbackId;

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
  /// URL such as `https://cir.nii.ac.jp/crid/1050282677628470784`. Public so
  /// `metadata_lookup.dart` can route a detected CRID straight to
  /// [lookupByCrid] before falling back to [search].
  static String? extractCrid(String text) {
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
