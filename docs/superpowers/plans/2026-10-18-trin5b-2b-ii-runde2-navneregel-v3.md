# Trin 5b 2b-ii runde 2 — navneregel v3 og den første nye person på bogens data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind as many as possible of the 12 marriages left `U` in 2b-ii to their existing partner with a deterministic name rule v3 (plus the projektejer's end-of-name correction), and create 2b-i's `new_person_needed` spouse (clause year 1314) as the first new person on the book's data; prove it in a restore copy.

**Architecture:**
- A new Python extractor `relation_persona_extract_v3.py` reuses v2's window and year rule. On top of that it adds:
  - a closed title list;
  - particle and title chains inside the name run;
  - a surname-anchored partner comparison;
  - an ordinal tie-break;
  - a zero-hits requirement for `D`/`N`;
  - a proposal for P-rows (re-decision with `deceased`).
- A new sheet tool `relation_marriage_sheet_v3.py` adds `navn: »…«` (end-of-name correction) and P-lines.
- In SQL:
  - `write_relation_persona` accepts profile v3 with three provenance keys;
  - `write_relation_person_create` rejects title words, stale clauses and stale interpretations;
  - a new read projection `relation_persona_v3_input` adds the post text and the P-rows.
- v2 code and v2 tests stay untouched.

