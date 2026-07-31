#!/usr/bin/env python3
"""Fail-closed build helpers for the 1939-v2 replacement artifact.

The command-line orchestration is deliberately kept in this module so the
work artifact can be reproduced without manual JSON editing.  Work files may
contain person data and must never be committed.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import shutil
import sys
from collections import Counter
from pathlib import Path
from typing import Iterable

import afstem_v2
import convert_1939_stamtavle as converter
from identitetsregister import Register, mint, reconcile
from omnoegl_lokator import PREFIX, _norm
from segment_1939 import clean_1939_text


def filter_duplicate_summaries(records: Iterable[dict]) -> tuple[list[dict], list[dict]]:
    """Remove only records explicitly classified as duplicate summaries."""
    usable, removed = [], []
    for record in records:
        (removed if record.get("dublet_af_stamtavle") else usable).append(record)
    return usable, removed


def _direct_calamari_matches(record: dict, calamari: dict[str, dict]) -> list[str]:
    raw = _norm(record.get("raw_text"))
    prefix = raw[:PREFIX]
    matches = []
    for match_id, candidate in calamari.items():
        narrative = _norm(candidate.get("narrative"))
        windows = [part for part in (narrative[:PREFIX], narrative[120:120 + PREFIX])
                   if len(part) >= 40]
        if ((len(prefix) >= 40 and prefix in narrative)
                or any(window in raw for window in windows)):
            matches.append(str(match_id))
    return matches


def choose_narrative(record: dict, calamari: dict[str, dict], *,
                     bridged_calamari_id: str | None = None) -> tuple[str, str, str | None]:
    """Choose Calamari only with one direct match or an approved text bridge.

    ``bridged_calamari_id`` is supplied only when the old artifact record was
    itself bound to that Calamari record and old->v2 passed the existing text
    anchor.  A missing, empty, or unknown bridge fails closed to direct match
    and ultimately raw text.
    """
    if bridged_calamari_id is not None:
        candidate = calamari.get(str(bridged_calamari_id))
        if candidate and candidate.get("narrative"):
            return candidate["narrative"], "calamari", str(bridged_calamari_id)
    matches = _direct_calamari_matches(record, calamari)
    if len(matches) == 1:
        match_id = matches[0]
        return calamari[match_id]["narrative"], "calamari", match_id
    return record["raw_text"], "raw", None


def mint_new_records(reg: Register, records: Iterable[dict], udgave: str,
                     *, expected_new: int) -> tuple[Register, int]:
    """Mint precisely the current reconcile ``new`` set and nothing else."""
    records = list(records)
    before = reconcile(reg, records, udgave)
    if before.tvetydige:
        raise ValueError(f"mint afvist: {len(before.tvetydige)} tvetydige")
    if len(before.nye) != expected_new:
        raise ValueError(f"forventede {expected_new} nye, fandt {len(before.nye)}")
    updated = Register.from_json(__import__("json").loads(reg.to_json()))
    mint(updated, before.nye, udgave)
    return updated, len(before.nye)


def attach_record_keys(reg: Register, records: Iterable[dict], udgave: str) -> list[dict]:
    """Return copies with complete, unique register book_post_id coverage."""
    records = list(records)
    result = reconcile(reg, records, udgave)
    if result.tvetydige or result.nye or len(result.entydige) != len(records):
        raise ValueError(
            "record_key-dækning fejler: "
            f"entydige={len(result.entydige)} tvetydige={len(result.tvetydige)} "
            f"nye={len(result.nye)} poster={len(records)}")
    key_by_locator = {
        (str(record.get("side") or record.get("sider")).split("-", 1)[0],
         str(record["lokal_id"])): book_post_id
        for record, book_post_id in result.entydige
    }
    attached = []
    for record in records:
        clone = copy.deepcopy(record)
        locator = (str(record.get("side") or record.get("sider")).split("-", 1)[0],
                   str(record["lokal_id"]))
        clone["record_key"] = key_by_locator[locator]
        attached.append(clone)
    keys = [record["record_key"] for record in attached]
    if len(keys) != len(set(keys)):
        raise ValueError("record_key-dækning fejler: dublette book_post_id'er")
    return attached


_LEADING_STRUCTURE_RE = re.compile(
    r"^\s*(?:\?\s*)?(?:(?:\d{1,3}[A-Za-z]?|[IVXLCDM]+|[A-ZÆØÅ])\s*[.)]\s*)+",
    re.IGNORECASE,
)
_TITLE_RE = re.compile(
    r"^(?:(?:Hr|Fru|Frøken|Greve|Grevinde|Komtesse|Baron|Baronesse)\.?(?:\s+|$))+",
    re.IGNORECASE,
)
_NAME_END_RE = re.compile(
    r"\s+(?:til|var|blev|nævnes|nævnt|gift|døde|født)\b|[,;(†+]",
    re.IGNORECASE,
)


def deterministic_name(record: dict) -> str:
    """Extract only the bounded leading source label; otherwise stop."""
    text = clean_1939_text(str(record.get("raw_text") or "")).strip()
    text = _LEADING_STRUCTURE_RE.sub("", text)
    text = _TITLE_RE.sub("", text).strip()
    end = _NAME_END_RE.search(text)
    candidate = (text[:end.start()] if end else text).strip(" .:–—-")
    # Without a delimiter, accepting a sentence as a name would fabricate data.
    if end is None or not (2 <= len(candidate) <= 120) or not re.search(r"[A-Za-zÆØÅæøå]", candidate):
        raise ValueError(f"navn kunne ikke udledes fail-closed for {record.get('lokal_id', '?')}")
    return candidate


def build_linked_v2(old_linked: list[dict], records: list[dict],
                    narratives: dict[str, dict]) -> tuple[list[dict], dict[str, dict], dict[str, int]]:
    """Build converter input while retaining numbered-record regression data.

    Existing structured fields are carried as the regression baseline.  They
    are marked ``efterudtraek`` unless byte-identical narrative comparison
    explicitly permits reuse.  New records contain only a deterministic name
    and are likewise marked; no facts are invented.
    """
    records_by_key = {record["record_key"]: record for record in records}
    old_keys = {record.get("record_key") for record in old_linked if record.get("record_key")}
    linked = copy.deepcopy(old_linked)
    narrative_map: dict[str, dict] = {}
    stats = {"genbrugt": 0, "nyudtraek": 0, "efterudtraek": 0}

    for old in linked:
        key = old.get("record_key")
        current = records_by_key.get(key)
        if current is None:
            continue
        info = narratives[key]
        old["fjernet"] = False
        old["_fakta_status"] = "genbrugt" if info.get("reuse_facts") else "efterudtraek"
        old["_narrativ_kilde"] = info["source"]
        old["_v2_lokal_id"] = current["lokal_id"]
        stats[old["_fakta_status"]] += 1
        narrative_map[str(old["_id"])] = {
            "narrative": info["narrative"],
            "side": current.get("side") or current.get("sider"),
            "metode": info["source"],
        }

    next_id = max((int(record["_id"]) for record in linked), default=0)
    for current in records:
        key = current["record_key"]
        if key in old_keys:
            continue
        next_id += 1
        info = narratives[key]
        try:
            name = deterministic_name(current)
        except ValueError:
            name = None
        linked.append({
            "_id": next_id,
            "_window": None,
            "_ctx": {
                # No structured extraction => do not let this record become a
                # parent candidate and perturb established family links.
                "linje": None,
                "slaegtled": None,
                "gruppe": None,
                "foraeldre_note": None,
            },
            "record_key": key,
            "lokal_id": current["lokal_id"],
            "nr": current.get("nr"),
            "navn": name,
            "koen": None,
            "fjernet": False,
            "_fakta_status": "efterudtraek",
            "_narrativ_kilde": info["source"],
            "_v2_lokal_id": current["lokal_id"],
        })
        stats["efterudtraek"] += 1
        narrative_map[str(next_id)] = {
            "narrative": info["narrative"],
            "side": current.get("side") or current.get("sider"),
            "metode": info["source"],
        }
    return linked, narrative_map, stats


_REGRESSION_ALLOWED = {
    "narrative", "sider", "_fakta_status", "_narrativ_kilde", "_v2_lokal_id",
}


def assert_known_regression_lock(old_clean: list[dict], new_clean: list[dict],
                                 known_keys: set[str]) -> None:
    """Require every known record's loader-facing output to remain stable."""
    old_by_key = {record.get("record_key"): record for record in old_clean}
    new_by_key = {record.get("record_key"): record for record in new_clean}
    failures = []
    for key in known_keys:
        old, new = old_by_key.get(key), new_by_key.get(key)
        if old is None or new is None:
            failures.append(key)
            continue
        old_cmp = {k: v for k, v in old.items() if k not in _REGRESSION_ALLOWED}
        new_cmp = {k: v for k, v in new.items() if k not in _REGRESSION_ALLOWED}
        if old_cmp != new_cmp:
            failures.append(key)
    if failures:
        raise ValueError(f"regressionslås fejler for {len(failures)}/{len(known_keys)} kendte poster")


