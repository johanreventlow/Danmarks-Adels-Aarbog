import json
from pathlib import Path

import evidenspas_v2
from omnoegl_lokator import _norm


WORK = Path(__file__).resolve().parents[4] / "work_1939_stamtavle"


def test_evidenspas_daekker_menneskeark_og_dubletter_med_kalibreret_evidens():
    resultat = evidenspas_v2.byg_evidenspas(
        forslag_path=WORK / "omnoegl-v2-forslag-2026-07-31.json",
        artefakt_path=WORK / "clean_1939.json",
        raw_path=WORK / "raw.txt",
        register_path=WORK / "identitetsregister-1939.json",
    )

    poster = resultat["poster"]
    assert len([p for p in poster if p["afgoerelse"] != "dublet-indstilling"]) == 48
    assert len([p for p in poster if p["afgoerelse"] == "dublet-indstilling"]) == 7
    assert len({p["legacy_id"] for p in poster}) == 55

    for post in poster:
        assert post["foreslaaet_v2_lokator"]
        assert post["konfidens_begrundelse"]
        assert len({signal["type"] for signal in post["signaler"]}) >= 2
        assert all(0 < len(signal["citat"].split()) <= 15 for signal in post["signaler"])


def test_genereret_json_er_deterministisk_og_registeret_er_uaendret(tmp_path):
    register_path = WORK / "identitetsregister-1939.json"
    foer = register_path.read_bytes()
    output = tmp_path / "evidens.json"
    rapport = tmp_path / "rapport.md"

    evidenspas_v2.generer(output_path=output, rapport_path=rapport)

    assert register_path.read_bytes() == foer
    assert json.loads(output.read_text(encoding="utf-8"))["register_sha256"]
    rapport_tekst = rapport.read_text(encoding="utf-8")
    assert rapport_tekst.startswith("# Kalibreret evidenspas")
    assert "Legacy i alt: afgjorte=15, ægte tvivl=19." in rapport_tekst
    assert "Nummereret formdrift: afgjorte=10, ægte tvivl=4." in rapport_tekst


def test_foerste_pas_maal_taeller_som_besat_og_totalen_har_nul_uforklarede():
    resultat = evidenspas_v2.byg_evidenspas(
        forslag_path=WORK / "omnoegl-v2-forslag-2026-07-31.json",
        artefakt_path=WORK / "clean_1939.json",
        raw_path=WORK / "raw.txt",
        register_path=WORK / "identitetsregister-1939.json",
    )
    ditlev = next(p for p in resultat["poster"]
                  if p["legacy_id"] == "VI.2.N1.1.1.1.II.A.2.1")

    assert "allerede besat" in ditlev["konfidens_begrundelse"]
    assert resultat["simuleret_total_reconcile"]["uforklarede"] == 0
    sim = resultat["simuleret_total_reconcile"]
    assert sim["mekanisk"] == {
        "entydige": 491, "tvetydige": 0, "nye": 62, "bortfaldne": 23,
    }
    assert "simulerede_mints" not in sim
    assert sim["mint_kandidater_ikke_anvendt"] == 55


def test_de_sy_v_dubletter_daekker_alle_personer_i_oversigtsblokkene():
    resultat = evidenspas_v2.byg_evidenspas(
        forslag_path=WORK / "omnoegl-v2-forslag-2026-07-31.json",
        artefakt_path=WORK / "clean_1939.json",
        raw_path=WORK / "raw.txt",
        register_path=WORK / "identitetsregister-1939.json",
    )
    dubletter = {p["legacy_id"]: p["dublet_af_v2_lokal_ids"] for p in resultat["poster"]
                 if p["afgoerelse"] == "dublet-indstilling"}

    assert dubletter == {
        "Oversigt.Indledning.U1": ["I.Andet.2"],
        "Oversigt.Indledning.U2": ["I.Andet.3"],
        "Oversigt.Indledning.U3": [
            "I.Andet.4",
            "I.Fjerde.4-M-a-r-g-r-e-t-h-e-III-Cai-Reventlows-Børn-m-Anna-Rantzau.1",
        ],
        "Oversigt.Indledning.U4": [
            "I.Tredje.I.7",
            "I.Fjerde.Ditlev-Reventlows-Børn-af-første-Ægteskab-m-Anna-Rantzau.1",
            "I.Tredje.I.9",
        ],
        "Oversigt.Indledning.U5": [
            "I.Fjerde.havde-hende-i-Huset-II-Otto-Reventlows-Børn-m-Dorothea-von-Ahlefeldt.1",
            "I.Femte.II.2",
            "I.Sjette.Bertram-Reventlows-Børn-m-Christine-Rantzau.1",
        ],
        "Oversigt.Indledning.U6": [
            "I.Syvende.I.2", "I.Ottende.I.2", "I.Ottende.I.3",
            "I.Sjette.Bertram-Reventlows-Børn-m-Christine-Rantzau.6",
        ],
        "Oversigt.Indledning.U7": [
            "I.Syvende.sum-Skanse-II-Ditlev-Reventlows-Børn-med-Marie-Elisabeth-Buchwald.10",
            "I.Ottende.III.5",
        ],
    }


def test_omnoeglinger_har_to_verificerede_uafhaengige_signaler_uden_fallback():
    resultat = evidenspas_v2.byg_evidenspas(
        forslag_path=WORK / "omnoegl-v2-forslag-2026-07-31.json",
        artefakt_path=WORK / "clean_1939.json",
        raw_path=WORK / "raw.txt",
        register_path=WORK / "identitetsregister-1939.json",
    )

    for post in resultat["poster"]:
        if post["afgoerelse"] != "omnoegling":
            continue
        verificerede = [s for s in post["signaler"] if s.get("verificeret") is True]
        assert {s["type"] for s in verificerede} >= {"strukturel_adresse", "identitetsanker"}, post["legacy_id"]
        assert len({tuple(s["grundlag"]) for s in verificerede}) >= 2
        assert all("støttes af" not in s["forklaring"] for s in verificerede)


def test_nul_uforklarede_valideres_mod_uafhaengig_baseline_maengde():
    resultat = evidenspas_v2.byg_evidenspas(
        forslag_path=WORK / "omnoegl-v2-forslag-2026-07-31.json",
        artefakt_path=WORK / "clean_1939.json",
        raw_path=WORK / "raw.txt",
        register_path=WORK / "identitetsregister-1939.json",
    )
    sim = resultat["simuleret_total_reconcile"]

    assert sim["forventede_nye_fra_baseline"] == 62
    assert sim["uventede_nye_lokatorer"] == []
    assert sim["manglende_forventede_nye_lokatorer"] == []


def test_alle_korte_citater_kan_genfindes_i_raw_tekst():
    resultat = evidenspas_v2.byg_evidenspas(
        forslag_path=WORK / "omnoegl-v2-forslag-2026-07-31.json",
        artefakt_path=WORK / "clean_1939.json",
        raw_path=WORK / "raw.txt",
        register_path=WORK / "identitetsregister-1939.json",
    )
    raw = _norm((WORK / "raw.txt").read_text(encoding="utf-8"))

    for post in resultat["poster"]:
        for signal in post["signaler"]:
            assert _norm(signal["citat"]) in raw, (post["legacy_id"], signal)
