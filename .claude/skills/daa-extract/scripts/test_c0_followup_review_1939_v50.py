"""DB-frie tests for menneskearket og dets fail-closed konverter."""
import importlib.util
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, _DIR / (name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


build = _load("build_c0_followup_review_1939_v50")
conv = _load("convert_c0_followup_decisions_1939_v50")


def _flags_doc():
    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "operations": [
            {"person_id": 991, "narrative_id": 660, "old_sha256": "a" * 64,
             "source_record_key": "record-x", "page_from": 504,
             "default_text": "Hr. Iven til Rixdorf.", "flags": []},
            {"person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
             "source_record_key": "record-y", "page_from": 504,
             "default_text": "Reventlow til Gaarz.", "flags": [
                 {"flag_id": "record-y:12:hyphen_unproven",
                  "kind": "hyphen_unproven", "char_offset": 12,
                  "context": "Revent-\nlow til", "person_id": 992,
                  "source_record_key": "record-y"}]},
        ],
        "flag_counts": {"hyphen_unproven": 1},
    }


def test_sheet_prefills_the_recommended_action():
    """Anbefalingerne er UDFYLDT: står en linje urørt, er den enig."""
    text = build.render_review(_flags_doc())
    assert "[MERGE] record-y:12:hyphen_unproven" in text


def test_sheet_lists_person_without_flags_as_auto():
    """991 har ingen flag — dens tekst er allerede korrekt. Den skal fremgå,
    så mennesket ser HELE mængden, ikke kun det der kræver et valg."""
    text = build.render_review(_flags_doc())
    assert "991" in text


def test_roundtrip_unchanged_sheet_yields_defaults():
    doc = _flags_doc()
    out = conv.parse_review(build.render_review(doc), doc)
    assert out["decisions"] == {"record-y:12:hyphen_unproven": "merge"}
    assert out["accepted_person_ids"] == [991, 992]


def test_keep_is_honoured():
    doc = _flags_doc()
    text = build.render_review(doc).replace("[MERGE] record-y", "[KEEP] record-y", 1)
    assert conv.parse_review(text, doc)["decisions"] == {
        "record-y:12:hyphen_unproven": "keep"}


def test_afvis_removes_the_person_but_keeps_the_others():
    """Delvis accept: afvises én, kører de øvrige. Alt-eller-intet ville
    presse mod at acceptere noget tvivlsomt for at få resten igennem."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT] 991", "[AFVIS] 991", 1)
    out = conv.parse_review(text, doc)
    assert out["accepted_person_ids"] == [992]


def test_unknown_token_is_terminal():
    doc = _flags_doc()
    text = build.render_review(doc).replace("[MERGE] record-y", "[MAASKE] record-y", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_TOKEN_INVALID"):
        conv.parse_review(text, doc)


def test_edited_context_is_terminal():
    """Byte-låst kontekst: alt andet end tokenet verificeres. Ellers kunne en
    utilsigtet redigering flytte et valg til et andet sted i teksten."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("Revent-\\n", "Rvent-\\n", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_TAMPERED"):
        conv.parse_review(text, doc)


def test_missing_line_is_terminal():
    doc = _flags_doc()
    text = "\n".join(l for l in build.render_review(doc).splitlines()
                     if "record-y:12" not in l)
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_MISSING"):
        conv.parse_review(text, doc)


