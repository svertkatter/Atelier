import 'dart:convert';

/// A work unit, corresponding to `projects/{name}/project.json`.
///
/// Projects reference library papers by citation key ([refs]); PDFs and
/// metadata are never copied into the project folder.
class Project {
  const Project({
    required this.id,
    required this.name,
    this.csl,
    this.refs = const <String>[],
    this.folderName,
  });

  final String id;
  final String name;

  /// CSL style file name for this project, e.g. `ipsj.csl`. Null = inherit
  /// global default.
  final String? csl;

  /// Citation keys referenced by this project (`refs` array in project.json).
  final List<String> refs;

  /// The `projects/{folderName}/` directory name. Defaults to [name].
  final String? folderName;

  String get effectiveFolderName => folderName ?? name;

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        csl: json['csl'] as String?,
        refs: (json['refs'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[],
      );

  /// Parse from raw project.json text.
  factory Project.parse(String source) =>
      Project.fromJson(jsonDecode(source) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        if (csl != null) 'csl': csl,
        'refs': refs,
      };

  /// Serialize to pretty-printed project.json text.
  String serialize() =>
      const JsonEncoder.withIndent('  ').convert(toJson());

  Project copyWith({
    String? id,
    String? name,
    String? csl,
    List<String>? refs,
    String? folderName,
  }) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        csl: csl ?? this.csl,
        refs: refs ?? this.refs,
        folderName: folderName ?? this.folderName,
      );
}
