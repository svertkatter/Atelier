import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xml/xml.dart' as xml;

import 'package:atelier/data/metadata/jstage_client.dart';
import 'package:atelier/data/metadata/metadata_source.dart';

/// Fixture shaped like the J-STAGE WebAPI XML feed (bilingual ja/en elements,
/// PRISM namespace for volume/issue/pages) — verified against
/// https://api.jstage.jst.go.jp/searchapi/do (service=3), July 2026.
const _jstageXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:prism="http://prismstandard.org/namespaces/basic/2.0/">
  <entry>
    <article_title>
      <ja>都市環境における音風景の知覚と感情的評価に関する研究</ja>
      <en>A Study on Perception and Emotional Evaluation of Urban Soundscapes</en>
    </article_title>
    <author>
      <ja><name>田中 太郎</name></ja>
      <en><name>Taro Tanaka</name></en>
    </author>
    <material_title>
      <ja>情報処理学会論文誌</ja>
      <en>Journal of Information Processing Society of Japan</en>
    </material_title>
    <prism:volume>65</prism:volume>
    <prism:number>2</prism:number>
    <prism:startingPage>1</prism:startingPage>
    <prism:endingPage>10</prism:endingPage>
    <pubyear>2024</pubyear>
    <prism:doi>10.1234/jstage.example</prism:doi>
  </entry>
</feed>
''';

void main() {
  group('JstageClient.normalize', () {
    test('maps a J-STAGE entry to CslMetadata, preferring ja title', () {
      final doc = xml.XmlDocument.parse(_jstageXml);
      final entry = doc.findAllElements('entry').first;
      final metadata = JstageClient.normalize(entry);

      expect(metadata.title, '都市環境における音風景の知覚と感情的評価に関する研究');
      expect(metadata.extra['title-en'],
          'A Study on Perception and Emotional Evaluation of Urban Soundscapes');
      expect(metadata.authors, hasLength(1));
      expect(metadata.authors.first.literal, '田中 太郎');
      expect(metadata.year, 2024);
      expect(metadata.containerTitle, '情報処理学会論文誌');
      expect(metadata.extra['container-title-en'],
          'Journal of Information Processing Society of Japan');
      expect(metadata.volume, '65');
      expect(metadata.issue, '2');
      expect(metadata.page, '1-10');
      expect(metadata.doi, '10.1234/jstage.example');
      expect(metadata.id, '10.1234/jstage.example');
    });

    test('falls back to en title when ja missing', () {
      const xmlText = '''
      <entry>
        <article_title><en>English Only Title</en></article_title>
      </entry>''';
      final entry = xml.XmlDocument.parse(xmlText).findAllElements('entry').first;
      final metadata = JstageClient.normalize(entry);
      expect(metadata.title, 'English Only Title');
      expect(metadata.extra.containsKey('title-en'), isFalse);
    });

    test('single page when start==end', () {
      const xmlText = '''
      <entry xmlns:prism="http://prismstandard.org/namespaces/basic/2.0/">
        <article_title><ja>T</ja></article_title>
        <prism:startingPage>5</prism:startingPage>
        <prism:endingPage>5</prism:endingPage>
      </entry>''';
      final entry = xml.XmlDocument.parse(xmlText).findAllElements('entry').first;
      final metadata = JstageClient.normalize(entry);
      expect(metadata.page, '5');
    });

    test('generates a slug id when no DOI present', () {
      const xmlText = '''
      <entry>
        <article_title><ja>タイトルのみ</ja></article_title>
      </entry>''';
      final entry = xml.XmlDocument.parse(xmlText).findAllElements('entry').first;
      final metadata = JstageClient.normalize(entry);
      expect(metadata.doi, isNull);
      expect(metadata.id, isNotEmpty);
    });
  });

  group('JstageClient.search (MockClient)', () {
    test('fetches and normalizes the first entry', () async {
      final client = JstageClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.jstage.jst.go.jp');
          expect(request.url.queryParameters['service'], '3');
          return http.Response.bytes(utf8.encode(_jstageXml), 200,
              headers: {'content-type': 'application/xml; charset=utf-8'});
        }),
      );

      final result = await client.search('音風景');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.jstage);
      expect(result.metadata.containerTitle, '情報処理学会論文誌');
    });

    test('returns null when no entry element present', () async {
      final client = JstageClient(
        httpClient: MockClient((request) async =>
            http.Response('<feed></feed>', 200)),
      );
      final result = await client.search('nothing');
      expect(result, isNull);
    });

    test('throws JstageException on server error', () async {
      final client = JstageClient(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      expect(() => client.search('x'), throwsA(isA<JstageException>()));
    });
  });
}
