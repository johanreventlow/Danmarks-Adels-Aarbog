# 2018-20 fase A: rendition, source records, byte-ankre og narrativ-bindinger

**Dato:** 2026-09-03
**Issue:** #149
**Status:** Godkendt design (projektejer, 2026-09-03 aften). Ikke implementeret.
**Revision samme aften:** opdelt i **149a** (dette dokument: kilderegnskab uden
bindinger) og **149b** (egen spec: legacy-migration til record-binding), fordi
#152's kontrakt (§4.3, §6.2) afviser upsert på legacy-narrativer og reserverer
eventtypen `legacy_migrated` til #149 uden at bygge en writer til den.
**Roadmapmål:** trin 3 i `docs/evidensbaseret-genimport/roadmap.md`.

## 1. Adgangskrav (roadmap §"Adgangskrav til nye planer")

| # | Krav | Svar |
|---|---|---|
| 1 | Roadmapmål | Trin 3: 2018-20 får fase A-ækvivalent provenance. |
| 2 | Led i værdikæden | Kilde → rendition → source record → forekomst/anker for `source_id = 1`. Narrativ-bindingen er 149b. |
| 3 | Generel, profil eller legacy-afvikling | **Generel** mekanik (writer og RPC'er fra #153/#152) plus **én lille udgaveprofil** `daa-2018-20`. Ingen nye DB-objekter, scripts eller tabeller med `2018` i navnet; nye scripts parametriseres på profil. |
| 4 | Redaktionel/brugerrettet værdi | 2018-20 får samme kilderegnskab som 1939: hver af de 591 poster er en varig `source_record` med `public_ref` og byte-anker i en frosset rendition. Det er forudsætningen for, at 149b kan give biografierne kildehenvisning, og for sammenligning på tværs af udgaver. |
| 5 | Bevis for færdig | Rehearsal mod en restore af prod-dump: eksakte tal for rendition (1), records (591), forekomster (591) og accepterede ankre (591); **nul kanonisk delta** (aggregat-hash af `person`, `fact`, `family_member`, `narrative` og `narrative_record_publication` uændret); replay giver `already_applied`; reversal gendanner tilstanden. Prod-apply er en separat gate. |
| 6 | Erstatter | Pilotens artefakter i `work/task16-2018-pilot` bliver regression, ikke input. 149b erstatter senere visningen "overgangsdata". |

## 2. Afgrænsning

**I scope (149a):** én rendition, 591 personposter som source records, én
forekomst og ét accepteret anker pr. post, ét hash-låst manifest gennem den
generelle writer, fase-pakke-gate, den læse-kun inventering i §8.

**Ikke i scope:** narrativ-bindinger og identitet (149b, se §5), tekstændringer
i narrativer (fase B-ækvivalent), strukturelle records (linjeindledninger,
slægtled-overskrifter, våbenbeskrivelser), klausul-observationer (#148),
fortolkning (#147), placement/membership (#150), identitetsvej (#151),
personoprettelse, modelkald af enhver art.

## 3. Rendition

- Kilde: PDF'en for DAA 2018-20 (særudgaven). Identificeres ved SHA-256, som skal
  matche `source_pdf_sha256` i pilotmanifestet fra task 16. Matcher ingen PDF i
  repoet, stopper fasen.
- Tekst: `pdftotext -layout` med sidemarkører i det format, `segment.py`
  forventer (`### PAGE n ###`). Output-SHA skal matche pilotens `raw_text_sha256`;
  afviger den, dokumenteres årsagen (pdftotext-version) og den nye SHA låses.
- Registrering: én række i `private.source_rendition` for `source_id = 1` med
  `rendition_key = 'daa-2018-20-pdftotext-r1'`, `rendition_kind = 'pdf_text_layer'`,
  `content_sha256` = SHA-256 af den rå tekstfil, `metadata` med pdftotext-version,
  PDF-SHA og sidetal.

## 4. Source records, forekomster og ankre

- Segmentering: `segment.py` køres deterministisk på renditionen og skal give
  591 poster, byte-identiske med `data/extracted-2026-06-18` på feltet
  `lokal_id` og `raw_text`. Afvigelse er stop.
- `record_key`: den værdi, prod allerede bruger i `public.person_external_id`
  for `source_id = 1` (jf. beslutningen 2026-07-30: `book_post_id = record_key`).
  Inventeringen (§8) verificerer, at mængden af `external_id` for source 1 og
  mængden af `lokal_id` fra segmenteringen er identiske. Er de det ikke,
  stopper fasen, og forskellen rapporteres som mængder, ikke antal.
- `record_kind = 'person_post'` for alle 591. Strukturelle blokke tælles i
  rapporten, men skrives ikke.
- Forekomst: hver posts `raw_text` skal findes som **eksakt delstreng** i
  renditionen; `char_from`/`char_to` er offsets i den rå tekst, `page_from`/
  `page_to` fra postens `sider`. Findes teksten ikke eksakt, fejler byggeren for
  posten, og fasen stopper (ingen fuzzy-match).
- Anker: én `source_record_anchor_event` pr. post med `decision_status =
  'accepted'`, `evidence = {method: 'deterministic-segment', segment_version,
  rendition_content_sha256, raw_text_sha256}`, `decided_by_name` = operatøren.
  Ankre er deterministiske; der er ingen menneskelig gennemgang i fase A.

## 5. Narrativ-bindinger: udskudt til 149b

149a skriver **ingen** bindinger. Årsag, målt i #152's spec: upsert på en
legacy-narrativ afvises (§6.2, "Legacy uden binding → Afvis"), en ny binding
kræver en entydig *accepteret identitetsmængde* i persona-laget (prod har 8
rækker), og eventtypen `legacy_migrated` er reserveret til #149 uden writer
(§4.3). Bindingen af 2018-20 er derfor en ny, editionsneutral mekanisme, ikke
en gentagelse af 1939's narrativ-publikation.

149b får egen spec efter inventeringen og skal som minimum bære disse regler
videre, som projektejeren godkendte 2026-09-03:

1. **Identitet, positiv evidens.** Personen skal have præcis én `external_id`
   for source 1, og den `record_key` må kun pege på præcis én person.
   Tekstlighed er aldrig et anker (spec 2026-08-02, invariant 14).
2. **Tekstlighed.** `narrative_norm_v1(narrativ.tekst)` skal være byte-lig
   `narrative_norm_v1(forekomst.verbatim_text)`.
3. **Disposition** (præcis én pr. narrativ, i ledgeren): `bound_published`,
   `bound_draft` (levende/staged/privat → `draft`), `unresolved_identity`,
   `unresolved_text`. Teksten ændres aldrig.
4. **Stopgrænse.** Over 10 % `unresolved_*` stopper fasen før prod.
5. **Mekanik.** Én generel writer, der lukker en grandfathered legacy-stream
   med `legacy_migrated` og opretter record-bindingen atomisk gennem #152's
   event-kontrakt. Identiteten record ↔ person indlæses som accepteret
   persona-identitet ud fra `person_external_id` med egen ledger.

## 6. Writer, kontrakt og rækkefølge

- Manifest: ét hash-låst manifest efter den generelle writers kontrakt (#153)
  med `source_evidence`-elementer (rendition, records, forekomster, ankre) og
  **nul** `person_create`-elementer; `expected_counts = {"person_creates": 0,
  "source_evidence": 591}`. Writer-profil: én række i
  `private.reimport_writer_profile` for `source_id = 1`, `profile_id =
  'daa-2018-20-source-evidence-v1'` med `writer_config` efter #153's lukkede
  feltmængde (`run_key_prefix`, `schema_version`, `extractor_version`,
  `rendition_key`, `rendition_kind`, `rendition_metadata`,
  `observation_extraction_method`, `citation_label_template`).
- Kontrakt: den generelle writer kræver `narrative_record_contract_version() = 2`.
  Rehearsal-basen skal derfor migreres til v2 efter #152's cutover-runbook,
  før 149a kan øves.
- Prod-rækkefølge: #152 cutover og #153 prod-verifikation **før** 149a's
  prod-apply.
- Gate: fase-pakke-gaten (`docs/runbooks/evidence-import-phase-gate.md`):
  backup 0600+SHA, restore-rehearsal, hash-låst manifest, projektejer-GO, ét
  apply, replay = `already_applied`, reversal bevist mod restore. Manifestet
  registreres i #156's ledger som bidrag med receipt.

## 7. Persondata

Fase A kalder ingen model. Tekst om levende personer forlader ikke maskinen.
Rapporter og fixtures indeholder kun `record_key`, tal og hashes, aldrig navne
eller narrativtekst. Bindinger for levende, staged eller private personer er
`draft`.

## 8. Inventering (læse-kun, første task)

Mod en restore af den seneste prod-dump, hvor source 1 er urørt
(`pre-c0f-20260821`), måles og rapporteres i aggregat:

- source 1: antal narrativer, external_ids, source records, renditions, bindinger;
- injektivitet person ↔ `record_key` (begge retninger, antal brud);
- mængdeforskel `external_id` ↔ `lokal_id` (antal kun-i-den-ene);
- andel narrativer byte-lig `raw_text` efter `narrative_norm_v1`;
- andel poster fundet som eksakt delstreng i renditionen;
- PDF-SHA og rå-tekst-SHA mod pilotmanifestet;
- antal `levende`, `staged`, `privat` blandt de 591.

Rapporten committes som `docs/superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md`
med tal og hashes alene.

## 9. Test

- Byggeren (Python): syntetiske fixtures uden rigtige navne; tests for eksakt
  delstreng, sideafledning, injektivitetsbrud, tekstafvigelse, stopgrænse,
  deterministisk output (samme input → samme manifest-SHA).
- Apply (R, generisk gateway `apply_reimport.R`): dry-run og apply mod
  engangs-restore; asserts på eksakte antal, nul kanonisk delta via
  aggregat-hash, replay, reversal.
- Synlighed: ingen offentlig projektion ændres; verificeres med
  `SET LOCAL ROLE anon` før og efter apply.

## 10. Ændringsmyndighed

Ændringer i §5's regel eller §6's rækkefølge kræver en post i
`docs/decisions.md`.
