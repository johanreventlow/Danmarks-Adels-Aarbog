#!/usr/bin/env python3
"""Reproducér renditionen for én udgaveprofil og bevis segmenteringsparitet.

Fail-closed: PDF-SHA, rå-tekst-SHA og mængden af lokal_id skal alle matche
profilen og det eksisterende segmenteringsartefakt, ellers stopper fasen.
Læser aldrig andet end `linje` og `nr_label` fra baseline-artefaktet, så der
aldrig passerer navne gennem dette trin (spec §7).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from typing import Any

from reimport_profile import load_profile

SCRIPT_DIR = Path(__file__).resolve().parent


class RenditionError(ValueError):
    pass


def _fail(code: str) -> None:
    raise RenditionError(code)


def verify_pdf(pdf_bytes: bytes, profile: dict[str, Any]) -> str:
    digest = hashlib.sha256(pdf_bytes).hexdigest()
    if digest != profile["pdf_sha256"]:
        _fail("SOURCE_EVIDENCE_PDF_SHA_MISMATCH")
    return digest


def verify_rendition(rendition_bytes: bytes, profile: dict[str, Any]) -> str:
    digest = hashlib.sha256(rendition_bytes).hexdigest()
    if digest != profile["raw_text_sha256"]:
        _fail("SOURCE_EVIDENCE_RENDITION_SHA_MISMATCH")
    return digest


def baseline_lokal_ids(directory: Path) -> list[str]:
    ids: list[str] = []
    for path in sorted(Path(directory).glob("*.json")):
        row = json.loads(path.read_text(encoding="utf-8"))
        linje, nr_label = row.get("linje"), row.get("nr_label")
        if not isinstance(linje, str) or not linje \
                or not isinstance(nr_label, str) or not nr_label:
            _fail("SOURCE_EVIDENCE_BASELINE_INVALID")
        ids.append(f"{linje}.{nr_label}")
    if not ids or len(ids) != len(set(ids)):
        _fail("SOURCE_EVIDENCE_BASELINE_INVALID")
    return sorted(ids)


def _structural_ids(posts: Any) -> list[str]:
    if not isinstance(posts, list) or not posts:
        _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
    produced: list[str] = []
    for post in posts:
        if not isinstance(post, dict):
            _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
        linje, nr_label = post.get("linje"), post.get("nr_label")
        if not isinstance(linje, str) or not linje \
                or not isinstance(nr_label, str) or not nr_label:
            _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
        produced.append(f"{linje}.{nr_label}")
    return produced


def segment_parity(posts: Any, baseline_ids: list[str], expected_count: int) -> list[str]:
    produced = _structural_ids(posts)
    if len(produced) != len(set(produced)) or len(produced) != expected_count \
            or set(produced) != set(baseline_ids):
        _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
    return sorted(set(produced))


def segment_digest(posts: Any, profile: dict[str, Any]) -> dict[str, Any]:
    rows = []
    for post in posts:
        linje, nr_label = post.get("linje"), post.get("nr_label")
        text = post.get("raw_text")
        if not isinstance(text, str) or not text:
            _fail("SOURCE_EVIDENCE_SEGMENT_PARITY_MISMATCH")
        rows.append({
            "record_key": f"{linje}-{nr_label}",
            "verbatim_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
        })
    rows.sort(key=lambda row: row["record_key"])
    digest = {
        "digest_schema_version": "source-evidence-segment-digest-v1",
        "segment_version": profile["segment_version"],
        "raw_text_sha256": profile["raw_text_sha256"],
        "posts": rows,
    }
    digest["digest_sha256"] = hashlib.sha256(json.dumps(
        digest, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")).hexdigest()
    return digest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", required=True)
    parser.add_argument("--pdf", required=True)
    parser.add_argument("--baseline-dir", default="data/extracted-2026-06-18")
    parser.add_argument("--output-dir", required=True)
    args = parser.parse_args()

    profile = load_profile(Path(args.profile))
    output_dir = Path(args.output_dir)
    if output_dir.exists():
        _fail("SOURCE_EVIDENCE_OUTPUT_EXISTS")
    verify_pdf(Path(args.pdf).read_bytes(), profile)

    version = subprocess.run(["pdftotext", "-v"], capture_output=True, text=True).stderr
    expected_version = profile["writer_config"]["rendition_metadata"]["pdftotext_version"]
    if expected_version not in version:
        _fail("SOURCE_EVIDENCE_PDFTOTEXT_VERSION_MISMATCH")

    pdftotext_args = profile["pdftotext_args"]
    extracted = subprocess.run(
        [str(SCRIPT_DIR / "extract_text.sh"), str(Path(args.pdf).resolve()),
         str(pdftotext_args["first_page"]), str(pdftotext_args["last_page"])],
        capture_output=True, check=True)
    verify_rendition(extracted.stdout, profile)

    output_dir.mkdir(parents=True)
    rendition_path = output_dir / "rendition.txt"
    rendition_path.write_bytes(extracted.stdout)

    segmented = subprocess.run(
        ["python3", str(SCRIPT_DIR / "segment.py"), str(rendition_path.resolve())],
        capture_output=True, check=True, cwd=SCRIPT_DIR)
    posts = json.loads(segmented.stdout.decode("utf-8"))
    (output_dir / "posts.json").write_bytes(segmented.stdout)

    ids = segment_parity(posts, baseline_lokal_ids(Path(args.baseline_dir)),
                         profile["expected_counts"]["source_evidence"])
    digest = segment_digest(posts, profile)
    (output_dir / "segment-digest.json").write_text(
        json.dumps(digest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(json.dumps({
        "raw_text_sha256": profile["raw_text_sha256"],
        "posts": len(ids),
        "segment_digest_sha256": digest["digest_sha256"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
