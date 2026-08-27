# DAA 1939 v50 fase A (kilderegnskab) — production readiness

Dato: 2026-08-18. Scope: fase A af den evidensbaserede 1939 v50-genimport —
komplet kilderegnskab på **helpost-niveau** for de 584 kilderecords, der endnu
ikke har en post-niveau-forankring i `private.source_record`. Ingen production
apply og ingen DDL er udført i dette trin; pakken indeholder kun bygger, writer,
tests og en rehearsal mod en lokal, produktionsækvivalent kopi.

## Konklusion

**GO for at forberede én fremtidig, eksplicit autoriseret production-apply af
fase A's 584 `source_evidence`-elementer.** Manifestet er deterministisk bygget
og hash-låst, writer-wrapperen er hard-låst til fase A's tælle­kontrakt
(0 `person_creates`, 0 `canonical_delta`, 584 `source_evidence`), og en
committed rehearsal mod en frisk restore af et umiddelbart prod-dump har
produceret præcis de forventede deltaer med nul ændring i alle kanoniske
tællinger. Replay er bevist idempotent.

Production-status er fortsat **NO-GO**, indtil brugeren særskilt har godkendt
apply med de eksakte hashes og identiteter nedenfor. Fase B/C og enhver
person-skabende eller kanonisk-ændrende operation er uden for denne pakke.

## Hvad pakken gør

Fase A skriver udelukkende **kildeevidens**: for hver af de 584 elementer
kaldes `public.red_apply_1939_v50_source_evidence` med
`disposition = retain_source_only`, hvilket materialiserer én helpost-record
(`private.source_record`) plus dens forankrings-/observations-lag
(`source_record_occurrence`, `source_record_anchor_current`,
`source_record_anchor_event`, `source_observation`, `source_mention`).

Ingen personer oprettes, ingen konklusion, assertion, citation, fact, relation,
familie eller cache røres. Writer-wrapperen
(`apply_phase_a_1939_v50.R` + `apply_phase_a_1939_v50_helpers.R`) kalder
bevidst **ikke** `red_apply_1939_v50_person_create` eller
`red_apply_1939_v50_canonical_delta` — fraværet er testasserteret som en
negativ "source-only"-garanti. Kaldsorden er
`connect → begin → authorize → begin_batch → 584× source_evidence → finalize →
(commit | rollback)`, serialiseret på den **delte** advisory-lås
`'daa-1939-v50-production-writer'`, så fase A ikke kan køre samtidig med
task 25-writeren i samme evidensdomæne.

CLI'en er fail-closed: den kræver **præcis ét** af `--dry-run` / `--apply`
(ingen default-apply), og afviser med `PHASE_A_1939_CLI_INVALID` og exit 1 før
enhver filsystem- eller DB-adgang. Manifestvalidering sker før `connect` —
verificeret ved at et ugyldigt manifest efterlader en tom gateway-log.

## Autoritative artefakter

