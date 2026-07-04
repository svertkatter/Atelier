import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:atelier/data/pandoc_export.dart';
import 'package:atelier/data/vault_config.dart';
import 'package:atelier/models/project.dart';

void main() {
  group('PandocExport.buildArgs', () {
    test('always includes --citeproc and bibliography', () {
      final args = PandocExport.buildArgs(
        draftPath: 'draft.md',
        refsJsonPath: 'refs.json',
        cslPath: 'styles/apa.csl',
        outputPath: 'out.docx',
      );
      expect(args, contains('--citeproc'));
      expect(args, contains('--bibliography=refs.json'));
      expect(args, contains('--csl=styles/apa.csl'));
      expect(args, containsAllInOrder(['-o', 'out.docx']));
      expect(args.first, 'draft.md');
    });

    test('omits --csl when no style given', () {
      final args = PandocExport.buildArgs(
        draftPath: 'draft.md',
        refsJsonPath: 'refs.json',
        cslPath: null,
        outputPath: 'out.docx',
      );
      expect(args.any((a) => a.startsWith('--csl=')), isFalse);
      expect(args, contains('--citeproc'));
    });
  });

  group('PandocExport.buildRefsJson', () {
    late Directory tempDir;
    late VaultConfig config;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('atelier_pandoc_test');
      config = VaultConfig(tempDir.path);
      await config.ensureScaffold();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> writeMeta(String key, String title) async {
      final dir = Directory(p.join(config.libraryDir, key));
      await dir.create(recursive: true);
      final meta = '''
---
csl_json:
  id: "$key"
  type: "article-journal"
  title: "$title"
  author:
    - family: "田中"
      given: "太郎"
  issued:
    date-parts: [[2024]]
tags: []
source: manual
doi: ""
cinii_id: ""
---

## AI要約

## 自分のメモ
''';
      await File(p.join(dir.path, 'meta.md')).writeAsString(meta);
    }

    test('collects refs in order and reports missing', () async {
      await writeMeta('tanaka2024', '音風景の研究');
      await writeMeta('smith2023', 'NLP Study');
      final project = Project(
        id: 'proj',
        name: 'Proj',
        refs: const ['smith2023', 'missing2020', 'tanaka2024'],
      );
      final missing = <String>[];
      final text =
          await PandocExport.buildRefsJson(project, config, missingKeys: missing);
      final arr = jsonDecode(text) as List;
      expect(arr.map((e) => (e as Map)['id']), ['smith2023', 'tanaka2024']);
      expect(missing, ['missing2020']);
      // Japanese title preserved.
      final tanaka = arr.firstWhere((e) => (e as Map)['id'] == 'tanaka2024');
      expect((tanaka as Map)['title'], '音風景の研究');
    });
  });

  group('PandocExport integration (real pandoc)', () {
    test('produces a docx when pandoc is available (else skip)', () async {
      final exe = await PandocExport.resolveExecutable();
      if (exe == null) {
        // No pandoc on this machine: skip rather than fail.
        markTestSkipped('pandoc not found on this machine');
        return;
      }

      final tempDir =
          await Directory.systemTemp.createTemp('atelier_pandoc_run');
      final config = VaultConfig(tempDir.path);
      await config.ensureScaffold();

      // Library paper.
      final libDir = Directory(p.join(config.libraryDir, 'doe2020'));
      await libDir.create(recursive: true);
      await File(p.join(libDir.path, 'meta.md')).writeAsString('''
---
csl_json:
  id: "doe2020"
  type: "article-journal"
  title: "A Test Paper"
  author:
    - family: "Doe"
      given: "Jane"
  issued:
    date-parts: [[2020]]
  container-title: "Journal of Testing"
tags: []
source: manual
doi: ""
cinii_id: ""
---

## AI要約

## 自分のメモ
''');

      // Project with draft citing the paper.
      final projDir = Directory(p.join(config.projectsDir, 'demo'));
      await projDir.create(recursive: true);
      final project = Project(
        id: 'demo',
        name: 'Demo',
        csl: null,
        refs: const ['doe2020'],
        folderName: 'demo',
      );
      await File(p.join(projDir.path, 'project.json'))
          .writeAsString(project.serialize());
      await File(p.join(projDir.path, 'draft.md'))
          .writeAsString('# Demo\n\nAs shown in [@doe2020], testing matters.\n');

      final result =
          await PandocExport.exportDocx(project: project, config: config);

      expect(result.ok, isTrue,
          reason: 'pandoc export failed: ${result.message}\n${result.stderr}');
      final outFile = File(result.outputPath!);
      expect(await outFile.exists(), isTrue);
      expect(await outFile.length(), greaterThan(0));

      await tempDir.delete(recursive: true);
    });
  });
}
