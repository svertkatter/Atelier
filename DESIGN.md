# Atelier — 全体設計書

> 論文を管理し、読み、書くためのローカルファーストアプリ  
> 最終更新：2025-05

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
- **Obsidianと共存**：AtelierのノートはただのMarkdownファイル。ObsidianのVaultに同居できる

### 将来ビジョン

Phase 1（論文管理・執筆）を核として、段階的に一般ノート機能を拡張していく。  
最終的にはObsidianを置き換えうる「生活のすべてのアイデアをまとめるアプリ」を目指す。  
ただし現フェーズは論文機能の完成を最優先とする。

---

## 2. 技術スタック

| 層 | 技術 | 理由 |
|---|---|---|
| フレームワーク | Flutter 3.x | iOS / Mac / Windows を1コードベースで対応 |
| 言語 | Dart | Flutter標準 |
| PDF表示 | pdfx | Flutter向け最有力パッケージ |
| データベース | sqflite (SQLite) | インデックス・検索専用。ローカル |
| 状態管理 | Riverpod | Flutter標準的な選択 |
| Markdown表示/編集 | flutter_markdown | |
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
| PDF / Word 出力 | ✅ | ✅ | ❌（pandoc不可） |
| AI要約（ローカルLLM） | ✅ | ✅ | ❌ |
| iCloud同期 | ✅ | ✅（iCloud for Windows） | ✅ |

iOS は「読む・書く・メモする」場所。出力はMac / Windowsで行う自然な分業。

---

## 3. データ構造

### iCloud Drive上のフォルダ構成

```
iCloud Drive / Atelier /
├── vault.sqlite                  ← 全体インデックス（タグ・検索・引用キー）
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

- PDFビューア（pdfxパッケージ）
- ハイライト（色分け：黄＝重要、緑＝使いたい、青＝疑問）
- ハイライト → clips.json に自動保存（コピーでなくページ参照）
- サイドバーにメモ欄（meta.mdの「自分のメモ」セクションに書き込む）

### 4-3. ライタ―モード（Writer）

論文を書く。このモードが他のアプリにない核心。

**ノートタブ（notes.md）**
- 自由なMarkdownメモ
- `@田中2024` でLibraryの論文を参照タグとして挿入
- ObsidianのMarkdownと互換性あり

**原稿タブ（draft.md）**
- 引用整形を意識した執筆
- `@田中2024` と打つと引用サジェストが出現
- インライン引用チップとして表示
- 出力時に pandoc → 選択中の.cslで整形 → 参考文献リスト自動生成

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
pandoc draft.md --bibliography=refs.json --csl=styles/ipsj.csl -o output.pdf
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
  - Flutterプロジェクトセットアップ
  - iCloud Drive フォルダ読み書き
  - ライブラリモード（PDFインポート・メタデータ取得・一覧表示）
  - リーダーモード（PDFビューア・ハイライト）

Phase 2：執筆
  - ライタ―モード（ノートタブ・原稿タブ）
  - @引用インライン挿入
  - pandoc出力（PDF・Word）

Phase 3：引用スタイル管理
  - CSLバンドル
  - オンライン検索・ダウンロード
  - プロジェクト別スタイル設定

Phase 4：iOS対応
  - file_picker経由でのiCloud Driveアクセス
  - ipaビルド・サイドロード確認

Phase 5：AI統合
  - Ollama API経由でのローカルLLM要約
  - Mac / Windows のみ

Phase 6以降（将来拡張）
  - 一般Markdownノート機能
  - Obsidianとの共存・段階的統合
```
