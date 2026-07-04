import 'package:appflowy_editor/appflowy_editor.dart';

/// Lossless (idempotent) conversion between standard Markdown (`draft.md`) and
/// the appflowy_editor 6.x [Document] block model used by the WYSIWYG writer.
///
/// Why a custom converter (not appflowy's built-in codec)?
/// The built-in `markdownToDocument` / `documentToMarkdown` does not guarantee
/// the round-trip stability we need for `draft.md` as the *source of truth*
/// (normal-form control, `[@key]` citations, blank-line preservation). We
/// target the appflowy [Document]/[Node]/[Delta] shapes so the editor widget
/// renders the result natively, but own the (de)serialization completely.
///
/// Round-trip contract:
/// - `decode(md)` -> [Document], `encode(doc)` -> Markdown.
/// - The pipeline converges to a *normal form* on the first pass and is then
///   idempotent: `encode(decode(encode(decode(md)))) == encode(decode(md))`.
/// - Only standard, Obsidian-compatible Markdown is emitted (CommonMark + GFM);
///   no Atelier-specific extensions.
///
/// Normal-form choices (documented so callers know what stabilizes):
/// - Italic is emitted with `*text*` (input `_text_` is accepted, re-emitted as
///   `*`).
/// - Unordered list markers are emitted as `- ` (input `* ` / `+ ` accepted).
/// - Ordered list items are re-numbered sequentially from 1.
/// - Bold+italic is emitted as `***text***`.
/// - Trailing spaces on lines are trimmed on output.
/// - A single trailing newline is guaranteed; interior blank lines are kept as
///   empty paragraphs.
///
/// Block type mapping (appflowy 6.x):
/// - `# ..###### ` -> `heading` (attribute `level`)
/// - `- ` / `* ` / `+ ` -> `bulleted_list` (nesting via node children)
/// - `1. ` -> `numbered_list` (nesting via node children)
/// - `> ` -> `quote`
/// - fenced code -> `code` (delta = raw code text, attribute `language`);
///   matches the type used by appflowy's own markdown parsers
/// - anything else -> `paragraph` (blank line = empty paragraph)
///
/// Citations: pandoc `[@key]` becomes a delta text run carrying the
/// [citationKey] attribute. The run's *display text* is arbitrary (the UI may
/// substitute an author+year label); [encode] emits `[@key]` from the attribute
/// alone, so the round trip is lossless regardless of the label.
class DraftMarkdown {
  const DraftMarkdown._();

  /// Node type for fenced code blocks (appflowy markdown convention).
  static const String codeBlockType = 'code';
  static const String codeBlockLangKey = 'language';

  /// Inline citation attribute key. Holds the citation key string.
  static const String citationKey = 'citation';

  // =========================================================================
  // Decode: Markdown -> Document
  // =========================================================================

  static Document decode(String markdown) {
    final normalized =
        markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    // A trailing '' from a final newline is not a real blank paragraph.
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    final nodes = _parseBlocks(lines);
    if (nodes.isEmpty) {
      nodes.add(paragraphNode(delta: Delta()));
    }
    final root = Node(type: 'page', children: nodes);
    return Document(root: root);
  }

