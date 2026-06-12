# Atelier — 全体設計書

> 論文を管理し、読み、書くためのローカルファーストアプリ
> 最終更新：2026-06（技術スタック精査・汎用ノート構想を反映）

---

## 1. コンセプト

### 解決する問題

既存の論文管理アプリ（Zotero等）は「管理」と「参照」で止まっており、執筆との統合がない。日本語論文への対応も不十分。

```
論文を管理する → 読む → 書く
```

この全サイクルを1つのアプリ・1つのiCloudフォルダで完結させる。

### 設計思想

- **ローカルファースト**：ネット接続なしで全機能が動く。接続はiCloud同期とメタデータ取得時のみ
- **ファイルが真実の源**：PDFと.mdファイルがデータ本体。アプリが壊れてもファイルは残る
- **iCloud = 同期レイヤー**：Obsidianと同じ思想。アプリはローカルファイルを読み書きするだけ
- **Library / Project 分離**：論文はLibraryに一元管理。Projectは参照するだけでコピーしない
- **日本語論文対応**：CiNii / J-STAGE API による自動メタデータ取得
- **Obsidianと共存→将来は置換**：AtelierのノートはただのMarkdownファイル。ObsidianのVaultに同居でき、最終的にはVault全体をAtelierに移行する

### 将来ビジョン

Phase 1（論文管理・執筆）を核として、段階的に一般ノート機能を拡張していく。
最終的には**ObsidianのVault全体（既存の全MDファイル）をAtelierに移し、生活のすべてのアイデアをAtelierで完結させる**。
ただし現フェーズは論文機能の完成を最優先とする。汎用ノート機能の技術設計は「9.」にまとめ、現フェーズの実装がそれを妨げないようにする。

---

## 2. 技術スタック

| 層 | 技術 | 理由 |
|---|---|---|
| フレームワーク | Flutter 3.x | iOS / Mac / Windows を1コードベースで対応 |
| 言語 | Dart | Flutter標準 |
| PDF表示 | **pdfrx** | PDFiumベース。テキスト選択対応・全OS対応。旧候補pdfxは注釈・選択不可のため不採用 |
| データベース | sqflite (SQLite) + **sqflite_common_ffi** | インデックス・検索専用。Windowsはffi必須 |
| 状態管理 | Riverpod | Flutter標準的な選択 |
| Markdown表示 | **flutter_markdown_plus** | 本家flutter_markdownは2025年に公式廃止。その公式後継 |
| Markdown編集 | TextFieldベース自作（プレビュー分離型） | Obsidianのソースモード相当。Phase 6でリッチ化検討 |
| ファイル選択 | file_picker | iOS Files app / iCloud Drive 対応 |
| 引用処理エンジン | pandoc（外部プロセス） | CSL完全対応。Mac / Windows のみ |
| 引用スタイル | CSL（Citation Style Language） | 業界標準。.csl ファイルとして流通 |
| メタデータ取得 | CrossRef / CiNii / J-STAGE API | 無料。日本語論文対応 |

### プラットフォーム別機能差

| 機能 | Mac | Windows | iOS |
|---|---|---|---|
| ライブラリ管理 | ✅ | ✅ | ✅ |
| PDFリーダー | ✅ | ✅ | ✅ |
| ノート・原稿執筆 | ✅ | ✅ | ✅ |
| 引用スタイル管理 | ✅ | ✅ | ✅ |
| docx出力（pandoc） | ✅ | ✅ | ❌（pandoc不可） |
| PDF出力 | 後続フェーズ | 後続フェーズ | ❌ |
| AI要約（ローカルLLM） | ✅ | ✅ | ❌ |
| iCloud同期 | ✅ | ✅（iCloud for Windows） | ✅ |

- iOS は「読む・書く・メモする」場所。出力はMac / Windowsで行う自然な分業
- 出力は**docxを先行実装**。PDF出力はLaTeXエンジン（日本語はLuaLaTeX+フォント設定）への依存が重いため、Phase 3以降で `--pdf-engine` 対応を検討
- iOSのiCloud Driveフォルダ常時アクセスはsecurity-scoped bookmarkの永続管理が必要（既知のリスク。Phase 4で対処）

