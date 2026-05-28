# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

仅 macOS 的图像生成与处理 CLI。SwiftMageX 是一个*编排器*:调用
Google AI 图像 API(Gemini 或 Imagen)进行图像生成,并使用 CoreImage / CoreText / ImageIO / Vision 完成
本地光栅操作(缩放、文字叠加、合成、App Store 截图、抠图去背、显著性感知裁剪),全部封装在一个仅有两个外部依赖的小
Swift 包中。同一个核心库还驱动一个 Model Context Protocol 服务器
(`swiftmagex-mcp`),让 AI 代理可以把这些能力当作工具来调用。

权威规范见 `SwiftMageX-MVP-0.1-spec.md`,v0.1.0 发布内容见
`RELEASE_NOTES.md`。

## 环境要求

- 运行在 Apple silicon(arm64)上的 macOS 14+
- Swift 6.0+ 工具链(Xcode 16+)——仅在从源码构建时需要
- 用于 `generate` 命令的 Google AI API 密钥,写入
  `SWIFTMAGEX_GEMINI_API_KEY`(或 `GEMINI_API_KEY`)——同一个密钥
  适用于 Gemini 和 Imagen 模型。`resize`、`text`、`composite`、`appstore`、`remove-bg` 与 `crop` 不需要密钥。

## 安装

### 预编译二进制(推荐)

从 [v0.1.0 release](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0)
下载 `swiftmagex`、`swiftmagex-mcp` 和 `SHA256SUMS`,校验后放入
`PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

若 Gatekeeper 隔离了下载文件,清除隔离属性:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### 从源码构建

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# 产物位于 .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### 不安装直接运行源码

```sh
swift run swiftmagex <子命令> …          # CLI
swift run swiftmagex-mcp                 # MCP 服务器(stdio 传输)
swift test                               # 完整测试套件
scripts/check.sh                         # 构建 + 测试一步完成
```

### 配置

在 shell 配置中导出 Gemini API 密钥(仅 `generate` 需要):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # 首选
# 备用变量,工具同样会读取:
export GEMINI_API_KEY="…"
```

不要把密钥嵌入提交进仓库的脚本中。CLI 不会打印、记录或写入密钥到
磁盘——即使在 `--verbose` 下,也不会写入输出文件的元数据。

## 快速手册

七个子命令共享同一组全局标志:

| 全局标志 | 作用 |
|---|---|
| `--json` | 以结构化 JSON 写到 stdout,而非人类可读文本。 |
| `-v`、`--verbose` | 把诊断信息写到 stderr。**不包含** API 密钥。 |
| `--version` | 打印 `0.1.0` 并退出。 |
| `-h`、`--help` | 显示该命令的帮助。 |

`--json` 输出和 MCP 工具返回的路径**始终是绝对路径**——调用方代理
无需知道当前工作目录。

### `swiftmagex generate` — 通过 Gemini 或 Imagen 文生图

```
swiftmagex generate <prompt> [选项]
```

| 选项 | 默认值 | 备注 |
|---|---|---|
| `<prompt>` | — | 必填位置参数。 |
| `-o`、`--output <路径>` | `./` | 文件或目录。目录时按 `swiftmagex_{timestamp}_{index}.png` 命名。 |
| `-s`、`--size <square\|portrait\|landscape>` | `square` | 比例提示,实际分辨率取决于模型。 |
| `-n`、`--count <1–4>` | `1` | 变体数量,每个变体一次独立请求。 |
| `--seed <uint64>` | — | 即便提供商忽略,也会写入元数据。 |
| `--model <id>` | `gemini-2.5-flash-image` | 内置:Gemini 系列(`gemini-2.5-flash-image`、`gemini-3-pro-image-preview`、`gemini-3.1-flash-image-preview`)与 Imagen 系列(`imagen-4.0-generate-001`、`imagen-4.0-fast-generate-001`、`imagen-4.0-ultra-generate-001`)。未知 ID 按 `imagen-`/`gemini-` 前缀路由。 |

