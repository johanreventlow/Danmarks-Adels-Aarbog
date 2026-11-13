# Trin 6e-2 — kildeetiket, trykte sider og 1939's koordinater: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Læseren ser 1939's poster med bogens egen opslagsnøgle og særtrykkets trykte side (»DAA 1939, s. 49 · IV, nr. 3«), linjens navn ved begge udgaver, 1939's linjer og B6-noten fra placement, og koordinat-RPC'en bliver billigere.

**Architecture:**
- **DB (tre dele):**
  - Et sidekort som data på `public.source`, læst af én omregningsfunktion.
  - En editionsneutral etiketregel: poster uden bogtrykt nøgle får linjekode og nr.
  - En koordinat-RPC med 1939's entydige nøgle og trykt startside.
- **Ceremoni:** genpublicerer de 563 1939-bindinger gennem 6d-1's revalideringssti, i én transaktion.
- **Klient:**
  - Logikken ligger DOM-fri i `packages/core`.
  - Klienten tåler både før- og eftertilstanden og deployes derfor først.

**Tech Stack:** PostgreSQL 17 (Supabase), plpgsql/SQL, psql-scripts; TypeScript, React (Vite), vitest, Playwright; npm workspaces.

**Spec:** `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md`. Læs §5.6, §5.7, §6, §8 og **§12 (tillæg 2026-11-13, afløser dele af §5.6-5.7)**. Task 0-rapporten fra 2026-11-13 er grundlaget for §12.7; Task 0 nedenfor genbekræfter kun det, der mangler.

## Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (b) og læservisningen af (c) (B6).
2. **Værdikædeled:** offentlig læseprojektion med forståelig kildehenvisning.
3. **Leverancetype:** generel og editionsneutral, plus én lille udgaveprofil som data (1939's sidekort; decisions 2026-11-13).
4. **Værdi:** læseren kan slå hver 1939-post op i bogen. Romertallenes forskellige betydning i de to bøger skjules ikke.
5. **Færdigbevis:** spec §8 med tillæggets punkt om trykte sider.
6. **Erstatter:** `record-<uuid>` som etiket, PDF-sider i læseren, legacy-linjen »1939« og koordinat-RPC'ens fald til legacy for kilde 3.
7. **Review-budget (B13):** 1 Codex-runde (`gpt-6.1-sol`) på tillæg + plan og 1 på diffen før prod. Opus afvejer hvert fund.

## Afvigelse fra den aftalte rækkefølge (meldes til projektejeren)

Den aftalte rækkefølge var:
1. en lille ændring, så klienten tåler den nye tilstand;
2. DDL og ceremoni;
3. 6e-2's webdel til sidst.

Planen samler i stedet hele webdelen i trin 1 (Del B). Klienten er bygget, så den viser prod korrekt både før og
efter DDL (Task 8). Så findes der ikke et vindue, hvor databasen er ændret, men klienten ikke er.

## Global Constraints

- **Prod-rækkefølge:**
  1. Klienten (Del B) deployes først og skal vise prod korrekt *før* DDL.
  2. Derefter DDL (Del A).
  3. Derefter data-ceremonien (Del C).
  4. Til sidst browsertjek.
- **Prod** røres kun i projektejerens shell med GO (`--jeg-mener-det --go <kode>`). AI'en kører kun mod lokale baser.
  - Dump før DDL og før data.
  - Vinduesvagten bruges fra starten.
  - Fortrydelse = restore af data-dumpet + forrige funktionsdefinitioner fra runbooken + `db-rls.sql`.
- **`schema.sql` er source of truth.**
  - `db-migrations.sql` får én ny blok sidst i filen: `-- ===== trin 6e-2: kildeetiket, sidekort og koordinater =====`.
  - Ændrede funktioner har byte-ens krop i begge filer. Migrationen er idempotent (to kørsler).
  - Ældre blokke redigeres ikke, undtagen de to spejlede steder i Task 2 (CHECK `:7837`, validator `:9607`), hvis blokken ellers ikke kan gøre dem idempotente. Foretræk en ny `ALTER` i den nye blok.
- **Kilde 1 (2018-20) byte-ens:**
  - `record_label`/`citation_label` på alle 587 bindinger og deres seneste hændelser.
  - De gamle kolonner i `public_person_source_coordinates()` for `source_id<>3`.
  - Basislinjerne er `66e9afd96e1b201a55c3984c0c1d66a3` (544 koordinatrækker) og `d97decc71a3621127abb3f8122d8ed7a` (587 etiketter: `binding_id|record_label|citation_label` sorteret efter binding_id) på stand-in `daa5ab_ddl_standin_20261113070325_6e2`. Kun lokale sammenligningspunkter; prod hashes før og efter.
- **Ingen editionsnavngiven permanent overflade.** Ingen regel nævner 1939, 2018-20 eller `source_id=3`. Scripts er kildeparametriserede (`-v src=3`). Ceremoni- og målescripts må bære trinnavn.
- **Ingen påstand, konklusion, citation eller `narrative.side` ændres.** Kun `source.sidekort`, `lineage_scheme_entry.label` (5 rækker), bindingernes to etiketter og nye publiceringshændelser.
- **Indhold pinnes, ikke id'er.** Linjeskemarettelser nøgles på `(source_id, code, label_foer)`, aldrig på entry-id fra stand-in'en.
- **Tekster (ordret):**
  - Postetiket: `<kode>, nr. <nr>` / `<kode>` / `''`.
  - »Kilde i Aarbogen«: `<kode>. <navn>[, s. <side>][, nr. <nr>]`.
  - Kort nummer: `<kode>[, s. <side>][, nr. <nr>]`.
  - B6: `✓ også i <udgave> (<kode>. <navn>)` og `<udgave> placerer i: <kode>. <navn>`.
  - Sideformen er altid `s. N` (`sideForm`).
- **PII:**
  - `work_1939_stamtavle/` må læses (projektejer 2026-11-13).
  - `work/` og `work_presens/` må aldrig læses.
  - `~/.private` røres ikke af implementere, heller ikke med `ls`.
  - Databaser droppes ikke; de listes.
- **Miljø:** `env -u PGOPTIONS` foran psql, `env -u NODE_OPTIONS` foran npm. Prods `statement_timeout` er 2 min for læsere, anon 3 s. Stand-in-tid er ikke prod-tid.
- **Hele CI lokalt før hver PR:** node-jobbet (`npm run test -w @daa/core && npm run typecheck -w @daa/core && npm run test -w web && npm run build -w web && npm --workspace mobile exec -- tsc --noEmit && npm test -w mobile`) og, for Del A/C, de berørte PostgreSQL-jobs fra `.github/workflows/ci.yml`.
- **Commits:** ét pr. task, Conventional Commits på dansk, trailer `Claude-Session: https://claude.ai/code/session_01VptDwx7y65uV3GSf7fTmx2`. PR'er `--draft`. Intet push uden projektejerens ja.
- **Grene:** Del B på `feat/trin6e2-klient`, Del A + C på `feat/trin6e2-db`, begge fra `docs/trin6e2-tillaeg`.

## Review Focus

1. **1939-person uden placement og uden binding, kun med citationer** (ægtefæller): »Kilde i Aarbogen« viser »DAA 1939, s. N« eller »DAA 1939«, aldrig »Linje 1939« eller en PDF-side. Test i Task 5 og Task 6.
2. **Et sideinterval over en planche eller uden for kortet** (`555-571`, `599`, `4`): viser aldrig en uomregnet PDF-side. Test i Task 1.
3. **En foldet person med to rækker i samme udgave** (Conrad 255 III-58 / 392 V-1):
   - personsidens nummer følger den biografi, siden åbner på;
   - B6 viser linjer uden note.
   
   Test i Task 5 og Task 7.
4. **Klienten mod prod før DDL** (ingen `printed_page`, kilde 3 kun legacy, `record-`-etiketter): samme visning som i dag, bortset fra de tilsigtede rettelser. Test i Task 8.
5. **En kilde uden sidekort** med interval »201-202«: uændret overalt. Test i Task 1 og Task 2.

---

### Task 0: Restmåling på stand-in (kun læsning; ingen commits)

Kør mod `daa5ab_ddl_standin_20261113070325_6e2` med `PGOPTIONS='-c default_transaction_read_only=on'`. Skriv rapporten til scratchpad som `6e2-task0b.md`. Kun tal, id'er og koder.

- [ ] **Step 1:** Når 1939's `citation.citat_tekst` (»DAA 1939 side N«) frem til læseren?
  - Spor `model.ts:220` (forældre_ukendt) og `public.ts:225` (kun `source_id IS NULL`).
  - Forventet: nej. Hvis ja, tilføjes vejen til Task 6.
- [ ] **Step 2:** Hvilke publicerede bindinger har en placement i entry 6, 57, 58 eller 59? Forventet: alle blandt de 563 med `record-`-etiket.
- [ ] **Step 3:** Indgår etiketten for entry 6, 57, 58 og 59 i medlemskabernes `source_basis`, placement-evidensen eller `membership_state`? Forventet: nej (som for 61).
- [ ] **Step 4:** Citationen med `side='4'`: assertion, faktatype og om den vises offentligt.
- [ ] **Step 5:** Tæl de 39 offentlige kilde 3-koordinatrækker uden gældende medlemskab. Har hver en publiceret binding, så startsiden kan findes? Forventet: 34 + 5; antal uden binding.
- [ ] **Step 6:** Tæl kilde 3-placements med mere end én accepteret placement pr. record. Forventet: 0.
- [ ] **Step 7:** Projektejeren får rapporten. En afvigelse fra en forventning stopper planen her.

**Allerede prøvet (2026-11-13, BEGIN … ROLLBACK på stand-in'en, med redaktionsaktøren):**
- De 5 linjeetiketter gør **252** af de 563 publicerede kilde 3-bindinger `stale_published`. Spec'ens 103 gjaldt
  kun linje III.
- `placement_header_violations(3)` = 0 med de nye etiketter.
- En binding med ændrede etiketter bliver `stale_published`, og `red_revalider_person_narrative_record` godtager den
  med en `revalidated`-hændelse (stale 253 → 252).
- Mekanismen er dermed bekræftet. Task 9 genbruger den.

## Del A — DDL (gren `feat/trin6e2-db`)

### Task 1: Sidekort og omregning

**Files:**
- Modify: `schema.sql` (ved `public.source`-tabellen og efter `public_person_source_coordinates`), `db-migrations.sql` (ny blok), `db-verify.sql`
- Test: `tests/sql/test-6e2-sidekort.sh` (ny; mønster som `tests/sql/test-6d3-upgrade.sh`), tilføjes til `ci.yml`

**Interfaces:**
- Produces:
  - `public.source.sidekort jsonb NULL`. NULL betyder, at kildens sider allerede er trykte sider.
    - Form: `[{"pdf_fra":int,"pdf_til":int,"trykt_fra":int}, …]`, sorteret og uden overlap.
    - CHECK via `private.sidekort_gyldigt(jsonb) RETURNS boolean IMMUTABLE`.
  - `public.source_trykt_side(p_source_id bigint, p_side text) RETURNS text STABLE SECURITY INVOKER`.
    - `p_side` NULL → NULL. Kildens `sidekort` NULL → `p_side` uændret.
    - `'N'` → trykt side eller NULL.
    - `'N-M'` → `'a-b'`, eller `'a'` hvis ens. NULL, hvis en af enderne er uden for kortet.
    - Alt andet → NULL.
  - `public.side_trykt(c public.citation) RETURNS text STABLE` = `source_trykt_side(c.source_id, c.side)` (PostgREST computed field).
  - `EXECUTE` til `anon, authenticated` på begge.

- [ ] **Step 1: Skriv den fejlende test.** Fixture-kilde med kortet fra spec §12.3: `[{490,545,1},{547,548,57},{550,555,59},{571,598,65}]`.

```sql
-- forventet (input → output)
('490','1') ('541','52') ('545','56') ('546',NULL) ('547','57') ('549',NULL) ('550','59') ('555','64')
('556',NULL) ('570',NULL) ('571','65') ('587','81') ('598','92') ('599',NULL) ('4',NULL) ('abc',NULL)
('541-542','52-53') ('555-571','64-65') ('546-547',NULL) (NULL,NULL)
-- kilde uden sidekort: ('201-202','201-202') ('4','4')
-- CHECK afviser: overlap [{490,545,1},{540,550,60}], usorteret, manglende nøgle, pdf_fra>pdf_til, tom liste
-- side_trykt(citation) på en fixture-citation med side '538' → '49'
```

- [ ] **Step 2:** Kør `bash tests/sql/test-6e2-sidekort.sh`. Forventet: FAIL (funktionen findes ikke).
- [ ] **Step 3:** Implementér i `schema.sql`, spejl ordret i den nye migrationsblok, og tilføj `db-verify.sql`-asserts.
  - Asserts:
    - funktionerne findes;
    - kald under `SET ROLE anon` lykkes for både `source_trykt_side` og `side_trykt`. Begge er INVOKER og læser
      `source.sidekort`, så kolonnen skal være læsbar for anon;
    - `db-verify` kontrollerer kortets gyldighed (`sidekort IS NULL OR private.sidekort_gyldigt(sidekort)`) og
      funktionernes kontrakt med både NULL og et udfyldt fixture-kort.
    - At `sidekort` er NULL efter migrationen er en førtilstand i opgraderingstesten, **ikke** en db-verify-invariant
      (Codex r1 #7): ceremonien udfylder kortet, og migrationen må ikke nulstille det ved genkørsel.
- [ ] **Step 4:** Kør testen og migrationen to gange på en kopi af stand-in'en. Forventet: PASS, og 2. kørsel ændrer intet.
- [ ] **Step 5: Commit** `feat(6e): sidekort som kildedata og omregning til trykt side`

### Task 2: Etiketreglen og tom postdel

**Files:**
- Modify: `schema.sql`:
  - `:3667`: bindingens CHECK.
  - `:12083`: validatoren.
  - `:14539-14610`: `narrative_record_labels`.
  - Ny funktion foran den.
- Modify: `db-migrations.sql` (ny blok), `db-verify.sql`
- Test: `tests/sql/test-6e2-etiket.sh` (ny), tilføjes til `ci.yml`

**Interfaces:**
- Consumes: `public.source_trykt_side` (Task 1).
- Produces:
  - `private.linje_kode(p_label text, p_code text) RETURNS text IMMUTABLE`.
    - Det ledende romertal eller bogstav i `^([IVXLC]+|[A-Z])\.\s` fra etiketten, ellers `p_code`.
  - `private.narrative_record_wanted_labels(p_source_record_id uuid) RETURNS jsonb` med `{record_label, citation_label}`.
    - `record_key !~ '^record-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'` → `record_label = record_key`.
    - Ellers efter antallet af accepterede placements:
      - 0 → `''`.
      - 1 → `linje_kode(entry.label, entry.code) || CASE WHEN printed_number IS NOT NULL THEN ', nr. '||printed_number ELSE '' END`.
      - over 1 → `RAISE 'RECORD_LABEL_PLACEMENTS_AMBIGUOUS'`.
    - `citation_label` = `<udgave>, s. <intervaller>`.
      - Intervallerne er ankrenes `page_from[-page_to]` omregnet med `source_trykt_side` og forbundet med `', '`.
      - Et interval, der giver NULL, udelades. Uden intervaller → kun `<udgave>`.
  - `narrative_record_labels`: stien uden binding bruger `narrative_record_wanted_labels`. Bindingens tilsidesættelse (`:14595-14604`) er uændret.
  - Bindingens CHECK: `record_label = '' OR btrim(record_label) <> ''` (NOT NULL bevares). Validatoren tillader `''` med samme regel.
  - Begge dele gennem en idempotent `ALTER` i den nye blok, som spejler `db-migrations.sql:7837`/`:9607`.

- [ ] **Step 1: Skriv den fejlende test.** Fixtures: en kilde med bogtrykte nøgler og en med `record-<uuid>` og sidekort; entries `V`/»Den grevelige linje af 1673«, `IV`/»IV. Den danske grevelige Linje af 1673.« og `Stamme-x`/»A. Den holstenske Linje.«.

```text
bognøgle »V-1« med 1 placement                       → record_label 'V-1', citation '<udgave>, s. 201-202' (uden kort)
record-uuid, 1 placement IV, nr. '3', anker PDF 538   → 'IV, nr. 3', 'DAA X, s. 49'
record-uuid, stamme A, nr. '2'                        → 'A, nr. 2'
record-uuid, 1 placement uden trykt nr.               → 'IV'
record-uuid, 0 placements, anker PDF 541              → '', 'DAA X, s. 52'
record-uuid, 2 placements                             → RECORD_LABEL_PLACEMENTS_AMBIGUOUS
eksisterende binding med 'gammel'                     → narrative_record_labels giver stadig 'gammel'
binding med record_label ''                           → accepteres; '  ' → CHECK-fejl; validator: samme
```

- [ ] **Step 2:** Kør testen. Forventet: FAIL.
- [ ] **Step 3:** Implementér, spejl og tilføj db-verify-assert: CHECK'en tillader `''` og afviser blanktegn.
- [ ] **Step 4:** Kør testen og den eksisterende publiceringstest (`tests/sql/test-placement-ceremoni.sh`). Forventet: PASS begge.
- [ ] **Step 5: Commit** `feat(6e): læsbar postetiket for poster uden bogtrykt nøgle og tom postdel`

### Task 3: Koordinat-RPC'en — 1939's nøgle, trykt side og fart

*Opus-opgave.*

**Files:**
- Modify: `schema.sql:3054-3066` (eller en ny mængdefunktion ved siden af) og `:3334-3393`, `db-migrations.sql`, `db-verify.sql`
- Test: `tests/sql/test-6e2-koordinater.sh` (ny), `tests/sql/test-6e2-upgrade.sh` (ny, signaturændring; mønster `test-6d3-upgrade.sh`), begge i `ci.yml`

**Interfaces:**
- Produces: `public.public_person_source_coordinates()`.
  - **Returtypen:** de nuværende kolonner i samme rækkefølge + `printed_page text` sidst. Ændringen kræver `DROP FUNCTION` + `CREATE` + de samme `REVOKE`/`GRANT` i migrationen.
  - **Ældre blokke (Codex r1 #1):** `db-migrations.sql:26699` og `:33894` genopretter funktionen med den gamle
    returtype med `CREATE OR REPLACE`. Det fejler ved anden kørsel. Foran hver af de to indsættes derfor en
    betinget `DROP FUNCTION`, som kun rammer, når den eksisterende funktion har kolonnen `printed_page` (opslag i
    `pg_proc.proallargtypes`/`proargnames`). Det er en undtagelse fra reglen om ældre blokke.
  - Testen kører **hele** `db-migrations.sql` to gange på en base med den gamle signatur og én gang oven på et frisk
    `schema.sql`.
  - **Kildegaten:** ingen to placements deler `(scheme_entry_id, generation_local, kuld_label, printed_number)`, med NULL som ens (`count(DISTINCT row(...))`). Gatens særskilte NULL-nr.-filter fjernes. Kildegaten bevares som sikkerhedsnet.
  - **`printed_page`:** kun for poster uden bogtrykt nøgle (`record_key` matcher `record-<uuid>`, samme regel som
    etiketten i Task 2). Ellers NULL, så 2018-20 bliver ved »V, nr. 1«.
    - Placement-række: `source_trykt_side(source_id, min(page_from)::text)` over postens accepterede ankre.
    - Legacy-række: samme over posten for den publicerede binding for `(person, source)` (narrativ med
      `subjekt_id = person_id`). Uden binding: NULL.
  - **Legacy-rækker:** `legacy_line_code` og `printed_number` uændrede. Klienten afgør visningen (Task 5).
  - **Fart:** `membership_is_current` evalueres ikke pr. række. En mængdebaseret afledning skal give **præcis samme** sæt af `(person_id, lineage_id)`. Mekanismen er implementerens.

- [ ] **Step 1: Skriv de fejlende tests:**
  - Fixture med to kuld i samme entry og slægtled, begge med nr. 1 → begge rækker `placement` (gaten består).
  - Én unummereret alene i sin gruppe → `placement` med NULL nr.
  - To rækker med ens nøgle → hele kilden `legacy`.
  - `printed_page` for en `record-`-post med anker på PDF 538 = `'49'`.
  - Post med bognøgle (»V-1«) → NULL.
  - Legacy-række uden binding → NULL.
  - `record-`-post i en kilde uden kort → `page_from` uændret.
  - Ækvivalens: mængdefunktionen = `membership_is_current` for hver fixture-medlemskab, inklusive et forældet medlemskab (ændret `state_sha256`).
- [ ] **Step 2:** Kør. Forventet: FAIL.
- [ ] **Step 3:** Implementér.
- [ ] **Step 4: Stand-in-mål** på en kopi af stand-in'en efter migrationen, `ANALYZE`, som anon, median af 3:
  - `public_person_source_coordinates()` ≤ 225 ms.
  - Kilde 1's gamle kolonner har md5 `66e9afd96e1b201a55c3984c0c1d66a3`.
  - Kilde 3 har 528 rækker `placement` og resten legacy (Task 0 step 5's tal).
  - Ækvivalens over alle 1.104 medlemskaber: 0 forskelle.
  
  - **Stopkriteriet er klientens faktiske vej** (Codex r1 #6): summen af de to sider, som `getAll` henter
    (`range(0,999)` + `range(1000,1999)`), skal være ≤ 450 ms. Det er to gange 225 ms, fordi siden før 6d-1 også
    hentede to sider med samme rækkeantal.
  - Desuden rapporteres det enkelte kald, med 225 ms som mål.
  
  Nås 225 ms ikke, **stop og rapportér tallene**. Målet sænkes ikke af implementeren.
- [ ] **Step 5:** `test-6e2-upgrade.sh`: migrationen på en base med den gamle signatur (to kørsler) → ny signatur, grants som før, anon kan kalde.
- [ ] **Step 6: Commit** `feat(6e): koordinat-RPC'en entydig på 1939's nøgle, med trykt side og mængdebaseret medlemskab`

### Task 4: Fakta-RPC'ens side, db-verify og hele CI

**Files:**
- Modify: `schema.sql:21361-21451` (`public_person_facts`: `c.side` → `public.source_trykt_side(s.id, c.side)`, samme signatur), `db-migrations.sql`, `db-verify.sql`
- Test: udvid `tests/sql/test-6e2-sidekort.sh`

- [ ] **Step 1: Fejlende test:** et ubundet fixture-faktum med citation `side='541'` i en kilde med kort giver `side='52'`. Uden kort: `'541'`.
- [ ] **Step 2-4:** Kør (fejl) → implementér og spejl → kør alle `tests/sql/test-6e2-*.sh` og de fire PostgreSQL-jobs fra `ci.yml` lokalt. Forventet: PASS.
- [ ] **Step 5: Commit** `feat(6e): fakta-RPC'en viser trykt side`

## Del B — klienten (gren `feat/trin6e2-klient`; deployes før DDL)

### Task 5: Linjevisning, »Kilde i Aarbogen« og bogens nummer

**Files:**
- Create: `packages/core/src/linjeVisning.ts`; test `packages/core/src/__tests__/linjeVisning.test.ts`
- Modify:
  - `packages/core/src/types.ts:10-22` (`RawExtId`: `trykt_side?: string | null`).
  - `coordinateRowToExtId` og `PublicCoordinateRow` (`printed_page?: string | null`, valgfri: før DDL findes den ikke).
  - `web/src/data/sources.ts`, `packages/core/src/kildeProveniens.ts:103-109` (`bogensNummer`).
  - `web/src/data/model.ts:156-159`.
  - Kaldestederne `web/src/components/PersonSide.tsx:52`, `packages/feed/src/pool.ts:232`, `web/src/components/feed/FeedStreamView.tsx:341`.
- Test: `web/src/data/__tests__/sources.test.ts` (findes den ikke, opret), `packages/core/src/__tests__/kildeProveniens.test.ts`

**Interfaces:**
- Produces:
  - `export function linjeKodeOgNavn(e: { code: string; label: string | null }): { kode: string; navn: string }`. Samme præfiksregel som SQL'ens `linje_kode`. `navn` = etiketten uden præfiks og uden afsluttende punktum; tom etiket → `navn = kode`.
  - `export function linjeTitel(e: { code: string; label: string | null }): string` → `${kode}. ${navn}`.
  - `export type SkemaOpslag = (sourceId: string, code: string) => { code: string; label: string | null } | null`.
    - Bygges i `model.ts` af `schemes` + `schemeEntries`, nøgle `${scheme.source_id}|${entry.code}`, **kun skemaer
      med `kind='stamtavle'`** (Codex r1 #4). Brug samme afgrænsning som `lineage.ts:60-66`
      (`entryBySourceCode`), og helst samme kode.
    - Test: en kilde med samme kode i et `presensliste`-skema med en anden etiket skal give stamtavlens titel.
  - `SourceRef` udvides **kompatibelt** (Codex r1 #2) med valgfrie felter:
    `{ ref: string; work: string; kort?: string; personId?: string; sourceId?: string; aar?: number | null; slaegtled?: number | null }`.
    Eksisterende producenter (`kildeProveniens.ts:69`, `mobile/src/data/buildAux.ts:77`) er uændrede.
    `bogensNummer` bruger `kort ?? ref` og behandler manglende felter som laveste prioritet.
  - `buildSources(extIds, sources, canonicalIdById, skema?: SkemaOpslag)`:
    - Kode i kildens skema → `ref = linjeTitel + [', s. '+trykt_side] + [', nr. '+nr]`, `kort = kode + [', s. '+side] + [', nr. '+nr]`.
    - Kode ikke i kildens skema (legacy »1939«, ingen kode) → hverken linje eller nr. `ref = kort = trykt_side ? 's. '+trykt_side : ''`.
    - Uden `skema` (ældre kald) → dagens form.
  - `buildSources` udfylder `slaegtled` fra `slaegtled_lokal`.
  - `bogensNummer(sourcesBy, personId): string | null` (signaturen er uændret).
    - Vælger den ref, der har højeste `aar` (nyeste udgave). Inden for udgaven lavest `slaegtled` (NULL sidst),
      dernæst laveste `personId` numerisk.
    - Returnerer `kort`.
    - Samme regel gælder for personside og feed, som funktionens kommentar kræver.
    - Begrundelse (*mit valg*): optræder en person i to linjer, står den fulde post i den linje, hvor personen er
      stamfar (lavt slægtled). Henvisningsposten står højt i den gamle linje, fx Conrad V-1 slægtled 1 mod III-58
      slægtled 12.

- [ ] **Step 1: Skriv de fejlende tests:**

```ts
expect(linjeTitel({ code: 'V', label: 'Den grevelige linje af 1673' })).toBe('V. Den grevelige linje af 1673');
expect(linjeTitel({ code: 'IV', label: 'IV. Den danske grevelige Linje af 1673.' })).toBe('IV. Den danske grevelige Linje af 1673');
expect(linjeTitel({ code: 'Stamme-holstenske', label: 'A. Den holstenske Linje.' })).toBe('A. Den holstenske Linje');
expect(linjeTitel({ code: 'Stamme-holstenske', label: 'Den holstenske Linje.' })).toBe('Stamme-holstenske. Den holstenske Linje'); // før ceremonien
// buildSources med skema
// kilde 3 placement IV/3, side '49'             → ref 'IV. Den danske grevelige Linje af 1673, s. 49, nr. 3', kort 'IV, s. 49, nr. 3'
// kilde 1 placement V/1, ingen side             → ref 'V. Den grevelige linje af 1673, nr. 1', kort 'V, nr. 1'
// kilde 3 legacy '1939'/275, side '52'          → ref 's. 52', kort 's. 52'
// kilde 3 legacy '1939'/275, ingen side         → ref '' (personVisning viser kun værket)
// uden skema-argument                           → 'Linje V, nr. 1' (uændret)
// bogensNummer: Conrad 255 (III-58, kilde 1), 392 (V-1, kilde 1), 1198 (kilde 3)
//   → 'V, nr. 1' (nyeste udgave = kilde 1; V-1 har slægtled 1, III-58 slægtled 12)
// »Optræder i Aarbogen som« for Conrad → 'DAA 2018-20, V, nr. 1 og DAA 2018-20, III, nr. 58 og DAA 1939, s. 52'
```

- [ ] **Step 2:** Kør `npm run test -w @daa/core` og `npm run test -w web`. Forventet: FAIL.
- [ ] **Step 3:** Implementér.
  - `personVisning.tsx:73` og `PersonSide.tsx:205-212` viser `work` og `ref` som i dag. En tom `ref` giver kun
    værket uden separator.
  - **»Optræder i Aarbogen som …«** (`personVisning.tsx:101-110`, spec §5.7) bygges af den foldede persons
    `sourcesBy`-refs i `bogensNummer`'s orden. Hver ref vises som `<work>, <kort>`, eller kun `<work>`, når `kort`
    er tom; refs forbindes med ' og '. Det afløser `mergedFrom`'s »linje (V-1)«-form, som viste 1939's gruppelokale
    nr. som »IV-3«.
  - Mobilens kopi (`mobile/src/app/person/[id].tsx:155`) røres ikke (ikke-mål).
- [ ] **Step 4:** Kør. Forventet: PASS.
- [ ] **Step 5: Commit** `feat(6e): linjens navn og trykt side i »Kilde i Aarbogen«, bogens nummer efter biografien`

### Task 6: Postetiketter i chips, familiekilder, Redaktion og proveniens

**Files:**
- Modify:
  - `packages/core/src/personFacts.ts` (eksportér `sideForm`).
  - `packages/core/src/editionSelector.ts:23-27` (`postLabel`).
  - `packages/core/src/familieKilder.ts:76-79` (`kildeLinje`).
  - `packages/core/src/editionFacts.ts:89-91` (`unikkeEfterLabel`).
  - `web/src/components/PersonNarrativeRecordEditor.tsx:233-234`.
  - `packages/core/src/kildeProveniens.ts:21-43` (`RaaCitationRow.side_trykt?`, `citationRowsTilProveniens`).
  - `web/src/data/public.ts:198-199`.
- Test: de tilsvarende `__tests__`-filer og `web/src/components/__tests__/PersonNarrativeRecordEditor.test.tsx` (opret, findes den ikke)

**Interfaces:**
- Produces:
  - `export function sideForm(label: string): string` (uændret adfærd).
  - `postLabel(v)` / `kildeLinje(k)` (Codex r1 #3):
    - Synlig postetiket → `sideForm(citationLabel || sourceLabel) · etiket`.
    - Tom postetiket `''` (de 35 uden placement) → `sideForm(citationLabel || sourceLabel)` uden separator.
    - Teknisk etiket (`record-…`, `legacy-source:…`, kun før ceremonien) → `sourceLabel` som i dag. Dens
      `citationLabel` bærer endnu PDF-siden.
  - `unikkeEfterLabel`: nøgle `recordRef ?? label`.
  - Redaktion: `<h3>{record.recordLabel || record.citationLabel}</h3>` og `aria-label` med samme fald.
  - `pageOrder` (`PersonNarrativeRecordEditor.tsx:36`) læser nu det trykte »s. N« fra `citationLabel`. Den bruges
    kun til sortering, og omregningen bevarer rækkefølgen. Ingen ændring.
  - Proveniens: `.select('assertion_id,side,side_trykt,source:source_id(titel,udgave)')`.
    - Fejler kaldet (funktionen findes ikke før DDL), gentages det uden `side_trykt`.
    - `citationRowsTilProveniens` bruger `side_trykt`, når feltet er til stede (også NULL), ellers `side`.

- [ ] **Step 1: Skriv de fejlende tests:**
  - Chip `{sourceLabel:'DAA 1939', citationLabel:'DAA 1939, s. 49', recordLabel:'IV, nr. 3'}` → `'DAA 1939, s. 49 · IV, nr. 3'`.
  - Samme med `recordLabel:'record-…'` og `citationLabel:'DAA 1939 side 538'` → `'DAA 1939'`.
  - `recordLabel:''`, `citationLabel:'DAA 1939, s. 52'` → `'DAA 1939, s. 52'`.
  - 2018-20 `{citationLabel:'DAA 2018-20, s. 201-202', recordLabel:'V-1'}` → `'DAA 2018-20, s. 201-202 · V-1'`.
  - `kildeLinje` tilsvarende med `Kilde: `.
  - To fakta med samme label, men forskellig `recordRef` → to kilder. Samme `recordRef` → én.
  - Redaktion med `recordLabel ''` → h3 = citationLabel, ingen tom h3.
  - Proveniens med `side_trykt:'52'` → `s. 52`; `side_trykt:null` → kun værket; uden feltet → `side`.
- [ ] **Step 2-4:** Kør (fejl) → implementér → kør. Forventet: PASS.
- [ ] **Step 5: Commit** `feat(6e): bogens side i chips og familiekilder, poster holdes adskilt på id`

### Task 7: Linjehoved, hovedets linjer pr. udgave og B6-noten

**Files:**
- Modify:
  - `packages/core/src/placementCoordinates.ts:30-42` (`compareLineHead`), `web/src/data/lineage.ts:110-113`.
  - Persondetaljens hoved: `web/src/components/personVisning.tsx` og det sted, hvor hovedets linjer renderes. Implementeren finder det og nævner fil:linje i commit-beskeden.
- Create: `packages/core/src/b6Note.ts`; test `packages/core/src/__tests__/b6Note.test.ts`

**Interfaces:**
- Produces:
  - `compareLineHead(a, b)` med `HeadKey = { nr: number | null; nr_label?: string | null; slaegtled?: number | null }`.
    - Rækkefølge: laveste `slaegtled` (NULL sidst), dernæst unummereret før nummereret, dernæst nr og label som i dag.
    - `lineage.ts` sender `nr: x.nr ?? null` og `slaegtled: x.slaegtled_lokal ?? null`.
  - `export type LinjeRaekke = { sourceId: string; udgave: string; entry: { code: string; label: string | null }; lineageId: string | null; provenance: 'placement' | 'legacy_external_id' }`.
  - **Hovedet viser linjetitler, ikke personens koordinater** (Codex r1 #5, afgjort med spec §12.4). Slægtled,
    gruppe og nr. står ikke i hovedet. Personens side og nr. står i »Kilde i Aarbogen« (Task 5), og slægtled og
    gruppe udelades efter afgørelse 14. Spec §5.7's »med slægtled, gruppe og nr.« er afløst af §12.4.
  - `export function linjerForUdgave(raekker: LinjeRaekke[], sourceId: string): string[]`.
    - Giver den valgte udgaves `linjeTitel`'er, unikke, i rækkefølgen af de første forekomster.
    - Rækken tæller, når koden findes i kildens skema, både `placement` og legacy. Det er samme regel som
      Task 5; kilde 1's 14 legacy-rækker viser deres linje som i dag.
  - `export function b6Noter(raekker: LinjeRaekke[], valgtSourceId: string): string[]`. En note pr. anden kilde med `placement`:
    - samme `lineageId` som en af den valgte kildes linjer → `✓ også i <udgave> (<linjeTitel>)`;
    - ellers `<udgave> placerer i: <linjeTitel>`.
    - Flere linjer i den valgte kilde giver ingen note.
    - Rækkerne kommer kun fra offentlige koordinatrækker i den foldede komponent, med `lineageId` fra `lineage_scheme_entry_lineage` (`relation_kind='canonical'`).
    - B6 bruger kun `placement`-rækker (gældende medlemskab); legacy giver aldrig en note.

- [ ] **Step 1: Skriv de fejlende tests:**
  - **Hoved:**
    - Entry med {slægtled 2, nr. 1} og {slægtled 1, uden nr.} → det unummererede.
    - {slægtled 1, nr. 1} og {slægtled 1, uden nr.} → det unummererede.
    - Kilde 1's fem hoveder i en fixture med kun nr. → uændrede: I→1, II→137, III→172, IV→298, V→392.
  - **Udgavens linjer:**
    - Conrad-komponenten valgt i 2018-20 → `['III. Den mecklenburgske linje', 'V. Den grevelige linje af 1673']`.
    - Valgt i 1939 (1198 uden placement) → `[]`.
    - Kilde 1-legacy-række med kode `V` → `['V. Den grevelige linje af 1673']` (som i dag).
    - Kilde 3-legacy-række med kode `1939` → `[]`.
  - **B6:**
    - 2018-20 V og 1939 IV med samme `lineageId` → `['✓ også i DAA 1939 (IV. Den danske grevelige Linje af 1673)']`.
    - Forskellig `lineageId` → `['DAA 1939 placerer i: …']`.
    - Kun to 2018-20-rækker (III, V) → `[]`.
- [ ] **Step 2:** Kør. Forventet: FAIL.
- [ ] **Step 3:** Implementér, og forbind hovedet.
  - Hovedet viser `linjerForUdgave` for vælgerens valgte udgave og noterne under linjerne.
  - Uden vælger: personens eneste udgave.
  - Legacy-rækker, hvis kode ikke findes i kildens stamtavleskema, giver ingen linje. Kilde 1's legacy-rækker
    giver deres linje som i dag (samme regel som Task 5).
- [ ] **Step 4:** Kør. Forventet: PASS.
- [ ] **Step 5: Commit** `feat(6e): linjens hoved efter slægtled, linjer pr. udgave og B6-note`

### Task 8: Klienten mod før- og eftertilstand

- [ ] **Step 1 (før):** Byg web og kør mod en kopi af stand-in'en, som den er (= prod nu), som anon.
  - Kør `e2e`, og tjek med browseren: Conrad 392, 1198 og en placeret 1939-person (1093→149).
  - Forventet:
    - ingen `record-`, `legacy-source:` eller »Linje 1939« i DOM'en;
    - fakta som i dag;
    - »Kilde i Aarbogen« for 1939 viser »DAA 1939« uden PDF-side, fordi legacy-koden ikke er i skemaet og `printed_page` mangler;
    - ingen konsolfejl ud over den kendte `side_trykt`-fallback (logges som warn, ikke error).
- [ ] **Step 2 (efter):** Gentag på en kopi efter Task 1-4's migration og Task 9's ceremoni (fra generalprøven). Forventet: spec §8's punkter for 1939 og 2018-20 og tillæggets sidepunkt.
- [ ] **Step 3:** Hele node-CI'en lokalt. Draft-PR for `feat/trin6e2-klient` efter projektejerens ja; merge = deploy (trin 1 i prod-rækkefølgen).

## Del C — ceremonien (gren `feat/trin6e2-db`)

### Task 9: Ceremoniens SQL og målescript

**Files:**
- Create:
  - `.claude/skills/daa-extract/scripts/etiket_ceremoni.sql` (kildeparametriseret).
  - `.claude/skills/daa-extract/scripts/maal_trin6e2.sql` (faser `foer|ddl|data`).
  - `.claude/skills/daa-extract/scripts/sidekort_1939.json` (kortet fra spec §12.3).
  - `.claude/skills/daa-extract/scripts/linjeetiketter_6e2.json`: `[{code, label_foer, label_efter}]` for de 5 rettelser i spec §12.5.
- Test: `tests/sql/test-etiket-ceremoni.sh` + `tests/sql/fixtures/` (syntetisk mini-kilde, mønster `test-placement-ceremoni.sh`), i `ci.yml`

**Interfaces:**
- psql-variabler: `actor src go sidekort_path sidekort_sha etiketter_path etiketter_sha expect_bindinger expect_tomme expect_entries expect_koord_andre expect_etiketter_andre expect_bio_offentlige expect_fakta_bundne`.
  - `expect_*_andre` = hashes for de øvrige kilder fra `maal foer`.
  - Filerne læses med `` \set x `cat :'path'` ``.
- Kvittering: `ETK_OK bindinger=<n> tomme=<n> entries=<n> revalideret=<n> stale=0 koord_andre=<md5> etiketter_andre=<md5>`.
- Én transaktion:
  - `SET LOCAL statement_timeout='15min'`.
  - Aktør via `request.jwt.claim.sub`.
  - `\g /dev/null` på alle `set_config`.
- **Rækkefølge:**
  1. **`ETK_PRE_*`:**
     - rolle;
     - DDL til stede (Task 1-3's funktioner og CHECK);
     - `source.sidekort` er NULL for `src`;
     - antal publicerede bindinger med `record-`-mønster i seneste hændelse = `expect_bindinger`;
     - 0 `stale_published`;
     - filernes sha = de GO-bundne;
     - hver `label_foer` findes præcis én gang for `(src, code)`.
  2. **Sidekort:** `UPDATE public.source SET sidekort = <fil>` for `src`.
  3. **Linjeskemaets 5 etiketter:** før/efter skrives til kvitteringen.
  4. **Bindingerne** (`src`, published, `record_label ~ '^record-'`): `record_label` og `citation_label` fra `narrative_record_wanted_labels`.
  5. **Revalidering:** `ANALYZE`, derefter én `\gexec`-sætning pr. `stale_published` med `red_revalider_person_narrative_record(person, src, record_key, state_sha)`. Mønstret er 6d-1's.
  6. **`ETK_POST_*`:**
     - 0 stale;
     - 0 seneste hændelser med `record-` for `src`;
     - revalideret = `expect_bindinger`;
     - tomme = `expect_tomme`;
     - **afstemning pr. binding:** ny `after_state` minus de tilladte stier (spec §12.2: `labels.record_label`, `labels.citation_label`, `binding.record_label`, `binding.citation_label`, `provenance.placements[*].scheme_entry_label` samt de provenance- og state-hashes, der afledes af dem) = forrige `after_state` minus de samme;
     - koordinat- og etikethash for de øvrige kilder = `expect_*_andre`;
     - antal offentlige biografier og bundne fakta = `expect_bio_offentlige` og `expect_fakta_bundne`;
     - en `src`-binding uden placement har `''` og `'<udgave>, s. N'`.
- **`maal_trin6e2.sql`** printer `KOORD_ANDRE`, `ETIKETTER_ANDRE`, `BINDINGER_RECORD`, `STALE`, `BIO_OFFENTLIGE`, `FAKTA_BUNDNE`, `FAMILIEKILDER` og `SKEMA_ETIKETTER`. Runneren stopper, hvis `ddl`'s hashes for de øvrige kilder afviger fra `foer`.

- [ ] **Step 1: Skriv de fejlende tests** (mini-kilde: 4 records med `record-`, 1 uden placement, 1 i en entry med rettet etiket, en modpart med bognøgle i en anden kilde):
  - `$fuld$`: ETK_OK, 0 stale, etiketter `'IV, nr. 3'`/`''`/`'A, nr. 2'`.
  - `$genkoersel$`: `ETK_PRE_FASE` uden skrivning.
  - `$fremmed_kilde$`: en bevidst ændring i den anden kilde → `ETK_POST_ANDRE`.
  - `$forkert_etiket_foer$`: `ETK_PRE_ETIKET`.
  - `$sha$`: ændret sidekortfil → `ETK_PRE_SHA`.
- [ ] **Step 2-4:** Kør (fejl) → implementér ceremoni, mål og pytest-wrapper som `test_maal_trin6c1.py` → grønne.
- [ ] **Step 5: Commit** `feat(6e): data-ceremoni for læsbare etiketter, sidekort og linjenavne`

### Task 10: Runner, runbook og generalprøve

**Files:**
- Create: `docs/runbooks/trin6e2-prod.md` (form som `docs/runbooks/trin6d1-prod.md`).
- Privat (kun hovedsessionen): `~/.private/5ab-overfoersel/40-trin6e2.sh` (kopi af 6d-1's runner med vinduesvagt; handlinger `go|standin|maal|dump|advisors|ddl|data|vindue`).

- [ ] **Step 1: Runner:**
  - Indholdsafledte forventninger fra Task 0 og stand-in-målingen (563, 35, 5).
  - GO binder DDL-blokkens sha, ceremoni-scriptet, målescriptet og de to json-filer.
  - Kræver `--jeg-mener-det`, og vinduesvagten har en negativtest.
- [ ] **Step 2: Runbook:**
  - Rækkefølge: `web-deploy (Del B) → go → maal foer → dump → advisors → ddl → maal ddl → advisors → dump → data → maal data → vindue → browsertjek`.
  - Kendt vindue: mellem `ddl` og `data` viser »Kilde i Aarbogen« 1939's PDF-side, fordi kortet først kommer med data. Det skal være minutter.
  - Fortrydelse: restore + forrige funktionsdefinitioner (gemt i runbooken) + `db-rls.sql`. Web-fortrydelse = redeploy.
- [ ] **Step 3: Generalprøve** fra operatørens cwd på en frisk kopi af stand-in'en med `statement_timeout='2min'`:
  - hele runbooken;
  - rækkediff: kun `source`, `lineage_scheme_entry`, `narrative_record_publication`, `narrative_publication_event`, `change_set`;
  - øvrige kilders hashes byte-ens;
  - den langsomste sætning × prod-faktoren (fra `maal`) under 15 min;
  - anon-tider: koordinat-RPC'en og Conrads biografi (392) inden for 209-487 ms.
- [ ] **Step 4: Negativer:** forkert GO, manglende flag, gentaget `data`, ændret json efter GO.
- [ ] **Step 5: Commit** `docs(6e): runbook for 6e-2 i prod` (runneren committes ikke).

### Task 11: Review, prod og færdigbevis

- [ ] **Step 1:** Codex `gpt-6.1-sol` over begge grenes diff (eksport uden `work*/`). Opus afvejer. Ret kun det godkendte efter projektejerens ja. Hele CI lokalt igen.
- [ ] **Step 2:** Spørg om push og draft-PR'er. CI på PR'erne skal være grøn.
- [ ] **Step 3: Prod** efter runbooken: web-deploy, så DDL-GO, så data-GO. AI'en læser kvitteringer og mål.
- [ ] **Step 4: Færdigbevis** (spec §8 + §12) i `docs/evidensbaseret-genimport/status.md`, `docs/database-current-state.md` (ny §) og changelog:
  - 563 genpublicerede, heraf 35 tomme;
  - 0 `record-`;
  - øvrige kilders hashes byte-ens;
  - koordinat-RPC'ens anon-tid i prod;
  - browsertjekket med de 5 bogopslag;
  - status-rækkerne for 1939 hæves til `produktionsverificeret`.
- [ ] **Step 5:** Commit `docs(6e): færdigbevis for 6e-2 i prod`.
