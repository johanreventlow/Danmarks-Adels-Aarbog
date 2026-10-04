#!/usr/bin/env python3
"""Overførselspakken for 2018-20 (#147; spec 2026-10-03 §4-§6).

Databasefri: SQL-filerne skriver JSON (daa.pack_export, daa.fingerprints, daa.transfer_digests,
daa.transfer_baseline); denne fil bygger og validerer pakken, klassificerer tilstanden og genererer
skrive-SQL'en for 07/08. Printer kun tal og hashes — aldrig noter, værdier eller aktør-id.
Alle skrevne filer er 0600.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from pathlib import Path

DRIFT_BASELINE_FIELDS = ("canonical_sha256", "clause_set_sha256", "schema_sha256")
EMPTY_SHA = hashlib.sha256(b"").hexdigest()
PACK_VERSION = "transfer-pack-v1"


class PackError(ValueError):
    """Fail-closed: intet skrives."""


def canonical(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def pack_sha256(manifest: dict) -> str:
    return sha256_text(canonical({k: v for k, v in manifest.items() if k != "pack_sha256"}))


def _write_private(path: Path, text: str) -> None:
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)


def build_pack(*, export: dict, fingerprints: dict, digests: dict, baseline: dict, record_check: dict, classification: dict,
               classification_sha256: str, receipt: dict, manifest_content_sha256: str,
               ledger_sha256: str) -> tuple[list[dict], dict]:
    if record_check["n_no_record"] > 0 or record_check["n_multi_record"] > 0:
        raise PackError(f"PACK_RECORD_AMBIGUOUS no_record={record_check['n_no_record']} "
                        f"multi_record={record_check['n_multi_record']}")
    missing_drift = [f for f in DRIFT_BASELINE_FIELDS if f not in baseline]
    if missing_drift:
        raise PackError(f"PACK_BASELINE_INCOMPLETE {len(missing_drift)}")
    rows = export["decisions"]
    if any(not isinstance(r.get("evidence"), dict) for r in rows):
        raise PackError("PACK_EVIDENCE_INVALID")
    keys = [r["interpretation_key"] for r in rows]
    if len(keys) != len(set(keys)):
        raise PackError("PACK_DUPLICATE_KEY")
    actors = {r["decided_by"] for r in rows}
    if len(actors) != 1:
        raise PackError(f"PACK_ACTOR_COUNT {len(actors)}")
    missing = [k for k in keys if k not in fingerprints]
    if missing:
        raise PackError(f"PACK_FINGERPRINT_MISSING {len(missing)}")
    by_ms = Counter(f"{r['evidence'].get('method', '')}|{r['status']}" for r in rows)
    if (len(rows) != digests["n_decided"] or dict(by_ms) != digests["decided_by_method_status"]
            or len(export["key_by_v1_id"]) != digests["n_interpretations"]
            or len(fingerprints) != digests["n_interpretations"]):
        raise PackError("PACK_COUNT_MISMATCH")

    key_by_v1 = export["key_by_v1_id"]
    keyed_cls = {}
    for item in classification["items"]:
        key = key_by_v1.get(item["interpretation_id"])
        if key is None:
            raise PackError("PACK_CLASSIFICATION_UNMAPPED")
        if key in keyed_cls:
            raise PackError("PACK_CLASSIFICATION_DUPLICATE")
        keyed_cls[key] = [item["class"], item["assertion_id"]]

    not_match = unclassified = 0
    for r in rows:
        method = r["evidence"].get("method")
        entry = keyed_cls.get(r["interpretation_key"])
        if method == "machine-corroboration-v1" and r["status"] == "accepted":
            if entry is None or entry[0] != "MATCH" or entry[1] != r["evidence"].get("assertion_id"):
                not_match += 1
        elif method == "human-sheet-kontrol-v1" and entry is None:
            unclassified += 1
    if not_match:
        raise PackError(f"PACK_MACHINE_NOT_MATCH {not_match}")
    if unclassified:
        raise PackError(f"PACK_HUMAN_UNCLASSIFIED {unclassified}")

    decisions = [{"interpretation_key": r["interpretation_key"],
                  "restore_interpretation_id": r["restore_interpretation_id"],
                  "expected_version": 1, "status": r["status"],
                  "decision_fingerprint": fingerprints[r["interpretation_key"]],
                  "evidence": r["evidence"]} for r in sorted(rows, key=lambda r: r["interpretation_key"])]
    decisions_text = canonical(decisions)  # nøjagtig de bytes, der skrives til decisions-keyed.json
    accepted = sorted(d["interpretation_key"] for d in decisions if d["status"] == "accepted")
    manifest = {
        "pack_version": PACK_VERSION,
        "manifest_content_sha256": manifest_content_sha256,
        "ledger_sha256": ledger_sha256,
        "dump_sha256": receipt["dump_sha256"],
        "dump_state": receipt["state"],
        "dump_kanonisk_md5": receipt["kanonisk_md5"],
        "baseline": baseline,
        "record_check": record_check,
        "classification_sha256": classification_sha256,
        "keyed_classification": dict(sorted(keyed_cls.items())),
        "actor_sha256": sha256_text(next(iter(actors))),
        "counts_by_method_status": dict(sorted(by_ms.items())),
        "n_decisions": len(decisions),
        "n_accepted": len(accepted),
        "accepted_keys": accepted,
        "digests": digests,
        "decisions_keyed_sha256": sha256_text(decisions_text),
    }
    manifest["pack_sha256"] = pack_sha256(manifest)
    return decisions, manifest


def classify_state(digests: dict, pack: dict) -> str:
    """Spec §5: EMPTY / PROPOSED / DECIDED / COMPLETE, ellers MIXED."""
    want = pack["digests"]
    nothing = (digests["n_interpretations"] == 0 and digests["n_decided"] == 0 and digests["n_bindings"] == 0)
    if nothing:
        return "EMPTY"
    proposals = (digests["n_interpretations"] == want["n_interpretations"]
                 and digests["proposal_digest"] == want["proposal_digest"])
    if not proposals:
        return "MIXED"
    no_bindings = digests["n_bindings"] == 0 and digests["binding_digest"] == EMPTY_SHA
    if (digests["n_decided"] == 0 and no_bindings and digests["decision_digest"] == EMPTY_SHA
            and digests["decided_by_method_status"] == {}):
        return "PROPOSED"
    decisions = (digests["n_decided"] == want["n_decided"]
                 and digests["decided_by_method_status"] == want["decided_by_method_status"]
                 and digests["decision_digest"] == want["decision_digest"])
    if not decisions:
        return "MIXED"
    if no_bindings:
        return "DECIDED"
    if digests["n_bindings"] == want["n_bindings"] and digests["binding_digest"] == want["binding_digest"]:
        return "COMPLETE"
    return "MIXED"


def _load(path: str):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    for flag in ("--export", "--fingerprints", "--digests", "--baseline", "--record-check", "--classification", "--dump-receipt",
                 "--manifest-content-sha256", "--ledger-sha256", "--out-dir"):
        b.add_argument(flag, required=True)
    s = sub.add_parser("state")
    s.add_argument("--digests", required=True)
    s.add_argument("--pack-manifest", required=True)
    args = ap.parse_args(argv)
    try:
        if args.cmd == "build":
            cls_path = Path(args.classification)
            decisions, manifest = build_pack(
                export=_load(args.export), fingerprints=_load(args.fingerprints), digests=_load(args.digests),
                baseline=_load(args.baseline), record_check=_load(args.record_check), classification=_load(args.classification),
                classification_sha256=hashlib.sha256(cls_path.read_bytes()).hexdigest(),
                receipt=_load(args.dump_receipt), manifest_content_sha256=args.manifest_content_sha256,
                ledger_sha256=args.ledger_sha256)
            out = Path(args.out_dir)
            if not out.is_dir() or out.stat().st_mode & 0o777 != 0o700:
                raise PackError("PACK_OUT_DIR_MODE")
            _write_private(out / "decisions-keyed.json", canonical(decisions))
            _write_private(out / "pack-manifest.json", canonical(manifest) + "\n")
            print(f"PACK_OK afgørelser={manifest['n_decisions']} accepterede={manifest['n_accepted']} "
                  f"klassificerede={len(manifest['keyed_classification'])} pack_sha256={manifest['pack_sha256']}")
        else:
            manifest = _load(args.pack_manifest)
            if pack_sha256(manifest) != manifest.get("pack_sha256"):
                raise PackError("PACK_SHA_MISMATCH")
            print(classify_state(_load(args.digests), manifest))
    except PackError as exc:
        print(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