def test_all_rejected_is_terminal():
    """En tom mængde er ikke en gyldig kørsel — samme regel som D2_APPLY_EMPTY."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT] ", "[AFVIS] ")
    with pytest.raises(SystemExit, match="C0F_REVIEW_EMPTY"):
        conv.parse_review(text, doc)


def test_unknown_flag_kind_is_terminal():
    """Målingen gav kun hyphen_unproven, men det er en egenskab ved DATA, ikke
    ved koden. En ny flagtype skal give en læsbar fejl, ikke en rå KeyError."""
    doc = _flags_doc()
    doc["operations"][1]["flags"][0]["kind"] = "some_future_flag_kind"
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_KIND_UNKNOWN"):
        build.render_review(doc)


def test_converter_rejects_unknown_flag_kind_independently_of_renderer():
    """Reviewer-fund (IMPORTANT #4): rendereren har gaten, konverteren skal
    have sin EGEN. Her renderes arket mens flag'et stadig er hyphen_unproven
    (så arket i sig selv er gyldigt og urørt) -- derefter ændres kun
    flags_doc'et, som konverteren ser. Konverteren må ikke antage at
    rendereren allerede har passet på; den skal selvstændigt afvise."""
    doc = _flags_doc()
    text = build.render_review(doc)
    doc["operations"][1]["flags"][0]["kind"] = "future_kind"
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_KIND_UNKNOWN"):
        conv.parse_review(text, doc)


def test_swapped_line_tails_cannot_move_a_decision():
    """Regression for Codex-fundet CRITICAL: den gamle kode slog en linjes
    hale op på det ID den LÆSTE af linjen selv, ikke på linjens POSITION i
    den forventede sekvens. Derfor kunne to linjers haler byttes om uden at
    nogen fejl blev rejst: hver linje så isoleret set stadig gyldig ud.
    Her afvises 991 legitimt, hvorefter angrebet bytter de to personers
    resterende hale-tekst om -- det skal fanges som LINE_TAMPERED, ikke
    stiltiende flytte afvisningen fra 991 til 992."""
    doc = _flags_doc()
    lines = build.render_review(doc).splitlines()
    i991 = next(i for i, l in enumerate(lines) if l.startswith("[ACCEPT] 991"))
    i992 = next(i for i, l in enumerate(lines) if l.startswith("[ACCEPT] 992"))
    tail991 = lines[i991].split(" ", 1)[1]
    tail992 = lines[i992].split(" ", 1)[1]
    lines[i991] = "[AFVIS] " + tail992   # 991s linje bærer nu 992s hale
    lines[i992] = "[ACCEPT] " + tail991  # 992s linje bærer nu 991s hale
    text = "\n".join(lines) + "\n"
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_TAMPERED"):
        conv.parse_review(text, doc)


def test_person_hale_is_locked():
    """Person-hale-låsen (reviewer-fund #5, gate 1 af 3): en person-linjes
    hale er lige så byte-låst som en flag-linjes. Rettes kildenøglen uden at
    tokenet ændres, skal det stadig fanges."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("record-x", "record-q", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_TAMPERED"):
        conv.parse_review(text, doc)


def test_person_missing_gate_fires():
    """Person-missing-gaten (reviewer-fund #5, gate 2 af 3). Bruger en ekstra
    operation UDEN flag som den SIDSTE i sekvensen, så dens person-linje kan
    fjernes uden at noget efterfølgende kolliderer med den forskudte
    position -- ellers ville manglende-linjen vise sig som TAMPERED på den
    næste linje i stedet for som en ren MISSING."""
    doc = _flags_doc()
    doc["operations"].append({
        "person_id": 993, "narrative_id": 662, "old_sha256": "c" * 64,
        "source_record_key": "record-z", "page_from": 505,
        "default_text": "Uden flag.", "flags": []})
    text = "\n".join(l for l in build.render_review(doc).splitlines()
                     if "[ACCEPT] 993" not in l)
    with pytest.raises(SystemExit, match="C0F_REVIEW_PERSON_MISSING"):
        conv.parse_review(text, doc)


def test_person_duplicate_gate_fires():
    """Person-duplicate-gaten (reviewer-fund #5, gate 3 af 3). Simulerer et
    flags-dokument hvor samme person_id optræder i to operationer --
    build_c0_followup_flags_1939_v50 forhindrer dette opstrøms
    (C0F_FLAGS_DUPLICATE_PERSON_ID), men konverteren må ikke stole blindt på
    det; den skal være selvstændigt fail-closed over for et korrupt input."""
    doc = _flags_doc()
    doc["operations"].append(dict(doc["operations"][0], narrative_id=999))
    text = build.render_review(doc)
    with pytest.raises(SystemExit, match="C0F_REVIEW_PERSON_DUPLICATE"):
        conv.parse_review(text, doc)


def test_keep_default_round_trips_without_false_tamper():
    """Advisor-fund (blokerende): TOKEN_BY_ACTION['keep'] bærer et indlejret
    mellemrum ("[KEEP] ") for at holde kolonnerne linjede med "[MERGE]".
    Uden denne test er den kun uskadt, fordi DEFAULT_ACTION i dag har præcis
    ét flag, som mapper til 'merge' -- den dag en flagtype defaulter til
    'keep', skal parse_review(render_review(doc), doc) STADIG lykkes for et
    fuldstændig urørt ark, ikke fejle som LINE_TAMPERED på sin egen maskinelt
    rigtige output."""
    doc = _flags_doc()
    doc["operations"][1]["flags"][0]["kind"] = "future_keep_kind"
    build.DEFAULT_ACTION["future_keep_kind"] = "keep"
    conv.DEFAULT_ACTION["future_keep_kind"] = "keep"
    try:
        text = build.render_review(doc)
        out = conv.parse_review(text, doc)
        assert out["decisions"] == {"record-y:12:hyphen_unproven": "keep"}
        assert out["accepted_person_ids"] == [991, 992]
    finally:
        del build.DEFAULT_ACTION["future_keep_kind"]
        del conv.DEFAULT_ACTION["future_keep_kind"]


def test_extra_line_is_terminal():
    """C0F_REVIEW_LINE_UNEXPECTED: en linje UD OVER den forventede sekvens
    (fx en kopieret flaglinje sat ind for enden) skal fanges, ikke stiltiende
    ignoreres."""
    doc = _flags_doc()
    text = build.render_review(doc)
    flag_line = next(l for l in text.splitlines() if "record-y:12" in l)
    text2 = text.rstrip("\n") + "\n" + flag_line + "\n"
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_UNEXPECTED"):
        conv.parse_review(text2, doc)


def test_flag_duplicate_gate_fires():
    """Simulerer et flags-dokument hvor samme flag_id optræder to gange for
    samme person -- konverteren skal opdage det selvstændigt, ikke antage at
    upstream (build_c0_followup_flags_1939_v50, som allerede har sin egen
    C0F_FLAGS_ID_COLLISION) har renset det."""
    doc = _flags_doc()
    doc["operations"][1]["flags"].append(dict(doc["operations"][1]["flags"][0]))
    text = build.render_review(doc)
    with pytest.raises(SystemExit, match="C0F_REVIEW_FLAG_DUPLICATE"):
        conv.parse_review(text, doc)


def test_broken_person_id_fails_closed_not_as_a_raw_exception():
    """Reviewer-fund (IMPORTANT #3): et ødelagt person-ID i arket må ikke give
    en rå ValueError/IndexError. Fordi identiteten nu altid kommer fra
    POSITIONEN (flags_doc), ikke fra tekst parset ud af linjen, forsøges der
    intet int()-kald på brugerstyret tekst længere -- afvigelsen fanges
    generisk som LINE_TAMPERED, før noget forsøges parset."""
    doc = _flags_doc()
    text = build.render_review(doc).replace("[ACCEPT] 991", "[ACCEPT] xyz", 1)
    with pytest.raises(SystemExit, match="C0F_REVIEW_LINE_TAMPERED"):
        conv.parse_review(text, doc)
