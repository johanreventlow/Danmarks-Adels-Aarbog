"""Find baseline records whose printed record boundary sits in the wrong place.

The 1939 baseline was cut by a parser, and a lost period or a lost letterspaced
name can move a cut into the middle of a biography.  The symptom always comes in
one of two shapes, both derived from the printed sibling numbering the baseline
already carries (``_orig_nr`` inside ``_gruppe_nr``):

``graensefejl_par``
    A record contains a later sibling's printed head, and that sibling starts
    mid-sentence without its own head.  The cut between the two sits too late.
``mangler_eget_hoved``
    A record does not open with its own printed head, but no sibling admits to
    holding it.  The head is lost somewhere else, or the name is unrecognisable.
``delt_narrativ``
    Two or more records carry the exact same narrative.  The cut did not divide
    the text, it duplicated it, so at most one of them owns what it says.

Matching is OCR-tolerant on names (letterspacing plus the confusable glyphs this
scan measured in the 1939 rendition) and strict on numbers, so a printed date
continuation like ``23 s. M.`` can never pose as a sibling head.  The scan reads
the baseline only; it never guesses a repair.

**The result is a floor, not a census.** Only boundaries that slipped *forward*
are provable this way: a head has to survive somewhere as a printed number plus
its own name.  A head that slipped backwards, or that OCR destroyed entirely, is
invisible here — which is why an orphan can appear without any swallower.
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
from collections.abc import Mapping, Sequence
from pathlib import Path


class BoundaryDefectError(ValueError):
    pass


# Glyph substitutions inside letterspaced names.  ``1``→``l`` (the same fix
# ``segment_1939.clean_1939_text`` applies), ``î``→``f`` and ``q``→``g`` were
# measured in this rendition; the remaining digit shapes are conventional.
# Digits that carry printed numbering are stripped before folding, so mapping a
# digit here can never disturb a record number.
_CONFUSABLE = str.maketrans({
    "1": "l", "0": "o", "5": "s", "8": "b",
    "î": "f", "ï": "i", "í": "i", "ì": "i",
    "q": "g", "|": "l", "!": "l",
})
_NAME_TOKEN_RE = re.compile(r"[^\W\d_]{3,}", re.UNICODE)
# The printed head often carries a rank before the name.  Stripping the rank is
# what keeps "6. Comtesse Wilhelmine Juliane" out of the defect list.
_TITEL_RE = re.compile(
    r"^(?:(?:Greve|Grevinde|Comtesse|Komtesse|Baron|Baronesse|Friherre|"
    r"Lensgreve|Hr|Fru|Frøken|Jomfru|Frk)\.?\s+){1,2}",
    re.I | re.UNICODE,
)
# A printed head inside a narrative: the sibling's number, then its name.
_EMBEDDED_HEAD_RE = re.compile(r"(?<![\d.,])\b(\d{1,3})\s*[a-z]?\.?\s+(\S.{0,44})")
_HEAD_WINDOW = 90
_NAME_PREFIX = 4
# Short shared strings ("† ung.", "N. N.") are legitimately repeated across
# siblings; a shared narrative only means something once it carries content.
_SHARED_MIN_CHARS = 30
# A dropped or garbled initial ("ilhelmine" for "Wilhelmine", "MWancy" for
# "Nancy") still leaves the printed head recognisable.  0.7 is a default, not a
# fitted value: on this rendition the flag count barely moves between 0.6 and
# 0.8, so the two populations sit far apart and the exact cut hardly matters.
_HEAD_SIMILARITY = 0.7


def fold_ocr(text: object) -> str:
    """Fold a printed name onto a comparable form, keeping Danish letters.

    Dropping every non-letter also collapses letterspacing, so ``H e n r i c h``
    and ``Henrich`` fold onto the same string without a separate despacing pass.
    """
    if not isinstance(text, str):
        raise BoundaryDefectError("tekst skal være en streng")
    lowered = text.lower().translate(_CONFUSABLE)
    return re.sub(r"[^a-zæøåöüä]", "", lowered)


def _record(value: object, index: int) -> Mapping:
    if not isinstance(value, Mapping):
        raise BoundaryDefectError(f"baseline-post {index} skal være en mapping")
    key = value.get("record_key")
    if not isinstance(key, str) or not key:
        raise BoundaryDefectError(f"baseline-post {index} mangler record_key")
    return value


def _name_stem(navn: object) -> str:
    """Return the folded start of the first real name token, or '' if none."""
    if not isinstance(navn, str):
        return ""
    stripped = re.sub(r"\[[^\]]*\]|\([^)]*\)|\?", " ", navn)
    for token in _NAME_TOKEN_RE.findall(stripped):
        folded = fold_ocr(token)
        if len(folded) >= _NAME_PREFIX:
            return folded[:_NAME_PREFIX]
    return ""


def _printed_number(record: Mapping) -> int | None:
    """Read the printed sibling number, which the baseline stores as int or str."""
    value = record.get("_orig_nr")
    if isinstance(value, bool):
        return None
    if isinstance(value, str):
        value = int(value) if value.strip().isdigit() else None
    if not isinstance(value, int) or value < 1:
        return None
    return value


def _branch(record: Mapping) -> object:
    """Name the printed branch: ``_v2_lokal_id`` without its trailing number."""
    lokal_id = record.get("_v2_lokal_id")
    if isinstance(lokal_id, str) and "." in lokal_id:
        return lokal_id.rsplit(".", 1)[0]
    return lokal_id


def _group_key(record: Mapping) -> object:
    """Identify the sibling set: the group number, else the printed branch.

    55 baseline records carry no ``_gruppe_nr``.  Their ``_v2_lokal_id`` still
    ends in the printed number, so the part before it names the branch and keeps
    an unrelated branch's number 8 from posing as this branch's sibling.
    """
    gruppe = record.get("_gruppe_nr")
    return ("gruppe", gruppe) if gruppe is not None else ("gren", _branch(record))


def _folded_name(navn: object) -> str:
    """Fold the first name tokens into one comparable string."""
    if not isinstance(navn, str):
        return ""
    stripped = re.sub(r"\[[^\]]*\]|\([^)]*\)|\?", " ", navn)
    return fold_ocr(" ".join(_NAME_TOKEN_RE.findall(stripped)[:3]))[:20]


def _head_window(record: Mapping, text: object) -> str:
    """Return the text opening with printed number and rank removed."""
    if not isinstance(text, str):
        return ""
    window = text.lstrip()[:_HEAD_WINDOW]
    number = _printed_number(record)
    if number is not None:
        window = re.sub(rf"^\(?\??\s*{number}\s*[a-z]?[.,)]?\s*", "", window)
    return _TITEL_RE.sub("", window.lstrip())


def _opens_with_own_head(record: Mapping, text: object) -> bool:
    """True when the supplied text opens with this record's printed head."""
    if not isinstance(text, str) or not text.strip():
        return True
    stem = _name_stem(record.get("navn"))
    if not stem:
        return True
    folded = fold_ocr(_head_window(record, text))
    if stem in folded[:60]:
        return True
    name = _folded_name(record.get("navn"))
    if not name:
        return True
    ratio = difflib.SequenceMatcher(None, name, folded[:len(name)]).ratio()
    return ratio >= _HEAD_SIMILARITY


