# Slettegraf for `red_slet_person_helt` (P = person-id)

Grundlag: `schema.sql` i worktree `.worktrees/personsletning` (identisk med `main` for `schema.sql`, `db-migrations.sql`,
`db-rls.sql`, `db-verify.sql`), spec `docs/superpowers/specs/2026-11-14-fuld-personsletning-design.md` §5-§6,
kortlægningen `purge/kortlaegning.md` (S1-S58) og `purge/count.sql`. Kun statisk læsning, ingen DB. Alle linjenumre er
`schema.sql`, kontrolleret med `sed -n`, medmindre andet står.

Kort om, hvad dokumentet siger (hverdagssprog):

- Sletningen kan lade sig gøre i én transaktion, hvis den følger en fast rækkefølge (fase 0-14 nedenfor), og hvis
  append-only-vagterne får en tilladelse pr. række via manifestet.
- Tre ting i specen holder ikke helt, som de står: (1) regel (c) for `change_set` overser sæt uden `change_event`
  (tilbagetrækning af et legacy-narrativ med fritekst-begrundelse), (2) låserækkefølgen i §6.12 tager kildelåsen
  til sidst, mens alle andre skrivere tager den først, og (3) delte reimport-autorisationer gemmer hele
  element-payloaden, så personens navn og narrativtekst står i en række, der også gælder andre (KONFLIKT).
- Tre KONFLIKT-rækker (K1-K3) og ét hul i specens change_set-regel (K4) kræver projektejerens afgørelse (afsnit 7).

---

## Afgørelser 2026-11-14 — gælder FORAN tabellerne nedenfor

Linjenumre er `schema.sql` på `main` `c41f67db` (skemafilerne er identiske med `af9c7abe`, som kortlægningen brugte).
Hvor et afsnit nedenfor siger noget andet, gælder dette afsnit.

**Projektejerens svar på §7:**

- **Q1 → S44a bevares.** `reimport_authorization.authorized_elements` røres ikke. Navn og tekst i elementet er bogtekst
  og en kopi af bogens lag, som bevares. Kvitteringens hash og revisionsspor forbliver intakte. K1 er lukket som
  tilladt rest.
- **Q2 → K2 bevares.** Linkteksten i andres narrativhistorik og publiceringstilstande bevares (spec §6.11 står ved
  magt). Beslutning 3 er præciseret: indhold om personens egen profil slettes, mens bogtekst i andres biografier
  bevares.
- **Q3 → advarsel, ingen blokering.** Forhåndsvisningen viser hver kørsel, der ikke længere kan fortrydes. Det gælder
  alle fortrydelsesveje: `red_reverse_reimport` (l. 5933), `red_reverse_1939_v50_reimport` (l. 6283),
  `red_reverse_reimport_cases` (l. 13288) og `red_reverse_reimport_publication` (l. 18672). Bygherren afgør pr. vej,
  hvornår en kørsel med P's rækker stadig kan fortrydes, og viser kun dem i advarslen.
- **Q4 → advarsel.** Er en `passed` kontrolkørsel kildens gældende, og indeholder dens population P, vises det.
- **Q5 → §4.2's præcisering er godkendt.** Det **retter §3.2** for `interpretation_promotion`. Triggertjekket (grund
  `egen`) er: målet findes og hører til P (person P, `F`, `A` på `F`/`R`, `R`, `N` for P, `H`). Kun for **familiemål**
  (`Fam_del`, `F_fam`, `R_fam` og Q6-bindinger) kræves desuden `interpretation.source_persona_id ∈ X`.
- **Q6 → S39c deles.** Kommer en promotion med `target_type='family' AND target_id ∈ Fam_keep` fra P's egen persona
  (`interpretation.source_persona_id ∈ X`), **slettes** den. Den nye mængde hedder `Prom_egen_fam`. Afhængige
  `relation_reopen`/`text_revision_reconciliation` slettes først (fase 2a/2b). Andres bindinger bevares (`id`/hash).
  Bygherren undersøger og tester, hvad `relation_binding_state` (l. 20004) og familiebekræftelsen gør, når en bevaret
  families binding forsvinder. Forventet: bindingen bliver forældet og kan genåbnes ad det eksisterende spor; det
  giver ingen fejl. Gør den noget andet, stopper bygherren og forelægger.
- **Q7 → `person_purge`-eventet får version n+1**, hvor n = `max(version)` for personaen. n aflæses i fase 0 og gemmes
  i manifestets række (`source_persona_identity`, x, grund `hel_stroem`, `forrige_version` = n). Det **retter §3.1
  punkt 3**:
  - Kernen kaldes med `expected_version` 0, fordi state er slettet, men skriver version n+1.
  - Undtagelsen i `validate_source_persona_identity_event` (l. 1859) gælder kun, når manifestets kvittering for
    (x, n) findes i denne transaktion og backend.
  - Indholds-uuid'et bliver (x, n+1). Det er nyt, så gamle henvisninger til version 1..n fejler synligt.
  - Test: en `passed` kontrolkørsel med x i stikprøven giver `failed` ved næste evaluering. Det er forventet og vises
    som Q4-advarslen.
- **Q8 → K3 på kontrollisten.** Titlen på et delt medie, der nævner P, rettes ikke. Den kommer med i `til_kontrol`.
- **Q9 → forhåndsvisningen får `til_kontrol`.** Listen viser fritekster, der er markeret `fritekst?` i tabellerne:
  - noter i `Y`-events (S11c, §3.3)
  - S34b
  - S37b
  - S38b/K5 (vielsestekst)
  - S44b
  - `parent_event.note` (S45b)
  - S49c
  - S58
  En tekst kommer med, når den indeholder P's id, P's visningsnavn eller et af `Fam`-id'erne. Listen blokerer ikke.
- **Q10 → bekræftet.** `import_korrektion`, der i dag er bundet til en anden person, bevares.
- **Q11 → backlog.** Engangsoprydning af historik-kopier efter de 26 personer, der er slettet tidligere med
  `red_slet_person`. Den får sit eget preview og ligger uden for denne bygning.

**Rettelser fra målinger (prod-kopi 13/11, kun tal):**

- **§4.4 punkt 2 er præciseret.** En `finalized` name_completion-batch blokerer kun, hvis dens **forældrebatch**
  stadig er `finalized`, altså ikke aktiveret. Efter aktivering skal barnet stå `finalized` for altid
  (`red_reverse_reimport` l. 5945-5946). Uden præciseringen kunne de 8 personer fra kørslen 18/8 aldrig slettes.
- **§4.4 punkt 3:** kun `issued` med `expires_at > now()`. I dag findes én udløbet `issued`, og den blokerer ikke.
- **Målt antal personer pr. regel i dag:**
  - §4.3 `aaben_koersel`: 0. Begge kontrolkørsler er `sealed>passed`.
  - §4.4 batches: 0. Ingen er `open`. Ingen `finalized` reimport har `person_create`. Én B-batch med 553
    `publication_identity`, så ingen har en eneste C-hændelse.
  - §4.5: 0.
  - §4.6 `samme_som_knudepunkt`: 33 personer (beslutning 8).
  - 1.150 personer har reimport-rækker. 1791 har ingen.

**Efter planreview v2 (2026-11-14):** L8 i §6.2 er `SHARE ROW EXCLUSIVE`, ikke ROW EXCLUSIVE. Fejlkoden
`PERSON_PURGE_LOCKSET_DRIFT` hedder `PURGE_LOCKSET_DRIFT`. `forrige_version` står kun på state-rækkens manifestpost,
og `hel_stroem`-tjekket bruger `OLD.version <= forrige_version` og »ingen version > forrige_version«, ikke
`max(version)` (planens Task 5).

