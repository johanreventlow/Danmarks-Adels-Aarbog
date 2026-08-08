"""Signalerne der afgør om en grænse skal læses af et menneske."""

from __future__ import annotations

from collections.abc import Mapping
import re

import segment


class SignalError(ValueError):
    pass


KLASSER = ("record_text", "structural_header", "layout", "noise")


# Et trykt hoved uden punktum ("7 Heinrich") er netop den form Calamari tabte.
# Porten skal derfor være bredere end selve postregelen, ellers lukker den
# præcis den fejl igennem som den findes for.
_LOEST_HOVED_RE = re.compile(
    r"(?m)^\s{0,4}\??\s{0,2}\d{1,3}\s*[a-z]?\.?\s+(?!(?:Jan|Febr|Marts|April|Maj|Juni|"
    r"Juli|Aug|Sept|Okt|Nov|Dec|Aar|s\.\s*M))[^\W\d_]",
    re.UNICODE,
)


def _har_trykt_hoved(text: str) -> bool:
    if not isinstance(text, str):
        raise SignalError("tekst skal være en streng")
    for line in text.splitlines():
        if segment.POST_1939_RE.match(line):
            return True
    return bool(_LOEST_HOVED_RE.search(text))


def may_bulk_confirm(gap_text: str, raw_text_window: str,
                     gap_summary: Mapping) -> bool:
    """Porten til hurtig bekræftelse: tre krav, alle skal holde.

    1. ingen brødtekst i hullet ifølge regnskabet
    2. intet trykt hoved i Calamari-hullet
    3. intet trykt hoved i rå OCR's modsvarende stykke

    Punkt 3 er det afgørende. Et hoved Calamari har tabt, er stadig synligt i
    den anden gengivelse, og uden dette krav kunne en manglende person havne i
    den bunke der godkendes tyve ad gangen.
    """
    if not isinstance(gap_summary, Mapping) or "har_broedtekst" not in gap_summary:
        raise SignalError("hul-opsummering mangler har_broedtekst")
    if gap_summary["har_broedtekst"]:
        return False
    return not _har_trykt_hoved(gap_text) and not _har_trykt_hoved(raw_text_window)


def classify_gap(clauses: list[dict], gap: Mapping) -> dict:
    """Opsummér hvad der ligger i hullet mellem to spænd.

    Regnskabet sorterer kun. Om et hul må massebekræftes afgøres af den
    negative tværgengivelses-kontrol, ikke af denne klassifikation: regnskabet
    kalder alt uklassificeret ``record_text`` og bruger ikke 1939-v2-profilens
    fulde strukturlogik.
    """
    if not isinstance(gap, Mapping):
        raise SignalError("hul skal være en mapping")
    char_from, char_to = gap.get("char_from"), gap.get("char_to")
    for value in (char_from, char_to):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise SignalError("hul har ugyldige positioner")
    if char_to < char_from:
        raise SignalError("hul slutter før det begynder")
    counts = dict.fromkeys(KLASSER, 0)
    for item in clauses:
        if not isinstance(item, Mapping):
            raise SignalError("klausul skal være en mapping")
        classification = item.get("classification")
        if classification not in KLASSER:
            raise SignalError("ukendt klausul-klassifikation")
        if char_to <= item["char_from"] or item["char_to"] <= char_from:
            continue
        if char_from == char_to:
            continue
        counts[classification] += 1
    return {
        "tegn": char_to - char_from,
        "klasser": counts,
        "har_broedtekst": counts["record_text"] > 0,
    }
