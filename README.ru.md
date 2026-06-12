# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Генерируйте, редактируйте и доводите до ума изображения прямо из
терминала — и научите этому своего AI-агента.** SwiftMageX — нативный
CLI для macOS: за генерацию и редактирование отвечают модели изображений
Google (Gemini и Imagen), а повседневная растровая работа выполняется
прямо на вашем Mac.

Что вы получаете:

- 🎨 **Генерация и редактирование одной командой** — text-to-image,
  image-to-image, композиция из нескольких изображений и инпейнтинг по
  маске; модель выбирается в каждом вызове под ваши требования к качеству.
- 🤖 **Claude Code, который умеет в картинки** — встроенный MCP-сервер
  (`swiftmagex-mcp`) отдаёт все возможности как инструменты, и Claude Code,
  Claude Desktop или любой MCP-клиент учится генерировать, редактировать и
  обрабатывать изображения в своём рабочем процессе.
- 📱 **Скриншоты для App Store за один запуск** — вставить скриншот в
  рамку устройства, положить на фон, добавить подпись и отресайзить под
  все размеры App Store Connect.
- 🔒 **Приватно и бесплатно там, где это важно** — resize, наложение
  текста, композиция, удаление фона и умное кадрирование работают целиком
  на устройстве через CoreImage / CoreText / Vision. Без API-ключа, ничего
  не покидает ваш Mac.
- 🪶 **Минимальный след** — один небольшой Swift-пакет, ровно две внешние
  зависимости, два самодостаточных бинарника.

Авторитативная спецификация — `SwiftMageX-MVP-0.1-spec.md`; описание того,
что вошло в v0.2.0, — в `RELEASE_NOTES.md`.

## Требования

- macOS 14+ на Apple silicon (arm64)
- Swift 6.0+ (Xcode 16+) — нужен только для сборки из исходников
- API-ключ Google AI в переменной `SWIFTMAGEX_GEMINI_API_KEY`
  (или `GEMINI_API_KEY`) для команды `generate` — подходит и для
  Gemini, и для Imagen. Для `resize`, `text`, `composite`, `appstore`, `remove-bg`, `crop` и `icon` ключ не требуется.

## Установка

### Готовый бинарник (рекомендуется)

Скачайте `swiftmagex`, `swiftmagex-mcp` и `SHA256SUMS` из
[релиза v0.2.0](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.2.0),
проверьте контрольные суммы и поместите бинарники в `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.2.0
```

Если Gatekeeper заблокирует скачанные файлы, снимите карантинный флаг:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### Сборка из исходников

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# бинарники окажутся в .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### Запуск без установки

```sh
swift run swiftmagex <subcommand> …      # CLI
swift run swiftmagex-mcp                 # MCP-сервер (stdio)
swift test                               # все тесты
scripts/check.sh                         # сборка + тесты одной командой
```

### Конфигурация

