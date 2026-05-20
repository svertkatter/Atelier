# CLAUDE.md — Atelier 開発用リファレンス

> このファイルはClaude Code がプロジェクトディレクトリで自動読み込みするファイルです。
> Atelier の開発時のみ参照されます。通常の Claude / Claude Code 使用には影響しません。

---

## このプロジェクトについて

**Atelier** は論文の管理・閲覧・執筆を統合するローカルファーストアプリ。  
Flutter製。Mac / Windows / iOS対応。iCloud Driveで同期。  
将来的には一般ノート機能も拡張し、Obsidianを置き換えうる個人知識管理アプリを目指す。

全体設計の詳細 → `DESIGN.md`（このファイルと同じフォルダ）

---

## 技術スタック（確定済み。変更提案不要）

```
言語          : Dart
フレームワーク : Flutter 3.x
状態管理      : Riverpod
DB            : sqflite（SQLite）
PDF表示       : pdfx
MD表示        : flutter_markdown
ファイル選択   : file_picker
引用処理      : pandoc（外部プロセス経由）
引用スタイル   : CSL（.cslファイル）
```

---

## アーキテクチャの鉄則

### 1. ファイルがデータの本体

```
✅ PDFと.mdファイルに書き込む
✅ vault.sqliteはインデックス専用（失われても.mdから再構築できる）
❌ SQLiteをメインのデータストアにしない
```

### 2. LibraryとProjectの分離

```
✅ Projectはlibrary/内の論文をIDで参照する（project.json の "refs" 配列）
❌ Projectフォルダ内にPDFをコピーしない
❌ メタデータをProjectに複製しない
```

### 3. プラットフォーム分岐

```dart
// pandocやOllamaなどデスクトップ専用処理は必ずガードする
if (Platform.isMacOS || Platform.isWindows) {
  // pandoc出力・ローカルLLM処理
} else {
  // iOS：.mdプレビューのみ、出力ボタンを非表示
}
```

### 4. ObsidianのVaultと共存できること

```
✅ ノートはすべて標準Markdownで書く
✅ フォルダ構成はiCloud Drive上の任意の場所を指定できる
❌ アプリ独自のバイナリ形式でノートを保存しない
```

---

## フォルダ構成（iCloud Drive）

```
Atelier/
├── vault.sqlite
├── styles/          ← .csl ファイル
├── library/
│   └── {id}/
│       ├── paper.pdf
│       └── meta.md  ← YAML frontmatter に CSL-JSON を含む
└── projects/
    └── {name}/
        ├── project.json
        ├── notes.md
        ├── draft.md
        └── clips.json
```

---

## 引用フロー

```
@キーワード入力 → vault.sqlite から候補検索 → インライン引用チップ表示
出力時：pandoc draft.md --bibliography=refs.json --csl=styles/{name}.csl -o output.{pdf|docx}
```

CSLスタイルの処理はすべてpandocに委譲。Dart側に引用ロジックを書かない。

---

## メタデータ取得の優先順位

```
1. CrossRef API（DOI検出時）
2. CiNii API（日本語論文・CiNii ID検出時）
3. J-STAGE API（J-STAGE URL含む時）
4. 手動入力フォーム（フォールバック）
```

---

## やってはいけないこと

```
❌ 外部クラウドストレージAPIに依存した実装（iCloud以外）
❌ .csl をDart側でパース・処理する
❌ iOS向けにpandoc処理を回避するハック
❌ ユーザーデータをアプリのサンドボックスのみに保存（iCloud Driveに置くこと）
❌ 引用スタイルを独自フォーマットで定義する（.csl標準を使う）
❌ Obsidianと非互換なMarkdown拡張を使う
```

---

## Dart / Flutter コーディング規約

- ファイル名：`snake_case.dart`
- クラス名：`PascalCase`
- Riverpodプロバイダーは `_provider` サフィックス
- 非同期処理は `AsyncValue` で状態管理
- プラットフォーム固有コードは `platform/` ディレクトリに分離

---

## 参照ファイル一覧

| ファイル | 用途 |
|---|---|
| `DESIGN.md` | 全体設計書（コンセプト・データ構造・機能仕様） |
| `CLAUDE.md` | このファイル。Claude Code用技術リファレンス |
| `PROJECT_PROMPT.md` | Claude Projectsカスタム指示のソース |
