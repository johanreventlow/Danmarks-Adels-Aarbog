# 5c-2 + B11: læseren ser placering og fakta med kilde — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** To editionsneutrale offentlige læse-RPC'er (fakta med kilde; koordinater fra placement) i prod, og web/mobil
der bruger dem, så læseren ser personens fakta med kildehenvisning og linje/nr./kuld fra afgjort evidens.

**Architecture:** PR 1 (DB) lægger én privat læsehjælper og to SECURITY DEFINER-RPC'er i `schema.sql` og
`db-migrations.sql` med pg-tests og ceremonimateriale; den køres i prod fra projektejerens shell. PR 2 (klient)
lægger rene funktioner i `packages/core`, skifter webbens og mobilens loader og tilføjer fakta-sektionen i
`DetailPanel`; den merges først efter ceremonien.

**Tech Stack:** PostgreSQL 17 / Supabase (plpgsql, RLS), TypeScript, React (Vite), React Native (Expo), vitest,
Playwright, psql, zsh.

**Spec:** `docs/superpowers/specs/2026-10-29-5c2-b11-laeserflade-design.md` (commit `8e3687f9`).

## Global Constraints

- Navne er editionsneutrale: ingen `2018-20`/`1939` i funktions-, fil- eller typenavne på permanente overflader.
- Begge RPC'er: `LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog`, fuldt kvalificerede navne,
  `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role; GRANT EXECUTE … TO anon,authenticated`. Hjælperen:
  `SECURITY INVOKER`, `REVOKE ALL … FROM PUBLIC,anon,authenticated,service_role`, ingen grants.
- DDL'en er additiv: kun `CREATE OR REPLACE FUNCTION`. Validatoren (`private.validate_interpretation_promotion_items`),
  `person_source_coordinate_legacy` og `fetchProveniens` ændres ikke. Ingen data skrives.
- `schema.sql` og `db-migrations.sql` har byte-ens funktionskroppe; migrationsblokken står mellem `-- BEGIN 5c2-b11`
  og `-- END 5c2-b11` og er idempotent.
- PII (invariant 8): `vaerdi_tekst`, `date_raw`, `citat_tekst` og narrativtekst må aldrig printes fra en kopi af prod
  eller prod. Målinger printer antal og id'er; stdout og stderr omdirigeres til filer under `~/.private/5c2/`.
- Prod skrives kun fra projektejerens shell. db-verify køres aldrig mod prod.
- UI-tekster (præcis): sektion »Fakta«; mærker »bundet til bogens post«, »fra den oprindelige import«,
  »Kilde ikke registreret«, »omstridt«; underoverskrift »Andre udsagn«; fejl »Fakta kunne ikke hentes«.
- Commits: Conventional Commits på dansk, aldrig på `main`; PR'er `--draft`; ét commit pr. task.

## Review Focus

1. **`samme_som`-foldet person med fakta på begge id'er:** alle fakta fra alle medlemmer vises én gang (dedup på
   `fact_id`), ikke kun det kanoniske id's. Test i Task 5 (`buildPersonFacts` dedup) og Task 6 (`fetchPersonDetail`
   kalder RPC'en med alle `numIds`).
2. **Omstridt konklusion uden valgt påstand (`valgt_assertion_id` NULL):** faktummet vises med mærket »omstridt«,
   alle påstande under »Andre udsagn«, ingen opfundet hovedværdi. Test i Task 1 (RPC returnerer rækker med
   `chosen=false`) og Task 5.
3. **Faktum uden værdi og uden dato** (begge NULL): vises med »—«, ikke udeladt. Test i Task 5.
4. **Person med legacy-række i to kilder og membership i den ene:** to rækker med hver sin `provenance_kind`.
   Test i Task 2.
5. **Kilde uden `udgave` (kilde 2, genealogi-database):** `source_label` = `source.titel`; citation uden kilde →
   »Kilde ikke registreret«. Test i Task 1 og Task 5.

---

### Task 1: Fakta-RPC og bindingshjælper (PR 1)

Gren `feat/5c2-b11-db` fra `docs/5c2-b11-spec`.

