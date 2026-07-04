import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:atelier/data/refs_json.dart';
import 'package:atelier/models/csl_metadata.dart';

void main() {
  group('RefsJson', () {
    final tanaka = const CslMetadata(
      id: 'tanaka2024',
      type: 'article-journal',
      title: '音風景の研究',
      authors: [CslName(family: '田中', given: '太郎')],
      issuedDateParts: [
        [2024]
      ],
      containerTitle: '情報処理学会論文誌',
    );
    final smith = const CslMetadata(
      id: 'smith2023',
      type: 'article-journal',
      title: 'NLP Study',
      authors: [CslName(family: 'Smith', given: 'John')],
      issuedDateParts: [
        [2023]
      ],
    );

    test('build produces CSL-JSON array preserving keys', () {
      final arr = RefsJson.build([tanaka, smith]);
      expect(arr.length, 2);
      expect(arr[0]['id'], 'tanaka2024');
      expect(arr[0]['title'], '音風景の研究');
      expect(arr[0]['container-title'], '情報処理学会論文誌');
      expect(arr[0]['author'], [
        {'family': '田中', 'given': '太郎'}
      ]);
      expect(arr[1]['id'], 'smith2023');
    });

    test('forRefs selects in refs order and skips missing', () {
      final available = {
        'tanaka2024': tanaka,
        'smith2023': smith,
      };
      final arr = RefsJson.forRefs(
        ['smith2023', 'missing', 'tanaka2024'],
        available,
      );
      expect(arr.map((m) => m['id']), ['smith2023', 'tanaka2024']);
    });

    test('serialize yields valid JSON round-trippable to same structure', () {
      final arr = RefsJson.build([tanaka]);
      final text = RefsJson.serialize(arr);
      final decoded = jsonDecode(text) as List;
      expect(decoded.length, 1);
      expect((decoded.first as Map)['id'], 'tanaka2024');
    });
  });
}
