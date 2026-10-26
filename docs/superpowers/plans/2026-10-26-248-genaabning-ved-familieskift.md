# #248 rute A — genåbning ved familieskift: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Et accepteret ægteskab, hvis tilstand efter en identitetsrettelse peger på en anden familie, kan genåbnes
(ny `proposed`-version) fra et hash-bundet ark. Derefter afgøres og bindes det ad den eksisterende vej. En vagt
forhindrer, at to ægtefæller i samme post bindes til samme person. Ægtefællearket kræver et svar, når det ser en
navnefælle. De to #248-ægteskaber bindes til familie 65 og 194 i prod.

**Architecture:**
- **Én ny RPC:** `public.red_genaabn_relation_interpretation`, med en tilføj-kun proveniens-tabel
  `private.relation_reopen`.
- **Én ændret privat funktion:** `private.relation_binding_state` får vagten mod dobbeltmål.
- **Uændret:** afgørelse (`red_decide_relation_interpretations`) og binding (`red_promote_relation_interpretations_batch`).
  Begge spærrer er pr. versions-id, så den nye version går igennem dem som ethvert forslag.
- **Arket:** projektionen `private.spouse_exception_projection` får ét felt, og Python-værktøjet lader en markeret
  linje stå ubesvaret (`?`).
- **Prod:** to ceremonier (DDL-blok, derefter data), øvet på en stand-in af prod efter skridt 1.

**Tech Stack:** PostgreSQL 17 (plpgsql), Python 3 (ark og pytest), bash/zsh (opgraderingstest, privat runner).

