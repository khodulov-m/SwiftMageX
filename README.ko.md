# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

macOS 전용 이미지 생성/처리 CLI. SwiftMageX는 *오케스트레이터*로,
이미지 생성은 Google AI 이미지 API(Gemini 또는 Imagen)에 위임하고 리사이즈, 텍스트 오버레이,
합성, App Store 스크린샷, 배경 제거, 살리언시 기반 크롭 같은 로컬 래스터 작업은 CoreImage / CoreText / ImageIO /
Vision으로 처리합니다. 모든 것이 외부 의존성이 정확히 두 개뿐인 작은 Swift 패키지
안에 들어 있습니다. 같은 코어 라이브러리가 Model Context
Protocol 서버(`swiftmagex-mcp`)를 구동하므로, AI 에이전트도 동일
기능을 도구로 호출할 수 있습니다.

권위 있는 사양은 `SwiftMageX-MVP-0.1-spec.md`이고, v0.1.0에 포함
된 내용은 `RELEASE_NOTES.md`를 참고하세요.

## 요구 사항

- Apple silicon(arm64)에서 동작하는 macOS 14+
- Swift 6.0+ 툴체인(Xcode 16+) — 소스 빌드 시에만 필요
- `generate` 명령에 사용할 Google AI API 키를
  `SWIFTMAGEX_GEMINI_API_KEY`(또는 `GEMINI_API_KEY`)에 설정.
  Gemini와 Imagen 모델 모두에 사용됩니다. `resize`, `text`,
  `composite`, `appstore`, `remove-bg`, `crop`은 키가 필요 없습니다.

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

여덟 개의 서브커맨드가 동일한 글로벌 플래그를 공유합니다:

| 글로벌 플래그 | 효과 |
|---|---|
| `--json` | 사람이 읽기 좋은 텍스트 대신 구조화된 JSON을 stdout으로 출력. |
| `-v`, `--verbose` | 진단 메시지를 stderr로 출력. API 키는 **포함되지 않습니다**. |
| `--cache-dir <경로>` | `generate`/`edit` 응답을 `<경로>` 아래에 캐싱해, 동일한 입력은 API를 호출하는 대신 이전에 기록한 프로바이더 바이트를 그대로 재생합니다. 명시적 opt-in — 아래 캐시 절 참고. |
| `--version` | `0.1.0`을 출력하고 종료. |
| `-h`, `--help` | 해당 명령의 도움말을 표시. |

`--json` 출력과 MCP 도구 결과의 출력 경로는 항상 **절대 경로**
입니다. 에이전트가 작업 디렉터리를 알 필요가 없습니다.

