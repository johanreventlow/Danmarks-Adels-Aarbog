"""Trin 5b 2b-ii runde 2 (spec §17.4-17.5): navneregel v3. Kun opdigtede navne."""
import json
import re
from pathlib import Path

import pytest

import relation_persona_extract_v3 as v3


def row(text, raw, partners=(), principal=1, ordinal=1, key="k1"):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "occurrence_id": "occ-II-1", "marriage_ordinal": ordinal, "supporting_count": 1, "principal_ok": principal is not None,
            "principal_person_id": principal, "principal_partners": list(partners), "post_text": "Anna A. " + text,
            "clauses": [{"observation_id": "o1", "clause_set_seq": 1, "clause_set_sha256": "a" * 64,
                         "verbatim_text": text, "post_char_from": 8, "post_char_to": 8 + len(text)}]}


def partner(pid, navn, ordinal=1, fam=3):
    return {"person_id": pid, "family_id": fam, "ordinal": ordinal, "navn": navn}


def name_of(text, p):
    return text[p["name_from"]:p["name_to"]]


def test_titel_inde_i_navnet_kommer_med():
    t = "Gift 1890 med Ida komtesse Dal, f. 1801."
    p = v3.propose(row(t, "Gift med Ida komtesse Dal", [partner(7, "Ida Dal")]), 1906)
    assert p["tok"] == "S" and p["partner_person_id"] == 7 and name_of(t, p) == "Ida komtesse Dal"


def test_rigs_og_lens_praefiks():
    assert v3.is_title("rigsgrevinde") and v3.is_title("Lensgreve") and v3.is_title("komtesse")
    assert not v3.is_title("rigs") and not v3.is_title("grevskab") and not v3.is_title("Dal")


def test_partikelkaede_von_und_zu():
    t = "Gift 1890 med Eva von und zu Fik."
    p = v3.propose(row(t, "Gift med Eva von und zu Fik"), 1906)
    assert name_of(t, p) == "Eva von und zu Fik" and p["tok"] == "D" and p["clause_years"] == [1890]


def test_genannt_og_dem():
    t = "Gift 1890 med Ulf genannt von dem Hagen."
    p = v3.propose(row(t, "Gift med Ulf genannt von dem Hagen"), 1906)
    assert name_of(t, p) == "Ulf genannt von dem Hagen"


def test_efternavn_skal_passe():
    # samme fornavn, andet efternavn ⇒ intet træf (v2 gav S på fornavnet alene)
    assert not v3.partner_hit("Eva von Fik", "Eva von Gro")
    assert v3.partner_hit("Eva komtesse von Fik", "Eva Fik")


def test_partner_med_aarstal_i_navnet():
    assert v3.partner_hit("Ida Dal", "Ida Dal (1850)")


def test_to_traef_afgoeres_af_nummer():
    t = "Gift 2. gang 1890 med Eva von Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Maria Fik", ordinal=2, fam=4)]
    p = v3.propose(row(t, "Gift med Eva von Fik", rows, ordinal=2), 1906)
    assert p["tok"] == "S" and p["partner_person_id"] == 8 and p["reason"] == "partnermatch_nummer"


def test_to_traef_uden_afgoerelse_giver_U():
    t = "Gift 1890 med Eva Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=1, fam=4)]
    assert v3.propose(row(t, "Gift med Eva Fik", rows, ordinal=2), 1906)["tok"] == "U"


def test_skaevt_nummer_ved_eet_traef_er_stadig_S():
    t = "Gift 1890 med Ida Dal."
    p = v3.propose(row(t, "Gift med Ida Dal", [partner(7, "Ida Dal", ordinal=2)], ordinal=1), 1906)
    assert p["tok"] == "S" and p["partner_ordinal"] == 2


def test_D_og_N_kraever_nul_traef():
    # Linje 5's fælde: to træf og intet afgørende nummer må aldrig blive D
    t = "Gift 1890 med Eva Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=3, fam=4)]
    assert v3.propose(row(t, "Gift med Eva Fik", rows, ordinal=2), 1906)["tok"] == "U"


