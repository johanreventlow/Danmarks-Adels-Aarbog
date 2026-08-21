"""DB-frie tests for manifest-byggeren."""
import hashlib
import importlib.util
import json
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "c0f_manifest", _DIR / "build_c0_followup_manifest_1939_v50.py")
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

RAW = "Revent-\nlow til Gaarz.\n"

DATABASE_NAME = "postgres"
DATABASE_IDENTITY = "test-identity-123"
FLAGS_SHA256 = "a" * 64


def _import_flags_mod():
    spec = importlib.util.spec_from_file_location(
        "c0f_flags", _DIR / "build_c0_followup_flags_1939_v50.py")
    flags_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(flags_mod)
    return flags_mod


def _flags_doc():
    flags_mod = _import_flags_mod()
    default = flags_mod.normalize_narrative_v1(RAW, RAW)
    return {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        # Baeret af den ægte producent (Task 2) og krydstjekket af manifest-
        # byggeren (Finding 4) -- skal vaere til stede i FIXTUREN, ellers
        # tester alle andre tests reelt kun failure-stien.
        "database_name": DATABASE_NAME,
        "database_identity": DATABASE_IDENTITY,
        "operations": [{
            "person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
            "source_record_key": "record-y", "page_from": 504,
            "default_text": default["text"],
            "flags": [dict(f, flag_id="record-y:%d:%s" % (f["char_offset"], f["kind"]),
                           person_id=992, source_record_key="record-y")
                      for f in default["flags"]],
        }],
        "flag_counts": {"hyphen_unproven": len(default["flags"])},
    }


def _candidates():
    return {"records": [{"new_record_key": "record-y", "verbatim_text": RAW,
                         "pages": {"page_from": 504, "page_to": 504}}]}


def _decisions(doc, action="merge"):
    return {"decisions": {f["flag_id"]: action
                          for op in doc["operations"] for f in op["flags"]},
            "accepted_person_ids": [992],
            "flags_sha256": FLAGS_SHA256}


def _build_manifest(doc, decisions, candidates, flags_sha256=FLAGS_SHA256):
    return mod.build_manifest(doc, decisions, candidates, flags_sha256)


def test_manifest_rejects_decisions_for_another_flags_file():
    doc = _flags_doc()
    decisions = _decisions(doc)
    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAGS_SHA256_MISMATCH"):
        _build_manifest(doc, decisions, _candidates(), "b" * 64)


def test_manifest_rejects_decisions_without_flags_binding():
    doc = _flags_doc()
    decisions = _decisions(doc)
    del decisions["flags_sha256"]
    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAGS_SHA256_MISSING"):
        _build_manifest(doc, decisions, _candidates())


def test_manifest_main_binds_exact_flags_file_bytes(tmp_path):
    """Samme JSON med anden whitespace er en anden flagsfil og skal afvises."""
    flags_path = tmp_path / "flags.json"
    decisions_path = tmp_path / "decisions.json"
    candidates_path = tmp_path / "candidates.json"
    output_path = tmp_path / "manifest.json"
    doc = _flags_doc()
    original_bytes = json.dumps(doc, ensure_ascii=False, sort_keys=True).encode("utf-8")
    decisions = _decisions(doc)
    decisions["flags_sha256"] = hashlib.sha256(original_bytes).hexdigest()

    # Semantisk samme dokument, men ikke de bytes menneskets beslutning bandt sig til.
    flags_path.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")
    decisions_path.write_text(json.dumps(decisions), encoding="utf-8")
    candidates_path.write_text(json.dumps(_candidates()), encoding="utf-8")

    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAGS_SHA256_MISMATCH"):
        mod.main([
            "--flags", str(flags_path),
            "--decisions", str(decisions_path),
            "--candidates", str(candidates_path),
            "--output", str(output_path),
        ])


def test_default_decisions_reproduce_default_text():
    doc = _flags_doc()
    man = _build_manifest(doc, _decisions(doc), _candidates())
    assert man["operations"][0]["new_text"] == doc["operations"][0]["default_text"]


