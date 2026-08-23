# Fair Witness — design notes

**Status:** 0.1.0 (MVP — one search, LOOK UP, result cards)  
**Id:** `harris.fair-witness`  
**Paths:** `/workspace/omarchy-fair-witness/` · playbook peers: Yellow Pixels 0.2.0, Space Jockey, Security Theater

## Why

Named for Heinlein’s *Stranger in a Strange Land* Fair Witness: look it up,
report what it says — no spin. Personal unofficial client for public
Grokipedia full-text search. No API keys. No vendor chrome.

## Shape (playbook — Yellow Pixels 0.2.0 lessons)

| Lesson | Apply |
|--------|--------|
| `bar-widget` + nested `Panel.qml` | Same — no separate panel kind |
| Theme tokens (`Color` / `Style` / `bar.foreground`) | Ice accent on title + LOOK UP |
| Schema knobs early | `resultLimit` int default 8 only |
| Honest empty/error | Toast on miss; quiet disclaimer |
| Ship extras | `preview.png`, Remove / Security / Network |
| Cache last success | `~/.cache/fair-witness/last.json` |
| Middle-click useful | Clear last search + toast "Cleared" |
| MIT + manifest at root | Marketplace layout |
| Unofficial disclaimer | Not affiliated with xAI / Grokipedia |
| Primary UI simple | One field + big button + cards — no chips |

## Bar

`● FW` — left click toggles panel. Tooltip: *Fair Witness — look it up ·
middle: clear*. Middle click clears last search / cache.

## Panel (0.1.0)

1. Big **FAIR WITNESS** + *look it up · report what it says*
2. One search / paste field
3. Huge ice **LOOK UP**
4. Result cards: title + snippet; Open / Copy title / Copy link
5. Optional **WITNESS** summary card for the selected result (snippet; page API not public in MVP)
6. Quiet footer: unofficial · not affiliated with xAI / Grokipedia · Fair Witness is Heinlein

## Data

- Search: `GET https://grokipedia.com/api/full-text-search?query=…&limit=8`
- Article URL: `https://grokipedia.com/page/{slug}`
- Page content API tried; not available publicly → search-only MVP

## Non-goals

Auth, write APIs, vendor branding, Grok chat, offline encyclopedia dump.
