# Trin 6d-2a: oversigtsreglen og 1939's resterende identitetssager — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** En 1939-oversigtsomtale leveres ikke længere som biografi for en person, der har sin egen detaljepost —
automatisk og reversibelt ved enhver ændring — `samme_som` får sin retning fra data, og 1014's kobling samt tre
oversigtspersonas' identitet afgøres.

**Architecture:**
- **Live regel (DDL, spec rev. 4):** én privat funktion `private.overview_mention_narratives(p_person_ids bigint[])`
  beregner reglen for de forespurgte personer ved hvert kald — ingen gemt markering, ingen triggere. Ingen skrivning
  til narrativ, binding eller publiceringshændelser.
- **To biografilæsere:** `public.public_person_bio_source_versions_v2` (web, `web/src/data/public.ts:231-246`,
  `feedAux.ts`) og den ældre `public.public_person_bio_source_versions` (mobil, `mobile/src/data/publicBioVersions.ts:49`
  — opdaget under Task 2; planen nævnte kun v2) udelader begge narrativer, funktionen returnerer, beregnet én gang pr.
  kald. Faktalæserne, hændelserne og narrativ-RLS bruger den fælles vagt og røres ikke.
- **Retning:** `public.red_samme_som` vender kanten, når data kan afgøre den, og falder tilbage til redaktørens retning,
  hvis G3/G4 (`schema.sql:7495-7504`) ville afvise.
- **Prod:** én DDL- og én data-ceremoni gennem en privat runner efter 6d-1's mønster.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), TypeScript/React (web, vitest), bash/zsh (opgraderingstest, runner).

**Spec:** `docs/superpowers/specs/2026-11-09-trin6d2a-oversigtsregel-identitet-design.md` (godkendt rev. 3, rev. 4 efter Codex-runden,
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
- **Ingen editionsnavngiven permanent overflade:** regelfunktion, RPC'er og ceremoni er kildeparametriserede; ingen
  udgavenavne eller kilde-id'er i logikken.
- **Reglen (spec §4.1, ordret):** *P*'s kilde-*K*-narrativ er en oversigtsomtale, når *P* ikke har et gældende
  linjemedlemskab med `source_basis.source_id = K` (`private.membership_is_current`), og *P*'s komponent (kun
  `samme_som` med `afklaret` konklusion, uanset retning) indeholder en anden person *Q*, der har et, er offentlig
  (`public.person_offentlig`) og har en *K*-narrativ, der ikke selv er en oversigtsomtale, og som
  `person_daa_narrative_publication_allowed` tillader. Stien fra *P* til *Q* går kun gennem offentlige personer (*P*
  selv undtaget). *Q*'s narrativ kan aldrig selv være en oversigtsomtale (*Q* har medlemskabet) → ingen rekursion over
  narrativer.
- **Uberørte:** `public_person_facts`, `public_family_sources`, `haendelse`-politikken, narrativ-RLS,
  `person_daa_narrative_publication_allowed`, 2018-20's data og koordinater, 6d-1's 528 placements og medlemskaber.
- **Tidsbudget (spec §4.1 rev. 4):** ingen af budgettets anon-kald mere end 10 % langsommere end før DDL'en (median af
  3, samme base). Det eksisterende ~3 s-niveau er backlog. Task 0's probe: ≈ 135 ms for alle personer (+4 %).
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
2. **Reglen følger sine indgange uden vedligeholdelse.** Et medlemskab, der bliver ugældende (identitet eller
   placement omafgjort, slægtsmedlemskab ændret), en kant uden afklaret konklusion, en tilbagetrukket publicering på
   *Q*: *P*'s tekst vises igen i samme transaktion. Låses af `$medlemskab_ugaeldende$`, `$placement_ugaeldende$`,
   `$konklusion_senere$` og `$q_tekst_trukket$` i Task 1 — uden noget manuelt genberegningskald.
