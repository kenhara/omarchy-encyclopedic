# Audit — `kenhara.encyclopedic` (Omarchy plugin) v0.1.1

## Context

Encyclopedic is an Omarchy Quickshell `bar-widget` plugin (`BarWidget.qml` →
`Panel.qml` + `WitnessStore.qml`) that shells out to `scripts/search.py` to hit
Grokipedia's public full-text search endpoint and render result cards, with a
direct-match "MATCH" hero and "RELATED" cards. The goal of this audit is to hold
it to the bar of the author's own shipped Omarchy plugins (Enricherino,
Compliantish, Rocketlauncher — all found on disk and used here as the
"known-good" reference) and to DHH-quality Omarchy work generally, and to catch
correctness bugs before another agent applies fixes.
Every finding carries a stable ID, a `file:line` anchor, why it matters, and
concrete fix guidance so it can be executed without further context. This
document is written in the same format as the author's existing
`omarchy-compliantish/AUDIT.md` and `omarchy-rocketlauncher/AUDIT.md` and is
intended to be committed to the repo root as **`AUDIT.md`** (which this plugin,
unlike its two siblings, currently lacks — see FW-18).
**Verification performed:** all 12 source/doc files read in full;
`python3 -m py_compile scripts/search.py` (OK); `--dry-run` and empty-query CLI
paths exercised (valid JSON, exit 2); the two headline bugs reproduced with
isolated tests — `strip_simple_html` re-introducing live markup (FW-01) and the
clipboard fallback chain running `xclip`/`xsel` after `wl-copy` (FW-04). Omarchy
conventions were checked against the author's three sibling plugins on disk, the
bundled canonical manifests in `omarchy-rocketlauncher/docs/research/examples/`, the
official Quickshell v0.3.0 docs, and the Omarchy `quattro` shell source
(`shell/Ui/BarWidget.qml`, `WidgetButton.qml`, `Panel.qml`, `bin/omarchy-plugin-validate`).
Confirmed **correct** (not bugs): `WidgetButton.pressed(int button)` with
`Qt.LeftButton`/`Qt.MiddleButton` (there is no `clicked`); the `Panel`
`open/close/toggle/closeForPopoutSwitch` + `opened`/`popoutSwitchClosing` surface
and `bar.switchPanelFrom(owner, direction)`; `BarWidget` `moduleName`/`settings`/
`setting(name, fallback)`; `FileView.setText`/`text()` and its already-atomic
writes (`atomicWrites` defaults to `true`); `Process`/`SplitParser`; the
`mkdir -p` → `Qt.callLater(setText)` write pattern; and the
`kinds:["bar-widget"]` + `entryPoints.barWidget` manifest shape (the validator
maps them as `bar-widget:barWidget`) — all match the siblings and upstream.
**Corrected during verification** (now findings, not clean): the clipboard API
(FW-04), `handleSummonPayload`/`onBarMiddleClick` framework assumptions (FW-13),
and the `int` schema type (FW-05).
**Headline:** For a tool whose entire promise is *"look it up, report what it
says — no spin,"* the worst failure mode is **rendering untrusted remote content
as live markup**. `scripts/search.py`'s `strip_simple_html` unescapes HTML
entities *after* stripping tags, which turns `&lt;img src=…&gt;` back into a real
`<img>` tag in the title/snippet, and the QML `Text` elements that display those
fields use Qt's default `AutoText`, which renders such markup as rich text. That
chain (FW-01 + FW-02) lets a crafted Grokipedia result inject rich text / remote
image fetches into the panel. These are the bar-clearing issues; everything else
is secondary.
---

## Severity summary

