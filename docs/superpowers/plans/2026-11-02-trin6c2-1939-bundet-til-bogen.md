# Trin 6c-2: 1939-fakta bundet til bogen — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1939's navne, titler, fødsler og dødsfald står i læseren som bundet til bogens post (»DAA 1939, s. N ·
<post>«), med bogens værdi, hvor projektejeren har valgt den, og uden at personsiden bliver langsommere.

**Architecture:**
- **PR 1 — basen** (to migrationsblokke): (a) set-baseret bindingstjek i `public_person_facts` (vej B); (b) en
  deterministisk forslagsversion, en påstandsnøglet rettelsesvej med journal og »højst én gældende binding pr.
  påstand«; en test, der låser, at »forkert person« (identitet → `unresolved`) ikke rører narrativ eller fakta.
- **PR 2 — scripts:** kontrollens SQL får kildescope og to nye udfald; kontrolværktøjet v2 (stratificeret stikprøve,
  svar `B/D/V` pr. felt og `P` pr. persona, maskinsættet beregnes efter svarene); kortværktøjet pr. persona ind i
  repo'et; målingen `maal_trin6c2.sql` og vej B's tidsmåling.
- **Øvelse** på en prod-dump-stand-in; **prod** i fire ceremonier fra projektejerens shell: (1) vej B, (2) basens
  writere + kort 122, (3) datoversioner + linjeskift-rettelser, (4) kontrol → kort → anvend → slutmåling.
