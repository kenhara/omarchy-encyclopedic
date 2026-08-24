#!/usr/bin/env python3
"""Encyclopedic — public Grokipedia full-text search (no auth).

CLI for Omarchy bar-widget (search + --page preview).
User-Agent version is read from manifest.json (fallback 0.1.5).

Unofficial. Not affiliated with xAI / Grokipedia.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

SEARCH_URL = "https://grokipedia.com/api/full-text-search"
PAGE_PREVIEW_URL = "https://grokipedia.com/api/page-preview"
PAGE_BASE = "https://grokipedia.com/page"
PLUGIN_ID = "kenhara.encyclopedic"
MAX_ARTICLE_CHARS = 60000
MAX_REMOTE_BYTES = 5 * 1024 * 1024
MAX_CACHE_BYTES = 2 * 1024 * 1024
MAX_RESPONSE_BYTES = 1 * 1024 * 1024


def read_manifest_version() -> str:
    try:
        manifest = Path(__file__).resolve().parent.parent / "manifest.json"
        data = json.loads(manifest.read_text(encoding="utf-8"))
        ver = str(data.get("version") or "").strip()
        if ver:
            return ver
    except Exception:
        pass
    return "0.1.6"


VERSION = read_manifest_version()
USER_AGENT = f"Encyclopedic/{VERSION} (Omarchy unofficial; {PLUGIN_ID})"


def emit(obj: dict[str, Any], exit_code: int = 0) -> None:
    line = json.dumps(obj, ensure_ascii=False)
    if len(line.encode("utf-8")) > MAX_RESPONSE_BYTES:
        line = json.dumps({"ok": False, "error": "helper response too large", "retryable": False})
    sys.stdout.write(line + "\n")
    sys.stdout.flush()
    raise SystemExit(exit_code)


def strip_simple_html(text: str) -> str:
    """Unescape first so encoded tags become strip-able, then strip, then
    optional second unescape, then whitespace collapse.

    Repro: strip_simple_html('&lt;img src=x&gt;') must NOT contain live <img>.
    """
    if not text:
        return ""
    s = html.unescape(str(text))
    # Drop simple highlight / markup tags; keep inner text.
    s = re.sub(r"</?(?:em|b|i|strong|mark|span|a|br|p)(?:\s[^>]*)?>", "", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def strip_article_markdown(text: str, max_chars: int = MAX_ARTICLE_CHARS) -> str:
    """Plain-text article body for in-panel preview. Keep paragraphs."""
    if not text:
        return ""
    s = html.unescape(str(text))
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = re.sub(r"!\[([^\]]*)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"\[\]\([^)]*\)", "", s)
    s = re.sub(r"^#{1,6}\s*", "", s, flags=re.M)
    s = re.sub(r"^[-*]{3,}\s*$", "", s, flags=re.M)
    s = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)
    s = re.sub(r"__([^_]+)__", r"\1", s)
    s = re.sub(r"(?<!\w)\*([^*]+)\*(?!\w)", r"\1", s)
    s = re.sub(r"(?<!\w)_([^_]+)_(?!\w)", r"\1", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    s = re.sub(r"</?(?:em|b|i|strong|mark|span|a|br|p|div|h[1-6])(?:\s[^>]*)?>", " ", s, flags=re.I)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t]+\n", "\n", s)
    s = re.sub(r"\n{3,}", "\n\n", s)
    s = re.sub(r"[ \t]{2,}", " ", s)
    s = s.strip()
    if max_chars > 0 and len(s) > max_chars:
        s = s[:max_chars].rstrip() + "\n\n…"
    return s


def article_url(slug: str) -> str:
    slug = str(slug or "").strip().lstrip("/")
    return f"{PAGE_BASE}/{urllib.parse.quote(slug, safe='_-')}"


def sanitize_https_url(url: str, slug: str = "") -> str:
    """Only allow https:; prefer grokipedia article URLs; else construct."""
    u = str(url or "").strip()
    if u.lower().startswith("https://"):
        return u
    if slug:
        return article_url(slug)
    return ""


RETRYABLE_HTTP = frozenset({502, 503, 504})
RETRY_BACKOFF_S = (0.5, 1.5)  # after attempt 1 and 2; 3 tries total
USER_TRANSIENT = "Grokipedia is temporarily unavailable — try again"


def http_get_json(url: str, timeout: float = 30.0) -> tuple[int, Any, str]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
    }
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw_bytes = resp.read(MAX_REMOTE_BYTES + 1)
            if len(raw_bytes) > MAX_REMOTE_BYTES:
                return 0, {"error": "response too large"}, "response too large"
            raw = raw_bytes.decode("utf-8", errors="replace")
            code = getattr(resp, "status", 200) or 200
            try:
                return code, json.loads(raw) if raw else {}, raw
            except json.JSONDecodeError:
                return code, {"_raw": raw}, raw
    except urllib.error.HTTPError as e:
        raw_bytes = e.read(MAX_REMOTE_BYTES + 1) if e.fp else b""
        if len(raw_bytes) > MAX_REMOTE_BYTES:
            return 0, {"error": "response too large"}, "response too large"
        raw = raw_bytes.decode("utf-8", errors="replace")
        try:
            parsed = json.loads(raw) if raw else {"error": str(e.reason)}
        except json.JSONDecodeError:
            parsed = {"_raw": raw or str(e.reason)}
        return int(e.code), parsed, raw
    except Exception as e:
        return 0, {"error": str(e)}, str(e)


def is_retryable_code(code: int) -> bool:
    return code == 0 or code in RETRYABLE_HTTP


def http_get_json_with_retries(
    url: str, timeout: float = 30.0
) -> tuple[int, Any, str, int]:
    """GET with bounded retries on network/timeout and 502/503/504.

    Returns (code, payload, raw, attempts). Does not retry 4xx.
    """
    attempts = 0
    code, payload, raw = 0, {}, ""
    max_tries = 1 + len(RETRY_BACKOFF_S)
    while attempts < max_tries:
        attempts += 1
        code, payload, raw = http_get_json(url, timeout=timeout)
        if not is_retryable_code(code):
            return code, payload, raw, attempts
        if attempts >= max_tries:
            break
        time.sleep(RETRY_BACKOFF_S[attempts - 1])
    return code, payload, raw, attempts


def _raw_detail(payload: Any, raw: str, fallback: str = "") -> str:
    """Debug detail for errorDetail — never the primary user-facing error."""
    if isinstance(payload, dict):
        for k in ("message", "error", "detail"):
            v = payload.get(k)
            if v and not isinstance(v, (dict, list)):
                return str(v)[:500]
        if payload.get("_raw"):
            return str(payload["_raw"])[:500]
    if raw and raw.strip():
        # Truncate HTML/Cloudflare prose
        return raw.strip()[:500]
    return fallback


def fail_result(
    *,
    query: str,
    limit: int,
    error: str,
    retryable: bool = False,
    error_detail: str | None = None,
) -> dict[str, Any]:
    out: dict[str, Any] = {
        "ok": False,
        "results": [],
        "primary": None,
        "related": [],
        "error": error,
        "retryable": bool(retryable),
        "query": query,
        "limit": limit,
    }
    if error_detail:
        out["errorDetail"] = error_detail
    return out


def normalize_item(item: Any) -> dict[str, Any] | None:
    if not isinstance(item, dict):
        return None
    slug = item.get("slug") or item.get("id") or ""
    title = item.get("title") or slug or ""
    snippet = item.get("snippet") or item.get("scrollAnchorText") or ""
    if not slug and not title:
        return None
    slug = str(slug).strip()
    title = strip_simple_html(str(title))
    snippet = strip_simple_html(str(snippet))
    raw_url = item.get("url") or ""
    url = sanitize_https_url(str(raw_url), slug)
    return {
        "title": title,
        "slug": slug,
        "url": url,
        "snippet": snippet,
    }


def norm_key(s: str) -> str:
    return re.sub(r"\s+", " ", str(s or "").strip().lower())


def slug_key(s: str) -> str:
    # Compare slug forms: spaces/underscores interchangeable
    return norm_key(s).replace(" ", "_")


def split_primary_related(
    results: list[dict[str, Any]], query: str
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """Pick direct match: exact title (CI) preferred, else exact slug (CI).

    No fake primary when nothing equals the query.
    """
    if not results:
        return None, []
    q = norm_key(query)
    q_slug = slug_key(query)
    if not q:
        return None, list(results)

    title_hit: dict[str, Any] | None = None
    slug_hit: dict[str, Any] | None = None
    for r in results:
        if not isinstance(r, dict):
            continue
        title = norm_key(r.get("title") or "")
        slug = slug_key(r.get("slug") or "")
        if title_hit is None and title and title == q:
            title_hit = r
        if slug_hit is None and slug and (slug == q_slug or slug == q):
            slug_hit = r
        if title_hit is not None:
            break

    primary = title_hit or slug_hit
    if primary is None:
        return None, list(results)

    related = [r for r in results if r is not primary]
    return primary, related


def search(query: str, limit: int) -> dict[str, Any]:
    q = str(query or "").strip()
    if not q:
        return fail_result(
            query="", limit=limit, error="empty query", retryable=False
        )
    limit = max(1, min(int(limit or 8), 20))
    params = urllib.parse.urlencode({"query": q, "limit": str(limit)})
    url = f"{SEARCH_URL}?{params}"
    code, payload, raw, _attempts = http_get_json_with_retries(url)

    if code == 0:
        detail = _raw_detail(
            payload,
            raw,
            fallback=str(payload.get("error") if isinstance(payload, dict) else payload),
        )
        return fail_result(
            query=q,
            limit=limit,
            error=USER_TRANSIENT,
            retryable=True,
            error_detail=detail or "network/timeout",
        )

    if code >= 400:
        detail = _raw_detail(payload, raw, fallback=f"HTTP {code}")
        if is_retryable_code(code):
            return fail_result(
                query=q,
                limit=limit,
                error=USER_TRANSIENT,
                retryable=True,
                error_detail=detail or f"HTTP {code}",
            )
        # Permanent (4xx and other non-retryable)
        msg = f"HTTP {code}"
        if isinstance(payload, dict):
            for k in ("message", "error", "detail"):
                v = payload.get(k)
                if v and not isinstance(v, (dict, list)):
                    # Prefer short structured messages; skip HTML blobs
                    s = str(v).strip()
                    if s and "<" not in s and len(s) < 200:
                        msg = f"HTTP {code}: {s}"
                        break
        return fail_result(
            query=q,
            limit=limit,
            error=msg,
            retryable=False,
            error_detail=detail if detail != msg else None,
        )

    items: list[Any] = []
    if isinstance(payload, dict):
        if isinstance(payload.get("results"), list):
            items = payload["results"]
        elif isinstance(payload.get("data"), list):
            items = payload["data"]
        elif isinstance(payload.get("hits"), list):
            items = payload["hits"]
    elif isinstance(payload, list):
        items = payload

    results: list[dict[str, Any]] = []
    for it in items[:limit]:
        norm = normalize_item(it)
        if norm:
            results.append(norm)

    primary, related = split_primary_related(results, q)
    return {
        "ok": True,
        "results": results,
        "primary": primary,
        "related": related,
        "error": None,
        "retryable": False,
        "query": q,
        "limit": limit,
        "totalCount": (
            payload.get("totalCount")
            if isinstance(payload, dict)
            else len(results)
        ),
    }


def fail_page(
    *,
    slug: str,
    error: str,
    retryable: bool = False,
    error_detail: str | None = None,
    found: bool = False,
) -> dict[str, Any]:
    out: dict[str, Any] = {
        "ok": False,
        "found": bool(found),
        "slug": slug,
        "title": "",
        "content": "",
        "description": "",
        "error": error,
        "retryable": bool(retryable),
    }
    if error_detail:
        out["errorDetail"] = error_detail
    return out


def fetch_page(slug: str) -> dict[str, Any]:
    """GET /api/page-preview?slug=… — full article body for in-panel Preview."""
    s = str(slug or "").strip().lstrip("/")
    if not s:
        return fail_page(slug="", error="empty slug", retryable=False)

    params = urllib.parse.urlencode({"slug": s})
    url = f"{PAGE_PREVIEW_URL}?{params}"
    code, payload, raw, _attempts = http_get_json_with_retries(url, timeout=45.0)

    if code == 0:
        detail = _raw_detail(
            payload,
            raw,
            fallback=str(payload.get("error") if isinstance(payload, dict) else payload),
        )
        return fail_page(
            slug=s,
            error=USER_TRANSIENT,
            retryable=True,
            error_detail=detail or "network/timeout",
        )

    if code >= 400:
        detail = _raw_detail(payload, raw, fallback=f"HTTP {code}")
        if is_retryable_code(code):
            return fail_page(
                slug=s,
                error=USER_TRANSIENT,
                retryable=True,
                error_detail=detail or f"HTTP {code}",
            )
        if code == 404:
            return fail_page(slug=s, error="Page not found", retryable=False, error_detail=detail)
        msg = f"HTTP {code}"
        if isinstance(payload, dict):
            for k in ("message", "error", "detail"):
                v = payload.get(k)
                if v and not isinstance(v, (dict, list)):
                    t = str(v).strip()
                    if t and "<" not in t and len(t) < 200:
                        msg = f"HTTP {code}: {t}"
                        break
        return fail_page(
            slug=s,
            error=msg,
            retryable=False,
            error_detail=detail if detail != msg else None,
        )

    if not isinstance(payload, dict):
        return fail_page(slug=s, error="unexpected page payload", retryable=False)

    if payload.get("found") is False:
        return fail_page(slug=s, error="Page not found", retryable=False)

    page = payload.get("page")
    if not isinstance(page, dict):
        page = payload if payload.get("content") or payload.get("title") else None
    if not isinstance(page, dict):
        return fail_page(slug=s, error="Page not found", retryable=False)

    title = strip_simple_html(str(page.get("title") or s))
    desc = strip_simple_html(str(page.get("description") or ""))
    raw_content = page.get("content") or page.get("text") or page.get("body") or ""
    body = strip_article_markdown(str(raw_content or desc or ""))
    out_slug = str(page.get("slug") or s).strip() or s
    return {
        "ok": True,
        "found": True,
        "slug": out_slug,
        "title": title,
        "content": body,
        "description": desc,
        "error": None,
        "retryable": False,
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="search.py",
        description="Encyclopedic — Grokipedia public full-text search (unofficial)",
    )
    p.add_argument("--query", "-q", default="", help="Search query")
    p.add_argument("--limit", "-n", type=int, default=8, help="Max results (1–20)")
    p.add_argument(
        "--page",
        default="",
        help="Fetch article body by slug (page-preview API)",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not call the network; emit structured dry-run JSON",
    )
    p.add_argument(
        "--load-cache",
        default="",
        help="Load and emit a bounded cache JSON file",
    )
    return p.parse_args(argv)


def load_cache(path: str) -> None:
    """Bounded cache read. Oversize rejects; decode/JSON errors are a no-op."""
    try:
        with open(path, "rb") as f:
            data = f.read(MAX_CACHE_BYTES + 1)
    except Exception:
        emit({"cleared": True})
    if len(data) > MAX_CACHE_BYTES:
        emit({"ok": False, "error": "cache too large"}, exit_code=1)
    try:
        obj = json.loads(data.decode("utf-8"))
    except Exception:
        emit({"cleared": True})
    if not isinstance(obj, dict):
        emit({"cleared": True})
    emit(obj)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    cache_path = str(args.load_cache or "").strip()
    if cache_path:
        load_cache(cache_path)

    q = str(args.query or "").strip()
    slug = str(args.page or "").strip()
    limit = max(1, min(int(args.limit or 8), 20))

    if slug:
        if args.dry_run:
            emit(
                {
                    "ok": False,
                    "found": False,
                    "slug": slug,
                    "title": "",
                    "content": "",
                    "description": "",
                    "error": "dry-run — no network call",
                    "retryable": False,
                },
                exit_code=2,
            )
        out = fetch_page(slug)
        emit(out, exit_code=0 if out.get("ok") else 1)

    if args.dry_run:
        emit(
            {
                "ok": False,
                "results": [],
                "primary": None,
                "related": [],
                "error": "dry-run — no network call",
                "retryable": False,
                "query": q,
                "limit": limit,
            },
            exit_code=2,
        )

    if not q:
        emit(
            {
                "ok": False,
                "results": [],
                "primary": None,
                "related": [],
                "error": "empty query",
                "retryable": False,
                "query": "",
                "limit": limit,
            },
            exit_code=2,
        )

    out = search(q, limit)
    emit(out, exit_code=0 if out.get("ok") else 1)


if __name__ == "__main__":
    main()