---

## 3. データ構造

### 配置の原則：プレーンファイルは同期、DBはローカル

SQLiteのDBファイル（特にWALモード）はクラウド同期と相性が悪く、部分同期・競合で破損しうる。
vault.sqlite はインデックス専用で.mdから再構築可能なため、**同期せず端末ごとにローカル保持**する。

```
【ローカル（各端末・同期しない）】
Application Support/Atelier/
└── vault.sqlite                  ← 全体インデックス。起動時にlibrary/を差分スキャンして更新

【iCloud Drive（同期対象）】
iCloud Drive / Atelier /
├── styles/                       ← CSLスタイルファイル置き場
│   ├── ipsj.csl
│   ├── apa-7th.csl
│   ├── ieee.csl
│   └── （ユーザー追加分）
├── library/                      ← 論文保管庫（グローバル・全Projectが参照）
│   ├── 2024_田中_音響/
│   │   ├── paper.pdf
│   │   └── meta.md               ← 要約・タグ・CSL-JSONメタデータ
│   └── 2023_Smith_NLP/
│       ├── paper.pdf
│       └── meta.md
└── projects/                     ← プロジェクト（作業単位）
    ├── 卒業論文_2025/
    │   ├── project.json          ← 参照論文IDリスト・引用スタイル設定
    │   ├── notes.md              ← 自由なメモ・アイデア・TODO
    │   ├── draft.md              ← 正式な原稿（引用整形・出力対象）
    │   └── clips.json            ← Libraryのハイライト参照（コピーでなくリンク）
    └── 学会発表_2025/
        ├── project.json
        ├── notes.md
        └── draft.md
```

### meta.md の構造

```markdown
---
csl_json:
  id: "tanaka2024"
  type: "article-journal"
  title: "都市環境における音風景の知覚と感情的評価に関する研究"
  author:
    - family: "田中"
      given: "太郎"
    - family: "鈴木"
      given: "花子"
  issued:
    date-parts: [[2024]]
  container-title: "情報処理学会論文誌"
  volume: "65"
  issue: "2"
tags: [サウンドスケープ, 知覚]
source: cinii
doi: ""
cinii_id: "AA12345678"
---

## AI要約

（ローカルLLMが生成した要約テキスト）

## 自分のメモ

（ユーザーの読書メモ）
```

### project.json の構造

```json
{
  "id": "graduation-2025",
  "name": "卒業論文 2025",
  "csl": "ipsj.csl",
  "refs": ["tanaka2024", "smith2023", "yamada2024"]
}
```

### clips.json の構造（ハイライト＝オーバーレイ方式）

PDFファイル自体には書き込まない。clips.json がハイライトの真実の源。

```json
{
  "clips": [
    {
      "id": "clip-001",
      "paper_id": "tanaka2024",
      "page": 3,
      "rects": [{"x": 0.12, "y": 0.34, "w": 0.6, "h": 0.02}],
      "text": "選択されたテキスト",
      "color": "yellow",
      "created": "2026-06-13"
    }
  ]
}
```

---

## 4. 機能設計：3モード

### 4-1. ライブラリモード（Library）

論文の保管・管理。

- PDF インポート（DOI / CiNii ID 自動認識 → メタデータ取得）
- タグ管理、著者・年・キーワード検索
- AI要約生成（Mac/Windows：Ollama API経由でローカルLLM）
- メタデータ手動編集（自動取得できなかった日本語論文向け）

### 4-2. リーダーモード（Reader）

PDFを読み、素材を蓄える。

- PDFビューア（pdfrxパッケージ。テキスト選択あり）
- ハイライト（色分け：黄＝重要、緑＝使いたい、青＝疑問）
- 選択テキスト＋座標 → clips.json に保存し、オーバーレイ描画
- サイドバーにメモ欄（meta.mdの「自分のメモ」セクションに書き込む）

### 4-3. ライタ―モード（Writer）

論文を書く。このモードが他のアプリにない核心。