def test_keep_reconstructs_exact_hyphenated_text():
    """Laaser resultatet EKSAKT -- ikke bare 'anderledes end default'.

    Codex-review (2026-08-21) fandt at den gamle 'blot != default_text'-
    paastand lod en mutation der splicede paa POSITIONEN prefix_len + 1
    (i stedet for prefix_len) glide igennem: teksten blev stadig
    'anderledes', bare forkert -- 'Reventl-ow' i stedet for 'Revent-low'.
    """
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    man = _build_manifest(doc, _decisions(doc, "keep"), _candidates())
    assert man["operations"][0]["new_text"] == "Revent-low til Gaarz."


def test_rejected_person_is_excluded():
    doc = _flags_doc()
    dec = _decisions(doc)
    dec["accepted_person_ids"] = []
    with pytest.raises(SystemExit, match="C0F_MANIFEST_EMPTY"):
        _build_manifest(doc, dec, _candidates())


def test_missing_decision_is_terminal():
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    dec = _decisions(doc)
    dec["decisions"] = {}
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DECISION_MISSING"):
        _build_manifest(doc, dec, _candidates())


def test_new_text_sha256_matches_the_text():
    doc = _flags_doc()
    man = _build_manifest(doc, _decisions(doc), _candidates())
    op = man["operations"][0]
    assert op["new_text_sha256"] == hashlib.sha256(
        op["new_text"].encode("utf-8")).hexdigest()


def test_corrupted_default_text_is_rejected_before_invariant_check():
    """Et splice kan i princippet genindføre et brud i den FÆRDIGE tekst;
    ``_assert_invariants`` hævder derfor invarianterne igen efter splice,
    uændret -- se runde 2, fund 2's docstring i implementeringsfilen.

    Denne konkrete korruption (en "### PAGE"-rest i default_text) bliver nu
    fanget ENDNU tidligere: ``C0F_MANIFEST_DEFAULT_TEXT_MISMATCH`` fyrer
    allerede når ``default_text`` ikke er PRÆCIS hvad en frisk normalisering
    af raw+corpus giver -- en "### PAGE"-streng kan aldrig forekomme i et
    ægte ``normalize_narrative_v1``-resultat (funktionen asserter det
    internt), så enhver default_text der indeholder den, afsløres her, FØR
    noget forsøges spliced. ``_assert_invariants``-kaldet på den færdige
    tekst i ``build_manifest`` er urørt og fungerer fortsat som en ekstra
    sikkerhedsdug -- den er blot ikke længere den FØRSTE linje der fanger
    netop denne fixture, fordi fund 2's rettelse lukker klassen tidligere."""
    doc = _flags_doc()
    doc["operations"][0]["default_text"] += "\n### PAGE 0001 ###"
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DEFAULT_TEXT_MISMATCH"):
        _build_manifest(doc, _decisions(doc), _candidates())


# ---------------------------------------------------------------------------
# Finding 1+2: præfiks-kontrollen accepterer en forkert splice-position, og
# kontraktbrud der overlever hele suiten.
# ---------------------------------------------------------------------------


def test_shifted_char_offset_is_rejected():
    """Codex-review's reproduktion: et flag-dokument hvis char_offset er
    forskudt fra det ægte bindestregs-sted (fx pga. korruption eller en
    forkert genereret flags-fil) skal afvises TERMINALT -- ikke splice
    på et forkert sted, blot fordi et præfiks tilfældigvis matcher."""
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    dec = _decisions(doc, "keep")
    doc["operations"][0]["flags"][0]["char_offset"] += 1
    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAG_NOT_FOUND"):
        _build_manifest(doc, dec, _candidates())


def _harder_splice_fixture():
    """En fixture hvor en TIDLIGERE normalisering (et default-merget
    bindestregspar) forkorter teksten FØR det flag vi tester på -- så
    raw-offsettet og default_text-offsettet for det andet flag ikke
    længere er det samme tal. Det er netop den situation hvor en splice
    der (fejlagtigt) bruger ``default_text[:char_offset]`` i stedet for
    ``normalize_narrative_v1(raw[:char_offset], corpus)["text"]`` rammer
    ved siden af.
    """
    flags_mod = _import_flags_mod()
    raw = "Sviger-\nfar var Efter-\nslægt.\n"
    corpus = raw
    default = flags_mod.normalize_narrative_v1(raw, corpus)
    assert default["text"] == "Svigerfar var Efterslægt."
    assert len(default["flags"]) == 2  # begge hyphen_unproven, ubevist i korpus
    doc = {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "database_name": DATABASE_NAME,
        "database_identity": DATABASE_IDENTITY,
        "operations": [{
            "person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
            "source_record_key": "record-y", "page_from": 504,
            "default_text": default["text"],
            "flags": [dict(f, flag_id="record-y:%d:%s" % (f["char_offset"], f["kind"]),
                           person_id=992, source_record_key="record-y")
                      for f in default["flags"]],
        }],
        "flag_counts": {"hyphen_unproven": len(default["flags"])},
    }
    candidates = {"records": [{"new_record_key": "record-y", "verbatim_text": raw,
                               "pages": {"page_from": 504, "page_to": 504}}]}
    return doc, candidates


