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

/// Real response captured live from
/// `https://cir.nii.ac.jp/crid/1050868284190107520.json` (July 2026, per the
/// implementation task) for `lookupByCrid`/`normalizeCridRecord` regression
/// coverage — this is the exact JSON-LD shape the CRID direct-lookup endpoint
/// returns, distinct from the opensearch/articles shape above. Note this
/// particular record has no DOI (a conference paper indexed via IRDB), which
/// is intentionally kept as-is to exercise the "no DOI found" path too.
const _ciniiCridFixture = {
  '@context': {
    '@vocab': 'https://cir.nii.ac.jp/schema/1.0/',
  },
  '@id': 'https://cir.nii.ac.jp/crid/1050868284190107520.json',
  '@type': 'Article',
  'productIdentifier': [
    {
      'identifier': {
        '@type': 'URI',
        '@value': 'https://ipsj.ixsq.nii.ac.jp/records/2003703',
      }
    }
  ],
  'resourceType': '会議発表資料(conference paper)',
  'dc:title': [
    {
      '@language': 'ja',
      '@value': '利己の鏡：芥川龍之介『鼻』を題材としたインタラクティブアートの提案',
    }
  ],
  'dc:language': 'ja',
  'description': [
    {
      'type': 'Other',
      'notation': [
        {'@value': '近年，小説を通じて他者の感情に触れるという経験が映像や即時的な表現に置き換わる中で、文学の輪郭は不明瞭となり...'}
      ],
    }
  ],
  'creator': [
    {
      '@id': 'https://cir.nii.ac.jp/crid/1070868284190107520',
      '@type': 'Researcher',
      'foaf:name': [
        {'@value': '椎原,蓮水'}
      ],
    },
    {
      '@id': 'https://cir.nii.ac.jp/crid/1070868284190107521',
      '@type': 'Researcher',
      'foaf:name': [
        {'@value': '中島,武三志'}
      ],
    },
  ],
  'publication': {
    'prism:publicationName': [
      {'@value': 'エンタテインメントコンピューティングシンポジウム2025論文集'}
    ],
    'dc:publisher': [
      {'@value': '情報処理学会'}
    ],
    'prism:publicationDate': '2025-08-18',
    'prism:volume': '2025',
    'prism:startingPage': '343',
    'prism:endingPage': '347',
  },
  'url': [
    {'@id': 'https://ipsj.ixsq.nii.ac.jp/records/2003703'}
  ],
  'dataSourceIdentifier': [
    {'@type': 'IRDB', '@value': 'oai:irdb.nii.ac.jp:02902:0006911364'}
  ],
};

void main() {
  group('CiniiClient.normalizeCridRecord (real CRID JSON-LD shape)', () {
    test('maps title/authors/publication/pages from the live fixture', () {
      final metadata = CiniiClient.normalizeCridRecord(
          _ciniiCridFixture.cast<String, dynamic>(),
          fallbackId: 'fallback');

      expect(metadata.id, '1050868284190107520');
      expect(metadata.title, '利己の鏡：芥川龍之介『鼻』を題材としたインタラクティブアートの提案');
      expect(metadata.authors, hasLength(2));
      expect(metadata.authors[0].family, '椎原');
      expect(metadata.authors[0].given, '蓮水');
      expect(metadata.authors[1].family, '中島');
      expect(metadata.authors[1].given, '武三志');
      expect(metadata.containerTitle, 'エンタテインメントコンピューティングシンポジウム2025論文集');
      expect(metadata.publisher, '情報処理学会');
      expect(metadata.volume, '2025');
      expect(metadata.page, '343-347');
      expect(metadata.year, 2025);
      expect(metadata.type, 'paper-conference');
      expect(metadata.url, 'https://ipsj.ixsq.nii.ac.jp/records/2003703');
      expect(metadata.extra['cinii_id'], '1050868284190107520');
      // This particular record has no DOI anywhere in it.
      expect(metadata.doi, isNull);
    });

    test('falls back to fallbackId when @id has no crid/ segment', () {
      final metadata = CiniiClient.normalizeCridRecord({
        'dc:title': [
          {'@value': 'No id here'}
        ],
      }, fallbackId: 'myfallback');
      expect(metadata.id, 'myfallback');
    });

    test('splits "family,given" creator names but keeps unsplittable names literal', () {
      final metadata = CiniiClient.normalizeCridRecord({
        'creator': [
          {
            'foaf:name': [
              {'@value': 'A Single Name'}
            ]
          },
        ],
      }, fallbackId: 'x');
      expect(metadata.authors.single.literal, 'A Single Name');
      expect(metadata.authors.single.family, isNull);
    });

    test('finds a DOI embedded in productIdentifier when present', () {
      final metadata = CiniiClient.normalizeCridRecord({
        'productIdentifier': [
          {
            'identifier': {'@type': 'URI', '@value': 'https://doi.org/10.1234/example'}
          }
        ],
      }, fallbackId: 'x');
      expect(metadata.doi, '10.1234/example');
    });
  });

  group('CiniiClient.lookupByCrid (MockClient)', () {
    test('fetches the direct CRID endpoint and normalizes the JSON-LD record',
        () async {
      final client = CiniiClient(
        httpClient: MockClient((request) async {
          expect(request.url.toString(),
              'https://cir.nii.ac.jp/crid/1050868284190107520.json');
          return http.Response.bytes(
              utf8.encode(jsonEncode(_ciniiCridFixture)), 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      final result = await client.lookupByCrid('1050868284190107520');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.cinii);
      expect(result.metadata.id, '1050868284190107520');
      expect(result.metadata.title, contains('利己の鏡'));
    });

    test('returns null on 404', () async {
      final client = CiniiClient(
        httpClient: MockClient((request) async => http.Response('', 404)),
      );
      final result = await client.lookupByCrid('0000000000000000000');
      expect(result, isNull);
    });

    test('throws CiniiException on server error', () async {
      final client = CiniiClient(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      expect(() => client.lookupByCrid('123'), throwsA(isA<CiniiException>()));
    });
  });

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
