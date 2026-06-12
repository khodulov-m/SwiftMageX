# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**ターミナルから直接、画像の生成・編集・仕上げを — そして同じことを
AI エージェントにも教えましょう。** SwiftMageX はネイティブな macOS
CLI です。生成と編集は Google の画像モデル(Gemini と Imagen)が担い、
日常的なラスター処理はあなたの Mac 上で直接実行されます。

得られるもの:

- 🎨 **生成も編集もコマンド 1 つで** — テキストから画像、画像から画像、
  複数画像の合成、マスクによるインペインティング。モデルは呼び出しごと
  に品質要件へ合わせて選べます。
- 🤖 **画像を扱える Claude Code** — 同梱の MCP サーバ
  (`swiftmagex-mcp`)がすべての機能をツールとして公開するので、Claude
  Code、Claude Desktop、任意の MCP クライアントがワークフローの中で
  画像の生成・編集・加工を行えるようになります。
- 📱 **App Store スクリーンショットをワンランで** — スクリーンショット
  をデバイスベゼルにはめ込み、背景に載せ、キャプションを添えて、App
  Store Connect の各サイズへ一括リサイズ。
- 🔒 **大事なところはプライベートかつ無料** — リサイズ、テキスト合成、
  画像合成、背景除去、スマートクロップは CoreImage / CoreText / Vision
  により完全にオンデバイスで動作。API キー不要、データは Mac の外に
  出ません。
- 🪶 **フットプリントは最小限** — 小さな Swift パッケージ 1 つ、外部
  依存はちょうど 2 つ、自己完結したバイナリ 2 本。

公式仕様は `SwiftMageX-MVP-0.1-spec.md`、v0.2.0 でリリースされた
内容は `RELEASE_NOTES.md` を参照してください。

## 必要要件

- Apple silicon(arm64)上の macOS 14+
- Swift 6.0+ ツールチェーン(Xcode 16+) — ソースからビルドする
  ときのみ必要
- `generate` コマンド用の Google AI API キーを
  `SWIFTMAGEX_GEMINI_API_KEY`(または `GEMINI_API_KEY`)に設定。
  Gemini と Imagen の両方の生成に使えます。`resize`、`text`、
  `composite`、`appstore`、`remove-bg`、`crop`、`icon` にキーは不要です。

## インストール

### プリビルドバイナリ(推奨)

[v0.2.0 リリース](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.2.0)
から `swiftmagex`、`swiftmagex-mcp`、`SHA256SUMS` を入手し、チェック
サムを検証してから `PATH` に置きます:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.2.0
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

8 つのサブコマンドはいずれも同じグローバルフラグを共有します:

| グローバルフラグ | 効果 |
|---|---|
| `--json` | 構造化 JSON エンベロープを stdout に出力します(人間向けテキストの代わり)。 |
| `-v`、`--verbose` | 診断メッセージを stderr に出します。API キーは**含まれません**。 |
| `--cache-dir <パス>` | `generate`/`edit` のレスポンスを `<パス>` にキャッシュし、同一入力では API を呼ばずに記録済みのプロバイダバイトを再生します。オプトイン — 下のキャッシュ節を参照。 |
| `--version` | `0.2.0` を出力して終了します。 |
| `-h`、`--help` | コマンドのヘルプを表示します。 |

`--json` 出力と MCP ツールの結果に含まれる出力パスは常に
**絶対パス**です。エージェントは作業ディレクトリを知らなくて構い
ません。

### `swiftmagex generate` — Gemini または Imagen によるテキストから画像

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
| `--model <id>` | `gemini-2.5-flash-image` | 組み込み: Gemini ファミリ(`gemini-2.5-flash-image`、`gemini-3-pro-image-preview`、`gemini-3.1-flash-image-preview`)と Imagen ファミリ(`imagen-4.0-generate-001`、`imagen-4.0-fast-generate-001`、`imagen-4.0-ultra-generate-001`)。未知の ID は `imagen-` / `gemini-` プレフィックスでルーティングされます。 |

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

**品質要件に合わせてモデルを選んでください。** モデルは `--model` で
呼び出しごとに切り替えられ、コマンドの他の部分は一切変わりません。
デフォルトの `gemini-2.5-flash-image` は安定したオールラウンダーです。
最新の `gemini-3.1-flash-image-preview` は明らかにディテールの豊かな
結果を生成し、横長の非正方形フレーミングを自律的に選びます。Imagen
ファミリーはアスペクト比を明示的に制御できます(`--size` が
`aspectRatio` に変換されます)。`imagen-4.0-fast-generate-001` は速度
重視、`imagen-4.0-ultra-generate-001` は最高品質重視です(1 回の呼び
出しにつき 1 枚)。例えば、`gemini-3.1-flash-image-preview` は次の
1408×768 のフレームを生成しました:

