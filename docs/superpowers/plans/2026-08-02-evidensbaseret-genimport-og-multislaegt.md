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
- Kandidater, OCR og redaktionelle beslutninger er private og må ikke kunne læses af anon eller almindelige authenticated-brugere.
- Commit kun syntetiske fixtures. Faktiske arbejdsartefakter, PDF-udtræk og potentielle persondata skal ligge i ignorerede arbejdsmapper.
- Hold 1939- og 2018–20-profiler adskilt. Genkendelsesændringer må ikke ændre no-flag/default-adfærd uden regressionstest og godkendelse.
- Afslut hver fase med fokuserede tests, relevante fulde testpakker, diff-kontrol og små commits. Rapportér kendte baselinefejl særskilt.
- Fuld bogkørsel, ekstern modelbehandling af levende personer og produktions-cutover kræver hver sin udtrykkelige menneskelige GO-beslutning.

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
- Create: .claude/skills/daa-extract/scripts/evidence_contract.py
- Create: .claude/skills/daa-extract/scripts/test_evidence_contract.py
- Create: .claude/skills/daa-extract/scripts/tests/fixtures/evidence-observation.synthetic.json

- [ ] **Step 1: Skriv kontrakttests, som først fejler**

Test præcist:

~~~python
def test_observation_requires_exact_source_span(): ...
def test_normalized_text_cannot_replace_verbatim_text(): ...
def test_mention_offsets_must_be_inside_observation(): ...
def test_source_persona_is_scoped_to_one_rendition(): ...
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
    char_from: int
    char_to: int

@dataclass(frozen=True)
class Observation:
    observation_id: str
    record_key: str
    kind: str
    verbatim_text: str
    span: SourceSpan
    extraction_method: str
    extraction_run_id: str
~~~

Validatoren afviser ukendte felter, tom verbatim_text, negative eller omvendte spans, dublerede ID'er og fortolkninger uden kendte observationer.

- [ ] **Step 3: Definér JSON Schema**

Observationsskemaet kræver schema_version, source_rendition, source_records, observations, text_variants, mentions, source_personas og extraction_run. Fortolkningsskemaet kræver interpretation_id, observation_ids, predicate, typed value, status, method og created_at.

Ingen kontrakt må gøre en kildepersona direkte til kanonisk person uden særskilt identitetsafgørelse.

- [ ] **Step 4: Tilføj syntetisk svær fixture**

Fixture omfatter samme mand omtalt tre gange med forskellig prosa; barn i én linje og grundlægger i en anden; indgiftet uden afledt slægtsnavn; titel og embede; usikker, ukendt og manglende dato; samt modstridende kilder.

- [ ] **Step 5: Test og commit**

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_contract.py -q
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/references .claude/skills/daa-extract/scripts/evidence_contract.py .claude/skills/daa-extract/scripts/test_evidence_contract.py .claude/skills/daa-extract/scripts/tests/fixtures/evidence-observation.synthetic.json
git branch --show-current
git commit -m "feat: define evidence extraction contracts"
~~~

### Task 3: Indfør klausul-ledger og deterministiske record-grænser

**Files:**

- Create: .claude/skills/daa-extract/scripts/clause_ledger.py
- Create: .claude/skills/daa-extract/scripts/test_clause_ledger.py
- Modify: .claude/skills/daa-extract/scripts/segment.py
- Modify: .claude/skills/daa-extract/scripts/validate.py

- [ ] **Step 1: Skriv regressionstests**

Test fuld tegnregnskab, nul eller flere observationer pr. klausul, record_key uafhængig af linjenummer, uændret default-output og editionsisolation.

- [ ] **Step 2: Implementér ledger som sidecar**

Tilføj et eksplicit flag --emit-evidence-ledger. Uden flag skal output være identisk med baseline. Hver ledger-række indeholder record_key, clause-ID, span, klassifikation og observations-ID'er.

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

Tilføj assertions for tabeller, fremmednøgler, unikheder, immutabilitet og rettigheder før DDL.

