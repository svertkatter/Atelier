import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atelier/data/metadata/cinii_client.dart';
import 'package:atelier/data/metadata/metadata_source.dart';

/// Fixture shaped like the CiNii Research OpenSearch v1 JSON-LD response
/// (verified against https://cir.nii.ac.jp/opensearch/articles?...&format=json,
/// July 2026 — the current, non-deprecated endpoint; NOT the legacy CiNii
/// Articles `naid` API, which DESIGN.md explicitly forbids).
const _ciniiFixture = {
  '@context': {},
  'opensearch:totalResults': 1,
  'items': [
    {
      '@id': 'https://cir.nii.ac.jp/crid/1050282677628470784',
      'title': '都市環境における音風景の知覚と感情的評価に関する研究',
      'dc:creator': ['田中 太郎', '鈴木 花子'],
      'dc:type': 'Article',
      'prism:publicationName': '情報処理学会論文誌',
      'prism:volume': '65',
      'prism:number': '2',
      'prism:publicationDate': '2024',
      'dc:identifier': ['AA12345678', 'https://doi.org/10.1234/abcd'],
    }
  ],
};

void main() {
  group('CiniiClient.normalize', () {
    test('maps a CiNii Research OpenSearch item to CslMetadata', () {
      final item = (_ciniiFixture['items'] as List).first as Map;
      final metadata =
          CiniiClient.normalize(item.cast(), fallbackId: 'fallback');

      expect(metadata.title, '都市環境における音風景の知覚と感情的評価に関する研究');
      expect(metadata.authors, hasLength(2));
      expect(metadata.authors[0].literal, '田中 太郎');
      expect(metadata.authors[1].literal, '鈴木 花子');
      expect(metadata.year, 2024);
      expect(metadata.containerTitle, '情報処理学会論文誌');
      expect(metadata.volume, '65');
      expect(metadata.issue, '2');
      expect(metadata.id, '1050282677628470784'); // extracted CRID
      expect(metadata.doi, '10.1234/abcd');
      expect(metadata.extra['cinii_id'], '1050282677628470784');
    });

    test('falls back to provided id when no CRID present in @id', () {
      final metadata = CiniiClient.normalize({
        'title': 'No CRID here',
      }, fallbackId: 'myfallback');
      expect(metadata.id, 'myfallback');
    });

    test('handles a single string dc:creator (not a list)', () {
      final metadata = CiniiClient.normalize({
        'title': 'T',
        'dc:creator': '山田 次郎',
      }, fallbackId: 'x');
      expect(metadata.authors, hasLength(1));
      expect(metadata.authors.first.literal, '山田 次郎');
    });
  });

  group('CiniiClient.search (MockClient)', () {
    test('fetches and normalizes the first item', () async {
      final client = CiniiClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'cir.nii.ac.jp');
          expect(request.url.path, '/opensearch/articles');
          expect(request.url.queryParameters['format'], 'json');
          return http.Response.bytes(
              utf8.encode(jsonEncode(_ciniiFixture)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      final result = await client.search('音風景');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.cinii);
      expect(result.metadata.title, contains('音風景'));
    });

    test('returns null when items array is empty', () async {
      final client = CiniiClient(
        httpClient: MockClient((request) async =>
            http.Response(jsonEncode({'items': []}), 200)),
      );
      final result = await client.search('nothing');
      expect(result, isNull);
    });

    test('throws CiniiException on server error', () async {
      final client = CiniiClient(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      expect(() => client.search('x'), throwsA(isA<CiniiException>()));
    });

    test('includes appid query parameter when configured', () async {
      final client = CiniiClient(
        appId: 'my-app-id',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['appid'], 'my-app-id');
          return http.Response(jsonEncode({'items': []}), 200);
        }),
      );
      await client.search('x');
    });
  });
}
