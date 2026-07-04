/// Minimal, deterministic YAML 1.1 emitter for meta.md frontmatter.
///
/// The `yaml` package only parses; it does not emit. We need emit for the
/// meta.md round trip, and we must be careful about YAML 1.1 implicit typing:
/// bare `no`/`yes`/`on`/`off`, numbers, and dates would be re-read as
/// bool/int/date. To stay lossless we quote any scalar that is not an
/// unambiguous plain string.
class YamlWriter {
  /// Emit [data] (a Map/List/scalar tree) as YAML block text (no leading
  /// `---`). Keys are emitted in insertion order.
  static String write(Object? data) {
    final buffer = StringBuffer();
    _writeNode(buffer, data, 0);
    return buffer.toString();
  }

  static void _writeNode(StringBuffer b, Object? node, int indent) {
    if (node is Map) {
      _writeMap(b, node, indent);
    } else if (node is List) {
      _writeList(b, node, indent);
    } else {
      // A bare scalar at top level (rare). Should be preceded by a key.
      b.writeln(_scalar(node));
    }
  }

  static void _writeMap(StringBuffer b, Map map, int indent) {
    final pad = '  ' * indent;
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is Map && value.isNotEmpty) {
        b.writeln('$pad$key:');
        _writeMap(b, value, indent + 1);
      } else if (value is Map) {
        b.writeln('$pad$key: {}');
      } else if (value is List && value.isNotEmpty) {
        // Inline scalar lists like `tags: [a, b]` for compactness and to match
        // the DESIGN.md sample. Nested/complex lists use block form.
        if (value.every(_isScalar)) {
          b.writeln('$pad$key: ${_flowList(value)}');
        } else {
          b.writeln('$pad$key:');
          _writeList(b, value, indent + 1);
        }
      } else if (value is List) {
        b.writeln('$pad$key: []');
      } else {
        b.writeln('$pad$key: ${_scalar(value)}');
      }
    }
  }

  static void _writeList(StringBuffer b, List list, int indent) {
    final pad = '  ' * indent;
    for (final item in list) {
      if (item is Map && item.isNotEmpty) {
        // Emit "- " then the map's first key inline, rest indented.
        final entries = item.entries.toList();
        final first = entries.first;
        b.writeln('$pad- ${first.key}: ${_inlineValueOrBlock(b, first.value, indent + 1, sameLine: true)}');
        for (final e in entries.skip(1)) {
          _writeMap(b, {e.key: e.value}, indent + 1);
        }
      } else if (item is List) {
        b.writeln('$pad- ${_flowList(item)}');
      } else {
        b.writeln('$pad- ${_scalar(item)}');
      }
    }
  }

  /// Helper for the first entry of a map item inside a list. For scalar values
  /// returns the scalar text; block collections are not expected as the first
  /// value in our data shapes, so we fall back to scalar.
  static String _inlineValueOrBlock(
      StringBuffer b, Object? value, int indent,
      {bool sameLine = false}) {
    if (value is Map && value.isNotEmpty) {
      // Not expected for our data; degrade to flow map.
      return '{${value.entries.map((e) => '${e.key}: ${_scalar(e.value)}').join(', ')}}';
    }
    if (value is List) {
      return _flowList(value);
    }
    return _scalar(value);
  }

  static bool _isScalar(Object? v) => v is! Map && v is! List;

  static String _flowList(List list) =>
      '[${list.map((e) => e is List ? _flowList(e) : _scalar(e)).join(', ')}]';

  /// Render a scalar, quoting when necessary to survive a YAML 1.1 re-parse as
  /// the same value.
  static String _scalar(Object? value) {
    if (value == null) return '""';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    final s = value.toString();
    if (_needsQuote(s)) {
      return _doubleQuote(s);
    }
    return s;
  }

  /// True if [s], emitted bare, would be re-parsed as a non-string or would
  /// break YAML structure. We intentionally over-quote for safety.
  static bool _needsQuote(String s) {
    if (s.isEmpty) return true;
    // Leading/trailing whitespace is lost when unquoted.
    if (s != s.trim()) return true;

    // YAML 1.1 implicit bool/null tokens (case-insensitive).
    const reserved = <String>{
      'true', 'false', 'yes', 'no', 'on', 'off', 'null', '~',
      'y', 'n',
    };
    if (reserved.contains(s.toLowerCase())) return true;

    // Looks like a number (int, float, or leading +/-).
    if (RegExp(r'^[+-]?(\d[\d_]*)(\.\d+)?([eE][+-]?\d+)?$').hasMatch(s)) {
      return true;
    }
    // Looks like a date/time (e.g. 2024-06-13).
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return true;

    // Characters that have structural meaning in YAML flow/block context.
    if (RegExp(r'''[:#\[\]{},&*!|>'"%@`]''').hasMatch(s)) return true;
    // Leading indicator characters.
    if (RegExp(r'^[\s\-?:,\[\]{}#&*!|>%@`"' r"'" r']').hasMatch(s)) return true;

    return false;
  }

  static String _doubleQuote(String s) {
    final escaped = s
        .replaceAll('\\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }
}
