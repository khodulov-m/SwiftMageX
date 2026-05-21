# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

macOS 専用の画像生成・処理 CLI。SwiftMageX は*オーケストレータ*で
あり、生成は Gemini API を呼び出し、ローカルなラスター処理(リ
サイズ、テキスト合成)は CoreImage / CoreText / ImageIO で実行し
ます。すべてが外部依存ちょうど 2 つの小さな Swift パッケージに収
まっています。同じコアライブラリが Model Context Protocol サーバ
(`swiftmagex-mcp`)を支え、AI エージェントが同じ機能をツールとし
て呼び出せます。

公式仕様は `SwiftMageX-MVP-0.1-spec.md`、v0.1.0 でリリースされた
内容は `RELEASE_NOTES.md` を参照してください。

## 必要要件

- Apple silicon(arm64)上の macOS 14+
- Swift 6.0+ ツールチェーン(Xcode 16+) — ソースからビルドする
  ときのみ必要
- `generate` コマンド用の Gemini API キーを
  `SWIFTMAGEX_GEMINI_API_KEY`(または `GEMINI_API_KEY`)に設定。
  `resize` と `text` にキーは不要です。

## インストール

### プリビルドバイナリ(推奨)

[v0.1.0 リリース](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0)
から `swiftmagex`、`swiftmagex-mcp`、`SHA256SUMS` を入手し、チェック
サムを検証してから `PATH` に置きます:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

Gatekeeper がダウンロードを検疫した場合は属性を削除します:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### ソースからビルド

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# 生成物は .build/arm64-apple-macosx/release/ に出力されます
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### インストールせずに実行

```sh
swift run swiftmagex <サブコマンド> …    # CLI
swift run swiftmagex-mcp                 # MCP サーバ(stdio トランスポート)
swift test                               # テストスイート全体
scripts/check.sh                         # ビルド + テストを一括実行
```

### 設定

シェルプロファイルで Gemini API キーをエクスポートします
(`generate` のみ必要):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # 推奨
# 代替として、ツールは以下も読み込みます:
export GEMINI_API_KEY="…"
```

リポジトリに入るスクリプトにキーを埋め込まないでください。CLI は
`--verbose` でも、出力ファイルのメタデータでも、キーを表示・ログ
化・ディスク書き込みすることはありません。

## クイックマニュアル

3 つのサブコマンドはいずれも同じグローバルフラグを共有します:

| グローバルフラグ | 効果 |
|---|---|
| `--json` | 構造化 JSON エンベロープを stdout に出力します(人間向けテキストの代わり)。 |
| `-v`、`--verbose` | 診断メッセージを stderr に出します。API キーは**含まれません**。 |
| `--version` | `0.1.0` を出力して終了します。 |
| `-h`、`--help` | コマンドのヘルプを表示します。 |

`--json` 出力と MCP ツールの結果に含まれる出力パスは常に
**絶対パス**です。エージェントは作業ディレクトリを知らなくて構い
ません。

### `swiftmagex generate` — Gemini によるテキストから画像

```
swiftmagex generate <prompt> [オプション]
```

| オプション | 既定値 | 補足 |
|---|---|---|
| `<prompt>` | — | 必須の位置引数。 |
| `-o`、`--output <path>` | `./` | ファイルまたはディレクトリ。ディレクトリ指定時は `swiftmagex_{timestamp}_{index}.png` の名前で出力されます。 |
| `-s`、`--size <square\|portrait\|landscape>` | `square` | アスペクト比のヒント。実際の解像度はモデル次第。 |
| `-n`、`--count <1–4>` | `1` | バリアント数。各バリアントは別リクエスト。 |
| `--seed <uint64>` | — | プロバイダが無視してもメタデータに記録します。 |
| `--model <id>` | `gemini-2.5-flash-image` | プレビュー品質は `gemini-3.1-flash-image-preview`。 |

```sh
# 1 枚を現在のディレクトリに出力
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# 横長 4 枚をディレクトリに、構造化出力
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# 再現性のある seed(プロバイダ依存)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

例 — 以下のコマンドで下の画像を生成しました(`gemini-2.5-flash-image`
による 1024×1024 PNG):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="白い背景の赤いリンゴ(生成画像)" width="320" />

各 PNG の出力には、`tEXt` チャンクとして prompt、モデル、seed、
タイムスタンプ、ツールバージョンが埋め込まれます(JPEG は EXIF の
`UserComment` フィールドを使用)。

### `swiftmagex resize` — ローカルのリサイズ / クロップ / 変換

```
swiftmagex resize <input> [オプション]
```

| オプション | 既定値 | 補足 |
|---|---|---|
| `<input>` | — | PNG、JPEG、HEIC、WebP。書き出しは PNG / JPEG のみ。 |
| `-w`、`--width <px>` | — | width / height のどちらかは必須。 |
| `-h`、`--height <px>` | — | 片方だけ指定するともう片方はアスペクト比から計算。 |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` と `fill` には両方の寸法が必要。 |
| `-o`、`--output <path>` | ソースと同じ場所 | デフォルトはソースの隣。 |
| `--format <png\|jpeg>` | ソースに合わせる | HEIC / WebP のソースは既定で PNG にフォールバック。 |
| `--quality <0.0–1.0>` | `0.9` | JPEG のみ。 |

```sh
# 正方形サムネイル、はみ出しはクロップ
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# 幅 1200 のバナーを JPEG 80% で再エンコード
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# 半分のサイズ、比率維持(幅のみ指定)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — テキスト合成