```sh
swiftmagex generate "A red fox curled up on a mossy rock in a misty autumn forest, golden leaves falling, soft photorealistic style" \
  --model gemini-3.1-flash-image-preview -o fox.png
```

<img src="docs/images/example-generate-fox-gemini31.png" alt="gemini-3.1-flash-image-preview が生成した秋の森のキツネの詳細な画像" width="480" />

### `swiftmagex edit` — Gemini による image-to-image / マルチ画像 / インペインティング

ソース画像(さらに追加の参照画像とオプションのマスク)を、テキスト
プロンプトと一緒に Gemini モデルへ送信します。各画像は `generate` が
使っているのと同じ `:generateContent` 呼び出しの中で `inlineData` パート
として同梱されます —— 新しいエンドポイントも、新しい依存も必要ありません。

```
swiftmagex edit <input> <prompt> [オプション]
```

| オプション | 既定値 | 補足 |
|---|---|---|
| `<input>` | — | 必須。プライマリのソース画像(PNG または JPEG)。 |
| `<prompt>` | — | 必須。編集内容を記述するテキスト指示。 |
| `--reference <パス>` | — | 繰り返し可。追加の参照画像(PNG または JPEG)。`--reference` を指定するたびに別の inline 画像パートが追加され、プロンプトがそれらを組み合わせて利用できます —— 例:「画像 1 の被写体を画像 2 のシーンに配置する」。 |
| `--mask <パス>` | — | 任意のグレースケール/二値マスク(PNG または JPEG)。白がプライマリ画像上の編集領域、黒が保持領域。 |
| `-o`、`--output <パス>` | `./` | ファイルまたはディレクトリ。ディレクトリ指定時のファイル名は `swiftmagex_{timestamp}_{index}.png`。 |
| `-n`、`--count <1–4>` | `1` | バリアント数。各バリアントは個別のリクエスト。 |
| `--seed <uint64>` | — | プロバイダーが無視する場合でもメタデータには記録されます。 |
| `--model <id>` | `gemini-2.5-flash-image` | Gemini モデルである必要があります —— Imagen の `:predict` 形式は inline 画像入力を受け付けず、終了コード 2 で拒否されます。 |

```sh
# 被写体の色を変える
swiftmagex edit apple.png "make the apple green instead of red" -o edited.png

# マスクを使って局所的にインペイント
swiftmagex edit photo.png "replace the marked region with a sunset sky" \
  --mask sky-mask.png -o photo_edited.png

# 2 枚の参照画像でコンポジション
swiftmagex edit person.png "place the person from image 1 into the scene of image 2" \
  --reference street.png -o composed.png

# 同じ編集の 4 バリアント
swiftmagex edit shot.jpg "add a snowy mountain in the background" -n 4 -o ./out
```

例 —— 3 つの編集前/編集後ペア(ソースと編集結果は [`examples/`](examples) に):

| ソース | 編集後 | 編集プロンプト |
|---|---|---|
| <img src="examples/apple.png" alt="白い背景の赤いリンゴ" width="200"> | <img src="examples/apple-edited.png" alt="鮮やかな緑に塗り替えたリンゴ" width="200"> | `"Change the apple's color from red to bright green, keep everything else identical"` |
| <img src="examples/mountain.png" alt="日の出の山岳湖" width="200"> | <img src="examples/mountain-edited.png" alt="同じシーンに熱気球が浮かぶ" width="200"> | `"Add a single colorful hot-air balloon floating in the sky above the mountains"` |
| <img src="examples/cabin.png" alt="夏の森の木製キャビン" width="200"> | <img src="examples/cabin-edited.png" alt="雪に覆われた同じキャビン" width="200"> | `"Transform the scene from a sunny summer day to a snowy winter day"` |

マルチ画像コンポジション — `--reference` で被写体とシーンを組み合わせる:

| 入力(被写体) | 参照(シーン) | 結果 |
|---|---|---|
| <img src="examples/canoe.png" alt="白い背景の木製カヌー" width="200"> | <img src="examples/mountain.png" alt="日の出の山岳湖" width="200"> | <img src="examples/canoe-on-mountain-lake.png" alt="山岳湖の水面に浮かぶカヌー" width="200"> |

```sh
swiftmagex edit examples/canoe.png \
  "Place the canoe from image 1 onto the lake from image 2, match the lighting and add reflections" \
  --reference examples/mountain.png -o examples/canoe-on-mountain-lake.png
```

