# Trin 6d-2a: oversigtsreglen og 1939's resterende identitetssager — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En 1939-oversigtsomtale leveres ikke længere som biografi for en person, der har sin egen detaljepost —
automatisk og reversibelt ved enhver ændring — `samme_som` får sin retning fra data, og 1014's kobling samt tre
oversigtspersonas' identitet afgøres.

**Architecture:**
- **Afledt markering (DDL):** privat tabel `private.overview_mention` med en fuld genberegningsfunktion og
  sætningsniveau-triggere på de tabeller, der ændrer reglens indgange. Ingen skrivning til narrativ, binding eller
  publiceringshændelser.
- **Én læser:** `public.public_person_bio_source_versions_v2` udelader narrativer i markeringen. Det er det eneste kald,
  der leverer 1939-biografitekst under kontrakt v2 (`web/src/data/public.ts:231-246`, `mobile/src/data/load.ts:283`);
  faktalæserne og hændelserne bruger den fælles vagt og røres ikke.
- **Retning:** `public.red_samme_som` vender kanten, når data kan afgøre den, og falder tilbage til redaktørens retning,
  hvis G3/G4 (`schema.sql:7495-7504`) ville afvise.
- **Prod:** én DDL- og én data-ceremoni gennem en privat runner efter 6d-1's mønster.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), TypeScript/React (web, vitest), bash/zsh (opgraderingstest, runner).

**Spec:** `docs/superpowers/specs/2026-11-09-trin6d2a-oversigtsregel-identitet-design.md` (godkendt rev. 3,
2026-11-09). Beslutning: `docs/decisions.md` 2026-11-09 »6d-2 deles i 6d-2a og 6d-2b«.

## Roadmap-kobling

Spec §1: trin 6, færdigbevis (a) — hvilke 1939-tekster læseren tilbydes som biografi. Værdikædeled: identitet på tværs
af personrækker → biografilæser. Erstatter visningen af oversigtsomtaler som biografi og de tre åbne
oversigtsidentiteter. Færdigbevis: Task 8 trin 4 (spec §8). Review-budget: én Codex-runde (`gpt-6.1-sol`) på
spec+plan (Task 0 trin 5), én på diffen (Task 8 trin 1); Opus afvejer hvert fund.

## Global Constraints

- **Gren:** `feat/trin6d2a` fra `docs/trin6d2-spec`. PR'er altid `--draft`. Intet push uden projektejerens ja.
- **Prod** røres kun i projektejerens shell med GO (`--jeg-mener-det --go <kode>`); AI'en kører kun mod lokale baser.
  Dump med ekstern kopi før hver skrivende ceremoni; vinduesvagt; fortryd = restore + `db-rls.sql`.
- **`schema.sql` er source of truth.** `db-migrations.sql` får én ny blok sidst, der begynder med
  `-- ===== trin 6d-2a: oversigtsomtaler og samme_som-retning =====`; ændrede/nye funktioner har byte-ens krop i begge
  filer; idempotent (to kørsler). Ældre blokke redigeres ikke.
- **Ingen editionsnavngiven permanent overflade:** markering, funktioner og triggere er kildeparametriserede; ingen
  udgavenavne eller kilde-id'er i logikken.
- **Reglen (spec §4.1, ordret):** *P*'s kilde-*K*-narrativ er en oversigtsomtale, når *P* ikke har et gældende
  linjemedlemskab med `source_basis.source_id = K` (`private.membership_is_current`), og *P*'s komponent (kun
  `samme_som` med `afklaret` konklusion, uanset retning) indeholder en anden person *Q*, der har et, er offentlig
  (`public.person_offentlig`) og har en *K*-narrativ, der ikke selv er en oversigtsomtale, og som
  `person_daa_narrative_publication_allowed` tillader.
- **Uberørte:** `public_person_facts`, `public_family_sources`, `haendelse`-politikken, narrativ-RLS,
  `person_daa_narrative_publication_allowed`, 2018-20's data og koordinater, 6d-1's 528 placements og medlemskaber.
