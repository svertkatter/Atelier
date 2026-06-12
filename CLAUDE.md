# CLAUDE.md — Atelier 開発用リファレンス

> このファイルはClaude Code がプロジェクトディレクトリで自動読み込みするファイルです。
> Atelier の開発時のみ参照されます。通常の Claude / Claude Code 使用には影響しません。

---

## このプロジェクトについて

**Atelier** は論文の管理・閲覧・執筆を統合するローカルファーストアプリ。
Flutter製。Mac / Windows / iOS対応。iCloud Driveで同期。
将来的には一般ノート機能も拡張し、Obsidianを置き換えうる個人知識管理アプリを目指す。

全体設計の詳細 → @DESIGN.md（このファイルと同じフォルダ）

---

## 技術スタック（確定済み。変更提案不要）

```
言語          : Dart
フレームワーク : Flutter 3.x
状態管理      : Riverpod
DB            : sqflite（SQLite）+ sqflite_common_ffi（Windows/デスクトップ用）
PDF表示       : pdfrx（PDFiumベース。テキスト選択対応）
MD表示        : flutter_markdown_plus（flutter_markdown の公式後継）
MD編集        : TextField ベースの自作エディタ（プレビュー分離型）
ファイル選択   : file_picker
引用処理      : pandoc（外部プロセス経由）
引用スタイル   : CSL（.cslファイル）
```

> 旧スタックからの変更履歴（2026-06 精査）：
> - `pdfx` → `pdfrx`：pdfx はテキスト選択・注釈不可のためリーダーモードが成立しない
> - `flutter_markdown` → `flutter_markdown_plus`：本家が公式に廃止（discontinued）
> - Windows では `sqflite_common_ffi` が必須（起動時に `databaseFactory = databaseFactoryFfi`）

---

## アーキテクチャの鉄則

### 1. ファイルがデータの本体

```
✅ PDFと.mdファイルに書き込む
✅ vault.sqliteはインデックス専用（失われても.mdから再構築できる）
✅ vault.sqlite は各端末のローカル（Application Support）に置く。iCloud Driveに置かない
❌ SQLiteをメインのデータストアにしない
❌ SQLite DBファイルをクラウド同期フォルダに置かない（WAL/部分同期で破損する）
```

### 2. LibraryとProjectの分離

```
✅ Projectはlibrary/内の論文をIDで参照する（project.json の "refs" 配列）
❌ Projectフォルダ内にPDFをコピーしない
❌ メタデータをProjectに複製しない
```

### 3. プラットフォーム分岐

```dart
// Windows では sqflite_common_ffi を初期化する
if (Platform.isWindows) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

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
✅ [[wikilink]] 記法は Obsidian 互換とする（将来の汎用ノート機能に向けて）
✅ フォルダ構成はiCloud Drive上の任意の場所を指定できる
❌ アプリ独自のバイナリ形式でノートを保存しない
```

### 5. ハイライトはオーバーレイ方式

```
✅ ハイライトは clips.json に保存（ページ番号・矩形座標・選択テキスト・色）
✅ 表示時に pdfrx 上にオーバーレイ描画する
❌ PDFファイル自体に注釈を書き込まない（元論文を汚さない）
```

---

## フォルダ構成

```
【ローカル（端末ごと・同期しない）】
Application Support/Atelier/
└── vault.sqlite     ← インデックス。起動時に library/ をスキャンして差分再構築

【iCloud Drive（同期対象・プレーンファイルのみ）】
Atelier/
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
出力時：meta.md の frontmatter から refs.json を生成（YAML→JSON 変換のみ）
       pandoc draft.md --bibliography=refs.json --csl=styles/{name}.csl -o output.docx
```

- CSLスタイルの処理はすべてpandocに委譲。Dart側に引用ロジックを書かない
- YAML→JSON 変換器は「データ変換」であり引用ロジックではない（実装してよい）
- **出力は docx を先行実装**。PDF出力は LaTeX エンジン依存が重いため後続フェーズ

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
❌ vault.sqlite を iCloud Drive に置く
❌ PDFファイル自体にハイライトを書き込む
```

---

## Dart / Flutter コーディング規約

- ファイル名：`snake_case.dart`
- クラス名：`PascalCase`
- Riverpodプロバイダーは `_provider` サフィックス
- 非同期処理は `AsyncValue` で状態管理
- プラットフォーム固有コードは `platform/` ディレクトリに分離

---

## Claude Code でのモデル使い分け

| 用途 | モデル | 例 |
|---|---|---|
| 設計判断・アーキテクチャ変更・複雑なリファクタ | Opus | データ構造の変更、同期ロジック、エディタ設計 |
| 通常の機能実装・バグ修正・UI構築 | Sonnet | 画面追加、API連携、テスト作成 |

- セッション内で `/model` で切替可能。迷ったら Sonnet で開始し、設計が絡んだら Opus へ
- 大きな変更の前に必ず計画を提示させ、承認後に実装する（plan mode 推奨）
- このファイルと @DESIGN.md を読んだ上で作業すること

---

## 将来フェーズ：汎用ノートアプリ化（Phase 6以降）

Atelier は最終的に Obsidian Vault 全体を移行先として受け入れる。
詳細スタックは @DESIGN.md の「9. 汎用ノート機能の技術スタック」を参照。
**現フェーズの実装でこの将来像を妨げる設計をしないこと**（特に wikilink 互換・標準MD遵守・フォルダ任意指定）。

---

## 参照ファイル一覧

| ファイル | 用途 |
|---|---|
| @DESIGN.md | 全体設計書（コンセプト・データ構造・機能仕様） |
| `CLAUDE.md` | このファイル。Claude Code用技術リファレンス |
| `PROJECT_PROMPT.md` | Claude Projectsカスタム指示のソース |
