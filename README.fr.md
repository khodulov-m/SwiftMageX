# SwiftMageX

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Português (BR)](README.pt-BR.md) · [Italiano](README.it.md) · [Русский](README.ru.md)

CLI de génération et de traitement d'images uniquement pour macOS.
SwiftMageX est un *orchestrateur* : il appelle l'API d'images Google AI (Gemini ou Imagen) pour la
génération et effectue des opérations raster locales (resize,
superposition de texte) via CoreImage / CoreText / ImageIO, depuis un
petit paquet Swift avec exactement deux dépendances externes. La même
bibliothèque centrale alimente un serveur Model Context Protocol
(`swiftmagex-mcp`) afin que les agents IA puissent utiliser ces
capacités comme outils.

La spécification de référence est `SwiftMageX-MVP-0.1-spec.md` ; ce qui
a été livré dans la v0.1.0 figure dans `RELEASE_NOTES.md`.

## Prérequis

- macOS 14+ sur Apple silicon (arm64)
- Toolchain Swift 6.0+ (Xcode 16+) — uniquement nécessaire pour
  compiler depuis les sources
- Une clé API Google AI dans `SWIFTMAGEX_GEMINI_API_KEY` (ou
  `GEMINI_API_KEY`) pour la commande `generate` — utilisée à la fois
  pour les modèles Gemini et Imagen. `resize` et `text` ne nécessitent
  aucune clé.

## Installation

### Binaire précompilé (recommandé)

Récupérez `swiftmagex`, `swiftmagex-mcp` et `SHA256SUMS` depuis la
[release v0.1.0](https://github.com/khodulov-m/SwiftMageX/releases/tag/v0.1.0),
vérifiez les sommes, puis placez les binaires dans votre `PATH` :

```sh
shasum -a 256 -c SHA256SUMS
chmod +x swiftmagex swiftmagex-mcp
sudo mv swiftmagex swiftmagex-mcp /usr/local/bin/
swiftmagex --version    # 0.1.0
```

Si Gatekeeper met les téléchargements en quarantaine, supprimez
l'attribut :

```sh
xattr -d com.apple.quarantine /usr/local/bin/swiftmagex /usr/local/bin/swiftmagex-mcp
```

### Compilation depuis les sources

```sh
git clone https://github.com/khodulov-m/SwiftMageX.git
cd SwiftMageX
swift build -c release
# les binaires arrivent dans .build/arm64-apple-macosx/release/
cp .build/arm64-apple-macosx/release/swiftmagex     /usr/local/bin/
cp .build/arm64-apple-macosx/release/swiftmagex-mcp /usr/local/bin/
```

### Exécuter sans installer

```sh
swift run swiftmagex <sous-commande> …   # CLI
swift run swiftmagex-mcp                 # serveur MCP (transport stdio)
swift test                               # suite de tests complète
scripts/check.sh                         # build + tests d'un coup
```

### Configuration

Exportez la clé API Gemini dans le profil de votre shell (uniquement
pour `generate`) :

```sh
export SWIFTMAGEX_GEMINI_API_KEY="…"   # préférée
# alternativement, l'outil lit aussi :
export GEMINI_API_KEY="…"
```

N'intégrez jamais la clé dans des scripts versionnés. Le CLI n'imprime,
ne journalise et n'écrit jamais la clé sur disque — même sous
`--verbose` et même dans les métadonnées du fichier de sortie.

## Manuel rapide

Trois sous-commandes, toutes partageant les mêmes flags globaux :

| Flag global | Effet |
|---|---|
| `--json` | Émet une enveloppe JSON structurée sur stdout au lieu du texte humain. |
| `-v`, `--verbose` | Imprime les diagnostics sur stderr. **N'inclut pas** la clé d'API. |
| `--version` | Imprime `0.1.0` et quitte. |
| `-h`, `--help` | Affiche l'aide de la commande. |

Les chemins de sortie sont toujours **absolus** dans la sortie `--json`
et dans les résultats des outils MCP — les agents n'ont pas besoin de
connaître le répertoire de travail.

### `swiftmagex generate` — texte vers image via Gemini ou Imagen

```
swiftmagex generate <prompt> [options]
```

| Option | Par défaut | Notes |
|---|---|---|
| `<prompt>` | — | Argument positionnel obligatoire. |
| `-o`, `--output <chemin>` | `./` | Fichier ou dossier. Si dossier, les fichiers sont nommés `swiftmagex_{timestamp}_{index}.png`. |
| `-s`, `--size <square\|portrait\|landscape>` | `square` | Indication de proportion. La résolution réelle dépend du modèle. |
| `-n`, `--count <1–4>` | `1` | Nombre de variantes. Chacune est une requête distincte. |
| `--seed <uint64>` | — | Enregistré dans les métadonnées même si le fournisseur l'ignore. |
| `--model <id>` | `gemini-2.5-flash-image` | Intégrés : famille Gemini (`gemini-2.5-flash-image`, `gemini-3-pro-image-preview`, `gemini-3.1-flash-image-preview`) et famille Imagen (`imagen-4.0-generate-001`, `imagen-4.0-fast-generate-001`, `imagen-4.0-ultra-generate-001`). Les ID inconnus sont routés via le préfixe `imagen-`/`gemini-`. |

```sh
# Une seule image dans le répertoire courant
swiftmagex generate "neon-lit cyberpunk alley in the rain"

# Quatre variantes paysage vers un dossier, sortie structurée
swiftmagex generate "mountain landscape at dawn" -n 4 -s landscape -o ./out --json

# Seed reproductible (dépend du fournisseur)
swiftmagex generate "minimalist app icon, fox head" --seed 42 -o icon.png
```

Exemple — l'appel ci-dessous a produit l'image ci-dessous (PNG 1024×1024
avec `gemini-2.5-flash-image`) :

```sh
swiftmagex generate "A simple red apple on a white background, test image" \
  -o apple.png
```

<img src="docs/images/example-generate-apple.png" alt="Pomme rouge générée sur fond blanc" width="320" />

Chaque PNG produit transporte le prompt, le modèle, le seed, l'horodatage
et la version de l'outil dans des chunks `tEXt` (les JPEG utilisent le
champ EXIF `UserComment`).