**Files:**
- Modify: `schema.sql` (efter `public_family_sources`, ca. `:18209`), `db-migrations.sql` (ny blok sidst i filen)
- Create: `tests/sql/fixtures/person-facts.sql`, `tests/sql/test-person-facts.sql`
- Modify: `tests/sql/inspect-5ab-function-parity.sql`, `.github/workflows/ci.yml` (writer-1939-jobbet efter
  »Familiekilder SQL« ca. `:505`; paritetsantal `:378-379`)

**Interfaces:**
- Produces: `private.assertion_binding_current(p_promotion_id uuid) RETURNS boolean`;
  `public.public_person_facts(p_person_ids bigint[]) RETURNS TABLE(person_id bigint, fact_id bigint, faktatype text,
  conclusion_status text, assertion_id bigint, chosen boolean, vaerdi_tekst text, date_raw text, date_min date,
  date_max date, date_qualifier text, date_certainty text, source_id bigint, source_label text, side text,
  record_ref uuid, record_label text, citation_label text)`.

- [ ] **Step 1: Skriv fixturen.** `pg_temp.fpf_bound(p_base bigint, p_actor uuid) RETURNS jsonb` bygger på
  `fixtures/relation-5b.sql` + `fixtures/relation-2a.sql` (som `test-family-sources.sql`): én afdød person
  `p_base` med publiceret post (`pg_temp.f2a_publish`), et `død`-faktum med assertion (`date_raw`), afklaret
  konklusion og citation; en accepteret fortolkning af et promoverbart dødsprædikat med én supporting-observation
  ankret til posten; promotion til assertionen via `red_preview_interpretation_promotions` +
  `red_promote_interpretations_batch` (mønster: `test-interpretation-promotion-targets.sql:92-97`). Returnerer
  `{person, fact, assertion, promotion, source, post, import_key, record_key}`. Forudsætninger for
  `red_ret_ocr_felt` (`schema.sql:1990-2040`): kilden får et `import_key`; personen har præcis én
  `person_external_id`-række i kilden med `record_key`; `død`-faktummets valgte assertion har præcis én citation i
  den kilde.
- [ ] **Step 2: Skriv de fejlende tests** i `tests/sql/test-person-facts.sql` (`BEGIN … ROLLBACK`, `DO`-blokke med
  `RAISE EXCEPTION` ved fejl, kaldt som `anon` via `SET LOCAL ROLE anon`):
  - `bundet`: én række; `record_ref` = postens `public_ref`, `record_label` og `citation_label` ikke NULL,
    `chosen` = true, `source_label` = kildens udgave.
  - Hver betingelse brudt for sig (i egen savepoint) giver stadig én række med `record_ref`, `record_label` og
    `citation_label` NULL:
    (a) fortolkningen superseded af en ny version;
    (b) en ekstra supporting-observation;
    (b2) anchoren gjort ikke-accepteret;
    (b3) anchoren peger på en record i en anden kilde;
    (c) publiceringen trukket tilbage (mønster: `test-family-sources.sql:105`);
    (c2) narrativets publiceringsgate falsk (som owner: `narrative.privat=true`);
    (d) **`red_ret_ocr_felt(p_person_id, p_import_key, p_record_key, 'doed', <fingerprint>, 'rettet',
    '{"raw":"<anden dato>", …}')`** med fingerprint fra `private.ocr_fingerprint(…, private.ocr_importeret('doed',
    …), <citat_tekst>)` som funktionen selv beregner;
    (e) faktummets `faktatype` ændret til en anden type som owner;
    (e2) faktummets `subjekt_id` flyttet til en anden offentlig person som owner (identitetsbrud);
    (f) narrativets `subjekt_id` sat til en anden offentlig person som owner (betingelse 3 alene; syntetisk).
  - Gemt regel, ikke aktiv: en nyere aktiv regelversion med en anden `expected_fact_type` ændrer ikke bindingen.
  - Entydighed: to gyldige promotions på samme assertion → `record_*` NULL (fail-closed, ingen dubletrækker).
  - Enighed med validatoren, kaldt som owner efter `RESET ROLE`: (d) giver `EVIDENCE_PROMOTION_VALUE_MISMATCH`,
    (e) `EVIDENCE_PROMOTION_FACT_TYPE_MISMATCH`, (e2) `EVIDENCE_PROMOTION_IDENTITY_MISMATCH`. Den ubrudte binding
    giver `assertion_binding_current` = true og validatoren `EVIDENCE_PROMOTION_ALREADY_PROMOTED` (alle tidligere
    grene bestået, `schema.sql:9688`).
  - Gate: levende person (`levende=true`) og `privat=true` → 0 rækker, både som `anon` og `authenticated`.
  - Konklusion `forældet` → 0 rækker; `omstridt` med `valgt_assertion_id` NULL → rækker med `chosen IS FALSE`.
  - Kilde uden `udgave` → `source_label` = `titel`; citation med `source_id` NULL → række med `source_*` NULL;
    assertion uden citation → én række med `source_*` NULL; to citationer → to rækker i citation-id-orden.
  - `narrative_record_contract_version()<2` (midlertidigt omdefineret i transaktionen) eller NULL-input → 0 rækker.
