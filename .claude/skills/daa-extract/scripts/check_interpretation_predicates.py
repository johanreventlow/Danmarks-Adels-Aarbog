#!/usr/bin/env python3
"""Byte-verificér references/interpretation-predicates.json mod databasen (#147 4.2).
Bruger psql via PG*-miljøet. --write regenererer filen fra databasen."""
from __future__ import annotations
import argparse, json, subprocess, sys
from pathlib import Path
FILE = Path(__file__).resolve().parents[1] / "references" / "interpretation-predicates.json"
SQL = """SELECT coalesce(json_agg(json_build_object('predicate',p.predicate,'interpretation_kind',p.interpretation_kind,'category',p.category,
  'value_kind',p.value_kind,'promotable',EXISTS(SELECT 1 FROM private.interpretation_predicate_promotable v WHERE v.predicate=p.predicate))
  ORDER BY p.predicate COLLATE "C"),'[]'::json) FROM private.interpretation_predicate p WHERE p.status='active' AND p.introduced_in<>'db-verify-fixture'"""

def from_db() -> dict:
    out = subprocess.run(["psql", "-X", "-At", "-v", "ON_ERROR_STOP=1", "-c", SQL], capture_output=True, text=True, check=True).stdout.strip()
    return {"schema_version": "interpretation-predicates-1.0", "predicates": json.loads(out)}

def render(payload: dict) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

def main() -> None:
    parser = argparse.ArgumentParser(); parser.add_argument("--write", action="store_true"); args = parser.parse_args()
    expected = render(from_db())
    if args.write:
        FILE.write_text(expected, encoding="utf-8"); print("written", len(json.loads(expected)["predicates"])); return
    actual = FILE.read_text(encoding="utf-8") if FILE.exists() else ""
    if actual != expected:
        print("PREDICATE_FILE_DRIFT: kør check_interpretation_predicates.py --write mod en base med gældende schema", file=sys.stderr); raise SystemExit(2)
    print("PREDICATE_FILE_OK")

if __name__ == "__main__": main()
