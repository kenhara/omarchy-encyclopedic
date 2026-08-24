# Encyclopedic 0.1.2 — audit fix map

Mapping of `AUDIT.md` findings → fixes shipped in **0.1.2**.

| ID | Severity | Fix |
|----|----------|-----|
| **FW-01** | High | `strip_simple_html`: unescape → strip tags → optional second unescape → whitespace collapse. Repro: encoded `<img>` no longer reconstitutes live markup. |
| **FW-02** | Med-High | `Panel.qml`: every Text bound to remote title/snippet/WITNESS uses `textFormat: Text.PlainText`. |
| **FW-03** | Medium | `WitnessStore.openUrlExternal` / `sanitizeOpenUrl`: allow `https:` only; else construct `https://grokipedia.com/page/{slug}` or toast refuse. `search.py` sanitizes result URLs the same way. |
| **FW-04** | Med-High | `Quickshell.clipboardText = t`; shell fallback `bash -c` with if/elif wl-copy → xclip → xsel; toast only on Quickshell success or `copyProc` exit 0. |
| **FW-05** | Medium | Manifest `resultLimit`: `type: integer`, `min: 1`, `max: 20`, `step: 1`. |
| **FW-06** | Low-Med | `persistToDisk` / `persistClear` call `FileView.setText` directly (dropped mkdir + `callLater` race). |
| **FW-07** | Low-Med | Open checks `Qt.openUrlExternally` bool; copy/open toasts only on real success (`onExited` 0 for Process paths). |
| **FW-08** | Low-Med | Failed/`ok:false` lookup sets `lastError` + toast only — keeps prior results/primary/related. |
| **FW-09** | Low | Removed unused in-process rate limiter; README no longer claims inter-call spacing. |
| **FW-10** | Low | Dropped redundant related recompute in `split_primary_related`. |
| **FW-11** | Low | Wired `lastUpdatedText` under panel header (“looked up …”). |
| **FW-12** | Low | QML trusts `search.py` `primary`/`related` when the key is present; client split is fallback only. |
| **FW-13** | Low | Deleted summon/`handleSummonPayload` machinery; renamed middle-click handler to `clearLastSearch`. |
| **FW-14** | Low | Hover (`hoverEnabled` + `containsMouse`) on LOOK UP, action pills, show-more, and cards. |
| **FW-15** | Low | Scrubbed `/workspace` and playbook-peer paths from `DESIGN.md`. |
| **FW-16** | Low | `search.py` reads version from `manifest.json` for User-Agent. |
| **FW-17** | Trivial | LICENSE: unquoted second `Software`. |
| **FW-18** | Trivial | Committed `AUDIT.md`; `REPO.md` is a short pointer to README. |
| **FW-19** | Low | `forceActiveFocus` on query field when panel opens. |
| **FW-20** | Low | `pluginDir` runs through `decodeURIComponent`. |
| **FW-21** | Low | Dropped `barWidget.aliases`; discovery terms live in `keywords`; README claim softened. |

Also: replaced all `Style.font.size(N)` with named tokens (`caption` / `bodySmall` / `body` / `subtitle` / `title`).

## Verify

```sh
python3 -m py_compile scripts/search.py
python3 - <<'PY'
import importlib.util
spec = importlib.util.spec_from_file_location('search', 'scripts/search.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
out = m.strip_simple_html('&lt;img src=x&gt;')
assert '<img' not in out.lower()
print('FW-01 OK:', repr(out))
PY
python3 scripts/search.py --query ''
python3 scripts/search.py --dry-run --query mars
rg -n 'Style\.font\.size\(|Quickshell\.clipboard[^T]|bash -lc' .
```

## 0.1.20 (marketplace #2218)

| ID | Finding | Fix |
|----|---------|-----|
| **HC-01** | Unbounded `resp.read()` / `HTTPError.read()` in `http_get_json` | Cap at `MAX_REMOTE_BYTES` (5 MiB); oversize → `(0, {error: response too large})` so search/fetch_page treat as transient. Never parse a partial body. |
| **HC-02** | Helper stdout unbounded | `emit()` rejects lines over `MAX_RESPONSE_BYTES` (1 MiB) with `{ok:false, error: helper response too large}`. |
| **HC-03** | `WitnessStore` SplitParser accumulates with no ceiling | `maxHelperOutput` 2 MiB; per-stream overflow flags; kill producer; toast `response too large`; no JSON.parse. |
| **HC-04** | FileView loads user-writable cache wholesale | `--load-cache` helper read capped at `MAX_CACHE_BYTES` (2 MiB); FileView writes only (`preload: false`). |


## 0.1.21 (marketplace #2218 follow-up)

| ID | Finding | Fix |
|----|---------|-----|
| **HC-05** | `load_cache()` still opened the replaceable cache with blocking `open(path, "rb")` — follows a symlink and can hang on a FIFO before the 2 MiB cap | Open `O_NOFOLLOW | O_NONBLOCK`; require `S_ISREG`; symlink/FIFO/non-regular emit `{cleared: true}` so the helper neither redirects nor blocks. Oversize still rejects. |
