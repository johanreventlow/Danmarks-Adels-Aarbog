# Evidensbaseret genimport og multi-slægt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Etablér en kildebevarende importarkitektur, hvor eksplicitte oplysninger udtrækkes granulært, identiteter afklares uden gæt, og personer, slægter, linjer, grene og kildeudgaver vises korrekt uden kildespecifikke lappeløsninger i den kanoniske model.

**Architecture:** Rå kildetekst og kildeobservationer ligger i et privat evidenslag. Fortolkninger og identitetsforslag ligger i et separat redaktionelt lag. Kun godkendte promotioner projiceres til den kanoniske genealogiske model. Slægt, kanonisk linje og kildens linjeinddeling modelleres hver for sig; én kanonisk person kan derfor have flere kildeomtaler og flere linjetilhørsforhold uden at blive dubleret.

**Tech Stack:** PostgreSQL 17/Supabase, Python 3, JSON Schema, R/RPostgres, TypeScript, React, React Native, Vitest/Jest og pytest.

## Ufravigelige rammer

- Udfør planen i en ny worktree på en dedikeret featuregren, eksempelvis feat/evidensbaseret-genimport. Udfør den ikke direkte på feat/union-redigering.
- Kontrollér git branch --show-current umiddelbart før hver filændring, staging og commit. Stop ved uventet gren eller fremmede ændringer.
- Slet eller erstat ingen produktionsdata, før en særskilt menneskeligt godkendt cutover.
- Brug den eksisterende database som sammenligningsgrundlag og som kilde til redaktionelle beslutninger, ikke som facit for ny udtrækning.
- Bevar rå OCR og transskription ordret. Normaliseret tekst er altid en afledt variant med provenance.
- Uden entydigt identitetsanker bliver resultatet en redaktionel opgave; systemet må aldrig gætte.
- Samme kildepersona må højst have ét aktivt kanonisk mål.
- record_key identificerer en logisk bogpost, aldrig automatisk et menneske. Layoutfelter er lokatorer, ikke varige ID'er.
- Bogens slægtled lagres pr. kildeplacering. Ægteskabsrelationer indgår aldrig i generationsberegning eller automatisk lineage-medlemskab.
- Våben, media og beskrivelser er generelle, versionsstyrede entiteter/forbindelser og må ikke modelleres som slægtsspecifikke specialfelter.
- Kandidater, OCR og redaktionelle beslutninger er private og må ikke kunne læses af anon eller almindelige authenticated-brugere.
- Commit kun syntetiske fixtures. Faktiske arbejdsartefakter, PDF-udtræk og potentielle persondata skal ligge i ignorerede arbejdsmapper.
- Hold 1939- og 2018–20-profiler adskilt. Genkendelsesændringer må ikke ændre no-flag/default-adfærd uden regressionstest og godkendelse.
- Afslut hver fase med fokuserede tests, relevante fulde testpakker, diff-kontrol og små commits. Rapportér kendte baselinefejl særskilt.
- Fuld bogkørsel, ekstern modelbehandling af levende personer og produktions-cutover kræver hver sin udtrykkelige menneskelige GO-beslutning.

## Arbejdsspor og kritisk vej

Den kritiske vej til de første extraction- og identitets-GO'er er Task 1–7, 10–11 og 13–22. Task 8–9 (heraldik og generelle beskrivelser) er et selvstændigt spor H, og Task 12 (mobil redaktørparitet) er et selvstændigt spor M. Spor H og M må udskydes uden at blokere 2018-A, 2018-B, 1939-A eller 1939-B; de skal først være grønne, før deres egne funktioner publiceres. Afhængigheder til et udskudt spor testes med stubs eller feature flags, ikke ved at udvide den kritiske model.

---

## Fase 0: Isolér arbejdet og frys baselines

### Task 1: Opret arbejdsgren og registrér reproducerbare baselines

**Files:**

- Create: docs/superpowers/reviews/evidence-import-baseline.md
- Inspect: .claude/skills/daa-extract/scripts/
- Inspect: schema.sql
- Inspect: db-migrations.sql
- Inspect: db-rls.sql
- Inspect: db-verify.sql
- Inspect: packages/core/src/
- Inspect: web/src/data/

- [ ] **Step 1: Bekræft udgangspunkt og opret worktree**

Kør fra det nuværende repository:

~~~bash
git branch --show-current
git status --short
git worktree add ../danmarksadelsaarbog-evidence -b feat/evidensbaseret-genimport
~~~

Forvent en ren worktree på den nye gren.

- [ ] **Step 2: Mål testbaselines uden datamutation**

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts
npm test --workspace packages/core -- --run
npm test --workspace web -- --run
~~~

Notér kommando, commit, beståede og fejlede tests samt fuld fejlidentitet. En eksisterende fejl må ikke kaldes grøn baseline.

- [ ] **Step 3: Registrér databasestrukturen som kontrolpunkt**

Dokumentér de effektive definitioner for lineage, person_external_id, person, familie-/relationsmodellen, kildecitater og redaktionelle roller med fil:linje. Markér snapshot som kodebaseret, indtil det er sammenholdt med en lokal database.

- [ ] **Step 4: Verificér og commit**

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/evidence-import-baseline.md
git branch --show-current
git commit -m "docs: freeze evidence import baselines"
~~~

**Stopport 0:** Baseline er reproducerbar, worktree er ren, og ingen bogdata er ændret.

---

## Fase 1: Fælles evidenskontrakt

### Task 2: Definér observationer, tekstvarianter og kildepersonaer

**Files:**

- Create: .claude/skills/daa-extract/references/observation-schema.json
- Create: .claude/skills/daa-extract/references/interpretation-schema.json
- Create: .claude/skills/daa-extract/references/source-anchor-contract.md
- Create: .claude/skills/daa-extract/scripts/evidence_contract.py
- Create: .claude/skills/daa-extract/scripts/test_evidence_contract.py
- Create: .claude/skills/daa-extract/scripts/tests/fixtures/evidence-observation.synthetic.json
- Create: .claude/skills/daa-extract/requirements-test.txt
- Modify: .github/workflows/ci.yml

- [ ] **Step 1: Skriv kontrakttests, som først fejler**

Test præcist:

~~~python
def test_observation_requires_exact_source_span(): ...
def test_normalized_text_cannot_replace_verbatim_text(): ...
def test_mention_offsets_must_be_inside_observation(): ...
def test_source_persona_is_scoped_to_one_source_edition(): ...
def test_record_key_is_not_derived_from_layout_or_person_name(): ...
def test_occurrence_can_remain_unanchored_without_data_loss(): ...
def test_two_renditions_can_map_to_one_logical_record(): ...
def test_occurrence_has_at_most_one_accepted_record_anchor(): ...
def test_split_or_merge_requires_reviewed_revision_links(): ...
def test_interpretation_requires_observation_ids(): ...
def test_unknown_and_absent_are_distinct(): ...
def test_confidence_is_not_an_identity_decision(): ...
~~~

Kør den fokuserede pytest og forvent fejl, fordi kontrakterne mangler.

- [ ] **Step 2: Implementér minimal Python-kontrakt**

~~~python
@dataclass(frozen=True)
class SourceSpan:
    rendition_id: str
    page_from: int
    page_to: int
    column_label: str | None
    char_from: int
    char_to: int
    bbox: tuple[int, int, int, int] | None

@dataclass(frozen=True)
class Observation:
    observation_id: str
    occurrence_id: str
    kind: str
    verbatim_text: str
    span: SourceSpan
    extraction_method: str
    extraction_run_id: str

@dataclass(frozen=True)
class RecordOccurrence:
    occurrence_id: str
    rendition_id: str
    extraction_run_id: str
    span: SourceSpan
    verbatim_text: str

@dataclass(frozen=True)
class RecordPlacement:
    record_key: str
    scheme_entry_id: str
    printed_number: str | None
    generation_local: int | None
    generation_global: int | None
    generation_label_raw: str | None
    kuld_label: str | None
    header_observation_id: str
~~~

