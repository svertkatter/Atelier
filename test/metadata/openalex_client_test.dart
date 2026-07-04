import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atelier/data/metadata/openalex_client.dart';
import 'package:atelier/data/metadata/metadata_source.dart';

/// Fixture shaped like a real OpenAlex work object
/// (verified against https://api.openalex.org/works/doi:10.1038/nphys1170).
const _openAlexFixture = {
  'id': 'https://openalex.org/W4289253527',
  'doi': 'https://doi.org/10.1038/nphys1170',
  'title': 'Measured measurement',
  'display_name': 'Measured measurement',
  'publication_year': 2009,
  'publication_date': '2009-01-01',
  'type': 'article',
  'authorships': [
    {
      'author_position': 'first',
      'author': {
        'display_name': 'Markus Aspelmeyer',
      },
      'raw_author_name': 'Markus Aspelmeyer',
    },
  ],
  'primary_location': {
    'source': {'display_name': 'Nature Physics'},
  },
  'biblio': {
    'volume': '5',
    'issue': '1',
    'first_page': '11',
    'last_page': '12',
  },
  'abstract_inverted_index': {
    'Quantum': [0],
    'measurement': [1, 3],
    'is': [2],
    'hard.': [4],
  },
};

void main() {
  group('OpenAlexClient.normalize', () {
    test('maps OpenAlex work JSON to CslMetadata', () {
      final metadata =
          OpenAlexClient.normalize(_openAlexFixture, citationId: '10.1038/nphys1170');

      expect(metadata.title, 'Measured measurement');
      expect(metadata.authors, hasLength(1));
      expect(metadata.authors.first.literal, 'Markus Aspelmeyer');
      expect(metadata.year, 2009);
      expect(metadata.issuedDateParts, [
        [2009, 1, 1]
      ]);
      expect(metadata.containerTitle, 'Nature Physics');
      expect(metadata.volume, '5');
      expect(metadata.issue, '1');
      expect(metadata.page, '11-12');
      expect(metadata.doi, '10.1038/nphys1170');
      expect(metadata.type, 'article-journal');
    });

    test('reconstructs abstract from inverted index in word order', () {
      final metadata =
          OpenAlexClient.normalize(_openAlexFixture, citationId: 'x');
      expect(metadata.abstractText, 'Quantum measurement is measurement hard.');
    });

    test('falls back to display_name when title missing', () {
      final metadata = OpenAlexClient.normalize({
        'display_name': 'Fallback Title',
        'doi': 'https://doi.org/10.1/x',
      }, citationId: '10.1/x');
      expect(metadata.title, 'Fallback Title');
    });

    test('single-page biblio (no last_page distinct) yields single page', () {
      final metadata = OpenAlexClient.normalize({
        'biblio': {'first_page': '42', 'last_page': '42'},
      }, citationId: 'x');
      expect(metadata.page, '42');
    });

    test('handles missing authorships/biblio gracefully', () {
      final metadata = OpenAlexClient.normalize({'doi': null}, citationId: 'x');
      expect(metadata.authors, isEmpty);
      expect(metadata.page, isNull);
    });
  });

  group('OpenAlexClient.fetchByDoi (MockClient)', () {
    test('fetches and normalizes without requiring an API key', () async {
      final client = OpenAlexClient(
        httpClient: MockClient((request) async {
          expect(request.url.toString(),
              contains('/works/doi:10.1038/nphys1170'));
          expect(request.headers['Authorization'], isNull);
          return http.Response(jsonEncode(_openAlexFixture), 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      final result = await client.fetchByDoi('10.1038/nphys1170');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.openalex);
      expect(result.metadata.containerTitle, 'Nature Physics');
    });

    test('returns null on 404', () async {
      final client = OpenAlexClient(
        httpClient: MockClient((request) async => http.Response('', 404)),
      );
      final result = await client.fetchByDoi('10.9999/missing');
      expect(result, isNull);
    });

    test('throws OpenAlexException on server error', () async {
      final client = OpenAlexClient(
        httpClient: MockClient((request) async => http.Response('', 503)),
      );
      expect(() => client.fetchByDoi('10.1/x'),
          throwsA(isA<OpenAlexException>()));
    });
  });
}