def test_kapitaliseret_titel_foer_navnet_giver_ikke_D():
    t = "Gift 1890 med Komtesse Ida Dal."
    p = v3.propose(row(t, "Gift med Komtesse Ida Dal"), 1906)
    assert p["tok"] == "U" and p["reason"] == "titel_i_navn"


def test_ukendt_titel_giver_U():
    # spec §17.9: »markise« er ikke på listen, så reglen stopper før den (afkortet til »Ida«). Et afkortet navn
    # må aldrig blive D; forslaget er U, og navnet står på arket, så mennesket kan rette med navn:.
    t = "Gift 1890 med Ida markise Dal."
    p = v3.propose(row(t, "Gift med Ida markise Dal"), 1906)
    assert p["tok"] == "U" and p["reason"] == "navn_afkortet" and name_of(t, p) == "Ida"


def test_afkortning_ved_bindestreg_og_forkortelse():
    # final review F1: et småord med bindestreg eller punktum foran et versalord er også en afkortning
    for t in ("Gift 1890 med Ida rigs-grevinde Dal.", "Gift 1890 med Ida f. Dal."):
        p = v3.propose(row(t, t[:-1]), 1906)
        assert p["tok"] == "U" and p["reason"] == "navn_afkortet" and name_of(t, p) == "Ida", t


def test_foedselsaar_efter_navnet_er_ikke_afkortning():
    t = "Gift 1890 med Ida Dal f. 1801."
    p = v3.propose(row(t, "Gift med Ida Dal"), 1906)
    assert p["tok"] == "D" and name_of(t, p) == "Ida Dal"


def test_efternavn_alene_er_ikke_partnertraef():
    # final review F2: samme efternavn, andet fornavn ⇒ ikke S, og heller ikke D (partneren ligner)
    assert not v3.partner_hit("Eva Fik", "Ida Fik")
    t = "Gift 1890 med Eva Fik."
    p = v3.propose(row(t, "Gift med Eva Fik", [partner(7, "Ida Fik")]), 1906)
    assert p["tok"] == "U" and p["reason"] == "partner_ligner"


def test_naesten_dublet_giver_ikke_D():
    t = "Gift 1890 med Anna Dal Hansen."
    p = v3.propose(row(t, "Gift med Anna Dal Hansen", [partner(7, "Anna Sophie Daal")]), 1906)
    assert p["tok"] == "U" and p["reason"] == "partner_ligner"


def test_rettet_navn_tjekkes_ogsaa_mod_regelnavnet():
    # et kortere rettet navn må ikke skjule, at regelens navn ligner en eksisterende partner
    t = "Gift 1890 med Ida Dal Hansen."
    p = v3.propose(row(t, "Gift med Ida Dal Hansen", [partner(7, "Bo Hansen")]), 1906, name_override="Ida Dal")
    assert p["tok"] == "U" and p["reason"] == "partner_ligner"


def test_til_gods_er_ikke_afkortning():
    # »til <gods>« er ikke en del af navnet (beslutning 2026-10-03) og udløser ikke navn_afkortet
    t = "Gift 1890 med Ida Dal til Ørum."
    p = v3.propose(row(t, "Gift med Ida Dal til Ørum"), 1906)
    assert p["tok"] == "D" and name_of(t, p) == "Ida Dal"


def test_navnerettelse_forlaenger_slutningen():
    # reglen stopper før det ulistede »markise« (U); rettelsen forlænger navnet, og så findes partneren
    t = "Gift 1890 med Ida markise Dal, f. 1801."
    r = row(t, "Gift med Ida markise Dal", [partner(7, "Ida Dal")])
    assert v3.propose(r, 1906)["tok"] == "U"
    p = v3.propose(r, 1906, name_override="Ida markise Dal")
    assert p["tok"] == "S" and p["name_basis"] == "sheet" and name_of(t, p) == "Ida markise Dal"


def test_komma_efter_efternavnet_bag_en_titel():
    # vinduet rækker ud over navnet, så kommaet ligger inde i segmentet (Fable-review af planen, fund 1)
    t = "Gift 1890 med Ida komtesse Dal, datter af Ole Hak."
    p = v3.propose(row(t, "Gift med Ida komtesse Dal, datter af Ole Hak", [partner(7, "Ida Dal")]), 1906)
    assert p["tok"] == "S" and name_of(t, p) == "Ida komtesse Dal"


