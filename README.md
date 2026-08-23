# Fair Witness

Look it up. Report what it says. Unofficial.

Public Grokipedia full-text search for Omarchy — one field, **LOOK UP**, result
cards. Named for Heinlein’s Fair Witness (*Stranger in a Strange Land*). No API
keys. No vendor chrome.

**ID:** `harris.fair-witness`  
**Author:** Harris Kenny  
**License:** MIT  
**Version:** 0.1.1

### 0.1.1
- Direct-match **hero**: when title or slug equals the query (CI), show an
  expandable MATCH preview at top (collapsed snippet + Show more; expanded
  fuller snippet + Open / Copy title / Copy link). **RELATED** cards below for
  everything else. No fake hero when there is no direct match.
- `scripts/search.py` and `WitnessStore` emit/compute `{ primary, related, results }`.

### 0.1.0
- MVP — bar `● FW`, panel search, `scripts/search.py` → Grokipedia public
  full-text search, result cards (Open / Copy title / Copy link), selected
  WITNESS snippet card, disk cache, middle-click clear, schema `resultLimit`.

## Repository

**GitHub:** https://github.com/kenhara/omarchy-fair-witness  
Local folder: **`omarchy-fair-witness`**.

## Unofficial disclaimer

**Fair Witness is unofficial.** It is **not** affiliated with, endorsed by, or
sponsored by xAI, Grokipedia, or any related entity. “Fair Witness” is a
literary reference to Robert A. Heinlein’s *Stranger in a Strange Land*. This
plugin is a thin personal client that calls a **public read** HTTP search API.
Aliases / keywords may mention Grokipedia for discovery; the display name does
not.

## Install

### From GitHub

```sh
omarchy plugin add https://github.com/kenhara/omarchy-fair-witness.git --enable
omarchy bar move harris.fair-witness --section right
```

### Local copy (this tree)

The **git repo root is the plugin** (`manifest.json` at root). On an Omarchy
machine:

```sh
mkdir -p ~/.config/omarchy/plugins
cp -a . ~/.config/omarchy/plugins/harris.fair-witness

omarchy plugin validate ~/.config/omarchy/plugins/harris.fair-witness
omarchy-shell shell rescanPlugins

omarchy bar move harris.fair-witness --section right
```

Hot reload applies on save under `~/.config/omarchy/plugins/`.

### Symlink (dev)

```sh
mkdir -p ~/.config/omarchy/plugins
ln -sfn /path/to/omarchy-fair-witness ~/.config/omarchy/plugins/harris.fair-witness
omarchy-shell shell rescanPlugins
```

## Configure

Open **widget settings** for Fair Witness (optional):

| Schema key | Label | Default |
|------------|-------|---------|
| `resultLimit` | Result limit (1–20) | `8` |

No API keys. Public read only.

CLI smoke:

```sh
python3 scripts/search.py --query 'mars' --limit 8
python3 scripts/search.py --dry-run --query 'mars'
```

## Usage

1. **Left-click** bar `● FW` → panel.
2. Type or paste a topic into the one field.
3. Hit **LOOK UP** (or Enter).
4. If the query exactly matches a title or slug, a **MATCH** hero appears at
   the top (expandable). **RELATED** cards list the rest. Otherwise a flat
   result list (and optional **WITNESS** snippet for the selected card).
5. **Open** / **Copy title** / **Copy link** on hero or cards.
6. **Middle-click** bar clears the last search (and cache).

### Controls

| Input | Action |
|-------|--------|
| Left-click bar | Toggle panel |
| Middle-click bar | Clear last search (+ cache); toast "Cleared" |
| Search field | One paste/type; Enter triggers LOOK UP |
| LOOK UP | `scripts/search.py` → result cards |
| Open | `xdg-open` / `Qt.openUrlExternally` on article URL |
| Copy title / Copy link | Clipboard |
| MATCH hero | Expand/collapse; Open / Copy when expanded |
| Select card (no match) | Updates WITNESS summary |

## Remove

```sh
omarchy plugin remove harris.fair-witness
```

Optional cache cleanup:

```sh
rm -rf ~/.cache/fair-witness
```

## Network

- Search: `GET https://grokipedia.com/api/full-text-search?query=…&limit=…`
- Article pages: `https://grokipedia.com/page/{slug}`

Outbound HTTPS only when you click **LOOK UP** (or open a result). No auth.
User-Agent: `FairWitness/0.1.1 (Omarchy unofficial; harris.fair-witness)`.
Polite client-side spacing between HTTP calls in one process.

Cache (last **successful** search): `~/.cache/fair-witness/last.json`.

## Scripts

`scripts/search.py` — urllib only, no extra deps.

```sh
python3 scripts/search.py --help
python3 scripts/search.py --query 'mars' --limit 8
# stdout JSON: {ok, results, primary, related, error}
```

Empty query and `--dry-run` emit structured error JSON (non-zero exit).

## Layout

```
manifest.json          # harris.fair-witness @ 0.1.1
BarWidget.qml          # bar entry + Loader → Panel; middle-click clear
Panel.qml              # search + LOOK UP + result cards
WitnessStore.qml       # queryInput, lookUp, cache, Process → search.py
qmldir
scripts/search.py
docs/preview/index.html
preview.svg
preview.png
DESIGN.md
REPO.md
LICENSE                # MIT
README.md
```

## Security baseline

- **No API keys.** Public read search only.
- Cache stores the last successful result list — no credentials.
- Outbound HTTPS only on explicit LOOK UP / Open. No auto-fire on panel open
  or middle-click.
- MIT at repo root. Unofficial — not affiliated with xAI or Grokipedia.
  Fair Witness is Heinlein.

## Preview

Open `docs/preview/index.html` in a browser for a filled HTML mock (v0.1.1)
with sample Mars as MATCH hero + RELATED. Marketplace card: `preview.png`.

## License

MIT — see [LICENSE](LICENSE).