### `swiftmagex generate` — Gemini 또는 Imagen으로 텍스트→이미지

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
| `--model <id>` | `gemini-2.5-flash-image` | 내장: Gemini 계열(`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`)과 Imagen 계열(`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). 알 수 없는 ID는 `imagen-` / `gemini-` 접두사로 라우팅됩니다. |

```sh
# 현재 디렉터리에 1장
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# 가로 4장을 디렉터리에, 구조화 출력
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# 재현 가능한 seed(공급자 종속)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

예시 — 아래 호출로 다음 이미지를 생성했습니다(`gemini-2.5-flash-image`로
생성한 1024×1024 PNG):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="흰 배경의 빨간 사과 (생성된 이미지)" width="320" />

각 출력 PNG는 `tEXt` 청크에 prompt, 모델, seed, 타임스탬프,
도구 버전을 담습니다(JPEG는 EXIF `UserComment` 필드 사용).

### `swiftmagex edit` — Gemini를 통한 이미지-투-이미지 / 다중 이미지 / 인페인팅

소스 이미지(추가 참조 이미지 및 선택적 마스크 포함)를 텍스트 프롬프트와
함께 Gemini 모델에 보냅니다. 각 이미지는 `generate`가 사용하는 것과
동일한 `:generateContent` 호출의 `inlineData` 파트로 함께 전송됩니다
—— 새 엔드포인트도, 새 의존성도 없습니다.

```
swiftmagex edit <input> <prompt> [옵션]
```

| 옵션 | 기본값 | 설명 |
|---|---|---|
| `<input>` | — | 필수. 기본 소스 이미지(PNG 또는 JPEG). |
| `<prompt>` | — | 필수. 편집을 설명하는 텍스트 지시. |
| `--reference <경로>` | — | 반복 가능. 추가 참조 이미지(PNG 또는 JPEG). `--reference`를 지정할 때마다 또 하나의 inline 이미지 파트가 추가되어 프롬프트가 이를 조합해 사용할 수 있습니다 —— 예: "이미지 1의 인물을 이미지 2의 장면에 배치하라". |
| `--mask <경로>` | — | 선택적인 그레이스케일/이진 마스크(PNG 또는 JPEG). 흰색은 기본 이미지에서 편집할 영역, 검정색은 보존할 영역을 표시. |
| `-o`, `--output <경로>` | `./` | 파일 또는 디렉터리. 디렉터리인 경우 파일명은 `swiftmagex_{timestamp}_{index}.png`. |
| `-n`, `--count <1–4>` | `1` | 변형 수. 각 변형은 별도 요청. |
| `--seed <uint64>` | — | 프로바이더가 무시하더라도 메타데이터에 기록됩니다. |
| `--model <id>` | `gemini-2.5-flash-image` | Gemini 모델이어야 합니다 —— Imagen의 `:predict` 형식은 inline 이미지 입력을 받지 않으며 종료 코드 2로 거부됩니다. |

```sh
# 피사체 색상 바꾸기
swiftmagex edit apple.png "make the apple green instead of red" -o edited.png

# 마스크로 영역 인페인팅
swiftmagex edit photo.png "replace the marked region with a sunset sky" \
  --mask sky-mask.png -o photo_edited.png

# 두 장의 참조 이미지로 합성
swiftmagex edit person.png "place the person from image 1 into the scene of image 2" \
  --reference street.png -o composed.png

# 동일한 편집의 네 가지 변형
swiftmagex edit shot.jpg "add a snowy mountain in the background" -n 4 -o ./out
```

예시 —— 세 가지 편집 전/후 쌍(원본과 편집 결과는
[`examples/`](examples) 에 있습니다):

| 소스 | 편집 후 | 편집 프롬프트 |
|---|---|---|
| <img src="examples/apple.png" alt="흰 배경의 빨간 사과" width="200"> | <img src="examples/apple-edited.png" alt="밝은 초록색으로 다시 칠한 사과" width="200"> | `"Change the apple's color from red to bright green, keep everything else identical"` |
| <img src="examples/mountain.png" alt="일출 무렵의 산악 호수" width="200"> | <img src="examples/mountain-edited.png" alt="봉우리 위로 열기구가 떠 있는 같은 장면" width="200"> | `"Add a single colorful hot-air balloon floating in the sky above the mountains"` |
| <img src="examples/cabin.png" alt="여름 숲속의 통나무집" width="200"> | <img src="examples/cabin-edited.png" alt="눈에 덮인 같은 통나무집" width="200"> | `"Transform the scene from a sunny summer day to a snowy winter day"` |

다중 이미지 합성 —— `--reference`로 피사체와 장면을 결합합니다:

| 입력(피사체) | 참조(장면) | 결과 |
|---|---|---|
| <img src="examples/canoe.png" alt="흰 배경의 목조 카누" width="200"> | <img src="examples/mountain.png" alt="일출 무렵의 산악 호수" width="200"> | <img src="examples/canoe-on-mountain-lake.png" alt="산악 호수 위에 떠 있는 카누" width="200"> |

```sh
swiftmagex edit examples/canoe.png \
  "Place the canoe from image 1 onto the lake from image 2, match the lighting and add reflections" \
  --reference examples/mountain.png -o examples/canoe-on-mountain-lake.png
```

편집된 출력에는 `generate`와 동일한 `tEXt`/EXIF 메타데이터가 담깁니다 ——
기록된 prompt는 원래의 생성 프롬프트가 아니라 편집 지시입니다.

### 응답 캐시

`generate`나 `edit`에 `--cache-dir <경로>`를 넘기면, 같은 요청이 이미
서비스된 경우 네트워크 호출을 우회합니다. 캐시는 content-addressed
방식입니다: 키는 model, prompt, size, count, seed에 더해 각 reference
이미지와 mask 바이트의 SHA-256까지 합쳐 다시 SHA-256으로 산출합니다.
히트 시에는 디스크에서 바이트를 재생하고, 그래도 출력 파일은 새로운
`tEXt`/EXIF 메타데이터(타임스탬프, 도구 버전)와 함께 새로 작성되므로
하위 파이프라인은 동일하게 동작합니다.

```sh
# 첫 호출은 API, 두 번째는 /tmp/sx-cache에서 재생.
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache --json
# → 재생된 이미지마다 JSON 출력에 "cached": true
```

유의 사항:

- **의도적인 opt-in입니다.** Gemini는 `--seed`를 존중하지 않으므로 같은
  입력이 호출마다 *달라지도록* 설계되어 있습니다 — 캐시 히트는 그
  의도된 비결정성을 조용히 "매번 같은 바이트"로 바꿔 버립니다. 그
  동작이 정말 원하는 것일 때만 `--cache-dir`를 넘기세요.
- **Best-effort.** 캐시 I/O 실패(쓰기 권한 없는 디렉터리, 손상된
  엔트리)는 명령을 중단하지 않고 평소처럼 네트워크 호출로 폴백합니다.
- **Eviction 없음.** 캐시는 디렉터리를 `rm -rf`할 때까지 계속 커집니다.
- 캐시는 `generate` / `edit`에만 적용됩니다(로컬 래스터 명령은
  프로바이더를 호출하지 않습니다). MCP 서버는 0.1에서 캐시를 노출하지
  않으며, CLI 플래그가 오늘의 유일한 진입점입니다.

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

### `swiftmagex composite` — 한 이미지를 다른 이미지 위에 합성

```
swiftmagex composite <배경> --overlay <전경> [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<배경>` | — | 캔버스 이미지. |
| `--overlay <경로>` | — | 필수. 위에 올릴 전경(알파 반영). |
| `--position` | `center` | `text`와 동일한 7개 앵커. |
| `--scale <비율>` | `1.0` | 배경 대비 전경 크기 비율. 가로세로비 유지. |
| `--offset-x`, `--offset-y <px>` | `0` | 앵커에서의 이동량(양수 = 오른쪽 / 아래). |
| `--opacity <0.0–1.0>` | `1.0` | 전경 합성 불투명도. |
| `-o`, `--output <경로>` | 배경 옆 | |
| `--format <png\|jpeg>`, `--quality` | 배경과 동일 / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — App Store Connect 스크린샷

스크린샷을 디바이스 프레임에 끼우고 배경에 맞게 스케일한 뒤, 선택적 캡션을
얹어 결과를 하나 이상의 App Store Connect iPhone 픽셀 크기로 출력합니다 —
한 번의 실행으로 일괄 처리합니다.

```
swiftmagex appstore <스크린샷> --background <배경> [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<스크린샷>` | — | 프레임에 끼울 캡처된 스크린샷. |
| `--background <경로>` | — | 필수. 디바이스 뒤를 채움(cover). |
| `--frame <경로\|id>` | 자동 | iPhone 프레임: 화면 부분이 투명한 PNG 경로 또는 [내장 프레임 id](#내장-디바이스-프레임)(예: `iphone-6.5-pommeplate-spacegray`). 생략하면 요청된 디바이스에 대해 내장 프레임이 있을 때 자동으로 선택. |
| `--list-frames` | — | 내장 디바이스 프레임을 나열하고 종료. `--json`과 함께 쓰면 파싱 가능한 형식으로 출력. |
| `--screen-rect <x,y,w,h>` | 자동 감지 | 프레임 안에서 스크린샷이 놓일 위치. 생략 시 프레임의 알파에서 감지. |
| `--device <id>` | `iphone-6.9` | 반복 가능. `iphone-6.9`(1290×2796), `iphone-6.5`(1242×2688), `iphone-5.5`(1242×2208), 또는 `all` 중 하나. |
| `--orientation <portrait\|landscape>` | `portrait` | 디바이스 치수를 교체. |
| `--scale <비율>` | `0.85` | 캔버스 대비 프레임 적용된 디바이스 크기 비율. |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | 배경 위 디바이스 위치. |
| `--caption <문자열>` | — | 선택적 캡션 텍스트. |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, 시스템, `96`, `#FFFFFF`, —, `0` | 캡션 스타일(`text`와 동일한 엔진). |
| `-o`, `--output <디렉터리>` | `./` | 출력 **디렉터리**. 파일명은 `appstore_{device}_{w}x{h}.png`. |

```sh
# 내장 iPhone 6.5" 프레임 사용(--frame 불필요)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# 커스텀 프레임으로 카탈로그의 모든 iPhone 크기를 한 번에
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### 내장 디바이스 프레임

SwiftMageX에는 CC0 라이선스의 iPhone 11 Pro Max / XS Max 프레임이
포함되어 있습니다([PommePlate](https://github.com/ephread/PommePlate)
Space Grey, 화면 컷아웃을 추가한 파생물 — 자세한 내용은
[Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md)
참조). `--device iphone-6.5`를 지정하면 자동으로 사용되며, `--frame
<경로>`로 직접 만든 아트워크로 덮어쓸 수 있습니다. 내장된 항목을
모두 보려면:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

사용자 제공 프레임도 그대로 동작합니다. 화면 부분이 투명한 PNG라면
무엇이든 사용할 수 있고, 화면 영역은 알파 채널에서 찾습니다(또는
`--screen-rect`로 지정).

### `swiftmagex remove-bg` — 로컬 배경 제거

Vision의 온디바이스 분할을 사용해 두드러진 전경 피사체를 잘라내어
투명 배경 위에 남깁니다. AI API도 키도 필요 없고, 쿼터 소비가 전혀
없습니다. 결과는 항상 알파 채널을 가지므로 PNG로 기록됩니다(`.png`가
아닌 `--output` 확장자는 `.png`로 보정됩니다).

```
swiftmagex remove-bg <input> [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC, WebP. |
| `-o`, `--output <경로>` | 소스의 형제 파일 | 항상 PNG로 기록. |

```sh
# 피사체를 잘라내어 투명 배경으로
swiftmagex remove-bg photo.jpg -o cutout.png

# 기본은 소스 옆에 PNG로 출력
swiftmagex remove-bg product.heic
```

두드러진 전경 피사체가 감지되지 않으면 명령은 래스터 오류로
실패합니다(종료 코드 1).

### `swiftmagex crop` — 살리언시 기반 종횡비 크롭

사용자가 지정한 종횡비로 잘라내며, 크롭 창은 Vision의 온디바이스 어텐션
모델이 검출한 두드러진 피사체에 중심을 맞춥니다 — 기하학적 중심이
아닙니다. AI API도 키도 필요 없고, 쿼터 소비가 전혀 없습니다. 출력은
소스의 픽셀 스케일을 유지하며(리사이즈가 아닌 크롭), 기본적으로 소스와
같은 형식을 사용합니다.

```
swiftmagex crop <input> --aspect <W:H> [옵션]
```

| 옵션 | 기본값 | 비고 |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC, WebP. 쓰기는 PNG / JPEG만. |
| `--aspect <W:H>` | — | 필수. 두 개의 양의 정수, 예: `1:1`, `4:5`, `9:16`. |
| `-o`, `--output <경로>` | 소스의 형제 파일 | |
| `--format <png\|jpeg>` | 소스와 동일 | HEIC / WebP는 기본 PNG로 폴백. |
| `--quality <0.0–1.0>` | `0.9` | JPEG에만 적용. |

```sh
# 두드러진 피사체를 중심으로 한 정사각형 크롭
swiftmagex crop photo.jpg --aspect 1:1

# 9:16 세로 크롭을 JPEG로 재인코딩
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

살리언시가 두드러진 객체를 찾지 못하는 경우(드묾; 평평하거나 균일한
이미지) 중앙 크롭으로 폴백해 요청된 종횡비를 그대로 유지합니다.

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

오류(`resize`, `text`, `remove-bg`, `crop`은 `provider` / `model` 생략):

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

`swiftmagex-mcp`는 stdio로 아홉 가지 도구
(`generate_image`, `edit_image`, `resize_image`, `overlay_text`, `composite_images`, `appstore_screenshots`, `list_frames`, `remove_background`, `smart_crop`)를 노출합니다.
도구 인자는 CLI 플래그와 동일하며(snake_case 키, 예: `font_size`, `screen_rect`, `devices`), 결과는 절대 경로를 반환해 호
출 에이전트가 서버의 작업 디렉터리를 알 필요가 없습니다.
`generate_image`와 `edit_image`는 추가로 이미지 바이트를 MCP `image`
콘텐츠로 함께 반환하여 호출 모델이 결과물을 직접 확인할 수 있습니다.
`list_frames`는 `appstore_screenshots`의 `frame` 인자가 id로 받아들이는
내장 디바이스 프레임을 열거합니다.

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
| `I/O error: input file not found: /…/foo.png`(종료 코드 1) | 로컬 명령(`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop`, 또는 해당 MCP 도구)에 전달한 경로가 존재하지 않거나 읽을 수 없음. | 절대 경로를 사용하고 권한을 확인하며 형식이 PNG / JPEG / HEIC / WebP인지 확인(쓰기는 PNG / JPEG만). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | 다운로드한 바이너리에 Gatekeeper 격리 적용. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex`(`swiftmagex-mcp`도 동일). |

## 범위와 상태

이번은 0.1 MVP — 세 가지 명령, 두 개의 Google AI 이미지 공급자
(Gemini와 Imagen), 한 MCP 서버이며, 여기에 0.1 이후 추가된 네 가지
로컬 명령 `composite`, `appstore`, `remove-bg`, `crop`(합성,
App Store Connect 스크린샷, Vision 기반 배경 제거, 살리언시 기반 크롭)이
더해졌습니다. 그 경계 밖은 모두 미루어졌으며 전체 제외 항목은 스펙
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
을 참조하세요(edit / 인페인팅, 로컬 공급자, Homebrew 배포,
구성 파일, Keychain 등).

## 라이선스

TBD.