編集後の出力にも `generate` と同じ `tEXt`/EXIF メタデータが入ります ——
記録される prompt は編集指示であり、元の生成プロンプトではありません。

### レスポンスキャッシュ

`generate` または `edit` に `--cache-dir <パス>` を渡すと、同じリクエストが
すでに処理されている場合にネットワーク呼び出しをショートカットできます。
キャッシュは content-addressed で、キーは model・prompt・size・count・seed
と、各 reference 画像・mask のバイト列の SHA-256 を合わせた SHA-256 です。
ヒット時にはディスクからバイトを再生し、それでも出力ファイルは新しい
`tEXt`/EXIF メタデータ(タイムスタンプ、ツールバージョン)とともに書き
出されるので、下流のパイプラインの挙動は変わりません。

```sh
# 1 回目は API を叩き、2 回目は /tmp/sx-cache から再生されます。
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache --json
# → 再生された画像ごとに JSON 出力で "cached": true
```

注意点:

- **あえて opt-in。** Gemini は `--seed` を尊重しないので、同じ入力でも
  呼び出しごとに*変化することが意図されています*。キャッシュヒットは
  その意図的な非決定性を「毎回同じバイト」に黙って置き換えてしまいます。
  それが望む挙動のときだけ `--cache-dir` を渡してください。
- **ベストエフォート。** キャッシュの I/O 失敗(書き込めないディレクトリ、
  破損エントリ)はコマンドを中断せず、通常のネットワーク呼び出しに
  フォールバックします。
- **eviction なし。** キャッシュはディレクトリを `rm -rf` するまで成長
  し続けます。
- キャッシュが効くのは `generate` / `edit` のみ(ローカルラスター系
  コマンドはプロバイダを呼びません)。MCP サーバーは 0.1 ではキャッシュ
  を公開せず、CLI フラグが唯一の入口です。

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

### `swiftmagex composite` — 画像を別の画像に合成

```
swiftmagex composite <背景> --overlay <前景> [オプション]
```

| オプション | デフォルト | 備考 |
|---|---|---|
| `<背景>` | — | キャンバスとなる画像。 |
| `--overlay <パス>` | — | 必須。上に重ねる前景(アルファを尊重)。 |
| `--position` | `center` | `text` と同じ 7 つのアンカー。 |
| `--scale <比率>` | `1.0` | 背景に対する前景のサイズ比。アスペクト比は保持。 |
| `--offset-x`, `--offset-y <px>` | `0` | アンカーからのずらし量(正 = 右 / 下)。 |
| `--opacity <0.0–1.0>` | `1.0` | 前景の合成不透明度。 |
| `-o`, `--output <パス>` | 背景の隣 | |
| `--format <png\|jpeg>`, `--quality` | 背景に合わせる / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — App Store Connect 用スクリーンショット

スクリーンショットをデバイスフレームにはめ込み、背景に合わせて拡縮し、任意の
キャプションを重ね、結果を 1 つ以上の App Store Connect の iPhone ピクセル
サイズで書き出します — 1 回の実行でまとめて処理します。

```
swiftmagex appstore <スクリーンショット> --background <背景> [オプション]
```

