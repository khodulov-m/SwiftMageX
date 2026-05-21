# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

macOS 전용 이미지 생성/처리 CLI. SwiftMageX는 *오케스트레이터*로,
이미지 생성은 Gemini API에 위임하고 리사이즈와 텍스트 오버레이
같은 로컬 래스터 작업은 CoreImage / CoreText / ImageIO로 처리합
니다. 모든 것이 외부 의존성이 정확히 두 개뿐인 작은 Swift 패키지
안에 들어 있습니다. 같은 코어 라이브러리가 Model Context
Protocol 서버(`swiftmagex-mcp`)를 구동하므로, AI 에이전트도 동일
기능을 도구로 호출할 수 있습니다.

권위 있는 사양은 `SwiftMageX-MVP-0.1-spec.md`이고, v0.1.0에 포함
된 내용은 `RELEASE_NOTES.md`를 참고하세요.

## 요구 사항

- Apple silicon(arm64)에서 동작하는 macOS 14+
- Swift 6.0+ 툴체인(Xcode 16+) — 소스 빌드 시에만 필요
- `generate` 명령에 사용할 Gemini API 키를
  `SWIFTMAGEX_GEMINI_API_KEY`(또는 `GEMINI_API_KEY`)에 설정.
  `resize`와 `text`는 키가 필요 없습니다.

## 설치

### 사전 빌드 바이너리(권장)

[v0.1.0 릴리스](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0)
에서 `swiftmagex`, `swiftmagex-mcp`, `SHA256SUMS`를 받은 뒤 체크
섬을 검증하고 `PATH`에 배치하세요:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

Gatekeeper가 다운로드를 격리하면 속성을 제거합니다:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### 소스에서 빌드

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# 바이너리는 .build/arm64-apple-macosx/release/ 에 생성됩니다
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### 설치 없이 소스에서 실행

```sh
swift run swiftmagex <서브커맨드> …      # CLI
swift run swiftmagex-mcp                 # MCP 서버(stdio 전송)
swift test                               # 전체 테스트
scripts/check.sh                         # 빌드 + 테스트 한 번에
```

### 구성