- **Tidsbudget (spec §4.1):** ingen anon-læser mere end 10 % langsommere end før DDL'en; alle under 3 s med margen.
- **Indholds-id'er:** ark og ceremoni refererer person-id'er og record keys, der findes i prod før ceremonien, og
  kortsvarenes hash; aldrig id'er oprettet af en ceremoni.
- **PII (invariant 8):** kortenes tekst (1939, alle afdøde) må vises for projektejeren; kort, token og målinger kun
  under `~/.private/6d2a/` (0600). Tests bruger opdigtede personer med negative id'er. Chat og commits: tal, nøgler,
  hashes.
- **Miljø:** `env -u PGOPTIONS` foran psql, `env -u NODE_OPTIONS` foran npm. Prods `statement_timeout` er 2 min.
- **Implementer-briefs:** ingen kommando på `~/.private`, heller ikke `ls`; drop ikke databaser, list dem.
- **Commits:** atomiske, Conventional Commits på dansk, ingen Claude-attribution; trailer
  `Claude-Session: https://claude.ai/code/session_01VptDwzGMfPB2hEdCGkchPr`.

## Review Focus

1. **Detaljepersonen *Q* er ikke offentlig eller har ingen synlig tekst.** *P*'s tekst skal stå (ellers forsvinder den
   eneste tekst). Låses af `$q_ikke_offentlig$` og `$q_uden_tekst$` i Task 1.
2. **Et medlemskab bliver ugældende** (identitet omafgjort) eller trækkes tilbage. Markeringen skal slippe *P* i samme
   transaktion. Låses af `$medlemskab_ugaeldende$` i Task 1.
3. **`red_samme_som` indsætter relationen før den afklarede konklusion** (`schema.sql:7566-7576`). Markeringen må først
   tælle kanten, når konklusionen er `afklaret`, og skal se den, når den bliver det. Låses af `$konklusion_senere$` i
   Task 1.
4. **En oversigtsperson, der allerede er alias for en 2018-20-person** (G3-tilfældet). Retningsreglen må ikke give en
   fejl, hvor redaktørens retning ville lykkes. Låses af `$g3_fallback$` i Task 3.
5. **Feedet kalder biografilæseren med alle modellens personer** (`web/src/data/feedAux.ts:47-79`). Markeringsopslaget
   må ikke gøre det kald langsommere end budgettet. Låses af tidsmålingen i Task 7 trin 3.

---

### Task 0: Måling, kort og Codex-runde (kun lokalt; ingen kode-commits)

**Files:** noter i `~/.private/6d2a/maaling.txt`; kort i `~/.private/6d2a/`; probes i `$CLAUDE_JOB_DIR/tmp`. Mål på
stand-in `daa5ab_ddl_standin_20261109142426_6d1c`; frisk stand-in fra prod først i Task 7.

