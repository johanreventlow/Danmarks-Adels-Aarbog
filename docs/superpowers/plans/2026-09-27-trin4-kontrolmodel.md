# Trin 4 · kontrolmodellen: mennesket ser kun uoverensstemmelser og en stikprøve — implementeringsplan

**Goal:** Erstat de fulde afgørelsesark med beslutningen 2026-09-27: forslag, hvis værdi matcher
databasen, accepteres og bindes maskinelt; mennesket ser kun reelle uoverensstemmelser og en
stikprøve på 20.

**Architecture:** Ingen DDL og ingen ændrede RPC'er. Nyt er en læse-kun klassifikation over
`proposed` (SQL), en fil med rækkeeksporten (SQL), et lille orkestreringsscript
(`control_model.py`) og en `method`-parameter i arkets SQL-oversættelse. Arket, HTML-fladen,
`red_decide_interpretation`, målfindingen (`interpretation_promotion_targets.sql`) og
bindings-RPC'erne genbruges uændret.

**Spec:** trin 4-spec §8.2-8.4 (+ ny ERRATA 8.2, 2026-09-27). **Beslutning:** `decisions.md`
2026-09-27. **Review-budget:** kun restore ⇒ 1 + 1 (decisions 2026-09-23); planrunden springes
over, koderunden tages af en uafhængig agent (ikke Codex — review 35, P1).

## Kobling (CLAUDE.md-styringen)