| ID | Severity | Area | One-line |
|----|----------|------|----------|
| FW-01 | **High** | search.py | `strip_simple_html` unescapes after stripping → re-introduces live `<img>`/`<script>` markup into title & snippet |
| FW-02 | **Medium-High** | Panel.qml | Remote title/snippet rendered with default `Text.AutoText` (no `PlainText`) → re-introduced markup is interpreted as rich text |
| FW-03 | Medium | search.py / WitnessStore | Remote-controlled `url` field opened via `Qt.openUrlExternally`/`xdg-open` with no scheme allow-list |
| FW-04 | **Medium-High** | WitnessStore | Clipboard fast-path uses a non-existent API (`Quickshell.clipboard`), so every copy falls to a mis-grouped shell fallback that runs `xclip`/`xsel` after `wl-copy` |
| FW-05 | Medium | manifest.json | `resultLimit` schema uses `"type":"int"` with no `min`/`max`/`step`; author's own numeric knobs use `"integer"` + bounds |
| FW-06 | Low-Med | WitnessStore | Cache-dir `mkdir` races the first write; first-run cache silently lost |
| FW-07 | Low-Med | WitnessStore | "Opened"/"Copied" toast shown even when the action silently failed |
| FW-08 | Low-Med | WitnessStore | A failed/empty lookup wipes the previously shown good results |
| FW-09 | Low | search.py / README | Rate limiter is a no-op — one HTTP call per process; README claims "spacing between HTTP calls in one process" |
| FW-10 | Low | search.py | `split_primary_related` recomputes `related` twice; comment describes slug-dedup that isn't implemented |
| FW-11 | Low | WitnessStore / Panel | Several store members computed/persisted but never surfaced (`lookedUpAt`/`lastUpdatedText`, `dataSource`, `panelOpen`, `totalCount`) |
| FW-12 | Low | search.py / QML / mock | primary/related + `normKey`/`slugKey` logic triplicated across three files — divergence risk |
| FW-13 | Low-Med | BarWidget / WitnessStore | Speculative framework APIs: `handleSummonPayload` + payload-`open()` are never invoked for a bar-widget; `onBarMiddleClick()` implies a hook that doesn't exist |
| FW-14 | Low | Panel.qml | Buttons/cards show a pointer cursor but no hover feedback; the HTML mock has `:hover`, the QML doesn't |
| FW-15 | Low | DESIGN.md | Internal `/workspace/…` path + internal "playbook peers" leak in a shipped public doc |
| FW-16 | Low | multiple | Version `0.1.1` hardcoded in ~13 places incl. the UA string — no single source of truth |
| FW-17 | Trivial | LICENSE | Second "Software" is quoted — deviates from canonical MIT text |
| FW-18 | Trivial | repo | No `AUDIT.md` (both sibling plugins ship one); REPO.md duplicates README install |
| FW-19 | Trivial | Panel.qml | Search field not auto-focused on panel open |
| FW-20 | Low | WitnessStore | `pluginDir` derivation doesn't percent-decode the `file://` URL → breaks if the plugin path contains spaces |
| FW-21 | Low | manifest / docs | `barWidget.aliases` is not a recognized bar-widget key (ignored by the loader); the README's "aliases aid discovery" claim doesn't hold |
---

## High severity

### FW-01 · `strip_simple_html` re-introduces live markup (unescape-after-strip)

**File:** `scripts/search.py:36-45` (`strip_simple_html`), used by `normalize_item` at `:95-96`
The function strips tags first, then calls `html.unescape` last:
```python
s = re.sub(r"</?(?:em|b|i|strong|mark|span|a|br|p)(?:\s[^>]*)?>", "", s, flags=re.I)
s = re.sub(r"<[^>]+>", "", s)   # strip tags
s = html.unescape(s)            # THEN unescape — turns &lt;img&gt; back into <img>
```
Because unescaping happens after tag removal, any entity-encoded markup in the
source survives as **live** markup in the output. Reproduced:
```
'&lt;img src=x onerror=alert(1)&gt;'            -> '<img src=x onerror=alert(1)>'
'<em>Mars</em> is the &lt;script&gt;evil&lt;/script&gt;' -> 'Mars is the <script>evil</script>'
```
Grokipedia content is open/AI-generated, so a title or snippet containing
`&lt;img src="http://tracker/…"&gt;` reaches the QML layer as a real `<img>` tag.
Combined with FW-02 this is a rendering-integrity / privacy-leak vector; on its
own it also just produces visibly wrong snippets (stray `<script>` text). Note
none of the sibling plugins strip HTML at all — this routine is unique to Fair
Witness, so the exposure is Fair-Witness-specific.
**Fix:** Unescape **before** stripping (and, ideally, once more after), so no tag
can be reconstituted after the tag pass. E.g. `html.unescape(s)` first, then the
two `re.sub` tag passes, then whitespace-collapse. Pair with FW-02.
---

## Medium-High severity

### FW-02 · Remote text rendered with `Text.AutoText` (no `PlainText`)