- [ ] **Step 2: Tilføj private tabeller**

Implementér private.extraction_run, source_rendition, source_record, source_observation, source_observation_text, source_mention, source_persona og source_persona_mention. Junction-tabellen skal bevare mentionens rolle og rækkefølge i personaen.

Kerne-DDL følger dette mønster:

~~~sql
create table private.source_rendition (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references source(id),
  rendition_kind text not null,
  content_sha256 text not null,
  metadata jsonb not null default '{}'::jsonb,
  unique (source_id, content_sha256)
);

create table private.source_record (
  id uuid primary key default gen_random_uuid(),
  rendition_id uuid not null references private.source_rendition(id),
  record_key text not null,
  page_from integer not null,
  page_to integer not null,
  verbatim_text text not null,
  extraction_run_id uuid not null references private.extraction_run(id),
  unique (rendition_id, record_key)
);
~~~

Alle afledte entiteter peger tilbage til record, rendition og extraction run. Publicering af en record-narrativ er en særskilt promotion med auditspor; rå recordtekst bliver ikke offentlig alene ved indlæsning.

- [ ] **Step 3: Gør rå evidens append-only**

Blokér UPDATE og DELETE på rendition, record og observation. Korrektion sker med ny extraction run og supersedes_id, aldrig ved overskrivning.

- [ ] **Step 4: Lås laget privat**

~~~sql
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;
~~~

Verificér eksplicit, at anon og almindelig authenticated hverken kan læse eller mutere laget.

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

- [ ] **Step 1: Skriv modeltests**

Bevis: to slægter kan begge have kode II; stamtavle og præsensliste kan nummerere samme lineage forskelligt; en lineage hører til én slægt; en person kan have flere memberships uden kopi; indgiftede arver ikke slægtsnavn; flere slægtsmedlemskaber kræver kontekst eller neutral etikette.

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
~~~

Flyt presens_kode-semantik til lineage_scheme_entry. Unikhed er (scheme_id, code), aldrig global code.

- [ ] **Step 3: Migrér eksisterende data tabsfrit**

Opret Reventlow som slægt, forbind eksisterende lineages og opret schemes for kendte stamtavle-/præsensnummereringer. Migrationen er idempotent og kontrollerer rækkeantal før/efter.

- [ ] **Step 4: Bevar eksplicit kompatibilitetsprojektion**

Hvis klienter stadig læser presens_kode, lever et navngivet overgangs-view/RPC. Undgå dobbelt sandhed i tabellerne.

- [ ] **Step 5: Implementér TypeScript-typer**

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

- [ ] **Step 6: Test frisk DB, migreret DB og core; commit**

~~~bash
npm test --workspace packages/core -- --run packages/core/src/__tests__/slaegter.test.ts
npm test --workspace packages/core -- --run
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

**Stopport 3:** Review bekræfter, at modellen ikke indeholder 1939-linje, kildeår i kanoniske lineages eller globale romertal.

---

## Fase 4: Kildepersonaer og identitetsafklaring

### Task 8: Byg fail-closed identitetskandidater

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

### Task 9: Tilføj privat redaktørkø

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

### Task 10: Tilføj mobil redaktørparitet

**Files:**

- Modify: konkrete redaktionelle read/write-filer under mobile/
- Create: mobil persona-kø og test med samme domænekontrakt som web

- [ ] **Step 1: Find konkrete modstykker**

~~~bash
rg -n "redaktionRead|redaktionWrite|SammenlignUdgaver|MatchOversigt" mobile
~~~

Registrér de præcise filer før ændring. Opret ikke en parallel identitetsalgoritme i klienten.

- [ ] **Step 2: Skriv og implementér paritetstests**

Mobil bruger samme RPC'er, versionering og handlingstyper. Smal skærm må stable tekster, men ikke skjule provenance eller modstrid før afgørelse.

- [ ] **Step 3: Kør scripts fra mobile/package.json og commit**

