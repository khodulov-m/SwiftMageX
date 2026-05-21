# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI per la generazione e l'elaborazione di immagini solo per macOS.
SwiftMageX è un *orchestratore*: invoca l'API Gemini per la
generazione ed esegue operazioni raster locali (resize, overlay di
testo) tramite CoreImage / CoreText / ImageIO, tutto in un piccolo
pacchetto Swift con esattamente due dipendenze esterne. La stessa
libreria centrale alimenta un server Model Context Protocol
(`swiftmagex-mcp`) così che gli agenti AI possano usare le stesse
capacità come strumenti.

La specifica autorevole è in `SwiftMageX-MVP-0.1-spec.md`; ciò che è
stato rilasciato nella v0.1.0 è in `RELEASE_NOTES.md`.

## Requisiti

- macOS 14+ su Apple silicon (arm64)
- Toolchain Swift 6.0+ (Xcode 16+) — necessaria solo per compilare
  dai sorgenti
- Una chiave API Gemini in `SWIFTMAGEX_GEMINI_API_KEY` (oppure
  `GEMINI_API_KEY`) per il comando `generate`. `resize` e `text` non
  richiedono chiave.

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

Tre sottocomandi, tutti con gli stessi flag globali:

| Flag globale | Effetto |
|---|---|
| `--json` | Emette un envelope JSON strutturato su stdout al posto del testo umano. |
| `-v`, `--verbose` | Stampa diagnostica su stderr. **Non** include la chiave API. |
| `--version` | Stampa `0.1.0` ed esce. |
| `-h`, `--help` | Mostra l'aiuto del comando. |

I percorsi di output sono sempre **assoluti** nell'output `--json` e
nei risultati degli strumenti MCP — l'agente non deve conoscere la
directory di lavoro.

### `swiftmagex generate` — testo → immagine via Gemini

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
| `--model <id>` | `gemini-2.5-flash-image` | Usa `gemini-3.1-flash-image-preview` per qualità preview. |

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

Errore (`resize` e `text` omettono `provider` / `model`):

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

`swiftmagex-mcp` espone tre strumenti — `generate_image`,
`resize_image`, `overlay_text` — su stdio. Gli argomenti rispecchiano
i flag della CLI; i risultati riportano percorsi assoluti così che
l'agente chiamante non debba sapere la directory di lavoro del
server. `generate_image` restituisce inoltre i byte dell'immagine come
contenuto MCP `image`, in modo che il modello che ha invocato lo
strumento possa ispezionare quanto prodotto.

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
| `I/O error: input file not found: /…/foo.png` (exit 1) | Il percorso passato a `resize` / `text` (o `resize_image` / `overlay_text`) non esiste o non è leggibile. | Usa un percorso assoluto, verifica i permessi e controlla che il formato sia PNG / JPEG / HEIC / WebP (la scrittura supporta solo PNG / JPEG). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Quarantena Gatekeeper su un binario scaricato. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (idem per `swiftmagex-mcp`). |

## Ambito e stato

Questa è la MVP 0.1 — tre comandi, un provider (Gemini), un server
MCP. Tutto ciò che va oltre questo perimetro è rinviato; per la lista
completa fuori ambito vedi la spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, provider locali, distribuzione via Homebrew, file
di configurazione, Keychain, …).

## Licenza

TBD.