**File:** `Panel.qml` — every `Text` bound to remote data: hero title `:239-249`, hero snippet `:251-263`, RELATED title `:393-401` / snippet `:403-414`, flat-card title `:522-530` / snippet `:532-543`, WITNESS `:658-680`
None of these set `textFormat`, so they use Qt's default `Text.AutoText`, which
runs `Qt::mightBeRichText()` and renders anything that looks like HTML as rich
text. Qt rich text supports `<img src=…>` (including remote and `file://` URLs)
and `<a href>`. With FW-01 feeding reconstituted `<img>`/`<a>` tags from remote
results, the panel will issue outbound image requests or mis-render on hostile
input. Even without FW-01, defaulting remote content to AutoText is the wrong
default for a "report what it says" tool.
**Fix:** Set `textFormat: Text.PlainText` on every `Text` that displays
remote-derived fields (titles, snippets). This is cheap, local, and makes the
display honest regardless of what the endpoint returns. (Siblings don't set this
today, but they also don't render open-web content or reconstitute markup — Fair
Witness genuinely needs it.)
---

## Medium severity

### FW-03 · Remote `url` opened without a scheme allow-list

**Files:** `scripts/search.py:97` (`normalize_item`), `WitnessStore.qml:105-121` (`openUrlExternal`), `:133-142` (`openResult`), `:267-273` (`openPrimary`)
`normalize_item` prefers the server-supplied `url` over the constructed
`grokipedia.com/page/{slug}` one: `url = item.get("url") or (article_url(slug) …)`.
That value flows straight into `Qt.openUrlExternally(u)` / `xdg-open <u>`. Because
the field is fully attacker-influenceable, a crafted result can make the widget
hand an arbitrary URI scheme to the desktop opener (`file://`, `mailto:`, custom
app schemes, etc.) on a single click of **Open**.
**Fix:** Validate before opening — accept only `https:` (or better, only
`https://grokipedia.com/…`) and otherwise fall back to the constructed article
URL or refuse with a toast. Cheapest place is `WitnessStore.openUrlExternal`
(reject non-`https` schemes); optionally also have `search.py` drop/normalize any
non-grokipedia `url`.

### FW-04 · Clipboard: dead fast-path API + mis-grouped shell fallback

**File:** `WitnessStore.qml:89-93` (fast path), `:95-99` (bash fallback)
Two compounding problems make **Copy title / Copy link** unreliable:
**(a) The fast path is dead code.** Verified against the Quickshell v0.3.0 docs:
there is **no `clipboard` object** on the `Quickshell` singleton — the clipboard
is a single writable string property, `Quickshell.clipboardText`. So
`if (Quickshell.clipboard) { Quickshell.clipboard.text = t }` is always falsy and
**every** copy falls through to the shell fallback below.
**(b) The shell fallback has wrong operator precedence.** With the fast path
dead, this runs on every copy:
```
printf '%s' "$1" | (command -v wl-copy >/dev/null && wl-copy \
  || command -v xclip >/dev/null && xclip -selection clipboard \
  || command -v xsel >/dev/null && xsel --clipboard --input || cat >/dev/null)
```
`&&`/`||` are left-associative with equal precedence, so this is **not**
"try wl-copy, else xclip, else xsel." Reproduced with stub binaries: when
`wl-copy` succeeds, `xclip` **and** `xsel` also run. `wl-copy` consumes the pipe,
so the later tools read EOF and set the clipboard to an **empty string**. On a
box where both a Wayland and an X clipboard tool are installed, **Copy silently
copies nothing**; on a wl-copy-only box it works but emits harmless
"command not found" noise. (The precedence pattern is copied verbatim across all
three sibling plugins; the fix should ideally propagate.)
**Fix:** (a) use the real API — `Quickshell.clipboardText = t` (note the
documented Wayland caveat: a Quickshell window must be focused, which the open
panel satisfies). (b) Keep a corrected fallback that runs exactly one tool, e.g.
`if command -v wl-copy >/dev/null; then wl-copy; elif command -v xclip …; then xclip -selection clipboard; elif command -v xsel …; then xsel --clipboard --input; else cat >/dev/null; fi`.

### FW-05 · `resultLimit` schema type/bounds diverge from the house convention

