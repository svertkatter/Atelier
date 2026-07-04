import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'package:atelier/data/meta_md.dart';
import 'package:atelier/models/csl_metadata.dart';
import 'package:atelier/models/paper.dart';

void main() {
  group('MetaMd parse', () {
    test('parses frontmatter and body sections (Japanese)', () {
      const source = '''
---
csl_json:
  id: "tanaka2024"
  type: "article-journal"
  title: "都市環境における音風景の知覚と感情的評価に関する研究"
  author:
    - family: "田中"
      given: "太郎"
    - family: "鈴木"
      given: "花子"
  issued:
    date-parts: [[2024]]
  container-title: "情報処理学会論文誌"
  volume: "65"
  issue: "2"
tags: [サウンドスケープ, 知覚]
source: cinii
doi: ""
cinii_id: "AA12345678"
---

## AI要約

これはローカルLLMが生成した要約テキストです。

## 自分のメモ

ここに読書メモを書く。
''';

      final paper = MetaMd.parse(source, folderName: 'tanaka2024');

      expect(paper.metadata.id, 'tanaka2024');
      expect(paper.metadata.type, 'article-journal');
      expect(paper.metadata.title,
          '都市環境における音風景の知覚と感情的評価に関する研究');
      expect(paper.metadata.authors.length, 2);
      expect(paper.metadata.authors[0].family, '田中');
      expect(paper.metadata.authors[0].given, '太郎');
      expect(paper.metadata.year, 2024);
      expect(paper.metadata.containerTitle, '情報処理学会論文誌');
      expect(paper.metadata.volume, '65');
      expect(paper.tags, ['サウンドスケープ', '知覚']);
      expect(paper.source, 'cinii');
      expect(paper.ciniiId, 'AA12345678');
      expect(paper.doi, isNull); // empty string -> null
      expect(paper.aiSummary, 'これはローカルLLMが生成した要約テキストです。');
      expect(paper.userNote, 'ここに読書メモを書く。');
    });
  });

  group('MetaMd round trip', () {
    Paper roundTrip(Paper original) {
      final text = MetaMd.serialize(original);
      return MetaMd.parse(text, folderName: original.effectiveFolderName);
    }

    test('lossless for Japanese metadata', () {
      final original = Paper(
        metadata: CslMetadata(
          id: 'tanaka2024',
          type: 'article-journal',
          title: '都市環境における音風景の知覚',
          authors: const [
            CslName(family: '田中', given: '太郎'),
            CslName(family: '鈴木', given: '花子'),
          ],
          issuedDateParts: const [
            [2024, 6, 13]
          ],
          containerTitle: '情報処理学会論文誌',
          volume: '65',
          issue: '2',
          page: '123-134',
          doi: '10.1234/abc',
        ),
        tags: const ['サウンドスケープ', '知覚'],
        source: 'cinii',
        ciniiId: 'AA12345678',
        aiSummary: '要約テキスト。改行を含む。\n二行目。',
        userNote: '自分のメモ。',
      );

      final result = roundTrip(original);

      expect(result.metadata.id, original.metadata.id);
      expect(result.metadata.title, original.metadata.title);
      expect(result.metadata.type, original.metadata.type);
      expect(result.metadata.authors.length, 2);
      expect(result.metadata.authors[1].family, '鈴木');
      expect(result.metadata.year, 2024);
      expect(result.metadata.issuedDateParts, [
        [2024, 6, 13]
      ]);
      expect(result.metadata.containerTitle, '情報処理学会論文誌');
      expect(result.metadata.volume, '65');
      expect(result.metadata.issue, '2');
      expect(result.metadata.page, '123-134');
      expect(result.metadata.doi, '10.1234/abc');
      expect(result.tags, original.tags);
      expect(result.source, 'cinii');
      expect(result.ciniiId, 'AA12345678');
      expect(result.aiSummary, original.aiSummary);
      expect(result.userNote, original.userNote);
    });

    test('idempotent: serialize(parse(serialize)) == serialize', () {
      final original = Paper(
        metadata: const CslMetadata(
          id: 'smith2023',
          type: 'article-journal',
          title: 'A Study of NLP',
          authors: [CslName(family: 'Smith', given: 'John')],
          issuedDateParts: [
            [2023]
          ],
        ),
        tags: const ['nlp'],
        source: 'crossref',
      );
      final once = MetaMd.serialize(original);
      final twice =
          MetaMd.serialize(MetaMd.parse(once, folderName: 'smith2023'));
      expect(twice, once);
    });

    test('YAML 1.1 traps: "no"-like tag and numeric-looking string survive',
        () {
      // A tag literally "no" must not become boolean false; a volume "007"
      // must not become int 7.
      final original = Paper(
        metadata: const CslMetadata(
          id: 'x',
          title: 'Edge cases',
          volume: '007',
          issue: 'on',
        ),
        tags: const ['no', 'yes', '2024-01-01'],
        source: 'manual',
      );
      final result = roundTrip(original);
      expect(result.tags, ['no', 'yes', '2024-01-01']);
      expect(result.metadata.volume, '007');
      expect(result.metadata.issue, 'on');

      // Also confirm the raw YAML re-parses those tags as strings, not bools.
      final text = MetaMd.serialize(original);
      final fmText = text
          .split('---')[1]; // between first and second '---'
      final parsed = loadYaml(fmText) as YamlMap;
      final tags = (parsed['tags'] as YamlList).toList();
      expect(tags.every((t) => t is String), isTrue);
    });

    test('preserves unknown CSL fields via extra', () {
      final original = Paper(
        metadata: const CslMetadata(
          id: 'y',
          title: 'Has extra',
          extra: {'ISSN': '1234-5678', 'language': 'ja'},
        ),
      );
      final result = roundTrip(original);
      expect(result.metadata.extra['ISSN'], '1234-5678');
      expect(result.metadata.extra['language'], 'ja');
    });
  });
}
