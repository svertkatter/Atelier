import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:atelier/data/meta_md.dart';
import 'package:atelier/data/vault_config.dart';
import 'package:atelier/data/vault_index.dart';
import 'package:atelier/models/csl_metadata.dart';
import 'package:atelier/models/paper.dart';
import 'package:atelier/models/project.dart';
import 'package:atelier/platform/database_init.dart';

void main() {
  setUpAll(() {
    // Run the index against a real SQLite engine on the host.
    useFfiDatabaseFactoryForTests();
  });

  late Directory tempRoot;
  late VaultConfig config;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('atelier_vault_test');
    config = await VaultConfig(tempRoot.path).ensureScaffold();
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  Future<void> writePaper(String folder, Paper paper) async {
    final dir = Directory(p.join(config.libraryDir, folder));
    await dir.create(recursive: true);
    await File(config.metaMdPath(folder))
        .writeAsString(MetaMd.serialize(paper));
  }

  Future<void> writeProject(String folder, Project project) async {
    final dir = Directory(p.join(config.projectsDir, folder));
    await dir.create(recursive: true);
    await File(config.projectJsonPath(folder))
        .writeAsString(project.serialize());
  }

  Paper samplePaper(String id, String title, int year) => Paper(
        metadata: CslMetadata(
          id: id,
          type: 'article-journal',
          title: title,
          authors: const [CslName(family: '田中', given: '太郎')],
          issuedDateParts: [
            [year]
          ],
          containerTitle: '情報処理学会論文誌',
        ),
        tags: const ['サウンドスケープ'],
        source: 'cinii',
      );

  test('scan indexes papers and projects from files', () async {
    await writePaper('tanaka2024', samplePaper('tanaka2024', '音風景', 2024));
    await writePaper('smith2023', samplePaper('smith2023', 'NLP', 2023));
    await writeProject(
      '卒業論文_2025',
      const Project(
        id: 'grad-2025',
        name: '卒業論文 2025',
        csl: 'ipsj.csl',
        refs: ['tanaka2024', 'smith2023'],
      ),
    );

    final index = await VaultIndex.open(); // in-memory
    final result = await index.scan(config);

    expect(result.papersIndexed, 2);
    expect(result.projectsIndexed, 1);
    expect(result.errors, isEmpty);

    final papers = await index.allPapers();
    expect(papers.length, 2);
    // Ordered year desc: tanaka(2024) first.
    expect(papers.first['id'], 'tanaka2024');
    expect(papers.first['author'], '田中 太郎');
    expect(papers.first['year'], 2024);
    expect(papers.first['tags'], 'サウンドスケープ');

    final projects = await index.allProjects();
    expect(projects.length, 1);
    expect(projects.first['id'], 'grad-2025');
    expect(projects.first['refs'], 'tanaka2024,smith2023');

    await index.close();
  });

  test(
      'ACCEPTANCE: deleting vault.sqlite fully rebuilds from meta.md',
      () async {
    await writePaper('tanaka2024', samplePaper('tanaka2024', '音風景', 2024));
    await writePaper('smith2023', samplePaper('smith2023', 'NLP', 2023));
    await writeProject(
      'proj',
      const Project(id: 'p1', name: 'Proj', refs: ['tanaka2024']),
    );

    final dbPath = p.join(tempRoot.path, 'local', 'vault.sqlite');
    await Directory(p.dirname(dbPath)).create(recursive: true);

    // First index build.
    final index1 = await VaultIndex.open(dbPath: dbPath);
    await index1.scan(config);
    final before = await index1.allPapers();
    expect(before.length, 2);
    await index1.close();

    // Simulate loss of the local DB.
    await File(dbPath).delete();
    expect(await File(dbPath).exists(), isFalse);

    // Rebuild from files only.
    final index2 = await VaultIndex.open(dbPath: dbPath);
    final result = await index2.scan(config);
    final after = await index2.allPapers();

    expect(result.papersIndexed, 2);
    expect(after.length, 2);
    expect(after.map((r) => r['id']).toSet(), {'tanaka2024', 'smith2023'});
    final projects = await index2.allProjects();
    expect(projects.length, 1);
    expect(projects.first['id'], 'p1');
    await index2.close();
  });

  test('differential rescan: unchanged files are not reindexed', () async {
    await writePaper('tanaka2024', samplePaper('tanaka2024', '音風景', 2024));

    final index = await VaultIndex.open();
    final first = await index.scan(config);
    expect(first.papersIndexed, 1);

    // No file changes -> nothing reindexed.
    final second = await index.scan(config);
    expect(second.papersIndexed, 0);
    expect(second.papersRemoved, 0);

    await index.close();
  });

  test('removed folder is pruned from index on rescan', () async {
    await writePaper('a', samplePaper('a', 'A', 2020));
    await writePaper('b', samplePaper('b', 'B', 2021));

    final index = await VaultIndex.open();
    await index.scan(config);
    expect((await index.allPapers()).length, 2);

    await Directory(p.join(config.libraryDir, 'b')).delete(recursive: true);
    final result = await index.scan(config);
    expect(result.papersRemoved, 1);
    expect((await index.allPapers()).length, 1);
    expect((await index.allPapers()).first['id'], 'a');

    await index.close();
  });

  test('searchPapers matches title/author/tags', () async {
    await writePaper('tanaka2024', samplePaper('tanaka2024', '音風景の知覚', 2024));
    await writePaper('smith2023', samplePaper('smith2023', 'NLP', 2023));

    final index = await VaultIndex.open();
    await index.scan(config);

    expect((await index.searchPapers('音風景')).length, 1);
    expect((await index.searchPapers('田中')).length, 2); // both authored 田中
    expect((await index.searchPapers('サウンドスケープ')).length, 2);
    expect((await index.searchPapers('存在しない')).length, 0);

    await index.close();
  });
}
