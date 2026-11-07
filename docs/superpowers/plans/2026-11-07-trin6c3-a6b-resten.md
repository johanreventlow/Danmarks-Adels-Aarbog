# Trin 6c-3: A6b-resten — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 2018-20's 10 A6b-poster får de manglende linjer i helpostens kildetekst og klausuler, og alle 16
kildehenvisninger, læseren ser i dag, står der igen efter én data-ceremoni — eller er trukket tilbage med
projektejerens svar, kvitteret i basen.

**Architecture:** 6a's revision (deployet) forælder 58 nøgler. Modellen genkøres på en stand-in for de 9 poster med
persona; nøglerne (`key_version 2`) er deterministiske og ens i prod. En lille generel DDL-blok (6c-3a) lader
relations-writeren genbruge en ægtefælle-persona efter tekstrevision, retter to steder, der antager én part pr. persona,
fjerner `superseded` fra #248-rivalvagten og tilføjer en append-only afstemningskvittering. Et afstemningsværktøj
matcher gamle og nye nøgler i basen (ingen værdier forlader den), afgrænser kontrolmodellen til de nye nøgler,
oversætter nøglebaserede kortsvar til prods id'er og skriver ceremoniens relations- og kvitterings-SQL.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), Python 3.11 (pytest), R (reimport-kæden `apply_reimport.R`),
codex-cli med `gpt-5.6-terra` under sandbox-gaten.

**Spec:** `docs/superpowers/specs/2026-11-07-trin6c3-a6b-resten-design.md` (godkendt 2026-11-07, §8 pkt. 1-6 ja;
rettet efter Fable-review og kortlægning, §10). Mekanismen: delspec 6a §4.4 og
`docs/evidensbaseret-genimport/kildetekst-revision-6a-bevis.md`.

## Roadmap-kobling

Spec §1: trin 6, overordnet spec §4's mål »A6b-resten«; sidste del af 6c. Færdigbevis: Task 9 Step 6 (spec §6).
Review-budget: én Codex-runde på spec+plan (før Task 1), én på diffen (Task 9); Fable-læsningen af specen er noteret
i `docs/decisions.md` 2026-11-07.

## Målt udgangspunkt