def _swallowed_heads(record: Mapping, text: object,
                     siblings: Sequence[Mapping]) -> list[dict]:
    """Find later siblings' printed heads sitting inside the supplied text."""
    if not isinstance(text, str) or not text.strip():
        return []
    own = _printed_number(record)
    if own is None:
        return []
    later = {}
    for sibling in siblings:
        number = _printed_number(sibling)
        stem = _name_stem(sibling.get("navn"))
        if number is not None and number > own and stem:
            later.setdefault(number, (sibling, stem))
    if not later:
        return []
    found: dict[int, dict] = {}
    # One pass over the narrative: every printed number followed by text.  A hit
    # only counts when the text is that sibling's own name, which is what keeps
    # a date continuation like '23 s. M.' out of the results.
    for match in _EMBEDDED_HEAD_RE.finditer(text):
        if match.start() == 0:
            continue
        number = int(match.group(1))
        if number in found or number not in later:
            continue
        sibling, stem = later[number]
        if not fold_ocr(match.group(2)).startswith(stem):
            continue
        found[number] = {
            "sibling_record_key": sibling.get("record_key"),
            "sibling_navn": sibling.get("navn"),
            "sibling_orig_nr": number,
            "position": match.start(),
            "swallowed_head": match.group(0).strip()[:60],
        }
    return sorted(found.values(), key=lambda entry: entry["position"])