ROOT = Path(__file__).resolve().parents[4]
WORK = ROOT / "work_1939_stamtavle"
REGISTER = WORK / "identitetsregister-1939.json"
SYNC_REGISTER = ROOT / "data" / "identitet" / "1939.json"
POSTS_PATH = WORK / "posts_1939_v2.json"
NARRATIVES_PATH = WORK / "narrative_1939_v2.json"
LINKED_PATH = WORK / "linked_clean_1939_v2.json"
CLEAN_PATH = WORK / "clean_1939_v2.json"
REPORT_PATH = WORK / "clean_1939_v2.report.json"


def _read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, value, *, indent: int = 2) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=indent) + "\n", encoding="utf-8")


def _locator_key(record: dict) -> str:
    side = str(record.get("side") or record.get("sider")).split("-", 1)[0]
    return f"{side}|{record['lokal_id']}"


def prepare() -> dict:
    segmented = afstem_v2._segmenter_v2(WORK / "raw.txt")
    usable, duplicates = filter_duplicate_summaries(segmented)
    if (len(segmented), len(duplicates), len(usable)) != (553, 7, 546):
        raise ValueError(
            f"segmenttal fejler: total={len(segmented)} dubletter={len(duplicates)} "
            f"brugbare={len(usable)}")

    reg = Register.from_json(_read(REGISTER))
    rc = reconcile(reg, usable, "1939")
    counts = (len(rc.entydige), len(rc.tvetydige), len(rc.nye), len(rc.bortfaldne))
    if counts != (491, 0, 55, 23):
        raise ValueError(f"pre-mint reconcile fejler: {counts}")
    old_clean = _read(WORK / "clean_1939.json")
    old_by_key = {record["record_key"]: record for record in old_clean}
    known_by_locator = {_locator_key(record): key for record, key in rc.entydige}
    calamari = _read(WORK / "narrative_1939_calamari.json")

    selected = {}
    source_counts = Counter()
    facts_counts = Counter()
    for record in usable:
        record_key = known_by_locator.get(_locator_key(record))
        old = old_by_key.get(record_key) if record_key else None
        bridge_id = None
        if old is not None and afstem_v2._tekstanker(old, record):
            bridge_id = str(old["_id"])
        narrative, source, match_id = choose_narrative(
            record, calamari, bridged_calamari_id=bridge_id)
        # A direct match for a known record must agree with its existing
        # Calamari binding; otherwise it is not an identity cross-check.
        if old is not None and bridge_id is None and match_id != str(old["_id"]):
            narrative, source, match_id = record["raw_text"], "raw", None
        reuse = bool(old is not None and old.get("narrative") == narrative)
        facts_status = "genbrugt" if reuse else "efterudtraek"
        selected[_locator_key(record)] = {
            "record_key": record_key,
            "narrative": narrative,
            "source": source,
            "match_id": match_id,
            "reuse_facts": reuse,
            "facts_status": facts_status,
        }
        source_counts[source] += 1
        facts_counts[facts_status] += 1

    _write(POSTS_PATH, usable, indent=1)
    _write(NARRATIVES_PATH, selected, indent=1)
    report = {
        "phase": "prepare",
        "segment_total": len(segmented),
        "duplicate_filtered": len(duplicates),
        "posts": len(usable),
        "reconcile": dict(zip(("entydige", "tvetydige", "nye", "bortfaldne"), counts)),
        "narrative_sources": dict(source_counts),
        "facts": {
            "genbrugt": facts_counts["genbrugt"],
            "nyudtraek": 0,
            "efterudtraek": facts_counts["efterudtraek"],
        },
    }
    _write(REPORT_PATH, report)
    return report


