# Offentlige kilderecord-versioner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Vis hver publiceret kilderecord som sin egen biografiversion uden at eksponere private record-id'er eller skjule legacy-narrativer.

**Architecture:** En privat, redaktionelt styret publiceringsbinding forbinder et offentligt `narrative` med højst én privat `source_record` og bærer en tilfældig offentlig `record_ref`, en menneskelig recordetiket og en citation. En `SECURITY DEFINER` read-RPC læser kun offentlige personer/narrativer og enten publicerede bindinger eller uforbundne legacy-narrativer. Web og mobil bruger RPC'en ved persondetaljen; hvis den ikke findes endnu, bevarer de den eksisterende editionsbaserede læsning.

**Tech Stack:** PostgreSQL 17, Supabase RLS/`SECURITY DEFINER`, TypeScript, Vitest/Jest, React og React Native.

## Global Constraints

- Migrationerne er additive; `narrative` og den eksisterende direkte læsevej må ikke ændres eller slettes.
- `private.source_record.id`, OCR, kandidatscorer, redaktionelle noter og ikke-publicerede bindingsrækker må aldrig returneres fra den offentlige RPC.
- En publiceret binding kræver en eksisterende privat source-record, et eksisterende offentligt narrativ og en offentlig person; der findes ingen automatisk legacy-mapping.
- En eksisterende narrativ uden nogen binding returneres som `legacy_narrative` med `record_ref=NULL`; findes en upubliceret/tilbagetrukket binding, returneres den ikke som legacy.
- Kun `source.slags='DAA-udgave'` indgår i biografiversioner, som i den eksisterende `buildBioVersions`-gate.
- `load_daa.R` og den fail-closed evidence-promotionvej ændres ikke.
- Kør `git branch --show-current` før hver mutation og commit; anvend kun en lokal testdatabase, aldrig produktion.

---

### Task 1: Privat publiceringsbinding og offentlig read-RPC

**Files:**
- Modify: `schema.sql`
- Modify: `db-migrations.sql`
- Modify: `db-rls.sql`
- Modify: `db-verify.sql`

**Interfaces:**
- Produces `private.narrative_record_publication(narrative_id,source_record_id,record_ref,record_label,citation_label,status)`.
- Produces `public.public_person_bio_source_versions(p_person_ids bigint[])`, der returnerer `person_id`, `record_ref`, `source_label`, `record_label`, `narrative_text`, `citation_label`, `provenance_kind`.

- [x] **Step 1: Skriv den fejlede DB-kontrakt**

Tilføj en isoleret `DO`-blok til `db-verify.sql`, der opretter én offentlig person, to DAA-narrativer, én privat source-record og én `published` binding. Den skal kræve to resultater: den bundne række har en ikke-NULL opaque `record_ref` og `provenance_kind='source_record'`; den ubundne række har `record_ref IS NULL` og `provenance_kind='legacy_narrative'`. Tilføj negative assertions for privat person, privat narrativ, draft-binding og læk af private UUID-felter.

- [x] **Step 2: Kør kontrakten rødt**

Kør `psql -v ON_ERROR_STOP=1 -f db-verify.sql` mod den disposable database. Forvent fejl, fordi bindingstabellen og RPC'en ikke findes.

- [x] **Step 3: Implementér minimal binding og RPC**

Opret append-only `private.narrative_record_publication` med én række pr. narrativ, UUID `record_ref DEFAULT gen_random_uuid()`, redaktionel `record_label`/`citation_label` og status `draft|published|withdrawn`. Opret `red_publicer_narrative_record(...)` og `red_tilbagetraek_narrative_record(...)` som redaktion-gatede `SECURITY DEFINER`-veje. RPC'en må kun returnere den navngivne syv-kolonners projektionsform; den filtrerer med `person_offentlig`, `narrative.privat=false`, DAA-slag og binding-status.

- [x] **Step 4: Kør DB-kontrakten grønt**

Kør den samme DB-verifikation på en frisk database og bekræft, at anon/authenticated ikke kan læse bindingstabellen eller kalde redaktionsmutationerne.