Spec §2 (stand-in `daa5ab_ddl_standin_20261107201240_c3a`, 2026-11-07): 58 nøgler/74 rækker; 16 bindinger (9
assertion, 7 family: 3 `relation.marriage`, 2 `relation.parent`, 2 `relation.child`); 13 partsrækker på 8 nøgler (den
8. er I-17's ubundne `relation.parent`); alle 7 relationers parter fra profil `relation-persona-2018-20` (v1); 3
ægtefælle-personas (I-89 ×2, III-37 ×1); ingen af de berørte personer har to accepterede personas; 0 `superseded`
fortolkninger i hele basen; 0 tekstversioner. Runnerprofil `daa-2018-20-v2` (prompt `evidence-extract-prompt-1.0.0.md`,
sha `d46cda80…`, i repoet). `relation_persona_input(1)` har 4 rækker uden for de 9 poster;
`relation_child_sheet_input(1)` har 2 eksisterende `proposed` børn uden for dem.

## Global Constraints

- Ingen tekst, navne eller værdier forlader basen i script-output; scripts printer kun antal, nøgler og hashes.
  Matchning af værdier sker i SQL (`binding_value_matches`, `saml_blanktegn_v1`), ikke i Python.
- Kun de 9 poster med persona sendes til modellen (alle `eligible` under `exclusion-2018-20-v1`); III-129 revideres,
  men genkøres ikke.
- Kortsvar og manifester refererer `interpretation_key` + version, familie-id og promotionsmål, aldrig
  `interpretation.id` (tilfældigt pr. base).
- Kontrolmodellen afgrænses til de nye nøgler på de 9 poster; ingen anden af kilde 1's forslag må afgøres eller
  bindes. Stikprøven er alle `MATCH` (`--strata-ubekraeftet 0 --strata-oevrige 20`); flere end 20 `MATCH` → stop.
- Hver af de 16 bindinger ender `genbundet` (ny nøgles gældende, accepterede version mod samme mål) eller
  `tilbagetrukket` (projektejerens svar) i afstemningskvitteringen; ingen uden udfald.
- DDL-blokken er generel: ingen udgavenavne; nye/ændrede funktioner har byte-identisk krop i `schema.sql` og
  `db-migrations.sql`; migrationen er idempotent (to kørsler).
- Ingen prod-skrivning uden GO i projektejerens shell (`--jeg-mener-det --go <kode>`); dump med B1 før hver skrivende
  ceremoni; frys fra dump til godkendt verify (også 1939 og læsere, spec §5 pkt. 5); fortrydelse af data-ceremonien
  er restore.
- Prods `statement_timeout` er 2 min; stand-in-tid er ikke prod-tid (mål forholdet).
- `~/.private` og `work*/` committes aldrig; filer med bogtekst eller værdier er 0600 i `~/.private/6c3/`.
- Implementer-briefs: ingen kommando på `~/.private`, heller ikke `ls`; drop ikke databaser, list dem; kør ikke R mod
  noget uden `R_ENVIRON_USER=/dev/null` og eksplicitte `PG*`-variabler.
- Push/PR kun efter projektejerens ja pr. gang; PR'er som kladde.

## Review Focus

1. **Modellen genfinder kun ét af I-89's to ægteskaber**, så ægteskabsnummeret i det nye sæt flytter. Forventet:
   afstemningen giver `ikke_genfundet` for det andet; det genfundne bindes kun, hvis `marriage_ordinal` og familien er
   de gamle; ellers kort. Test i Task 5 (`test_ordinal_flyttet_er_ikke_genfundet`).
2. **Genbrug af persona, når to kandidater opfylder reglen** (to forældede ægteskaber på samme post med samme
   ordinal efter en tidligere fejl). Forventet: `RELATION_PERSONA_REUSE_AMBIGUOUS`, intet skrevet. Test i Task 1.
3. **Kontrolmodellen ser andre af kilde 1's forslag** (klassifikationen er kildebred). Forventet: `afgraens` fjerner
   alt uden for nøglelisten, og en plan med et id uden for listen afvises (`AFGRAENSNING_LAEK`). Test i Task 5.
4. **Svaret er givet på stand-in'en, men prods plan afviger** (anden klasse eller version for en nøgle). Forventet:
   `oversaet` stopper med `KORT_PROD_AFVIGER`; intet SQL. Test i Task 5.
5. **Kvitteringen dækker ikke præcis revisionens mængder** (en binding mangler, en ekstra nøgle, `genbundet` mod et
   andet mål eller med en ugyldig binding). Forventet: writeren afviser med `AFSTEMNING_MAENGDE_AFVIGER` /
   `AFSTEMNING_MAAL_AFVIGER` / `AFSTEMNING_BINDING_UGYLDIG`. Test i Task 3.

---

### Før Task 1: B13's Codex-runde på spec+plan (hovedsessionen)

- [ ] Codex (`gpt-6.1-sol`, adversarial review af spec + denne plan; udeluk `work*/` i søgekommandoen). Opus afvejer
  hvert fund (nødvendig / forenkl / kendt begrænsning / afvis). Indarbejd, skriv reviewlog i spec §10 og en sektion
  nederst her. Commit `docs(6c-3): Codex-runde på spec+plan`.

### Task 0: Genmåling og værktøjstjek (hovedsessionen)

**Files:** ledger `.superpowers/sdd/2026-11-07-trin6c3/progress.md` (gitignoreret).

- [ ] **Step 1:** Projektejeren kører `koer.zsh 29-trin6c2.sh dump-kopi` og `standin <kvittering> c3b`. Forventet:
  `daa5ab_ddl_standin_<14 cifre>_c3b`. (`c3a` beholdes til sammenligning; ingen base droppes.)
- [ ] **Step 2:** På `c3b`: `source_text_revision_dependencies.sql` for de 10 → samme tal som spec §2.1; antal
  `superseded` i hele basen = 0; antal tekstversioner = 0; personas pr. post som §2.3. Afviger noget: stop og forklar.
- [ ] **Step 3:** `codex --version`; `gpt-5.6-terra` står i `~/.codex/models_cache.json`; `shasum -a 256
  .claude/skills/daa-extract/references/evidence-extract-prompt-1.0.0.md` = `d46cda80…`; klausulreglerne i
  runnerprofilen `daa-2018-20-v2` er dem, de nuværende sæt er skåret med. Mangler modellen: stop (spec §4.2).

### Task 1: Genbrug af ægtefælle-persona efter tekstrevision (blok 6c-3a)

**Files:**
- Modify: `schema.sql` — `private.write_relation_persona` (ægteskabsgrenen ca. 17450-17478),
  `private.verify_relation_persona_receipts` (ca. 18045-18110), `private.relation_derived_counts` (ca. 18113).
- Modify: `db-migrations.sql` — ny blok `-- ===== trin 6c-3a: tekstrevision og relationer =====` sidst, med hele
  kroppene (byte-identiske med `schema.sql`).
- Modify: `tests/sql/inspect-5ab-function-parity.sql` (tilføj `verify_relation_persona_receipts` og
  `relation_derived_counts`, hvis de ikke står der; ret sumkommentaren) og `.github/workflows/ci.yml:407-408`
  (forventet antal).
- Create: `tests/sql/test-relation-persona-reuse.sql` (fixtures: `tests/sql/fixtures/relation-5b.sql` og
  `t5_payload`/`t5_apply` fra `tests/sql/test-source-text-revision.sql`); kør den i ci.yml ved siden af linje 604.

**Interfaces:**
- Produces: genbrugsreglen i `write_relation_persona` (profil `relation-persona-2018-20` og senere): før
  `INSERT` af ægtefælle-personaen findes kandidater = personas med en `spouse`-part i samme forekomst på en nøgle,
  hvis gældende version er `superseded` med `decision_evidence->>'basis'='source_text_revision'`, samme
  `marriage_ordinal` som payloaden, og uden `spouse`-part på en nøgle med gældende status `proposed`/`accepted`.
  Én kandidat → partsrækken peger på den, ingen ny persona, ingen ny mention; kvitteringen får `"reused": true`.
  Ingen → som i dag. Flere → `RELATION_PERSONA_REUSE_AMBIGUOUS`. Samme indholds-id som en eksisterende persona, der
  *ikke* er kandidat → som i dag (`unique_violation` re-raises).
- `verify_relation_persona_receipts`: for `reused` kræves, at personaen findes, at dens `spouse`-mention ligger i
  samme forekomst, og at kandidatreglen holder; ellers som i dag.
- `relation_derived_counts`: `spouse_personas_reused` tælles for sig; `spouse_personas`/`mentions` tæller kun
  oprettede.

- [ ] **Step 1: Skriv testen** `test-relation-persona-reuse.sql`: fixture-post med ét ægteskab, bundet; revision
  (navnet samme sted) → ny nøgle → writer genbruger (persona-antal uændret, partsrække på ny nøgle, `reused`,
  finalize grøn); revision hvor navnet flytter (andet `post_offset`) → genbrug via reglen; to forældede ægteskaber med
  samme ordinal → `RELATION_PERSONA_REUSE_AMBIGUOUS`; uden revision (gammel nøgle `accepted`) → `unique_violation`
  som i dag; forskellig ordinal → ingen genbrug (ny persona).
- [ ] **Step 2:** Kør mod frisk skema (`psql -f schema.sql` + migrationer som CI-jobbet ved linje 604) → FAIL.
- [ ] **Step 3:** Implementér i `schema.sql` og blokken.
- [ ] **Step 4:** Testen, `tests/sql/test-relation-persona-writer.sql` og `tests/sql/test-source-text-revision.sql` →
  PASS; paritet ens på frisk og opgraderet base.
- [ ] **Step 5:** Commit `feat(db): genbrug af ægtefælle-persona efter tekstrevision (blok 6c-3a)`.

### Task 2: Én part pr. persona og #248-vagten (blok 6c-3a)

**Files:**
- Modify: `schema.sql` — `private.persona_family_context` (ca. 18153), `private.spouse_principal_person` (ca. 19093),
  `private.relation_binding_state` (linje med `ic2.status<>'rejected'`, ca. 19352); samme kroppe i blokken.
- Modify: `tests/sql/test-relation-binding.sql` (#248-afsnittet ca. 849ff) og
  `tests/sql/test-relation-persona-reuse.sql`.

**Interfaces:**
- `persona_family_context` og `spouse_principal_person`: ægtefælleparter tælles kun, når partens nøgle har gældende
  status `proposed` eller `accepted` (samme filter som `relation_persona_v3_input`, ca. 20352).
- `relation_binding_state`: rivaler med seneste status i (`rejected`,`superseded`) ignoreres.

- [ ] **Step 1: Test:** efter genbrug (Task 1's fixture) giver `persona_family_context` og `spouse_principal_person`
  samme resultat som før revisionen; `red_source_persona_detail` for personaen er ikke `context_unavailable`;
  #248-fixturen med en `superseded` rival giver ikke-NULL tilstand; med en `proposed` rival som i dag (NULL).
- [ ] **Step 2-4:** FAIL → implementér → testene + `test-relation-decision.sql` → PASS.
- [ ] **Step 5:** Commit `fix(db): én part pr. persona og #248 efter forældelse (blok 6c-3a)`.

### Task 3: Afstemningskvitteringen (blok 6c-3a)

**Files:**
- Modify: `schema.sql` og blokken — tabellen `private.text_revision_reconciliation` og
  `private.write_text_revision_reconciliation`.
- Modify: `db-verify.sql` (assert-blok 6c-3a; skabelon: `relation_reopen`'s, ca. 10404).
- Modify: paritetsfil + ci.yml-antal (tilføj writeren).
- Create: `tests/sql/test-text-revision-reconciliation.sql`; kør i ci.yml ved linje 604.

**Interfaces:**
- Tabel (mønster `private.relation_reopen`, ca. 19519): `id bigint identity`, `revision_batch_id uuid`,
  `revision_element_id text` (FK `(batch_id, element_id)` → `private.reimport_event`), `old_interpretation_key uuid NOT
  NULL`, `old_promotion_id uuid NULL` (FK `interpretation_promotion`), `outcome text` CHECK i (`genbundet`,
  `tilbagetrukket`, `aaben`, `genfundet`, `ikke_genfundet`), `new_interpretation_key uuid NULL`, `new_promotion_id
  uuid NULL` (FK), `context jsonb NOT NULL` (objekt), `decided_by uuid NOT NULL`, `decided_by_name text NOT NULL`,
  `created_at`; UNIQUE `(old_interpretation_key, old_promotion_id) NULLS NOT DISTINCT`; append-only- og
  no-truncate-triggere med `private.reject_evidence_mutation()`; RLS; REVOKE fra PUBLIC/anon/authenticated/
  service_role.
- `private.write_text_revision_reconciliation(p_revision_batch_id uuid, p_items jsonb, p_context jsonb) RETURNS
  jsonb` (SECURITY DEFINER, `search_path=pg_catalog,public,private`, REVOKE fra alle). Aktør fra
  `request.jwt.claim.sub` + `profiles` (som `red_*`). Regler:
  1. Batchens events er `source_text_revision`; mængden af nøgler, de forældede, og mængden af `binding_loss`-
     promotions læses fra event-payloaden (feltnavnene læses i `write_source_text_revision` før testen skrives).
  2. `p_items` dækker hver forældet nøgle præcis én gang uden promotion (`genfundet`/`ikke_genfundet`) og hver
     `binding_loss`-promotion præcis én gang (`genbundet`/`tilbagetrukket`/`aaben`); ellers
     `AFSTEMNING_MAENGDE_AFVIGER`.
  3. `genbundet`: `new_promotion_id` har samme `target_type` og `target_id` som den gamle
     (`AFSTEMNING_MAAL_AFVIGER`) og er gyldig nu (assertion: `assertion_binding_current`; family: prædikatet fra
     `public_family_sources`/`text_revision_binding_set`) (`AFSTEMNING_BINDING_UGYLDIG`).
  4. `tilbagetrukket`/`aaben` kræver `p_context` med `svar_sha256` (hex64) og `ref` pr. item
     (`AFSTEMNING_SVAR_MANGLER`).
  5. Returnerer `{genbundet, tilbagetrukket, aaben, genfundet, ikke_genfundet}` som antal.

- [ ] **Step 1: Test** med en revideret fixture (Task 1's): fuld, korrekt kvittering → antal; manglende binding,
  ekstra nøgle, forkert mål, ugyldig binding og manglende svar → hver sin kode; UPDATE/DELETE/TRUNCATE afvist;
  `authenticated` kan ikke kalde writeren.
- [ ] **Step 2-4:** FAIL → implementér (+ `db-verify.sql`) → PASS; paritet; migrationen to gange på opgraderet base
  (`tests/sql/test-248-upgrade.sh`-mønsteret).
- [ ] **Step 5:** Commit `feat(db): append-only afstemningskvittering for tekstrevision (blok 6c-3a)`.

### Task 4: Ark for forældre og afgrænsede børn; udvalg pr. post

**Files:**
- Create: `.claude/skills/daa-extract/scripts/relation_parent_sheet.py`, `relation_parent_rows.sql` (læse-kun:
  nøgle, version, principal-persona, familie-kandidat fra `relation_structural_candidates`; ingen navne i stdout),
  `test_relation_parent_sheet.py`.
- Modify: `relation_child_sheet.py` (`--interpretation-keys <fil>` på `render` og `sql`) og
  `test_relation_child_sheet.py`.
- Modify: `build_eligible_selection.py` (`--records <fil>`; kun `eligible` records tages med, ellers
  `SELECTION_RECORD_NOT_ELIGIBLE`) og dens test.
- Modify: ci.yml pytest-linjen.

**Interfaces:**
- `relation_parent_sheet.py render --rows --interpretation-keys --out` og `sql --rows --sheet --approved-sha256
  --out`: svar B/R/U pr. linje som børnearket; B → `red_afgoer_relation_interpretation(key, version, 'same',
  <familie>, note, {basis:'human_sheet', sheet_sha256, rows_sha256, line})`, R → `'rejected'`, U → intet. Familie =
  den eneste kandidat; ingen eller flere → linjen kan ikke få B (`PARENT_FAMILY_NOT_UNIQUE`). Hjælpere importeres fra
  `relation_child_sheet.py` (ingen kopi).
- Børnearket: med `--interpretation-keys` indeholder ark og SQL kun de nøgler; `rows_sha256` beregnes over de valgte
  rækker; ukendt nøgle → `CHILD_KEY_UNKNOWN`. Børn kaldes med `p_family_id NULL`.

- [ ] **Step 1: Test** (syntetisk): forælderark round-trip med hardkodet sha; B uden entydig familie afvist; børnearkets
  afgrænsning udelader rækker uden for listen; `--records` med en `excluded` record afvist.
- [ ] **Step 2-4:** FAIL → implementér → `python`-jobbet. **Step 5:** Commit
  `feat(scripts): forælderark og afgrænsede relationsark`.

### Task 5: Afstemningsværktøjet

**Files:**
- Create: `.claude/skills/daa-extract/scripts/tekstrevision_afstemning.sql` (læse-kun; `-v batch=<revisionens
  batch_id>`: pr. forældet nøgle og pr. ny nøgle på samme poster: nøgle, version, status, prædikat, persona,
  modpart-persona, `marriage_ordinal`, `binding_loss`-promotion og mål; matchen gammel→ny beregnes her: fakta =
  samme persona + prædikat og `binding_value_matches(regelens value_kind, ny værdi, målpåstandens vaerdi_tekst,
  date_raw)` mod den gamle bindings påstand, ellers lighed af `saml_blanktegn_v1(værdi)`; relationer = samme
  prædikat, principal, modpart og `marriage_ordinal`. Udskriver kun nøgler, udfald og hashes).
- Create: `tekstrevision_afstemning.py` med kommandoerne nedenfor og `test_tekstrevision_afstemning.py`.
- Modify: ci.yml pytest-linjen.

**Interfaces:**
- `afgraens --noegler <fil> --classification <fil> --rows <fil> --out-dir`: kontrolmodellens klassifikation og rækker
  beskåret til nøglelisten med genberegnede antal; `plan_run_v2` skal acceptere output (test); et id uden for listen
  i input efter beskæring → `AFGRAENSNING_LAEK`.
- `kortsvar --plan-dir <c3b-plan> --ark <ark v2> --idkort <fil> --out <svar.json>`: ark v2's `F <id> <ver>`-linjer
  oversat til `{interpretation_key, version, svar, note}` via stand-in'ens id→nøgle-kort
  (`SELECT id, interpretation_key, version` i læse-kun SQL).
- `oversaet --svar <svar.json> --plan-dir <prod-plan> --idkort <prod-idkort> --out <ark>`: nøglebaserede svar → ark
  v2 med prods id'er; prods plan skal have samme nøgler, versioner og klasser som svarene (ellers
  `KORT_PROD_AFVIGER`).
- `relationer-sql --afstemning <json> --svar <relationssvar.json> --out <sql>`: ægteskaber: preview-mængden skal være
  lig de forventede nye ægteskabsnøgler (`AEGTESKAB_MAENGDE_AFVIGER`) → `red_decide_relation_interpretations`;
  derefter `red_preview_relation_promotions` → `red_promote_relation_interpretations_batch` for alle genfundne
  relationer mod den gamle bindings familie. Forældre/børn-afgørelserne kommer fra Task 4's SQL.
- `tilbagetraek-ark --afstemning <json> --out <fil>`: token-fil (memory: token-fil) med én linje pr. binding uden
  genfundet nøgle: `T <ref> : T|V  # post, prædikat` (ref = gammel nøgle + promotion-mål, ingen værdier); `parse`
  afviser ubesvarede linjer og ukendte refs (`TILBAGETRAEK_LINJE_UGYLDIG`). HTML-konteksten (posttekst, side) bygges
  lokalt i `~/.private/6c3/` som 6c-2's kort.
- `kvittering-sql --afstemning <json> --svar <alle svar> --out <sql>`: ét kald til
  `private.write_text_revision_reconciliation` med alle items; `genbundet` slår `new_promotion_id` op i
  transaktionen (nøgle + mål), ingen id'er i filen.

- [ ] **Step 1: Test** (syntetisk JSON, ingen DB): `test_ordinal_flyttet_er_ikke_genfundet`,
  `test_afgraens_fjerner_andre_noegler` og `AFGRAENSNING_LAEK`, `test_kortsvar_oversaet_roundtrip` (stand-in-id'er →
  nøgler → prod-id'er giver samme ark modulo id'er), `KORT_PROD_AFVIGER` ved anden klasse, `relationer-sql`
  med forkert ægteskabsmængde → `AEGTESKAB_MAENGDE_AFVIGER`, kvitterings-SQL dækker hver binding præcis én gang.
- [ ] **Step 2-4:** FAIL → implementér → `python`-jobbet + `test_clause_readers.py` (repo-vide vagt; tilføj de nye
  filer til ALLOWED med begrundelse, hvis den kræver det).
- [ ] **Step 5:** Commit `feat(scripts): afstemning efter kildetekst-revision`.

### Task 6: PR 1 (DB) og PR 2 (scripts) samlet

- [ ] **Step 1:** Hele CI-jobbene lokalt (node springes over; r, python, de fire PostgreSQL-jobs), ikke kun nye
  testfiler (memory: kør hele CI-jobbet lokalt). Paritet 47 + nye.
- [ ] **Step 2:** `get_advisors`-ækvivalent: statisk grant-gennemgang af blokken (ingen EXECUTE for anon/authenticated
  på nye private funktioner; tabellen uden grants).
- [ ] **Step 3:** Projektejerens ja → push og to kladde-PR'er (DB, scripts). PR 1 merges før data-ceremonien.

### Task 7: Hele kæden på stand-in'en med rigtige kort (hovedsessionen)

Under `~/.private/6c3/` (0700). Base: `c3b` + blok 6c-3a (`db-migrations.sql` ×2 + `db-rls.sql`), ICU, 2 min,
`ANALYZE`.

- [ ] **Step 1: Revision:** `build_source_text_revision_manifest.py` (profil
  `daa-2018-20-source-text-revision-v1`) → 10 operationer, `dispositions` = `[I-84: span_outside]` (I-84 er ikke i
  afhængighedsfilen; manifestet bygges fra de 11 kandidater som i 6a) → `apply_reimport.R` dry-run → authorize
  (`service_role`) → apply → replay `already_applied`. Forventet som 6a-beviset: 58 `superseded`, 10 tekstversioner,
  `binding_loss` = de 16, narrativ-hashene uændrede.
- [ ] **Step 2: Model:** ledger (`export_model_eligibility.R --policy exclusion-2018-20-v1`), runner-input,
  `build_eligible_selection.py --records <9 poster>`, `build_43b_manifest.py --profile-id daa-2018-20-v2 --dagsvaerk
  6c-3`, `gate-access-test.sh`, `run_evidence_43b.py` (`gpt-5.6-terra`). Gaten som 6c-1 Task 8 Step 2; rapport kun
  med tal i `docs/evidensbaseret-genimport/runner-6c3-koersel.md`.
- [ ] **Step 3: Forslag:** `build_43b_proposal_manifest.py --profile
  .claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json --cache-key
  current --expect-runner-manifest-sha256 <sha>` → R-kæden. Alle nye nøgler `key_version 2`. Notér forventningen
  (elementer, claims pr. prædikat) før kørslen.
- [ ] **Step 4: Parter:** `relation_persona_input.sql` → `relation_persona_extract.py` (v1) → manifest filtreret til
  de nye nøgler på de 9 poster → `relation_persona_apply.sql`. Forventet: 3 genbrugte ægtefælle-personas, 0 nye.
- [ ] **Step 5: Afstemning og kort:** `tekstrevision_afstemning.sql` → udfald pr. nøgle; kontrolmodel
  (`interpretation_control_classification.sql`/`interpretation_control_rows.sql` med kilde 1) → `afgraens` →
  `control_model_v2.py plan --source-id 1 --strata-ubekraeftet 0 --strata-oevrige 20` → `persona_kort.py html`;
  børneark og forælderark afgrænset; ikke-genfundne bindinger som kort med T/V (tilbagetræk / ved ikke).
  Over 30 punkter: stop. **Projektejeren svarer** i browseren; `persona_kort.py flet` → `kortsvar`; relationsarkene
  gemmes som de er. Svarfilerne hashes ved godkendelse (memory: hash-bind).
- [ ] **Step 6: Afgørelser og bindinger på `c3b`:** `control_model_v2.py sql` (ark fra `oversaet` mod `c3b` selv,
  som round-trip-prøve) → forælder-/børne-SQL → `relationer-sql` → `kvittering-sql`. Forventet: kvitteringen dækker
  58 nøgler og 16 bindinger; `public_person_facts`/`public_family_sources` for de berørte som før revisionen (bortset
  fra tilbagetrukne); narrativ-hashene uændrede; anden kilde 1-forslag uændret (`k1_bindinger_hash` fra
  `maal_trin6c2.sql` ens før og efter, bortset fra de 16 → nye).
- [ ] **Step 7: Generalprøve på frisk stand-in `c3c`** (fra samme dump + blokken): hele data-ceremonien med
  runneren (Task 8) og de rigtige svar, uden modelkald (forslagsmanifestet genbruges). Mål vinduet fra revisionens
  commit til genbindingens commit og hvert statement; `fortryd` (restore) → tilstand før. Fejl → spec tilbage til
  projektejeren.

### Task 8: Runner, runbook og decisions (hovedsessionen)

**Files:** privat `~/.private/5ab-overfoersel/32-trin6c3.sh` (via `lib.zsh`/`koer.zsh`): `maal`, `dump`, `go-ddl`,
`apply-ddl`, `fortryd-ddl`, `go-data`, `apply-data`, `verify`, `go-fortryd`, `fortryd`; GO for data binder
revisionsmanifest, afhængighedsfil, forslagsmanifest, partsmanifest, svarfiler (fakta, børn, forældre,
tilbagetrækninger) og commit. `apply-data` kører: revision (R-kæden) → forslag (R-kæden, samme manifest som `c3b`) →
parter → klassifikation i prod → `afgraens` → `plan` → `oversaet` (stop ved `KORT_PROD_AFVIGER`) →
`control_model_v2.py sql` → forælder-/børne-SQL → `relationer-sql` → `kvittering-sql` → måling efter; hvert trin
stopper ceremonien ved fejl, og trinnene efter revisionen kan genoptages uden at revidere igen.
`docs/runbooks/trin6c3-prod.md` (mønster `trin6m-del2-prod.md`: rækkefølge,
forventede linjer, vindue og frys, stoppunkter, fortrydelse). `docs/decisions.md`: BESLUTTET 2026-11-07 — 6c-3's
afgrænsning og §8 pkt. 1-6, herunder `BEGGE` flyttet fra 6c-3 til opret-benet/6e.
Præcise allow-regler i `.claude/settings.local.json` for `maal`, `dump`, `go-*`, `verify` (memory: runner-allowlist),
efter projektejerens ja.

- [ ] **Step 1:** Runner + runbook; øvet i Task 7 Step 7. **Step 2:** Commit `docs(runbooks): trin 6c-3` og
  `docs(decisions): 6c-3 afgrænset, BEGGE flyttet`.

### Task 9: Codex-diffreview, prod og status

- [ ] **Step 1:** B13's anden Codex-runde på hele diffen; Opus afvejer; rettelser i nye commits.
- [ ] **Step 2:** PR 1 og PR 2 merget (projektejeren). `main` rent i hovedcheckouten.
- [ ] **Step 3: DDL-ceremonien:** `maal` → `dump` → `go-ddl` → projektejeren `apply-ddl --jeg-mener-det --go <kode>` →
  `NOTIFY pgrst` → advisors/grant-gennemgang.
- [ ] **Step 4: Data-ceremonien:** genmål (afhængighedsfil = den bundne; ellers stop) → `dump` (B1: to kopier, hash i
  `database-current-state.md`) → `go-data` → projektejeren `apply-data --jeg-mener-det --go <kode>` → `verify`.
- [ ] **Step 5:** Tre stikprøver som anon i læserfladen: et genbundet faktum (»DAA 2018-20 · <post>«) og en genbundet
  familie med kildelinje.
- [ ] **Step 6: Færdigbevis** (spec §6) i `docs/evidensbaseret-genimport/kildetekst-revision-6c3-prod.md` (kun antal
  og nøgler): tekst og klausuler; kvitteringens 58 + 16; ingen nye ægtefælle-personas; narrativ-hashene; læseren.
  `status.md` (rækken »Kildetekst-revision« for 2018-20 → `produktionsverificeret`; aktivt programmål → 6d),
  `database-current-state.md` (ny §), `changelog.md`, decisions 2026-10-28 pkt. 3's kendte følge omformuleret.
  Commit og docs-PR som kladde.

## Efter planen

- Oprydning af `c3a`, `c3b`, `c3c` kun efter måling og projektejerens ja.
- Næste delspec: 6d.
