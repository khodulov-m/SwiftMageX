# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI de generación y procesamiento de imágenes solo para macOS. SwiftMageX
es un *orquestador*: invoca la API de imágenes de Google AI (Gemini o Imagen) para generar y realiza
operaciones rasterizadas locales (resize, superposición de texto,
composición, capturas para App Store, eliminación de fondo, recorte
sensible a la saliencia) con CoreImage / CoreText / ImageIO / Vision,
todo desde un pequeño paquete Swift con exactamente dos dependencias
externas. La misma biblioteca central
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
  Gemini como para Imagen. `resize`, `text`, `composite`, `appstore`, `remove-bg` y `crop` no requieren clave.

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

Ocho subcomandos, todos comparten los mismos flags globales:

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

### `swiftmagex edit` — imagen a imagen / inpainting vía Gemini

Envía una imagen de origen (y una máscara opcional) a un modelo Gemini junto
con el prompt de texto. La imagen viaja como parte `inlineData` dentro de la
misma llamada `:generateContent` que usa `generate` — sin nuevo endpoint, sin
nueva dependencia.

```
swiftmagex edit <input> <prompt> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<input>` | — | Obligatorio. Imagen de origen (PNG o JPEG). |
| `<prompt>` | — | Obligatorio. Instrucción de texto que describe la edición. |
| `--mask <ruta>` | — | Máscara opcional en escala de grises o binaria (PNG o JPEG). El blanco marca la región a editar; el negro la preserva. |
| `-o`, `--output <ruta>` | `./` | Archivo o directorio. Si es directorio, los archivos se nombran `swiftmagex_{timestamp}_{index}.png`. |
| `-n`, `--count <1–4>` | `1` | Cantidad de variantes. Cada una es una petición separada. |
| `--seed <uint64>` | — | Se registra en metadatos incluso si el proveedor lo ignora. |
| `--model <id>` | `gemini-2.5-flash-image` | Debe ser un modelo Gemini — la forma `:predict` de Imagen no acepta entradas de imagen inline y se rechaza con código de salida 2. |

```sh
# Cambiar el color de un sujeto
swiftmagex edit apple.png "make the apple green instead of red" -o edited.png

# Inpaint de una región con máscara
swiftmagex edit photo.png "replace the marked region with a sunset sky" \
  --mask sky-mask.png -o photo_edited.png

# Cuatro variantes de la misma edición
swiftmagex edit shot.jpg "add a snowy mountain in the background" -n 4 -o ./out
```

Las salidas editadas llevan los mismos metadatos `tEXt`/EXIF que `generate` —
el prompt registrado es la instrucción de edición, no el prompt original de
generación.

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

### `swiftmagex composite` — pegar una imagen sobre otra

```
swiftmagex composite <fondo> --overlay <primer-plano> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<fondo>` | — | La imagen de lienzo. |
| `--overlay <ruta>` | — | Obligatorio. Primer plano pegado encima (respeta el alfa). |
| `--position` | `center` | Los mismos siete anclajes que `text`. |
| `--scale <fracción>` | `1.0` | Tamaño del primer plano como fracción del fondo; conserva la relación de aspecto. |
| `--offset-x`, `--offset-y <px>` | `0` | Desplazamiento desde el anclaje (positivo = derecha / abajo). |
| `--opacity <0.0–1.0>` | `1.0` | Opacidad de fusión del primer plano. |
| `-o`, `--output <ruta>` | junto al fondo | |
| `--format <png\|jpeg>`, `--quality` | igual que el fondo / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — capturas para App Store Connect

Enmarca una captura en un marco de dispositivo, la escala sobre un fondo,
superpone un pie de foto opcional y escribe el resultado en uno o varios
tamaños de píxeles de iPhone de App Store Connect, en lote y de una sola pasada.

