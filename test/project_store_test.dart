import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:atelier/data/project_store.dart';
import 'package:atelier/data/vault_config.dart';
import 'package:atelier/models/project.dart';

void main() {
  late Directory tempDir;
  late VaultConfig config;
  late ProjectStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('atelier_projstore');
    config = VaultConfig(tempDir.path);
    await config.ensureScaffold();
    store = ProjectStore(config);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('create writes project.json and empty draft.md', () async {
    final proj = await store.create(name: '卒業論文 2025', csl: 'apa.csl');
    expect(proj.csl, 'apa.csl');
    final jsonFile = File(config.projectJsonPath(proj.effectiveFolderName));
    expect(await jsonFile.exists(), isTrue);
    final draft = File(store.draftPath(proj));
    expect(await draft.exists(), isTrue);
    expect(await draft.readAsString(), '');

    // project.json round-trips.
    final parsed =
        Project.parse(await jsonFile.readAsString());
    expect(parsed.name, '卒業論文 2025');
  });

  test('create sanitizes illegal folder characters', () async {
    final proj = await store.create(name: 'a/b:c*?');
    expect(proj.effectiveFolderName, isNot(contains('/')));
    expect(proj.effectiveFolderName, isNot(contains(':')));
    final dir = Directory(p.join(config.projectsDir, proj.effectiveFolderName));
    expect(await dir.exists(), isTrue);
  });

  test('ensureRef adds a key once and persists', () async {
    var proj = await store.create(name: 'refproj');
    proj = await store.ensureRef(proj, 'tanaka2024');
    expect(proj.refs, contains('tanaka2024'));
    // Idempotent.
    final again = await store.ensureRef(proj, 'tanaka2024');
    expect(again.refs.where((r) => r == 'tanaka2024').length, 1);

    // Persisted to disk.
    final onDisk = jsonDecode(
      await File(config.projectJsonPath(proj.effectiveFolderName))
          .readAsString(),
    ) as Map<String, dynamic>;
    expect((onDisk['refs'] as List), contains('tanaka2024'));
  });

  test('write/read draft round-trips including japanese', () async {
    final proj = await store.create(name: 'draftproj');
    const md = '# 見出し\n\n本文 [@key]。\n';
    await store.writeDraft(proj, md);
    expect(await store.readDraft(proj), md);
  });

  test('listProjects finds created projects', () async {
    await store.create(name: 'p1');
    await store.create(name: 'p2');
    final list = await store.listProjects();
    expect(list.map((e) => e.name), containsAll(<String>['p1', 'p2']));
  });
}
