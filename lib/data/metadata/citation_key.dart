import '../../models/csl_metadata.dart';

/// Generates citation keys (e.g. `tanaka2024`) from CSL metadata, ASCII-izing
/// non-Latin family names and disambiguating collisions with a/b/c suffixes.
///
/// The key doubles as the `library/{key}/` folder name (see DESIGN.md meta.md
/// `csl_json.id`), so it must be filesystem-safe on all platforms.
class CitationKey {
  const CitationKey._();

  /// Generate a key for [metadata], avoiding collisions with [existingKeys].
  /// [existingKeys] should include every citation key currently in the vault
  /// index (case-insensitive comparison, since folder names are
  /// case-insensitive on Windows/macOS).
  static String generate(
    CslMetadata metadata, {
    Set<String> existingKeys = const <String>{},
  }) {
    final base = _baseKey(metadata);
    final lowerExisting = existingKeys.map((k) => k.toLowerCase()).toSet();

    if (!lowerExisting.contains(base.toLowerCase())) return base;

    for (var i = 0; i < 26; i++) {
      final suffix = String.fromCharCode('a'.codeUnitAt(0) + i);
      final candidate = '$base$suffix';
      if (!lowerExisting.contains(candidate.toLowerCase())) return candidate;
    }
    // Extremely unlikely fallback: append a running counter.
    var n = 1;
    while (true) {
      final candidate = '$base${n++}';
      if (!lowerExisting.contains(candidate.toLowerCase())) return candidate;
    }
  }

  static String _baseKey(CslMetadata metadata) {
    final familyRaw = metadata.authors.isNotEmpty
        ? (metadata.authors.first.family ?? metadata.authors.first.literal)
        : null;
    final family = _asciiize(familyRaw ?? 'unknown');
    final year = metadata.year?.toString() ?? 'nd';
    final key = '$family$year';
    return key.isEmpty ? 'paper$year' : key;
  }

  /// Transliterate to ASCII: keep existing ASCII letters/digits as-is, strip
  /// diacritics from Latin script, and drop anything else (e.g. Japanese
  /// kanji/kana) since we have no reliable romanization without a library.
  /// A name that becomes empty after stripping falls back to "author".
  static String _asciiize(String input) {
    final decomposed = _stripDiacritics(input);
    final asciiOnly =
        decomposed.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    return asciiOnly.isEmpty ? 'author' : asciiOnly;
  }

  static const Map<String, String> _diacriticMap = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a', 'å': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c', 'ý': 'y', 'ß': 'ss',
    'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A', 'Ã': 'A', 'Å': 'A',
    'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
    'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
    'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O', 'Õ': 'O',
    'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
    'Ñ': 'N', 'Ç': 'C', 'Ý': 'Y',
  };

  static String _stripDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_diacriticMap[char] ?? char);
    }
    return buffer.toString();
  }
}
