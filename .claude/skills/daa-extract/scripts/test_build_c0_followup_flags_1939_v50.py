"""DB-frie tests for build_c0_followup_flags_1939_v50.py."""
import importlib.util
import json
import pathlib
import pytest

_DIR = pathlib.Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location(
    "c0f_flags", _DIR / "build_c0_followup_flags_1939_v50.py")
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)

SHA = "a" * 64
IDS = [963, 967, 978, 991, 992, 1296, 1297, 1298, 1299]


def _selection(**kw):
    sel = [{"person_id": p, "narrative_id": 600 + i, "old_sha256": SHA,
            "privat": False, "side": "508"} for i, p in enumerate(IDS)]
    doc = {"schema_version": "1.0", "selected": sel,
           "database_name": "postgres", "database_identity": "764273"}
    doc.update(kw)
    return doc


def _decision_rows():
    """De rå [KOBL]-rækker som build_flags_document nu udleder
    record_by_person af -- se _derive_record_by_person i implementeringen
    for hvorfor kontrollen bor her og ikke som en færdig dict."""
    return [{"token": "[KOBL]", "person_id": p, "new_record_key": "record-%032x" % p}
            for p in IDS]


def _candidates(text="Ditlev til Wittenberg.\n"):
    return {"records": [{"new_record_key": "record-%032x" % p,
                         "verbatim_text": text,
                         "pages": {"page_from": 508, "page_to": 508}}
                        for p in IDS]}


def test_happy_path_produces_nine_operations():
    doc = mod.build_flags_document(_selection(), _candidates(), _decision_rows())
    assert len(doc["operations"]) == 9
    assert [op["person_id"] for op in doc["operations"]] == IDS
    assert doc["schema_version"] == "1939-v50-c0-followup-flags-v1"


def test_database_identity_is_carried_through():
    """Uden den kan en eksport fra rehearsal-basen føde et manifest, der køres
    mod prod. D2 spærrede for det med D2_APPLY_DATABASE_MISMATCH. Dette er
    kun den POSITIVE pass-through-test -- selve gaten (krav om tilstedeværelse
    og ikke-tomhed) håndhæves og testes af test_missing_database_name_is_terminal
    m.fl. længere nede. kwargs er eksplicitte her (selvom _selection() nu også
    sætter dem som default) for at bevise pass-through frem for default-værdi."""
    doc = mod.build_flags_document(
        _selection(database_name="postgres", database_identity="764273"),
        _candidates(), _decision_rows())
    assert doc["database_name"] == "postgres"
    assert doc["database_identity"] == "764273"


def test_default_text_is_normalized_not_raw():
    """Rå OCR må ALDRIG nå manifestet: alle ni records har enlige linjeskift,
    og 1299 bærer '### PAGE'. Uden normalisering ville fasen indføre rå tekst
    i en bestand af 551 rensede narrativer."""
    doc = mod.build_flags_document(
        _selection(), _candidates("Revent-\nlow til Gaarz.\n\n### PAGE 0063 ###\n"),
        _decision_rows())
    for op in doc["operations"]:
        assert "### PAGE" not in op["default_text"]
        assert "-\n" not in op["default_text"]
        assert not op["default_text"].endswith(("\n", " "))


def test_side_mismatch_is_terminal():
    """narrative.side vs recordens page_from er en IDENTITETSKONTROL: den
    beviser at vi rammer den rigtige post. Målt 2026-08-21: 9/9 match."""
    sel = _selection()
    sel["selected"][0]["side"] = "999"
    with pytest.raises(SystemExit, match="C0F_FLAGS_SIDE_MISMATCH"):
        mod.build_flags_document(sel, _candidates(), _decision_rows())


def test_side_null_is_terminal():
    sel = _selection()
    sel["selected"][0]["side"] = None
    with pytest.raises(SystemExit, match="C0F_FLAGS_SIDE_MISSING"):
        mod.build_flags_document(sel, _candidates(), _decision_rows())


def test_missing_record_is_terminal():
    rows = [r for r in _decision_rows() if r["person_id"] != 963]
    with pytest.raises(SystemExit, match="C0F_FLAGS_RECORD_MISSING"):
        mod.build_flags_document(_selection(), _candidates(), rows)


def test_person_1017_is_rejected():
    """1017 er flyttet til C3: dens kobling ville slette ~92 tegn permanent."""
    sel = _selection()
    sel["selected"][0]["person_id"] = 1017
    with pytest.raises(SystemExit, match="C0F_FLAGS_IDS_INVALID"):
        mod.build_flags_document(sel, _candidates(), _decision_rows())


def test_empty_normalized_text_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_TEXT_EMPTY"):
        mod.build_flags_document(_selection(), _candidates("   \n  "),
                                 _decision_rows())