Экспортируйте ключ Gemini в профиле оболочки (нужен только для `generate`):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # предпочтительный вариант
# либо запасной — утилита также читает:
export GEMINI_API_KEY="…"
```

Не вшивайте ключ в скрипты, которые попадают в репозиторий. CLI никогда
не печатает, не логирует и не записывает ключ на диск — даже под
`--verbose` и в метаданных выходных файлов.

## Краткий мануал

Восемь подкоманд; глобальные флаги общие:

| Флаг | Эффект |
|---|---|
| `--json` | Выдаёт структурированный JSON-конверт в stdout вместо человекочитаемого текста. |
| `-v`, `--verbose` | Печатает диагностику в stderr. API-ключ **не** включается. |
| `--cache-dir <путь>` | Кэширует ответы `generate`/`edit` в `<путь>`, чтобы одинаковые запросы воспроизводили ранее записанные байты провайдера вместо обращения к API. Опционально — см. раздел про кэш ниже. |
| `--version` | Печатает `0.2.0` и завершает работу. |
| `-h`, `--help` | Показывает справку по команде. |

Пути в `--json`-выводе и в результатах MCP-инструментов всегда
**абсолютные** — агенту не нужно знать текущую рабочую директорию.

### `swiftmagex generate` — генерация по тексту через Gemini или Imagen

```
swiftmagex generate <prompt> [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<prompt>` | — | Обязательный позиционный аргумент. |
| `-o`, `--output <path>` | `./` | Файл или директория. Для директории имена формируются как `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | Подсказка по соотношению сторон. Итоговое разрешение зависит от модели. |
| `-n`, `--count <1–4>` | `1` | Число вариантов. Каждый — отдельный запрос. |
| `--seed <uint64>` | — | Записывается в метаданные, даже если провайдер его игнорирует. |
| `--model <id>` | `gemini-2.5-flash-image` | Встроенные: семейство Gemini (`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) и семейство Imagen (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Неизвестные ID маршрутизируются по префиксу `imagen-`/`gemini-`. |

```sh
# Одно изображение в текущую директорию
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Четыре landscape-варианта в директорию, JSON-вывод
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Воспроизводимый seed (зависит от провайдера)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Пример — следующий вызов сгенерировал изображение ниже (PNG 1024×1024
от `gemini-2.5-flash-image`):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="Сгенерированное красное яблоко на белом фоне" width="320" />

Каждый выходной PNG содержит prompt, модель, seed, метку времени и
версию утилиты в `tEXt`-чанках (для JPEG — в EXIF-поле `UserComment`).

**Выбирайте модель под свои требования к качеству.** Модели взаимозаменяемы
в каждом вызове через `--model` — всё остальное в команде не меняется.
Дефолтная `gemini-2.5-flash-image` — стабильная «рабочая лошадка»; новейшая
`gemini-3.1-flash-image-preview` даёт заметно более детализированный
результат и сама выбирает широкие, неквадратные кадры; семейство Imagen
даёт явный контроль соотношения сторон (`--size` транслируется в
`aspectRatio`): `imagen-4.0-fast-generate-001` оптимизирована по скорости,
`imagen-4.0-ultra-generate-001` — по максимальному качеству (одно
изображение за вызов). Например, `gemini-3.1-flash-image-preview`
сгенерировала этот кадр 1408×768:

```sh
swiftmagex generate "A red fox curled up on a mossy rock in a misty autumn forest, golden leaves falling, soft photorealistic style" \
  --model gemini-3.1-flash-image-preview -o fox.png
```

<img src="docs/images/example-generate-fox-gemini31.png" alt="Детализированная лиса в осеннем лесу, сгенерирована gemini-3.1-flash-image-preview" width="480" />

### `swiftmagex edit` — image-to-image / мультиизображение / инпейнтинг через Gemini

Отправляет исходное изображение (плюс любые дополнительные референсы и
опциональную маску) в модель Gemini вместе с текстовым промтом. Каждое
изображение передаётся как `inlineData`-часть того же вызова
`:generateContent`, который использует `generate` — без нового эндпоинта
и без новой зависимости.

```
swiftmagex edit <input> <prompt> [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<input>` | — | Обязательно. Основное исходное изображение (PNG или JPEG). |
| `<prompt>` | — | Обязательно. Текстовая инструкция, описывающая правку. |
| `--reference <путь>` | — | Повторяемая. Дополнительное референс-изображение (PNG или JPEG). Каждый `--reference` добавляет ещё одну inline-часть, которую промт может комбинировать — например: «возьми объект из изображения 1 и помести его в сцену из изображения 2». |
| `--mask <путь>` | — | Опциональная маска в градациях серого или бинарная (PNG или JPEG). Белый отмечает область для правки на основном изображении, чёрный сохраняет оригинал. |
| `-o`, `--output <путь>` | `./` | Файл или директория. Для директории файлы именуются `swiftmagex_{timestamp}_{index}.png`. |
| `-n`, `--count <1–4>` | `1` | Количество вариантов. Каждый — отдельный запрос. |
| `--seed <uint64>` | — | Записывается в метаданные, даже если провайдер его игнорирует. |
| `--model <id>` | `gemini-2.5-flash-image` | Должна быть модель Gemini — форма `:predict` у Imagen не принимает inline-входы изображения и отклоняется с кодом выхода 2. |

```sh
# Сменить цвет объекта
swiftmagex edit apple.png "make the apple green instead of red" -o edited.png

# Инпейнтинг области с маской
swiftmagex edit photo.png "replace the marked region with a sunset sky" \
  --mask sky-mask.png -o photo_edited.png

# Композиция из двух референсных изображений
swiftmagex edit person.png "place the person from image 1 into the scene of image 2" \
  --reference street.png -o composed.png

# Четыре варианта одной и той же правки
swiftmagex edit shot.jpg "add a snowy mountain in the background" -n 4 -o ./out
```

Примеры — три пары «до / после» (источники и правки в
[`examples/`](examples)):

| Источник | После правки | Промт правки |
|---|---|---|
| <img src="examples/apple.png" alt="Красное яблоко на белом фоне" width="200"> | <img src="examples/apple-edited.png" alt="Яблоко, перекрашенное в ярко-зелёный" width="200"> | `"Change the apple's color from red to bright green, keep everything else identical"` |
| <img src="examples/mountain.png" alt="Горное озеро на рассвете" width="200"> | <img src="examples/mountain-edited.png" alt="Та же сцена с воздушным шаром над вершинами" width="200"> | `"Add a single colorful hot-air balloon floating in the sky above the mountains"` |
| <img src="examples/cabin.png" alt="Деревянная хижина в летнем лесу" width="200"> | <img src="examples/cabin-edited.png" alt="Та же хижина под снегом" width="200"> | `"Transform the scene from a sunny summer day to a snowy winter day"` |

Композиция из нескольких изображений — объединить объект и сцену через
`--reference`:

| Вход (объект) | Референс (сцена) | Результат |
|---|---|---|
| <img src="examples/canoe.png" alt="Деревянное каноэ на белом фоне" width="200"> | <img src="examples/mountain.png" alt="Горное озеро на рассвете" width="200"> | <img src="examples/canoe-on-mountain-lake.png" alt="Каноэ на поверхности горного озера" width="200"> |

```sh
swiftmagex edit examples/canoe.png \
  "Place the canoe from image 1 onto the lake from image 2, match the lighting and add reflections" \
  --reference examples/mountain.png -o examples/canoe-on-mountain-lake.png
```

Отредактированные выходы несут те же метаданные `tEXt`/EXIF, что и
`generate` — записанный prompt является инструкцией правки, а не исходным
промтом генерации.

### Кэширование ответов

Передайте `--cache-dir <путь>` в `generate` или `edit`, чтобы коротко
замкнуть сетевой вызов, когда идентичный запрос уже обслуживался. Кэш
content-addressed: ключ — SHA-256 от model, prompt, size, count, seed
плюс SHA-256 байтов каждого reference-изображения и mask. При попадании
байты воспроизводятся с диска, и всё равно записывается выходной файл со
свежими `tEXt`/EXIF-метаданными (timestamp, версия инструмента), так что
последующие пайплайны ведут себя одинаково.

```sh
# Первый вызов идёт в API; второй воспроизводится из /tmp/sx-cache.
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache --json
# → "cached": true в JSON-выводе для каждого воспроизведённого изображения
```

Оговорки:

- **Намеренно опционально.** Gemini не учитывает `--seed`, поэтому
  одинаковые входы *должны* варьироваться от вызова к вызову — попадание
  в кэш молча превращает эту намеренную недетерминированность в «те же
  байты каждый раз». Включайте `--cache-dir` только если хотите именно
  этого.
- **Best-effort.** Сбои I/O кэша (директория недоступна для записи,
  повреждённая запись) деградируют до обычного сетевого вызова, а не
  обрывают команду.
- **Без eviction.** Кэш растёт, пока вы не сделаете `rm -rf` директории.
- Кэш покрывает только `generate` / `edit` (локальные растровые команды
  не обращаются к провайдеру). MCP-сервер в 0.1 не экспонирует кэш;
  CLI-флаг — единственная точка входа сегодня.

### `swiftmagex resize` — локальный ресайз / кроп / смена формата

```
swiftmagex resize <input> [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC или WebP. Запись — только PNG / JPEG. |
| `-w`, `--width <px>` | — | Нужно указать хотя бы одно из width/height. |
| `-h`, `--height <px>` | — | Если задано одно — второе вычисляется по соотношению сторон. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` и `fill` требуют оба измерения. |
| `-o`, `--output <path>` | рядом с исходником | По умолчанию — соседний файл. |
| `--format <png\|jpeg>` | как у исходника | Для HEIC / WebP по умолчанию PNG. |
| `--quality <0.0–1.0>` | `0.9` | Только для JPEG. |

```sh
# Квадратная превьюшка, излишки обрезаются
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# Баннер шириной 1200, перекодирование в JPEG c качеством 80 %
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# В пол-размера, пропорции сохранены (указана только ширина)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — наложение текста

```
swiftmagex text <input> --text "<строка>" [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<input>` | — | Изображение, на которое накладывается текст. |
| `--text <строка>` | — | Обязательный. `\n` — перенос строки; длинные строки переносятся по словам. |
| `--position` | `bottom` | Один из: `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font <имя>` | системный | Например, `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` или `#RRGGBBAA`. |
| `--stroke <hex>` | — | Без флага — без обводки. |
| `--stroke-width <pt>` | `2.0` | Используется только если задан `--stroke`. |
| `-o`, `--output <path>` | рядом с исходником | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### `swiftmagex composite` — наложение одного изображения на другое

```
swiftmagex composite <фон> --overlay <передний-план> [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<фон>` | — | Изображение-холст. |
| `--overlay <путь>` | — | Обязательно. Передний план поверх (альфа учитывается). |
| `--position` | `center` | Те же семь якорей, что и у `text`. |
| `--scale <доля>` | `1.0` | Размер переднего плана как доля от фона; пропорции сохраняются. |
| `--offset-x`, `--offset-y <px>` | `0` | Смещение от якоря (положительное = вправо / вниз). |
| `--opacity <0.0–1.0>` | `1.0` | Непрозрачность наложения переднего плана. |
| `-o`, `--output <путь>` | рядом с фоном | |
| `--format <png\|jpeg>`, `--quality` | как у фона / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — скриншоты для App Store Connect

Вставляет скриншот в рамку устройства, масштабирует его на фон, накладывает
необязательную подпись и записывает результат в одном или нескольких пиксельных
размерах iPhone для App Store Connect — пакетно, за один прогон.

```
swiftmagex appstore <скриншот> --background <фон> [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<скриншот>` | — | Снятый скриншот, помещаемый в рамку. |
| `--background <путь>` | — | Обязательно. Заполняет (cover) фон за устройством. |
| `--frame <путь\|id>` | авто | Рамка iPhone: путь к PNG с прозрачным вырезом под экран или [id встроенной рамки](#встроенные-рамки-устройств) (напр. `iphone-6.5-pommeplate-spacegray`). Без значения автоматически подбирается встроенная рамка для запрошенного устройства, если такая есть. |
| `--list-frames` | — | Выводит список встроенных рамок устройств и завершает работу. С `--json` — в машиночитаемой форме. |
| `--screen-rect <x,y,w,h>` | автоопределение | Где разместить скриншот внутри рамки. Без значения определяется по альфа-каналу рамки. |
| `--device <id>` | `iphone-6.9` | Повторяемый. Один из `iphone-6.9` (1290×2796), `iphone-6.5` (1242×2688), `iphone-5.5` (1242×2208) или `all`. |
| `--orientation <portrait\|landscape>` | `portrait` | Меняет местами размеры устройства. |
| `--scale <доля>` | `0.85` | Размер устройства в рамке как доля от холста. |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | Где устройство располагается на фоне. |
| `--caption <строка>` | — | Необязательный текст подписи. |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, системный, `96`, `#FFFFFF`, —, `0` | Стиль подписи (тот же движок, что у `text`). |
| `-o`, `--output <каталог>` | `./` | **Каталог** вывода; файлы называются `appstore_{device}_{w}x{h}.png`. |

```sh
# Используем встроенную рамку iPhone 6.5" (без --frame)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# Своя рамка, сразу все размеры iPhone из каталога
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### Встроенные рамки устройств

SwiftMageX поставляется со встроенной рамкой iPhone 11 Pro Max / XS Max
под лицензией CC0 из [PommePlate](https://github.com/ephread/PommePlate)
(Space Grey, производное произведение с добавленным вырезом под экран —
см. [Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md)).
При `--device iphone-6.5` она подбирается автоматически; передайте
`--frame <путь>`, чтобы переопределить её собственной графикой. Список
всего, что встроено:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

Рамки, переданные пользователем, по-прежнему работают как раньше —
подойдёт любой PNG с прозрачным отверстием под экран; область экрана
определяется по альфа-каналу (или задайте её через `--screen-rect`).

### `swiftmagex remove-bg` — локальное удаление фона

Вырезает заметный объект переднего плана и оставляет его на прозрачном
фоне, используя сегментацию Vision на устройстве — без AI API, без ключа,
с нулевым расходом квоты. Результат всегда имеет альфа-канал, поэтому
записывается в PNG (расширение `--output`, отличное от `.png`,
приводится к `.png`).

```
swiftmagex remove-bg <input> [options]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC или WebP. |
| `-o`, `--output <path>` | рядом с исходником | Всегда записывается в PNG. |

```sh
# Вырезать объект на прозрачный фон
swiftmagex remove-bg photo.jpg -o cutout.png

# По умолчанию — PNG рядом с исходником
swiftmagex remove-bg product.heic
```

Если заметный объект переднего плана не обнаружен, команда завершается
с растровой ошибкой (exit 1).

### `swiftmagex crop` — кадрирование по соотношению с учётом выраженности

Кадрирует под заданное пользователем соотношение сторон, центрируя окно
обрезки на выраженном объекте, найденном моделью внимания Vision на
устройстве, — а не на геометрическом центре. Без AI API, без ключа, с
нулевым расходом квоты. Вывод сохраняет пиксельный масштаб исходника
(это кадрирование, а не resize), а формат по умолчанию совпадает с
исходным.

```
swiftmagex crop <input> --aspect <W:H> [опции]
```

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC или WebP. Запись только PNG / JPEG. |
| `--aspect <W:H>` | — | Обязательно. Два положительных целых, напр. `1:1`, `4:5`, `9:16`. |
| `-o`, `--output <path>` | рядом с исходником | |
| `--format <png\|jpeg>` | как у исходника | HEIC / WebP по умолчанию падают в PNG. |
| `--quality <0.0–1.0>` | `0.9` | Только JPEG. |

```sh
# Квадратное кадрирование с центром на выраженном объекте
swiftmagex crop photo.jpg --aspect 1:1

# Вертикальное 9:16, перекодированное в JPEG
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

Если выраженность не находит ни одного объекта (редко; плоские или
однородные изображения), кадрирование переходит на центрирование по
геометрии — заданное соотношение сторон всё равно соблюдается.

### `swiftmagex icon` — пакеты Icon Composer `.icon`

Собирает пакет [Icon Composer](https://developer.apple.com/icon-composer/)
`.icon` — слоистый формат иконок Liquid Glass для iOS 26+ / macOS 26+ —
из подготовленных изображений-слоёв. Полностью локально, без ключа.
Слои перечисляются снизу вверх и складываются на канве Icon Composer
1024 pt; команда записывает `icon.json` и `Assets/` и сообщает
абсолютный путь пакета. Слои готовьте заранее командами `generate`,
`remove-bg` или `resize`.

```
swiftmagex icon <layer[,key=value...]>... [options]
```

Пер-слойные опции добавляются к пути через запятую: `name=…`,
`glass=true|false` (Liquid Glass, по умолчанию true), `scale=N`
(множитель натурального размера слоя, 1 пиксель исходника = 1 пункт),
`dx=N` / `dy=N` (смещение в пунктах от центрированного размещения,
положительное = вправо/вниз), `fill=#RRGGBB[AA]` (сплошная тонировка),
`group=N` (с 1; слои одной группы должны идти подряд, максимум 4 на
группу).

| Опция | По умолчанию | Примечания |
|---|---|---|
| `<layer>...` | — | Снизу вверх. Рекомендуется PNG с прозрачностью; другие форматы перекодируются в PNG. |
| `-o`, `--output <path>` | `AppIcon.icon` | `.icon` дописывается, если отсутствует. |
| `--fill <solid:#HEX\|auto:#HEX>` | `solid:#FFFFFF` | Фон иконки; `auto:` — системный градиент из одного цвета. |
| `--overwrite` | выкл. | Атомарно заменить существующий пакет. |
| `--flat-preview` | выкл. | Дополнительно записать плоский композит 1024×1024 PNG (`<name>-flat.png`) — без Liquid Glass и маски-сквиркла — для README и сборок без Xcode. |
| `--flat-preview-output <path>` | рядом с пакетом | |
| `--validate` | выкл. | Проверить пакет компиляцией через `actool` из Xcode (нужен Xcode 26). Выход 4, если actool отсутствует; выход 2, если пакет не компилируется. |

```sh
# Фон + стеклянный знак, градиентная заливка, с превью и проверкой компиляции
swiftmagex icon bg.png mark.png,scale=0.8,dy=-20 \
  --fill auto:#7B1FA2 -o AppIcon.icon --flat-preview --validate

# Бейдж в правом нижнем углу, без стекла, белая тонировка, своя группа
swiftmagex icon art.png badge.png,glass=false,fill=#FFFFFF,dx=222,dy=223,group=2
```

Готовый `AppIcon.icon` кладите в проект Xcode 26 (или открывайте в
Icon Composer) — Xcode отрисует эффект Liquid Glass и сгенерирует
плоские варианты для старых версий ОС.

### Схема JSON-вывода

Любая команда под `--json` выдаёт один и тот же конверт. Ключи
отсортированы; nil-поля полностью опускаются (никаких `null`-заглушек).

Успех:

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

Ошибка (`resize`, `text`, `remove-bg` и `crop` не выдают `provider` / `model`):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

Потоки: результаты → **stdout**; диагностика (`--verbose`) → **stderr**.
JSON-ошибка под `--json` тоже пишется в stdout — чтобы агент мог парсить
всё из одного потока.

### Коды возврата

| Код | Значение | Пример |
|---|---|---|
| `0` | Успех | — |
| `1` | Непредвиденная / растровая / I/O-ошибка | нечитаемый входной файл, сбой кодировщика |
| `2` | Некорректные входные данные | плохая комбинация `--fit`, битый hex-цвет, `--count` вне 1–4 |
| `3` | Ошибка провайдера / API | 5xx от Gemini, `429` после 5 повторов |
| `4` | Конфигурация | отсутствует `SWIFTMAGEX_GEMINI_API_KEY` |

Политика повторов при 429: до 5 попыток, экспоненциальная задержка
1 с → 2 с → 4 с → 8 с → 16 с.

## MCP-сервер

`swiftmagex-mcp` предоставляет десять инструментов — `generate_image`,
`edit_image`, `resize_image`, `overlay_text`, `composite_images`,
`appstore_screenshots`, `list_frames`, `remove_background`, `smart_crop`
и `compose_icon` — через stdio. Аргументы инструментов повторяют флаги
CLI (ключи в snake_case, напр. `font_size`, `screen_rect`, `devices`); в
результатах возвращаются абсолютные пути, так что агенту не нужно знать
рабочую директорию сервера. `generate_image` и `edit_image` дополнительно
возвращают байты изображения как MCP `image`-контент, чтобы вызывающая
модель могла увидеть, что получилось. `list_frames` перечисляет
встроенные рамки устройств, чьи id принимает аргумент `frame`
инструмента `appstore_screenshots`. `compose_icon` повторяет
`swiftmagex icon` (слои — массив объектов) и при `flat_preview`
возвращает плоское превью как image-контент — естественная цепочка для
агента: `generate_image` → `remove_background` → `compose_icon`.

### Подключение Claude Code

Claude Code регистрирует MCP-серверы через `claude mcp add`. Внутри
репозитория, где должен быть доступен SwiftMageX, выполните:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Чтобы сервер был доступен во всех сессиях Claude Code на этой машине,
используйте user-скоуп:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Посмотреть зарегистрированные серверы — `claude mcp list` или
`claude mcp get swiftmagex`; удалить — `claude mcp remove swiftmagex`.
Транспорт по умолчанию — stdio, флаг `--transport` указывать не нужно.

### Подключение Claude Desktop

Добавьте запись в
`~/Library/Application Support/Claude/claude_desktop_config.json`:

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

Блок `env` ограничивает доступность API-ключа только этим сервером —
ключ не оседает в глобальном окружении клиента.

## Решение проблем

| Симптом | Вероятная причина | Что делать |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | В окружении нет API-ключа при запуске `generate` / вызове `generate_image`. | Экспортируйте `SWIFTMAGEX_GEMINI_API_KEY` (или запасной `GEMINI_API_KEY`); для MCP — добавьте ключ в блок `env` клиента, как показано выше. |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini возвращал `429` на всех попытках в окне backoff'а (1 с → 16 с). | Дождитесь пополнения квоты, переключите проект или попробуйте позже. Расписание backoff'а зафиксировано; см. спецификацию §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | Путь, переданный в локальную команду (`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop` или их MCP-инструменты), не существует или нечитаем. | Передайте абсолютный путь, проверьте права, убедитесь, что формат — один из PNG / JPEG / HEIC / WebP (запись только в PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Gatekeeper поставил карантин на скачанный бинарник. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (и то же для `swiftmagex-mcp`). |

## Область и статус

Это 0.1 MVP — три команды, два провайдера изображений Google AI
(Gemini и Imagen), один MCP-сервер — плюс пять локальных дополнений
после 0.1: `composite`, `appstore`, `remove-bg`, `crop` и `icon`
(композиция, скриншоты для App Store Connect, удаление фона на базе
Vision, кадрирование по выраженности и пакеты Icon Composer `.icon`). Всё, что за этой границей, отложено; полный список вне области см. в
спецификации
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, локальные провайдеры, дистрибуция через Homebrew,
конфиг-файл, Keychain и т. п.).

## Лицензия

MIT. Полный текст — в файле [LICENSE](LICENSE).
