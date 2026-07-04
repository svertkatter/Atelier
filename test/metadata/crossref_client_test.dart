import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:atelier/data/metadata/crossref_client.dart';
import 'package:atelier/data/metadata/metadata_source.dart';

/// Fixture shaped like a real CrossRef `works/{doi}` response
/// (verified against https://api.crossref.org/works/10.1038/nphys1170).
const _crossrefFixture = {
  'status': 'ok',
  'message-type': 'work',
  'message': {
    'title': ['Measured measurement'],
    'author': [
      {'family': 'Aspelmeyer', 'given': 'Markus'},
    ],
    'issued': {
      'date-parts': [
        [2009, 1]
      ]
    },
    'container-title': ['Nature Physics'],
    'volume': '5',
    'issue': '1',
    'page': '11-12',
    'DOI': '10.1038/nphys1170',
    'URL': 'https://doi.org/10.1038/nphys1170',
    'publisher': 'Springer Science and Business Media LLC',
    'type': 'journal-article',
  },
};

void main() {
  group('CrossrefClient.normalize', () {
    test('maps CrossRef message JSON to CslMetadata', () {
      final metadata = CrossrefClient.normalize(
        (_crossrefFixture['message'] as Map).cast(),
        citationId: '10.1038/nphys1170',
      );

      expect(metadata.title, 'Measured measurement');
      expect(metadata.authors, hasLength(1));
      expect(metadata.authors.first.family, 'Aspelmeyer');
      expect(metadata.authors.first.given, 'Markus');
      expect(metadata.year, 2009);
      expect(metadata.containerTitle, 'Nature Physics');
      expect(metadata.volume, '5');
      expect(metadata.issue, '1');
      expect(metadata.page, '11-12');
      expect(metadata.doi, '10.1038/nphys1170');
      expect(metadata.publisher, 'Springer Science and Business Media LLC');
      expect(metadata.type, 'journal-article');
    });

    test('takes the first title/container-title when arrays have >1 entry',
        () {
      final metadata = CrossrefClient.normalize({
        'title': ['Primary Title', 'Alt Title'],
        'container-title': ['Journal A', 'Journal A Abbrev'],
        'DOI': '10.1/x',
      }, citationId: '10.1/x');

      expect(metadata.title, 'Primary Title');
      expect(metadata.containerTitle, 'Journal A');
    });

    test('strips JATS tags from abstract', () {
      final metadata = CrossrefClient.normalize({
        'DOI': '10.1/x',
        'abstract': '<jats:p>Some <jats:italic>abstract</jats:italic>.</jats:p>',
      }, citationId: '10.1/x');

      expect(metadata.abstractText, 'Some abstract.');
    });

    test('handles missing author/date-parts gracefully', () {
      final metadata =
          CrossrefClient.normalize({'DOI': '10.1/x'}, citationId: '10.1/x');
      expect(metadata.authors, isEmpty);
      expect(metadata.year, isNull);
    });
  });

  group('CrossrefClient.fetchByDoi (MockClient)', () {
    test('fetches and normalizes, sends polite User-Agent with mailto', () async {
      String? sentUserAgent;
      final client = CrossrefClient(
        contactEmail: 'alice241102@gmail.com',
        httpClient: MockClient((request) async {
          sentUserAgent = request.headers['User-Agent'];
          expect(request.url.path, '/works/10.1038/nphys1170');
          return http.Response(
              jsonEncode(_crossrefFixture), 200,
              headers: {'content-type': 'application/json'});
        }),
      );

      final result = await client.fetchByDoi('10.1038/nphys1170');
      expect(result, isNotNull);
      expect(result!.source, MetadataSource.crossref);
      expect(result.metadata.title, 'Measured measurement');
      expect(sentUserAgent, contains('mailto:alice241102@gmail.com'));
    });

    test('strips doi.org URL prefix before querying', () async {
      Uri? requestedUri;
      final client = CrossrefClient(
        httpClient: MockClient((request) async {
          requestedUri = request.url;
          return http.Response(jsonEncode(_crossrefFixture), 200);
        }),
      );

      await client.fetchByDoi('https://doi.org/10.1038/nphys1170');
      expect(requestedUri!.path, '/works/10.1038/nphys1170');
    });

    test('returns null on 404', () async {
      final client = CrossrefClient(
        httpClient: MockClient((request) async => http.Response('', 404)),
      );
      final result = await client.fetchByDoi('10.9999/missing');
      expect(result, isNull);
    });

    test('throws CrossrefException on server error', () async {
      final client = CrossrefClient(
        httpClient: MockClient((request) async => http.Response('', 500)),
      );
      expect(() => client.fetchByDoi('10.1/x'),
          throwsA(isA<CrossrefException>()));
    });
  });
}
