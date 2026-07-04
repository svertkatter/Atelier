/// CSL-JSON author name (family / given).
///
/// Mirrors the CSL-JSON `name-variable` shape. Both fields are optional
/// because Japanese metadata sometimes provides only a literal name.
class CslName {
  const CslName({this.family, this.given, this.literal});

  final String? family;
  final String? given;

  /// Some sources provide a single unsplit name; CSL-JSON allows `literal`.
  final String? literal;

  factory CslName.fromJson(Map<String, dynamic> json) => CslName(
        family: json['family'] as String?,
        given: json['given'] as String?,
        literal: json['literal'] as String?,
      );

  /// Serialize to a CSL-JSON name object, omitting null fields.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (family != null) 'family': family,
        if (given != null) 'given': given,
        if (literal != null) 'literal': literal,
      };

  @override
  bool operator ==(Object other) =>
      other is CslName &&
      other.family == family &&
      other.given == given &&
      other.literal == literal;

  @override
  int get hashCode => Object.hash(family, given, literal);
}

/// CSL-JSON metadata for a single reference.
///
/// This is the citation-processor–facing representation (`csl_json` block in
/// meta.md). [id] is the citation key. Unknown/extra CSL fields are preserved
/// verbatim in [extra] so we never lose data on the meta.md round trip.
class CslMetadata {
  const CslMetadata({
    required this.id,
    this.type,
    this.title,
    this.authors = const <CslName>[],
    this.issuedDateParts,
    this.containerTitle,
    this.volume,
    this.issue,
    this.page,
    this.doi,
    this.url,
    this.publisher,
    this.abstractText,
    this.extra = const <String, dynamic>{},
  });

  /// Citation key (CSL-JSON `id`). Also the library folder name.
  final String id;

  /// CSL type, e.g. `article-journal`.
  final String? type;
  final String? title;
  final List<CslName> authors;

  /// CSL `issued.date-parts`, e.g. `[[2024]]` or `[[2024, 6, 13]]`.
  /// Stored as-is (list of lists of ints).
  final List<List<int>>? issuedDateParts;

  final String? containerTitle;
  final String? volume;
  final String? issue;
  final String? page;
  final String? doi;
  final String? url;
  final String? publisher;
  final String? abstractText;

  /// Any CSL fields not explicitly modeled above, kept for lossless round trip.
  final Map<String, dynamic> extra;

  /// The publication year (first element of the first date-part), if present.
  int? get year {
    final dp = issuedDateParts;
    if (dp != null && dp.isNotEmpty && dp.first.isNotEmpty) {
      return dp.first.first;
    }
    return null;
  }

  /// A denormalized author string for indexing/search (e.g. "田中 太郎; Smith").
  String get authorDisplay => authors
      .map((a) {
        if (a.literal != null && a.literal!.isNotEmpty) return a.literal!;
        return [a.family, a.given]
            .where((s) => s != null && s.isNotEmpty)
            .join(' ');
      })
      .where((s) => s.isNotEmpty)
      .join('; ');

  /// Well-known keys that map to explicit fields. Used to split [extra].
  static const Set<String> _knownKeys = <String>{
    'id',
    'type',
    'title',
    'author',
    'issued',
    'container-title',
    'volume',
    'issue',
    'page',
    'DOI',
    'URL',
    'publisher',
    'abstract',
  };

  factory CslMetadata.fromJson(Map<String, dynamic> json) {
    List<List<int>>? dateParts;
    final issued = json['issued'];
    if (issued is Map) {
      final dp = issued['date-parts'];
      if (dp is List) {
        dateParts = dp
            .whereType<List>()
            .map((row) => row
                .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
                .toList())
            .toList();
      }
    }

    final authorsRaw = json['author'];
    final authors = <CslName>[];
    if (authorsRaw is List) {
      for (final a in authorsRaw) {
        if (a is Map) {
          authors.add(CslName.fromJson(a.map(
              (k, v) => MapEntry(k.toString(), v))));
        }
      }
    }

    final extra = <String, dynamic>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }

    return CslMetadata(
      id: (json['id'] ?? '').toString(),
      type: json['type'] as String?,
      title: json['title'] as String?,
      authors: authors,
      issuedDateParts: dateParts,
      containerTitle: json['container-title'] as String?,
      volume: json['volume']?.toString(),
      issue: json['issue']?.toString(),
      page: json['page']?.toString(),
      doi: json['DOI'] as String?,
      url: json['URL'] as String?,
      publisher: json['publisher'] as String?,
      abstractText: json['abstract'] as String?,
      extra: extra,
    );
  }

  /// Serialize to CSL-JSON. Field order is stable and null fields omitted so
  /// the meta.md round trip is deterministic.
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'id': id};
    if (type != null) map['type'] = type;
    if (title != null) map['title'] = title;
    if (authors.isNotEmpty) {
      map['author'] = authors.map((a) => a.toJson()).toList();
    }
    if (issuedDateParts != null) {
      map['issued'] = {'date-parts': issuedDateParts};
    }
    if (containerTitle != null) map['container-title'] = containerTitle;
    if (volume != null) map['volume'] = volume;
    if (issue != null) map['issue'] = issue;
    if (page != null) map['page'] = page;
    if (doi != null) map['DOI'] = doi;
    if (url != null) map['URL'] = url;
    if (publisher != null) map['publisher'] = publisher;
    if (abstractText != null) map['abstract'] = abstractText;
    // Preserve unknown fields.
    for (final entry in extra.entries) {
      map[entry.key] = entry.value;
    }
    return map;
  }
}
