# CLAUDE.md — Atelier 開発用リファレンス

> このファイルはClaude Code がプロジェクトディレクトリで自動読み込みするファイルです。
> Atelier の開発時のみ参照されます。通常の Claude / Claude Code 使用には影響しません。

---

## このプロジェクトについて

**Atelier** は論文の管理・閲覧・執筆を統合するローカルファーストアプリ。
Flutter製。Mac / Windows / iOS対応。iCloud Driveで同期。
将来的には一般ノート機能も拡張し、Obsidianを置き換えうる個人知識管理アプリを目指す。

**MVPは「論文管理 → 執筆 → 出力」の一気通貫（縦の背骨）を最優先**。詳細な実装順は @DESIGN.md「8.」。

全体設計の詳細 → @DESIGN.md（このファイルと同じフォルダ）

---

## 技術スタック（確定済み。変更時はユーザー承認）

```
言語          : Dart
フレームワーク : Flutter 3.x
状態管理      : Riverpod
DB            : sqflite（SQLite）+ sqflite_common_ffi（Windows/デスクトップ用・端末ローカル）
PDF表示       : pdfrx（PDFiumベース。テキスト選択対応）
MD表示        : flutter_markdown_plus（flutter_markdown の公式後継）
原稿編集      : WYSIWYG（appflowy_editor）。# 等の記法を画面に出さず、標準Markdownへ往復変換して保存
メモ編集      : TextField ベースの自作エディタ（ソースモード）＋プレビュー分離
ファイル選択   : file_picker
引用処理      : pandoc（外部プロセス経由）
引用スタイル   : CSL（.cslファイル）
メタデータ取得 : CrossRef / OpenAlex / CiNii Research / J-STAGE
ローカルLLM   : OpenAI互換API（Ollama / LM Studio / Jan、base_url 切替）
```

> 変更履歴：
> - 2026-06(2)：原稿エディタを TextField から **WYSIWYG(appflowy_editor)** へ変更（原稿で `#` を露出させない要件）。メモ編集は従来のソースモードを維持。LLMを **OpenAI互換クライアント**に一般化（Ollama/LM Studio/Jan を base_url 切替で対応）。メタデータに **OpenAlex** を追加。実装順を**一気通貫優先**に再構成。
> - 2026-06：`pdfx` → `pdfrx`（pdfx はテキスト選択・注釈不可のためリーダーモードが成立しない）／`flutter_markdown` → `flutter_markdown_plus`（本家が公式に廃止）／Windows では `sqflite_common_ffi` が必須（起動時に `databaseFactory = databaseFactoryFfi`）

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

### 3. 原稿はWYSIWYG・保存は標準MD

```
✅ 原稿(draft.md)はWYSIWYGで編集し、# や ** を画面に出さない
✅ 読込＝MDをパースしてノードに展開、保存＝ノードを標準MDへ直列化（往復ロスレス）
✅ draft.md は標準Markdownが正本（Obsidian/他アプリで開いても破綻しない）
✅ メモ(notes.md)はソースモード＋プレビューでよい（Obsidian互換領域）
❌ エディタ内部のJSON表現を draft.md の代わりに保存しない
❌ Obsidian非互換のMarkdown拡張を出力しない
```

### 4. プラットフォーム分岐

```dart
// Windows では sqflite_common_ffi を初期化する
if (Platform.isWindows) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

// pandocやローカルLLMなどデスクトップ専用処理は必ずガードする
if (Platform.isMacOS || Platform.isWindows) {
  // pandoc出力・ローカルLLM処理
} else {
  // iOS：.mdプレビューのみ、出力ボタンを非表示
}
```

### 5. ObsidianのVaultと共存できること

```
✅ ノートはすべて標準Markdownで書く
✅ [[wikilink]] 記法は Obsidian 互換とする（将来の汎用ノート機能に向けて）
✅ フォルダ構成はiCloud Drive上の任意の場所を指定できる
❌ アプリ独自のバイナリ形式でノートを保存しない
```

### 6. ハイライトはオーバーレイ方式

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
│   └── {id}/        ← フォルダ名 = citation key（csl_json.id。例：tanaka2024）
│       ├── paper.pdf
│       └── meta.md  ← YAML frontmatter に CSL-JSON を含む
└── projects/
    └── {name}/
        ├── project.json
        ├── notes.md  ← ソースモード編集
        ├── draft.md  ← WYSIWYG編集・標準MD保存
        └── clips.json
```

---

## ローカルLLM連携

```
エンドポイント : POST {base_url}/v1/chat/completions（SSEストリーミング）
プリセット     : Ollama http://localhost:11434/v1 / LM Studio http://localhost:1234/v1 / Jan http://localhost:1337/v1
モデル選択     : 起動時 GET {base_url}/v1/models で一覧取得して選ばせる（Ollama は model 名完全一致が必要）
失敗時         : 「LLM未起動」をUIに明示。要約が失敗しても本体機能は継続
iOS           : localhostにLLMは無い → LAN内PCのIP:ポート指定 or 機能無効
```

---

## 引用フロー

```
@キーワード入力 → vault.sqlite から候補検索 → インライン引用チップ表示
draft.md への保存形式：pandoc標準の [@citation-key]（例：[@tanaka2024]）。これが正本
出力時：meta.md の frontmatter から refs.json を生成（YAML→JSON 変換のみ）
       pandoc draft.md --citeproc --bibliography=refs.json --csl=styles/{name}.csl -o output.docx
```

- **`--citeproc` は必須**（pandoc 2.11+。これがないと引用が解決されない）
- CSLスタイルの処理はすべてpandocに委譲。Dart側に引用ロジックを書かない
- YAML→JSON 変換器は「データ変換」であり引用ロジックではない（実装してよい）
  - YAML 1.1 の暗黙型変換（`no`→false 等）に注意。文字列は明示的に扱うこと
- **出力は docx を先行実装**。PDF出力は LaTeX エンジン依存が重いため後続フェーズ

---

## メタデータ取得の優先順位

```
1.   CrossRef API（DOI検出時）— User-Agent に連絡先 mailto を含める
1.5  OpenAlex API（CrossRef失敗/情報が薄い時の補完。キー不要）
2.   CiNii Research API（日本語論文・CiNii ID検出時）
3.   J-STAGE API（J-STAGE URL含む時）
4.   手動入力フォーム（フォールバック）
```

- ※旧 CiNii Articles は CiNii Research に統合済み。旧 `naid` エンドポイントは非推奨。実装直前に現行仕様を確認すること。

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
❌ WYSIWYGエディタの内部表現(JSON等)を draft.md の代わりに保存する（draft.mdは標準MDが正本）
```

---

## Dart / Flutter コーディング規約

- ファイル名：`snake_case.dart`
- クラス名：`PascalCase`
- Riverpodプロバイダーは `_provider` サフィックス
- 非同期処理は `AsyncValue` で状態管理
- プラットフォーム固有コードは `platform/` ディレクトリに分離
- ファイルI/O・CSL-JSON正規化・vault.sqlite再構築・MD往復は**ユニットテスト必須**

---

## Claude Code でのモデル使い分け

| 用途 | モデル | 例 |
|---|---|---|
| 設計判断・アーキテクチャ変更・複雑なリファクタ | Opus | データ構造の変更、同期ロジック、MD往復/エディタ設計 |
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
