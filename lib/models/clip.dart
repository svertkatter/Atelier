import 'dart:convert';

/// A normalized highlight rectangle. All values are fractions of page
/// width/height (0.0–1.0) so they are resolution independent.
class ClipRect {
  const ClipRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  factory ClipRect.fromJson(Map<String, dynamic> json) => ClipRect(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'x': x, 'y': y, 'w': w, 'h': h};

  @override
  bool operator ==(Object other) =>
      other is ClipRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);
}

/// A single highlight (overlay), stored in `clips.json`. The PDF file itself is
/// never modified — clips.json is the source of truth.
class Clip {
  const Clip({
    required this.id,
    required this.paperId,
    required this.page,
    required this.rects,
    required this.text,
    required this.color,
    this.created,
  });

  final String id;

  /// Citation key of the library paper this clip belongs to.
  final String paperId;

  /// 1-based page number.
  final int page;

  final List<ClipRect> rects;

  /// Selected text.
  final String text;

  /// Highlight color name, e.g. `yellow`, `green`, `blue`.
  final String color;

  /// ISO-8601 date string (`YYYY-MM-DD`).
  final String? created;

  factory Clip.fromJson(Map<String, dynamic> json) => Clip(
        id: (json['id'] ?? '').toString(),
        paperId: (json['paper_id'] ?? '').toString(),
        page: (json['page'] as num?)?.toInt() ?? 0,
        rects: (json['rects'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    ClipRect.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
                .toList() ??
            const <ClipRect>[],
        text: (json['text'] ?? '').toString(),
        color: (json['color'] ?? 'yellow').toString(),
        created: json['created'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'paper_id': paperId,
        'page': page,
        'rects': rects.map((r) => r.toJson()).toList(),
        'text': text,
        'color': color,
        if (created != null) 'created': created,
      };
}

/// The full `clips.json` document: `{ "clips": [ ... ] }`.
class ClipsFile {
  const ClipsFile({this.clips = const <Clip>[]});

  final List<Clip> clips;

  factory ClipsFile.fromJson(Map<String, dynamic> json) => ClipsFile(
        clips: (json['clips'] as List?)
                ?.whereType<Map>()
                .map((e) =>
                    Clip.fromJson(e.map((k, v) => MapEntry(k.toString(), v))))
                .toList() ??
            const <Clip>[],
      );

  factory ClipsFile.parse(String source) {
    if (source.trim().isEmpty) return const ClipsFile();
    return ClipsFile.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'clips': clips.map((c) => c.toJson()).toList()};

  String serialize() =>
      const JsonEncoder.withIndent('  ').convert(toJson());
}
