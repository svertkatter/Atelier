import 'package:yaml/yaml.dart';

import '../models/csl_metadata.dart';
import '../models/paper.dart';
import 'yaml_writer.dart';

/// Reads and writes `library/{id}/meta.md`.
///
/// Structure:
/// ```
/// ---
/// csl_json: { ... }
/// tags: [...]
/// source: crossref
/// doi: ""
/// cinii_id: ""
/// ---
///
/// ## AI要約
///
/// (summary)
///
/// ## 自分のメモ
///
/// (note)
/// ```
///
/// The round trip (parse -> serialize) must be lossless for all modeled fields
/// and must preserve multibyte (Japanese) content.
class MetaMd {
  static const String aiSummaryHeading = '## AI要約';
  static const String userNoteHeading = '## 自分のメモ';

  /// Parse meta.md [source] into a [Paper]. [folderName] is the containing
  /// directory name (used when it differs from the citation key).
  static Paper parse(String source, {String? folderName}) {
    final split = _splitFrontmatter(source);
    final frontmatterText = split.$1;
    final body = split.$2;

    Map<String, dynamic> fm = <String, dynamic>{};
    if (frontmatterText.trim().isNotEmpty) {
      final parsed = loadYaml(frontmatterText);
      if (parsed is Map) {
        fm = _deepConvert(parsed) as Map<String, dynamic>;
      }
    }

    final cslRaw = fm['csl_json'];
    final csl = (cslRaw is Map)
        ? CslMetadata.fromJson(cslRaw.cast<String, dynamic>())
        : CslMetadata(id: folderName ?? '');

    final tags = <String>[];
    final tagsRaw = fm['tags'];
    if (tagsRaw is List) {
      tags.addAll(tagsRaw.map((e) => e.toString()));
    }

    final sections = _parseSections(body);

    return Paper(
      metadata: csl,
      tags: tags,
      source: _asString(fm['source']),
      doi: _asString(fm['doi']),
      ciniiId: _asString(fm['cinii_id']),
      aiSummary: sections[aiSummaryHeading],
      userNote: sections[userNoteHeading],
      folderName: folderName,
    );
  }

  /// Serialize a [Paper] back to meta.md text.
  static String serialize(Paper paper) {
    // Build the frontmatter map in a stable order.
    final fm = <String, dynamic>{
      'csl_json': paper.metadata.toJson(),
      'tags': paper.tags,
      'source': paper.source ?? '',
      'doi': paper.doi ?? '',
      'cinii_id': paper.ciniiId ?? '',
    };

    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.write(YamlWriter.write(fm));
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln(aiSummaryHeading);
    buffer.writeln();
    if (paper.aiSummary != null && paper.aiSummary!.trim().isNotEmpty) {
      buffer.writeln(paper.aiSummary!.trim());
      buffer.writeln();
    }
    buffer.writeln(userNoteHeading);
    buffer.writeln();
    if (paper.userNote != null && paper.userNote!.trim().isNotEmpty) {
      buffer.writeln(paper.userNote!.trim());
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// Split a `---`-delimited frontmatter block from the body.
  /// Returns (frontmatter, body). If no frontmatter, returns ('', source).
  static (String, String) _splitFrontmatter(String source) {
    // Normalize newlines for parsing.
    final normalized = source.replaceAll('\r\n', '\n');
    if (!normalized.startsWith('---')) {
      return ('', normalized);
    }
    // Find the closing --- on its own line after the opening.
    final lines = normalized.split('\n');
    // lines[0] is the opening '---'.
    var closeIndex = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        closeIndex = i;
        break;
      }
    }
    if (closeIndex == -1) {
      // Malformed; treat whole thing as body.
      return ('', normalized);
    }
    final fm = lines.sublist(1, closeIndex).join('\n');
    final body = lines.sublist(closeIndex + 1).join('\n');
    return (fm, body);
  }

  /// Extract "## " sections keyed by their full heading line.
  static Map<String, String> _parseSections(String body) {
    final result = <String, String>{};
    final lines = body.split('\n');
    String? currentHeading;
    final content = <String>[];

    void flush() {
      final heading = currentHeading;
      if (heading != null) {
        result[heading] = content.join('\n').trim();
      }
      content.clear();
    }

    for (final line in lines) {
      final trimmed = line.trimRight();
      if (trimmed.startsWith('## ')) {
        flush();
        currentHeading = trimmed;
      } else if (currentHeading != null) {
        content.add(line);
      }
    }
    flush();
    return result;
  }

  static String? _asString(Object? v) {
    if (v == null) return null;
    final s = v.toString();
    return s.isEmpty ? null : s;
  }

  /// Recursively convert YamlMap/YamlList into plain Dart Map/List so the rest
  /// of the code deals with standard collections.
  static Object? _deepConvert(Object? node) {
    if (node is YamlMap) {
      return <String, dynamic>{
        for (final entry in node.entries)
          entry.key.toString(): _deepConvert(entry.value)
      };
    }
    if (node is YamlList) {
      return node.map(_deepConvert).toList();
    }
    if (node is Map) {
      return <String, dynamic>{
        for (final entry in node.entries)
          entry.key.toString(): _deepConvert(entry.value)
      };
    }
    if (node is List) {
      return node.map(_deepConvert).toList();
    }
    return node;
  }
}