```sh
# 输出单张到当前目录
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# 四张横幅变体到目录,结构化输出
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# 可复现 seed(取决于提供商)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

示例 — 下面的调用生成了下方的图片(由 `gemini-2.5-flash-image` 输出的
1024×1024 PNG):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="白色背景上的红色苹果(生成图像)" width="320" />

每个输出的 PNG 会在 `tEXt` 块中携带 prompt、模型、seed、时间戳和
工具版本;JPEG 写入 EXIF 的 `UserComment` 字段。

### `swiftmagex resize` — 本地缩放 / 裁剪 / 格式转换

```
swiftmagex resize <input> [选项]
```

| 选项 | 默认值 | 备注 |
|---|---|---|
| `<input>` | — | PNG、JPEG、HEIC 或 WebP。写入仅支持 PNG / JPEG。 |
| `-w`、`--width <px>` | — | width / height 至少给一个。 |
| `-h`、`--height <px>` | — | 仅给一个时,另一边按宽高比推算。 |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` 与 `fill` 需要同时给出两个维度。 |
| `-o`、`--output <路径>` | 与源同目录 | 默认放在源文件旁边。 |
| `--format <png\|jpeg>` | 与源同 | HEIC / WebP 源默认输出 PNG。 |
| `--quality <0.0–1.0>` | `0.9` | 仅 JPEG。 |

```sh
# 正方形缩略图,裁掉超出部分
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# 宽 1200,转 JPEG 80% 质量
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# 半尺寸,保持比例(只给宽)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — 文字叠加

```
swiftmagex text <input> --text "<字符串>" [选项]
```

| 选项 | 默认值 | 备注 |
|---|---|---|
| `<input>` | — | 用于叠加的源图。 |
| `--text <字符串>` | — | 必填。`\n` 表示换行;过长会按词自动换行。 |
| `--position` | `bottom` | 可选 `top`、`center`、`bottom`、`top-left`、`top-right`、`bottom-left`、`bottom-right`。 |
| `--font <名称>` | 系统字体 | 例如 `"Helvetica-Bold"`。 |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` 或 `#RRGGBBAA`。 |
| `--stroke <hex>` | — | 不填即无描边。 |
| `--stroke-width <pt>` | `2.0` | 仅在设置 `--stroke` 时生效。 |
| `-o`、`--output <路径>` | 与源同目录 | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### `swiftmagex composite` — 把一张图叠到另一张图上

```
swiftmagex composite <背景> --overlay <前景> [选项]
```

| 选项 | 默认 | 说明 |
|---|---|---|
| `<背景>` | — | 画布图像。 |
| `--overlay <路径>` | — | 必填。叠在上方的前景(保留透明度)。 |
| `--position` | `center` | 与 `text` 相同的七个锚点。 |
| `--scale <比例>` | `1.0` | 前景相对背景的尺寸比例;保持宽高比。 |
| `--offset-x`, `--offset-y <px>` | `0` | 相对锚点的偏移(正值 = 右 / 下)。 |
| `--opacity <0.0–1.0>` | `1.0` | 前景混合不透明度。 |
| `-o`, `--output <路径>` | 与背景同目录 | |
| `--format <png\|jpeg>`, `--quality` | 跟随背景 / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — App Store Connect 截图

把截图嵌入设备外框,按背景缩放,叠加可选的标题文字,并将结果输出为一个或多个
App Store Connect 的 iPhone 像素尺寸——一次运行批量完成。

```
swiftmagex appstore <截图> --background <背景> [选项]
```

