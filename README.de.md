# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI für Bildgenerierung und Bildverarbeitung — nur für macOS. SwiftMageX
ist ein *Orchestrator*: er ruft die Gemini-API zur Generierung auf und
führt lokale Rasteroperationen (Resize, Text-Overlay) mit CoreImage /
CoreText / ImageIO durch — alles aus einem kleinen Swift-Paket mit
genau zwei externen Abhängigkeiten. Dieselbe Kernbibliothek bedient
einen Model-Context-Protocol-Server (`swiftmagex-mcp`), damit
KI-Agenten dieselben Fähigkeiten als Tools nutzen können.

Die maßgebliche Spezifikation liegt in `SwiftMageX-MVP-0.1-spec.md`;
was in v0.1.0 ausgeliefert wurde, steht in `RELEASE_NOTES.md`.

## Voraussetzungen

- macOS 14+ auf Apple silicon (arm64)
- Swift-6.0+-Toolchain (Xcode 16+) — nur für den Bau aus den Quellen
- Ein Gemini-API-Key in `SWIFTMAGEX_GEMINI_API_KEY` (oder
  `GEMINI_API_KEY`) für den `generate`-Befehl. `resize` und `text`
  benötigen keinen Key.

## Installation

### Vorgebautes Binary (empfohlen)

Lade `swiftmagex`, `swiftmagex-mcp` und `SHA256SUMS` aus dem
[v0.1.0-Release](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0),
prüfe die Checksummen und lege die Binaries in deinen `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

Falls Gatekeeper die Downloads in Quarantäne nimmt, entferne das
Attribut:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### Aus den Quellen bauen

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# Binaries landen in .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### Ohne Installation aus den Quellen ausführen

```sh
swift run swiftmagex <unterbefehl> …     # CLI
swift run swiftmagex-mcp                 # MCP-Server (stdio-Transport)
swift test                               # vollständige Testsuite
scripts/check.sh                         # Build + Tests in einem Schritt
```

### Konfiguration

Exportiere den Gemini-API-Key im Shell-Profil (nur für `generate`
erforderlich):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # bevorzugt
# alternativ liest das Tool auch:
export GEMINI_API_KEY="…"
```

Den Key nie in eingecheckte Skripte schreiben. Die CLI gibt den Key
nie aus, loggt ihn nicht und schreibt ihn nicht auf die Platte — auch
nicht unter `--verbose` und nicht in Output-Datei-Metadaten.

## Schnelles Handbuch

Drei Unterbefehle, alle teilen sich dieselben globalen Flags:

| Globales Flag | Wirkung |
|---|---|
| `--json` | Strukturierte JSON-Hülle auf stdout statt menschenlesbarem Text. |
| `-v`, `--verbose` | Diagnose-Meldungen auf stderr. Enthält den API-Key **nicht**. |
| `--version` | Gibt `0.1.0` aus und endet. |
| `-h`, `--help` | Zeigt Hilfe für den Befehl. |

Ausgabepfade sind in `--json`-Ausgabe und in MCP-Tool-Ergebnissen
immer **absolut** — Agenten müssen das Arbeitsverzeichnis nicht
kennen.

### `swiftmagex generate` — Text-zu-Bild via Gemini

```
swiftmagex generate <prompt> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<prompt>` | — | Erforderliches Positionsargument. |
| `-o`, `--output <pfad>` | `./` | Datei oder Verzeichnis. Bei Verzeichnis lauten Dateinamen `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | Seitenverhältnis-Hinweis. Tatsächliche Auflösung hängt vom Modell ab. |
| `-n`, `--count <1–4>` | `1` | Anzahl Varianten. Jede Variante ist eine eigene Anfrage. |
| `--seed <uint64>` | — | Wird in Metadaten festgehalten, auch wenn der Provider den Seed ignoriert. |
| `--model <id>` | `gemini-2.5-flash-image` | `gemini-3.1-flash-image-preview` für Preview-Qualität. |

```sh
# Einzelnes Bild ins aktuelle Verzeichnis
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Vier Landscape-Varianten in ein Verzeichnis, strukturierte Ausgabe
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Reproduzierbarer Seed (providerabhängig)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Beispiel — der folgende Aufruf hat das untenstehende Bild erzeugt (1024×1024
PNG mit `gemini-2.5-flash-image`):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="Generierter roter Apfel auf weißem Hintergrund" width="320" />

Jede ausgegebene PNG-Datei trägt Prompt, Modell, Seed, Zeitstempel und
Toolversion in `tEXt`-Chunks (JPEG nutzt das EXIF-Feld `UserComment`).

### `swiftmagex resize` — lokales Resize / Crop / Formatwechsel

```
swiftmagex resize <input> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC oder WebP. Schreiben nur in PNG / JPEG. |
| `-w`, `--width <px>` | — | Mindestens eines von width / height nötig. |
| `-h`, `--height <px>` | — | Bei nur einem wird das andere aus dem Seitenverhältnis berechnet. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` und `fill` benötigen beide Dimensionen. |
| `-o`, `--output <pfad>` | Geschwister-Datei zur Quelle | Standard: neben der Quelldatei. |
| `--format <png\|jpeg>` | wie Quelle | HEIC- / WebP-Quellen fallen auf PNG zurück. |
| `--quality <0.0–1.0>` | `0.9` | Nur JPEG. |

