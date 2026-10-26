# Trin 5c: slægt, linje og generation som placement og membership (#150) — design

**Status:** UDKAST 2026-10-26, afventer projektejerens afgørelser i §8.
**Gren:** `docs/150-5c-spec` fra `main` (`db67fb17`).
**Grundlag:** issue #150; `docs/decisions.md` 2026-10-05 (trin 5 aktiveret, 5a → 5b → 5c) og 2026-09-04 (149b valg A:
»begge udgaver revalideres samlet, når #150/#151 leverer placements«); planen 2026-08-02 Task 17 trin 3;
`docs/superpowers/reviews/task6-legacy-placement-consumer-inventory.md` (overgangskontrakterne);
afvigelsesvurderingen 2026-08-22 §7.4. Målt på en kopi af prod efter #248 (2026-10-26).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 5, sidste delspec (5c, #150). Efter 5c: Fable-review af trin 1-5, derefter trin 6.
2. **Værdikædeled:** observation (overskrifter som kildebundne observationer) → afgørelse (placement) →
   promotion (membership). I dag ender kæden ved source record; slægt/linje/generation bor kun i legacy.
3. **Leverancetype:** generel mekanisme (header-evidens, placement, ledger, membership-promotion) + én
   midlertidig legacy-afvikling (2018-20's `person_external_id`). Udgaveprofil kun for overskrifts-grammatikken.
4. **Værdi:** redaktionelt: hver persons placering i slægten har kilde, afgørelse og fortrydelse; multi-slægt
   bliver en tilstand, ikke en mulighed (invariant 9 i datavejen). Læserværdi kommer først med 5c-2 (§2).
5. **Færdigbevis:** se §7.
6. **Erstatter:** `backfill_slaegtled.R`/`post_load_fixup.R` som skrivevej for slægtled (fryses, Task 6
   **LegacyBackfillFreeze**); `person_external_id` som eneste bærer af placering.

## 2. Problem og målt udgangspunkt

- Placement-, membership- og lineage-tabellerne er skeletter: `source_record_placement`, `source_persona_placement`,
  `person_slaegt_membership`, `person_lineage_membership` = **0 rækker**. Eneste writer er
  `red_apply_reimport_person_create` (1939-person-oprettelse), der kræver en placement, som aldrig findes.
- Grundstruktur findes: 1 `slaegt` (Reventlow, status **`historical`** — #150 kræver `active`), 3
  `lineage_scheme` (2018-20 stamtavle med I-V, 1939 med VI, præsensliste), 8 entries, 7 `lineage`.
- Legacy: 1.167 `person_external_id`-rækker. **Kilde 1 (2018-20): 591**, alle med linje, nr og
  `slaegtled_lokal`, 292 med `slaegtled_gennem`. **Kilde 3 (1939): 576**, men 542 har pladsholderen `linje='1939'`,
  8 ingen linje, 0 slægtled — 1939's placering hører til trin 6.
- **Skelettet kan ikke opfyldes af nogen rigtig bog.** `validate_source_record_placement` kræver en
  `header`-observation i postens egen ankrede forekomst, og `validate_evidence_scope` kræver, at en observation
  ligger inden for sin forekomsts tekstspænd. Overskrifterne (»I / DEN HOLSTENSKE LINJE«, »Tiende (25.)
  slægtled«, kuld-romertal, »med X:«) står *mellem* posterne. Der er 0 `header`-observationer i prod, og ingen
  writer producerer dem. 2018-20's klausuler er alle `record_text` (ingen overskrifter inde i posterne).
- **Placements ændrer publiceringstilstanden.** Målt: én accepteret record- + persona-placement ændrer
  `narrative_publication_state` (`authority.identity_people` og `provenance`; status og eligibility uændret).
  Den gemte tilstands-sha passer så ikke længere → bindingen bliver `stale_published`. For kilde 1: **541
  publicerede** og 46 drafts. Revalidering findes pr. post (`red_revalider_person_narrative_record`).
- Læsere af legacy (bl.a. `red_person_grid` med `max(slaegtled_lokal)`, `red_match_personer`,
  `regen_person_visning`'s slægtsnavn, web/mobil/core) er kortlagt i Task 6-inventaret.

## 3. Afgrænsning: 5c deles i to (anbefalet, §8 spørgsmål 1)

- **5c-1 (denne spec):** header-evidens, placements for kilde 1, ledger for alle legacy-rækker,
  membership-promotion, `slaegt` → `active`, revalidering. **Ingen læser ændres**; paritet bevises (§7).
- **5c-2 (senere spec):** læserne skifter til placement/membership efter Task 6's navngivne kontrakter
  (`GridPlacementSummary`, `MatchPlacementPayload`, `PlacementCoordinates`, `PresensSchemeProjection`, …) med
  paritetstest; legacy-kolonner fjernes først, når begge udgaver er migreret (trin 6).

## 4. Design (5c-1)

### 4.1 Overskrifter som kildebundne observationer (§8 spørgsmål 2)

**Anbefalet (A): strukturelle forekomster.** Hver overskrift i 2018-20's rendition bliver en
`source_record_occurrence` med eget `occurrence_key` (fx `header:<side>:<char_from>`) og eget
`extraction_run`, aldrig ankret til en source record, med én `source_observation` af kind `header`
(rå tekst, side, tegnspænd, overskriftsniveau `linje|slaegtled|kuld|aegteskab` i en kontrolleret
attribut). Udtrækket er deterministisk (profilens regexer fra `segment.py`, versioneret som
`header_rule_version`), kører lokalt på den rå tekst og sender intet til en model.

`validate_source_record_placement` omskrives: header-observationen skal ligge i en **uankret forekomst i samme
rendition** og være **den nærmeste foregående overskrift af sit niveau** før postens forekomst (reglen og dens
version står i placementens `evidence`). Kravet om `EVIDENCE_PLACEMENT_SOURCE_MISMATCH` bevares.

Fravalgt (B): at udvide de 591 forekomsters spænd, så overskriften kommer med — 149a's forekomster er
uforanderlige og hash-bundne.

Følger af A: db-verify's placement-blokke og `evidence_contract.py`/`clause_ledger.py` bærer den gamle kontrakt
og opdateres; overførselsværktøjets forekomst-digests for kilde 1 skifter (forventet, som ved 5b); en
signaturændret validator kræver opgraderingstest fra prods skema.

### 4.2 Placements for kilde 1

- **Record-placement** pr. accepteret source record i kilde 1: `scheme_entry_id` (linjens entry i 2018-20-schemaet),
  `printed_number` (postens nr., observeret i postens egen `person_post`-observation), `generation_local`,
  `generation_global` (kun hvor bogen trykker parentes-tallet), `kuld_label`, `section_path`,
  `header_observation_id` (linje-overskriften; øvrige niveauer i `evidence`).
- **Persona-placement** kun for hovedpersonen (`principal_member`, persona via `primary`-mention,
  `basis_observation_id` = postens `person_post`-observation). Ægtefæller og børnehenvisninger får ingen
  placering i 5c-1 (Task 6 regel 3: omtalt ægtefælle arver aldrig placering).
- **Afgørelse uden fuldt ark:** legacy og header-observationerne stammer fra samme læsning af samme tekst, så
  enighed er ikke uafhængig bekræftelse. Derfor: maskinel accept (`decision_origin='migration'`), hvor
  overskriftsreglen og legacy er enige, **plus en blind kontrolstikprøve på K poster**, som projektejeren tjekker
  mod PDF'en (som 5b's kontrolmodel; K = 20 er mit forslag). Uenigheder og huller går til en token-fil uden
  forudfyldte svar. Manglende `slaegtled_gennem` er observeret fravær, ikke uenighed.
- Indholds-id'er (`private.content_uuid`) for forekomster, observationer, placements og afgørelser, så kørslen
  kan genspilles med samme id'er.

### 4.3 Ledger: én disposition pr. legacy-række

Ny tilføj-kun tabel (privat) med præcis én gældende disposition pr. `person_external_id`-række:
`mapped` (accepteret placement findes), `retained_legacy` (bevares uændret, fx kilde 3 indtil trin 6),
`archived_by_editor`, `unresolved` (kræver menneske). Alle 1.167 rækker får en disposition i 5c-1; kilde 3's 576
får `retained_legacy`. Ingen legacy-række ændres eller slettes.

### 4.4 Membership via promotion (§8 spørgsmål 3)

Én promotions-RPC (SECURITY DEFINER, `redaktion`) fra accepteret persona-placement (`principal_member`) +
accepteret identitet → `person_lineage_membership` (`role='member'`) og `person_slaegt_membership`.
`source_basis` bærer placement-id'er, identitetsversion og regelversion; en tilstands-sha som ved
relationsbindinger gør en binding forældet, når placement eller identitet ændres. Forslag:
`membership_kind='agnatic'` for alle hovedpersoner i stamtavlen; `adopted`/`editorial` kun ved en menneskelig
afgørelse. `slaegt` Reventlow sættes til `active`.

### 4.5 Revalidering af publiceringerne (§8 spørgsmål 4)

De 541 publicerede bindinger i kilde 1 revalideres i **samme transaktion** som placementerne accepteres, med
`red_revalider_person_narrative_record`, så læseren aldrig ser `stale_published`. Forhånds- og efterbetingelse:
samme antal `published`, uændret eligibility, 0 `stale_published`. 1939's 563 publicerede er uberørte (ingen
placements for kilde 3).

## 5. Følger

- `red_slet_person` blokeres af memberships (decisions :1830); sletning af en hovedperson kræver derefter, at
  membership og placement trækkes tilbage først.
- Kilde 1 og 3 bliver asymmetriske (placement mod `existing_exact_binding`) indtil trin 6 — modsat 149b's
  begrundelse for symmetri; accepteret, fordi 1939 mangler linjedata.
- 0 kanonisk delta i eksisterende tabeller; nye rækker kun i de tomme placement-/membership-tabeller, ledgeren,
  forekomster/observationer for overskrifter og publiceringshændelser (revalidering).

## 6. Prod

1. **DDL-ceremoni (GO 1):** validator-omskrivning, ledger-tabel, promotions-RPC, vokabular. Måling, dump,
   blokken i én transaktion, fingeraftryk før/efter, `get_advisors` (forventet: +1 `rls_enabled_no_policy` pr. ny
   privat tabel), `NOTIFY pgrst`. Øves på en stand-in med prods 2-minutters grænse.
2. **Dataceremoni (GO 2):** overskrifts-forekomster, placements, ledger, memberships og revalidering i én
   transaktion med `statement_timeout='15min'`, for-/efterbetingelser og rækkediff-forventning. Kontrolarket og
   token-filen er hash-bundne i GO'en.
3. **Paritet:** `red_person_grid`, `red_match_personer`, `regen_person_visning`-resultater og
   `public_family_sources` er byte-identiske før og efter (læserne er urørte).
4. **Fortrydelse:** DDL via dumpet; data: placements kan `superseded`, memberships trækkes tilbage via
   promotions-RPC'ens reversal; revalideringshændelser er historik. Dumpet er nødudvejen.

## 7. Færdigbevis

- Lokal CI grøn + opgraderingstest fra prods skema.
- Stand-in-øvelse: 587 hovedpersoner med accepteret placement og membership (de 4 `unresolved_text` får
  `unresolved`), 591 + 576 ledger-dispositioner, 0 `stale_published`, paritet (§6.3).
- Prod: begge GO'er kørt med forventede kvitteringer; status-snapshot hæver »Placement og membership« til
  `produktionsverificeret` for kilde 1.

## 8. Afgørelser for projektejeren

1. **Opdeling:** 5c-1 (evidens, placement, membership) nu og 5c-2 (læserskift) som egen spec? *Anbefalet: ja.*
2. **Overskriftsmodel:** strukturelle forekomster (A) med omskrevet validator? *Anbefalet: A.*
3. **Membership-art:** alle stamtavlens hovedpersoner som `agnatic`? Gifte-ind får aldrig membership.
4. **Revalidering:** de 541 publiceringer revalideres maskinelt i samme transaktion (uændret eligibility), eller
   skal de ses af et menneske først?

Mine egne valg (kan rettes): K = 20 i kontrolstikprøven; kun hovedpersonens persona-placement i 5c-1;
`occurrence_key`-form og `header_rule_version` overlades til planen.

## 9. Uden for scope

5c-2 (læserne), 1939's placering (trin 6), fjernelse af legacy-kolonner, præsenslistens scheme-scopede opslag,
`founder`/`claimant`-roller, ægtefællers og børns placering.
