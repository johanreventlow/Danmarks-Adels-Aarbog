#!/usr/bin/env python3
"""Resumérbar, fail-closed fakta-efterudtræk-pipeline for DAA 1939."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import convert_1939_stamtavle as converter
import validate

ROOT = Path(__file__).resolve().parents[4]
WORK = ROOT / "work_1939_stamtavle"
BASELINE = WORK / "clean_1939_v2.json"
RUN = WORK / "efterudtraek_terra"
RESULT = WORK / "clean_1939_v3.json"
REPORT = WORK / "efterudtraek-rapport-2026-07-31.md"
REGISTER = ROOT / "data/identitet/1939.json"
IMMUTABLE = ("narrative", "record_key", "lokal_id", "_lokal_id", "_v2_lokal_id",
             "linje", "nr", "nr_label", "boern", "_boern_link", "_boern_ref")
LIFE_EVENTS = {"fødsel", "dåb", "død", "begravelse"}
ALLOWED_FACT_TYPES = LIFE_EVENTS | {"titel"}


class PipelineError(ValueError):
    pass


@dataclass(frozen=True)
class Issue:
    batch_id: str
    record_key: str | None
    reason: str


def _read(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _write(path: Path, data: Any, *, indent: int = 2) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=indent) + "\n", encoding="utf-8")


def _schema_properties() -> tuple[set[str], set[str], set[str]]:
    schema = _read(Path(__file__).parent / "../references/extraction-schema.json")
    fact = set(schema["properties"]["facts"]["items"]["properties"])
    marriage = set(schema["properties"]["aegteskaber"]["items"]["properties"])
    partner_date = set(schema["$defs"]["datofakta"]["properties"])
    return fact, marriage, partner_date


FACT_FIELDS, MARRIAGE_FIELDS, PARTNER_DATE_FIELDS = _schema_properties()


def _nonempty(value: Any) -> bool:
    return value not in (None, "", [], {})


def _norm_name(value: Any) -> str:
    return re.sub(r"\s+", " ", str(value or "").strip()).casefold()


def _fact_identity(fact: dict) -> tuple[Any, Any]:
    return fact.get("faktatype"), fact.get("date_raw")


def _duplicate_facts(facts: list[dict]) -> bool:
    if not all(isinstance(fact, dict) for fact in facts):
        return False
    identities = [_fact_identity(f) for f in facts]
    return len(identities) != len(set(identities))


def _exact_span(value: Any, narrative: str) -> bool:
    return isinstance(value, str) and bool(value) and value in narrative


def _date_issues(raw: Any, narrative: str, label: str) -> list[str]:
    if not _nonempty(raw):
        return []
    if not isinstance(raw, str) or raw not in narrative:
        return [f"{label} er ikke et eksakt narrative-substring"]
    absent = [year for year in re.findall(r"\d{4}", raw) if year not in narrative]
    if absent:
        return [f"{label} har årstal uden for narrative: {absent}"]
    try:
        info = validate.derive_date_info(raw)
    except Exception as exc:
        return [f"{label} validate.derive_date_info fejlede: {exc}"]
    raw_years = [int(year) for year in re.findall(r"\d{4}", raw)]
    if raw_years:
        for bound in (info.get("date_min"), info.get("date_max")):
            if bound and re.match(r"^\d{4}", str(bound)):
                bound_year = int(str(bound)[:4])
                if not min(raw_years) <= bound_year <= max(raw_years):
                    return [f"{label} afledt grænse modsiger rå årstal"]
    return []


def _matches_type(value: Any, declared: Any) -> bool:
    declared = declared if isinstance(declared, list) else [declared]
    return any((kind == "string" and isinstance(value, str))
               or (kind == "integer" and isinstance(value, int) and not isinstance(value, bool))
               or (kind == "boolean" and isinstance(value, bool))
               or (kind == "array" and isinstance(value, list))
               or (kind == "object" and isinstance(value, dict))
               or (kind == "null" and value is None)
               for kind in declared)


def _shape_issues(value: Any, schema: dict, label: str) -> list[str]:
    if not isinstance(value, dict):
        return [f"{label} skal være object"]
    issues = []
    for required in schema.get("required", []):
        if required not in value:
            issues.append(f"{label} mangler krævet felt {required}")
    properties = schema.get("properties", {})
    for key, item in value.items():
        if key in properties and "type" in properties[key] and not _matches_type(item, properties[key]["type"]):
            issues.append(f"{label}.{key} har forkert type")
    return issues


def _record_issues(record: dict, narrative: str, *, enforce_schema: bool = True) -> list[str]:
    issues: list[str] = []
    if enforce_schema and set(record) != {"record_key", "facts", "aegteskaber"}:
        issues.append("record har andre eller manglende top-level felter")
    facts, marriages = record.get("facts"), record.get("aegteskaber")
    if not isinstance(facts, list) or not isinstance(marriages, list):
        return issues + ["facts og aegteskaber skal være arrays"]
    if _duplicate_facts(facts):
        issues.append("dublet faktaidentitet (faktatype, date_raw)")
    schema = _read(Path(__file__).parent / "../references/extraction-schema.json")
    fact_schema = schema["properties"]["facts"]["items"]
    marriage_schema = schema["properties"]["aegteskaber"]["items"]
    partner_schema = schema["$defs"]["datofakta"]
    for fact in facts:
        if not isinstance(fact, dict):
            issues.append("fact skal være object")
            continue
        if enforce_schema and set(fact) - FACT_FIELDS:
            issues.append("fact har ikke-skema felter")
            continue
        if enforce_schema:
            issues.extend(_shape_issues(fact, fact_schema, "fact"))
        if fact.get("faktatype") not in ALLOWED_FACT_TYPES:
            issues.append(f"fact faktatype er uden for efterudtrækkets målflade: {fact.get('faktatype')}")
        if not _exact_span(fact.get("kilde_span"), narrative):
            issues.append("fact kilde_span er ikke eksakt narrative-substring")
        if fact.get("faktatype") in LIFE_EVENTS and not _nonempty(fact.get("date_raw")):
            issues.append("livsbegivenhed mangler date_raw")
        issues.extend(_date_issues(fact.get("date_raw"), narrative, "fact date_raw"))
    for marriage in marriages:
        if not isinstance(marriage, dict):
            issues.append("ægteskab skal være object")
            continue
        if enforce_schema and set(marriage) - MARRIAGE_FIELDS:
            issues.append("ægteskab har ikke-skema felter")
            continue
        if enforce_schema:
            issues.extend(_shape_issues(marriage, marriage_schema, "ægteskab"))
        if not _exact_span(marriage.get("kilde_span"), narrative):
            issues.append("ægteskab kilde_span er ikke eksakt narrative-substring")
        issues.extend(_date_issues(marriage.get("dato_raw"), narrative, "ægteskab dato_raw"))
        for key in ("partner_foedsel", "partner_daab", "partner_doed"):
            date = marriage.get(key)
            if date is not None:
                if not isinstance(date, dict):
                    issues.append(f"{key} skal være object")
                elif enforce_schema and set(date) - PARTNER_DATE_FIELDS:
                    issues.append(f"{key} har ikke-skema felter")
                else:
                    if enforce_schema:
                        issues.extend(_shape_issues(date, partner_schema, key))
                    issues.extend(_date_issues(date.get("date_raw"), narrative, f"{key} date_raw"))
    return issues


def validate_wrapper(wrapper: dict, batches: dict[str, list[str]], baseline_by_key: dict[str, dict]) -> list[Issue]:
    issues: list[Issue] = []
    required = {"batch_id", "model", "attempt", "records"}
    batch_id = wrapper.get("batch_id") if isinstance(wrapper, dict) else "?"
    if not isinstance(wrapper, dict) or set(wrapper) != required:
        return [Issue(str(batch_id), None, "wrapper har andre eller manglende felter")]
    batch_ok = isinstance(batch_id, str) and batch_id in batches
    attempt = wrapper.get("attempt")
    if not batch_ok or wrapper.get("model") != "gpt-5.6-terra" or type(attempt) is not int or attempt < 1:
        issues.append(Issue(str(batch_id), None, "ugyldig batch/model/attempt"))
    records = wrapper.get("records")
    if not isinstance(records, list):
        return [Issue(str(batch_id), None, "records skal være array")]
    valid_records = []
    for record in records:
        if not isinstance(record, dict):
            issues.append(Issue(str(batch_id), None, "record skal være object"))
        elif not isinstance(record.get("record_key"), str):
            issues.append(Issue(str(batch_id), None, "record_key skal være string"))
        else:
            valid_records.append(record)
    seen = [record["record_key"] for record in valid_records]
    expected = batches[batch_id] if batch_ok else []
    if len(valid_records) != len(records) or set(seen) != set(expected) or len(seen) != len(set(seen)):
        issues.append(Issue(str(batch_id), None, "batchmedlemskab eller record_key-dækning er ikke eksakt"))
    for record in valid_records:
        key = record["record_key"]
        base = baseline_by_key.get(key)
        if base is None:
            issues.append(Issue(batch_id, key, "ukendt record_key"))
            continue
        for reason in _record_issues(record, base["narrative"]):
            issues.append(Issue(batch_id, key, reason))
    return issues


def prepare(baseline_path: Path = BASELINE, run_root: Path = RUN, batch_size: int = 25) -> int:
    records = _read(Path(baseline_path))
    if batch_size < 1:
        raise PipelineError("batch-size skal være positiv")
    for start in range(0, len(records), batch_size):
        number = start // batch_size
        batch = {"batch_id": f"batch-{number:03d}", "records": [
            {"index": i, "record_key": r["record_key"], "narrative": r["narrative"]}
            for i, r in enumerate(records[start:start + batch_size], start=start)]}
        _write(Path(run_root) / "input" / f"batch-{number:03d}.json", batch)
    return (len(records) + batch_size - 1) // batch_size


def _input_batches(run_root: Path) -> dict[str, list[str]]:
    batches = {}
    for path in sorted((Path(run_root) / "input").glob("batch-*.json")):
        data = _read(path)
        batches[data["batch_id"]] = [record["record_key"] for record in data["records"]]
    return batches


def _read_output(path: Path, batch_id: str) -> tuple[Any | None, Issue | None]:
    try:
        value = _read(path)
    except (OSError, json.JSONDecodeError) as exc:
        return None, Issue(batch_id, None, f"ugyldig JSON i output-batch: {exc}")
    if not isinstance(value, dict):
        return None, Issue(batch_id, None, "output-wrapper skal være object")
    return value, None


def check(baseline_path: Path = BASELINE, run_root: Path = RUN, *, expected_count: int = 546) -> list[Issue]:
    baseline = _read(Path(baseline_path))
    by_key = {record.get("record_key"): record for record in baseline}
    issues: list[Issue] = []
    if len(baseline) != expected_count or len(by_key) != expected_count:
        issues.append(Issue("baseline", None, f"baseline skal have præcis {expected_count} unikke keys"))
    try:
        batches = _input_batches(Path(run_root))
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        batches = {}
        issues.append(Issue("input", None, f"ugyldig JSON eller form i input-batch: {exc}"))
    expected = set(by_key)
    batch_keys = [key for keys in batches.values() for key in keys]
    if set(batch_keys) != expected or len(batch_keys) != len(expected):
        issues.append(Issue("input", None, "input-batches dækker ikke baseline eksakt"))
    output_paths = {path.stem: path for path in (Path(run_root) / "output").glob("batch-*.json")}
    if set(output_paths) != set(batches):
        issues.append(Issue("output", None, "output-batches matcher ikke input-batches eksakt"))
    for batch_id, keys in batches.items():
        path = Path(run_root) / "output" / f"{batch_id}.json"
        if not path.exists():
            issues.append(Issue(batch_id, None, "manglende output-batch"))
        else:
            wrapper, issue = _read_output(path, batch_id)
            if issue:
                issues.append(issue)
            else:
                issues.extend(validate_wrapper(wrapper, {batch_id: keys}, by_key))
    retry = [{"batch_id": x.batch_id, "record_key": x.record_key, "reason": x.reason} for x in issues]
    _write(Path(run_root) / "retry.json", retry)
    return issues


def _supplement(old: Any, new: Any) -> tuple[Any, int, int]:
    """Fill only empty leaves; preserve every non-empty old value."""
    if isinstance(old, dict) and isinstance(new, dict):
        result = copy.deepcopy(old)
        count, conflicts = 0, 0
        for key, value in new.items():
            if key not in result or not _nonempty(result[key]):
                if _nonempty(value):
                    result[key] = copy.deepcopy(value)
                    count += 1
            elif isinstance(result[key], dict) and isinstance(value, dict):
                result[key], nested, nested_conflicts = _supplement(result[key], value)
                count += nested
                conflicts += nested_conflicts
            elif _nonempty(value) and result[key] != value:
                conflicts += 1
        return result, count, conflicts
    return copy.deepcopy(old), 0, int(_nonempty(old) and _nonempty(new) and old != new)


def _union_evidence(union: dict) -> bool:
    span, name = union.get("kilde_span"), union.get("partner_navn")
    if not isinstance(span, str) or not _nonempty(name) or str(name) not in span:
        return False
    return bool(re.search(r"\bGift\b|\bg\.\s*|\b(?:viet|ægte)\b|\d\s*°\s*.*\b(?:med|m\.)", span, re.I))


def merge_record(old: dict, new: dict) -> tuple[dict, dict[str, int]]:
    if old.get("record_key") != new.get("record_key"):
        raise PipelineError("record_key mismatch")
    fresh = new.get("facts", [])
    if _duplicate_facts(fresh):
        raise PipelineError("dublet faktaidentitet i nyt output")
    old_facts = old.get("facts", [])
    covered_types = {fact.get("faktatype") for fact in fresh}
    kept = [copy.deepcopy(f) for f in old_facts if f.get("faktatype") not in covered_types]
    all_facts = copy.deepcopy(fresh) + kept
    if _duplicate_facts(all_facts):
        raise PipelineError("dublet faktaidentitet i endeligt output")
    result = copy.deepcopy(old)
    result["facts"] = all_facts
    stats = {"new_facts": len(fresh), "retained_facts": len(kept),
             "replaced_facts": len(old_facts) - len(kept), "supplemented_fields": 0,
             "marriage_conflicts": 0, "marriage_identity_conflicts": 0,
             "marriage_field_conflicts": 0, "accepted_unions": 0, "rejected_unions": 0}
    unions = copy.deepcopy(old.get("aegteskaber", []))
    for candidate in new.get("aegteskaber", []):
        ordinal, name = candidate.get("ordinal"), _norm_name(candidate.get("partner_navn"))
        same_ordinal = [i for i, old_u in enumerate(unions) if old_u.get("ordinal") == ordinal]
        same_name = [i for i, old_u in enumerate(unions) if name and _norm_name(old_u.get("partner_navn")) == name]
        compatible = [i for i in set(same_ordinal + same_name)
                      if unions[i].get("ordinal") == ordinal
                      and (not name or not _norm_name(unions[i].get("partner_navn")) or _norm_name(unions[i].get("partner_navn")) == name)]
        if len(compatible) == 1:
            unions[compatible[0]], count, conflicts = _supplement(unions[compatible[0]], candidate)
            stats["supplemented_fields"] += count
            stats["marriage_field_conflicts"] += conflicts
        elif same_ordinal or same_name:
            stats["marriage_conflicts"] += 1
            stats["marriage_identity_conflicts"] += 1
        elif _union_evidence(candidate):
            unions.append(copy.deepcopy(candidate))
            stats["accepted_unions"] += 1
        else:
            stats["rejected_unions"] += 1
    result["aegteskaber"] = unions[:len(old.get("aegteskaber", []))] + sorted(unions[len(old.get("aegteskaber", [])):], key=lambda x: x.get("ordinal", 0))
    return result, stats


def _wrappers(run_root: Path) -> list[dict]:
    return [_read(path) for path in sorted((Path(run_root) / "output").glob("batch-*.json"))]


def _coverage(records: list[dict]) -> dict[str, int]:
    coverage = {
        fact_type: sum(any(f.get("faktatype") == fact_type for f in record.get("facts", []))
                       for record in records)
        for fact_type in ("fødsel", "dåb", "død", "begravelse", "titel")
    }
    coverage["ægteskab"] = sum(bool(record.get("aegteskaber")) for record in records)
    return coverage


def _batch_provenance(run_root: Path, wrappers: list[dict]) -> tuple[int, int]:
    path = Path(run_root) / "provenance.json"
    try:
        provenance = _read(path)
        reused = provenance["reused_quarantine_batches"]
        fresh = provenance["fresh_terra_batches"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        raise PipelineError(f"ugyldig batch-proveniens: {exc}") from exc
    expected = [wrapper["batch_id"] for wrapper in wrappers]
    combined = reused + fresh if isinstance(reused, list) and isinstance(fresh, list) else []
    if (not all(isinstance(value, str) for value in combined)
            or len(combined) != len(set(combined)) or set(combined) != set(expected)):
        raise PipelineError("batch-proveniens er ikke en eksakt partition af output-batches")
    return len(reused), len(fresh)


def _preserves_nonempty(old: Any, new: Any) -> bool:
    if not _nonempty(old):
        return True
    if isinstance(old, dict):
        return isinstance(new, dict) and all(
            key in new and (not _nonempty(value) or _preserves_nonempty(value, new[key]))
            for key, value in old.items())
    if isinstance(old, list):
        return isinstance(new, list) and old == new
    return old == new


def _merged_issues(baseline: list[dict], merged: list[dict]) -> list[str]:
    errors = []
    if [r.get("record_key") for r in merged] != [r.get("record_key") for r in baseline]:
        errors.append("merge ændrer record_key-dækning eller rækkefølge")
    for old, value in zip(baseline, merged):
        key = old["record_key"]
        if any(value.get(field) != old.get(field) for field in IMMUTABLE):
            errors.append(f"immutable fields ændret: {key}")
        if _duplicate_facts(value.get("facts", [])):
            errors.append(f"dublet facts: {key}")
        old_unions, new_unions = old.get("aegteskaber", []), value.get("aegteskaber", [])
        if len(new_unions) < len(old_unions) or any(
                not _preserves_nonempty(union, new_unions[index])
                for index, union in enumerate(old_unions)):
            errors.append(f"ægteskab ikke strukturelt bevaret: {key}")
    return errors


def _legacy_provenance_issues(baseline: list[dict]) -> int:
    return sum(len(_record_issues({
        "record_key": record["record_key"],
        "facts": record.get("facts", []),
        "aegteskaber": record.get("aegteskaber", []),
    }, record["narrative"], enforce_schema=False)) for record in baseline)


def merge(baseline_path: Path = BASELINE, run_root: Path = RUN, result_path: Path = RESULT,
          report_path: Path = REPORT) -> dict:
    issues = check(baseline_path, run_root)
    if issues:
        raise PipelineError(f"check fejlede: {len(issues)} forhold; se retry.json")
    baseline = _read(Path(baseline_path))
    updates = {record["record_key"]: record for wrapper in _wrappers(Path(run_root)) for record in wrapper["records"]}
    stats = Counter()
    merged = []
    for record in baseline:
        value, local = merge_record(record, updates[record["record_key"]])
        merged.append(value)
        stats.update(local)
    errors = _merged_issues(baseline, merged)
    if errors:
        raise PipelineError(f"merge-validering fejlede: {len(errors)} forhold; {errors[0]}")
    converter.skriv_manifest(merged, Path(result_path))
    wrappers = _wrappers(Path(run_root))
    reused_batches, fresh_batches = _batch_provenance(Path(run_root), wrappers)
    stats.update({"output_batches": len(wrappers), "output_records": sum(len(w["records"]) for w in wrappers),
                  "attempt_sum": sum(w["attempt"] for w in wrappers),
                  "retries": sum(max(w["attempt"] - 1, 0) for w in wrappers),
                  "retry_batches": sum(w["attempt"] > 1 for w in wrappers),
                  "rejected_issues": len(_read(Path(run_root) / "retry.json")),
                  "reused_quarantine_batches": reused_batches,
                  "fresh_terra_batches": fresh_batches,
                  "legacy_provenance_issues": _legacy_provenance_issues(baseline)})
    for label, records in (("before", baseline), ("after", merged)):
        for fact_type, count in _coverage(records).items():
            stats[f"coverage_{label}_{fact_type}"] = count
    numeric = {key: int(value) for key, value in stats.items()}
    _write(Path(run_root) / "merge-stats.json", numeric)
    models = Counter(w["model"] for w in wrappers)
    Path(report_path).parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# 1939 efterudtræk", "",
        f"- Terra output-batches: {numeric['output_batches']}",
        f"- Genbrugte karantæne-batches: {numeric['reused_quarantine_batches']}",
        f"- Friske Terra-batches: {numeric['fresh_terra_batches']}",
        f"- Terra records: {numeric['output_records']}",
        f"- Forsøg i alt: {numeric['attempt_sum']}",
        f"- Retries: {numeric['retries']}",
        f"- Retry-batches: {numeric['retry_batches']}",
        f"- Afviste endelige forhold: {numeric['rejected_issues']}",
        f"- Bevarede legacy-proveniensforhold: {numeric['legacy_provenance_issues']}",
        f"- Model-fordeling: {dict(models)}",
    ]
    for fact_type in ("fødsel", "dåb", "død", "begravelse", "titel", "ægteskab"):
        lines.append(f"- Dækning {fact_type}: {numeric[f'coverage_before_{fact_type}']} -> {numeric[f'coverage_after_{fact_type}']}")
    lines.extend([
        f"- Nye facts: {numeric['new_facts']}",
        f"- Erstattede gamle facts: {numeric['replaced_facts']}",
        f"- Bevarede gamle facts: {numeric['retained_facts']}",
        f"- Supplerede ægteskabsfelter: {numeric['supplemented_fields']}",
        f"- Ægteskabsfeltkonflikter: {numeric['marriage_field_conflicts']}",
        f"- Ægteskabsidentitetskonflikter: {numeric['marriage_identity_conflicts']}",
        f"- Accepterede nye unions: {numeric['accepted_unions']}",
        f"- Afviste nye unions: {numeric['rejected_unions']}", "",
    ])
    Path(report_path).write_text("\n".join(lines), encoding="utf-8")
    return numeric


def verify_result(baseline: list[dict], result: list[dict], result_path: Path, register_path: Path) -> list[str]:
    errors = []
    old_keys, new_keys = [r.get("record_key") for r in baseline], [r.get("record_key") for r in result]
    if len(result) != 546 or len(new_keys) != len(set(new_keys)) or new_keys != old_keys:
        errors.append("546 unikke record_keys i baseline-rækkefølge fejler")
    by_old = {r["record_key"]: r for r in baseline}
    for value in result:
        old = by_old.get(value.get("record_key"))
        if not old:
            continue
        if any(value.get(field) != old.get(field) for field in IMMUTABLE):
            errors.append(f"immutable fields ændret: {value['record_key']}")
        if _duplicate_facts(value.get("facts", [])):
            errors.append(f"dublet facts: {value['record_key']}")
        old_unions, new_unions = old.get("aegteskaber", []), value.get("aegteskaber", [])
        if len(new_unions) < len(old_unions) or any(
                not _preserves_nonempty(union, new_unions[index])
                for index, union in enumerate(old_unions)):
            errors.append(f"ægteskab ikke strukturelt bevaret: {value['record_key']}")
    register = _read(Path(register_path))
    active = {p["book_post_id"] for p in register.get("poster", []) if p.get("status") == "aktiv" and p.get("udgave") == "1939"}
    if not set(new_keys).issubset(active):
        errors.append("record_keys er ikke alle aktive 1939-registerkeys")
    manifest_path = Path(str(result_path) + ".manifest.json")
    if not manifest_path.exists():
        errors.append("manifest mangler")
    else:
        manifest = _read(manifest_path)
        expected = hashlib.sha256(Path(result_path).read_bytes()).hexdigest()
        if manifest != {"artefakt": Path(result_path).name, "sha256": expected, "rene": 546, "flaggede": 0, "andel_rene": 1.0}:
            errors.append("manifest-gate eller sha256 fejler")
    return errors


def verify(baseline_path: Path = BASELINE, run_root: Path = RUN, result_path: Path = RESULT,
           register_path: Path = REGISTER) -> list[str]:
    issues = check(baseline_path, run_root)
    if issues:
        return [f"check: {issue.reason}" for issue in issues]
    baseline = _read(Path(baseline_path))
    result = _read(Path(result_path))
    errors = verify_result(baseline, result, Path(result_path), Path(register_path))
    updates = {record["record_key"]: record
               for wrapper in _wrappers(Path(run_root)) for record in wrapper["records"]}
    expected = [merge_record(record, updates[record["record_key"]])[0] for record in baseline]
    if result != expected:
        errors.append("resultat matcher ikke deterministisk merge af baseline og valideret Terra-output")
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("prepare", "check", "merge", "verify", "all"))
    parser.add_argument("--baseline", type=Path, default=BASELINE)
    parser.add_argument("--run", type=Path, default=RUN)
    parser.add_argument("--result", type=Path, default=RESULT)
    parser.add_argument("--report", type=Path, default=REPORT)
    parser.add_argument("--register", type=Path, default=REGISTER)
    parser.add_argument("--batch-size", type=int, default=25)
    args = parser.parse_args(argv)
    if args.command == "prepare":
        print(prepare(args.baseline, args.run, args.batch_size)); return 0
    if args.command == "check":
        errors = check(args.baseline, args.run)
    elif args.command == "merge":
        merge(args.baseline, args.run, args.result, args.report); return 0
    elif args.command == "verify":
        errors = verify(args.baseline, args.run, args.result, args.register)
    else:
        errors = check(args.baseline, args.run)
        if not errors:
            merge(args.baseline, args.run, args.result, args.report)
            errors = verify(args.baseline, args.run, args.result, args.register)
    if errors:
        for error in errors:
            print(error)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
