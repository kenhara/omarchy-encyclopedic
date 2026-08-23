# Fair Witness — Quattro pre-ship checklist (0.1.3)

Omarchy Quattro pre-ship pass for `harris.fair-witness`. Builds on the 0.1.2
audit map (`AUDIT.md` / `AUDIT-NOTES.md`).

## Checklist

| # | Item | Status |
|---|------|--------|
| 1 | No `Style.font.size(` — named tokens only | **pass** — `caption` / `bodySmall` / `body` / `subtitle` / `title` |
| 2 | Font: `bar.fontFamily` / `"monospace"` fallback | **pass** — BarWidget + Panel (0.1.3 dropped `Style.font.family`) |
| 3 | `Quickshell.clipboardText = t` | **pass** — WitnessStore `copyText` |
| 4 | Clipboard `bash -c` if/elif wl-copy→xclip→xsel; toast on success | **pass** — no `bash -lc`; toast on Quickshell path or `copyProc` exit 0/127 |
| 5 | No secrets in argv | **pass** — public search only; argv is `python3` + script + `--query`/`--limit` |
| 6 | No `/workspace/` in public docs | **pass** — DESIGN scrubbed in 0.1.2 |
| 7 | LICENSE second `Software` unquoted | **pass** — canonical MIT |
| 8 | README hero `preview.png`; Install + Remove | **pass** — hero added 0.1.3 |
| 9 | FileView cache (no mkdir + `Qt.callLater` race) | **pass** — `cacheFile.setText` direct |
| 10 | Dead `dataChanged` / unused store noise | **pass** — no `dataChanged`; dropped unused `panelOpen` (0.1.3) |
| 11 | Honest copy/open toasts | **pass** — Copied/Opened only on real success |
| 12 | `Text.PlainText` on all remote Text | **pass** — MATCH / RELATED / flat / WITNESS title+snippet |
| 13 | Unescape-before-strip HTML | **pass** — `scripts/search.py` `strip_simple_html` |
| 14 | https URL allow-list | **pass** — `sanitizeOpenUrl` + `sanitize_https_url` |
| 15 | Keep results on failed lookup | **pass** — `ok:false` toasts only; prior primary/related kept |
| 16 | Version sync | **pass** — **0.1.3** manifest / README / DESIGN / Panel / preview / UA fallback |
| 17 | Integer schema min/max/step | **pass** — `resultLimit` 1–20 step 1 |
| 18 | No invented summon APIs | **pass** — no `handleSummonPayload`; middle-click → `clearLastSearch` |
| 19 | Hover on actionable | **pass** — LOOK UP, pills, show-more, cards |
| 20 | Controls L/R/M; pitch ≤15 words; no `curl\|sh` | **pass** — L toggle / R none / M clear; *Look it up. Report what it says. Unofficial.* |

## FW-specific kept (do not regress)

| Keep | Status |
|------|--------|
| MATCH hero (title/slug == query CI) | **kept** — expandable MATCH + Show more / Open / Copy |
| RELATED cards below primary | **kept** — related list when primary exists |
| Flat list when no direct match | **kept** — no fake hero |
| Unofficial / no API keys / no vendor chrome | **kept** |

## Changed in 0.1.3

- README hero `![Fair Witness](preview.png)`; Controls row for right-click
- `"monospace"` font fallback (drop `Style.font.family`)
- Drop unused `panelOpen`
- Version sync to **0.1.3** (incl. `preview.svg` was still on 0.1.1)
- This `PRE-SHIP.md`

## Pre-ship grep (expect empty)

```
Style.font.size(
Quickshell.clipboard[^T]
env .*API_KEY=
bash -lc
/workspace/
handleSummonPayload
signal dataChanged
```

Also confirm every remote title/snippet `Text` has `textFormat: Text.PlainText`.

## Verify

```sh
python3 -m py_compile scripts/search.py
python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location('search', 'scripts/search.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
out = m.strip_simple_html('&lt;img src=x&gt;')
assert '&lt;img' not in out.lower() and '<img' not in out.lower()
print('FW-01 OK:', repr(out), 'UA', m.VERSION)
PY
python3 scripts/search.py --dry-run --query mars
rg -n 'Style\.font\.size\(|Quickshell\.clipboard[^T]|bash -lc|/workspace/|handleSummonPayload|signal dataChanged' .
```

## Still for live Omarchy VM

- Confirm `Style.font.*` named tokens resolve on target shell
- Confirm Quickshell `clipboardText` + https Open + MATCH/RELATED on a real search