def test_flere_partnere_og_titel_viser_stadig_navnet():
    # arket skal vise regelens navn netop dér, hvor mennesket skal rette med navn:
    t = "Gift 1890 med Eva Fik."
    rows = [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=1, fam=4)]
    p = v3.propose(row(t, "Gift med Eva Fik", rows, ordinal=2), 1906)
    assert p["reason"] == "flere_partnere" and name_of(t, p) == "Eva Fik"
    t2 = "Gift 1890 med Komtesse Ida Dal."
    p2 = v3.propose(row(t2, "Gift med Komtesse Ida Dal"), 1906)
    assert p2["reason"] == "titel_i_navn" and name_of(t2, p2) == "Komtesse Ida Dal"


def test_navnerettelse_skal_slutte_ved_helt_ord():
    t = "Gift 1890 med Ida Dal, f. 1801."
    for bad in ("Ida Da", "Ida Dal,"):
        with pytest.raises(v3.NameOverrideError):
            v3.propose(row(t, "Gift med Ida Dal"), 1906, name_override=bad)


def test_navnerettelse_uden_navnestart_afvises():
    # tidlige U (her: intet nummer) må ikke sluge en navn:-rettelse tavst (spec §17.6)
    t = "Gift 1890 med Ida Dal."
    with pytest.raises(v3.NameOverrideError):
        v3.propose(row(t, "Gift med Ida Dal", ordinal=None), 1906, name_override="Ida Dal")


def test_bindestregstitel_fanges_som_i_sql():
    # SQL-tvillingen deler på alle ikke-bogstaver; Python skal fange det samme allerede på arket
    assert not v3.title_free("Ida Rigs-Grevinde Dal")


def test_navnerettelse_skal_starte_ved_navnestarten():
    t = "Gift 1890 med Ida Dal, datter af Ole Dal."
    with pytest.raises(v3.NameOverrideError):
        v3.propose(row(t, "Gift med Ida Dal, datter af Ole Dal", [partner(7, "Ole Dal")]), 1906, name_override="Ole Dal")
    with pytest.raises(v3.NameOverrideError):
        v3.propose(row(t, "Gift med Ida Dal, datter af Ole Dal"), 1906, name_override="Ida Dalx")


def test_regelnavn_har_basis_rule():
    t = "Gift 1890 med Ida Dal."
    assert v3.propose(row(t, "Gift med Ida Dal"), 1906)["name_basis"] == "rule"


def prow(**kw):
    base = {"source_persona_id": "00000000-0000-0000-0000-000000000001", "identity_version": 1,
            "previous": {"basis": "web_detail", "note": "kø", "decided_at": "2026-10-13"},
            "name_text": "Gro von Hak", "clause_text": "Gift 1314 med Gro von Hak.", "clause_is_current": True,
            "post_text": "Carl C. Gift 1314 med Gro von Hak.", "marriage_ordinal": 1, "principal_person_id": 5,
            "principal_partners": []}
    return {**base, **kw}


def test_P_D_ved_gammelt_aar():
    p = v3.propose_redecide(prow(), 1906)
    assert p == {"tok": "D", "reason": "aldersregel", "clause_years": [1314]}


def test_P_partner_findes_giver_U():
    assert v3.propose_redecide(prow(principal_partners=[partner(9, "Gro Hak")]), 1906)["tok"] == "U"


def test_P_lignende_partner_giver_U():
    # final review F2: P-linjen opretter en ny person, så dubletværnet er det løse (ét fælles kerneord)
    p = v3.propose_redecide(prow(principal_partners=[partner(9, "Gro Dal")]), 1906)
    assert p["tok"] == "U" and p["reason"] == "partner_findes"


def test_P_titel_og_afloest_klausul_og_nyt_aar():
    assert v3.propose_redecide(prow(name_text="Gro komtesse Hak"), 1906)["tok"] == "U"
    assert v3.propose_redecide(prow(clause_is_current=False), 1906)["tok"] == "U"
    assert v3.propose_redecide(prow(clause_text="Gift 1950 med Gro von Hak."), 1906)["tok"] == "N"
    assert v3.propose_redecide(prow(marriage_ordinal=None), 1906)["tok"] == "U"


