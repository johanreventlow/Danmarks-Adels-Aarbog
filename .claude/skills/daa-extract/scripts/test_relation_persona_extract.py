import json
import subprocess
import sys
from pathlib import Path

import relation_persona_extract as rpe

HERE = Path(__file__).parent
SHA = "a" * 64


def row(raw, text=None, predicate="relation.marriage", ordinal=1, key="k1", n_sup=1, post_from=100, record="I-1"):
    text = raw if text is None else text
    clauses = [] if n_sup == 0 else [{"observation_id": "o-" + key, "verbatim_text": text, "post_char_from": post_from,
                                      "post_char_to": post_from + len(text), "clause_set_seq": 1, "clause_set_sha256": SHA}]
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": predicate, "raw": raw,
            "record_key": record, "occurrence_id": "occ-" + record,
            "marriage_ordinal": ordinal if predicate == "relation.marriage" else None,
            "supporting_count": max(n_sup, 1) if n_sup else 1, "clauses": clauses, "principal_ok": True}


# 2018-20-formen (målt 6/10): »Gift <dato> med <navn>« eller påstanden begynder med navnet;
# år skrives med * (født) og † (død).
def test_aegteskab_med_navn_og_aar():
    raw = "Gift 15.6.1975 med Bo Beta, * 3.2.1950 i Kbh., † 2001, datter af Carl Ceta."
    m, st = rpe.extract_rows([row(raw)])
    p = m["authorized_elements"]["relation-persona:k1"]
    assert raw[p["name_from"]:p["name_to"]] == "Bo Beta"
    assert (p["birth_raw"], p["death_raw"]) == ("1950", "2001")
    assert p["post_offset"] == 100 and p["span_from"] == 0 and p["span_to"] == len(raw)
    assert m["expected_counts"] == {"person_creates": 0, "source_evidence": 0, "relation_personas": 1}
    assert st["elementer"] == 1


def test_aar_i_foraeldresegment_tages_ikke():
    raw = "Gift med Bo Beta, datter af Carl Ceta, * 1900, † 1960."
    p = rpe.extract_rows([row(raw)])[0]["authorized_elements"]["relation-persona:k1"]
    assert p["birth_raw"] is None and p["death_raw"] is None


def test_d_af_er_ikke_doed():
    raw = "Gift med Bo Beta, f. 1950, d. af Carl."
    p = rpe.extract_rows([row(raw)])[0]["authorized_elements"]["relation-persona:k1"]
    assert (p["birth_raw"], p["death_raw"]) == ("1950", None)


def test_barn_har_null_felter():
    p = rpe.extract_rows([row("Datter Dora.", predicate="relation.child")])[0]["authorized_elements"]["relation-persona:k1"]
    assert all(p[k] is None for k in ("marriage_ordinal", "name_from", "name_to", "birth_raw", "death_raw"))


def test_parkeringsgrunde():
    rows = [row("Gift med Bo Beta.", text="noget andet", key="a"),
            row("Gift med Bo Beta.", text="Gift med Bo Beta. Gift med Bo Beta.", key="b"),
            row("Gift med Bo Beta.", n_sup=0, key="c"),
            row("gift 1975.", key="d"),
            row("Gift med Bo Beta.", ordinal=None, key="e")]
    rows[2]["supporting_count"] = 2
    m, st = rpe.extract_rows(rows)
    assert m["authorized_elements"] == {}
    assert st["parkeret"] == {"ikke_ordret": 1, "tvetydigt_spaend": 1, "flere_klausuler": 1, "intet_navn": 1, "intet_nummer": 1}


def test_dubletter_parkeres_begge():
    a, b = row("Gift med Bo Beta.", key="a"), row("Gift med Bo Beta.", key="b")
    m, st = rpe.extract_rows([a, b])
    assert m["authorized_elements"] == {} and st["parkeret"] == {"dublet": 2}


def test_payload_noegler_er_writerens():
    p = rpe.extract_rows([row("Gift med Bo Beta.")])[0]["authorized_elements"]["relation-persona:k1"]
    assert sorted(p) == ["birth_raw", "clause_observation_id", "clause_set_seq", "clause_set_sha256", "death_raw",
                         "interpretation_key", "interpretation_version", "marriage_ordinal", "name_from", "name_to",
                         "post_offset", "predicate", "profile", "span_from", "span_to"]


def test_cli_printer_ingen_vaerdier(tmp_path):
    inp = tmp_path / "in.json"
    inp.write_text(json.dumps({"input_sha256": SHA, "input": [row("Gift med Hemmelig Navnesen, * 1950.")]}))
    out = tmp_path / "out.json"
    r = subprocess.run([sys.executable, str(HERE / "relation_persona_extract.py"), "--input", str(inp), "--out", str(out)],
                       capture_output=True, text=True, check=True)
    first = r.stdout.splitlines()[0]
    assert "Hemmelig" not in r.stdout + r.stderr and "1950" not in first   # 2. linje er en hex-hash
    assert first.startswith("RELATION_EXTRACT_OK elementer=1")
    assert oct(out.stat().st_mode & 0o777) == "0o600"


def navn(raw):
    p = rpe.extract_rows([row(raw)])[0]["authorized_elements"].get("relation-persona:k1")
    return None if p is None else raw[p["name_from"]:p["name_to"]]


def test_b_form_paastanden_begynder_med_navnet():
    assert navn("Bo Beta, * 1950") == "Bo Beta"
    assert navn("Bo Beta (adopteret)") == "Bo Beta"


def test_titel_i_smaa_bogstaver_springes_over():
    assert navn("Gift 1975 med kammerherre Bo Beta, * 1950") == "Bo Beta"


def test_til_gods_er_ikke_navn():
    assert navn("Gift med Bo Beta til Alfagaard") == "Bo Beta"


def test_af_inde_i_navnet_afskaerer_ikke():
    assert navn("Gift med Bo greve af Beta, * 1950") == "Bo greve af Beta"


def test_gift_uden_med_er_intet_navn():
    assert navn("Gift 1975.") is None and navn("gift 1975.") is None


def test_aar_med_tegn_i_spaendet():
    p = rpe.extract_rows([row("Gift med Bo Beta, * 1950, † 2001")])[0]["authorized_elements"]["relation-persona:k1"]
    assert (p["birth_raw"], p["death_raw"]) == ("1950", "2001")


def test_titelopremsning_med_komma_springes_over():
    assert navn("Gift 1975 med cand.jur., kammerherre Bo Beta, * 1950") == "Bo Beta"


def test_b_form_med_titel_i_smaa_bogstaver():
    assert navn("kammerherre Bo Beta, * 1950") == "Bo Beta"
    assert navn("cand.jur., overlæge Bo Beta") == "Bo Beta"


def test_titelloeb_med_cifre_eller_mange_ord_er_intet_navn():
    assert navn("Gift med 2 gange tidligere gift Bo Beta") is None
    assert navn("Gift med en meget lang beskrivelse uden noget som helst navn Bo") is None


def test_uden_entydig_accepteret_hovedperson_parkeres():
    r = row("Gift med Bo Beta.")
    r["principal_ok"] = False
    m, st = rpe.extract_rows([r])
    assert m["authorized_elements"] == {} and st["parkeret"] == {"ingen_hovedperson": 1}
