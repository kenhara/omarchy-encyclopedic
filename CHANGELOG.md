# Changelog

## 0.1.22

Defensive security follow-up.

- Open/Copy parse `https://` URLs and allow only `grokipedia.com` /
  `www.grokipedia.com`; otherwise build `https://grokipedia.com/page/{slug}`
  or refuse. `sanitizeOpenUrl` requires `https://` (not `https:`). `copyLink`
  uses the sanitizer.
- `http_get_json` refuses redirects whose final host is not grokipedia https.
  Host is checked before following and again via `geturl()` before the body
  is read. No auth headers are set or forwarded.
- `Text.PlainText` on `lastError`, `toastText`, `lastUpdatedText`, and other
  remote-derived Text. In-panel Preview stays PlainText (no WebView).
- Neutralize at model entry (`normalize_item` + `applyPayload`): strip tags
  without a reconstituting trailing unescape; drop leftover markdown images;
  cap title / snippet / slug / url / error. Re-applied on disk cache ingest.
- Cache write helper: `O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW` 0600 temp in the
  destination directory, fsync, `replace`. Directory `0700`. Fail closed if
  `O_NOFOLLOW` is missing. `O_CLOEXEC`. HC-05 cache reads unchanged.
- Pin `PATH=/usr/bin:/bin` on Processes. `python3 -B` stays.

## 0.1.21

- Cache read: `O_NOFOLLOW | O_NONBLOCK`, require a regular file (HC-05).

## 0.1.20

- Cap HTTP (5 MiB), cache (2 MiB), helper stdout (1 MiB), QML buffers (2 MiB).
