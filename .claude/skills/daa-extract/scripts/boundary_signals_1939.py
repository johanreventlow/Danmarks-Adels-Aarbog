"""Signalerne der afgør om en grænse skal læses af et menneske."""

from __future__ import annotations

from collections.abc import Mapping


class SignalError(ValueError):
    pass


KLASSER = ("record_text", "structural_header", "layout", "noise")


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
