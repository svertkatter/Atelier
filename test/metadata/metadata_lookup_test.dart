import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atelier/data/metadata/metadata_lookup.dart';
import 'package:atelier/data/metadata/metadata_source.dart';

void main() {
  group('MetadataLookup.lookup', () {
    test('DOI input with a rich CrossRef response uses CrossRef, never calls OpenAlex', () async {
      var openAlexCalled = false;
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.crossref.org') {
            return http.Response(
              jsonEncode({
                'message': {
                  'title': ['Rich Title'],
                  'author': [
                    {'family': 'Tanaka', 'given': 'Taro'}
                  ],
                  'issued': {
                    'date-parts': [
                      [2024]
                    ]
                  },
                  'DOI': '10.1234/rich',
                }
              }),
              200,
            );
          }
          openAlexCalled = true;
          return http.Response('', 404);
        }),
      );

      final result = await lookup.lookup('10.1234/rich');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.crossref);
      expect(openAlexCalled, isFalse);
    });

    test('DOI input where CrossRef 404s falls back to OpenAlex', () async {
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.crossref.org') {
            return http.Response('', 404);
          }
          return http.Response(
            jsonEncode({
              'title': 'OpenAlex Title',
              'doi': 'https://doi.org/10.1234/missing',
              'publication_year': 2022,
            }),
            200,
          );
        }),
      );

      final result = await lookup.lookup('10.1234/missing');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.openalex);
      expect(result.metadata.title, 'OpenAlex Title');
    });

    test('DOI input where CrossRef returns thin metadata still falls back to OpenAlex', () async {
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          if (request.url.host == 'api.crossref.org') {
            // Thin: no title, no authors.
            return http.Response(
                jsonEncode({
                  'message': {'DOI': '10.1234/thin'}
                }),
                200);
          }
          return http.Response(
            jsonEncode({
              'title': 'Filled In By OpenAlex',
              'doi': 'https://doi.org/10.1234/thin',
              'authorships': [
                {
                  'author': {'display_name': 'Someone'}
                }
              ],
            }),
            200,
          );
        }),
      );

      final result = await lookup.lookup('10.1234/thin');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.openalex);
      expect(result.metadata.title, 'Filled In By OpenAlex');
    });

    test('CiNii URL input routes to CiNii Research', () async {
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'cir.nii.ac.jp');
          return http.Response(
              jsonEncode({
                'items': [
                  {
                    '@id': 'https://cir.nii.ac.jp/crid/123',
                    'title': 'CiNii Paper',
                  }
                ]
              }),
              200);
        }),
      );

      final result =
          await lookup.lookup('https://cir.nii.ac.jp/crid/123');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.cinii);
    });

    test(
        'REGRESSION: a CiNii CRID URL hits the direct /crid/{id}.json lookup '
        '(not opensearch), and never falls back when the direct lookup '
        'succeeds', () async {
      var opensearchCalled = false;
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'cir.nii.ac.jp');
          if (request.url.path.contains('opensearch')) {
            opensearchCalled = true;
            // The real-world bug: opensearch 0-matches a bare CRID number.
            return http.Response(jsonEncode({'items': []}), 200);
          }
          // Direct CRID lookup endpoint.
          expect(request.url.toString(),
              'https://cir.nii.ac.jp/crid/1050868284190107520.json');
          // Japanese text needs explicit UTF-8 bytes + charset header — a
          // plain http.Response(String, ...) defaults to latin1 and throws
          // when encoding non-Latin1 characters (would otherwise be silently
          // swallowed by MetadataLookup's CRID->opensearch fallback catch).
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              '@id': 'https://cir.nii.ac.jp/crid/1050868284190107520.json',
              'dc:title': [
                {'@language': 'ja', '@value': '実在のCRIDレコード'}
              ],
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await lookup
          .lookup('https://cir.nii.ac.jp/crid/1050868284190107520');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.cinii);
      expect(result.metadata.title, '実在のCRIDレコード');
      expect(result.metadata.id, '1050868284190107520');
      expect(opensearchCalled, isFalse);
    });

    test(
        'a CiNii CRID URL falls back to opensearch when the direct lookup '
        '404s', () async {
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          if (!request.url.path.contains('opensearch')) {
            return http.Response('', 404);
          }
          return http.Response(
            jsonEncode({
              'items': [
                {
                  '@id': 'https://cir.nii.ac.jp/crid/999',
                  'title': 'Found via opensearch fallback',
                }
              ]
            }),
            200,
          );
        }),
      );

      final result =
          await lookup.lookup('https://cir.nii.ac.jp/crid/999');
      expect(result, isNotNull);
      expect(result!.metadata.title, 'Found via opensearch fallback');
    });

    test('J-STAGE URL input routes to J-STAGE', () async {
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.jstage.jst.go.jp');
          return http.Response(
            '<feed><entry><article_title><ja>JStage Paper</ja></article_title></entry></feed>',
            200,
          );
        }),
      );

      final result = await lookup
          .lookup('https://www.jstage.jst.go.jp/article/xxx/1/1/1_1/_article');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.jstage);
    });

    test('unrecognized input returns null (caller falls back to manual form)', () async {
      final lookup = MetadataLookup(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      final result = await lookup.lookup('just some notes, no identifier');
      expect(result, isNull);
    });
  });
}
