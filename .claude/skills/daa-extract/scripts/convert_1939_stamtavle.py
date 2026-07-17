#!/usr/bin/env python3
# =====================================================================
#  convert_1939_stamtavle.py — deterministisk konverter (A3a) fra
#  1939-Reventlow-stamtavlens ekstraktion (work_1939_stamtavle/
#  linked_clean.json) til load_daa.R's clean.json-format.
#
#  Brug:  python3 convert_1939_stamtavle.py [input.json [output.json]]
#         default: work_1939_stamtavle/linked_clean.json
#              ->  work_1939_stamtavle/clean_1939.json  (gitignoreret —
#         input/output indeholder persondata om potentielt levende;
#         COMMIT ALDRIG output).
#
#  NØGLERUM (kritisk beslutning): hele stamtavlen får ÉT syntetisk
#  linje = "1939" og globalt unikke heltals-nr 1..N (deterministisk:
#  sorteret på _id). nr_label SÆTTES TIL str(nr) — IKKE originalen —
#  fordi (a) load_daa.R's pmap keyer på (linje, nr_label) og kræver
#  unikhed (originale løbenumre er GRUPPE-lokale: kun 22 distinkte
#  labels over 539 poster, massiv duplikering), og (b) resolve_barn_keys
#  (load_helpers.R) opløser boern.nr_range via eksakt nøgle
#  "linje-<n>", så A3c's fremtidige nr_range i det globale nøglerum kun
#  virker når nr_label == str(nr). Originalen bevares tabsfrit i
#  passthrough-felterne _orig_nr/_lokal_id (loaderen ignorerer
#  ukendte felter). load_daa.R røres IKKE.
#
#  Datoer: ALLE dato-strenge rutes gennem validate.derive_date_info
#  (A2-parseren) — ingen egen dato-parsing her.
#
#  TODO(A3b): narrative sættes bevidst til None — den fyldes senere
#  deterministisk af segmenteren med bogens ORDRETTE prosa (invariant
#  #6: narrativ må aldrig syntetiseres). kilde_span er foreløbig =
#  date_raw; A3b forfiner til mindste klausul i raw-teksten.
#  TODO(A3c): boern/forældre-links bygges i et senere trin ud fra
#  _foraelder_id/_boern_ref/_ctx-passthrough — udelades helt her.
# =====================================================================
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import derive_date_info  # noqa: E402  (A2-parseren — genbrug, omskriv ikke)

CONVERTER_VERSION = "1.0.0"
LINJE = "1939"

# (input-felt, faktatype) for dato-fakta. erhverv/uddannelse udelades
# bevidst — load_daa.R springer dem over (bliver i narrativen, A3b).
DATE_FACT_FIELDS = (("foedsel", "fødsel"), ("doed", "død"), ("begravelse", "begravelse"))

# Fritekst-felter der samles i ét note-felt (bevarelse; load_daa.R
# læser IKKE top-niveau note — feltet er til A3b/A3c + menneskelig QA).
NOTE_FIELDS = ("noter", "note", "notes", "slaegtskab_note", "navn_note",
               "navn_kilde", "usikker_noter", "usikker_note", "note_usikker",
               "navn_usikker_note", "nr_note")


def _s(v):
    """Trimmet ikke-tom streng eller None."""
    if isinstance(v, str):
        v = v.strip()
        return v or None
    return None


def build_date_fact(faktatype, blok):
    """Dato-blok ({date_raw, sted, ...}) -> loader-fact eller None.

    date_raw rutes gennem derive_date_info (A2). Blok med KUN sted giver
    stadig et fakta (steds-evidens uden dato). Tom blok -> None.
    dato_usikker (kildens egen tvivl) overlays certainty='uncertain'
    hvis parseren ikke selv satte noget.
    """
    if not isinstance(blok, dict):
        return None
    date_raw = _s(blok.get("date_raw"))
    sted = _s(blok.get("sted"))
    if date_raw is None and sted is None:
        return None
    info = derive_date_info(date_raw)
    certainty = info["certainty"]
    if blok.get("dato_usikker") and certainty is None:
        certainty = "uncertain"
    return {
        "faktatype": faktatype,
        "vaerdi": None,
        "date_raw": date_raw,
        "date_min": info["date_min"],
        "date_max": info["date_max"],
        "date_qualifier": info["qualifier"],
        "date_certainty": certainty,
        "calendar": info["calendar"],
        "sted": sted,
        "kilde_span": date_raw,  # foreløbig; A3b-segmenter forfiner
    }


def convert_godser(godser):
    """Liste af gods-strenge -> [{navn: str}, ...] (tomme droppes)."""
    ud = []
    for g in godser or []:
        navn = _s(g)
        if navn:
            ud.append({"navn": navn})
    return ud


def convert_aegteskab(a):
    """Ét ekstraktions-ægteskab -> loaderens format. Dato via A2-parseren."""
    dato_raw = _s(a.get("dato_raw"))
    info = derive_date_info(dato_raw)
    note_dele = [t for t in (_s(a.get("partner_note")), _s(a.get("skilt_note")))
                 if t]
    if a.get("navn_usikker") or a.get("partner_navn_usikker"):
        note_dele.append("partnernavn usikkert (OCR/kilde)")
    return {
        "ordinal": a.get("ordinal"),
        "partner_navn": _s(a.get("partner_navn")),
        "dato_raw": dato_raw,
        "date_min": info["date_min"],
        "date_max": info["date_max"],
        "sted": _s(a.get("sted")),
        "skilt": bool(a.get("skilt")),
        "partner_foraeldre": _s(a.get("partner_foraeldre")),
        "note": " — ".join(note_dele) or None,
        "kilde_span": dato_raw,  # foreløbig; A3b forfiner
    }


