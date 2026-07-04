# Atelier — 全体設計書

> 論文を管理し、読み、書くためのローカルファーストアプリ
> 最終更新：2026-06（原稿エディタをWYSIWYG化／実装順を一気通貫優先に再構成／LLMをOpenAI互換に一般化／OpenAlex・CiNii Research注記を追加）

---

## 1. コンセプト

### 解決する問題

既存の論文管理アプリ（Zotero等）は「管理」と「参照」で止まっており、執筆との統合がない。日本語論文への対応も不十分。

```
論文を管理する → 読む → 書く
```

この全サイクルを1つのアプリ・1つのiCloudフォルダで完結させる。**MVPはこの「管理→執筆→出力」の縦の背骨を一本通すことを最優先**とする。

### 設計思想

- **ローカルファースト**：ネット接続なしで全機能が動く。接続はiCloud同期とメタデータ取得時のみ
- **ファイルが真実の源**：PDFと.mdファイルがデータ本体。アプリが壊れてもファイルは残る
- **iCloud = 同期レイヤー**：Obsidianと同じ思想。アプリはローカルファイルを読み書きするだけ
- **Library / Project 分離**：論文はLibraryに一元管理。Projectは参照するだけでコピーしない
- **原稿は WYSIWYG・保存は標準MD**：原稿執筆では `#` 等の記法を画面に出さない。ただし draft.md は標準Markdownのまま保存し、エディタ内部表現を永続化しない
- **日本語論文対応**：CiNii Research / J-STAGE API による自動メタデータ取得
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
| 原稿執筆エディタ | **WYSIWYG（appflowy_editor）** | `#` 等の記法を画面に出さず装飾ブロックで表示。MD入出力対応。代替候補 super_editor。**保存は標準MD（draft.md）が正本**で、エディタJSONは永続化しない |
| メモ編集 | TextFieldベース自作（ソースモード）＋プレビュー分離 | notes.md 用。Obsidianのソースモード相当。`#` 可視で構わない領域 |
| ファイル選択 | file_picker | iOS Files app / iCloud Drive 対応 |
| 引用処理エンジン | pandoc（外部プロセス） | CSL完全対応。Mac / Windows のみ |
| 引用スタイル | CSL（Citation Style Language） | 業界標準。.csl ファイルとして流通 |
| メタデータ取得 | CrossRef / OpenAlex / CiNii Research / J-STAGE API | 無料。CrossRef→OpenAlexで英語論文を堅牢化、CiNii/J-STAGEで日本語論文対応 |
| ローカルLLM | **OpenAI互換API（Ollama / LM Studio / Jan）** | 3者とも `/v1/chat/completions` を提供。base_url と model を設定で切替え1実装で対応。Mac/Windowsのみ |

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
- ローカルLLMはMac/Windowsのlocalhost（Ollama:11434 / LM Studio:1234 / Jan:1337）を既定とし、設定でbase_urlを上書き可能にする。iOSはLAN内PCのIP:ポートを指定するか機能無効

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
│   │                                ※フォルダ名 = citation key（csl_json.id）に統一。
│   │                                  project.json の refs・[@key] 引用・vault再構築が同じキーで解決できる
│   ├── tanaka2024/
│   │   ├── paper.pdf
│   │   └── meta.md               ← 要約・タグ・CSL-JSONメタデータ
│   └── smith2023/
│       ├── paper.pdf
│       └── meta.md
└── projects/                     ← プロジェクト（作業単位）
    ├── 卒業論文_2025/
    │   ├── project.json          ← 参照論文IDリスト・引用スタイル設定
    │   ├── notes.md              ← 自由なメモ・アイデア・TODO（ソースモード編集）
    │   ├── draft.md              ← 正式な原稿（WYSIWYG編集・標準MD保存・引用整形/出力対象）
    │   └── clips.json            ← Libraryのハイライト参照（コピーでなくリンク）
    └── 学会発表_2025/
        ├── project.json
        ├── notes.md
        └── draft.md
```

> 補足：draft.md は WYSIWYG エディタで編集するが、保存形式は**標準Markdownのまま**（正本）。エディタは読込時にMDをパースしてノードに展開し、保存時に標準MDへ直列化する。Obsidianや他アプリで開いても破綻しないこと。

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
- AI要約生成（Mac/Windows：OpenAI互換API経由でローカルLLM）
- メタデータ手動編集（自動取得できなかった日本語論文向け）

### 4-2. リーダーモード（Reader）

PDFを読み、素材を蓄える。

- PDFビューア（pdfrxパッケージ。テキスト選択あり）
- ハイライト（色分け：黄＝重要、緑＝使いたい、青＝疑問）
- 選択テキスト＋座標 → clips.json に保存し、オーバーレイ描画
- 2ページ見開き表示（PdfViewerParams のページレイアウトで対応）
- サイドバーにメモ欄（meta.mdの「自分のメモ」セクションに書き込む）

### 4-3. ライタ―モード（Writer）

論文を書く。このモードが他のアプリにない核心。

**ノートタブ（notes.md）**
- 自由なMarkdownメモ（編集＝プレーンテキスト/ソースモード、プレビュー＝flutter_markdown_plus）
- `@田中2024` でLibraryの論文を参照タグとして挿入
- ObsidianのMarkdownと互換性あり（`#` 可視で構わない領域）