**ノートタブ（notes.md）**
- 自由なMarkdownメモ（編集＝プレーンテキスト、プレビュー＝flutter_markdown_plus）
- `@田中2024` でLibraryの論文を参照タグとして挿入
- ObsidianのMarkdownと互換性あり

**原稿タブ（draft.md）**
- 引用整形を意識した執筆
- `@田中2024` と打つと引用サジェストが出現
- インライン引用チップとして表示
- 出力時：meta.md frontmatter → refs.json 生成 → pandoc → 選択中の.cslで整形 → 参考文献リスト自動生成

**右パネル（Library参照）**
- プロジェクトに紐づいた論文リスト
- 対象論文のclips（ハイライト）をパレットとして表示
- 論文名クリック → 該当PDFページを右パネルで表示

---

## 5. 引用スタイル管理

### 設計方針

`.csl` ファイルがデータ本体。アプリはどの`.csl`を使うかを管理するだけ。
処理はすべてpandocに委譲するため、Dart側に引用ロジックは不要。

```
project.json { "csl": "ipsj.csl" }
         ↓ 出力時
pandoc draft.md --bibliography=refs.json --csl=styles/ipsj.csl -o output.docx
```

### スタイルの3レイヤー

| レイヤー | 内容 |
|---|---|
| 同梱プリセット | 情報処理学会・APA 7th・IEEE・MLA・Chicago・電子情報通信学会 等 約30件 |
| オンライン追加 | GitHub CSL リポジトリ（10,000件以上）から検索・ダウンロード |
| カスタム | 既存.cslをベースに編集 / 外部から.cslをインポート |

### プロジェクトごとのスタイル設定

```
グローバル設定：APA 7th（デフォルト）
  └── 卒業論文プロジェクト：情報処理学会（上書き）
  └── 学会発表プロジェクト：IEICE（上書き）
  └── 未設定プロジェクト ：グローバル設定を継承
```

---

## 6. メタデータ取得フロー

```
PDFをインポート
  ├─ DOIが検出できる
  │    └─ CrossRef API → CSL-JSON取得 → meta.md生成
  ├─ CiNii IDが検出できる
  │    └─ CiNii API → CSL-JSON取得 → meta.md生成
  ├─ J-STAGEのURLが含まれる
  │    └─ J-STAGE API → CSL-JSON取得 → meta.md生成
  └─ 何も取得できない
       └─ 手動入力フォーム（著者・タイトル・誌名・年・巻号頁）
```

---

## 7. iOS 配布方法

公開・配布は行わない個人利用アプリ。

- ipaファイルをXcodeでビルド → 自端末にサイドロード
- Apple Developer Program（$99/年）またはXcode無料プロビジョニングで対応
- TestFlightでの自己配布も可

---

## 8. 実装優先順位

```
Phase 1：コア（Mac / Windows）
  - Flutterプロジェクトセットアップ（Windows: sqflite_common_ffi 初期化を含む）
  - iCloud Drive フォルダ読み書き＋vault.sqliteのローカル再構築処理
  - ライブラリモード（PDFインポート・メタデータ取得・一覧表示）
  - リーダーモード（pdfrxビューア・ハイライト→clips.json）

Phase 2：執筆
  - ライタ―モード（ノートタブ・原稿タブ）
  - @引用インライン挿入
  - pandoc出力（docx先行。PDFは後続）

Phase 3：引用スタイル管理
  - CSLバンドル
  - オンライン検索・ダウンロード
  - プロジェクト別スタイル設定
  - PDF出力（--pdf-engine / 日本語組版）の検討

Phase 4：iOS対応
  - file_picker経由でのiCloud Driveアクセス（security-scoped bookmark対応）
  - ipaビルド・サイドロード確認

Phase 5：AI統合
  - Ollama API経由でのローカルLLM要約
  - Mac / Windows のみ

Phase 6以降（将来拡張）
  - 汎用Markdownノート機能（→ 9. 参照）
  - Obsidian Vault全体の移行・段階的統合
```

---

## 9. 汎用ノート機能の技術スタック（Phase 6以降・実装即応用）