def test_splice_uses_raw_prefix_not_default_text_offset():
    doc, candidates = _harder_splice_fixture()
    flags = doc["operations"][0]["flags"]
    # flag 0 = "Sviger-\nfar" (offset 6) forbliver default (merge).
    # flag 1 = "Efter-\nslægt" (offset 21) afgøres "keep".
    decisions = {}
    for f in flags:
        decisions[f["flag_id"]] = "keep" if f["char_offset"] == 21 else "merge"
    dec_doc = {"decisions": decisions, "accepted_person_ids": [992],
               "flags_sha256": FLAGS_SHA256}
    man = _build_manifest(doc, dec_doc, candidates)
    assert man["operations"][0]["new_text"] == "Svigerfar var Efter-slægt."


def test_rejected_person_flags_never_reach_decision_lookup():
    """Filtreringen mod accepted_person_ids sker FØR flag-beslutningerne
    anvendes -- decisions_doc['decisions'] er IKKE forfiltreret efter
    accept. Beviser dette ved at give den afviste person INGEN beslutning
    overhovedet: hvis filteret var deaktiveret eller kørte for sent, ville
    build_manifest fejle med C0F_MANIFEST_DECISION_MISSING for person 993 i
    stedet for at lykkes med kun person 992 i resultatet."""
    flags_mod = _import_flags_mod()
    raw_accept = "Revent-\nlow til Gaarz.\n"
    raw_reject = "Ander-\nsen til Blegdam.\n"
    corpus = raw_accept + "\n" + raw_reject
    default_accept = flags_mod.normalize_narrative_v1(raw_accept, corpus)
    default_reject = flags_mod.normalize_narrative_v1(raw_reject, corpus)
    if not default_accept["flags"] or not default_reject["flags"]:
        pytest.skip("fixturen gav ingen flag at bevise pointen med")

    doc = {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "database_name": DATABASE_NAME,
        "database_identity": DATABASE_IDENTITY,
        "operations": [
            {
                "person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
                "source_record_key": "record-y", "page_from": 504,
                "default_text": default_accept["text"],
                "flags": [dict(f, flag_id="record-y:%d:%s" % (f["char_offset"], f["kind"]),
                               person_id=992, source_record_key="record-y")
                          for f in default_accept["flags"]],
            },
            {
                "person_id": 993, "narrative_id": 662, "old_sha256": "c" * 64,
                "source_record_key": "record-z", "page_from": 505,
                "default_text": default_reject["text"],
                # BEMÆRK: ingen beslutning gives for disse flag nedenfor --
                # det er selve pointen.
                "flags": [dict(f, flag_id="record-z:%d:%s" % (f["char_offset"], f["kind"]),
                               person_id=993, source_record_key="record-z")
                          for f in default_reject["flags"]],
            },
        ],
        "flag_counts": {},
    }
    candidates = {"records": [
        {"new_record_key": "record-y", "verbatim_text": raw_accept,
         "pages": {"page_from": 504, "page_to": 504}},
        {"new_record_key": "record-z", "verbatim_text": raw_reject,
         "pages": {"page_from": 505, "page_to": 505}},
    ]}
    decisions = {f["flag_id"]: "merge" for f in doc["operations"][0]["flags"]}
    dec_doc = {"decisions": decisions, "accepted_person_ids": [992],
               "flags_sha256": FLAGS_SHA256}

    man = _build_manifest(doc, dec_doc, candidates)
    assert [op["person_id"] for op in man["operations"]] == [992]


# ---------------------------------------------------------------------------
# Finding 3: rå Python-fejl ved malformet input.
# ---------------------------------------------------------------------------