```
swiftmagex text <input> --text "<文字列>" [オプション]
```

| オプション | 既定値 | 補足 |
|---|---|---|
| `<input>` | — | 上に描画するソース画像。 |
| `--text <文字列>` | — | 必須。`\n` で改行、長い行は単語単位で折り返し。 |
| `--position` | `bottom` | `top`、`center`、`bottom`、`top-left`、`top-right`、`bottom-left`、`bottom-right` のいずれか。 |
| `--font <名前>` | システムフォント | 例: `"Helvetica-Bold"`。 |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` または `#RRGGBBAA`。 |
| `--stroke <hex>` | — | 省略すると縁取りなし。 |
| `--stroke-width <pt>` | `2.0` | `--stroke` 指定時のみ有効。 |
| `-o`、`--output <path>` | ソースと同じ場所 | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### JSON 出力スキーマ

`--json` ですべてのコマンドが同じエンベロープを返します。キーは
ソート済み、nil フィールドは丸ごと省略されます(`null` プレース
ホルダはありません)。

成功:

```json
{
  "command": "generate",
  "model": "gemini-2.5-flash-image",
  "outputs": [
    { "format": "png", "height": 1024, "path": "/abs/out/swiftmagex_…_1.png", "width": 1024 }
  ],
  "provider": "gemini",
  "status": "ok"
}
```

エラー(`resize` と `text` は `provider` / `model` を省略):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

ストリーム規約:結果 → **stdout**、診断(`--verbose`)→
**stderr**。`--json` 下のエラー JSON も stdout に出力され、エー
ジェントは 1 つのストリームで解析できます。

### 終了コード

| コード | 意味 | 例 |
|---|---|---|
| `0` | 成功 | — |
| `1` | 想定外 / ラスター / I/O 失敗 | 入力ファイル読み込み不可、エンコーダ失敗 |
| `2` | 入力不正 | `--fit` の不正組み合わせ、不正な hex 色、`--count` が 1–4 外 |
| `3` | プロバイダ / API 失敗 | Gemini の 5xx、5 回リトライ後の `429` |
| `4` | 設定 | `SWIFTMAGEX_GEMINI_API_KEY` が未設定 |

429 リトライポリシー: 最大 5 回、指数バックオフ
1 s → 2 s → 4 s → 8 s → 16 s。

## MCP サーバ

`swiftmagex-mcp` は stdio 上で 3 つのツール
(`generate_image`、`resize_image`、`overlay_text`)を提供します。
引数は CLI フラグと対応しており、結果は絶対パスを返すので、呼び出
し側エージェントはサーバの作業ディレクトリを知る必要がありません。
`generate_image` は加えて、生成された画像のバイト列を MCP の
`image` コンテンツとして返し、呼び出し側モデルが出力結果を直接確
認できます。

### Claude Code を設定する

Claude Code は `claude mcp add` で MCP サーバを登録します。SwiftMageX
を使いたいリポジトリの中で実行してください:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

このマシン上のすべての Claude Code セッションで利用したい場合は
ユーザースコープを使います:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

登録済みの確認は `claude mcp list` か `claude mcp get swiftmagex`、
削除は `claude mcp remove swiftmagex`。既定のトランスポートは stdio
なので `--transport` フラグは不要です。

### Claude Desktop を設定する

`~/Library/Application Support/Claude/claude_desktop_config.json`
にエントリを追加します:

```json
{
  "mcpServers": {
    "swiftmagex": {
      "command": "/usr/local/bin/swiftmagex-mcp",
      "env": {
        "SWIFTMAGEX_GEMINI_API_KEY": "your-key-here"
      }
    }
  }
}
```

`env` ブロックにより API キーはこのサーバにのみ渡され、クライアン
トの一般的な環境変数には残りません。

## トラブルシューティング

| 症状 | 原因の可能性 | 対処 |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY`(終了コード 4) | `generate` や `generate_image` 実行時に API キーが環境にない。 | `SWIFTMAGEX_GEMINI_API_KEY`(または代替の `GEMINI_API_KEY`)をエクスポート。MCP の場合はクライアントの `env` ブロックに記述(上記参照)。 |
| `Provider error: quota exhausted after 5 retries`(終了コード 3) | バックオフ窓(1 s → 16 s)内のすべての試行で Gemini が `429` を返した。 | クォータの回復を待つ、プロジェクトを切り替える、または後ほど再実行。バックオフ間隔は固定(仕様 §13)。 |
| `I/O error: input file not found: /…/foo.png`(終了コード 1) | `resize` / `text`(または `resize_image` / `overlay_text`)に渡したパスが存在しないか読み取り不可。 | 絶対パスを使い、権限と形式(PNG / JPEG / HEIC / WebP、書き出しは PNG / JPEG のみ)を確認。 |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | ダウンロードしたバイナリに Gatekeeper の検疫が付与されている。 | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex`(`swiftmagex-mcp` も同様)。 |

## スコープと状態

これは 0.1 MVP — 3 つのコマンド、1 つのプロバイダ(Gemini)、
1 つの MCP サーバです。それ以外はすべて延期されています。スコープ
外の項目一覧は仕様
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
を参照(edit / インペイント、ローカルプロバイダ、Homebrew 配布、
設定ファイル、Keychain、…)。

## ライセンス

TBD。