def test_title_words_match_schema():
    # Tvillingtest (spec §17.5): listen i Python = array-literalen i private.relation_title_words() i schema.sql
    schema = (Path(__file__).resolve().parents[4] / "schema.sql").read_text(encoding="utf-8")
    m = re.search(r"FUNCTION private\.relation_title_words\(\).*?ARRAY\[(.*?)\]", schema, re.S)
    assert m, "private.relation_title_words() mangler i schema.sql"
    assert tuple(re.findall(r"'([a-zæøå]+)'", m.group(1))) == v3.TITLE_WORDS
    m2 = re.search(r"FUNCTION private\.relation_name_has_title\(.*?\^\((\w+)\|(\w+)\)", schema, re.S)
    assert m2 and (m2.group(1), m2.group(2)) == v3.TITLE_PREFIXES


# #244 (spec §5): bogens »g. N°« — paritet med SQL (tests/fixtures/relation-book-ordinal.json) og værnet.
BOOK_FIXTURE = Path(__file__).resolve().parents[4] / "tests" / "fixtures" / "relation-book-ordinal.json"


def test_book_ordinal_paritet():
    for case in json.loads(BOOK_FIXTURE.read_text(encoding="utf-8")):
        assert v3.book_ordinal(case["raw"]) == case["expect"], case["raw"]


def test_book_ordinal_none():
    assert v3.book_ordinal(None) is None


def test_nummer_modsiger_bog():
    t = "g. 2° m. Bo Beta, f. 1801."
    assert v3.propose(row(t, t, ordinal=1), 1906)["reason"] == "nummer_modsiger_bog"
    assert v3.propose(row(t, t, ordinal=2), 1906)["reason"] != "nummer_modsiger_bog"


# --- Trin 6d-3: profilen som data (CLI --profile) --------------------------------------------------------------------
import hashlib
import subprocess
import sys

SCRIPT = Path(__file__).parent / "relation_persona_extract_v3.py"
PROFILES = Path(__file__).resolve().parents[1] / "profiles"
P_2018 = PROFILES / "relation-persona-2018-20.json"
P_1939 = PROFILES / "relation-persona-1939.json"


def other_row(predicate, raw, text, key, record="II-9", post_from=40):
    r = row(text, raw, key=key)
    r.update(predicate=predicate, marriage_ordinal=None, record_key=record)
    r["clauses"][0].update(post_char_from=post_from, post_char_to=post_from + len(text))
    return r


V1_KEYS = ("interpretation_key", "interpretation_version", "predicate", "raw", "record_key", "occurrence_id", "marriage_ordinal",
           "supporting_count", "clauses", "principal_ok")


def v1_of(r):
    """v1-inputtets række (red_relation_persona_input): uden hovedperson-id, partnere og posttekst."""
    return {k: r[k] for k in V1_KEYS}


def run_cli(tmp_path, v1_rows, *extra, v3_rows=None, cutoff=1906, name="m.json", expect_ok=True, claimed="auto"):
    inp = tmp_path / "in.json"
    doc = {"input": v1_rows}
    if claimed is not None:
        doc["input_sha256"] = v3.canonical_sha256(v1_rows) if claimed == "auto" else claimed
    inp.write_text(json.dumps(doc), encoding="utf-8")
    args = ["--input", str(inp), "--out", str(tmp_path / name)]
    if v3_rows is not None:
        i3 = tmp_path / "in3.json"
        i3.write_text(json.dumps({"contract": "relation-persona-v3-input", "source_id": 1, "deceased_cutoff_year": cutoff,
                                  "rows": v3_rows, "redecide_rows": []}), encoding="utf-8")
        args += ["--v3-input", str(i3)]
    r = subprocess.run([sys.executable, str(SCRIPT), *args, *extra], capture_output=True, text=True)
    if not expect_ok:
        assert r.returncode != 0 and not (tmp_path / name).exists()
        return r.stderr
    assert r.returncode == 0, r.stderr
    return (tmp_path / name).read_bytes(), r.stdout


