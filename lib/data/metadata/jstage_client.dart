import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;

import '../../models/csl_metadata.dart';
import 'metadata_source.dart';

/// J-STAGE WebAPI client (`GET https://api.jstage.jst.go.jp/searchapi/do`).
///
/// The API returns an Atom-like XML feed (PRISM namespace) with bilingual
/// (ja/en) sub-elements for title/author, confirmed against
/// https://www.jstage.jst.go.jp/static/pages/JstageServices/TAB3/-char/en
/// (July 2026). A typical `<entry>`:
///
/// ```xml
/// <entry>
///   <article_title><ja>...</ja><en>...</en></article_title>
///   <author><ja><name>田中 太郎</name></ja><en><name>Taro Tanaka</name></en></author>
///   <material_title><ja>...</ja><en>...</en></material_title>
///   <prism:volume>65</prism:volume>
///   <prism:number>2</prism:number>
///   <prism:startingPage>1</prism:startingPage>
///   <prism:endingPage>10</prism:endingPage>
///   <pubyear>2024</pubyear>
///   <prism:doi>10.1234/...</prism:doi>
/// </entry>
/// ```
///
/// Per DESIGN.md「6.」日本語論文の日英併記メタデータはロスせず保持: both ja/en title
/// variants are preserved (ja as the primary `title`, en in `extra['title-en']`)
/// rather than picking just one.
class JstageClient {
  JstageClient({http.Client? httpClient}) : _client = httpClient ?? http.Client();

  final http.Client _client;

  static const String _base = 'https://api.jstage.jst.go.jp/searchapi/do';

  /// Search J-STAGE by free text (title/keywords) or a J-STAGE article URL
  /// (from which the identifying text is extracted). Returns the first match.
  Future<MetadataLookupResult?> search(String query) async {
    final uri = Uri.parse(_base).replace(queryParameters: {
      'service': '3',
      'text': query,
      'count': '1',
    });

    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw JstageException('J-STAGE returned HTTP ${response.statusCode}');
    }

    final xml.XmlDocument doc;
    try {
      doc = xml.XmlDocument.parse(response.body);
    } catch (e) {
      throw JstageException('J-STAGE response was not valid XML: $e');
    }

    final entries = doc.findAllElements('entry');
    if (entries.isEmpty) return null;
    final entry = entries.first;

    final metadata = normalize(entry);
    return MetadataLookupResult(metadata: metadata, source: MetadataSource.jstage);
  }

  /// Convert a raw `<entry>` XML element into [CslMetadata].
  static CslMetadata normalize(xml.XmlElement entry) {
    final titleJa = _bilingualText(entry, 'article_title', 'ja');
    final titleEn = _bilingualText(entry, 'article_title', 'en');

    final authors = <CslName>[];
    for (final authorEl in entry.findElements('author')) {
      final ja = authorEl.getElement('ja');
      final name = ja?.getElement('name')?.innerText.trim() ??
          authorEl.getElement('en')?.getElement('name')?.innerText.trim();
      if (name != null && name.isNotEmpty) {
        authors.add(CslName(literal: name));
      }
    }

    final containerJa = _bilingualText(entry, 'material_title', 'ja');
    final containerEn = _bilingualText(entry, 'material_title', 'en');

    final pubYearText = _elementText(entry, 'pubyear');
    List<List<int>>? dateParts;
    final year = int.tryParse(pubYearText ?? '');
    if (year != null) {
      dateParts = [
        [year]
      ];
    }

    final startPage = _prismText(entry, 'startingPage');
    final endPage = _prismText(entry, 'endingPage');
    String? page;
    if (startPage != null && startPage.isNotEmpty) {
      page = (endPage != null && endPage.isNotEmpty && endPage != startPage)
          ? '$startPage-$endPage'
          : startPage;
    }

    final doi = _prismText(entry, 'doi');
    final title = titleJa ?? titleEn;

    return CslMetadata(
      id: doi ?? _slugify(title ?? 'jstage'),
      type: 'article-journal',
      title: title,
      authors: authors,
      issuedDateParts: dateParts,
      containerTitle: containerJa ?? containerEn,
      volume: _prismText(entry, 'volume'),
      issue: _prismText(entry, 'number'),
      page: page,
      doi: doi,
      extra: <String, dynamic>{
        if (titleEn != null && titleEn != title) 'title-en': titleEn,
        if (containerEn != null && containerEn != (containerJa ?? containerEn))
          'container-title-en': containerEn,
      },
    );
  }

  static String? _bilingualText(
      xml.XmlElement entry, String tag, String lang) {
    final el = entry.getElement(tag);
    if (el == null) return null;
    final text = el.getElement(lang)?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  static String? _elementText(xml.XmlElement entry, String tag) {
    final text = entry.getElement(tag)?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  /// `prism:`-namespaced elements: match by local name since the namespace
  /// prefix binding can vary.
  static String? _prismText(xml.XmlElement entry, String localName) {
    for (final child in entry.childElements) {
      if (child.name.local == localName) {
        final text = child.innerText.trim();
        return text.isEmpty ? null : text;
      }
    }
    return null;
  }

  static String _slugify(String text) {
    final ascii = text.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '');
    return ascii.isEmpty ? 'jstage' : ascii.toLowerCase();
  }

  void close() => _client.close();
}

class JstageException implements Exception {
  JstageException(this.message);
  final String message;

  @override
  String toString() => 'JstageException: $message';
}