def test_operation_missing_flags_field_is_terminal():
    doc = _flags_doc()
    dec = _decisions(doc)  # bygges FØR feltet fjernes -- den skal ikke selv KeyError'e
    del doc["operations"][0]["flags"]
    with pytest.raises(SystemExit, match="C0F_MANIFEST_OP_MISSING_FIELD"):
        _build_manifest(doc, dec, _candidates())


def test_operation_invalid_person_id_is_terminal():
    doc = _flags_doc()
    dec = _decisions(doc)
    doc["operations"][0]["person_id"] = "abc"
    with pytest.raises(SystemExit, match="C0F_MANIFEST_OP_PERSON_ID_INVALID"):
        _build_manifest(doc, dec, _candidates())


# ---------------------------------------------------------------------------
# Finding 4 (minor): database_name/database_identity bliver None hvis de
# mangler i flag-dokumentet.
# ---------------------------------------------------------------------------


def test_database_name_missing_is_terminal():
    doc = _flags_doc()
    del doc["database_name"]
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DATABASE_NAME_MISSING"):
        _build_manifest(doc, _decisions(doc), _candidates())


def test_database_identity_missing_is_terminal():
    doc = _flags_doc()
    del doc["database_identity"]
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DATABASE_IDENTITY_MISSING"):
        _build_manifest(doc, _decisions(doc), _candidates())


# ---------------------------------------------------------------------------
# Runde 2, fund 1: _safe_int accepterede floats og cifferstrenge (og --
# efter en reviewer-mutation der fjernede bool-afvisningen -- bool), fordi
# den brugte en generel int(value) i stedet for type(value) is int.
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("bad_person_id", [992.9, "992", True, None])
def test_operation_person_id_rejects_non_int_types(bad_person_id):
    """Låser hver af de fire typer reviewer fremhævede: en float der
    tidligere blev trunkeret (992.9 -> 992), en cifferstreng der tidligere
    blev konverteret ("992" -> 992), True (bool er en int-underklasse i
    Python), og None. Alle fire SKAL afvises terminalt -- ingen af dem må
    stille konverteres til et gyldigt heltal."""
    doc = _flags_doc()
    dec = _decisions(doc)
    doc["operations"][0]["person_id"] = bad_person_id
    with pytest.raises(SystemExit, match="C0F_MANIFEST_OP_PERSON_ID_INVALID"):
        _build_manifest(doc, dec, _candidates())


@pytest.mark.parametrize("bad_id", [992.9, "992", True, None])
def test_accepted_person_id_rejects_non_int_types(bad_id):
    doc = _flags_doc()
    dec = _decisions(doc)
    dec["accepted_person_ids"] = [bad_id]
    with pytest.raises(SystemExit, match="C0F_MANIFEST_ACCEPTED_ID_INVALID"):
        _build_manifest(doc, dec, _candidates())


@pytest.mark.parametrize("bad_value", [660.9, "660", True, None])
def test_operation_narrative_id_rejects_non_int_types(bad_value):
    doc = _flags_doc()
    dec = _decisions(doc)
    doc["operations"][0]["narrative_id"] = bad_value
    with pytest.raises(SystemExit, match="C0F_MANIFEST_NARRATIVE_ID_INVALID"):
        _build_manifest(doc, dec, _candidates())


@pytest.mark.parametrize("bad_value", [504.5, "504", True, None])
def test_operation_page_from_rejects_non_int_types(bad_value):
    doc = _flags_doc()
    dec = _decisions(doc)
    doc["operations"][0]["page_from"] = bad_value
    with pytest.raises(SystemExit, match="C0F_MANIFEST_PAGE_FROM_INVALID"):
        _build_manifest(doc, dec, _candidates())


@pytest.mark.parametrize("bad_value", [6.5, "6", True, None])
def test_flag_char_offset_rejects_non_int_types(bad_value):
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    dec = _decisions(doc)
    doc["operations"][0]["flags"][0]["char_offset"] = bad_value
    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAG_OFFSET_INVALID"):
        _build_manifest(doc, dec, _candidates())


