# 149b legacy-migration: rehearsal-rapport

**Observeret:** 2026-09-04
**Kodegrundlag:** `feat/149-2018-20-fase-a` t.o.m. leverance 2b (commit `a2f3be2`)
**Resultat:** **GENNEMFØRT** — alle forventede tal og hashes ramt, ingen stopporte udløst

Dette er afgrænset, lokalt disponerbart bevis, **ikke en produktionsautorisation**.
Ingen produktionsdatabase, push, merge, deploy eller netværkshandling er brugt.
Kun `record_key`, tal, id'er og hashes; ingen persondata, ingen narrativtekst.
Runbook: [`legacy-migration-reimport-rehearsal.md`](../runbooks/legacy-migration-reimport-rehearsal.md).

## Basetabel

| Base | Rolle | Kontraktversion |
|---|---|---|
| `daa149b_inv_20260903` | skabelon — aldrig rørt gennem hele kørslen | v1 (aldrig migreret) |
| `daa149b_rehearsal_20260904` | arbejdsbase — 149a anvendt, derefter 149b | 1 → **2** (efter cutover) |

- `database_identity` = `{"database_name": "daa149b_rehearsal_20260904", "system_identifier": "7680906716015365850"}`.
- Aktør (rolle `redaktion`): id `cb751628-9b55-42bc-a743-4c76de87d647` (samme aktør genbrugt fra trin 1 til trin 2-3).
- 149a-batch (source-evidence, `finalized`): `16482e81-212d-4c30-8dc7-c562c16daf77`.
- 149b-batch (legacy-migration, `finalized`): `cf32ba22-8229-4c67-bcdd-097305d8bea8`.

## Låste inputhashes