def test_profile_1939_parent_v1_payload(tmp_path):
    parent = other_row("relation.parent", "Datter af Ole Beta", "Anna, Datter af Ole Beta, f. 1801.", "p1")
    body, _ = run_cli(tmp_path, [parent], "--profile", str(P_1939))        # ingen v3-prædikater i rækkerne: v3-input ikke nødvendigt
    e = json.loads(body)["authorized_elements"]["relation-persona:p1"]
    assert e["profile"] == "relation-persona-1939-v1" and e["predicate"] == "relation.parent"
    assert "name_basis" not in e and "sheet_sha256" not in e and "sheet_line" not in e   # v1-form, ingen v3-nøgler
    assert e["name_from"] is None and e["name_to"] is None and e["marriage_ordinal"] is None
    t = parent["clauses"][0]["verbatim_text"]
    assert t[e["span_from"]:e["span_to"]] == "Datter af Ole Beta" and e["post_offset"] == 40 + e["span_from"]


def test_profile_1939_child_parked(tmp_path):
    child = other_row("relation.child", "Datter Dora", "Datter Dora, f. 1830.", "c1")
    body, out = run_cli(tmp_path, [child], "--profile", str(P_1939))
    assert json.loads(body)["authorized_elements"] == {}
    assert '"praedikat_ikke_i_profil": 1' in out


def test_profile_1939_marriage_v3_over_raw_text(tmp_path):
    t = "Gift 1890 med Ida Bran-\ndenburg, f. 1801."   # orddeling i klausulen: raw-tekstform finder vinduet
    m_row = row(t, "Gift med Ida Brandenburg", key="m1")
    m = m_row
    body, _ = run_cli(tmp_path, [v1_of(m)], "--profile", str(P_1939), v3_rows=[m_row])
    e = json.loads(body)["authorized_elements"]["relation-persona:m1"]
    assert e["profile"] == "relation-persona-1939-v1" and e["name_basis"] == "rule" and e["sheet_line"] == 1
    v3_sha = hashlib.sha256((tmp_path / "in3.json").read_bytes()).hexdigest()
    assert e["sheet_sha256"] == v3_sha
    mf = json.loads(body)
    assert mf["v3_input_file_sha256"] == v3_sha and mf["v1_input_file_sha256"] == hashlib.sha256((tmp_path / "in.json").read_bytes()).hexdigest()
    assert mf["input_sha256"] == v3.canonical_sha256([v1_of(m_row)])
    assert t[e["name_from"]:e["name_to"]] == "Ida Bran-\ndenburg"   # originalens positioner, over orddelingen
    # samme tekst med 2018-20-profilen (folded): intet vindue, parkeret
    body2, out2 = run_cli(tmp_path, [v1_of(m)], v3_rows=[m], name="m2.json")
    assert json.loads(body2)["authorized_elements"] == {} and "intet_vindue" in out2


U1, U2, U3, U4 = (f"00000000-0000-0000-0000-00000000000{c}" for c in "1234")


def mixed_rows():
    """Opdigtede ægteskaber: S, D, N, partner_ligner, flere_partnere, titel_i_navn, intet_vindue (alle med partnere)."""
    return [
        row("Gift 1890 med Ida Dal, f. 1801.", "Gift med Ida Dal", [partner(7, "Ida Dal")], key="00000000-0000-0000-0000-000000000001"),
        row("Gift 1850 med Eva von Fik.", "Gift med Eva von Fik", key="00000000-0000-0000-0000-000000000002", ordinal=2),
        row("Gift 1950 med Bo Gro.", "Gift med Bo Gro", key="00000000-0000-0000-0000-000000000003", ordinal=3),
        # partner_ligner: ligner en eksisterende partner uden at ramme (kun ét fælles kerneord)
        row("Gift 1890 med Eva Fik.", "Gift med Eva Fik", [partner(7, "Ida Fik")], key="00000000-0000-0000-0000-000000000004"),
        # flere_partnere: to partnere rammer, ingen afgørende
        row("Gift 1890 med Eva Fik.", "Gift med Eva Fik",
            [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=3, fam=4)],
            key="00000000-0000-0000-0000-000000000005", ordinal=2),
        row("Gift 1890 med Komtesse Ida Dal.", "Gift med Komtesse Ida Dal", key="00000000-0000-0000-0000-000000000006"),
        row("Gift 1890 med Ida Dal.", "Gift med Ulla Dal", key="00000000-0000-0000-0000-000000000007"),
    ]