- [x] **Step 5: Commit** (`5dccf19`)

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git commit -m "feat: expose published source record narratives safely"
```

### Task 2: Record-bevarende core-kontrakt

**Files:**
- Modify: `packages/core/src/bioVersions.ts`
- Modify: `packages/core/src/types.ts`
- Modify: `packages/core/src/index.ts`
- Modify: `packages/core/src/__tests__/bioVersions.test.ts`

**Interfaces:**
- Produces `BioSourceVersion` med `recordRef: string | null`, `provenanceKind: 'source_record' | 'legacy_narrative'`, én tekst per publiceret record.
- Bevarer den eksisterende `BioVersion`/`buildBioVersions` uændret til fallback-klienter.

- [x] **Step 1: Skriv en fejlet core-test**

Tilføj en test med to rækker fra samme bog men forskellige `recordRef`; resultatet skal have længde to, i deterministisk record-label rækkefølge, uden tekstsammenfletning. Tilføj en legacy-række og assertér `recordRef=null` samt `provenanceKind='legacy_narrative'`.

- [x] **Step 2: Kør testen rødt**

```bash
npm test --workspace packages/core -- --run src/__tests__/bioVersions.test.ts
```

- [x] **Step 3: Implementér den minimale builder**

Tilføj `buildBioSourceVersions(rows)` som validerer den offentlige RPC-form, filtrerer tom tekst og returnerer hver række individuelt. Den må aldrig modtage eller repræsentere private source-record UUID'er.

- [x] **Step 4: Kør core-testene grønt** (`28` filer / `411` tests; typecheck grøn)

```bash
npm test --workspace packages/core -- --run
npm run typecheck --workspace packages/core
```

- [x] **Step 5: Commit** (`861244e`)

```bash
git add packages/core/src/bioVersions.ts packages/core/src/types.ts packages/core/src/index.ts packages/core/src/__tests__/bioVersions.test.ts
git commit -m "feat: preserve public source records in bio versions"
```

### Task 3: Bagudkompatibel web- og mobillæsning

**Files:**
- Modify: `web/src/data/public.ts`
- Modify: `web/src/components/DetailPanel.tsx`
- Modify: relevant web tests
- Create: `mobile/src/data/publicBioVersions.ts`
- Modify: `mobile/src/app/person/[id].tsx`
- Create/Modify: relevant mobile tests

**Interfaces:**
- Web og mobil kalder kun `public_person_bio_source_versions`; den eksisterende editionsbaserede data bruges som fallback, når RPC'en endnu ikke er deployet.
- UI viser bog + recordetiket per version og mærker `legacy_narrative` som overgangsdata.

- [x] **Step 1: Skriv fejlede klienttests**

Test RPC-mapping af to records fra samme bog, en legacy-række og et svar med et ekstra privat UUID-felt. UI-data skal bevare de to records, vise legacy-mærkning og ignorere ukendte felter. Test fallback, når RPC'en mangler, mod det eksisterende `buildBioVersions`-resultat.

- [x] **Step 2: Kør tests rødt**

```bash
npm test --workspace web -- --run
npm test --workspace mobile -- --runInBand
```

- [x] **Step 3: Implementér on-demand læsning og visning**

Web erstatter kun detaljens versionsdatasæt; standardbio er stadig første version. Mobil henter versionsdata efter personvalg, annullerer/ignorerer forældede svar og beholder `person.bio` indtil RPC-svaret findes. Begge UI'er viser ikke en recordvælger, hvis kun én version er synlig.

- [x] **Step 4: Kør fuld klientverifikation** (web: `57` filer / `661` tests og build grøn med lokale offentlige Supabase-pladsholdere; mobil: `30` suiter / `425` tests og `tsc --noEmit` grøn)

```bash
npm test --workspace web -- --run
npm run build --workspace web
npm test --workspace mobile -- --runInBand
npm run typecheck --workspace mobile
```

- [x] **Step 5: Commit** (`5a06e64`, `d0bb4b6`)

```bash
git add web/src mobile/src packages/core/src
git commit -m "feat: show distinct public source narratives"
```

### Task 4: Samlet migrations- og deploygate

**Files:**
- Modify: `docs/superpowers/plans/2026-08-02-evidensbaseret-genimport-og-multislaegt.md`

- [x] **Step 1: Kør frisk og migreret DB-verifikation**

Frisk `daa_task15_fresh_20260803` passerede Task 15-kontrakten. Den samlede `db-verify.sql` nåede en eksisterende, ikke-Task-15-fejl ved den gamle visning-navn-regression. Den historiske lokale kopi `daa_baseline` manglede Supabase's `auth.users`; med en minimal lokal stub passerede Task 15-kontrakten efter `db-migrations.sql` og `db-rls.sql`, hvorefter den samlede verifier senere stoppede i en eksisterende rolleforventning (`EVIDENCE_ROLE_FORBIDDEN`). Ingen produktionsdatabase blev brugt.

Kør `schema.sql`, `db-rls.sql` og `db-verify.sql` på en tom, lokal PostgreSQL-database og derefter migrationsvejen på en historisk kopi. Notér præcist resultat og eventuelle miljøbegrænsninger.

- [x] **Step 2: Bekræft deployrækkefølge**

Deployrækkefølge: (1) anvend Supabase-migrationen og read-RPC'en, (2) smoke-test som anon at RPC'en kun giver den navngivne offentlige projektion, (3) deploy Vercel-webklienten og derefter mobilklienten. Ved rollback rulles klienten først tilbage; allerede publicerede bindingsrækker trækkes kun tilbage ved en eksplicit redaktionel beslutning. Produktion er ikke ændret og kræver særskilt accept.

Dokumentér: Supabase-migration og read-RPC først, derefter Vercel; smoke-test anon-læsning; rollback af Vercel før eventuel tilbagetrækning af publiceringsbindinger. Produktionsmigration kræver særskilt brugeraccept.

- [x] **Step 3: Opdatér hovedplan og commit**

Markér kun Task 15-felter som færdige ved observeret testresultat.

```bash
git diff --check
git status --short
git add docs/superpowers/plans
git commit -m "docs: verify public source narrative rollout"
```
