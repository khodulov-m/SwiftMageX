# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI de generación y procesamiento de imágenes solo para macOS. SwiftMageX
es un *orquestador*: invoca la API de imágenes de Google AI (Gemini o Imagen) para generar y realiza
operaciones rasterizadas locales (resize, superposición de texto) con
CoreImage / CoreText / ImageIO, todo desde un pequeño paquete Swift con
exactamente dos dependencias externas. La misma biblioteca central
respalda un servidor Model Context Protocol (`swiftmagex-mcp`) para que
los agentes de IA puedan usar esas capacidades como herramientas.

La especificación autorizada está en `SwiftMageX-MVP-0.1-spec.md` y lo
que se publicó en la v0.1.0 está en `RELEASE_NOTES.md`.

## Requisitos

- macOS 14+ en Apple silicon (arm64)
- Toolchain Swift 6.0+ (Xcode 16+) — solo necesario para compilar desde
  fuente
- Una clave de la API de Google AI en `SWIFTMAGEX_GEMINI_API_KEY`
  (o `GEMINI_API_KEY`) para el comando `generate` — válida tanto para
  Gemini como para Imagen. `resize` y `text` no requieren clave.

## Instalación

### Binario precompilado (recomendado)

Descarga `swiftmagex`, `swiftmagex-mcp` y `SHA256SUMS` desde la
[release v0.1.0](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0),
verifica las sumas y coloca los binarios en tu `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

Si Gatekeeper marca las descargas en cuarentena, elimina el atributo:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### Compilar desde fuente

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# los binarios quedan en .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### Ejecutar desde fuente sin instalar

```sh
swift run swiftmagex <subcomando> …      # CLI
swift run swiftmagex-mcp                 # servidor MCP (transporte stdio)
swift test                               # suite de pruebas completa
scripts/check.sh                         # build + tests en un solo paso
```

### Configuración

Exporta la clave de la API de Gemini en tu perfil de shell (solo
necesaria para `generate`):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # preferida
# o, como alternativa, la herramienta también lee:
export GEMINI_API_KEY="…"
```

Nunca incrustes la clave en scripts versionados. El CLI nunca imprime,
loguea ni escribe la clave en disco — ni siquiera con `--verbose` ni en
los metadatos del archivo de salida.

## Manual rápido

Tres subcomandos, todos comparten los mismos flags globales:

| Flag global | Efecto |
|---|---|
| `--json` | Emite un sobre JSON estructurado en stdout en lugar de texto humano. |
| `-v`, `--verbose` | Imprime mensajes de diagnóstico en stderr. **No** incluye la clave de API. |
| `--version` | Imprime `0.1.0` y termina. |
| `-h`, `--help` | Muestra ayuda del comando. |

Las rutas de salida son siempre **absolutas** en la salida `--json` y en
los resultados de las herramientas MCP — los agentes no necesitan
conocer el directorio de trabajo.

### `swiftmagex generate` — texto a imagen vía Gemini o Imagen

