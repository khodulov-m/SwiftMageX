# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

**Bilder direkt im Terminal generieren, bearbeiten und veredeln — und das
Gleiche Ihrem KI-Agenten beibringen.** SwiftMageX ist ein natives
macOS-CLI: Für Generierung und Bearbeitung sprechen Googles Bildmodelle
(Gemini und Imagen), die alltägliche Rasterarbeit erledigt Ihr Mac selbst.

Was Sie bekommen:

- 🎨 **Generieren und Bearbeiten mit einem Befehl** — Text-zu-Bild,
  Bild-zu-Bild, Multi-Bild-Komposition und maskenbasiertes Inpainting; das
  Modell ist pro Aufruf wählbar, passend zu Ihren Qualitätsanforderungen.
- 🤖 **Claude Code, das Bilder kann** — der mitgelieferte MCP-Server
  (`swiftmagex-mcp`) stellt jede Fähigkeit als Tool bereit, sodass Claude
  Code, Claude Desktop oder jeder MCP-Client lernt, Bilder im eigenen
  Workflow zu generieren, zu bearbeiten und zu verarbeiten.
- 📱 **App-Store-Screenshots in einem Durchlauf** — Screenshot in einen
  Geräterahmen setzen, auf einen Hintergrund legen, Caption hinzufügen und
  auf alle App-Store-Connect-Größen skalieren.
- 🔒 **Privat und kostenlos, wo es zählt** — Resize, Text-Overlay,
  Compositing, Hintergrundentfernung und Smart Crop laufen vollständig auf
  dem Gerät via CoreImage / CoreText / Vision. Kein API-Key, nichts
  verlässt Ihren Mac.
- 🪶 **Winziger Fußabdruck** — ein kleines Swift-Paket, genau zwei externe
  Abhängigkeiten, zwei eigenständige Binaries.

Die maßgebliche Spezifikation liegt in `SwiftMageX-MVP-0.1-spec.md`;
was in v0.2.0 ausgeliefert wurde, steht in `RELEASE_NOTES.md`.

## Voraussetzungen

- macOS 14+ auf Apple silicon (arm64)
- Swift-6.0+-Toolchain (Xcode 16+) — nur für den Bau aus den Quellen
- Ein Google-AI-API-Key in `SWIFTMAGEX_GEMINI_API_KEY` (oder
  `GEMINI_API_KEY`) für den `generate`-Befehl — funktioniert für
  Gemini- und Imagen-Modelle. `resize`, `text`, `composite`, `appstore`,
  `remove-bg` und `crop` benötigen keinen Key.

## Installation

### Vorgebautes Binary (empfohlen)

