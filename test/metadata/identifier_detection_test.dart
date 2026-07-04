import 'package:flutter_test/flutter_test.dart';

import 'package:atelier/data/metadata/identifier_detection.dart';

void main() {
  group('IdentifierDetection.detect', () {
    test('detects a bare DOI', () {
      final result = IdentifierDetection.detect('10.1038/nphys1170');
      expect(result.kind, DetectedIdentifierKind.doi);
      expect(result.value, '10.1038/nphys1170');
    });

    test('detects a DOI inside a doi.org URL', () {
      final result =
          IdentifierDetection.detect('https://doi.org/10.1038/nphys1170');
      expect(result.kind, DetectedIdentifierKind.doi);
      expect(result.value, '10.1038/nphys1170');
    });

    test('detects a CiNii Research crid URL', () {
      final result = IdentifierDetection.detect(
          'https://cir.nii.ac.jp/crid/1050282677628470784');
      expect(result.kind, DetectedIdentifierKind.cinii);
    });

    test('detects a legacy CiNii naid URL as cinii (still routed to CiNii Research)', () {
      final result =
          IdentifierDetection.detect('https://ci.nii.ac.jp/naid/110001234567');
      expect(result.kind, DetectedIdentifierKind.cinii);
    });

    test('detects a J-STAGE URL even if it also contains a DOI-like path', () {
      final result = IdentifierDetection.detect(
          'https://www.jstage.jst.go.jp/article/ipsjjip/1/1/1_1/_article');
      expect(result.kind, DetectedIdentifierKind.jstage);
    });

    test('J-STAGE host wins over a DOI also present in the URL', () {
      final result = IdentifierDetection.detect(
          'https://www.jstage.jst.go.jp/article/xxx/10.1234/example/_article');
      expect(result.kind, DetectedIdentifierKind.jstage);
    });

    test('returns none for plain text with no identifiers', () {
      final result = IdentifierDetection.detect('random note text');
      expect(result.kind, DetectedIdentifierKind.none);
    });

    test('returns none for empty input', () {
      final result = IdentifierDetection.detect('   ');
      expect(result.kind, DetectedIdentifierKind.none);
    });
  });
}
