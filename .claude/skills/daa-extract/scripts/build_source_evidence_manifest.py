#!/usr/bin/env python3
"""Byg ét lukket, ikke-autoriserende source_evidence-manifest for én udgaveprofil.

Manifestets form er #153's lukkede gateway-kontrakt (apply_reimport_helpers.R,
validate_reimport_manifest): præcis manifest_content_sha256, source,
expected_counts og operations. Scriptet rører aldrig en database og
autoriserer aldrig en skrivning.

Ankring: segment.py:147 gemmer raw_text = norm(' '.join(lines)), så en post er
aldrig en litteral delstreng af pdftotext-outputtet. project_rendition bygger
derfor den samme normalisering over hele renditionen med et offset-kort tilbage
til den rå tekst, og posten skal findes som EKSAKT delstreng i den projektion.
Ingen fuzzy-match.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import segment
from reimport_profile import load_profile

SIDER_RE = re.compile(r"^(\d{1,6})(?:-(\d{1,6}))?$")
WHITESPACE_RE = re.compile(r"\s")


class ManifestError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ManifestError(code)


def _project_line(line: str, base: int) -> tuple[list[str], list[int]]:
    chars: list[str] = []
    offsets: list[int] = []
    pending_space = False
    for index, char in enumerate(line):
        if WHITESPACE_RE.match(char):
            if chars:
                pending_space = True
            continue
        if pending_space:
            chars.append(" ")
            offsets.append(base + index)
            pending_space = False
        chars.append(char)
        offsets.append(base + index)
    return chars, offsets


def project_rendition(text: str,
                      noise_rule: str = "anywhere") -> tuple[str, list[int]]:
    """Samme linjeregler som segment._segment_2018_20: PAGE-, blanke og
    NOISE-linjer springes over, øvrige linjer strippes og samles med ét
    mellemrum. `noise_rule` følger segmentprofilen; default er v1, som de
    eksisterende manifester er bygget med."""
    chars: list[str] = []
    offsets: list[int] = []
    cursor = 0
    lines = text.split("\n")
    for index, line in enumerate(lines):
        base = cursor
        cursor += len(line) + 1
        if segment.PAGE_RE.match(line) or not line.strip() \
                or segment.is_noise(lines, index, noise_rule):
            continue
        line_chars, line_offsets = _project_line(line, base)
        if not line_chars:
            continue
        if chars:
            chars.append(" ")
            offsets.append(base)
        chars.extend(line_chars)
        offsets.extend(line_offsets)
    return "".join(chars), offsets


def pages_from_sider(sider: Any) -> tuple[int, int]:
    if not isinstance(sider, str):
        _fail("SOURCE_EVIDENCE_PAGE_INVALID")
    match = SIDER_RE.match(sider)
    if match is None:
        _fail("SOURCE_EVIDENCE_PAGE_INVALID")
    page_from = int(match.group(1))
    page_to = int(match.group(2)) if match.group(2) else page_from
    if page_from < 1 or page_to < page_from:
        _fail("SOURCE_EVIDENCE_PAGE_INVALID")
    return page_from, page_to


def record_key_of(post: dict[str, Any]) -> str:
    """Samme nøgle som load_helpers.R:153 (linje + '-' + nr_label)."""
    linje, nr_label = post.get("linje"), post.get("nr_label")
    if not isinstance(linje, str) or not linje \
            or not isinstance(nr_label, str) or not nr_label:
        _fail("SOURCE_EVIDENCE_RECORD_KEY_INVALID")
    return f"{linje}-{nr_label}"


def build_manifest(profile: dict[str, Any], rendition_bytes: bytes,
                   posts: Any) -> dict[str, Any]:
    rendition_sha = hashlib.sha256(rendition_bytes).hexdigest()
    if rendition_sha != profile["raw_text_sha256"]:
        _fail("SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH")
    text = rendition_bytes.decode("utf-8")
    projection, offsets = project_rendition(text)
    if not isinstance(posts, list) or not posts:
        _fail("SOURCE_EVIDENCE_POSTS_INVALID")

    operations: list[dict[str, Any]] = []
    seen: set[str] = set()
    cursor = 0
    for post in posts:
        if not isinstance(post, dict):
            _fail("SOURCE_EVIDENCE_POSTS_INVALID")
        record_key = record_key_of(post)
        if record_key in seen:
            _fail("SOURCE_EVIDENCE_RECORD_KEY_DUPLICATE")
        seen.add(record_key)
        verbatim = post.get("raw_text")
        if not isinstance(verbatim, str) or not verbatim:
            _fail("SOURCE_EVIDENCE_VERBATIM_TEXT_INVALID")
        start = projection.find(verbatim, cursor)
        if start < 0:
            _fail("SOURCE_EVIDENCE_SPAN_NOT_FOUND")
        end = start + len(verbatim)
        char_from = offsets[start]
        char_to = offsets[end - 1] + 1
        if char_from < 0 or char_to <= char_from:
            _fail("SOURCE_EVIDENCE_SPAN_OVERLAP")
        if project_rendition(text[char_from:char_to])[0] != verbatim:
            _fail("SOURCE_EVIDENCE_SPAN_ROUNDTRIP_MISMATCH")
        cursor = end
        page_from, page_to = pages_from_sider(post.get("sider"))
        operations.append({
            "element_id": f"source-evidence:{record_key}",
            "dependency_class": "source_evidence",
            "source_record_key": record_key,
            "source_id": profile["source_id"],
            "category": "person_post",
            "disposition": "retain_source_only",
            "rendition_content_sha256": rendition_sha,
            "source_span": {"char_from": char_from, "char_to": char_to},
            "page_evidence": {"page_from": page_from, "page_to": page_to},
            "verbatim_text": verbatim,
            "verbatim_sha256": hashlib.sha256(verbatim.encode("utf-8")).hexdigest(),
            "anchor_method": "deterministic-segment",
            "segment_version": profile["segment_version"],
        })

    if len(operations) != profile["expected_counts"]["source_evidence"]:
        _fail("SOURCE_EVIDENCE_COUNT_MISMATCH")

    manifest = {
        "source": {
            "id": profile["source_id"],
            "profile_id": profile["profile_id"],
            "profile_sha256": profile["profile_sha256"],
        },
        "expected_counts": {
            "source_evidence": len(operations),
            "person_creates": profile["expected_counts"]["person_creates"],
            "canonical_delta": 0,
        },
        "operations": sorted(
            operations,
            key=lambda op: (op["source_span"]["char_from"], op["element_id"])),
    }
    manifest["manifest_content_sha256"] = hashlib.sha256(json.dumps(
        manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")).hexdigest()
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--rendition-text", required=True)
    parser.add_argument("--posts", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if output.exists():
        _fail("SOURCE_EVIDENCE_OUTPUT_EXISTS")
    profile = load_profile(Path(args.profile))
    manifest = build_manifest(
        profile,
        Path(args.rendition_text).read_bytes(),
        json.loads(Path(args.posts).read_text(encoding="utf-8")))
    output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(json.dumps({
        "manifest_content_sha256": manifest["manifest_content_sha256"],
        "manifest_bytes_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "source_evidence": len(manifest["operations"]),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