```
swiftmagex generate <prompt> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<prompt>` | — | Argumento posicional obligatorio. |
| `-o`, `--output <ruta>` | `./` | Archivo o directorio. Si es directorio, los archivos se nombran `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | Pista de proporción. La resolución real depende del modelo. |
| `-n`, `--count <1–4>` | `1` | Cantidad de variantes. Cada una es una petición separada. |
| `--seed <uint64>` | — | Se registra en metadatos incluso si el proveedor lo ignora. |
| `--model <id>` | `gemini-2.5-flash-image` | Integrados: familia Gemini (`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) y familia Imagen (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Los IDs desconocidos se enrutan por prefijo `imagen-`/`gemini-`. |

```sh
# Una sola imagen en el directorio actual
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Cuatro variantes apaisadas a un directorio, salida estructurada
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Seed reproducible (depende del proveedor)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Ejemplo — la llamada siguiente generó la imagen mostrada abajo (PNG 1024×1024
con `gemini-2.5-flash-image`):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="Manzana roja generada sobre fondo blanco" width="320" />

Cada PNG de salida lleva el prompt, modelo, seed, timestamp y versión de
la herramienta en chunks `tEXt` (los JPEG usan el campo EXIF `UserComment`).

### `swiftmagex resize` — resize / recorte / conversión local

```
swiftmagex resize <input> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC o WebP. Escritura solo PNG / JPEG. |
| `-w`, `--width <px>` | — | Se requiere al menos uno de width / height. |
| `-h`, `--height <px>` | — | Si solo se da uno, el otro se calcula por proporción. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` y `fill` requieren ambas dimensiones. |
| `-o`, `--output <ruta>` | hermano del origen | Por defecto, junto al archivo de origen. |
| `--format <png\|jpeg>` | igual al origen | Los orígenes HEIC / WebP usan PNG por defecto. |
| `--quality <0.0–1.0>` | `0.9` | Solo JPEG. |

```sh
# Miniatura cuadrada, recortar el sobrante
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# Banner de 1200 de ancho, recodificado a JPEG al 80 %
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# Mitad del tamaño, proporción preservada (solo ancho)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — superposición de texto

```
swiftmagex text <input> --text "<cadena>" [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<input>` | — | Imagen sobre la que dibujar. |
| `--text <cadena>` | — | Obligatorio. `\n` produce salto de línea; las líneas largas hacen wrap por palabras. |
| `--position` | `bottom` | Uno de `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font <nombre>` | fuente del sistema | Ej. `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` o `#RRGGBBAA`. |
| `--stroke <hex>` | — | Omitir para no aplicar trazo. |
| `--stroke-width <pt>` | `2.0` | Solo se usa cuando `--stroke` está activo. |
| `-o`, `--output <ruta>` | hermano del origen | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### Esquema de salida JSON

Cada comando emite el mismo sobre con `--json`. Las claves van ordenadas;
los campos nulos se omiten por completo (sin `null` placeholders).

Éxito:

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

Error (`resize` y `text` omiten `provider` / `model`):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

Convenciones de streams: resultados → **stdout**; diagnósticos
(`--verbose`) → **stderr**. El JSON de error con `--json` también va a
stdout para que un agente pueda parsearlo en un único lugar.

### Códigos de salida

| Código | Significado | Ejemplo |
|---|---|---|
| `0` | Éxito | — |
| `1` | Fallo inesperado / raster / I/O | archivo de entrada ilegible, fallo del codificador |
| `2` | Entrada inválida | combinación errónea de `--fit`, color hex mal formado, `--count` fuera de 1–4 |
| `3` | Fallo del proveedor / API | 5xx de Gemini, `429` tras 5 reintentos |
| `4` | Configuración | falta `SWIFTMAGEX_GEMINI_API_KEY` |

Política de retry en 429: hasta 5 reintentos con backoff exponencial
1 s → 2 s → 4 s → 8 s → 16 s.

## Servidor MCP

`swiftmagex-mcp` expone tres herramientas — `generate_image`,
`resize_image`, `overlay_text` — sobre stdio. Los argumentos espejan los
flags del CLI; los resultados reportan rutas absolutas para que el
agente no necesite saber el directorio de trabajo del servidor.
`generate_image` además devuelve los bytes de la imagen como contenido
MCP `image` para que el modelo invocante pueda ver lo que se produjo.

### Configurar Claude Code

Claude Code registra servidores MCP mediante `claude mcp add`. Dentro del
repo donde quieras tener SwiftMageX disponible, ejecuta:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Para que esté disponible en cada sesión de Claude Code en esta máquina,
usa el scope de usuario:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Revisa lo registrado con `claude mcp list` o `claude mcp get swiftmagex`,
y elimínalo con `claude mcp remove swiftmagex`. El transporte por defecto
es stdio — no hace falta el flag `--transport`.

### Configurar Claude Desktop

Añade una entrada a
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

El bloque `env` limita la clave de API solo a este servidor — nunca
queda en el entorno general del cliente.

## Resolución de problemas

| Síntoma | Causa probable | Solución |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | No hay clave en el entorno al correr `generate` o invocar `generate_image`. | Exporta `SWIFTMAGEX_GEMINI_API_KEY` (o el alternativo `GEMINI_API_KEY`); para MCP, añádelo al bloque `env` del cliente como se muestra arriba. |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini devolvió `429` en cada intento dentro de la ventana de backoff (1 s → 16 s). | Espera a que se reponga la cuota, cambia de proyecto, o reintenta luego. La política de backoff es fija; ver spec §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | La ruta de `resize` / `text` (o `resize_image` / `overlay_text`) no existe o no es legible. | Pasa una ruta absoluta, verifica permisos, comprueba que el formato sea PNG / JPEG / HEIC / WebP (la escritura es solo PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Cuarentena de Gatekeeper sobre un binario descargado. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (e igual para `swiftmagex-mcp`). |

## Alcance y estado

Esta es la MVP 0.1 — tres comandos, dos proveedores de imágenes de
Google AI (Gemini e Imagen), un servidor MCP. Cualquier cosa fuera de ese límite está diferida; ver la lista
completa fuera de alcance en spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, proveedores locales, distribución Homebrew, archivo
de configuración, Keychain, …).

## Licencia

TBD.
