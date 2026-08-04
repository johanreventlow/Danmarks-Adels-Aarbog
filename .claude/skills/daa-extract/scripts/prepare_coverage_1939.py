"""Build anchored 1939 candidates from explicit, reviewer-supplied bridges."""

from __future__ import annotations

from collections.abc import Mapping

from coverage_1939 import ALLOWED_STATUSES, POSTKLASSER, validate_coverage


def _mapping(value: object, label: str) -> Mapping:
    if not isinstance(value, Mapping):
        raise ValueError(f"{label} skal være en mapping")
    return value


def _positive_int(value: object, label: str, *, zero_allowed: bool = False) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < (0 if zero_allowed else 1):
        raise ValueError(f"{label} skal være et positivt heltal")
    return value


def _pages(value: object, label: str) -> list[int]:
    if not isinstance(value, list) or not value:
        raise ValueError(f"{label} skal være en ikke-tom liste")
    return [_positive_int(page, label) for page in value]


def _post_pages(value: object) -> list[int]:
    if not isinstance(value, str) or not value:
        raise ValueError("post sider mangler")
    pieces = value.split("-")
    if len(pieces) == 1:
        return [_positive_int(int(pieces[0]), "post side")]
    if len(pieces) == 2:
        first, last = (_positive_int(int(piece), "post side") for piece in pieces)
        if first > last:
            raise ValueError("post sideinterval er omvendt")
        return list(range(first, last + 1))
    raise ValueError("post sider har ugyldigt format")


def build_candidates(calamari_text: str, posts: list[dict], raw_bridges: list[dict]) -> list[dict]:
    """Return only candidates with one exact, explicit Calamari/raw bridge."""
    if not isinstance(calamari_text, str):
        raise ValueError("calamari_text skal være en streng")
    if not isinstance(posts, list) or not all(isinstance(post, Mapping) for post in posts):
        raise ValueError("posts skal være en liste af mappings")
    if not isinstance(raw_bridges, list):
        raise ValueError("raw_bridges skal være en liste")

    seen_indices: set[int] = set()
    seen_ids: set[str] = set()
    spans: list[tuple[int, int]] = []
    candidates: list[dict] = []
    for bridge_value in raw_bridges:
        bridge = _mapping(bridge_value, "bridge")
        candidate_id = bridge.get("candidate_id")
        if not isinstance(candidate_id, str) or not candidate_id:
            raise ValueError("candidate_id mangler")
        if candidate_id in seen_ids:
            raise ValueError("candidate_id forekommer flere gange")
        seen_ids.add(candidate_id)

        post_index = _positive_int(bridge.get("post_index"), "post_index", zero_allowed=True)
        if post_index >= len(posts):
            raise ValueError("ukendt post_index")
        if post_index in seen_indices:
            raise ValueError("post_index forekommer flere gange")
        seen_indices.add(post_index)
        post = posts[post_index]

        span = _mapping(bridge.get("calamari_span"), "Calamari-span")
        char_from = _positive_int(span.get("char_from"), "Calamari-span char_from", zero_allowed=True)
        char_to = _positive_int(span.get("char_to"), "Calamari-span char_to", zero_allowed=True)
        if char_from >= char_to or char_to > len(calamari_text):
            raise ValueError("ikke eksakt Calamari-span")
        verbatim = bridge.get("calamari_verbatim_text")
        if not isinstance(verbatim, str) or calamari_text[char_from:char_to] != verbatim:
            raise ValueError("ikke eksakt Calamari-span")
        spans.append((char_from, char_to))

        pdf_pages = _pages(bridge.get("pdf_pages"), "PDF-side")
        if _post_pages(post.get("sider")) != pdf_pages:
            raise ValueError("PDF-sider stemmer ikke")

        kind = bridge.get("kind")
        if not isinstance(kind, str) or not kind:
            raise ValueError("rå-bro kind mangler")
        raw_from = _positive_int(bridge.get("raw_char_from"), "rå-bro raw_char_from", zero_allowed=True)
        raw_to = _positive_int(bridge.get("raw_char_to"), "rå-bro raw_char_to", zero_allowed=True)
        if raw_from >= raw_to:
            raise ValueError("rå-bro skal have positiv længde")

        postklasse = post.get("postklasse") or "nummereret"
        if postklasse not in POSTKLASSER:
            raise ValueError("postklasse er ukendt")
        candidates.append({
            "candidate_id": candidate_id,
            "postklasse": postklasse,
            "calamari_span": {"char_from": char_from, "char_to": char_to},
            "pdf_pages": pdf_pages,
            "raw_structure_bridge": {
                "kind": kind,
                "raw_char_from": raw_from,
                "raw_char_to": raw_to,
            },
        })

    for (_, previous_end), (next_start, _) in zip(sorted(spans), sorted(spans)[1:]):
        if previous_end > next_start:
            raise ValueError("Calamari-spans overlapper")
    return candidates


def assemble_coverage(
    source: dict,
    expected_baseline_keys: set[str],
    decisions: list[dict],
    candidates: list[dict],
) -> dict:
    """Resolve reviewer decisions to candidates, then revalidate complete coverage."""
    if not isinstance(decisions, list):
        raise ValueError("decisions skal være en liste")
    candidate_by_id: dict[str, dict] = {}
    for candidate_value in candidates:
        candidate = _mapping(candidate_value, "candidate")
        candidate_id = candidate.get("candidate_id")
        if not isinstance(candidate_id, str) or not candidate_id:
            raise ValueError("candidate_id mangler")
        if candidate_id in candidate_by_id:
            raise ValueError("candidate_id forekommer flere gange")
        candidate_by_id[candidate_id] = dict(candidate)

    entries: list[dict] = []
    for decision_value in decisions:
        decision = _mapping(decision_value, "decision")
        status = decision.get("status")
        if status not in ALLOWED_STATUSES:
            raise ValueError("ukendt status")
        entry = {
            "baseline_record_key": decision.get("baseline_record_key"),
            "status": status,
        }
        if status == "accepteret":
            candidate_id = decision.get("candidate_id")
            if candidate_id not in candidate_by_id:
                raise ValueError("ukendt candidate_id")
            entry["candidate"] = candidate_by_id[candidate_id]
        elif status == "eksplicit_dublet":
            entry["duplicate_of_baseline_record_key"] = decision.get(
                "duplicate_of_baseline_record_key"
            )
        else:
            entry["reason"] = decision.get("reason")
        entries.append(entry)

    bundle = {"schema_version": 1, "source": source, "entries": entries}
    validate_coverage(bundle, expected_baseline_keys=expected_baseline_keys)
    return bundle
