# Kortlægning: fuld sletning af en person (`public.person.id`)

Kilde: `schema.sql` (main @ af9c7abe), `db-rls.sql`, `db-verify.sql`, `web/src`, `packages/feed`, `docs/decisions.md`.
Kun læsning — intet er kørt mod en database. Linjenumre er `schema.sql`, medmindre andet står.
Numrene **S1–S58** bruges identisk i `count.sql` (dér nulpolstret, S01…S58, plus underpunkter som S23b/S37c/S58a). `count.sql` er **aldrig kørt** — kun statisk kontrolleret (parentes-balance, kolonnenavne mod `schema.sql`).

Kolonnen **I dag** = hvad `red_slet_person` (l. 7156–7252) gør i dag:
`slet` = sletter rækken · `null` = nulstiller referencen · `cascade` = FK-cascade tager den ·
`afvis` = funktionen afviser sletningen · **`—`** = røres ikke (efterlader spor eller giver FK-fejl).

## Kort fortalt

- `red_slet_person` rydder kernen (fakta + evidenskæde, relationer, noter, narrativer + binding,
  external-id, familie-links, medlemskaber, karantæne, profil-binding). Den efterlader **mindst
  15 typer spor** i offentlige tabeller (story, entity_description, suggestion, feed_pin,
  import_korrektion, paastand_korrektion, medier, tomme familier, `[[person:id|navn]]` i andres
  tekst …) og **hele historikken** (change_set/change_event — inkl. et komplet `foer`-snapshot af
  alt den selv slettede).
- Der er **tre hårde blokeringer**, ikke to: ud over publication-events og kildeidentitet har
  `private.source_persona_identity_candidate.candidate_person_id` en NOT NULL-FK uden ON DELETE
  på en append-only-tabel, og den er **ikke** gatet i `red_slet_person` (rå FK-fejl midt i
  sletningen).
- Historikken er ikke kun "personens egne" change_sets: personens id og indhold ligger i andre
  personers change_sets (union, samme_som, flyt_barn, bulk-/reimport-/cutover-sæt), og
  `red_opret_person` skriver **navnet** i `summary` med `subjekt_type=NULL`.

---

## Punkt 1 — Hårde FK'er mod `public.person(id)`

| # | Tabel.kolonne | ON DELETE | Find ud fra pid | Spærring | I dag | Linje |
|---|---|---|---|---|---|---|
| S1 | `public.person.id` (selve rækken) | — | `id = pid` | `trg_log_person` logger DELETE med fuldt `foer` | slet | 126 |
| S2 | `public.person_external_id.person_id` | NO ACTION | `person_id = pid` | `trg_external_id_regen` (regen visning) | slet | 142–152 |
| S3 | `public.family_member.person_id` | NO ACTION | `person_id = pid` | `trg_partner_loft` (kun INSERT/UPDATE); EXCLUDE-constraint deferrable | slet | 3704–3720 |
| S4 | `public.slaegtsnavn_karantaene.person_id` (PK) | NO ACTION | `person_id = pid` | ingen (cache, ikke versioneret) | slet | 3658 |
| S5 | `public.profiles.reventlow_person_id` | NO ACTION | `reventlow_person_id = pid` | versioneret: skip_cols er kun `email`,`rolle` (l. 9184), så både `reventlow_person_id` og `navn` (tilføjet l. 9683) logges | null | 3669 |
| S6 | `public.bookmark.person_id` | **CASCADE** | `person_id = pid` | ingen | cascade | 3690–3696 |
| S7 | `public.person_slaegt_membership.person_id` | NO ACTION | `person_id = pid` | versioneret | slet | 2272 |
| S8 | `public.person_lineage_membership.person_id` | NO ACTION | `person_id = pid` | versioneret | slet | 2281 |
| S9 | `private.person_create_receipt.person_id` | **CASCADE** | `person_id = pid` | ingen | cascade | 10387 |
| S10 | `private.source_persona_identity.canonical_person_id` | NO ACTION | `canonical_person_id = pid` | mutérbar tilstand, men constraint-trigger `identity_state_has_event` kræver match med seneste event; `validate_source_persona_identity_state` kræver tabel-ejer for ikke-`proposed` | **afvis** (`PERSON_HAR_KILDEIDENTITET`) | 1637, 1882–1944, 1964 |
| S11 | `private.source_persona_identity_event.canonical_person_id` | NO ACTION | `canonical_person_id = pid` | **append-only** (`trg_source_persona_identity_event_append_only`, `reject_evidence_mutation`) | **afvis** | 1669, 1973–1991 |
| S12 | `private.source_persona_identity_candidate.candidate_person_id` (NOT NULL) | NO ACTION | `candidate_person_id = pid` | **append-only + no-truncate**; `candidate_run.candidates_sha256`/`candidate_count` og `identity_control_run.*_sha256` er hash/tal over kandidaterne | **— (ikke gatet → rå FK-fejl)** | 1724–1752 |

