import QtQuick
import Quickshell
import Quickshell.Io

// Fair Witness — runs scripts/search.py via Process; parses JSON stdout.
// Public Grokipedia search only. No API keys.
// Caches last successful search to ~/.cache/fair-witness/last.json
QtObject {
  id: store

  property int resultLimit: 8
  property bool panelOpen: false

  property string queryInput: ""
  property bool loading: false
  property string lastError: ""
  property string toastText: ""
  property var results: []          // [{title,slug,url,snippet}, ...]
  property var primary: null        // direct title/slug match, or null
  property var related: []          // results without primary (or all if no primary)
  property bool heroExpanded: false
  property int selectedIndex: -1
  property string searchBuf: ""
  property string lookedUpAt: ""
  property string dataSource: "none"  // disk | search | none
  property string lastQuery: ""
  property var lastPayload: null    // full JSON from search.py

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/fair-witness"
  readonly property string cachePath: cacheDir + "/last.json"
  readonly property string pluginDir: String(Qt.resolvedUrl("."))
    .replace(/^file:\/\//, "")
    .replace(/\/$/, "")
  readonly property string searchPath: pluginDir + "/scripts/search.py"

  readonly property string barGlyph: "●"
  readonly property string barLabel: store.barGlyph + " FW"
  readonly property string lastUpdatedText: formatUpdated(store.lookedUpAt)

  readonly property bool hasResults: store.results && store.results.length > 0
  readonly property bool hasPrimary: !!(store.primary && typeof store.primary === "object")

  readonly property var selectedResult: {
    if (store.selectedIndex < 0 || !store.results || store.selectedIndex >= store.results.length)
      return null
    return store.results[store.selectedIndex]
  }

  signal dataChanged()

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
    store.dataChanged()
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
      if (typeof Quickshell !== "undefined" && Quickshell.clipboard) {
        Quickshell.clipboard.text = t
        store.showToast("Copied")
        return true
      }
    } catch (e) {}
    copyProc.command = [
      "bash", "-lc",
      "printf '%s' \"$1\" | (command -v wl-copy >/dev/null && wl-copy || command -v xclip >/dev/null && xclip -selection clipboard || command -v xsel >/dev/null && xsel --clipboard --input || cat >/dev/null)",
      "fw-copy", t
    ]
    copyProc.running = true
    store.showToast("Copied")
    return true
  }

  function openUrlExternal(url) {
    var u = String(url || "").trim()
    if (!u.length) {
      store.showToast("No URL")
      return false
    }
    try {
      Qt.openUrlExternally(u)
      store.showToast("Opened")
      return true
    } catch (e) {
      openUrlProc.command = ["xdg-open", u]
      openUrlProc.running = true
      store.showToast("Opened")
      return true
    }
  }

  function selectResult(index) {
    var i = parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length) {
      store.selectedIndex = -1
    } else {
      store.selectedIndex = i
    }
    store.dataChanged()
  }

  function openResult(index) {
    var i = (index === undefined || index === null) ? store.selectedIndex : parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length) {
      store.showToast("No result")
      return false
    }
    store.selectedIndex = i
    var r = store.results[i]
    return store.openUrlExternal(r && r.url ? r.url : "")
  }

  function copyTitle(index) {
    var i = (index === undefined || index === null) ? store.selectedIndex : parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length)
      return store.copyText("")
    return store.copyText(store.results[i].title || "")
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
      store.showToast(store.lastError)
      store.dataChanged()
      return
    }
    store.loading = true
    store.lastError = ""
    store.searchBuf = ""
    store.selectedIndex = -1
    store.heroExpanded = false
    var lim = store.clampLimit(store.resultLimit)
    searchProc.command = [
      "python3",
      store.searchPath,
      "--query", q,
      "--limit", String(lim)
    ]
    searchProc.running = true
    store.dataChanged()
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
    var body = JSON.stringify(obj || store.buildCacheObject(), null, 2) + "\n"
    ensureCacheDir.running = true
    Qt.callLater(function() {
      try {
        cacheFile.setText(body)
      } catch (e) {}
    })
  }

  function persistClear() {
    ensureCacheDir.running = true
    Qt.callLater(function() {
      try {
        cacheFile.setText(JSON.stringify({ version: 1, cleared: true }, null, 2) + "\n")
      } catch (e) {}
    })
  }


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
      store.heroExpanded = false
  }

  function openPrimary() {
    if (!store.primary) {
      store.showToast("No result")
      return false
    }
    return store.openUrlExternal(store.primary.url || "")
  }

  function copyPrimaryTitle() {
    if (!store.primary)
      return store.copyText("")
    return store.copyText(store.primary.title || "")
  }

  function copyPrimaryLink() {
    if (!store.primary)
      return store.copyText("")
    return store.copyText(store.primary.url || "")
  }

  function toggleHero() {
    if (!store.primary) return
    store.heroExpanded = !store.heroExpanded
    store.dataChanged()
  }

  function applyPayload(obj, source) {
    if (!obj || typeof obj !== "object") return false
    if (obj.cleared === true) return false
    var payload = obj.payload !== undefined ? obj.payload : obj
    if (!payload || typeof payload !== "object") return false
    var list = payload.results
    if (!Array.isArray(list)) list = []
    store.lastPayload = payload
    store.results = list
    store.lastQuery = obj.query || payload.query || store.lastQuery || ""
    if (store.lastQuery.length && !String(store.queryInput || "").trim().length)
      store.queryInput = store.lastQuery
    // Prefer server-provided primary/related when present; else split client-side
    var q = store.lastQuery || payload.query || ""
    if (payload.primary !== undefined && payload.primary !== null
        && typeof payload.primary === "object") {
      store.primary = payload.primary
      if (Array.isArray(payload.related)) {
        store.related = payload.related
      } else {
        var pSlug = String(payload.primary.slug || "")
        var pTitle = String(payload.primary.title || "")
        store.related = list.filter(function(r) {
          if (!r) return true
          if (pSlug && String(r.slug || "") === pSlug) return false
          if (!pSlug && pTitle && String(r.title || "") === pTitle) return false
          return true
        })
      }
    } else {
      store.applyPrimarySplit(list, q)
    }
    store.lookedUpAt = obj.lookedUpAt || store.lookedUpAt || ""
    store.dataSource = source || "search"
    store.lastError = payload.error ? String(payload.error) : ""
    store.selectedIndex = list.length ? 0 : -1
    if (!store.primary)
      store.heroExpanded = false
    store.dataChanged()
    return true
  }

  function onSearchFinished(exitCode) {
    store.loading = false
    var raw = store.searchBuf || ""
    store.searchBuf = ""
    if (!raw.length) {
      store.lastError = "search produced no output (exit " + exitCode + ")"
      store.dataChanged()
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
      store.lookedUpAt = new Date().toISOString()
      store.applyPayload({ payload: obj, query: store.lastQuery, lookedUpAt: store.lookedUpAt }, "search")
      if (obj.ok) {
        var n = (obj.results || []).length
        store.showToast(n ? (n + " result" + (n === 1 ? "" : "s")) : "No matches")
        store.persistToDisk(store.buildCacheObject(obj, store.lookedUpAt))
      } else {
        store.showToast(store.lastError || "Search failed")
      }
      store.dataChanged()
    } catch (e) {
      store.lastError = "search JSON parse failed"
      store.dataChanged()
    }
  }

  function clearResult() {
    store.results = []
    store.primary = null
    store.related = []
    store.heroExpanded = false
    store.lastPayload = null
    store.lastError = ""
    store.lookedUpAt = ""
    store.dataSource = "none"
    store.selectedIndex = -1
    store.lastQuery = ""
    store.persistClear()
    store.showToast("Cleared")
    store.dataChanged()
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

  function handleSummonPayload(obj) {
    if (obj === undefined || obj === null || obj === "")
      return false
    if (typeof obj === "string") {
      var raw = String(obj).trim()
      if (!raw.length) return false
      try { obj = JSON.parse(raw) } catch (e) {
        // Treat bare string as query
        store.queryInput = raw
        Qt.callLater(function() { store.lookUp() })
        return true
      }
    }
    if (typeof obj !== "object") return false
    var acted = false
    if (obj.query || obj.q || obj.paste) {
      store.queryInput = String(obj.query || obj.q || obj.paste)
      acted = true
    }
    if (obj.limit !== undefined || obj.resultLimit !== undefined) {
      store.resultLimit = store.clampLimit(obj.limit !== undefined ? obj.limit : obj.resultLimit)
      acted = true
    }
    if (obj.clear === true || obj.clear === "true" || obj.clear === 1) {
      store.clearResult()
      acted = true
    }
    if (obj.lookup === true || obj.lookup === "true" || obj.lookup === 1
        || obj.search === true || obj.search === "true" || obj.witness === true) {
      Qt.callLater(function() { store.lookUp() })
      acted = true
    }
    return acted
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
    id: ensureCacheDir
    command: ["mkdir", "-p", store.cacheDir]
    running: false
  }

  Process {
    id: copyProc
    running: false
  }

  Process {
    id: openUrlProc
    running: false
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
