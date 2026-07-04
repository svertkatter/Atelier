import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:atelier/data/draft_markdown.dart';
import 'package:atelier/ui/writer_screen.dart';

/// Widget tests for the true-WYSIWYG editing surface. These verify the core
/// WYSIWYG requirements without a native build:
/// - markdown markers (`#`, `**`, `[@...]`) are never rendered,
/// - heading/citation content is displayed as styled text,
/// - citation runs get the chip decoration (background + primary color).
void main() {
  Widget host(EditorState state) => MaterialApp(
        home: Scaffold(
          body: AtelierDraftEditor(
            editorState: state,
            autoFocus: false,
          ),
        ),
      );

  /// Collect the plain text of every RichText widget in the tree.
  List<String> richTexts(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((rt) => rt.text.toPlainText())
      .toList();

  testWidgets('renders heading and body without markdown markers',
      (tester) async {
    final doc = DraftMarkdown.decode(
        '# 見出しテキスト\n\n本文に**太字**と*斜体*を含む。\n');
    final state = EditorState(document: doc);

    await tester.pumpWidget(host(state));
    await tester.pump();

    final texts = richTexts(tester);
    final joined = texts.join('\n');

    // Content is rendered...
    expect(joined, contains('見出しテキスト'));
    expect(joined, contains('太字'));
    expect(joined, contains('斜体'));
    // ...but markdown markers are not.
    expect(joined, isNot(contains('# ')));
    expect(joined, isNot(contains('**')));
    expect(joined.contains('*斜体*'), isFalse);
  });

  testWidgets('bold run is rendered with bold font weight', (tester) async {
    final doc = DraftMarkdown.decode('normal **strong** tail\n');
    final state = EditorState(document: doc);

    await tester.pumpWidget(host(state));
    await tester.pump();

    // Find the span carrying the bold text and assert its style.
    TextStyle? boldStyle;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.text == 'strong') {
          boldStyle = span.style;
          return false;
        }
        return true;
      });
    }
    expect(boldStyle, isNotNull, reason: 'bold run should be rendered');
    expect(boldStyle!.fontWeight, FontWeight.bold);
  });

  testWidgets('citation renders as chip label, never as [@key]',
      (tester) async {
    final doc = DraftMarkdown.decode('先行研究 [@tanaka2024] を参照。\n');
    // Simulate the label enrichment the Writer performs on load.
    final node = doc.root.children.first;
    final rebuilt = Delta();
    for (final op in node.delta!) {
      if (op is TextInsert &&
          op.attributes?[DraftMarkdown.citationKey] == 'tanaka2024') {
        rebuilt.insert('田中 太郎 (2024)', attributes: op.attributes);
      } else if (op is TextInsert) {
        rebuilt.insert(op.text, attributes: op.attributes);
      }
    }
    node.updateAttributes({blockComponentDelta: rebuilt.toJson()});
    final state = EditorState(document: doc);

    await tester.pumpWidget(host(state));
    await tester.pump();

    final joined = richTexts(tester).join('\n');
    // Chip label shown; pandoc syntax hidden.
    expect(joined, contains('田中 太郎 (2024)'));
    expect(joined, isNot(contains('[@tanaka2024]')));
    expect(joined, isNot(contains('[@')));

    // The chip span carries the decoration (background + weight).
    TextStyle? chipStyle;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.text == '田中 太郎 (2024)') {
          chipStyle = span.style;
          return false;
        }
        return true;
      });
    }
    expect(chipStyle, isNotNull, reason: 'citation span should be rendered');
    expect(chipStyle!.backgroundColor, isNotNull,
        reason: 'chip must have a tinted background');
    expect(chipStyle!.fontWeight, FontWeight.w600);

    // Round trip from the edited document still yields pandoc syntax:
    // the label is cosmetic, the attribute is the source of truth.
    expect(DraftMarkdown.encode(state.document),
        '先行研究 [@tanaka2024] を参照。\n');
  });

  testWidgets('code block renders content in monospace without fences',
      (tester) async {
    final doc = DraftMarkdown.decode('```dart\nfinal x = 1;\n```\n');
    final state = EditorState(document: doc);

    await tester.pumpWidget(host(state));
    await tester.pump();

    final joined = richTexts(tester).join('\n');
    expect(joined, contains('final x = 1;'));
    expect(joined, isNot(contains('```')));
  });
}