| Artefakt | SHA-256 |
|---|---|
| `phase-a-anchor-manifest-v1.json` (**fil-byte**) | `1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208` |
| manifest **content** (kanonisk serialisering) | `19d72155d6e85cd54a8da3f8211a0d6272219cdee4603a6de1b35dafef9613bb` |
| `import-preview-v1.json` (task 21) | `04f2780b4fc3f63263324cbb5133e07d1eed70018f7ea11212597a26cc196ca5` |
| `database-preview-v1.json` (task 21) | `a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c` |
| `production-write-manifest-v1.json` (task 25) | `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f` |
| `boundary-materialization-v3-ditlev.json` (sider) | `73aa0eecb365de35b8e5ca38af87c7b247fbdd7d14e2ece358d86e4680056b4f` |
| Calamari-rendition (`full_ocr_calamari_r6_clean.txt`) | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` |

Alle fem input-hashes er pinnet som modul-konstanter i byggeren
(`build_phase_a_anchor_manifest_1939_v50.py`) og verificeres mod de faktiske
filbytes før parsing; enhver drift fejler lukket. Manifestets `arithmetic`
(592/8/584/543) og `counts` (0/584/0) er ligeledes hard-låst i både byggeren og
R-validatoren. Manifestet ligger under ignoreret `work/` og committes ikke.

### KRITISK: de to manifest-hashes er ikke ombyttelige

Fase A har **to** manifest-hashes med **hver sin rolle**, og de må ikke
forveksles i godkendelsen:

- **Fil-byte-SHA `1945416b…`** er integritetstjekket på selve filen. Det er
  denne værdi, CLI'ens `--manifest-sha256` verificerer.
- **Kanonisk content-SHA `19d72155…`** er feltet `manifest_content_sha256`
  *inde i* manifestet. Det er **denne** værdi, der lagres i
  `private.reimport_1939_write_batch.manifest_sha256`, og som
  `red_begin_1939_v50_reimport` (schema.sql:2406-2424) matcher på, når den
  genbruger et `finalized` batch ved en gentagen apply. Idempotensen —
  altså garantien for at et utilsigtet gentaget `--apply` ikke skriver evidens
  igen — er nøglet på `19d72155…`, ikke på fil-byte-hashet.

Empirisk bekræftet i rehearsalen: batch-rækkens lagrede `manifest_sha256` er
`19d72155…`, mens `shasum -a 256` af filen giver `1945416b…`.

## Element-regnskab

- **584 elementer = 592 − 8.** `import-preview-v1.json` har 592
  `source_records`; de 8, task 25 allerede skrev som `person_create`
  (`PRODUCTION_NEW_NAMES`), er ekskluderet.
- **Kategorier:** 576 `person` (fra `record_kind = unclassified`),
  6 `structural_context`, 2 `cross_reference`.
- **543 elementer** bærer `canonical_target.person_id` (de
  `requires_existing_anchor`-poster, hvis person-id kommer fra
  `database-preview-v1.json['person_anchors']['matched']`); byggeren asserter
  1:1-opløsning. De øvrige 41 har hverken `canonical_target` eller
  `legacy_payload` — nøglerne udelades helt, ikke sat til `null`. 13 af de 543
  har `legacy_name: null` (reelt navnløse baseline-personer, verificeret
  tilstand, ikke datafejl).
- **235 nøgler deles bevidst med task 25's claim-rows.** Task 25 skrev
  fakta-/ægteskabs-/relations-granulær evidens for 235 unikke
  `source_record_key` (`fact` 101, `marriage` 72, `relationship` 62). Fase A
  er helpost-granulær og tilføjer for disse 235 en **ny** occurrence/
  observation/mention med sin egen `occurrence_key` — ingen SQL-konflikt.
  `ON CONFLICT` bevarer de eksisterende `source_record`-rækker og deres
  `record_kind`, og `private.source_record` har append-only-triggeren
  `trg_source_record_append_only` → `reject_evidence_mutation()`, som raiser på
  ALLE UPDATE/DELETE. Overskrivning af `record_kind` er dermed **strukturelt
  umuligt**, ikke bare empirisk ikke-observeret.
- Identiteten holder på begge sider: 584 = 349 nye records + 235 delte.

## Rehearsal mod frisk produktionsækvivalent restore

Kørt i `daa1939_phase_a_rehearsal1` — en frisk restore af et umiddelbart
prod-dump taget med det allow-listede backup-script (kun `DEST`-linjen ændret):
`daa-local-phase-a-rehearsal-20260818-175344.dump`, mode 600, 4.746.282 bytes,
sha256 `ddcc4c788425a60040a5baa3217a325615c2de025470d2d4834440e5792a2223`.
Lokal PostgreSQL 17, adskilt fra produktion. Kontroltal efter restore matchede
eksakt: `person` 1812, `private.source_record` 243,
`source_record_anchor_current` 313, `source_persona` 8; begge eksisterende
reimport-batches i terminal (ikke-`open`) tilstand. Aktør:
`ba4ce28d-42a0-48af-a47c-773c26934236` (`profiles.rolle = 'redaktion'`).
Fuld rapport med alle kommandoer:
`work/task25-1939-v50-production-writer/phase-a-rehearsal-report.md` (ignoreret
`work/`, ikke committet).

**Dry-run** (`--dry-run`): exit 0, `status=finalized`, `committed=false`, 584
`source_evidence` forudset. Baseline før/efter er **byte-identisk** — begge
filer sha256 `cc4dad3e3dd5c62ab3a1f070b53e9fb7f33c46c20a735512a68c4a8f2836cd53`.

**Apply** (`--apply`): exit 0, `status=finalized`, `committed=true`, batch
`3b1882e2-7f9d-484e-a7d2-f607bc3dfbc6` med
`observed_counts = {person_creates: 0, canonical_delta: 0, source_evidence: 584}`
og 584 write-events, alle `operation='source_evidence'`.

| Tabel | Pre | Post | Delta |
|---|---|---|---|
| `private.source_record` | 243 | 592 | +349 |
| `source_record_occurrence` | 313 | 897 | +584 |
| `source_record_anchor_current` | 313 | 897 | +584 |
| `source_record_anchor_event` | 313 | 897 | +584 |
| `source_observation` | 313 | 897 | +584 |
| `source_mention` | 313 | 897 | +584 |
| `extraction_run` | 1 | 2 | +1 |
| `source_persona` | 8 | 8 | 0 |
| `source_rendition` | 1 | 1 | 0 |

**Alle kanoniske tællinger uændrede** pre→post, byte-lige i selve
baseline-JSON-filerne (ikke kun i et efterfølgende re-query): `person` 1812,
`person`-med-`staged=true` 96, `narrative` 1170, `fact` 7199, `assertion` 9304,
`citation` 8582, `conclusion` 9215, `relation` 2031, `family` 682,
`family_member` 2258, `person_external_id` 1168.

De 349 nye records fordeler sig `person` 341, `structural_context` 6,
`cross_reference` 2. `record_kind`-bevarelsen er verificeret **nøgle for
nøgle**: alle 243 delte record-keys er byte-identiske pre→post (0 ændrede
rækker). Identiteten 584 = 349 + 235 er bekræftet på anchor-event-niveau via
join (`anchor_event → occurrence` [ny kørsel] `→ source_record`, grupperet på om
recorden er ny): 349 anchor-events på nye records, 235 på eksisterende.

**Replay-kontrol:** samme `--apply`-kommando kørt igen → exit 0,
`status=already_applied`, **samme** `batch_id` `3b1882e2…`, ingen ny batch og
**nul nye evidensrækker**. Eneste ændring er én ekstra
`reimport_1939_authorization`-række (bogholderi): `red_authorize_…` indsætter
ubetinget en ny autorisationsrække, hvorefter `red_begin_…` genbruger det
eksisterende `finalized` batch uden at omkoble `write_batch.authorization_id`.
Et utilsigtet gentaget `--apply` lækker altså én forældreløs
autorisationsrække, men rører ikke evidensen. Dry-runs er bogholderi-gratis
(0 nye autorisationsrækker).

Hele rehearsalen er **uafhængigt genopmålt af reviewer** direkte mod den
efterladte live-DB og de efterladte JSON-filer (read-only `psql`/`shasum`/`cmp`)
— alle tal og hashes matcher eksakt. Verdikt: Approved, ingen Critical, ingen
Important.

## Frisk verifikation

- **Python:** 22/22 i `test_build_phase_a_anchor_manifest_1939_v50.py`
  (inkl. et reelt-artefakt-testcase, der kører — ikke skip'et); fuld suite
  `1732 passed, 3 skipped`.
- **R:** writer-kontrakten `PASS 80 assertions`; fuld suite
  `FAIL 0 | PASS 813` (WARN 3 / SKIP 2 er præeksisterende og urelaterede —
  samme benigne `--file=`-detektionsadvarsel og lokal-DB-smoke-skips).
- **Begge tasks reviewet, og fix-runden er lukket:** gren-præcise tests for
  tvetydigt boundary-opslag, begge `ANCHOR_LOOKUP_FAILED`-grene,
  `OUTPUT_EXISTS` og den literalt pinnede 11-nøgle-payloadkontrakt;
  byte-verificeret kanonisk serialisering Python↔R (round-trip på tre virkelige
  operationer, inkl. `legacy_name: null`); delt advisory-lås
  `'daa-1939-v50-production-writer'`; CLI kræver eksplicit `--dry-run|--apply`;
  positiv **og** negativ RPC-navnekontrol i writerens krop.
- **Credentialscan** over de nye/ændrede filer i pakken
  (`apply_phase_a_1939_v50.R`, `apply_phase_a_1939_v50_helpers.R`,
  `build_phase_a_anchor_manifest_1939_v50.py`,
  `test_apply_phase_a_1939_v50.R`,
  `test_build_phase_a_anchor_manifest_1939_v50.py`,
  `tests/testthat/test-apply-phase-a-1939-v50.R`) med mønstrene
  `eyJ…` / `postgres://…:…@` / `service_role` / `sb_secret` / `password=`:
  **0 hits** i alle seks filer.