# ---------------------------------------------------------------------------
# Runde 2, fund 2: FLAG_NOT_FOUND-kontrollen lå EFTER "continue" for
# default-handlede flag, og default_text blev slet ikke krydstjekket mod en
# frisk normalisering af raw+corpus -- en operation koblet til en ANDEN
# records raw kunne derfor passere ubemærket, især i nul-flag-tilfældet.
# ---------------------------------------------------------------------------


def test_shifted_char_offset_is_rejected_even_for_default_action():
    """Den snævre del af fund 2: genfindingskontrollen skal gælde ALLE
    flag, ikke kun dem med en (splice-udløsende) afvigende beslutning. Et
    flag med default-handling (merge) og et forskudt offset skal også
    afvises -- den gamle placering lod "continue" springe kontrollen helt
    over for netop denne gren."""
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    dec = _decisions(doc, "merge")  # default-handling -- rammer 'continue'-grenen
    doc["operations"][0]["flags"][0]["char_offset"] += 1
    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAG_NOT_FOUND"):
        _build_manifest(doc, dec, _candidates())


def test_default_text_from_wrong_record_is_rejected():
    """Reviewer-scenariet: en operations default_text stammer fra den
    RIGTIGE tekst, men source_record_key peger på en ANDEN records raw.
    En frisk normalisering af den forkerte raw kan aldrig give samme tekst
    som den ægte default_text, så mismatchet opdages uanset flagenes
    handlinger."""
    doc = _flags_doc()
    candidates = _candidates()
    candidates["records"].append({
        "new_record_key": "record-other",
        "verbatim_text": "Noget helt andet.\n",
        "pages": {"page_from": 999, "page_to": 999},
    })
    doc["operations"][0]["source_record_key"] = "record-other"
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DEFAULT_TEXT_MISMATCH"):
        _build_manifest(doc, _decisions(doc), candidates)


def test_default_text_mismatch_detected_even_with_zero_flags():
    """Det værste tilfælde reviewer pegede på: en operation med NUL flag
    (allerede korrekt tekst, intet at afgøre for et menneske) blev IKKE
    tjekket overhovedet før denne rettelse, fordi flag-loopet i
    _decided_text simpelthen ikke kørte for en tom liste. Kontrollen skal
    fyre UAFHÆNGIGT af om der er noget at splice."""
    flags_mod = _import_flags_mod()
    clean_raw = "Rolig sætning uden orddeling.\n"
    default = flags_mod.normalize_narrative_v1(clean_raw, clean_raw)
    assert default["flags"] == []  # denne tekst har intet at afgøre

    doc = {
        "schema_version": "1939-v50-c0-followup-flags-v1",
        "database_name": DATABASE_NAME,
        "database_identity": DATABASE_IDENTITY,
        "operations": [{
            "person_id": 992, "narrative_id": 661, "old_sha256": "b" * 64,
            "source_record_key": "record-wrong", "page_from": 504,
            "default_text": default["text"],  # ægte tekst -- for clean_raw
            "flags": [],
        }],
        "flag_counts": {},
    }
    candidates = {"records": [{"new_record_key": "record-wrong",
                               "verbatim_text": "En helt anden tekst.\n",
                               "pages": {"page_from": 504, "page_to": 504}}]}
    dec_doc = {"decisions": {}, "accepted_person_ids": [992],
               "flags_sha256": FLAGS_SHA256}
    with pytest.raises(SystemExit, match="C0F_MANIFEST_DEFAULT_TEXT_MISMATCH"):
        _build_manifest(doc, dec_doc, candidates)


# ---------------------------------------------------------------------------
# Runde 2, fund 3: eksakt duplerede flag-id'er blev begge spliced, fordi to
# nul-længde-indsættelser på samme punkt ikke tælles som "overlappende" af
# det halvåbne interval-tjek ("Revent--low").
# ---------------------------------------------------------------------------


def test_duplicate_flag_id_is_rejected():
    doc = _flags_doc()
    if not doc["operations"][0]["flags"]:
        pytest.skip("fixturen gav ingen flag")
    flags = doc["operations"][0]["flags"]
    flags.append(dict(flags[0]))  # eksakt duplikat: samme flag_id/kind/offset
    dec = _decisions(doc, "keep")
    with pytest.raises(SystemExit, match="C0F_MANIFEST_FLAG_ID_DUPLICATE"):
        _build_manifest(doc, dec, _candidates())
