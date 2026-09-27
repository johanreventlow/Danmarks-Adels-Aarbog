# Trin 4 · omsegmentering af klausulsæt + S4 — implementeringsplan

**Goal:** Byg den generelle writer-operation `clause_revision` og S4-rettelsen fra spec'en, bevis
dem i en rehearsal mod et frisk prod-dump og gør prod-kørslen for 2018-20's 51 poster GO-klar.

**Spec:** `docs/superpowers/specs/2026-09-27-trin4-omsegmentering-og-s4-design.md` (rev. 3, GO
2026-09-27). **Beslutning:** `decisions.md` 2026-09-27 (skridt 3-4). **Review-budget:** DDL ⇒ 2 + 2;
planrunderne er brugt på spec'en, så de to resterende er koderunder (Task 6). Codex bruges ikke
(review 35, P1).

## Kobling (CLAUDE.md-styringen)

| | |
| --- | --- |
| Roadmapmål | Trin 4 (#147/#148) |
| Værdikædeled | Klausullaget → proposed-ingest |
| Leverancetype | Generel writer-operation + rettelse af den generelle forslagswriter |
| Redaktionel værdi | 51 poster med rettede klausuler/flag, før modellen og redaktøren læser dem |
| Færdigbevis | Rehearsal mod frisk prod-dump: 51 revideret, projektion `match`, kanonisk delta 0, `anon` uændret, fortrydelse og frem igen |
| Erstatter | Restore som eneste vej til at rette klausuler |

## Global Constraints

- **Ingen prod i denne plan.** Prod-kørslen er en separat GO-pakke efter rehearsal (Task 7).
- **Invarianter i nye triggerfunktioner** (spec §3.4). Før et navn vælges: `grep -c '<navn>'
  db-migrations.sql schema.sql` = 0. Den nye blok står **sidst** i `db-migrations.sql`.
  `validate_clause_observation`, `validate_clause_disposition` og de eksisterende writere må få
  ekstra kontroller, men ingen invariant må *kun* ligge dér.
- **Negative asserts** i tests og `db-verify.sql` bruger formen `IF v_error IS NULL OR v_error NOT
  LIKE …` (review 35, S1 er ikke rettet; tilføj ikke flere blinde tests).
- **`ORDER BY … COLLATE "C"`** i alt, der hasher eller sammenligner ordnede rækker (CI kører en_US).
- **ACL:** REVOKE navngiver rollerne (`anon`, `authenticated`, `PUBLIC`); nye `red_*` på vagtens liste.
- **Ingen kildetekst** i repo, logs, commits eller chat. Rigtige data kun i `~/.private/omseg-*/`
  (0700/0600); tal og hashes må ud.
- **Testbaser** hedder `daa_omseg_<stamp>_<formål>`; de ryddes målt i Task 8.
- **Lokal gate før push:** frisk base bygget som CI (bootstrap → schema → rls → migrations ×2 → rls)
  + SQL-testene, `env -u NODE_OPTIONS /usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts`,
  `Rscript run-tests.R`. Nye testfiler i `ci.yml`'s lister (P6: stadig navnelister). Mellem-push
  med `[skip ci]`; ét CI-løb pr. PR.
- R-scripts mod lokale baser: `env -u PGPASSWORD PGHOST=/tmp PGPORT=5432 PGUSER=$USER
  PGDATABASE=<db> Rscript --vanilla` (aldrig `~/.Renviron`s prod-værdier).

## Tasks

Hver task: test først (rød), implementering (grøn), lokal gate, ét commit. Gren
`feat/147-omsegmentering` fra `main` efter #221.

### Task 1: DDL — kolonne, indeks, sæt-hash, view, triggere

**Files:** `schema.sql`, `db-migrations.sql` (ny sidste blok), `db-rls.sql`,
`tests/sql/test-clause-set.sql` (ny), `ci.yml`.

- [ ] Navnetjek: `trg_source_observation_clause_set`, `trg_clause_set_density`,
  `trg_clause_disposition_set_rule`, `trg_interpretation_observation_current_clause`, deres
  funktioner, `clause_observation_current`, `clause_set_sha256` → 0 forekomster før.
- [ ] `clause_set_seq integer CHECK (>= 1)`, nullable, **uden default**.
- [ ] Indeksskift i ét `DO`-blok: byg `(parent_observation_id, coalesce(clause_set_seq,1),
  clause_ordinal) WHERE parent_observation_id IS NOT NULL` under midlertidigt navn, drop
  `ux_source_observation_clause_ordinal`, omdøb; kun når den eksisterende definition mangler
  `clause_set_seq`.
- [ ] `trg_source_observation_clause_set` (BEFORE INSERT): ikke-klausul ⇒ `clause_set_seq IS NULL`;
  ny klausul ⇒ `NOT NULL` og `= coalesce(max,0)+1` (max over `coalesce(seq,1)`) eller `= max` med
  samme `extraction_run_id` som sættets eksisterende rækker.
- [ ] `trg_clause_set_density`: udskudt constraint-trigger; ordinaler `1..n` tætte pr. sæt.
- [ ] `private.clause_set_sha256(parent uuid, seq int)` efter spec §3.1 (kanonisk JSON via
  `interpretation_proposal_canonical_json_text`, flag sorteret og uden dubletter).
- [ ] View `private.clause_observation_current` (`security_invoker`), højeste `coalesce(seq,1)`.
- [ ] Vokabular `clause_disposition_machine/erstattet`; `trg_clause_disposition_set_rule`
  (BEFORE INSERT): `erstattet` kun uden for det aktuelle sæt og kun én gang; alt andet kun inden
  for; intet efter `erstattet`.
- [ ] `trg_interpretation_observation_current_clause` (BEFORE INSERT): afvis et link til en
  klausul uden for det aktuelle sæt; andre observationstyper passerer urørt. (I pilotbasen er alle
  498 links klausuler — 243 forslag × deres afgjorte versioner, fordi `red_decide_interpretation`
  kopierer links til den nye version. Det kolliderer ikke, fordi en revision afvises, så længe en
  fortolkning citerer sættet.)
- [ ] `reimport_event_operation_check` + `clause_revision` via den eksisterende union-hjælper.
- [ ] Tests mod (a) en frisk CI-base og (b) en kopi `createdb -T daa43b_20260912192527
  daa_omseg_<stamp>_ddl` (868 klausuler med `NULL` seq). På begge: kør `db-migrations.sql` to gange
  og tjek, at `pg_indexes` og `pg_get_functiondef` stadig viser den nye tilstand. Assert direkte:
  en klausulrække uden `clause_set_seq` (sådan en gammel writerkrop ville skrive) afvises; en
  ikke-klausul med seq afvises; et sæt 2 med hul i ordinalerne afvises ved commit; `erstattet` i det
  aktuelle sæt afvises.

### Task 2: `write_clause_revision` + RPC + operationens rør

**Files:** `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql`,
`tests/sql/test-clause-revision.sql` (ny), `apply_reimport_helpers.R`,
`tests/testthat/test-apply-reimport.R`, `reimport_profile.py` (+ test),
`tests/sql/inspect-reimport-writer-catalog.sql`, `ci.yml`.

- [ ] Fælles hjælpefunktion for autorisation/lås/anker/rendition/forælder, brugt af både
  `write_clause_evidence` (som nu skriver `clause_set_seq = 1` eksplicit) og
  `write_clause_revision`.
- [ ] `write_clause_revision` efter spec §3.2: lås `source_record`, helpost, det aktuelle sæts
  rækker `FOR UPDATE`; afvis `CLAUSE_REVISION_BASE_DRIFT`, `…_HAS_INTERPRETATIONS`,
  `…_HAS_HUMAN_DISPOSITION`, `…_NOOP`; skriv nyt sæt + startdispositioner, `erstattet` på det
  gamle, `reimport_event` med før/efter-hash; `SET CONSTRAINTS … IMMEDIATE` til sidst.
- [ ] `public.red_apply_reimport_clause_revision` + ACL + `red_*`-vagtens liste.
- [ ] Rørene fra spec §3.6: `validate_reimport_authorization_payload` (nøgle, antal 2-6, præfiks,
  optælling), `red_finalize_reimport`, `red_reimport_batch_result` (inkl. `event.operation IN`),
  REVOKE-lister i `schema.sql` og `db-rls.sql`.
- [ ] `reimport_profile.py`: profilskema `reimport-clause-revision-profile-v1` + validator.
- [ ] `apply_reimport_helpers.R`: tællenøgle `clause_revisions`, `dependency_class`, dry-run/apply.
- [ ] Tests: én pr. afvisningskode; en ren flag-ændring er *ikke* `NOOP`; fortrydelse via en anden
  revision (sæt 3 = sæt 1's spans) og frem igen (sæt 4); `erstattet` er terminal; dry-run efterlader
  intet. Negativ på rigtige data i en daa43b-kopi: dens 84 forslag får `HAS_INTERPRETATIONS` til at
  fyre for de berørte poster (tal i rapporten, ingen tekst).

### Task 3: S4 og sæt-filter i forslagswriteren

**Files:** `schema.sql`, `db-migrations.sql`, `db-verify.sql`,
`tests/sql/test-interpretation-proposal-s4.sql` (ny), `ci.yml`.

- [ ] Dublet-tjek på tværs af batches **i samme kilde** (join `reimport_batch.source_id`).
- [ ] Ordinal-opslag og FOREIGN_POST-sonden via `clause_observation_current`.
- [ ] `db-verify.sql`: den aktive `write_interpretation_proposal` indeholder
  `clause_observation_current`, og den aktive `write_clause_evidence` indeholder `clause_set_seq`
  (mønster som `db-verify.sql:261`).
- [ ] Tests: andet batch for samme post ⇒ `…_PROPOSAL_EXISTS`; samme `record_key` i en anden kilde
  ⇒ tilladt; citat af en ordinal, der kun findes i det afløste sæt ⇒ `…_CLAUSE_UNKNOWN`; rå INSERT i
  `interpretation_observation` mod en erstattet klausul ⇒ triggeren afviser.

### Task 4: Læserne + den statiske vagt

**Files:** læserne i spec §3.5, `.claude/skills/daa-extract/scripts/test_clause_readers.py` (ny;
pytest-mappen, der allerede kører i CI), `ci.yml`.

- [ ] Hver læser går via `clause_observation_current` eller filtrerer eksplicit på sættet.
- [ ] Statisk test: regex `observation_kind\s*=\s*'clause'`, `parent_observation_id`,
  `clause_ordinal` uden for en smal tilladelsesliste (view, writere, triggere, projektioner,
  `db-verify.sql`, migrationsfilen) ⇒ fejl.
- [ ] Fixture med to sæt for én post: hver SQL-læser returnerer kun det aktuelle.

### Task 5: Builder, projektion, komparator og revisionsprofil

**Files:** `build_clause_evidence_manifest.py` (+ test), `clause_evidence_projection.sql`,
`compare_clause_evidence_projection.py` (+ test), `compare_interpretation_proposal_projection.py`
(tællenøgler), ny `references/reimport-profiles/daa-2018-20-clause-revision-v1.json`,
`tests/fixtures/clause-set-sha256.json` (ny).

- [ ] `clause_set_sha256` i Python med parametrene fra spec §3.1. **Paritetslås:** én fixture med
  en fastlåst hash, som både SQL-testen (Task 1) og Python-testen asserter mod.
- [ ] Builder i `revision`-tilstand: tager kun poster, hvis sæt-hash ændres; læser gammelt seq og hash
  fra projektionen; `expected_counts.clause_revisions`.
- [ ] Projektionen: `clause_set_seq` og `clause_set_sha256` pr. klausul; events for både
  `clause_evidence` og `clause_revision`.
- [ ] Komparatoren i revisionstilstand (spec §3.7): gammelt sæt uændret + én ny version `erstattet`;
  nyt sæt = manifestet med version 1; event `clause_revision` med før/efter-hash; alt andet uændret.
- [ ] Revisionsprofilen: regler `clause-rules-2018-20-v3`, afledt `segmenter_version`,
  `observation_extraction_method = clause_segment_v1`.
- [ ] Mål mod prod-teksterne (privat, kun tal): builderen udvælger præcis 51 poster (42 spans + 9
  flag).

### Task 6: Kodereview

- [ ] **R1** (opus-agent, ikke Codex): hele diffen, når Task 1-5 er grønne lokalt. Fund efterprøves
  i koden før rettelse.
- [ ] **R2** (smal): kun rettede fund og den kode, rettelserne ændrede. Efter budgettet tæller kun
  fund, hvor noget kan skrives forkert.
- [ ] Push, draft-PR, ét CI-løb.

### Task 7: Rehearsal mod et frisk prod-dump og GO-pakke

Alle dumps under `~/.private` er ældre end hærdningen 19.-20/9, og Supabase-MCP'en peger på et
andet projekt. **Dumpet tages derfor af projektejeren** med et script, jeg lægger i
`~/.private/omseg-rehearsal/` og som køres med `! zsh …`.

- [ ] Restore til `daa_omseg_<stamp>_rehearsal`; tjek 591 poster, 868 klausuler, 0 fortolkninger.
- [ ] DDL (Task 1-3's migration) → før-snapshot (**efter** DDL'en, spec §3.7) → dry-run → apply
  (51) → projektion `match` → kanonisk delta 0 → `anon` uændret (8 hashes) → fortrydelses-revision
  → frem igen → projektion `match`.
- [ ] Runbook `docs/runbooks/clause-revision-prod-apply.md` efter 4.1c's mønster (skrivepause,
  backup, preflight inkl. `db-verify`-tjekket fra Task 3, apply, verify).
- [ ] Rapport `docs/evidensbaseret-genimport/omsegmentering-rehearsal-2018-20.md` (tal og
  hashes), status og changelog. Prod-kørslen kræver projektejerens GO.

### Task 8: Oprydning (målt)

- [ ] List `daa_omseg_*`-baserne med størrelse og formål og `~/.private/omseg-*` med indhold. Vis det
  til projektejeren sammen med sletteforespørgslen; slet først efter ja.

## Efter denne plan

- Prod-kørslen af revisionen (egen GO) og `get_advisors` mod det rigtige projekt efter DDL'en.
- Piloten om for alle 32 poster (cachen er kontrakt 1.0) og kontrolmodellen på de nye forslag.
- 4.4's GO-pakke bindes igen (nyt dump, rehearsal — rækkehashes ændres af DDL'en).
- Trin 6: genudtræk af poster med forslag (`superseded`-beslutning, forslagsnøgle version 2).