| 选项 | 默认 | 说明 |
|---|---|---|
| `<截图>` | — | 放入外框的截图。 |
| `--background <路径>` | — | 必填。在设备后方铺满(cover)。 |
| `--frame <路径\|id>` | 自动 | iPhone 外框:屏幕部分透明的 PNG 路径,或[内置外框 id](#内置设备外框)(如 `iphone-6.5-pommeplate-spacegray`)。省略时,若所请求设备有内置外框,则自动选用。 |
| `--list-frames` | — | 列出内置设备外框并退出。与 `--json` 搭配使用可输出可解析格式。 |
| `--screen-rect <x,y,w,h>` | 自动检测 | 截图在外框中的位置。省略时从外框的透明通道检测。 |
| `--device <id>` | `iphone-6.9` | 可重复。`iphone-6.9`(1290×2796)、`iphone-6.5`(1242×2688)、`iphone-5.5`(1242×2208)或 `all` 之一。 |
| `--orientation <portrait\|landscape>` | `portrait` | 交换设备尺寸。 |
| `--scale <比例>` | `0.85` | 嵌框设备相对画布的尺寸比例。 |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | 设备在背景上的位置。 |
| `--caption <字符串>` | — | 可选的标题文字。 |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, 系统, `96`, `#FFFFFF`, —, `0` | 标题样式(与 `text` 同一引擎)。 |
| `-o`, `--output <目录>` | `./` | 输出**目录**;文件名为 `appstore_{device}_{w}x{h}.png`。 |

```sh
# 使用内置的 iPhone 6.5" 外框(无需 --frame)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# 自定义外框,一次生成目录中所有 iPhone 尺寸
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### 内置设备外框

SwiftMageX 内置了一份 CC0 协议的 iPhone 11 Pro Max / XS Max 外框,
取自 [PommePlate](https://github.com/ephread/PommePlate)(Space Grey;
为契合本工具的透明屏幕镂空,做了添加屏幕镂空的派生处理——详见
[Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md))。
传入 `--device iphone-6.5` 即可自动使用;若要换成自己的图,使用
`--frame <路径>` 覆盖。列出全部内置项:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

用户自备的外框依然按原方式工作——任何带透明屏幕镂空的 PNG 均可;
屏幕区域会从透明通道中识别(或用 `--screen-rect` 指定)。

### `swiftmagex remove-bg` — 本地抠图去背

使用 Vision 的设备端分割,抠出显著前景主体并置于透明背景上——无需 AI
API、无需密钥、零配额消耗。结果始终带有 alpha 通道,因此以 PNG 写出
(非 `.png` 的 `--output` 扩展名会被纠正为 `.png`)。

```
swiftmagex remove-bg <input> [选项]
```

| 选项 | 默认值 | 备注 |
|---|---|---|
| `<input>` | — | PNG、JPEG、HEIC 或 WebP。 |
| `-o`、`--output <路径>` | 与源同目录 | 始终以 PNG 写出。 |

```sh
# 抠出主体并置于透明背景
swiftmagex remove-bg photo.jpg -o cutout.png

# 默认输出到源文件旁的 PNG
swiftmagex remove-bg product.heic
```

若未检测到显著的前景主体,命令将以光栅错误失败(退出码 1)。

### `swiftmagex crop` — 显著性感知的宽高比裁剪

按用户指定的宽高比进行裁剪,裁剪窗口居中对齐于 Vision 设备端注意力模型
识别的显著主体——而不是几何中心。无需 AI API、无需密钥、零配额消耗。
输出保持源图像的像素尺度(这是裁剪,不是缩放),默认沿用源文件格式。

```
swiftmagex crop <input> --aspect <W:H> [选项]
```

| 选项 | 默认值 | 备注 |
|---|---|---|
| `<input>` | — | PNG、JPEG、HEIC 或 WebP。写出仅支持 PNG / JPEG。 |
| `--aspect <W:H>` | — | 必填。两个正整数,如 `1:1`、`4:5`、`9:16`。 |
| `-o`、`--output <路径>` | 与源同目录 | |
| `--format <png\|jpeg>` | 与源一致 | HEIC / WebP 默认回退为 PNG。 |
| `--quality <0.0–1.0>` | `0.9` | 仅 JPEG。 |

```sh
# 以显著主体为中心的正方形裁剪
swiftmagex crop photo.jpg --aspect 1:1

# 9:16 竖版裁剪,重新编码为 JPEG
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

当显著性识别不到任何显著对象(罕见;平坦或均匀图像)时,回退为居中
裁剪,以保证所请求的宽高比依然成立。

### JSON 输出格式

所有命令在 `--json` 下输出同一信封,键按字母排序,nil 字段完全省略
(没有 `null` 占位)。

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

错误(`resize`、`text`、`remove-bg` 与 `crop` 省略 `provider` / `model`):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

流约定:结果 → **stdout**;诊断(`--verbose`)→ **stderr**。
`--json` 下的错误 JSON 同样写到 stdout,便于代理在一处解析。

### 退出码

| 退出码 | 含义 | 示例 |
|---|---|---|
| `0` | 成功 | — |
| `1` | 意外 / 光栅 / I/O 失败 | 输入文件不可读、编码器失败 |
| `2` | 输入非法 | `--fit` 搭配错误、hex 颜色错误、`--count` 超出 1–4 |
| `3` | 提供商 / API 失败 | Gemini 5xx,5 次重试后仍 `429` |
| `4` | 配置缺失 | 缺少 `SWIFTMAGEX_GEMINI_API_KEY` |

429 重试策略:最多 5 次,指数退避 1 s → 2 s → 4 s → 8 s → 16 s。

## MCP 服务器

`swiftmagex-mcp` 通过 stdio 暴露八个工具:`generate_image`、
`resize_image`、`overlay_text`、`composite_images`、`appstore_screenshots`、`list_frames`、`remove_background`、`smart_crop`。工具参数与 CLI 标志保持一致(snake_case 键名,如 `font_size`、`screen_rect`、`devices`);返回的
文件路径都是绝对路径,调用方代理无需知道服务器的工作目录。
`generate_image` 还会以 MCP `image` 内容形式返回图像字节,便于调用
模型直接检视产物。`list_frames` 列出 `appstore_screenshots` 的 `frame`
参数可接受作为 id 的内置设备外框。

### 配置 Claude Code

Claude Code 通过 `claude mcp add` 注册 MCP 服务器。在希望使用
SwiftMageX 的仓库内执行:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

若希望本机所有 Claude Code 会话都能使用,改用用户级 scope:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

用 `claude mcp list` 或 `claude mcp get swiftmagex` 查看已注册项,
用 `claude mcp remove swiftmagex` 移除。默认传输是 stdio,无需
`--transport` 标志。

### 配置 Claude Desktop

在
`~/Library/Application Support/Claude/claude_desktop_config.json`
中添加条目:

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

`env` 块把 API 密钥限定在该服务器范围内,密钥不会出现在客户端的全局
环境里。

## 故障排查

| 现象 | 可能原因 | 解决方式 |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY`(退出码 4) | 运行 `generate` 或调用 `generate_image` 时环境里没有 API 密钥。 | 导出 `SWIFTMAGEX_GEMINI_API_KEY`(或备用 `GEMINI_API_KEY`);MCP 场景下加进客户端的 `env` 块,见上文。 |
| `Provider error: quota exhausted after 5 retries`(退出码 3) | Gemini 在 1 s → 16 s 的退避窗口内每次都返回 `429`。 | 等待配额恢复、切换项目或稍后重试。退避节奏是固定的,见规范 §13。 |
| `I/O error: input file not found: /…/foo.png`(退出码 1) | 传给本地命令(`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop`,或其 MCP 工具)的路径不存在或不可读。 | 使用绝对路径,检查权限,确认格式属于 PNG / JPEG / HEIC / WebP(写入仅支持 PNG / JPEG)。 |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | 已下载的二进制被 Gatekeeper 隔离。 | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex`(`swiftmagex-mcp` 同理)。 |

## 范围与状态

这是 0.1 MVP——三个命令、两个 Google AI 图像提供商(Gemini 与
Imagen)、一个 MCP 服务器,外加 0.1 之后新增的四个本地命令
`composite`、`appstore`、`remove-bg`、`crop`(图像合成、
App Store Connect 截图、基于 Vision 的抠图去背、显著性感知裁剪)。
超出该边界的内容均推迟,详见规范
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting、本地提供商、Homebrew 分发、配置文件、
Keychain 等)。

## 许可证

TBD。
