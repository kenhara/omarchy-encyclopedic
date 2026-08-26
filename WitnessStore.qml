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
  property string cacheBuf: ""
  readonly property int maxHelperOutput: 2 * 1024 * 1024
  property bool searchOverflow: false
  property bool articleOverflow: false
  property bool cacheOverflow: false
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
  readonly property var helperEnv: ({
    "PYTHONDONTWRITEBYTECODE": "1",
    "PATH": "/usr/bin:/bin"
  })
  readonly property int maxTitleChars: 300
  readonly property int maxSnippetChars: 4000
  readonly property int maxSlugChars: 200
  readonly property int maxUrlChars: 500
  readonly property int maxErrorChars: 400
  property string pendingCacheBody: ""

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
    store.toastText = store.neutralizeError(msg, "")
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

  function capField(text, limit) {
    var s = String(text || "")
    var n = parseInt(limit, 10)
    if (!isFinite(n) || n <= 0) return s
    if (s.length > n) return s.substring(0, n)
    return s
  }

  function unescapeHtmlOnce(text) {
    var s = String(text || "")
    return s.replace(/&(#x[0-9a-fA-F]+|#\d+|lt|gt|amp|quot|apos);/g, function(m, ent) {
      if (ent === "lt") return "<"
      if (ent === "gt") return ">"
      if (ent === "amp") return "&"
      if (ent === "quot") return "\""
      if (ent === "apos") return "'"
      if (ent.charAt(0) === "#") {
        var code = ent.charAt(1).toLowerCase() === "x"
          ? parseInt(ent.substring(2), 16)
          : parseInt(ent.substring(1), 10)
        if (isFinite(code) && code >= 0 && code <= 0x10ffff)
          return String.fromCodePoint(code)
      }
      return m
    })
  }

  function stripSimpleHtml(text) {
    var s = store.unescapeHtmlOnce(String(text || ""))
    s = s.replace(/<[^>]+>/g, "")
    s = s.replace(/!\[[^\]]*\]\([^)]*\)/g, "")
    s = s.replace(/\s+/g, " ").trim()
    return s
  }

  function articleUrlFromSlug(slug) {
    var s = String(slug || "").trim().replace(/^\//, "")
    if (!s.length) return ""
    return "https://grokipedia.com/page/" + encodeURIComponent(s).replace(/%2F/g, "/")
  }

  function isAllowedGrokipediaHttps(url) {
    var u = String(url || "").trim()
    if (u.length < 8) return false
    if (u.substring(0, 8).toLowerCase() !== "https://") return false
    var rest = u.substring(8)
    var cut = rest.length
    var seps = ["/", "?", "#"]
    var i
    for (i = 0; i < seps.length; i++) {
      var p = rest.indexOf(seps[i])
      if (p >= 0 && p < cut) cut = p
    }
    var authority = rest.substring(0, cut)
    if (authority.indexOf("@") >= 0)
      return false
    var host = authority
    if (host.charAt(0) === "[")
      return false
    var colon = host.lastIndexOf(":")
    if (colon >= 0) host = host.substring(0, colon)
    host = host.toLowerCase()
    if (host.length && host.charAt(host.length - 1) === ".")
      host = host.substring(0, host.length - 1)
    return host === "grokipedia.com" || host === "www.grokipedia.com"
  }

  function sanitizeOpenUrl(url, slug) {
    var u = String(url || "").trim()
    if (store.isAllowedGrokipediaHttps(u) && u.length <= store.maxUrlChars)
      return u
    var built = store.articleUrlFromSlug(slug)
    if (built.length && store.isAllowedGrokipediaHttps(built) && built.length <= store.maxUrlChars)
      return built
    return ""
  }

  function neutralizeItem(item) {
    if (!item || typeof item !== "object") return null
    var slug = store.capField(store.stripSimpleHtml(String(item.slug || item.id || "").trim()), store.maxSlugChars)
    var title = store.capField(store.stripSimpleHtml(item.title || slug || ""), store.maxTitleChars)
    var snippet = store.capField(store.stripSimpleHtml(item.snippet || item.scrollAnchorText || ""), store.maxSnippetChars)
    if (!slug.length && !title.length) return null
    var url = store.sanitizeOpenUrl(item.url || "", slug)
    url = store.capField(url, store.maxUrlChars)
    return { title: title, slug: slug, url: url, snippet: snippet }
  }

  function neutralizeList(list) {
    var src = Array.isArray(list) ? list : []
    var out = []
    var i
    for (i = 0; i < src.length; i++) {
      var n = store.neutralizeItem(src[i])
      if (n) out.push(n)
    }
    return out
  }

  function neutralizeError(msg, fallback) {
    var s = store.stripSimpleHtml(String(msg || fallback || ""))
    return store.capField(s, store.maxErrorChars)
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
    store.articleTitle = store.capField(store.stripSimpleHtml(String(title || "")), store.maxTitleChars)
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
    store.articleOverflow = false
    pageProc.command = [
      "python3",
      "-B",
      store.searchPath,
      "--page",
      s
    ]
    pageProc.environment = store.helperEnv
    pageProc.running = true
    return true
  }

  function onPageFinished(exitCode) {
    var fetchSlug = store.articleFetchSlug
    var requested = store.articleRequestSlug
    store.articleBuf = store.articleBuf || ""
    if (!requested) {
      store.articleBuf = ""
      store.articleOverflow = false
      store.articleLoading = false
      return
    }
    if (requested && requested !== fetchSlug) {
      store.articleFetchSlug = requested
      store.articleBuf = ""
      store.articleOverflow = false
      store.articleLoading = true
      pageProc.command = [
        "python3",
        "-B",
        store.searchPath,
        "--page",
        requested
      ]
      pageProc.environment = store.helperEnv
      Qt.callLater(function() { pageProc.running = true })
      return
    }
    if (store.articleOverflow) {
      store.articleBuf = ""
      store.articleOverflow = false
      store.articleLoading = false
      store.articleError = store.neutralizeError("response too large")
      store.showToast(store.articleError)
      return
    }
    store.articleLoading = false
    var raw = store.articleBuf || ""
    store.articleBuf = ""
    if (!raw.length) {
      store.articleError = store.neutralizeError("article produced no output (exit " + exitCode + ")")
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
        store.articleSlug = store.capField(store.stripSimpleHtml(String(obj.slug || fetchSlug || "")), store.maxSlugChars)
        store.articleTitle = store.capField(store.stripSimpleHtml(String(obj.title || store.articleTitle || "")), store.maxTitleChars)
        store.articleBody = String(obj.content || "")
        store.articleError = ""
        store.articleExpanded = true
        store.heroExpanded = true
        if (!store.articleBody.length)
          store.showToast("No article text")
      } else {
        store.articleError = store.neutralizeError(obj.error, "Article failed")
        store.articleBody = ""
        store.showToast(store.articleError)
      }
    } catch (e) {
      store.articleError = store.neutralizeError("article JSON parse failed")
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

  function copySanitizedLink(url, slug) {
    var u = store.sanitizeOpenUrl(url, slug)
    if (!u.length) {
      store.showToast("Refused — https only")
      return false
    }
    return store.copyText(u)
  }

  function copyLink(index) {
    var i = (index === undefined || index === null) ? store.selectedIndex : parseInt(index, 10)
    if (!isFinite(i) || i < 0 || !store.results || i >= store.results.length)
      return store.copyText("")
    var r = store.results[i]
    return store.copySanitizedLink(r && r.url ? r.url : "", r && r.slug ? r.slug : "")
  }

  function lookUp() {
    if (store.loading && searchProc.running)
      return
    var q = String(store.queryInput || "").trim()
    if (!q.length) {
      store.lastError = store.neutralizeError("Enter something to look up")
      store.lastRetryable = false
      store.showToast(store.lastError)
      return
    }
    store.loading = true
    store.lastError = ""
    store.lastRetryable = false
    store.searchBuf = ""
    store.searchOverflow = false
    store.clearArticle()
    var lim = store.clampLimit(store.resultLimit)
    searchProc.command = [
      "python3",
      "-B",
      store.searchPath,
      "--query", q,
      "--limit", String(lim)
    ]
    searchProc.environment = store.helperEnv
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
    store.pendingCacheBody = JSON.stringify(obj || store.buildCacheObject(), null, 2) + "\n"
    store.flushCacheWrite()
  }

  function persistClear() {
    store.pendingCacheBody = JSON.stringify({ version: 1, cleared: true }, null, 2) + "\n"
    store.flushCacheWrite()
  }

  function flushCacheWrite() {
    if (cacheWriteProc.running)
      return
    var body = store.pendingCacheBody
    if (!body || !body.length)
      return
    store.pendingCacheBody = ""
    cacheWriteProc.command = [
      "python3",
      "-B",
      store.searchPath,
      "--write-cache",
      store.cachePath,
      "--cache-body",
      body
    ]
    cacheWriteProc.environment = store.helperEnv
    cacheWriteProc.running = true
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
    return store.copySanitizedLink(store.primary.url || "", store.primary.slug || "")
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
      store.lastError = store.neutralizeError(payload.error, "Search failed")
      store.lastRetryable = !!(payload.retryable || payload.transient)
      store.dataSource = source || store.dataSource
      return false
    }

    var list = store.neutralizeList(Array.isArray(payload.results) ? payload.results : [])
    payload.results = list
    store.lastQuery = obj.query || payload.query || store.lastQuery || ""
    if (store.lastQuery.length && !String(store.queryInput || "").trim().length)
      store.queryInput = store.lastQuery

    // FW-12: trust search.py primary/related when the key is present
    var q = store.lastQuery || payload.query || ""
    if (Object.prototype.hasOwnProperty.call(payload, "primary")) {
      store.primary = store.neutralizeItem(payload.primary)
      if (Array.isArray(payload.related)) {
        store.related = store.neutralizeList(payload.related)
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

    payload.primary = store.primary
    payload.related = store.related
    if (payload.error)
      payload.error = store.neutralizeError(payload.error, "")
    store.lastPayload = payload
    store.results = list
    store.lookedUpAt = obj.lookedUpAt || store.lookedUpAt || ""
    store.dataSource = source || "search"
    store.lastError = payload.error ? store.neutralizeError(payload.error, "") : ""
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
    if (store.searchOverflow) {
      store.searchBuf = ""
      store.searchOverflow = false
      store.lastError = store.neutralizeError("response too large")
      store.lastRetryable = false
      store.showToast(store.lastError)
      return
    }
    var raw = store.searchBuf || ""
    store.searchBuf = ""
    if (!raw.length) {
      store.lastError = store.neutralizeError("search produced no output (exit " + exitCode + ")")
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
        store.lastError = store.neutralizeError(obj.error, "Search failed")
        store.lastRetryable = !!(obj.retryable || obj.transient)
        store.showToast(store.lastError)
      }
    } catch (e) {
      store.lastError = store.neutralizeError("search JSON parse failed")
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
    store.cacheBuf = ""
    store.cacheOverflow = false
    cacheProc.command = [
      "python3",
      "-B",
      store.searchPath,
      "--load-cache",
      store.cachePath
    ]
    cacheProc.environment = store.helperEnv
    cacheProc.running = true
  }

  function onCacheFinished(exitCode) {
    if (store.cacheOverflow) {
      store.cacheBuf = ""
      store.cacheOverflow = false
      store.lastError = store.neutralizeError("response too large")
      store.showToast(store.lastError)
      return
    }
    var raw = store.cacheBuf || ""
    store.cacheBuf = ""
    if (!raw.length)
      return
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
    if (blob.length)
      store.loadDiskText(blob)
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

  Process {
    id: cacheWriteProc
    running: false
    environment: ({
      "PYTHONDONTWRITEBYTECODE": "1",
      "PATH": "/usr/bin:/bin"
    })
    onExited: function(exitCode, exitStatus) {
      if (store.pendingCacheBody && store.pendingCacheBody.length)
        store.flushCacheWrite()
    }
  }

  Process {
    id: copyProc
    running: false
    environment: ({
      "PATH": "/usr/bin:/bin"
    })
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
    environment: ({
      "PATH": "/usr/bin:/bin"
    })
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
    environment: ({
      "PYTHONDONTWRITEBYTECODE": "1",
      "PATH": "/usr/bin:/bin"
    })
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(line) {
        if (store.articleOverflow) return
        if (store.articleBuf.length + line.length + 1 > store.maxHelperOutput) {
          store.articleOverflow = true
          pageProc.running = false
          return
        }
        store.articleBuf += line
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var t = String(line || "")
        if (t.length)
          store.articleError = store.neutralizeError(t)
      }
    }
    onExited: function(exitCode, exitStatus) {
      store.onPageFinished(exitCode)
    }
  }

  Process {
    id: searchProc
    running: false
    environment: ({
      "PYTHONDONTWRITEBYTECODE": "1",
      "PATH": "/usr/bin:/bin"
    })
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(line) {
        if (store.searchOverflow) return
        if (store.searchBuf.length + line.length + 1 > store.maxHelperOutput) {
          store.searchOverflow = true
          searchProc.running = false
          return
        }
        store.searchBuf += line
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        var s = String(line || "")
        if (s.length)
          store.lastError = store.neutralizeError(s)
      }
    }
    onExited: function(exitCode, exitStatus) {
      store.onSearchFinished(exitCode)
    }
  }

  Process {
    id: cacheProc
    running: false
    environment: ({
      "PYTHONDONTWRITEBYTECODE": "1",
      "PATH": "/usr/bin:/bin"
    })
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(line) {
        if (store.cacheOverflow) return
        if (store.cacheBuf.length + line.length + 1 > store.maxHelperOutput) {
          store.cacheOverflow = true
          cacheProc.running = false
          return
        }
        store.cacheBuf += line
      }
    }
    onExited: function(exitCode, exitStatus) {
      store.onCacheFinished(exitCode)
    }
  }
}