- `git diff --check`: **grøn**.
- Ingen verbatim-tekst er printet eller logget nogen steder i pakken (kun
  tælle-/hash-/strukturkontrol) — invariant 8.

## Kendte noter og forbehold

1. **Lokal `GRANT USAGE ON SCHEMA auth TO postgres`** var nødvendig på
   rehearsal-basen, fordi restoren dropper en flerlinjers GRANT-blok, når
   `dashboard_user` ikke findes lokalt. Det er et **restore-artefakt**:
   produktionen har grants nativt fra Supabase (task 25-writeren kørte dér
   uden indgreb). Autorisationsgatet blev **ikke** svækket —
   `require_reimport_1939_editor()` kræver fortsat
   `auth.uid() IS NOT NULL AND current_rolle() = 'redaktion'`, og empirisk test
   bekræfter at `auth.uid()` returnerer netop `DAA_REIMPORT_ACTOR_ID`.
2. **Produktionen har allerede én præeksisterende forældreløs
   `reimport_1939_authorization`-række** (fra tidligere aktivitet, uafhængig af
   fase A). I rehearsal-basen fandtes 5 autorisationsrækker i alt efter replay,
   **alle** med `status='consumed'` (ingen `issued`/`expired`). Efterkontrollen
   må derfor ikke antage et bestemt totalantal, kun deltaerne.