def test_flag_ids_are_globally_unique_and_locally_sorted():
    """Sorteringsgarantien er PER OPERATION (``flags.sort()`` sker inden i
    per-person-loopet i build_flags_document). Med ægte UUID-record-nøgler
    holder GLOBAL sortering på tværs af operationer IKKE -- kun fixturens
    zero-paddede hex-nøgler (record-%032x) giver det udseende ved et
    tilfælde, fordi de tilfældigvis følger person_id-orden. Test den
    kontrakt koden faktisk giver, ikke en der kun holder i fixture-rummet."""
    doc = mod.build_flags_document(
        _selection(), _candidates("Revent-\nlow og Futter-\nkamp.\n"),
        _decision_rows())
    all_ids = [f["flag_id"] for op in doc["operations"] for f in op["flags"]]
    assert len(all_ids) == len(set(all_ids))  # globalt unikke (nøgle-praefiks er unik pr. person)
    for op in doc["operations"]:
        ids = [f["flag_id"] for f in op["flags"]]
        assert ids == sorted(ids)  # kun DENNE sortering er en kontrakt


def test_flag_id_collision_is_terminal(monkeypatch):
    """Kollisionsgaten skal bevise sig selv ved rent faktisk at fyre -- ikke
    bare bestå fordi ingen test rammer den. En ægte kollision (samme
    record-nøgle, samme char_offset, samme kind) kan efter
    C0F_FLAGS_DUPLICATE_RECORD_KEY ikke længere opstå ved at to personer
    deler nøgle, så den tvinges her frem ved at monkeypatche
    normalize_narrative_v1 til at returnere to identiske flag for én record.
    Efter DUPLICATE_RECORD_KEY er dette IKKE en dataform-kontrol længere, men
    en normalizer-invariant-backstop: intet input Task 3/4 kan konstruere
    burde kunne fyre den i praksis."""
    def _fake_normalize(raw, corpus):
        return {"text": raw.strip(), "flags": [
            {"char_offset": 3, "kind": "hyphen_unproven"},
            {"char_offset": 3, "kind": "hyphen_unproven"},
        ]}

    monkeypatch.setattr(mod, "normalize_narrative_v1", _fake_normalize)
    with pytest.raises(SystemExit, match="C0F_FLAGS_ID_COLLISION"):
        mod.build_flags_document(_selection(), _candidates(), _decision_rows())


def test_missing_database_name_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_DATABASE_NAME_MISSING"):
        mod.build_flags_document(_selection(database_name=None), _candidates(),
                                 _decision_rows())


def test_blank_database_name_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_DATABASE_NAME_MISSING"):
        mod.build_flags_document(_selection(database_name="   "), _candidates(),
                                 _decision_rows())


def test_missing_database_identity_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_DATABASE_IDENTITY_MISSING"):
        mod.build_flags_document(_selection(database_identity=None), _candidates(),
                                 _decision_rows())


def test_blank_database_identity_is_terminal():
    with pytest.raises(SystemExit, match="C0F_FLAGS_DATABASE_IDENTITY_MISSING"):
        mod.build_flags_document(_selection(database_identity=""), _candidates(),
                                 _decision_rows())


def test_duplicate_person_id_via_direct_call_is_terminal():
    """Reviewerens skarpeste fund: en Dict[int, str] kan ikke bære beviset
    for at to rækker konkurrerede om samme person_id -- den information er
    udslettet før build_flags_document nogensinde ser en dict. Derfor
    modtager funktionen nu de RÅ decision_rows og udleder selv, med begge
    kontroller på det sted dubletterne stadig er synlige. Denne test rammer
    build_flags_document DIREKTE (ikke kun via main()), og beviser dermed at
    ingen kalder kan omgå kontrollen ved selv at bygge en færdig dict."""
    rows = _decision_rows()
    rows.append({"token": "[KOBL]", "person_id": IDS[0],
                "new_record_key": "record-%032x" % (IDS[0] + 100000)})
    with pytest.raises(SystemExit, match="C0F_FLAGS_DUPLICATE_PERSON_ID"):
        mod.build_flags_document(_selection(), _candidates(), rows)


def test_reused_record_key_via_direct_call_is_terminal():
    """Reviewerens oprindelige reproduktion: to personer der peger på samme
    record-nøgle må IKKE stiltiende give begge samme tekst -- writeren kunne
    senere erstatte den enes biografi med den andens. Rammer
    build_flags_document DIREKTE via decision_rows, ikke kun via main()."""
    rows = _decision_rows()
    rows[1] = {"token": "[KOBL]", "person_id": IDS[1],
              "new_record_key": rows[0]["new_record_key"]}  # 967 genbruger 963's nøgle
    with pytest.raises(SystemExit, match="C0F_FLAGS_DUPLICATE_RECORD_KEY"):
        mod.build_flags_document(_selection(), _candidates(), rows)