def sheet_flow_manifest(rows, cutoff, sha, profile=None):
    """Arkflowet for real: render -> parse -> validér -> persona-manifest med alle forslag uændrede."""
    import relation_marriage_sheet_v3 as sh
    rows3 = {"rows": rows, "deceased_cutoff_year": cutoff, "redecide_rows": []}
    text = sh.render_sheet(rows3, profile)
    lines = sh.parse_sheet(text)
    m_props, _ = sh.check_sheet(lines, rows3, profile)
    return m_props, sh.persona_manifest(lines, rows3, sheet_sha256=sha, profile=profile)


def raw_mixed_rows():
    """Rå 1939-tekst: orddeling, linjeskift, sidemarkør og CRLF + partnerregler (uden dubletter)."""
    return [
        row("Gift 1890 med Ida Bran-\ndenburg, f. 1801.", "Gift med Ida Brandenburg", key="00000000-0000-0000-0000-000000000001"),
        row("Gift 1890 med Eva\r\nvon Fik, f. 1801.", "Gift med Eva von Fik", [partner(7, "Eva Fik")],
            key="00000000-0000-0000-0000-000000000002"),
        row("Gift 1950 med Bo\n### PAGE 12 ###\nGro.", "Gift med Bo Gro", key="00000000-0000-0000-0000-000000000003", ordinal=2),
        row("Gift 1890 med Eva Fik.", "Gift med Eva Fik", [partner(7, "Ida Fik")], key="00000000-0000-0000-0000-000000000004"),
        row("Gift 1890 med Eva Fik.", "Gift med Eva Fik",
            [partner(7, "Eva Fik", ordinal=1, fam=3), partner(8, "Eva Fik", ordinal=3, fam=4)],
            key="00000000-0000-0000-0000-000000000005", ordinal=2),
    ]


@pytest.mark.parametrize("profile_file,rows_fn", [(P_2018, mixed_rows), (P_1939, raw_mixed_rows)])
def test_cli_lig_arkflowet_og_parkerer_partnerregler(tmp_path, profile_file, rows_fn):
    rows = rows_fn()
    body, out = run_cli(tmp_path, [v1_of(r) for r in rows], "--profile", str(profile_file), v3_rows=rows)
    got = json.loads(body)
    v3_sha = hashlib.sha256((tmp_path / "in3.json").read_bytes()).hexdigest()
    props, expected = sheet_flow_manifest(rows, 1906, v3_sha, v3.load_profile(profile_file))
    assert {"partner_ligner", "flere_partnere"} <= {p["reason"] for p in props}
    assert got["authorized_elements"] == expected["authorized_elements"]
    assert got["expected_counts"] == expected["expected_counts"]
    # partner_ligner og flere_partnere er parkeret, ikke elementer
    assert "relation-persona:00000000-0000-0000-0000-000000000004" not in got["authorized_elements"]
    assert "relation-persona:00000000-0000-0000-0000-000000000005" not in got["authorized_elements"]
    assert '"partner_ligner": 1' in out and '"flere_partnere": 1' in out
    if profile_file == P_1939:   # rå tekst giver elementer (ikke intet_vindue)
        assert "relation-persona:00000000-0000-0000-0000-000000000001" in got["authorized_elements"]


def test_cli_parkerer_dubletter(tmp_path):
    # Bevidst forskel fra arket (se kommentaren i extract_rows): to ægteskaber på samme post, samme offset og
    # spændlængde parkeres begge. Derfor er tilfældet udeladt fra parity-testen ovenfor.
    t = "Gift 1890 med Ida Dal, f. 1801."
    a = row(t, "Gift med Ida Dal", key="00000000-0000-0000-0000-00000000000a")
    b = row(t, "Gift med Ida Dal", key="00000000-0000-0000-0000-00000000000b", ordinal=2)
    body, out = run_cli(tmp_path, [v1_of(a), v1_of(b)], v3_rows=[a, b])
    assert json.loads(body)["authorized_elements"] == {} and '"dublet": 2' in out


