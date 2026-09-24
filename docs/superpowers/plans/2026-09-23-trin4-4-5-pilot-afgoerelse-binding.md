# Trin 4 · dagsværk 4.5: pilot, afgørelse og binding — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kør hele fortolkningskæden — klausuler → model → forslag → menneskets afgørelse → binding — for mindst 30 afdøde 2018-20-poster i én restore, og mål, om den er værd at køre på hele udgaven.

**Architecture:** Ingen ny motor og ingen ny DDL. 4.3b's runner, 4.4's writer og de eksisterende RPC'er `red_decide_interpretation`, `red_preview_interpretation_promotions` og `red_promote_interpretations_batch` bruges som de er. Det nye er et udvidet udvalg (24 nye poster oven i 4.3b's 10), et afgørelsesark som token-fil med hash-binding, en SQL-oversættelse fra ark til RPC, en bindingsforespørgsel i SQL og en rapport efter spec §8.4.

**Tech Stack:** Python 3 (pytest), PostgreSQL 17 lokalt (psql), `codex exec` bag Seatbelt-gaten, R kun via de eksisterende 4.4-rehearsal-scripts.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §8 (inkl. ERRATA 8.2), §9, §10.

**Forudgående:** `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3b.md`, `proposal-ingest-147-4-4-rehearsal.md`; decisions 2026-09-23 (»review-budget og gater efter konsekvens« og »4.4's prod-kørsel parkeres«).

---

## Målt udgangspunkt (2026-09-23, læse-kun mod restoren)

| Fakta | Tal | Konsekvens for planen |
| --- | --- | --- |
| Restoren `daa43b_20260912192527` har de 84 forslag fra 4.4 | 84 `proposed`, 8 personaer | Genbruges — intet genkøres |
| Forslagenes værdier sammenlignet med den nuværende writers output (4.4-rehearsal på `main`) | Identisk hash `7171190b…` over nøgle, prædikat og værdi | Ingen ombygning af de 84 |
| #196's projektionsfunktioner (`private.interpretation_proposal_*`) | Mangler i restoren (0 af 8) | Task 0 løfter en **kopi** til `main`s skema |
| Runner-kontrakt nu vs. 4.3b-manifestet | Profil 1.3.0, prompt `d46cda80…`, model `gpt-5.6-terra`, skema `904c903c…`, `evidence-runner-1.0` — identiske | 4.3b's 10 og de nye poster måles under **samme frosne kontrakt** |
| Eligibility-ledger (`~/.private/43b-ledger/`) | 488 `eligible`, 103 `excluded` | Udvalget tages kun herfra |
| Prøvekørsel af Task 1's kode mod de rigtige data (kun tal) | 24 nye i 4 bundter + 6 i reserve; dækning mindst ét gift-udsagn 15, flere 6, usikker dato 18, titel 22; 8 strata à 3; 1 henvisning udelukket | Kravene kan opfyldes. Prioriteringen af sjældne signaler overrepræsenterer signalrige poster (titel 22/24 mod 243/488 i puljen); rapporten skal angive det |
| Persona-identiteter | 595 af 595 `accepted` | Binding er ikke blokeret af identitet |
| Aktive promotion-regler | 5 prædikater: `person.birth`, `.death`, `.name`, `.title`, `.byname` | 25 af de 84 forslag er promoverbare; alle har strengværdi |
| Redaktionsprofiler i restoren | 2 | Projektejeren udpeger, hvilken der afgør (Task 5) |
| 4.3b's forbrug | 175.840 input-tokens for 10 poster | ≈17.600 pr. post; 24 nye ≈ 420.000 |

## Global Constraints

- **Ingen prod.** Alt sker i en lokal kopi af restoren. Restoren selv røres ikke; den er udgangspunktet, hvis kopien skal kasseres.
- **Kun afdøde, `eligible` records** fra ledgeren (spec §9.2). Runneren slår op i ledgeren for hvert kald.
- **Samme frosne kontrakt som 4.3b** — profil `daa-2018-20-v1` 1.3.0, prompt `d46cda80177cf3b6…`, model `gpt-5.6-terra`. Ændres noget af det, er 4.3b's 10 poster ikke længere sammenlignelige, og så er beviset kun de nye.
- **Ingen kildetekst i repoet, logs, commits eller chatten** — heller ikke via ordrette claim-værdier (4.3b's R6). Den committede rapport rummer record-nøgler, prædikater, tal og hashes.
- **Private artefakter:** `0600`-filer, `0700`-mapper under `~/.private/45-pilot/`. Aldrig i git.
- **Afgørelser under projektejerens redaktionsprofil** med `request.jwt.claim.sub` sat i transaktionen (`red_*`-rollegaten kaster ellers).
- **Test lokalt med `/usr/bin/python3 -m pytest`** (Homebrews Python har ikke pytest); CI kører Python 3.11 og kun de testfiler, der står i `ci.yml`s job `python` — nye testfiler skal tilføjes dér.
- **Review-budget 1 + 1** (kun restore; decisions 2026-09-23): én smal Codex-runde på planen, én på koden. Ingen undtagelsesrunde. Gate: ingen prod-gate; færdig = én rigtig kørsel.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, den fælles fortolkningskæde (#147), leverance 5.
2. **Værdikædeled:** fortolkning → *afgørelse* → *binding*. »Extractor-runner og modelkald« og »Proposed-ingest« flyttes til `integreret ende-til-ende` for 2018-20; »Promotion« kun for bindingsdelen (spec §8.5).
3. **Leverancetype:** generel mekanisme for ark → afgørelse og for bindingsforespørgslen (editionsneutral); udvalget er pilot-specifikt.
4. **Redaktionel værdi:** første gang et menneske afgør maskinelle forslag i databasen, og første måling af, hvor stor en del der kan bindes til eksisterende fakta. Svaret afgør, om hele udgaven skal køres.
5. **Færdigbevis:** ≥30 afdøde poster gennem hele kæden i én base; afgørelser skrevet med `red_decide_interpretation`; bindinger med `red_promote_interpretations_batch`; rapport efter §8.4 med skalafremskrivning.
6. **Erstatter:** den manuelle vej, hvor en redaktør læser biografien og selv indtaster fakta; og 4.3b's bedømmelse, der kun lå i en fil og aldrig nåede databasen.

## Projektejerens valg i denne plan

- **V1 — udvalget:** 4.3b's 10 poster tæller med, og der vælges **24 nye plus 6 i reserve** — alle 30 godkendt i samme GO. ≥30 **bekræftede biografiske poster** er en fail-closed gate (Task 3 Step 2): en post er bekræftet biografisk, når den gav mindst ét kontraktgyldigt claim. 4.3b bidrager med 8. Når de 24 er kørt, køres reserven kun, hvis der er under 30; er der stadig under 30, stopper dagsværket før ingest.
- **V4 — »indgiftede« måles af gift-aksen (projektejerens afgørelse 2026-09-24):** §8.1's to akser »gift«-udsagn og indgiftede slås sammen. I 2018-20 optræder de indgiftede som ægtefællen i et slægtsmedlems post (spec §5.3, §7.2), så tekstens egne gift-udsagn er det direkte mål. Et database-signal (»partner uden forældre i basen«) blev fravalgt: det måler, hvor mange slægter der er indlæst, ikke personen, og skifter betydning, når næste slægt kommer ind.
- **V2 — stopkriteriet:** 4.3b's fem tærskler genbruges uændret (Task 2). Spec §8.4 tilføjer: en kategori med absurd lav eller høj dækning er `NO-GO` for fuld kørsel.
- **V3 — modelkaldene:** projektejerens GO med manifest-hash og budget, efter kvotenulstilling (spec §10).

## Prøvekørt, før planen blev sendt til læsning (2026-09-23)

- Task 1's kode og tests: 10/10 bestået; mod de rigtige data (kun tal) `UDVALG_OK nye=24 reserve=6 bundter=5`, dækning mindst ét gift-udsagn 15 / flere 6 / usikker dato 18 / titel 22.
- Task 2's kode og tests: 10/10 bestået (plus runnerens egne 99); mutationstesten stopper på `SCHEMA_DRIFT` uden modelkald.
- Task 4's ændring: 29/29 bestået; 4.4's manifest genbygget byte-identisk i legacy-tilstand.
- Task 5's kode og tests: 14/14 bestået.
- Task 7's forespørgsel og SQL-test mod en frisk base (bootstrap, `schema.sql`, `db-rls.sql`, `db-migrations.sql`, `db-rls.sql`): `OK … alle udfald, tekst- og datogren, enig med RPC, genkørsel`.

Implementøren skriver stadig testene først (TDD); prøvekørslen viser kun, at planens kode og tests passer sammen.

## Review Focus

Fem forhold, som ingen enkelt tasks test naturligt rammer, men som vil ramme brugeren først:

1. **Et ark, der er ændret efter godkendelsen — eller hvor en beslutningslinje er slettet, indrykket eller har fået et andet UUID, før hashen blev taget.** Forventning: `SHEET_HASH_MISMATCH` henholdsvis `SHEET_LINE_INVALID`/`SHEET_IDENTITY_MISMATCH`, og intet skrives. Arkets beslutninger skal dække præcis rækkefilens sæt af `(interpretation_id, version)`, og rækkefilen er selv hash-bundet. Test i Task 5.
2. **Et ark med uafgjorte linjer (`_`).** Forventning: STOP med antal og linjenumre, ingen delvis skrivning. Test i Task 5.
3. **To assertions på samme person matcher samme værdi.** Forventning: fortolkningen bindes ikke, men tælles som `AMBIGUOUS`. Test i Task 7.
4. **En fortolkning afgjort i databasen mellem ark-byg og afgørelse** (versionen er ikke længere 1). Forventning: hele transaktionen ruller tilbage på `EVIDENCE_INTERPRETATION_VERSION_CONFLICT`. Test i Task 6.
5. **Krydshenvisninger eller tomme svar blandt de 24 nye.** Forventning: de tæller ikke som bekræftede biografiske poster; falder antallet under 30, køres reserven, og er det stadig under 30, stopper dagsværket før ingest. Håndteret i Task 1 (henvisningsreglen, reserven) og Task 3 Step 2 (gaten).

---

## Filoversigt

| Fil | Ændring |
| --- | --- |
| `.claude/skills/daa-extract/scripts/build_45_selection.py` | **Ny.** Stratificeret udvalg af 24 nye poster efter §8.1's akser. |
| `.claude/skills/daa-extract/scripts/test_build_45_selection.py` | **Ny.** |
| `.claude/skills/daa-extract/scripts/build_43b_manifest.py` | Udvides: `--dagsvaerk` og bundter fra udvalget; 4.3b-adfærd uændret. |
| `.claude/skills/daa-extract/scripts/run_evidence_43b.py` | Udvides: `--bundle` valideres mod manifestets bundter; 4.3b-adfærd uændret. |
| `.claude/skills/daa-extract/scripts/test_evidence_run_manifest.py` | **Ny.** |
| `.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py` | Udvides: `--cache-key legacy\|current`. |
| `.claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py` | Udvides. |
| `.claude/skills/daa-extract/scripts/interpretation_decision_sheet.py` | **Ny.** Byg og læs afgørelsesarket (token-fil); byg afgørelses-SQL. |
| `.claude/skills/daa-extract/scripts/test_interpretation_decision_sheet.py` | **Ny.** |
| `.claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql` | **Ny.** Finder bindingsmål i SQL med RPC'ens egen normalisering. |
| `tests/sql/test-interpretation-promotion-targets.sql` | **Ny.** Fixture-test af bindingsforespørgslen. |
| `.github/workflows/ci.yml` | Kør den nye SQL-test i jobbet `evidence promotion`. |
| `docs/evidensbaseret-genimport/interpretation-pilot-2018-20.md` | **Ny.** Rapporten (§8.4). |
| `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md` | Modenhed efter §8.5. |

Uden for repoet (`~/.private/45-pilot/`, `0600`): arbejdsbasen, udvalg, manifester, cache, afgørelsesark, afgørelses-SQL, backup og bindingsresultat.

---

### Task 0: Arbejdsbase — kopi af restoren løftet til `main`s skema

**Files:** ingen i repoet. Private: `~/.private/45-pilot/workdb.txt`.

- [ ] **Step 1: Mål restoren før kopien.**

```bash
psql -X -d daa43b_20260912192527 -At -c "SET default_transaction_read_only=on;
  SELECT count(*), md5(string_agg(interpretation_key::text||predicate||md5(value::text),'|' ORDER BY interpretation_key))
  FROM private.interpretation"
```

Forventet: `84|7171190b07078870c39e90a1f8ce920b`. Andet tal er STOP.

- [ ] **Step 2: Kopiér.** Ingen forbindelser til restoren må være åbne (`createdb -T` kræver det).

```bash
mkdir -p -m 700 ~/.private/45-pilot
W=daa45_pilot_$(date +%Y%m%d%H%M%S)
createdb -T daa43b_20260912192527 "$W" && print -r -- "$W" > ~/.private/45-pilot/workdb.txt
chmod 600 ~/.private/45-pilot/workdb.txt
```

- [ ] **Step 3: Løft skemaet** (idempotent, samme filer som prod får):

```bash
W=$(cat ~/.private/45-pilot/workdb.txt)
psql -X -d "$W" -v ON_ERROR_STOP=1 -f db-migrations.sql > ~/.private/45-pilot/migrate.out 2>&1
psql -X -d "$W" -v ON_ERROR_STOP=1 -f db-rls.sql >> ~/.private/45-pilot/migrate.out 2>&1
grep -c 'ERROR' ~/.private/45-pilot/migrate.out
```

Forventet: `0`.

- [ ] **Step 4: Verificér.** `db-verify.sql` mod arbejdsbasen; kræv `OK: #147` og `OK: #148` og ingen `FEJL`. Gentag Step 1's forespørgsel mod arbejdsbasen: stadig `84|7171190b…`. Tæl `private.interpretation_proposal_%`-funktioner: 8.

```bash
psql -X -d "$W" -v ON_ERROR_STOP=1 -f db-verify.sql > ~/.private/45-pilot/verify.out 2>&1; echo "rc=$?"
grep -c 'OK: #147' ~/.private/45-pilot/verify.out; grep -c 'OK: #148' ~/.private/45-pilot/verify.out
grep -c 'FEJL' ~/.private/45-pilot/verify.out
```

**Verify:** rc=0, begge OK-tællinger ≥1, 0 `FEJL`, de 84 uændrede, 8 projektionsfunktioner. Ingen commit (intet i repoet).

---

### Task 1: Udvalget — 24 nye poster efter §8.1

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_45_selection.py`
- Test: `.claude/skills/daa-extract/scripts/test_build_45_selection.py`

**Interfaces:**
- Consumes: `evidence_runner.canonical_record_input`, `check_eligibility`, `load_ledger`, `sha256_text`; runner-input `~/.private/43b-runner-input/runner-input-v1.json` (`records[key] = {record_key, persona_id, post_verbatim_text, clauses[{ordinal, verbatim_text, verbatim_sha256}]}`). Ingen databaseeksport: alle akser måles på teksten.
- Produces: `gift_antal(tekst: str) -> int`, `features(record: dict) -> dict`, `er_henvisning(record: dict) -> bool`, `select_new(records: dict, eligible: list[str], exclude: set[str], count: int, reserve: int = 0) -> tuple[list[str], list[str]]`, `coverage(records, keys) -> dict[str, int]`, `definition_sha256() -> str`; udvalgsfil med `records` (hovedudvalg + reserve), `hovedudvalg`, `reserve`, `bundter` (`bundt_1`…`bundt_4` à seks, plus `reserve`), `strata_version = "45-strata-v3"`, `strata_sha256` (længdegrænser, udtryk, krav og algoritme), `ledger_sha256`, `record_input_sha256`, `udelukket_allerede_koert` (4.3b's 10).

**Akser (spec §8.1), målt på de 488 `eligible` 2026-09-23:**

| Akse | Signal | Fordeling |
| --- | --- | --- |
| Tekstlængde | `len(post_verbatim_text)`: kort < 200, middel < 800, lang ≥ 800 | p33 = 202, p66 = 591 |
| »Gift«-udsagn og indgiftede (V4) | **antal** forekomster af `\b(?:gift\|ægte\w*)`: 0 / 1 / 2+ | 59 + 45 poster har mindst ét |
| Titler/embeder | `TITEL_RE` (listen i koden) | 243 |
| Usikre datoer | `\bca\.`, `\bomkr\.`, `?`, `\b\d{3,4}/\d{2,4}\b` | 93 |

Primære strata er længde × gift-antal (op til 9 strata), valgt i rundgang; de første 24 er hovedudvalget, de næste 6 reserven. Inden for et stratum ordnes efter antal sjældne signaler (gift-udsagn, flere gift-udsagn, usikker dato, titel) faldende og derefter `record_key` — så de sjældne akser kommer med uden at blive egne strata. Bagefter kræves dækning i hovedudvalget: ≥9 med mindst ét gift-udsagn, ≥3 med flere, ≥3 med usikre datoer, ≥6 med titler. Opfyldes det ikke, eller er puljen for lille, stopper scriptet med tallene (fail-closed), og planen revideres — tærsklen sænkes ikke. **Kendt skævhed:** prioriteringen overrepræsenterer signalrige poster; rapporten angiver udvalgets fordeling mod puljens.

**Henvisningsreglen:** en post under 100 tegn, der indeholder `\bse\b`, er en krydshenvisning og vælges ikke (4.3b's to henvisninger var 50 og 70 tegn med »se«). Antallet af sådanne udelukkede poster skrives i udvalgsfilen.

- [ ] **Step 1: Skriv de fejlende tests.**

```python
# test_build_45_selection.py
import pytest
from build_45_selection import (SelectionCoverageError, coverage, definition_sha256,
                                er_henvisning, features, gift_antal, select_new)


def rec(key, tekst):
    return {"record_key": key, "persona_id": f"p-{key}", "post_verbatim_text": tekst,
            "clauses": [{"ordinal": 1, "verbatim_text": tekst, "verbatim_sha256": "x"}]}


def test_features_maaler_alle_akser_og_gift_som_antal():
    f = features(rec("A", "Kammerherre, gift 1850, ægtede 1860, † ca. 1901 " + "x" * 900))
    assert f == {"laengde": "lang", "gift": "2+", "gift_mindst_et": True, "gift_flere": True,
                 "titel": True, "usikker_dato": True}


def test_features_kort_uden_signaler():
    f = features(rec("B", "Født 1800."))
    assert f == {"laengde": "kort", "gift": "0", "gift_mindst_et": False, "gift_flere": False,
                 "titel": False, "usikker_dato": False}


def test_gift_antal_taeller_hvert_udsagn():
    assert gift_antal("gift 1800; ægtede 1810; gift 1820") == 3


def test_henvisning_er_kort_og_siger_se():
    assert er_henvisning(rec("C", "Se Reventlow, Conrad."))
    assert not er_henvisning(rec("D", "Se " + "x" * 120))
    assert not er_henvisning(rec("E", "Født 1800, død 1850."))


def _pulje():
    records = {}
    for i in range(80):
        key = f"I-{i:03d}"
        gift = "gift ægtede " if i % 4 == 0 else ("gift " if i % 2 else "")
        tekst = gift + ("ca. " if i % 5 == 0 else "") \
            + ("Kammerherre " if i % 3 == 0 else "") + "x" * (50 + 30 * i)
        records[key] = rec(key, tekst)
    return records


def test_udvalget_er_deterministisk_og_uafhaengigt_af_raekkefoelge():
    records = _pulje()
    keys = sorted(records)
    a = select_new(records, keys, set(), 24, 6)
    b = select_new(dict(reversed(list(records.items()))), list(reversed(keys)), set(), 24, 6)
    assert a == b and len(a[0]) == 24 and len(a[1]) == 6
    assert not set(a[0]) & set(a[1])


def test_udvalget_springer_koerte_og_ikke_eligible_over():
    records = _pulje()
    keys = sorted(records)
    exclude, eligible = set(keys[:10]), keys[:70]
    valgt, reserve = select_new(records, eligible, exclude, 24, 6)
    assert not (set(valgt) | set(reserve)) & exclude
    assert set(valgt) | set(reserve) <= set(eligible)


def test_udvalget_spreder_over_laengde_og_gift_antal():
    records = _pulje()
    valgt, _ = select_new(records, sorted(records), set(), 24)
    strata = {(features(records[k])["laengde"], features(records[k])["gift"]) for k in valgt}
    assert len(strata) >= 6


def test_manglende_daekning_stopper():
    records = {f"K-{i}": rec(f"K-{i}", "x" * 300) for i in range(40)}
    with pytest.raises(SelectionCoverageError) as exc:
        select_new(records, sorted(records), set(), 24)
    assert "gift_mindst_et=0" in str(exc.value)


def test_for_lille_pulje_stopper():
    records = _pulje()
    with pytest.raises(SelectionCoverageError, match="valgt=10"):
        select_new(records, sorted(records)[:10], set(), 24)


def test_definitionshash_binder_graenser(monkeypatch):
    import build_45_selection as b
    foer = definition_sha256()
    monkeypatch.setattr(b, "LAENGDE_GRAENSER", (150, 800))
    assert definition_sha256() != foer
```

- [ ] **Step 2: Kør og se dem fejle.**

Run: `cd .claude/skills/daa-extract/scripts && env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_build_45_selection.py -q`
Expected: FAIL med `ModuleNotFoundError: No module named 'build_45_selection'`.

- [ ] **Step 3: Implementér.**

```python
#!/usr/bin/env python3
"""Udvalget til dagsværk 4.5 (spec §8.1): 24 nye poster + 6 i reserve oven i 4.3b's 10.

Deterministisk og hash-bundet: længdegrænser, regulære udtryk, dækningskrav og
algoritmeversion indgår alle i `strata_sha256`.

Spec §8.1's akser »gift«-udsagn og indgiftede måles samlet af gift-antallet (V4): i
2018-20 optræder indgiftede som ægtefællen i et slægtsmedlems post, og tekstens egne
udsagn er et signal, der ikke skifter betydning, når flere slægter indlæses.
Printer kun nøgler, tal og hashes — aldrig tekst.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from evidence_runner import (EligibilityError, canonical_record_input, check_eligibility,
                             load_ledger, sha256_text)

STRATA_VERSION = "45-strata-v3"
LAENGDE_GRAENSER = (200, 800)
GIFT_RE = re.compile(r"\b(?:gift|ægte\w*)", re.IGNORECASE)
TITEL_RE = re.compile(
    r"\b(?:kammerherre|hofjægermester|lensgreve|greve|baron|godsejer|amtmand|"
    r"stiftamtmand|generalmajor|oberst|kaptajn|ritmester|premierløjtnant|minister|"
    r"gehejmeråd|konferensråd|etatsråd|kammerjunker|hofmarskal|stiftsdame|hofdame)\b",
    re.IGNORECASE)
USIKKER_RE = re.compile(r"(?:\bca\.|\bomkr\.|\?|\b\d{3,4}/\d{2,4}\b)", re.IGNORECASE)
HENVISNING_RE = re.compile(r"\bse\b", re.IGNORECASE)
KRAV = {"gift_mindst_et": 9, "gift_flere": 3, "usikker_dato": 3, "titel": 6}
BUNDT = 6
RESERVE = 6


class SelectionCoverageError(RuntimeError):
    pass


def gift_antal(tekst: str) -> int:
    return len(GIFT_RE.findall(tekst))


def features(record: dict) -> dict:
    tekst = record["post_verbatim_text"]
    n, g = len(tekst), gift_antal(tekst)
    kort, middel = LAENGDE_GRAENSER
    return {
        "laengde": "kort" if n < kort else ("middel" if n < middel else "lang"),
        "gift": "0" if g == 0 else ("1" if g == 1 else "2+"),
        "gift_mindst_et": g >= 1,
        "gift_flere": g >= 2,
        "titel": bool(TITEL_RE.search(tekst)),
        "usikker_dato": bool(USIKKER_RE.search(tekst)),
    }


def er_henvisning(record: dict) -> bool:
    tekst = record["post_verbatim_text"]
    return len(tekst) < 100 and bool(HENVISNING_RE.search(tekst))


def coverage(records: dict, keys: list[str]) -> dict[str, int]:
    out = {akse: 0 for akse in KRAV}
    for k in keys:
        f = features(records[k])
        for akse in KRAV:
            out[akse] += f[akse]
    return out


def definition_sha256() -> str:
    return sha256_text(STRATA_VERSION + "|" + json.dumps(
        {"laengde": LAENGDE_GRAENSER, "gift": GIFT_RE.pattern, "titel": TITEL_RE.pattern,
         "usikker": USIKKER_RE.pattern, "henvisning": HENVISNING_RE.pattern,
         "krav": KRAV, "bundt": BUNDT,
         "reserve": RESERVE, "algoritme": "laengde-x-gift-rundgang-sjaeldne-foerst-v1"},
        sort_keys=True))


def select_new(records: dict, eligible: list[str], exclude: set[str],
               count: int, reserve: int = 0) -> tuple[list[str], list[str]]:
    strata: dict[tuple[str, str], list[str]] = {}
    for k in sorted(set(eligible) - exclude):
        if er_henvisning(records[k]):
            continue
        f = features(records[k])
        strata.setdefault((f["laengde"], f["gift"]), []).append(k)
    for bucket in strata.values():
        bucket.sort(key=lambda k: (-sum(features(records[k])[a] for a in KRAV), k))
    navne = sorted(strata)
    raekke: list[str] = []
    i = 0
    while len(raekke) < count + reserve and any(strata[n] for n in navne):
        bucket = strata[navne[i % len(navne)]]
        if bucket:
            raekke.append(bucket.pop(0))
        i += 1
    valgt, reserve_keys = raekke[:count], raekke[count:]
    daekning = coverage(records, valgt)
    if any(daekning[a] < krav for a, krav in KRAV.items()) or len(valgt) < count:
        raise SelectionCoverageError("SELECTION_COVERAGE valgt=%d " % len(valgt) + " ".join(
            f"{a}={daekning[a]}" for a in KRAV))
    return valgt, reserve_keys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--runner-input", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--exclude-selection", required=True, help="4.3b's udvalgsfil")
    ap.add_argument("--out", required=True)
    ap.add_argument("--count", type=int, default=24)
    args = ap.parse_args()

    records = json.loads(Path(args.runner_input).read_text(encoding="utf-8"))["records"]
    ledger = load_ledger(json.loads(Path(args.ledger).read_text(encoding="utf-8")))
    exclude = set(json.loads(Path(args.exclude_selection).read_text(encoding="utf-8"))["records"])

    eligible = []
    for key, rec in records.items():
        try:
            check_eligibility(ledger, key, canonical_record_input(rec))
        except EligibilityError:
            continue
        eligible.append(key)
    henvisninger = sum(1 for k in eligible if k not in exclude and er_henvisning(records[k]))

    try:
        valgt, reserve = select_new(records, eligible, exclude, args.count, RESERVE)
    except SelectionCoverageError as exc:
        print(str(exc))
        return 1

    bundter = {f"bundt_{n + 1}": valgt[i:i + BUNDT]
               for n, i in enumerate(range(0, len(valgt), BUNDT))}
    if reserve:
        bundter["reserve"] = reserve
    alle = valgt + reserve
    udvalg = {
        "strata_version": STRATA_VERSION,
        "strata_sha256": definition_sha256(),
        "ledger_sha256": hashlib.sha256(Path(args.ledger).read_bytes()).hexdigest(),
        "records": alle,
        "hovedudvalg": valgt,
        "reserve": reserve,
        "bundter": bundter,
        "udelukket_allerede_koert": sorted(exclude),
        "udelukket_henvisninger": henvisninger,
        "daekning": coverage(records, valgt),
        "record_input_sha256": {k: canonical_record_input(records[k]) for k in alle},
    }
    out = Path(args.out)
    out.write_text(json.dumps(udvalg, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)
    print(f"UDVALG_OK nye={len(valgt)} reserve={len(reserve)} bundter={len(bundter)} "
          f"henvisninger_udelukket={henvisninger}")
    print(f"  daekning {udvalg['daekning']}")
    print(f"  strata_sha256 {udvalg['strata_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Kør testene.**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_build_45_selection.py -q`
Expected: 10 passed.

- [ ] **Step 5: Kør udvalget.**

```bash
cd .claude/skills/daa-extract/scripts
python3 build_45_selection.py --runner-input ~/.private/43b-runner-input/runner-input-v1.json \
  --ledger ~/.private/43b-ledger/eligibility-ledger-v1.json \
  --exclude-selection ~/.private/43b-udvalg.json --out ~/.private/45-pilot/udvalg.json
```

Forventet: `UDVALG_OK nye=24 reserve=6 bundter=5` (prøvekørt: dækning mindst ét gift-udsagn 15, flere 6, usikker dato 18, titel 22; 8 strata à 3). `SELECTION_COVERAGE` er et fund, der går til projektejeren.

- [ ] **Step 6: Commit** — tilføj først `test_build_45_selection.py` til pytest-listen i `ci.yml`s trin »evidence builders/runner/comparators · pytest«.

```bash
git add .claude/skills/daa-extract/scripts/build_45_selection.py .claude/skills/daa-extract/scripts/test_build_45_selection.py .github/workflows/ci.yml
git commit -m "feat(147): stratificeret udvalg til 4.5's pilot"
```

---

### Task 2: Pre-run-manifest og projektejerens GO

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/build_43b_manifest.py`
- Modify: `.claude/skills/daa-extract/scripts/run_evidence_43b.py:40,71`
- Test: `.claude/skills/daa-extract/scripts/test_evidence_run_manifest.py`

**Interfaces:**
- Produces (i `build_43b_manifest.py`): `build_manifest(udvalg: dict, *, dagsvaerk: str, restore_identity: str, ledger_sha256: str, profil: dict, claims_schema_sha256: str, code_sha256: str | None = None) -> dict`, `bundles_of(manifest: dict) -> dict[str, list[str]]`, `manifest_sha256(manifest: dict) -> str`, `runner_code_sha256(scripts_dir: Path = SCRIPTS) -> str` (over `evidence_extract.py`, `evidence_runner.py`, `run_evidence_43b.py`) og `check_contract(manifest, *, schema_text, runner_contract_version, code_sha256) -> str | None` (STOP-koderne `MANIFEST_TAMPERED`, `SCHEMA_DRIFT`, `RUNNER_CONTRACT_DRIFT`, `RUNNER_CODE_DRIFT`). 4.5's manifest bærer `runner_code_sha256`; 4.3b's gør ikke og tjekkes derfor ikke på kode. `bundles_of` returnerer `manifest["bundter"]`, hvis nøglen findes, ellers `{"bundt_1": manifest["bundt_1"], "bundt_2": manifest["bundt_2"]}` (4.3b-manifestet).
- `run_evidence_43b.py --bundle <navn>`: navnet skal findes i `bundles_of(manifest)`; ellers `BUNDLE_UNKNOWN` og exit 1.

- [ ] **Step 1: Skriv de fejlende tests.**

```python
# test_evidence_run_manifest.py
import hashlib
import json
from pathlib import Path

import pytest

import build_43b_manifest as bm
import evidence_extract
import evidence_runner
from build_43b_manifest import (build_manifest, bundles_of, check_contract,
                                manifest_sha256, runner_code_sha256)

PROFIL = {"profile_id": "daa-2018-20-v1", "version": "1.3.0",
          "prompt_file": "p.md", "prompt_sha256": "d46c", "model_id": "gpt-5.6-terra"}
SKEMA = "{\"skema\": 1}"


def udvalg45():
    return {"records": [f"R-{i}" for i in range(12)],
            "bundter": {"bundt_1": [f"R-{i}" for i in range(6)],
                        "reserve": [f"R-{i}" for i in range(6, 12)]},
            "record_input_sha256": {f"R-{i}": f"h{i}" for i in range(12)},
            "strata_version": "45-strata-v2", "strata_sha256": "s" * 64}


def m45(**kw):
    return build_manifest(udvalg45(), dagsvaerk="4.5", restore_identity="daa45_x",
                          ledger_sha256="L", profil=PROFIL,
                          claims_schema_sha256=evidence_runner.sha256_text(SKEMA),
                          code_sha256=kw.get("code", "c" * 64))


def test_manifest_baerer_bundter_dagsvaerk_og_kodehash():
    m = m45()
    assert m["dagsvaerk"] == "4.5" and m["runner_code_sha256"] == "c" * 64
    assert bundles_of(m) == udvalg45()["bundter"]
    assert m["budget"]["antal_kald"] == 12
    assert m["manifest_sha256"] == manifest_sha256(m)


def test_4_3b_manifestet_laeses_uaendret():
    gammelt = {"bundt_1": ["I-29"], "bundt_2": ["III-104"], "records": ["I-29", "III-104"]}
    assert bundles_of(gammelt) == {"bundt_1": ["I-29"], "bundt_2": ["III-104"]}


def test_kontrakten_holder_naar_intet_er_aendret():
    assert check_contract(m45(), schema_text=SKEMA,
                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                          code_sha256="c" * 64) is None


@pytest.mark.parametrize("aendring,kode", [
    (dict(schema_text="{\"skema\": 2}"), "SCHEMA_DRIFT"),
    (dict(runner_contract_version="evidence-runner-9.9"), "RUNNER_CONTRACT_DRIFT"),
    (dict(code_sha256="d" * 64), "RUNNER_CODE_DRIFT"),
])
def test_kontraktdrift_stopper(aendring, kode):
    args = dict(schema_text=SKEMA, runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                code_sha256="c" * 64)
    args.update(aendring)
    assert check_contract(m45(), **args) == kode


def test_manipuleret_manifest_stopper():
    m = m45()
    m["records"].append("R-99")
    assert check_contract(m, schema_text=SKEMA,
                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
                          code_sha256="c" * 64) == "MANIFEST_TAMPERED"


def test_kodehash_aendres_naar_runnerkoden_aendres(tmp_path):
    for navn in bm.RUNNER_CODE_FILES:
        (tmp_path / navn).write_text("x", encoding="utf-8")
    foer = runner_code_sha256(tmp_path)
    (tmp_path / "evidence_runner.py").write_text("y", encoding="utf-8")
    assert runner_code_sha256(tmp_path) != foer


def test_runneren_kalder_ikke_modellen_ved_skemadrift(tmp_path, monkeypatch):
    """Mutationstest: skemaet ændres efter GO → STOP før første modelkald."""
    import run_evidence_43b
    rec = {"record_key": "R-1", "persona_id": "p", "post_verbatim_text": "t",
           "clauses": [{"ordinal": 1, "verbatim_text": "t",
                        "verbatim_sha256": evidence_runner.sha256_text("t")}]}
    ledger = {"schema_version": evidence_runner.LEDGER_SCHEMA_VERSION, "policy_version": "p",
              "rules_script_sha256": "r" * 64, "source_id": 1, "restore_identity": "x",
              "records": {"R-1": {"status": "eligible", "reasons": [],
                                  "record_input_sha256": evidence_runner.canonical_record_input(rec)}}}
    (tmp_path / "ledger.json").write_text(json.dumps(ledger), encoding="utf-8")
    (tmp_path / "input.json").write_text(json.dumps({"records": {"R-1": rec}}), encoding="utf-8")
    profil = evidence_extract.load_profile("daa-2018-20-v1")
    udvalg = {"records": ["R-1"], "bundter": {"bundt_1": ["R-1"]},
              "record_input_sha256": {"R-1": evidence_runner.canonical_record_input(rec)},
              "strata_version": "t", "strata_sha256": "s" * 64}
    m = build_manifest(udvalg, dagsvaerk="4.5", restore_identity="x",
                       ledger_sha256=hashlib.sha256((tmp_path / "ledger.json").read_bytes()).hexdigest(),
                       profil=profil, claims_schema_sha256="0" * 64,  # ≠ det aktuelle skema
                       code_sha256=runner_code_sha256())
    (tmp_path / "m.json").write_text(json.dumps(m), encoding="utf-8")
    kaldt = []
    monkeypatch.setattr(evidence_runner, "run_codex", lambda *a, **k: kaldt.append(1))
    monkeypatch.setattr("sys.argv", ["run", "--manifest", str(tmp_path / "m.json"),
                                     "--approved-sha256", m["manifest_sha256"],
                                     "--runner-input", str(tmp_path / "input.json"),
                                     "--ledger", str(tmp_path / "ledger.json"),
                                     "--bundle", "bundt_1", "--cache-dir", str(tmp_path / "c"),
                                     "--out", str(tmp_path / "o.json"),
                                     "--judgement-sheet", str(tmp_path / "a.json")])
    assert run_evidence_43b.main() == 1
    assert kaldt == []
    assert not (tmp_path / "o.json").exists()


def test_4_3b_manifestets_hash_kan_genberegnes():
    sti = Path.home() / ".private" / "43b-manifest.json"
    if not sti.exists():
        pytest.skip("privat 4.3b-manifest findes ikke på denne maskine")
    m = json.loads(sti.read_text(encoding="utf-8"))
    assert manifest_sha256(m) == m["manifest_sha256"]
```

Den sidste test beviser, at omskrivningen ikke ændrer hash-definitionen. Den springer over i CI (privat fil) — det er en lokal kontrol, ikke dækning, og står sådan i Task 2's verifikation.

- [ ] **Step 2: Kør og se dem fejle.**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_evidence_run_manifest.py -q`
Expected: FAIL med `ImportError: cannot import name 'build_manifest'`.

- [ ] **Step 3: Implementér.** Erstat `build_43b_manifest.py` med nedenstående (manifest-dict'en trukket ud i `build_manifest`; hash-definitionen er uændret, så 4.3b-manifestets hash stadig kan genberegnes):

```python
#!/usr/bin/env python3
"""Pre-run-manifestet til 4.3b og 4.5 (spec §10).

Spec §10 kræver projektejerens GO med **manifest-hash og budget** — ikke kun en
ledger-SHA (anden læsers R5). Manifestet bygges derfor FØR modellen kaldes og
binder alt, kørslen er godkendt til: records, deres inputhashes, ledgeren,
profilen, prompten, modellen, outputskemaet, runner-kontrakten, runner-koden og
budgettet. `check_contract` genvaliderer det ved kørslen (4.5-review, fund 3).

Manifestets hash er GO-grundlaget. Indeholder ingen biografitekst.
"""
from __future__ import annotations

import argparse, hashlib, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import evidence_extract, evidence_runner

SCRIPTS = Path(__file__).resolve().parent
SKEMA = SCRIPTS.parent / "references" / "evidence-claims-1.0.json"
#: Filerne, hvis bytes afgør hvad der sendes og hvordan svaret valideres.
RUNNER_CODE_FILES = ("evidence_extract.py", "evidence_runner.py", "run_evidence_43b.py")
OVERHEAD = 15266


def runner_code_sha256(scripts_dir: Path = SCRIPTS) -> str:
    h = hashlib.sha256()
    for navn in RUNNER_CODE_FILES:
        h.update(navn.encode("utf-8") + b"\0" + (scripts_dir / navn).read_bytes() + b"\0")
    return h.hexdigest()


def manifest_sha256(manifest: dict) -> str:
    krop = {k: v for k, v in manifest.items() if k != "manifest_sha256"}
    return hashlib.sha256(json.dumps(krop, ensure_ascii=False, sort_keys=True,
                                     separators=(",", ":")).encode("utf-8")).hexdigest()


def bundles_of(manifest: dict) -> dict[str, list[str]]:
    if "bundter" in manifest:
        return manifest["bundter"]
    return {"bundt_1": manifest["bundt_1"], "bundt_2": manifest["bundt_2"]}


def build_manifest(udvalg: dict, *, dagsvaerk: str, restore_identity: str,
                   ledger_sha256: str, profil: dict, claims_schema_sha256: str,
                   code_sha256: str | None = None) -> dict:
    manifest = {
        "schema_version": "evidence-run-manifest-1.0",
        "status": "pending",
        "dagsvaerk": dagsvaerk,
        "restore_identity": restore_identity,
        "records": udvalg["records"],
        "record_input_sha256": udvalg["record_input_sha256"],
        "strata_version": udvalg["strata_version"],
        "eligibility_ledger_sha256": ledger_sha256,
        "profile_id": profil["profile_id"],
        "profile_version": profil["version"],
        "prompt_file": profil["prompt_file"],
        "prompt_sha256": profil["prompt_sha256"],
        "model": profil["model_id"],
        "claims_schema_sha256": claims_schema_sha256,
        "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION,
        "budget": {
            "enhed": "input-tokens",
            "overhead_pr_kald": OVERHEAD,
            "antal_kald": len(udvalg["records"]),
            "forventet_overhead_i_alt": OVERHEAD * len(udvalg["records"]),
            "note": "Nyttelasten kommer oveni og afhænger af postlængden. "
                    "Ingen kroneomregning (afvigelse D).",
        },
    }
    if "bundter" in udvalg:
        manifest["bundter"] = udvalg["bundter"]
        manifest["strata_sha256"] = udvalg["strata_sha256"]
    else:
        manifest["bundt_1"] = udvalg["bundt_1"]
        manifest["bundt_2"] = udvalg["bundt_2"]
    if code_sha256 is not None:
        manifest["runner_code_sha256"] = code_sha256
    manifest["manifest_sha256"] = manifest_sha256(manifest)
    return manifest


def check_contract(manifest: dict, *, schema_text: str, runner_contract_version: str,
                   code_sha256: str) -> str | None:
    """None hvis kørselsmiljøet er det godkendte; ellers en navngivet STOP-kode."""
    if manifest_sha256(manifest) != manifest.get("manifest_sha256"):
        return "MANIFEST_TAMPERED"
    if evidence_runner.sha256_text(schema_text) != manifest["claims_schema_sha256"]:
        return "SCHEMA_DRIFT"
    if runner_contract_version != manifest["runner_contract_version"]:
        return "RUNNER_CONTRACT_DRIFT"
    if "runner_code_sha256" in manifest and code_sha256 != manifest["runner_code_sha256"]:
        return "RUNNER_CODE_DRIFT"
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--selection", required=True)
    ap.add_argument("--ledger", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--restore-identity", required=True)
    ap.add_argument("--dagsvaerk", default="4.3b")
    args = ap.parse_args()

    udvalg = json.loads(Path(args.selection).read_text(encoding="utf-8"))
    profil = evidence_extract.load_profile("daa-2018-20-v1")
    evidence_extract.resolve_prompt(profil["prompt_file"], profil["prompt_sha256"])
    manifest = build_manifest(
        udvalg, dagsvaerk=args.dagsvaerk, restore_identity=args.restore_identity,
        ledger_sha256=hashlib.sha256(Path(args.ledger).read_bytes()).hexdigest(),
        profil=profil,
        claims_schema_sha256=evidence_runner.sha256_text(SKEMA.read_text(encoding="utf-8")),
        code_sha256=None if args.dagsvaerk == "4.3b" else runner_code_sha256())

    out = Path(args.out)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    out.chmod(0o600)
    print(f"MANIFEST_OK records={len(manifest['records'])} bundter={sorted(bundles_of(manifest))}")
    print(f"  manifest_sha256: {manifest['manifest_sha256']}")
    print(f"  ledger_sha256:   {manifest['eligibility_ledger_sha256'][:32]}…")
    print(f"  prompt_sha256:   {manifest['prompt_sha256'][:32]}…")
    print(f"  model:           {manifest['model']}  profil {manifest['profile_version']}")
    print(f"  budget:          ~{manifest['budget']['forventet_overhead_i_alt']:,} input-tokens overhead")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

Og ret `run_evidence_43b.py` — bundter fra manifestet, og kontrakten genvalideret før første `prepare_call_dir`:

```diff
--- a/.claude/skills/daa-extract/scripts/run_evidence_43b.py
+++ b/.claude/skills/daa-extract/scripts/run_evidence_43b.py
@@ -24,6 +24,7 @@
 
 import evidence_extract
 import evidence_runner
+from build_43b_manifest import bundles_of, check_contract, runner_code_sha256
 from evidence_runner import (ResponseCache, build_gate_profile, build_gated_argv,
                              canonical_record_input, load_ledger, prepare_call_dir,
                              run_record_guarded, sha256_text)
@@ -36,7 +37,7 @@
                     help="manifest-hashen fra projektejerens GO")
     ap.add_argument("--runner-input", required=True)
     ap.add_argument("--ledger", required=True)
-    ap.add_argument("--bundle", choices=["bundt_1", "bundt_2"], required=True)
+    ap.add_argument("--bundle", required=True)
     ap.add_argument("--cache-dir", required=True)
     ap.add_argument("--out", required=True)
     ap.add_argument("--judgement-sheet", required=True)
@@ -63,12 +64,24 @@
         return 1
 
     skema_sti = Path(__file__).resolve().parents[1] / "references" / "evidence-claims-1.0.json"
-    skema = json.loads(skema_sti.read_text(encoding="utf-8"))
+    skema_tekst = skema_sti.read_text(encoding="utf-8")
+    # Den godkendte kontrakt genvalideres FØR første kald (4.5-review, fund 3).
+    fejl = check_contract(manifest, schema_text=skema_tekst,
+                          runner_contract_version=evidence_runner.RUNNER_CONTRACT_VERSION,
+                          code_sha256=runner_code_sha256())
+    if fejl:
+        print(f"{fejl} — kørselsmiljøet er ikke det, der blev givet GO til. Intet sendes.")
+        return 1
+    skema = json.loads(skema_tekst)
     cache = ResponseCache(args.cache_dir)
     home = os.path.expanduser("~")
     repo = Path(__file__).resolve().parents[4]
 
-    keys = manifest[args.bundle]
+    bundter = bundles_of(manifest)
+    if args.bundle not in bundter:
+        print(f"BUNDLE_UNKNOWN {args.bundle} — manifestet har {sorted(bundter)}")
+        return 1
+    keys = bundter[args.bundle]
     print(f"== {args.bundle}: {len(keys)} records ==\n")
 
     resultater, ark = [], []
```

- [ ] **Step 4: Kør testene** — også de eksisterende runner-tests.

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_evidence_run_manifest.py test_evidence_runner.py -q`
Expected: alle bestået (prøvekørt: 10 + 99); `test_runneren_kalder_ikke_modellen_ved_skemadrift` stopper på `SCHEMA_DRIFT` uden modelkald; `test_4_3b_manifestets_hash_kan_genberegnes` bestået lokalt (springer over i CI — privat fil, ikke dækning).

- [ ] **Step 5: Commit** — tilføj `test_evidence_run_manifest.py` til samme pytest-liste i `ci.yml`.

```bash
git add .claude/skills/daa-extract/scripts/build_43b_manifest.py .claude/skills/daa-extract/scripts/run_evidence_43b.py .claude/skills/daa-extract/scripts/test_evidence_run_manifest.py .github/workflows/ci.yml
git commit -m "feat(147): runner-manifest med vilkårlige bundter til 4.5"
```

- [ ] **Step 6: Byg 4.5's manifest.**

```bash
python3 build_43b_manifest.py --dagsvaerk 4.5 --selection ~/.private/45-pilot/udvalg.json \
  --ledger ~/.private/43b-ledger/eligibility-ledger-v1.json \
  --restore-identity "$(cat ~/.private/45-pilot/workdb.txt)" --out ~/.private/45-pilot/manifest.json
```

- [ ] **Step 7: GO-anmodning til projektejeren** — i chatten, uden tekst: manifest-hash, de 24 + 6 record-nøgler (reserven markeret), strata-dækning, antal udelukkede henvisninger, budget (≈17.600 input-tokens pr. post ⇒ ≈420.000 for de 24, højst ≈530.000 hvis reserven køres; plus fast CLI-overhead), og stopkriteriet:

| Mål | Nævner | Tærskel (som 4.3b) |
| --- | --- | --- |
| Præcision — sand ifølge teksten | alle afgjorte claims | ≥ 90 % |
| Klausulbinding | alle claims | ≥ 90 % |
| Ordrethed | claims med ordret krav | ≥ 95 % |
| Dækning — andel af menneskeligt noterede udsagn, modellen fandt | noterede udsagn | ≥ 60 % |
| Brugbarhed — biografiske poster med mindst ét korrekt claim | biografiske poster | alle |

Plus §8.4: en prædikatkategori med absurd lav eller høj dækning er `NO-GO` for fuld kørsel. Et claim om en levende person eller med en klausul fra en anden record stopper sporet øjeblikkeligt.

- [ ] **Step 8:** Projektejerens GO med manifest-hash, efter kvotenulstilling. **Uden GO: intet kald.**

---

### Task 3: Kørslen — 24 nye poster i fire bundter

**Files:** ingen i repoet.

- [ ] **Step 1:** Kør bundt for bundt; adgangstesten sker før hvert kald i scriptet.

```bash
for B in bundt_1 bundt_2 bundt_3 bundt_4; do
  python3 run_evidence_43b.py --manifest ~/.private/45-pilot/manifest.json --approved-sha256 <GO-hash> \
    --runner-input ~/.private/43b-runner-input/runner-input-v1.json \
    --ledger ~/.private/43b-ledger/eligibility-ledger-v1.json --bundle "$B" \
    --cache-dir ~/.private/45-pilot/cache --out ~/.private/45-pilot/resultat-$B.json \
    --judgement-sheet ~/.private/45-pilot/raa-ark-$B.json > ~/.private/45-pilot/koersel-$B.out 2>&1
  echo "$B rc=$?"; grep -E '^== |BATCH_PENDING|GATE_FAILED' ~/.private/45-pilot/koersel-$B.out
done
```

Outputtet rummer kun nøgler, tal og prædikater; det må læses. `GATE_FAILED` eller `BATCH_PENDING` stopper sporet med et navngivet fund.

- [ ] **Step 2: Gaten ≥30 bekræftede biografiske poster (V1).** Tæl de nye poster med mindst ét kontraktgyldigt claim og læg 4.3b's 8 til:

```bash
N=$(jq -s '[.[].resultater[] | select(.antal_claims > 0)] | length' ~/.private/45-pilot/resultat-bundt_[1-4].json)
echo "bekræftet biografiske: $((N + 8))"
```

Under 30: kør reserven med samme kommando og `--bundle reserve`, og tæl igen med `resultat-reserve.json` med i globben. Stadig under 30: **STOP** før Task 4 — et fund til projektejeren, ingen kald uden for GO'et. Notér, om reserven blev kørt; Task 4 Step 6 skal vide det.

- [ ] **Step 3:** Forbrug pr. record noteres fra `resultat-*.json` (`usage`). Det er grundlaget for skalafremskrivningen.

**Verify:** alle kørte records med valideret cachepost (`green` eller `delvis`); ≥30 bekræftede biografiske poster; ingen `SCHEMA_DRIFT`/`RUNNER_*_DRIFT`/prompt-/profildrift.

---

### Task 4: Ingest af de nye forslag i arbejdsbasen

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py:183-230`
- Test: `.claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py`

**Interfaces:**
- Produces: `cache_path(cache_dir: Path, ident: dict, *, mode: str) -> Path`, `records_to_ingest(runner_manifest: dict, bundles: list[str] | None) -> list[str]`; CLI `--cache-key {legacy,current}` (default `legacy`) og `--bundles <kommaliste>` (default: hele manifestet). `current` slår op med `evidence_runner.ResponseCache.key(ident)`, hvor `ident` også rummer `record_key`, og kontraktversionen tages fra runner-manifestet. **Legacy-tilstanden er byte-uændret** — 4.4's manifest (`c310ca63…`/`a328ede9…`) genbygges identisk (prøvekørt); de nye provenance-felter `cache_key_mode` og `records` skrives kun i `current`.

- [ ] **Step 1: Skriv den fejlende test** i den eksisterende testfil (samme fixture-mønster som filens øvrige tests: en cache-mappe med én fil og et runner-manifest):

```python
def test_current_cache_key_finder_filen_med_record_key(tmp_path):
    import build_43b_proposal_manifest as b
    import evidence_runner
    rec = {"record_key": "R-1", "persona_id": "p", "post_verbatim_text": "t",
           "clauses": [{"ordinal": 1, "verbatim_text": "t",
                        "verbatim_sha256": evidence_runner.sha256_text("t")}]}
    ident = {"profile_id": "daa-2018-20-v1", "profile_version": "1.3.0", "model": "m",
             "prompt_sha256": "p", "record_key": "R-1",
             "record_input_sha256": evidence_runner.canonical_record_input(rec),
             "claims_schema_sha256": "s",
             "runner_contract_version": evidence_runner.RUNNER_CONTRACT_VERSION}
    assert b.cache_path(tmp_path, ident, mode="current").name == \
        f"{evidence_runner.ResponseCache.key(ident)}.json"
    legacy = {k: v for k, v in ident.items() if k != "record_key"}
    assert b.cache_path(tmp_path, legacy, mode="legacy").name == \
        f"{b.legacy_cache_key(legacy)}.json"


def test_records_to_ingest_tager_kun_navngivne_bundter():
    import pytest
    import build_43b_proposal_manifest as b
    m = {"records": ["A", "B", "C"], "bundter": {"bundt_1": ["A", "B"], "reserve": ["C"]}}
    assert b.records_to_ingest(m, None) == ["A", "B", "C"]
    assert b.records_to_ingest(m, ["bundt_1"]) == ["A", "B"]
    with pytest.raises(ValueError, match="BUNDLE_UNKNOWN"):
        b.records_to_ingest(m, ["bundt_9"])
```

- [ ] **Step 2:** Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_build_43b_proposal_manifest.py -q` — Expected: FAIL `AttributeError: ... 'cache_path'` (og `'records_to_ingest'`).

- [ ] **Step 3: Implementér** — hele ændringen af `build_43b_proposal_manifest.py`:

```diff
--- a/.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py
+++ b/.claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py
@@ -65,6 +65,26 @@
     return hashlib.sha256(material.encode("utf-8")).hexdigest()
 
 
+def cache_path(cache_dir: Path, ident: dict, *, mode: str) -> Path:
+    if mode == "legacy":
+        return cache_dir / f"{legacy_cache_key(ident)}.json"
+    if mode == "current":
+        return cache_dir / f"{evidence_runner.ResponseCache.key(ident)}.json"
+    raise ValueError(f"CACHE_KEY_MODE_UNKNOWN {mode}")
+
+
+def records_to_ingest(runner_manifest: dict, bundles: list[str] | None) -> list[str]:
+    """Hele manifestet, eller kun de navngivne bundter (4.5: reserven kun hvis kørt)."""
+    if not bundles:
+        return list(runner_manifest["records"])
+    from build_43b_manifest import bundles_of
+    alle = bundles_of(runner_manifest)
+    ukendte = [b for b in bundles if b not in alle]
+    if ukendte:
+        raise ValueError(f"BUNDLE_UNKNOWN {ukendte}")
+    return [k for b in bundles for k in alle[b]]
+
+
 def normaliser(tekst: str) -> str:
     """NFKC, casefold, whitespace-kollaps, strip af afsluttende tegnsætning."""
     t = unicodedata.normalize("NFKC", tekst).casefold()
@@ -187,6 +207,8 @@
     ap.add_argument("--cache-dir", required=True)
     ap.add_argument("--profile", required=True)
     ap.add_argument("--out", required=True)
+    ap.add_argument("--cache-key", choices=["legacy", "current"], default="legacy")
+    ap.add_argument("--bundles", help="kommasepareret; default: hele manifestet")
     ap.add_argument("--expect-runner-manifest-sha256", required=True,
                     help="4.3b's godkendte manifest-hash — bygningen stopper, hvis "
                          "forslagene ikke stammer fra netop den kørsel")
@@ -214,7 +236,15 @@
     usage_sum = {"input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0,
                  "cached_input_tokens": 0, "cache_write_input_tokens": 0}
 
-    for key in runner_manifest["records"]:
+    kontrakt = (LEGACY_RUNNER_CONTRACT_VERSION if args.cache_key == "legacy"
+                else runner_manifest["runner_contract_version"])
+    try:
+        noegler = records_to_ingest(runner_manifest,
+                                    args.bundles.split(",") if args.bundles else None)
+    except ValueError as exc:
+        print(str(exc))
+        return 1
+    for key in noegler:
         rec = runner_input[key]
         ident = {
             "profile_id": runner_manifest["profile_id"],
@@ -223,9 +253,11 @@
             "prompt_sha256": runner_manifest["prompt_sha256"],
             "record_input_sha256": canonical_record_input(rec),
             "claims_schema_sha256": runner_manifest["claims_schema_sha256"],
-            "runner_contract_version": LEGACY_RUNNER_CONTRACT_VERSION,
+            "runner_contract_version": kontrakt,
         }
-        sti = cache_dir / f"{legacy_cache_key(ident)}.json"
+        if args.cache_key == "current":
+            ident["record_key"] = key
+        sti = cache_path(cache_dir, ident, mode=args.cache_key)
         if not sti.exists():
             print(f"CACHE_MISS {key} — svaret fra 4.3b kan ikke adresseres.")
             return 1
@@ -334,7 +366,7 @@
             "predicates_sha256": sha256_text(
                 (Path(__file__).resolve().parents[1] / "references"
                  / "interpretation-predicates.json").read_text(encoding="utf-8")),
-            "runner_contract_version": LEGACY_RUNNER_CONTRACT_VERSION,
+            "runner_contract_version": kontrakt,
             "denylist_version": denylist["version"],
             "persona_role_map_version": rolle_map["version"],
             # FEM tal, ikke tre. Uden dem kan "antal = manifestets" ikke
@@ -353,6 +385,10 @@
             "usage": usage_sum,
         },
     }
+    if args.cache_key == "current":
+        # Kun i den nye tilstand: 4.4's legacy-manifest skal kunne genbygges byte-identisk.
+        manifest["provenance"]["cache_key_mode"] = "current"
+        manifest["provenance"]["records"] = noegler
     krop = json.dumps(manifest, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
     manifest["manifest_content_sha256"] = hashlib.sha256(krop.encode("utf-8")).hexdigest()
 
```

- [ ] **Step 4:** Run testfilen igen — Expected: alle bestået (prøvekørt: 29). Genbyg derefter 4.4's manifest i legacy-tilstand til en midlertidig 0600-fil og kontrollér fil-SHA `c310ca63…` og `manifest_content_sha256` `a328ede9…`; slet den midlertidige fil igen (den rummer claim-værdier).

- [ ] **Step 5: Commit.**

```bash
git add .claude/skills/daa-extract/scripts/build_43b_proposal_manifest.py .claude/skills/daa-extract/scripts/test_build_43b_proposal_manifest.py
git commit -m "feat(147): forslagsmanifest kan læse den nuværende cache-nøgle"
```

- [ ] **Step 6: Byg forslagsmanifestet for de 24.**

```bash
python3 build_43b_proposal_manifest.py --cache-key current --bundles bundt_1,bundt_2,bundt_3,bundt_4 \
  --runner-manifest ~/.private/45-pilot/manifest.json --runner-input ~/.private/43b-runner-input/runner-input-v1.json \
  --cache-dir ~/.private/45-pilot/cache --profile ../references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json \
  --expect-runner-manifest-sha256 <GO-hash> --out ~/.private/45-pilot/proposal-manifest.json
```

Blev reserven kørt i Task 3, tilføjes `,reserve` til `--bundles`. Femtalsregnskabet skal gå op (`PROPOSAL_MANIFEST_OK`, ingen `REGNSKABET GÅR IKKE OP`).

- [ ] **Step 7: Kør ingesten** med kopier af 4.4's rehearsal-scripts (`~/.private/44-rehearsal-scripts/44-dryrun.R` og `44-apply.R`) i `~/.private/45-pilot/`. Scriptene finder repoet som `../..` fra deres egen placering; i kopierne erstattes linjen `root <- normalizePath(...)` derfor med repoets absolutte sti. De tager manifestet som eneste argument og læser forbindelsen fra `PGDATABASE`/`PGHOST`/`PGPORT`/`PGUSER`/`PGPASSWORD` — kør dem med `PGDATABASE="$W"` og tomme øvrige (lokal socket), aldrig med `~/.Renviron`s prod-værdier: `env -u PGHOST -u PGPORT -u PGUSER -u PGPASSWORD PGDATABASE="$W" Rscript --vanilla ~/.private/45-pilot/44-dryrun.R ~/.private/45-pilot/proposal-manifest.json`. Kør dry-run før apply. Forventningen (antal forslag, `principal`/`other`, dispositioner) skrives **før** kørslen ud fra manifestets regnskab. Efter kørslen: nul kanonisk delta og `anon` uberørt. #196's komparator bruges **ikke** som gate her: dens fresh/replay-tilstand kræver præcis én ny autorisation, mens dry-run + apply efterlader to (dry-runnens ubrugte `issued` og applyens) — det er prod-wrapperens problem (4.4 D-tabellen), ikke restore-pilotens. Gaten er forventning = resultat, som i 4.4's rehearsal.

**Verify:** forventning = resultat på alle tal; forslag i alt = 84 + manifestets ingestible; `canonical_delta` = 0.

---

### Task 5: Afgørelsesarket — token-fil med hash-binding

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_decision_sheet.py`
- Test: `.claude/skills/daa-extract/scripts/test_interpretation_decision_sheet.py`

**Interfaces:**
- Consumes: en eksport fra arbejdsbasen (Step 5), én række pr. `proposed` fortolkning: `{interpretation_id, version, record_key, predicate, value_text, confidence, persona_role, cited: [{ordinal, text, flags}]}`; valgfrit 4.3b's domme `{(record_key, predicate, value_text): "J"|"N"}`.
- Produces: `reviewsignal(row: dict) -> list[str]`; `render_sheet(rows: list[dict], prior: dict) -> str`; `parse_sheet(text: str) -> list[Decision]` med `Decision(interpretation_id: str, version: int, status: str, note: str, line: int)`; `check_identity(decisions: list[Decision], rows: list[dict]) -> None`; `decision_sql(decisions: list[Decision], *, sheet_sha256: str, rows_sha256: str) -> str`; exception `SheetError`. CLI: `render --rows --prior --out` (printer `rows_sha256`) og `sql --sheet --approved-sha256 --rows --expect-rows-sha256 --out`.

**Arkets form (én beslutning pr. linje; alt andet er kommentar):**

```
# POST I-100 · person.death · confidence 0.92 · principal
#   [3] <klausultekst>
#   værdi: <værdi>        anbefaling: A (4.3b: sand)
D 5b1c…-uuid 1 : A
```

Linjen `se nærmere:` er ERRATA 8.2's reviewsignal, udledt af confidence (< 0,8), persona-rolle (`other`), klausulflag og antal citerede klausuler — vist, aldrig gemt i databasen. Mennesket skriver `A` (accepted), `R` (rejected) eller `U` (unresolved) efter kolonet, eventuelt efterfulgt af `# note`. `_` er uafgjort. Anbefalingen forudfyldes kun, hvor maskinen kan afgøre den (ERRATA 8.2): 4.3b's dom for et identisk claim (`J` ⇒ `A`, `N` ⇒ `R`); ellers står `_`. Sandhed afgøres af mennesket.

- [ ] **Step 1: Skriv de fejlende tests.**

```python
# test_interpretation_decision_sheet.py
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import pytest
from interpretation_decision_sheet import (Decision, SheetError, check_identity, decision_sql,
                                           parse_sheet, render_sheet)

U1 = "11111111-1111-4111-8111-111111111111"
U2 = "22222222-2222-4222-8222-222222222222"
U3 = "33333333-3333-4333-8333-333333333333"
H = "ab" * 32
SCRIPT = str(Path(__file__).resolve().parent / "interpretation_decision_sheet.py")


def row(uid, pred="person.death", value="1850"):
    return {"interpretation_id": uid, "version": 1, "record_key": "I-1", "predicate": pred,
            "value_text": value, "confidence": 0.9, "persona_role": "principal",
            "cited": [{"ordinal": 1, "text": "† 1850", "flags": []}]}


def test_render_forudfylder_kun_fra_tidligere_dom():
    ark = render_sheet([row(U1), row(U2, value="1851")], {("I-1", "person.death", "1850"): "J"})
    assert f"D {U1} 1 : A" in ark
    assert f"D {U2} 1 : _" in ark


def test_render_viser_reviewsignal_fra_forespoergbare_felter():
    r = row(U1)
    r["confidence"] = 0.5
    r["cited"][0]["flags"] = ["unknown_abbreviation"]
    ark = render_sheet([r, row(U2, value="1851")], {})
    assert "se nærmere: lav confidence, klausulflag" in ark
    assert "se nærmere: nej" in ark


def test_parse_laeser_beslutninger_og_noter():
    ark = f"# kommentar\nD {U1} 1 : A\nD {U2} 1 : R # forkert år\n"
    assert parse_sheet(ark) == [Decision(U1, 1, "accepted", "", 2),
                                Decision(U2, 1, "rejected", "forkert år", 3)]


def test_uafgjort_stopper_med_linjenumre():
    with pytest.raises(SheetError, match="SHEET_UNDECIDED lines=2"):
        parse_sheet(f"# x\nD {U1} 1 : _\n")


def test_ukendt_token_og_dublet_stopper():
    with pytest.raises(SheetError, match="SHEET_TOKEN_INVALID"):
        parse_sheet(f"D {U1} 1 : X\n")
    with pytest.raises(SheetError, match="SHEET_DUPLICATE"):
        parse_sheet(f"D {U1} 1 : A\nD {U1} 1 : R\n")


def test_ugyldig_og_indrykket_linje_stopper():
    with pytest.raises(SheetError, match="SHEET_LINE_INVALID"):
        parse_sheet("D ikke-en-uuid 1 : A\n")
    with pytest.raises(SheetError, match="SHEET_LINE_INVALID line=2"):
        parse_sheet(f"D {U1} 1 : A\n  D {U2} 1 : R\n")


def test_slettet_linje_fanges_af_identitetstjekket():
    with pytest.raises(SheetError, match="mangler=1 ekstra=0"):
        check_identity(parse_sheet(f"D {U1} 1 : A\n"), [row(U1), row(U2)])


def test_ombyttet_uuid_fanges_af_identitetstjekket():
    with pytest.raises(SheetError, match="mangler=1 ekstra=1"):
        check_identity(parse_sheet(f"D {U1} 1 : A\nD {U3} 1 : R\n"), [row(U1), row(U2)])


def test_aendret_version_fanges_af_identitetstjekket():
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        check_identity(parse_sheet(f"D {U1} 2 : A\n"), [row(U1)])


def test_sql_er_en_transaktion_med_taelling_og_citering():
    sql = decision_sql([Decision(U1, 1, "accepted", "o'hara", 2)], sheet_sha256=H, rows_sha256=H)
    assert sql.startswith("\\set ON_ERROR_STOP on\nBEGIN;")
    assert "SET LOCAL ROLE authenticated;" in sql
    assert "set_config('request.jwt.claim.sub', :'actor', true)" in sql
    assert f"red_decide_interpretation('{U1}'::uuid, 1, 'accepted'," in sql
    assert "o''hara" in sql and '"rows_sha256"' in sql
    assert "DECISION_COUNT_MISMATCH" in sql
    assert sql.rstrip().endswith("COMMIT;")


def test_sql_kraever_begge_hashes():
    with pytest.raises(SheetError, match="SHEET_HASH_REQUIRED"):
        decision_sql([Decision(U1, 1, "accepted", "", 1)], sheet_sha256="", rows_sha256=H)
    with pytest.raises(SheetError, match="SHEET_HASH_REQUIRED"):
        decision_sql([Decision(U1, 1, "accepted", "", 1)], sheet_sha256=H, rows_sha256="")


def _cli(tmp_path, ark_tekst, godkend_foer=None, rows=None, rows_hash=None):
    rows_fil = tmp_path / "rows.json"
    rows_fil.write_text(json.dumps(rows or [row(U1)]), encoding="utf-8")
    ark = tmp_path / "ark.txt"
    ark.write_text(godkend_foer or ark_tekst, encoding="utf-8")
    godkendt = hashlib.sha256(ark.read_bytes()).hexdigest()
    ark.write_text(ark_tekst, encoding="utf-8")
    p = subprocess.run([sys.executable, SCRIPT, "sql", "--sheet", str(ark),
                        "--approved-sha256", godkendt, "--rows", str(rows_fil),
                        "--expect-rows-sha256",
                        rows_hash or hashlib.sha256(rows_fil.read_bytes()).hexdigest(),
                        "--out", str(tmp_path / "d.sql")], capture_output=True, text=True)
    return p, tmp_path / "d.sql"


def test_cli_afviser_aendret_ark(tmp_path):
    p, sql = _cli(tmp_path, f"D {U1} 1 : R\n", godkend_foer=f"D {U1} 1 : A\n")
    assert p.returncode == 1 and "SHEET_HASH_MISMATCH" in p.stdout and not sql.exists()


def test_cli_afviser_aendret_raekkefil(tmp_path):
    p, sql = _cli(tmp_path, f"D {U1} 1 : A\n", rows_hash="0" * 64)
    assert p.returncode == 1 and "ROWS_HASH_MISMATCH" in p.stdout and not sql.exists()


def test_cli_skriver_sql_for_komplet_ark(tmp_path):
    p, sql = _cli(tmp_path, f"D {U1} 1 : A\n")
    assert p.returncode == 0 and "SQL_OK afgørelser=1" in p.stdout and sql.exists()
```

- [ ] **Step 2:** Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest test_interpretation_decision_sheet.py -q` — Expected: FAIL `ModuleNotFoundError`.

- [ ] **Step 3: Implementér.**

```python
#!/usr/bin/env python3
"""Afgørelsesark for fortolkninger (spec §8.2): token-fil → red_decide_interpretation.

To hashes binder afgørelsen: arkets (det mennesket godkendte) og rækkefilens (det
eksakte sæt `(interpretation_id, version)`, arket blev bygget af). Oversættelsen
kræver, at arkets beslutninger dækker præcis det sæt — en slettet, indrykket eller
ombyttet linje stopper (4.5-review, fund 1).

Arket indeholder kildetekst og skrives 0600 uden for repoet. SQL'en bærer kun id'er,
status, de to hashes og menneskets noter.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from dataclasses import dataclass
from pathlib import Path

TOKENS = {"A": "accepted", "R": "rejected", "U": "unresolved"}
LINE_RE = re.compile(
    r"^D (?P<id>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) "
    r"(?P<ver>[1-9][0-9]*) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")


class SheetError(RuntimeError):
    pass


@dataclass(frozen=True)
class Decision:
    interpretation_id: str
    version: int
    status: str
    note: str
    line: int


def reviewsignal(r: dict) -> list[str]:
    """ERRATA 8.2: signalet udledes af forespørgbare felter og persisteres ikke."""
    s = []
    if r["confidence"] < 0.8:
        s.append("lav confidence")
    if r["persona_role"] != "principal":
        s.append("anden person")
    if any(c["flags"] for c in r["cited"]):
        s.append("klausulflag")
    if len(r["cited"]) > 1:
        s.append("flere klausuler")
    return s


def render_sheet(rows: list[dict], prior: dict) -> str:
    out = ["# AFGØRELSE AF FORTOLKNINGSFORSLAG (4.5)",
           "# Skriv A (accepter), R (afvis) eller U (uafklaret) efter kolonet.",
           "# En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.",
           ""]
    for r in sorted(rows, key=lambda r: (r["record_key"], r["predicate"], r["interpretation_id"])):
        dom = prior.get((r["record_key"], r["predicate"], r["value_text"]))
        anbefaling = {"J": "A (4.3b: sand)", "N": "R (4.3b: usand)"}.get(dom, "ingen")
        out.append(f"# POST {r['record_key']} · {r['predicate']} · confidence "
                   f"{r['confidence']} · {r['persona_role']}")
        for c in r["cited"]:
            flag = f"  flag: {','.join(c['flags'])}" if c["flags"] else ""
            out.append(f"#   [{c['ordinal']}] {c['text']}{flag}")
        out.append(f"#   værdi: {r['value_text']}        anbefaling: {anbefaling}")
        out.append(f"#   se nærmere: {', '.join(reviewsignal(r)) or 'nej'}")
        tok = {"J": "A", "N": "R"}.get(dom, "_")
        out.append(f"D {r['interpretation_id']} {r['version']} : {tok}")
        out.append("")
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Decision]:
    decisions, undecided, seen = [], [], set()
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.rstrip()
        if not line.startswith("D "):
            if line.lstrip().startswith("D "):
                raise SheetError(f"SHEET_LINE_INVALID line={n}")   # indrykket beslutning
            continue
        m = LINE_RE.match(line)
        if not m:
            raise SheetError(f"SHEET_LINE_INVALID line={n}")
        if m["id"] in seen:
            raise SheetError(f"SHEET_DUPLICATE line={n}")
        seen.add(m["id"])
        if m["tok"] == "_":
            undecided.append(n)
            continue
        if m["tok"] not in TOKENS:
            raise SheetError(f"SHEET_TOKEN_INVALID line={n}")
        decisions.append(Decision(m["id"], int(m["ver"]), TOKENS[m["tok"]],
                                  (m["note"] or "").strip(), n))
    if undecided:
        raise SheetError("SHEET_UNDECIDED lines=" + ",".join(map(str, undecided)))
    return decisions


def check_identity(decisions: list[Decision], rows: list[dict]) -> None:
    forventet = {(r["interpretation_id"], r["version"]) for r in rows}
    faktisk = {(d.interpretation_id, d.version) for d in decisions}
    if faktisk != forventet:
        raise SheetError(f"SHEET_IDENTITY_MISMATCH mangler={len(forventet - faktisk)} "
                         f"ekstra={len(faktisk - forventet)}")


def _lit(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def decision_sql(decisions: list[Decision], *, sheet_sha256: str, rows_sha256: str) -> str:
    for h in (sheet_sha256, rows_sha256):
        if not re.fullmatch(r"[0-9a-f]{64}", h or ""):
            raise SheetError("SHEET_HASH_REQUIRED")
    out = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL ROLE authenticated;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true);",
           "CREATE TEMP TABLE decided(id uuid) ON COMMIT DROP;"]
    for d in decisions:
        evidence = json.dumps({"method": "human-sheet-4.5", "sheet_sha256": sheet_sha256,
                               "rows_sha256": rows_sha256, "line": d.line, "note": d.note},
                              ensure_ascii=False, sort_keys=True)
        out.append(f"INSERT INTO decided SELECT red_decide_interpretation("
                   f"'{d.interpretation_id}'::uuid, {d.version}, '{d.status}', "
                   f"{_lit(evidence)}::jsonb);")
    out.append("DO $$ BEGIN IF (SELECT count(*) FROM decided) <> "
               f"{len(decisions)} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;")
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("--rows", required=True)
    r.add_argument("--prior")
    r.add_argument("--out", required=True)
    s = sub.add_parser("sql")
    s.add_argument("--sheet", required=True)
    s.add_argument("--approved-sha256", required=True)
    s.add_argument("--rows", required=True)
    s.add_argument("--expect-rows-sha256", required=True)
    s.add_argument("--out", required=True)
    args = ap.parse_args()

    rows_bytes = Path(args.rows).read_bytes()
    rows_sha = hashlib.sha256(rows_bytes).hexdigest()
    rows = json.loads(rows_bytes.decode("utf-8"))

    if args.cmd == "render":
        prior = {}
        if args.prior:
            prior = {tuple(k.split("\x1f")): v for k, v in
                     json.loads(Path(args.prior).read_text(encoding="utf-8")).items()}
        out = Path(args.out)
        out.write_text(render_sheet(rows, prior), encoding="utf-8")
        out.chmod(0o600)
        forudfyldt = sum(1 for r in rows if (r["record_key"], r["predicate"], r["value_text"]) in prior)
        print(f"ARK_OK linjer={len(rows)} forudfyldt={forudfyldt}")
        print(f"  rows_sha256 {rows_sha}")
        return 0

    if rows_sha != args.expect_rows_sha256:
        print("ROWS_HASH_MISMATCH — rækkefilen er ikke den, arket blev bygget af.")
        return 1
    data = Path(args.sheet).read_bytes()
    faktisk = hashlib.sha256(data).hexdigest()
    if faktisk != args.approved_sha256:
        print("SHEET_HASH_MISMATCH — arket er ikke det, der blev godkendt.")
        return 1
    try:
        decisions = parse_sheet(data.decode("utf-8"))
        check_identity(decisions, rows)
        sql = decision_sql(decisions, sheet_sha256=faktisk, rows_sha256=rows_sha)
    except SheetError as exc:
        print(str(exc))
        return 1
    out = Path(args.out)
    out.write_text(sql, encoding="utf-8")
    out.chmod(0o600)
    tal = {st: sum(1 for d in decisions if d.status == st) for st in TOKENS.values()}
    print(f"SQL_OK afgørelser={len(decisions)} {tal}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4:** Run testfilen — Expected: 14 passed (heraf tre CLI-tests: ændret ark, ændret rækkefil, komplet ark).

- [ ] **Step 5: Eksportér rækkerne fra arbejdsbasen** (0600; filen rummer klausultekst og læses ikke — kun tælles). Forespørgslen er afprøvet mod restoren 2026-09-23 (84 rækker, 8 poster). `value_text` følger 4.3b-arkets regel: strengen selv, eller `raw` for objekter.

```bash
psql -X -q -d "$W" -At -v ON_ERROR_STOP=1 -c "SET default_transaction_read_only=on" -c "
WITH rows AS (
  SELECT ic.id AS interpretation_id, ic.version, sr.record_key, ic.predicate,
         CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END AS value_text,
         ic.confidence, CASE WHEN ic.source_persona_id IS NULL THEN 'other' ELSE 'principal' END AS persona_role,
         jsonb_agg(jsonb_build_object('ordinal', so.clause_ordinal, 'text', so.verbatim_text,
                   'flags', coalesce(so.clause_flags, '[]'::jsonb)) ORDER BY so.clause_ordinal) AS cited
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id = ic.id
    JOIN private.source_observation so ON so.id = io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id = so.occurrence_id
                                               AND ac.decision_status = 'accepted'
    JOIN private.source_record sr ON sr.id = ac.source_record_id
   WHERE ic.status = 'proposed'
   GROUP BY ic.id, ic.version, sr.record_key, ic.predicate, ic.value, ic.confidence, ic.source_persona_id)
SELECT coalesce(jsonb_agg(to_jsonb(rows) ORDER BY record_key, predicate, interpretation_id), '[]') FROM rows" \
  > ~/.private/45-pilot/rows.json
chmod 600 ~/.private/45-pilot/rows.json
jq 'length' ~/.private/45-pilot/rows.json; jq '[.[].record_key]|unique|length' ~/.private/45-pilot/rows.json
```

Forventet: 84 + de nye forslag fra Task 4, fordelt på 8 + antallet af nye poster med forslag. Afviger tallet, stopper Task 5 — en række uden accepteret anker ville ellers mangle i arket.

- [ ] **Step 6: Byg 4.3b's domme** til `~/.private/45-pilot/prior.json` med et engangsscript i `~/.private/45-pilot/` (privat, fordi det læser de private BEDØM-filer): for hvert claim i `~/.private/43b-kørsel/bedoemmelsesark-bundt{1,2}.json` og `bedoemmelsesark-I11.json` parres claim nummer *n* med S-linjen nummer *n* for samme post i den tilsvarende `BEDØM-*.txt`, og nøglen er `record_key\x1fpredicate\x1fværditekst`. Scriptet printer kun antal parrede og uparrede. Uparrede giver `_` i arket — aldrig et gæt.

- [ ] **Step 7: Render arket og aflever det.**

```bash
python3 interpretation_decision_sheet.py render --rows ~/.private/45-pilot/rows.json \
  --prior ~/.private/45-pilot/prior.json --out ~/.private/45-pilot/AFGØR.txt
```

`render` printer `rows_sha256`; den noteres i sessionen og bruges i Task 6. Rækkefilen må ikke ændres herefter. Projektejeren udfylder arket, udpeger sin redaktionsprofil og giver i chatten `shasum -a 256 ~/.private/45-pilot/AFGØR.txt`. Under udfyldningen noteres også de udsagn, modellen burde have fundet (dækningsmålet), i en særskilt fil `~/.private/45-pilot/MANGLER.txt`, ét pr. linje med postens nøgle først.

- [ ] **Step 8: Commit** (kun kode) — tilføj `test_interpretation_decision_sheet.py` til pytest-listen i `ci.yml`.

```bash
git add .claude/skills/daa-extract/scripts/interpretation_decision_sheet.py .claude/skills/daa-extract/scripts/test_interpretation_decision_sheet.py .github/workflows/ci.yml
git commit -m "feat(147): afgørelsesark som token-fil med hash-binding og SQL-oversættelse"
```

---

### Task 6: Afgørelserne i databasen

**Files:** ingen i repoet.

- [ ] **Step 1: Byg SQL'en** med arkets godkendte hash og rækkefilens hash fra Task 5 Step 7:

```bash
python3 interpretation_decision_sheet.py sql --sheet ~/.private/45-pilot/AFGØR.txt \
  --approved-sha256 <hash-fra-chatten> --rows ~/.private/45-pilot/rows.json \
  --expect-rows-sha256 <rows_sha256 fra render> --out ~/.private/45-pilot/afgoerelser.sql
```

Forventet: `SQL_OK afgørelser=<antal rækker>`. `SHEET_IDENTITY_MISMATCH`, `SHEET_UNDECIDED` eller en hash-fejl er STOP.

- [ ] **Step 2: Negativtest af versionskonflikten** (Review Focus 4) i en engangskopi, så arbejdsbasen er urørt. Konflikten lægges på den **sidste** beslutning i SQL-filen, så testen beviser rollback efter mange forudgående vellykkede RPC-kald:

```bash
createdb -T "$W" "${W}_neg"
SIDSTE=$(grep -o "red_decide_interpretation('[0-9a-f-]*'" ~/.private/45-pilot/afgoerelser.sql | tail -1 | cut -d"'" -f2)
# psql udfylder ikke :'variabler' i -c; derfor stdin.
psql -X -d "${W}_neg" -v ON_ERROR_STOP=1 -v actor=<profil-uuid> -v sidste="$SIDSTE" <<'SQL'
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SELECT red_decide_interpretation(:'sidste'::uuid, 1, 'unresolved', '{"method":"negativtest"}'::jsonb);
COMMIT;
SQL
psql -X -d "${W}_neg" -v actor=<profil-uuid> -f ~/.private/45-pilot/afgoerelser.sql > ~/.private/45-pilot/neg.out 2>&1
grep -c EVIDENCE_INTERPRETATION_NOT_PROPOSED ~/.private/45-pilot/neg.out
psql -X -d "${W}_neg" -At -c "SELECT count(*) FROM private.interpretation WHERE decision_evidence->>'method'='human-sheet-4.5'"
```

Forventet: fejlen findes (1), og tællingen er `0` — hele transaktionen rullede tilbage. `${W}_neg` er en engangsbase til netop denne test; den nævnes i Task 8's oprydningsgate.

- [ ] **Step 3: Kør afgørelserne** mod arbejdsbasen:

```bash
psql -X -d "$W" -v actor=<profil-uuid> -f ~/.private/45-pilot/afgoerelser.sql > ~/.private/45-pilot/afgoer.out 2>&1; echo "rc=$?"
psql -X -d "$W" -At -c "SET default_transaction_read_only=on; SELECT status, count(*) FROM private.interpretation_current GROUP BY 1 ORDER BY 1"
```

**Verify:** rc=0; `proposed` = 0 for de afgjorte; `accepted + rejected + unresolved` = antal linjer i arket; hver ny version har `decision_evidence->>'sheet_sha256'` = den godkendte hash.

---

### Task 7: Backup, bindingsforespørgsel og binding

**Files:**
- Create: `.claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql`
- Test: `tests/sql/test-interpretation-promotion-targets.sql`
- Modify: `.github/workflows/ci.yml` (jobbet `evidence promotion`)

**Interfaces:**
- `interpretation_promotion_targets.sql` er en psql-fil uden sideeffekter (kører med `default_transaction_read_only=on`). Den printer én JSON-værdi og gemmer den i `daa.targets_result`: `{"items": [{"interpretation_id", "target_type": "assertion", "target_id"}], "counts": {"<predicate>": {"MATCH": n, "NO_MATCH": n, "AMBIGUOUS": n, "NO_IDENTITY": n, "NO_PLACEMENT": n, "NOT_BULK": n, "ALREADY_PROMOTED": n, "UNSUPPORTED_RULE": n}}}` — alle otte udfald for hvert prædikat med mindst én accepteret fortolkning, 0-fyldt. `items` indeholder kun `MATCH`. Regelflagene (`requires_persona_identity`, `requires_principal_placement`, `bulk_eligible`) og eksisterende promotions spejles fra RPC'en, så en genkørsel ikke giver et `MATCH`, som preview afviser; en regel uden identitetskrav er `UNSUPPORTED_RULE` (fail-closed).
- Normaliseringen er **præcis** RPC'ens: `lower(btrim(normalize(x,NFC)))` på fortolkningens `value #>> '{}'` og assertionens `vaerdi_tekst` (`value_kind='text'`) eller `date_raw` (`value_kind='date_raw'`).

- [ ] **Step 1: Backup** efter afgørelserne og før binding (spec §8.5):

```bash
pg_dump -Fc -d "$W" -f ~/.private/45-pilot/efter-afgoerelser.dump && chmod 600 ~/.private/45-pilot/efter-afgoerelser.dump
shasum -a 256 ~/.private/45-pilot/efter-afgoerelser.dump > ~/.private/45-pilot/efter-afgoerelser.dump.sha256
pg_restore -l ~/.private/45-pilot/efter-afgoerelser.dump | grep -c 'TABLE DATA private interpretation '
```

Forventet: `1` (tabellens data er med).

- [ ] **Step 2: Skriv den fejlende SQL-test** `tests/sql/test-interpretation-promotion-targets.sql`. Den kører i én psql-transaktion, der rulles tilbage. Fixturen følger `tests/sql/test-evidence-promotion.sql` (linje 225-330): én kilde, kørsel, rendition, forekomst og observation; fire personaer og fire personer. Fire `person.death`-fortolkninger dækker de fire udfald, og én `person.office` (uden regel) må ikke tælles. Til sidst skal RPC'ens preview godkende hvert `MATCH` — det beviser, at forespørgsel og RPC er enige.

```sql
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO auth.users(id,email) VALUES ('a4500000-0000-4000-8000-000000000001','targets45@test.invalid');
INSERT INTO profiles(id,rolle,navn,email) VALUES
  ('a4500000-0000-4000-8000-000000000001','redaktion','Targets 45','targets45@test.invalid');
INSERT INTO person(id,levende,privat,status) VALUES
  (-4501,false,false,'targets45'),(-4502,false,false,'targets45'),(-4503,false,false,'targets45');
INSERT INTO source(id,titel,import_key) VALUES (-4500,'Targets 45','verify:targets45');
INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
  VALUES ('a4500000-0000-4000-8000-0000000000e1',-4500,'targets45-run','1.0','verify','verify',repeat('9',64),'{}');
INSERT INTO private.source_rendition(id,source_id,rendition_key,rendition_kind,content_sha256,metadata)
  VALUES ('a4500000-0000-4000-8000-0000000000e2',-4500,'targets45-rendition','text_layer',repeat('8',64),'{}');
INSERT INTO private.source_record_occurrence(id,rendition_id,occurrence_key,page_from,page_to,char_from,char_to,
  verbatim_text,physical_fingerprint,structural_fingerprint,extraction_run_id)
  VALUES ('a4500000-0000-4000-8000-0000000000e3','a4500000-0000-4000-8000-0000000000e2','targets45-occ',1,1,0,4,
          '1850','phys-targets45','struct-targets45','a4500000-0000-4000-8000-0000000000e1');
INSERT INTO private.source_observation(id,occurrence_id,observation_kind,page_from,page_to,char_from,char_to,
  verbatim_text,quality_status,extraction_method,extraction_run_id)
  VALUES ('a4500000-0000-4000-8000-0000000000e4','a4500000-0000-4000-8000-0000000000e3','name_clause',1,1,0,4,
          '1850','clear','verify','a4500000-0000-4000-8000-0000000000e1');
-- Fire personaer (1-3 får identitet til -4501..-4503; 4 får ingen), hver med sin mention.
INSERT INTO private.source_persona(id,source_id,persona_key,created_run_id)
  SELECT ('a4500000-0000-4000-8000-00000000010'||n)::uuid,-4500,'targets45-p'||n,'a4500000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,4) n;
INSERT INTO private.source_mention(id,observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
  SELECT ('a4500000-0000-4000-8000-00000000020'||n)::uuid,'a4500000-0000-4000-8000-0000000000e4','person',0,4,'1850',
         'a4500000-0000-4000-8000-0000000000e1' FROM generate_series(1,4) n;
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT ('a4500000-0000-4000-8000-00000000010'||n)::uuid,('a4500000-0000-4000-8000-00000000020'||n)::uuid,'principal',1
    FROM generate_series(1,4) n;
-- Kanonisk: -4501 én død '1850' (MATCH); -4502 to død '1851' (AMBIGUOUS); -4503 død '1900' (NO_MATCH mod '1901').
INSERT INTO fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-4511,'person',-4501,'død'),(-4512,'person',-4501,'navn'),(-4521,'person',-4502,'død'),(-4522,'person',-4502,'død'),(-4531,'person',-4503,'død');
INSERT INTO assertion(id,target_type,target_id,vaerdi_tekst,calendar,uforanderlig) VALUES
  (-4512,'fact',-4512,'Anna Reventlow','gregoriansk',true);
INSERT INTO assertion(id,target_type,target_id,date_raw,calendar,uforanderlig) VALUES
  (-4511,'fact',-4511,'1850','gregoriansk',true),(-4521,'fact',-4521,' 1851 ','gregoriansk',true),
  (-4522,'fact',-4522,'1851','gregoriansk',true),(-4531,'fact',-4531,'1900','gregoriansk',true);
-- Seks forslag: fire person.death (værdi pr. persona), én person.office og én person.name (tekstgren) på persona 1.
INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
  predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  SELECT ('a4500000-0000-4000-8000-00000000030'||n)::uuid,('a4500000-0000-4000-8000-00000000040'||n)::uuid,1,-4500,
         ('a4500000-0000-4000-8000-00000000010'||CASE WHEN n>=5 THEN 1 ELSE n END)::uuid,'property',
         CASE n WHEN 5 THEN 'person.office' WHEN 6 THEN 'person.name' ELSE 'person.death' END,
         to_jsonb(CASE n WHEN 1 THEN '1850' WHEN 2 THEN '1851' WHEN 3 THEN '1901' WHEN 4 THEN '1852'
                         WHEN 5 THEN 'amtmand' ELSE ' anna REVENTLOW' END),
         '1.0','source_statement',1,'proposed','verify','a4500000-0000-4000-8000-0000000000e1'
    FROM generate_series(1,6) n;
INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT ('a4500000-0000-4000-8000-00000000030'||n)::uuid,'a4500000-0000-4000-8000-0000000000e4','supporting',1
    FROM generate_series(1,6) n;
SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
SET CONSTRAINTS private.interpretation_has_observation DEFERRED;
SELECT set_config('request.jwt.claim.sub','a4500000-0000-4000-8000-000000000001',true);
SET LOCAL ROLE authenticated;
SELECT red_decide_source_persona_identity(('a4500000-0000-4000-8000-00000000010'||n)::uuid,-4500-n,0,'accepted',
         '{"basis":"targets45"}') FROM generate_series(1,3) n;
SELECT red_decide_interpretation(('a4500000-0000-4000-8000-00000000030'||n)::uuid,1,'accepted','{"basis":"targets45"}')
  FROM generate_series(1,6) n;
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF (r->'counts'->'person.death'->>'MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: MATCH %',r; END IF;
  IF (r->'counts'->'person.death'->>'AMBIGUOUS')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: AMBIGUOUS %',r; END IF;
  IF (r->'counts'->'person.death'->>'NO_MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: NO_MATCH %',r; END IF;
  IF (r->'counts'->'person.death'->>'NO_IDENTITY')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: NO_IDENTITY %',r; END IF;
  IF r->'counts' ? 'person.office' THEN RAISE EXCEPTION 'FEJL: prædikat uden regel talt med'; END IF;
  IF (r->'counts'->'person.name'->>'MATCH')::int IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FEJL: tekstgren %',r; END IF;
  IF (r->'counts'->'person.name'->>'AMBIGUOUS')::int IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FEJL: 0-fyld %',r; END IF;
  IF jsonb_array_length(r->'items') <> 2 THEN RAISE EXCEPTION 'FEJL: items %',r->'items'; END IF;
END $$;
-- Forespørgsel og RPC skal være enige om hvert MATCH.
SET LOCAL default_transaction_read_only = off;
SET LOCAL ROLE authenticated;
DO $$
DECLARE p jsonb := red_preview_interpretation_promotions(current_setting('daa.targets_result')::jsonb->'items');
BEGIN
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p->'items') i WHERE (i->>'eligible')::boolean IS NOT TRUE) THEN
    RAISE EXCEPTION 'FEJL: RPC afviser et MATCH: %',p;
  END IF;
  PERFORM red_promote_interpretations_batch(current_setting('daa.targets_result')::jsonb->'items',
                                            p->>'preview_hash');
END $$;
-- Genkørsel efter binding: de bundne er ALREADY_PROMOTED, ikke MATCH.
RESET ROLE;
SET LOCAL default_transaction_read_only = on;
\i .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql
DO $$
DECLARE r jsonb := current_setting('daa.targets_result')::jsonb;
BEGIN
  IF jsonb_array_length(r->'items') <> 0
     OR (r->'counts'->'person.death'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1
     OR (r->'counts'->'person.name'->>'ALREADY_PROMOTED')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'FEJL: genkørsel %',r;
  END IF;
  RAISE NOTICE 'OK: interpretation_promotion_targets — alle udfald, tekst- og datogren, enig med RPC, genkørsel';
END $$;
ROLLBACK;
```

Personaerne får identitet til `-4500-n` (dvs. -4501, -4502, -4503). Kolonne- og constraint-navnene er de samme som i `test-evidence-promotion.sql`; afviger `date_raw`-kolonnen eller `red_decide_source_persona_identity`s argumentorden fra skemaet, rettes fixturen efter skemaet — ikke omvendt.

- [ ] **Step 3:** Run mod en frisk lokal base (samme opbygning som CI-jobbet `evidence promotion`: bootstrap, `schema.sql`, `db-migrations.sql`, `db-rls.sql`) — Expected: FAIL `could not open file ".../interpretation_promotion_targets.sql"`.

- [ ] **Step 4: Implementér målfilen.** Én `SELECT`, der både printer JSON'en og gemmer den i `daa.targets_result` (så testen kan læse den; `set_config` er tilladt i en læse-kun-transaktion). Filen indeholder ingen `BEGIN` og ingen `SET`; kalderen sætter læse-kun.

```sql
-- Bindingsmål for accepterede, promoverbare fortolkninger (spec §8.3).
-- Spejler private.validate_interpretation_promotion_items: samme regelvalg,
-- regelflag (identitet, principal-placering, bulk), eksisterende promotions og
-- normalisering. Kun MATCH bliver til items; alle andre udfald tælles med 0-fyld.
WITH acc AS (
  SELECT ic.id AS interpretation_id, ic.predicate, ic.value #>> '{}' AS v,
         spi.canonical_person_id AS pid, r.expected_fact_type, r.value_kind,
         r.requires_persona_identity, r.requires_principal_placement, r.bulk_eligible,
         EXISTS (SELECT 1 FROM private.source_persona_placement_current pl
                  WHERE pl.source_persona_id = ic.source_persona_id
                    AND pl.decision_status = 'accepted'
                    AND pl.placement_role IN ('principal_member','co_principal')) AS has_placement,
         EXISTS (SELECT 1 FROM private.interpretation_promotion pr
                  WHERE pr.interpretation_id = ic.id) AS already_promoted
    FROM private.interpretation_current ic
    JOIN private.interpretation_promotion_rule_current r
      ON r.predicate = ic.predicate AND r.interpretation_kind = ic.interpretation_kind
     AND r.target_type = 'assertion' AND r.status = 'active'
    LEFT JOIN private.source_persona_identity spi
      ON spi.source_persona_id = ic.source_persona_id AND spi.decision_status = 'accepted'
   WHERE ic.status = 'accepted'
), cand AS (
  SELECT acc.interpretation_id, a.id AS assertion_id
    FROM acc
    JOIN public.fact f ON f.subjekt_type = 'person' AND f.subjekt_id = acc.pid
                      AND f.faktatype = acc.expected_fact_type
    JOIN public.assertion a ON a.target_type = 'fact' AND a.target_id = f.id
   WHERE lower(btrim(normalize(acc.v, NFC))) = lower(btrim(normalize(
           CASE acc.value_kind WHEN 'text' THEN a.vaerdi_tekst
                               WHEN 'date_raw' THEN a.date_raw END, NFC)))
), targets AS (
  SELECT acc.interpretation_id, acc.predicate,
         CASE WHEN NOT acc.requires_persona_identity THEN 'UNSUPPORTED_RULE'
              WHEN acc.pid IS NULL THEN 'NO_IDENTITY'
              WHEN acc.requires_principal_placement AND NOT acc.has_placement THEN 'NO_PLACEMENT'
              WHEN NOT acc.bulk_eligible THEN 'NOT_BULK'
              WHEN acc.already_promoted THEN 'ALREADY_PROMOTED'
              WHEN count(cand.assertion_id) = 0 THEN 'NO_MATCH'
              WHEN count(cand.assertion_id) = 1 THEN 'MATCH'
              ELSE 'AMBIGUOUS' END AS outcome,
         min(cand.assertion_id) AS assertion_id
    FROM acc LEFT JOIN cand USING (interpretation_id)
   GROUP BY acc.interpretation_id, acc.predicate, acc.pid, acc.requires_persona_identity,
            acc.requires_principal_placement, acc.has_placement, acc.bulk_eligible,
            acc.already_promoted
), outcomes(outcome) AS (
  VALUES ('MATCH'),('NO_MATCH'),('AMBIGUOUS'),('NO_IDENTITY'),('NO_PLACEMENT'),
         ('NOT_BULK'),('ALREADY_PROMOTED'),('UNSUPPORTED_RULE')
), grid AS (
  SELECT p.predicate, o.outcome,
         (SELECT count(*) FROM targets t WHERE t.predicate = p.predicate AND t.outcome = o.outcome) AS n
    FROM (SELECT DISTINCT predicate FROM acc) p CROSS JOIN outcomes o
), result AS (
  SELECT jsonb_build_object(
    'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_id', t.interpretation_id, 'target_type', 'assertion',
        'target_id', t.assertion_id) ORDER BY t.interpretation_id)
      FROM targets t WHERE t.outcome = 'MATCH'), '[]'::jsonb),
    'counts', coalesce((SELECT jsonb_object_agg(predicate, c) FROM (
        SELECT predicate, jsonb_object_agg(outcome, n) AS c FROM grid GROUP BY predicate) x),
      '{}'::jsonb)) AS j
)
SELECT set_config('daa.targets_result', j::text, false) AS targets FROM result;
```

- [ ] **Step 5:** Run SQL-testen — Expected: `NOTICE: OK: interpretation_promotion_targets …`. Tilføj den som ét trin i CI-jobbet `evidence promotion` efter `tests/sql/test-evidence-promotion.sql`, med samme `psql -v ON_ERROR_STOP=1`-kald.

- [ ] **Step 6: Commit.**

```bash
git add .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql tests/sql/test-interpretation-promotion-targets.sql .github/workflows/ci.yml
git commit -m "feat(147): bindingsmål for accepterede fortolkninger i SQL"
```

- [ ] **Step 7: Find målene i arbejdsbasen.**

```bash
psql -X -q -d "$W" -At -v ON_ERROR_STOP=1 -c "SET default_transaction_read_only=on" \
  -f .claude/skills/daa-extract/scripts/interpretation_promotion_targets.sql > ~/.private/45-pilot/targets.json
jq -c '.counts' ~/.private/45-pilot/targets.json; jq '.items|length' ~/.private/45-pilot/targets.json
```

Tallene er rapportens bindingsandel; de må læses (ingen tekst).

- [ ] **Step 8: Bind.** Preview og batch i samme session under redaktionsprofilen:

```bash
psql -X -d "$W" -v ON_ERROR_STOP=1 -v actor=<profil-uuid> -v items="$(jq -c .items ~/.private/45-pilot/targets.json)" <<'SQL' > ~/.private/45-pilot/binding.out 2>&1
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', :'actor', true);
SELECT red_preview_interpretation_promotions(:'items'::jsonb)->>'preview_hash' AS h \gset
SELECT red_promote_interpretations_batch(:'items'::jsonb, :'h') AS batch_id;
COMMIT;
SQL
echo "rc=$?"; grep -E 'batch_id|ERROR|EVIDENCE_' ~/.private/45-pilot/binding.out
```

Er `items` tom, springes Step 8 over, og det står i rapporten. En `EVIDENCE_PROMOTION_*`-fejl ruller alt tilbage; så er forespørgsel og RPC uenige — et fund, ikke noget der omgås.

**Verify:** `private.interpretation_promotion` har præcis `len(items)` nye rækker i én batch; intet kanonisk er oprettet (`fact`/`assertion`-antal uændret).

---

### Task 8: Rapport, status og oprydningsgate

**Files:**
- Create: `docs/evidensbaseret-genimport/interpretation-pilot-2018-20.md`
- Modify: `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`

- [ ] **Step 1: Mål** (kun tal, fra arbejdsbasen og de private resultatfiler), pr. prædikattype:
  - præcision mod afgørelsen: `accepted / (accepted + rejected)`; `unresolved` tælles for sig;
  - exact-span-rate: andel, hvor værdien står ordret i den citerede klausul (samme regel som 4.3b-arkets O);
  - dispositionsdækning: klausuler med disposition (`fortolkning_foreslaaet`, `afventer_identitet`) af alle klausuler i de valgte poster;
  - `normalized` uden `raw`-belæg: objektværdier, hvor `raw` ikke står i den citerede klausul;
  - forbrug pr. record (input, output, reasoning) og kvote;
  - bindingsandel: `MATCH` / accepterede promoverbare, med `NO_MATCH`/`AMBIGUOUS`/`NO_IDENTITY` hver for sig;
  - dækning mod `MANGLER.txt`: fundne / (fundne + manglende) pr. post.

- [ ] **Step 2: Skalafremskrivning.** 488 `eligible` × målt forbrug pr. post (median og p90), antal kald, forventet menneskelig afgørelsestid pr. forslag (målt som antal linjer i arket delt med den tid, projektejeren oplyser), og forventet antal bindinger ved samme andel. Skriv eksplicit, hvad fremskrivningen ikke dækker (1939's OCR-klausuler er trin 6).

- [ ] **Step 3: Skriv rapporten** — record-nøgler, strata, hashes (manifest, ark, backup, bindingsbatch), tabellerne fra Step 1-2, stopkriteriets dom og §8.4's `GO`/`NO-GO` for fuld kørsel. **Ingen claim-værdier og ingen klausultekst.** En negativ konklusion skrives lige så tydeligt som en positiv.

- [ ] **Step 4: Status og changelog.** Efter §8.5: »Extractor-runner og modelkald« og »Proposed-ingest« → `integreret ende-til-ende` for 2018-20 (hovedpersonens persona); »Promotion« kun for bindingsdelen, markeret sådan. Intet bliver `produktionsverificeret`. Afgør projektejeren samtidig, om 4.4's parkerede prod-kørsel skal genoptages samlet med afgørelserne, noteres det i `decisions.md`.

- [ ] **Step 5: Commit.**

```bash
git add docs/evidensbaseret-genimport/interpretation-pilot-2018-20.md docs/evidensbaseret-genimport/status.md docs/changelog.md
git commit -m "docs(147): 4.5-pilotrapport — afgørelse, binding og skalafremskrivning"
```

- [ ] **Step 6: Oprydningsgate** (måling først, sletning kun med projektejerens ja): arbejdsbasen, `${W}_neg`, backup-dumpet, cache, ark (`AFGØR.txt`, `MANGLER.txt`, rå ark), `rows.json`, `prior.json`, afgørelses-SQL og restoren `daa43b_20260912192527`. Hver post vises med størrelse og om indholdet findes andre steder. Restoren slettes tidligst, når projektejeren har besluttet 4.4's prod-spørgsmål, for en genoptagelse kan kræve den.

---

## Selvreview-checkliste

- [ ] Er alle kørsler sket i arbejdsbasen — ikke i restoren, og ikke i prod?
- [ ] Er de 24 nye poster valgt før første kald, og alle under samme kontrakt som 4.3b's 10?
- [ ] Står manifest-hashen i GO'et, og er kvoten nulstillet?
- [ ] Blev arkets hash verificeret, før SQL'en blev bygget — og er ingen linjer uafgjorte?
- [ ] Er bindingsnormaliseringen byte-for-byte RPC'ens, og kørte den i SQL?
- [ ] Er backuppen taget efter afgørelserne og før bindingen, og indeholder den `private.interpretation`?
- [ ] Står der kildetekst eller claim-værdier i rapporten, logs, commits eller chatten?
- [ ] Er bindingsandelen rapporteret med alle fire udfald, ikke kun `MATCH`?
- [ ] Står en negativ konklusion lige så tydeligt som en positiv?

## Anden læser

Én smal runde (budget 1 + 1). Codex `gpt-5.6-sol` bedes efterprøve:

1. **Om Task 7's forespørgsel kan give et `MATCH`, som RPC'en afviser**, eller omvendt — dvs. om normalisering, regelvalg og identitetsled er de samme.
2. **Om Task 5-6 kan skrive en afgørelse, mennesket ikke har truffet** (arket ændret, forkert version, delvis transaktion).
3. **Om udvalget i Task 1 opfylder §8.1** (indgiftede måles af gift-aksen, V4) med de valgte signaler, eller om en akse reelt ikke måles.
4. **Om noget i planen kan sende en ikke-eligible record afsted** eller skrive kildetekst ud af maskinen.

Fund, hvis værste udfald er et falsk STOP, er højst MINOR (decisions 2026-09-23).

## Ændringslog

- **2026-09-23, efter anden læser (Codex `gpt-5.6-sol`, eneste runde; NO-GO: 3 MAJOR, 2 MINOR, ingen BLOCKER).** Alle fund er efterprøvet og rettet i task-kroppen, ikke i en præambel; rettelserne er prøvekørt. Ingen runde 2 (budget 1 + 1).
  1. *Arkhashen bandt ikke de forelagte fortolkninger* → rækkefilen hash-bindes, `check_identity` kræver præcis dens `(id, version)`-sæt, indrykkede beslutningslinjer afvises; tests for slettet, indrykket og ombyttet linje; Task 6's negativtest rammer sidste linje (Task 5-6, Review Focus 1).
  2. *Udvalget målte ikke §8.1, og ≥30 var ingen gate* → gift som antal (0/1/2+) i strata; »indgiftet« som eksplicit definitionsvalg V4 (partner uden fødselsfamilie) i stedet for fravær af egen `barn`-række; 6 reserveposter i samme GO og en fail-closed gate på ≥30 bekræftede biografiske poster; hele definitionen i `strata_sha256` (V1, V4, Task 1, Task 3).
  3. *Kontrakten blev ikke genvalideret ved kaldet* → `check_contract` (manifest, skemahash, kontraktversion, runner-kodehash) før første `prepare_call_dir`, med mutationstest uden modelkald (Task 2).
  4. *Bindingsforespørgslen spejlede ikke regelflag og eksisterende promotions* (MINOR) → otte udfald, test af genkørsel efter binding (Task 7).
  5. *Tællingerne var ikke 0-fyldte, og tekstgrenen var utestet* (MINOR) → krydsprodukt prædikat × udfald; `person.name`-tilfælde i testen (Task 7).
- **2026-09-24, projektejerens afgørelse af V4.** Database-signalet for indgiftede (partner uden forældre i basen) er fjernet: det måler indlæsningsgraden, ikke personen, og skifter betydning, når flere slægter indlæses. Gift-antallet dækker nu begge §8.1-akser; Task 1's databaseeksport er væk (`45-strata-v3`). Prøvekørt: 10/10, `UDVALG_OK nye=24 reserve=6`.