```sh
# Quadratisches Thumbnail, Überstand wegschneiden
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# 1200 px breites Banner, JPEG mit 80 % Qualität
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# Halbe Größe, Seitenverhältnis erhalten (nur Breite)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — Text-Overlay

```
swiftmagex text <input> --text "<string>" [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<input>` | — | Bild, auf das gezeichnet wird. |
| `--text <string>` | — | Erforderlich. `\n` erzeugt Zeilenumbruch; lange Zeilen werden wortweise umgebrochen. |
| `--position` | `bottom` | Eines von `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font <name>` | Systemfont | Z. B. `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` oder `#RRGGBBAA`. |
| `--stroke <hex>` | — | Weglassen heißt keine Kontur. |
| `--stroke-width <pt>` | `2.0` | Nur relevant, wenn `--stroke` gesetzt ist. |
| `-o`, `--output <pfad>` | Geschwister-Datei zur Quelle | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### JSON-Ausgabe-Schema

Jeder Befehl emittiert unter `--json` dieselbe Hülle. Schlüssel sind
sortiert; nil-Felder fehlen vollständig (keine `null`-Platzhalter).

Erfolg:

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

Fehler (`resize` und `text` lassen `provider` / `model` weg):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

Stream-Konvention: Ergebnisse → **stdout**; Diagnose (`--verbose`) →
**stderr**. Fehler-JSON unter `--json` geht ebenfalls auf stdout,
damit ein Agent alles an einer Stelle parsen kann.

### Exit-Codes

| Code | Bedeutung | Beispiel |
|---|---|---|
| `0` | Erfolg | — |
| `1` | Unerwartet / Raster / I/O | unlesbare Eingabedatei, Encoder-Fehler |
| `2` | Ungültige Eingabe | falsche `--fit`-Kombination, fehlerhafter Hex-Farbwert, `--count` außerhalb 1–4 |
| `3` | Provider- / API-Fehler | Gemini 5xx, `429` nach 5 Retries |
| `4` | Konfiguration | `SWIFTMAGEX_GEMINI_API_KEY` fehlt |

429-Retry-Strategie: bis zu 5 Versuche, exponentielles Backoff
1 s → 2 s → 4 s → 8 s → 16 s.

## MCP-Server

`swiftmagex-mcp` stellt drei Tools — `generate_image`,
`resize_image`, `overlay_text` — über stdio bereit. Tool-Argumente
spiegeln die CLI-Flags wider; Ergebnisse melden absolute Dateipfade,
damit der aufrufende Agent das Arbeitsverzeichnis des Servers nicht
kennen muss. `generate_image` liefert zusätzlich die Bildbytes als
MCP-`image`-Inhalt, damit das aufrufende Modell das Resultat
inspizieren kann.

### Claude Code einrichten

Claude Code registriert MCP-Server über `claude mcp add`. Im Repository,
in dem SwiftMageX verfügbar sein soll, ausführen:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Damit er in jeder Claude-Code-Session auf diesem Rechner verfügbar ist,
den User-Scope verwenden:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Registriertes prüfen mit `claude mcp list` oder
`claude mcp get swiftmagex`, entfernen mit `claude mcp remove swiftmagex`.
Standard-Transport ist stdio — kein `--transport`-Flag nötig.

### Claude Desktop einrichten

Einen Eintrag in
`~/Library/Application Support/Claude/claude_desktop_config.json`
aufnehmen:

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

Der `env`-Block beschränkt den API-Key auf genau diesen Server —
er landet nicht im allgemeinen Environment des Clients.

## Troubleshooting

| Symptom | Wahrscheinliche Ursache | Lösung |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | Kein API-Key im Environment bei `generate` bzw. `generate_image`. | `SWIFTMAGEX_GEMINI_API_KEY` (oder ersatzweise `GEMINI_API_KEY`) exportieren; für MCP in den `env`-Block des Clients eintragen (siehe oben). |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini hat in jedem Versuch im Backoff-Fenster (1 s → 16 s) `429` geliefert. | Auf Quota-Erneuerung warten, Projekt wechseln oder später erneut starten. Backoff-Schema ist fix; siehe Spec §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | Der an `resize` / `text` (oder `resize_image` / `overlay_text`) übergebene Pfad existiert nicht oder ist nicht lesbar. | Absoluten Pfad übergeben, Berechtigungen prüfen, Format aus PNG / JPEG / HEIC / WebP wählen (Schreiben nur in PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Gatekeeper-Quarantäne auf einem heruntergeladenen Binary. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (und dasselbe für `swiftmagex-mcp`). |

## Umfang und Status

Dies ist das 0.1 MVP — drei Befehle, ein Provider (Gemini), ein
MCP-Server. Alles außerhalb dieser Grenze ist aufgeschoben; die
vollständige Out-of-Scope-Liste findet sich in spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / Inpainting, lokale Provider, Homebrew-Distribution,
Konfigurationsdatei, Keychain, …).

## Lizenz

TBD.
