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
import re
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
    # restore_interpretation_id er version 1-id'et (arkets og klassifikationens id, spec §4.1); det skal
    # pege på netop afgørelsens nøgle.
    if any(key_by_v1.get(r.get("restore_interpretation_id")) != r["interpretation_key"] for r in rows):
        raise PackError("PACK_ID_MISMATCH")
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
            aid = entry[1] if entry is not None else None
            if (entry is None or entry[0] != "MATCH" or not isinstance(aid, int) or isinstance(aid, bool)
                    or aid != r["evidence"].get("assertion_id")):
                not_match += 1
        elif method == "human-sheet-kontrol-v1" and entry is None:
            unclassified += 1
    if not_match:
        raise PackError(f"PACK_MACHINE_NOT_MATCH {not_match}")
    if unclassified:
        raise PackError(f"PACK_HUMAN_UNCLASSIFIED {unclassified}")

    decisions = [{"interpretation_key": r["interpretation_key"],
                  "restore_interpretation_id": r["restore_interpretation_id"],
                  "restore_decision_interpretation_id": r["restore_decision_interpretation_id"],
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


SCRIPTS = ".claude/skills/daa-extract/scripts"
DO_TAGS = ("$g$", "$c$", "$m$", "$p$", "$a$", "$w$", "$d$")
_HEX64 = re.compile(r"[0-9a-f]{64}")
_UUID = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")
DECISION_STATUSES = ("accepted", "rejected", "unresolved", "superseded")
CONTROL_CLASSES = ("MATCH", "MATCH_SINGLETON", "AMBIGUOUS", "SKRIVEMAADE", "NO_FACT", "REAL_DIFF",
                   "NO_IDENTITY", "NO_PLACEMENT", "UNSUPPORTED_RULE")


def _bad(field: str):
    # Feltnavnet, aldrig værdien (kan være evidens/fritekst).
    raise PackError(f"PACK_FIELD_INVALID {field}")


def _hex(v, field):
    if not (isinstance(v, str) and _HEX64.fullmatch(v)):
        _bad(field)


def _uuid(v, field):
    if not (isinstance(v, str) and _UUID.fullmatch(v)):
        _bad(field)


def _count(v, field):
    if not isinstance(v, int) or isinstance(v, bool) or v < 0:
        _bad(field)


def _validate_manifest(manifest: dict, state: str) -> None:
    """Hvidliste over hver skalar, generatoren indlejrer i SQL'en (pakkens segl er selvrefererende)."""
    d = manifest["digests"]
    _hex(manifest.get("pack_sha256"), "pack_sha256")
    _hex(manifest.get("actor_sha256"), "actor_sha256")
    _hex(d.get("proposal_digest"), "digests.proposal_digest")
    _count(d.get("n_interpretations"), "digests.n_interpretations")
    if state == "DECIDED":
        _hex(d.get("decision_digest"), "digests.decision_digest")
        _count(d.get("n_decided"), "digests.n_decided")
        _hex(d.get("binding_digest"), "digests.binding_digest")
        _count(d.get("n_bindings"), "digests.n_bindings")
        keys = manifest.get("accepted_keys")
        if not isinstance(keys, list):
            _bad("accepted_keys")
        for k in keys:
            _uuid(k, "accepted_keys[]")
    else:
        _hex(d.get("decision_digest"), "digests.decision_digest")
        _count(manifest.get("n_decisions"), "n_decisions")
        _hex(manifest.get("baseline", {}).get("clause_set_sha256"), "baseline.clause_set_sha256")
        kc = manifest.get("keyed_classification")
        if not isinstance(kc, dict):
            _bad("keyed_classification")
        for k, v in kc.items():
            _uuid(k, "keyed_classification{}")
            if not (isinstance(v, list) and len(v) == 2 and v[0] in CONTROL_CLASSES
                    and (v[1] is None or (isinstance(v[1], int) and not isinstance(v[1], bool)))):
                _bad("keyed_classification[]")


def _validate_decisions(decisions: list) -> None:
    if not isinstance(decisions, list):
        _bad("decisions")
    for d in decisions:
        _uuid(d.get("interpretation_key"), "decisions[].interpretation_key")
        _uuid(d.get("restore_interpretation_id"), "decisions[].restore_interpretation_id")
        _uuid(d.get("restore_decision_interpretation_id"), "decisions[].restore_decision_interpretation_id")
        if d.get("status") not in DECISION_STATUSES:
            _bad("decisions[].status")
        _hex(d.get("decision_fingerprint"), "decisions[].decision_fingerprint")
        if not isinstance(d.get("evidence"), dict):
            _bad("decisions[].evidence")


def _check_tags(sql: str) -> str:
    """Seler og livrem: hvert DO-tag skal stå præcis to gange (åbning og lukning af én blok)."""
    tags = Counter(re.findall(r"\$[A-Za-z_]*\$", sql))
    if not tags or any(n != 2 for n in tags.values()):
        raise PackError("PACK_DOLLAR_TAG")
    return sql


def _lit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def _quiet_include(name: str) -> str:
    """Kør en delt læse-fil uden at dens resultatrække når stdout."""
    return f"\\o /dev/null\n\\i {SCRIPTS}/{name}\n\\o"


def _head() -> list[str]:
    # psql indsætter ikke :src i $-quotede DO-blokke; kilden lægges derfor i en GUC.
    # REPEATABLE READ: vagter og skrivning ser ét snapshot. Sessionen skal citere strenge som standard.
    return ["\\set ON_ERROR_STOP on", "\\set QUIET on", "BEGIN;",
            "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;",
            "DO $u$ BEGIN IF current_setting('standard_conforming_strings') <> 'on' "
            "THEN RAISE EXCEPTION 'TRANSFER_SESSION_UNSAFE'; END IF; END $u$;",
            "SELECT set_config('daa.src', :'src', true) \\g /dev/null"]


def _state_guard(want: dict, state: str, code: str) -> str:
    """SQL-vagt: kør digests og kræv netop indgangstilstanden (spec §5)."""
    w = want["digests"]
    cond = {"PROPOSED": (f"(d->>'n_interpretations')::int = {int(w['n_interpretations'])} "
                         f"AND d->>'proposal_digest' = {_lit(w['proposal_digest'])} "
                         "AND (d->>'n_decided')::int = 0 AND (d->>'n_bindings')::int = 0"),
            "DECIDED": (f"(d->>'n_interpretations')::int = {int(w['n_interpretations'])} "
                        f"AND d->>'proposal_digest' = {_lit(w['proposal_digest'])} "
                        f"AND (d->>'n_decided')::int = {int(w['n_decided'])} "
                        f"AND d->>'decision_digest' = {_lit(w['decision_digest'])} "
                        "AND (d->>'n_bindings')::int = 0")}[state]
    return (_quiet_include("interpretation_transfer_digests.sql") + "\n"
            "DO $g$ DECLARE d jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN "
            f"IF NOT ({cond}) THEN RAISE EXCEPTION '{code}'; END IF; END $g$;")


def _actor_switch(manifest: dict) -> list[str]:
    """Aktøren = pakkens (uuid-hash, spec §6.2); derefter kun RPC'erne som authenticated."""
    return ["SELECT set_config('request.jwt.claim.sub', :'actor', true) \\g /dev/null",
            "DO $a$ BEGIN IF encode(extensions.digest(convert_to(current_setting('request.jwt.claim.sub')::uuid::text,"
            f"'UTF8'),'sha256'),'hex') IS DISTINCT FROM {_lit(manifest['actor_sha256'])} "
            "THEN RAISE EXCEPTION 'TRANSFER_ACTOR_MISMATCH'; END IF; END $a$;",
            "SET LOCAL ROLE authenticated;"]


def _tail() -> list[str]:
    # Udskudte kontroller (fx interpretation_has_observation) skal fyre FØR resultat-digesten.
    return ["RESET ROLE;", "SET CONSTRAINTS ALL IMMEDIATE;"]


def decide_sql(decisions: list[dict], manifest: dict) -> str:
    """07: én transaktion. Læsning som ejerrolle; kun RPC-kaldene som authenticated (review 2, N4).
    Vagtrækkefølge: tilstand → klausulsæt → præmis → fingeraftryk → nøgleopslag → aktør → skrivning → digest."""
    _validate_manifest(manifest, "PROPOSED")
    _validate_decisions(decisions)
    if any(d.get("expected_version") != 1 for d in decisions):
        raise PackError("PACK_EXPECTED_VERSION")
    pack = manifest["pack_sha256"]
    plan = canonical([{"k": d["interpretation_key"], "s": d["status"], "fp": d["decision_fingerprint"],
                       "e": d["evidence"]} for d in decisions])
    keyed = canonical(manifest["keyed_classification"])
    # Planen (med evidens-noter) og klassifikationen indlejres i $-quotede DO-blokke; en note med et
    # af tags'ene ville afslutte blokken for tidligt. Fail-closed her i stedet for som syntaksfejl.
    if any(tag in text for tag in DO_TAGS for text in (plan, keyed)):
        raise PackError("PACK_DOLLAR_TAG")
    base = manifest["baseline"]
    n_dec = int(manifest["n_decisions"])
    return _check_tags("\n".join(_head() + [
        _state_guard(manifest, "PROPOSED", "TRANSFER_STATE_NOT_PROPOSED"),
        # (1) Klausulsættet (spec §4.2).
        _quiet_include("transfer_baseline.sql"),
        "DO $c$ BEGIN IF current_setting('daa.transfer_baseline')::jsonb->>'clause_set_sha256' IS DISTINCT FROM "
        f"{_lit(base['clause_set_sha256'])} THEN RAISE EXCEPTION 'CLAUSE_SET_DRIFT'; END IF; END $c$;",
        # (2) Præmissen: nøglet klassifikation i tilstand PROPOSED = pakkens (spec §4.3). Den delte
        # klassifikation ser alle kilder; kun kildens forslag sammenlignes.
        _quiet_include("interpretation_control_classification.sql"),
        "DO $m$ DECLARE r jsonb := current_setting('daa.control_result')::jsonb; f jsonb; "
        f"want jsonb := {_lit(keyed)}::jsonb; BEGIN "
        "SELECT coalesce(jsonb_object_agg(i.interpretation_key::text, jsonb_build_array(x->>'class', "
        "(x->>'assertion_id')::bigint)), '{}'::jsonb) INTO f FROM jsonb_array_elements(r->'items') x "
        "JOIN private.interpretation i ON i.id = (x->>'interpretation_id')::uuid "
        "AND i.source_id = current_setting('daa.src')::bigint; "
        "IF f IS DISTINCT FROM want THEN RAISE EXCEPTION 'MACHINE_PREMISE_DRIFT'; END IF; END $m$;",
        # (3) Fingeraftryk og id-opslag; planen lægges i en GUC, som authenticated kan læse.
        _quiet_include("interpretation_decision_fingerprint.sql"),
        "DO $p$ DECLARE fps jsonb := current_setting('daa.fingerprints')::jsonb; "
        f"plan jsonb := {_lit(plan)}::jsonb; out jsonb; n int; BEGIN "
        "IF EXISTS (SELECT 1 FROM jsonb_array_elements(plan) p WHERE p->>'fp' IS NULL "
        "OR fps->>(p->>'k') IS DISTINCT FROM p->>'fp') THEN RAISE EXCEPTION 'DECISION_FINGERPRINT_MISMATCH'; END IF; "
        "IF (SELECT count(DISTINCT p->>'k') FROM jsonb_array_elements(plan) p) <> jsonb_array_length(plan) "
        "THEN RAISE EXCEPTION 'DECISION_KEY_UNRESOLVED duplicate'; END IF; "
        "SELECT count(*), jsonb_agg(jsonb_build_object('id', ic.id, 's', p->>'s', 'e', "
        f"(p->'e') || jsonb_build_object('pack_sha256', {_lit(pack)}))) INTO n, out "
        "FROM jsonb_array_elements(plan) p JOIN private.interpretation_current ic "
        "ON ic.interpretation_key = (p->>'k')::uuid AND ic.version = 1 AND ic.status = 'proposed' "
        "AND ic.source_id = current_setting('daa.src')::bigint; "
        "IF n <> jsonb_array_length(plan) THEN RAISE EXCEPTION 'DECISION_KEY_UNRESOLVED % af %', "
        "jsonb_array_length(plan) - n, jsonb_array_length(plan); END IF; "
        "PERFORM set_config('daa.decide_plan', out::text, true); END $p$;",
        # (4) Skrivningen.
        *_actor_switch(manifest),
        "DO $w$ DECLARE n int; BEGIN "
        "SELECT count(red_decide_interpretation((x->>'id')::uuid, 1, x->>'s', x->'e')) INTO n "
        "FROM jsonb_array_elements(current_setting('daa.decide_plan')::jsonb) x; "
        f"IF n <> {n_dec} THEN RAISE EXCEPTION 'DECISION_COUNT %', n; END IF; END $w$;",
        *_tail(),
        # (5) Resultatet = pakkens.
        _quiet_include("interpretation_transfer_digests.sql"),
        "DO $d$ DECLARE d jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN "
        f"IF d->>'decision_digest' IS DISTINCT FROM {_lit(manifest['digests']['decision_digest'])} "
        f"OR (d->>'n_decided')::int <> {n_dec} "
        "THEN RAISE EXCEPTION 'DECISION_DIGEST_MISMATCH'; END IF; END $d$;",
        "COMMIT;",
        f"\\echo 'TRANSFER_07_OK afgørelser={n_dec}'",
    ]) + "\n")


def bind_sql(manifest: dict) -> str:
    """08: én transaktion; pakkescope obligatorisk; preview og batch i samme transaktion."""
    _validate_manifest(manifest, "DECIDED")
    scope = canonical(manifest["accepted_keys"])
    n_bind = int(manifest["digests"]["n_bindings"])
    return _check_tags("\n".join(_head() + [
        _state_guard(manifest, "DECIDED", "TRANSFER_STATE_NOT_DECIDED"),
        f"SELECT set_config('daa.transfer_scope', {_lit(scope)}, true) \\g /dev/null",
        # Aktuelle accepterede for kilden = pakkens accepterede nøgler.
        "DO $s$ DECLARE f jsonb; BEGIN "
        "SELECT coalesce(jsonb_agg(interpretation_key::text ORDER BY interpretation_key::text COLLATE \"C\"), '[]') "
        "INTO f FROM private.interpretation_current WHERE source_id = current_setting('daa.src')::bigint "
        "AND status = 'accepted'; "
        "IF f IS DISTINCT FROM current_setting('daa.transfer_scope')::jsonb THEN "
        "RAISE EXCEPTION 'BIND_SCOPE_DRIFT accepted'; END IF; END $s$;",
        # Målfindingen afgrænset til pakkens nøgler; fortolkninger uden for pakken bliver ikke items
        # (spec §6.2/§10) — de tælles kun.
        _quiet_include("interpretation_promotion_targets_scoped.sql"),
        "DO $n$ DECLARE t jsonb := current_setting('daa.targets_scoped')::jsonb; BEGIN "
        f"IF jsonb_array_length(t->'items') <> {n_bind} OR jsonb_array_length(t->'singleton_items') <> 0 "
        "THEN RAISE EXCEPTION 'BIND_SCOPE_DRIFT items=% singleton=%', jsonb_array_length(t->'items'), "
        "jsonb_array_length(t->'singleton_items'); END IF; "
        "RAISE NOTICE 'TRANSFER_08 items=% uden_for_pakken=%', jsonb_array_length(t->'items'), "
        "(t->>'out_of_scope')::int; END $n$;",
        *_actor_switch(manifest),
        "DO $b$ DECLARE items jsonb := current_setting('daa.targets_scoped')::jsonb->'items'; "
        "p jsonb := red_preview_interpretation_promotions(items); BEGIN "
        "IF jsonb_array_length(p->'items') <> jsonb_array_length(items) OR EXISTS (SELECT 1 FROM "
        "jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) "
        "THEN RAISE EXCEPTION 'BIND_NOT_ELIGIBLE'; END IF; "
        "PERFORM red_promote_interpretations_batch(items, p->>'preview_hash'); END $b$;",
        *_tail(),
        _quiet_include("interpretation_transfer_digests.sql"),
        "DO $d$ DECLARE d jsonb := current_setting('daa.transfer_digests')::jsonb; BEGIN "
        f"IF d->>'binding_digest' IS DISTINCT FROM {_lit(manifest['digests']['binding_digest'])} "
        f"OR (d->>'n_bindings')::int <> {n_bind} THEN RAISE EXCEPTION 'BINDING_DIGEST_MISMATCH'; END IF; END $d$;",
        "COMMIT;",
        f"\\echo 'TRANSFER_08_OK bindinger={n_bind}'",
    ]) + "\n")


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
    for name in ("decide-sql", "bind-sql"):
        g = sub.add_parser(name)
        g.add_argument("--pack-dir", required=True)
        g.add_argument("--out", required=True)
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
        elif args.cmd in ("decide-sql", "bind-sql"):
            pdir = Path(args.pack_dir)
            manifest = _load(pdir / "pack-manifest.json")
            if pack_sha256(manifest) != manifest.get("pack_sha256"):
                raise PackError("PACK_SHA_MISMATCH")
            dec_bytes = (pdir / "decisions-keyed.json").read_bytes()
            if hashlib.sha256(dec_bytes).hexdigest() != manifest["decisions_keyed_sha256"]:
                raise PackError("PACK_DECISIONS_SHA_MISMATCH")
            decisions = json.loads(dec_bytes.decode("utf-8"))
            if Path(args.out).exists():
                raise PackError("PACK_OUT_EXISTS")
            sql = decide_sql(decisions, manifest) if args.cmd == "decide-sql" else bind_sql(manifest)
            _write_private(Path(args.out), sql)
            print(f"{args.cmd.upper().replace('-', '_')}_OK pack_sha256={manifest['pack_sha256']} "
                  f"sha256={sha256_text(sql)}")
        else:
            manifest = _load(args.pack_manifest)
            if pack_sha256(manifest) != manifest.get("pack_sha256"):
                raise PackError("PACK_SHA_MISMATCH")
            print(classify_state(_load(args.digests), manifest))
    except FileExistsError:
        print("PACK_OUT_EXISTS")
        return 1
    except PackError as exc:
        print(str(exc))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