**Historikkens `foer`/`efter`:** `count.sql` bruger `coalesce(efter,foer)` på nogle tabeller og mangler `feed_pin`-
formaterne fra NY-B. S46-regexen rammer aldrig (kandidat-uuid'er). Alle tre rettes, før `count.sql` bruges som
uafhængig måler (plan Task 1).

---

## 0. Notation og id-mængder (beregnes i fase 0, FØR noget slettes)

Alle mængder beregnes efter låsene (afsnit 6) og indgår i forhåndsvisningens hash. `Pt = P::text`.

| Navn | Definition |
|---|---|
| `X` | personas med `private.source_persona_identity.canonical_person_id = P` (nuværende afgørelse accepted → P; tabellen l. 1637) |
| `Y` | personas ∉ `X` med mindst én `private.source_persona_identity_event.canonical_person_id = P` (l. 1669) |
| `F` | `fact` med `subjekt_type='person' AND subjekt_id=P` (l. 3723) |
| `Fam` | `family_id` fra `family_member WHERE person_id=P` (l. 3704) |
| `Fam_del` | `f ∈ Fam` hvor resten (`person_id<>P`) har højst én `rolle='partner'` og ingen andre roller (spec §6.4) |
| `Fam_keep` | `Fam \ Fam_del` |
| `F_fam` | `fact` med `subjekt_type='family' AND subjekt_id ∈ Fam_del` |
| `R` | `relation` med `(subjekt_type='person' AND subjekt_id=P) OR (objekt_type='person' AND objekt_id=P)` (l. 3737), plus relationer med en fact-ende i `F` (S19) |
| `R_fam` | `relation` med en ende `('family', f∈Fam_del)` eller `('fact', x∈F_fam)` |
| `M_del` | medie-id'er i `R`, hvor ALLE relationer til mediet er i `R ∪ R_fam`, og ingen `fact/story/narrative/note/suggestion/entity_description` har mediet som subjekt/target, og ingen `text_mention(maal_type='media')` peger på det |
| `Fd`, `Rd` | `F ∪ F_fam`, `R ∪ R_fam` |
| `A` | `assertion` med `(target_type,target_id) ∈ ({fact}×Fd ∪ {relation}×Rd)` (l. 3757) |
| `N` | `narrative` med `(subjekt_type,subjekt_id) ∈ {('person',P)} ∪ ({family}×Fam_del)` (l. 3819) |
| `H` | `haendelse` med `narrative_id ∈ N` (CASCADE) ∪ `(subjekt_type='person' AND subjekt_id=P)` ∪ `(subjekt_type='family' AND subjekt_id ∈ Fam_del)` (l. 6431) |
| `S` | `story` med subjekt `('person',P)` eller `('family',f∈Fam_del)` (l. 6475) |
| `ED` | `entity_description` med `subjekt_type='person' AND subjekt_id=P` (l. 11942) |
| `Prom_egen` | `interpretation_promotion` med mål i de slettede rækker (person P, `Fd`, `A`, `Rd`, `N`, `H`, `Fam_del`) og ejet af P (se afsnit 4.2) |
| `Prom_anden` | samme mål, men ikke ejet af P → blokering |
| `PEI*` | `(source_id, record_key)` for P's `person_external_id`, levende + historiske fra `change_event(tabel='person_external_id', row_pk->>'person_id'=Pt)`, minus nøgler der i dag er bundet til en anden person |

---

## 1. Sted-tabel

Handlinger: **slet** · **nulstil** (kolonne) · **loesn** (kolonne → NULL på en andens række) · **bevar_andres** (fælles
række, røres ikke) · **blokér** (sletningen afvises). Fase = sletteorden (afsnit 1.1). "Vagt" = trigger der beskytter
tabellen, og om den afviser DELETE (AO = append-only DELETE-afvisning).

Kolonnen **Indhold** udfyldes kun for bevar_andres: `id` = kun P's id/hash/uuid; `INDHOLD` = navn/tekst/datoer om P
→ **KONFLIKT** (spec-beslutning 3); `fritekst?` = menneskeskrevet tekst, der ikke kan bevises ren statisk (afsnit 7).

### 1a. Kerne og hårde FK'er

| Sted | Tabel | Find ud fra P | Handling | Fase | Vagt (navn, linje) | Indhold |
|---|---|---|---|---|---|---|
| S1 | `public.person` | `id=P` | slet | 11 | `trg_log_person` (log_change, loop l. 9401-9409; registry l. 9158) — logger kun med åbent sæt; ingen AO | |
| S2 | `public.person_external_id` | `person_id=P` (PEI* aflæses i fase 0 før sletning) | slet | 10 | `trg_external_id_regen` l. 6669 (regen), `trg_log_person_external_id` | |
| S3 | `public.family_member` | `person_id=P`; **plus** alle rækker med `family_id ∈ Fam_del` | slet | 10 | `trg_partner_loft` l. 8278 (kun INS/UPD), EXCLUDE `family_member_en_foedselsfamilie` l. 3718 deferrable, `trg_log_family_member` | |
| S4 | `public.slaegtsnavn_karantaene` | `person_id=P` | slet | 10 | ingen | |
| S5 | `public.profiles` | `reventlow_person_id=P` | **nulstil** `reventlow_person_id` | 10 | `trg_log_profiles` (skip `email`,`rolle`, l. 9184) | |
| S6 | `public.bookmark` | `person_id=P` | slet (eksplicit, ikke via CASCADE, så det står i manifest/preview) | 4 | ingen | |
| S7 | `public.person_slaegt_membership` | `person_id=P` | slet | 10 | `trg_log_person_slaegt_membership` | |
| S8 | `public.person_lineage_membership` | `person_id=P` | slet | 10 | `trg_log_person_lineage_membership` | |
| S9 | `private.person_create_receipt` | `person_id=P` | slet (CASCADE; i praksis tom uden for den oprettende transaktion, kvitteringen forbruges l. 10475-10476) | 11 | ingen | |
| S10 | `private.source_persona_identity` | `source_persona_id ∈ X` | slet, derefter ny række v1 `rejected` via `decide_source_persona_identity(...,'person_purge')` (afsnit 3) | 2l + 2m | `trg_source_persona_identity_state_validate` l. 1961 (INS/UPD; ejer-krav for ikke-`proposed`); `identity_state_has_event` l. 1964 deferred INS/UPD/DEL; **ingen AO** | |
| S11a | `private.source_persona_identity_event` | `source_persona_id ∈ X` (hele strømmen) | slet | 2k | `trg_source_persona_identity_event_append_only` (loop l. 1973-1987, CREATE l. 1983-1984) → `reject_evidence_mutation` l. 916 **AO**; `…_validate` l. 1958 (INS); `identity_event_is_projected` l. 1968 deferred INS | |
| S11b | samme | `source_persona_id ∈ Y AND canonical_person_id=P` (spec §6.10) | slet | 2k | samme **AO** | |
| S11c | samme (andres) | `source_persona_id ∉ X AND evidence->'same_individual_person_ids' @> to_jsonb(P)` (skrives l. 11331) | bevar_andres | – | **AO** | id |
| S12 | `private.source_persona_identity_candidate` | `candidate_person_id=P` | slet (FK NOT NULL l. 1728) | 2j | `trg_source_persona_identity_candidate_append_only` (loop l. 1742-1751, CREATE l. 1747) → l. 916 **AO**; truncate l. 1749 | |

### 1b. Kerne-evidens (offentlige tabeller)

| Sted | Tabel | Find ud fra P | Handling | Fase | Vagt | Indhold |
|---|---|---|---|---|---|---|
| S13 | `public.fact` | `id ∈ F` | slet | 8 | `trg_log_fact`; FK fra `haendelse.fact_id` (l. 6447, NO ACTION) og `story.fact_id` (l. 6481, SET NULL) | |
| S13b NY | `public.fact` (familie) | `id ∈ F_fam` | slet | 8 | samme | |
| S14 | `public.relation` | `id ∈ R` | slet | 8 | `trg_relation_evidence_delete` l. 7413 → `guard_relation_evidence_delete` l. 7394 (afviser DELETE mens assertion/conclusion/note peger på den); `trg_log_relation` | |
| S14b NY | `public.relation` (familie-/familiefakta-ende) | `id ∈ R_fam` | slet | 8 | samme | |
| S15 | `public.assertion` | `id ∈ A` | slet | 6 | `trg_assertion_relation_target` l. 7381 (INS/UPD), `trg_assertion_regen` l. 6653 (UPD), `trg_log_assertion` | |
| S16 | `public.conclusion` | `(target_type,target_id) ∈ Fd∪Rd` | slet (før assertion: `valgt_assertion_id` FK l. 3776) | 6 | `trg_conclusion_regen` l. 6636, `trg_conclusion_relation_target` l. 7384, `trg_log_conclusion` | |
| S17 | `public.citation` | `assertion_id ∈ A` | slet (før assertion, FK l. 3792) | 6 | `trg_log_citation` | |
| S18 | `public.note` | `(target_type,target_id) ∈ {('person',P)} ∪ fact×Fd ∪ relation×Rd ∪ family×Fam_del` | slet | 6 | `trg_mentions_note` l. 9679 (rydder `text_mention` for kilden), `trg_note_relation_target` l. 7387, `trg_log_note` | |
| S19 | `public.relation` med fact-ende | `(subjekt_type='fact' AND subjekt_id ∈ F) OR (objekt_type='fact' AND objekt_id ∈ F)` — er med i `R` | slet | 8 | som S14 | |
| S20 | `public.assertion` på en ANDENS fakta med værdien P | `objekt_type='person' AND objekt_id=P AND id ∉ A` (v1 skriver kun `family`, l. 8075/8445) | **blokér** (defensivt: kan være `valgt_assertion_id` i en andens konklusion) | 0 | – | |
| NY-A | `public.assertion` på en andens fakta med værdien en familie, der slettes | `objekt_type='family' AND objekt_id ∈ Fam_del AND id ∉ A` (forældrefamilie-påstand, l. 8075/8445) | **blokér** | 0 | – | |

### 1c. Narrativ, publicering, formidling

| Sted | Tabel | Find ud fra P | Handling | Fase | Vagt | Indhold |
|---|---|---|---|---|---|---|
| S21 | `public.narrative` | `id ∈ N` | slet | 7 | `trg_mentions_narrative` l. 9676, `trg_log_narrative`; FK fra `narrative_record_publication` (l. 3833), `npe` (l. 13891), `nlp` (l. 13820) — alle NO ACTION | |
| S22 | `private.narrative_record_publication` | `narrative_id ∈ N` | slet | 3d | `trg_narrative_record_publication_validate` l. 3853 (kun INS/UPD); ingen AO | |
| S23 | `private.narrative_publication_event` | `narrative_id ∈ N` | slet (pr. stream i faldende `stream_version`, eller ét DELETE — FK'erne er NO ACTION og tjekkes ved statement-slut) | 3b | `trg_narrative_publication_event_append_only` l. 14060 → `reject_narrative_publication_event_mutation` l. 13997 **AO**; `…_validate` l. 14057 (INS) | |
| S23b | `npe.before_state/after_state` og `nlp.baseline_state` for ANDRES narrativer | `narrative_id ∉ N` og `…->'authority'->'identities'` indeholder `canonical_person_id=P` (kun principal/co_principal, l. 14975-14998) | bevar_andres | – | **AO** | id (`canonical_person_id`, `identity_version`, persona-uuid). Tilstanden indeholder også ANDENS narrativtekst (`'text'`, l. 15066); står `[[person:P|Navn]]` i den, er det INDHOLD → se K2 |
| S24 | `private.narrative_legacy_publication` | `narrative_id ∈ N` | først **nulstil** `latest_event_id` (fase 3a), så slet (3c) | 3a/3c | `trg_narrative_legacy_publication_validate` l. 14063 (kun INS/UPD). **Validatoren tillader allerede** `latest_event_id := NULL` (tjekker kun ikke-NULL, l. 14035) → ingen triggerændring nødvendig; DELETE har ingen vagt | |
| S25 | `public.haendelse` under P's narrativer | `narrative_id ∈ N` | slet (CASCADE l. 6435) | 7 | `trg_log_haendelse` (skip_cols l. 9169: kun `id`+`feed_status` logges) | |
| S26 | `public.haendelse` med P som subjekt under en andens narrativ | `subjekt_type='person' AND subjekt_id=P AND narrative_id ∉ N` | slet | 5 | samme | |
| S27 | andres `haendelse` forankret i slettede fakta/relationer | `id ∉ H AND (fact_id ∈ Fd OR relation_id ∈ Rd)` | **loesn** `fact_id`/`relation_id` (som i dag, l. 7237-7238) | 5 | skip_cols → intet logges | |
| S28 | `public.text_mention` med kilde i slettet prosa | `(kilde_type='narrative' AND kilde_id ∈ N) OR (kilde_type='note' AND kilde_id ∈ note_del)` | slet (automatisk via `trg_regen_mentions` l. 9663, triggere l. 9676/9679) | 6/7 | – | |
| S29 | `public.text_mention` og prosa hos andre med token til P | se afsnit 4.1 | **blokér** | 0 | – | |
| S30 | `public.story` + `story_kilde` | `id ∈ S` | slet (`story_kilde` CASCADE l. 6510) | 4 | `trg_log_story`, `trg_log_story_kilde` | |
| S31 | andres `story` forankret i slettede rækker | `id ∉ S AND (fact_id ∈ Fd OR relation_id ∈ Rd OR haendelse_id ∈ H)` | **loesn** (automatisk `ON DELETE SET NULL`, l. 6480-6482) | 5-8 | intet logges (intet åbent sæt) | |
| S32 | `public.feed_pin` | `kort_noegle ~ '^(portrait|citat|naevnt|dagensperson):P$'` ∪ `'^(jubilaeum|embede):P:'` ∪ `'^slaegt:P:[0-9]+$'` ∪ `'^slaegt:[0-9]+:P$'` ∪ `'arkiv:'||h` og `'paadennedag:h:'||h` for `h ∈ H` ∪ `'story:'||s` for `s ∈ S` ∪ `'forbundet:'||f` for `f ∈ Fam_del` | slet | 4 | `trg_log_feed_pin` | |
| NY-B | (del af S32) | nøgleformaterne `story:`, `paadennedag:h:`, `dagensperson:` mangler i kortlægningen og `count.sql` (kilde: `packages/feed/src/story.ts:108`, `temporal.ts:100,130`) | slet | 4 | | |
| S32c | `feed_pin 'forbundet:'||f` for `f ∈ Fam_keep` | | bevar_andres | – | `trg_log_feed_pin` | id (familie-id) |
| S33 | `public.entity_description` + `private.entity_description_source` | `id ∈ ED` | slet (`…_source` CASCADE l. 11961) | 4 | `trg_entity_description_subject` l. 11981 (INS/UPD), `trg_log_entity_description` l. 11989 | |
| S34 | `public.suggestion` | `subjekt_type='person' AND subjekt_id=P` ∪ `subjekt_type='family' AND subjekt_id ∈ Fam_del` | slet | 4 | ingen (ikke versioneret). `interpretation_forslag_binding` (l. 10073) sidder på `private.interpretation` (AFTER INSERT), ikke på `suggestion` | |
| S34b | andres `suggestion`, hvor `payload`/`vaerdi`/`note`/`kilde_fritekst` nævner P | `subjekt ≠ P` og `payload::text`/tekst indeholder P's id eller token | **blokér** ved token (afsnit 4.1); ellers bevar_andres | 0 | – | fritekst? |

### 1d. Rettelsesjournaler, medier, familier

| Sted | Tabel | Find ud fra P | Handling | Fase | Vagt | Indhold |
|---|---|---|---|---|---|---|
| S35 | `public.import_korrektion` | `(import_key, record_key) ∈ {(s.import_key, rk) : (s.id, rk) ∈ PEI*}` | slet | 6 | `trg_log_import_korrektion`; ingen FK (l. 156-158) | |
| S36 | `public.paastand_korrektion` | `assertion_id ∈ A*` (levende + historiske assertions, afsnit 2) | slet (FK `change_set_id` l. 10095 → skal væk før change_set) | 6 | **ingen trigger** (kun kommentar l. 10081-10086) | |
| S37 | `public.media` + `media_variant` | `id ∈ M_del` | slet (`media_variant` CASCADE l. 103); stier til udbakke (§6.7) | 9 | `trg_log_media` | |
| S37b | delte medier | relation P↔medie slettes (i `R`), mediet bevares | bevar_andres | – | | `titel`/`original_filnavn` kan nævne P → fritekst? |
| S38 | `public.family` | `id ∈ Fam_del` | slet | 10 | `trg_log_family` | |
| S38b | `family` i `Fam_keep` + dens vielsesfakta, evidens, noter, narrativer | | bevar_andres (beslutning 7) | – | | vielsens `citation.citat_tekst`/`assertion.vaerdi_tekst` er bogtekst, der kan nævne P → se K5 |

### 1e. Private ledgers

| Sted | Tabel | Find ud fra P | Handling | Fase | Vagt | Indhold |
|---|---|---|---|---|---|---|
| S39a | `private.interpretation_promotion` | `id ∈ Prom_egen` | slet | 2c | `trg_interpretation_promotion_append_only` (loop l. 1973-1987) → l. 916 **AO**; `…_validate` l. 1955 (INS) | |
| S39b | samme | `id ∈ Prom_anden` | **blokér** (afsnit 4.2) | 0 | **AO** | |
| S39c | familiebindinger på `Fam_keep` | `target_type='family' AND target_id ∈ Fam_keep` | bevar_andres (hash bliver forældet, V5) | – | **AO** | id (hash, familie-id) — se også spørgsmål Q6 |
| S40 | `private.legacy_placement_disposition` | `person_id=P` | slet | 2i | `trg_legacy_placement_disposition_append_only` l. 2809 → l. 916 **AO** | |
| S41a | `private.reimport_event` | `canonical_person_id=P` (ops `person_create` l. 4376, `legacy_migration` l. 4556, `canonical_delta` l. 5902, `publication_persona` l. 18344, `publication_identity` l. 18550, `relation_person_create` l. 20807) | slet (person_create-payload bærer `name` og `narrative.text`) | 2g | `trg_reimport_event_append_only` l. 4072 → `reject_reimport_writer_mutation` l. 4063 **AO**; `trg_reimport_event_publication_identity_finalized` l. 18661 er deferred, men kun `AFTER INSERT` → rammer ikke DELETE | |
| S41b | `reimport_event` uden P som kolonne, med P i payload | `operation='activation'` → `payload->'post_activation_receipts' ? Pt` (l. 6170); `publication_identity` med `payload->>'same_as_hint_person_id'=Pt` (nøglen l. 18402) | bevar_andres | – | **AO** | id (+ record_key + hashes) |
| S42 | `private.reimport_name_completion_result` | `person_id=P` | slet | 2f | `trg_reimport_name_completion_result_append_only` l. 4073 → l. 4063 **AO** | |
| S43a | `private.reimport_case_event` | `action='record_assign' AND payload->>'target_person_id'=Pt` (l. 12971-12980) | slet | 2h | `trg_reimport_case_event_append_only` l. 9300 → `reject_reimport_case_event_mutation` l. 9297 **AO** | |
| S43b | samme | `action='identity_different' AND payload->'person_ids' @> to_jsonb(P)` (par P/Q, l. 12916-12922) | bevar_andres | – | **AO** | id |
| S44a | `private.reimport_authorization.authorized_elements` | element-nøgler hvis payload er P's element (`authorized_elements->element_id = p_payload`, l. 4233-4234/4409) | bevar_andres (fælles batch-række) | – | **ingen trigger** (status opdateres l. 5966) | **INDHOLD → KONFLIKT K1**: `person-create:`-elementet indeholder `name` (krævet l. 4354) og `narrative.text` (l. 4375); name_completion-autorisationen har `payloads.<element>.name` (l. 5740/5894/5902) |
| S44b | `private.reimport_case_authorization.authorized_elements` | C3-elementer med P | bevar_andres | – | ingen trigger | fritekst? (`before_state`-form ikke statisk afgjort) |
| S45a | `private.identity_control_parent_card` | `counterpart_person_id=P` | slet | 2e | loop l. 19455-19468 (CREATE l. 19461) → l. 916 **AO** | |
| M5 | `private.identity_control_parent_event` | `card_id ∈ S45a` | slet | 2d | samme loop **AO** | |
| S45b | `identity_control_parent_card` | `P = ANY(partner_ids) AND counterpart_person_id<>P` | bevar_andres | – | **AO** | id; tilhørende `parent_event.note` er fritekst? |
| S46 | `private.identity_control_sample` | `mapping`/`expected` er **kandidat-uuid'er**, ikke person-id (l. 19748-19760); P findes via `candidate.id WHERE candidate_person_id=P`. `count.sql`'s regex rammer aldrig | bevar_andres (dinglende kandidat-uuid efter S12) | – | **AO** | id (ikke engang P's id) |
| S47 | `candidate.basis`, `identity(_event).evidence` | P's egne rækker følger S10-S12; andres: se S11c | se S10-S12/S11c | | **AO** | |
| S48 | hashes over familierækker (`relation_binding_state` l. 20004; `relation_classification_event.state_sha256` l. 20137; `candidate.family_context_sha256` l. 1734) | familie-id'er i `Fam` | bevar_andres (bliver forældede) | – | **AO** (`trg_relation_classification_event_append_only` l. 20148) | id/hash |
| S49a | `private.relation_reopen` | `superseded_promotion_id ∈ Prom_egen` (FK l. 20267) | slet | 2b | `trg_relation_reopen_append_only` l. 20281 → l. 916 **AO** | |
| S49b | `private.text_revision_reconciliation` | `old_promotion_id ∈ Prom_egen OR new_promotion_id ∈ Prom_egen OR (revision_batch_id,revision_element_id) ∈ S41a` (FK l. 21382/21385/21390) | slet | 2a | `trg_text_revision_reconciliation_append_only` l. 21403 → l. 916 **AO** | |
| S49c | `private.marriage_ordinal_correction` | `family_id ∈ Fam` | bevar_andres (fortolkningsniveau, bogens lag) | – | `trg_marriage_ordinal_correction_append_only` l. 1426 **AO** | id (familie-id); `evidence` fritekst? |
| S49d | `relation_reopen` med `from/to_family_id ∈ Fam_del`, men promotion ikke i `Prom_egen` | | følger S39b (blokeres) | | | |
| S50 | `private.narrative_record_cutover_receipt.result` | `record_events[].narrative_id ∈ N` (l. 14552-14556) | bevar_andres | – | `trg_narrative_record_cutover_receipt_append_only` l. 17417 → l. 17408 **AO** | id (narrativ-/event-uuid, ikke P's person-id) |
| S51 | `private.identity_relation_update_prelock` | transient, ryddes ved COMMIT (l. 7548) | – (intet at gøre) | – | | |
| S58 | øvrige jsonb (`interpretation.value/decision_evidence`, `relation_reopen.context`, `relation_classification_event.evidence`, `source_*_placement_decision.evidence`, …) | bogens lag eller fortolkningsniveau; P's egne rækker er dækket ovenfor | bevar_andres | – | **AO** | fritekst? (ikke statisk afgjort; se Q9) |
| NY-C | `private.identity_control_exclusion` | `source_persona_id ∈ X` | bevar_andres (bogens persona, intet P-id) | – | **AO** | intet |
| NY-D | `private.relation_persona_profile` (l. 17932) | ingen person-reference (tjekket) | – | – | | |

### 1f. Historik

| Sted | Tabel | Find ud fra P | Handling | Fase | Vagt | Indhold |
|---|---|---|---|---|---|---|
| S54 | `public.change_event` | lukningen `E` (afsnit 2) | slet | 12 | **ingen trigger**; FK `change_set_id` l. 9312 | |
| S57 | `change_event` i berørte sæt, uden for `E` | | bevar_andres | – | | id (andres rækker); undtagelse K2 (andres narrativ-/notetekst med `[[person:P|Navn]]`) |
| S52/S53/S55 | `public.change_set` | regel i afsnit 2.3 | slet (mængden `D`) | 13 | self-FK `reverterer_id` l. 9205 (NO ACTION) | |
| S52b | sæt med subjekt P, som stadig har andres events | | bevar_andres | – | | id (`subjekt_id=P`, summary med id'er — M1). Undtagelse: K3 |
| S56 | indgående FK til sæt: `npe.change_set_id` l. 13887, `paastand_korrektion.change_set_id` l. 10095, `reimport_case_batch.change_set_id` l. 9265 | | P's npe/paastand_korrektion slettes før; `reimport_case_batch` bevares altid (→ sættet bevares) | 3b/6 | | |

### 1.1 Faseplan (sletteorden, lavest først)

FK-pile: `A → B` = A peger på B, så A slettes før B.

| Fase | Hvad | Hvorfor her |
|---|---|---|
| 0 | Låse (afsnit 6), rollegate, id-mængder, blokeringer, preview-hash sammenlignet | ingen skrivning før hash er godkendt |
| 1 | `private.person_purge_manifest` skrives (alle rækker i fase 2-13, med `grund`) | triggerne læser den |
| 2a | `text_revision_reconciliation` | `→ interpretation_promotion` (l. 21382/21385), `→ reimport_event` (l. 21390) |
| 2b | `relation_reopen` | `→ interpretation_promotion` (l. 20267) |
| 2c | `interpretation_promotion` (Prom_egen) | mål skal stadig findes, så triggeren kan efterprøve ejerskabet (afsnit 3.2) |
| 2d | `identity_control_parent_event` | `→ parent_card` (l. 19444) |
| 2e | `identity_control_parent_card` | |
| 2f | `reimport_name_completion_result` | ingen FK ind; før person |
| 2g | `reimport_event` | efter 2a |
| 2h | `reimport_case_event` | |
| 2i | `legacy_placement_disposition` | |
| 2j | `source_persona_identity_candidate` | `→ person` (l. 1728) |
| 2k | `source_persona_identity_event` (S11a, S11b) | `→ person` (l. 1672); S11a skal slettes, MENS state-rækken stadig peger på P (triggerens tjek) |
| 2l | `source_persona_identity` for `X` | `→ person` (l. 1639); `identity_state_has_event` er deferred og ser først resultatet ved COMMIT |
| 2m | `decide_source_persona_identity(x, NULL, 0, 'rejected', {"reason":"not_a_person"}, 'person_purge')` for hver `x ∈ X` | skriver event v1 + state v1, så de deferred triggere (l. 1964/1968) er glade ved COMMIT |
| 3a | `UPDATE nlp SET latest_event_id=NULL` for `narrative_id ∈ N` | bryder cirklen `nlp.latest_event_id → npe` (l. 13905) / `npe.legacy_publication_ref → nlp` (l. 13898) |
| 3b | `narrative_publication_event` (`narrative_id ∈ N`) | `→ narrative_record_publication` (l. 13889), `→ nlp` (l. 13898), self `reversed_event_id` (l. 13900), `→ change_set` (l. 13887) |
| 3c | `narrative_legacy_publication` | `→ narrative` (l. 13820) |
| 3d | `narrative_record_publication` | `→ narrative` (l. 3833) |
| 4 | `feed_pin`, `bookmark`, `suggestion`, `entity_description` (+source CASCADE), `story` (+`story_kilde` CASCADE) | `story.haendelse_id/fact_id/relation_id` er SET NULL, så rækkefølgen er fri, men P's egne stories først undgår unødige SET NULL |
| 5 | `haendelse` S26 + `subjekt_type='family' AND subjekt_id ∈ Fam_del`; derefter `UPDATE haendelse SET fact_id/relation_id = NULL` (S27) | `haendelse.fact_id/relation_id → fact/relation` NO ACTION (l. 6447-6448) |
| 6 | `citation` → `conclusion` → `assertion`; `paastand_korrektion`; `import_korrektion`; `note` | `citation.assertion_id`, `conclusion.valgt_assertion_id → assertion`; noter skal væk før relation (vagt l. 7394) |
| 7 | `narrative` (`N`) | `haendelse` CASCADE; efter 3b-3d |
| 8 | `relation` (`Rd`), derefter `fact` (`Fd`) | relationer med fact-ende peger polymorft på fakta; evidensvagt l. 7394 kræver fase 6 først |
| 9 | `media` (`M_del`, `media_variant` CASCADE); stier i udbakken | relationer til mediet er væk i fase 8 |
| 10 | `profiles` (nulstil), `person_external_id`, `family_member` (P's + resten af `Fam_del`), `family` (`Fam_del`), `person_slaegt_membership`, `person_lineage_membership`, og SIDST `slaegtsnavn_karantaene` | alle `→ person`/`→ family`. Underordenen er bærende: `trg_external_id_regen` (l. 6669) og `trg_conclusion_regen` (l. 6636) fyrer ved DELETE og kører `regen_person_visning(P)`, som kan upserte `slaegtsnavn_karantaene` for P (kommentar l. 3655-3657). Karantænen skal derfor slettes efter de sidste regen-udløsere (fase 6 og `person_external_id`), som i `red_slet_person` (pei l. 7240, karantæne l. 7246) |
| 11 | `person` (`person_create_receipt`, `bookmark` CASCADE, tomme her) | sidste række med FK-mål |
| 12 | `change_event` i `E` | `→ change_set` (l. 9312) |
| 13 | `change_set` i `D`: fortryd-sæt dybest først, så originaler (eller ét DELETE: NO ACTION tjekkes ved statement-slut) | `reverterer_id` self-FK; FK fra npe/paastand_korrektion er væk efter 3b/6 |
| 14 | manifest tømmes; kontrol-tælling = 0; retur | |

Bemærk: `red_slet_person` (l. 7156-7252) sletter i rækkefølgen citation → conclusion → assertion → note →
narrative_record_publication → narrative → haendelse-loesn → relation → fact → external_id → family_member → … → person.
Faseplanen ovenfor er den samme for kernen og lægger ledgers (fase 2-3) og historik (12-13) rundt om den.

---

## 2. Historiklukningen (spec §6.3a)

### 2.1 Princip

Et `change_event` slettes, hvis (1) det handler om en række, der slettes nu, ELLER (2) dets `foer` eller `efter`
(hver for sig, ikke `coalesce(efter,foer)`) bærer P's indhold. Regel (2) er nødvendig, fordi rækker, der er slettet
tidligere (fx en relation, der blev fjernet i 2026-08), kun findes her, og fordi en række kan have skiftet ejer (en
`UPDATE` af `target_id`, `fix_240_saml.sql` flytter noter). `count.sql` bruger `coalesce(efter,foer)` for
assertion/conclusion/citation/note/story_kilde/feed_pin/import_korrektion og misser derfor en `UPDATE`, hvor nøglen
flyttede væk fra P.

For en række, der **bevares** (en andens), slettes kun de events, hvis `foer`/`efter` bærer P's indhold, ikke alle
events med samme `row_pk`.

### 2.2 Historiske id-mængder (fikspunkt)

Alle sammenligninger som tekst (`->>`), fordi `profiles.id` er uuid. `ce` = `public.change_event`. For hver tabel
gælder prædikatet `p(x)` på `x ∈ {ce.foer, ce.efter}` (NULL tæller ikke).

```
F*  = F ∪ F_fam
      ∪ { ce.row_pk->>'id' | ce.tabel='fact' AND p_fact(x) },
      p_fact(x)      := x->>'subjekt_type'='person' AND x->>'subjekt_id'=Pt
R*  = Rd
      ∪ { ce.row_pk->>'id' | ce.tabel='relation' AND p_rel(x) },
      p_rel(x)       := (x->>'subjekt_type'='person' AND x->>'subjekt_id'=Pt)
                     OR (x->>'objekt_type' ='person' AND x->>'objekt_id' =Pt)
                     OR (x->>'subjekt_type'='fact'   AND x->>'subjekt_id' ∈ F*)
                     OR (x->>'objekt_type' ='fact'   AND x->>'objekt_id'  ∈ F*)
A*  = A ∪ { ce.row_pk->>'id' | ce.tabel='assertion' AND p_ass(x) },
      p_ass(x)       := (x->>'target_type'='fact' AND x->>'target_id' ∈ F*)
                     OR (x->>'target_type'='relation' AND x->>'target_id' ∈ R*)
N*  = N ∪ { ce.row_pk->>'id' | ce.tabel='narrative' AND x->>'subjekt_type'='person' AND x->>'subjekt_id'=Pt }
S*  = S ∪ { ce.row_pk->>'id' | ce.tabel='story' AND x->>'subjekt_type'='person' AND x->>'subjekt_id'=Pt }
H*  = H (kun levende; skip_cols l. 9169 fjerner subjekt/narrativ, så historiske hændelser kan ikke kobles — de
      bærer kun id+feed_status, intet indhold)
M*  = M_del ∪ { medie-id i x for ce.tabel='relation' AND p_rel(x) AND x->>'objekt_type'='media'
                 AND mediet findes ikke længere AND ingen anden (historisk) relation fra en anden end P }
PEI*= se afsnit 0
```

`F*` og `R*` afhænger af hinanden kun via S19 (fact-ende); løs dem som rekursiv CTE eller to omgange (F* først, så
R*). Dybden er 1.

### 2.3 Event-mængden `E`

`ce ∈ E`, hvis én af disse gælder:

| `ce.tabel` | Prædikat |
|---|---|
| `person` | `row_pk->>'id'=Pt` |
| `person_external_id`, `family_member`, `person_slaegt_membership`, `person_lineage_membership` | `row_pk->>'person_id'=Pt` |
| `family_member` (resten af slettede familier) | `row_pk->>'family_id' ∈ Fam_del` |
| `family` | `row_pk->>'id' ∈ Fam_del` |
| `profiles` | `foer->>'reventlow_person_id'=Pt OR efter->>'reventlow_person_id'=Pt` (rækken er brugerens, men `navn` er P's navn, når brugeren er P) |
| `fact` | `row_pk->>'id' ∈ Fd` OR `p_fact(foer)` OR `p_fact(efter)` |
| `relation` | `row_pk->>'id' ∈ Rd` OR `p_rel(foer)` OR `p_rel(efter)` |
| `assertion` | `row_pk->>'id' ∈ A` OR `p_ass(foer)` OR `p_ass(efter)` |
| `conclusion` | `target ∈ F*∪R*` i `foer` eller `efter` (samme form som `p_ass`) |
| `citation` | `foer->>'assertion_id' ∈ A*` OR `efter->>'assertion_id' ∈ A*` |
| `note` | for `x ∈ {foer,efter}`: `(target_type,target_id) ∈ {('person',Pt)} ∪ fact×F* ∪ relation×R* ∪ family×Fam_del` |
| `narrative` | `row_pk->>'id' ∈ N` OR subjekt person P i `foer`/`efter` |
| `haendelse` | `row_pk->>'id' ∈ H*` |
| `story` | `row_pk->>'id' ∈ S` OR subjekt person P i `foer`/`efter` |
| `story_kilde` | `foer->>'story_id' ∈ S*` OR `efter->>'story_id' ∈ S*` |
| `entity_description` | `row_pk->>'id' ∈ ED` OR subjekt person P i `foer`/`efter` |
| `feed_pin` | `foer->>'kort_noegle'` eller `efter->>'kort_noegle'` matcher S32-mønstrene med `H*`, `S*`, `Fam_del` |
| `import_korrektion` | `(x->>'import_key', x->>'record_key') ∈ PEI*`-nøglerne for `x ∈ {foer,efter}` |
| `media` | `row_pk->>'id' ∈ M*` |
| øvrige (`source`, `place`, `estate`, `organisation`, `lineage`, `slaegt`, `vocab`, …) | ingen P-sti |

Transitivt: `A*` dækker også påstande, der kun findes i historikken (deres `citation`-events findes via
`assertion_id ∈ A*`). En `citation` uden kendt assertion (fordi assertion-eventet mangler) kan ikke kobles — det
sker kun, hvis assertion blev indsat uden åbent sæt (bulk-load), og så har citationen heller intet event.

**Ikke i `E`, bevidst:** andres narrativ-/note-events med `[[person:P|…]]` i teksten (spec §6.11) → K2.
`haendelse`-events for P's tidligere hændelser (kun `id`+`feed_status`, intet indhold, kan ikke kobles).

### 2.4 Hvilke `change_set` slettes (rettet regel)

Specens regel (c) »havde events, der blev slettet nu« overser sæt **uden** `change_event`. Det findes:
`private.withdraw_legacy_narrative` (l. 16322) åbner et sæt med summary `'Tilbagetrak legacy-narrativ %s: %s'` hvor
`%s` er **fritekst** `p_reason` (l. 16397-16401), subjekt `('person', P)`, og skriver kun en
`narrative_publication_event` (l. 16427) og en `UPDATE` på `narrative_legacy_publication`, som ikke er versioneret.
Efter fase 3b har sættet hverken events eller FK, men regel (c) er falsk → det overlever med P som subjekt og en
mulig navnetekst. Det samme gælder `reverse_narrative_publication_event`-sæt (l. 16645-16649), hvis de kun skriver
publiceringsrækker.

Rettet regel. Lad `D0` = sæt hvor mindst én gælder:

1. sættet havde ≥ 1 event i `E`;
2. `subjekt_type='person' AND subjekt_id=P AND reverterer_id IS NULL`;
3. sættet havde en indgående `narrative_publication_event` eller `paastand_korrektion`, som slettes nu.

`reverterer_id IS NULL` i punkt 2 er nødvendig: `red_fortryd_change_set` kopierer originalens subjekt
(l. 9559-9572). Et fortryd-sæt for et BEVARET sæt med subjekt P (fx `red_opret_union` med den anden partners
events tilbage) har ingen events og ingen FK og ville ellers blive slettet. Så forsvinder vagten »allerede fortrudt«
(l. 9531-9533), og det bevarede sæt kunne fortrydes igen (spec §6.3a sidste punkt, §8-testen). Fortryd-sæt kommer
derfor KUN med via `Frev`.

`C = { cs ∈ D0 : ingen events tilbage efter fase 12 AND ingen npe/paastand_korrektion/reimport_case_batch peger på cs }`.
`Frev = alle sæt f, hvor f.reverterer_id ∈ C ∪ Frev` (rekursivt; fortryd-sæt har aldrig events, fordi
`red_fortryd_change_set` nulstiller `app.change_set_id` før de inverse skrivninger, l. 9556, og afviser sæt med npe,
l. 9500-9527).
`D = C ∪ Frev`. Et sæt i `D0 \ C` bevares (med andres events; summary kun med id'er = M1).

Sletteorden: `Frev` i faldende kæde-dybde, så `C`. Fortryd-sæt for bevarede sæt røres ikke (deres summary er
`'Fortrød: '` + det bevarede sæts summary, l. 9564/9572, og bærer intet nyt).

---

## 3. Identitetsstrømme

### 3.1 P's egne personas (`X`, spec §6.9)

For hver `x ∈ X`:

1. Slet **alle** `source_persona_identity_event` for `x` (alle versioner, også `canonical_person_id` NULL eller en
   anden person — fx et tidligere `accepted → Q`, eller `unresolved` med `evidence.deceased.clause_years`).
2. Slet state-rækken `source_persona_identity(x)`. Der er ingen AO-trigger på state-tabellen; kun den deferred
   `identity_state_has_event` (l. 1964), som ved COMMIT kræver state = seneste event.
3. Kald `private.decide_source_persona_identity(x, NULL, 0, 'rejected', '{"reason":"not_a_person"}', 'person_purge')`.
   Kernen (l. 10404) tager selv `source_persona FOR UPDATE` (l. 10440) og state `FOR UPDATE` (l. 10450), regner
   version 0 (state slettet) og skriver event v1 + state v1. `validate_source_persona_identity_event` (l. 1859, trigger l. 1958)
   kræver `max(version)+1 = 1` → derfor SKAL alle events være væk først.
   Ny gren i kernen: `p_origin='person_purge'` kræver `p_decision_status='rejected'`, `p_expected_version=0`,
   `p_evidence = '{"reason":"not_a_person"}'` (præcis), og at manifestet for denne transaktion indeholder
   `('source_persona_identity', x, 'hel_stroem')` — så ingen anden kalder kan bruge oprindelsen.

Konsekvens at kende: event-id er indholdsafledt af `(persona, version)` (l. 10548). Det nye v1-event får **samme
uuid** som det slettede v1-event, og `version=1` betyder nu noget andet end i alle kvitteringer, der nævner
`identity_version` (andres npe-tilstande S23b, `identity_control_sample.identity_version`,
`relation_reopen.spouse_identity_version`). Ingen kode slår event-uuid'er op andre steder (grep:
kun l. 10548/10554). Se Q7.

### 3.2 Hvordan triggeren kan godkende sletningen (manifest-»grund«)

Manifestet `private.person_purge_manifest(xid8, backend_pid, person_id, tabel, raekke_pk, grund)`. Triggeren slår
`(pg_current_xact_id(), pg_backend_pid(), TG_TABLE_NAME, pk)` op og efterprøver uafhængigt efter `grund`:

| Tabel | grund | Uafhængigt tjek i triggeren (på `OLD`) |
|---|---|---|
| `source_persona_identity_event` | `egen` / `andres_ref` | `OLD.canonical_person_id = m.person_id` |
| `source_persona_identity_event` | `hel_stroem` | `EXISTS (SELECT 1 FROM source_persona_identity i WHERE i.source_persona_id=OLD.source_persona_id AND i.decision_status='accepted' AND i.canonical_person_id=m.person_id)` — virker kun, fordi events slettes før state (fase 2k før 2l) |
| `source_persona_identity_candidate` | `egen` | `OLD.candidate_person_id = m.person_id` |
| `legacy_placement_disposition`, `reimport_name_completion_result` | `egen` | `OLD.person_id = m.person_id` |
| `reimport_event` | `egen` | `OLD.canonical_person_id = m.person_id` |
| `reimport_case_event` | `egen` | `OLD.action='record_assign' AND OLD.payload->>'target_person_id' = m.person_id::text` |
| `interpretation_promotion` | `egen` | målet findes stadig (fase 2c før 6-11) og hører til P: `person=P`, eller `fact.subjekt=P`, `relation` med P-ende, `narrative.subjekt=P`, `assertion` på sådan fakta/relation, `haendelse.subjekt=P`/under P's narrativ, eller `family` med P som medlem; plus `interpretation.source_persona_id ∈ X` |
| `relation_reopen`, `text_revision_reconciliation` | `afledt` | den refererede promotion (eller reimport_event) står selv i manifestet |
| `identity_control_parent_card` | `egen` | `OLD.counterpart_person_id = m.person_id` |
| `identity_control_parent_event` | `afledt` | `OLD.card_id` står i manifestet som parent_card |
| `narrative_publication_event` | `egen` | `narrative.subjekt_type='person' AND subjekt_id=m.person_id` for `OLD.narrative_id` (narrativet findes til fase 7) |

`reject_evidence_mutation` (l. 916) deles af bogens tabeller og ledgers; tilladelseslisten skal derfor være på
`TG_TABLE_NAME` og standard-afvise. Bogens tabeller (loop l. 1101-1121, `vocab`/`clause_disposition` l. 1125-1135,
`interpretation`, `interpretation_observation`, `interpretation_party` l. 1400, placements l. 2680-2691,
`identity_control_run/sample/event/exclusion`) må aldrig stå på listen. `reject_reimport_writer_mutation` (l. 4063),
`reject_reimport_case_event_mutation` (l. 9297) og `reject_narrative_publication_event_mutation` (l. 13997) er
separate funktioner og skal have samme mønster. `reimport_writer_profile` og `narrative_record_cutover_receipt` skal
ikke kunne slettes.

### 3.3 Andre personas, der peger på P (spec §6.10)

- `Y`: events med `canonical_person_id=P` slettes (grund `andres_ref`). Strømmen får et hul; `red_source_persona_history`
  (l. 11178-11191) er en ren liste og tåler det. Nabo-events kan bære fritekst om P (`evidence.note` på et senere
  `different`) → Q9.
- Andres events med P i `evidence.same_individual_person_ids` (dubletreglen, l. 11331) eller `candidate_id` på en
  af P's kandidatrækker: bevares (kun id/uuid). `control_run_status` (l. 19617-19618) læser listen og tåler P's id.
- Hvis `Y`-eventet, der slettes, er netop `identity_version+1` for en persona i en kontrolkørsels stikprøve, giver
  `control_run_status` derefter `failed/afvigelse` (l. 19610-19612) → blokering i afsnit 4.3.

### 3.4 `identity_control_parent_card`

Kortet tilhører fortolkningen (`interpretation_key` for et `relation.parent`-forslag på et barns record; kortene udvælges l. 19706-19714 og skrives l. 19730-19733),
ikke en person. `counterpart_person_id` er den strukturelle modpart, `partner_ids` er familiens partnere ved
registreringen.

- `counterpart_person_id = P`: kortet handler om P som forælder → slet kort + events (M5).
- `P ∈ partner_ids`, modpart en anden: kortet handler om modparten → bevar (kun id i arrayet).
- `family_id ∈ Fam_del`: familie-id dingler; kun id.
- `parent_event.note` (tabel l. 19443-19454, skrevet l. 19555) er fritekst fra arket og kan nævne P → Q9.

### 3.5 Kandidatkørsler og kontrolkørsler

- **Kandidatkørsel** (`candidate_run`) har ingen status; den er uforanderlig og atomisk (`red_record_identity_candidates`
  l. 11451, eksklusiv kildelås l. 11470). »Åben kandidatkørsel« findes ikke som tilstand. Efter sletning af P's
  kandidatrækker passer `candidates_sha256`/`candidate_count` ikke (M2), og ranglisten for en persona kan mangle
  rang 1; køens `best_tier` (l. 11045-11048) bliver NULL. Ingen kode genberegner hashen.
- **Stikprøvens mapping** (l. 11272-11276): `red_afgoer_source_persona` slår kandidaten op via
  `mapping->>display_position`. Er kandidaten slettet, bliver `v_cand` tom, `v_person` NULL, og `same` fejler med
  `EVIDENCE_IDENTITY_DECISION_INVALID` (l. 11349). En forseglet kørsel kan så ikke afsluttes for den persona.
- **Kontrolkørslens status** beregnes (`control_run_status` l. 19581-19634), den gemmes ikke. Seneste `failed` er terminal; `passed` er
  IKKE terminal: `red_evaluate_identity_control_run` (l. 19808) og `red_corroborate_family_identities` (l. 19948)
  genberegner, og `control_input_list_sha256` (l. 19486) ændres, når P forsvinder fra `red_match_personer` →
  `failed/kandidatinput_aendret`. Følgen: en `passed` kørsel, der stadig er kildens gældende, kan ikke længere
  bruges til familiebekræftelse efter sletningen. Se afsnit 4.3 og Q4.

---

## 4. Blokeringer (spec §6.6) — præcise betingelser

Alle tjek kører i fase 0 efter låsene, og resultatet indgår i preview-hashen.

### 4.1 `link_i_tekst`

Mål `T = {('person',P)} ∪ {('family',f) : f ∈ Fam_del} ∪ {('media',m) : m ∈ M_del}` (`parse_mentions` l. 9629 kender
også `family` og `media`; et link til en familie eller et medie, der slettes, bliver også dødt → NY).

Blokér, hvis `EXISTS (SELECT 1 FROM parse_mentions(kol) m WHERE (m.maal_type, m.maal_id) ∈ T)` for en række, der
**ikke** slettes, i én af:

| Kolonne | Række bevares når |
|---|---|
| `narrative.tekst` | `id ∉ N` (hurtig sti: `text_mention` l. 9640 for narrative/note) |
| `note.indhold` | note ikke slettes |
| `story.titel`, `story.tekst` | `id ∉ S` |
| `entity_description.tekst` | `id ∉ ED` |
| `haendelse.klausul` | `id ∉ H` (afledt af narrativet, men lagret) |
| `suggestion.vaerdi`, `.note`, `.kilde_fritekst`, `.payload::text` | ikke slettet |
| `citation.citat_tekst`, `assertion.vaerdi_tekst`, `assertion.date_raw` | ikke i `A`/citation-sletningen |
| `media.titel` | medie bevares |

Andres `change_event`, `npe.after_state->…->'text'` og `nlp.baseline_state` scannes ikke (specens §6.11) → K2.

### 4.2 `anden_promotion`

En promotion `p` med mål i de slettede rækker er **P's egen**, hvis `interpretation.source_persona_id ∈ X` for
`p.interpretation_id`. Ellers `anden`. Præcisering: for mål i P's egne rækker (person P, `F`, `A` på `F/R`, `R`,
`N` for P, `H`) er promotionen altid P's, selv om fortolkningen sidder på en andens record (fx en person oprettet af
`relation_person_create` fra en forælders post, l. 20686-20810) — ellers kan sådan en person aldrig slettes.
`anden_promotion` blokerer kun for mål i `Fam_del`, `F_fam`, `R_fam` (familiens fakta/relationer), hvor
fortolkningens principal-persona ikke er i `X` (fx en ægtefælles `relation.marriage`, l. 20519-20523). Se Q5.

### 4.3 `aaben_koersel` (kontrolkørsel)

For hver kildes kontrolkørsel `r`, hvor seneste `identity_control_event.status` er NULL (uforseglet) eller `'sealed'`
(l. 19412-19424), blokér hvis én gælder:

- en stikprøve i `r` har `source_persona_id ∈ X ∪ Y`;
- en stikprøves `mapping`-værdi eller `expected` er id på en kandidatrække med `candidate_person_id=P`;
- `identity_control_exclusion(r)` har en persona i `X`;
- et forældrekort i `r` har `counterpart_person_id=P`, `P = ANY(partner_ids)` eller `family_id ∈ Fam`;
- `r.candidate_run_id` har en kandidatrække med `candidate_person_id=P` (populationen ændres → kørslen fejler).

`passed`: blokér ikke, men vis i forhåndsvisningen, at kørslen bliver `failed` ved næste evaluering, hvis den er
kildens gældende (Q4).

### 4.4 Reimport-, C3- og publiceringsbatches

Blokér, hvis én gælder for en kilde `s ∈ sources(P)` (afsnit 6):

- `private.reimport_batch` med `status='open'` (l. 3960) for kilden;
- `private.reimport_batch` med `status='finalized'`, der indeholder P's `person_create`-hændelse (endnu ikke
  aktiveret): `red_activate_reimport_batch` (l. 6146-6171) kræver, at antallet af `name_completion_result` =
  `expected_counts` og at hver `person_create` har sin `canonical_delta` (l. 6159). Slettes P's rækker, kan batchen
  aldrig aktiveres, og ingen af de andre personer i den bliver frigivet (`staged=false`, l. 6160). Det samme gælder
  den tilhørende name_completion-batch (`finalized`, l. 5737);
- `private.reimport_authorization` med `status='issued' AND expires_at > now()` for kilden;
- `private.reimport_case_batch` med `status='open'` eller `reimport_case_authorization` med `status='issued'`;
- **NY:** sletning af P's `publication_identity`-event (S41a) ville fjerne den eneste C-hændelse for en B-batch
  (`payload->>'persona_batch_id'`): `persona_awaiting_control` (l. 10641-10661) kræver blot ÉN C-hændelse pr. B-batch,
  så andre personas i B-batchen ville igen stå som »venter på kontrol« og forsvinde fra køen.

Bemærk: Fuldførte batches (`finalized`/`activated`) blokerer ikke, men efter sletningen kan de ikke længere fortrydes:
`red_reverse_reimport` (l. 5933-5966) kræver, at antal `canonical_delta` og `name_completion_result` = `expected_counts`;
`red_reverse_reimport_cases` (l. 13288) har tilsvarende tællinger. Fail-closed, men det gælder hele batchen (Q3).

### 4.5 `persona_awaiting_control`

Blokér, hvis `private.persona_awaiting_control(x)` er sand for et `x ∈ X ∪ Y`. For `x ∈ X` er den i praksis altid
falsk (en accepteret, ikke-fortrudt identitet → `false`, l. 10650-10652); tjekket er robusthed, ikke en reel sti.

### 4.6 `samme_som_knudepunkt`

`nabo(P) = { q : relation rolle='samme_som', subjekt_type='person', objekt_type='person', og (subjekt_id=P, objekt_id=q) eller (subjekt_id=q, objekt_id=P) }`.
Blokér, hvis `count(DISTINCT q) ≥ 2`. Grafen er en skov (én sink pr. komponent, `enforce_samme_som_invariants`,
trigger l. 7769), så enhver knude med grad ≥ 2 deler komponenten. Grad 1: kanten slettes med evidens (den er i `R`).
`ikke_samme_som` med P slettes også (i `R`); dens par i `reimport_case_event` (S43b) bevares.

### 4.7 Øvrige

- S20 og NY-A (afsnit 1b): en andens påstand, hvis værdi er P eller en familie, der slettes.
- Fremmed aktivt `change_set` (spec §6.1, som l. 3312/4428).

---

## 5. Summaries med navn

### 5.1 Fejning

`grep -c 'begin_change_set(' schema.sql` = 63 linjer: 1 definition (l. 9339), 61 kald, 1 kommentar (l. 8367). Derudover: direkte `INSERT INTO change_set` i `red_fortryd_change_set` (l. 9559/9567) og cutover
(l. 14509); `UPDATE change_set SET summary` kun i fortryd (l. 9617). `begin_change_set` er frataget `authenticated`
(`db-rls.sql` l. 996-998), så summary kun formes af serverfunktioner og scripts. `db-migrations.sql` har samme
operationer og formater (eneste afvigelse: ældre `red_upsert_narrativ` uden kilde-id; kun id'er). Scripts uden for
skemaet (`R/update-1939-narratives.R:232`, `R/update-2018-narratives.R:227`, `.claude/skills/daa-extract/scripts/*`)
bruger faste tekster eller id'er/tællinger.

| Gruppe | Operationer (linje) | Summary-form | Kan bære navn/indhold? | Hvordan sættet findes |
|---|---|---|---|---|
| Kun id'er/faste ord | `red_set_koen` 6985, `red_set_privat` 6994, `red_tilfoej_oplysning` 6772, `red_set_konklusion` 6830, `red_edit_oplysning` 6856, `red_slet_oplysning` 6908, `red_tilbagetraek_fakta` 6951, `red_set_haendelse_status` 7009, `red_opret_story` 7029, `red_rediger_story` 7056, `red_set_story_status` 7079, `red_slet_story` 7093, `red_set_story_kilder` 7108, `red_slet_person` 7193, `red_upsert_narrativ` 7272, `red_relation` 7302, `red_slet_relation` 7354/7356, `red_slet_medierelation_uden_evidens` 7442, `red_samme_som` 7847, `red_fjern_samme_som` 7874, `red_ikke_samme_som` 7912, `red_fjern_ikke_samme_som` 7937, `red_publicer_personer` 7980, `red_tilfoej_relation` 7999, `red_opret_union` 8023, `red_set_familie_konfidens` 8040, `red_slet_familie_link` 8090, `red_tilfoej_barn` 8167, `red_tilfoej_partner` 8315, `red_set_familie_ordinal` 8357, `red_flyt_barn` 8376, `red_tilfoej_foraeldre_paastand` 8433, `red_vaelg_foraeldre` 8505, `red_bekraeft_media_upload` 8729, `red_opdater_media` 8783, `red_genopret_media` 8803, `red_set_media_rettigheder` 8819, `red_fjern_media` 8838, `red_erstat_media_fil` 8901, `red_udrens_media` 9086, `red_saet_portraet` 9122, `red_apply_reimport_cases` 12902, `placement_membership` 3329, `narrative_record_legacy_migrated` 4497, `narrative_record_*` 16126 (`decision_basis` er fast tekst, l. 16117-16125), `narrative_record_reversal` 16645, cutover 14509 | id'er, faktatype, rolle, status, record_key, nonce | Nej | via events/subjekt |
| Kort-nøgle | `red_set_feed_pin` 7131, `red_fjern_feed_pin` 7146 | `'Satte %s på kort %s'` | `embede:P:<embedstitel>:<år>` bærer P's embedstitel (indhold) | sættet indeholder kun pin-eventet → slettes via regel 1 |
| Faktatype | `red_upsert_fakta` 6730, `red_opret_fakta` 6802 | `'Opdaterede %s på %s/%s'` (faktatype, ikke værdi) | Nej | |
| OCR | `red_ret_ocr_felt` 2127 | `'OCR-%s: %s/%s'` (felt, import_key, record_key) | Nej | subjekt P |
| Påstand | `red_ret_paastand` 10314 | `'Paastand %s: %s'` med `p_grund` | Nej: `grund` er CHECK-låst til `bogen_har_ret`/`linjeskift-v1` (l. 10091-10092) | subjekt = fakta-subjekt; FK fra `paastand_korrektion` |
| **Navn** | `red_opret_person` 8641 | `'Oprettede person <p_navn>'`, subjekt NULL | **Ja, P's navn** | events: `person` INSERT (`row_pk.id=P`) + P's fakta/evidens via `red_upsert_fakta` (genbrugt sæt). Kun RPC-kald (ingen interne kaldere; `mobile/src/data/redaktionWrite.ts:340`), så sættet har kun P's events |
| **Entitetsnavn** | `red_opret_estate` 8664, `red_opret_kilde` 8675, `red_opret_organisation` 8686 | navn/titel på ejendom/kilde/organisation | ikke personnavn (kan i teorien være opkaldt efter P) | – |
| **Medietitel** | `red_opret_media` 8707, `red_upload_media` 8753 | `'Oprettede/Uploadede media <titel or original_filnavn>'`, subjekt `('media', NULL)` | **Måske** (fx »Portræt af …«) | events: `media` INSERT (+ `relation afbildet` ved `p_afbildet_person_id`, l. 8744) |
| **Fritekst** | `red_reverse_placement_membership` 3369 | `btrim(p_note)`, subjekt `('person',P)` | **Ja, fritekst** | events: P's membership-DELETEs → regel 1 og 2 |
| **Fritekst** | `withdraw_legacy_narrative` 16397 | `'Tilbagetrak legacy-narrativ %s: %s'` med `p_reason`, subjekt `('person',P)` (l. 16401) | **Ja, fritekst** | **ingen change_event**; kun npe (l. 16427) + `UPDATE nlp` (l. 16403/16437) → fanges KUN af rettet regel 2/3 |
| Fortryd | `red_fortryd_change_set` 9559/9567 + 9617 | `'Fortrød: '` + original summary (+ `' [%s divergenser tvunget]'`) | arver originalens | `reverterer_id` → `Frev` |

### 5.2 Konklusion

Summaries, der kan bære P's navn eller indhold: `red_opret_person`, dens `Fortrød:`-kopi, `red_set_feed_pin`/
`red_fjern_feed_pin` (embede-nøgle), `red_reverse_placement_membership` (fritekst), `withdraw_legacy_narrative`
(fritekst), og muligvis `red_opret_media`/`red_upload_media` (medietitel).

- Med **specens** regel fanges alle undtagen `withdraw_legacy_narrative` (ingen events → regel (c) falsk) og
  `red_*_media` for et **delt** medie (sættet bevarer medie-eventet).
- Med den **rettede** regel (afsnit 2.4) fanges også `withdraw_legacy_narrative` (subjekt = P, `reverterer_id`
  NULL). En `Fortrød:`-kopi fanges kun via `Frev`, dvs. kun når originalen slettes; det ændrer intet for
  navnesættene, fordi `red_opret_person`-sættet altid slettes helt. Tilbage står kun
  medietitlen for et delt medie (K3), og det er mediets egen tekst, som også står i `media.titel`.
- Sæt, der slettes helt, kan ikke efterlade summary. Sæt, der bevares (andres events tilbage), har kun id-formater
  (gruppe 1), bortset fra K3.

---

## 6. Låserækkefølge

### 6.1 Hvad de andre gør

| Skriver | Rækkefølge (linjer) |
|---|---|
| `red_afgoer_source_persona` (l. 11196) | kildelås **delt** `daa-identity-candidates:<source>` (l. 11239) → læser kandidater/stikprøve → `decide` |
| `decide_source_persona_identity` (l. 10404) | `source_persona FOR UPDATE` (l. 10440) → `source_persona_identity FOR UPDATE` (l. 10450) → `lock_family_rows(gammelt mål, nyt mål)` (l. 10458) = person → familie → medlemmer (l. 18910-18925) |
| `red_record_identity_candidates`, `red_register_identity_control_run`, `red_evaluate…`, `red_corroborate…`, `red_decide_relation_interpretations`, `red_genaabn…`, `red_promote_relation_interpretations_batch` | kildelås **eksklusiv** først (l. 11470, 19648, 19816, 19957, 20228, 20314, 20495), personer bagefter |
| `red_afgoer_relation_interpretation` (l. 19276) | kildelås **delt** (l. 19300) → personer (`lock_family_rows`) |
| Reimport-/publiceringsskrivere (fx `write_publication_identity` l. 18394) | kontrakt delt → `lock_reimport_writer(source, profile)` (l. 4154) → kildelås eksklusiv → … → `LOCK change_set IN ACCESS EXCLUSIVE` → person |
| Publiceringsskrivere (narrativ, l. 15223-15235, 16363, 16539, 4431) | `source_record FOR UPDATE` → `LOCK change_set IN ACCESS EXCLUSIVE` → `person FOR UPDATE` (»audit-before-person«) |
| `red_slet_person` (l. 7156) | kontrakt delt (l. 7163) → rolle → `samme_som_mutation` (l. 7177) → generation (l. 7178) → `begin_change_set` (ROW EXCLUSIVE på change_set) → source/external-id `FOR UPDATE` (l. 7197) → `lock_identity_people` (l. 7200) |
| `red_samme_som` (l. 7819) | `samme_som_mutation` → generation → `lock_identity_people` |
| `red_fortryd_change_set` (l. 9484) | kontrakt delt → `LOCK change_set ACCESS SHARE` (l. 9499) → evt. `samme_som_mutation` + generation → INSERT change_set → rækker |

Ingen funktion i `schema.sql` tager både `samme_som_mutation` og en kildelås, heller ikke via indlejrede kald (tjekket for alle 12 steder med `samme_som_mutation`, bl.a. `red_apply_reimport_cases` l. 12771 → `red_ikke_samme_som` l. 12913, `red_reverse_reimport_cases` l. 13400, triggeren `enforce_samme_som_invariants` l. 7716) og heller ikke i ceremoni-scripts (`identitet_ceremoni.sql:192`, `samme_som_kort_ceremoni.sql:145`). Alle funktioner med både `lock_reimport_writer` og kildelås tager skriverlåsen først (fx l. 17972→17975, 18414→18416, 20699→20700).

### 6.2 Forslag (afviger fra spec §6.12)

```
L1  pg_advisory_xact_lock_shared('daa-narrative-record-contract')         -- som l. 7163
L2  rollegate (auth.uid() NOT NULL, current_rolle()='redaktion'); afvis fremmed app.change_set_id
L3  læs sources(P) = kilder for person_external_id(P) ∪ personas X∪Y ∪ kandidatrækker for P ∪ kontrolkørsler med P
    og profiler = reimport_writer_profile for de kilder
L4  lock_reimport_writer(source, profile) for alle par, sorteret
L5  pg_advisory_xact_lock('daa-identity-candidates:'||source) — EKSKLUSIV, sorteret efter source-id
L6  source_persona FOR UPDATE (X∪Y, sorteret) → source_persona_identity FOR UPDATE (X∪Y, sorteret)
L7  pg_advisory_xact_lock(hashtext('samme_som_mutation')) → guard_identity_mutation_snapshot()
L8  LOCK TABLE public.change_set IN ROW EXCLUSIVE MODE
L9  source JOIN person_external_id WHERE person_id=P ... FOR UPDATE OF s,pei      -- som l. 7195-7199
L10 lock_identity_people(ARRAY[P] ∪ samme_som-nabo)                              -- fejler hvis P mangler
L11 lock_family_rows(ARRAY[P])                                                    -- person → familier → medlemmer
L12 genberegn sources/profiler; er mængden vokset → afvis (PERSON_PURGE_LOCKSET_DRIFT, prøv igen)
L13 genberegn forhåndsvisning; anden hash → afvis
```

Begrundelse for afvigelserne:

1. **Kildelåsen først (L5), ikke sidst.** Alle andre skrivere tager kildelåsen før person-/identitetsrækker. Spec
   §6.12 tager den efter `lock_family_rows`. Med en **eksklusiv** lås til sidst opstår cyklen: `red_afgoer_source_persona`
   holder kildelåsen delt og venter i `decide → lock_family_rows` på P's række, som sletningen holder, mens
   sletningen venter på kildelåsen → 40P01. Med låsen først venter afgøreren før den rører noget.
2. **Eksklusiv, ikke delt.** Delt ville tillade `red_afgoer_relation_interpretation` (delt, personer før identitet)
   og `red_afgoer_source_persona` (delt) samtidig. Den første låser personer og evt. derefter identitetsrækker;
   sletningen låser identitetsrækker før personer (L6 før L10) → mulig cyklus. Eksklusiv serialiserer sletningen mod
   alle kildebundne identitets-/relationsskrivere; prisen er, at køen for den kilde venter i de sekunder,
   sletningen tager.
3. **Identitetsrækker (L6) før personer (L10)** spejler `decide` (source_persona → identity → person).
4. **`change_set` ROW EXCLUSIVE (L8) før personer.** Sletningen åbner intet sæt, men sletter `change_set`-rækker i
   fase 13 og ville få tabellåsen EFTER personlåsene. En publiceringsskriver med `ACCESS EXCLUSIVE` på `change_set`,
   der venter på P's række, giver så en cyklus. Låsen tidligt følger kodebasens »audit-before-person«-orden
   (kommentar l. 15224-15228; `LOCK` l. 15228, `person FOR UPDATE` l. 15232). Den er forenelig med `red_fortryd`'s ACCESS SHARE og andre `begin_change_set` (ROW
   EXCLUSIVE). Bemærk: de frosne R-scripts tager `SHARE ROW EXCLUSIVE` på `change_set` m.fl.
   (`R/update-1939-narratives.R:225-226`); de er døde ved kontrakt v2.
5. **Reimport-skriverlås (L4).** Navnefuldførelsen (`red_apply_reimport_name_completion`, l. 5886-5902) indsætter
   fakta på `person_id` uden at låse personrækken (fact har ingen FK). Uden L4 kan en åben batch skrive en forældreløs
   fakta for P lige efter COMMIT. L4 + blokeringen i afsnit 4.4 lukker det.
6. **`samme_som_mutation` + generation (L7)** før `change_set` og personer, som `red_slet_person`. Ingen skriver tager
   `samme_som` efter en kildelås eller identitetsrække, så L5/L6 før L7 giver ingen cyklus.

Kendt rest: `lock_family_rows` (l. 18910-18925) fejler ikke, hvis personen mangler. En afgørelse `same → P`, der venter
på sletningen, fortsætter efter COMMIT og fejler først på FK'en `source_persona_identity_event.canonical_person_id`
(l. 1672) med en rå FK-fejl. Med eksklusiv kildelås kan det kun ske for afgørelser uden kildelås (der er ingen for
identitet). `red_fortryd_change_set` kan stadig give 40P01 mod `lock_family_rows`, hvis den holder et familieled og
så rører P (samme klasse som kommentaren l. 18912-18917: fail-closed, gentag).

---

## 7. Konflikter og åbne spørgsmål til projektejeren

### KONFLIKT-rækker (bevar_andres med indhold om P)

| # | Række | Hvad står der om P | Hvorfor den ikke bare kan slettes |
|---|---|---|---|
| K1 | `private.reimport_authorization.authorized_elements` (S44a) for batches, der oprettede eller navnefuldførte P | element-payloaden ordret: `name` og `narrative.text` (person_create; `authorized_elements->element_id = p_payload`, l. 4233-4234; `name` krævet l. 4354, `narrative.text` brugt l. 4375) og `name` (name_completion; ligger under `authorized_elements->'payloads'->element_id`, l. 5894/5740, og bruges som `p_payload->>'name'` l. 5902) | én række pr. batch for mange personer; `manifest_sha256`/`preview_sha256` og skrivernes kontrol `authorized_elements->element_id = p_payload` (l. 4233-4234) hviler på den. Ingen AO-trigger, men en UPDATE ændrer en batch-kvittering. For 1791 (1939-import) er det sandsynligt, at rækken findes. |
| K2 | Andres `change_event` (narrative/note) og andres `npe.before/after_state` + `nlp.baseline_state` (`'text'`, l. 15066) med `[[person:P|Navn]]` | P's navn i linkteksten | spec §6.11 bevarer dem bevidst (bogens ordlyd), men beslutning 3 siger kun id-nummer. Blokeringen 4.1 retter kun den levende tekst. |
| K3 | Bevaret `change_set` fra `red_opret_media`/`red_upload_media` for et **delt** medie | medietitel/filnavn, hvis den nævner P | sættet har en andens events (mediet bevares) |
| K4 (spec-hul, ikke bevaret række) | `change_set` fra `withdraw_legacy_narrative` (fritekst `p_reason`, subjekt P, ingen events) | muligt navn i fritekst | specens regel (c) sletter det ikke; den rettede regel i 2.4 gør |

K5 (betinget, ikke talt med): vielsesfakta i bevarede familier (`citation.citat_tekst`, `assertion.vaerdi_tekst`)
er bogtekst og kan nævne P. Beslutning 7 bevarer dem; specen påstår, at de »ikke bærer den slettedes navn«, hvilket
ikke er sikret.

### Åbne spørgsmål

- **Q1 (K1):** Hvordan skal en batch-autorisation, der indeholder P's navn og narrativtekst, behandles? Mulighederne
  er at acceptere resten, at nulstille P's element i `authorized_elements` (ændrer en kvittering, hashen passer ikke
  længere) eller at blokere sletningen.
- **Q2 (K2):** Gælder beslutning 3 (»kun id-nummer i andres historik«) også linkteksten i andres narrativhistorik og
  publiceringstilstande, eller står §6.11 ved magt?
- **Q3:** Efter sletningen kan hele reimport-batchen, der oprettede P, ikke fortrydes. `red_reverse_reimport` tæller
  `canonical_delta`/`name_completion_result` mod `expected_counts` (l. 5948), og C3-fortrydelsen tæller tilsvarende.
  Det er fail-closed, men det gælder også alle andre personer i batchen. Er det acceptabelt, eller skal en
  sletning blokeres, mens batchen stadig kan fortrydes?
- **Q4:** Skal en `passed` kontrolkørsel, der stadig er kildens gældende, blokere sletningen? Efter sletningen bliver
  den `failed` ved næste evaluering (input-hashen ændres), så den ikke længere kan bruges til familiebekræftelse.
- **Q5:** `anden_promotion`: bekræft præciseringen i 4.2, så den kun blokerer familie-mål og ikke P's egne rækker,
  der er promoveret fra en andens record. Uden præciseringen kan en person oprettet af `relation_person_create`
  (fx fra en forælders post) aldrig slettes.
- **Q6:** Familiebindinger fra P's **egen** persona til en familie, der bevares (børn eller anden partner tilbage):
  skal promotionen bevares (den bliver forældet) eller slettes (P's persona står nu som »ikke en person«)?
- **Q7:** Det nye `person_purge`-event får version 1 og samme indholds-uuid som det slettede v1. Kvitteringer andre
  steder (`identity_version=1` i andres npe, stikprøver, `relation_reopen`) peger så på en anden betydning. Er det
  acceptabelt, eller skal oprindelsen have en anden version (kræver ændring af valideringen l. 1859)?
- **Q8:** Medier: skal et delt medie, hvis titel nævner P, have titlen rettet (K3), eller er det mediets indhold?
- **Q9:** Fritekst, der ikke kan bevises ren statisk: `source_persona_identity_event.evidence.note` hos `Y`,
  `relation_reopen.note`, `identity_control_parent_event.note`, noter/narrativer på bevarede familier,
  `suggestion` hos andre, `marriage_ordinal_correction.evidence`, `reimport_case_authorization.authorized_elements`.
  Skal forhåndsvisningen vise dem til manuel kontrol (anbefalet), eller ignoreres de?
- **Q10:** `import_korrektion` (S35) knyttes til P via `(import_key, record_key)`. Er nøglen i dag bundet til en anden
  person (tidligere flytning), bevares den. Bekræft.
- **Q11:** Personer slettet før med `red_slet_person` har en fuld kopi i historikken (inkl. `'Oprettede person <navn>'`).
  Den nye funktion kan ikke nå dem, fordi P skal findes. Skal det med i runbooken?

---

## Optælling (rækker i sted-tabellen afsnit 1)

| Handling | Antal | Steder |
|---|---|---|
| slet | 48 | S1-S4, S6-S9, S10 (slet+genskriv), S11a, S11b, S12, S13, S13b, S14, S14b, S15-S19, S21-S26, S28, S30, S32, NY-B, S33, S34, S35-S37, S38, S39a, S40, S41a, S42, S43a, S45a, M5, S49a, S49b, S54, S52/S53/S55 |
| nulstil | 2 | S5 (`profiles.reventlow_person_id`), S24 (`nlp.latest_event_id`, før sletning) |
| loesn | 2 | S27 (`haendelse.fact_id/relation_id`), S31 (`story.*_id`, automatisk SET NULL) |
| bevar_andres | 19 | S11c, S23b, S32c, S37b, S38b, S39c, S41b, S43b, S44a, S44b, S45b, S46, S48, S49c, S50, S58, NY-C, S57, S52b |
| blokér | 5 | S20, NY-A, S29, S34b (ved token), S39b |
| KONFLIKT | 3 | K1 (S44a), K2 (S57/S23b-tekst), K3 (S52b-medie). K4 er et hul i specens regel, som den rettede regel lukker; ikke en bevaret række |

S24 tælles under både slet og nulstil (først `latest_event_id := NULL`, så sletning). Uden handling: S47 (henviser til
S10-S12/S11c), S49d (følger S39b), S51 (transient), S56 (FK-oversigt), NY-D (ingen person-reference).