FIX = Path(__file__).parent / "fixtures"


def test_cli_default_golden(tmp_path):
    # Fast facit for standardprofilen: inputfilerne og det forventede manifest ligger i fixtures/ (opdigtede personer).
    out = tmp_path / "m.json"
    r = subprocess.run([sys.executable, str(SCRIPT), "--input", str(FIX / "relation-extract-v1-input.json"),
                        "--v3-input", str(FIX / "relation-extract-v3-input.json"), "--out", str(out)],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    assert out.read_bytes() == (FIX / "relation-extract-default-golden.json").read_bytes()


@pytest.mark.parametrize("field,value", [("supporting_count", 2), ("record_key", "II-2"), ("occurrence_id", "occ-andet"),
                                         ("interpretation_version", 2), ("predicate", "relation.child"), ("raw", "Gift med Ida"),
                                         ("marriage_ordinal", 5), ("clauses", []), ("principal_ok", False)])
def test_join_felt_afvigelse_afvises(tmp_path, field, value):
    rows = mixed_rows()[:2]
    v1 = [v1_of(r) for r in rows]
    bad = [{**rows[0], field: value}] + rows[1:]
    assert "INPUT_ROW_MISMATCH" in run_cli(tmp_path, v1, v3_rows=bad, expect_ok=False)


@pytest.mark.parametrize("field", ["supporting_count", "record_key", "occurrence_id"])
def test_join_felt_mangler_afvises(tmp_path, field):
    rows = mixed_rows()[:2]
    v1 = [v1_of(r) for r in rows]
    v3_missing = [{k: v for k, v in rows[0].items() if k != field}] + rows[1:]
    assert "INPUT_ROW_MISMATCH" in run_cli(tmp_path, v1, v3_rows=v3_missing, expect_ok=False)
    v1_missing = [{k: v for k, v in v1[0].items() if k != field}] + v1[1:]
    assert "INPUT_ROW_MISMATCH" in run_cli(tmp_path, v1_missing, v3_rows=rows, expect_ok=False, name="y.json")


def test_v1_input_sha_kontrolleres(tmp_path):
    rows = mixed_rows()[:2]
    v1 = [v1_of(r) for r in rows]
    assert "V1_INPUT_SHA_MISMATCH" in run_cli(tmp_path, v1, v3_rows=rows, claimed="f" * 64, expect_ok=False)
    body, _ = run_cli(tmp_path, v1, v3_rows=rows, claimed=None, name="n.json")      # ikke oplyst: feltet udelades
    assert "input_sha256" not in json.loads(body) and "v1_input_file_sha256" in json.loads(body)


def test_default_profile_unchanged(tmp_path):
    rows = mixed_rows()
    v1 = [v1_of(r) for r in rows]
    default, _ = run_cli(tmp_path, v1, v3_rows=rows, name="d.json")
    withfile, _ = run_cli(tmp_path, v1, "--profile", str(P_2018), v3_rows=rows, name="f.json")
    assert default == withfile
    got = json.loads(default)
    assert got["authorized_elements"] and all(e["profile"] == "relation-persona-2018-20-v3"
                                              for e in got["authorized_elements"].values())


def test_fail_closed_input(tmp_path):
    rows = mixed_rows()[:3]
    v1 = [v1_of(r) for r in rows]
    assert "V3_INPUT_REQUIRED" in run_cli(tmp_path, v1, expect_ok=False)                        # v3-prædikat, ingen v3-input
    assert "V3_ROW_MISSING" in run_cli(tmp_path, v1, v3_rows=rows[:2], expect_ok=False)          # v1-række uden v3-række
    extra = row("Gift 1890 med Ida Dal.", "Gift med Ida Dal", key="00000000-0000-0000-0000-0000000000ff")
    assert "V1_ROW_MISSING" in run_cli(tmp_path, v1, v3_rows=rows + [extra], expect_ok=False)    # v3-række uden v1-række
    changed = [{**rows[0], "raw": "Gift med Ida"}] + rows[1:]
    assert "INPUT_ROW_MISMATCH" in run_cli(tmp_path, v1, v3_rows=changed, expect_ok=False)       # rækkerne afviger
