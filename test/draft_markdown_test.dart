import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atelier/data/draft_markdown.dart';

/// Round-trip the source through decode -> encode.
String roundTrip(String md) => DraftMarkdown.encode(DraftMarkdown.decode(md));

void main() {
  group('DraftMarkdown round trip (lossless / idempotent normal form)', () {
    /// Assert the pipeline converges: first pass produces a normal form, and
    /// applying it again is a no-op (idempotent).
    void expectStable(String input, {String? normalForm}) {
      final once = roundTrip(input);
      final twice = roundTrip(once);
      expect(twice, once,
          reason: 'round trip must be idempotent for:\n$input');
      if (normalForm != null) {
        expect(once, normalForm);
      }
    }

    test('headings h1-h3', () {
      expectStable('# Title\n', normalForm: '# Title\n');
      expectStable('## Section\n', normalForm: '## Section\n');
      expectStable('### Sub\n', normalForm: '### Sub\n');
    });

    test('paragraph with plain text', () {
      expectStable('Hello world\n', normalForm: 'Hello world\n');
    });

    test('bold and italic', () {
      expectStable('This is **bold** text\n',
          normalForm: 'This is **bold** text\n');
      expectStable('This is *italic* text\n',
          normalForm: 'This is *italic* text\n');
      // Underscore italic normalizes to asterisk.
      expectStable('This is _italic_ text\n',
          normalForm: 'This is *italic* text\n');
      expectStable('Both ***strong***\n', normalForm: 'Both ***strong***\n');
    });

    test('strikethrough', () {
      expectStable('~~gone~~\n', normalForm: '~~gone~~\n');
    });

    test('inline code', () {
      expectStable('use `flutter test` now\n',
          normalForm: 'use `flutter test` now\n');
    });

    test('links', () {
      expectStable('see [Flutter](https://flutter.dev)\n',
          normalForm: 'see [Flutter](https://flutter.dev)\n');
    });

    test('bulleted list', () {
      expectStable('- one\n- two\n- three\n',
          normalForm: '- one\n- two\n- three\n');
    });

    test('bulleted list markers normalize to dash', () {
      expectStable('* one\n+ two\n', normalForm: '- one\n- two\n');
    });

    test('numbered list re-numbers sequentially', () {
      expectStable('1. first\n2. second\n3. third\n',
          normalForm: '1. first\n2. second\n3. third\n');
      // Out-of-order input normalizes.
      expectStable('3. a\n7. b\n', normalForm: '1. a\n2. b\n');
    });

    test('nested bulleted list', () {
      const input = '- parent\n  - child\n  - child2\n- parent2\n';
      expectStable(input, normalForm: input);
    });

    test('blockquote', () {
      expectStable('> quoted line\n', normalForm: '> quoted line\n');
    });

    test('fenced code block preserves content', () {
      const input = '```dart\nvoid main() {}\n```\n';
      expectStable(input, normalForm: input);
    });

    test('fenced code block without language', () {
      const input = '```\nplain code\n```\n';
      expectStable(input, normalForm: input);
    });

    test('blank lines preserved as spacing', () {
      const input = 'para one\n\npara two\n';
      expectStable(input, normalForm: input);
    });

    test('japanese text', () {
      expectStable('# 音風景の研究\n\n都市環境における**知覚**の評価。\n',
          normalForm: '# 音風景の研究\n\n都市環境における**知覚**の評価。\n');
    });

    test('mixed japanese/english with formatting', () {
      const input =
          '田中 (2024) は *sound* を論じた。`code` も含む。\n';
      expectStable(input, normalForm: input);
    });

    test('pandoc citation [@key] preserved', () {
      expectStable('先行研究 [@tanaka2024] によれば…\n',
          normalForm: '先行研究 [@tanaka2024] によれば…\n');
    });

    test('multiple citations in a paragraph', () {
      expectStable('複数 [@smith2023] と [@tanaka2024] を引用。\n',
          normalForm: '複数 [@smith2023] と [@tanaka2024] を引用。\n');
    });

    test('citation with hyphen and colon keys', () {
      expectStable('[@doe-2020] [@ns:key1]\n',
          normalForm: '[@doe-2020] [@ns:key1]\n');
    });

    test('full document corpus', () {
      const input = '# 論文タイトル\n'
          '\n'
          '## はじめに\n'
          '\n'
          'これは *強調* と **太字** を含む段落 [@tanaka2024]。\n'
          '\n'
          '- 箇条書き1\n'
          '- 箇条書き2\n'
          '  - ネスト\n'
          '\n'
          '1. 番号1\n'
          '2. 番号2\n'
          '\n'
          '> 引用ブロック\n'
          '\n'
          '```dart\n'
          'final x = 1;\n'
          '```\n'
          '\n'
          '参考: [link](https://example.com)。\n';
      expectStable(input, normalForm: input);
    });
  });

  group('DraftMarkdown citation attribute mapping', () {
    test('decode marks citation runs with the citation attribute', () {
      final doc = DraftMarkdown.decode('text [@key1] more\n');
      final node = doc.root.children.first;
      final citeRuns = node.delta!
          .whereType<TextInsert>()
          .where((op) => op.attributes?[DraftMarkdown.citationKey] != null)
          .toList();
      expect(citeRuns.length, 1);
      expect(citeRuns.first.attributes![DraftMarkdown.citationKey], 'key1');
      // Display text defaults to the key itself.
      expect(citeRuns.first.text, 'key1');
    });

    test('encode turns a citation run back into [@key]', () {
      final delta = Delta()
        ..insert('see ')
        ..insert('key1', attributes: {DraftMarkdown.citationKey: 'key1'});
      final doc = Document(
        root: Node(
          type: 'page',
          children: [paragraphNode(delta: delta)],
        ),
      );
      final out = DraftMarkdown.encode(doc);
      expect(out, 'see [@key1]\n');
    });

    test('encode uses the attribute, not the display label', () {
      // The UI may replace the visible text with an author+year chip label;
      // the serialized form must still come from the attribute.
      final delta = Delta()
        ..insert('cf. ')
        ..insert('田中 (2024)',
            attributes: {DraftMarkdown.citationKey: 'tanaka2024'});
      final doc = Document(
        root: Node(
          type: 'page',
          children: [paragraphNode(delta: delta)],
        ),
      );
      expect(DraftMarkdown.encode(doc), 'cf. [@tanaka2024]\n');
    });
  });

  group('DraftMarkdown structure (appflowy 6.x block model)', () {
    test('empty markdown yields a single empty paragraph', () {
      final doc = DraftMarkdown.decode('');
      expect(doc.root.children.length, 1);
      final node = doc.root.children.first;
      expect(node.type, ParagraphBlockKeys.type);
      expect(node.delta!.toPlainText(), '');
    });

    test('heading level survives encode', () {
      final doc = DraftMarkdown.decode('### Deep\n');
      final node = doc.root.children.first;
      expect(node.type, HeadingBlockKeys.type);
      expect(node.attributes[HeadingBlockKeys.level], 3);
    });

    test('code block stored as code node with raw delta text', () {
      final doc = DraftMarkdown.decode('```\nx\n```\n');
      final node = doc.root.children.first;
      expect(node.type, DraftMarkdown.codeBlockType);
      expect(node.delta!.toPlainText(), 'x');
    });

    test('nested list children become node children', () {
      final doc = DraftMarkdown.decode('- parent\n  - child\n');
      final parent = doc.root.children.first;
      expect(parent.type, BulletedListBlockKeys.type);
      expect(parent.children.length, 1);
      expect(parent.children.first.type, BulletedListBlockKeys.type);
      expect(parent.children.first.delta!.toPlainText(), 'child');
    });
  });
}