```
swiftmagex appstore <captura> --background <fondo> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<captura>` | — | La captura colocada dentro del marco. |
| `--background <ruta>` | — | Obligatorio. Rellena (cover) detrás del dispositivo. |
| `--frame <ruta\|id>` | auto | Marco de iPhone: ruta a un PNG con un recorte de pantalla transparente, o un [id de marco integrado](#marcos-de-dispositivo-integrados) (p. ej. `iphone-6.5-pommeplate-spacegray`). Omítelo para que se elija automáticamente un marco integrado del dispositivo solicitado, si hay uno disponible. |
| `--list-frames` | — | Lista los marcos de dispositivo integrados y sale. Combínalo con `--json` para una salida parseable. |
| `--screen-rect <x,y,w,h>` | autodetección | Dónde va la captura dentro del marco. Si se omite, se detecta desde el alfa del marco. |
| `--device <id>` | `iphone-6.9` | Repetible. Uno de `iphone-6.9` (1290×2796), `iphone-6.5` (1242×2688), `iphone-5.5` (1242×2208) o `all`. |
| `--orientation <portrait\|landscape>` | `portrait` | Intercambia las dimensiones del dispositivo. |
| `--scale <fracción>` | `0.85` | Tamaño del dispositivo enmarcado como fracción del lienzo. |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | Dónde se sitúa el dispositivo sobre el fondo. |
| `--caption <cadena>` | — | Texto de pie de foto opcional. |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, sistema, `96`, `#FFFFFF`, —, `0` | Estilo del pie de foto (mismo motor que `text`). |
| `-o`, `--output <dir>` | `./` | **Directorio** de salida; los archivos se llaman `appstore_{device}_{w}x{h}.png`. |

```sh
# Marco integrado de iPhone 6.5" (no hace falta --frame)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# Marco propio, todos los tamaños de iPhone del catálogo de una vez
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### Marcos de dispositivo integrados

SwiftMageX incluye un marco de iPhone 11 Pro Max / XS Max bajo licencia CC0,
tomado de [PommePlate](https://github.com/ephread/PommePlate) (Space Grey,
derivado con un recorte de pantalla incrustado — véase
[Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md)).
Con `--device iphone-6.5` se usa automáticamente; pasa `--frame <ruta>` para
sobrescribirlo con tu propia ilustración. Para listar todo lo integrado:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

Los marcos aportados por el usuario siguen funcionando igual: cualquier PNG
con un hueco de pantalla transparente; la región de pantalla se halla a partir
del canal alfa (o fíjala con `--screen-rect`).

### `swiftmagex remove-bg` — eliminación de fondo local

Recorta el sujeto destacado en primer plano y lo deja sobre un fondo
transparente, usando la segmentación on-device de Vision — sin API de IA,
sin clave, sin consumo de cuota. El resultado siempre lleva canal alfa, así
que se escribe como PNG (una extensión `--output` distinta de `.png` se
convierte a `.png`).

```
swiftmagex remove-bg <input> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC o WebP. |
| `-o`, `--output <ruta>` | hermano del origen | Siempre se escribe como PNG. |

```sh
# Recortar el sujeto sobre un fondo transparente
swiftmagex remove-bg photo.jpg -o cutout.png

# Por defecto, un PNG hermano del origen
swiftmagex remove-bg product.heic
```

Si no se detecta un sujeto destacado en primer plano, el comando falla con
un error de raster (exit 1).

### `swiftmagex crop` — recorte por relación de aspecto sensible a la saliencia

Recorta a una relación de aspecto indicada por el usuario centrando la
ventana de recorte sobre el sujeto destacado detectado por el modelo de
atención on-device de Vision — no sobre el centro geométrico. Sin API de
IA, sin clave, sin consumo de cuota. La salida conserva la escala de
píxeles del origen (es un recorte, no un resize) y por defecto usa el
mismo formato.

```
swiftmagex crop <input> --aspect <W:H> [opciones]
```

| Opción | Predeterminado | Notas |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC o WebP. Escritura solo PNG / JPEG. |
| `--aspect <W:H>` | — | Obligatorio. Dos enteros positivos, p. ej. `1:1`, `4:5`, `9:16`. |
| `-o`, `--output <ruta>` | hermano del origen | |
| `--format <png\|jpeg>` | igual al origen | HEIC / WebP cae a PNG por defecto. |
| `--quality <0.0–1.0>` | `0.9` | Solo JPEG. |

```sh
# Recorte cuadrado centrado en el sujeto destacado
swiftmagex crop photo.jpg --aspect 1:1

# Recorte vertical 9:16, re-codificado como JPEG
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

Cuando la saliencia no encuentra objetos destacados (raro; imágenes planas
o uniformes), recurre a un recorte centrado para que la relación de aspecto
solicitada se respete igualmente.

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

Error (`resize`, `text`, `remove-bg` y `crop` omiten `provider` / `model`):

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

`swiftmagex-mcp` expone nueve herramientas — `generate_image`, `edit_image`,
`resize_image`, `overlay_text`, `composite_images`, `appstore_screenshots`,
`list_frames`, `remove_background` y `smart_crop` — sobre stdio. Los argumentos espejan
los flags del CLI (claves en snake_case, p. ej. `font_size`, `screen_rect`,
`devices`); los resultados reportan rutas absolutas para que el
agente no necesite saber el directorio de trabajo del servidor.
`generate_image` y `edit_image` además devuelven los bytes de la imagen como
contenido MCP `image` para que el modelo invocante pueda ver lo que se produjo.
`list_frames` enumera los marcos de dispositivo integrados cuyos ids
acepta el argumento `frame` de `appstore_screenshots`.

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
| `I/O error: input file not found: /…/foo.png` (exit 1) | La ruta de un comando local (`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop`, o sus herramientas MCP) no existe o no es legible. | Pasa una ruta absoluta, verifica permisos, comprueba que el formato sea PNG / JPEG / HEIC / WebP (la escritura es solo PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Cuarentena de Gatekeeper sobre un binario descargado. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (e igual para `swiftmagex-mcp`). |

## Alcance y estado

Esta es la MVP 0.1 — tres comandos, dos proveedores de imágenes de
Google AI (Gemini e Imagen), un servidor MCP — más cuatro adiciones
locales posteriores a 0.1: `composite`, `appstore`, `remove-bg` y `crop`
(composición, capturas para App Store Connect, eliminación de fondo
basada en Vision y recorte sensible a la saliencia). Cualquier cosa
fuera de ese límite está diferida; ver la lista
completa fuera de alcance en spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, proveedores locales, distribución Homebrew, archivo
de configuración, Keychain, …).

## Licencia

TBD.
