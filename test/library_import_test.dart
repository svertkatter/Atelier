import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:atelier/data/library_import.dart';
import 'package:atelier/data/meta_md.dart';
import 'package:atelier/data/vault_config.dart';
import 'package:atelier/models/csl_metadata.dart';

void main() {
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