Validatoren afviser ukendte felter, tom verbatim_text, negative eller omvendte spans, dublerede ID'er og fortolkninger uden kendte observationer. En record placement uden en kendt header_observation_id afvises; legacy-felter kan først migreres, når kildeudtrækket leverer denne observation.

source-anchor-contract.md fastlægger, at første accepterede segmentering opretter en logisk source_record med uigennemsigtig record_key og en accepteret source_record_anchor_event til den rå occurrence. En ny OCR-rendition opretter først en uforankret occurrence. Verificeret én-til-én-kontinuitet forankrer den til den eksisterende record; split, merge og tvivl opretter nye records eller reviewopgaver med append-only revision-events.

- [ ] **Step 3: Definér JSON Schema**

Observationsskemaet kræver schema_version, source_rendition, source_records, source_record_occurrences, source_record_anchor_events, source_record_revision_events, record_placements, persona_placements, observations, text_variants, mentions, source_personas og extraction_run. Fortolkningsskemaet kræver interpretation_id, observation_ids, predicate, typed value, status, method og created_at.

Ingen kontrakt må gøre en kildepersona direkte til kanonisk person uden særskilt identitetsafgørelse.

- [ ] **Step 4: Tilføj syntetisk svær fixture**

Fixture omfatter samme mand omtalt tre gange med forskellig prosa; barn i én linje og grundlægger i en anden; en mand gift med sin niece fra et andet trykt slægtled; indgiftet uden afledt slægtsnavn; titel og embede; usikker, ukendt og manglende dato; samt modstridende kilder.

- [ ] **Step 5: Test og commit**

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -q
git diff --check
git branch --show-current
git add .github/workflows/ci.yml .claude/skills/daa-extract/requirements-test.txt .claude/skills/daa-extract/references .claude/skills/daa-extract/scripts/evidence_contract.py .claude/skills/daa-extract/scripts/test_evidence_contract.py .claude/skills/daa-extract/scripts/tests/fixtures/evidence-observation.synthetic.json
git branch --show-current
git commit -m "feat: define evidence extraction contracts"
~~~

Tilføj samtidig en Python-job eller et eksplicit trin i CI, som installerer den pinnede testafhængighed fra `requirements-test.txt` og kører hele `.claude/skills/daa-extract/scripts`-suiten med `python3 -m pytest`. Pin første pytest-version til den lokalt verificerede `8.4.2`. Den lokale macOS-kommando bruger fortsat `/usr/bin/python3`; CI må ikke antage samme absolutte sti.

### Task 3: Indfør klausul-ledger og deterministiske record-grænser

**Files:**

- Create: .claude/skills/daa-extract/scripts/clause_ledger.py
- Create: .claude/skills/daa-extract/scripts/test_clause_ledger.py
- Modify: .claude/skills/daa-extract/scripts/segment.py
- Modify: .claude/skills/daa-extract/scripts/validate.py

- [ ] **Step 1: Skriv regressionstests**

Test fuld tegnregnskab, nul eller flere observationer pr. klausul, record_key uafhængig af linjenummer, uændret default-output og editionsisolation. Tilføj testene:

~~~python
def test_generation_header_creates_record_placement_with_header_evidence(): ...
def test_spouse_mention_does_not_inherit_principal_generation(): ...
def test_uncle_and_niece_keep_different_printed_generations(): ...
def test_spouse_edges_are_excluded_from_computed_generation(): ...
~~~

- [ ] **Step 2: Implementér ledger som sidecar**

Tilføj et eksplicit flag --emit-evidence-ledger. Uden flag skal output være identisk med baseline. Hver ledger-række indeholder record_key, occurrence-ID, clause-ID, span, klassifikation og observations-ID'er. Strukturelle overskrifter giver record placement med ordret slægtledslabel, lokal/gennemgående ordinal, kuld og header-observation.

- [ ] **Step 3: Tilføj dækningsinvariant**

Alle ikke-whitespace tegn tilhører en klausul eller er eksplicit klassificeret layout/støj. Afvis overlap undtagen registrerede nested spans.

- [ ] **Step 4: Test og commit**

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_clause_ledger.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/scripts/clause_ledger.py .claude/skills/daa-extract/scripts/test_clause_ledger.py .claude/skills/daa-extract/scripts/segment.py .claude/skills/daa-extract/scripts/validate.py
git branch --show-current
git commit -m "feat: add source clause coverage ledger"
~~~

**Stopport 1:** Kontrakt og ledger validerer fixture, og eksisterende default-segmentering er uændret.

---

## Fase 2: Privat evidens- og fortolkningslag

### Task 4: Opret append-only kildelag og extraction runs

**Files:**

- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql

- [ ] **Step 1: Skriv fejlede DB-verifikationer først**

Tilføj assertions for tabeller, fremmednøgler, unikheder, immutabilitet og rettigheder før DDL. Test specifikt, at en occurrence kan eksistere uden anchor; højst én accepted anchor er aktuel også ved samtidige writes; accepted kræver actor/timestamp/evidence; et afvist forslag kan genfremsættes som en ny version uden UPDATE; og split/merge aldrig kan repræsenteres som tavs én-til-én-genbrug.

- [ ] **Step 2: Tilføj private tabeller**

Implementér private.extraction_run, source_rendition, source_record, source_record_occurrence, source_record_anchor_event, source_record_revision_event, source_observation, source_observation_text, source_mention, source_persona og source_persona_mention. Junction-tabellen skal bevare mentionens rolle og rækkefølge i personaen. Alle nye maskinkoder er engelske; danske etiketter hører til præsentationslaget.

Kerne-DDL følger dette mønster:

~~~sql
create table private.source_rendition (
  id uuid primary key default gen_random_uuid(),
  source_id bigint not null references source(id),
  rendition_key text not null,
  rendition_kind text not null,
  content_sha256 text not null,
  metadata jsonb not null default '{}'::jsonb,
  unique (source_id, rendition_key)
);

create index source_rendition_content_idx
  on private.source_rendition (source_id, content_sha256);

create table private.source_record (
  id uuid primary key default gen_random_uuid(),
  source_id bigint not null references source(id),
  record_key text not null,
  record_kind text not null,
  created_run_id uuid not null references private.extraction_run(id),
  unique (source_id, record_key)
);

create table private.source_record_occurrence (
  id uuid primary key default gen_random_uuid(),
  rendition_id uuid not null references private.source_rendition(id),
  occurrence_key text not null,
  page_from integer not null,
  page_to integer not null,
  column_label text,
  char_from integer not null,
  char_to integer not null,
  bbox jsonb,
  verbatim_text text not null,
  physical_fingerprint text not null,
  structural_fingerprint text not null,
  extraction_run_id uuid not null references private.extraction_run(id),
  unique (rendition_id, extraction_run_id, occurrence_key)
);

create table private.source_record_anchor_event (
  id uuid primary key default gen_random_uuid(),
  occurrence_id uuid not null references private.source_record_occurrence(id),
  source_record_id uuid not null references private.source_record(id),
  decision_status text not null check (
    decision_status in ('proposed','accepted','rejected')
  ),
  evidence jsonb not null,
  version integer not null default 1,
  -- Immutable audit identifier: intentionally no FK to mutable auth.users.
  decided_by uuid,
  decided_by_name text,
  decided_at timestamptz not null default now(),
  unique (occurrence_id, source_record_id, version)
);

create table private.source_record_revision_event (
  id uuid primary key default gen_random_uuid(),
  predecessor_record_id uuid not null references private.source_record(id),
  successor_record_id uuid not null references private.source_record(id),
  relation_kind text not null check (
    relation_kind in ('split_into','merged_from','replaced_by')
  ),
  decision_status text not null check (
    decision_status in ('proposed','accepted','rejected')
  ),
  evidence jsonb not null,
  version integer not null,
  -- Immutable audit identifier: intentionally no FK to mutable auth.users.
  decided_by uuid,
  decided_by_name text,
  decided_at timestamptz not null default now(),
  unique (
    predecessor_record_id, successor_record_id, relation_kind, version
  )
);
~~~

