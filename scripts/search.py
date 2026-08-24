#!/usr/bin/env python3
"""Encyclopedic — public Grokipedia full-text search (no auth).

CLI for Omarchy bar-widget.
User-Agent version is read from manifest.json (fallback 0.1.5).

Unofficial. Not affiliated with xAI / Grokipedia.
"""
from __future__ import annotations

import argparse
import html
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

SEARCH_URL = "https://grokipedia.com/api/full-text-search"
PAGE_BASE = "https://grokipedia.com/page"
PLUGIN_ID = "kenhara.encyclopedic"


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
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
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


def http_get_json(url: str, timeout: float = 30.0) -> tuple[int, Any, str]:
    headers = {
        "User-Agent": USER_AGENT,
        "Accept": "application/json",
    }
    req = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            code = getattr(resp, "status", 200) or 200
            try:
                return code, json.loads(raw) if raw else {}, raw
            except json.JSONDecodeError:
                return code, {"_raw": raw}, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", errors="replace") if e.fp else ""
        try:
            parsed = json.loads(raw) if raw else {"error": str(e.reason)}
        except json.JSONDecodeError:
            parsed = {"_raw": raw or str(e.reason)}
        return int(e.code), parsed, raw
    except Exception as e:
        return 0, {"error": str(e)}, str(e)


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
        return {
            "ok": False,
            "results": [],
            "primary": None,
            "related": [],
            "error": "empty query",
            "query": "",
            "limit": limit,
        }
    limit = max(1, min(int(limit or 8), 20))
    params = urllib.parse.urlencode({"query": q, "limit": str(limit)})
    url = f"{SEARCH_URL}?{params}"
    code, payload, _raw = http_get_json(url)
    if code == 0:
        return {
            "ok": False,
            "results": [],
            "primary": None,
            "related": [],
            "error": f"network error: {payload.get('error') if isinstance(payload, dict) else payload}",
            "query": q,
            "limit": limit,
        }
    if code >= 400:
        msg = f"HTTP {code}"
        if isinstance(payload, dict):
            for k in ("message", "error", "detail"):
                if payload.get(k):
                    msg = f"HTTP {code}: {payload[k]}"
                    break
        return {
            "ok": False,
            "results": [],
            "primary": None,
            "related": [],
            "error": msg,
            "query": q,
            "limit": limit,
        }

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
        "query": q,
        "limit": limit,
        "totalCount": (
            payload.get("totalCount")
            if isinstance(payload, dict)
            else len(results)
        ),
    }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="search.py",
        description="Encyclopedic — Grokipedia public full-text search (unofficial)",
    )
    p.add_argument("--query", "-q", default="", help="Search query")
    p.add_argument("--limit", "-n", type=int, default=8, help="Max results (1–20)")
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Do not call the network; emit structured dry-run JSON",
    )
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    q = str(args.query or "").strip()
    limit = max(1, min(int(args.limit or 8), 20))

    if args.dry_run:
        emit(
            {
                "ok": False,
                "results": [],
                "primary": None,
                "related": [],
                "error": "dry-run — no network call",
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
                "query": "",
                "limit": limit,
            },
            exit_code=2,
        )

    out = search(q, limit)
    emit(out, exit_code=0 if out.get("ok") else 1)


if __name__ == "__main__":
    main()
