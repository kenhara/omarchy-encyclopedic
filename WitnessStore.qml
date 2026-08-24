import QtQuick
import Quickshell
import Quickshell.Io

// Encyclopedic — runs scripts/search.py via Process; parses JSON stdout.
// Public Grokipedia search + page-preview. No API keys.
// Caches last successful search to ~/.cache/encyclopedic/last.json
Item {
  id: store

  property int resultLimit: 8

  property string queryInput: ""
  property bool loading: false
  property string lastError: ""
  property bool lastRetryable: false
  property string toastText: ""
  property var results: []          // [{title,slug,url,snippet}, ...]
  property var primary: null        // direct title/slug match, or null
  property var related: []          // results without primary (or all if no primary)
  property bool heroExpanded: false
  property int selectedIndex: -1
  property string searchBuf: ""
  property string articleBuf: ""
  property bool articleLoading: false
  property bool articleExpanded: false
  property string articleSlug: ""
  property string articleTitle: ""
  property string articleBody: ""
  property string articleError: ""
  property string articleRequestSlug: ""
  property string articleFetchSlug: ""
  property string lookedUpAt: ""
  property string dataSource: "none"  // disk | search | none
  property string lastQuery: ""
  property var lastPayload: null    // full JSON from search.py

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/encyclopedic"
  readonly property string cachePath: cacheDir + "/last.json"
  // FW-20: percent-decode so paths with spaces work for python3
  readonly property string pluginDir: {
    var raw = String(Qt.resolvedUrl("."))
      .replace(/^file:\/\//, "")
      .replace(/\/$/, "")
    try {
      return decodeURIComponent(raw)
    } catch (e) {
      return raw
    }
  }
  readonly property string searchPath: pluginDir + "/scripts/search.py"

  // FA search (\uf002) — tintable via Text.color; color emoji is not.
  readonly property string barGlyph: "\uf002"
  readonly property string barLabel: store.barGlyph
  readonly property string lastUpdatedText: formatUpdated(store.lookedUpAt)

  readonly property bool hasResults: store.results && store.results.length > 0
  readonly property bool hasPrimary: !!(store.primary && typeof store.primary === "object")
  readonly property bool articleIsPrimary: {
    if (!store.hasPrimary || !store.articleSlug)
      return false
    return String(store.primary.slug || "") === store.articleSlug
  }

  readonly property var selectedResult: {
    if (store.selectedIndex < 0 || !store.results || store.selectedIndex >= store.results.length)
      return null
    return store.results[store.selectedIndex]
  }

  // WITNESS pane: selected result that is not the MATCH hero (hero is the preview).
  readonly property bool showingWitness: {
    var s = store.selectedResult
    if (!s)
      return false
    if (store.hasPrimary && store.sameResult(store.primary, s))
      return false
    return true
  }

  function clampLimit(n) {
    var v = parseInt(n, 10)
    if (!isFinite(v)) return 8
    if (v < 1) return 1
    if (v > 20) return 20
    return v
  }

  function applySettings(opts) {
    opts = opts || {}
    if (opts.resultLimit !== undefined)
      store.resultLimit = store.clampLimit(opts.resultLimit)
  }

  function formatUpdated(iso) {
    if (!iso) return "never"
    var t = Date.parse(iso)
    if (!isFinite(t)) return String(iso)
    var sec = Math.max(0, Math.floor((Date.now() - t) / 1000))
    if (sec < 60) return "just now"
    if (sec < 3600) return Math.floor(sec / 60) + "m ago"
    if (sec < 86400) return Math.floor(sec / 3600) + "h ago"
    return Math.floor(sec / 86400) + "d ago"
  }

  function showToast(msg) {
    store.toastText = String(msg || "")
    toastClear.restart()
  }

  function copyText(text) {
    var t = String(text || "")
    if (!t.length) {
      store.showToast("Nothing to copy")
      return false
    }
    try {
      if (typeof Quickshell !== "undefined" && Quickshell.clipboardText !== undefined) {
        Quickshell.clipboardText = t
        store.showToast("Copied")
        return true
      }
    } catch (e) {}
    // Shell fallback: exactly one of wl-copy / xclip / xsel; bash -c (not -lc).
    // Toast only on copyProc success (onExited) — never claim Copied early.
    copyProc.command = [
      "bash", "-c",
      't="$1"; if command -v wl-copy >/dev/null 2>&1; then printf "%s" "$t" | wl-copy; elif command -v xclip >/dev/null 2>&1; then printf "%s" "$t" | xclip -selection clipboard; elif command -v xsel >/dev/null 2>&1; then printf "%s" "$t" | xsel --clipboard --input; else exit 127; fi',
      "fw-copy", t
    ]
    copyProc.running = true
    return true
  }

  function articleUrlFromSlug(slug) {
    var s = String(slug || "").trim().replace(/^\//, "")
    if (!s.length) return ""
    return "https://grokipedia.com/page/" + encodeURIComponent(s).replace(/%2F/g, "/")
  }

  function sanitizeOpenUrl(url, slug) {
    var u = String(url || "").trim()
    if (u.toLowerCase().indexOf("https:") === 0)
      return u
    var built = store.articleUrlFromSlug(slug)
    if (built.length)
      return built
    return ""
  }

  function openUrlExternal(url, slug) {
    var u = store.sanitizeOpenUrl(url, slug)
    if (!u.length) {
      store.showToast("Refused — https only")
      return false
    }
    try {
      var ok = Qt.openUrlExternally(u)
      if (ok !== false) {
        store.showToast("Opened")
        return true
      }
    } catch (e) {}
    openUrlProc.command = ["xdg-open", u]
    openUrlProc.running = true
    return true
  }

  function sameResult(a, b) {
    if (!a || !b || typeof a !== "object" || typeof b !== "object")
      return false
    if (a === b)
      return true
    var aslug = String(a.slug || "")
    var bslug = String(b.slug || "")
    if (aslug.length && aslug === bslug)
      return true
    var aurl = String(a.url || "")
    var burl = String(b.url || "")
    if (aurl.length && aurl === burl)
      return true
    return false
  }

  function indexOfResult(obj) {
    if (!obj || !store.results)
      return -1
    for (var i = 0; i < store.results.length; i++) {
      if (store.sameResult(store.results[i], obj))
        return i
    }
    return -1
  }

  function selectResult(index) {
    var i = parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length) {
      store.selectedIndex = -1
    } else {
      store.selectedIndex = i
    }
  }

  function clearArticle() {
    store.articleLoading = false
    store.articleExpanded = false
    store.heroExpanded = false
    store.articleSlug = ""
    store.articleTitle = ""
    store.articleBody = ""
    store.articleError = ""
    store.articleBuf = ""
    store.articleRequestSlug = ""
    store.articleFetchSlug = ""
  }

  function fetchArticle(slug, title) {
    var s = String(slug || "").trim()
    if (!s.length) {
      store.showToast("No article")
      return false
    }
    if (s === store.articleSlug && store.articleBody && store.articleBody.length) {
      store.articleExpanded = true
      store.heroExpanded = true
      return true
    }
    store.articleRequestSlug = s
    store.articleTitle = String(title || "")
    store.articleError = ""
    store.articleBody = ""
    store.articleSlug = s
    store.articleExpanded = true
    store.heroExpanded = true
    store.articleLoading = true
    if (pageProc.running)
      return true
    store.articleFetchSlug = s
    store.articleBuf = ""
    pageProc.command = [
      "python3",
      "-B",
      store.searchPath,
      "--page",
      s
    ]
    pageProc.environment = ({
      "PYTHONDONTWRITEBYTECODE": "1"
    })
    pageProc.running = true
    return true
  }

  function onPageFinished(exitCode) {
    var fetchSlug = store.articleFetchSlug
    var requested = store.articleRequestSlug
    store.articleBuf = store.articleBuf || ""
    if (!requested) {
      store.articleBuf = ""
      store.articleLoading = false
      return
    }
    if (requested && requested !== fetchSlug) {
      store.articleFetchSlug = requested
      store.articleBuf = ""
      store.articleLoading = true
      pageProc.command = [
        "python3",
        "-B",
        store.searchPath,
        "--page",
        requested
      ]
      pageProc.environment = ({
        "PYTHONDONTWRITEBYTECODE": "1"
      })
      Qt.callLater(function() { pageProc.running = true })
      return
    }
    store.articleLoading = false
    var raw = store.articleBuf || ""
    store.articleBuf = ""
    if (!raw.length) {
      store.articleError = "article produced no output (exit " + exitCode + ")"
      store.showToast(store.articleError)
      return
    }
    var lines = raw.split("\n")
    var blob = ""
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = String(lines[i] || "").trim()
      if (line.charAt(0) === "{") {
        blob = line
        break
      }
    }
    if (!blob.length)
      blob = raw.trim()
    try {
      var obj = JSON.parse(blob)
      if (obj.ok) {
        store.articleSlug = String(obj.slug || fetchSlug || "")
        store.articleTitle = String(obj.title || store.articleTitle || "")
        store.articleBody = String(obj.content || "")
        store.articleError = ""
        store.articleExpanded = true
        store.heroExpanded = true
        if (!store.articleBody.length)
          store.showToast("No article text")
      } else {
        store.articleError = String(obj.error || "Article failed")
        store.articleBody = ""
        store.showToast(store.articleError)
      }
    } catch (e) {
      store.articleError = "article JSON parse failed"
      store.articleBody = ""
      store.showToast(store.articleError)
    }
  }

  // In-panel preview — fetch full article body; never xdg-open / Qt.openUrlExternally.
  function previewResult(index) {
    var i = (index === undefined || index === null) ? store.selectedIndex : parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length) {
      store.showToast("No result")
      return false
    }
    store.selectedIndex = i
    var r = store.results[i]
    return store.fetchArticle(r && r.slug ? r.slug : "", r && r.title ? r.title : "")
  }

  function previewPrimary() {
    if (!store.primary) {
      store.showToast("No result")
      return false
    }
    var i = store.indexOfResult(store.primary)
    if (i >= 0)
      store.selectedIndex = i
    return store.fetchArticle(store.primary.slug || "", store.primary.title || "")
  }

  function previewObject(obj) {
    var i = store.indexOfResult(obj)
    if (i >= 0)
      return store.previewResult(i)
    if (obj && obj.slug) {
      return store.fetchArticle(obj.slug || "", obj.title || "")
    }
    store.showToast("No result")
    return false
  }

  function openResult(index) {
    var i = (index === undefined || index === null) ? store.selectedIndex : parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length) {
      store.showToast("No result")
      return false
    }
    store.selectedIndex = i
    var r = store.results[i]
    return store.openUrlExternal(r && r.url ? r.url : "", r && r.slug ? r.slug : "")
  }

  function copyLink(index) {
    var i = (index === undefined || index === null) ? store.selectedIndex : parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length)
      return store.copyText("")
    return store.copyText(store.results[i].url || "")
  }

  function lookUp() {
    if (store.loading && searchProc.running)
      return
    var q = String(store.queryInput || "").trim()
    if (!q.length) {
      store.lastError = "Enter something to look up"
      store.lastRetryable = false
      store.showToast(store.lastError)
      return
    }
    store.loading = true
    store.lastError = ""
    store.lastRetryable = false
    store.searchBuf = ""
    store.clearArticle()
    var lim = store.clampLimit(store.resultLimit)
    searchProc.command = [
      "python3",
      "-B",
      store.searchPath,
      "--query", q,
      "--limit", String(lim)
    ]
    searchProc.environment = ({
      "PYTHONDONTWRITEBYTECODE": "1"
    })
    searchProc.running = true
  }

  function buildCacheObject(payload, atIso) {
    return {
      version: 1,
      lookedUpAt: atIso || store.lookedUpAt || "",
      query: store.lastQuery || String(store.queryInput || "").trim(),
      resultLimit: store.clampLimit(store.resultLimit),
      payload: payload || store.lastPayload || ({})
    }
  }

  function persistToDisk(obj) {
    // FileView.setText mkpath — no mkdir Process + Qt.callLater race (FW-06).
    var body = JSON.stringify(obj || store.buildCacheObject(), null, 2) + "\n"
    try {
      cacheFile.setText(body)
    } catch (e) {}
  }

  function persistClear() {
    try {
      cacheFile.setText(JSON.stringify({ version: 1, cleared: true }, null, 2) + "\n")
    } catch (e) {}
  }

  // Fallback split only when search.py omitted primary/related (FW-12).
  function normKey(s) {
    return String(s || "").trim().toLowerCase().replace(/\s+/g, " ")
  }

  function slugKey(s) {
    return store.normKey(s).replace(/ /g, "_")
  }

  function splitPrimaryRelated(list, query) {
    var results = Array.isArray(list) ? list : []
    var related = []
    var i
    if (!results.length)
      return { primary: null, related: [] }
    var q = store.normKey(query)
    var qSlug = store.slugKey(query)
    if (!q.length)
      return { primary: null, related: results.slice() }

    var titleHit = null
    var slugHit = null
    for (i = 0; i < results.length; i++) {
      var r = results[i]
      if (!r || typeof r !== "object") continue
      var title = store.normKey(r.title || "")
      var slug = store.slugKey(r.slug || "")
      if (!titleHit && title && title === q)
        titleHit = r
      if (!slugHit && slug && (slug === qSlug || slug === q))
        slugHit = r
      if (titleHit)
        break
    }
    var primary = titleHit || slugHit
    if (!primary)
      return { primary: null, related: results.slice() }

    related = []
    for (i = 0; i < results.length; i++) {
      if (results[i] !== primary)
        related.push(results[i])
    }
    return { primary: primary, related: related }
  }

  function applyPrimarySplit(list, query) {
    var split = store.splitPrimaryRelated(list, query)
    store.primary = split.primary
    store.related = split.related
    if (!split.primary)
      store.articleExpanded = false
  }

  function openPrimary() {
    if (!store.primary) {
      store.showToast("No result")
      return false
    }
    return store.openUrlExternal(store.primary.url || "", store.primary.slug || "")
  }

  function copyPrimaryLink() {
    if (!store.primary)
      return store.copyText("")
    return store.copyText(store.primary.url || "")
  }

  function toggleHero() {
    if (!store.primary) return
    var slug = String(store.primary.slug || "")
    if (!store.articleBody || store.articleSlug !== slug) {
      store.previewPrimary()
      return
    }
    store.articleExpanded = !store.articleExpanded
    store.heroExpanded = store.articleExpanded
  }

  function applyPayload(obj, source) {
    if (!obj || typeof obj !== "object") return false
    if (obj.cleared === true) return false
    var payload = obj.payload !== undefined ? obj.payload : obj
    if (!payload || typeof payload !== "object") return false

    // FW-08: failed lookup must not wipe prior good results
    if (payload.ok === false) {
      store.lastError = payload.error ? String(payload.error) : "Search failed"
      store.lastRetryable = !!(payload.retryable || payload.transient)
      store.dataSource = source || store.dataSource
      return false
    }

    var list = payload.results
    if (!Array.isArray(list)) list = []
    store.lastPayload = payload
    store.results = list
    store.lastQuery = obj.query || payload.query || store.lastQuery || ""
    if (store.lastQuery.length && !String(store.queryInput || "").trim().length)
      store.queryInput = store.lastQuery

    // FW-12: trust search.py primary/related when the key is present
    var q = store.lastQuery || payload.query || ""
    if (Object.prototype.hasOwnProperty.call(payload, "primary")) {
      store.primary = (payload.primary && typeof payload.primary === "object")
        ? payload.primary : null
      if (Array.isArray(payload.related)) {
        store.related = payload.related
      } else if (store.primary) {
        var pSlug = String(store.primary.slug || "")
        var pTitle = String(store.primary.title || "")
        store.related = list.filter(function(r) {
          if (!r) return true
          if (pSlug && String(r.slug || "") === pSlug) return false
          if (!pSlug && pTitle && String(r.title || "") === pTitle) return false
          return true
        })
      } else {
        store.related = list.slice()
      }
    } else {
      store.applyPrimarySplit(list, q)
    }

    store.lookedUpAt = obj.lookedUpAt || store.lookedUpAt || ""
    store.dataSource = source || "search"
    store.lastError = payload.error ? String(payload.error) : ""
    store.lastRetryable = false
    store.selectedIndex = list.length ? 0 : -1
    store.articleBody = ""
    store.articleSlug = ""
    store.articleError = ""
    store.articleExpanded = false
    store.heroExpanded = false
    if (!store.primary)
      store.articleExpanded = false
    return true
  }

  function onSearchFinished(exitCode) {
    store.loading = false
    var raw = store.searchBuf || ""
    store.searchBuf = ""
    if (!raw.length) {
      store.lastError = "search produced no output (exit " + exitCode + ")"
      store.lastRetryable = false
      store.showToast(store.lastError)
      return
    }
    var lines = raw.split("\n")
    var blob = ""
    for (var i = lines.length - 1; i >= 0; i--) {
      var line = String(lines[i] || "").trim()
      if (line.charAt(0) === "{") {
        blob = line
        break
      }
    }
    if (!blob.length)
      blob = raw.trim()
    try {
      var obj = JSON.parse(blob)
      store.lastQuery = String(store.queryInput || "").trim()
      if (obj.ok) {
        store.lookedUpAt = new Date().toISOString()
        store.applyPayload({ payload: obj, query: store.lastQuery, lookedUpAt: store.lookedUpAt }, "search")
        var n = (obj.results || []).length
        store.showToast(n ? (n + " result" + (n === 1 ? "" : "s")) : "No matches")
        store.persistToDisk(store.buildCacheObject(obj, store.lookedUpAt))
      } else {
        // FW-08: keep prior results/primary/related; error + toast only
        store.lastError = String(obj.error || "Search failed")
        store.lastRetryable = !!(obj.retryable || obj.transient)
        store.showToast(store.lastError)
      }
    } catch (e) {
      store.lastError = "search JSON parse failed"
      store.lastRetryable = false
      store.showToast(store.lastError)
    }
  }

  function clearResult() {
    store.results = []
    store.primary = null
    store.related = []
    store.clearArticle()
    store.lastPayload = null
    store.lastError = ""
    store.lastRetryable = false
    store.lookedUpAt = ""
    store.dataSource = "none"
    store.selectedIndex = -1
    store.lastQuery = ""
    store.persistClear()
    store.showToast("Cleared")
  }

  function loadDiskText(text) {
    try {
      var obj = JSON.parse(text || "{}")
      if (obj.cleared === true) return false
      return store.applyPayload(obj, "disk")
    } catch (e) {
      return false
    }
  }

  function bootstrap() {
    cacheFile.reload()
  }

  function onCacheLoaded(text) {
    if (text && text.length > 2)
      store.loadDiskText(text)
  }

  Component.onCompleted: {
    store.bootstrap()
  }

  Timer {
    id: toastClear
    interval: 1800
    repeat: false
    onTriggered: store.toastText = ""
  }

  FileView {
    id: cacheFile
    path: store.cachePath
    watchChanges: false
    printErrors: false
    onLoaded: store.onCacheLoaded(text())
    onLoadFailed: { /* first run — no cache yet */ }
  }

  Process {
    id: copyProc
    running: false
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0)
        store.showToast("Copied")
      else if (exitCode === 127)
        store.showToast("No clipboard tool")
      else
        store.showToast("Copy failed")
    }
  }

  Process {
    id: openUrlProc
    running: false
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0)
        store.showToast("Opened")
      else
        store.showToast("Open failed")
    }
  }

  Process {
    id: pageProc
    running: false
    stdout: SplitParser {
      onRead: function(line) { store.articleBuf += line + "\n" }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var t = String(line || "")
        if (t.length)
          store.articleError = t
      }
    }
    onExited: function(exitCode, exitStatus) {
      store.onPageFinished(exitCode)
    }
  }

  Process {
    id: searchProc
    running: false
    stdout: SplitParser {
      onRead: function(line) { store.searchBuf += line + "\n" }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var s = String(line || "")
        if (s.length)
          store.lastError = s
      }
    }
    onExited: function(exitCode, exitStatus) {
      store.onSearchFinished(exitCode)
    }
  }
}