Forslag, accept og afvisning er separate append-only events; current-state views udleder den seneste version pr. nøgle. Ved insert af en accepterende anchor-event låser write-RPC'en occurrence-rækken, validerer næste version og afviser, hvis en anden kandidat fortsat er aktuelt accepteret. Test to samtidige acceptforsøg; en sekventiel check er ikke nok. En afvisning og et senere genforslag bruger et højere versionsnummer og aldrig UPDATE. source_persona scopes til source_id, ikke rendition_id, så samme kildepersona kan overleve forbedret OCR. Forankring til en eksisterende record kræver accepteret én-til-én-kontinuitet; split, merge eller flere kandidater går til review. Observationer peger på occurrence og får logisk record-kontekst gennem den aktive anchor. Publicering af en record-narrativ er en særskilt promotion med auditspor; rå recordtekst bliver ikke offentlig alene ved indlæsning.

- [ ] **Step 3: Gør rå evidens append-only**

Blokér UPDATE og DELETE på rendition, record, observation, anchor events og revision events. Korrektion sker med ny extraction run, ny eventversion og supersedes_id, aldrig ved overskrivning. Aktør-/creator-UUID'er på append-only-rækker er frosne auditværdier uden FK til `auth.users`; ellers ville `ON DELETE SET NULL` selv være en forbudt UPDATE af historikken.

- [ ] **Step 4: Lås laget privat**

~~~sql
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
revoke all on schema private from public, anon, authenticated;

alter default privileges in schema private
  revoke all on tables from public, anon, authenticated;
alter default privileges in schema private
  revoke all on sequences from public, anon, authenticated;
alter default privileges in schema private
  revoke execute on functions from public, anon, authenticated;
~~~

Kør ALTER DEFAULT PRIVILEGES som den samme ejerrolle, der skal oprette de senere private objekter; default privileges er ejer-specifikke. PostgreSQL's indbyggede `EXECUTE` til `PUBLIC` kan ikke fjernes schema-lokalt, så sikkerheden for senere private funktioner består af manglende `USAGE` på schemaet, schema-lokale default-revokes og eksplicit funktions-revoke ved hver migration — ikke af en global ændring, som ville påvirke public-RPC'er. Verificér effektiv adgang som rollerne, ikke kun den isolerede funktions-ACL. Opret i testen en midlertidig tabel og funktion efter default-revokes for at bevise, at fremtidige objekter heller ikke kan nås.

- [ ] **Step 5: Test frisk lokal database og commit**

Anvend fuld schema-/migrationsvej og db-verify.sql på en tom lokal database, aldrig produktion.

~~~bash
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git branch --show-current
git commit -m "feat: add private source evidence schema"
~~~

### Task 5: Opret fortolkninger, promotions og identitetsafgørelser

**Files:**

- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql

- [ ] **Step 1: Skriv fail-closed verifikationer**

Databasen skal afvise to aktive kanoniske mål for samme persona, promotion uden accepteret fortolkning, fortolkning uden observation, afgørelse uden actor/tid og falsk menneskelig godkendelse.

- [ ] **Step 2: Implementér tabeller**

Tilføj private.interpretation, interpretation_observation, interpretation_promotion, source_persona_identity og source_persona_identity_event.

Én persona har højst én aktiv identitet. Status er proposed, accepted, rejected, unresolved eller superseded. Partial match modelleres med separate personaer/mentions.

- [ ] **Step 3: Implementér atomiske security-definer-funktioner**

Følg projektets current_rolle-, search_path-, revoke/grant- og auditmønster. Accept/afvis skal låse mål-rækken, kontrollere expected_version og skrive event samt ny tilstand i samme transaktion.

- [ ] **Step 4: Test samtidighed og commit**

To afgørelser fra samme version skal give præcis én succes og én versionskonflikt. Offentlige brugere må ikke kalde mutationerne.

~~~bash
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql
git branch --show-current
git commit -m "feat: add interpretation and identity decision ledger"
~~~

**Stopport 2:** Laget installeres fra nul, er privat og bevarer alle evidensversioner.

---

## Fase 3: Ren model for slægt, linje, gren og kildeskema

### Task 6: Adskil slægt og kanonisk lineage fra kildens nummerering

**Files:**

- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql
- Create: packages/core/src/slaegter.ts
- Create: packages/core/src/__tests__/slaegter.test.ts
- Modify: packages/core/src/types.ts
- Modify: packages/core/src/index.ts
- Inspect and inventory: packages/core/src/generations.ts
- Inspect and inventory: packages/core/src/tree.ts
- Inspect and inventory: packages/core/src/matchUdgaver.ts
- Inspect and inventory: web/src/data/model.ts
- Inspect and inventory: mobile/src/data/load.ts
- Inspect and inventory: .claude/skills/daa-extract/scripts/backfill_slaegtled.R
- Inspect and inventory: .claude/skills/daa-extract/scripts/post_load_fixup.R

- [ ] **Step 1: Skriv modeltests**

Bevis: to slægter kan begge have kode II; stamtavle og præsensliste kan nummerere samme lineage forskelligt; en lineage hører til én slægt; en person kan have flere memberships uden kopi; indgiftede arver ikke slægtsnavn; flere slægtsmedlemskaber kræver kontekst eller neutral etikette. Tilføj desuden:

~~~text
En mand og hans niece kan være ægtefæller og beholde forskellige trykte slægtled.
En spouse edge ændrer aldrig beregnet parent-child-generation.
En omtalt ægtefælle arver ikke hovedpersonens record placement.
Samme person kan have forskellige slægtledslabels i to source schemes.
Der findes ingen global generation-kolonne på person.
~~~

- [ ] **Step 2: Implementér kanonisk DDL**

Tilføj:

~~~text
public.slaegt(id, navn, sorteringsnavn, slug, status)
public.lineage(..., slaegt_id, canonical_label, parent_lineage_id)
public.lineage_scheme(id, slaegt_id, source_id, kind, label)
public.lineage_scheme_entry(id, scheme_id, code, label, sort_order)
public.lineage_scheme_entry_lineage(entry_id, lineage_id, relation_kind)
public.person_slaegt_membership(person_id, slaegt_id, membership_kind, source_basis)
public.person_lineage_membership(person_id, lineage_id, role, valid_from, valid_to)
private.source_record_placement(id, source_record_id, scheme_entry_id, printed_number, generation_local, generation_global, generation_label_raw, kuld_label, section_path, header_observation_id, supersedes_placement_id)
private.source_persona_placement(source_persona_id, record_placement_id, placement_role, basis_observation_id, status)
~~~

Flyt presens_kode-semantik til lineage_scheme_entry. Unikhed er (scheme_id, code), aldrig global code.

source_record_placement er unik blandt aktive placeringer pr. (source_record_id, scheme_entry_id), og header_observation_id er obligatorisk. Tabellen har ingen legacy-undtagelse: uden accepteret source record og overskriftsobservation oprettes ingen placement. placement_role begrænses til principal_member, co_principal, mentioned_spouse og child_reference. Kun principal_member eller co_principal kan foreslås promoveret til lineage-medlemskab, og promotion kræver særskilt evidens. Genealogisk generation beregnes fra parent-child-relationer med valgt rod; family-partnere traverseres ikke som generationskanter.

- [ ] **Step 3: Inventér alle legacy-forbrugere før migration**

Kør mindst:

~~~bash
rg -n "slaegtled_lokal|slaegtled_gennem|kuld|presens_kode" schema.sql db-migrations.sql packages/core web mobile .claude/skills/daa-extract/scripts
~~~

Registrér alle læsere og skrivere samt deres overgangskontrakt. Inventaret skal mindst omfatte SQL-funktionen med max(slaegtled_lokal), API-payloads, core generations/tree/matchUdgaver, web- og mobilloadere samt R-backfill/fixup. Ingen legacy-kolonne eller fallback fjernes, før hver consumer har en navngivet erstatning og en paritetstest.

- [ ] **Step 4: Etablér schemes, men udskyd legacy-migrationen**

