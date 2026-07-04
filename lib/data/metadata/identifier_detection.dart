/// Detects which metadata source to try first, per DESIGN.md「6.」:
/// DOI -> CrossRef(->OpenAlex); CiNii ID/URL -> CiNii Research;
/// J-STAGE URL -> J-STAGE; otherwise -> manual entry.
enum DetectedIdentifierKind { doi, cinii, jstage, none }

class DetectedIdentifier {
  const DetectedIdentifier(this.kind, this.value);
  final DetectedIdentifierKind kind;

  /// The extracted DOI / CiNii CRID / raw J-STAGE query text (for J-STAGE,
  /// simply the original input since the API takes free text).
  final String value;
}

/// Inspects free-form user input (pasted text, a URL, or a bare DOI) and
/// determines which metadata API to query first.
class IdentifierDetection {
  const IdentifierDetection._();

  static final RegExp _doiPattern =
      RegExp(r'10\.\d{4,9}/[^\s"<>]+', caseSensitive: false);
  static final RegExp _ciniiCridPattern = RegExp(r'crid/(\d+)');
  static final RegExp _ciniiNaidPattern = RegExp(r'naid/(\d+)');
  static final RegExp _jstageHost =
      RegExp(r'jstage\.jst\.go\.jp', caseSensitive: false);

  /// Detect the identifier kind in [input]. DOI takes priority since a DOI can
  /// appear inside a jstage.jst.go.jp URL (J-STAGE articles have DOIs too) —
  /// but per DESIGN.md, a J-STAGE *URL* should route to the J-STAGE API, so we
  /// check the J-STAGE host first, then CiNii, then bare DOI.
  static DetectedIdentifier detect(String input) {
    final text = input.trim();
    if (text.isEmpty) {
      return const DetectedIdentifier(DetectedIdentifierKind.none, '');
    }

    if (_jstageHost.hasMatch(text)) {
      return DetectedIdentifier(DetectedIdentifierKind.jstage, text);
    }

    final crid = _ciniiCridPattern.firstMatch(text) ??
        _ciniiNaidPattern.firstMatch(text);
    if (crid != null) {
      return DetectedIdentifier(DetectedIdentifierKind.cinii, text);
    }

    final doi = _doiPattern.firstMatch(text);
    if (doi != null) {
      return DetectedIdentifier(DetectedIdentifierKind.doi, doi.group(0)!);
    }

    return const DetectedIdentifier(DetectedIdentifierKind.none, '');
  }
}