| オプション | デフォルト | 備考 |
|---|---|---|
| `<スクリーンショット>` | — | フレームにはめ込む撮影済みスクリーンショット。 |
| `--background <パス>` | — | 必須。デバイスの背後を埋める(cover)。 |
| `--frame <パス\|id>` | 自動 | iPhone フレーム: 画面部分が透明な PNG のパス、または[同梱フレームの id](#組み込みのデバイスフレーム)(例: `iphone-6.5-pommeplate-spacegray`)。省略すると、指定デバイス用の同梱フレームが利用可能な場合は自動選択される。 |
| `--list-frames` | — | 同梱されているデバイスフレームを一覧表示して終了。`--json` と併用で機械可読な形式に。 |
| `--screen-rect <x,y,w,h>` | 自動検出 | フレーム内でスクリーンショットを置く位置。省略時はフレームのアルファから検出。 |
| `--device <id>` | `iphone-6.9` | 繰り返し可。`iphone-6.9`(1290×2796)、`iphone-6.5`(1242×2688)、`iphone-5.5`(1242×2208)、または `all` のいずれか。 |
| `--orientation <portrait\|landscape>` | `portrait` | デバイスの寸法を入れ替える。 |
| `--scale <比率>` | `0.85` | キャンバスに対するフレーム済みデバイスのサイズ比。 |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | 背景上でのデバイスの配置。 |
| `--caption <文字列>` | — | 任意のキャプションテキスト。 |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, システム, `96`, `#FFFFFF`, —, `0` | キャプションのスタイル(`text` と同じエンジン)。 |
| `-o`, `--output <ディレクトリ>` | `./` | 出力**ディレクトリ**。ファイル名は `appstore_{device}_{w}x{h}.png`。 |

```sh
# 同梱の iPhone 6.5" フレームを使う(--frame 不要)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# 独自フレーム、カタログの全 iPhone サイズを一度に
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### 組み込みのデバイスフレーム

SwiftMageX には CC0 ライセンスの iPhone 11 Pro Max / XS Max フレームが
同梱されています([PommePlate](https://github.com/ephread/PommePlate) の
Space Grey、画面の切り抜きを追加した派生作品 — 詳細は
[Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md)
を参照)。`--device iphone-6.5` を指定すると自動で使用され、`--frame
<パス>` を指定すれば自前のアートワークで上書きできます。同梱内容の
一覧表示:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

ユーザー提供のフレームも従来どおり動作します — 画面部分が透明な PNG
なら何でも使えます。画面領域はアルファチャンネルから検出されます
(または `--screen-rect` で指定)。

### `swiftmagex remove-bg` — ローカルの背景除去

Vision のオンデバイスセグメンテーションを使い、目立つ前景の被写体を
切り抜いて透明背景の上に残します。AI API もキーも不要、クォータ消費
ゼロです。結果は必ずアルファチャンネルを持つため PNG で書き出されま
す(`.png` 以外の `--output` 拡張子は `.png` に補正されます)。

```
swiftmagex remove-bg <input> [オプション]
```

| オプション | 既定値 | 補足 |
|---|---|---|
| `<input>` | — | PNG、JPEG、HEIC、WebP。 |
| `-o`、`--output <path>` | ソースと同じ場所 | 常に PNG で書き出し。 |

```sh
# 被写体を切り抜いて透明背景にする
swiftmagex remove-bg photo.jpg -o cutout.png

# 既定ではソースの隣に PNG を出力
swiftmagex remove-bg product.heic
```

目立つ前景の被写体が検出されない場合、コマンドはラスターエラーで失敗
します(終了コード 1)。

### `swiftmagex crop` — サリエンシー対応のアスペクト比クロップ

ユーザー指定のアスペクト比でクロップし、クロップウィンドウは Vision の
オンデバイス注意モデルが検出した目立つ被写体に中心を合わせます — 幾何
中心ではありません。AI API もキーも不要、クォータ消費ゼロです。出力は
ソースのピクセルスケールを保持し(リサイズではなくクロップ)、既定で
ソースと同じ形式になります。

```
swiftmagex crop <input> --aspect <W:H> [オプション]
```

| オプション | 既定値 | 補足 |
|---|---|---|
| `<input>` | — | PNG、JPEG、HEIC、WebP。書き出しは PNG / JPEG のみ。 |
| `--aspect <W:H>` | — | 必須。2 つの正の整数、例 `1:1`、`4:5`、`9:16`。 |
| `-o`、`--output <path>` | ソースと同じ場所 | |
| `--format <png\|jpeg>` | ソースと同じ | HEIC / WebP は既定で PNG にフォールバック。 |
| `--quality <0.0–1.0>` | `0.9` | JPEG のみ。 |

```sh
# 目立つ被写体を中心にした正方形クロップ
swiftmagex crop photo.jpg --aspect 1:1

# 9:16 の縦長クロップを JPEG で再エンコード
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

サリエンシーが目立つオブジェクトを見つけられない場合(まれ。平坦・均一
な画像)、要求されたアスペクト比を保てるよう中央クロップにフォール
バックします。

### `swiftmagex icon` — Icon Composer の `.icon` パッケージ

準備済みのレイヤー画像から
[Icon Composer](https://developer.apple.com/icon-composer/) の `.icon`
パッケージ(iOS 26+ / macOS 26+ のレイヤー化された Liquid Glass アプリ
アイコン形式)を組み立てます。完全にローカルで、キーは不要。レイヤーは
下から上の順に列挙し、Icon Composer の 1024 pt キャンバスに積み重ね
られます。コマンドは `icon.json` と `Assets/` を書き出し、パッケージの
絶対パスを返します。レイヤーは事前に `generate`、`remove-bg`、`resize`
で準備してください。

```
swiftmagex icon <layer[,key=value...]>... [options]
```

レイヤーごとのオプションはパスにカンマ区切りで追加します: `name=…`、
`glass=true|false`(Liquid Glass、デフォルト true)、`scale=N`
(レイヤーの自然サイズに掛ける倍率。ソース 1 ピクセル = 1 ポイント)、
`dx=N` / `dy=N`(中央配置からのポイント単位オフセット、正 = 右/下)、
`fill=#RRGGBB[AA]`(単色ティント)、`group=N`(1 始まり。同じグループの
レイヤーは連続している必要があり、1 グループ最大 4 レイヤー)。

| オプション | デフォルト | 補足 |
|---|---|---|
| `<layer>...` | — | 下から上へ。透過付き PNG を推奨。他形式は PNG に再エンコードされます。 |
| `-o`, `--output <path>` | `AppIcon.icon` | `.icon` がなければ自動で付加。 |
| `--fill <solid:#HEX\|auto:#HEX>` | `solid:#FFFFFF` | アイコン背景。`auto:` は 1 色から生成されるシステムグラデーション。 |
| `--overwrite` | オフ | 既存パッケージをアトミックに置き換え。 |
| `--flat-preview` | オフ | フラットな 1024×1024 PNG コンポジット(`<name>-flat.png`)も書き出し — Liquid Glass もスクワークルマスクもなし。README や Xcode を使わない用途向け。 |
| `--flat-preview-output <path>` | パッケージの隣 | |
| `--validate` | オフ | Xcode の `actool` でコンパイル検証(Xcode 26 が必要)。actool がなければ終了コード 4、コンパイル失敗なら 2。 |

```sh
# 背景 + ガラスのマーク、グラデーション塗り、プレビューとコンパイル検証付き
swiftmagex icon bg.png mark.png,scale=0.8,dy=-20 \
  --fill auto:#7B1FA2 -o AppIcon.icon --flat-preview --validate

# 右下に固定したバッジ、ガラスなし、白ティント、専用グループ
swiftmagex icon art.png badge.png,glass=false,fill=#FFFFFF,dx=222,dy=223,group=2
```

生成された `AppIcon.icon` を Xcode 26 プロジェクトに入れる(または
Icon Composer で開く)と、Xcode が Liquid Glass エフェクトを描画し、
古い OS 向けのフラット版を自動生成します。

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

エラー(`resize`、`text`、`remove-bg`、`crop` は `provider` / `model` を省略):

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

`swiftmagex-mcp` は stdio 上で 10 個のツール
(`generate_image`、`edit_image`、`resize_image`、`overlay_text`、`composite_images`、`appstore_screenshots`、`list_frames`、`remove_background`、`smart_crop`、`compose_icon`)を提供します。
引数は CLI フラグと対応しており(snake_case のキー、例: `font_size`、`screen_rect`、`devices`)、結果は絶対パスを返すので、呼び出
し側エージェントはサーバの作業ディレクトリを知る必要がありません。
`generate_image` と `edit_image` は加えて、生成された画像のバイト列を
MCP の `image` コンテンツとして返し、呼び出し側モデルが出力結果を直接
確認できます。`list_frames` は同梱されているデバイスフレームを列挙し、
その id は `appstore_screenshots` の `frame` 引数で受け付けられます。
`compose_icon` は `swiftmagex icon` に対応し(レイヤーはオブジェクトの
配列)、`flat_preview` を指定するとフラットプレビューを image コンテンツ
として返します — エージェントの自然なフローは `generate_image` →
`remove_background` → `compose_icon` です。

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
| `I/O error: input file not found: /…/foo.png`(終了コード 1) | ローカルコマンド(`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop`、またはそれらの MCP ツール)に渡したパスが存在しないか読み取り不可。 | 絶対パスを使い、権限と形式(PNG / JPEG / HEIC / WebP、書き出しは PNG / JPEG のみ)を確認。 |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | ダウンロードしたバイナリに Gatekeeper の検疫が付与されている。 | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex`(`swiftmagex-mcp` も同様)。 |

## スコープと状態

これは 0.1 MVP — 3 つのコマンド、2 つの Google AI 画像プロバイダ
(Gemini と Imagen)、1 つの MCP サーバ、さらに 0.1 以降に追加された
5 つのローカルコマンド `composite`、`appstore`、`remove-bg`、`crop`、`icon`
(画像合成、App Store Connect スクリーンショット、Vision ベースの背景除去、
サリエンシー対応クロップ、Icon Composer の `.icon` パッケージ)です。それ以外はすべて延期されています。スコープ
外の項目一覧は仕様
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
を参照(edit / インペイント、ローカルプロバイダ、Homebrew 配布、
設定ファイル、Keychain、…)。

## ライセンス

MIT。全文は [LICENSE](LICENSE) を参照してください。
