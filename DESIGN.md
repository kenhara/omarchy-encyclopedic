# Encyclopedic — design notes

**Status:** 0.1.22  
**Id:** `kenhara.encyclopedic`

## Why

Named for Heinlein’s *Stranger in a Strange Land* Encyclopedic: look it up,
report what it says — no spin. Personal unofficial client for public
Grokipedia full-text search. No API keys. No vendor chrome.

## Shape

| Lesson | Apply |
|--------|--------|
| `bar-widget` + nested `Panel.qml` | Same — no separate panel kind |
| Theme tokens (`Color` / `Style` / `bar.foreground`) | Ice accent on title + LOOK UP |
| Schema knobs early | `resultLimit` integer 1–20 default 8 |
| Honest empty/error | Toast on miss; keep prior results on fail |
| Ship extras | `preview.png`, Remove / Security / Network |
| Cache last success | `~/.cache/encyclopedic/last.json` |
| Middle-click useful | Clear last search + toast "Cleared" |
| MIT + manifest at root | Marketplace layout |
| Unofficial disclaimer | Not affiliated with xAI / Grokipedia |
| Primary UI simple | One field + big button + cards — no chips |
| Remote text | `textFormat: Text.PlainText`; grokipedia.com https Open |

## Bar

Tintable FA search (`\uf002`) — left click toggles panel. Tooltip:
*Encyclopedic — look it up · middle: clear*. Middle click clears last
search / cache.

## Panel

1. Big **ENCYCLOPEDIC** + *look it up* (+ looked-up age)
2. One search / paste field (focused on open)
3. Huge ice **LOOK UP**
4. **Direct match** (title/slug == query CI): expandable **MATCH** hero
   (larger title; Preview fetches full article in-panel; Show more expands
   the loaded body; Preview accent / Open + Copy Link secondary), then **RELATED** cards
5. **No direct match:** flat result cards + optional **WITNESS** summary
   for selected / Previewed card — no fake hero
6. Quiet footer: Unofficial · Grokipedia

## Data

- Search: `GET https://grokipedia.com/api/full-text-search?query=…&limit=8`
- Article URL: `https://grokipedia.com/page/{slug}` (Open allowlists grokipedia.com https)
- Preview: `GET https://grokipedia.com/api/page-preview?slug=…` (full body, in-panel)

## Non-goals

Auth, write APIs, vendor branding, Grok chat, offline encyclopedia dump.
