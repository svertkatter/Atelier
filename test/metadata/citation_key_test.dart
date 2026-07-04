import 'package:flutter_test/flutter_test.dart';

import 'package:atelier/data/metadata/citation_key.dart';
import 'package:atelier/models/csl_metadata.dart';

void main() {
  CslMetadata paper({String? family, String? literal, int? year}) =>
      CslMetadata(
        id: 'ignored',
        authors: [
          if (family != null || literal != null)
            CslName(family: family, literal: literal)
        ],
        issuedDateParts: year != null
            ? [
                [year]
              ]
            : null,
      );

  group('CitationKey.generate', () {
    test('family + year, lowercased', () {
      final key = CitationKey.generate(paper(family: 'Tanaka', year: 2024));
      expect(key, 'tanaka2024');
    });

    test('ASCII-izes accented Latin family names', () {
      final key = CitationKey.generate(paper(family: 'Müller', year: 2020));
      expect(key, 'muller2020');
    });

    test('non-Latin (Japanese) family name falls back to "author"', () {
      // Family is unavailable in structured form (family:null) but literal
      // Japanese name is present; ASCII-ization strips all non-ASCII chars.
      final key =
          CitationKey.generate(paper(literal: '田中 太郎', year: 2024));
      expect(key, 'author2024');
    });

    test('missing year uses "nd"', () {
      final key = CitationKey.generate(paper(family: 'Smith'));
      expect(key, 'smithnd');
    });

    test('missing author uses "unknown"', () {
      final key = CitationKey.generate(paper(year: 2024));
      expect(key, 'unknown2024');
    });

    test('collision appends a, b, c... suffix', () {
      final base = paper(family: 'Tanaka', year: 2024);
      final key1 = CitationKey.generate(base, existingKeys: {'tanaka2024'});
      expect(key1, 'tanaka2024a');

      final key2 = CitationKey.generate(base,
          existingKeys: {'tanaka2024', 'tanaka2024a'});
      expect(key2, 'tanaka2024b');
    });

    test('collision check is case-insensitive', () {
      final key = CitationKey.generate(paper(family: 'Tanaka', year: 2024),
          existingKeys: {'Tanaka2024'});
      expect(key, 'tanaka2024a');
    });

    test('no collision when key is unique', () {
      final key = CitationKey.generate(paper(family: 'Yamada', year: 2019),
          existingKeys: {'tanaka2024'});
      expect(key, 'yamada2019');
    });
  });
}