| | |
| --- | --- |
| Roadmapmål | Trin 4 (#147): fortolkningskæden for 2018-20, hovedpersonens persona |
| Værdikædeled | Afgørelse → promotion (binding) |
| Leverancetype | Værktøj + måling |
| Redaktionel værdi | Projektejerens byrde pr. kørsel falder fra hele arket (243 kort i 4.5) til ≈ 25 |
| Workflow, det erstatter | Fulde afgørelsesark (4.5 Task 5-6) |
| Færdigbevis | Én rigtig kørsel (regel 4, 2026-09-03) på pilotens egne data, sammenlignet med projektejerens faktiske 4.5-afgørelser |

## Global Constraints

- **Ingen prod.** Kørslen sker i en ny kopi af restoren `daa43b_20260912192527`; restoren og
  4.5's arbejdsbase røres ikke.
- **Rediger ikke `interpretation_promotion_targets.sql`** — prod-vej-spec'ens inventar hasher den.
- **MATCH-udtrykket er byte-identisk med målfindingens:** `lower(btrim(normalize(x,NFC)))`.
  Skrivemåde-klassen er kun klassifikation; den ændrer aldrig en status.
- **Ingen kildetekst i repo, logs, commits eller chat.** Rækkefiler og ark er `0600` under
  `~/.private/kontrol-*/`.
- Test med `env -u NODE_OPTIONS /usr/bin/python3 -m pytest`; nye testfiler tilføjes `ci.yml`.

## Kørslens rækkefølge (korrekthedskrav)

1. **Klassificér** alle `proposed` med en aktiv promotionregel: `MATCH`, `MATCH_SINGLETON`,
   `AMBIGUOUS`, `SKRIVEMAADE`, `NO_FACT`, `REAL_DIFF`, `NO_IDENTITY`, `NO_PLACEMENT`,
   `UNSUPPORTED_RULE`. Output: JSON med `items` (id, version, prædikat, klasse, `assertion_id`
   for MATCH) og 0-fyldte tal pr. prædikat. Forslag uden promotionregel indgår ikke og forbliver
   `proposed`.
2. **Træk stikprøven** blandt `MATCH` (kun bulk-mål) deterministisk: sortér efter
   `sha256("kontrolmodel-v1:" + interpretation_id)`, tag de første 20. `sample_sha256` noteres,
   før et menneske ser et kort. Er der ≤ 20 kandidater, er de alle i stikprøven, og intet
   accepteres maskinelt.
3. **Menneskets ark** = `REAL_DIFF` ∪ stikprøven, bygget med det eksisterende ark-værktøj af en
   delmængde af rækkefilen. Arket hash-bindes ved godkendelse som i 4.5.
4. **Gate:** ét `R` **eller** `U` i stikprøven ⇒ STOP (`SAMPLE_FAILED`); intet accepteres
   maskinelt i den kørsel. `U` tæller med, fordi en uafklaret stikprøve ikke er en godkendt.
5. **Skriv** menneskets afgørelser (`method = human-sheet-kontrol-v1`), derefter den maskinelle
   accept af de resterende `MATCH` (`method = machine-corroboration-v1`, evidens:
   `decision = "decisions.md 2026-09-27"`, `classification_sha256`, `sample_sha256`,
   `assertion_id`) — hver med forventet version, i én transaktion med antalskontrol.
6. **Verificér som mængde, derefter bind:** målfindingens `MATCH`-sæt = maskinsættet ∪ de
   menneskeaccepterede `MATCH` i stikprøven (`verify-sql` før binding — bagefter er målene
   `ALREADY_PROMOTED`); derefter den eksisterende målfinding og batch-RPC.

Uændret `proposed` efter kørslen: `SKRIVEMAADE`, `NO_FACT`, `AMBIGUOUS`, `NO_IDENTITY`,
`NO_PLACEMENT`, `UNSUPPORTED_RULE` og alle ikke-promoverbare forslag. De tælles i rapporten.
En accepteret `REAL_DIFF` forbliver accepteret og ubundet — det er meningen, ikke en fejl
(oprettelse af nye fakta er åbent punkt 11.3).

## Tasks

### Task 1: Klassifikationen i SQL — test først

**Files:** Create `.claude/skills/daa-extract/scripts/interpretation_control_classification.sql`,
`tests/sql/test-interpretation-control-classification.sql`; Modify `.github/workflows/ci.yml`.

- [ ] Testen genbruger målfindingstestens fixture og tilføjer: en dato med `†` foran (`SKRIVEMAADE`),
  en persona uden faktum af typen (`NO_FACT`), en reelt forskellig værdi (`REAL_DIFF`).
- [ ] Den afgørende assert: accepteres klassifikationens `MATCH`-sæt, giver
  `interpretation_promotion_targets.sql` præcis de samme id'er som `MATCH`.
- [ ] Kør mod en frisk base bygget som CI-jobbet (bootstrap → schema → rls → migrations ×2 → rls):
  først FAIL (filen findes ikke), så `OK`. Tilføj testen i jobbet `evidence promotion`.

### Task 2: Rækkeeksporten som fil

**Files:** Create `.claude/skills/daa-extract/scripts/interpretation_control_rows.sql`.

- [ ] 4.5-planens Task 5 Step 5-forespørgsel ordret som fil (samme `value_text`-regel).

### Task 3: `method` i arkets SQL-oversættelse

**Files:** Modify `interpretation_decision_sheet.py`, `test_interpretation_decision_sheet.py`.

- [ ] `decision_sql(..., method="human-sheet-4.5")` og `--method` på `sql`; standard uændret
  (test låser det eksisterende output), `human-sheet-kontrol-v1` til kontrolmodellen.

### Task 4: `control_model.py` — test først

**Files:** Create `.claude/skills/daa-extract/scripts/control_model.py`, `test_control_model.py`;
Modify `ci.yml` (pytest-listen).

- [ ] `plan --classification --rows --out-dir`: skriver `rows-kontrol.json` (REAL_DIFF ∪ stikprøve),
  `machine-plan.json` (resten af `MATCH` med version og `assertion_id`) og `plan.json` med
  `classification_sha256`, `rows_sha256`, `sample_sha256`, `rows_kontrol_sha256`.
- [ ] `machine-sql --plan --sheet --approved-sha256`: tjekker hashes, parser arket, kræver at
  stikprøven er fuldt `accepted` (ellers `SAMPLE_FAILED`), og skriver SQL'en for maskinsættet.
- [ ] Tests: stikprøvens determinisme og uafhængighed af inputrækkefølge; ≤ 20 kandidater ⇒ tomt
  maskinsæt; `R` og `U` i stikprøven ⇒ STOP; `REAL_DIFF`-afvisning stopper ikke; ændret
  klassifikation eller ark ⇒ hash-fejl; `MATCH_SINGLETON`/`AMBIGUOUS` kommer aldrig i
  maskinsættet; SQL'en bærer forventet version og antalskontrol.

### Task 5: Spec-errata

**Files:** Modify trin 4-spec'en (ny `8.2 ERRATA (2026-09-27)`).

- [ ] Arket er ikke længere hele forslagsmængden; rækkefølgen ovenfor; `U` i stikprøven er STOP;
  de to metodeværdier.

### Task 6: Én rigtig kørsel og rapport

- [ ] `createdb -T daa43b_20260912192527 daa_kontrol_<stamp>` (tjek `pg_stat_activity` først);
  genafspil 4.5's ingest med dens proposal-manifest ⇒ 243 `proposed` som før projektejerens ark.
- [ ] Klassificér, planlæg, render det korte ark **forudfyldt med projektejerens egne
  4.5-afgørelser** (samme nøgle som 4.5's prior). Projektejeren godkender en hash og udfylder
  intet.
- [ ] Skriv, bind, verificér mængden. Mål: maskinsættet mod projektejerens 4.5-afgørelser på de
  identiske claims (enighed), bindinger mod 4.5's 43, antal kort for mennesket.
- [ ] Rapport `docs/evidensbaseret-genimport/kontrolmodel-kørsel-2018-20.md` (tal og hashes, ingen
  tekst), status og changelog. Uafhængigt kodereview (1 runde) før merge.
