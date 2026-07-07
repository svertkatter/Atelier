import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:atelier/data/library_import.dart';
import 'package:atelier/data/meta_md.dart';
import 'package:atelier/data/metadata/crossref_client.dart';
import 'package:atelier/data/vault_config.dart';
import 'package:atelier/data/vault_index.dart';
import 'package:atelier/models/csl_metadata.dart';
import 'package:atelier/platform/database_init.dart';

void main() {
  setUpAll(() {
    useFfiDatabaseFactoryForTests();
  });

  late Directory tempRoot;
  late VaultConfig config;
  late File sourcePdf;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('atelier_import_test');
    config = await VaultConfig(tempRoot.path).ensureScaffold();
    sourcePdf = File(p.join(tempRoot.path, 'source.pdf'));
    await sourcePdf.writeAsBytes([0x25, 0x50, 0x44, 0x46]); // "%PDF"
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('importPaper creates library/{key}/ with paper.pdf and meta.md',
      () async {
    final importer = LibraryImport(config);
    final metadata = CslMetadata(
      id: 'tanaka2024',
      type: 'article-journal',
      title: '音風景の知覚',
      authors: const [CslName(family: '田中', given: '太郎')],
      issuedDateParts: [
        [2024]
      ],
    );

    final paper = await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: metadata,
      tags: const ['サウンドスケープ'],
      source: 'crossref',
      doi: '10.1234/example',
    );

    expect(paper.effectiveFolderName, 'tanaka2024');
    final pdfFile = File(config.paperPdfPath('tanaka2024'));
    final metaFile = File(config.metaMdPath('tanaka2024'));
    expect(await pdfFile.exists(), isTrue);
    expect(await metaFile.exists(), isTrue);

    final parsed = MetaMd.parse(await metaFile.readAsString(),
        folderName: 'tanaka2024');
    expect(parsed.metadata.title, '音風景の知覚');
    expect(parsed.tags, ['サウンドスケープ']);
    expect(parsed.source, 'crossref');
    expect(parsed.doi, '10.1234/example');
  });

  test('importPaper disambiguates a colliding citation key', () async {
    final importer = LibraryImport(config);
    final metadata = CslMetadata(
      id: 'tanaka2024',
      title: 'Second paper by the same key',
      authors: const [CslName(family: 'Tanaka')],
      issuedDateParts: [
        [2024]
      ],
    );

    final paper = await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: metadata,
      existingKeys: {'tanaka2024'},
    );

    expect(paper.effectiveFolderName, 'tanaka2024a');
    expect(await File(config.paperPdfPath('tanaka2024a')).exists(), isTrue);
  });

  test(
      'REGRESSION: importing a CrossRef result (metadata.id == DOI) never '
      'creates a nested/slash folder and lands at library/ top level, '
      'indexed', () async {
    // CrossrefClient.normalize sets metadata.id to the (slash-containing) DOI
    // itself — this is the exact shape that reached importPaper in the field
    // and produced library/10.1038/nphys1170/ (an unindexable nested path).
    final metadata = CrossrefClient.normalize({
      'title': ['Observation of a nonlinear photonic phenomenon'],
      'author': [
        {'family': 'Tanaka', 'given': 'Taro'}
      ],
      'issued': {
        'date-parts': [
          [2024]
        ]
      },
      'DOI': '10.1038/nphys1170',
    }, citationId: '10.1038/nphys1170');
    expect(metadata.id, '10.1038/nphys1170'); // sanity: reproduces the bug input

    final importer = LibraryImport(config);
    final paper = await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: metadata,
      source: 'crossref',
      doi: metadata.doi,
    );

    // Folder name is the generated citation key, not the raw DOI.
    expect(paper.effectiveFolderName, 'tanaka2024');
    expect(paper.effectiveFolderName, isNot(contains('/')));

    // The folder exists directly under library/ (no nested "10.1038/..." path).
    expect(await Directory(p.join(config.libraryDir, 'tanaka2024')).exists(),
        isTrue);
    expect(await Directory(p.join(config.libraryDir, '10.1038')).exists(),
        isFalse);

    // The DOI itself is preserved (just not used as the folder/id).
    final metaFile = File(config.metaMdPath('tanaka2024'));
    final parsed = MetaMd.parse(await metaFile.readAsString(),
        folderName: 'tanaka2024');
    expect(parsed.doi, '10.1038/nphys1170');
    expect(parsed.metadata.id, 'tanaka2024');

    // The vault index scan (library/ top-level only) picks it up.
    final index = await VaultIndex.open();
    final result = await index.scan(config);
    expect(result.papersIndexed, 1);
    expect(result.errors, isEmpty);
    final rows = await index.allPapers();
    expect(rows.map((r) => r['id']), contains('tanaka2024'));
    await index.close();
  });

  test('a manually-typed short id (already a safe key) is kept as-is',
      () async {
    final importer = LibraryImport(config);
    final metadata = CslMetadata(id: 'my-key_1', title: 'Manual entry');
    final paper = await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: metadata,
    );
    expect(paper.effectiveFolderName, 'my-key_1');
  });

  test('a bare numeric id (e.g. a CiNii CRID) is never used as the folder key',
      () async {
    final importer = LibraryImport(config);
    final metadata = CslMetadata(
      id: '1050282677628470784',
      title: 'CiNii paper without a safe id',
      authors: const [CslName(family: 'Suzuki')],
      issuedDateParts: [
        [2023]
      ],
    );
    final paper = await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: metadata,
    );
    expect(paper.effectiveFolderName, 'suzuki2023');
  });

  test('importPaper without a PDF creates a metadata-only entry', () async {
    final importer = LibraryImport(config);
    final metadata = CslMetadata(id: 'nopdf2024', title: 'No PDF yet');
    final paper = await importer.importPaper(
      sourcePdfPath: null,
      metadata: metadata,
    );
    expect(await File(config.metaMdPath('nopdf2024')).exists(), isTrue);
    expect(await File(config.paperPdfPath('nopdf2024')).exists(), isFalse);
    expect(paper.effectiveFolderName, 'nopdf2024');
  });

  test('attachPdf copies a PDF into an existing metadata-only entry',
      () async {
    final importer = LibraryImport(config);
    await importer.importPaper(
      sourcePdfPath: null,
      metadata: CslMetadata(id: 'nopdf2025', title: 'No PDF yet'),
    );
    expect(await File(config.paperPdfPath('nopdf2025')).exists(), isFalse);

    await importer.attachPdf(key: 'nopdf2025', sourcePdfPath: sourcePdf.path);
    expect(await File(config.paperPdfPath('nopdf2025')).exists(), isTrue);
  });

  test('saveMetadata overwrites meta.md for manual edits', () async {
    final importer = LibraryImport(config);
    final metadata = CslMetadata(id: 'yamada2020', title: 'Original title');
    final paper = await importer.importPaper(
      sourcePdfPath: sourcePdf.path,
      metadata: metadata,
    );

    final updated = paper.copyWith(
      metadata: CslMetadata(id: 'yamada2020', title: 'Edited title'),
      tags: const ['edited'],
    );
    await importer.saveMetadata(updated);

    final reparsed = MetaMd.parse(
        await File(config.metaMdPath('yamada2020')).readAsString(),
        folderName: 'yamada2020');
    expect(reparsed.metadata.title, 'Edited title');
    expect(reparsed.tags, ['edited']);
  });
}