**File:** `manifest.json:40-48`
```json
{ "key": "resultLimit", "type": "int", "label": "Result limit",
  "description": "Max search results to request (1–20). Default 8.",
  "defaultValue": 8 }
```
The author's own numeric knobs use `"type": "integer"` with `min`/`max`/`step`
(e.g. `omarchy-compliantish` `refreshIntervalSec`: `"integer"`, `min` 60,
`max` 86400, `step` 60). `"int"` is not the form any sibling or the canonical
`manifest-template-bar-widget.json` uses. The official docs confirm only
`string`/`boolean`/`multiselect` schema types (the inline-schema settings form is
rendered by a separate settings app, so `int`/`integer`/`min`/`max` couldn't be
confirmed against upstream) — but the author's shipped `"integer"` knobs are the
known-working precedent. `"int"` matches neither the docs nor the siblings and may
be silently ignored or fail to render. The "1–20" range lives only in prose. Not
fatal (the QML `clampLimit` at `:51-57` re-clamps regardless), but the settings UI
may misbehave.
**Fix:** `"type": "integer"`, add `"min": 1, "max": 20, "step": 1` to match the
author's own convention.
---

## Low–Medium severity

### FW-06 · First-run cache write races the `mkdir`

**File:** `WitnessStore.qml:194-202` (`persistToDisk`), `:204-211` (`persistClear`)
```js
ensureCacheDir.running = true          // async: mkdir -p ~/.cache/encyclopedic
Qt.callLater(function() { cacheFile.setText(body) })   // may run before mkdir exits
```
`Qt.callLater` fires on the next event-loop tick, typically **before** the
`mkdir` subprocess has finished, so on a truly fresh install the first
`setText` targets a directory that doesn't exist yet; the first successful search
is never cached. (Same shape as `omarchy-compliantish/AUDIT.md` ST-08; it is
the shared house pattern.) Compounding it: `FileView.setText` reports failure via
the async `saveFailed` signal, not by throwing, so the surrounding `try/catch`
(`:198-200`) can't catch a write error — all write failures are silently dropped.
**Fix:** Write from the `mkdir` Process's `onExited` (chain the write after the
dir is guaranteed), or make the cache `FileView` create parents. Applying it here
and back-porting to the siblings would retire the pattern.

### FW-07 · Success toast shown even when the action failed

**File:** `WitnessStore.qml:105-121` (`openUrlExternal`), `:82-103` (`copyText`)
`openUrlExternal` calls `Qt.openUrlExternally(u)` and unconditionally shows
"Opened" and returns `true`. Verified: `Qt.openUrlExternally` **returns a `bool`
and does not throw**, so the `catch`→`xdg-open` fallback is essentially
unreachable and a failed open still reports "Opened". `copyText`'s bash branch
likewise toasts "Copied" the instant the Process is *launched*, before it can
fail. (Same as ST-06 in the sibling audit.)
**Fix:** Check `Qt.openUrlExternally`'s boolean return and toast accordingly; for
the bash clipboard path, toast on the Process's `onExited` with a 0 exit code
rather than at launch.

### FW-08 · A failed lookup wipes the last good results

**File:** `WitnessStore.qml:335-372` (`onSearchFinished` → `applyPayload`), `:293-333`
On a non-`ok` result (network error, HTTP error), `onSearchFinished` still calls
`applyPayload`, which sets `store.results = []` (`:298-301`) and clears
primary/related. A transient network blip therefore blanks the panel that was
showing a good prior result, replaced only by an error line.
**Fix:** On `!obj.ok`, surface the error (toast + `lastError`) but leave the
existing `results`/`primary`/`related`/`selectedIndex` intact, so a flaky network
doesn't destroy the last honest answer.
---

## Low severity

### FW-09 · Rate limiter is dead code; README overstates it

**Files:** `scripts/search.py:25-27, 54-58`; `README.md:134`
`MIN_INTERVAL_SEC`/`_last_http_at` space *consecutive* HTTP calls within one
process, but the CLI makes exactly **one** call per invocation and exits, so the
sleep never triggers. README says "Polite client-side spacing between HTTP calls
in one process," which is vacuously true.
**Fix:** Either drop the limiter and soften the README line, or keep it and
label it as forward-looking. Low stakes; mainly an honesty/clarity nit.

### FW-10 · `split_primary_related` recomputes `related`; misleading comment

**File:** `scripts/search.py:149-153`
```python
related = [r for r in results if r is not primary]
# Also drop identity-equal duplicates by slug if same object identity fails
if related and primary in results:
    related = [r for r in results if r is not primary]   # identical recompute
```
The second block recomputes the exact same list; the comment promises slug-based
dedup that never happens.
**Fix:** Delete the `if` block (and the comment), or actually dedup by slug if
that was the intent.