- Afgørelserne skrives direkte i prod gennem ceremonien (som 6c-1's C), ikke gennem overførselspakken; derfor røres
  `transfer_pack.py` ikke (spec §4.6 pkt. 3).

**Tech Stack:** PostgreSQL 17 / plpgsql (`schema.sql`, `db-migrations.sql`, `db-verify.sql`), psql-tests i
`tests/sql/`, Python 3 + pytest (`.claude/skills/daa-extract/scripts/`), zsh-runnere i `~/.private/5ab-overfoersel/`,
GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-02-trin6c2-1939-bundet-til-bogen-design.md`. Læs §2-§8 før hver task.

## Global Constraints

- `schema.sql` er source of truth. Hver DB-ændring står i `schema.sql` og i én af to idempotente blokke sidst i
  `db-migrations.sql`, der kan køres to gange:
  - `-- ===== trin 6c-2a: set-baseret bindingstjek (vej B) =====`
  - `-- ===== trin 6c-2b: forslagsversion, påstandsrettelse, én binding pr. påstand =====`
  Ceremoni 1 anvender kun 6c-2a; ceremoni 2 kun 6c-2b (runneren udtrækker blokken mellem overskriften og næste
  `-- =====`).
- Ingen editionsnavngivne funktioner, tabeller, udfald eller fejlkoder. Kilden kommer altid fra data
  (`source_persona.source_id`, `interpretation.source_id`) eller en parameter; aldrig `source_id=3` i kode.
- 2018-20 er uændret: `public_person_facts` giver byte-ens rækker for alle personer; `control_model.py` v1 og
  `interpretation_decision_sheet.py` røres ikke; 2018-20's bindinger er alle gyldige før og efter hver ceremoni
  (nøglet liste).
- Navne (præcis tekst):
  - normaliseringsregel `dato-markoer-v1`; funktion `private.normaliser_dato_markoer_v1(text) RETURNS text`
    (IMMUTABLE): fjern én indledende `f.` eller `†` med efterfølgende blanktegn, saml alle blanktegn (`\s+`) til ét
    mellemrum, trim; intet andet;
  - RPC `public.red_normaliser_forslag(p_interpretation_id uuid, p_expected_version integer, p_regel text) RETURNS
    jsonb`; `method` på den nye version: `deterministisk-normalisering:dato-markoer-v1`;
  - tabel `public.paastand_korrektion` (append-only: `id`, `assertion_id`, `interpretation_id` NULL, `grund` ∈
    `bogen_har_ret`/`linjeskift-v1`, `foer jsonb`, `efter jsonb`, `change_set_id`, `actor_id`, `actor_navn`,
    `oprettet_at`); RLS som `import_korrektion`;
  - RPC `public.red_ret_paastand(p_assertion_id bigint, p_forventet jsonb, p_grund text, p_interpretation_id uuid,
    p_dato jsonb DEFAULT NULL) RETURNS jsonb` og `public.red_paastand_historik(p_assertion_id bigint)`;
  - »forkert person« bruger den eksisterende `red_afgoer_source_persona(p_source_persona_id, p_expected_version,
    'unresolved', NULL, p_note, p_context)` med `ønsket_person_id=<id>; grund=<tekst>` i `p_note` og kortkvitteringen
    `{"basis":"human_sheet","sheet_sha256","rows_sha256","line"}` i `p_context` (konteksten afviser en
    `ønsket_person_id`-nøgle, målt i Task 5); ingen ny RPC (spec §4.2);
  - nyt udfald i `validate_interpretation_promotion_items` og i klassifikationen: `ALREADY_BOUND_OTHER`; nyt udfald i
    klassifikationen: `TARGET_SHARED`;
  - kontrolværktøj `control_model_v2.py` (SEED `kontrolmodel-v2`, metode `human-sheet-kontrol-v2`, maskinmetode
    `machine-corroboration-v2`); kortværktøj `persona_kort.py` + `persona_kort.html` + `persona_kort_kontekst.sql`;
  - måling: `T6C2_MAAL tilstand=<foer|a|b|c|d> forslag_k=<n> match=<n> skrivemaade=<n> real_diff=<n>
    accepteret_k=<n> bindinger_k=<n> rettelser=<n> unresolved_fra_kort=<n> k1_bindinger_hash=<sha256>` (`-v source_id`,
    standard 3); vej B: `T6C2_VEJB person=<id> ms=<n>` pr. kald.
- Fejlkoder (præcis tekst): `NORMALISERING_REGEL_UKENDT`, `NORMALISERING_PRAEDIKAT_UGYLDIG`,
  `NORMALISERING_UAENDRET`, `NORMALISERING_IKKE_PROPOSED`, `NORMALISERING_VERSION_KONFLIKT`,
  `NORMALISERING_KOERSEL_MANGLER`; `PAASTAND_ROLLE_FORBUDT`,
  `PAASTAND_DRIFT`, `PAASTAND_KILDE_DELT`, `PAASTAND_BINDING_BRYDES`, `PAASTAND_NAVN_FORKORTES`,
  `PAASTAND_GRUND_UGYLDIG`, `PAASTAND_VAERDI_UAENDRET`, `PAASTAND_FAKTATYPE_UGYLDIG`, `PAASTAND_FORSLAG_UOVERENS`;
  ceremoni `PERSONA_HAR_PROMOTIONER`; kontrol `PLAN_SCOPE_MANGLER`,
  `SHEET_V2_LINE_INVALID`, `SHEET_V2_UNDECIDED`, `SAMPLE_FAILED`.
- `red_ret_paastand`'s værdi er aldrig fri: `bogen_har_ret` → forslagets aktuelle værdi (`p_interpretation_id`'s
  `interpretation_current`); `linjeskift-v1` → påstandens egen værdi med blanktegn samlet. Kun datoer tager `p_dato`
  (`date_min`/`date_max`/`date_qualifier` beregnet af `validate.py:derive_date_info`). Visningscachen følger af
  `trg_assertion_regen` (`schema.sql:6305`); intet skriver `person.visning_*` direkte.
- Persondata: intet script eller output i repoet viser posttekst, værdier eller navne; kun antal, id'er og hashes.
  Kortark, kontekst, svar og kvitteringer ligger kun under `~/.private/6c2/` (0700/0600). Fixtures er syntetiske.
  Ingen model får poster. Søge- og Codex-kommandoer udelukker `work*/` og `~/.private` i selve kommandoen.
- Prod: kun fra projektejerens shell med `--jeg-mener-det` og GO-kode; RPC'er med `request.jwt.claim.sub` sat i
  transaktionen. Prods `statement_timeout` er 2 min; stand-ins øves med `ALTER DATABASE … SET
  statement_timeout='2min'`, ICU-locale og `ANALYZE` efter restore. Prod-tid anslås med 27× for writer-/RPC-kald og
  3× for én stor læsning (`database-current-state.md` §18); vej B's tid måles kun i prod.
- Commits: Conventional Commits med dansk beskrivelse, med `Claude-Session`-linjen. Ét commit pr. task. Ingen push
  uden projektejerens ja; PR'er som draft.
- Lokal verifikation før push: hele de berørte CI-jobs (`writer-1939-v50-db`, `narrative-record-contract-db`,
  `evidence-promotion-db`, `interpretation-proposal-db` begge rækkefølger, `python`), ikke kun egne testfiler.

## Review Focus

1. **En person med både 2018-20- og 1939-bindinger og en ugyldig binding imellem:** vej B giver præcis samme rækker
   og kildelinjer som i dag. Testes i Task 1 step 1 og på stand-in'en for alle personer i Task 9.
2. **To forslag (samme eller forskellige personas, enhver kilde) mod samme påstand:** ingen af dem binder i samme
   kørsel (`TARGET_SHARED`); mod en påstand med en gyldig binding → `ALREADY_BOUND_OTHER`; læseren viser fortsat den
   eksisterende postreference. Testes i Task 4 og Task 6.
3. **»Bogen har ret« på et navn, hvor forslaget er en del af databasens navn** (titel eller gods ville forsvinde):
   afvises med `PAASTAND_NAVN_FORKORTES`; kortet tilbyder ikke `B`. Testes i Task 3 og Task 8.
4. **»Forkert person« på en persona, hvis post er publiceret** (kort 122, retning 2-origin): identiteten bliver
   `unresolved`, narrativet står publiceret uændret, `public_person_facts` for den gamle person er uændret, og
   personaens forslag klassificeres `NO_IDENTITY`. Testes i Task 5.
5. **Projektejeren svarer `P` på en persona, hvis `MATCH`-felter ellers ville være bundet maskinelt:** ingen af
   personaens forslag får en afgørelse; maskinsættet er beregnet uden dem. Testes i Task 7.

---

## PR 1 — database (gren `feat/trin6c2-db` fra `docs/trin6c2-spec`)

### Task 1: Vej B — set-baseret bindingstjek (blok 6c-2a)

**Files:**
- Modify: `schema.sql` `public.public_person_facts` (ca. 20045-20115): CTE `b` afgør gyldighed for alle personens
  promotion-rækker i én mængdeoperation (join mod `interpretation_current` for de berørte `interpretation_key`, regel
  ved `rule_key`/`rule_version`, identitet, faktatype og værdisammenligning som i `assertion_binding_current`).
- Modify: `schema.sql` `private.assertion_binding_current` (19872): værdisammenligningen flyttes til én IMMUTABLE
  hjælper `private.binding_value_matches(p_value_kind text, p_interpretation_value jsonb, p_vaerdi_tekst text,
  p_date_raw text) RETURNS boolean`, som begge bruger.
- Create: `tests/sql/fixtures/public_person_facts_reference.sql` (den nuværende funktion som
  `pg_temp.public_person_facts_ref`, kopieret fra `main`).
- Modify: `tests/sql/test-person-facts.sql`; `db-migrations.sql` blok 6c-2a.

**Interfaces:** Produces: `public_person_facts(bigint[])` med uændret signatur og rækkeform; `binding_value_matches`.

- [ ] **Step 1: Test:** for hver fixtureperson (med gyldig, ugyldig, dobbelt og 1939-binding) er
  `public_person_facts(ARRAY[id])` mængde-lig `pg_temp.public_person_facts_ref(ARRAY[id])` (`EXCEPT` begge veje = 0);
  `assertion_binding_current` og den nye CTE er enige for alle promotion-rækker; `EXPLAIN` af kaldet indeholder ikke
  et SubPlan pr. promotion-række mod `interpretation`.
- [ ] **Step 2:** Kør mod `main`'s schema med referencen: lighed OK, `EXPLAIN`-assertion FAIL.
- [ ] **Step 3:** Implementér; blok 6c-2a.
- [ ] **Step 4:** `writer-1939-v50-db`-jobbet lokalt mod frisk `schema.sql` og mod `db-migrations.sql` kørt to gange.
- [ ] **Step 5:** Commit `perf(db): vej B — fakta-kaldet afgør bindinger som mængde`.

### Task 2: Deterministisk forslagsversion (blok 6c-2b)

**Files:**
- Modify: `schema.sql`: `private.normaliser_dato_markoer_v1(text)`; `public.red_normaliser_forslag(...)` (mønster:
  `red_decide_interpretation` `:9340` for version, `supersedes_id`, kopierede observationslinks og lås). Kræver
  rollen `redaktion`, `status='proposed'`, `version = p_expected_version`, prædikat ∈ `person.birth`/`person.death`,
  regel = `dato-markoer-v1`; ny værdi = reglen anvendt på den gamle; uændret værdi → `NORMALISERING_UAENDRET`. Ny
  række: `status='proposed'`, `derivation_kind='deterministic'`, `method` fra Global Constraints,
  `extraction_run_id` = `current_setting('daa.extraction_run_id', true)::uuid` (ét pr. ceremoni; mangler →
  `NORMALISERING_KOERSEL_MANGLER`), øvrige felter kopieret.
- Create: `tests/sql/test-interpretation-normalisering.sql`; Modify: `db-migrations.sql` blok 6c-2b;
  `db-rls.sql` (grants som `red_decide_interpretation`).

**Interfaces:** Produces: `red_normaliser_forslag`; `normaliser_dato_markoer_v1`.

- [ ] **Step 1: Test:** `normaliser_dato_markoer_v1` på `f. 12. marts 1702` → `12. marts 1702`; `†  1750` → `1750`;
  `12. marts\n1702` → `12. marts 1702`; `død 1750` → uændret (kun `f.`/`†`); `ff. 1702` → uændret. RPC: version 2 er
  `proposed`, `deterministic`, `supersedes_id` = v1, samme nøgle og kilde, observationslinks som v1;
  `interpretation_current` returnerer v2; klassifikationen (`interpretation_control_classification.sql`) ser v2's
  værdi. Fejl: forkert version → `NORMALISERING_VERSION_KONFLIKT`; `person.name` → `NORMALISERING_PRAEDIKAT_UGYLDIG`;
  `accepted` forslag → `NORMALISERING_IKKE_PROPOSED`; ukendt regel → `NORMALISERING_REGEL_UKENDT`; manglende
  `daa.extraction_run_id` → `NORMALISERING_KOERSEL_MANGLER`. Kald uden rolle afvises.
- [ ] **Step 2:** Kør: FAIL (funktion findes ikke).
- [ ] **Step 3:** Implementér.
- [ ] **Step 4:** `interpretation-proposal-db` begge rækkefølger + testfilen to gange efter migration.
- [ ] **Step 5:** Commit `feat(db): deterministisk version af et forslag (dato-markoer-v1)`.

### Task 3: Påstandsnøglet rettelse og journal (blok 6c-2b)

**Files:**
- Modify: `schema.sql`: tabel `paastand_korrektion`; `red_ret_paastand`; `red_paastand_historik` (mønster:
  `red_ret_ocr_felt` `:2034` for rolle, `begin_change_set('red_ret_paastand', …, 'person', <faktaets person>)`, lås).
- Modify: `db-rls.sql`, `db-migrations.sql` blok 6c-2b, `db-verify.sql` (tabellen findes, RLS på, ingen anon-grant).
- Create: `tests/sql/test-paastand-rettelse.sql`.

**Interfaces:**
- `p_forventet` = `{"fact_id", "faktatype", "vaerdi_tekst", "date_raw", "valgt_assertion_id", "citation_sources":
  [bigint]}` som kortet så dem; enhver afvigelse → `PAASTAND_DRIFT`.
- Produces: kvittering `{assertion_id, grund, foer, efter, change_set_id, korrektion_id}`.

- [ ] **Step 1: Test** (fixture: person med 1939-citeret navn, titel, fødsel, død; én påstand også citeret af kilde 1):
  - `bogen_har_ret` på titel → `vaerdi_tekst` = forslagets værdi, samme `assertion.id`, én `paastand_korrektion` og
    `change_event` med før/efter; `red_paastand_historik` viser den; `visning_*` regenereret af triggeren;
  - dato: `date_raw` = forslagets, `date_min/max/qualifier` = `p_dato`; uden `p_dato` → `PAASTAND_FAKTATYPE_UGYLDIG`;
  - `linjeskift-v1`: `12. marts\n1702` → `12. marts 1702`, `date_min/max` uændrede; allerede ren → `PAASTAND_VAERDI_UAENDRET`;
  - påstand citeret af to kilder → `PAASTAND_KILDE_DELT`; forslag fra en anden kilde end citationen →
    `PAASTAND_KILDE_DELT`; ændret værdi siden kortet → `PAASTAND_DRIFT`;
  - forslaget er ikke `proposed`/`accepted` for netop dette faktum og denne persona → `PAASTAND_FORSLAG_UOVERENS`;
  - navn: forslaget `Ditlev` mod påstanden `Ditlev Reventlow til X` → `PAASTAND_NAVN_FORKORTES` (regel: den nye værdi
    er en ægte delstreng af den gamle efter blanktegnssamling og små bogstaver);
  - en gyldig binding på påstanden fra et andet forslag ville blive ugyldig → `PAASTAND_BINDING_BRYDES`;
  - `koen`-faktum eller ukendt grund → `PAASTAND_FAKTATYPE_UGYLDIG`/`PAASTAND_GRUND_UGYLDIG`; uden rolle →
    `PAASTAND_ROLLE_FORBUDT`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementér. **Step 4:** `evidence-promotion-db` + testfilen efter migration ×2.
- [ ] **Step 5:** Commit `feat(db): påstandsnøglet rettelse med journal (bogen_har_ret, linjeskift-v1)`.

### Task 4: Højst én gældende binding pr. påstand (blok 6c-2b)

**Files:** Modify: `schema.sql` `private.validate_interpretation_promotion_items` (10618; nyt `reason_code`
`ALREADY_BOUND_OTHER` efter `ALREADY_PROMOTED`, når en anden fortolkning — fra enhver kilde — har en gyldig binding
på samme påstand, eller når to forskellige fortolkninger i samme batch rammer samme påstand, uanset persona; læseren
tæller på tværs af kilder, `schema.sql:20088-20091`); `db-migrations.sql`
6c-2b; `tests/sql/test-evidence-promotion.sql`, `tests/sql/test-person-facts.sql`.

- [ ] **Step 1: Test:** to personas fra kilde 3 med accepterede forslag mod samme påstand: første batch binder,
  anden får `ALREADY_BOUND_OTHER`; samme to i én batch → begge `ALREADY_BOUND_OTHER`; to fortolkninger fra **samme**
  persona i én batch → begge afvist; en kilde 1-binding på påstanden blokerer en kilde 3-binding; `public_person_facts`
  viser postreferencen for den bundne; alle eksisterende tests i `evidence-promotion-db` grønne (prod: 0 påstande
  med flere bindinger, målt 2026-11-02).
- [ ] **Step 2:** FAIL. **Step 3:** Implementér. **Step 4:** `evidence-promotion-db` + `writer-1939-v50-db`.
- [ ] **Step 5:** Commit `feat(db): højst én gældende binding pr. påstand`.

### Task 5: »Forkert person« rører hverken narrativ eller fakta (kun test)

Fallback (c) (spec §4.2): ingen flytte-RPC; `P` og kort 122 sætter identiteten `unresolved` med den eksisterende
`red_afgoer_source_persona` (`schema.sql:10247`). Narrativvejen kan ikke publicere på et mål uden placements
(`schema.sql:13911-13936`, `:14030-14041`); kilde 3 har 0 (målt).

**Files:** Create: `tests/sql/test-persona-forkert-person.sql`; Modify: `.github/workflows/ci.yml`
(`narrative-record-contract-db` kører filen).

- [ ] **Step 1: Test** (fixture: 1939-agtig persona med identitet origin `publication_binding` og publiceret narrativ
  på person X, uden placements; ét `proposed` forslag): `red_afgoer_source_persona(…, 'unresolved', NULL, note,
  {"basis":"human_sheet", "ønsket_person_id": Y, …})` lykkes med `expected_version`; identiteten er `unresolved`
  med version + 1 og event; `narrative_record_publication` er stadig `published` på X; `narrative_record_state` for
  X er ikke blokeret (den aktive binding bærer autoriteten); `public_person_facts(ARRAY[X])` uændret;
  klassifikationen giver forslaget `NO_IDENTITY`. Stale version → `EVIDENCE_IDENTITY_VERSION_CONFLICT`. Kræver
  `p_context` felter, der ikke passer til en kortafgørelse (fx stikprøvekontekst), noteres det præcise krav i
  testen og i Task 7's SQL.
- [ ] **Step 2:** Kør mod `main`'s schema. Forventet: grøn (ingen DDL). Er den rød: **stop for projektejeren** —
  så kræver selv `unresolved` en ændring, og 6c-2 skal have en ny beslutning.
- [ ] **Step 3:** Commit `test(db): forkert person sætter identiteten uafklaret uden at røre narrativ og fakta`.

## PR 2 — scripts (gren `feat/trin6c2-scripts` fra `feat/trin6c2-db`)

### Task 6: Kontrollens SQL: kildescope og to nye udfald

**Files:** Modify: `.claude/skills/daa-extract/scripts/interpretation_control_classification.sql`,
`interpretation_control_rows.sql`, `interpretation_promotion_targets.sql`: **valgfri** GUC `daa.control_src`; sat →
filter `ic.source_id = current_setting('daa.control_src')::bigint`; ikke sat → output byte-ens med i dag (v1-kaldere:
`control_model.py`, `tests/sql/transfer-decide-bind.sh:57-60,143-144`, CI `ci.yml:222`). `control_model_v2.py`
nægter at køre uden kildeparameter (`PLAN_SCOPE_MANGLER`) og sætter altid GUC'en.
Klassifikationen får `ALREADY_BOUND_OTHER` (målet har en gyldig binding fra en anden fortolkning fra samme kilde)
og `TARGET_SHARED` (to forskellige fortolkninger med `MATCH` på samme påstand, uanset persona og kilde) før `MATCH`. Rækkeeksporten får
`identity_outcome` (`source_persona_identity.evidence->>'outcome'`), `persona_id`, `identity_version` og
`navn_forkortes` (bool, samme regel som `PAASTAND_NAVN_FORKORTES`). Modify: `tests/sql/test-interpretation-control-
classification.sql`, `test-interpretation-promotion-targets.sql`; byte-ens-test for 2018-20 med `daa.control_src=1`.

- [ ] **Step 1: Test:** uden GUC → byte-ens med `main` (hardkodet sha) og `transfer-decide-bind.sh` grøn; kilde 1 og 3
  i samme fixture giver adskilte resultater med GUC;
  2018-20-fixturens klassifikation er byte-ens med `main`'s (hardkodet sha); de to nye udfald; rækkernes nye felter.
- [ ] **Step 2-4:** FAIL → implementér → `evidence-promotion-db` + `python`. **Step 5:** Commit
  `feat(scripts): kontrollens SQL med kildescope, ALREADY_BOUND_OTHER og TARGET_SHARED`.

### Task 7: Kontrolværktøjet v2

**Files:** Create: `.claude/skills/daa-extract/scripts/control_model_v2.py` og `test_control_model_v2.py` (importerer
hjælpere fra `control_model.py`; v1 røres ikke); Modify: `.github/workflows/ci.yml` pytest-linjen.

**Interfaces:**
- `plan_run_v2(classification: dict, rows: list, *, source_id: int, strata: dict[str,int]) -> dict`:
  menneskets rækker = `REAL_DIFF` ∪ `SKRIVEMAADE` ∪ stikprøve; stikprøven = 10 `MATCH` med `identity_outcome` ∈
  {`svag`,`ingen_kandidat`} + 10 blandt resten, sorteret med `_sample_key` under SEED `kontrolmodel-v2`; personas i
  færre end 10 i et stratum → resten fyldes fra det andet
  og tallet rapporteres. Skriver `plan.json` (+ `persona_ids`, `strata`), `rows-kontrol.json`, `machine-candidates.json`.
- Ark v2: `F <interpretation_id> <ver> : B|D|V|_  # note` pr. felt; `P <persona_id> <identity_version> : -|P|P
  <person_id>` pr. persona. `parse_sheet_v2(text) -> (fields, personas)`; fejl `SHEET_V2_LINE_INVALID`,
  `SHEET_V2_UNDECIDED`, `SHEET_DUPLICATE`.
- `apply_plan_v2(plan, sheet_text, *, sheet_sha256, hashes) -> dict` → `{unresolved: [...], rettelser: [...],
  afgoerelser: [...], maskine: [...]}`: stikprøvefelt ≠ `B` eller stikprøvepersona med `P` → `SAMPLE_FAILED`;
  `P`-personas' forslag udelades af alt (også maskinen); `B` på `navn_forkortes` → `SHEET_V2_LINE_INVALID`;
  mapping som spec §4.4 pkt. 7. Datorettelsers `p_dato` beregnes her med `validate.derive_date_info(date_raw)`
  (`validate.py:623`-familien). `sql_v2(...)` skriver den samlede SQL i rækkefølgen `P`-identiteter → `unresolved` (med værnet: personaen har ingen
  promotion af nogen måltype, ellers `PERSONA_HAR_PROMOTIONER`) → rettelser →
  afgørelser → maskinaccept med re-klassifikation i transaktionen; `verify_sql_v2(plan, applied)` kræver MATCH =
  maskine ∪ stikprøve ∪ udtaget pga. `P` (planpartition), og at de bundne = maskine ∪ stikprøve ∪ `B`-rettede,
  med alle `P`-personas' forslag `proposed` og ubundne (promotionssæt) — spec §4.4 pkt. 7.

- [ ] **Step 1: Test** (syntetisk): stratificering 10/10 og opfyldning; `P` på en persona med maskine-MATCH fjerner
  dem; `D` på stikprøvefelt → `SAMPLE_FAILED`; `B` på `navn_forkortes` afvises; ark-round-trip; 2018-20's
  `control_model.py`-tests uændret grønne.
- [ ] **Step 2-4:** FAIL → implementér → `python`-jobbet. **Step 5:** Commit `feat(scripts): kontrolværktøjet v2`.

### Task 8: Kortværktøjet pr. persona i repo'et

**Files:** Create: `.claude/skills/daa-extract/scripts/persona_kort.py` (kommandoer `kontekst-ids`, `html`, `flet`),
`persona_kort.html`, `persona_kort_kontekst.sql` (læse-kun; udvidelse af `~/.private/5ab-overfoersel/c-kort/
kontekst.sql` med personaens felter, databasens værdier, forslagets værdier og `navn_forkortes`), `test_persona_kort.py`,
`fixtures/persona-kort-syntetisk/` (opdigtede navne og tekster). Grundlag: `~/.private/5ab-overfoersel/c-kort/kort.py`
(233 linjer) og `kort.html` (kun kode læses; ingen data).

- [ ] **Step 1: Test:** syntetisk plan + kontekst → HTML indeholder hverken klasse, `sample` eller stikprøvemarkering;
  felter grupperet pr. persona, højst 30 pr. ark; `navn_forkortes`-felter har ingen `B`-knap; `MATCH`-felter uden
  svar vises som kontekst; svarfil → `flet` → ark v2 → `parse_sheet_v2` round-trip byte-ens med en hardkodet sha.
- [ ] **Step 2-4:** FAIL → implementér → `python`-jobbet. **Step 5:** Commit `feat(scripts): kortværktøj pr. persona`.

### Task 9: Målinger

**Files:** Create: `maal_trin6c2.sql` (linjen fra Global Constraints; `tilstand`: `foer` = intet 6c-2,
`a` = vej B, `b` = writere + kort 122 `unresolved`, `c` = datoversioner, `d` = anvendt; `k1_bindinger_hash` = sha over alle kilde
1-bindingers id og gyldighed; med `-v liste=<fil>` skrives den nøglede liste (promotion-id, kilde, gyldig) til
`~/.private/6c2/`, så en ændret hash kan diffes pr. binding — spec §7; målt 2026-11-02: 622 gyldige bindinger, ingen
påstand med mere end én), `vejb_tid.sql` (læse-kun; tager `-v personer` og kalder fakta-kaldet som `anon` med
`\timing` 5 gange pr. person), `linjeskift_kandidater.sql` (læse-kun; præcis spec §4.4 pkt. 4's afgrænsning;
udskriver kun antal og påstands-id'er; gate: ingen kandidats `date_raw` indgår i en familie-`state_sha256`,
placement- eller publiceringstilstand — ellers `LINJESKIFT_TILSTAND_BEROERT` og ingen liste), `test_maal_trin6c2.py`.

- [ ] **Step 1-4:** test på syntetisk base (linjeformat, tilstande, at kandidatlisten udelukker delte og bundne
  påstande) → implementér → `python`. **Step 5:** Commit `feat(scripts): målinger for 6c-2`.

## Øvelse (lokalt; stand-in fra frisk prod-dump, ICU, 2 min, `ANALYZE`)

### Task 10: Vej B og hele forløbet på stand-in'en

- [ ] **Step 1: Vej B's lighed:** referencefunktionen fra Task 1 indlæses; for **alle** personer er gammel og ny
  mængde-lige. Notér de 10 tungeste personer (efter forventede 1939-bindinger: nuværende promotion-rækker + 1939-
  `MATCH`) i `~/.private/6c2/vejb-personer.txt`.
- [ ] **Step 2: Ceremoni 2:** blok 6c-2b; kort 122 → `red_afgoer_source_persona(…, 'unresolved', …)` med
  `ønsket_person_id` 1054 (persona-id fra C's kontrol); narrativet uændret publiceret.
- [ ] **Step 3: Ceremoni 3:** `red_normaliser_forslag` på alle kilde 3-datoforslag, hvor reglen ændrer værdien;
  `linjeskift_kandidater.sql` → `red_ret_paastand(…, 'linjeskift-v1', …)` på listen. Forventet: ~579 nye versioner;
  ≤ 70 rettelser; klassifikation ≈ §2.2-prognosen (MATCH ~1.025, rest-`SKRIVEMAADE` ~22). Afviger noget med > 10 %:
  stop og forklar.
- [ ] **Step 4: Ceremoni 4 som øvelse:** plan, kortark, et øvelsesark (alle stikprøvefelter `B`, øvrige `V` bortset
  fra mindst ét vellykket `B` på et `REAL_DIFF` og ét `P <id>`), apply, verify (begge kontrakter), bindinger,
  slutmåling. Derefter et ark med ét
  `D` i stikprøven → `SAMPLE_FAILED` og intet skrevet.
- [ ] **Step 5:** Mål hvert writer-/RPC-kald (omregn 27×) og hver stor læsning (3×). Over 60 s anslået: del i
  deterministiske delbatches og øv igen. `maal` efter hvert trin; `k1_bindinger_hash` uændret hele vejen.

### Task 11: Runbook og private runner

**Files:** Create: `docs/runbooks/trin6c2-prod.md` (mønster `trin6c1-prod.md`: forudsætninger, fire ceremonier,
varighed, stoppunkter, fortrydelse pr. ceremoni: 1 = gendan funktionen fra blokken på `main`; 2-4 = restore af
ceremoniens dump); privat `~/.private/5ab-overfoersel/29-trin6c2.sh` (`maal`, `vejb`, `go-1..4`, `dump`,
`apply-1..4`, `kort`, `flet`) via `lib.zsh`; GO for ceremoni 4 binder plan-, ark- og kontekstens hash.

- [ ] **Step 1:** Frisk stand-in: hele runbooken med runneren; fortrydelse af ceremoni 3 og 4 med restore → `maal`
  tilbage. **Step 2:** Commit `docs(runbooks): trin 6c-2`.

## Prod

### Task 12: Codex-diffreview og ceremoni 1 (vej B)

- [ ] **Step 1:** Codex-runde på diffen af PR 1 + PR 2 (`gpt-6.1-sol`, read-only, `--glob '!work*/**'`); Opus afvejer.
  B13's anden og sidste runde.
- [ ] **Step 2:** Projektejerens ja → push og draft-PR'er; CI grøn; merge = projektejeren. Derefter slutøvelse af
  Task 11 step 1 på `main` (merge-commit, ikke grenens head) før ceremoni 1.
- [ ] **Step 3:** `vejb` før (de 10 personer) → ceremoni 1 → resultatstikprøve i prod: gammel og ny funktion
  mængde-lige for de 10 personer + 20 tilfældige (referencefunktionen fra Task 1 i `pg_temp`, `SET LOCAL
  statement_timeout='10min'` som vej A) → `vejb` efter. Kriterium: lighed og median ≤ 1,0 s for hver af de 10. Ikke nået: **stop**; 6c-2 fortsætter ikke til ceremoni 2 (spec §4.1 pkt. 4). Projektejeren læser Security
  Advisor.

### Task 13: Ceremoni 2 og 3

- [ ] **Step 1:** Projektejeren bekræfter kort 122's `ønsket_person_id` (1054) i GO'en. Ceremoni 2 (blok 6c-2b +
  kort 122 `unresolved`) →
  `maal` `b`; Security Advisor.
- [ ] **Step 2:** Ceremoni 3 → `maal` `c`; tallene mod Task 10 step 3.

### Task 14: Ceremoni 4, læsertjek og status

- [ ] **Step 1:** Kontrol i prod → kortark (lokal HTML under `~/.private/6c2/`) → projektejerens svar → flet → hash →
  GO → anvend → efter sidste skrivning: `vejb` (≤ 1,0 s) og nøglet bindingsafstemning; brud → stop og restore af
  ceremoni 4's dump. Listen over `unresolved` med `ønsket_person_id` lægges i overleveringen til 6d.
- [ ] **Step 2:** Browsertjek som `anon` mod prod (spec §7 (b)): en 1939-person uden 2018-20-modpart; en rettet værdi;
  barnebarnet (kort 122) uden 1939-fakta bundet gennem oversigtspost B, og 1054 med bundne fakta fra sin egen post;
  de 10 tungeste.
- [ ] **Step 3:** `status.md` (1939 »Forslag og afgørelse« og promotion med dato; tjekliste (a)),
  `database-current-state.md`, `changelog.md`. Commit `docs(trin6c2): 1939-fakta bundet til bogen i prod`.

---

## Reviewlog

Spec: builder-tjek og Fable-review (NO-GO, 14 fund) afvejet i specens §9. B13's Codex-runde på spec+plan
(2026-11-02, `gpt-6.1-sol`): NO-GO, 8 fund; afvejning i specens §10. Planen rettet i Task 4-7, 10, 12-14; Task 5 er
nu en ren test (fallback (c)). Næste og sidste B13-runde er diffreviewet i Task 12.