**原稿タブ（draft.md）**
- **WYSIWYG編集**：見出し・強調・引用などは装飾ブロックとして表示し、`#`・`**` 等の記法を画面に出さない
- `@田中2024` と打つと引用サジェストが出現 → インライン引用チップとして表示
- 引用チップの保存形式は pandoc 標準の **`[@citation-key]`**（例：`[@tanaka2024]`）。draft.md ではこの形式が正本（Obsidianではただのテキストとして無害に表示される）
- **保存は標準Markdown（draft.md）**。エディタ内部のJSON表現は永続化しない。読込＝MD→ノード木、保存＝ノード木→標準MD。**往復ロスレス**が要件（テスト対象）
- ソースモードへの切替トグルを併設（生MDを直接編集できる退避手段）
- 出力時：meta.md frontmatter → refs.json 生成 → pandoc → 選択中の.cslで整形 → 参考文献リスト自動生成

**右パネル（Library参照）**
- プロジェクトに紐づいた論文リスト
- 対象論文のclips（ハイライト）をパレットとして表示
- 論文名クリック → 該当PDFページを右パネルで表示

> WYSIWYG実装の最重要リスク = MD往復ロスレス。代表的記法（見出し/箇条書き/強調/引用/コード/`@key`引用）の往復テストを最優先で用意する。Obsidian非互換の独自記法を出力しないこと。appflowy_editorで破綻する場合のみ super_editor を再評価。

---

## 5. 引用スタイル管理

### 設計方針

`.csl` ファイルがデータ本体。アプリはどの`.csl`を使うかを管理するだけ。
処理はすべてpandocに委譲するため、Dart側に引用ロジックは不要。

```
project.json { "csl": "ipsj.csl" }
         ↓ 出力時
pandoc draft.md --citeproc --bibliography=refs.json --csl=styles/ipsj.csl -o output.docx
（--citeproc は必須。pandoc 2.11+ ではこれがないと引用が解決されない）
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
  │    ├─ CrossRef API → CSL-JSON取得 → meta.md生成
  │    └─ 取得失敗/情報が薄い → OpenAlex API（DOI: 指定・キー不要）で補完
  ├─ CiNii IDが検出できる
  │    └─ CiNii Research API → CSL-JSON取得 → meta.md生成
  ├─ J-STAGEのURLが含まれる
  │    └─ J-STAGE API → CSL-JSON取得 → meta.md生成
  └─ 何も取得できない
       └─ 手動入力フォーム（著者・タイトル・誌名・年・巻号頁）
```

- CrossRef は polite pool 利用のため User-Agent に連絡先 mailto を含める。
- ※注意：旧「CiNii Articles」は CiNii Research に統合済み。旧 `naid` ベースのエンドポイントは非推奨のため、実装直前に現行 CiNii Research API 仕様を確認すること。
- 日本語論文の日英併記メタデータは可能な限りロスせず保持し、pandoc に渡す段で出力スタイルに応じた言語に落とす。

---

## 7. iOS 配布方法

公開・配布は行わない個人利用アプリ。

- ipaファイルをXcodeでビルド → 自端末にサイドロード
- Apple Developer Program（$99/年）またはXcode無料プロビジョニング（7日で失効）で対応
- TestFlightでの自己配布も可

---

## 8. 実装優先順位（一気通貫を最優先）

```
Phase 1：一気通貫スパイン（管理 → 執筆 → 出力）Mac / Windows
  目標デモ = 「1論文を登録（DOI自動取得）→ それを引用した原稿をWYSIWYGで書く → 引用解決済みdocxを出力」が一本で通る
  - Flutterプロジェクトセットアップ（Windows: sqflite_common_ffi 初期化を含む）
  - iCloud Drive フォルダ読み書き ＋ vault.sqlite のローカル再構築処理
    （受け入れ：vault.sqliteを削除しても library/meta.md から完全再構築できる）
  - ライブラリ：PDFインポート・メタデータ取得（CrossRef→OpenAlex→CiNii/J-STAGE→手動）・一覧
  - リーダー：PDF表示のみ（執筆中に参照できる程度。ハイライトはPhase 2）
  - ライター：原稿タブ（WYSIWYG・#非表示・標準MD保存）＋ @引用インライン挿入
  - 出力：pandoc出力（docx先行。引用整形・参考文献リスト）

Phase 2：精読・メモ
  - リーダー：ハイライト→clips.json・オーバーレイ描画・色分け・2ページ見開き
  - ライター：ノートタブ（notes.md ソースモード＋プレビュー）・@参照

Phase 3：引用スタイル管理
  - CSLバンドル
  - オンライン検索・ダウンロード
  - プロジェクト別スタイル設定
  - PDF出力（--pdf-engine / 日本語組版 LuaLaTeX）の検討

Phase 4：iOS対応
  - file_picker経由でのiCloud Driveアクセス（security-scoped bookmark対応）
  - ipaビルド・サイドロード確認

Phase 5：AI統合
  - OpenAI互換API経由のローカルLLM要約（Ollama / LM Studio / Jan を base_url 切替で）
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
❌ Atelier独自のMD拡張を導入しない（原稿WYSIWYGの出力も標準MDに限る）
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
| 汎用ノートのリッチ編集 | 原稿WYSIWYG（appflowy_editor）を流用 or 拡張 | 論文原稿で確立した往復ロスレス基盤を再利用 |

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
| アーキテクチャ設計・データ構造変更・同期/インデックス設計・エディタ(MD往復)やFTS設計 | **Opus** | 設計判断の質が結果を左右する |
| 通常の画面実装・API連携・バグ修正・テスト作成・リファクタの実行 | **Sonnet** | 速度とコストのバランスが良い |

運用ルール：

- 迷ったらSonnetで開始し、設計が絡む議論になったら `/model` でOpusへ切替
- Phase跨ぎの作業・「9.」の汎用ノート機能の初期設計はOpusで計画→Sonnetで実装
- 大きな変更はplan modeで計画を提示→承認後に実装
- CLAUDE.md がこの設計書を `@DESIGN.md` で自動読み込みするため、リポジトリルートに両ファイルを置くこと