- [ ] **Step 3: Kør og se dem fejle.** `psql -d <lokal testbase bygget som writer-1939-jobbet> -v ON_ERROR_STOP=1 -f
  tests/sql/test-person-facts.sql`. Forventet: fejl `function public.public_person_facts(bigint[]) does not exist`.
- [ ] **Step 4: Implementér `private.assertion_binding_current`** (spec §4.1 betingelse 1 og 4): læs promotionen
  (`target_type='assertion'`), kræv `interpretation_current.id = interpretation_id AND status='accepted'`, slå
  reglen op ved promotionens egen `(rule_key, rule_version)` i `private.interpretation_promotion_rule`, identiteten
  i `private.source_persona_identity` (`decision_status='accepted'`), og genkontrollér `subjekt_type='person'`,
  `subjekt_id = canonical_person_id` (når reglen kræver identitet), `faktatype = expected_fact_type` og
  værdien efter `value_kind` med `lower(btrim(normalize(x,NFC)))` som validatoren (`schema.sql:9694-9708`).
- [ ] **Step 5: Implementér `public.public_person_facts`.** Struktur som `public_family_sources`: guard på
  kontraktversion; fakta `subjekt_type='person' AND subjekt_id=ANY(p_person_ids) AND
  public.entitet_offentlig('person',subjekt_id)`; konklusion `status IN ('afklaret','omstridt')`; alle assertions på
  faktummet, `chosen = coalesce(assertion.id = conclusion.valgt_assertion_id, false)`; `LEFT JOIN citation` +
  `source` (`coalesce(udgave,titel)`); `LEFT JOIN LATERAL` på bindingen, der først tæller kvalificerende promotions
  og kun udfylder etiketterne ved præcis én: promotion med `assertion_binding_current`, præcis én
  supporting-observation med præcis én accepteret anchor (`:18176-18184`), præcis én publiceret
  `narrative_record_publication` for recorden, narrativ med `subjekt_type='person'`, `subjekt_id` = faktummets
  person og `person_daa_narrative_publication_allowed`, etiketter fra seneste `narrative_publication_event`
  (`:18201-18202`). `ORDER BY person_id, fact_id, assertion_id, citation.id NULLS LAST`.
- [ ] **Step 6: Samme blok i `db-migrations.sql`** mellem `-- BEGIN 5c2-b11` og `-- END 5c2-b11`; tilføj
  `('private','assertion_binding_current'),('public','public_person_facts')` til paritetsinspektøren og ret
  kommentaren og antallet 33 → 35 i `ci.yml:378-379`; tilføj trinnet `psql … -f tests/sql/test-person-facts.sql` i
  writer-1939-jobbet efter »Familiekilder SQL«.
- [ ] **Step 7: Kør.** Testen ovenfor + `tests/sql/test-family-sources.sql` + `test-interpretation-promotion-targets.sql`
  i samme base. Forventet: alle `DO`-blokke gennemført, ingen `ERROR`. Paritet: byg en frisk base (schema.sql) og en
  migreret (db-migrations.sql ×2) som `ci.yml:370-380` og `cmp` paritetsfilerne; forventet 35 linjer, ens.
- [ ] **Step 8: Commit** `feat(db): public_person_facts med gældende trin 4-binding`.

### Task 2: Koordinat-RPC (PR 1)

**Files:**
- Modify: `schema.sql` (efter `person_source_coordinate_legacy`, ca. `:2238`, men efter `membership_is_current`
  `:2972`), `db-migrations.sql` (samme blok)
- Create: `tests/sql/test-person-source-coordinates.sql`
- Modify: `tests/sql/inspect-5ab-function-parity.sql`, `.github/workflows/ci.yml` (frisk-schema-jobbet efter
  `test-placement-membership.sql` `:224`; paritetsantal)