def test_key_shared_with_excluded_person_is_terminal():
    """Tredje re-review: kollisionskontrollen daekkede kun de ni, saa en
    noegle delt mellem en scoped person og en EKSKLUDERET person (fx 1017,
    som er bevidst udeladt fordi dens kobling ville slette ~92 tegn
    permanent) var usynlig -- 1017's raekke blev filtreret vaek FOER
    key_owner nogensinde saa den. Maalt mod de aegte data (2026-08-21): 10
    [KOBL]-raekker, 10 unikke noegler, ingen kollision i praksis -- rent
    latent, men samme fejlklasse som blev lukket for de to scopede retninger.
    Denne test bruger 1017 helt konkret, ikke et vilkaarligt tal udenfor
    PERSON_IDS, for at spejle det virkelige scenarie."""
    rows = _decision_rows()
    shared_key = rows[0]["new_record_key"]  # 963's noegle
    rows.append({"token": "[KOBL]", "person_id": 1017, "new_record_key": shared_key})
    with pytest.raises(SystemExit, match="C0F_FLAGS_DUPLICATE_RECORD_KEY"):
        mod.build_flags_document(_selection(), _candidates(), rows)


def test_kobl_row_missing_person_id_is_terminal():
    """En [KOBL]-raekke uden person_id maa IKKE naa row["new_record_key"]
    eller int(pid) og fejle med en bar exception -- den funktion der skal
    vaere selv-garanterende giver en C0F_-kode ligesom alt andet her."""
    rows = _decision_rows()
    rows.append({"token": "[KOBL]", "new_record_key": "record-uden-person-id"})
    with pytest.raises(SystemExit, match="C0F_FLAGS_KOBL_ROW_MISSING_PERSON_ID"):
        mod.build_flags_document(_selection(), _candidates(), rows)


def test_kobl_row_missing_record_key_is_terminal():
    """Samme princip som ovenfor, for det andet paakraevede felt: en
    [KOBL]-raekke uden new_record_key gav tidligere en bar KeyError ved
    row["new_record_key"] -- nu en C0F_-kode."""
    rows = _decision_rows()
    rows.append({"token": "[KOBL]", "person_id": 1017})
    with pytest.raises(SystemExit, match="C0F_FLAGS_KOBL_ROW_MISSING_RECORD_KEY"):
        mod.build_flags_document(_selection(), _candidates(), rows)


def _write_json(path, obj):
    path.write_text(json.dumps(obj), encoding="utf-8")


def _run_main(tmp_path, decisions, selection=None, candidates=None):
    """Kører main() ende-til-ende via temp-filer -- bekræfter at CLI-laget
    fortsat sender de rå rækker uændret videre til build_flags_document."""
    sel_path = tmp_path / "selection.json"
    cand_path = tmp_path / "candidates.json"
    dec_path = tmp_path / "decisions.json"
    out_path = tmp_path / "out.json"
    _write_json(sel_path, selection if selection is not None else _selection())
    _write_json(cand_path, candidates if candidates is not None else _candidates())
    _write_json(dec_path, decisions)
    return mod.main(["--selection", str(sel_path), "--candidates", str(cand_path),
                     "--decisions", str(dec_path), "--output", str(out_path)])


def test_main_rejects_duplicate_person_id_in_decisions(tmp_path):
    """Samme defekt som test_duplicate_person_id_via_direct_call_is_terminal,
    men gennem hele CLI-stien (JSON-filer -> main() -> build_flags_document)
    for at bevise at intet går tabt i main()'s tyndere lag."""
    rows = _decision_rows()
    rows.append({"token": "[KOBL]", "person_id": IDS[0],
                "new_record_key": "record-%032x" % (IDS[0] + 100000)})
    decisions = {"schema_version": "1.0", "decisions": rows}
    with pytest.raises(SystemExit, match="C0F_FLAGS_DUPLICATE_PERSON_ID"):
        _run_main(tmp_path, decisions)


def test_main_rejects_reused_record_key_via_decisions(tmp_path):
    """Samme defekt som test_reused_record_key_via_direct_call_is_terminal,
    men gennem hele CLI-stien."""
    rows = _decision_rows()
    rows[1] = {"token": "[KOBL]", "person_id": IDS[1],
              "new_record_key": rows[0]["new_record_key"]}
    decisions = {"schema_version": "1.0", "decisions": rows}
    with pytest.raises(SystemExit, match="C0F_FLAGS_DUPLICATE_RECORD_KEY"):
        _run_main(tmp_path, decisions)