### FW-11 · Built-but-unwired store state

**Files:** `WitnessStore.qml` — `lookedUpAt`/`formatUpdated`/`lastUpdatedText` (`:37-38, 66-75`), `dataSource` (`:26`), `panelOpen` (`:12`), `totalCount` (emitted in `search.py:218`), `searchBuf` public prop (`:25`); none referenced in `Panel.qml`
`formatUpdated` computes a nice "just now / 3m ago" string and `lookedUpAt` is
persisted, but the panel never shows it; `dataSource`, `panelOpen`, `totalCount`
are set/stored and never read.
**Fix:** Either wire the honest touch into the panel (a small "looked up 3m ago ·
N results" line under the header would fit the "report what it says" ethos), or
remove the dead members. Prefer wiring `lastUpdatedText` in; drop the rest.

### FW-12 · Triplicated primary/related logic

**Files:** `scripts/search.py:107-153`, `WitnessStore.qml:214-265`, `docs/preview/index.html:226-247`
`normKey`, `slugKey`, and the split are reimplemented three times. They already
differ subtly (Python breaks the loop on a title hit; the QML mirrors it; the
mock is a third copy) and will drift.
**Fix:** Treat `search.py`'s output as authoritative (it already emits
`primary`/`related`), and have the QML use them directly rather than re-splitting;
keep the mock clearly labeled as a standalone demo. Reduces three copies to one
source of truth.

### FW-13 · Speculative / dead framework APIs

**Files:** `BarWidget.qml:38-46, 60-63`, `WitnessStore.qml:409-442`, `Panel.qml:42-48`
Verified against the Omarchy `quattro` source, two framework assumptions don't
hold:
- **`handleSummonPayload` is invented.** The string appears **nowhere** in the
  Omarchy repo. The real summon contract injects an `open(payloadJson)` function —
  and, critically, summon has **"no bar target"**: a `kinds:["bar-widget"]` plugin
  can never be summoned. So `handleSummonPayload` (BarWidget + WitnessStore + the
  Panel wrapper) and the payload branch of `open(payloadJson)` are ~40 lines of
  dead code with respect to the framework; nothing external ever calls them.
- **`onBarMiddleClick()` is not a framework callback.** No such hook exists
  upstream; middle-click works here *only* because `WidgetButton.onPressed` wires
  `Qt.MiddleButton → root.onBarMiddleClick()` itself (which is correct). The name
  implies a framework hook that isn't there.
Neither breaks anything today, but shipping guessed-at framework surface is
exactly the kind of thing the DHH bar rejects.
**Fix:** Either drop the summon machinery entirely (simplest — the widget can't be
summoned), or, if summon is a real goal, add a `panel`/`overlay` kind with a
matching entry point and rename to the real `open(payloadJson)` contract. Rename
`onBarMiddleClick()` to a plain local name (e.g. `clearOnMiddleClick()`) so it
doesn't read as a framework override.

### FW-14 · No hover feedback on buttons/cards

**File:** `Panel.qml` — button/card `Rectangle`s throughout (e.g. LOOK UP `:151-174`, hero actions `:286-348`, card actions `:419-484`, `:548-610`)
Each interactive element sets `cursorShape: Qt.PointingHandCursor` but nothing
changes on hover; the HTML mock, by contrast, has `:hover` states on `.pill`,
`.lookup`, `.btn`, `.more`. The QML feels less alive than its own mock. (Same as
ST-13 in the sibling audit.)
**Fix:** Add a `HoverHandler` (or `MouseArea.containsMouse`) per button and
lighten `color`/`border.color` on hover, matching the mock's brightness bumps.

### FW-15 · Internal scaffolding leaks in DESIGN.md

**File:** `DESIGN.md:5`
`**Paths:** /workspace/omarchy-encyclopedic/ · playbook peers: Enricherino
0.2.0, Rocketlauncher, Compliantish` ships a build-machine absolute path and
internal project references in a public doc. (Same as ST-10 in the sibling
audit.)
**Fix:** Remove the `/workspace/…` path and the "playbook peers" line, or move
them to a private note.

### FW-16 · No single source of truth for the version

