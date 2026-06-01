# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI per la generazione e l'elaborazione di immagini solo per macOS.
SwiftMageX è un *orchestratore*: invoca l'API immagini di Google AI (Gemini o Imagen) per la
generazione ed esegue operazioni raster locali (resize, overlay di
testo, composizione, screenshot per App Store, rimozione dello sfondo,
ritaglio sensibile alla salienza) tramite CoreImage / CoreText / ImageIO /
Vision, tutto in un piccolo pacchetto Swift con esattamente due
dipendenze esterne. La stessa
libreria centrale alimenta un server Model Context Protocol
(`swiftmagex-mcp`) così che gli agenti AI possano usare le stesse
capacità come strumenti.

La specifica autorevole è in `SwiftMageX-MVP-0.1-spec.md`; ciò che è
stato rilasciato nella v0.1.0 è in `RELEASE_NOTES.md`.

## Requisiti

- macOS 14+ su Apple silicon (arm64)
- Toolchain Swift 6.0+ (Xcode 16+) — necessaria solo per compilare
  dai sorgenti
- Una chiave API Google AI in `SWIFTMAGEX_GEMINI_API_KEY` (oppure
  `GEMINI_API_KEY`) per il comando `generate` — vale sia per i modelli
  Gemini sia per quelli Imagen. `resize`, `text`, `composite`, `appstore`,
  `remove-bg` e `crop` non richiedono chiave.

## Installazione

### Binario precompilato (consigliato)

Scarica `swiftmagex`, `swiftmagex-mcp` e `SHA256SUMS` dalla
[release v0.1.0](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0),
verifica i checksum e poi metti i binari nel `PATH`:

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

Se Gatekeeper mette in quarantena i download, rimuovi l'attributo:

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### Compilare dai sorgenti

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# i binari finiscono in .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### Eseguire dai sorgenti senza installare

```sh
swift run swiftmagex <sottocomando> …    # CLI
swift run swiftmagex-mcp                 # server MCP (trasporto stdio)
swift test                               # suite di test completa
scripts/check.sh                         # build + test in un colpo
```

### Configurazione

Esporta la chiave API Gemini nel profilo della shell (serve solo per
`generate`):

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # preferita
# in alternativa, lo strumento legge anche:
export GEMINI_API_KEY="…"
```

Non incorporare mai la chiave in script committati. La CLI non
stampa, non logga e non scrive mai la chiave su disco — neanche con
`--verbose` né nei metadati dei file di output.

## Manuale rapido

Otto sottocomandi, tutti con gli stessi flag globali:

| Flag globale | Effetto |
|---|---|
| `--json` | Emette un envelope JSON strutturato su stdout al posto del testo umano. |
| `-v`, `--verbose` | Stampa diagnostica su stderr. **Non** include la chiave API. |
| `--cache-dir <percorso>` | Memorizza le risposte di `generate`/`edit` in `<percorso>`, così richieste identiche riproducono i byte del provider già registrati invece di chiamare l'API. Opt-in — vedi la sezione cache più sotto. |
| `--version` | Stampa `0.1.0` ed esce. |
| `-h`, `--help` | Mostra l'aiuto del comando. |

I percorsi di output sono sempre **assoluti** nell'output `--json` e
nei risultati degli strumenti MCP — l'agente non deve conoscere la
directory di lavoro.

### `swiftmagex generate` — testo → immagine via Gemini o Imagen

```
swiftmagex generate <prompt> [opzioni]
```

| Opzione | Predefinito | Note |
|---|---|---|
| `<prompt>` | — | Argomento posizionale obbligatorio. |
| `-o`, `--output <percorso>` | `./` | File o directory. Se directory, i file vengono nominati `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | Suggerimento di proporzioni. La risoluzione reale dipende dal modello. |
| `-n`, `--count <1–4>` | `1` | Numero di varianti. Ogni variante è una richiesta separata. |
| `--seed <uint64>` | — | Registrato nei metadati anche se il provider lo ignora. |
| `--model <id>` | `gemini-2.5-flash-image` | Integrati: famiglia Gemini (`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) e famiglia Imagen (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Gli ID sconosciuti vengono instradati in base al prefisso `imagen-`/`gemini-`. |

```sh
# Una singola immagine nella directory corrente
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Quattro varianti landscape in una directory, output strutturato
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Seed riproducibile (dipende dal provider)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Esempio — la chiamata seguente ha prodotto l'immagine qui sotto (PNG
1024×1024 con `gemini-2.5-flash-image`):

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="Mela rossa generata su sfondo bianco" width="320" />