### `swiftmagex resize` — resize / recadrage / conversion locale

```
swiftmagex resize <input> [options]
```

| Option | Par défaut | Notes |
|---|---|---|
| `<input>` | — | PNG, JPEG, HEIC ou WebP. Écriture en PNG / JPEG seulement. |
| `-w`, `--width <px>` | — | Au moins un de width / height est requis. |
| `-h`, `--height <px>` | — | Si un seul est fourni, l'autre est calculé selon le ratio. |
| `--fit <contain\|cover\|fill>` | `contain` | `cover` et `fill` exigent les deux dimensions. |
| `-o`, `--output <chemin>` | voisin de la source | Par défaut, à côté du fichier source. |
| `--format <png\|jpeg>` | comme la source | Les sources HEIC / WebP basculent par défaut en PNG. |
| `--quality <0.0–1.0>` | `0.9` | JPEG uniquement. |

```sh
# Miniature carrée, recadrage du dépassement
swiftmagex resize photo.png -w 512 -h 512 --fit cover -o thumb.png

# Bannière de 1200 px de large, recompression JPEG à 80 %
swiftmagex resize banner.png -w 1200 --format jpeg --quality 0.8

# Demi-taille, ratio préservé (largeur seule)
swiftmagex resize cover.heic -w 1024 -o cover_1024.png
```

### `swiftmagex text` — superposition de texte

```
swiftmagex text <input> --text "<chaîne>" [options]
```

| Option | Par défaut | Notes |
|---|---|---|
| `<input>` | — | Image sur laquelle dessiner. |
| `--text <chaîne>` | — | Obligatoire. `\n` insère un saut de ligne ; les longues lignes sont coupées par mots. |
| `--position` | `bottom` | Une de `top`, `center`, `bottom`, `top-left`, `top-right`, `bottom-left`, `bottom-right`. |
| `--font <nom>` | police système | Ex. `"Helvetica-Bold"`. |
| `--font-size <pt>` | `48` | |
| `--color <hex>` | `#FFFFFF` | `#RRGGBB` ou `#RRGGBBAA`. |
| `--stroke <hex>` | — | Omettre pour aucune bordure. |
| `--stroke-width <pt>` | `2.0` | Pris en compte uniquement quand `--stroke` est défini. |
| `-o`, `--output <chemin>` | voisin de la source | |

```sh
swiftmagex text screenshot.png --text "Download on the App Store" --position bottom
swiftmagex text cover.png --text "SALE" --position center --font-size 96 --stroke "#000000"
```

### Schéma de sortie JSON

Chaque commande émet la même enveloppe sous `--json`. Les clés sont
triées ; les champs nuls sont entièrement omis (pas de `null`).

Succès :

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

Erreur (`resize` et `text` omettent `provider` / `model`) :

