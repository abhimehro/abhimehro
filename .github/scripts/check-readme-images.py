#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
import time
from pathlib import Path

USER_AGENT = "abhimehro-readme-image-health/1.0 (+https://github.com/abhimehro/abhimehro)"
CONNECT_TIMEOUT = 10
MAX_TIME = 45
MAX_ATTEMPTS = 3
MAX_BODY_SNIP = 180


def _build_img_url_re() -> re.Pattern[str]:
    dq = chr(34)
    sq = chr(39)
    bs = chr(92)
    md = (
        "!"
        + bs
        + "["
        + "[^"
        + bs
        + "]]*"
        + bs
        + "]"
        + bs
        + "("
        + "(https?://[^)"
        + bs
        + "s]+)"
        + bs
        + ")"
    )
    img = (
        "<img"
        + bs
        + "b[^>]*"
        + bs
        + "bsrc"
        + bs
        + "s*="
        + bs
        + "s*["
        + dq
        + sq
        + "](https?://[^"
        + dq
        + sq
        + "]+)["
        + dq
        + sq
        + "]"
    )
    image = (
        "<image"
        + bs
        + "b[^>]*"
        + bs
        + "b(?:href|src)"
        + bs
        + "s*="
        + bs
        + "s*["
        + dq
        + sq
        + "](https?://[^"
        + dq
        + sq
        + "]+)["
        + dq
        + sq
        + "]"
    )
    return re.compile("(?:" + md + "|" + img + "|" + image + ")", re.I)


IMG_URL_RE = _build_img_url_re()


def extract_urls(readme_text: str) -> list[str]:
    cleaned: list[str] = []
    seen: set[str] = set()
    for match in IMG_URL_RE.finditer(readme_text):
        url = next(g for g in match.groups() if g)
        url = url.strip().rstrip(").,;").split("#", 1)[0]
        if not url.lower().startswith(("http://", "https://")):
            continue
        if url in seen:
            continue
        seen.add(url)
        cleaned.append(url)
    return cleaned


def normalize_content_type(value: str) -> str:
    if not value:
        return ""
    return value.split(";", 1)[0].strip().lower()


def is_image_like(content_type: str, body_prefix: bytes) -> tuple[bool, str]:
    ct = normalize_content_type(content_type)
    lower_prefix = body_prefix[:512].lower()
    if ct.startswith("image/"):
        return True, "image/* content-type"
    if ct in {"text/xml", "application/xml", "application/xhtml+xml"}:
        return True, ct + " accepted as image-like"
    if b"<svg" in lower_prefix:
        label = ct if ct else "missing content-type"
        if ct in {"", "text/plain", "application/octet-stream"}:
            return True, label + " with SVG payload"
        if (ct.startswith("text/") or ct.startswith("application/")) and b"<html" not in lower_prefix:
            return True, ct + " with SVG payload"
    if b"<!doctype html" in lower_prefix or b"<html" in lower_prefix:
        return False, "HTML document returned instead of image"
    if not ct:
        return False, "missing content-type and body is not SVG"
    return False, "non-image content-type: " + ct


def curl_probe(url: str) -> tuple[int, str, str, bytes, str]:
    body_path = Path("/tmp") / ("rih-body-%s" % abs(hash(url)))
    write_fmt = "%{http_code}" + chr(9) + "%{url_effective}" + chr(9) + "%{content_type}"
    cmd = [
        "curl",
        "-sS",
        "-L",
        "--compressed",
        "-A",
        USER_AGENT,
        "--connect-timeout",
        str(CONNECT_TIMEOUT),
        "--max-time",
        str(MAX_TIME),
        "-o",
        str(body_path),
        "-w",
        write_fmt,
        url,
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        out = (proc.stdout or "").strip()
        writeout = out.splitlines()[-1] if out else ""
        parts = writeout.split(chr(9))
        while len(parts) < 3:
            parts.append("")
        status_s, final_url, content_type = parts[0], parts[1], parts[2]
        try:
            status = int(status_s)
        except ValueError:
            status = 0
        body = body_path.read_bytes()[:2048] if body_path.exists() else b""
        err = (proc.stderr or "").strip()
        return status, final_url or url, content_type, body, err
    finally:
        try:
            body_path.unlink(missing_ok=True)
        except Exception:
            pass


def probe(url: str) -> tuple[bool, list[str]]:
    details: list[str] = []
    for attempt in range(1, MAX_ATTEMPTS + 1):
        status, final_url, content_type, body_prefix, err = curl_probe(url)
        ok, reason = is_image_like(content_type, body_prefix)
        if 200 <= status < 300 and ok:
            ct_label = content_type if content_type else "<none>"
            details = [
                "status=" + str(status),
                "content-type=" + ct_label,
                "(" + reason + ")",
            ]
            if final_url != url:
                details.append("final=" + final_url)
            return True, details

        snip = re.sub(
            chr(92) + "s+",
            " ",
            body_prefix[:MAX_BODY_SNIP].decode("utf-8", "replace"),
        ).strip()
        ct_label = content_type if content_type else "<none>"
        details = [
            "attempts=%d/%d" % (attempt, MAX_ATTEMPTS),
            "status=" + str(status),
            "content-type=" + ct_label,
            "reason=" + reason,
        ]
        if final_url != url:
            details.append("final=" + final_url)
        if err:
            details.append("curl_error=" + err.replace(chr(10), " "))
        if snip:
            details.append("body_snip=" + snip)
        if not (200 <= status < 300):
            details.append("note=expected HTTP 2xx")

        retryable = status in {0, 408, 425, 429} or 500 <= status <= 599
        if attempt < MAX_ATTEMPTS and retryable:
            time.sleep(attempt * 2)
            continue
        return False, details
    return False, details or ["reason=unknown failure"]


def main(argv: list[str]) -> int:
    readme_path = Path(argv[1] if len(argv) > 1 else "README.md")
    if not readme_path.is_file():
        print("::error::README not found: " + str(readme_path))
        return 1

    urls = extract_urls(readme_path.read_text(encoding="utf-8", errors="replace"))
    if not urls:
        print("::error::No remote image URLs found in " + str(readme_path))
        return 1

    print("Found %d unique remote image URL(s)." % len(urls))
    print()

    failures = 0
    passes = 0
    for url in urls:
        ok, details = probe(url)
        if ok:
            passes += 1
            print("PASS  " + url)
        else:
            failures += 1
            print("FAIL  " + url)
            print(
                "::error title=Broken README image::"
                + url
                + " -> "
                + ", ".join(details)
            )
        for line in details:
            print("      " + line)
        print()

    print("-" * 40)
    print("Summary: %d passed, %d failed, %d total" % (passes, failures, len(urls)))
    if failures:
        print(
            "::error::README image health check failed for %d URL(s). "
            "Open the job log for URL-level detail." % failures
        )
        return 1

    print("All remote README images look healthy.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