**Files:** `manifest.json:5`, `README.md` (×5), `DESIGN.md`, `Panel.qml:7`, `preview.svg:61`, `docs/preview/index.html` (×2), `scripts/search.py:5,24`
`0.1.1` appears in ~13 places, including the runtime User-Agent string
(`search.py:24`). It is currently consistent, but every bump is a manual sweep
and the UA will silently drift. (Cf. ST-09 "version drift" in the sibling audit.)
**Fix:** Have `search.py` read the version from `manifest.json` at runtime for the
UA (single source), and keep doc mentions to a minimum. Low priority while
consistent.

### FW-21 · `barWidget.aliases` is ignored; the "discovery" claim doesn't hold

**Files:** `manifest.json:30-36`; `README.md:37-38`, `DESIGN.md:25`
`aliases` is only consumed by Omarchy's **menu/agents** plugins, not the
bar-widget loader — for a `kinds:["bar-widget"]` plugin it is silently ignored
dead config. The README states *"Aliases / keywords may mention Grokipedia for
discovery,"* which doesn't hold if the loader never reads them. (The siblings
carry `aliases` too, so this is a house-wide harmless habit — but the discovery
claim is specific to this plugin's docs.)
**Fix:** Drop `barWidget.aliases` (or move discovery terms into `keywords`, which
is also unvalidated but at least the documented catch-all), and soften the README
line so it doesn't promise behavior the loader doesn't provide.
---

## Trivial

### FW-17 · LICENSE deviates from canonical MIT

**File:** `LICENSE:7` — `to deal in the "Software" without restriction` quotes the
second "Software"; canonical MIT does not. (Identical to ST-11.) **Fix:** remove
the quotes.

### FW-18 · Missing `AUDIT.md`; REPO.md duplicates README install

**Files:** repo root (no `AUDIT.md`); `REPO.md:8-11` vs `README.md:44-46`
Both sibling plugins ship an `AUDIT.md`; Encyclopedic does not (this document is
intended to fill that gap). `REPO.md` also re-states the README install block —
two copies to keep in sync (cf. ST-12). **Fix:** commit this as `AUDIT.md`; have
REPO.md link to README rather than duplicate it.

### FW-19 · Search field not focused on open

**File:** `Panel.qml:114-146` (`queryEdit`)
Opening the panel doesn't focus the query field, so the user must click before
typing. **Fix:** `forceActiveFocus()` on `queryEdit` when the panel opens (guard
so it doesn't steal focus while loading).

### FW-20 · `pluginDir` doesn't percent-decode the file URL

**File:** `WitnessStore.qml:31-34`
`String(Qt.resolvedUrl(".")).replace(/^file:\/\//,"").replace(/\/$/,"")` leaves
percent-encoding intact, so a plugin path containing a space (`%20`) yields a
`searchPath` `python3` can't find. Edge case, and shared with the siblings, but
real. **Fix:** `decodeURIComponent(...)` the stripped path.
---

## Suggested fix order for the implementing agent

1. **FW-01 + FW-02** together (the headline security chain) — `search.py`
   unescape order + `textFormat: Text.PlainText` on remote `Text` elements.
2. **FW-04** clipboard (use `Quickshell.clipboardText` + fix the fallback grouping)
   and **FW-03** URL scheme allow-list — small, contained correctness fixes that
   restore Copy and make Open safe.
3. **FW-05** manifest `integer` + bounds — one-line schema fix.
4. **FW-06 / FW-07 / FW-08** robustness/honesty around cache-write, toasts, and
   result-clearing.
5. **FW-13** — decide whether to delete the dead summon machinery or make it real;
   deleting is the DHH-simple choice.
6. The Low/Trivial batch (FW-09…FW-21) as cleanup — several are one-liners and
   several mirror the author's own sibling-audit findings.

## Verification after fixes

- `python3 -m py_compile scripts/search.py` and re-run the FW-01 reproduction
  (`strip_simple_html('&lt;img src=x&gt;')` must return literal text, no `<img>`).
- `python3 scripts/search.py --query 'mars' --limit 8` on a networked Omarchy box
  → valid JSON, `ok:true`, a `primary` for an exact-title query.
- In Omarchy: open the panel, confirm the settings knob renders as a bounded
  integer (FW-05); Copy title/link with both `wl-copy` and `xclip` present
  actually pastes the value (FW-04); Open only launches `https` URLs (FW-03);
  hover states respond (FW-14); a network failure keeps the prior results (FW-08).