def _identity(record: Mapping) -> dict:
    return {
        "record_key": record["record_key"],
        "navn": record.get("navn"),
        "sider": record.get("sider"),
        "_orig_nr": _printed_number(record),
        "_v2_lokal_id": record.get("_v2_lokal_id"),
    }


def find_boundary_defects(baseline: object) -> dict:
    """Report every boundary defect the printed numbering can prove."""
    if not isinstance(baseline, list):
        raise BoundaryDefectError("baseline skal være en liste")
    records = [_record(value, index) for index, value in enumerate(baseline)]
    by_group: dict[object, list[Mapping]] = {}
    for record in records:
        by_group.setdefault(_group_key(record), []).append(record)

    missing_head = {
        record["record_key"] for record in records
        if _printed_number(record) is not None
        and not _opens_with_own_head(record, record.get("narrative"))
    }
    pairs: list[dict] = []
    swallowed_only: list[dict] = []
    paired_orphans: set[str] = set()
    for record in records:
        siblings = by_group.get(_group_key(record), [])
        for hit in _swallowed_heads(record, record.get("narrative"), siblings):
            entry = {
                "gruppe_nr": record.get("_gruppe_nr"),
                "gren": _branch(record),
                "swallower": _identity(record),
                "orphan": _identity(next(
                    sibling for sibling in siblings
                    if sibling["record_key"] == hit["sibling_record_key"]
                )),
                "position": hit["position"],
                "swallowed_head": hit["swallowed_head"],
            }
            if hit["sibling_record_key"] in missing_head:
                paired_orphans.add(hit["sibling_record_key"])
                pairs.append(entry)
            else:
                swallowed_only.append(entry)

    orphans = [
        _identity(record) for record in records
        if record["record_key"] in missing_head - paired_orphans
    ]
    shared: dict[str, list[Mapping]] = {}
    for record in records:
        narrative = record.get("narrative")
        if isinstance(narrative, str) and len(narrative.strip()) >= _SHARED_MIN_CHARS:
            shared.setdefault(narrative.strip(), []).append(record)
    shared_groups = [
        {"tegn": len(narrative), "poster": [_identity(record) for record in group]}
        for narrative, group in shared.items() if len(group) > 1
    ]
    return {
        "summary": {
            "poster": len(records),
            "graensefejl_par": len(pairs),
            "slugt_hoved": len(swallowed_only),
            "mangler_eget_hoved": len(orphans),
            "delt_narrativ": len(shared_groups),
        },
        "graensefejl_par": pairs,
        "slugt_hoved": swallowed_only,
        "mangler_eget_hoved": orphans,
        "delt_narrativ": shared_groups,
    }


def suggested_reason(pair: Mapping) -> str:
    """Compose the greppable Danish begrundelse for the review UI."""
    if not isinstance(pair, Mapping) or "swallower" not in pair or "orphan" not in pair:
        raise BoundaryDefectError("par mangler swallower/orphan")
    swallower, orphan = pair["swallower"], pair["orphan"]
    return (
        "GRÆNSEFEJL: Postgrænsen mellem nr. "
        f"{swallower['_orig_nr']} {swallower['navn']} og nr. "
        f"{orphan['_orig_nr']} {orphan['navn']} sidder for sent. "
        f"Hovedet “{pair['swallowed_head']}” ligger inde i nr. "
        f"{swallower['_orig_nr']}s tekst, og nr. {orphan['_orig_nr']} starter "
        "midt i en sætning. Ingen kandidat afgrænser posten alene."
    )