def mint_phase() -> dict:
    if REGISTER.read_bytes() != SYNC_REGISTER.read_bytes():
        raise ValueError("work-register og data/identitet/1939.json er ikke synkroniserede før mint")
    records = _read(POSTS_PATH)
    original_bytes = REGISTER.read_bytes()
    original = Register.from_json(json.loads(original_bytes))
    updated, minted_count = mint_new_records(original, records, "1939", expected_new=55)
    before_by_id = {post.book_post_id: post for post in original.poster.values()}
    after_by_id = {post.book_post_id: post for post in updated.poster.values()}
    for book_post_id, before in before_by_id.items():
        after = after_by_id.get(book_post_id)
        if after is None or after.lokator != before.lokator or after.status != before.status \
                or after.begrundelse != before.begrundelse:
            raise ValueError("mint ville ændre en eksisterende registerpost")

    backup = WORK / "identitetsregister-1939.pre-mint-2026-07-31.bak.json"
    if backup.exists():
        raise ValueError(f"backup findes allerede: {backup}")
    shutil.copy2(REGISTER, backup)
    rendered = (updated.to_json() + "\n").encode("utf-8")
    REGISTER.write_bytes(rendered)
    SYNC_REGISTER.write_bytes(rendered)

    rc = reconcile(updated, records, "1939")
    counts = (len(rc.entydige), len(rc.tvetydige), len(rc.nye), len(rc.bortfaldne))
    if counts != (546, 0, 0, 23):
        raise ValueError(f"post-mint reconcile fejler: {counts}")
    report = {
        "phase": "mint",
        "minted": minted_count,
        "backup": backup.name,
        "reconcile": dict(zip(("entydige", "tvetydige", "nye", "bortfaldne"), counts)),
        "register_sha256": hashlib.sha256(rendered).hexdigest(),
    }
    _write(REPORT_PATH, {**_read(REPORT_PATH), **report})
    return report