쉘 프로파일에서 Gemini API 키를 export 하세요(`generate`에만
필요):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # 권장
# 대안으로 도구는 다음 변수도 읽습니다:
export GEMINI_API_KEY="…"
```

저장소에 커밋되는 스크립트에 키를 삽입하지 마세요. CLI는 `--verbose`
에서도, 출력 파일 메타데이터에도 키를 출력/로그/디스크에 남기지
않습니다.

## 빠른 매뉴얼

세 개의 서브커맨드가 동일한 글로벌 플래그를 공유합니다:

| 글로벌 플래그 | 효과 |
|---|---|
| `--json` | 사람이 읽기 좋은 텍스트 대신 구조화된 JSON을 stdout으로 출력. |
| `-v`, `--verbose` | 진단 메시지를 stderr로 출력. API 키는 **포함되지 않습니다**. |
| `--version` | `0.1.0`을 출력하고 종료. |
| `-h`, `--help` | 해당 명령의 도움말을 표시. |

`--json` 출력과 MCP 도구 결과의 출력 경로는 항상 **절대 경로**
입니다. 에이전트가 작업 디렉터리를 알 필요가 없습니다.

### `swiftmagex generate` — Gemini로 텍스트→이미지

```
swiftmagex generate <prompt> [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<prompt>` | — | 필수 위치 인자. |
| `-o`, `--output <경로>` | `./` | 파일 또는 디렉터리. 디렉터리면 파일 이름은 `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | 비율 힌트. 실제 해상도는 모델에 따라 달라집니다. |
| `-n`, `--count <1–4>` | `1` | 변형 개수. 각 변형은 개별 요청. |
| `--seed <uint64>` | — | 공급자가 무시해도 메타데이터에 기록됩니다. |
| `--model <id>` | `gemini-2.5-flash-image` | 프리뷰 품질은 `gemini-3.1-flash-image-preview`. |

```sh
# 현재 디렉터리에 1장
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# 가로 4장을 디렉터리에, 구조화 출력
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# 재현 가능한 seed(공급자 종속)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

각 출력 PNG는 `tEXt` 청크에 prompt, 모델, seed, 타임스탬프,
도구 버전을 담습니다(JPEG는 EXIF `UserComment` 필드 사용).

### `swiftmagex resize` — 로컬 리사이즈 / 크롭 / 포맷 변환

```
swiftmagex resize <input> [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC, WebP. 쓰기는 PNG / JPEG만 지원. |
| `-w`, `--width <px>` | — | width / height 중 적어도 하나는 필수. |
| `-h`, `--height <px>` | — | 한쪽만 주면 나머지는 비율에서 계산. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover`와 `fill`은 두 차원 모두 필요. |
| `-o`, `--output <경로>` | 소스의 형제 파일 | 기본은 소스 옆. |
| `--format <png\|jpeg>` | 소스와 동일 | HEIC / WebP 소스는 PNG로 기본 출력. |
| `--quality <0.0–1.0>` | `0.9` | JPEG 전용. |

```sh
# 정사각형 썸네일, 넘치는 부분은 잘라냄
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# 폭 1200 배너, JPEG 80%로 재인코딩
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# 절반 크기, 비율 유지(폭만 지정)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — 텍스트 오버레이

```
swiftmagex text <input> --text "<문자열>" [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<input>` | — | 그릴 대상 이미지. |
| `--text <문자열>` | — | 필수. `\n`은 줄바꿈, 긴 줄은 단어 단위로 줄바꿈. |
| `--position` | `bottom` | `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right` 중 하나. |
| `--font <이름>` | 시스템 글꼴 | 예: `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` 또는 `#RRGGBBAA`. |
| `--stroke <hex>` | — | 생략하면 외곽선 없음. |
| `--stroke-width <pt>` | `2.0` | `--stroke` 설정 시에만 적용. |
| `-o`, `--output <경로>` | 소스의 형제 파일 | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### JSON 출력 스키마

모든 명령은 `--json`에서 동일한 봉투를 출력합니다. 키는 정렬되며
nil 필드는 완전히 생략됩니다(`null` 자리표시 없음).

성공:

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

오류(`resize`와 `text`는 `provider` / `model` 생략):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

스트림 규칙: 결과 → **stdout**, 진단(`--verbose`) → **stderr**.
`--json`의 오류 JSON도 stdout으로 가서 에이전트가 한 곳에서 파싱
할 수 있습니다.

### 종료 코드

| 코드 | 의미 | 예 |
|---|---|---|
| `0` | 성공 | — |
| `1` | 예기치 못한 / 래스터 / I/O 오류 | 입력 파일 읽기 실패, 인코더 실패 |
| `2` | 잘못된 입력 | `--fit` 조합 오류, 잘못된 hex 색, `--count` 1–4 범위 벗어남 |
| `3` | 공급자 / API 오류 | Gemini 5xx, 5회 재시도 후의 `429` |
| `4` | 구성 오류 | `SWIFTMAGEX_GEMINI_API_KEY` 없음 |

429 재시도 정책: 최대 5회, 지수 백오프
1 s → 2 s → 4 s → 8 s → 16 s.

## MCP 서버

`swiftmagex-mcp`는 stdio로 세 가지 도구
(`generate_image`, `resize_image`, `overlay_text`)를 노출합니다.
도구 인자는 CLI 플래그와 동일하며, 결과는 절대 경로를 반환해 호
출 에이전트가 서버의 작업 디렉터리를 알 필요가 없습니다.
`generate_image`는 추가로 이미지 바이트를 MCP `image` 콘텐츠로
함께 반환하여 호출 모델이 결과물을 직접 확인할 수 있습니다.

### Claude Code 구성

Claude Code는 `claude mcp add`로 MCP 서버를 등록합니다. SwiftMageX를
사용할 저장소 안에서 실행하세요:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

이 머신의 모든 Claude Code 세션에서 쓰려면 user 스코프를 사용합니다:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

등록 상태는 `claude mcp list` 또는 `claude mcp get swiftmagex`로 확인하고,
`claude mcp remove swiftmagex`로 제거합니다. 기본 전송은 stdio이므로
`--transport` 플래그는 필요 없습니다.

### Claude Desktop 구성

`~/Library/Application Support/Claude/claude_desktop_config.json`
에 항목을 추가합니다:

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

`env` 블록은 API 키를 이 서버에만 한정해 노출시키므로, 키가 클라
이언트 전체 환경에 남지 않습니다.

## 문제 해결

| 증상 | 가능한 원인 | 해결 |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY`(종료 코드 4) | `generate` 실행 또는 `generate_image` 호출 시 환경에 API 키가 없음. | `SWIFTMAGEX_GEMINI_API_KEY`(또는 대체 `GEMINI_API_KEY`)를 export. MCP라면 위 예시처럼 클라이언트 `env` 블록에 추가. |
| `Provider error: quota exhausted after 5 retries`(종료 코드 3) | 백오프 윈도우(1 s → 16 s) 동안 매번 Gemini가 `429`를 반환. | 쿼터 회복을 기다리거나 프로젝트를 전환, 또는 나중에 재시도. 백오프 스케줄은 고정(스펙 §13). |
| `I/O error: input file not found: /…/foo.png`(종료 코드 1) | `resize` / `text`(또는 `resize_image` / `overlay_text`)에 전달한 경로가 존재하지 않거나 읽을 수 없음. | 절대 경로를 사용하고 권한을 확인하며 형식이 PNG / JPEG / HEIC / WebP인지 확인(쓰기는 PNG / JPEG만). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | 다운로드한 바이너리에 Gatekeeper 격리 적용. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex`(`swiftmagex-mcp`도 동일). |

## 범위와 상태

이번은 0.1 MVP — 세 가지 명령, 한 공급자(Gemini), 한 MCP 서버입
니다. 그 경계 밖은 모두 미루어졌으며 전체 제외 항목은 스펙
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
을 참조하세요(edit / 인페인팅, 로컬 공급자, Homebrew 배포,
구성 파일, Keychain 등).

## 라이선스

TBD.