Ingen andre `REFERENCES person` i `schema.sql` (grep på `person(id)`/`public.person(id)`).

## Punkt 2 — Polymorfe/bløde referencer og kæder

### 2a. Kerne-evidens (offentlige tabeller)

| # | Tabel/kolonne | Ref.-type | Find ud fra pid | Spærring | I dag | Linje |
|---|---|---|---|---|---|---|
| S13 | `fact (subjekt_type,subjekt_id)` | polymorf | `subjekt_type='person' AND subjekt_id=pid` → F | versioneret; `haendelse.fact_id` FK uden ON DELETE (nulstilles først) | slet | 3723 |
| S14 | `relation (subjekt_*/objekt_*)` | polymorf, begge ender | person som subjekt **eller** objekt → R | `trg_relation_evidence_delete` (afviser DELETE hvis assertion/conclusion/note stadig peger på den); identitets-låse ved samme_som | slet | 3737, 7394–7415 |
| S15 | `assertion (target_type,target_id)` | polymorf | `target ∈ F ∪ R` → A | `trg_assertion_relation_target`; `uforanderlig` håndhæves kun i RPC'er (l. 6905), ikke trigger | slet | 3757 |
| S16 | `conclusion (target_*)`, `valgt_assertion_id` FK | polymorf + FK | `target ∈ F ∪ R` | FK → assertion: skal slettes før assertion; `trg_conclusion_regen` | slet | 3772 |
| S17 | `citation.assertion_id` FK (indhold: `citat_tekst`) | FK | `assertion_id ∈ A` | FK → assertion | slet | 3790 |
| S18 | `note (target_type,target_id)` (indhold: `indhold`) | polymorf | `target person=pid` eller `fact ∈ F` / `relation ∈ R` | `trg_mentions_note` | slet | 3811 |
| S19 | `relation` med en **fact-ende** (`subjekt/objekt_type='fact'`, id ∈ F), fx 'udførte' | polymorf | se kolonne | — | **—** (ikke i R → dinglende) | 3733 (kommentar) |
| S20 | `assertion.objekt_type/objekt_id` (påstandens værdi = entitet) | polymorf | `objekt_type='person' AND objekt_id=pid` (v1 bruger kun 'family') | — | **—** (defensivt) | 3762–3763 |

### 2b. Narrativ, publikation, formidling