| Artefakt | SHA-256 |
|---|---|
| Prod-dump `pre-c0f-20260821-112005.dump` | `fcfeb22532975d45803b98813e51bdde33b5a79537547b7ce202a28eaf7046b3` |
| Rendition `rendition.txt` (149a's, genbrugt som corpus) | `2dd5cf8408943ccc50ac4d89dcbd08ac3b49a90fdabd1ddcbd7b22d218026563` |
| Legacy-profil-fil `daa-2018-20-legacy-migration-v1.json` | `414189fc811372f2b9224835355b87f97cf127a75b36cebd8dd660fbcd59272e` |
| `profile_sha256` (Python = databaseberegnet) | `954f3bb361863af487ab08b6ad6ff972b319db2dd0b38e4031f0146e509d95b4` |
| `manifest_content_sha256` | `b4baa1aec784d483905e0cb6c0bbd74e4d74de7cc1ec69f76287279b1db0f211` |
| `manifest_bytes_sha256` | `662f16f37f0fc8e13acc10c465ea38fa1b77ddcecfdecb93e7424ce4ee43aa5b` |
| `preview_sha256` | `774efc5b9ebd37ae6514d5cfddc9d3435746634035f7c9316446a80fc91dceb9` |
| Autorisation (apply) | `26d4ff6a-edf8-4b5c-a9d2-e7eed082ac7e` |
| Autorisation (replay) | `b7d53d6d-c74b-4e15-90d5-c2eb5aa3ee93` |
| Batch (149b legacy-migration) | `cf32ba22-8229-4c67-bcdd-097305d8bea8` |
| Batch-reversal-dry-run `receipts_sha256` | `33c205ddf1142fd4c187c526dc6d4171f5c471f94ba0cd5941622871ab5ea8b9` |

Manifestet har 587 `legacy_migration`-operationer (`dependency_class =
legacy_migration` for alle), 591 `dispositions`. `expected_counts` (manifest,
4 nøgler før filtrering) = `{canonical_delta:0, legacy_migrations:587,
person_creates:0, source_evidence:0}`; previewets `expected_counts` (3 nøgler,
`canonical_delta` allerede fjernet) = `{legacy_migrations:587,
person_creates:0, source_evidence:0}`.

## Dispositioner og de fire `unresolved_text`-nøgler

| Disposition | Tal |
|---|---|
| `bound_published` | **541** |
| `bound_draft` | **46** |
| `unresolved_text` | **4** |
| `unresolved_identity` | **0** |

`unresolved_text`-nøgler: **`I-133`, `II-35`, `III-129`, `IV-94`** — samme fire
som spec §3's målte forudsætninger forudsagde (3 ikke-levende, 1 levende).
Stopgrænsen (10 % af 591 = 60) er ikke nået: 4/591 = 0,7 %.

Identiteten er injektiv for alle 591 (1 person pr. `record_key`, 1
`external_id` pr. person, 1 narrativ pr. person) — `unresolved_identity`
kan strukturelt ikke opstå for dette datasæt.

## Før/efter-tabeller

### Tal (source 1)

| Måling | Før | Efter |
|---|---|---|
| `source_persona` | 0 | **587** |
| accepterede identiteter (`authority='person_external_id'`) | 0 | **587** |
| bindinger `narrative_record_publication`, `published` | 0 | **541** |
| bindinger `narrative_record_publication`, `draft` | 0 | **46** |
| ledger `narrative_legacy_publication`, `migrated` | 0 | **541** |
| ledger `narrative_legacy_publication`, `grandfathered_publication` | 544 | **3** |
| ledger `narrative_legacy_publication`, `withdrawn` | 0 | **0** |
| `narrative_publication_event`, `draft_created` | 0 | **587** |
| `narrative_publication_event`, `published` | 0 | **541** |
| `narrative_publication_event`, `legacy_migrated` | 0 | **541** |
| `narrative_publication_event`, `baseline` | 544 | 544 (uændret) |
| `reimport_event`, `legacy_migration` | 0 | **587** |
| `reimport_event`, `source_evidence` (149a, uændret) | 591 | 591 |
| batches for source 1 | 1 | **2** |

### Hash-neutralitet pr. tabel

| Tabel | Før = efter? |
|---|---|
| `person` (superuser, aggregat) | **ja** |
| `fact` | **ja** |
| `family_member` | **ja** |
| `narrative` (aggregat) | **ja** |
| `narrative`-kerne `(id,tekst,privat,side)` for alle 591 | **ja** (591 rækker) |
| `narrative_record_publication` | **nej** (forventet — 587 nye bindinger) |
| `narrative_legacy_publication` | **nej** (forventet — 544 → 3 `grandfathered_publication`, 541 `migrated`) |
| `anon`: `assertion`, `citation`, `conclusion`, `fact`, `family_member`, `narrative`, `person`, `person_external_id` (8 tabeller) | **ja for alle 8** |

Kun de to private ledger-/binding-tabeller ændrer sig. Ingen anden tabel — hverken
den offentlige domænemodel eller `anon`-projektionerne — viser nogen kanonisk
delta.

### Offentlig flade (v1 + v2)

| Funktion | Før | Efter |
|---|---|---|
| `public_person_bio_source_versions_v2` — `legacy_narrative`, source 1 | 544 | **3** |
| `public_person_bio_source_versions_v2` — `source_record`, source 1 | 0 | **541** |
| `public_person_bio_source_versions` (v1-navn) — `legacy_narrative` | 544 | **3** |
| `public_person_bio_source_versions` (v1-navn) — `source_record` | 0 | **541** |
| v2-rækker for de 47 levende blandt de 591 | 0 | **0** |
| v1-rækker for de 47 levende blandt de 591 | 0 | **0** |

Hver bundet biografi (541 stk.) vises præcis én gang som `source_record`; de
tre fortsat-grandfathered (`I-133`, `II-35`, `III-129`) vises præcis én gang
som `legacy_narrative`; `IV-94` (levende, `unresolved_text`) vises som før
slet ikke.

### Redaktørflade

`red_person_narrative_records` (rolle `authenticated` + `request.jwt.claim.sub`):

- `I-1` (migreret): præcis én række, `provenance_kind='source_record'`,
  `publication_status='published'`, `eligibility_status='eligible'`, intet
  `blocking_reason`, autoritet `existing_exact_binding`. Ingen
  `grandfathered_legacy`-række.
- `I-133` (fortsat grandfathered): én række, `provenance_kind='grandfathered_legacy'`,
  `publication_status='published'`.
- Over alle 591: `source_record/published`=541, `source_record/draft`=46,
  `grandfathered_legacy/published`=3, `IV-94` giver ingen rækker (590 rækker i alt).

## Replay

Ny autorisation, samme manifest/preview, gentaget apply: `status="already_applied"`,
`committed=true`, ingen ny batch, alle tal og hashes byte-identiske med
efter-apply-billedet.

## Reversal

### Enkelt narrativ (`I-1`), i en transaktion der rulles tilbage

Sekvens: (a) `red_fortryd_person_narrative_publication_event(legacy_migrated)`
mens bindingen er aktiv → afvist `NARRATIVE_LEGACY_MIGRATION_BINDING_ACTIVE`;
(b) fortryd `published` → binding `draft`; (c) `red_kasser_person_narrative_record`
→ binding `withdrawn`; (d) fortryd `legacy_migrated` → ledger tilbage til
`grandfathered_publication`; gate `person_daa_narrative_publication_allowed`
→ `true` igen; offentlig flade for personen → 1 × `legacy_narrative`, 0 ×
`source_record`. `ROLLBACK` — efter-billedet er byte-identisk med
efter-apply-billedet, så batchen forblev intakt til batch-dry-run.

### Batch-reversal — **kun dry-run**

`reverse_reimport_legacy_migration.R --batch-id cf32ba22-… --authorization
15c489fc-… --dry-run`: `mode=dry-run`, `reversed_elements=587` (alle
`element_ids` med præfiks `legacy-migration:`), `receipts_sha256 =
33c205ddf1142fd4c187c526dc6d4171f5c471f94ba0cd5941622871ab5ea8b9`,
`committed=false`. Efter dry-run: autorisationen stadig `issued`, ingen
`reversal`-events, tal/hashes uændrede. **`--apply` blev bevidst ikke kørt** —
basen skal persistere med batchen anvendt til 149b's videre arbejde. Den fulde
apply-reversal-vej er bevist **kun** i integrationstesten
(`tests/integration/test-reimport-legacy-migration.R`), ikke i denne rehearsal
— en gentagelse i rehearsal ville kræve en ny restore for at gentage apply.

**Batch-status og replay efter en `--apply`-fortrydelse** (ikke udført her, men
en fælde operatøren skal kende): batchen forbliver `finalized`, og den
autoritative markør for »fortrudt« er `private.reimport_event` med
`operation='reversal'` og `element_id='legacy-migration-reversal:<authorization_id>'`.
Kører man samme manifest igen bagefter, svarer gatewayen fortsat
`already_applied`, fordi `red_begin_reimport`'s replay-opslag filtrerer på
`status='finalized'` — `already_applied` er altså ikke bevis for, at data stadig
er anvendt. Adfærden er bevidst (`reversed` er reserveret til
`red_reverse_reimport`, og en statusændring ville lade manifestet åbne en ny
batch, der først dør på `LEGACY_MIGRATION_ALREADY_BOUND`) og er testet i
`tests/integration/test-reimport-legacy-migration.R` trin 7.

`red_reverse_reimport` kaldt som `authenticated`-aktøren afvises korrekt med
`REIMPORT_WRITER_REVERSAL_INVALID` (batchen er `finalized`, ikke `activated`,
intet `name_completion`-barn) — fail-closed-bevis, ikke gendannelsesbevis.

## Restpunkter

1. **De 4 `unresolved_text`-narrativer er ikke rettet.** `I-133`, `II-35`,
   `III-129` forbliver `grandfathered_publication`; `IV-94` forbliver ubundet.
   Tekstrettelse for 2018-20 er en separat, endnu utruffet beslutning (spec
   §2, »ikke i scope«).
2. **De 13 mulige `NOISE_RE`-prosalinjer er ikke rettet.** Fundet i
   [`2026-09-03-2018-20-fase-a-inventering.md`](../superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md)
   måling 8 (segmenteringens støjfilter fjerner ca. 100 linjer midt i poster,
   op til 13 kan være prosa). Rapporteres, rettes ikke af 149b.
3. **Valg A (identitet uden placement-kæde) og valg B (reversal-designet)
   afventer projektejerens eksplicitte kvittering før prod-GO** — begge er
   PM-rollens egne valg (spec §5, §8; `docs/decisions.md` 2026-09-03/04).
4. **Batch-reversalens `--apply` er kun bevist syntetisk**, ikke mod denne
   rehearsal-base (se ovenfor).
5. **Deferred minors fra reviewrunderne** (M-1 til M-7 for Task 5, samt
   flerdelte fund for Task 6/7) står i
   `.superpowers/sdd/2026-09-03-2018-20-fase-b-legacy-migration/progress.md` —
   ingen af dem er blokerende for dette rehearsal-bevis, og ingen er rettet
   af leverance 3.
6. **Neutralitetstællingen** (`withdrawn` binding ∧ `grandfathered_publication`
   ledger) blev målt til **0** på denne base (før 149b-apply, som forventet —
   se `STEP1-REPORT.md` punkt 1 under »Ekstra målinger«) og skal genmåles i
   prod før 149b-apply dér (runbookens §7).

## Kodegrundlag og udførelse

- Task 10 trin 1 (restore → migrationer → #152-cutover → 149a-apply):
  udført af en Claude-subagent 2026-09-04, ingen fejl, ingen afvigelser.
- Task 10 trin 2-3 (149b: eksport → manifest → preview → dry-run →
  autorisation → apply → verifikation → replay → reversal): en tidligere
  agent-session tabte forbindelsen efter kun at have genbrugt (og rettet) en
  efterladt `state.sql`-forespørgsel; gendispatchet og gennemført uden andre
  afvigelser end de i §6 (runbook) noterede fælder.
- Ingen repo-filer ændret under rehearsal, intet committet, ingen
  prod-/Supabase-forbindelse.
