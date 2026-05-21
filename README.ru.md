# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI для генерации и обработки изображений, только под macOS. SwiftMageX —
*оркестратор*: он обращается к Gemini API для генерации и выполняет
локальные растровые операции (resize, наложение текста) через
CoreImage / CoreText / ImageIO. Это компактный Swift-пакет ровно с двумя
внешними зависимостями. Та же базовая библиотека используется в сервере
Model Context Protocol (`swiftmagex-mcp`), благодаря чему AI-агенты могут
вызывать те же возможности в виде инструментов.

Авторитативная спецификация — `SwiftMageX-MVP-0.1-spec.md`; описание того,
что вошло в v0.1.0, — в `RELEASE_NOTES.md`.

## Требования

- macOS 14+ на Apple silicon (arm64)
- Swift 6.0+ (Xcode 16+) — нужен только для сборки из исходников
- API-ключ Gemini в переменной `SWIFTMAGEX_GEMINI_API_KEY`
  (или `GEMINI_API_KEY`) для команды `generate`. Для `resize` и `text`
  ключ не требуется.

## Установка

### Готовый бинарник (рекомендуется)

Скачайте `swiftmagex`, `swiftmagex-mcp` и `SHA256SUMS` из
[релиза v0.1.0](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0),
проверьте контрольные суммы и поместите бинарники в `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
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

Три подкоманды; глобальные флаги общие:

| Флаг | Эффект |
|---|---|
| `--json` | Выдаёт структурированный JSON-конверт в stdout вместо человекочитаемого текста. |
| `-v`, `--verbose` | Печатает диагностику в stderr. API-ключ **не** включается. |
| `--version` | Печатает `0.1.0` и завершает работу. |
| `-h`, `--help` | Показывает справку по команде. |

Пути в `--json`-выводе и в результатах MCP-инструментов всегда
**абсолютные** — агенту не нужно знать текущую рабочую директорию.

### `swiftmagex generate` — генерация по тексту через Gemini

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
| `--model <id>` | `gemini-2.5-flash-image` | `gemini-3.1-flash-image-preview` — для предварительного качества. |

```sh
# Одно изображение в текущую директорию
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Четыре landscape-варианта в директорию, JSON-вывод
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Воспроизводимый seed (зависит от провайдера)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Каждый выходной PNG содержит prompt, модель, seed, метку времени и
версию утилиты в `tEXt`-чанках (для JPEG — в EXIF-поле `UserComment`).

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

Ошибка (`resize` и `text` не выдают `provider` / `model`):

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

`swiftmagex-mcp` предоставляет три инструмента — `generate_image`,
`resize_image`, `overlay_text` — через stdio. Аргументы инструментов
повторяют флаги CLI; в результатах возвращаются абсолютные пути, так что
агенту не нужно знать рабочую директорию сервера. `generate_image`
дополнительно возвращает байты изображения как MCP `image`-контент, чтобы
вызывающая модель могла увидеть, что получилось.

### Подключение MCP-клиента (Claude Desktop)

Добавьте запись в конфиг MCP вашего клиента. Для Claude Desktop это
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
| `I/O error: input file not found: /…/foo.png` (exit 1) | Путь, переданный в `resize` / `text` (или `resize_image` / `overlay_text`), не существует или нечитаем. | Передайте абсолютный путь, проверьте права, убедитесь, что формат — один из PNG / JPEG / HEIC / WebP (запись только в PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Gatekeeper поставил карантин на скачанный бинарник. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (и то же для `swiftmagex-mcp`). |

## Область и статус

Это 0.1 MVP — три команды, один провайдер (Gemini), один MCP-сервер. Всё,
что за этой границей, отложено; полный список вне области см. в
спецификации
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, локальные провайдеры, дистрибуция через Homebrew,
конфиг-файл, Keychain и т. п.).

## Лицензия

TBD.