Lade `swiftmagex`, `swiftmagex-mcp` und `SHA256SUMS` aus dem
[v0.2.0-Release](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.2.0),
prüfe die Checksummen und lege die Binaries in deinen `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.2.0
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

Acht Unterbefehle, alle teilen sich dieselben globalen Flags:

| Globales Flag | Wirkung |
|---|---|
| `--json` | Strukturierte JSON-Hülle auf stdout statt menschenlesbarem Text. |
| `-v`, `--verbose` | Diagnose-Meldungen auf stderr. Enthält den API-Key **nicht**. |
| `--cache-dir <pfad>` | Cached `generate`/`edit`-Antworten unter `<pfad>`, sodass identische Anfragen die bereits aufgezeichneten Provider-Bytes replayen statt die API zu rufen. Opt-in — siehe Cache-Abschnitt unten. |
| `--version` | Gibt `0.2.0` aus und endet. |
| `-h`, `--help` | Zeigt Hilfe für den Befehl. |

Ausgabepfade sind in `--json`-Ausgabe und in MCP-Tool-Ergebnissen
immer **absolut** — Agenten müssen das Arbeitsverzeichnis nicht
kennen.

### `swiftmagex generate` — Text-zu-Bild via Gemini oder Imagen

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
| `--model <id>` | `gemini-2.5-flash-image` | Eingebaut: Gemini-Familie (`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) und Imagen-Familie (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Unbekannte IDs werden per `imagen-`/`gemini-`-Präfix geroutet. |

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

**Wählen Sie das Modell passend zu Ihren Qualitätsanforderungen.** Modelle
sind pro Aufruf über `--model` austauschbar — am Befehl ändert sich sonst
nichts. Das Standardmodell `gemini-2.5-flash-image` ist der stabile
Allrounder; das neueste `gemini-3.1-flash-image-preview` liefert deutlich
detailliertere Ergebnisse und wählt von sich aus breitere, nicht-quadratische
Bildausschnitte; die Imagen-Familie bietet explizite Kontrolle über das
Seitenverhältnis (`--size` wird auf `aspectRatio` abgebildet), wobei
`imagen-4.0-fast-generate-001` auf Geschwindigkeit und
`imagen-4.0-ultra-generate-001` auf maximale Qualität ausgelegt ist (ein
Bild pro Aufruf). `gemini-3.1-flash-image-preview` hat zum Beispiel dieses
1408×768-Bild erzeugt:

```sh
swiftmagex generate "A red fox curled up on a mossy rock in a misty autumn forest, golden leaves falling, soft photorealistic style" \
  --model gemini-3.1-flash-image-preview -o fox.png
```

<img src="docs/images/example-generate-fox-gemini31.png" alt="Detailreicher Fuchs im Herbstwald, erzeugt von gemini-3.1-flash-image-preview" width="480" />

### `swiftmagex edit` — Bild-zu-Bild / Multi-Bild / Inpainting via Gemini

Sendet ein Quellbild (plus eventuelle weitere Referenzen und eine optionale
Maske) zusammen mit dem Text-Prompt an ein Gemini-Modell. Jedes Bild reist
als `inlineData`-Part im selben `:generateContent`-Aufruf mit, den `generate`
verwendet — kein neuer Endpoint, keine neue Abhängigkeit.

```
swiftmagex edit <input> <prompt> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<input>` | — | Erforderlich. Primäres Quellbild (PNG oder JPEG). |
| `<prompt>` | — | Erforderlich. Text-Anweisung, die die Bearbeitung beschreibt. |
| `--reference <pfad>` | — | Wiederholbar. Zusätzliches Referenzbild (PNG oder JPEG). Jedes `--reference` fügt einen weiteren inline Image-Part hinzu, den der Prompt kombinieren kann — z. B. „nimm das Motiv aus Bild 1 und setze es in Szene 2". |
| `--mask <pfad>` | — | Optionale Graustufen-/Binärmaske (PNG oder JPEG). Weiß markiert den zu bearbeitenden Bereich auf dem primären Bild, Schwarz erhält das Original. |
| `-o`, `--output <pfad>` | `./` | Datei oder Verzeichnis. Bei Verzeichnis werden Dateien `swiftmagex_{timestamp}_{index}.png` benannt. |
| `-n`, `--count <1–4>` | `1` | Anzahl der Varianten. Jede ist eine separate Anfrage. |
| `--seed <uint64>` | — | Wird in Metadaten aufgezeichnet, auch wenn der Provider ihn ignoriert. |
| `--model <id>` | `gemini-2.5-flash-image` | Muss ein Gemini-Modell sein — Imagens `:predict`-Form akzeptiert keine inline Bild-Eingaben und wird mit Exit-Code 2 abgelehnt. |

```sh
# Farbe eines Motivs ändern
swiftmagex edit apple.png "make the apple green instead of red" -o edited.png

# Bereich mit Maske inpainten
swiftmagex edit photo.png "replace the marked region with a sunset sky" \
  --mask sky-mask.png -o photo_edited.png

# Komposition aus zwei Referenzbildern
swiftmagex edit person.png "place the person from image 1 into the scene of image 2" \
  --reference street.png -o composed.png

# Vier Varianten derselben Bearbeitung
swiftmagex edit shot.jpg "add a snowy mountain in the background" -n 4 -o ./out
```

Beispiele — drei Vorher/Nachher-Paare (Quellen und Bearbeitungen in
[`examples/`](examples)):

| Quelle | Bearbeitet | Bearbeitungsprompt |
|---|---|---|
| <img src="examples/apple.png" alt="Roter Apfel auf weißem Hintergrund" width="200"> | <img src="examples/apple-edited.png" alt="Apfel in hellem Grün umgefärbt" width="200"> | `"Change the apple's color from red to bright green, keep everything else identical"` |
| <img src="examples/mountain.png" alt="Bergsee bei Sonnenaufgang" width="200"> | <img src="examples/mountain-edited.png" alt="Dieselbe Szene mit Heißluftballon über den Gipfeln" width="200"> | `"Add a single colorful hot-air balloon floating in the sky above the mountains"` |
| <img src="examples/cabin.png" alt="Holzhütte im Sommerwald" width="200"> | <img src="examples/cabin-edited.png" alt="Dieselbe Hütte unter Schnee" width="200"> | `"Transform the scene from a sunny summer day to a snowy winter day"` |

Multi-Bild-Komposition — Motiv und Szene über `--reference` kombinieren:

| Eingabe (Motiv) | Referenz (Szene) | Ergebnis |
|---|---|---|
| <img src="examples/canoe.png" alt="Holzkanu auf weißem Hintergrund" width="200"> | <img src="examples/mountain.png" alt="Bergsee bei Sonnenaufgang" width="200"> | <img src="examples/canoe-on-mountain-lake.png" alt="Kanu, das auf dem Bergsee schwimmt" width="200"> |

```sh
swiftmagex edit examples/canoe.png \
  "Place the canoe from image 1 onto the lake from image 2, match the lighting and add reflections" \
  --reference examples/mountain.png -o examples/canoe-on-mountain-lake.png
```

Bearbeitete Ausgaben tragen dieselben `tEXt`/EXIF-Metadaten wie `generate` —
der aufgezeichnete Prompt ist die Bearbeitungsanweisung, nicht der
ursprüngliche Generierungs-Prompt.

### Antwort-Cache

`--cache-dir <pfad>` an `generate` oder `edit` weitergeben, um den
Netzwerkaufruf kurzzuschließen, wenn eine identische Anfrage schon einmal
beantwortet wurde. Der Cache ist content-addressed: der Schlüssel ist ein
SHA-256 über Model, Prompt, Size, Count, Seed plus SHA-256 jeder
Referenzbild- und Mask-Bytefolge. Bei einem Hit werden die Bytes von der
Platte replayed und trotzdem eine frische Output-Datei mit aktuellen
`tEXt`/EXIF-Metadaten (Timestamp, Tool-Version) geschrieben — nachgelagerte
Pipelines verhalten sich identisch.

```sh
# Erster Aufruf trifft die API; zweiter replayed aus /tmp/sx-cache.
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache --json
# → "cached": true im JSON für jedes replayte Bild
```

Hinweise:

- **Bewusst Opt-in.** Gemini honoriert `--seed` nicht, identische Eingaben
  sind also *gedacht* zu variieren — ein Cache-Hit verwandelt diese
  beabsichtigte Nicht-Determiniertheit lautlos in „jedes Mal dieselben
  Bytes". Nur `--cache-dir` setzen, wenn das gewollt ist.
- **Best-Effort.** Cache-I/O-Fehler (nicht beschreibbares Verzeichnis,
  korrupter Eintrag) führen zu einem normalen Netzwerkaufruf statt zum
  Abbruch des Kommandos.
- **Keine Eviction.** Der Cache wächst, bis `rm -rf` auf das Verzeichnis
  läuft.
- Caching wirkt nur auf `generate` / `edit` (lokale Raster-Kommandos
  rufen keinen Provider). Der MCP-Server stellt Caching in 0.1 nicht
  bereit; das CLI-Flag ist heute der einzige Einstieg.

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

### `swiftmagex composite` — ein Bild auf ein anderes legen

```
swiftmagex composite <hintergrund> --overlay <vordergrund> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<hintergrund>` | — | Das Leinwand-Bild. |
| `--overlay <pfad>` | — | Erforderlich. Vordergrund, der oben aufgelegt wird (Alpha wird beachtet). |
| `--position` | `center` | Dieselben sieben Anker wie bei `text`. |
| `--scale <bruch>` | `1.0` | Vordergrundgröße als Bruchteil des Hintergrunds; Seitenverhältnis bleibt erhalten. |
| `--offset-x`, `--offset-y <px>` | `0` | Verschiebung vom Anker (positiv = rechts / unten). |
| `--opacity <0.0–1.0>` | `1.0` | Deckkraft des Vordergrunds. |
| `-o`, `--output <pfad>` | neben dem Hintergrund | |
| `--format <png\|jpeg>`, `--quality` | wie Hintergrund / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — App-Store-Connect-Screenshots

Rahmt einen Screenshot in einen Geräterahmen, skaliert ihn auf einen Hintergrund,
legt eine optionale Bildunterschrift darüber und schreibt das Ergebnis in einer
oder mehreren App-Store-Connect-iPhone-Pixelgrößen — gebündelt in einem Durchlauf.

```
swiftmagex appstore <screenshot> --background <bg> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<screenshot>` | — | Der aufgenommene Screenshot, der in den Rahmen gesetzt wird. |
| `--background <pfad>` | — | Erforderlich. Hinter dem Gerät gefüllt (cover). |
| `--frame <pfad\|id>` | automatisch | iPhone-Rahmen: Pfad zu einer PNG mit transparentem Bildschirm-Ausschnitt oder eine [mitgelieferte Frame-ID](#integrierte-geräterahmen) (z. B. `iphone-6.5-pommeplate-spacegray`). Weglassen, um automatisch einen mitgelieferten Rahmen für das gewählte Gerät zu wählen, sofern vorhanden. |
| `--list-frames` | — | Listet die mitgelieferten Geräterahmen auf und beendet. Mit `--json` für eine maschinenlesbare Form. |
| `--screen-rect <x,y,w,h>` | automatisch | Wo der Screenshot im Rahmen sitzt. Wird ohne Angabe aus dem Alpha des Rahmens erkannt. |
| `--device <id>` | `iphone-6.9` | Wiederholbar. Eines von `iphone-6.9` (1290×2796), `iphone-6.5` (1242×2688), `iphone-5.5` (1242×2208) oder `all`. |
| `--orientation <portrait\|landscape>` | `portrait` | Tauscht die Gerätemaße. |
| `--scale <bruch>` | `0.85` | Größe des gerahmten Geräts als Bruchteil der Leinwand. |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | Wo das Gerät auf dem Hintergrund sitzt. |
| `--caption <string>` | — | Optionaler Untertitel-Text. |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, System, `96`, `#FFFFFF`, —, `0` | Untertitel-Styling (gleiche Engine wie `text`). |
| `-o`, `--output <verz>` | `./` | Ausgabe-**Verzeichnis**; Dateien heißen `appstore_{device}_{w}x{h}.png`. |

```sh
# Mitgelieferten iPhone-6.5"-Rahmen verwenden (kein --frame nötig)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# Eigener Rahmen, alle katalogisierten iPhone-Größen in einem Durchlauf
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### Integrierte Geräterahmen

SwiftMageX liefert einen CC0-lizenzierten iPhone-11-Pro-Max-/-XS-Max-Rahmen
aus [PommePlate](https://github.com/ephread/PommePlate) (Space Grey,
Ableitung mit eingestanztem Bildschirm-Ausschnitt — siehe
[Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md)).
Mit `--device iphone-6.5` wird er automatisch verwendet; `--frame <pfad>`
überschreibt das mit eigener Grafik. Alles Mitgelieferte auflisten:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

Eigene Rahmen funktionieren unverändert — jede PNG mit transparentem
Bildschirm-Loch; der Bildschirmbereich wird aus dem Alpha-Kanal erkannt
(oder mit `--screen-rect` festgelegt).

### `swiftmagex remove-bg` — lokale Hintergrundentfernung

Schneidet das hervorstechende Vordergrundmotiv aus und stellt es auf
einen transparenten Hintergrund — mit Visions On-Device-Segmentierung,
ohne KI-API, ohne Key, ohne Quota-Verbrauch. Das Ergebnis trägt immer
einen Alpha-Kanal und wird daher als PNG geschrieben (eine von `.png`
abweichende `--output`-Endung wird auf `.png` korrigiert).

```
swiftmagex remove-bg <input> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC oder WebP. |
| `-o`, `--output <pfad>` | Geschwister-Datei zur Quelle | Wird immer als PNG geschrieben. |

```sh
# Motiv auf transparentem Hintergrund freistellen
swiftmagex remove-bg photo.jpg -o cutout.png

# Standard: PNG-Geschwister-Datei zur Quelle
swiftmagex remove-bg product.heic
```

Wird kein hervorstechendes Vordergrundmotiv erkannt, schlägt der Befehl
mit einem Raster-Fehler fehl (exit 1).

### `swiftmagex crop` — salienz-basierter Seitenverhältnis-Zuschnitt

Schneidet auf ein vom Nutzer angegebenes Seitenverhältnis zu und zentriert
das Zuschnitt-Fenster auf das vom On-Device-Attention-Modell von Vision
erkannte hervorstechende Motiv — nicht auf die geometrische Mitte. Ohne
KI-API, ohne Key, ohne Quota-Verbrauch. Die Ausgabe behält die
Pixel-Skalierung der Quelle (es ist ein Zuschnitt, kein Resize) und nutzt
standardmäßig dasselbe Format.

```
swiftmagex crop <input> --aspect <W:H> [optionen]
```

| Option | Standard | Hinweise |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC oder WebP. Schreiben nur PNG / JPEG. |
| `--aspect <W:H>` | — | Pflicht. Zwei positive Ganzzahlen, z. B. `1:1`, `4:5`, `9:16`. |
| `-o`, `--output <pfad>` | Geschwister-Datei zur Quelle | |
| `--format <png\|jpeg>` | wie Quelle | HEIC / WebP fallen auf PNG zurück. |
| `--quality <0.0–1.0>` | `0.9` | Nur JPEG. |

```sh
# Quadratischer Zuschnitt, zentriert auf das hervorstechende Motiv
swiftmagex crop photo.jpg --aspect 1:1

# 9:16-Hochkant-Zuschnitt, neu als JPEG codiert
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

Findet die Salienz keine hervorstechenden Objekte (selten; flache oder
gleichmäßige Bilder), fällt der Befehl auf einen mittigen Zuschnitt
zurück, sodass das gewünschte Seitenverhältnis trotzdem eingehalten wird.

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

Fehler (`resize`, `text`, `remove-bg` und `crop` lassen `provider` / `model` weg):

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

`swiftmagex-mcp` stellt neun Tools — `generate_image`, `edit_image`,
`resize_image`, `overlay_text`, `composite_images`, `appstore_screenshots`,
`list_frames`, `remove_background` und `smart_crop` — über stdio bereit. Tool-Argumente
spiegeln die CLI-Flags wider (snake_case-Schlüssel, z. B. `font_size`,
`screen_rect`, `devices`); Ergebnisse melden absolute Dateipfade,
damit der aufrufende Agent das Arbeitsverzeichnis des Servers nicht
kennen muss. `generate_image` und `edit_image` liefern zusätzlich die
Bildbytes als MCP-`image`-Inhalt, damit das aufrufende Modell das Resultat
inspizieren kann. `list_frames` listet die mitgelieferten Geräterahmen
auf, deren IDs `appstore_screenshots` im `frame`-Argument akzeptiert.

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
| `I/O error: input file not found: /…/foo.png` (exit 1) | Der an einen lokalen Befehl (`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop` bzw. deren MCP-Tools) übergebene Pfad existiert nicht oder ist nicht lesbar. | Absoluten Pfad übergeben, Berechtigungen prüfen, Format aus PNG / JPEG / HEIC / WebP wählen (Schreiben nur in PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Gatekeeper-Quarantäne auf einem heruntergeladenen Binary. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (und dasselbe für `swiftmagex-mcp`). |

## Umfang und Status

Dies ist das 0.1 MVP — drei Befehle, zwei Google-AI-Bild-Provider
(Gemini und Imagen), ein MCP-Server — plus vier lokale Erweiterungen nach
0.1: `composite`, `appstore`, `remove-bg` und `crop` (Compositing,
App-Store-Connect-Screenshots, Vision-basierte Hintergrundentfernung und
salienz-basierter Zuschnitt). Alles außerhalb dieser Grenze ist
aufgeschoben; die
vollständige Out-of-Scope-Liste findet sich in spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / Inpainting, lokale Provider, Homebrew-Distribution,
Konfigurationsdatei, Keychain, …).

## Lizenz

MIT. Der vollständige Text steht in [LICENSE](LICENSE).
