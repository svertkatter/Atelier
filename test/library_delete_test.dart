import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:atelier/data/library_delete.dart';
import 'package:atelier/data/library_import.dart';
import 'package:atelier/data/project_store.dart';
import 'package:atelier/data/vault_config.dart';
import 'package:atelier/models/csl_metadata.dart';

void main() {
  late Directory tempRoot;
  late VaultConfig config;
  late File sourcePdf;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('atelier_delete_test');
    config = await VaultConfig(tempRoot.path).ensureScaffold();
    sourcePdf = File(p.join(tempRoot.path, 'source.pdf'));
    await sourcePdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]);
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('projectsReferencing finds every project.json whose refs include the key',
      () async {
    final importer = LibraryImport(config);
    await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: CslMetadata(id: 'tanaka2024', title: 'T'),
    );

    final store = ProjectStore(config);
    final p1 = await store.create(name: 'proj1');
    await store.ensureRef(p1, 'tanaka2024');
    final p2 = await store.create(name: 'proj2');
    await store.ensureRef(p2, 'other2020');
    final p3 = await store.create(name: 'proj3');
    await store.ensureRef(p3, 'tanaka2024');

    final deleter = LibraryDelete(config);
    final referencing = await deleter.projectsReferencing('tanaka2024');
    expect(referencing.map((p) => p.name).toSet(), {'proj1', 'proj3'});
  });

  test('delete removes the library folder and scrubs refs from all projects',
      () async {
    final importer = LibraryImport(config);
    await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: CslMetadata(id: 'tanaka2024', title: 'T'),
    );

    final store = ProjectStore(config);
    var proj = await store.create(name: 'grad');
    proj = await store.ensureRef(proj, 'tanaka2024');
    proj = await store.ensureRef(proj, 'other2020');

    final deleter = LibraryDelete(config);
    await deleter.delete('tanaka2024');

    expect(
        await Directory(p.join(config.libraryDir, 'tanaka2024')).exists(),
        isFalse);

    final reloaded = await store.load(proj.effectiveFolderName);
    expect(reloaded!.refs, ['other2020']);
    expect(reloaded.refs, isNot(contains('tanaka2024')));
  });

  test('delete is a no-op (does not throw) when the folder is already gone',
      () async {
    final deleter = LibraryDelete(config);
    await deleter.delete('nonexistent2024');
  });

  test('delete with no referencing projects only removes the folder',
      () async {
    final importer = LibraryImport(config);
    await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: CslMetadata(id: 'solo2024', title: 'Solo'),
    );
    final deleter = LibraryDelete(config);
    await deleter.delete('solo2024');
    expect(await Directory(p.join(config.libraryDir, 'solo2024')).exists(),
        isFalse);
  });
}
