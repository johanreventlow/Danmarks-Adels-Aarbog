#!/usr/bin/env python3
"""Kontrolmodellen: mennesket ser kun uoverensstemmelser og en stikprøve (#147).

Beslutning: `docs/decisions.md` 2026-09-27. Plan: `docs/superpowers/plans/2026-09-27-trin4-kontrolmodel.md`.

En kørsel:
  1. `interpretation_control_classification.sql` klassificerer alle `proposed` med en aktiv
     promotionregel; `interpretation_control_rows.sql` eksporterer rækkefilen.
  2. `plan` trækker stikprøven blandt `MATCH` deterministisk og skriver menneskets rækkefil
     (REAL_DIFF ∪ stikprøve) og maskinplanen (resten af `MATCH`) — hash-bundet i `plan.json`,
     FØR et menneske ser et kort.
  3. Arket bygges og oversættes med `interpretation_decision_sheet.py`
     (`--method human-sheet-kontrol-v1`), uændret.
  4. `machine-sql` kræver, at stikprøven er fuldt accepteret (et `R` eller `U` er STOP), og
     skriver den maskinelle accept af resten.
  5. Bindingen sker med den eksisterende målfinding og batch-RPC; `verify-sql` efterprøver, at
     målfindingens MATCH-sæt er præcis maskinsættet ∪ stikprøven.

Ingen kildetekst printes. Alle skrevne filer er 0600.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

from interpretation_decision_sheet import SheetError, check_identity, parse_sheet

SEED = "kontrolmodel-v1"
SAMPLE_SIZE = 20
MACHINE_METHOD = "machine-corroboration-v1"
HUMAN_METHOD = "human-sheet-kontrol-v1"
DECISION_REF = "decisions.md 2026-09-27"
TARGETS_SQL = ".claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql"

#: Klasserne fra interpretation_control_classification.sql. Kun MATCH (bulk) kan accepteres
#: maskinelt; kun REAL_DIFF og stikprøven vises for mennesket; resten forbliver `proposed`.
CLASSES = ("MATCH", "MATCH_SINGLETON", "AMBIGUOUS", "SKRIVEMAADE", "NO_FACT", "REAL_DIFF",
           "NO_IDENTITY", "NO_PLACEMENT", "UNSUPPORTED_RULE")


class ControlError(ValueError):
    """Fail-closed: intet skrives."""


def _sample_key(interpretation_id: str) -> str:
    return hashlib.sha256(f"{SEED}:{interpretation_id}".encode("utf-8")).hexdigest()


def _canonical_sha(obj) -> str:
    return hashlib.sha256(json.dumps(obj, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def _validate(classification) -> list[dict]:
    items = classification.get("items") if isinstance(classification, dict) else None
    if not isinstance(items, list):
        raise ControlError("CLASSIFICATION_INVALID items")
    seen = set()
    for i in items:
        if (not isinstance(i, dict) or i.get("class") not in CLASSES
                or not isinstance(i.get("interpretation_id"), str)
                or not isinstance(i.get("version"), int) or i["version"] < 1):
            raise ControlError("CLASSIFICATION_INVALID item")
        if i["interpretation_id"] in seen:
            raise ControlError("CLASSIFICATION_INVALID duplicate")
        seen.add(i["interpretation_id"])
        if i["class"] in ("MATCH", "MATCH_SINGLETON") and not isinstance(i.get("assertion_id"), int):
            raise ControlError("CLASSIFICATION_INVALID assertion_id")
    return items


def plan_run(classification: dict, rows: list[dict], sample_size: int = SAMPLE_SIZE) -> dict:
    """Stikprøve, menneskets rækker og maskinplanen. Ren funktion; ingen I/O."""
    items = _validate(classification)
    match = sorted((i for i in items if i["class"] == "MATCH"),
                   key=lambda i: _sample_key(i["interpretation_id"]))
    sample, machine = match[:sample_size], match[sample_size:]
    real_diff = [i for i in items if i["class"] == "REAL_DIFF"]

    ark = {i["interpretation_id"]: i["version"] for i in sample + real_diff}
    by_id = {r["interpretation_id"]: r for r in rows}
    for interpretation_id, version in ark.items():
        r = by_id.get(interpretation_id)
        if r is None:
            raise ControlError("ROWS_MISSING")
        if r["version"] != version:
            raise ControlError("ROWS_VERSION_MISMATCH")

    counts: dict[str, int] = {c: 0 for c in CLASSES}
    for i in items:
        counts[i["class"]] += 1
    return {
        "sample_ids": sorted(i["interpretation_id"] for i in sample),
        "real_diff_ids": sorted(i["interpretation_id"] for i in real_diff),
        "rows_kontrol": [r for r in rows if r["interpretation_id"] in ark],
        "machine": sorted(({"interpretation_id": i["interpretation_id"], "version": i["version"],
                            "predicate": i["predicate"], "assertion_id": i["assertion_id"]}
                           for i in machine), key=lambda m: m["interpretation_id"]),
        "counts": counts,
    }


def _lit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def machine_sql(plan: dict, sheet_text: str, *, sheet_sha256: str, hashes: dict) -> str | None:
    """Gaten og den maskinelle accept. `None` når maskinsættet er tomt."""
    decisions = parse_sheet(sheet_text)
    check_identity(decisions, plan["rows_kontrol"])
    sample = set(plan["sample_ids"])
    afvist = sum(1 for d in decisions if d.interpretation_id in sample and d.status == "rejected")
    uafklaret = sum(1 for d in decisions if d.interpretation_id in sample and d.status == "unresolved")
    if afvist or uafklaret:
        raise ControlError(f"SAMPLE_FAILED rejected={afvist} unresolved={uafklaret}")
    if not plan["machine"]:
        return None

    ids = ",".join(f"'{i}'" for i in plan["sample_ids"])
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL ROLE authenticated;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
           # Menneskets afgørelser af stikprøven skal stå i basen, før maskinen må accepte.
           "DO $$ BEGIN IF (SELECT count(*) FROM private.interpretation i WHERE i.supersedes_id IN ("
           f"{ids}) AND i.status = 'accepted' AND i.decision_evidence->>'method' = '{HUMAN_METHOD}') "
           f"<> {len(plan['sample_ids'])} THEN RAISE EXCEPTION 'SAMPLE_NOT_APPLIED'; END IF; END $$;",
           "CREATE TEMP TABLE decided(id uuid) ON COMMIT DROP;"]
    for m in plan["machine"]:
        evidence = json.dumps({"method": MACHINE_METHOD, "decision": DECISION_REF,
                               "classification_sha256": hashes.get("classification_sha256"),
                               "sample_sha256": hashes.get("sample_sha256"),
                               "sheet_sha256": sheet_sha256, "assertion_id": m["assertion_id"]},
                              ensure_ascii=False, sort_keys=True)
        out.append(f"INSERT INTO decided SELECT red_decide_interpretation("
                   f"'{m['interpretation_id']}'::uuid, {m['version']}, 'accepted', "
                   f"{_lit(evidence)}::jsonb);")
    out.append("DO $$ BEGIN IF (SELECT count(*) FROM decided) <> "
               f"{len(plan['machine'])} THEN RAISE EXCEPTION 'MACHINE_COUNT_MISMATCH'; END IF; END $$;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def verify_sql(plan: dict) -> str:
    """Læse-kun: målfindingens MATCH-sæt (via `supersedes_id`) = maskinsættet ∪ stikprøven."""
    forventet = sorted(plan["sample_ids"] + [m["interpretation_id"] for m in plan["machine"]])
    literal = json.dumps(forventet)
    return "\n".join([
        "\\set ON_ERROR_STOP on",
        "BEGIN;",
        "SET LOCAL default_transaction_read_only = on;",
        f"\\i {TARGETS_SQL}",
        "DO $$",
        "DECLARE t jsonb := current_setting('daa.targets_result')::jsonb;",
        "        faktisk jsonb;",
        f"        forventet jsonb := {_lit(literal)}::jsonb;",
        "BEGIN",
        "  SELECT coalesce(jsonb_agg(ni.supersedes_id::text ORDER BY ni.supersedes_id::text), '[]')",
        "    INTO faktisk FROM jsonb_array_elements(t->'items') x",
        "    JOIN private.interpretation ni ON ni.id = (x->>'interpretation_id')::uuid;",
        "  IF faktisk IS DISTINCT FROM forventet OR jsonb_array_length(t->'singleton_items') <> 0 THEN",
        "    RAISE EXCEPTION 'CONTROL_TARGETS_MISMATCH faktisk=% forventet=%',",
        "      jsonb_array_length(faktisk), jsonb_array_length(forventet);",
        "  END IF;",
        "  RAISE NOTICE 'CONTROL_TARGETS_OK %', jsonb_array_length(faktisk);",
        "END $$;",
        "ROLLBACK;",
    ]) + "\n"


def _write(path: Path, data: bytes) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(data)
    os.chmod(path, 0o600)
    return hashlib.sha256(data).hexdigest()


def _json_bytes(obj) -> bytes:
    return (json.dumps(obj, ensure_ascii=False, indent=1) + "\n").encode("utf-8")


def _sha_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _load_plan(plan_dir: Path) -> tuple[dict, dict]:
    meta = json.loads((plan_dir / "plan.json").read_text(encoding="utf-8"))
    for navn, felt in (("rows-kontrol.json", "rows_kontrol_sha256"),
                       ("machine-plan.json", "machine_plan_sha256")):
        if _sha_file(plan_dir / navn) != meta[felt]:
            raise ControlError(f"PLAN_HASH_MISMATCH {navn}")
    plan = {"sample_ids": meta["sample_ids"], "real_diff_ids": meta["real_diff_ids"],
            "rows_kontrol": json.loads((plan_dir / "rows-kontrol.json").read_text(encoding="utf-8")),
            "machine": json.loads((plan_dir / "machine-plan.json").read_text(encoding="utf-8"))}
    if _canonical_sha(plan["sample_ids"]) != meta["sample_sha256"]:
        raise ControlError("PLAN_HASH_MISMATCH sample")
    return plan, meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--classification", required=True)
    p.add_argument("--rows", required=True)
    p.add_argument("--out-dir", required=True)
    m = sub.add_parser("machine-sql")
    m.add_argument("--plan-dir", required=True)
    m.add_argument("--sheet", required=True)
    m.add_argument("--approved-sha256", required=True)
    m.add_argument("--out", required=True)
    v = sub.add_parser("verify-sql")
    v.add_argument("--plan-dir", required=True)
    v.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        if args.cmd == "plan":
            k_path, r_path = Path(args.classification), Path(args.rows)
            classification = json.loads(k_path.read_text(encoding="utf-8"))
            rows = json.loads(r_path.read_text(encoding="utf-8"))
            plan = plan_run(classification, rows)
            ud = Path(args.out_dir)
            meta = {"seed": SEED, "sample_size": SAMPLE_SIZE, "decision": DECISION_REF,
                    "classification_sha256": _sha_file(k_path), "rows_sha256": _sha_file(r_path),
                    "sample_ids": plan["sample_ids"], "sample_sha256": _canonical_sha(plan["sample_ids"]),
                    "real_diff_ids": plan["real_diff_ids"], "counts": plan["counts"],
                    "rows_kontrol_sha256": _write(ud / "rows-kontrol.json", _json_bytes(plan["rows_kontrol"])),
                    "machine_plan_sha256": _write(ud / "machine-plan.json", _json_bytes(plan["machine"]))}
            _write(ud / "plan.json", _json_bytes(meta))
            print(f"PLAN_OK klasser={json.dumps(plan['counts'], sort_keys=True)} "
                  f"stikprøve={len(plan['sample_ids'])} uoverensstemmelser={len(plan['real_diff_ids'])} "
                  f"maskinelle={len(plan['machine'])} ark={len(plan['rows_kontrol'])}")
            print(f"  sample_sha256 {meta['sample_sha256']}")
            print(f"  rows_kontrol_sha256 {meta['rows_kontrol_sha256']}")
            return 0

        plan, meta = _load_plan(Path(args.plan_dir))
        if args.cmd == "verify-sql":
            _write(Path(args.out), verify_sql(plan).encode("utf-8"))
            print(f"VERIFY_SQL_OK forventet={len(plan['sample_ids']) + len(plan['machine'])}")
            return 0

        data = Path(args.sheet).read_bytes()
        faktisk = hashlib.sha256(data).hexdigest()
        if faktisk != args.approved_sha256:
            print("SHEET_HASH_MISMATCH — arket er ikke det, der blev godkendt.")
            return 1
        sql = machine_sql(plan, data.decode("utf-8"), sheet_sha256=faktisk, hashes=meta)
        if sql is None:
            print("MACHINE_EMPTY — alle kandidater var i stikprøven; intet at accepte maskinelt.")
            return 0
        _write(Path(args.out), sql.encode("utf-8"))
        print(f"MACHINE_SQL_OK maskinelle={len(plan['machine'])}")
        return 0
    except (ControlError, SheetError) as exc:
        print(str(exc))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