def write_report(report: Mapping, out: Path) -> None:
    """Write the report, refusing to overwrite an earlier scan."""
    if not isinstance(report, Mapping) or "summary" not in report:
        raise BoundaryDefectError("rapport mangler summary")
    with Path(out).open("x", encoding="utf-8") as handle:
        json.dump(report, handle, ensure_ascii=False, indent=2)
        handle.write("\n")


def _markdown(report: Mapping) -> str:
    lines = [
        "# Grænsefejl i 1939-baselinen",
        "",
        f"- Poster scannet: {report['summary']['poster']}",
        f"- Grænsefejl-par (hoved slugt + forældreløs post): {report['summary']['graensefejl_par']}",
        f"- Slugt hoved uden forældreløs modpart: {report['summary']['slugt_hoved']}",
        f"- Mangler eget hoved uden kendt sluger: {report['summary']['mangler_eget_hoved']}",
        f"- Delt narrativ (samme tekst på flere poster): {report['summary']['delt_narrativ']}",
        "",
        "Listen er et **gulv, ikke en optælling**: kun grænser der er skredet",
        "fremad kan bevises af den trykte nummerering. Et hoved der er skredet",
        "bagud, eller som OCR har ødelagt helt, er usynligt her.",
        "",
    ]
    if report["graensefejl_par"]:
        lines += ["## Grænsefejl-par", ""]
        for pair in report["graensefejl_par"]:
            lines += [
                f"### nr. {pair['swallower']['_orig_nr']} {pair['swallower']['navn']}"
                f" → nr. {pair['orphan']['_orig_nr']} {pair['orphan']['navn']}"
                f" (side {pair['orphan']['sider']})",
                "",
                f"- Sluger: `{pair['swallower']['record_key']}`",
                f"- Forældreløs: `{pair['orphan']['record_key']}`",
                f"- Begrundelse til gennemgangen: `{suggested_reason(pair)}`",
                "",
            ]
    if report["slugt_hoved"]:
        lines += ["## Slugt hoved uden forældreløs modpart", ""]
        for entry in report["slugt_hoved"]:
            lines.append(
                f"- nr. {entry['swallower']['_orig_nr']} {entry['swallower']['navn']}"
                f" indeholder “{entry['swallowed_head']}”"
                f" (`{entry['swallower']['record_key']}`)"
            )
        lines.append("")
    if report["delt_narrativ"]:
        lines += ["## Delt narrativ (samme tekst på flere poster)", ""]
        for group in report["delt_narrativ"]:
            navne = " · ".join(
                f"nr {entry['_orig_nr']} {entry['navn']} (side {entry['sider']})"
                for entry in group["poster"]
            )
            lines.append(f"- {group['tegn']} tegn delt af: {navne}")
        lines.append("")
    if report["mangler_eget_hoved"]:
        lines += ["## Mangler eget hoved (sluger ukendt)", ""]
        for entry in report["mangler_eget_hoved"]:
            lines.append(
                f"- nr. {entry['_orig_nr']} {entry['navn']} (side {entry['sider']},"
                f" `{entry['record_key']}`)"
            )
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True,
                        help="JSON-rapport; skrives kun hvis filen ikke findes")
    parser.add_argument("--markdown-out", type=Path,
                        help="valgfri læsevenlig rapport til gennemgangen")
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
    report = find_boundary_defects(baseline)
    write_report(report, args.out)
    if args.markdown_out:
        with args.markdown_out.open("x", encoding="utf-8") as handle:
            handle.write(_markdown(report))
    summary = report["summary"]
    print(
        f"{summary['poster']} poster · {summary['graensefejl_par']} grænsefejl-par · "
        f"{summary['slugt_hoved']} slugt hoved · "
        f"{summary['mangler_eget_hoved']} mangler eget hoved · "
        f"{summary['delt_narrativ']} delt narrativ"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