Ogni PNG di output porta prompt, modello, seed, timestamp e versione
dello strumento nei chunk `tEXt` (i JPEG usano il campo EXIF
`UserComment`).

### `swiftmagex edit` — image-to-image / multi-immagine / inpainting via Gemini

Invia un'immagine sorgente (più eventuali riferimenti aggiuntivi e una
maschera opzionale) a un modello Gemini insieme al prompt testuale. Ogni
immagine viaggia come parte `inlineData` nella stessa chiamata
`:generateContent` che usa `generate` — nessun endpoint nuovo, nessuna
dipendenza nuova.

```
swiftmagex edit <input> <prompt> [opzioni]
```

| Opzione | Predefinito | Note |
|---|---|---|
| `<input>` | — | Obbligatorio. Immagine sorgente primaria (PNG o JPEG). |
| `<prompt>` | — | Obbligatorio. Istruzione testuale che descrive la modifica. |
| `--reference <percorso>` | — | Ripetibile. Immagine di riferimento aggiuntiva (PNG o JPEG). Ogni `--reference` aggiunge un'altra parte inline che il prompt può comporre — es. "porta il soggetto dall'immagine 1 nella scena dell'immagine 2". |
| `--mask <percorso>` | — | Maschera opzionale in scala di grigi o binaria (PNG o JPEG). Il bianco indica l'area da modificare sull'immagine primaria, il nero preserva l'originale. |
| `-o`, `--output <percorso>` | `./` | File o directory. Se directory, i file sono nominati `swiftmagex_{timestamp}_{index}.png`. |
| `-n`, `--count <1–4>` | `1` | Numero di varianti. Ciascuna è una richiesta separata. |
| `--seed <uint64>` | — | Registrato nei metadati anche quando il provider lo ignora. |
| `--model <id>` | `gemini-2.5-flash-image` | Deve essere un modello Gemini — la forma `:predict` di Imagen non accetta input immagine inline e viene rifiutata con codice di uscita 2. |

```sh
# Cambia il colore di un soggetto
swiftmagex edit apple.png "make the apple green instead of red" -o edited.png

# Inpainting di una regione con maschera
swiftmagex edit photo.png "replace the marked region with a sunset sky" \
  --mask sky-mask.png -o photo_edited.png

# Composizione fra due immagini di riferimento
swiftmagex edit person.png "place the person from image 1 into the scene of image 2" \
  --reference street.png -o composed.png

# Quattro varianti della stessa modifica
swiftmagex edit shot.jpg "add a snowy mountain in the background" -n 4 -o ./out
```

Esempi — tre coppie prima / dopo (sorgenti e modifiche in
[`examples/`](examples)):

| Sorgente | Modificata | Prompt di modifica |
|---|---|---|
| <img src="examples/apple.png" alt="Mela rossa su sfondo bianco" width="200"> | <img src="examples/apple-edited.png" alt="Mela ricolorata di verde brillante" width="200"> | `"Change the apple's color from red to bright green, keep everything else identical"` |
| <img src="examples/mountain.png" alt="Lago di montagna all'alba" width="200"> | <img src="examples/mountain-edited.png" alt="Stessa scena con mongolfiera sopra le vette" width="200"> | `"Add a single colorful hot-air balloon floating in the sky above the mountains"` |
| <img src="examples/cabin.png" alt="Baita di legno in un bosco estivo" width="200"> | <img src="examples/cabin-edited.png" alt="Stessa baita coperta di neve" width="200"> | `"Transform the scene from a sunny summer day to a snowy winter day"` |