**Tech Stack:**
- PostgreSQL 17 (PL/pgSQL, append-only `db-migrations.sql` with the flattened `schema.sql`);
- Python 3 (pytest);
- psql/bash e2e;
- GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md` **§17** (GODKENDT 2026-10-18). The rest of that spec (§1–§16) is the 2b-ii base this round builds on.

## Global Constraints

- **Privacy.** Names and source text must never appear in chat, commits, PR or report; only numbers and hashes.
  - Private files live in `~/.private/5b-navneregel-v3/` (0600), never in a git work tree.
  - Test fixtures use invented names only.
- **No model reads the clause text.** Everything is deterministic (spec §17.4).
- **`db-migrations.sql` is append-only for merged content.** New and changed functions go in new blocks marked `-- Trin 5b 2b-ii runde 2 (#151, spec §17.x)`, placed **immediately above** the line `-- 5b-sektionen slutter her (nye 5b-blokke indsættes over denne linje).` (currently `db-migrations.sql:23071`). `schema.sql` is edited in place, so a fresh schema equals a migrated schema.
- **Payload profile** is `relation-persona-2018-20-v3`. The writer profile id in `private.reimport_writer_profile` stays `relation-persona-2018-20`.
- **Age rule** is unchanged: `aarstal-120-v1`, cutoff `1906`. `red_afgoer_source_persona` and the writer's year recompute are **not** changed (spec §17.3: age rule v2 is out).
- **Title list (spec §17.5), closed:**
  - base words: `baron, baronesse, friherre, friherreinde, greve, grevinde, hertug, hertuginde, komtesse, prins, prinsesse`;
  - optional prefix `rigs` or `lens`, on a base word only.
- **Particles v3** = v2's `{von, de, af, du, la, van, zu, der, den}` ∪ `{und, zu, dem, genannt}`.
- **`D` and `N` require zero partner hits and a title-free name.** `U` → `S` is only possible when the rule confirms it on the corrected name.
- **`navn:` must:**
  - start exactly at the rule's name start;
  - appear verbatim and exactly once in the clause;
  - end within the window.
- **v3 persona elements carry** `name_basis` (`rule`|`sheet`), `sheet_sha256` and `sheet_line`. There are no new columns; the payload is copied into `reimport_event`.
- **psql in scripts:** use `env -u PGOPTIONS psql -X`. Sheet scripts lock `SET LOCAL standard_conforming_strings=on`.
- **Commits:**
  - Conventional Commits in Danish, atomic per task;
  - trailer `Claude-Session: https://claude.ai/code/session_011rKEYw62xDPse4zhLARtjo`;
  - no Claude attribution;
  - no push without the projektejer's yes.
- **pytest:** `/private/tmp/claude-501/-Users-johanreventlow-TypeScript-danmarksadelsaarbog/661443a4-16c6-44ec-b137-e7792168526d/scratchpad/venv314/bin/python -m pytest`. Recreate it with `python3 -m venv … && …/pip install pytest pyyaml` if tmp cleanup removed it.
- **Scratchpad helpers** (not in the repo; tmp cleanup can remove them):
  - `mkdb.sh <db> fresh|migrated|writer` builds a disposable DB from the working tree. `fresh` = `tests/sql/evidence-promotion-bootstrap.sql` + `schema.sql` + `db-rls.sql`. `migrated` = the same plus `db-migrations.sql` twice and `db-rls.sql`. `writer` = `fresh` plus `tests/sql/1939-v50-writer-bootstrap.sql`, then `BEGIN` / `tests/sql/reimport-writer-v2-bootstrap.sql` / `COMMIT`, then `db-rls.sql`. All `psql` runs use `env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1`.
  - `gen_ci.py <repo> <outdir> <venv>` reads `.github/workflows/ci.yml` and writes one bash script per job. It skips `npm ci` and `install.packages` steps. Each job with a postgres service gets its own `initdb` cluster on its own port (from 55441, `--locale=en_US.UTF-8`, `trust`), with `POSTGRES_DB` created. The step env is exported, and each script ends with `CI_JOB_OK_<job>` when nothing failed.
  - If either is missing, recreate it from this description before Task 3.
- **Local test DBs** are named `ci5b_v3_*`. The evidence base `daa5b_2b_ii_bevis_20261017132417` is read-only; the proof runs in a copy.
- **Review budget** is 1 + 1 (decisions 2026-09-23, restore only).

## Review Focus

1. **A capitalized title before the name** (»Komtesse Ida Dal«) is the name start under v2's start rule. The title then enters the span, and for `D` it would reach `visning_navn`.
   - Expected: `D` is impossible (title check), so the proposal is `U`.
   - Pinned by `test_kapitaliseret_titel_foer_navnet_giver_ikke_D` (Task 1) and the writer test `RELATION_PERSON_CREATE_NAME_TITLE` (Task 3).
2. **The canonical partner name carries a suffix or digits** (`visning_fuldt_navn` with a year or a parenthesis).
   - Expected: digits are ignored and the surname is still the last core word.
   - Pinned by `test_partner_med_aarstal_i_navnet` (Task 1).
3. **`navn:` text that also appears earlier in the post but only once in the clause** is allowed. Text that appears twice in the clause is rejected.
   - Pinned by `test_navn_to_gange_afvises` (Task 4).
4. **The P-row's spouse already exists as a partner** (the principal got a family after 2b-i).
   - Expected: `U`, never `D` (duplicate).
   - Pinned by `test_P_partner_findes_giver_U` (Task 1).
5. **Re-running the identity script after the P-line has applied.**
   - Expected: `EVIDENCE_IDENTITY_VERSION_CONFLICT` and 0 new events.
   - Pinned by the e2e rerun in `test-relation-marriage-sheet-v3.sh` and its separate P-line call (Task 4), and by negative test A with its separate P-line call (Task 6). The script rerun alone stops at the first `M` line and never tests the P-line's lock.

---

## File Structure

| Fil | Ansvar | Task |
| --- | --- | --- |
| `.claude/skills/daa-extract/scripts/relation_persona_extract_v3.py` (+ `test_relation_persona_extract_v3.py`) | titelliste, navneregel v3, partnersammenligning, S/D/N/I/U, P-forslag | 1 |
| `~/.private/5b-navneregel-v3/` (privat) | tørkørselstal | 2 |
| `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | `private.relation_title_words`, `private.relation_name_has_title`, `write_relation_persona` v3, `write_relation_person_create` stramninger, `relation_persona_v3_input` + `red_`-wrapper | 3 |
| `tests/sql/test-relation-persona-v3.sql`, `tests/sql/test-relation-person-create-v3.sql` | writer v3, v3-input, person_create-afvisninger | 3 |
| `.claude/skills/daa-extract/scripts/relation_marriage_sheet_v3.py` (+ test), `relation_v3_rows.sql` | ark v3: render/sql, `navn:`, P-linjer | 4 |
| `tests/sql/fixtures/relation-marriage-v3.sql`, `tests/sql/test-relation-marriage-sheet-v3.sh` | ark v3 ende til ende | 4 |
| `.github/workflows/ci.yml` | CI | 5 |
| `.claude/skills/daa-extract/scripts/test_identity_guard_static.py` | ALLOWLIST-tælling for den nye migrationskopi | 3 |
| `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md`, `status.md`, `docs/changelog.md`, `docs/decisions.md` | bevis og dokumenter | 6 |

---

### Task 1: Udtræk v3 (navneregel, titelliste, partnersammenligning, P-forslag)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/relation_persona_extract_v3.py`
- Test: `.claude/skills/daa-extract/scripts/test_relation_persona_extract_v3.py`

**Interfaces:**
- Consumes (v2, unchanged): `relation_persona_extract_v2.CAP, STOP_TITLE, TOKEN, YEAR, PARTICLES, _start, _words, windows`; `relation_persona_extract.LETTER, MAX_NAME_WORDS, UPPER`.
- Produces:
  - `PROFILE: str = "relation-persona-2018-20-v3"`, `RULE: str = "aarstal-120-v1"`;
  - `TITLE_WORDS: tuple[str, ...]`, `TITLE_PREFIXES: tuple[str, ...]`, `PARTICLES: set[str]`;
  - `is_title(word: str) -> bool`, `title_free(name: str) -> bool`;
  - `partner_hit(name: str, partner_name: str | None) -> bool`;
  - `class NameOverrideError(ValueError)`;
  - `propose(row: dict, cutoff: int, name_override: str | None = None) -> dict`. The returned keys are `tok, reason` and, when a name was found, `span_from, span_to, name_from, name_to, clause_years, name_basis`. The name keys are present also for `U` with reason `flere_partnere`, `titel_i_navn` or `navn_afkortet`. For `S` it also returns `partner_person_id, partner_ordinal`. A `name_override` on a row without a name start raises `NameOverrideError`.
  - `propose_redecide(prow: dict, cutoff: int) -> dict`. The returned keys are `tok ∈ {D,N,U}, reason`, plus `clause_years` when `tok ∈ {D,N}`.

- [ ] **Step 1: Write the failing tests**

```python
"""Trin 5b 2b-ii runde 2 (spec §17.4-17.5): navneregel v3. Kun opdigtede navne."""
import re
from pathlib import Path

import pytest

import relation_persona_extract_v3 as v3


def row(text, raw, partners=(), principal=1, ordinal=1, key="k1"):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "marriage_ordinal": ordinal, "supporting_count": 1, "principal_ok": principal is not None,
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd .claude/skills/daa-extract/scripts && $PY -m pytest test_relation_persona_extract_v3.py -q` (`$PY` = the venv python from Global Constraints)
Expected: FAIL with `ModuleNotFoundError: No module named 'relation_persona_extract_v3'`.

- [ ] **Step 3: Implement**

```python
"""Trin 5b 2b-ii runde 2 (spec §17.4-17.5): navneregel v3, partnersammenligning og P-forslag.

Deterministisk; ingen model læser teksten. Ordvinduet og årstallene er v2's (SQL-tvillingerne er uændrede).
"""
from __future__ import annotations

import re

from relation_persona_extract import LETTER, MAX_NAME_WORDS, UPPER
from relation_persona_extract_v2 import CAP, STOP_TITLE, TOKEN, WORD, YEAR, _start, _words, windows
from relation_persona_extract_v2 import PARTICLES as _PARTICLES_V2

PROFILE = "relation-persona-2018-20-v3"
RULE = "aarstal-120-v1"
# Lukket titelliste (spec §17.5) = SQL-tvillingen private.relation_title_words(); test_title_words_match_schema låser dem.
TITLE_WORDS = ("baron", "baronesse", "friherre", "friherreinde", "greve", "grevinde", "hertug", "hertuginde",
               "komtesse", "prins", "prinsesse")
TITLE_PREFIXES = ("rigs", "lens")
PARTICLES = _PARTICLES_V2 | {"und", "zu", "dem", "genannt"}
NOT_NAME = {"til"}   # »til <gods>« ≠ navn (beslutning 2026-10-03); udløser ikke navn_afkortet
LOWER_WORD = re.compile(r"[a-zæøåà-öø-ÿ]+")


class NameOverrideError(ValueError):
    """Arkets navn: står ikke ordret og entydigt fra navnestarten inden for vinduet."""


def is_title(word: str) -> bool:
    w = word.lower()
    return w in TITLE_WORDS or any(w.startswith(p) and w[len(p):] in TITLE_WORDS for p in TITLE_PREFIXES)


def title_free(name: str) -> bool:
    """Sikring ved D (spec §17.5): hvert ord har versal eller er en partikel, og intet ord er en titel.
    Ordene deles som i SQL-tvillingen (på alle ikke-ordtegn), så »Rigs-Grevinde« fanges allerede på arket."""
    for m in WORD.finditer(name):
        w = m.group(0)
        if is_title(w) or not (CAP.fullmatch(w) or w.lower() in PARTICLES):
            return False
    return True


def _links_to_name(toks, k: int) -> bool:
    """Partikler og titler inde i navnet: kæden fra k skal ende i et ord med versal. Komma/punktum må ikke stå
    inde i kæden, men gerne efter slutordet (hovedløkken afslutter navnet dér)."""
    j = k
    while j < len(toks):
        word = toks[j][2]
        bare = word.rstrip(",.;:")
        if bare.lower() in PARTICLES or is_title(bare):
            if bare != word:
                return False
            j += 1
            continue
        return bool(CAP.fullmatch(bare))
    return False


def _truncated(text: str, nt: int, st: int) -> bool:
    """Reglen stoppede foran et ulistet småord, som efterfølges af et versalord (fx en ukendt titel inde i
    navnet). Sådan et navn er afkortet og må ikke blive D (spec §17.9)."""
    m = re.match(r"\s+(\S+)\s+(\S+)", text[nt:st])
    if not m:
        return False
    w, nxt = m.group(1), m.group(2).rstrip(",.;:")
    return bool(LOWER_WORD.fullmatch(w)) and w not in PARTICLES and w not in NOT_NAME and bool(CAP.fullmatch(nxt))


def _name(seg: str):
    """Som v2, men navneløbet fortsætter over partikel- og titelkæder, der ender i et versalord."""
    start, after_gift = _start(seg)
    toks = [(m.start(), m.end(), m.group(0)) for m in TOKEN.finditer(seg, start)]
    k = 0
    while k < len(toks):                                   # spring titler/forkortelser over (som v2)
        word = toks[k][2]
        bare = word.rstrip(",.;:")
        if CAP.fullmatch(bare) and not (word.endswith(".") and len(bare) <= 4):
            break
        k += 1
    if k == len(toks):
        return None
    titel = seg[start:toks[k][0]]
    if any(ch in titel for ch in ";()*†") or STOP_TITLE.search(titel):
        return None
    if after_gift and not re.fullmatch(r"[\s\d.,°/-]*", titel):
        return None
    if not after_gift and any(ch.isdigit() for ch in titel):
        return None
    nf, nt, words = toks[k][0], None, 0
    while k < len(toks):
        s, _e, word = toks[k]
        bare = word.rstrip(",.;:")
        if CAP.fullmatch(bare):
            nt, words = s + len(bare), words + 1
        elif nt is not None and bare == word and _links_to_name(toks, k):
            nt = s + len(bare)
        else:
            break
        if bare != word:                                   # komma/punktum afslutter navnet
            break
        k += 1
    if nt is None or words > MAX_NAME_WORDS or not LETTER.search(seg[nf:nt]):
        return None
    return nf, nt


def _core(name: str | None) -> list[str]:
    return [w for _, _, w in _words(name or "") if not w.isdigit() and w not in PARTICLES and not is_title(w)]


def partner_hit(name: str, partner_name: str | None) -> bool:
    """Efternavnet (sidste kerneord) skal passe, og mindst halvdelen af navnets kerneord skal være fælles."""
    a, b = _core(name), _core(partner_name)
    if not a or not b or a[-1] != b[-1]:
        return False
    sa = set(a)
    return 2 * len(sa & set(b)) >= len(sa)


def propose(row: dict, cutoff: int, name_override: str | None = None) -> dict:
    """Forslag for én række. En navn:-rettelse kræver en navnestart; ellers NameOverrideError (spec §17.6),
    også ved de tidlige U og ved I, så rettelsen aldrig ignoreres tavst."""
    p = _propose(row, cutoff, name_override)
    if name_override is not None and "name_from" not in p:
        raise NameOverrideError("ingen navnestart")
    return p


def _propose(row: dict, cutoff: int, name_override: str | None) -> dict:
    if not row.get("principal_ok") or row.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if row["supporting_count"] != 1 or len(row["clauses"]) != 1:
        return {"tok": "U", "reason": "flere_klausuler"}
    if row.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    text, raw = row["clauses"][0]["verbatim_text"], row.get("raw") or ""
    w = windows(text, raw)
    if len(w) != 1:
        return {"tok": "U", "reason": "intet_vindue" if not w else "tvetydigt_vindue"}
    sf, st = w[0]
    seg = text[sf:st]
    nm = _name(seg)
    if nm is None:
        if UPPER.search(seg, _start(seg)[0]) is None:
            return {"tok": "I", "reason": "intet_navn", "span_from": sf, "span_to": st}
        return {"tok": "U", "reason": "navn_uklart"}
    nf, nt = sf + nm[0], sf + nm[1]
    basis = "rule"
    if name_override is not None:
        o = name_override
        end = nf + len(o)
        if (o != o.strip() or not LETTER.search(o) or not text.startswith(o, nf)
                or end > st or text.count(o) != 1
                or not o[-1].isalpha() or (end < len(text) and text[end].isalnum())):   # helt ord, ingen tegnsætning
            raise NameOverrideError("navn")
        nt, basis = nf + len(o), "sheet"
    name = text[nf:nt]
    years = sorted({int(y) for y in YEAR.findall(text)})
    out = {"span_from": sf, "span_to": st, "name_from": nf, "name_to": nt, "clause_years": years, "name_basis": basis}
    hits = [p for p in row.get("principal_partners", []) if partner_hit(name, p.get("navn"))]
    ids = {p["person_id"] for p in hits}
    if len(ids) == 1:
        return {**out, "tok": "S", "reason": "partnermatch", "partner_person_id": hits[0]["person_id"],
                "partner_ordinal": hits[0].get("ordinal")}
    if ids:
        same = {p["person_id"] for p in hits if p.get("ordinal") == row["marriage_ordinal"]}
        if len(same) == 1:
            return {**out, "tok": "S", "reason": "partnermatch_nummer", "partner_person_id": same.pop(),
                    "partner_ordinal": row["marriage_ordinal"]}
        return {**out, "tok": "U", "reason": "flere_partnere"}
    if not title_free(name):
        return {**out, "tok": "U", "reason": "titel_i_navn"}
    if basis == "rule" and _truncated(text, nt, st):
        return {**out, "tok": "U", "reason": "navn_afkortet"}
    if years and max(years) <= cutoff:
        return {**out, "tok": "D", "reason": "aldersregel"}
    return {**out, "tok": "N", "reason": "kan_ikke_erklaeres_afdoed"}


def propose_redecide(prow: dict, cutoff: int) -> dict:
    """P-linjen (spec §17.6): en new_person_needed uden deceased; D kun efter aldersreglen og uden partnertræf."""
    if not prow.get("clause_is_current"):
        return {"tok": "U", "reason": "klausul_afloest"}
    if prow.get("principal_person_id") is None:
        return {"tok": "U", "reason": "ingen_hovedperson"}
    if prow.get("marriage_ordinal") is None:
        return {"tok": "U", "reason": "intet_nummer"}
    name = prow.get("name_text") or ""
    if any(partner_hit(name, p.get("navn")) for p in prow.get("principal_partners", [])):
        return {"tok": "U", "reason": "partner_findes"}
    if not title_free(name):
        return {"tok": "U", "reason": "titel_i_navn"}
    years = sorted({int(y) for y in YEAR.findall(prow.get("clause_text") or "")})
    if years and max(years) <= cutoff:
        return {"tok": "D", "reason": "aldersregel", "clause_years": years}
    return {"tok": "N", "reason": "kan_ikke_erklaeres_afdoed", "clause_years": years}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `$PY -m pytest test_relation_persona_extract_v3.py test_relation_persona_extract_v2.py -q`
Expected:
- `test_title_words_match_schema` FAILS: `private.relation_title_words() mangler i schema.sql`. Task 3 makes it pass, so mark it `@pytest.mark.xfail(strict=True, reason="Task 3")` now and remove the mark in Task 3.
- All others PASS. v2 tests are unchanged and green.

- [ ] **Step 5: Commit**

```bash
git add .claude/skills/daa-extract/scripts/relation_persona_extract_v3.py .claude/skills/daa-extract/scripts/test_relation_persona_extract_v3.py
git commit -m "feat(151): navneregel v3 med titelliste, partikelkæder og efternavnsmatch (2b-ii runde 2)"
```

---

### Task 2: Tørkørsel på bogens data (læse-kun, kun tal) — STOP-port

**Files:** private only: `~/.private/5b-navneregel-v3/` (mode 700; files 0600). No repo change.

**Interfaces:**
- Consumes:
  - `~/.private/5b-2b-ii/rows.json` (2b-ii's rows file; sha `7065dd4e…d6cb`);
  - `~/.private/5b-2b-ii/ark.txt` (the user's 2b-ii answers);
  - `v3.propose`, `v3.propose_redecide`;
  - the evidence base, read-only.
- Produces: the ledger lines with the distribution, which Task 6 compares against.

- [ ] **Step 1: The 12 rows under v3.**
  - Run a read-only Python snippet over `rows.json`, skipping the 2 rows whose 2b-ii answer was `S` (they are bound).
  - Print per row only: index, v2 token, v3 token, reason, number of partner hits, ordinal skew (yes/no), and whether the v3 name is longer than v2's (yes/no).
  - Then print the total distribution.
  - Expected design outcome:
    - `S` 9 (the 8 name-span failures plus row 5 via ordinal);
    - row 2 `U ingen_hovedperson`;
    - row 11 `U flere_klausuler`;
    - row 1 `I` or `U`;
    - `D` 0 and `N` 0.
- [ ] **Step 2: The P-row, read-only SQL in the evidence base.** For the `unresolved`/`new_person_needed` persona without `deceased`, print:
  - `version`;
  - spouse-party `marriage_ordinal`;
  - principal accepted (t/f);
  - `private.relation_person_create_family(principal, ord) IS NULL`;
  - clause is `clause_observation_current` (t/f);
  - clause years;
  - name: word count, title (t/f), particle (t/f);
  - the spouse-party interpretation's status in `interpretation_current` is `proposed` or `accepted` (t/f), which is the new writer check (c);
  - the persona is in no sealed control sample (t/f), which `red_afgoer_source_persona`'s guard requires.

  Expected:
  - version 1, ordinal not NULL, principal accepted, family NULL, current t, interpretation t, not sealed t;
  - years `[1314]`;
  - name 3 words, title f, particle t.
- [ ] **Step 3: STOP rule.** If any of the 12 gets `D` or `N`, or the P-row deviates from Step 2's expectation, stop and ask the projektejer. Report only the numbers. An `S` count below 9 is **not** a stop: the remaining rows are what `navn:` is for. Write both outputs to the ledger.

---

### Task 3: SQL — titelliste, writer v3, person_create-stramninger, v3-input

**Files:**
- Modify: `schema.sql` (in place, next to the 2b-ii definitions), `db-migrations.sql` (new blocks above the 5b end marker), `db-rls.sql:702` (ACL list), `db-verify.sql:2980` (ACL list) plus a new verify block after `$verify_family_id$` (`db-verify.sql:10248`).
- Create: `tests/sql/test-relation-persona-v3.sql`, `tests/sql/test-relation-person-create-v3.sql`.
- Modify: `.claude/skills/daa-extract/scripts/test_identity_guard_static.py` (ALLOWLIST: `("db-migrations.sql", "write_relation_person_create", "relation_person_create")` goes from 1 to 2, with the comment `# 2b-ii runde 2: kopi med titelværn og aktualitetstjek`; precedent: `red_afgoer_source_persona … : 2`). Step 4 pkt. 3 adds the second copy, so the guard is red without this.

**Interfaces:**
- Consumes: the existing fixtures `tests/sql/fixtures/relation-5b.sql` and `relation-2a.sql` (`pg_temp.f5b_actor/_source/_post/_claim/_spouse/_family/_write/_batch/_profile`, `pg_temp.f2a_event_for_state`).
- Produces:
  - `private.relation_title_words() RETURNS text[] IMMUTABLE`;
  - `private.relation_name_has_title(p_name text) RETURNS boolean IMMUTABLE`;
  - `private.relation_persona_v3_input(p_source_id bigint) RETURNS jsonb` (contract `relation-persona-v3-input`, keys `source_id, deceased_cutoff_year, rows[], redecide_rows[]`);
  - `public.red_relation_persona_v3_input(bigint)` (redaktion only);
  - error codes `RELATION_PERSON_CREATE_NAME_TITLE`, `RELATION_PERSON_CREATE_CLAUSE_STALE`, `RELATION_PERSON_CREATE_INTERPRETATION_STALE`.

- [ ] **Step 1: Write the failing SQL tests.**

`tests/sql/test-relation-persona-v3.sql`:

```sql
-- Trin 5b 2b-ii runde 2 (spec §17.7): relation_persona profil v3 og v3-input. Opdigtede navne.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $v3_title$
BEGIN
  IF NOT private.relation_name_has_title('Ida komtesse Dal') OR NOT private.relation_name_has_title('Ida Rigsgrevinde Dal')
     OR NOT private.relation_name_has_title('Ida lensbaronesse Dal') OR private.relation_name_has_title('Eva von und zu Fik')
     OR private.relation_name_has_title('Ida Grevskab') THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: titeltjek';
  END IF;
  RAISE NOTICE 'OK: titelliste';
END $v3_title$;

DO $v3_writer$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3a1'; s jsonb; p jsonb; c jsonb; v_clause uuid; v_in jsonb; e jsonb;
  v_text text:='Gift 1890 med Ida komtesse Dal, f. 1801.'; sp uuid; v_ev jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5341,false,false,'5b'),(-5342,false,false,'5b');
  s:=pg_temp.f5b_source(-5341);
  p:=pg_temp.f5b_post(-5341,s,'II-41','Anna Alfa. '||v_text,ARRAY['Anna Alfa.',v_text],-5341,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  v_clause:=(p->'clauses'->>1)::uuid;
  c:=pg_temp.f5b_claim(-5341,s,'relation.marriage',v_clause,'Gift med Ida komtesse Dal');
  -- P-kandidat: en anden post, ægtefælle-persona afgjort new_person_needed uden deceased (som 2b-i's kø)
  p:=pg_temp.f5b_post(-5341,s,'II-42','Bent B. Gift 1314 med Gro von Hak.',ARRAY['Bent B.','Gift 1314 med Gro von Hak.'],-5342,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  sp:=pg_temp.f5b_spouse(-5341,s,p,pg_temp.f5b_claim(-5341,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1314 med Gro von Hak.'),
        (p->'clauses'->>1)::uuid,'Gro von Hak',1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(sp,0,'new_person_needed',NULL,'kø',NULL);
  RESET ROLE;
  v_in:=private.relation_persona_v3_input(-5341);
  IF v_in->>'contract'<>'relation-persona-v3-input' OR jsonb_array_length(v_in->'rows')<>1
     OR v_in#>>'{rows,0,post_text}'<>'Anna Alfa. '||v_text OR jsonb_array_length(v_in->'redecide_rows')<>1
     OR v_in#>>'{redecide_rows,0,source_persona_id}'<>sp::text OR (v_in#>>'{redecide_rows,0,identity_version}')::int<>1
     OR v_in#>>'{redecide_rows,0,clause_text}'<>'Gift 1314 med Gro von Hak.' OR v_in#>>'{redecide_rows,0,name_text}'<>'Gro von Hak'
     OR (v_in#>>'{redecide_rows,0,clause_is_current}')::boolean IS NOT TRUE OR v_in#>>'{redecide_rows,0,previous,basis}'<>'web_detail'
     OR (v_in#>>'{redecide_rows,0,principal_person_id}')::bigint<>-5342 THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: v3-input %',v_in;
  END IF;
  e:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',v_clause,'clause_set_seq',1,
    'clause_set_sha256',private.clause_set_sha256((SELECT parent_observation_id FROM private.source_observation WHERE id=v_clause),1),
    'death_raw',NULL,'interpretation_key',c->>'key','interpretation_version',1,'marriage_ordinal',1,
    'name_from',14,'name_to',30,'post_offset',(SELECT post_char_from FROM private.source_observation WHERE id=v_clause),
    'predicate','relation.marriage','profile','relation-persona-2018-20-v3','span_from',0,'span_to',30);
  BEGIN   -- v3 uden proveniensnøgler afvises
    PERFORM pg_temp.f5b_write(-5341,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
    RAISE EXCEPTION 'V3_TEST_FAILED: v3 uden name_basis godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_INVALID%' THEN RAISE; END IF; END;
  BEGIN   -- ukendt name_basis afvises
    PERFORM pg_temp.f5b_write(-5341,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),
      e||'{"name_basis":"model","sheet_line":1}'||jsonb_build_object('sheet_sha256',repeat('b',64))));
    RAISE EXCEPTION 'V3_TEST_FAILED: name_basis model godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_INVALID%' THEN RAISE; END IF; END;
  e:=e||'{"name_basis":"sheet","sheet_line":1}'||jsonb_build_object('sheet_sha256',repeat('b',64));
  PERFORM pg_temp.f5b_write(-5341,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
  SELECT payload INTO v_ev FROM private.reimport_event WHERE element_id='relation-persona:'||(c->>'key');
  IF v_ev->>'sheet_sha256'<>repeat('b',64) OR v_ev->>'name_basis'<>'sheet' OR (v_ev->>'sheet_line')::int<>1 THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: proveniens i hændelsen %',v_ev;
  END IF;
  IF (SELECT sm.verbatim_text FROM private.interpretation_party_current pc
        JOIN private.source_persona_mention spm ON spm.persona_id=pc.source_persona_id AND spm.mention_role='spouse'
        JOIN private.source_mention sm ON sm.id=spm.mention_id
       WHERE pc.interpretation_key=(c->>'key')::uuid AND pc.party_role='spouse') IS DISTINCT FROM 'Ida komtesse Dal' THEN
    RAISE EXCEPTION 'V3_TEST_FAILED: ægtefælle-mention';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: relation_persona v3 (proveniens, afvisninger, v3-input)';
END $v3_writer$;
ROLLBACK;
```

If `reimport_event` stores the payload under another column name, or `f5b_spouse` takes the claim as `jsonb` from `f5b_claim`, use what the fixture defines. Read `tests/sql/fixtures/relation-5b.sql` first and record any adaptation as a ruling.

`tests/sql/test-relation-person-create-v3.sql`: copy the helper header (`pg_temp.f2bii_npn`, `f2bii_run`, `f2bii_counts`, `f2bii_delta`) verbatim from `tests/sql/test-relation-person-create.sql:1-37`, then add three blocks:

```sql
-- titelord i navnet ⇒ afvist, 0 delta
DO $v3_title_reject$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3b1'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; n0 jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-5351,false,false,'5b');
  s:=pg_temp.f5b_source(-5351);
  p:=pg_temp.f5b_post(-5351,s,'II-51','Anna Alfa. Gift 1890 med Ida komtesse Dal.',ARRAY['Anna Alfa.','Gift 1890 med Ida komtesse Dal.'],-5351,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5351,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Ida komtesse Dal.');
  sp:=pg_temp.f5b_spouse(-5351,s,p,c,(p->'clauses'->>1)::uuid,'Ida komtesse Dal',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5351);
  n0:=pg_temp.f2bii_counts();
  BEGIN
    PERFORM pg_temp.f2bii_run(-5351,v_actor,m);
    RAISE EXCEPTION 'RPC3_TEST_FAILED: titel godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_NAME_TITLE%' THEN RAISE; END IF; END;
  IF pg_temp.f2bii_delta(n0,pg_temp.f2bii_counts())<>'{"person":0,"family":0,"fm":0,"fact":0,"assertion":0,"citation":0,"conclusion":0}'::jsonb THEN
    RAISE EXCEPTION 'RPC3_TEST_FAILED: delta ved titel';
  END IF;
  RAISE NOTICE 'OK: titelord afvist';
END $v3_title_reject$;

-- afløst klausul ⇒ afvist
DO $v3_clause_stale$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3b1'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; v_clause uuid;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5352,false,false,'5b');
  s:=pg_temp.f5b_source(-5352);
  p:=pg_temp.f5b_post(-5352,s,'II-52','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5352,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  v_clause:=(p->'clauses'->>1)::uuid;
  c:=pg_temp.f5b_claim(-5352,s,'relation.marriage',v_clause,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5352,s,p,c,v_clause,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5352);
  -- et nyere klausulsæt for samme post gør klausulen ikke-aktuel
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
      quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,
      clause_classification,clause_flags,clause_set_seq)
    SELECT occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,quality_status,extraction_method,
           extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,clause_classification,clause_flags,2
      FROM private.source_observation WHERE parent_observation_id=(SELECT parent_observation_id FROM private.source_observation WHERE id=v_clause)
       AND observation_kind='clause';
  BEGIN
    PERFORM pg_temp.f2bii_run(-5352,v_actor,m);
    RAISE EXCEPTION 'RPC3_TEST_FAILED: afløst klausul godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_CLAUSE_STALE%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK: afløst klausul afvist';
END $v3_clause_stale$;

-- afløst fortolkning ⇒ afvist
DO $v3_interp_stale$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000005b3b1'; s jsonb; p jsonb; c jsonb; sp uuid; m jsonb; v_cur private.interpretation%ROWTYPE;
BEGIN
  INSERT INTO person(id,levende,privat,status) VALUES (-5353,false,false,'5b');
  s:=pg_temp.f5b_source(-5353);
  p:=pg_temp.f5b_post(-5353,s,'II-53','Anna Alfa. Gift 1890 med Bo Beta.',ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.'],-5353,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-5353,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp:=pg_temp.f5b_spouse(-5353,s,p,c,(p->'clauses'->>1)::uuid,'Bo Beta',1);
  PERFORM pg_temp.f2bii_npn(v_actor,sp,ARRAY[1890]);
  m:=private.relation_person_create_input(-5353);
  SELECT * INTO v_cur FROM private.interpretation_current WHERE interpretation_key=(c->>'key')::uuid;
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
      value,schema_version,derivation_kind,confidence,status,method,extraction_run_id,supersedes_id)
    VALUES (gen_random_uuid(),v_cur.interpretation_key,v_cur.version+1,v_cur.source_id,v_cur.source_persona_id,
      v_cur.interpretation_kind,v_cur.predicate,v_cur.value,v_cur.schema_version,v_cur.derivation_kind,v_cur.confidence,
      'superseded',v_cur.method,v_cur.extraction_run_id,v_cur.id);
  BEGIN
    PERFORM pg_temp.f2bii_run(-5353,v_actor,m);
    RAISE EXCEPTION 'RPC3_TEST_FAILED: afløst fortolkning godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSON_CREATE_INTERPRETATION_STALE%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK: afløst fortolkning afvist';
END $v3_interp_stale$;
ROLLBACK;
```

If a trigger rejects the hand-inserted clause set or interpretation version, produce the same state through the existing path the trigger points to: the clause-revision helper in `tests/sql/test-clause-revision.sql`, or the interpretation decision RPC. Record it as a ruling. The assertion (error code, 0 writes) is fixed.

- [ ] **Step 2: Run them to verify they fail.** Build a writer DB with the scratchpad `mkdb.sh ci5b_v3_t3 writer` (bootstrap + schema + rls + `1939-v50-writer-bootstrap` + `BEGIN`/`reimport-writer-v2-bootstrap`/`COMMIT` + rls), then `env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d ci5b_v3_t3 -f tests/sql/test-relation-persona-v3.sql`.
  Expected: FAIL with `function private.relation_name_has_title(unknown) does not exist`. Then `test-relation-person-create-v3.sql` is expected to FAIL on the missing title check (`RPC3_TEST_FAILED: titel godtaget`).

- [ ] **Step 3: Implement in `schema.sql`.**

(a) Add the title functions next to `private.relation_ordered_windows` (`schema.sql` ~16801):

```sql
-- Trin 5b 2b-ii runde 2 (spec §17.5): lukket titelliste = Python-tvillingen TITLE_WORDS (test_title_words_match_schema).
CREATE OR REPLACE FUNCTION private.relation_title_words()
RETURNS text[] LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT ARRAY['baron','baronesse','friherre','friherreinde','greve','grevinde','hertug','hertuginde','komtesse','prins','prinsesse']::text[]
$$;
REVOKE ALL ON FUNCTION private.relation_title_words() FROM PUBLIC,anon,authenticated,service_role;
-- Titelordene er ASCII, så lower() under C-lc_ctype rækker; ikke-ASCII versaler bliver blot skilletegn.
CREATE OR REPLACE FUNCTION private.relation_name_has_title(p_name text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,private AS $$
  SELECT EXISTS (SELECT 1 FROM regexp_split_to_table(lower(coalesce(p_name,'')),'[^0-9a-zà-öø-ÿ]+') w
                  WHERE w<>'' AND (w=ANY(private.relation_title_words())
                        OR (w ~ '^(rigs|lens)' AND substr(w,5)=ANY(private.relation_title_words()))))
$$;
REVOKE ALL ON FUNCTION private.relation_name_has_title(text) FROM PUBLIC,anon,authenticated,service_role;
```

(b) `private.write_relation_persona` (`schema.sql:14972`): replace the key-set and profile lines in the validation `IF` with:

```sql
     OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(p_payload) k)
        <> (SELECT array_agg(k ORDER BY k COLLATE "C") FROM unnest(
             ARRAY['birth_raw','clause_observation_id','clause_set_seq','clause_set_sha256','death_raw','interpretation_key',
                   'interpretation_version','marriage_ordinal','name_from','name_to','post_offset','predicate','profile',
                   'span_from','span_to']
             || CASE WHEN p_payload->>'profile'='relation-persona-2018-20-v3'
                     THEN ARRAY['name_basis','sheet_line','sheet_sha256'] ELSE '{}'::text[] END) k)
     OR p_element_id<>'relation-persona:'||coalesce(p_payload->>'interpretation_key','')
     OR coalesce(p_payload->>'predicate','') NOT IN ('relation.marriage','relation.child','relation.parent')
     OR coalesce(p_payload->>'profile','') NOT IN ('relation-persona-2018-20-v1','relation-persona-2018-20-v2',
                                                   'relation-persona-2018-20-v3')
     -- v3 (2b-ii runde 2, spec §17.7): arkets proveniens; kun ægteskaber
     OR (p_payload->>'profile'='relation-persona-2018-20-v3' AND (
           NOT v_marriage OR coalesce(p_payload->>'name_basis','') NOT IN ('rule','sheet')
           OR coalesce(p_payload->>'sheet_sha256','') !~ '^[0-9a-f]{64}$'
           OR jsonb_typeof(p_payload->'sheet_line')<>'number' OR (p_payload->>'sheet_line') !~ '^[1-9][0-9]*$'))
```

The span check's `ELSE` branch (the v2 window) already covers v3. Change the comment to `-- v2/v3 (…): det eneste minimale ordnede ordvindue.`

(c) `private.write_relation_person_create` (`schema.sql:16488`): directly after `IF v_name IS DISTINCT FROM p_payload->>'name_text' THEN … END IF;` insert:

```sql
  -- 2b-ii runde 2 (spec §17.5/§17.7): titel ≠ navn; kun aktuel klausul og ikke-afløst fortolkning.
  IF private.relation_name_has_title(v_name) THEN RAISE EXCEPTION 'RELATION_PERSON_CREATE_NAME_TITLE'; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.clause_observation_current c WHERE c.id=v_obs) THEN
    RAISE EXCEPTION 'RELATION_PERSON_CREATE_CLAUSE_STALE';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_party_current sp
                   JOIN private.interpretation_current ic ON ic.interpretation_key=sp.interpretation_key
                  WHERE sp.source_persona_id=v_sp AND sp.party_role='spouse' AND ic.status IN ('proposed','accepted')) THEN
    RAISE EXCEPTION 'RELATION_PERSON_CREATE_INTERPRETATION_STALE';
  END IF;
```

(d) After `public.red_relation_persona_v2_input` (`schema.sql` ~16867), add the v3 projection:

```sql
-- Trin 5b 2b-ii runde 2 (spec §17.6): rækkefil til ark v3 — v2-rækkerne med hele posten, plus P-rækkerne
-- (new_person_needed uden deceased). Privat og læsende; navne og tekst forlader kun via redaktionens RPC.
CREATE OR REPLACE FUNCTION private.relation_persona_v3_input(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v2 jsonb; v_rows jsonb; v_re jsonb;
BEGIN
  IF p_source_id IS NULL THEN RAISE EXCEPTION 'RELATION_PERSONA_V3_INPUT_INVALID'; END IF;
  v2:=private.relation_persona_v2_input(p_source_id);
  SELECT coalesce(jsonb_agg(t.r || jsonb_build_object('post_text',(
           SELECT po.verbatim_text FROM private.source_observation co
             JOIN private.source_observation po ON po.id=co.parent_observation_id
            WHERE co.id=(t.r#>>'{clauses,0,observation_id}')::uuid)) ORDER BY t.n),'[]'::jsonb)
    INTO v_rows FROM jsonb_array_elements(v2->'rows') WITH ORDINALITY AS t(r,n);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'source_persona_id',i.source_persona_id::text,'identity_version',i.version,
      'previous',jsonb_build_object('basis',i.evidence->>'basis','note',i.evidence->>'note',
                                    'decided_at',to_char(i.decided_at AT TIME ZONE 'UTC','YYYY-MM-DD')),
      'name_text',sm.verbatim_text,'clause_observation_id',o.id::text,'clause_text',o.verbatim_text,
      'clause_is_current',EXISTS (SELECT 1 FROM private.clause_observation_current cc WHERE cc.id=o.id),
      'post_text',po.verbatim_text,'record_key',sr.record_key,'page_from',o.page_from,
      'marriage_ordinal',spp.marriage_ordinal,'principal_person_id',pi.canonical_person_id,
      'principal_partners',coalesce((
          SELECT jsonb_agg(jsonb_build_object('person_id',x.person_id,'family_id',x.family_id,'ordinal',x.ordinal,
                   'navn',coalesce(pp.visning_fuldt_navn,pp.visning_navn),'foedt',pp.visning_foedt,'doed',pp.visning_doed)
                 ORDER BY x.person_id,x.family_id)
            FROM public.family_member me JOIN public.family_member x ON x.family_id=me.family_id AND x.rolle='partner'
                 AND x.person_id<>me.person_id JOIN public.person pp ON pp.id=x.person_id
           WHERE me.person_id=pi.canonical_person_id AND me.rolle='partner'),'[]'::jsonb))
     ORDER BY i.source_persona_id::text COLLATE "C"),'[]'::jsonb)
    INTO v_re
    FROM private.source_persona_identity i
    JOIN private.source_persona p ON p.id=i.source_persona_id AND p.source_id=p_source_id
    JOIN private.source_persona_mention spm ON spm.persona_id=i.source_persona_id AND spm.mention_role='spouse'
    JOIN private.source_mention sm ON sm.id=spm.mention_id
    JOIN private.source_observation o ON o.id=sm.observation_id
    LEFT JOIN private.source_observation po ON po.id=o.parent_observation_id
    LEFT JOIN private.interpretation_party_current spp ON spp.source_persona_id=i.source_persona_id AND spp.party_role='spouse'
    LEFT JOIN private.interpretation_party_current pr ON pr.interpretation_key=spp.interpretation_key AND pr.party_role='principal'
    LEFT JOIN private.source_persona_identity pi ON pi.source_persona_id=pr.source_persona_id AND pi.decision_status='accepted'
    LEFT JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
    LEFT JOIN private.source_record sr ON sr.id=ac.source_record_id
   WHERE i.decision_status='unresolved' AND i.evidence->>'reason'='new_person_needed' AND NOT (i.evidence ? 'deceased');
  RETURN jsonb_build_object('contract','relation-persona-v3-input','source_id',p_source_id,
                            'deceased_cutoff_year',1906,'rows',v_rows,'redecide_rows',v_re);
END $$;
REVOKE ALL ON FUNCTION private.relation_persona_v3_input(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.red_relation_persona_v3_input(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  RETURN private.relation_persona_v3_input(p_source_id);
END $$;
REVOKE ALL ON FUNCTION public.red_relation_persona_v3_input(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_relation_persona_v3_input(bigint) TO authenticated;
```

Spec §17.6 allowed reusing the queue RPCs, but `red_source_persona_detail` carries neither the clause text, the previous decision's evidence, the marriage ordinal nor the principal. Record this as a ruling: »ny læsefunktion, fordi kø-RPC'erne mangler klausul, tidligere evidens, nummer og hovedperson«.

- [ ] **Step 4: Mirror in `db-migrations.sql`.** Above the line `-- 5b-sektionen slutter her …`, add four blocks headed `-- Trin 5b 2b-ii runde 2 (#151, spec §17.x): …`:
  1. the two title functions, verbatim;
  2. the **complete** new `private.write_relation_persona`, copied from `schema.sql` after edit (b) (the comment says »Kopi med ændringer«, as the 2b-ii block did);
  3. the **complete** new `private.write_relation_person_create`, copied after edit (c), including its `REVOKE` line;
  4. `relation_persona_v3_input` and its `red_` wrapper, verbatim.

- [ ] **Step 5: ACL lists and verify.**
  - In `db-rls.sql:702` and `db-verify.sql:2980`, add `'public.red_relation_persona_v3_input(bigint)'` (with `::regprocedure` in db-verify) on the line after the v2 entry.
  - Also the older ACL list in `db-migrations.sql` (around line 18826, `to_regprocedure('public.red_relation_persona_v2_input(bigint)')`): add `to_regprocedure('public.red_relation_persona_v3_input(bigint)'),` after the v2 line. 2b-ii added v2 there, and v3 follows that precedent.
  - After `$verify_family_id$` (`db-verify.sql:10248`), add:

```sql
-- Trin 5b 2b-ii runde 2 (spec §17.7): profil v3 og titellisten.
DO $verify_relation_v3$
BEGIN
  IF to_regprocedure('private.relation_title_words()') IS NULL OR to_regprocedure('private.relation_name_has_title(text)') IS NULL
     OR NOT private.relation_name_has_title('Ida komtesse Dal') OR private.relation_name_has_title('Eva von Fik') THEN
    RAISE EXCEPTION 'VERIFY_RELATION_TITLE_WORDS';
  END IF;
  IF position('relation-persona-2018-20-v3' IN pg_get_functiondef('private.write_relation_persona(uuid,text,jsonb)'::regprocedure))=0
     OR position('RELATION_PERSON_CREATE_NAME_TITLE' IN pg_get_functiondef('private.write_relation_person_create(uuid,text,jsonb)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'VERIFY_RELATION_V3_WRITERS';
  END IF;
  RAISE NOTICE 'OK: 5b 2b-ii runde 2 — titelliste og writer v3';
END $verify_relation_v3$;
```

- [ ] **Step 6: Run to verify they pass.**
  - Rebuild `ci5b_v3_t3` from the edited `schema.sql`.
  - Run both new SQL tests, then the 2b-ii SQL tests (`test-relation-persona-v2.sql`, `test-relation-person-create.sql`, `test-relation-disposition.sql`), then `db-verify.sql`.
  - Remove the xfail mark from `test_title_words_match_schema` and run `$PY -m pytest test_relation_persona_extract_v3.py test_identity_guard_static.py -q`.
  - Expected: every `RAISE NOTICE 'OK: …'` is printed, no ERROR, and pytest is all green.
  - Then the migration path: `ci5b_v3_t3m` = a fresh DB from **origin/main**'s `schema.sql`/`db-rls.sql` plus the writer bootstraps, then HEAD's `db-migrations.sql` twice, `db-rls.sql`, and both new SQL tests. Expected: green.

- [ ] **Step 7: Commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-relation-persona-v3.sql tests/sql/test-relation-person-create-v3.sql .claude/skills/daa-extract/scripts/test_relation_persona_extract_v3.py .claude/skills/daa-extract/scripts/test_identity_guard_static.py
git commit -m "feat(151): relation_persona profil v3, titelværn i relation_person_create og v3-rækkefil (2b-ii runde 2)"
```

---

### Task 4: Ark v3 (render/sql, `navn:`, P-linjer) og ende til ende

**Files:**
- Create: `.claude/skills/daa-extract/scripts/relation_marriage_sheet_v3.py`, `.claude/skills/daa-extract/scripts/test_relation_marriage_sheet_v3.py`, `.claude/skills/daa-extract/scripts/relation_v3_rows.sql`, `tests/sql/fixtures/relation-marriage-v3.sql`, `tests/sql/test-relation-marriage-sheet-v3.sh`.

**Interfaces:**
- Consumes:
  - `v3.propose`, `v3.propose_redecide`, `v3.PROFILE`, `v3.RULE`, `v3.NameOverrideError` (Task 1);
  - `public.red_relation_persona_v3_input` (Task 3);
  - `decision_sheet_core.SheetError, require_hex64, sql_literal, verify_bound`;
  - `spouse_exception_sheet._write_private, check_private_path`;
  - `relation_marriage_sheet._ws`.
- Produces:
  - CLI `relation_marriage_sheet_v3.py render --rows R --out A [--private-root P]`, which prints `ARK_OK s= d= n= i= u= p_d= p_n= p_u=`;
  - CLI `relation_marriage_sheet_v3.py sql --rows R --sheet A --approved-sha256 H --expect-rows-sha256 H --manifest-out M --identity-out I`, which prints `SQL_OK manifest=<n> identitet=<n>`;
  - the persona manifest (`relation_persona_apply.sql`-compatible, profile v3);
  - the identity script (psql; `:'actor'`).

- [ ] **Step 1: Write the failing tests** (`test_relation_marriage_sheet_v3.py`):

```python
"""Trin 5b 2b-ii runde 2 (spec §17.6): ark v3. Kun opdigtede navne."""
import json

import pytest

import relation_marriage_sheet_v3 as sh
from decision_sheet_core import SheetError

K1, K2 = "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"
SP = "33333333-3333-3333-3333-333333333333"


def mrow(key, text, raw, partners=(), ordinal=1):
    return {"interpretation_key": key, "interpretation_version": 1, "predicate": "relation.marriage", "raw": raw,
            "record_key": "II-1", "marriage_ordinal": ordinal, "supporting_count": 1, "principal_ok": True,
            "principal_person_id": 5, "principal_partners": list(partners), "post_text": "Anna A. " + text,
            "clauses": [{"observation_id": "44444444-4444-4444-4444-444444444444", "clause_set_seq": 1,
                         "clause_set_sha256": "a" * 64, "verbatim_text": text, "post_char_from": 8, "post_char_to": 8 + len(text)}]}


def rows():
    return {"contract": "relation-persona-v3-input", "source_id": 1, "deceased_cutoff_year": 1906,
            "rows": [mrow(K1, "Gift 1890 med Ida komtesse Dal til Ørum.", "Gift med Ida komtesse Dal til Ørum",
                          [{"person_id": 7, "family_id": 3, "ordinal": 2, "navn": "Ida Dal"}]),
                     mrow(K2, "Gift 1890 med Ole Dal, datter af Ole Dal.", "Gift med Ole Dal, datter af Ole Dal")],
            "redecide_rows": [{"source_persona_id": SP, "identity_version": 1,
                               "previous": {"basis": "web_detail", "note": "kø", "decided_at": "2026-10-13"},
                               "name_text": "Gro von Hak", "clause_text": "Gift 1314 med Gro von Hak.",
                               "clause_is_current": True, "post_text": "Carl C. Gift 1314 med Gro von Hak.",
                               "record_key": "II-9", "page_from": 9, "marriage_ordinal": 1, "principal_person_id": 6,
                               "principal_partners": []}]}


def sheet(m1="S", m2="D", p="D", extra1=""):
    return (f"# ark\nM {K1} 1 : {m1}{extra1}\nM {K2} 1 : {m2}\nP {SP} 1 : {p}\n")


def test_render_viser_skaevt_nummer_hele_posten_og_P():
    out = sh.render_sheet(rows())
    assert "nr. i bogen 1 ≠ nr. i familien 2" in out
    assert "Hele posten:" in out and "Tidligere afgørelse: web_detail, 2026-10-13" in out
    assert f"P {SP} 1 : D" in out


def test_navnerettelse_giver_sheet_basis_og_hash_i_manifest():
    lines = sh.parse_sheet(sheet(extra1=" navn: »Ida komtesse Dal«"))
    m = sh.persona_manifest(lines, rows(), sheet_sha256="c" * 64)
    e = m["authorized_elements"]["relation-persona:" + K1]
    assert e["profile"] == "relation-persona-2018-20-v3" and e["name_basis"] == "sheet"
    assert e["sheet_sha256"] == "c" * 64 and e["sheet_line"] == 1
    assert m["authorized_elements"]["relation-persona:" + K2]["name_basis"] == "rule"


def test_navn_to_gange_afvises():
    # K2's klausul rummer »Ole Dal« to gange (rækken er uændret, så vinduet findes og navnestarten nås)
    r = rows()
    assert sh.propose(r["rows"][1], 1906)["tok"] == "D"
    with pytest.raises(SheetError, match="SHEET_NAME_INVALID"):
        sh.check_sheet(sh.parse_sheet(sheet(m2="D").replace(f"M {K2} 1 : D", f"M {K2} 1 : D navn: »Ole Dal«")), r)


def test_navn_ved_I_eller_U_afvises():
    with pytest.raises(SheetError, match="SHEET_NAME_INVALID"):
        sh.check_sheet(sh.parse_sheet(sheet(m1="U", extra1=" navn: »Ida Dal«")), rows())


def test_U_til_S_kun_naar_reglen_bekraefter():
    # K2 har ingen partner ⇒ S er ikke tilladt, heller ikke med rettet navn
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.check_sheet(sh.parse_sheet(sheet(m2="S")), rows())


def test_S_til_N_er_ikke_tilladt():
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.check_sheet(sh.parse_sheet(sheet(m1="N")), rows())


def test_P_D_kun_naar_reglen_siger_D():
    r = rows()
    r["redecide_rows"][0]["clause_text"] = "Gift 1950 med Gro von Hak."
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        sh.check_sheet(sh.parse_sheet(sheet()), r)


def test_P_version_skal_passe():
    with pytest.raises(SheetError, match="SHEET_IDENTITY_MISMATCH"):
        sh.check_sheet(sh.parse_sheet(sheet().replace(f"P {SP} 1", f"P {SP} 2")), rows())


def test_identitetsscript_P_bruger_raekkefilens_version_og_deceased():
    lines = sh.parse_sheet(sheet())
    sql = sh.identity_sql(lines, rows(), sheet_sha256="c" * 64, rows_sha256="d" * 64)
    assert f"red_afgoer_source_persona('{SP}'::uuid, 1, 'new_person_needed', NULL," in sql
    assert '"clause_years": [1314]' in sql and '"rule": "aarstal-120-v1"' in sql and "erstatter version 1" in sql
    assert sql.count("red_afgoer_source_persona(") == 3


def test_P_N_skriver_intet():
    sql = sh.identity_sql(sh.parse_sheet(sheet(p="N")), rows(), sheet_sha256="c" * 64, rows_sha256="d" * 64)
    assert SP not in sql
```

- [ ] **Step 2: Run to verify they fail.** Run `$PY -m pytest test_relation_marriage_sheet_v3.py -q`. Expected: `ModuleNotFoundError`.

- [ ] **Step 3: Implement `relation_marriage_sheet_v3.py`.**

```python
"""Trin 5b 2b-ii runde 2 (spec §17.6): ægteskabsark v3 — M-linjer med navnerettelse, P-linjer til genafgørelse.

Arket og rækkefilen rummer navne og bogens tekst; værktøjet printer kun antal og koder. `sql` laver et
persona-manifest (profil v3, med arkets hash og linje) og ét identitetsscript (M og P i samme transaktion).
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from relation_marriage_sheet import _ws
from relation_persona_extract_v3 import PROFILE, RULE, NameOverrideError, propose, propose_redecide
from spouse_exception_sheet import _write_private, check_private_path

UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
M_RE = re.compile(rf"^M (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>[SDNIU])"
                  rf"(?:\s+navn:\s*»(?P<navn>[^»«]+)«)?\s*(?:#\s*(?P<note>.*))?$")
P_RE = re.compile(rf"^P (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>[DNU])\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^[MP] {UUID} ")
# S kan ikke blive N (D/N kræver nul partnertræf, spec §17.4); U løftes kun via genberegning på rettet navn.
ALLOWED = {"S": {"S", "I", "U"}, "D": {"D", "N", "I", "U"}, "N": {"N", "I", "U"}, "I": {"I", "U"}, "U": {"I", "U"}}
ALLOWED_P = {"D": {"D", "N", "U"}, "N": {"N", "U"}, "U": {"N", "U"}}


@dataclass(frozen=True)
class Line:
    kind: str
    key: str
    version: int
    tok: str
    navn: str | None
    note: str
    line: int


def _cutoff(rows: dict) -> int:
    return int(rows["deceased_cutoff_year"])


def render_sheet(rows: dict) -> str:
    cutoff = _cutoff(rows)
    out = ["# ÆGTESKABSARK v3 (trin 5b 2b-ii runde 2)",
           "# S = samme som forslagets partner · D = ny person, afdød efter bogen (alle årstal senest grænseåret)",
           "# N = ny person, kan ikke erklæres afdød (oprettes ikke nu) · I = intet navn i bogen · U = uafklaret",
           "# Er navnet forkert afsluttet, så skriv efter svaret:  navn: »navnet præcis som i bogen«",
           "#   (det skal begynde, hvor forslaget begynder). D/N kræver et navn uden titel.",
           "# P-linjer: D = opret den afdøde ægtefælle (ny afgørelse med dødsoplysning) · N/U = lad stå.",
           "# Ret kun undtagelser. En note må følge efter '#'. Gem, og giv hashen i chatten.", ""]
    n = len(rows["rows"])
    for i, r in enumerate(rows["rows"], 1):
        p = propose(r, cutoff)
        text = r["clauses"][0]["verbatim_text"] if r["clauses"] else ""
        out += [f"## ÆGTESKAB {i}/{n} · post {r.get('record_key') or '?'}", f"#   Bogen: »{_ws(text)}«"]
        if "name_from" in p:
            out.append(f"#   Ægtefællens navn: »{_ws(text[p['name_from']:p['name_to']])}«")
        partners = "; ".join(f"{_ws(x.get('navn')) or '(intet navn)'} ({x.get('foedt') or '?'}–{x.get('doed') or '?'})"
                             f" · familie {x.get('family_id')} · nr. {x.get('ordinal') if x.get('ordinal') is not None else '?'}"
                             for x in r.get("principal_partners", []))
        out.append(f"#   Hovedpersonens partnere: {partners or '(ingen)'}")
        if p["tok"] == "S" and p.get("partner_ordinal") is not None and p["partner_ordinal"] != r["marriage_ordinal"]:
            out.append(f"#   OBS: nr. i bogen {r['marriage_ordinal']} ≠ nr. i familien {p['partner_ordinal']} — bekræft bevidst")
        if "clause_years" in p:
            out.append(f"#   Årstal i klausulen: {', '.join(map(str, p['clause_years'])) or '(ingen)'} · grænse {cutoff}")
        if p["tok"] == "D":
            out += [f"#   Hele posten: »{_ws(r.get('post_text'))}«",
                    "#   Gælder et senere årstal i posten ægtefællen? Så svar N."]
        out += [f"#   Forslag: {p['tok']} ({p['reason']})",
                f"M {r['interpretation_key']} {r['interpretation_version']} : {p['tok']}", ""]
    for j, q in enumerate(rows.get("redecide_rows", []), 1):
        p = propose_redecide(q, cutoff)
        prev = q.get("previous") or {}
        out += [f"## GENAFGØRELSE {j} · post {q.get('record_key') or '?'}, s. {q.get('page_from') or '?'}",
                f"#   Tidligere afgørelse: {prev.get('basis')}, {prev.get('decided_at')} · note: »{_ws(prev.get('note'))}«",
                f"#   Ægtefællens navn: »{_ws(q.get('name_text'))}«",
                f"#   Klausulen: »{_ws(q.get('clause_text'))}«",
                f"#   Hele posten: »{_ws(q.get('post_text'))}«",
                f"#   Årstal i klausulen: {', '.join(map(str, p.get('clause_years', []))) or '(ingen)'} · grænse {cutoff}",
                "#   Gælder et senere årstal i posten ægtefællen? Så svar N.",
                f"#   Forslag: {p['tok']} ({p['reason']})",
                f"P {q['source_persona_id']} {q['identity_version']} : {p['tok']}", ""]
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines: list[Line] = []
    for raw in text.splitlines():
        if not raw.strip() or raw.startswith("#"):
            continue
        m = M_RE.match(raw) or P_RE.match(raw)
        if not m:
            raise SheetError("SHEET_LINE_INVALID" if LOOSE_RE.match(raw) else "SHEET_LINE_UNKNOWN")
        navn = m.groupdict().get("navn")
        lines.append(Line(raw[0], m["key"], int(m["ver"]), m["tok"], navn, (m["note"] or "").strip(), len(lines) + 1))
    return lines


def check_sheet(lines: list[Line], rows: dict) -> tuple[list[dict], list[dict]]:
    cutoff = _cutoff(rows)
    m_lines = [l for l in lines if l.kind == "M"]
    p_lines = [l for l in lines if l.kind == "P"]
    exp_m = [(r["interpretation_key"], int(r["interpretation_version"])) for r in rows["rows"]]
    exp_p = [(q["source_persona_id"], int(q["identity_version"])) for q in rows.get("redecide_rows", [])]
    if (not lines or [l.kind for l in lines] != ["M"] * len(m_lines) + ["P"] * len(p_lines)
            or [(l.key, l.version) for l in m_lines] != exp_m or [(l.key, l.version) for l in p_lines] != exp_p):
        raise SheetError("SHEET_IDENTITY_MISMATCH")
    m_props = []
    for l, r in zip(m_lines, rows["rows"]):
        if l.navn is not None and l.tok not in ("S", "D", "N"):
            raise SheetError(f"SHEET_NAME_INVALID line={l.line}")
        try:
            p = propose(r, cutoff, name_override=l.navn)
        except NameOverrideError:
            raise SheetError(f"SHEET_NAME_INVALID line={l.line}") from None
        if l.tok not in ALLOWED[p["tok"]]:
            raise SheetError(f"SHEET_TOKEN_NOT_ALLOWED line={l.line}")
        m_props.append(p)
    p_props = []
    for l, q in zip(p_lines, rows.get("redecide_rows", [])):
        p = propose_redecide(q, cutoff)
        if l.tok not in ALLOWED_P[p["tok"]]:
            raise SheetError(f"SHEET_TOKEN_NOT_ALLOWED line={l.line}")
        p_props.append(p)
    return m_props, p_props


def persona_manifest(lines: list[Line], rows: dict, *, sheet_sha256: str) -> dict:
    require_hex64(sheet_sha256)
    m_props, _ = check_sheet(lines, rows)
    elements = {}
    for l, r, p in zip([l for l in lines if l.kind == "M"], rows["rows"], m_props):
        if l.tok not in ("S", "D", "N"):
            continue
        c = r["clauses"][0]
        elements["relation-persona:" + r["interpretation_key"]] = {
            "birth_raw": None, "clause_observation_id": c["observation_id"], "clause_set_seq": c["clause_set_seq"],
            "clause_set_sha256": c["clause_set_sha256"], "death_raw": None,
            "interpretation_key": r["interpretation_key"], "interpretation_version": r["interpretation_version"],
            "marriage_ordinal": r["marriage_ordinal"], "name_basis": p["name_basis"], "name_from": p["name_from"],
            "name_to": p["name_to"], "post_offset": c["post_char_from"] + p["span_from"], "predicate": "relation.marriage",
            "profile": PROFILE, "sheet_line": l.line, "sheet_sha256": sheet_sha256,
            "span_from": p["span_from"], "span_to": p["span_to"]}
    return {"expected_counts": {"person_creates": 0, "source_evidence": 0, "relation_personas": len(elements)},
            "authorized_elements": dict(sorted(elements.items()))}


def identity_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    m_props, p_props = check_sheet(lines, rows)
    cutoff = _cutoff(rows)
    m_todo = [(l, p) for l, p in zip([l for l in lines if l.kind == "M"], m_props) if l.tok in ("S", "D", "N")]
    p_todo = [(l, p) for l, p in zip([l for l in lines if l.kind == "P"], p_props) if l.tok == "D"]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;"]
    for l, _ in m_todo:
        sql.append(f"SELECT source_persona_id AS p{l.line} FROM private.interpretation_party_current "
                   f"WHERE interpretation_key='{l.key}' AND party_role='spouse' AND source_persona_id IS NOT NULL \\gset")
    sql += ["SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
            "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256}
    for l, p in m_todo:
        note = sql_literal(f"ark v3 {tag} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        ctx = {**base, "line": l.line}
        if l.tok == "S":
            action, person = "same", str(int(p["partner_person_id"]))
        else:
            action, person = "new_person_needed", "NULL"
            if l.tok == "D":
                ctx["deceased"] = {"rule": RULE, "cutoff_year": cutoff, "clause_years": p["clause_years"]}
        sql.append(f"SELECT red_afgoer_source_persona(:'p{l.line}'::uuid, 0, '{action}', {person}, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    for l, p in p_todo:
        note = sql_literal(f"ark v3 {tag} linje {l.line} — erstatter version {l.version}" + (f" — {l.note}" if l.note else ""))
        ctx = {**base, "line": l.line, "deceased": {"rule": RULE, "cutoff_year": cutoff, "clause_years": p["clause_years"]}}
        sql.append(f"SELECT red_afgoer_source_persona('{l.key}'::uuid, {l.version}, 'new_person_needed', NULL, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--rows", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--out", required=True)
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--manifest-out", "--identity-out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        rows_path = check_private_path(Path(args.rows), root)
        rows_bytes = rows_path.read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        if rows.get("contract") != "relation-persona-v3-input":
            raise SheetError("ROWS_CONTRACT_INVALID")
        if args.cmd == "render":
            out = check_private_path(Path(args.out), root)
            _write_private(out, render_sheet(rows))
            c = {t: 0 for t in "SDNIU"}
            cp = {t: 0 for t in "DNU"}
            for row in rows["rows"]:
                c[propose(row, _cutoff(rows))["tok"]] += 1
            for q in rows.get("redecide_rows", []):
                cp[propose_redecide(q, _cutoff(rows))["tok"]] += 1
            print(f"ARK_OK s={c['S']} d={c['D']} n={c['N']} i={c['I']} u={c['U']} p_d={cp['D']} p_n={cp['N']} p_u={cp['U']}")
            return 0
        mout = check_private_path(Path(args.manifest_out), root)
        iout = check_private_path(Path(args.identity_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        manifest = persona_manifest(lines, rows, sheet_sha256=sheet_sha)
        ident = identity_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
        _write_private(mout, json.dumps(manifest, sort_keys=True, ensure_ascii=False) + "\n")
        _write_private(iout, ident)
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK manifest={len(manifest['authorized_elements'])} identitet={ident.count('red_afgoer_source_persona(')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

`relation_v3_rows.sql` is a copy of `relation_v2_rows.sql` with the header comment changed to v3 and the select changed to `SELECT public.red_relation_persona_v3_input(:source)::text;`.

- [ ] **Step 4: Run to verify they pass.** Run `$PY -m pytest test_relation_marriage_sheet_v3.py test_relation_persona_extract_v3.py test_relation_marriage_sheet.py -q`. Expected: all PASS; v2 sheet tests unchanged.

- [ ] **Step 5: E2E fixture and script.**

`tests/sql/fixtures/relation-marriage-v3.sql` (source −22601): (a) an `S` row whose name holds a lowercase title (the partner exists); (b) a `D` row with a particle chain (principal without partners); (c) a P persona in a third post, decided `new_person_needed` without `deceased` (clause year 1314):

```sql
-- Trin 5b 2b-ii runde 2 Task 4: data til ark v3's ende-til-ende-test (writer-kontrakt 2). Opdigtede navne.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
DO $marriage_v3_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0611'; s jsonb; p jsonb; c jsonb; sp uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn) VALUES
    (-22601,false,false,'v3','Anna A'),(-22602,false,false,'v3','Bent B'),(-22603,false,false,'v3','Carl C'),
    (-22611,false,false,'v3','Ida Dal');
  s:=pg_temp.f5b_source(-22601);
  p:=pg_temp.f5b_post(-22601,s,'F-1','Anna A. Gift 1890 med Ida komtesse Dal, f. 1801.',
       ARRAY['Anna A.','Gift 1890 med Ida komtesse Dal, f. 1801.'],-22601,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22601,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Ida komtesse Dal');
  PERFORM pg_temp.f5b_family(-22601,-22611,1);
  p:=pg_temp.f5b_post(-22601,s,'F-2','Bent B. Gift 1890 med Eva von und zu Fik.',
       ARRAY['Bent B.','Gift 1890 med Eva von und zu Fik.'],-22602,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f5b_claim(-22601,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift med Eva von und zu Fik');
  p:=pg_temp.f5b_post(-22601,s,'F-3','Carl C. Gift 1314 med Gro von Hak.',ARRAY['Carl C.','Gift 1314 med Gro von Hak.'],-22603,v_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-22601,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1314 med Gro von Hak.');
  sp:=pg_temp.f5b_spouse(-22601,s,p,c,(p->'clauses'->>1)::uuid,'Gro von Hak',1);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(sp,0,'new_person_needed',NULL,'kø',NULL);
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE;
END $marriage_v3_fixture$;
COMMIT;
```

`tests/sql/test-relation-marriage-sheet-v3.sh`: mirror `tests/sql/test-relation-marriage-sheet.sh` with these differences:
- actor `…2b0611`, source `-22601`;
- `relation_v3_rows.sql`;
- expected render `ARK_OK s=1 d=1 n=0 i=0 u=0 p_d=1 p_n=0 p_u=0`;
- expected sql `SQL_OK manifest=2 identitet=3`.

Then the assertions, as `q -At <<SQL | grep -qx 't'` blocks:

```sql
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-22601 AND i.decision_status='accepted' AND i.canonical_person_id=-22611
           AND i.evidence->>'sheet_sha256'='$ark_sha')=1
   AND (SELECT count(*) FROM private.reimport_event WHERE element_id LIKE 'relation-persona:%'
         AND payload->>'sheet_sha256'='$ark_sha' AND payload->>'profile'='relation-persona-2018-20-v3')=2
   AND (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
         WHERE p.source_id=-22601 AND i.decision_status='unresolved' AND i.version=2
           AND i.evidence#>'{deceased,clause_years}'='[1314]'::jsonb AND i.evidence->>'sheet_sha256'='$ark_sha')=1;
```

After `relation_person_create` (from `private.relation_person_create_input(-22601)`, expecting 2 elements):

```sql
SELECT (SELECT count(*) FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id
          JOIN public.person pp ON pp.id=i.canonical_person_id
         WHERE p.source_id=-22601 AND i.decision_status='accepted' AND i.evidence->>'method'='relation-person-create-v1'
           AND pp.staged AND NOT pp.levende AND pp.visning_navn IN ('Eva von und zu Fik','Gro von Hak'))=2;
```

Then rerun the identity script ⇒ `EVIDENCE_IDENTITY_VERSION_CONFLICT`, 0 new identity events. That rerun stops at the first `M` line, so the P-line's lock is tested on its own as well: call `red_afgoer_source_persona(<P persona>, 1, 'new_person_needed', NULL, 'x', <deceased-kontekst>)` alone (as `authenticated` with the actor) ⇒ `EVIDENCE_IDENTITY_VERSION_CONFLICT` (the identity is now version 2 or later), 0 new identity events. Finish with `echo MARRIAGE_SHEET_V3_E2E_OK`.

- [ ] **Step 6: Run the e2e.** Build `ci5b_v3_sheet` like CI's `ci5b_2bii_sheet` (`.github/workflows/ci.yml:495-500`), then run `bash tests/sql/test-relation-marriage-sheet-v3.sh ci5b_v3_sheet`. Expected: `MARRIAGE_SHEET_V3_E2E_OK`. Also run `bash tests/sql/test-relation-marriage-sheet.sh` in a fresh DB, which is expected to give `MARRIAGE_SHEET_E2E_OK` (v2 unchanged).

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/daa-extract/scripts/relation_marriage_sheet_v3.py .claude/skills/daa-extract/scripts/test_relation_marriage_sheet_v3.py .claude/skills/daa-extract/scripts/relation_v3_rows.sql tests/sql/fixtures/relation-marriage-v3.sql tests/sql/test-relation-marriage-sheet-v3.sh
git commit -m "feat(151): ægteskabsark v3 med navnerettelse og P-linjer til genafgørelse (2b-ii runde 2)"
```

---

### Task 5: CI, opgradering og fuld lokal CI

**Files:** Modify `.github/workflows/ci.yml`. (`tests/sql/test-2bii-upgrade.sh` is left untouched: its DB lacks the writer bootstraps, so the new tests would throw `REIMPORT_NARRATIVE_RECORD_CONTRACT_REQUIRED` there. Task 3 Step 6's `ci5b_v3_t3m` covers the upgrade path with the bootstraps; Fable review of the plan, fund 3.)

- [ ] **Step 1: CI.**
  - At the end of the pytest line (`ci.yml:142`), add `.claude/skills/daa-extract/scripts/test_relation_persona_extract_v3.py .claude/skills/daa-extract/scripts/test_relation_marriage_sheet_v3.py` (before ` -q`).
  - In the loop at `ci.yml:491`, extend the list to `test-relation-persona-v2 test-relation-person-create test-relation-disposition test-relation-persona-v3 test-relation-person-create-v3`.
  - In the e2e step (`ci.yml:501`), add a line after the v2 script: `bash tests/sql/test-relation-marriage-sheet-v3.sh ci5b_2bii_sheet` (other source and person ids, so the same DB works).
- [ ] **Step 2: Full local CI.**
  - Generate the job scripts with the scratchpad `gen_ci.py` and run all 7 jobs plus the unchanged `bash tests/sql/test-2bii-upgrade.sh ci5b_v3_up` (regression only).
  - Use `env -u PGOPTIONS env -u NODE_OPTIONS` (memories: PGOPTIONS mutes NOTICE tests, and NODE_OPTIONS points at a removed preload).
  - Expected: `CI_JOB_OK_*` × 7 and `UPGRADE_OK`.
  - Fix any failure before committing. A failure in a repo-wide guard (e.g. `test_clause_readers`) is a finding about the new files, not pre-existing noise.
- [ ] **Step 3: Commit**: `test(151): CI for 2b-ii runde 2`.

---

### Task 6: Bevis i restore (spec §17.8), rapport og dokumenter

**Files:**
- Create: `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md`.
- Modify: `docs/evidensbaseret-genimport/status.md` (the 2b-ii row, or a new row below it), `docs/changelog.md`, `docs/decisions.md` (new post at the top).
- Private: `~/.private/5b-navneregel-v3/`; reuse `step.sh`, `identitet`-runner and the efterkørsel scripts from `~/.private/5b-2b-ii/` and `~/.private/5b-2b-i/` (copy, do not edit them in place).

- [ ] **Step 1: Arbejdsbase.**
  - Run `createdb -T daa5b_2b_ii_bevis_20261017132417 daa5b_navnv3_bevis_<ts>`.
  - Lift it to HEAD (`db-migrations.sql`, `db-rls.sql`, `db-verify.sql`).
  - Take before-measurements:
    - the canonical aggregate hashes (as 2b-ii);
    - 2a's tuple digest `89bde760…5923`;
    - anon-read hashes;
    - counts of `person/family/family_member/fact/assertion/citation/conclusion`;
    - bindings (232).
  - Write the Task 2 expectations for the P-row into the ledger **before** any write.
  - Take negative copies `_negA` and `_negC` now.
- [ ] **Step 2: Rækkefil og ark.**
  - `relation_v3_rows.sql` → `rows.json` (0600).
  - `render` → `ark.txt`. The ARK_OK line should match Task 2's distribution (P: `p_d=1`).
  - **STOP:** the projektejer reviews the sheet with `open -e`, adds `navn:` where needed, and gives the sha256 in chat. Record the distribution (numbers only), the number of `navn:` lines and the number of skew-confirmed `S`.
- [ ] **Step 3: Anvendelse.**
  - `sql` → manifest plus identity script.
  - `relation_persona_apply.sql` → personas.
  - Identity script (`S` + `P`).
  - `red_relation_person_create_input(1)` → manifest; record its hash in the ledger. Expected: 1 element, `family_mode` `new`.
  - `relation_batch_apply.sql operation=relation_person_create`.
- [ ] **Step 4: Efterkørsel**, as 2b-ii Task 8 Step 4: decide → bind-preview → bind → rerun gives 0. Expected bindings = 232 + `S` + 1. Count new `ordinal_afvigelse` classifications.
- [ ] **Step 5: Disposition.** `red_relation_disposition_input(1)` → batch; rerun gives 0. Report the number of clauses that switch and the number that still wait (§17.8 asks for which, not why; no breakdown by blocking reason).
- [ ] **Step 6: Kontrolmålinger (spec §17.8).**
  - The new person: `staged`, `levende=false`, `visning_navn` = mention text, title-free (`NOT private.relation_name_has_title`).
  - The chain fact → assertion → citation (source 1, page) → conclusion.
  - 1 family, 2 `family_member`.
  - Identity `accepted` with `deceased`.
  - `verify_relation_person_create_receipts` green.
  - The persona receipts' `sheet_sha256` equals the identity evidence's `sheet_sha256`.
  - Anon-read hashes unchanged.
  - Aggregate hashes unchanged except the new rows.
  - The 2a digest unchanged.
- [ ] **Step 7: Negativtests.**
  - **A** (copy `_negA`): run the identity script twice; the second run gives `EVIDENCE_IDENTITY_VERSION_CONFLICT` and 0 new events. Then call the P-line's `red_afgoer_source_persona(<P>, 1, …)` **alone** (the script's rerun stops at the first `M` line, so it never reaches the P-line). Expected: `EVIDENCE_IDENTITY_VERSION_CONFLICT`, 0 new events.
  - **C** (copy `_negC`, no DB writes needed): a hand-edited sheet with one `U` row raised to `S` (no rule confirmation), with a fresh hash ⇒ `SHEET_TOKEN_NOT_ALLOWED`, 0 files.
  - Then rename the copies to `slet_<MMDD>__…` (quarantine; manifest in `~/.private/5b-navneregel-v3/`).
- [ ] **Step 8: Dokumenter**, numbers and hashes only.
  - The report covers:
    - distribution and coverage;
    - the new person;
    - which proof is still missing (`existing` per errata §16.1);
    - skew counts;
    - disposition;
    - negative tests;
    - deviations.
  - `status.md` and `changelog.md` are dated.
  - `decisions.md` post: »BESLUTTET: `mention.place` udsættes (246 klausuler i `afventer_identitet`); aldersregel v2 designet, men ubrugt (2026-10-18)«.
  - Commit `docs(151): 2b-ii runde 2 bevist i restore — navneregel v3 og den første nye person på bogens data`.

---

## Self-Review

1. **Spec coverage:**

   | Spec | Plan |
   | --- | --- |
   | §17.1 | header and Task 6 report |
   | §17.2 | erratum already in the spec; Task 2 Step 2 re-measures it |
   | §17.3 | Global Constraints (age rule untouched) and Task 6 decisions post |
   | §17.4 | Task 1 |
   | §17.5 | Task 1 (Python) and Task 3 (SQL twin, writer check, twin test) |
   | §17.6 | Task 4 (plus the Task 3 input projection, with a ruling about the queue RPCs) |
   | §17.7 | Task 3 |
   | §17.8 | Task 2 (dry run) and Task 6 |
   | §17.9 | Tasks 1, 3, 4, 5 |
   | §17.10 | Task 6 |
   | §17.11 | Task 6 report |

2. **Placeholder scan:**
   - Two adaptation clauses remain (Task 3 Step 1: fixture signatures and trigger paths). Both pin the assertion and require a ruling, which is the executor's documented latitude.
3. **Type consistency:**
   - `propose(row, cutoff, name_override=None)` and `propose_redecide(prow, cutoff)` match across Tasks 1, 2 and 4.
   - The keys `name_basis/sheet_line/sheet_sha256` match across Tasks 3 and 4.
   - The contract `relation-persona-v3-input` with `rows`/`redecide_rows` matches across Tasks 3 and 4.
   - The error codes match across Tasks 3 and 6.
4. **Review Focus:** each of the 5 lines has a named test in its owning task (Tasks 1, 3, 4 and 6).
5. **Plan review (Fable, 2026-10-19), all findings incorporated:**
   - (1) `_links_to_name` allows punctuation after the end word (`test_komma_efter_efternavnet_bag_en_titel`);
   - (2) the `test_identity_guard_static.py` count goes to 2 (Task 3);
   - (3) the `test-2bii-upgrade.sh` change is cut (Task 5);
   - (4) `test_navn_to_gange_afvises` uses the unchanged row;
   - (5) `flere_partnere`/`titel_i_navn` carry `**out`;
   - (6) `navn:` must end on a whole word;
   - (7) unknown title ⇒ `U navn_afkortet` (spec §17.9);
   - (8) the P-line's lock is tested on its own (Task 4 e2e, Task 6 A);
   - minors:
     - `navn:` without a name start always raises;
     - `title_free` splits like SQL;
     - Task 2 measures the interpretation status and the control-sample seal;
     - v3 goes into the older ACL list too;
     - the scratchpad helpers are described;
     - Task 6 disposition is counts only.