~~~bash
git diff --check
git branch --show-current
git add mobile
git branch --show-current
git commit -m "feat: add mobile source persona review parity"
~~~

**Stopport 4:** Menneskelig test på fixture beviser én kanonisk person med flere selvstændige kildeforekomster.

---

## Fase 5: Granulær udtrækning og kanonisk projektion

### Task 11: Implementér versionsstyret, resumérbar extraction

**Files:**

- Create: .claude/skills/daa-extract/scripts/evidence_extract.py
- Create: .claude/skills/daa-extract/scripts/test_evidence_extract.py
- Create: .claude/skills/daa-extract/references/extraction-profiles.json

- [ ] **Step 1: Skriv granularitetstests**

Test navnedele/varianter; fødsel, dåb, død og begravelse separat; ægteskaber; forældre/børn; titel, tiltaleform, rang og embede separat; uddannelse, ejendom, bopæl, militærtjeneste, hæder og publikation; usikkerhed, negation og ukendt; indgiftedes oplysninger; samt modstridende påstande uden overskrivning.

- [ ] **Step 2: Implementér editionsprofiler**

Profiler for 1939 og 2018–20 deler outputkontrakt. De beskriver layout/genkendelse, men opfinder ikke kildeårsspecifikke felter i genealogisk model.

- [ ] **Step 3: Implementér resumérbare batches**

Hver batch har inputhash, profilversion, extractorversion, record-ID'er, outputhash og valideringsstatus. Identiske grønne batches kan genbruges. Delvist output merges aldrig.

- [ ] **Step 4: Implementér fail-closed validering**

Afvis eksplicitte påstande uden span, tekst som ikke kan genfindes, mentions uden for tekst, ukendte typer, persona uden record og ufuldstændig batch.

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

### Task 12: Byg ny projektionsloader ved siden af den gamle

**Files:**

- Create: .claude/skills/daa-extract/scripts/project_evidence.R
- Create: .claude/skills/daa-extract/scripts/project_evidence_helpers.R
- Create: .claude/skills/daa-extract/scripts/test_project_evidence.R
- Inspect initially: .claude/skills/daa-extract/scripts/load_daa.R
- Inspect initially: .claude/skills/daa-extract/scripts/load_helpers.R

- [ ] **Step 1: Skriv transaktionelle tests**

Test accepteret observation én gang; uafklaret persona uden kanonisk oprettelse; tre records til én person og tre versioner; flere lineages uden personkopi; indgiftet uden medlemskab; bevaret manuel afgørelse; fuld rollback; zero-match og mixed match/new; og positiv kildeprovenance.

- [ ] **Step 2: Implementér loaderen**

Loaderen indlæser valideret run i privat lag, genbruger stabile persona-ID'er, anvender accepterede identiteter, projicerer kun accepterede promotions, skriver provenance og afviser kildeløse familiemedlemmer. Hver godkendt batch er transaktionel.

- [ ] **Step 3: Bevar gammel loader urørt**

load_daa.R ændres ikke i denne task. Kør den nye vej i separat database og sammenlign, før gammel vej eventuelt udfases.

- [ ] **Step 4: Kør tests i dedikeret lokal database og commit**

~~~bash
git diff --check
git branch --show-current
git add .claude/skills/daa-extract/scripts/project_evidence.R .claude/skills/daa-extract/scripts/project_evidence_helpers.R .claude/skills/daa-extract/scripts/test_project_evidence.R
git branch --show-current
git commit -m "feat: project accepted evidence into canonical genealogy"
~~~

**Stopport 5:** Syntetisk end-to-end beviser én person/flere records, flere lineages uden dublet, separat kildeprosa og private kandidater.

---

## Fase 6: Kildeudgaver i offentlig visning

### Task 13: Vis hver publiceret kilderecord separat

**Files:**

- Modify: packages/core/src/bioVersions.ts
- Modify: packages/core/src/types.ts
- Modify: relevante core-tests
- Modify: relevante webkomponenter for biografi/kildeversioner
- Modify: tilsvarende mobile komponenter