Composizione multi-immagine — combina un soggetto con una scena via `--reference`:

| Input (soggetto) | Riferimento (scena) | Risultato |
|---|---|---|
| <img src="examples/canoe.png" alt="Canoa in legno su sfondo bianco" width="200"> | <img src="examples/mountain.png" alt="Lago di montagna all'alba" width="200"> | <img src="examples/canoe-on-mountain-lake.png" alt="Canoa che galleggia sul lago di montagna" width="200"> |

```sh
swiftmagex edit examples/canoe.png \
  "Place the canoe from image 1 onto the lake from image 2, match the lighting and add reflections" \
  --reference examples/mountain.png -o examples/canoe-on-mountain-lake.png
```

Gli output modificati portano gli stessi metadati `tEXt`/EXIF di `generate` —
il prompt registrato è l'istruzione di modifica, non quello originale di
generazione.

### Cache delle risposte

Passa `--cache-dir <percorso>` a `generate` o `edit` per cortocircuitare
la chiamata di rete quando una richiesta identica è già stata servita.
La cache è content-addressed: la chiave è uno SHA-256 su model, prompt,
size, count, seed più lo SHA-256 dei byte di ogni immagine di referenza
e della mask. In caso di hit i byte sono riprodotti dal disco e viene
comunque scritto un file di output con metadati `tEXt`/EXIF aggiornati
(timestamp, versione strumento), così le pipeline a valle si comportano
allo stesso modo.

```sh
# Prima chiamata: API; seconda: replay da /tmp/sx-cache.
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache
swiftmagex generate "a red apple on white" --cache-dir /tmp/sx-cache --json
# → "cached": true nell'output JSON per ogni immagine riprodotta
```

Note:

- **Opt-in per scelta.** Gemini non rispetta `--seed`, quindi input
  identici sono *pensati* per variare tra una chiamata e l'altra — un
  cache hit converte silenziosamente quel non-determinismo intenzionale
  in "stessi byte ogni volta". Passa `--cache-dir` solo se è quello che
  vuoi.
- **Best-effort.** I fallimenti di I/O della cache (directory non
  scrivibile, entry corrotta) degradano a una normale chiamata di rete
  invece di abortire il comando.
- **Niente eviction.** La cache cresce finché non fai `rm -rf` della
  directory.
- La cache si applica solo a `generate` / `edit` (i comandi raster
  locali non chiamano alcun provider). Il server MCP non espone la cache
  in 0.1; il flag CLI è oggi l'unico punto d'ingresso.

### `swiftmagex resize` — resize / crop / conversione di formato locale

```
swiftmagex resize <input> [opzioni]
```

| Opzione | Predefinito | Note |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC o WebP. Scrittura solo in PNG / JPEG. |
| `-w`, `--width <px>` | — | Serve almeno uno tra width / height. |
| `-h`, `--height <px>` | — | Quando ne dai uno solo, l'altro viene calcolato dalla proporzione. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` e `fill` richiedono entrambe le dimensioni. |
| `-o`, `--output <percorso>` | fratello della sorgente | Default: accanto al file di origine. |
| `--format <png\|jpeg>` | come la sorgente | Le sorgenti HEIC / WebP vanno per default in PNG. |
| `--quality <0.0–1.0>` | `0.9` | Solo JPEG. |

```sh
# Thumbnail quadrato, ritagliando l'eccesso
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# Banner largo 1200, ricodifica JPEG all'80%
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# Metà dimensione, proporzioni preservate (solo larghezza)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — overlay di testo

```
swiftmagex text <input> --text "<stringa>" [opzioni]
```

| Opzione | Predefinito | Note |
|---|---|---|
| `<input>` | — | Immagine su cui disegnare. |
| `--text <stringa>` | — | Obbligatorio. `\n` introduce un a capo; le righe lunghe vanno a capo a livello di parola. |
| `--position` | `bottom` | Uno tra `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font <nome>` | font di sistema | Es. `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` o `#RRGGBBAA`. |
| `--stroke <hex>` | — | Ometti per non avere contorno. |
| `--stroke-width <pt>` | `2.0` | Usato solo quando `--stroke` è impostato. |
| `-o`, `--output <percorso>` | fratello della sorgente | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### `swiftmagex composite` — sovrapporre un'immagine a un'altra