Opret Reventlow som slægt, forbind eksisterende lineages og opret schemes for kendte stamtavle-/præsensnummereringer. Bevar slaegtled_lokal, slaegtled_gennem og kuld uændret i person_external_id og registrér deres rækkeantal/hash som migrationsbaseline. Opret ikke source_record_placements for dem i denne fase: før Task 17/20 mangler både verificeret source record og header-observation. Selve migrationsleddet udføres kildevis efter extraction og er idempotent.

- [ ] **Step 5: Bevar eksplicit kompatibilitetsprojektion**

Hvis klienter stadig læser presens_kode eller legacy-slægtled, lever et navngivet overgangs-view/RPC. Før extraction læser det legacyfelterne; efter kildevis migration læser det verificerede placements og falder kun tilbage for eksplicit uafklarede rækker. Undgå tavs prioritetsændring og dobbelt sandhed i tabellerne. Cutover-gaten kræver, at hver legacy-række er migreret med observeret evidens, eksplicit bevaret eller forklaret som uafklaret; ingen række må forsvinde tavst.

- [ ] **Step 6: Implementér TypeScript-typer**

~~~typescript
export type SlaegtRef = { id: string; navn: string; slug: string };
export type LineageRef = {
  id: string;
  slaegtId: string;
  canonicalLabel: string;
  parentLineageId: string | null;
};
export type LineageSchemeEntryRef = {
  id: string;
  schemeId: string;
  code: string;
  label: string;
};
~~~

Cache- og opslagstaster indeholder stabile ID'er; rå II må aldrig være global nøgle.

- [ ] **Step 7: Test frisk DB, migreret DB og alle legacy-consumers; commit**

~~~bash
npm test --workspace packages/core -- --run packages/core/src/__tests__/slaegter.test.ts
npm test --workspace packages/core -- --run
npm test --workspace web -- --run
npm test --workspace mobile -- --runInBand
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql packages/core/src
git branch --show-current
git commit -m "feat: separate clans lineages and source schemes"
~~~

### Task 7: Opdatér webens lineage-opslag

**Files:**

- Modify: web/src/data/lineage.ts
- Modify: web/src/data/model.ts
- Modify: web/src/data/types.ts
- Modify: relevante tests under web/src/data/__tests__/

- [ ] **Step 1: Test kolliderende linjekoder**

Brug syntetiske slægter A og B med kode II samt to schemes med forskellig kode for samme lineage. Navigation, etiketter og cache må ikke krydse data.

- [ ] **Step 2: Brug ID-baseret kontekst**

~~~typescript
type LineageContext = {
  slaegtId: string;
  lineageId: string;
  schemeId?: string;
  schemeEntryId?: string;
};
~~~

Vis eksempelvis Reventlow · II. linje, når konteksten ellers er tvetydig.

- [ ] **Step 3: Test og commit**

~~~bash
npm test --workspace web -- --run
git diff --check
git branch --show-current
git add web/src/data/lineage.ts web/src/data/model.ts web/src/data/types.ts web/src/data/__tests__
git branch --show-current
git commit -m "refactor: scope lineage navigation by clan and scheme"
~~~

**Stopport 3:** Review bekræfter, at kernemodellen ikke indeholder 1939-linje, kildeår i kanoniske lineages eller globale romertal. Den kritiske vej kan fortsætte til Task 10 uden spor H.

### Task 8: Modellér våben, afbildninger og generelle beskrivelser

**Spor H — udskydeligt:** Task 8–9 er ikke en forudsætning for extraction-, identitets- eller bogpiloternes GO-gater.

**Files:**

- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql
- Create: packages/core/src/entityDescriptions.ts
- Create: packages/core/src/__tests__/entityDescriptions.test.ts
- Modify: packages/core/src/types.ts
- Modify: packages/core/src/index.ts

**Interfaces:**

- Consumes: slaegt- og lineage-ID'er fra Task 6 samt eksisterende coat_of_arms, media, relation, assertion og conclusion.
- Produces: EntityDescription, CoatOfArmsAssociation og publicerbare read-projektioner til Task 9 og den offentlige kildevisning.

- [ ] **Step 1: Skriv fejlede model- og RLS-tests**

Test præcist:

~~~text
En slægt kan have flere historiske våben med periode og provenance.
En lineage kan have sin egen variant uden at kopiere slægtens våben.
Samme coat_of_arms kan forbindes med flere kanoniske entiteter.
Ét coat_of_arms kan have flere media-afbildninger.
Beskrivelse af våbnet og billedtekst til media er forskellige entity_description-rækker.
Ordret kildebeskrivelse, blasonering og redaktionel tekst overskriver ikke hinanden.
Kladder og rettighedsblokerede media er usynlige for anon.
En relation med ukendt subjekt- eller objekttype afvises.
~~~

- [ ] **Step 2: Implementér en generel beskrivelsestabel**