def _kryds_ref_tekst(kr):
    """kryds_ref (str | liste af {type,ref,note,tekst,raw}) -> tekststumper."""
    if isinstance(kr, str):
        t = _s(kr)
        return [f"kryds_ref: {t}"] if t else []
    ud = []
    for item in kr or []:
        if isinstance(item, dict):
            dele = [_s(item.get(k)) for k in ("type", "ref", "tekst", "raw", "note")]
            tekst = " ".join(d for d in dele if d)
            if tekst:
                ud.append(f"kryds_ref: {tekst}")
        else:
            t = _s(item)
            if t:
                ud.append(f"kryds_ref: {t}")
    return ud


def collect_note(rec):
    """Saml alle fritekst-/note-felter + kryds_ref i én streng (eller None)."""
    dele = []
    for felt in NOTE_FIELDS:
        v = rec.get(felt)
        if isinstance(v, list):
            dele.extend(t for t in (_s(x) for x in v) if t)
        else:
            t = _s(v)
            if t:
                dele.append(t)
    dele.extend(_kryds_ref_tekst(rec.get("kryds_ref")))
    return " | ".join(dele) or None


def convert_record(rec, global_nr):
    """Én linked_clean-post -> én loader-post i det globale 1939-nøglerum."""
    facts = []
    titel = _s(rec.get("titel"))
    if titel:
        facts.append({"faktatype": "titel", "vaerdi": titel, "date_raw": None,
                      "date_min": None, "date_max": None, "date_qualifier": None,
                      "date_certainty": None, "calendar": None, "sted": None,
                      "kilde_span": titel})
    for felt, faktatype in DATE_FACT_FIELDS:
        f = build_date_fact(faktatype, rec.get(felt))
        if f is not None:
            facts.append(f)
    # 'kvalifikator' på død (fx 'ung') er ikke en dato-qualifier — bevar som note
    ekstra_noter = []
    doed = rec.get("doed")
    if isinstance(doed, dict) and _s(doed.get("kvalifikator")):
        ekstra_noter.append(f"død: {_s(doed.get('kvalifikator'))}")
    for felt, _ft in DATE_FACT_FIELDS:
        blok = rec.get(felt)
        if isinstance(blok, dict) and _s(blok.get("note")):
            ekstra_noter.append(f"{felt}-note: {_s(blok.get('note'))}")

    aegteskaber = sorted(
        (convert_aegteskab(a) for a in rec.get("aegteskaber") or []),
        key=lambda m: (m["ordinal"] is None, m["ordinal"]))

    note = collect_note(rec)
    if ekstra_noter:
        note = " | ".join(([note] if note else []) + ekstra_noter)

    out = {
        "linje": LINJE,
        "nr": global_nr,
        "nr_label": str(global_nr),  # SKAL == str(nr): pmap-/barn-opslag, se header
        "navn": rec["navn"],
        "koen": rec.get("koen"),
        "usikker": bool(rec.get("navn_usikker") or rec.get("ufuldstaendig")
                        or rec.get("usikker")),
        # TODO(A3b): fyldes af segmenteren med ORDRET prosa — syntetiseres aldrig
        "narrative": None,
        "facts": facts,
        "aegteskaber": aegteskaber,
        "godser": convert_godser(rec.get("godser")),
        "note": note,
        # ---- passthrough (loaderen ignorerer; A3b/A3c + QA bruger dem) ----
        "_id": rec["_id"],
        "_orig_nr": rec.get("nr"),
        "_lokal_id": rec.get("lokal_id"),
        "_ctx": rec.get("_ctx"),
        "_boern_ref": rec.get("boern_ref"),
        "_foraeldre_note": rec.get("foraeldre_note"),
        "_window": rec.get("_window"),
        "_converter_version": CONVERTER_VERSION,
    }
    if rec.get("_foraelder_id") is not None:
        out["_foraelder_id"] = rec["_foraelder_id"]
    tilnavn = _s(rec.get("tilnavn"))
    if tilnavn:
        out["tilnavn"] = tilnavn
    # boern udelades BEVIDST (A3c) — loaderen tolererer fravær (NULL-opslag)
    return out


def convert_all(records):
    """Hele korpus: sortér deterministisk på _id, tildel nr 1..N."""
    ordnet = sorted(records, key=lambda r: r["_id"])
    return [convert_record(rec, i) for i, rec in enumerate(ordnet, start=1)]


def main(argv):
    inp = Path(argv[1]) if len(argv) > 1 else Path("work_1939_stamtavle/linked_clean.json")
    ud = Path(argv[2]) if len(argv) > 2 else Path("work_1939_stamtavle/clean_1939.json")
    with open(inp, encoding="utf-8") as f:
        records = json.load(f)
    out = convert_all(records)
    with open(ud, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print(f"convert_1939_stamtavle v{CONVERTER_VERSION}: "
          f"{len(records)} poster ind -> {len(out)} poster ud ({ud})")


if __name__ == "__main__":
    main(sys.argv)
