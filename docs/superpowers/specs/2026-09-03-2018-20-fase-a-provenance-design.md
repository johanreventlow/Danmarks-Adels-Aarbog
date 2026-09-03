# 2018-20 fase A: rendition, source records, byte-ankre og narrativ-bindinger

**Dato:** 2026-09-03
**Issue:** #149
**Status:** Godkendt design (projektejer, 2026-09-03 aften). Ikke implementeret.
**Roadmapmål:** trin 3 i `docs/evidensbaseret-genimport/roadmap.md`.

## 1. Adgangskrav (roadmap §"Adgangskrav til nye planer")

| # | Krav | Svar |
|---|---|---|
| 1 | Roadmapmål | Trin 3: 2018-20 får fase A-ækvivalent provenance. |
| 2 | Led i værdikæden | Kilde → rendition → source record → forekomst/anker → narrativ-binding, for `source_id = 1`. |
| 3 | Generel, profil eller legacy-afvikling | **Generel** mekanik (writer og RPC'er fra #153/#152) plus **én lille udgaveprofil** `daa-2018-20`. Ingen nye DB-objekter, scripts eller tabeller med `2018` i navnet; nye scripts parametriseres på profil. |
| 4 | Redaktionel/brugerrettet værdi | De 591 biografier fra 2018-20 får en stabil, offentlig kildehenvisning (`public_ref`) og ophører med at være "overgangsdata". Forudsætning for senere sammenligning på tværs af udgaver. |
| 5 | Bevis for færdig | Rehearsal mod en restore af prod-dump: eksakte tal for records, forekomster, ankre og bindinger; **nul kanonisk delta** (aggregat-hash af `person`, `fact`, `family_member`, `narrative` uændret); replay giver `already_applied`; reversal gendanner tilstanden. Prod-apply er en separat gate. |
| 6 | Erstatter | Visningen af 2018-20-narrativer uden kildebinding. Pilotens artefakter i `work/task16-2018-pilot` bliver regression, ikke input. |

## 2. Afgrænsning

**I scope:** én rendition, 591 personposter som source records, én forekomst og ét
accepteret anker pr. post, narrativ-bindinger efter reglen i §5, en ledger med
præcis én disposition pr. narrativ, fase-pakke-gate.

**Ikke i scope:** tekstændringer i narrativer (fase B-ækvivalent), strukturelle
records (linjeindledninger, slægtled-overskrifter, våbenbeskrivelser), klausul-
observationer (#148), fortolkning (#147), placement/membership (#150),
identitetsvej (#151), personoprettelse, modelkald af enhver art.

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

## 5. Narrativ-bindinger: den målte gate

For hver narrativ med `source_id = 1` og `subjekt_type = 'person'`:

1. **Identitet, positiv evidens.** Personen skal have præcis én `external_id`
   for source 1, og den `record_key` må kun pege på præcis én person.
   Tekstlighed er aldrig et anker (spec 2026-08-02, invariant 14).
2. **Tekstlighed.** `narrative_norm_v1(narrativ.tekst)` skal være byte-lig
   `narrative_norm_v1(forekomst.verbatim_text)`.
3. **Disposition** (præcis én pr. narrativ, i ledgeren):
   - `bound_published`: 1 og 2 opfyldt, personen er hverken `levende`, `staged`
     eller `privat`.
   - `bound_draft`: 1 og 2 opfyldt, personen er `levende`, `staged` eller
     `privat`. Bindingen skrives med `status = 'draft'` (fail-closed synlighed).
   - `unresolved_identity`: 1 ikke opfyldt.
   - `unresolved_text`: 2 ikke opfyldt. Teksten ændres **ikke**.
4. **Stopgrænse.** Er andelen af `unresolved_*` over 10 % af narrativerne,
   stopper fasen før prod med rapport. Fase B for 2018-20 er da projektejerens
   separate beslutning.

Ingen narrativ ændres, ingen person oprettes, ingen kanonisk række rører sig.

## 6. Writer, kontrakt og rækkefølge

- Manifest: ét hash-låst manifest efter den generelle writers kontrakt (#153)
  med `source_evidence`-elementer (rendition, records, forekomster, ankre) og
  **nul** `person_create`-elementer. Writer-profil: én række i
  `private.reimport_writer_profile` for `source_id = 1`, `profile_id =
  'daa-2018-20'`.
- Bindinger: skrives gennem #152's record-nøglede publicerings-RPC
  (kontraktversion 2), aldrig gennem den gamle `(subjekt, source_id)`-vej.
- Prod-rækkefølge: #152 cutover og #153 prod-verifikation **før** #149's
  prod-apply. Rehearsal må gerne køres nu mod en restore med aktuelle
  migrationer.
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
- Apply (R, generisk writer): dry-run og apply mod engangs-restore; asserts på
  eksakte antal, nul kanonisk delta via aggregat-hash, replay, reversal.
- Bindinger: dispositionsfordeling matcher ledgeren; `draft`-reglen for
  levende/staged/privat verificeres med `SET LOCAL ROLE anon`.

## 10. Ændringsmyndighed

Ændringer i §5's regel eller §6's rækkefølge kræver en post i
`docs/decisions.md`.