```
swiftmagex composite <sfondo> --overlay <primo-piano> [opzioni]
```

| Opzione | Default | Note |
|---|---|---|
| `<sfondo>` | — | L'immagine di base (la tela). |
| `--overlay <percorso>` | — | Obbligatorio. Primo piano incollato sopra (rispetta l'alfa). |
| `--position` | `center` | Gli stessi sette ancoraggi di `text`. |
| `--scale <frazione>` | `1.0` | Dimensione del primo piano come frazione dello sfondo; proporzioni mantenute. |
| `--offset-x`, `--offset-y <px>` | `0` | Spostamento dall'ancoraggio (positivo = destra / basso). |
| `--opacity <0.0–1.0>` | `1.0` | Opacità di fusione del primo piano. |
| `-o`, `--output <percorso>` | accanto allo sfondo | |
| `--format <png\|jpeg>`, `--quality` | come lo sfondo / `0.9` | |

```sh
swiftmagex composite bg.png --overlay logo.png --position top-right --scale 0.2 -o hero.png
```

### `swiftmagex appstore` — screenshot per App Store Connect

Inquadra uno screenshot in una cornice di dispositivo, lo scala su uno sfondo,
sovrappone una didascalia opzionale e scrive il risultato in una o più
dimensioni in pixel iPhone di App Store Connect — in batch, in un'unica passata.

```
swiftmagex appstore <screenshot> --background <sfondo> [opzioni]
```

| Opzione | Default | Note |
|---|---|---|
| `<screenshot>` | — | Lo screenshot collocato nella cornice. |
| `--background <percorso>` | — | Obbligatorio. Riempie (cover) dietro al dispositivo. |
| `--frame <percorso\|id>` | auto | Cornice iPhone: percorso a un PNG con un ritaglio di schermo trasparente, oppure un [id di cornice inclusa](#cornici-dispositivo-incluse) (es. `iphone-6.5-pommeplate-spacegray`). Ometti per scegliere automaticamente una cornice inclusa per il dispositivo richiesto, quando disponibile. |
| `--list-frames` | — | Elenca le cornici dispositivo incluse ed esce. Usalo con `--json` per una forma analizzabile. |
| `--screen-rect <x,y,w,h>` | autorilevamento | Dove va lo screenshot nella cornice. Se omesso, rilevato dall'alfa della cornice. |
| `--device <id>` | `iphone-6.9` | Ripetibile. Uno tra `iphone-6.9` (1290×2796), `iphone-6.5` (1242×2688), `iphone-5.5` (1242×2208) o `all`. |
| `--orientation <portrait\|landscape>` | `portrait` | Scambia le dimensioni del dispositivo. |
| `--scale <frazione>` | `0.85` | Dimensione del dispositivo inquadrato come frazione della tela. |
| `--position`, `--offset-x`, `--offset-y` | `center`, `0`, `0` | Dove si posiziona il dispositivo sullo sfondo. |
| `--caption <stringa>` | — | Testo della didascalia opzionale. |
| `--caption-position`, `--font`, `--font-size`, `--color`, `--stroke`, `--stroke-width` | `bottom`, sistema, `96`, `#FFFFFF`, —, `0` | Stile della didascalia (stesso motore di `text`). |
| `-o`, `--output <dir>` | `./` | **Directory** di output; i file si chiamano `appstore_{device}_{w}x{h}.png`. |

```sh
# Cornice iPhone 6.5" inclusa (nessun --frame necessario)
swiftmagex appstore shot.png --background bg.png --device iphone-6.5 \
  --caption "Plan your week" --stroke "#000000" --stroke-width 6

# Cornice personalizzata, tutte le dimensioni iPhone del catalogo in una volta
swiftmagex appstore shot.png --background bg.png --frame iphone.png --device all -o ./shots
```

#### Cornici dispositivo incluse

SwiftMageX include una cornice iPhone 11 Pro Max / XS Max con licenza CC0
proveniente da [PommePlate](https://github.com/ephread/PommePlate) (Space
Grey, opera derivata con ritaglio di schermo aggiunto — vedi
[Resources/Frames/ATTRIBUTION.md](Sources/SwiftMageXKit/Resources/Frames/ATTRIBUTION.md)).
Con `--device iphone-6.5` viene usata automaticamente; passa `--frame
<percorso>` per sostituirla con la tua grafica. Per elencare tutto ciò
che è incluso:

```sh
swiftmagex appstore --list-frames
# → iphone-6.5-pommeplate-spacegray  iphone-6.5  iPhone 11 Pro Max / XS Max — Space Grey (PommePlate)
```

Le cornici fornite dall'utente continuano a funzionare allo stesso modo:
qualsiasi PNG con un foro di schermo trasparente; la regione dello
schermo si ricava dal canale alfa (oppure fissala con `--screen-rect`).

### `swiftmagex remove-bg` — rimozione dello sfondo locale

Ritaglia il soggetto in primo piano più rilevante e lo lascia su uno
sfondo trasparente, usando la segmentazione on-device di Vision — senza
API di IA, senza chiave, con consumo di quota nullo. Il risultato ha
sempre un canale alfa, quindi viene scritto come PNG (un'estensione
`--output` diversa da `.png` viene convertita in `.png`).

```
swiftmagex remove-bg <input> [opzioni]
```

| Opzione | Predefinito | Note |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC o WebP. |
| `-o`, `--output <percorso>` | fratello della sorgente | Sempre scritto come PNG. |

```sh
# Ritaglia il soggetto su sfondo trasparente
swiftmagex remove-bg photo.jpg -o cutout.png

# Per default, un PNG accanto alla sorgente
swiftmagex remove-bg product.heic
```

Se non viene rilevato alcun soggetto rilevante in primo piano, il comando
fallisce con un errore raster (exit 1).

### `swiftmagex crop` — ritaglio per rapporto sensibile alla salienza

Ritaglia a un rapporto fornito dall'utente centrando la finestra di
ritaglio sul soggetto rilevante individuato dal modello di attenzione
on-device di Vision — non sul centro geometrico. Senza API di IA, senza
chiave, con consumo di quota nullo. L'output mantiene la scala di pixel
della sorgente (è un ritaglio, non un resize) e, per impostazione
predefinita, usa lo stesso formato.

```
swiftmagex crop <input> --aspect <W:H> [opzioni]
```

| Opzione | Predefinito | Note |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC o WebP. Scrittura solo PNG / JPEG. |
| `--aspect <W:H>` | — | Obbligatorio. Due interi positivi, es. `1:1`, `4:5`, `9:16`. |
| `-o`, `--output <percorso>` | fratello della sorgente | |
| `--format <png\|jpeg>` | uguale alla sorgente | HEIC / WebP ricadono su PNG di default. |
| `--quality <0.0–1.0>` | `0.9` | Solo JPEG. |

```sh
# Ritaglio quadrato centrato sul soggetto rilevante
swiftmagex crop photo.jpg --aspect 1:1

# Ritaglio verticale 9:16 ricodificato come JPEG
swiftmagex crop photo.jpg --aspect 9:16 -o portrait.jpg --format jpeg --quality 0.85
```

Quando la salienza non trova oggetti rilevanti (raro; immagini piatte o
uniformi), ricade su un ritaglio centrato così che il rapporto richiesto
sia comunque rispettato.

### Schema di output JSON

Ogni comando emette lo stesso envelope sotto `--json`. Le chiavi sono
ordinate; i campi nulli vengono omessi del tutto (niente `null` come
placeholder).

Successo:

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

Errore (`resize`, `text`, `remove-bg` e `crop` omettono `provider` / `model`):

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

Convenzioni sugli stream: risultati → **stdout**; diagnostica
(`--verbose`) → **stderr**. Il JSON di errore sotto `--json` va
comunque su stdout, così un agente lo può analizzare da un unico
posto.

### Codici di uscita

| Codice | Significato | Esempio |
|---|---|---|
| `0` | Successo | — |
| `1` | Errore inatteso / raster / I/O | file di input illeggibile, fallimento dell'encoder |
| `2` | Input non valido | combinazione `--fit` errata, colore hex malformato, `--count` fuori 1–4 |
| `3` | Errore del provider / API | 5xx di Gemini, `429` dopo 5 retry |
| `4` | Configurazione | `SWIFTMAGEX_GEMINI_API_KEY` mancante |

Politica di retry sui 429: fino a 5 tentativi con backoff esponenziale
1 s → 2 s → 4 s → 8 s → 16 s.

## Server MCP

`swiftmagex-mcp` espone nove strumenti — `generate_image`, `edit_image`,
`resize_image`, `overlay_text`, `composite_images`, `appstore_screenshots`,
`list_frames`, `remove_background` e `smart_crop` — su stdio. Gli argomenti rispecchiano
i flag della CLI (chiavi in snake_case, es. `font_size`, `screen_rect`,
`devices`); i risultati riportano percorsi assoluti così che
l'agente chiamante non debba sapere la directory di lavoro del
server. `generate_image` ed `edit_image` restituiscono inoltre i byte
dell'immagine come contenuto MCP `image`, in modo che il modello che ha
invocato lo strumento possa ispezionare quanto prodotto. `list_frames`
enumera le cornici dispositivo incluse i cui id sono accettati
dall'argomento `frame` di `appstore_screenshots`.

### Configurare Claude Code

Claude Code registra i server MCP tramite `claude mcp add`. All'interno
del repo in cui vuoi avere SwiftMageX, esegui:

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Per renderlo disponibile in ogni sessione di Claude Code su questa
macchina, usa lo scope utente:

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Verifica quanto registrato con `claude mcp list` o
`claude mcp get swiftmagex`; rimuovi con `claude mcp remove swiftmagex`.
Il trasporto predefinito è stdio — il flag `--transport` non serve.

### Configurare Claude Desktop

Aggiungi una voce a
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

Il blocco `env` limita la chiave API a questo solo server — non
finisce nell'ambiente generale del client.

## Risoluzione dei problemi

| Sintomo | Causa probabile | Soluzione |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | Nessuna chiave API nell'ambiente quando si lancia `generate` o si invoca `generate_image`. | Esporta `SWIFTMAGEX_GEMINI_API_KEY` (oppure il fallback `GEMINI_API_KEY`); per MCP, aggiungila al blocco `env` del client come sopra. |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini ha restituito `429` a ogni tentativo nella finestra di backoff (1 s → 16 s). | Attendi il ripristino della quota, cambia progetto o riprova più tardi. Il calendario del backoff è fisso; vedi spec §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | Il percorso passato a un comando locale (`resize` / `text` / `composite` / `appstore` / `remove-bg` / `crop`, o i loro strumenti MCP) non esiste o non è leggibile. | Usa un percorso assoluto, verifica i permessi e controlla che il formato sia PNG / JPEG / HEIC / WebP (la scrittura supporta solo PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Quarantena Gatekeeper su un binario scaricato. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (idem per `swiftmagex-mcp`). |

## Ambito e stato

Questa è la MVP 0.1 — tre comandi, due provider di immagini Google AI
(Gemini e Imagen), un server MCP — più quattro aggiunte locali post-0.1:
`composite`, `appstore`, `remove-bg` e `crop` (composizione, screenshot
per App Store Connect, rimozione dello sfondo basata su Vision e ritaglio
sensibile alla salienza). Tutto ciò che va oltre questo perimetro è
rinviato; per la lista
completa fuori ambito vedi la spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, provider locali, distribuzione via Homebrew, file
di configurazione, Keychain, …).

## Licenza

TBD.
