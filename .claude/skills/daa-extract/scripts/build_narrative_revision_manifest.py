#!/usr/bin/env python3
"""Byg et privat revisionsmanifest for narrativer ud fra to segmentprofiler.

A6b (decisions 2026-10-27/-28): v1-støjreglen fjernede prosalinjer midt på en
side. Manifestet sammenligner segmenteringen med profilen `fra` og `til` over
samme rå tekst og tager kun poster, hvis tekst er ændret. Det afviser, hvis en
postgrænse eller et andet felt end teksten er ændret, og hvis ændringen er andet
end rene indsættelser af ord. Manifestet rummer posttekst (PII) og skrives kun
til en fil med mode 0600; stdout bærer kun antal, nøgler og hash. Scriptet rører
aldrig en database.
"""
from __future__ import annotations

import argparse
import contextlib
import difflib
import hashlib
import io
import json
import os
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import segment


class ManifestError(ValueError):
    pass


def _fail(code: str) -> None:
    raise ManifestError(code)


def _sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _canonical_sha256(value: Any) -> str:
    return _sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                              ensure_ascii=False))


def _segment(raw_text: str, udgave: str) -> list[dict[str, Any]]:
    profile = segment.UDGAVE_PROFILER.get(udgave)
    if profile is None:
        _fail("NARRATIVE_REVISION_PROFILE_UNKNOWN")
    # Segmenteren skriver posterne og kvalitetsrapporten ud; de holdes inde.
    with contextlib.redirect_stdout(io.StringIO()), \
            contextlib.redirect_stderr(io.StringIO()):
        return profile["segmenter"](raw_text.splitlines(), profile)


def _record_key(post: dict[str, Any]) -> str:
    """Samme nøgle som build_source_evidence_manifest.record_key_of."""
    linje, nr_label = post.get("linje"), post.get("nr_label")
    if not isinstance(linje, str) or not linje \
            or not isinstance(nr_label, str) or not nr_label:
        _fail("NARRATIVE_REVISION_RECORD_KEY_INVALID")
    return f"{linje}-{nr_label}"


def _inserted_tokens(old: str, new: str) -> int:
    opcodes = difflib.SequenceMatcher(
        None, old.split(" "), new.split(" "), autojunk=False).get_opcodes()
    if any(tag not in ("equal", "insert") for tag, *_ in opcodes):
        _fail("NARRATIVE_REVISION_NOT_PURE_INSERTION")
    return sum(j2 - j1 for tag, _, _, j1, j2 in opcodes if tag == "insert")


def build_revision_manifest(raw_text: str, fra: str, til: str,
                            source_id: int) -> dict[str, Any]:
    old_posts, new_posts = _segment(raw_text, fra), _segment(raw_text, til)
    if [_record_key(p) for p in old_posts] != [_record_key(p) for p in new_posts]:
        _fail("NARRATIVE_REVISION_BOUNDARY_CHANGED")

    elements = []
    for old, new in zip(old_posts, new_posts):
        if {k: v for k, v in old.items() if k != "raw_text"} \
                != {k: v for k, v in new.items() if k != "raw_text"}:
            _fail("NARRATIVE_REVISION_BOUNDARY_CHANGED")
        if old["raw_text"] == new["raw_text"]:
            continue
        elements.append({
            "record_key": _record_key(old),
            "old_text": old["raw_text"],
            "new_text": new["raw_text"],
            "old_sha256": _sha256(old["raw_text"]),
            "new_sha256": _sha256(new["raw_text"]),
            "inserted_tokens": _inserted_tokens(old["raw_text"], new["raw_text"]),
        })
    elements.sort(key=lambda e: e["record_key"])

    manifest = {"kind": "narrative_revision", "source_id": source_id,
                "fra": fra, "til": til, "elements": elements}
    manifest["manifest_sha256"] = _canonical_sha256(manifest)
    return manifest


def _write_private(out: Path, manifest: dict[str, Any]) -> None:
    """Skriv til en ny fil, der er 0600 fra første byte, og erstat `out`
    atomisk. En eksisterende fil med bredere mode bliver aldrig skrevet i."""
    if out.is_symlink():
        _fail("NARRATIVE_REVISION_OUT_SYMLINK")
    tmp = out.with_name(f".{out.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(manifest, fh, ensure_ascii=False, indent=2, sort_keys=True)
            fh.write("\n")
        os.replace(tmp, out)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--raw", required=True)
    parser.add_argument("--fra", required=True)
    parser.add_argument("--til", required=True)
    parser.add_argument("--source-id", required=True, type=int)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    raw_text = Path(args.raw).read_text(encoding="utf-8")
    manifest = build_revision_manifest(raw_text, args.fra, args.til, args.source_id)
    _write_private(Path(args.out), manifest)
    keys = ",".join(e["record_key"] for e in manifest["elements"])
    print(f"NARRATIVE_REVISION_MANIFEST elements={len(manifest['elements'])} "
          f"keys={keys} sha={manifest['manifest_sha256']}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ManifestError as error:
        sys.exit(f"NARRATIVE_REVISION_FEJL {error}")
