# Task 6 — legacy-forbrugerinventar

Dette er overgangskontrakten for `slaegtled_lokal`, `slaegtled_gennem`, `kuld`
og `presens_kode`. Den nye model erstatter ikke historiske værdier med gæt:
hver gammel række bliver senere enten evidens-mappet, eksplicit bevaret som legacy
eller markeret uafklaret.

| Forbruger | Nuværende adfærd | Navngivet overgangskontrakt |
|---|---|---|
| `person_external_id` i `schema.sql` og migrations | Lagrer bogkoordinater og slægtled. | **LegacyPlacementBaseline**: behold værdier uændret til kildevis disposition. |
| `red_person_grid()` | Reducerer i dag flere værdier med `max(slaegtled_lokal)`. | **GridPlacementSummary**: valgt, ID-kontekstualiseret placering eller neutral fler-placeringsetikette. |
| `red_match_personer()` | Sender legacy-felterne i `extIds`. | **MatchPlacementPayload**: kompatibilitetspayload med evidensplaceringer eller eksplicit unresolved fallback. |
| `packages/core/src/generations.ts` | Bygger koordinater af `(source_id, linje)` og legacy slægtled/kuld. | **PlacementCoordinates**: stable source-, scheme-entry- og lineage-ID'er; bevar null-karantæne og kuld-grupper. |
| `packages/core/src/tree.ts` | Bruger lokal generation og kuld til kandidat-ring; spouse er ikke generationskant. | **CandidateRingPlacementParity**: identisk træ-output på legacy/projiceret input. |
| `packages/core/src/matchUdgaver.ts` | Bærer legacyfelter i bogreference. | **MatchPlacementPayload**: bevar referencesemantik, men læs fra overgangsprojektionen. |
| `web/src/data/model.ts` og `mobile/src/data/load.ts` | Læser `person_external_id`; fejl giver tomme koordinater. | **WebPlacementLoader** / **MobilePlacementLoader**: overgangs-view/RPC med paritetstest og eksplicit availability-gate. |
| Web/mobile `presensLinjer.ts` | Globalt `Record<presens_kode,...>`. | **PresensSchemeProjection**: scheme-scopet opslag med entry-ID; samme kode II må ikke kollidere. |
| `segment.py`, `segment_1939.py` | Udleder overskrifter og rå slægtled/kuld. | **ObservedHeaderPlacementLedger**: emitér kun placeringskandidater med observeret header-evidens. |
| `backfill_slaegtled.R` | Opdaterer efter `(source_id,linje,nr)`; kan ramme flere rækker. | **LegacyBackfillFreeze**: forbliver legacy-only; må ikke skrive nye placements. |
| `post_load_fixup.R` | Orkestrerer ovenstående backfill. | **LegacyBackfillFreeze**: behold replay-adfærd indtil en separat idempotent evidensmigrator findes. |

## Cutover-regler

1. `lineage.presens_kode` og den globale unikke indeksregel bevares, til web og mobil
   har scheme-scopede cache- og navigationstaster. `lineage_scheme_entry` er den nye
   autoritative struktur, men ikke endnu klienternes autoritative læsevej.
2. `person_source_coordinate_legacy` er den navngivne, security-invoker
   kompatibilitetsprojektion. Den viser kun eksisterende felter og påstår ikke at
   de er observerede placements.
3. En `private.source_record_placement` kræver accepted record-anker og konkret
   header-observation. En `source_persona_placement` kræver desuden sin egen
   observation i den samme accepted record; omtalt ægtefælle arver aldrig placering.
4. Ingen legacy-kolonne, fallback eller consumer fjernes før en navngivet erstatning
   har paritetstest. Særligt må grid-sammendraget ikke omskrives til én global
   generation pr. person.