| # | Tabel/kolonne | Ref.-type | Find ud fra pid | Spærring | I dag | Linje |
|---|---|---|---|---|---|---|
| S21 | `narrative (subjekt_*)` (`tekst`) | polymorf | `subjekt_type='person' AND subjekt_id=pid` → N | `trg_mentions_narrative`; versioneret | slet | 3819 |
| S22 | `private.narrative_record_publication.narrative_id` FK | FK, ingen ON DELETE | `narrative_id ∈ N` | `validate_…` (binding immutable ved UPDATE); FK-mål for events | slet | 3831–3866 |
| S23 | `private.narrative_publication_event` (`narrative_id`, `binding_id`, `change_set_id` FK; `before/after_state` jsonb indeholder `canonical_person_id`, record-ids) | FK | `narrative_id ∈ N` | **append-only** (`trg_narrative_publication_event_append_only`), `stream_version`-kæde pr. `stream_ref`, `reversed_event_id` self-FK | **afvis** (`PERSON_HAR_NARRATIVE_PUBLICATION_HISTORY`) | 13825–13901, 13930–14062 |
| S23b | **Andre** personers publication-streams: `narrative_publication_event.before/after_state` og `narrative_legacy_publication.baseline_state` indeholder `canonical_person_id` for *alle* accepterede personas på recorden — også `mentioned_spouse`/`child_reference` (`narrative_publication_state`, l. 14978–15005) | jsonb i append-only | jsonb-nøgle `canonical_person_id = pid` på events hvor `narrative_id ∉ N` | append-only + sha256 over tilstanden | **—** (kan ikke ryddes) | 14878, 14978 |
| S24 | `private.narrative_legacy_publication.narrative_id` FK (`baseline_state` jsonb) | FK, ingen ON DELETE | `narrative_id ∈ N` | validate-trigger (baseline immutable); event-FK peger ind | **—** (oprettes kun sammen med et baseline-event, l. 14571–14590, så S23-gaten fanger den i praksis) | 13800–13823 |
| S25 | `haendelse.narrative_id` FK | **CASCADE** | `narrative_id ∈ N` | — | cascade | 6431–6453 |
| S26 | `haendelse (subjekt_*)` under **en anden persons** narrativ | polymorf | `subjekt_type='person' AND subjekt_id=pid AND narrative_id ∉ N` | — | **—** | 6433–6434 |
| S27 | `haendelse.fact_id / relation_id` (andres hændelser forankret i P's fakta/relationer) | FK uden ON DELETE | `fact_id ∈ F OR relation_id ∈ R` | FK blokerer | null | 7237–7238 |
| S28 | `text_mention` med **kilde** = P's narrativ/note | afledt indeks | `kilde_type='narrative' AND kilde_id ∈ N` (+ noter) | vedligeholdes af trigger | cascade (trigger) | 9640–9681 |
| S29 | `text_mention.maal_type='person', maal_id=pid` — dvs. **andres** narrativer/noter indeholder `[[person:pid|Navn]]` | afledt indeks over prosa | `maal_type='person' AND maal_id=pid` | teksten selv ligger i andres `narrative.tekst`/`note.indhold` (og deres change_event) | **—** | 9624–9635 |
| S30 | `story (subjekt_*)` (`titel`, `tekst`) + `story_kilde` (CASCADE fra story) | polymorf | `subjekt_type='person' AND subjekt_id=pid` | versioneret | **—** | 6475–6513 |
| S31 | `story.fact_id / relation_id` (andres stories forankret i P's fakta/relationer) | FK **SET NULL** | `fact_id ∈ F OR relation_id ∈ R` | — | auto (SET NULL) | 6481–6482 |
| S32 | `feed_pin.kort_noegle` (tekstnøgle) | indlejret id | `portrait:pid`, `citat:pid`, `naevnt:pid`, `jubilaeum:pid:…`, `embede:pid:<label>:<år>`, `slaegt:<a>:<b>` (pid som a eller b), `arkiv:<haendelse-id>` (P's hændelser), `forbundet:<family-id>` | versioneret; `embede`-nøglen bærer embedstitel som tekst | **—** | 6518; `packages/feed/src/pool.ts:71–250` |
| S33 | `entity_description (subjekt_*)` (`tekst`) + `private.entity_description_source` (CASCADE) | polymorf | `subjekt_type='person' AND subjekt_id=pid` | versioneret (`trg_log_entity_description`) | **—** | 11942–11990 |
| S34 | `suggestion (subjekt_*)` (`vaerdi`, `payload`, `note`, `kilde_fritekst`) | polymorf | `subjekt_type='person' AND subjekt_id=pid` (payload kan også nævne id) | ikke versioneret | **—** | 3673–3685 |

### 2c. Rettelsesjournaler, medier, familier

| # | Tabel/kolonne | Ref.-type | Find ud fra pid | Spærring | I dag | Linje |
|---|---|---|---|---|---|---|
| S35 | `import_korrektion (import_key, record_key)` (`importeret`/`korrigeret` = navn/datoer) | nøgle via artefakt | `source.import_key` + `person_external_id.record_key` for pid (**skal beregnes før S2 slettes**; ellers via change_event-historik) | versioneret; bevidst ingen FK (l. 156–158) | **—** | 159–175, 2036–2150 |
| S36 | `paastand_korrektion.assertion_id` (`foer`/`efter` jsonb = gammel/ny påstandsværdi) + `change_set_id` FK | id uden FK | `assertion_id ∈ A` (inkl. historiske assertion-id'er) | "aldrig opdateret eller slettet" (kommentar l. 10081–10086; **ingen trigger**); FK → change_set blokerer sletning af change_set | **—** | 10087–10101 |
| S37 | `media` via `relation rolle='afbildet' person→media` (+ evt. andre roller) og `media_variant` (CASCADE) | polymorf | media-id'er i P's relationer; "eksklusive" = ingen anden relation/fact/story/narrative/note/suggestion/text_mention peger på mediet | `red_udrens_media` kræver `upload_status='fjernet'` + nul ankre (l. 9049–9104); `titel`/`original_filnavn` kan bære navnet | relation slettes; **media-række + bytes bliver** | 67–112, 9049 |
| S38 | `family` + `fact`/`narrative`/`note` med `subjekt/target_type='family'` for P's familier | FK (family_member) + polymorf | `family_id IN (SELECT family_id FROM family_member WHERE person_id=pid)` | versioneret; `lock_family_rows` | **—** (familien, vielses-fakta m.m. bliver; kan stå tom) | 3699, 18910 |

### 2d. Private ledgers (identitet, reimport, kontrol) — alle append-only

| # | Tabel/kolonne | Ref.-type | Find ud fra pid | Spærring | I dag | Linje |
|---|---|---|---|---|---|---|
| S39 | `private.interpretation_promotion (target_type,target_id)` + `evidence` (familiebinding: `state_sha256`) | polymorf, ingen FK | `target ∈ {person=pid, fact∈F, assertion∈A, relation∈R, narrative∈N, haendelse, family∈fams}` | append-only (loop l. 1973) | **—** (dinglende) | 1596–1633, 1839–1854 |
| S40 | `private.legacy_placement_disposition.person_id` (+ `legacy_sha256` over external-id-rækken) | id uden FK | `person_id = pid` | append-only + no-truncate | **—** | 2793–2834 |
| S41 | `private.reimport_event.canonical_person_id` + `payload` jsonb (`person_id`, `narrative_id`, …) | id uden FK | kolonne `= pid` eller payload-nøgle | append-only (`trg_reimport_event_append_only`); `text_revision_reconciliation` FK ind | **—** | 3976–3988, 4072 |
| S42 | `private.reimport_name_completion_result (person_id, fact_id, assertion_id, citation_id, conclusion_id)` + hashes | id uden FK | `person_id = pid` | append-only | **—** | 4045–4061, 4073 |
| S43 | `private.reimport_case_event.payload` jsonb (identity_different/record_assign) | jsonb | payload-nøgle = pid | append-only (`trg_reimport_case_event_append_only`) | **—** | 9279–9302 |
| S44 | `private.reimport_authorization.authorized_elements` / `private.reimport_case_authorization.authorized_elements` jsonb | jsonb | payload-nøgle = pid (heuristik) | ingen trigger (status opdateres), men indgår i `manifest/preview_sha256` | **—** | 3931–3952, 9227–9251 |
| S45 | `private.identity_control_parent_card.counterpart_person_id` + `partner_ids bigint[]` | id uden FK | `counterpart_person_id=pid OR pid = ANY(partner_ids)` | append-only (loop l. 19455–19468); `sheet_sha256`/`rows_sha256` i events | **—** | 19432–19449 |
| S46 | `private.identity_control_sample.mapping` jsonb | jsonb | payload-nøgle = pid (heuristik) | append-only | **—** | 19392–19411 |
| S47 | `private.source_persona_identity_candidate.basis`, `source_persona_identity(_event).evidence` jsonb | jsonb | via S10–S12 | append-only | — | 1645, 1678, 1732 |
| S48 | Hashes over familie-rækker: `private.relation_binding_state` (l. 20004) indeholder `family_member`-rækker `[person_id, rolle, ordinal, konfidens]` → `interpretation_promotion.evidence.state_sha256`, `relation_classification_event.state_sha256`; `persona_family_context` → `candidate.family_context_sha256` | hash | familie-id'er i fams | append-only; sletning af P's `family_member` gør **ægtefællers/børns** bindinger "stale" | — | 20004–20129, 18880–18905, 20132 |
| S49 | `private.relation_reopen (from/to_family_id)`, `private.marriage_ordinal_correction.family_id`, `private.text_revision_reconciliation` (via promotion-id) | familie-/promotion-id | `family_id ∈ fams` | append-only + no-truncate | — | 20263, 1409, 21377 |
| S50 | `private.narrative_record_cutover_receipt.result` jsonb (aggregeret kvittering over alle narrativer) | jsonb | heuristik | append-only | — | 17390–17419 |
| S51 | `private.identity_relation_update_prelock.locked_person_ids` | transient | `pid = ANY(locked_person_ids)` | ryddes af deferred trigger ved COMMIT | — | 7521–7551 |
| S58 | Øvrige jsonb-kolonner, der kan bære P's id (input-payloads flettes ind med `p_payload||…`, så nøglenavnene er ikke faste): `interpretation_promotion.evidence`, `interpretation.value`/`decision_evidence`, `source_persona_identity_candidate.basis`, `relation_reopen.context`, `text_revision_reconciliation.context`, `relation_classification_event.evidence`, `marriage_ordinal_correction.evidence`, `legacy_placement_disposition.evidence`, `source_*_placement_decision.evidence`, `suggestion.payload` | jsonb | heuristik: nøgle der indeholder `person` med værdi pid (også citeret, jf. `(p_payload->>'person_id')::bigint` l. 5902) eller pid i et array under en `partner`/`person`-nøgle | append-only (undtagen suggestion) | **—** | 1258–1303, 1732, 20132–20280, 21377 |

## Punkt 3 — Historik (`change_set` / `change_event`)

Mekanik: `log_change()` (l. 9370–9398) logges for hver tabel i `version_pk_registry` (l. 9157–9192 +
`entity_description` l. 11984): `row_pk` = PK-kolonnerne, `foer`/`efter` = **hele rækken som jsonb**
minus `skip_cols`. Logning sker kun, når `app.change_set_id` er sat (bulk-load logges ikke).
`red_slet_person` selv logger DELETE med fuldt `foer` af alt, den sletter → **sletningen efterlader
en komplet kopi af personen i change_event**, og `red_fortryd_change_set` (l. 9484) kan genskabe den.

| # | Sted | Hvordan pid/indhold optræder | Find ud fra pid | Spærring | Linje |
|---|---|---|---|---|---|
| S52 | `change_set (subjekt_type, subjekt_id)` | P er subjekt (red_set_koen, red_slet_person, red_ret_ocr_felt, red_tilfoej_partner, placement_membership_reversal, narrative_record_legacy_migrated …) | `subjekt_type='person' AND subjekt_id=pid` | FK-mål for S54–S56 og `reverterer_id` | 9194–9206 |
| S53 | `change_set.summary` hvor P **ikke** er subjekt | `red_opret_person`: `'Oprettede person <NAVN>'`, subjekt NULL (l. 8641); `red_samme_som`: `'Markerede person %s som samme som %s'`, subjekt = den anden (l. 7847); `red_ikke_samme_som` (l. 7912); `red_opret_union` `'… mellem A og B'`, subjekt=A (l. 8023); `red_relation` (l. 7302); `red_slet_familie_link`/`set_familie_*` (person-id i tekst); fortryd kopierer: `'Fortrød: <summary>'` (l. 9564/9572) | heuristik: `summary ~ '\m<pid>\M'` + alle sæt der indeholder P-events (S54) | — | 9339–9360 |
| S54 | `change_event` (alle tabeller) | se nøglestier nedenfor; `foer`/`efter` bærer navn, datoer, prosa, citater, noter | lukning over change_event (rækker der allerede er slettet findes **kun** her) | ingen trigger; `change_set_id` FK | 9310–9319 |
| S55 | `change_set.reverterer_id` (reversal-kæde) | et fortryd-sæt peger på originalen; summary-kopi | `reverterer_id ∈ {hit-sæt}` rekursivt | self-FK uden ON DELETE | 9205 |
| S56 | Indgående FK'er til change_set fra P-relevante sæt: `private.narrative_publication_event.change_set_id` (append-only!), `paastand_korrektion.change_set_id`, `private.reimport_case_batch.change_set_id` | FK | `change_set_id ∈ {hit-sæt}` | et change_set med et publication-event (fx contract-cutover-sættet, der bærer **alle** personers baseline-events) kan aldrig slettes | 13887, 10095, 9265 |
| S57 | Ikke-henførbare events i hit-sæt: change_events i et P-sæt, som ikke matcher en P-nøglesti | andre personers ændringer (union, bulk, reimport, cutover) **og** P's egne rækker, der ikke kan kobles (haendelse, family, media, citation uden kendt assertion) | `change_set_id ∈ hit-sæt AND event ∉ P-hits` | sættet kan ikke slettes helt; selektiv event-sletning gør fortryd ufuldstændig | — |

Nøglestier i `change_event` (S54), alle sammenlignet som tekst:

| `tabel` | Sti til pid |
|---|---|
| `person` | `row_pk->>'id' = pid` |
| `person_external_id`, `family_member`, `person_slaegt_membership`, `person_lineage_membership` | `row_pk->>'person_id' = pid` |
| `profiles` | `foer/efter->>'reventlow_person_id' = pid` (`email`, `rolle` er skip-cols) |
| `fact` | `foer/efter: subjekt_type='person' ∧ subjekt_id=pid` → historisk fakta-mængde F* |
| `relation` | `foer/efter: (subjekt|objekt)_type='person' ∧ _id=pid` → R* |
| `assertion` | `foer/efter: target ∈ F* ∪ R*` (eller `row_pk.id ∈ A`) → A* |
| `conclusion` | `foer/efter: target ∈ F* ∪ R*` |
| `citation` | `foer/efter->>'assertion_id' ∈ A*` |
| `note` | `foer/efter: target person=pid / fact∈F* / relation∈R*` |
| `narrative` | `foer/efter: subjekt person=pid` → N*; andres narrativer med `[[person:pid|` i `tekst` |
| `story` / `entity_description` | `foer/efter: subjekt person=pid` |
| `story_kilde` | `foer/efter->>'story_id'` ∈ P's stories |
| `feed_pin` | `foer/efter->>'kort_noegle'` matcher S32-mønstre |
| `import_korrektion` | `foer/efter: (import_key, record_key)` ∈ P's (historiske) external-ids |
| `haendelse` | **kan ikke kobles**: skip_cols fjerner `subjekt_*`, `narrative_id`, `klausul` m.m. (l. 9169) — rækkerne bærer kun `id`+`feed_status`, dvs. intet indhold |
| `media`, `family` | kun hvis de selv slettes (S37/S38) |

## Punkt 4 — Append-only-/uforanderlighedsspærringer og kæder

| Spærring | Tabel(ler) | Tillader | Effekt for en fuld sletning | Linje |
|---|---|---|---|---|
| `trg_<t>_append_only` + `_append_only_truncate` → `private.reject_evidence_mutation()` (ubetinget RAISE, ingen bypass-flag) | extraction_run, source_rendition, source_record, source_record_occurrence, source_record_anchor_event, source_record_revision_event, source_observation, source_observation_text, source_mention, source_persona, source_persona_mention | kun INSERT | rammer ikke, så længe bog-laget bevares (punkt 7) | 916–920, 1101–1121 |
| samme, loop 2 | private.vocab, clause_disposition | kun INSERT | — | 1125–1135 |
| samme, loop | source_persona_identity_candidate_run, **source_persona_identity_candidate** | kun INSERT | **S12 blokerer** | 1742–1752 |
| samme, loop | interpretation, interpretation_observation, interpretation_promotion_rule(_line), interpretation_promotion_batch, **interpretation_promotion**, **source_persona_identity_event** | kun INSERT | S11 blokerer; S39 kan ikke ryddes | 1973–1991 |
| `trg_interpretation_party_append_only`, marriage_ordinal_correction, relation_classification_event, relation_reopen, text_revision_reconciliation, legacy_placement_disposition, source_*_placement(+_decision) | | kun INSERT | S40, S48, S49 kan ikke ryddes | 1400, 1426, 2680–2691, 2809, 20148, 20281, 21403 |
| identity_control_run/sample/event/exclusion/**parent_card**/parent_event | | kun INSERT | S45/S46 kan ikke ryddes | 19455–19468 |
| `reject_reimport_writer_mutation` | reimport_writer_profile, **reimport_event**, **reimport_name_completion_result** | kun INSERT | S41/S42 kan ikke ryddes | 4063–4073 |
| `reject_reimport_case_event_mutation` | reimport_case_event | kun INSERT | S43 | 9297–9302 |
| `reject_narrative_publication_event_mutation` | **narrative_publication_event** | kun INSERT | **S23 blokerer**; FK til narrative + change_set | 13997–14062 |
| `reject_narrative_record_cutover_receipt_mutation` | narrative_record_cutover_receipt | kun INSERT | S50 | 17408–17419 |
| `reject_interpretation_predicate_mutation` | interpretation_predicate | UPDATE af ikke-nøglefelter | — | 1184–1196 |
| `identity_state_has_event` (deferred constraint trigger) | source_persona_identity | UPDATE/DELETE kun hvis tilstand = seneste event | S10 kan ikke slettes, mens S11-events findes | 1896–1944, 1964 |
| `validate_*` med `current_user = tabel-ejer` | source_persona_identity(_event), interpretation_promotion | kun ejer-rolle (SECURITY DEFINER-writers) | — | 1825–1891 |
| `trg_relation_evidence_delete` | relation | DELETE kun uden evidens | rækkefølge: citation → conclusion → assertion → note → relation | 7394–7415 |
| `narrative_record_publication_validate` | narrative_record_publication | UPDATE af status; binding-nøgler immutable | — | 3841–3853 |
| `narrative_legacy_publication_validate` | narrative_legacy_publication | UPDATE af status/latest_event_id | — | 14007–14065 |
| `db-verify.sql` (dangling-mål) | | | ingen assert på, at `interpretation_promotion`/`legacy_placement_disposition`/`reimport_*`-mål findes — kun en NOTICE-måling (l. 10555–10571). `red_doede_links` (view) vil vise S29-tokens som døde links. NB: db-verify's egen test-oprydning bruger `SET session_replication_role=replica` for at slette i append-only-tabeller (l. 5114–5116) — det slår også FK-triggere fra og kræver superuser | db-verify.sql 5114, 7323–7534, 10555 |
| `db-verify.sql` | | | kræver at `trg_narrative_publication_event_append_only`, `trg_source_record_append_only` m.fl. **findes og er enabled** (`tgenabled<>'D'`) og at event-kæder er konsistente (shape, reversal, identity, legacy latest_event) | db-verify.sql 73–180, 2756, 4477, 10224–10799 |

Hash-/versionskæder en sletning kan bryde for **andre** rækker:

| Kæde | Hvad brydes | Linje |
|---|---|---|
| `narrative_publication_event (stream_ref, stream_version)` + `before/after_state_sha256` | pr. narrativ-stream → sletning af **hele** P's streams bryder ikke andre streams; men cutover-/batch-change_sets deles | 13846, 13974–13980 |
| `narrative_legacy_publication.latest_event_id` ↔ event | skal slettes sammen med sin stream | 13903–13905 |
| `source_persona_identity_event (source_persona_id, version)` | per persona; sletning af P's events efterlader personaen uden tilstand → `identity_state_has_event` | 1683, 1872–1878 |
| `source_persona_identity_candidate_run.candidates_sha256`, `candidate_count`, `persona_count` | fjernes kandidatrækker for P, matcher kørslens hash/tal ikke længere (andre personers kandidater i samme kørsel) | 1705–1722 |
| `identity_control_run.identity_population_sha256`, `input_list_sha256`, `excluded_sha256`; `identity_control_event.sheet_sha256/rows_sha256` | populationshash over identiteter/kandidater | 19373–19422 |
| `interpretation_promotion.evidence.state_sha256` = hash(`relation_binding_state`) | indeholder `family_member`-rækker → ægtefællens/barnets binding bliver "stale", når P's family_member slettes (gælder også i dag) | 1624–1633, 20004–20129 |
| `relation_classification_event.state_sha256` | samme | 20132–20145 |
| `legacy_placement_disposition.legacy_sha256` = hash(person_external_id-rækken) | `is_current` bliver falsk/NULL | 2793–2834 |
| `reimport_*`: `manifest_sha256`, `preview_sha256`, `observed_counts`, `result_sha256`, `payload_sha256` | batch-kvitteringer over mange personer | 3931–4061, 9227–9295 |
| `narrative_record_cutover_receipt.result_sha256` | aggregeret over alle narrativer | 17390–17405 |
| `change_event.seq` pr. change_set | selektiv sletning efterlader huller; fortryd bliver delvis | 9313, 9578 |

## Punkt 5 — Låse og guards i `red_slet_person`

| Lås/guard | Hvad den beskytter | Linje |
|---|---|---|
| `pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0))` | serialiserer mod den atomiske narrative-record-cutover (exclusive), så kontraktversion og publication-tilstand ikke skifter under sletningen | 7163–7166 |
| `current_rolle()='redaktion'` | rollegate (kræver `jwt.claim.sub` i psql) | 7167 |
| Gate: publication-events på P's narrativer | append-only-historik (S23) | 7168–7176 |
| `pg_advisory_xact_lock(hashtext('samme_som_mutation'))` | global identitetsprotokol: samme_som/ikke_samme_som-grafen (træ-invariant, én sink pr. komponent) | 7177 |
| `private.guard_identity_mutation_snapshot()` | bumper singleton `identity_mutation_generation` → stale REPEATABLE READ-writers fejler 40001; giver transaktionsbundet bevis til `prelock_identity_relation_delete` | 7178, 7461–7489 |
| Gate: `source_persona_identity(_event).canonical_person_id` | S10/S11 FK + uforanderligt beslutningsspor | 7186–7191 |
| `begin_change_set('red_slet_person', …, 'person', pid)` | åbner audit-sættet (alle DELETEs logges med `foer`) | 7193 |
| `SELECT … FROM source JOIN person_external_id … FOR UPDATE OF s,pei` | fælles skriveorden med OCR-rettelsen (source/external-id → person → evidens), undgår deadlock-cyklus | 7195–7199 |
| `private.lock_identity_people(ARRAY[pid])` | `FOR UPDATE` på person-rækken i stigende orden (global låsrækkefølge); fejler `IDENTITY_PERSON_NOT_FOUND` | 7200, 7555–7575 |
| (ikke kaldt) `private.lock_family_rows` | person → familier → medlemmer; kommentar: blokerer `red_slet_person` | 18910–18926 |
| (ikke gatet) S12 kandidat-FK, S24 legacy-publikation uden event (teoretisk) | — | — |

## Punkt 6 — Storage (Supabase)

- Én **privat** bucket `media` (db-rls.sql 405–439). Ingen bucket eller sti pr. person: stien er
  indholdsadresseret `redaktor/<sha[0:2]>/<sha>-{thumb,medium,large}.jpg`
  (`web/src/data/mediaPaths.ts:7–13`, `mobile/src/lib/mediaPaths.ts:8`); bulk-import (`import_media.R`)
  kan bruge andre stier — sandheden er altid `media.storage_path` + `media_variant.storage_path`.
- Fra pid: `relation` (P ↔ `media`, især `rolle='afbildet'`, subjekt=person) → `media.id` →
  `(media.bucket, media.storage_path)` + `media_variant.storage_path` (samme bucket).
- Samme bytes kan kun registreres én gang (`media_sha256_uidx`, l. 93) → **et medie kan være delt**
  af flere personer/entiteter; kun eksklusive medier må slettes.
- Sletning af bytes er **klient-sidet efter commit** (`supabase.storage.from(bucket).remove(stier)`,
  `web/src/Redaktion.tsx:1710`; `red_udrens_media` returnerer stierne, l. 9081–9103). Policy
  `media_obj_delete` kræver rolle `redaktion`. Fejler remove, bliver objekterne forældreløse.
- Strandede uploads (`upload_status='kladde'`/`'fejlet'`) uden relation kan ikke kobles til pid.

## Punkt 7 — Hvad der IKKE bør slettes (ifølge koden)

| Sted | Begrundelse i koden |
|---|---|
| `private.source_record` (+ occurrence, observation, observation_text, mention, rendition, extraction_run) | l. 7225–7226: »private.source_record røres derimod ALDRIG: at teksten står på siden er stadig sandt«; l. 915: »Alle rå kilde-/hypoteserækker er uforanderlige«; append-only-triggere |
| `private.source_persona` (+ persona_mention, placements, interpretation, interpretation_party) | bogens personer som kilden beskriver dem; uafhængig af den kanoniske person; append-only |
| `source`, `lineage`, `slaegt`, `vocab`, `lineage_scheme*` | delte strukturer |
| Andre personers rækker (børn, ægtefæller), og familien hvis andre stadig er medlemmer | tilhører andre |
| Delte medier og andres stories/hændelser forankret i P | redaktionelt indhold overlever ankeret (kommentar l. 6479, 7230–7236) |
| `change_set`-rækker, der bærer andres events eller publication-events | append-only FK (S56) og andres fortryd |

**Konflikt med GDPR-målet:** `docs/decisions.md` (l. 3206–3210) siger selv, at »den reelle
eksponering ved en sletteanmodning ligger i `private.source_persona`/`source_record` — bogens egen
tekst — og den består uanset om person-rækken slettes hårdt«. `verbatim_text`, `interpretation.value`
og `import_korrektion.importeret` *er* indhold om personen. En fuld GDPR-sletning af en levende
person kan altså ikke opnås uden en beslutning om bog-laget.

---

## Søgt, intet fundet

- Abonnementer/tilmeldinger/notifikationer: ingen tabeller (`grep -i 'tilmeld|abonn|subscri|notif'` i `schema.sql`/`db-rls.sql`: 0 tabel-træf).
- Proposal-tabeller: ingen separat tabel; forslag er `private.interpretation` med `status='proposed'` (persona-niveau, bog-laget) og `public.suggestion` (S34).
- Cache/projektion: `person.visning_*` (ryger med rækken), `slaegtsnavn_karantaene` (S4), `text_mention` (S28/S29), `media_variant` (S37); ingen materialiserede views.
- Klient-tabeller (`.from(...)` i `web/src`, `mobile/src`, `packages`): alle findes i `schema.sql`; ingen ekstra person-tabeller.

## Spørgsmål og risici, koden ikke afgør

1. **Tombstone eller hard delete?** `docs/decisions.md` l. 3130–3216 anbefaler tombstone + udtømning,
   men »beslutningen er ikke truffet«. S10–S12, S23 og S39–S50 gør hard delete umulig uden at
   disable/omgå append-only-triggere. Er det overhovedet tilladt at ændre append-only-tabeller
   (fx via ejer-rolle og `ALTER TABLE … DISABLE TRIGGER`)? `db-verify.sql` kræver triggerne enabled.
2. **Hvor mange personer rammes af S12?** Kandidat-FK'en er ikke gatet; antal ukendt uden opslag.
   Ved en bypass med `session_replication_role=replica` (som db-verify's test-oprydning) slås også
   FK-kontrollen fra — så kan der efterlades rå dinglende FK'er. Kan Supabase-rollen overhovedet det?
3. **Bog-laget og GDPR:** skal en levende persons persona/observationstekst kunne fjernes/maskeres,
   og hvordan uden at bryde `source_record`-uforanderligheden og andre personers hashes?
4. **Historik-politik:** skal change_event-rækker slettes, maskeres (foer/efter → `{}`) eller
   erstattes af en tombstone-markør? Blandede sæt (S57) og publication-event-FK (S56) gør
   hel-sæt-sletning umulig; selektiv sletning gør `red_fortryd_change_set` delvis og kan
   genoplive data via resterende `foer`.
5. **Summary-tekster:** der er ingen struktureret kobling fra `red_opret_person`-sættets navn
   (subjekt NULL) til pid ud over change_event(INSERT person). Fritekst-heuristik kan give
   falske positive (andre tal) og falske negative (navne uden id).
6. **`[[person:pid|Navn]]` i andres prosa (S29):** skal teksten omskrives? Hvis narrativet er
   record-bundet/publiceret, kræver en ændring publication-events på den *anden* persons stream.
7. **Id-genbrug:** person-id er IDENTITY, men loaderne sætter eksplicitte id'er og synker
   sekvensen bagefter med `setval(… max(id)+1)` (`load_daa.R:1077`; `post_load_fixup.R:130` tager
   også `max(row_pk->>'id')` fra change_event med; cutover gør det samme for narrative, l. 14620–14640).
   `narrative` (l. 12648) og `change_set` (l. 9558) allokerer med `max(id)+1`. Slettes den højeste
   person/narrativ **og** dens historik, kan id'et blive genbrugt, og rester (S39–S46, S58) peger
   så på en ny række.
8. **Genimport:** reimport-/loader-stierne kan genskabe personen fra bogen (persona → person_create).
   Skal en slettet person blokeres permanent (tombstone-guard), og hvor?
9. **Kontraktversion:** `schema.sql` seeder `narrative_record_contract.version=1`; prod kører
   ifølge docs v2. Gates og writers opfører sig forskelligt — skal måles i prod.
10. **Familier (S38):** når P var eneste/en af to partnere — slettes familien og dens vielses-fakta
    (delt indhold med ægtefællen)? Hvad med børnenes `barn`-række i den familie?
11. **jsonb-ledgers (S41–S47, S50):** hvilke nøgler bærer person-id'er er kun delvist kortlagt;
    `count.sql` bruger en regex-heuristik på kendte nøgler.
12. **Klient-cache:** web/mobil (PWA, offline-data, `localStorage`-bogmærker) kan have personens
    data cachet; ikke dækket af DB-sletning.
13. **auth.users:** hvis personen er en levende bruger (`profiles.reventlow_person_id`), er
    brugerkontoen (`profiles.navn/email`, `change_set.actor_navn` frosset som tekst) et separat
    GDPR-spor.
14. **Supabase-backup/PITR og repo-dumps** (CLAUDE.md: »hold et dump i repo'et«) indeholder personen.