- [ ] **Trin 1 (DB, kun antal og id'er):** reglens mængde med Global Constraints' endelige definition (forventet 10
  narrativer, 9 synlige; kilde 1: 0); hvilke af de 10 der har bindinger og fakta-/familiekildelinjer gennem recorden
  (skal være uændrede efter; kun tal). Kolonnerne, `public.person_offentlig` læser (Task 1's triggerliste).
- [ ] **Trin 2 (tid):** baseline på stand-in for tidsbudgettets kald: `public_person_bio_source_versions_v2` med alle
  offentlige person-id'er og med de 20 tungeste; direkte `narrative`-select som anon side for side;
  `public_person_facts` og `public_family_sources` for de 20 tungeste; `haendelse` side for side; koordinat-RPC'en.
  Gem som `maaling.txt` (ms pr. kald).
- [ ] **Trin 3 (identitet):** find kandidaterne for kort: 1014 (forventet 1048) og de to personas uden
  identitetsrække (Ditlev †1664, Cay Friedrich †1762) efter oversigternes sidehenvisninger; for kort 122 bekræft 1054
  fra evidensens `ønsket_person_id`. Afklar den menneskelige afgørelsesvej i `private.decide_source_persona_identity`
  (`schema.sql:10109`) og dens kalder: kræver den, at kandidaten står i den gældende kandidatkørsel
  (`schema.sql:~11043`)? Står en kandidat der ikke, er det en lille tilføjelse til Task 6 (ikke en omgåelse); skriv
  den ind i planen.
- [ ] **Trin 4: Kort.** Byg ét HTML-ark og én token-fil (memory `kortark-kraever-kontekst-html`,
  `menneske-gennemgang-token-fil`): 4 kort med oversigtsteksten, PDF-siden, kandidatens post og forudfyldt svar; svar
  `J`/`N`/`A <person-id>`. Projektejeren svarer; hash token-filen ved godkendelse (memory `hash-bind-menneskets-godkendelse`).
- [ ] **Trin 5: Codex-runde** (`gpt-6.1-sol`) på spec+plan fra en eksport uden `work*/` (udeluk `work*/` i selve
  søgekommandoen). Opus dømmer hvert fund; indarbejd efter projektejerens ja; log i spec §10; commit
  `docs(6d): plan for 6d-2a efter Codex-runde`.

### Task 1: Markeringen af oversigtsomtaler

**Files:**
- Modify: `schema.sql` (efter `private.membership_component_states`), migrationsblokken, `db-verify.sql`
  (`::regprocedure`-listen, tabellens RLS og ACL)
- Create: `tests/sql/test-overview-mention.sql`; tilføj til `.github/workflows/ci.yml` efter
  `test-membership-component.sql`

**Interfaces:**
- Produces: tabel `private.overview_mention(narrative_id bigint PRIMARY KEY REFERENCES public.narrative(id) ON DELETE
  CASCADE, person_id bigint NOT NULL, source_id bigint NOT NULL, detail_person_id bigint NOT NULL)`; RLS slået til,
  ingen politikker, `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role`.
- Produces: `private.overview_mentions_computed() RETURNS TABLE(narrative_id bigint, person_id bigint, source_id
  bigint, detail_person_id bigint)` — STABLE, ren beregning efter Global Constraints' regel over alle DAA-kilder;
  `detail_person_id` = mindste *Q*.
- Produces: `private.refresh_overview_mentions() RETURNS integer` — erstatter tabellens indhold med beregningen,
  returnerer antal rækker. Kaldes af sætningsniveau-`AFTER INSERT OR UPDATE OR DELETE`-triggere på
  `public.relation` (kun når en `samme_som`-række er berørt — tjek i triggeren), `public.conclusion` (kun
  `target_type='relation'`), `public.person_lineage_membership`, `private.source_persona_identity` (gyldighed af
  medlemskab), `public.narrative`, `private.narrative_record_publication` og
  `private.narrative_legacy_publication` (om *Q*'s tekst er synlig) og `public.person` (kun `UPDATE OF` kolonnerne
  fra Task 0 trin 1). Ingen af triggerne kalder hinanden rekursivt.
- **Højst én genberegning pr. transaktion ved masseskrivninger:** skriver en kalder mange rækker i en løkke (6d-1's
  promotion: 528 medlemskaber), må genberegningen ikke køre pr. sætning. *Valg:* triggeren markerer transaktionen
  (`set_config('overview_mention.dirty', txid, true)`), og en `DEFERRABLE INITIALLY DEFERRED` constraint-trigger på
  en hjælpetabel genberegner én gang ved commit; markeringen er dermed korrekt efter commit, og biografilæseren ser
  aldrig en halv tilstand udefra.

- [ ] **Trin 1: Fejlende test** (opdigtede personer, kilder og linjer med negative id'er; kilde *K* = en testkilde):
  `$grundtilfaelde$` (*P* uden medlemskab, *Q* med medlemskab og offentlig tekst, afklaret kant → *P*'s narrativ i
  tabellen); `$selv_medlem$` (*P* har selv medlemskab → ikke i tabellen); `$q_ikke_offentlig$`; `$q_uden_tekst$`;
  `$anden_kilde$` (*Q*'s medlemskab er fra en anden kilde → ikke i tabellen); `$ikke_afklaret$` (omstridt
  konklusion → ikke i tabellen); `$konklusion_senere$` (kant indsat uden konklusion → ikke; konklusion sat til
  `afklaret` → i tabellen); `$kant_fjernet$` (relation slettet → væk); `$medlemskab_ugaeldende$` (*Q*'s identitet
  omafgjort, så `membership_is_current` er falsk → *P* væk); `$paritet$` (tabellen = `overview_mentions_computed()` efter
  hver ændring ovenfor); `$q_tekst_trukket$` (*Q*'s binding trukket tilbage → *P* væk efter commit);
  `$en_gang_pr_transaktion$` (100 medlemskaber indsat i én transaktion → `refresh_overview_mentions` kørt én gang,
  talt via en testtæller); `$acl$` (anon og authenticated kan hverken læse tabellen eller kalde funktionerne).
- [ ] **Trin 2:** `env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d <lokal testbase> -f tests/sql/test-overview-mention.sql`
  → fejler (tabellen findes ikke).
- [ ] **Trin 3:** Implementér tabel, funktioner og triggere i `schema.sql`; kopiér byte-ens til migrationsblokken;
  `db-verify.sql`.
- [ ] **Trin 4:** Testen og `tests/sql/run-db-verify-disposable.sql` → grønne. Mål `refresh_overview_mentions()` på
  stand-in'en (forventet < 1 s) og `test-placement-ceremoni.sh` (6d-1's ceremoni) med triggerne på: samme kvittering,
  tidstillæg < 2 s.
- [ ] **Trin 5: Commit** `feat(6d): afledt markering af oversigtsomtaler`.

### Task 2: Biografilæseren udelader oversigtsomtaler

**Files:** Modify `schema.sql` (`public.public_person_bio_source_versions_v2` `:16586`), migrationsblokken.
Test: `tests/sql/test-overview-mention.sql` (udvid).

**Interfaces:**
- Consumes: `private.overview_mention` (Task 1).
- Samme signatur og kolonner; hver gren, der i dag kræver `person_daa_narrative_publication_allowed(narrative.id)`
  (`:16633`, `:16649`, `:16694`, `:16720`, `:16770`, `:16790`, `:16819`, `:16837`), kræver desuden
  `NOT EXISTS (SELECT 1 FROM private.overview_mention o WHERE o.narrative_id = narrative.id)`.

- [ ] **Trin 1: Fejlende tests:** `$bio_skjult$` (grundtilfældet: *P*'s tekst er ikke i v2-resultatet for *P*, og *Q*'s
  er); `$bio_reversibel$` (kant fjernet → *P*'s tekst er tilbage); `$fakta_uroert$` (`public_person_facts` og
  `public_family_sources` for *P* og *Q* er byte-ens før og efter kanten); `$haendelse_uroert$` (en hændelse på *P*'s
  narrativ er stadig synlig som anon); `$henning$` (*P* uden kant → tekst vises).
- [ ] **Trin 2-4:** kør (fejl) → implementér + migrationsblok → grønne; desuden `test-narrative-record-contract.sql`
  og `test-narrative-record-cutover.sql` grønne.
- [ ] **Trin 5: Commit** `feat(6d): biografilæseren udelader oversigtsomtaler`.

### Task 3: Retningen i `samme_som` afgøres af data

**Files:** Modify `schema.sql` (`public.red_samme_som` `:7545`), migrationsblokken. Create
`tests/sql/test-samme-som-retning.sql`; tilføj til CI ved Task 1's test.

**Interfaces:**
- Produces: `private.samme_som_data_direction(p_a bigint, p_b bigint) RETURNS TABLE(alias_id bigint, objekt_id bigint)`
  — STABLE. Findes en kilde *K*, hvor præcis én af de to har et gældende linjemedlemskab med kildegrundlag *K*, og den
  anden har en accepteret persona-identitet eller en `person_external_id`-række i *K* uden et sådant medlemskab,
  returneres (den uden, den med). Ellers ingen række. Flere kilder, der peger modsat → ingen række.
- `public.red_samme_som(p_alias_id bigint, p_objekt_id bigint)` (samme signatur og returtype): bruger
  `samme_som_data_direction`, hvis den giver en række, og G3/G4 og cyklustjekket ville tillade den retning (samme
  betingelser som `enforce_samme_som_invariants`, `:7495-7504`); ellers redaktørens retning. Triggeren er uændret og
  afgør fortsat, om kanten tillades.

- [ ] **Trin 1: Fejlende tests:** `$data_vender$` (redaktøren angiver detalje → oversigt; kanten bliver oversigt →
  detalje); `$data_bekraefter$` (rigtig retning bevares); `$g3_fallback$` (oversigtspersonen er allerede alias for en
  tredje person; datavejen ville afvises af G3 → redaktørens retning bruges og lykkes); `$begge_placeret$` og
  `$ingen_placeret$` (redaktørens retning); `$2018_20_par$` (to personer med medlemskab i hver sin kilde → redaktørens
  retning); `$modsat_kilder$` (to kilder peger modsat → redaktørens retning).
- [ ] **Trin 2-4:** kør (fejl) → implementér + migrationsblok → grønne; `test-1939-v50-c3-identity-invariants.sql`
  grøn.
- [ ] **Trin 5: Commit** `feat(6d): samme_som-retningen afgøres af data, når den kan`.

### Task 4: Redaktøren ser markeringen

**Files:**
- Modify: `schema.sql` + migrationsblok (ny RPC), `web/src/data/redaktionRead.ts` (`:318`, narrativlisten),
  komponenten, der viser listen (find den fra `redaktionRead.ts`'s kalder)
- Test: `tests/sql/test-overview-mention.sql` (udvid), vitest ved komponenten

**Interfaces:**
- Produces: `public.red_overview_mentions(p_narrative_ids bigint[]) RETURNS TABLE(narrative_id bigint,
  detail_person_id bigint)` — SECURITY DEFINER, `search_path` fast, kun `current_rolle()='redaktion'` (ellers
  `REDAKTION_REQUIRED`); `GRANT EXECUTE … TO authenticated`.
- Web: en narrativ i markeringen får mærket »Oversigtsomtale — vises ikke som biografi (detaljepost: person
  <detail_person_id>)«.

- [ ] **Trin 1: Fejlende tests:** `$red_rpc$` (redaktion får rækken; anon/authenticated uden rolle får fejlen); vitest
  `viser oversigtsmærke` (mock af RPC'en; mærket vises kun for den markerede).
- [ ] **Trin 2-4:** kør (fejl) → implementér → `npm run test -w web` og SQL-testen grønne.
- [ ] **Trin 5: Commit** `feat(6d): redaktøren ser, at en tekst er en oversigtsomtale`.

### Task 5: Opgraderingstest og hele CI lokalt

**Files:** Create `tests/sql/test-6d2a-upgrade.sh` (kopi af `tests/sql/test-6d1-upgrade.sh`).

- [ ] **Trin 1:** Byg fra `git merge-base origin/main HEAD`, kør nye `db-migrations.sql` + `db-rls.sql` to gange,
  assert at Task 1-4's funktioner har `schema.sql`'s kroppe (`pg_get_functiondef`-sha), at tabellen og triggerne
  findes, og at `overview_mention` = `overview_mentions_computed()`; kør Task 1-4's testfiler og
  `run-db-verify-disposable.sql`; slut med `echo UPGRADE_OK`.
- [ ] **Trin 2:** Kør den og `test-6d1-upgrade.sh` → `UPGRADE_OK` fra begge.
- [ ] **Trin 3:** Hele CI-jobbet lokalt (alle PostgreSQL-jobs, python, R-suiten, node med `tsc --noEmit`). Forventet
  grønt.
- [ ] **Trin 4: Commit** `test(6d): opgraderingstest for 6d-2a`.

### Task 6: Data-ceremoniens SQL og målescript

**Files:**
- Create: `.claude/skills/daa-extract/scripts/identitet_ceremoni.sql` (kildeparametriseret: tager kortsvarene som
  JSON-fil og deres sha), `maal_trin6d2a.sql` (faser `foer|ddl|data`), `test_maal_trin6d2a.py`
- Test: `tests/sql/test-identitet-ceremoni.sh`

**Interfaces:**
- Consumes: `red_samme_som` (Task 3), `private.decide_source_persona_identity` (`schema.sql:10109`; vejen fra Task 0
  trin 3), Task 0's token-fil.
- `maal_trin6d2a.sql` printer én linje: `T6D2A_MAAL fase=<foer|ddl|data> markering=<n> synlige_oversigt=<n>
  kanter_1014=<0|1> unresolved=<n> uden_identitet=<n> KOORD_2018_20=<md5> KOORD_SRC=<md5> FAKTA=<md5> BIO=<md5>`
  (`FAKTA` = md5 over `public_person_facts` + `public_family_sources` for alle offentlige personer; `BIO` = md5 over
  v2-læseren). `fase=ddl`, når `overview_mention` findes; `data`, når kortenes skrivninger findes.
- Ceremonien: én transaktion; for hvert kort med `J`/`A` en kobling eller identitet; nulstil `app.change_set_id`
  mellem kaldene; POST: `unresolved=0` og `uden_identitet=0` bortset fra registrerede `N`; `FAKTA` og `KOORD_2018_20`
  uændrede; markeringen = beregningen. Kvittering `T6D2A_OK kanter=<n> identiteter=<n> markering=<n>`.

- [ ] **Trin 1: Fejlende tests:** målescriptets format (`test_maal_trin6d2a.py`); ceremonien på en lokal base med
  opdigtede kort: `J` på kobling og identitet → kvittering; forkert token-sha → `T6D2A_PRE_SHA`; `N` → intet skrevet
  for kortet; gentaget kørsel → `T6D2A_PRE_FASE`.
- [ ] **Trin 2-4:** kør (fejl) → implementér → grønne.
- [ ] **Trin 5: Commit** `feat(6d): data-ceremoni og målescript for 6d-2a`.

### Task 7: Runner, runbook og generalprøve

**Files:**
- Create (privat, aldrig i repoet): `~/.private/5ab-overfoersel/34-trin6d2a.sh` (+ `34-trin6d2a-vindue.sql`) efter
  `33-trin6d1.sh`: `maal`, `anon` (tidsbudgettets kald), `dump`, `dump-kopi`, `standin`, `go-ddl`, `apply-ddl`,
  `go-data`, `apply-data`, `verify`, `fortryd`.
- Create: `docs/runbooks/trin6d2a-prod.md`.

- [ ] **Trin 1: Runner:** fastlåste indholdsafledte forventninger (Task 0's tal, kortenes sha), GO binder DDL-blokkens
  sha og commit; vinduesvagt; `anon` måler alle kald i tidsbudgettet og sammenligner med baseline (fejl over +10 %).
- [ ] **Trin 2: Runbook:** rækkefølge `maal → anon → dump → go-ddl → apply-ddl → maal → anon → dump → go-data →
  apply-data → verify → anon`, stoppunkter og fortryd under meldt frys.
- [ ] **Trin 3: Generalprøve** fra operatørens cwd på en stand-in fra en frisk prod-`dump-kopi`: hele rækkefølgen;
  tidsbudgettet overholdt (Review Focus 5); fortryd-data og fortryd-DDL på en anden stand-in.
- [ ] **Trin 4: Negativer:** forkert GO, manglende flag, gentaget `apply-data`, ændret token-fil.
- [ ] **Trin 5: Commit** `docs(6d): runbook for 6d-2a i prod` (runneren committes ikke).

### Task 8: Review, prod og færdigbevis

- [ ] **Trin 1:** Codex `gpt-6.1-sol` over hele grenens diff (eksport uden `work*/`); Opus dømmer; ret kun det
  godkendte efter projektejerens ja; hele CI lokalt igen.
- [ ] **Trin 2:** Spørg om push og draft-PR; CI på PR'en grøn.
- [ ] **Trin 3: Prod** i projektejerens shell efter runbooken; AI'en læser kvitteringer og mål.
- [ ] **Trin 4: Færdigbevis** (spec §8) i `docs/evidensbaseret-genimport/status.md`, `database-current-state.md` og
  changelog: markeringen = beregningen og mængden før/efter; 0 af dem i v2-læseren som anon; reversibilitet (fra
  generalprøven); `FAKTA` og `KOORD_2018_20` uændrede; kortenes udfald; tidsbudgettet.
- [ ] **Trin 5:** `docs/decisions.md`: noter 6d-2a i prod; commit `docs(6d): færdigbevis for 6d-2a i prod`.