3. **Skjult mellemled.** En sti *P* → ikke-offentlig *R* → *Q* skjuler ikke *P*'s tekst (anon kan ikke se kanten, så
   appen kan ikke folde *P* ind i *Q*). Låses af `$skjult_mellemled$`.
4. **En oversigtsperson, der allerede er alias for en 2018-20-person** (G3-tilfældet). Retningsreglen må ikke give en
   fejl, hvor redaktørens retning ville lykkes; et gentaget kald må ikke fejle eller skrive igen. Låses af
   `$g3_fallback$` og `$idempotent$` i Task 3.
5. **Feedet kalder biografilæseren med alle modellens personer** (`web/src/data/feedAux.ts:47-79`). Regelfunktionen må
   ikke gøre kaldet mere end 10 % langsommere. De dyre funktionskald må kun ramme de forfiltrerede par; ingen
   `MATERIALIZED`-CTE'er. Låses af tidsmålingen i Task 1 trin 4 og Task 7 trin 3.

---

### Task 0: Måling, kort og Codex-runde (kun lokalt; ingen kode-commits) — UDFØRT 2026-11-09

Noter, tider, probe, kort og manifest i `~/.private/6d2a/` (0600). Resultat (kun tal):
- [x] **Trin 1:** reglens mængde = 10 narrativer (personerne 967, 974, 977, 978, 991, 992, 1013, 1017, 1021, 1802),
  9 synlige, kilde 1: 0. Paritet for de 10 *P* som anon: `public_person_facts` 21 rækker, `public_family_sources` 0,
  biografi 9 (md5 i `paritet-10.txt`). `person_offentlig` læser `levende`, `privat`, `staged`.
- [x] **Trin 2:** baseline (anon, median ms): biografi alle personer ≈ 3080, 20 tungeste ≈ 116; direkte narrativside
  ≈ 3000-3100; koordinater ≈ 564; `public_person_facts` max ≈ 246; `public_family_sources` max ≈ 51; `haendelse` tom.
  En naiv set-beregning tog 14 s; den forfiltrerede live-probe (`probe-live-regel.sql`) ≈ 135 ms, samme 10.
- [x] **Trin 3:** `red_afgoer_source_persona` kræver kun kandidatkørsel, hvis `candidate_id` gives; de 3 personas har 0
  kontrolstikprøver → ingen tilføjelse. Kandidater: 1014 → 1048; persona `589f8292` (kort 122) → 1054; `b06067a3`
  (Ditlev †1664) → 1123; `a573cad1` (Cay Friedrich †1762) → 1158. 1014 er `staged`. 1054/1123/1158 får hver deres
  anden accepterede kilde-3-persona (første tilfælde i 1939; ingen unik-regel).
- [x] **Trin 4:** 4 kort; projektejeren svarede J på alle; svarfilens sha `c001c206…709d`.
- [x] **Trin 5:** Codex-runde (12 fund, NO-GO) → spec rev. 4 (§10); projektejeren valgte live-beregning og uændret
  narrativ-RLS.

### Task 1: Regelfunktionen

**Files:**
- Modify: `schema.sql` (efter `private.membership_component_states`), migrationsblokken, `db-verify.sql`
  (`::regprocedure`-listen, ACL)
- Create: `tests/sql/test-overview-mention.sql`; tilføj til `.github/workflows/ci.yml` efter
  `test-membership-component.sql`