~~~sql
create table entity_description (
  id bigint generated by default as identity primary key,
  subjekt_type text not null,
  subjekt_id bigint not null,
  kind text not null check (
    kind in ('overview','history','caption','blazon_explanation')
  ),
  language_code text not null default 'da',
  tekst text not null,
  status text not null check (status in ('draft','approved','published','archived')),
  privat boolean not null default false,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

create table private.entity_description_source (
  description_id bigint not null references public.entity_description(id) on delete cascade,
  source_record_id uuid not null references private.source_record(id),
  citation_note text,
  primary key (description_id, source_record_id)
);
~~~

Følg projektets versioneringsmønster. En beskrivelse kan have nul, én eller flere source records gennem junction-tabellen i private schema; afhængigheden går fra private til public, aldrig omvendt. Ordret kildetekst forbliver i evidenslaget. Tilføj validering af tilladte subjekt_type-værdier og deres faktiske ID'er, så den polymorfe reference ikke kan pege på ikke-eksisterende slægt, lineage, coat_of_arms, media, person eller estate.

entity_description er redaktionel, stabil entitetsprosa. source_record bevarer kildeprosa, og story bevarer formidlingshistorier. Migrér kun narrative-rækker, som faktisk er redaktionel entitetsprosa, med type og provenance; eksisterende kilde-narrativer afstemmes særskilt i Task 17 og 20. Behold en tidsbegrænset kompatibilitetsprojektion; nye writes må ikke skabe en fjerde konkurrerende tekstsandhed. Tabellen og junction-tabellen får RLS, versionsregistrering og revoke/grant efter projektets mønster. Public read-modeller returnerer kun sikre citationsetiketter, aldrig private UUID'er.

- [ ] **Step 3: Genbrug coat_of_arms, media og relation**

Bevar coat_of_arms som selvstændig entitet. Brug evidensbårne relationer fra slaegt, lineage eller person til coat_of_arms med rollen har_vaaben og kvalifikator for varianttype. Genbrug mediemodellens eksisterende retning fra media til coat_of_arms med rollen afbildet. Periode, konfidens og provenance ligger på relation/assertion, ikke som nye slægtskolonner. Migrér eksisterende coat_of_arms.blasonering til fact/assertion/conclusion og note til den korrekte beskrivelses-/noterolle; behold kun en kompatibilitetsprojektion under overgangen. Tilføj vocab- og valideringstest for de to roller og den kanoniske objekttype coat_of_arms.

- [ ] **Step 4: Implementér core-typer**

~~~typescript
export type EntityDescription = {
  id: string;
  subjectType: "person" | "slaegt" | "lineage" | "coat_of_arms" | "media" | "estate";
  subjectId: string;
  kind: "overview" | "history" | "caption" | "blazon_explanation";
  languageCode: string;
  text: string;
  status: "draft" | "approved" | "published" | "archived";
  citations: Array<{ sourceLabel: string; citationLabel: string }>;
  version: number;
};

export type CoatOfArmsAssociation = {
  subjectType: "slaegt" | "lineage" | "person";
  subjectId: string;
  coatOfArmsId: string;
  variantType: string | null;
  validFrom: string | null;
  validTo: string | null;
};
~~~

- [ ] **Step 5: Kør frisk/migreret DB samt core-tests og commit**

~~~bash
npm test --workspace packages/core -- --run packages/core/src/__tests__/entityDescriptions.test.ts
npm test --workspace packages/core -- --run
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql packages/core/src/entityDescriptions.ts packages/core/src/__tests__/entityDescriptions.test.ts packages/core/src/types.ts packages/core/src/index.ts
git branch --show-current
git commit -m "feat: model entity descriptions and heraldic media"
~~~

### Task 9: Tilføj redaktørflade for beskrivelser og våben

**Files:**

- Modify: web/src/data/redaktionRead.ts
- Modify: web/src/data/redaktionWrite.ts
- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql
- Create: web/src/components/Entitetsbeskrivelser.tsx
- Create: web/src/components/VaabenRedigering.tsx
- Create: web/src/components/EntityDescriptionSection.tsx
- Create: web/src/components/CoatOfArmsGallery.tsx
- Create: web/src/components/__tests__/Entitetsbeskrivelser.test.tsx
- Create: web/src/components/__tests__/VaabenRedigering.test.tsx
- Create: web/src/components/__tests__/EntityDescriptionSection.test.tsx
- Create: web/src/components/__tests__/CoatOfArmsGallery.test.tsx
- Modify: web/src/Redaktion.tsx

**Interfaces:**

- Consumes: EntityDescription og CoatOfArmsAssociation fra Task 8.
- Produces: versionskontrolleret redigering af beskrivelser, våbentilknytninger og billedtekster uden at publicere rå evidens.

- [ ] **Step 1: Skriv UI- og RPC-tests**

Test opret/redigér/arkivér beskrivelse; samtidighedskonflikt; særskilt blasonering og billedtekst; flere våben på samme slægt; variant på lineage; flere media pr. våben; rettighedsgate og private kladder.

- [ ] **Step 2: Implementér read/write-RPC'er**

~~~text
red_entity_descriptions(subject_type, subject_id) -- editor-only, sikre labels plus private links efter rollecheck
red_upsert_entity_description(id, expected_version, subject_type, subject_id, kind, language_code, text, status, source_record_ids, private)
red_coat_of_arms_associations(subject_type, subject_id)
red_link_coat_of_arms(subject_type, subject_id, coat_of_arms_id, variant_type, valid_from, valid_to, evidence_note)
red_link_coat_of_arms_media(coat_of_arms_id, media_id)
~~~

Alle mutationer rollechecks, versionskontrolleres og auditeres. Editor-RPC'en må kun returnere private source_record-ID'er efter eksplicit redaktørrollecheck. En separat public read-RPC returnerer kun published beskrivelser, sikre citationsetiketter og media, som også består mediarettighedsgaten; dens kontrakt må ikke indeholde private UUID'er.

- [ ] **Step 3: Implementér komponenterne**

Redaktøren vælger først entitet: slægt, lineage, våben eller media. UI gør det tydeligt, om teksten beskriver selve våbnet eller den konkrete afbildning. Tilknytning til en lineage viser altid slægtskontekst.

- [ ] **Step 4: Implementér offentlig visning**

EntityDescriptionSection viser kun published descriptions og markerer sprog/kind uden at eksponere private source_record-ID'er. CoatOfArmsGallery grupperer godkendte våben pr. slægt eller lineage, viser kun media der består rettighedsgaten, og holder våbenbeskrivelse og billedtekst adskilt.

- [ ] **Step 5: Kør webtests og commit**

~~~bash
npm test --workspace web -- --run web/src/components/__tests__/Entitetsbeskrivelser.test.tsx web/src/components/__tests__/VaabenRedigering.test.tsx web/src/components/__tests__/EntityDescriptionSection.test.tsx web/src/components/__tests__/CoatOfArmsGallery.test.tsx
npm test --workspace web -- --run
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql web/src/data/redaktionRead.ts web/src/data/redaktionWrite.ts web/src/components/Entitetsbeskrivelser.tsx web/src/components/VaabenRedigering.tsx web/src/components/EntityDescriptionSection.tsx web/src/components/CoatOfArmsGallery.tsx web/src/components/__tests__/Entitetsbeskrivelser.test.tsx web/src/components/__tests__/VaabenRedigering.test.tsx web/src/components/__tests__/EntityDescriptionSection.test.tsx web/src/components/__tests__/CoatOfArmsGallery.test.tsx web/src/Redaktion.tsx
git branch --show-current
git commit -m "feat: edit descriptions and heraldic associations"
~~~

**Spor H-gate:** Heraldik og entity descriptions kan publiceres uden private source_record-ID'er, og tekstrollerne er adskilt.

---

## Fase 4: Kildepersonaer og identitetsafklaring

### Task 10: Byg fail-closed identitetskandidater

**Files:**

- Create: .claude/skills/daa-extract/scripts/source_persona.py
- Create: .claude/skills/daa-extract/scripts/test_source_persona.py
- Modify: .claude/skills/daa-extract/scripts/identitetsregister.py

- [ ] **Step 1: Skriv adversarial tests**

Test tre mentions til én persona uden automatisk kanonisk merge; ens navn uden positivt anker; ægtefælle-/datoanker; global injectivitet; modstridende personnumre; flere personaer fra én record; og bevarelse af manuelle beslutninger ved genudtræk.

- [ ] **Step 2: Implementér kandidatobjekt**

~~~python
@dataclass(frozen=True)
class IdentityCandidate:
    source_persona_id: str
    canonical_person_id: str
    evidence_ids: tuple[str, ...]
    contradictions: tuple[str, ...]
    score_components: Mapping[str, float]
    proposed_action: Literal["same", "different", "unresolved"]
~~~

Score rangerer kun. Automatisk accept kræver eksplicit versionsstyret policy med positive ankre og nul modstrid; ellers unresolved.

- [ ] **Step 3: Bevar stabile identitetsnøgler**

record_key og eksterne personnumre er evidens. (linje, nr) er kun lokator. Genudtræk remapper tidligere afgørelser via provenance, aldrig navn alene.

- [ ] **Step 4: Test og commit**

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_source_persona.py .claude/skills/daa-extract/scripts/test_identitetsregister.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/scripts/source_persona.py .claude/skills/daa-extract/scripts/test_source_persona.py .claude/skills/daa-extract/scripts/identitetsregister.py
git branch --show-current
git commit -m "feat: propose fail-closed source persona identities"
~~~

### Task 11: Tilføj privat redaktørkø

**Files:**

- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql
- Modify: web/src/data/redaktionRead.ts
- Modify: web/src/data/redaktionWrite.ts
- Create: web/src/components/KildepersonaKo.tsx
- Create: web/src/components/__tests__/KildepersonaKo.test.tsx
- Modify: web/src/Redaktion.tsx

- [ ] **Step 1: Skriv RPC- og UI-tests**

Test køfiltre, pagination, evidensvisning, samme/forskellig/uafklaret, versionskonflikt og at afgørelse kræver synligt kildegrundlag.

- [ ] **Step 2: Implementér redaktørbeskyttede read-RPC'er**

~~~text
red_source_persona_queue(status, source_id, cursor, page_size)
red_source_persona_detail(source_persona_id)
red_source_persona_history(source_persona_id)
~~~

Detail returnerer tekstversioner, spans, relationelle ankre, modstrid og historik.

- [ ] **Step 3: Implementér atomisk write-RPC**

~~~text
red_afgoer_source_persona(source_persona_id, expected_version, action, canonical_person_id, note)
~~~

canonical_person_id kræves ved same og er forbudt ved different/unresolved.

- [ ] **Step 4: Implementér webkøen**

Vis kildeomtaler og kanonisk kandidat side om side. Forskellige narrative tekster forbliver separate. En redaktør kan efter import bekræfte, at den tre gange omtalte ægtemand er samme person.

- [ ] **Step 5: Test og commit**

~~~bash
npm test --workspace web -- --run web/src/components/__tests__/KildepersonaKo.test.tsx
npm test --workspace web -- --run
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql web/src
git branch --show-current
git commit -m "feat: add private source persona review queue"
~~~

**Stopport 4:** Menneskelig test på fixture beviser én kanonisk person med flere selvstændige kildeforekomster. Den kritiske vej kan fortsætte uden spor M.

### Task 12: Tilføj mobil redaktørparitet

**Spor M — udskydeligt:** Mobilparitet blokerer ikke extraction- eller identitets-GO'er. Webredaktøren er den første menneskelige reviewflade; Task 12 får sin egen publiceringsgate.

**Files:**

- Modify: mobile/src/data/redaktionRead.ts
- Modify: mobile/src/data/redaktionWrite.ts
- Modify: mobile/src/data/__tests__/redaktionRead.test.ts
- Modify: mobile/src/data/__tests__/redaktionWrite.test.ts
- Create: mobile/src/app/redaktion/kildepersonaer.tsx
- Create: mobile/src/components/redaktion/KildepersonaKo.tsx
- Create: mobile/src/components/redaktion/Entitetsbeskrivelser.tsx
- Create: mobile/src/components/redaktion/VaabenRedigering.tsx
- Create: mobile/src/components/redaktion/__tests__/KildepersonaKo.test.tsx
- Create: mobile/src/components/redaktion/__tests__/Entitetsbeskrivelser.test.tsx
- Create: mobile/src/components/redaktion/__tests__/VaabenRedigering.test.tsx
- Modify: mobile/src/app/redaktion/entitet/slaegt.tsx
- Modify: mobile/src/app/redaktion/entitet/slaegt-narrativ.tsx
- Modify: mobile/src/app/redaktion/entitet/[type].tsx
- Modify: mobile/src/app/redaktion/entitet/materiale.tsx

- [ ] **Step 1: Skriv data- og komponenttests**

Test samme persona-actions og expected_version som web; slægts-/lineage-kontekst; beskrivelseskind og source links; våbenvariant; særskilt våbenbeskrivelse/billedtekst; mediarettigheder og privat kladde. Opret ikke en parallel identitetsalgoritme i klienten.

- [ ] **Step 2: Implementér mobilvisningerne**

Mobil bruger de samme RPC'er, versionering, EntityDescription-typer og persona-handlinger som web. Smal skærm må stable tekster, men ikke skjule provenance, modstrid, tekstrolle eller rettighedsstatus før afgørelse.

- [ ] **Step 3: Kør scripts fra mobile/package.json og commit**

~~~bash
npm test --workspace mobile -- --runInBand
git diff --check
git branch --show-current
git add mobile
git branch --show-current
git commit -m "feat: add mobile evidence and heraldry editor parity"
~~~

**Spor M-gate:** Mobilklienten har samme privatlivs-, versions- og afgørelseskontrakt som webredaktøren.

---

## Fase 5: Granulær udtrækning og kanonisk projektion

### Task 13: Implementér versionsstyret, resumérbar extraction

**Files:**

- Create: .claude/skills/daa-extract/scripts/evidence_extract.py
- Create: .claude/skills/daa-extract/scripts/test_evidence_extract.py
- Create: .claude/skills/daa-extract/references/extraction-profiles.json

- [ ] **Step 1: Skriv granularitetstests**

Test navnedele/varianter; fødsel, dåb, død og begravelse separat; ægteskaber; forældre/børn; titel, tiltaleform, rang og embede separat; uddannelse, ejendom, bopæl, militærtjeneste, hæder og publikation; usikkerhed, negation og ukendt; indgiftedes oplysninger; samt modstridende påstande uden overskrivning.

Test også ikke-personlige poster: slægts- og linjeindledninger, slægtledsoverskrifter, våbenbeskrivelser, blasoneringer, billedtekster og henvisninger fra en våbenafbilledning til slægt eller gren. De skal bruge samme observation/interpretation-kontrakt og må ikke skabe kunstige personer.

- [ ] **Step 2: Implementér editionsprofiler**

Profiler for 1939 og 2018–20 deler outputkontrakt. De beskriver layout/genkendelse, men opfinder ikke kildeårsspecifikke felter i genealogisk model. Hver versioneret profil fastlåser eksplicit `model_id`, `prompt_version` og `escalation_model_id`; første profil bruger `gpt-5.6-terra` som standard og `gpt-5.6-sol` kun til markerede undtagelser. En profilændring kræver en ny version og menneskelig GO.

- [ ] **Step 3: Implementér resumérbare batches**

Hver batch har inputhash, profilversion, extractorversion, det effektive model-ID, promptversion, record-ID'er, outputhash, token-/omkostningsregnskab og valideringsstatus. `evidence_extract.py` kræver en eksplicit profil og må hverken læse et ambient modelvalg eller falde tilbage til en global settings-default. Identiske grønne batches kan genbruges. Delvist output merges aldrig. Kun records, som en dokumenteret gate markerer, må køre én gang på eskalationsmodellen.

- [ ] **Step 4: Implementér fail-closed validering**

Afvis eksplicitte påstande uden span, tekst som ikke kan genfindes, mentions uden for tekst, ukendte typer, persona uden record, ufuldstændig batch samt manglende, ukendt eller profildrivet model-/prompt-ID. Test, at ændret ambient settings ikke kan ændre den effektive model.

- [ ] **Step 5: Test og commit**

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_extract.py -q
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/scripts/evidence_extract.py .claude/skills/daa-extract/scripts/test_evidence_extract.py .claude/skills/daa-extract/references/extraction-profiles.json
git branch --show-current
git commit -m "feat: add resumable granular evidence extraction"
~~~

### Task 14: Byg ny projektionsloader ved siden af den gamle

**Files:**

- Create: .claude/skills/daa-extract/scripts/project_evidence.R
- Create: .claude/skills/daa-extract/scripts/project_evidence_helpers.R
- Create: .claude/skills/daa-extract/scripts/test_project_evidence.R
- Create: tests/testthat/test-project-evidence.R
- Inspect initially: .claude/skills/daa-extract/scripts/load_daa.R
- Inspect initially: .claude/skills/daa-extract/scripts/load_helpers.R
- Modify: .github/workflows/ci.yml

- [ ] **Step 1: Skriv transaktionelle tests**

Test accepteret observation én gang; uafklaret persona uden kanonisk oprettelse; tre records til én person og tre versioner; flere lineages uden personkopi; indgiftet uden medlemskab; bevaret manuel afgørelse; fuld rollback; zero-match og mixed match/new; og positiv kildeprovenance.

Test desuden, at mand og niece beholder hver sin source placement efter projektion; spouse relationen ændrer ingen generation; og ikke-personlige fortolkninger bevares uden at skabe kunstige personer. Hvis spor H er implementeret, kører en særskilt integrationstest, hvor en accepteret våbenpåstand kan forbinde coat_of_arms med slægt/lineage, mens en kildebeskrivelse ikke bliver redaktionel entity_description uden særskilt promotion. Hvis spor H er udskudt, parkeres disse promotions typebevarende i evidenslaget og blokerer ikke kerneprojektionen.

- [ ] **Step 2: Implementér loaderen**

Loaderen indlæser valideret run i privat lag, genbruger stabile persona-ID'er, anvender accepterede identiteter, projicerer kun accepterede promotions, skriver provenance og afviser kildeløse familiemedlemmer. Hver godkendt batch er transaktionel.

- [ ] **Step 3: Bevar gammel loader urørt**

load_daa.R ændres ikke i denne task. Kør den nye vej i separat database og sammenlign, før gammel vej eventuelt udfases.

- [ ] **Step 4: Kør tests i dedikeret lokal database og commit**

Lad `tests/testthat/test-project-evidence.R` være den tynde testthat-wrapper, som sourcer projektions-testen, så det eksisterende `run-tests.R` faktisk kører den. Tilføj nødvendige testafhængigheder til CI og en job-/service-kontrakt for den dedikerede Postgres-testdatabase; en fil, som kun kan køres manuelt, tæller ikke som CI-integration.

~~~bash
Rscript run-tests.R
git diff --check
git branch --show-current
git add .github/workflows/ci.yml tests/testthat/test-project-evidence.R .claude/skills/daa-extract/scripts/project_evidence.R .claude/skills/daa-extract/scripts/project_evidence_helpers.R .claude/skills/daa-extract/scripts/test_project_evidence.R
git branch --show-current
git commit -m "feat: project accepted evidence into canonical genealogy"
~~~

**Stopport 5:** Syntetisk end-to-end beviser én person/flere records, flere lineages uden dublet, separat kildeprosa og private kandidater.

---

## Fase 6: Kildeudgaver i offentlig visning

### Task 15: Vis hver publiceret kilderecord separat

**Files:**

- Modify: schema.sql
- Modify: db-migrations.sql
- Modify: db-rls.sql
- Modify: db-verify.sql
- Modify: packages/core/src/bioVersions.ts
- Modify: packages/core/src/types.ts
- Modify: relevante core-tests
- Modify: relevante webkomponenter for biografi/kildeversioner
- Modify: tilsvarende mobile komponenter

- [ ] **Step 1: Skriv regressions- og privatlivstests**

Tre records fra samme bog vises separat; 1939 og 2018–20 kan modsige hinanden; kanonisk resumé er separat; kun publicerede tekster vises; candidate scores, noter og afviste identiteter returneres aldrig offentligt. Tilføj også en legacy-narrativ uden source_record: den skal fortsat være synlig gennem den navngivne kompatibilitetsadapter og må hverken få et opdigtet record-ID eller forsvinde.

- [ ] **Step 2: Modellér record-versioner**

~~~typescript
export type BioSourceVersion = {
  sourceId: string;
  recordRef: string | null;
  sourceLabel: string;
  recordLabel: string;
  narrativeText: string;
  citationLabel: string;
  provenanceKind: "source_record" | "legacy_narrative";
  publicationStatus: "published";
};
~~~

Visuel gruppering efter bog er tilladt, men hver record forbliver selvstændig. recordRef er en publiceringsgodkendt, uigennemsigtig reference fra read-projektionen, aldrig private.source_record.id. `recordRef=null` er kun tilladt for `legacy_narrative`; adapteren er feature-flagget og fjernes først ved den samlede narrative-afstemningsgate.

- [ ] **Step 3: Implementér web og mobil**

Standardvisningen viser kanonisk biografi. Kildens versioner giver valg af bog og forekomst. En SECURITY DEFINER read-RPC med fast search_path projicerer kun publiceringsgodkendte records til sikre recordRef/citationsetiketter; den returnerer aldrig private UUID'er. Linjeetiketter kvalificeres med slægt og scheme. Indtil Task 17/20 har afstemt legacy narrative, må UI'et ikke love fuld source_record-dækning, og legacy-tekster mærkes som overgangsdata frem for at blive skjult.

- [ ] **Step 4: Kør tests og commit**

~~~bash
npm test --workspace packages/core -- --run
npm test --workspace web -- --run
git diff --check
git branch --show-current
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql packages/core web mobile
git branch --show-current
git commit -m "feat: preserve distinct public source narratives"
~~~

**Stopport 6:** Offentlig API/UI viser kun godkendt materiale; rå OCR og redaktørdata forbliver private.

---

## Fase 7: 2018–20 som pilot og første fulde import

### Task 16: Kør stratificeret pilot uden produktionsmutation

**Files:**

- Create: docs/superpowers/reviews/2018-evidence-pilot.md
- Generated and ignored: pilotmanifest, batchoutput og reviewark i privat arbejdsmappe

- [ ] **Step 1: Fastlæg pilotudvalg før kørsel**

Udvælg deterministisk mindst 30 personrecords: simple personer, lange biografier, flere ægteskaber, indgiftede, flere lineages, titler/embeder, usikre datoer, levende personer og — hvis korpus indeholder det — ægteskab mellem medlemmer fra forskellige slægtled. Tilføj mindst 10 strukturelle/non-person records med linjeindledning, slægtledsoverskrift, slægtsbeskrivelse, våbenbeskrivelse eller billedtekst. Repo-notatet indeholder kun record keys og aggregater, ikke persontekst.

- [ ] **Step 2: Kontrollér databeskyttelse**

Hvis ekstern model skal behandle levende personers tekst, stop og indhent særskilt godkendelse af databehandler, retention og destination. Ellers brug lokal behandling eller ikke-følsomt udvalg.

- [ ] **Step 3: Kør extraction privat**

Brug frosset profil, inputhash og batchmanifest. Intet output går til produktion eller commit.

- [ ] **Step 4: Gennemfør dobbelt review**

Mål record-/klausuldækning, præcision/recall pr. type, exact-span-rate, ubegrundede normaliseringer, record continuity ved ny rendition, persona split/merge-fejl, uafklarede identiteter, record/persona placement-roller, slægtledslabels, indgiftedes dækning, titel/embede, våben/beskrivelsesklassifikation og token-/tidsforbrug. Kritiske identitets- eller genankringsfejl accepteres ikke.

- [ ] **Step 5: Projicér i parallel database**

Sammenlign med eksisterende database pr. record: bevarede/nye fakta, modstrid, relationer, memberships, narrativer og identiteter. Gammel database har ikke automatisk forrang.

- [ ] **Step 6: Commit kun aggregeret rapport**

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/2018-evidence-pilot.md
git branch --show-current
git commit -m "docs: report 2018 evidence pilot"
~~~

**Menneskelig GO 2018-A:** Godkend profil, kvalitetsgrænser og omkostning før fuld udtrækning.

### Task 17: Kør fuld 2018–20-udtrækning og review

**Files:**

- Generated and ignored: fuldt manifest og batches
- Generated and ignored: narrative-crosswalk-2018.json
- Create: docs/superpowers/reviews/2018-evidence-full-run.md

- [ ] **Step 1:** Kør alle batches resumérbart; kun fuldt grønne batches tæller.
- [ ] **Step 2:** Review alle fail-closed køer; tvivl forbliver uafklaret.
- [ ] **Step 3:** Migrér 2018–20 slaegtled_lokal, slaegtled_gennem og kuld til source_record_placement, men kun hvor accepteret record/persona-kontinuitet og en konkret header-observation giver positiv provenance. Hver legacy-række får dispositionen mapped, retained_legacy eller unresolved; opfind aldrig observationer.
- [ ] **Step 4:** Afstem hver eksisterende 2018–20 narrative-række mod accepterede source records med positiv source/persona-evidens. Tekstlig lighed alene er ikke et anker. Ledgeren registrerer præcis én disposition pr. legacy-række: mapped, retained_legacy, archived_by_editor eller unresolved; flere kandidater går til review.
- [ ] **Step 5:** Projicér i parallel database og kontrollér injectivitet, familiegraf, provenance, memberships, efternavn, placements, kildeversioner, narrative-ledger og privatliv.
- [ ] **Step 6:** Rapportér eksakte records, observationer, personaer, sikre match, nye personer, uafklarede, afviste, konflikter, placement-/narrative-dispositioner og valideringsfejl.
- [ ] **Step 7:** Commit kun rapporten.

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/2018-evidence-full-run.md
git branch --show-current
git commit -m "docs: report full 2018 evidence extraction"
~~~

**Menneskelig GO 2018-B:** Godkend parallel database som kandidat, ikke som produktions-cutover.

---

## Fase 8: 1939 OCR, pilot og fuld import

### Task 18: Afgør om 1939 kræver nyt PDF-udtræk

**Files:**

- Create: docs/superpowers/reviews/1939-text-quality-decision.md
- Inspect only: råtekst, sidebilleder, OCR-metadata og segmenteringsrapporter

- [ ] **Step 1: Udtag stratificeret sideprøve**

Medtag tæt sats, spalter, sideskift, oversigter, unummererede grundlæggere, ægteskaber, fodnoter og kendte dårlige OCR-sider.

- [ ] **Step 2: Sammenlign råtekst og sidebillede**

Mål tegnfejl, tabte linjer, forkert læserækkefølge, sammenklistrede felter, sideskift og navne-/nummerfejl. Ændr ikke eksisterende råtekst.

- [ ] **Step 3: Vælg dokumenteret vej**

Vælg eksisterende råtekst som frosset rendition, gen-OCR af udpegede sider som ny rendition eller fuld gen-OCR som ny rendition. Slet aldrig gammel rendition.

- [ ] **Step 4: Commit beslutningen**

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/1939-text-quality-decision.md
git branch --show-current
git commit -m "docs: decide 1939 text extraction quality"
~~~

### Task 19: Kør 1939-pilot med fælles kontrakt

**Files:**

- Create: docs/superpowers/reviews/1939-evidence-pilot.md
- Generated and ignored: pilotmanifest og batches

- [ ] **Step 1:** Frys PDF-/råteksthash, OCR-version, profil og sider; normalisering ændrer ikke verbatim.
- [ ] **Step 2:** Kør stratificeret udvalg med vanskelige strukturer, personnumre, dubletter, flere narrativer, slægtledsoverskrifter samt forekommende slægts-/våbenbeskrivelser.
- [ ] **Step 3:** Sammenlign med 2018 og identitetsregister; de er kandidatankre, ikke facit.
- [ ] **Step 4:** Auditér med 2018-mål plus OCR-fejl, segmenteringsdækning, record continuity, tabte personer, personnumre og korrekt placering af hovedperson kontra omtalt ægtefælle.
- [ ] **Step 5:** Commit kun rapporten.

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/1939-evidence-pilot.md
git branch --show-current
git commit -m "docs: report 1939 evidence pilot"
~~~

**Menneskelig GO 1939-A:** Godkend rendition, profil, kvalitet og omkostning før fuld udtrækning.

### Task 20: Kør fuld 1939-udtrækning og tværudgave-review

**Files:**

- Generated and ignored: fuldt 1939-manifest og batches
- Generated and ignored: narrative-crosswalk-1939.json
- Create: docs/superpowers/reviews/1939-evidence-full-run.md

- [ ] **Step 1:** Afstem recordregnskabet; forklar hver tilføjet, splittet, samlet eller parkeret record med record_key.
- [ ] **Step 2:** Review samme person flere gange, tværudgave-match, grundlægger/barn og indgiftede med flere ægteskaber.
- [ ] **Step 3:** Migrér 1939-slægtledsfelterne efter samme positive record/header-observationsgate som i Task 17; tvivl forbliver legacy og går til review.
- [ ] **Step 4:** Afstem hver eksisterende 1939 narrative-række som i Task 17. Positiv source/persona-evidens er påkrævet; tvivl bliver retained_legacy eller unresolved og aldrig et gættet source_record-link.
- [ ] **Step 5:** Projicér parallelt; bevar hver bogs og records narrativ, legacy-kompatibilitetsrækker og flere påstande pr. faktum.
- [ ] **Step 6:** Dokumentér eksakte resultater, herunder dispositionen for alle legacy-placements og -narrativer, og commit rapporten.

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/1939-evidence-full-run.md
git branch --show-current
git commit -m "docs: report full 1939 evidence extraction"
~~~

**Menneskelig GO 1939-B:** Godkend samlet parallel database som cutover-kandidat, ikke produktions-cutover.

---

## Fase 9: Cutover-rehearsal og særskilt produktionsbeslutning

### Task 21: Rehearsér genopbygning og rollback

**Files:**

- Create: docs/runbooks/evidence-import-cutover.md
- Create: docs/superpowers/reviews/evidence-import-cutover-rehearsal.md
- Modify only if tests demand it: db-verify.sql

- [ ] **Step 1: Tag og verificér backup**

Test restore i separat lokal database. Backup er først gyldig efter restore og centrale række-/hashkontroller.

- [ ] **Step 2: Kør cutover fra nul i isoleret kopi**

Runbook har konkrete kommandoer og checkpoints for schema, evidensimport, identiteter, promotion, projektion, RLS, offentlig smoke test og rollback.

- [ ] **Step 3: Sammenlign gammel og ny database**

Rapportér personer/dubletter, familiegraf, slægter/lineages/schemes/memberships, provenance, kildeversioner, uafklarede poster og privat lækagekontrol. Afstem desuden alle eksisterende narrative-rækker pr. kilde: hver række skal være mappet til accepteret source record, eksplicit retained_legacy, redaktionelt arkiveret eller unresolved. Kontroller rækkeantal og teksthash før/efter; nul stille tab.

Krav: nul kendte forkerte identitetsmatch, nul kildeløse nye familiemedlemmer, nul offentlige kandidater, nul uforklarede legacy-placements, nul uforklarede narrative-rækker og forklaring på alle materielle differencer. Kompatibilitetsadapteren må først fjernes, når alle narrative-rækker har en godkendt slutdisposition.

- [ ] **Step 4: Test rollback**

Gendan backup i ny database, kør db-verify.sql, og bekræft at gammel applikationsversion kan læse den.

- [ ] **Step 5: Commit runbook og rapport**

~~~bash
git diff --check
git branch --show-current
git add docs/runbooks/evidence-import-cutover.md docs/superpowers/reviews/evidence-import-cutover-rehearsal.md db-verify.sql
git branch --show-current
git commit -m "docs: rehearse evidence import cutover"
~~~

### Task 22: Fremlæg særskilt GO/NO-GO-pakke

**Files:**

- Create: docs/superpowers/reviews/evidence-import-go-no-go.md

- [ ] **Step 1:** Saml commit-SHA'er, tests, baselinefejl, datakvalitet, uafklarede identiteter, sikkerhed, restorebevis, ydelse, omkostning og risici uden cutover.
- [ ] **Step 2:** Afslut entydigt med GO eller NO-GO. GO tillader kun planlægning af en særskilt godkendt produktionsændring.
- [ ] **Step 3:** Kør endelig verifikation og commit.

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
Rscript run-tests.R
npm test --workspace packages/core -- --run
npm test --workspace web -- --run
npm test --workspace mobile -- --runInBand
git diff --check
git status --short
git branch --show-current
git add docs/superpowers/reviews/evidence-import-go-no-go.md
git branch --show-current
git commit -m "docs: assess evidence import production readiness"
git status --short
~~~

**Endelig stopport:** Produktions-cutover er en ny destruktiv opgave, som kræver brugerens udtrykkelige tilladelse.

---

## Definition of done

Programmet er først færdigt, når:

- Råtekst og afledte tekstversioner har stabil, reproducerbar provenance.
- Observation, fortolkning, identitetsafgørelse og kanonisk promotion er adskilte trin.
- Udtrækningen er granulær nok til nye formål uden nyt PDF-udtræk, medmindre OCR-renditionen senere forbedres.
- Samme person kan optræde i flere records, bøger, lineages og roller uden persondublet.
- Logiske source records overlever nye renditions gennem occurrences og eksplicitte revision-events; split og merge bliver aldrig tavst genankret.
- Forskellige kilders narrative tekster bevares og vises separat; alle legacy-narrativer har en eksplicit, tabsfri disposition.
- Slægt, kanonisk lineage og kildens nummereringsscheme er adskilt.
- Trykt slægtled, lokalt slægtled, gennemgående slægtled og beregnet genealogisk afstand er adskilte; spouse edges påvirker ingen af dem.
- Linjeetiketter er scoped til slægt og scheme; II er aldrig global identitet.
- Efternavn afledes kun af eksplicit slægtsmedlemskab og kontekst, ikke ægteskab.
- Flere slægter kan indlæses uden slægtsspecifikke felter eller kodegrene.
- Alle importerede kanoniske fakta og relationer har positiv provenance.
- Uafklarede identiteter forbliver redaktionelle opgaver.
- Privat evidenslag og redaktørkø er utilgængelige offentligt.
- Append-only anchor- og revision-events kan genforeslås efter afvisning uden historikmutation.
- Slægter, lineages og personer kan knyttes evidensbåret til våben; våben kan have flere media-afbildninger med egne beskrivelser og rettigheder.
- Kildebeskrivelse, blasonering, redaktionel beskrivelse og billedtekst bevares som forskellige tekstroller.
- 2018–20 og 1939 har hver bestået pilot, fuld validering og parallel projektion.
- Backup, restore, rehearsal og rollback er afprøvet før produktionsbeslutning.

## Afgrænsning

Planen giver ikke i sig selv tilladelse til at:

- slette eller erstatte eksisterende data;
- køre fuld extraction af nogen bog;
- sende persontekst til ekstern model;
- publicere rå OCR, kandidater eller redaktørnoter;
- udføre produktions-cutover;
- ændre redaktionelle match uden menneskelig afgørelse.