def artifact_phase() -> dict:
    records = _read(POSTS_PATH)
    reg = Register.from_json(_read(REGISTER))
    attached = attach_record_keys(reg, records, "1939")
    selected_by_locator = _read(NARRATIVES_PATH)
    selected_by_key = {}
    for record in attached:
        info = selected_by_locator[_locator_key(record)]
        selected_by_key[record["record_key"]] = info

    old_linked = _read(WORK / "linked_clean.json")
    linked, narrative_map, facts_stats = build_linked_v2(
        old_linked, attached, selected_by_key)
    _write(LINKED_PATH, linked, indent=1)

    # Use the old raw narrative map only for structural scope computation;
    # selected v2 narratives are merged after conversion and cannot perturb
    # the 491 known records' non-narrative output.
    structural_map = _read(WORK / "narrative_1939.json")
    converted = converter.convert_all(linked, rapport={}, narrative_map=structural_map)
    wanted_keys = {record["record_key"] for record in attached}
    converted = [record for record in converted if record.get("record_key") in wanted_keys]
    merged, missing = converter.flet_narrative(converted, NARRATIVES_PATH, narrative_map=narrative_map)
    if missing or merged != 546:
        raise ValueError(f"narrativdækning fejler: flettet={merged} mangler={len(missing)}")
    if len(converted) != 546:
        raise ValueError(f"convert-output fejler: {len(converted)} poster")

    old_clean = _read(WORK / "clean_1939.json")
    known_keys = {record["record_key"] for record in attached
                  if any(old.get("record_key") == record["record_key"] for old in old_clean)}
    if len(known_keys) != 491:
        raise ValueError(f"kendt regressionsmængde fejler: {len(known_keys)}")
    assert_known_regression_lock(old_clean, converted, known_keys)
    manifest = converter.skriv_manifest(converted, CLEAN_PATH)
    if manifest["andel_rene"] < 0.90:
        raise ValueError(f"manifest-gate rød: {manifest['andel_rene']}")

    missing_names = sum(not record.get("navn") for record in converted)
    report = {
        "phase": "artifact",
        "posts": len(converted),
        "record_keys": len({record["record_key"] for record in converted}),
        "facts": facts_stats,
        "names_missing_after_deterministic_extraction": missing_names,
        "manifest": manifest,
        "known_regression_locked": len(known_keys),
    }
    _write(REPORT_PATH, {**_read(REPORT_PATH), **report})
    return report


def verify_phase() -> dict:
    records = _read(CLEAN_PATH)
    manifest = _read(Path(str(CLEAN_PATH) + ".manifest.json"))
    clean_bytes = CLEAN_PATH.read_bytes()
    reg = Register.from_json(_read(REGISTER))
    active = {post.book_post_id for post in reg.poster.values() if post.status == "aktiv"}
    tomb = {post.book_post_id for post in reg.poster.values() if post.status == "tombstone"}
    keys = [record.get("record_key") for record in records]
    locators = [record.get("_v2_lokal_id") for record in records]
    failures = {
        "posts": len(records) != 546,
        "missing_record_key": any(not key for key in keys),
        "duplicate_record_key": len(keys) != len(set(keys)),
        "unknown_record_key": bool(set(keys) - active),
        "tombstoned_record_key": bool(set(keys) & tomb),
        "duplicate_locator": len(locators) != len(set(locators)),
        "manifest_hash": hashlib.sha256(clean_bytes).hexdigest() != manifest.get("sha256"),
        "manifest_gate": manifest.get("andel_rene", 0) < 0.90,
    }
    failed = [key for key, value in failures.items() if value]
    if failed:
        raise ValueError("slutverifikation fejler: " + ", ".join(failed))
    report = {
        "phase": "verify",
        "posts": len(records),
        "unique_record_keys": len(set(keys)),
        "unique_locators": len(set(locators)),
        "replace_dryrun_compatible": True,
        "manifest_gate": manifest["andel_rene"],
    }
    _write(REPORT_PATH, {**_read(REPORT_PATH), **report})
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("prepare", "mint", "artifact", "verify"))
    args = parser.parse_args(argv)
    result = {
        "prepare": prepare,
        "mint": mint_phase,
        "artifact": artifact_phase,
        "verify": verify_phase,
    }[args.phase]()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