### ゴール

ObsidianのVaultにある全MDファイルをAtelierに移し、論文に限らないすべてのアイデア・知識をAtelierで完結させる。
**移行は「フォルダを開くだけ」で成立すること**（変換・インポート処理を不要にする）。

### 移行を保証する互換性要件（現フェーズから遵守）

```
✅ 標準Markdown（CommonMark + GFMテーブル）のみ
✅ [[wikilink]]・[[note#見出し]]・[[note|表示名]] のObsidian記法をサポート
✅ YAML frontmatter（tags, aliases 等）をObsidianと同じ解釈で読む
✅ #タグ のインライン記法
✅ 添付ファイルの相対パス参照（![[image.png]]）
❌ Atelier独自のMD拡張を導入しない
```

### 追加コンポーネントと技術選定

| 機能 | 技術 | 備考 |
|---|---|---|
| 全文検索 | SQLite **FTS5**（sqflite/ffi経由） | vault.sqliteにFTS仮想テーブルを追加。日本語はトークナイザ要検討（unicode61＋bigram自前 or trigram） |
| wikilinkパース | Dart自作パーサ（正規表現＋ASTレベル） | markdownパッケージのインライン構文拡張として実装 |
| バックリンク | vault.sqlite に links(from_id, to_id) テーブル | ファイル保存時に差分更新。表示はサイドパネル |
| ファイル監視 | watcher パッケージ | 外部編集（Obsidian併用期間中）の検知と再インデックス |
| タグインデックス | vault.sqlite に tags テーブル | frontmatter＋インライン#タグの両方を収集 |
| クイックスイッチャー | Cmd/Ctrl+O → FTS5あいまい検索 | Obsidianの基本操作を踏襲 |
| デイリーノート | テンプレート＋日付ファイル生成 | projects/外に notes/ ルートを新設 |
| グラフビュー | 任意（後回し可） | links テーブルから描画。CustomPainter または graphview パッケージ |
| エディタ強化 | super_editor 系を再評価 | Phase 6時点の成熟度で判断。それまではTextField＋プレビュー |

### フォルダ構成の拡張

```
iCloud Drive / Atelier /
├── styles/
├── library/        ← 論文（従来通り）
├── projects/       ← 論文プロジェクト（従来通り）
└── notes/          ← 汎用ノート（ObsidianのVaultをここに移す or 任意パス指定）
    ├── デイリー/
    ├── アイデア/
    └── （Obsidianのフォルダ構成をそのまま維持）
```

- vault.sqlite のインデックス対象に notes/ を追加するだけで、既存アーキテクチャ（ファイルが真実・DBはローカル再構築）がそのまま通用する
- 移行期はObsidianと同じフォルダを両アプリで開いて併用できる（watcherで整合性維持）

### 段階的移行プラン

```
Step 1：notes/ ルートの読み込み・一覧・編集（論文機能と同じエディタを流用）
Step 2：[[wikilink]] パース＋リンク先ジャンプ
Step 3：FTS5全文検索＋クイックスイッチャー
Step 4：バックリンク表示・タグブラウザ
Step 5：Obsidian Vaultを正式に移行（併用終了）
Step 6：グラフビュー等の任意機能
```

---

## 10. Claude Code 開発運用（モデル使い分け）

| 場面 | モデル | 理由 |
|---|---|---|
| アーキテクチャ設計・データ構造変更・同期/インデックス設計・エディタやFTS設計 | **Opus** | 設計判断の質が結果を左右する |
| 通常の画面実装・API連携・バグ修正・テスト作成・リファクタの実行 | **Sonnet** | 速度とコストのバランスが良い |

運用ルール：

- 迷ったらSonnetで開始し、設計が絡む議論になったら `/model` でOpusへ切替
- Phase跨ぎの作業・「9.」の汎用ノート機能の初期設計はOpusで計画→Sonnetで実装
- 大きな変更はplan modeで計画を提示→承認後に実装
- CLAUDE.md がこの設計書を `@DESIGN.md` で自動読み込みするため、リポジトリルートに両ファイルを置くこと
