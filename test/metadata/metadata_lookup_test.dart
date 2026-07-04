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