3. **`person_staged` er ikke en tabel** — betegnelsen dækker
   `count(*) FROM person WHERE staged = true`. Nævnt fordi tallet 96 optræder i
   baselines under det label.
4. **`db-verify.sql`s kendte, urelaterede røde blok** (`regen genskabte ikke
   visning_navn`) gælder fortsat og fejler identisk på uændrede HEAD-filer;
   db-verify køres scoped, jf. `docs/database-current-state.md`.
5. **Vault-filtreringen fjernede 10 TOC-linjer** (ikke ~4 som opskriften
   antydede) — de 6 ekstra er ACL-linjer på vault-funktioner/-tabeller. Alle
   nævner utvetydigt `vault`; substansen uændret.
6. **`--preview-sha256` er kun formatvalideret** (64-hex) i wrapperen, ikke
   krydstjekket mod manifestets `input_hashes` — samme mønster som den
   eksisterende task 25-writer. Værdien er derfor en del af den eksplicitte
   godkendelse nedenfor, ikke en maskinel invariant. Controller-ruling:
   `--preview-sha256` = **database**-previewets SHA `a00efd43…` (som brugt i
   rehearsalen).
7. Manifestets `arithmetic`-lås (592/8/584/543) er strengere end strengt
   krævet. En fremtidig, legitim fase-A-batch med andre tal vil kræve, at
   låsen løsnes bevidst.

## Gates og krævet fremtidig godkendelse

Stoptilstande i den nuværende kæde: forkert eller drevet input-hash (alle fem),
forkert manifest-fil-byte-hash, `counts`/`arithmetic`-afvigelse, manglende
eller dobbelt tilstandsflag, manglende `redaktion`-aktør, ikke-64-hex
preview-SHA, verbatim-drift mod Calamari-renditionen, manglende eller tvetydigt
boundary-sideopslag, `page_from < 1`, samt eksisterende output-fil.

Før en production apply skal en ny, eksplicit brugergodkendelse navngive:

1. **produktionsdatabasen** `postgres` / system identifier
   `7642734024280108049`;
2. en **ny umiddelbar backup** med eksakt sti, mode `0600`, bytestørrelse og
   SHA-256 (taget umiddelbart før apply — rehearsal-dumpet `ddcc4c78…` tæller
   ikke);
3. **manifest fil-byte-SHA-256**
   `1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208`
   (CLI'ens `--manifest-sha256`) **OG** **manifest content-SHA-256**
   `19d72155d6e85cd54a8da3f8211a0d6272219cdee4603a6de1b35dafef9613bb`
   (batchens lagrede `manifest_sha256` og idempotens-nøglen) — begge, med hver
   sin rolle, jf. afsnittet ovenfor;
4. `--preview-sha256` =
   `a00efd43a34358f95f4b0df40695f4abd3b279066bee196e3cbdbd1b87b9e97c`;
5. `DAA_REIMPORT_ACTOR_ID` = en **redaktions-profil** (`profiles.rolle =
   'redaktion'`) i produktionen;
6. **præcis én `--apply`, uden retry** — replay er bevist idempotent for
   evidensen, men lækker én forældreløs autorisationsrække, så en gentagelse
   skal være et bevidst valg, ikke en refleks;
7. en **read-only efterkontrol** mod produktionen med samme tal som
   rehearsalen: `source_record` +349 (til i alt 592),
   occurrence/anchor_current/anchor_event/observation/mention +584 hver (til i
   alt 897), `extraction_run` +1, `source_persona` uændret 8, præcis én ny
   `finalized` batch med 584 `source_evidence`-write-events, og **nul** ændring
   i de kanoniske tællinger (person 1812, narrative 1170, fact 7199, assertion
   9304, citation 8582, conclusion 9215, relation 2031, family 682,
   family_member 2258, person_external_id 1168, staged 96).

Indtil alle syv punkter er navngivet i en eksplicit godkendelse, er production
apply **NO-GO**.
