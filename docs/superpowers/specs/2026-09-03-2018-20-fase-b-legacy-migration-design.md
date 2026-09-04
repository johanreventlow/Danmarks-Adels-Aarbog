# 2018-20 fase B (149b): legacy-migration af narrativer til record-binding

**Dato:** 2026-09-03
**Issue:** #166 (149b, udskilt fra #149)
**Status:** Designspec skrevet af PM-rollen (Fable) på grundlag af projektejerens
regler i #166 og 149a-spec §5 (godkendt 2026-09-03). To valg er PM'ens egne og
er ført i `docs/decisions.md` som **»kræver projektejerens kvittering før
prod-GO«**: (A) identitet uden placement-kæde (§5) og (B) reversal-designet (§8).
Ikke implementeret.
**Roadmapmål:** trin 3 i `docs/evidensbaseret-genimport/roadmap.md` (149a → 149b).
**Forudsætning:** 149a (`docs/superpowers/specs/2026-09-03-2018-20-fase-a-provenance-design.md`)
er `integreret ende-til-ende`; inventeringen
`docs/superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md`.

## 1. Adgangskrav (roadmap §»Adgangskrav til nye planer«)

| # | Krav | Svar |
|---|---|---|
| 1 | Roadmapmål | Trin 3: 2018-20 får fase A-ækvivalent provenance. 149b lukker leddet »narrativ ↔ source record« for source 1. |
| 2 | Led i værdikæden | identitet (record ↔ person) → publicering med kildehenvisning. 149a leverede rendition → record → forekomst → anker; 149b binder de 591 eksisterende narrativer til de 591 records og afslutter deres grandfathered legacy-streams. |
| 3 | Generel, profil eller legacy-afvikling | **Generel** mekanik: én ny elementoperation `legacy_migration` i #153's generelle writer, én ny gren i #152's dedikerede reversal, ingen nye tabeller, ingen DB-objekter med `2018` i navnet. Plus **én lille writer-profil** `daa-2018-20-legacy-migration-v1`. Det er samtidig **legacy-afvikling**: `grandfathered_publication` → `migrated` er den exit-betingelse, #152 §4.4 reserverede til #149. |
| 4 | Redaktionel/brugerrettet værdi | Biografierne fra 2018-20 får kildehenvisning (`DAA 2018-20 side N`) og stabil `source_record_ref` i stedet for »Overgangsdata — kildepost ikke fastlagt«. Redaktørfladen kan derefter redigere dem gennem #152's record-kontrakt (revision, tilbagetrækning, revalidering) i stedet for read-only. |
| 5 | Bevis for færdig | Rehearsal mod en restore af prod-dumpet migreret til kontraktversion 2 og med 149a anvendt: eksakte tal pr. disposition (§4) svarende til manifestet; offentlig v2-flade viser hver bundet biografi **præcis én gang** som `source_record` og ingen som `legacy_narrative`; `anon`-hash af de otte tabeller uændret (kun private projektioner + `narrative_record_publication` ændres); replay `already_applied`; per-narrativ reversal gendanner eksakt førtilstand for både record- og legacy-stream. Prod-apply er en separat gate. |
| 6 | Erstatter | Visningen »Overgangsdata« for source 1 (544 rækker i ledgeren efter cutover) og den parallelle 1939-måde at oprette bindinger på (C3's `red_apply_reimport_cases`, deaktiveret ved kontrakt v2). |

## 2. Afgrænsning

**I scope:**
- én generel elementoperation `legacy_migration` i `private.reimport_event`/den
  generelle writer (#153), med autorisation, preview, dry-run, apply, replay og
  finalize gennem de eksisterende RPC'er;
- identitetsledger pr. record: `source_persona` + `source_persona_mention` +
  `source_persona_identity` (`accepted`) med `person_external_id` som evidens;
- afslutning af én grandfathered legacy-stream pr. narrativ (`legacy_migrated`,
  ledger `migrated`) og oprettelse af record-bindingen for **det eksisterende
  narrativ** (samme `narrative.id`, samme tekst) gennem #152's eventkontrakt;
- de fire dispositioner og 10 %-stopgrænsen (§4);
- en `legacy_migrated`-gren i `private.reverse_narrative_publication_event` (§8);
- manifestbygger (Python, kun hashes), preview (R, læse-kun), rehearsal, rapport,
  fase-pakke-bidrag.

**Ikke i scope:** tekstændringer (fase B-ækvivalent for 2018-20 er en separat
beslutning; de 4 `unresolved_text` og de 13 mulige `NOISE_RE`-prosalinjer
rapporteres, rettes ikke), record-/persona-*placements* og `header`-observationer
(#150), én identitetsvej/webkø (#151), strukturelle records, `slaegt`-narrativet
(1 række), #147/#148, personoprettelse, `narrative.side` (§6.5), modelkald.

## 3. Målte forudsætninger (prod-dump `pre-c0f-20260821`, restore `daa149b_inv_20260903`, læse-kun 2026-09-03)

| Måling | Værdi | Konsekvens |
|---|---|---|
| Personer med præcis én `external_id` for source 1 / `record_key` delt af >1 person | 591 / 0 | injektiv begge veje (inventering måling 4) |
| Narrativer pr. person, source 1 | 1 for 591/591 | én binding pr. person |
| `levende` blandt de 591 | `false` 544, `true` 47, `NULL` 0; `privat` 0, `staged` 0 | 544 publicerbare, 47 kladder |
| Cutover-eksportens legacy-prædikat (`levende IS FALSE`, ikke privat/staged, ubundet) | 544 | ledgeren får 544 source-1-rækker ved #152-cutover |
| Byte-lig efter `narrative_norm_v1` (inventering måling 7) | 587 / 4 ulige (`I-133`, `II-35`, `III-129` ikke-levende; `IV-94` levende) | 4 × `unresolved_text` |
| `narrative.side` for source 1 | `NULL` for alle 591 | side kommer fra record-labels, narrativrækken røres ikke |
| `haendelse`-rækker på source-1-narrativer | 0 | ingen afledte events blokerer |
| Record-placements / persona-placements i prod (alle udgaver) | 0 / 0 | placement-kæden er ubrugt i prod; se §5 |
| Accepterede persona-identiteter (source 3) | 8 | 1939's 550 bindinger bærer autoritet `existing_exact_binding` |
| `lineage_scheme` for source 1 | id 1, entries I–V | ikke brugt af 149b (ingen placements) |

## 4. Dispositioner, forventede tal og stopgrænse

Præcis én disposition pr. narrativ; manifestet bærer alle 591 i sin
`dispositions`-liste (kun `record_key`, `narrative_id`, `person_id`, disposition,
hashes), men kun `bound_*` bliver til elementer.

| Disposition | Regel | Forventet (fra §3) |
|---|---|---|
| `bound_published` | identitet entydig begge veje, tekst byte-lig efter norm, narrativ i ledgeren som `grandfathered_publication` med matchende baseline, policy tillader publicering | **541** |
| `bound_draft` | som ovenfor, men personen er `levende`/`staged`/`privat` eller narrativet `privat` → ingen ledger-række, binding `draft` | **46** |
| `unresolved_text` | norm-tekst ulig forekomstens tekst | **4** |
| `unresolved_identity` | brud på injektivitet, 0 eller >1 narrativ, eller narrativ allerede bundet | **0** |

- Stopgrænse: `unresolved_*` > 10 % af 591 (dvs. ≥ 60) stopper fasen før prod.
  Forventet 4/591 = 0,7 %.
- Tallene er afledt af dumpet 2026-08-21. Rehearsal-preview **og** prod-preview
  måler dem igen; enhver afvigelse fra manifestets `expected_counts` er stop,
  ikke justering.
- Inkonsistens = stop, ikke disposition: et narrativ, der er publicerbart men
  mangler i ledgeren, eller er i ledgeren som `withdrawn`/`migrated`, gør hele
  manifestet ugyldigt (`LEGACY_MIGRATION_LEDGER_INCONSISTENT`). Det er drift
  siden cutover og kræver menneskelig afgørelse.

## 5. Identitet: accepteret persona-identitet fra `person_external_id` — uden placement-kæde

**Regel (projektejer, #166 pkt. 2-3):** identiteten record ↔ person indlæses som
accepteret persona-identitet med `person_external_id` som positiv evidens; én
disposition pr. række; tekstlighed er aldrig anker.

**Mekanik pr. element:**
1. `private.extraction_run` for batchen (`run_key_prefix || manifest_sha256`,
   idempotent som i `ensure_reimport_source_evidence`).
2. `private.source_persona(source_id, persona_key = record_key, created_run_id)`.
3. `private.source_persona_mention(persona, mention, 'primary', 1)` hvor `mention`
   er den ene `source_mention`, 149a skrev for recordens forekomst
   (præcis én, ellers `LEGACY_MIGRATION_MENTION_AMBIGUOUS`).
4. `public.red_decide_source_persona_identity(persona, person_id, 0, 'accepted',
   evidence)` med `evidence = {authority: 'person_external_id',
   person_external_id: {person_id, source_id, record_key}, batch_id, element_id,
   profile_sha256, authorized_payload_sha256}` — dét er den egen ledger
   (`source_persona_identity_event` v1).

**Valg A (PM, kræver kvittering før prod-GO): ingen record-/persona-placements.**
#152 §6.1(9) definerer »den entydige identitetsmængde« gennem
`source_record_placement` → `source_persona_placement` → `source_persona_identity`.
Placement kræver en `header`-observation ankret til recorden
(`EVIDENCE_PLACEMENT_HEADER_REQUIRED`); ingen udgave har `header`-observationer,
og prod har 0 placements. Placement er roadmap-trin 5 (#150/#151). At bygge
kæden for 2018-20 alene ville omprioritere roadmappen og give asymmetri med
1939. Konsekvens, som spec'en gør eksplicit:
- Før bindingen rapporterer `narrative_publication_state` autoritet
  `missing_identity` (blocked). Writeren registrerer dét som sandfærdig
  `before_state`; efter bindingen er autoriteten `existing_exact_binding`,
  præcis som 1939's 550 bindinger. Identitetsledgeren findes, men indgår ikke i
  `provenance.identities`, før #150/#151 tilføjer placements.
- Når #150/#151 senere bagudfylder placements og kobler identiteterne, ændres
  `publication_state` (provenance) → publiceringerne bliver `stale_published`
  og kræver en revalideringsbatch. Det gælder 1939's 550 i samme grad; de to
  udgaver forbliver symmetriske.
- Writeren træffer **ingen** identitetsafgørelse selv (#152 §11): afgørelsen er
  den hash-låste, menneskeligt autoriserede manifest-godkendelse + den
  historiske `person_external_id`-beslutning (2026-07-30, `book_post_id = record_key`).
  Afstemning med #151: afgørelsen ligger i DB (`source_persona_identity_event`)
  med batch- og autorisationshash, ikke kun i gitignorerede filer.

## 6. Writer: elementoperation `legacy_migration`

### 6.1 Udvidelse af #153's lukkede mængder (generel, editionsneutral)

- `private.reimport_event.operation` CHECK: + `legacy_migration`.
- `expected_counts`: nøglerne `person_creates` og `source_evidence` forbliver
  obligatoriske; `legacy_migrations` er en **valgfri** tredje nøgle (fravær =
  0). Gælder `validate_reimport_authorization_payload`, `red_finalize_reimport`
  (tæller alle tre, når nøglen er erklæret), `red_reimport_batch_result`,
  `preview_authorization_request` (R) og `reimport_writer_expected_counts` (R).
  149a's to-nøgle-manifester og tests forbliver gyldige.
- Element-id-præfiks `legacy-migration:<record_key>`; autoriserede elementer
  matches som i dag på præcis payload.
- Ny RPC `public.red_apply_reimport_legacy_migration(p_batch_id uuid,
  p_element_id text, p_payload jsonb) RETURNS jsonb`, `SECURITY DEFINER`,
  REVOKE fra PUBLIC/anon/authenticated/service_role, GRANT kun `authenticated`
  (samme ACL-mønster som `red_apply_reimport_source_evidence`). `get_advisors`
  køres efter DDL.
- **#152's læsefunktioner (fund ved kodelæsning 2026-09-03):** legacy-grenen i
  `public.public_person_bio_source_versions_v2` og `public.public_person_bio_source_versions`
  joiner `narrative_legacy_publication` på `narrative_id` uden filter på `status`,
  og `person_daa_narrative_publication_allowed` returnerer fra binding-grenen uden
  at se på ledgeren. Et narrativ med `published` binding **og** `migrated`
  ledger-række ville derfor vises to gange (`source_record` + `Overgangsdata`
  bygget af `legacy_migrated`-eventets `after_state`). #152 havde aldrig
  tilfældet; 149b skaber det 541 gange. Rettelse i 149b: begge legacy-grene
  filtrerer `legacy.status='grandfathered_publication'`; `red_person_narrative_records`'
  legacy-forespørgsel udelader `migrated` rækker (record-rækken bærer nu
  narrativet; `legacy_migrated`-eventet ses fortsat i
  `red_person_narrative_publication_history`). `withdrawn` legacy-rækker vises
  uændret. Klienten (`web/src/data/redaktionRead.ts`, `public.ts`) kræver ingen
  ændring.
- Writer-profil: én række `private.reimport_writer_profile` for `source_id = 1`,
  `profile_id = 'daa-2018-20-legacy-migration-v1'`, `writer_config` med
  #153's lukkede feltmængde (samme `rendition_key`/`rendition_kind`/
  `rendition_metadata`/`citation_label_template` som 149a-profilen;
  `run_key_prefix = 'reimport-legacy-migration:'`, `schema_version =
  'legacy-migration-manifest-v1'`, `extractor_version = 'legacy-migration-v1'`,
  `observation_extraction_method = 'none'`).

### 6.2 Payload (lukket feltmængde, kun hashes — ingen tekst)

```
source_record_key, source_id, person_id, narrative_id,
disposition ∈ {bound_published, bound_draft},
narrative_text_sha256      -- sha256(narrative.tekst), rå
occurrence_verbatim_sha256 -- sha256(source_record_occurrence.verbatim_text)
normalized_text_sha256     -- sha256(narrative_norm_v1(tekst)) = sha256(norm(verbatim))
legacy_publication_ref     -- uuid ved bound_published, null ved bound_draft
legacy_baseline_sha256     -- ledgerens baseline_sha256 ved bound_published, null ellers
persona_key                -- = record_key
```

### 6.3 Preconditions (fail-closed, i denne rækkefølge)

1. Delt cutover-lås, kontraktversion 2, åben batch, `redaktion`-aktør,
   `lock_reimport_writer(source, profile)`, element autoriseret med identisk
   payload.
2. Record `(source_id, record_key)` findes, låses `FOR UPDATE`; præcis én
   accepteret anker-forekomst; `sha256(occurrence.verbatim_text)` = payload.
3. `person_external_id`: præcis én række for `(source_id, record_key)` =
   `person_id`, og `person_id` har præcis én række for `source_id`.
4. Narrativ: præcis ét `narrative(subjekt_type='person', subjekt_id=person_id,
   source_id)` = `narrative_id`; ingen `narrative_record_publication` for det
   (uanset status); `sha256(tekst)` = payload; rækken låses.
5. Legacy-ledger: ved `bound_published` findes rækken med
   `status='grandfathered_publication'`, `baseline_sha256` = payload og
   `narrative_legacy_state(..., true)->>'baseline_matches' = true`, og
   `publication_policy.publication_allowed = true`; ved `bound_draft` findes
   **ingen** ledger-række, og `publication_allowed = false`. Alt andet:
   `LEGACY_MIGRATION_LEDGER_INCONSISTENT`.
6. `app.change_set_id` er tom (`NARRATIVE_RECORD_FOREIGN_CHANGE_SET`).

### 6.4 Projektion og events (ét change set pr. element)

Låserække (#152 §6.1 og legacy-writernes mønster): `LOCK TABLE public.change_set
IN ACCESS EXCLUSIVE MODE` → `private.source_record FOR UPDATE` → den aktive
narrativrække → ledger, seneste legacy-event og narrativ via
`narrative_legacy_state(ref, true)` (kun `bound_published`). Bindingen låses
aldrig før recorden. Prod-apply kører under det eksterne writer-traffic hold fra
#152's cutover-runbook, fordi 541 offentlige publiceringer skifter form.

1. Identitet (§5): run, persona, mention, `red_decide_source_persona_identity`
   (GRANTED `authenticated`, `schema.sql:6979-6986`; bruges allerede af
   `red_apply_reimport_person_create`).
2. `v_before := private.narrative_publication_state(person, source, record_key)`
   (autoritet `missing_identity` er sandfærdig og registreres).
3. `begin_change_set('narrative_record_legacy_migrated', …, 'person', person_id)`.
4. **Legacy-stream** (kun `bound_published`): `UPDATE narrative_legacy_publication
   SET status='migrated'`; append `legacy_migrated` (stream = `legacy_publication_ref`,
   before/after = `narrative_legacy_publication_state`, `decision_basis` =
   »Legacy-migration til source record <record_key> (batch <id>)«);
   `latest_event_id` opdateres. Efterkontrol: `narrative_legacy_state.ledger_status
   = 'migrated'`, `publication_status = 'withdrawn'`.
5. **Record-stream:** `INSERT narrative_record_publication(narrative_id,
   source_record_id, record_label, citation_label, status='draft')` med labels fra
   `private.narrative_record_labels(record)`; `after_1 :=
   narrative_publication_state(...)`; append `draft_created` (v1, before = `v_before`).
   Ved `bound_published`: `UPDATE … status='published'`; `after_2`; append
   `published` (v2, before = `after_1`).
6. Efterkontrol som `mutate_person_narrative_record`: `narrative_record_state`'s
   `latest_event_id`, `publication_state_sha256`, `publication_status`
   (`published` hhv. `draft`), `authority.kind = 'existing_exact_binding'`,
   `eligibility_status = 'eligible'`; for `bound_published` desuden
   `public.person_daa_narrative_publication_allowed(narrative_id) = true`.
7. `INSERT private.reimport_event(operation='legacy_migration',
   source_record_key, canonical_person_id, payload || resultat
   {persona_id, identity_version, legacy_event_id, binding_id,
   draft_event_id, published_event_id, publication_state_sha256, state_sha256})`.
8. Gatewayen nulstiller `app.change_set_id` efter hvert element (som ved
   `person_create`).

### 6.5 Hvad der bevidst ikke røres

- `narrative.tekst`, `narrative.privat`, `narrative.side` (side indgår i
  legacy-baseline-hashen; ændring før `legacy_migrated` ville give
  `NARRATIVE_LEGACY_BASELINE_DRIFT`). Sidehenvisning bæres af record-labels.
- `person`, `fact`, `family_member`, `person_external_id`.
- Ingen `source_record`/forekomst/anker skrives (149a's).

## 7. Manifest, preview og gate

- **Eksport (R, læse-kun, REPEATABLE READ READ ONLY):**
  `export_legacy_migration_candidates.R --profile … --output-dir <0700-mappe uden work-komponent>`
  skriver pr. record: `record_key`, `person_id`, `narrative_id`, `levende/privat/staged`,
  `narrative.privat`, `sha256(tekst)`, ledger-status/ref/baseline-hash,
  forekomstens `verbatim_sha256` — og **den rå tekst** for narrativ og forekomst i en
  separat 0600-fil, som kun bruges lokalt af normaliseringen og aldrig committes
  (samme posture som #152's cutover-eksport; afviser stier med `work`).
- **Bygger (Python):** `build_legacy_migration_manifest.py --profile --candidates
  --texts --rendition-text --output` beregner `narrative_norm_v1` (fra
  `normalize_narrative_1939_v50.py`, corpus = renditionen) for begge sider,
  tildeler disposition, håndhæver §4's stopgrænse og inkonsistensregel, og
  skriver et manifest **uden tekst**: `source`, `expected_counts`
  (`person_creates 0`, `source_evidence 0`, `legacy_migrations N`),
  `dispositions` (alle 591), `operations` (kun `bound_*`, `dependency_class =
  'legacy_migration'`), `manifest_content_sha256`. Deterministisk: samme input →
  samme hash.
- **Validator:** `validate_reimport_manifest` (R) udvides til den nye
  `dependency_class` og den valgfri tredje nøgle.
- **Preview (R, læse-kun):** før-billede pr. source: antal legacy-rækker pr. status,
  bindinger pr. status, personas/identiteter for source, dispositioner talt op
  mod manifestet, kanoniske aggregat-hashes (`person`, `fact`, `family_member`,
  `narrative`, `narrative_record_publication`, `narrative_legacy_publication`)
  og `anon`-hashes. `preview_sha256` = preview-filens bytes (149a-afvigelse 5).
- **Gate:** fase-pakke-gaten (backup 0600+SHA, restore-rehearsal, hash-låst
  manifest, projektejer-GO, ét apply, replay `already_applied`, reversal bevist).
  Prod-rækkefølge: #152-cutover → #153 (m. guard-rettelse) → 149a → 149b.

## 8. Reversal (valg B, PM — kræver kvittering før prod-GO)

**Revideret 2026-09-04 efter implementeringsfund (leverance 1):** #152's reversal
appender et `reversal`-event til samme stream, så efter fortrydelse af `published`
er `draft_created` ikke længere streamens seneste event og kan ikke fortrydes
(`NARRATIVE_PUBLICATION_EVENT_NOT_LATEST`, empirisk bekræftet). Kæden er derfor:

- **Per narrativ, dedikeret:** `private.reverse_narrative_publication_event`
  håndterer allerede `published` (→ draft). Kladden trækkes tilbage med den
  eksisterende `red_kasser_person_narrative_record` (`draft_discarded` → binding
  `withdrawn`). Der tilføjes `legacy_migrated` til den reversible mængde med
  gaten: eventet er streamens seneste, ledgeren står `migrated`,
  `baseline_matches = true`, policy tillader publicering, **og** narrativets
  record-binding er ikke aktiv (status `withdrawn`), ellers
  `NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE`. Reversal sætter ledgeren tilbage
  til `grandfathered_publication` og appender `reversal`. Fuld fortrydelse af ét
  `bound_published`-narrativ er derfor: reverse `published` → discard draft →
  reverse `legacy_migrated` (tre nye events, fuld historik bevaret). For
  `bound_draft` er det ét trin: reverse `draft_created` (→ withdrawn).
- **Læsegaten efter fuld fortrydelse (fund 2026-09-04):**
  `person_daa_narrative_publication_allowed` returnerede `false`, så snart
  narrativet havde en binding-række uanset status, og nåede aldrig legacy-grenen;
  record-grenene i `public_person_bio_source_versions(_v2)` joiner bindingen uden
  statusfilter. Kombinationen (withdrawn binding + grandfathered ledger) findes
  først med 149b. 149b retter derfor begge i #152's læsefunktioner: gaten ser kun
  bindinger med status `draft`/`published`, og record-grenene kræver
  `binding.status='published'`. Efter fuld fortrydelse vises det grandfathered
  narrativ igen præcis én gang som `legacy_narrative`.
- **Kendt begrænsning:** fuld fortrydelse er endelig for narrativet.
  `narrative_record_publication.narrative_id` er UNIQUE, og writeren afviser et
  narrativ med enhver eksisterende binding (`LEGACY_MIGRATION_ALREADY_BOUND`).
  Genmigrering af et fortrudt narrativ er uden for 149b og kræver en ny beslutning
  (fx en `withdrawn`-only-gren i writeren, jf. #152 §6.2's mønster for nye
  narrativer).
- **Batch:** `red_reverse_reimport` afviser fortsat en ren `legacy_migration`-batch
  (`REIMPORT_WRITER_REVERSAL_INVALID`); en samlet fortrydelse er de per-narrativ
  trin kørt i omvendt elementrækkefølge af et R-script under én
  reversal-autorisation, med efterkontrol af at legacy-tal og bindings-tal er
  tilbage på før-billedet. Restore fra 0600-backup er den sidste udvej.
- **Batch-status efter fuld fortrydelse (fund 2026-09-04):** batchen forbliver
  `finalized`. `reversed` er reserveret til `red_reverse_reimport`'s fulde
  tilbagerulning (som kræver `activated` + en `name_completion`-child-batch), og
  `red_begin_reimport`'s replay-opslag filtrerer på `status='finalized'` — en
  statusændring ville lade samme manifest åbne en **ny** batch, der først dør på
  `LEGACY_MIGRATION_ALREADY_BOUND`. Den autoritative markør for »fortrudt« er
  derfor `private.reimport_event` med `operation='reversal'` og
  `element_id='legacy-migration-reversal:<authorization_id>'`, ikke batch-status.
  **Operatørfælde:** en genkørsel af samme manifest efter en fortrydelse svarer
  fortsat `already_applied` (replay-vejen), selv om virkningerne er rullet
  tilbage. `already_applied` må derfor aldrig læses som »stadig anvendt« uden at
  reversal-markøren er tjekket:
  ```sql
  SELECT count(*) FROM private.reimport_event
   WHERE batch_id = :batch AND operation = 'reversal';   -- >0 = batchen er fortrudt
  ```
- `red_tilbagetraek_legacy_narrative` på en `migrated` række fejler med
  `NARRATIVE_LEGACY_PUBLICATION_TRANSITION_INVALID`; det testes.

## 9. Persondata

Ingen model kaldes. Manifest, preview, rapporter, fixtures og tests indeholder
kun `record_key`, id'er, tal og hashes. Rå tekst forlader kun databasen til en
0600-fil uden for repoet, som normaliseringen læser lokalt. Bindinger for
`levende`/`staged`/`privat` personer er `draft` og forbliver skjult af
publiceringsgaten. Synthetiske fixtures bruger opdigtede navne.

## 10. Test

- **SQL** (`tests/sql/test-reimport-legacy-migration.sql`, syntetisk v2-base):
  alle §6.3-preconditions fejler med deres kode; `bound_published` giver ledger
  `migrated`, binding `published`, tre events, `publication_allowed = true`,
  v2-fladen viser præcis én række; `bound_draft` giver binding `draft`, ingen
  legacy-event, v2-fladen viser ingen; replay = `already_applied`; reversal-kæden
  §8 gendanner eksakt før-hash for begge streams; `red_tilbagetraek_legacy_narrative`
  på `migrated` afvises; `public_person_bio_source_versions_v2`, `public_person_bio_source_versions`
  og `red_person_narrative_records` viser et migreret narrativ præcis én gang og
  aldrig som `legacy_narrative`/`grandfathered_legacy`, mens en `withdrawn` legacy-række
  stadig optræder i redaktørlisten; editionskatalog-gaten forbliver ren; 149a's
  to-nøgle-manifest autoriseres stadig. Kørsel i CI som nyt job ved siden af
  `reimport_legacy_source_evidence_153`.
- **R:** enhedstests for validator/expected_counts/dispatch; integrationstest
  mod syntetisk v2-base (dry-run, apply, replay), idempotent pr. kørsel.
- **Python:** bygger-tests: disposition pr. regel, stopgrænse, inkonsistens,
  determinisme, ingen tekst i output.
- **Rehearsal (definition of done, beslutning 2026-09-03 pkt. 4):** restore af
  prod-dump → migrations → #152-cutover → 149a-apply → 149b preview/dry-run/apply
  med de forventede tal 541/46/4/0 — målt som **eksakte eventtal**: 587 personas,
  587 accepterede identiteter, 587 `draft_created`, 541 `published`, 541
  `legacy_migrated`, ledger for source 1 = 541 `migrated` + 3 `grandfathered_publication`
  + 0 `withdrawn`, 587 bindinger (541 `published`, 46 `draft`) — `anon`-hashes
  uændrede for de otte tabeller (publication-tilstandshashes indeholder
  `published_at = clock_timestamp()` og sammenlignes ikke på tværs af baser;
  sammenlign rækketal og status),
  `public_person_bio_source_versions_v2` for de 591 personer viser 541
  `source_record`-rækker og 0 `legacy_narrative` for source 1, replay, tre-trins
  reversal for ét narrativ.

## 11. Ændringsmyndighed

Ændringer i §4's regler, §5's valg A eller §8's valg B kræver en post i
`docs/decisions.md`. Prod-apply kræver desuden projektejerens kvittering for
valg A og B samt fase-pakke-gaten.