```json
{
  "command": "generate",
  "error": { "category": "configuration", "code": 4, "message": "missing SWIFTMAGEX_GEMINI_API_KEY" },
  "status": "error"
}
```

Conventions de flux : résultats → **stdout** ; diagnostics
(`--verbose`) → **stderr**. Le JSON d'erreur sous `--json` va aussi
sur stdout afin qu'un agent puisse le parser à un seul endroit.

### Codes de sortie

| Code | Sens | Exemple |
|---|---|---|
| `0` | Succès | — |
| `1` | Échec inattendu / raster / I/O | fichier d'entrée illisible, échec de l'encodeur |
| `2` | Entrée invalide | combinaison `--fit` invalide, couleur hex mal formée, `--count` hors 1–4 |
| `3` | Échec fournisseur / API | 5xx Gemini, `429` après 5 retries |
| `4` | Configuration | `SWIFTMAGEX_GEMINI_API_KEY` manquante |

Politique de retry sur 429 : jusqu'à 5 tentatives, backoff exponentiel
1 s → 2 s → 4 s → 8 s → 16 s.

## Serveur MCP

`swiftmagex-mcp` expose trois outils — `generate_image`,
`resize_image`, `overlay_text` — via stdio. Les arguments des outils
reprennent les flags du CLI ; les résultats renvoient des chemins
absolus afin que l'agent appelant n'ait pas besoin de connaître le
répertoire de travail du serveur. `generate_image` retourne en plus les
octets de l'image en contenu MCP `image` afin que le modèle puisse
inspecter ce qui a été produit.

### Configurer Claude Code

Claude Code enregistre les serveurs MCP via `claude mcp add`. Dans le
dépôt où vous voulez que SwiftMageX soit disponible, lancez :

```sh
claude mcp add swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Pour le rendre disponible dans chaque session Claude Code sur cette
machine, utilisez le scope utilisateur :

```sh
claude mcp add -s user swiftmagex /usr/local/bin/swiftmagex-mcp \
  -e SWIFTMAGEX_GEMINI_API_KEY=your-key-here
```

Inspectez ce qui est enregistré avec `claude mcp list` ou
`claude mcp get swiftmagex` ; supprimez avec `claude mcp remove swiftmagex`.
Le transport par défaut est stdio — pas besoin du flag `--transport`.

### Configurer Claude Desktop

Ajoutez une entrée à
`~/Library/Application Support/Claude/claude_desktop_config.json` :

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

Le bloc `env` cantonne la clé d'API à ce seul serveur — elle ne se
retrouve pas dans l'environnement général du client.

## Dépannage

| Symptôme | Cause probable | Correctif |
|---|---|---|
| `Configuration error: missing SWIFTMAGEX_GEMINI_API_KEY` (exit 4) | Aucune clé dans l'environnement lors d'un `generate` ou d'un appel `generate_image`. | Exportez `SWIFTMAGEX_GEMINI_API_KEY` (ou le repli `GEMINI_API_KEY`) ; pour MCP, ajoutez-la au bloc `env` du client comme ci-dessus. |
| `Provider error: quota exhausted after 5 retries` (exit 3) | Gemini a répondu `429` à chaque tentative dans la fenêtre de backoff (1 s → 16 s). | Attendez la recharge du quota, changez de projet, ou réessayez plus tard. Le calendrier de backoff est figé ; voir spec §13. |
| `I/O error: input file not found: /…/foo.png` (exit 1) | Le chemin passé à `resize` / `text` (ou `resize_image` / `overlay_text`) n'existe pas ou est illisible. | Donnez un chemin absolu, vérifiez les permissions, et confirmez que le format est PNG / JPEG / HEIC / WebP (écriture en PNG / JPEG seulement). |
| `"swiftmagex" cannot be opened because the developer cannot be verified` | Quarantaine Gatekeeper sur un binaire téléchargé. | `xattr -d com.apple.quarantine /usr/local/bin/swiftmagex` (et idem pour `swiftmagex-mcp`). |

## Portée et statut

Il s'agit du MVP 0.1 — trois commandes, deux fournisseurs d'images
Google AI (Gemini et Imagen), un serveur MCP. Tout ce qui sort de ce périmètre est différé ; la liste
hors périmètre complète figure dans spec
[§2 Scope of version 0.1](SwiftMageX-MVP-0.1-spec.md#2-scope-of-version-01)
(edit / inpainting, fournisseurs locaux, distribution Homebrew, fichier
de configuration, Keychain, …).

## Licence

TBD.