- [ ] **Step 1: Skriv regressions- og privatlivstests**

Tre records fra samme bog vises separat; 1939 og 2018–20 kan modsige hinanden; kanonisk resumé er separat; kun publicerede tekster vises; candidate scores, noter og afviste identiteter returneres aldrig offentligt.

- [ ] **Step 2: Modellér record-versioner**

~~~typescript
export type BioSourceVersion = {
  sourceId: string;
  sourceRecordId: string;
  sourceLabel: string;
  recordLabel: string;
  narrativeText: string;
  citationLabel: string;
  publicationStatus: "published";
};
~~~

Visuel gruppering efter bog er tilladt, men hver record forbliver selvstændig.

- [ ] **Step 3: Implementér web og mobil**

Standardvisningen viser kanonisk biografi. Kildens versioner giver valg af bog og forekomst. Linjeetiketter kvalificeres med slægt og scheme.

- [ ] **Step 4: Kør tests og commit**

~~~bash
npm test --workspace packages/core -- --run
npm test --workspace web -- --run
git diff --check
git branch --show-current
git add packages/core web mobile
git branch --show-current
git commit -m "feat: preserve distinct public source narratives"
~~~

**Stopport 6:** Offentlig API/UI viser kun godkendt materiale; rå OCR og redaktørdata forbliver private.

---

## Fase 7: 2018–20 som pilot og første fulde import

### Task 14: Kør stratificeret pilot uden produktionsmutation

**Files:**

- Create: docs/superpowers/reviews/2018-evidence-pilot.md
- Generated and ignored: pilotmanifest, batchoutput og reviewark i privat arbejdsmappe

- [ ] **Step 1: Fastlæg pilotudvalg før kørsel**

Udvælg deterministisk mindst 30 records: simple personer, lange biografier, flere ægteskaber, indgiftede, flere lineages, titler/embeder, usikre datoer og levende personer. Repo-notatet indeholder kun record keys og aggregater, ikke persontekst.

- [ ] **Step 2: Kontrollér databeskyttelse**

Hvis ekstern model skal behandle levende personers tekst, stop og indhent særskilt godkendelse af databehandler, retention og destination. Ellers brug lokal behandling eller ikke-følsomt udvalg.

- [ ] **Step 3: Kør extraction privat**

Brug frosset profil, inputhash og batchmanifest. Intet output går til produktion eller commit.

- [ ] **Step 4: Gennemfør dobbelt review**

Mål record-/klausuldækning, præcision/recall pr. type, exact-span-rate, ubegrundede normaliseringer, persona split/merge-fejl, uafklarede identiteter, indgiftedes dækning, titel/embede og token-/tidsforbrug. Kritiske identitetsfejl accepteres ikke.

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

### Task 15: Kør fuld 2018–20-udtrækning og review

**Files:**

- Generated and ignored: fuldt manifest og batches
- Create: docs/superpowers/reviews/2018-evidence-full-run.md

- [ ] **Step 1:** Kør alle batches resumérbart; kun fuldt grønne batches tæller.
- [ ] **Step 2:** Review alle fail-closed køer; tvivl forbliver uafklaret.
- [ ] **Step 3:** Projicér i parallel database og kontrollér injectivitet, familiegraf, provenance, memberships, efternavn, kildeversioner og privatliv.
- [ ] **Step 4:** Rapportér eksakte records, observationer, personaer, sikre match, nye personer, uafklarede, afviste, konflikter og valideringsfejl.
- [ ] **Step 5:** Commit kun rapporten.

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

### Task 16: Afgør om 1939 kræver nyt PDF-udtræk

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

### Task 17: Kør 1939-pilot med fælles kontrakt

**Files:**

- Create: docs/superpowers/reviews/1939-evidence-pilot.md
- Generated and ignored: pilotmanifest og batches