**Interfaces:**
- Produces: `private.overview_mention_narratives(p_person_ids bigint[]) RETURNS TABLE(narrative_id bigint, person_id
  bigint, source_id bigint, detail_person_id bigint)` — STABLE, `SECURITY DEFINER`, `SET search_path=pg_catalog`,
  `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role`. Returnerer oversigtsomtalerne blandt de forespurgte
  personers DAA-narrativer efter Global Constraints' regel; `detail_person_id` = mindste *Q*. Kildeparametriseret
  (ingen kilde-id'er eller udgavenavne).
- Form (Task 0's probe, `~/.private/6d2a/probe-live-regel.sql` — projektejeren kan give indholdet; implementeren læser
  ikke `~/.private`): (a) forespurgte personers DAA-narrativer, hvis person har en afklaret `samme_som`-kant; (b)
  rekursion over afklarede kanter (begge retninger) fra disse, kun ind i offentlige personer; (c) billig forfiltrering
  uden funktionskald: *Q* ≠ *P* med en `person_lineage_membership`-række (`source_basis ? 'persona_placement_id'`,
  `source_basis->>'source_id'` = *K*) og en *K*-narrativ; (d) først derefter `membership_is_current` (*P* mangler, *Q*
  har), `person_offentlig(Q)` og `person_daa_narrative_publication_allowed` på *Q*'s *K*-narrativ. Opslag direkte i
  basistabellerne (deres indeks); ingen `MATERIALIZED`-CTE'er.

- [ ] **Trin 1: Fejlende test** (opdigtede personer, kilder og linjer med negative id'er; kilde *K* = en testkilde):
  `$grundtilfaelde$` (*P* uden medlemskab, *Q* med medlemskab og offentlig tekst, afklaret kant → *P*'s narrativ
  returneres med `detail_person_id` = *Q*); `$selv_medlem$`; `$q_ikke_offentlig$`; `$q_uden_tekst$`; `$anden_kilde$`;
  `$ikke_afklaret$`; `$konklusion_senere$` (kant uden konklusion → ikke; konklusion sat til `afklaret` → returneres);
  `$kant_fjernet$`; `$medlemskab_ugaeldende$` (*Q*'s identitet omafgjort → *P* ikke returneret);
  `$placement_ugaeldende$` (*Q*'s persona-placement afvist uden identitetsændring → ikke returneret);
  `$q_tekst_trukket$` (*Q*'s binding trukket tilbage → ikke returneret); `$skjult_mellemled$` (*P* → ikke-offentlig *R*
  → *Q* → ikke returneret; *R* offentlig → returneret); `$kun_forespurgte$` (en *P* uden for `p_person_ids` returneres
  ikke); `$acl$` (anon og authenticated kan ikke kalde funktionen).
- [ ] **Trin 2:** `env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d <lokal testbase> -f tests/sql/test-overview-mention.sql`
  → fejler (funktionen findes ikke).
- [ ] **Trin 3:** Implementér i `schema.sql`; kopiér byte-ens til migrationsblokken; `db-verify.sql`.
- [ ] **Trin 4:** Testen og `tests/sql/run-db-verify-disposable.sql` → grønne. På stand-in
  `daa5ab_ddl_standin_20261109142426_6d1c` (efter `ANALYZE`): funktionen med alle personer returnerer narrativerne
  636, 643, 646, 647, 660, 661, 682, 686, 690, 1176 og tager højst 10 % af biografilæserens baseline (≈ 300 ms; median
  af 3).
- [ ] **Trin 5: Commit** `feat(6d): live regel for oversigtsomtaler`.

### Task 2: Biografilæseren udelader oversigtsomtaler

**Files:** Modify `schema.sql` (`public.public_person_bio_source_versions_v2` `:16586`), migrationsblokken.
Test: `tests/sql/test-overview-mention.sql` (udvid).

**Interfaces:**
- Consumes: `private.overview_mention_narratives` (Task 1), kaldt **én gang** pr. læserkald med `p_person_ids`
  (fx en CTE), ikke pr. række.
- Samme signatur og kolonner; hver gren, der i dag kræver `person_daa_narrative_publication_allowed(narrative.id)`
  (`:16633`, `:16649`, `:16694`, `:16720`, `:16770`, `:16790`, `:16819`, `:16837`), udelader desuden narrativer i
  funktionens resultat.

- [ ] **Trin 1: Fejlende tests:** `$bio_skjult$` (grundtilfældet: *P*'s tekst er ikke i v2-resultatet for *P*, og *Q*'s
  er); `$bio_reversibel$` (kant fjernet → *P*'s tekst er tilbage); `$fakta_uroert$` (`public_person_facts` og
  `public_family_sources` for *P* og *Q* er byte-ens før og efter kanten); `$haendelse_uroert$` (en hændelse på *P*'s
  narrativ er stadig synlig som anon, og *P*'s narrativ kan stadig læses direkte); `$henning$` (*P* uden kant → tekst
  vises).
- [ ] **Trin 2-4:** kør (fejl) → implementér + migrationsblok → grønne; desuden `test-narrative-record-contract.sql`
  og `test-narrative-record-cutover.sql` grønne. Mål biografilæseren med alle personer på stand-in'en: højst +10 %
  mod Task 0's baseline.
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
- **Idempotens (Codex-fund 12):** under RPC'ens eksisterende låse slås kanten op i *begge* retninger, før retningen
  vælges; findes den, returneres den uændret (ingen ny audit, evidens eller konklusion) — også hvis medlemskaberne
  siden har ændret sig.

- [ ] **Trin 1: Fejlende tests:** `$data_vender$` (redaktøren angiver detalje → oversigt; kanten bliver oversigt →
  detalje); `$data_bekraefter$` (rigtig retning bevares); `$g3_fallback$` (oversigtspersonen er allerede alias for en
  tredje person; datavejen ville afvises af G3 → redaktørens retning bruges og lykkes); `$begge_placeret$` og
  `$ingen_placeret$` (redaktørens retning); `$2018_20_par$` (to personer med medlemskab i hver sin kilde → redaktørens
  retning); `$modsat_kilder$` (to kilder peger modsat → redaktørens retning); `$idempotent$` (samme kald gentaget i begge
  argumentrækkefølger, også efter et ændret medlemskab → samme relations-id, ingen ny audit- eller konklusionsrække).
- [ ] **Trin 2-4:** kør (fejl) → implementér + migrationsblok → grønne; `test-1939-v50-c3-identity-invariants.sql`
  grøn.
- [ ] **Trin 5: Commit** `feat(6d): samme_som-retningen afgøres af data, når den kan`.

### Task 4: Redaktøren ser markeringen

**Files:**
- Modify: `schema.sql` + migrationsblok (ny RPC), `web/src/data/redaktionRead.ts` (`:318`, narrativlisten),
  komponenten, der viser listen (find den fra `redaktionRead.ts`'s kalder)
- Test: `tests/sql/test-overview-mention.sql` (udvid), vitest ved komponenten

**Interfaces:**
- Produces: `public.red_overview_mentions(p_person_ids bigint[]) RETURNS TABLE(narrative_id bigint,
  detail_person_id bigint)` — SECURITY DEFINER, `search_path` fast, kun `current_rolle()='redaktion'` (ellers
  `REDAKTION_REQUIRED`); `GRANT EXECUTE … TO authenticated`. Tynd indpakning af
  `private.overview_mention_narratives` (Task 1).
- Web: en narrativ, som RPC'en returnerer, får mærket »Oversigtsomtale — vises ikke som biografi (detaljepost: person
  <detail_person_id>)«.

- [ ] **Trin 1: Fejlende tests:** `$red_rpc$` (redaktion får rækken; anon/authenticated uden rolle får fejlen); vitest
  `viser oversigtsmærke` (mock af RPC'en; mærket vises kun for den markerede).
- [ ] **Trin 2-4:** kør (fejl) → implementér → `npm run test -w web` og SQL-testen grønne.
- [ ] **Trin 5: Commit** `feat(6d): redaktøren ser, at en tekst er en oversigtsomtale`.

### Task 5: Opgraderingstest og hele CI lokalt

**Files:** Create `tests/sql/test-6d2a-upgrade.sh` (kopi af `tests/sql/test-6d1-upgrade.sh`).

- [ ] **Trin 1:** Byg fra `git merge-base origin/main HEAD`, kør nye `db-migrations.sql` + `db-rls.sql` to gange,
  assert at Task 1-4's funktioner har `schema.sql`'s kroppe (`pg_get_functiondef`-sha) og ACL; kør Task 1-4's
  testfiler og
  `run-db-verify-disposable.sql`; slut med `echo UPGRADE_OK`.
- [ ] **Trin 2:** Kør den og `test-6d1-upgrade.sh` → `UPGRADE_OK` fra begge.
- [ ] **Trin 3:** Hele CI-jobbet lokalt (alle PostgreSQL-jobs, python, R-suiten, node med `tsc --noEmit`). Forventet
  grønt.
- [ ] **Trin 4: Commit** `test(6d): opgraderingstest for 6d-2a`.

### Task 6: Data-ceremoniens SQL og målescript

**Files:**
- Create: `.claude/skills/daa-extract/scripts/identitet_ceremoni.sql` (kildeparametriseret: tager kortmanifestet og
  svarene som JSON-fil og deres sha), `maal_trin6d2a.sql` (faser `foer|ddl|data`), `test_maal_trin6d2a.py`
- Test: `tests/sql/test-identitet-ceremoni.sh`

**Interfaces:**
- Consumes: `red_samme_som` (Task 3); `public.red_afgoer_source_persona` med `p_action='same'`,
  `p_context={"basis":"human_sheet","sheet_sha256":<manifestets sha>,"rows_sha256":<svarenes sha>,"line":<kort>}` og
  **uden** `candidate_id` (Task 0 trin 3); Task 0's kort.
- **Kortmanifest (Codex-fund 9):** et kanonisk JSON pr. kort: kort-nr., handling (`samme_som` eller `identitet`),
  persona-id og `persona_key` (identitet) eller begge person-id'er (kobling), forventet identitetsstatus og -version
  (`unresolved`/2 for kort 122; ingen række for de to andre), kandidatens person-id, sha256 over den viste
  oversigtstekst og over kandidatposten. Manifestet bygges af den lokale prod-kopi og hashes; svarfilen (J/N/A)
  refererer manifestets sha. Ceremonien efterprøver hver førtilstand under lås (version, status, tekst-sha) og
  afbryder med `T6D2A_PRE_MANIFEST` ved afvigelse.
- `maal_trin6d2a.sql` printer én linje: `T6D2A_MAAL fase=<foer|ddl|data> regel=<n> synlige_oversigt=<n>
  kanter_par=<0|1> unresolved=<n> uden_identitet=<n> KOORD_2018_20=<md5> KOORD_SRC=<md5> FAKTA=<md5> BIO=<md5>`
  (`FAKTA` = md5 over `public_person_facts` + `public_family_sources` for alle offentlige personer; `BIO` = md5 over
  v2-læseren; `kanter_par` = antal samme_som-kanter mellem `-v par_a`/`-v par_b`, begge retninger, uden person-id'er i
  scriptet; `regel`/`synlige_oversigt` er `na` i `foer`). `fase=ddl`, når `private.overview_mention_narratives` findes; `data`, når ceremoniens kvittering
  findes (registreres også ved fire `N`, Codex-fund 10).
- Ceremonien: én transaktion; for hvert kort med `J`/`A` en kobling eller identitet; nulstil `app.change_set_id`
  mellem kaldene; POST: `unresolved=0` og `uden_identitet=0` bortset fra registrerede `N`; `FAKTA` og `KOORD_2018_20`
  uændrede; regelfunktionen (alle personer) giver den forventede mængde. Kvittering
  `T6D2A_OK kanter=<n> identiteter=<n> regel=<n>`, skrevet som en change_set-/auditpost, også ved nul skrivninger.
  Testes: to af de tre identiteter peger på personer, der allerede har en accepteret kilde-3-persona;
  `placement_membership_set(3)` og `persona_family_context` er uændrede for dem.

- [ ] **Trin 1: Fejlende tests:** målescriptets format (`test_maal_trin6d2a.py`); ceremonien på en lokal base med
  opdigtede kort: `J` på kobling og identitet → kvittering; forkert token-sha → `T6D2A_PRE_SHA`; `N` → intet skrevet
  for kortet; gentaget kørsel → `T6D2A_PRE_FASE`; ændret kandidattekst eller identitetsversion efter manifestet →
  `T6D2A_PRE_MANIFEST`; fire `N` → kvittering og `fase=data`.
- [ ] **Trin 2-4:** kør (fejl) → implementér → grønne.
- [ ] **Trin 5: Commit** `feat(6d): data-ceremoni og målescript for 6d-2a`.

### Task 7: Runner, runbook og generalprøve

**Files:**
- Create (privat, aldrig i repoet): `~/.private/5ab-overfoersel/34-trin6d2a.sh` (+ `34-trin6d2a-vindue.sql`) efter
  `33-trin6d1.sh`: `maal`, `anon` (tidsbudgettets kald), `dump`, `dump-kopi`, `standin`, `go-ddl`, `apply-ddl`,
  `go-data`, `apply-data`, `verify`, `fortryd`.
- Create: `docs/runbooks/trin6d2a-prod.md`.

- [ ] **Trin 1: Runner:** fastlåste indholdsafledte forventninger (Task 0's tal, manifestets og svarenes sha); GO
  binder sha over **alle** udførte artefakter: DDL-blokken, data-SQL'en, målescriptet, manifest, svar, runneren og
  vinduesvagten, samt commit (Codex-fund 11). Før hver skrivende ceremoni: dump + ekstern kopi, hvis sha
  efterprøves mod kopien, før `apply-*` får lov. Vinduesvagten: præcist tilladt write-set pr. ceremoni (tabeller +
  forventede rækkeaftryk); enhver anden skrivning i vinduet, også fra samme aktør, lukker restorevejen. `anon`
  måler alle kald i tidsbudgettet og sammenligner med baseline (fejl over +10 %).
- [ ] **Trin 2: Runbook:** rækkefølge `maal → anon → dump → dump-kopi → go-ddl → apply-ddl → maal → anon → dump →
  dump-kopi → go-data → apply-data → verify → anon`, stoppunkter og fortryd under meldt frys.
- [ ] **Trin 3: Generalprøve** fra operatørens cwd på en stand-in fra en frisk prod-`dump-kopi`: hele rækkefølgen;
  tidsbudgettet overholdt (Review Focus 5); fortryd-data og fortryd-DDL på en anden stand-in. **Appens sammenlægning**
  (Codex-fund 8): kør `collapseSameAs`/`validateGroups` (`packages/core`) på stand-in'ens anon-data efter data-
  ceremonien; de 11 berørte komponenter er accepteret (ikke karantæneret), sink uændret (134 for 1014/1048), og
  biografimappingen giver *Q*'s tekst på kortet.
- [ ] **Trin 4: Negativer:** forkert GO, manglende flag, gentaget `apply-data`, ændret token-fil.
- [ ] **Trin 5: Commit** `docs(6d): runbook for 6d-2a i prod` (runneren committes ikke).

### Task 8: Review, prod og færdigbevis

- [ ] **Trin 1:** Codex `gpt-6.1-sol` over hele grenens diff (eksport uden `work*/`); Opus dømmer; ret kun det
  godkendte efter projektejerens ja; hele CI lokalt igen.
- [ ] **Trin 2:** Spørg om push og draft-PR; CI på PR'en grøn.
- [ ] **Trin 3: Prod** i projektejerens shell efter runbooken; AI'en læser kvitteringer og mål.
- [ ] **Trin 4: Færdigbevis** (spec §8) i `docs/evidensbaseret-genimport/status.md`, `database-current-state.md` og
  changelog: regelfunktionens mængde før/efter; 0 af dem i v2-læseren som anon; reversibilitet (fra
  generalprøven); `FAKTA` og `KOORD_2018_20` uændrede; kortenes udfald; tidsbudgettet.
- [ ] **Trin 5:** `docs/decisions.md`: noter 6d-2a i prod; commit `docs(6d): færdigbevis for 6d-2a i prod`.
