"""Signalerne der afgør om en grænse skal læses af et menneske."""

from __future__ import annotations

from collections.abc import Mapping
import re
import statistics

import segment
from detect_boundary_defects_1939 import (
    _opens_with_own_head,
    _printed_number,
    _swallowed_heads,
)


class SignalError(ValueError):
    pass


KLASSER = ("record_text", "structural_header", "layout", "noise")

# Under en tredjedel af søskendemedianen regnes som afvigende. Rent
# sorteringssignal — det bliver aldrig en advarsel i sig selv.
_LAENGDE_ANDEL = 3


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


def _number_skip(record: Mapping, span: Mapping,
                 siblings: list[Mapping]) -> bool:
    own = _printed_number(record)
    if own is None:
        return False
    for sibling in siblings:
        number = _printed_number(sibling)
        position = sibling.get("char_from")
        if number is None or number == own:
            continue
        if position is None:
            return True
        if isinstance(position, bool) or not isinstance(position, int) or position < 0:
            raise SignalError("søskende har ugyldig char_from")
        if (number < own) != (position < span["char_from"]):
            return True
    return False


def span_signals(span: Mapping, record: Mapping, span_text: str,
                 siblings: list[Mapping], *,
                 sibling_lengths: list[int] | None = None) -> list[str]:
    """Udled de fire sorteringssignaler fra et spænd og dets søskende."""
    if not isinstance(span, Mapping):
        raise SignalError("spænd skal være en mapping")
    char_from = span.get("char_from")
    if isinstance(char_from, bool) or not isinstance(char_from, int) or char_from < 0:
        raise SignalError("spænd mangler gyldig char_from")
    char_to = span.get("char_to", char_from)
    if (isinstance(char_to, bool) or not isinstance(char_to, int)
            or char_to < char_from):
        raise SignalError("spænd har ugyldig char_to")
    if not isinstance(record, Mapping):
        raise SignalError("baseline-post skal være en mapping")
    if not isinstance(span_text, str):
        raise SignalError("spændtekst skal være en streng")
    if not isinstance(siblings, list):
        raise SignalError("søskende skal være en liste")
    if any(not isinstance(sibling, Mapping) for sibling in siblings):
        raise SignalError("hver søskende skal være en mapping")
    if sibling_lengths is not None:
        if not isinstance(sibling_lengths, list):
            raise SignalError("søskendelængder skal være en liste")
        if any(isinstance(length, bool) or not isinstance(length, int) or length < 0
               for length in sibling_lengths):
            raise SignalError("søskendelængder skal være ikke-negative heltal")

    signals = []
    if not _opens_with_own_head(record, span_text):
        signals.append("mangler_eget_hoved")
    if _swallowed_heads(record, span_text, siblings):
        signals.append("slugt_hoved")
    if _number_skip(record, span, siblings):
        signals.append("nummerspring")
    if sibling_lengths:
        median = statistics.median(sibling_lengths)
        length = char_to - char_from
        if median and (length * _LAENGDE_ANDEL < median
                       or length > median * _LAENGDE_ANDEL):
            signals.append("laengdeafvigelse")
    return signals


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
    if not isinstance(gap_summary, Mapping):
        raise SignalError("hul-opsummering skal være en mapping")
    if set(gap_summary) != {"tegn", "klasser", "har_broedtekst"}:
        raise SignalError("hul-opsummering skal have tegn, klasser og har_broedtekst")
    tegn = gap_summary["tegn"]
    if isinstance(tegn, bool) or not isinstance(tegn, int) or tegn < 0:
        raise SignalError("hul-opsummering har ugyldigt tegnantal")
    klasser = gap_summary["klasser"]
    if not isinstance(klasser, Mapping) or set(klasser) != set(KLASSER):
        raise SignalError("hul-opsummering har ugyldige klasser")
    for antal in klasser.values():
        if isinstance(antal, bool) or not isinstance(antal, int) or antal < 0:
            raise SignalError("hul-opsummering har ugyldige klasseantal")
    if not isinstance(gap_summary["har_broedtekst"], bool):
        raise SignalError("hul-opsummering har ugyldigt har_broedtekst")
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
    if not isinstance(clauses, list):
        raise SignalError("klausuler skal være en liste")
    validated_clauses = []
    for item in clauses:
        if not isinstance(item, Mapping):
            raise SignalError("klausul skal være en mapping")
        clause_from, clause_to = item.get("char_from"), item.get("char_to")
        for value in (clause_from, clause_to):
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                raise SignalError("klausul har ugyldige positioner")
        if clause_to <= clause_from:
            raise SignalError("klausul har ugyldige positioner")
        classification = item.get("classification")
        if classification not in KLASSER:
            raise SignalError("ukendt klausul-klassifikation")
        validated_clauses.append((clause_from, clause_to, classification))

    counts = dict.fromkeys(KLASSER, 0)
    for clause_from, clause_to, classification in validated_clauses:
        if char_to <= clause_from or clause_to <= char_from:
            continue
        counts[classification] += 1
    covered_until = char_from
    for clause_from, clause_to, _ in sorted(validated_clauses):
        if char_to <= clause_from or clause_to <= char_from:
            continue
        covered_from = max(char_from, clause_from)
        if covered_from > covered_until:
            raise SignalError("klausuler dækker ikke hele hullet")
        covered_until = max(covered_until, min(char_to, clause_to))
        if covered_until == char_to:
            break
    if covered_until < char_to:
        raise SignalError("klausuler dækker ikke hele hullet")
    return {
        "tegn": char_to - char_from,
        "klasser": counts,
        "har_broedtekst": counts["record_text"] > 0,
    }