**Spec:** `docs/superpowers/specs/2026-10-26-248-genaabning-ved-familieskift-design.md` (GODKENDT 2026-10-26).
Baggrund: `docs/decisions.md` (#248, 2026-10-26), 2b-i-spec'en §4.2-§4.4 og §13.

## Global Constraints

- **Gren:**
  - `feat/248-genaabning` oprettes fra `docs/248-rute-a-spec`, så spec, plan og kode ender i én PR.
  - PR'en er altid `--draft`.
  - Intet push uden et udtrykkeligt ja.
- **Prod:**
  - Prod røres kun i projektejerens shell med GO (`koer.zsh`).
  - AI'en kører kun mod lokale baser.
- **`schema.sql` er source of truth:**
  - `db-migrations.sql` får én ny blok mellem `-- Dubletregel-blokken slutter her.` (linje ~25479) og
    `-- 5b-sektionen slutter her …`.
  - Blokken begynder med `-- Genåbning ved familieskift (#248, decisions 2026-10-26)` og slutter med
    `-- Genåbnings-blokken slutter her.`
  - Dubletregel-blokken (sha-bundet i `database-current-state.md` §12) må ikke redigeres. Rute A's
    `relation_binding_state` står i den nye blok og vinder, fordi den kommer senere.
- **Fejlkoder:**
  - `RELATION_REOPEN_CONTEXT_INVALID|NOT_FOUND|NOT_ELIGIBLE|VERSION_MISMATCH|STATE_INVALID|NOT_NEEDED|BINDING_INVALID`
  - `EVIDENCE_ROLE_FORBIDDEN`
  - ved revideret klausul: `INTERPRETATION_OBSERVATION_CLAUSE_NOT_CURRENT` (fra den eksisterende trigger)
  - arket: `SHEET_UNANSWERED`
- **Indholds-id for den genåbnede version:**
  `private.content_uuid('interpretation-reopen', jsonb_build_object('interpretation_key',<nøgle>,'version',<ny version>))`.
- **ACL som #244:**
  - RPC: `REVOKE ALL … FROM PUBLIC,anon,authenticated; GRANT EXECUTE … TO authenticated`.
  - Tabellen: `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role`, RLS slået til, triggere med
    `private.reject_evidence_mutation()`.
- **PII:**
  - Navne og bogtekst må kun stå i `~/.private/248/`.
  - Tests bruger opdigtede personer med negative id'er.
  - Chat, commits og rapporter indeholder kun tal og hashes.
- **Miljø:**
  - `env -u PGOPTIONS` foran psql og `env -u NODE_OPTIONS` foran npm.
  - Python-tests køres med `/usr/bin/python3 -m pytest`.
- **Commits:**
  - Atomiske, Conventional Commits på dansk og uden Claude-attribution.
  - Trailer: `Claude-Session: https://claude.ai/code/session_01XDZqSLkJ25jUUA7F89S6HB`.

## Review Focus

1. **Vagten må ikke ophæve en eksisterende binding i prod.** Antallet af gældende bindinger for kilde 1 skal være det
   samme før og efter DDL'en på stand-in'en. Det låses af målingen i Task 1, trin 6.
2. **Læserens svartid.** `relation_binding_state` kaldes for hver række i `public_family_sources`. Vagtens
   opslag skal bruge indekseret adgang. `public_family_sources` over alle familier måles før og efter på stand-in'en
   (Task 1, trin 6); maks. 20 % langsommere.
3. **Et genåbnet ægteskab, hvis klausulsæt er revideret siden.** Genåbningen skal fejle hele vejen uden halv skrivning
   (ingen række i `relation_reopen`, ingen ny version). Det låses af `genaabn_revideret_klausul` i Task 2.
4. **Samtidig genåbning af samme ægteskab fra to sessioner.** Den anden session skal få `VERSION_MISMATCH` eller
   `NOT_ELIGIBLE`, ikke en unikheds- eller triggerfejl. Det låses af `genaabn_gentaget` i Task 2 (sekventielt
   andet kald; låseordenen gør det samtidige tilfælde ækvivalent).
5. **Et ark, hvor to ægtefæller i samme post har samme kandidat nr. 1.** Begge linjer skal stå `?`, og et ark med
   `?` skal afvises med `SHEET_UNANSWERED`. Det låses i Task 4.

---

### Task 0: Stand-in af prod efter skridt 1 (forudsætning, kun lokalt)

Det, der skal bevises i prod, kan kun ses på prods data. Ingen eksisterende base matcher prod nu
(`daa240_dubtest_20261026` er fra før #263 og skridt 1).

**Files:** ingen i repoet. Noter skrives i `~/.private/248/standin.txt`.

- [ ] **Trin 1:** Opret basen `daa5ab_ddl_standin_20261026160000_248a` med ICU-locale, som prod:
  `createdb --locale-provider=icu --icu-locale=da-DK --template=template0`. Restore
  `~/.private/5ab-overfoersel/prod/248/daa-prod-20261026124140-248.dump` (sha `8d17f579…`) med
  `pg_restore --no-owner`. Brug auth-shimmen som i `lokal-db-testbase` (memory).
- [ ] **Trin 2:** Kør `fix_248_maal.sql`. Forventet: `FIX248 fase=foer`.
- [ ] **Trin 3:** Kør `fix_248_identitet.sql` med prods aktør (fra `b2/aktoer.txt`; må aldrig udskrives) og `src=1`.
  Forventet: `FIX248_IDENTITET_OK`. Kør derefter `fix_248_maal.sql` igen. Forventet: `fase=efter`.
- [ ] **Trin 4:** Gem basislinjen i `standin.txt`:
  - antal gældende bindinger for kilde 1 (samme definition som `pg_temp.gaeldende`, over alle nøgler);
  - `count(*)` og tid (`\timing`, median af 3) for `public_family_sources(ARRAY(SELECT id FROM family))`;
  - `jsonb_array_length(spouse_exception_projection(1)->'o_rows')`.
- [ ] **Trin 5:** Tag en skabelonkopi `daa5ab_ddl_standin_20261026160000_248t`, så hver øvelse starter forfra.

### Task 1: Vagt mod dobbeltmål i `relation_binding_state`

**Files:**
- Modify: `schema.sql:16570-16658` (`private.relation_binding_state`)
- Modify: `db-migrations.sql` (ny blok, se Global Constraints; fuld kopi af funktionen)
- Test: `tests/sql/test-relation-binding.sql` (ny DO-blok sidst i filen, i egen `BEGIN … ROLLBACK`)

**Interfaces:**
- Produces: `private.relation_binding_state(uuid) RETURNS jsonb` med uændret signatur og uændret output for
  alle andre tilfælde. NULL, når vagten slår til.

- [ ] **Trin 1: Skriv den fejlende test** `dobbeltmaal_menneskevej`. Brug fixtures `relation-5b.sql` og
  `relation-2a.sql`, som `$rebind_preview$` (linje 672-686) gør:
  - lav én post med to ægteskabspåstande for samme hovedperson, som D-3 i `tests/sql/test-family-corroboration.sql:48-55`
    (`f5b_post` med tre klausuler `'g. 1° m. …'`/`'g. 2° m. …'`, to `f5b_claim` og to `f5b_spouse` med nr. 1 og 2;
    `f2a_marriage` laver én post pr. kald og kan ikke bruges). Afgør begge ægtefællepersonas `same` til samme
    person med `red_afgoer_source_persona`, og lav en familie med `f5b_family`;
  - assert: `private.relation_binding_state(<hver af de to>) IS NULL`;
  - kontrol: afgør den ene ægtefælle til en anden person (ny version, `same`, anden person med egen familie) og
    assert, at begge tilstande nu er IKKE NULL;
  - `RAISE NOTICE 'OK: dobbeltmål på menneskevejen'`.
- [ ] **Trin 2: Kør og se den fejle.** Byg testbasen som CI-jobbet (`.github/workflows/ci.yml:196-201`) og kør
  `env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -f tests/sql/test-relation-binding.sql`. Forventet:
  `RELATION_BINDING_TEST_FAILED: dobbeltmål` (tilstanden er ikke NULL).
- [ ] **Trin 3: Implementér vagten.** I grenen `v_role='spouse'`, lige efter `IF v_a=v_b THEN RETURN NULL; END IF;`:
  RETURN NULL, når der findes en anden ægtefællepart (`pc2.source_persona_id` ≠ denne parts persona) i en gældende
  `relation.marriage`-fortolkning med `status<>'rejected'`, hvis første understøttende observation har samme
  `occurrence_id`, og hvis parts accepterede identitet er `v_b`.
  - Joinet spejler `FAMILY_CORROBORATION_DOUBLE_TARGET` (`schema.sql:16475-16488`).
  - Postens `occurrence_id` hentes fra `v_i`'s `interpretation_observation` (`evidence_role='supporting'`,
    `ordinal=1`) → `source_observation`.
  - Kommentar på én linje med henvisning til #248 og rute A's spec §3.3.
  - Kopiér den fulde nye definition til den nye blok i `db-migrations.sql`.
- [ ] **Trin 4: Kør testfilen igen.** Forventet: `OK: dobbeltmål på menneskevejen` og alle tidligere NOTICE'er.
- [ ] **Trin 5: Paritet.** Byg en frisk og en migreret base. Kør `tests/sql/inspect-5ab-function-parity.sql`
  i begge og `diff`. Forventet: ingen forskel.
- [ ] **Trin 6: Mål på stand-in'en** (kopi af `…_248t`): læg kun `CREATE OR REPLACE` af funktionen og gentag
  Task 0, trin 4. Forventet:
  - gældende bindinger er uændret;
  - `public_family_sources` giver samme antal og er højst 20 % langsommere.

  Er den langsommere, tilføj et indeks på `private.interpretation_party(source_persona_id)` eller omskriv opslaget,
  før du går videre.
- [ ] **Trin 7: Commit.** `feat(248): vagt mod to ægtefæller i samme post til samme person`.

### Task 2: `private.relation_reopen` og `public.red_genaabn_relation_interpretation`

**Files:**
- Modify: `schema.sql`:
  - tabellen lige efter `private.marriage_ordinal_correction` (linje ~1363);
  - RPC'en lige efter `public.red_decide_relation_interpretations` (linje ~16797).
- Modify: `db-migrations.sql`:
  - den nye blok (tabel + RPC, idempotent: `CREATE TABLE IF NOT EXISTS`, DO-blok til triggere og RLS som
    #244's `$marriage_ordinal_correction_table$`);
  - `to_regprocedure`-listen ved `'public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb)'` (linje ~18830).
- Modify: `db-rls.sql:706` (grant-listen), `db-verify.sql:2984` (`::regprocedure`-listen) og en tabelblok i
  `db-verify.sql`, der kopierer `private.marriage_ordinal_correction`-blokken (linje 10272-10283) til
  `private.relation_reopen`.
- Test: `tests/sql/test-relation-binding.sql`. Erstat slutningen af `$rebind_preview$` (linje 775-790) og tilføj en ny
  DO-blok `$genaabn_negativ$`.

**Interfaces:**
- Consumes: `private.relation_binding_state(uuid)` (Task 1).
- Produces:
  - `public.red_genaabn_relation_interpretation(p_interpretation_id uuid, p_expected_version integer, p_note text,
    p_context jsonb) RETURNS uuid`, SECURITY DEFINER, `SET search_path=pg_catalog,public,private`. Returnerer id'et
    for den nye `proposed`-version.
  - Tabellen `private.relation_reopen`:
    - `to_interpretation_id uuid PRIMARY KEY REFERENCES private.interpretation(id)`
    - `interpretation_key uuid NOT NULL`
    - `from_interpretation_id uuid NOT NULL UNIQUE REFERENCES private.interpretation(id)`
    - `superseded_promotion_id uuid NOT NULL REFERENCES private.interpretation_promotion(id)`
    - `from_family_id bigint NOT NULL`
    - `to_family_id bigint NOT NULL CHECK (to_family_id<>from_family_id)`
    - `spouse_source_persona_id uuid NOT NULL`
    - `spouse_identity_version integer NOT NULL CHECK (spouse_identity_version>=1)`
    - `note text NOT NULL CHECK (btrim(note)<>'')`
    - `context jsonb NOT NULL CHECK (jsonb_typeof(context)='object')`
    - `reopened_by uuid NOT NULL`
    - `reopened_by_name text NOT NULL`
    - `reopened_at timestamptz NOT NULL DEFAULT clock_timestamp()`
    - Triggerne hedder `trg_relation_reopen_append_only` og `trg_relation_reopen_no_truncate`.

- [ ] **Trin 1: Skriv den fejlende positive test.** Udvid `$rebind_preview$` efter `REBIND_FAMILY_CHANGED`-assertionen
  (linje 780-782) og før `antal batches`. Det gamle antal batches (3) tjekkes, før genåbningen.
  - Kald `red_genaabn_relation_interpretation(v_mid, <version>, 'test: familieskift',
    '{"basis":"human_sheet","line":1,"sheet_sha256":"<64×a>","rows_sha256":"<64×b>"}')` som `authenticated`.
  - Kør `SET CONSTRAINTS ALL IMMEDIATE` straks efter, så en manglende observationslink fejler i testen.
  - Assert, at den nye version:
    - har `status='proposed'`, `version` = gammel + 1, `supersedes_id=v_mid` og `decided_by IS NULL`;
    - har id = `private.content_uuid('interpretation-reopen',{key,version})`;
    - har samme antal observationslinks som `v_mid`.
  - Assert, at `private.relation_reopen` har én række med `superseded_promotion_id` = seneste binding for `v_mid`,
    samt `from_family_id` (den gamle) og `to_family_id` (den nye) korrekt.
  - Assert, at `red_preview_relation_decisions(-21201)->>'count'` er `1`. Kald `red_decide_relation_interpretations`,
    find derefter den gældende version via nøglen, preview og promovér til den nye familie, og assert
    `eligible=true` og `supersedes_promotion_id IS NULL`.
  - Assert, at `public_family_sources(ARRAY[<ny familie>])` har 1 række for ægteskabet, og at den gamle familie har 0.
  - Forælderbindingen `v_pid` er uændret gældende (søskende-analogen).
  - `RAISE NOTICE 'OK: genåbning ved familieskift'`.
- [ ] **Trin 2: Skriv negativtesten** `$genaabn_negativ$` i egen `BEGIN … ROLLBACK` med samme fixtures. Hver case
  forventer præcis sin kode (fang den med `EXCEPTION WHEN others`, og sammenlign `SQLERRM`, som resten af filen gør):

  | Case | Opsætning | Forventet |
  |---|---|---|
  | `genaabn_samme_familie` | bundet ægteskab, struktur uændret | `RELATION_REOPEN_NOT_NEEDED` |
  | `genaabn_null_tilstand` | ægtefællens identitet afgjort `unresolved` efter bindingen | `RELATION_REOPEN_STATE_INVALID` |
  | `genaabn_ikke_aegteskab` | forælderfortolkningen `v_pid` | `RELATION_REOPEN_NOT_ELIGIBLE` |
  | `genaabn_proposed` | et uafgjort ægteskab | `RELATION_REOPEN_NOT_ELIGIBLE` |
  | `genaabn_ikke_gaeldende` | id'et for en ældre version | `RELATION_REOPEN_NOT_ELIGIBLE` |
  | `genaabn_forkert_version` | `p_expected_version` = gældende − 1 | `RELATION_REOPEN_VERSION_MISMATCH` |
  | `genaabn_kontekst` | fire varianter: `basis='web'`, ekstra nøgle, `line='0'`, tom note | `RELATION_REOPEN_CONTEXT_INVALID` |
  | `genaabn_ukendt` | tilfældigt uuid | `RELATION_REOPEN_NOT_FOUND` |
  | `genaabn_rolle` | `request.jwt.claim.sub` uden redaktionsrolle | `EVIDENCE_ROLE_FORBIDDEN` |
  | `genaabn_ingen_binding` | accepteret med `family-structure-v1`, men aldrig bundet | `RELATION_REOPEN_BINDING_INVALID` |
  | `genaabn_gentaget` | andet kald med samme argumenter efter en vellykket genåbning | `RELATION_REOPEN_NOT_ELIGIBLE` |
  | `genaabn_revideret_klausul` | klausulsættet revideret efter bindingen (`clause_set_seq`+1 under samme parent, som i `test-clause-revision.sql`) | `INTERPRETATION_OBSERVATION_CLAUSE_NOT_CURRENT`, og `relation_reopen` + versionsantal uændret |

  Sidst: `RAISE NOTICE 'OK: genåbning afviser'`.
- [ ] **Trin 3: Kør og se begge fejle.** Forventet: `function red_genaabn_relation_interpretation(...) does not exist`.
- [ ] **Trin 4: Implementér tabellen**, kopieret efter `marriage_ordinal_correction` (`schema.sql:1338-1363`).
- [ ] **Trin 5: Implementér RPC'en** i formen read → lock → re-read fra `red_ret_aegteskabsnummer` (`schema.sql:15701-15769`).
  Rækkefølge:
  1. Rolle: `auth.uid()` og `current_rolle()='redaktion'`.
  2. Kontekst: nøglesættet er præcis `basis,line,rows_sha256,sheet_sha256`, med de samme regex'er som #244.
     Tom note og NULL-argumenter giver `CONTEXT_INVALID`.
  3. Fortolkningen findes, ellers `NOT_FOUND`. Lås: eksklusiv kildelås
     `pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||source_id,0))`, så nøglens gældende række
     `FOR UPDATE`, så `lock_family_rows` over tilstandens parter.
  4. Læs igen. `NOT_ELIGIBLE`, hvis rækken ikke er den gældende, `predicate<>'relation.marriage'`,
     `status<>'accepted'` eller `decision_evidence->>'method'<>'family-structure-v1'`. `VERSION_MISMATCH`, hvis
     `version<>p_expected_version`.
  5. `STATE_INVALID`, hvis `relation_binding_state` er NULL. `NOT_NEEDED`, hvis tilstandens familie =
     `decision_evidence->>'family_id'`.
  6. `BINDING_INVALID`, hvis der ikke er nogen seneste familiebinding for id'et (rækkefølge
     `promoted_at DESC, id DESC` som i previewet), eller hvis dens `target_id` ≠ `decision_evidence->>'family_id'`.
  7. INSERT den nye version med kolonnelisten fra `red_decide_interpretation` (`schema.sql:8296-8308`).
     Afvigelser: `id` = indholds-id, `status='proposed'`, `supersedes_id` = den accepterede, `decision_evidence='{}'`,
     `decided_* NULL`. Kopiér observationslinks som `schema.sql:8309-8314`.
  8. INSERT i `relation_reopen`. Aktørnavnet findes som i `red_decide_interpretation` (`profiles`).
     Ægtefællens persona og identitetsversion tages fra tilstandens `parties`.
  9. RETURN det nye id.

  Kopiér til migrationsblokken, og registrér i de fire lister (se Files).
- [ ] **Trin 6: Kør testfilen.** Forventet: begge nye NOTICE'er og alle gamle.
- [ ] **Trin 7: Kør db-verify** i den migrerede base (`tests/sql/run-db-verify-disposable.sql`). Forventet: grøn.
- [ ] **Trin 8: Commit.** `feat(248): genåbning af et accepteret ægteskab ved familieskift`.

### Task 3: Opgraderingstest og hele CI lokalt

**Files:**
- Create: `tests/sql/test-248-upgrade.sh` (kopi af `tests/sql/test-244-upgrade.sh`)
- Modify: `tests/sql/test-relation-binding-upgrade.sh:15` og `tests/sql/test-2bii-upgrade.sh:17` (uændret liste;
  kør dem kun)

- [ ] **Trin 1:** Skriv `test-248-upgrade.sh`:
  1. Byg fra `git merge-base origin/main HEAD` (prods skema efter #265).
  2. Kør de nye `db-migrations.sql` og `db-rls.sql` to gange.
  3. Assert: `to_regprocedure('public.red_genaabn_relation_interpretation(uuid,integer,text,jsonb)') IS NOT NULL` og
     `to_regclass('private.relation_reopen') IS NOT NULL`.
  4. Kør `tests/sql/test-relation-binding.sql` og derefter `run-db-verify-disposable.sql` i en anden base bygget på
     samme måde. Slutter med `echo UPGRADE_OK`.
- [ ] **Trin 2:** Kør `bash tests/sql/test-248-upgrade.sh ci248_up`, `test-relation-binding-upgrade.sh` og
  `test-2bii-upgrade.sh`. Forventet: `UPGRADE_OK` fra hver.
- [ ] **Trin 3:** Kør alle syv CI-jobs lokalt som i #265 (memory: »kør hele CI-jobbet lokalt«), inklusive
  `interpretation-proposal-db` i begge katalogrækkefølger og transfer-testene. Forventet: alle grønne.
- [ ] **Trin 4: Commit.** `test(248): opgraderingstest fra prods skema`.

### Task 4: Ægtefællearket kræver svar ved navnefælle

**Files:**
- Modify: `schema.sql:16958-17025` (`private.spouse_exception_projection`) og kopi i den nye migrationsblok
- Modify: `.claude/skills/daa-extract/scripts/spouse_exception_sheet.py`
- Test: `.claude/skills/daa-extract/scripts/test_spouse_exception_sheet.py`, `tests/sql/test-spouse-exception-projection.sql`

**Interfaces:**
- Produces:
  - Hver række i `s_rows` får nøglen `post_rivals` (integer ≥ 0): antallet af *andre* ægtefællepersonas i samme post,
    hvis kandidat nr. 1 i samme kørsel eller accepterede identitet er den samme person (`candidate_person_id`).
  - Kontrakten forbliver `spouse-exception-rows-v2`. Feltet er additivt, og Python læser det med `.get('post_rivals', 0)`.

- [ ] **Trin 1: Skriv de fejlende tests.**
  - SQL (`test-spouse-exception-projection.sql`, ny blok `post_rivals`): to uafgjorte ægtefællepersonas i samme post
    med samme kandidat nr. 1. Assert `post_rivals=1` på begge. En persona i en anden post har `0`.
  - Python:
    - `test_rival_render_ubesvaret`: en række med `post_rivals=1` renderes med en `# ADVARSEL`-linje, og S-linjen
      ender på `: ?`.
    - `test_rival_ubesvaret_afvises`: et ark med `: ?` giver `SheetError("SHEET_UNANSWERED")` i `sql`-kommandoen.
    - `test_rival_besvaret_godtages`: `?` erstattet med `A` giver gyldig SQL.
    - `test_uden_rival_uaendret`: en række uden nøglen renderes byte-identisk med i dag.
- [ ] **Trin 2: Kør og se dem fejle.** Brug `/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_spouse_exception_sheet.py -q`
  og psql-filen.
- [ ] **Trin 3: Implementér.**
  - Projektionen: et korreleret `count(*)` med samme join som vagten i Task 1, men over `source_persona_mention`'s
    persona og kandidattabellen i `v_run` (rank 1) samt `source_persona_identity` (`accepted`).
  - Python, `render_sheet`: når `post_rivals>0`, tilføj
    `#   ADVARSEL: kandidat 1 er også kandidat for {n} anden ægtefælle i posten — navnefælle? Svar S, A eller U.`
    og skriv `: ?`.
  - `S_RE` tillader `?`.
  - `check_identity` eller `sql` afviser `?` med `SHEET_UNANSWERED`, før der skrives SQL.
- [ ] **Trin 4: Kør pytest, psql-testen og `bash tests/sql/test-spouse-exception-sheet.sh <frisk base>`.**
  Forventet: alle grønne, og e2e-arket er uændret.
- [ ] **Trin 5: Commit.** `feat(248): ægtefællearket kræver svar, når kandidat 1 deles i posten`.

### Task 5: Prod-scripts, runbook og øvelse

**Files:**
- Create: `.claude/skills/daa-extract/scripts/fix_248_a_fingeraftryk.sql` (som `fix_240_ddl151_fingeraftryk.sql`, over
  `relation_binding_state`, `spouse_exception_projection`, `red_genaabn_relation_interpretation` samt tabellens
  eksistens og ACL; giver `DDL248A sha=<hex> n=<antal>`)
- Create: `.claude/skills/daa-extract/scripts/fix_248_genaabn.sql` (dataceremonien, én transaktion)
- Modify: `.claude/skills/daa-extract/scripts/fix_248_maal.sql` (ny fase `bundet`)
- Create: `docs/runbooks/248-genaabning-prod.md`
- Privat: `~/.private/5ab-overfoersel/20-248-a.sh` (handlinger `go`, `maal`, `dump`, `ddl`, `genaabn`; kopieret fra
  `18-fix-240.sh` (ddl) og `19-fix-248.sh` (resten); DDL-blokken udtrækkes mellem de to markørlinjer, og dens sha
  indgår i GO-koden)

**Interfaces:**
- Consumes: alt fra Task 1, 2 og 4.

- [ ] **Trin 1: `fix_248_maal.sql`.** Tilføj fasen `bundet`: person = up, version 2, tilstand = ufid, gældende 1 (og
  bindingens `target_id` = ufid), søskende 1, `kilder_fid=1`, `kilder_ufid=1`. Tilføj kolonnen `genaabnet`
  (antal rækker i `relation_reopen` for nøglen; findes tabellen ikke, er værdien 0 via `to_regclass`).
- [ ] **Trin 2: `fix_248_genaabn.sql`.** Bygget som `fix_248_identitet.sql`: samme `fix248`-tabel og `pg_temp`-hjælpere,
  `SET LOCAL statement_timeout='15min'`.
  - **Forhåndsbetingelser `FIX248A_PRE_*`:**
    - rolle;
    - decision set = 0;
    - pr. linje: gældende version `accepted`, `family-structure-v1` og `decision_evidence.family_id = fid`;
    - tilstandens familie = ufid;
    - gældende = 0;
    - seneste binding på fid;
    - ingen `relation_reopen`-række;
    - søskende gældende = 1.
  - **Genåbn** begge med `red_genaabn_relation_interpretation`. Kontekst:
    `{basis:'human_sheet', line:1|2, sheet_sha256:'1556cec6…5e9d764', rows_sha256:'e43be6b4…c32'}`. Note:
    `'#248 rute A: ægtefællen afgjort igen (GO 248); genåbnet for familie <ufid>'`.
  - **Afgør:** `relation_decision_set(1)`. Kræv `count=2` og at nøglerne er netop de to. Kald
    `red_decide_relation_interpretations(1, set_sha256)`.
  - **Bind:** find de gældende id'er via nøglen. Items `[{interpretation_id, family_id: ufid}]`. Kør preview
    (kræv begge `eligible`), og derefter `red_promote_relation_interpretations_batch(1, items, preview_sha256)`.
  - **Efterbetingelser `FIX248A_POST_*`:**
    - pr. linje gældende = 1 på ufid;
    - `kilder(ufid,up)=1`, `kilder(fid,bp)=1`;
    - søskende uændret;
    - `relation_reopen` har én række pr. nøgle med `superseded_promotion_id` = den gamle binding;
    - ingen `relation_classification_event` for de nye afgørelser (4° og 2° afviger ikke længere);
    - decision set = 0.
  - Slutter med `\echo FIX248A_GENAABN_OK genaabnet=2 afgjort=2 bundet=2`.
- [ ] **Trin 3: Runbook** `docs/runbooks/248-genaabning-prod.md` (form som `fix-240-dobbeltfamilier-prod.md`):
  - forventet tilstandstabel (`ddl248a` foer/efter × fase efter/bundet);
  - skridt: `go` → `maal` → `dump` → `ddl --jeg-mener-det --go` → `maal` → `genaabn --jeg-mener-det --go` → `maal`.
  - Noter:
    - rådgiveren forventes at give **+1** `rls_enabled_no_policy` (`private.relation_reopen`, med vilje);
    - `fix_240_maal.sql`'s `ddl151`-fingeraftryk ændres af DDL'en (`relation_binding_state`), og det er ikke drift;
    - overførselsværktøjets digests afviger fra GO 2-pakken (forventet);
    - fortrydelse: DDL'en via dumpets gamle definitioner; data har ingen fortryd-vej.
- [ ] **Trin 4: Den private runner** `20-248-a.sh`.
  - Kræver `--jeg-mener-det` og `--go`, og afviser ukendte argumenter (memory: prod-wrapper).
  - Fasen tjekkes før og efter hvert skrivende skridt.
  - `ddl`: én transaktion med `statement_timeout 15min`, `NOTIFY pgrst, 'reload schema'`, og fingeraftryk før og efter.
  - Output går til `$DAA_PRIVATE_DIR/248a`.
- [ ] **Trin 5: Øv på stand-in'en** (frisk kopi af `…_248t`, med en grænse på 2 minutter pr. sætning via
  `ALTER DATABASE … SET statement_timeout='2min'`):
  - hele runbooken gennem runneren;
  - negativer: forkert GO-kode, manglende flag og gentaget `genaabn` (stopper på fasen);
  - rækkediff over alle tabeller i public og private før og efter. Forventet kun:
    - `private.interpretation` +4 (2 genåbnet + 2 afgjort);
    - `private.interpretation_observation` +4×links;
    - `private.relation_reopen` +2;
    - `private.interpretation_promotion` +2 og `private.interpretation_promotion_batch` +1;
    - `private.relation_decision_*`/klassifikation +0.

  Notér GO-koden og de faktiske tal i runbookens afsnit »Prøvet«.
- [ ] **Trin 6: Commit** scripts og runbook hver for sig:
  - `feat(248): scripts til genåbningens DDL- og dataceremoni`
  - `docs(248): runbook for genåbningen i prod`

### Task 6: Afslutning før PR

- [ ] **Trin 1:** Selvreview af hele grenen mod spec'ens §3-§6. Kør derefter et uafhængigt review (Codex
  `gpt-5.6-sol` eller Fable, efter projektejerens valg) med Opus som dommer over fundene (memory: »Opus afvejer Codex-fund«).
- [ ] **Trin 2:** `docs/decisions.md`: tilføj til #248-posten, at arket nu kræver svar ved delt kandidat (præcisering
  af spec §3.3).
- [ ] **Trin 3:** Hele CI lokalt igen. Spørg derefter om push og en draft-PR.