- [ ] **Step 1:** Frys PDF-/råteksthash, OCR-version, profil og sider; normalisering ændrer ikke verbatim.
- [ ] **Step 2:** Kør stratificeret udvalg med vanskelige strukturer, personnumre, dubletter og flere narrativer.
- [ ] **Step 3:** Sammenlign med 2018 og identitetsregister; de er kandidatankre, ikke facit.
- [ ] **Step 4:** Auditér med 2018-mål plus OCR-fejl, segmenteringsdækning, tabte personer og personnumre.
- [ ] **Step 5:** Commit kun rapporten.

~~~bash
git diff --check
git branch --show-current
git add docs/superpowers/reviews/1939-evidence-pilot.md
git branch --show-current
git commit -m "docs: report 1939 evidence pilot"
~~~

**Menneskelig GO 1939-A:** Godkend rendition, profil, kvalitet og omkostning før fuld udtrækning.

### Task 18: Kør fuld 1939-udtrækning og tværudgave-review

**Files:**

- Generated and ignored: fuldt 1939-manifest og batches
- Create: docs/superpowers/reviews/1939-evidence-full-run.md

- [ ] **Step 1:** Afstem recordregnskabet; forklar hver tilføjet, splittet, samlet eller parkeret record med record_key.
- [ ] **Step 2:** Review samme person flere gange, tværudgave-match, grundlægger/barn og indgiftede med flere ægteskaber.
- [ ] **Step 3:** Projicér parallelt; bevar hver bogs og records narrativ og flere påstande pr. faktum.
- [ ] **Step 4:** Dokumentér eksakte resultater og commit rapporten.

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

### Task 19: Rehearsér genopbygning og rollback

**Files:**

- Create: docs/runbooks/evidence-import-cutover.md
- Create: docs/superpowers/reviews/evidence-import-cutover-rehearsal.md
- Modify only if tests demand it: db-verify.sql

- [ ] **Step 1: Tag og verificér backup**

Test restore i separat lokal database. Backup er først gyldig efter restore og centrale række-/hashkontroller.

- [ ] **Step 2: Kør cutover fra nul i isoleret kopi**

Runbook har konkrete kommandoer og checkpoints for schema, evidensimport, identiteter, promotion, projektion, RLS, offentlig smoke test og rollback.

- [ ] **Step 3: Sammenlign gammel og ny database**

Rapportér personer/dubletter, familiegraf, slægter/lineages/schemes/memberships, provenance, kildeversioner, uafklarede poster og privat lækagekontrol.

Krav: nul kendte forkerte identitetsmatch, nul kildeløse nye familiemedlemmer, nul offentlige kandidater og forklaring på alle materielle differencer.

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

### Task 20: Fremlæg særskilt GO/NO-GO-pakke

**Files:**

- Create: docs/superpowers/reviews/evidence-import-go-no-go.md

- [ ] **Step 1:** Saml commit-SHA'er, tests, baselinefejl, datakvalitet, uafklarede identiteter, sikkerhed, restorebevis, ydelse, omkostning og risici uden cutover.
- [ ] **Step 2:** Afslut entydigt med GO eller NO-GO. GO tillader kun planlægning af en særskilt godkendt produktionsændring.
- [ ] **Step 3:** Kør endelig verifikation og commit.

~~~bash
/usr/bin/python3 -m pytest .claude/skills/daa-extract/scripts -q
npm test --workspace packages/core -- --run
npm test --workspace web -- --run
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
- Forskellige kilders narrative tekster bevares og vises separat.
- Slægt, kanonisk lineage og kildens nummereringsscheme er adskilt.
- Linjeetiketter er scoped til slægt og scheme; II er aldrig global identitet.
- Efternavn afledes kun af eksplicit slægtsmedlemskab og kontekst, ikke ægteskab.
- Flere slægter kan indlæses uden slægtsspecifikke felter eller kodegrene.
- Alle importerede kanoniske fakta og relationer har positiv provenance.
- Uafklarede identiteter forbliver redaktionelle opgaver.
- Privat evidenslag og redaktørkø er utilgængelige offentligt.
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