  /// Parse a flat list of lines into block nodes (recursively for list nesting).
  static List<Node> _parseBlocks(List<String> lines) {
    final nodes = <Node>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Fenced code block.
      if (_isFence(line)) {
        final lang = line.trimLeft().substring(3).trim();
        final buf = <String>[];
        i++;
        while (i < lines.length && !_isFence(lines[i])) {
          buf.add(lines[i]);
          i++;
        }
        if (i < lines.length) i++; // consume closing fence
        nodes.add(_codeBlockNode(buf.join('\n'), lang));
        continue;
      }

      // Heading (# .. ######).
      final heading = _headingMatch(line);
      if (heading != null) {
        nodes.add(
          headingNode(level: heading.$1, delta: parseInline(heading.$2)),
        );
        i++;
        continue;
      }

      // Blockquote.
      final quote = _quoteMatch(line);
      if (quote != null) {
        nodes.add(quoteNode(delta: parseInline(quote)));
        i++;
        continue;
      }

      // List item (ordered or unordered), including nested children.
      if (_listItemMatch(line) != null) {
        final result = _parseListItem(lines, i);
        nodes.add(result.$1);
        i += result.$2;
        continue;
      }

      // Blank line -> empty paragraph (preserves vertical spacing).
      if (line.trim().isEmpty) {
        nodes.add(paragraphNode(delta: Delta()));
        i++;
        continue;
      }

      // Plain paragraph.
      nodes.add(paragraphNode(delta: parseInline(line)));
      i++;
    }
    return nodes;
  }

  /// Parse a single list item at [start], including any indented continuation
  /// lines that form nested child list items. Returns the node and the number
  /// of source lines consumed.
  static (Node, int) _parseListItem(List<String> lines, int start) {
    final match = _listItemMatch(lines[start])!;
    final indent = match.indent;
    final ordered = match.ordered;

    var i = start + 1;
    final childLines = <String>[];
    while (i < lines.length) {
      final next = lines[i];
      final nextItem = _listItemMatch(next);
      if (nextItem != null && nextItem.indent > indent) {
        childLines.add(next.substring(_stripWidth(next, indent)));
        i++;
      } else {
        break;
      }
    }

    final children =
        childLines.isEmpty ? const <Node>[] : _parseBlocks(childLines);
    final delta = parseInline(match.content);
    final node = ordered
        ? numberedListNode(delta: delta, children: children)
        : bulletedListNode(delta: delta, children: children);
    return (node, i - start);
  }

  // =========================================================================
  // Encode: Document -> Markdown
  // =========================================================================

  static String encode(Document document) {
    final buffer = StringBuffer();
    _encodeNodes(document.root.children, buffer, 0);
    var out = buffer.toString();
    out = out.replaceAll(RegExp(r'\n+$'), '');
    return '$out\n';
  }

  static void _encodeNodes(List<Node> nodes, StringBuffer buffer, int depth) {
    var orderedCounter = 0;
    String? prevType;
    for (final node in nodes) {
      if (node.type == NumberedListBlockKeys.type) {
        if (prevType != NumberedListBlockKeys.type) orderedCounter = 0;
        orderedCounter++;
      }
      _encodeNode(node, buffer, depth, orderedCounter);
      prevType = node.type;
    }
  }

  static void _encodeNode(
      Node node, StringBuffer buffer, int depth, int orderedNumber) {
    final indent = '  ' * depth;

    if (node.type == codeBlockType) {
      final lang = node.attributes[codeBlockLangKey] as String? ?? '';
      final text = node.delta?.toPlainText() ?? '';
      buffer.writeln('$indent```$lang');
      if (text.isNotEmpty) {
        for (final l in text.split('\n')) {
          buffer.writeln('$indent$l');
        }
      }
      buffer.writeln('$indent```');
      return;
    }

    final delta = node.delta;
    final inline = delta == null ? '' : _encodeDelta(delta);

    String line;
    switch (node.type) {
      case HeadingBlockKeys.type:
        final level = _headingLevel(node);
        line = '${'#' * level} $inline';
        break;
      case QuoteBlockKeys.type:
        line = '> $inline';
        break;
      case BulletedListBlockKeys.type:
        line = '- $inline';
        break;
      case NumberedListBlockKeys.type:
        line = '$orderedNumber. $inline';
        break;
      case ParagraphBlockKeys.type:
        line = inline;
        break;
      default:
        // Unknown block: degrade to its plain text as a paragraph.
        line = inline;
    }
    buffer.writeln('$indent${line.trimRight()}');

    if (node.children.isNotEmpty) {
      _encodeNodes(node.children, buffer, depth + 1);
    }
  }

  /// Serialize a [Delta] to inline Markdown, including `[@key]` citations.
  static String _encodeDelta(Delta delta) {
    final buffer = StringBuffer();
    for (final op in delta) {
      if (op is! TextInsert) continue;
      final attrs = op.attributes ?? const <String, dynamic>{};
      final cite = attrs[citationKey];
      if (cite is String && cite.isNotEmpty) {
        // The attribute is the source of truth; the visible label (op.text)
        // may be an author+year chip and is intentionally discarded.
        buffer.write('[@$cite]');
        continue;
      }
      buffer.write(_wrapInline(op.text, attrs));
    }
    return buffer.toString();
  }

  static String _wrapInline(String text, Attributes attrs) {
    if (text.isEmpty) return '';
    final href = attrs[AppFlowyRichTextKeys.href];
    if (href is String && href.isNotEmpty) {
      final inner = _emphasize(text, attrs);
      return '[$inner]($href)';
    }
    if (attrs[AppFlowyRichTextKeys.code] == true) {
      return '`$text`';
    }
    return _emphasize(text, attrs);
  }

  static String _emphasize(String text, Attributes attrs) {
    final bold = attrs[AppFlowyRichTextKeys.bold] == true;
    final italic = attrs[AppFlowyRichTextKeys.italic] == true;
    final strike = attrs[AppFlowyRichTextKeys.strikethrough] == true;
    var out = text;
    if (bold && italic) {
      out = '***$out***';
    } else if (bold) {
      out = '**$out**';
    } else if (italic) {
      out = '*$out*';
    }
    if (strike) out = '~~$out~~';
    return out;
  }

  // =========================================================================
  // Inline parsing (Markdown -> Delta) with citation support
  // =========================================================================

  /// Parse inline Markdown [text] into a [Delta]. Handles `**bold**`,
  /// `*italic*` / `_italic_`, `***both***`, `` `code` ``, `~~strike~~`,
  /// `[label](url)`, and pandoc `[@key]` citations.
  static Delta parseInline(String text) {
    final delta = Delta();
    var i = 0;
    final n = text.length;
    final plain = StringBuffer();

    void flushPlain() {
      if (plain.isNotEmpty) {
        delta.insert(plain.toString());
        plain.clear();
      }
    }

    while (i < n) {
      // Citation: [@key]
      if (text[i] == '[' && i + 1 < n && text[i + 1] == '@') {
        final close = text.indexOf(']', i);
        if (close != -1) {
          final key = text.substring(i + 2, close);
          if (_isCitationKey(key)) {
            flushPlain();
            delta.insert(key, attributes: {citationKey: key});
            i = close + 1;
            continue;
          }
        }
      }

      // Link: [label](url)
      if (text[i] == '[') {
        final link = _matchLink(text, i);
        if (link != null) {
          flushPlain();
          final labelDelta = parseInline(link.label);
          for (final op in labelDelta) {
            if (op is TextInsert) {
              final a = <String, dynamic>{
                ...?op.attributes,
                AppFlowyRichTextKeys.href: link.url,
              };
              delta.insert(op.text, attributes: a);
            }
          }
          i = link.end;
          continue;
        }
      }

      // Inline code: `code`
      if (text[i] == '`') {
        final close = text.indexOf('`', i + 1);
        if (close != -1) {
          flushPlain();
          delta.insert(text.substring(i + 1, close),
              attributes: {AppFlowyRichTextKeys.code: true});
          i = close + 1;
          continue;
        }
      }

      // Strikethrough: ~~text~~
      if (text.startsWith('~~', i)) {
        final close = text.indexOf('~~', i + 2);
        if (close != -1) {
          flushPlain();
          final inner = parseInline(text.substring(i + 2, close));
          for (final op in inner) {
            if (op is TextInsert) {
              delta.insert(op.text, attributes: {
                ...?op.attributes,
                AppFlowyRichTextKeys.strikethrough: true,
              });
            }
          }
          i = close + 2;
          continue;
        }
      }

      // Bold+italic: ***text***
      if (text.startsWith('***', i)) {
        final close = text.indexOf('***', i + 3);
        if (close != -1) {
          flushPlain();
          delta.insert(text.substring(i + 3, close), attributes: {
            AppFlowyRichTextKeys.bold: true,
            AppFlowyRichTextKeys.italic: true,
          });
          i = close + 3;
          continue;
        }
      }

      // Bold: **text**
      if (text.startsWith('**', i)) {
        final close = text.indexOf('**', i + 2);
        if (close != -1) {
          flushPlain();
          final inner = parseInline(text.substring(i + 2, close));
          for (final op in inner) {
            if (op is TextInsert) {
              delta.insert(op.text, attributes: {
                ...?op.attributes,
                AppFlowyRichTextKeys.bold: true,
              });
            }
          }
          i = close + 2;
          continue;
        }
      }

      // Italic: *text* or _text_
      if (text[i] == '*' || text[i] == '_') {
        final marker = text[i];
        final close = text.indexOf(marker, i + 1);
        if (close != -1 && close > i + 1) {
          flushPlain();
          delta.insert(text.substring(i + 1, close),
              attributes: {AppFlowyRichTextKeys.italic: true});
          i = close + 1;
          continue;
        }
      }

      plain.write(text[i]);
      i++;
    }
    flushPlain();
    return delta;
  }

  // =========================================================================
  // Small helpers
  // =========================================================================

  static Node _codeBlockNode(String text, String lang) {
    return Node(
      type: codeBlockType,
      attributes: {
        blockComponentDelta: (Delta()..insert(text)).toJson(),
        if (lang.isNotEmpty) codeBlockLangKey: lang,
      },
    );
  }

  static int _headingLevel(Node node) {
    final lvl = node.attributes[HeadingBlockKeys.level];
    if (lvl is int && lvl >= 1 && lvl <= 6) return lvl;
    return 1;
  }

  static bool _isFence(String line) => RegExp(r'^\s*```').hasMatch(line);

  /// Returns (level, content) for `# ` .. `###### ` headings.
  static (int, String)? _headingMatch(String line) {
    final m = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (m == null) return null;
    return (m.group(1)!.length, m.group(2)!);
  }

  /// Returns the quote content for `> ` lines.
  static String? _quoteMatch(String line) {
    final m = RegExp(r'^\s*>\s?(.*)$').firstMatch(line);
    return m?.group(1);
  }

  static bool _isCitationKey(String key) =>
      key.isNotEmpty && RegExp(r'^[A-Za-z0-9_:.\-]+$').hasMatch(key);

  static int _stripWidth(String line, int parentIndent) {
    final leading = line.length - line.trimLeft().length;
    final want = parentIndent + 2;
    return leading < want ? leading : want;
  }

  /// Match a list item; null if the line is not a list item.
  static _ListItemMatch? _listItemMatch(String line) {
    final m = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$').firstMatch(line);
    if (m == null) return null;
    final indent = m.group(1)!.length;
    final marker = m.group(2)!;
    final ordered = RegExp(r'^\d').hasMatch(marker);
    return _ListItemMatch(
        indent: indent, ordered: ordered, content: m.group(3)!);
  }

  /// Match a link `[label](url)` starting at [start] (points at `[`).
  static _LinkMatch? _matchLink(String text, int start) {
    if (text[start] != '[') return null;
    var depth = 0;
    var i = start;
    var labelEnd = -1;
    while (i < text.length) {
      if (text[i] == '[') depth++;
      if (text[i] == ']') {
        depth--;
        if (depth == 0) {
          labelEnd = i;
          break;
        }
      }
      i++;
    }
    if (labelEnd == -1) return null;
    if (labelEnd + 1 >= text.length || text[labelEnd + 1] != '(') return null;
    final urlEnd = text.indexOf(')', labelEnd + 2);
    if (urlEnd == -1) return null;
    final label = text.substring(start + 1, labelEnd);
    final url = text.substring(labelEnd + 2, urlEnd);
    return _LinkMatch(label, url, urlEnd + 1);
  }
}

/// Result of matching a list item line.
class _ListItemMatch {
  const _ListItemMatch({
    required this.indent,
    required this.ordered,
    required this.content,
  });
  final int indent;
  final bool ordered;
  final String content;
}

/// Matched link `[label](url)`.
class _LinkMatch {
  const _LinkMatch(this.label, this.url, this.end);
  final String label;
  final String url;
  final int end;
}