**Interfaces:**
- Produces: `public.public_person_source_coordinates() RETURNS TABLE(person_id bigint, source_id bigint,
  legacy_line_code text, printed_number integer, printed_number_label text, generation_local integer,
  generation_global integer, kuld_label text, provenance_kind text)`.

- [ ] **Step 1: Skriv de fejlende tests** med samme opsætning som `tests/sql/test-placement-membership.sql`
  (placement, identitet, promotion af membership):
  - Person med præcis én gældende membership i kilde K → række for `(person,K)` med `provenance_kind='placement'`,
    `legacy_line_code` = entryens `code`, `printed_number_label='15a'` og `printed_number=15` når placementens
    `printed_number` er `'15a'`, `kuld_label` fra placementen også når legacy har en anden.
  - Samme person med legacy-række i en anden kilde → anden række med `'legacy_external_id'` og legacy-værdier,
    `printed_number_label = nr::text` (Review Focus 4).
  - Membership gjort ugældende (ret identitetens version, så sha'en ikke passer) → legacy.
  - To kvalificerende memberships i samme kilde (to lineages) → legacy.
  - Levende person og person med `privat=true` → 0 rækker for personen, som `anon` og `authenticated`.
  - Rækkerne er sorteret efter `(person_id, source_id)` og `(person_id, source_id)` er entydig.
- [ ] **Step 2: Kør og se dem fejle.** Forventet: `function public.public_person_source_coordinates() does not exist`.
- [ ] **Step 3: Implementér** (spec §4.2): én række pr. `person_external_id`-række med
  `entitet_offentlig('person',person_id)`. For hver række: kandidater = `person_lineage_membership` for personen,
  hvor `private.membership_is_current` og den placement, `source_basis->>'record_placement_id'` peger på, har en
  `source_record` med samme `source_id`. Præcis én kandidat → placementens værdier
  (`printed_number` = `substring(printed_number from '^[0-9]+')::integer`); ellers legacy. Tilføj
  `UNION ALL` for kandidater uden legacy-række (forventet 0). `ORDER BY person_id, source_id`.
- [ ] **Step 4: Migrationsblok, paritet (35 → 36) og CI-trin** som Task 1 Step 6.
- [ ] **Step 5: Kør** testen + `test-placement-membership.sql` + paritets-`cmp`. Forventet: grønt, 36 linjer ens.
- [ ] **Step 6: Commit** `feat(db): public_person_source_coordinates fra gældende placement`.

### Task 3: Ceremonimateriale og stand-in-øvelse (PR 1)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/maal_5c2_b11.sql`, `.claude/skills/daa-extract/scripts/check_5c2_coordinate_diff.sql`,
  `.claude/skills/daa-extract/scripts/5c2_forventet_diff.txt`, `.claude/skills/daa-extract/scripts/5c2_forventet_maal.txt`,
  `docs/runbooks/5c2-b11-prod.md`
- Private (ikke i git): `~/.private/5ab-overfoersel/24-5c2-b11.sh`

**Interfaces:**
- Consumes: migrationsblokken `-- BEGIN 5c2-b11 … -- END 5c2-b11` fra Task 1-2.
- Produces: `maal_5c2_b11.sql` printer én linje `C2B11_MAAL funktioner=<0|3> definer=<n> anon=<t|f> auth=<t|f>
  koord=<n> placement=<n> legacy=<n> fakta=<n> bundet=<n> import=<n> ingen_kilde=<n> uden_narrativ=<n>
  udfald_i_alt=<n> udfald_publicering=<n>` (antal; `funktioner=0` før DDL'en, og så er resten tomt).
  `check_5c2_coordinate_diff.sql` printer diff-sættet som `person_id|felt`-linjer og én slutlinje
  `C2B11_DIFF n=<n> genparitet=<ok|fejl>`.

- [ ] **Step 1: Skriv `maal_5c2_b11.sql`** (læse-kun; `has_function_privilege` for anon og authenticated; tællinger
  kaldt `SET LOCAL ROLE anon`; `uden_narrativ` = offentlige personer uden narrativ med ≥1 række fra fakta-RPC'en;
  `udfald_i_alt` = assertion-promotions på offentlige personers fakta, hvor `record_ref` er NULL;
  `udfald_publicering` = de af dem, hvor `assertion_binding_current` og betingelse 2 holder, men betingelse 3
  fejler — spec §7's tal for betingelse 3).
- [ ] **Step 2: Skriv `check_5c2_coordinate_diff.sql`.** Felterne `legacy_line_code`, `printed_number`,
  `printed_number_label` (legacy normaliseret til `nr::text`), `generation_local`, `generation_global`,
  `kuld_label`; sammenlign RPC'en med `person_source_coordinate_legacy` som `anon`; `provenance_kind` indgår ikke.
  `genparitet=ok` når `(person_id, source_id, legacy_line_code, generation_local, generation_global)` er ens for alle
  rækker og eneste afvigende felter er `kuld_label` og `printed_number_label` (spec §7, træparitet).
- [ ] **Step 3: Byg en stand-in** fra A6b-dumpet (`~/.private/5ab-overfoersel/prod/a6b/daa-prod-20261028224757-a6b.dump`)
  med husets opskrift (ICU, `db-rls.sql`, `ANALYZE`, `ALTER DATABASE … SET statement_timeout='2min'`), navn
  `daa5ab_ddl_standin_<stempel>_5c2`. Kør `maal` (forventet `funktioner=0`), anvend blokken, kør `maal` og diff.
  Forventet: `C2B11_DIFF genparitet=ok` med højst 40 linjer (35 `kuld_label`, 5 `printed_number_label`; færre kun
  hvis nogle af personerne er levende og derfor skjult for `anon`), `placement + legacy = koord` (højst 576 + 591),
  `uden_narrativ=621`. Skriv det målte diff-sæt til `5c2_forventet_diff.txt` (person-id'er og feltnavne, ingen
  tekst) og `maal`-linjen efter DDL'en til `5c2_forventet_maal.txt`; begge er prods forventning (runner og
  HTTP-gate) og står også i runbooken. Afviger noget andet: stop og ledger en ruling.
- [ ] **Step 4: Skriv runbooken** (husets form, jf. `docs/runbooks/a6b-narrativ-revision-prod.md`): hvad skrives
  (tre funktioner, ingen data), forløb `maal → go → dump → apply → maal → NOTIFY pgrst → get_advisors →
  PostgREST-gate`, stand-in-tal fra Step 3, fortrydelse (revert PR 2; funktionerne bliver stående; dumpet er
  nødudvejen).
- [ ] **Step 5: Skriv den private runner** `24-5c2-b11.sh` efter `23-a6b.sh`-mønstret (`lib.zsh`, `koer.zsh`):
  `maal`, `go` (GO-kode over commit + migrationsblok + de to SQL-filer + begge forventningsfiler + runneren selv og
  de `lib.zsh`-hjælpere, den kører, som i `docs/runbooks/a6b-narrativ-revision-prod.md:21`), `dump` (B1, age,
  rundtur), `apply --jeg-mener-det --go X` (B1-genkontrol, `maal` før = `funktioner=0`, blokken udtrukket med `sed`
  fra markørerne i én transaktion, `NOTIFY pgrst`, `maal` efter = `5c2_forventet_maal.txt` byte for byte, diff =
  `5c2_forventet_diff.txt` → `C2B11_APPLY_OK`).
  Øv den mod stand-in'en fra Step 3 (frisk kopi), inkl. et afvist forsøg med forkert GO-kode.
- [ ] **Step 6: Commit** (kun repo-filerne) `feat(5c2): måling, diffkontrol og runbook til prod`. Push og draft-PR
  kun efter projektejerens ja.

### Task 4: Koordinatkontrakt i core (PR 2)

Gren `feat/5c2-b11-klient` fra `main` efter PR 1's merge. Kan skrives før ceremonien, men merges først efter.

**Files:**
- Create: `packages/core/src/placementCoordinates.ts`, `packages/core/src/__tests__/placementCoordinates.test.ts`
- Modify: `packages/core/src/types.ts:8-18,131`, `packages/core/src/collapseSameAs.ts:308-312`,
  `packages/core/src/index.ts`, `packages/core/src/__tests__/collapseSameAs.test.ts`,
  `packages/core/src/__tests__/generations.test.ts`

**Interfaces:**
- Produces: `RawExtId` får `nr_label?: string | null; provenance?: 'placement' | 'legacy_external_id'`;
  `Provenance` får `nr_label: string | null`; `type PublicCoordinateRow` (RPC'ens kolonner fra Task 2);
  `coordinateRowToExtId(row: PublicCoordinateRow): RawExtId`;
  `compareLineHead(a: { nr: number | null; nr_label?: string | null }, b: same): number`.

- [ ] **Step 1: Skriv de fejlende tests:**
  - `coordinateRowToExtId` mapper `legacy_line_code→linje`, `printed_number→nr`, `printed_number_label→nr_label`,
    `generation_local→slaegtled_lokal`, `generation_global→slaegtled_gennem`, `kuld_label→kuld`,
    `provenance_kind→provenance`; NULL-felter forbliver `null`.
  - `compareLineHead`: `{nr:15,nr_label:'15a'}` < `{nr:15,nr_label:'15b'}` < `{nr:16}`; `nr:null` sidst.
  - `collapseSameAs`: en foldet person, hvis alias har `nr_label:'41b'`, har `mergedFrom[...]` med `nr_label:'41b'`.
  - `buildGenCoords` er en projektion af netop `(person_id, source_id, linje, slaegtled_lokal, slaegtled_gennem,
    kuld)`: to inputs, der kun adskiller sig i `nr`, `nr_label` og `provenance`, giver identisk output.
- [ ] **Step 2: Kør** `npm run test -w @daa/core`. Forventet: FAIL (`coordinateRowToExtId` findes ikke).
- [ ] **Step 3: Implementér** typerne, de to funktioner og `nr_label` i `collapseSameAs`' `ext`-map og `mergedFrom`.
- [ ] **Step 4: Kør** `npm run test -w @daa/core && npm run typecheck -w @daa/core`. Forventet: grønt.
- [ ] **Step 5: Commit** `feat(core): koordinatkontrakt med nr_label og provenance`.

### Task 5: `buildPersonFacts` i core (PR 2)

**Files:**
- Create: `packages/core/src/personFacts.ts`, `packages/core/src/__tests__/personFacts.test.ts`
- Modify: `packages/core/src/index.ts`

**Interfaces:**
- Produces: `type PublicPersonFactRow` (kolonnerne fra Task 1); `type PersonFactSource = { kind: 'bundet' |
  'import' | 'ingen'; label: string; recordRef: string | null }`; `type PersonFactStatement = { assertionId:
  string; value: string; source: PersonFactSource }`; `type PersonFactView = { factId: string; faktatype: string;
  omstridt: boolean; chosen: PersonFactStatement | null; others: PersonFactStatement[] }`;
  `buildPersonFacts(rows: PublicPersonFactRow[]): PersonFactView[]`; `FAKTA_UDELADT = ['forældrefamilie',
  'forældre_ukendt']`.

- [ ] **Step 1: Skriv de fejlende tests:**
  - Udeladelse: rækker med `forældrefamilie` og `forældre_ukendt` giver intet.
  - Rækkefølge: `navn, tilnavn, fødsel, dåb, titel, dekoration, adling, floruit, klosterindgang, overhoved, død,
    dødsårsag, begravelse`; inden for typen `date_min` (NULL sidst), så `fact_id`; ukendte typer sidst.
  - Værdi: `vaerdi_tekst` og `date_raw` sammen som `"<vaerdi_tekst>, <date_raw>"`, ellers den ene, ellers `"—"`.
  - Kilde: `record_ref` sat → `kind:'bundet'`, `label = "<source_label>, <citation_label || record_label>"`;
    ellers `source_label` sat → `kind:'import'`, `label = side ? "<source_label>, s. <side>" : source_label`;
    ellers `kind:'ingen'`, `label:'Kilde ikke registreret'`.
  - Flere påstande: den med `chosen` er `chosen`, resten i `others` med hver sin kilde. Omstridt uden valgt:
    `omstridt:true`, `chosen:null`, alle i `others`.
  - Dedup: samme `fact_id` fra to medlems-id'er giver ét `PersonFactView`; samme `assertion_id` med to citationer
    giver to udsagn.
- [ ] **Step 2: Kør** `npm run test -w @daa/core`. Forventet: FAIL.
- [ ] **Step 3: Implementér** `buildPersonFacts`.
- [ ] **Step 4: Kør** test + typecheck. Forventet: grønt.
- [ ] **Step 5: Commit** `feat(core): buildPersonFacts med tre kildevisninger`.

### Task 6: Web (PR 2)

**Files:**
- Modify: `web/src/data/model.ts:72-77,153`, `web/src/data/lineage.ts:104-106`, `web/src/data/sources.ts:20`,
  `web/src/data/public.ts:176-260`, `web/src/components/DetailPanel.tsx:84` og fakta-sektionen før »Kilde i
  Aarbogen« (`:270`)
- Create: `web/src/components/PersonFakta.tsx`, `web/src/components/__tests__/PersonFakta.test.tsx`,
  `web/e2e/person-facts.spec.ts`
- Modify: web-tests, der mocker `person_source_coordinate_legacy` eller `PersonDetailData` (find med grep)

**Interfaces:**
- Consumes: `coordinateRowToExtId`, `compareLineHead` (Task 4); `buildPersonFacts`, `PersonFactView` (Task 5).
- Produces: `PersonDetailData` får `facts: PersonFactView[]; factsError: boolean` (også i `TOM_PERSONDETALJE`).

- [ ] **Step 1: Skriv de fejlende tests:**
  - `PersonFakta.test.tsx`: overskriften »Fakta«; et bundet udsagn viser »bundet til bogens post«, et importeret
    »fra den oprindelige import«, et uden kilde »Kilde ikke registreret«; omstridt viser »omstridt« og »Andre
    udsagn«; `error` viser »Fakta kunne ikke hentes«; tom liste uden fejl renderer intet.
  - `person-facts.spec.ts` (hermetisk mock som `family-sources.spec.ts`): `rpc/public_person_source_coordinates`
    returnerer en række med `printed_number_label:'15a'` → detaljen viser »I-15a«; `rpc/public_person_facts`
    kaldes med alle `p_person_ids` for en foldet person og viser sektionen for en person uden bio; et 500-svar fra
    fakta-RPC'en viser »Fakta kunne ikke hentes«; `person_source_coordinate_legacy` kaldes aldrig.
- [ ] **Step 2: Kør** `npm run test -w web` og `npm run e2e -w web -- person-facts`. Forventet: FAIL.
- [ ] **Step 3: Implementér:** loaderen via `getAll(() => supabase.rpc('public_person_source_coordinates'))
  .then(r => r.map(coordinateRowToExtId))` med den eksisterende `.catch(warn → [])`; `extMap` bærer `nr_label`;
  `lineage.ts` bruger `compareLineHead`; visning `nr_label ?? nr`; `fetchPersonDetail` kalder
  `public_person_facts` med `numIds` i den eksisterende `Promise.all` (fejl → `factsError:true`, `facts:[]`, resten
  af detaljen uberørt); `PersonFakta` i `DetailPanel`.
- [ ] **Step 4: Kør** `npm run test -w web && npm run build -w web && npm run e2e -w web`. Forventet: grønt.
- [ ] **Step 5: Commit** `feat(web): fakta med kilde og koordinater fra placement`.

### Task 7: Mobil (PR 2)

**Files:**
- Modify: `mobile/src/data/load.ts:219,350`, `mobile/src/data/buildAux.ts:72,101-102`,
  `mobile/src/app/person/[id].tsx:98`, mobil-tests der mocker `person_external_id` (find med grep)

**Interfaces:**
- Consumes: `coordinateRowToExtId`, `compareLineHead` (Task 4).

- [ ] **Step 1: Ret testene** til den nye RPC (`public_person_source_coordinates`) og et `nr_label`-suffiks i
  visningen; kør `npm test -w mobile`. Forventet: FAIL.
- [ ] **Step 2: Implementér** loaderen (`getAll` + `coordinateRowToExtId`), `extMap` med `nr_label`,
  `compareLineHead` i `buildAux`, visning `nr_label ?? nr`.
- [ ] **Step 3: Kør** `npm test -w mobile && npm --workspace mobile exec -- tsc --noEmit`. Forventet: grønt.
- [ ] **Step 4: Kør hele node-CI-jobbet lokalt** (`ci.yml:51-93`). Forventet: grønt.
- [ ] **Step 5: Commit** `feat(mobil): koordinater fra public_person_source_coordinates`.

### Task 8: Prod (projektejeren) og merge-gate

**Files:**
- Create: `web/scripts/verify-public-rpcs.mjs`, `web/scripts/verify-public-rpcs.test.mjs`

- [ ] **Step 1: Skriv `verify-public-rpcs.mjs`** med `@supabase/supabase-js` (som appen), så pagineringen er
  klientens egen: `supabase.rpc(navn, args).range(from, from+999)` til en kort side, fejl kaster. Læser
  `VITE_SUPABASE_URL` og `VITE_SUPABASE_ANON_KEY` fra `web/.env.local` uden at printe dem. Personmængden er alle
  offentlige person-id'er fra `person` (`select('id')`, pagineret, som `anon`), ikke kun dem med koordinater, så
  personer uden bog-nummer kommer med; fakta-RPC'en kaldes i bidder af 500 id'er. Printer kun
  `RPC_GATE koord=<n> placement=<n> legacy=<n> fakta=<n> bundet=<n> import=<n> ingen=<n> resultat=<OK|AFVIGER>`,
  hvor resultatet er sammenligningen med de tilsvarende felter i `5c2_forventet_maal.txt`.
  `verify-public-rpcs.test.mjs` (`node --test`, hermetisk `fetch`-mock): tre sider (1000, 1000, 17) giver 2017
  rækker; en 500-fejl på side 2 giver exit ≠ 0; nøglen forekommer ikke i output. Commit på PR 2-grenen:
  `chore(web): PostgREST-gate for de offentlige RPC'er`.
- [ ] **Step 2: Ceremonien** (efter PR 1's merge; projektejerens shell, én kommando ad gangen):
  `koer.zsh 24-5c2-b11.sh maal` → `funktioner=0`; `go` → kode; `dump` → `EKSTERN_… rundtur=ok`;
  `apply --jeg-mener-det --go <kode>` → `C2B11_APPLY_OK`; derefter `get_advisors` (forventet: de to RPC'er som
  anon-eksponerede SECURITY DEFINER, som `public_family_sources`; intet andet nyt).
- [ ] **Step 3: Merge-gate.** `node web/scripts/verify-public-rpcs.mjs` mod prod. Forventet: `resultat=OK`
  (lig `5c2_forventet_maal.txt`, som GO-koden bandt). Afviger de: PR 2 merges ikke.
- [ ] **Step 4: Merge PR 2** (projektejeren) → Vercel. Browsertjek som `anon` (spec §7): person uden prosa med
  fakta; bundet faktum med postreference; en kuld-rettet person og en »15a«-person med uændret linjehoved; en
  kilde 3-person; en levende person uden fakta-sektion. Notér kun person-id'er og ja/nej.

### Task 9: Dokumentation

**Files:**
- Modify: `docs/evidensbaseret-genimport/status.md`, `docs/database-current-state.md`, `docs/changelog.md`

- [ ] **Step 1:** `status.md` (overskriv snapshot): rækkerne »Læsere på placement/membership (5c-2)« og
  »Læserflade: fakta med kildehenvisning (B11)« → `produktionsverificeret` 2018-20 med dato og andelen bundne;
  »Aktivt programmål« → trin 6-spec'en (sig det samme i `roadmap.md`s »Aktivt programmål«). Ny § i
  `database-current-state.md` (funktioner, GO-kode, dump-sha, tal). Changelog-post.
- [ ] **Step 2: Commit** på en `docs/`-gren: `docs(status): 5c-2 og B11 i prod`.

## Reviewlog

**Codex plan-review r1 2026-10-29 (`gpt-6.1-sol`): NO-GO** (2 P1, 6 P2) → Opus-dom: alle 8 nødvendige, intet afvist.
Rettet:
- **P1:** HTTP-gaten bruger alle offentlige personer og klientens `.range()`-paginering, med en hermetisk test
  (Task 8).
- **P2:**
  - forventningsfilen `5c2_forventet_maal.txt` bundet i GO-koden og brugt af runner og gate (Task 3, Task 8)
  - `chosen` via `coalesce`
  - entydighedsgate for bindingen og citation-id i sorteringen
  - præcis OCR-fixture
  - negative tests for anchor, kilde, publiceringsgate, identitet, gemt regel og privat koordinatperson, med
    validatorens konkrete koder (Task 1-2)
  - udfaldsmålingen delt i i alt og betingelse 3 (Task 3)

Spec §4.1 betingelse 1 fik entydigheden. Review-budgettet for planen er brugt.
