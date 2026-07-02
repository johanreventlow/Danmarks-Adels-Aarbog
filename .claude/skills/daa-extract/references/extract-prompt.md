<!-- prompt-version: 2026-07-02 (Sonnet 5-baseline) -->
<!-- Frossen, autoritativ prompt for trin ③ (fakta-udtræk). Rediger DENNE fil (ikke
     ad hoc pr. kørsel) og bump prompt-version ved ændringer, så modeller/kørsler
     kan sammenlignes uden prompt-drift. Se SKILL.md §③. -->

# Trin ③ fakta-udtræk — instruktioner (DAA stamtavle)

Arbejdsmappe: /Users/johanreventlow/TypeScript/danmarksadelsaarbog

LÆS FØRST:
- docs/daa-extraction-archetype.md (§3 fælder, §4 datoer)
- .claude/skills/daa-extract/references/extraction-schema.json (skemaet)

For HVER post i din batch-fil → ét JSON-objekt der validerer mod skemaet. Skriv ét
objekt per post til `work/extracted/<linje>-<nr_label>.json` (overskriv). Brug Write.

Postens input (fra `posts.json`): `raw_text`, `linje`, `nr`, `nr_label`,
`slaegtled`, `aegteskab_kontekst`, `kuld`.

## Regler
- Kopiér `linje`, `nr`, `nr_label` VERBATIM fra posten. `usikker` = postens værdi. UDLED IKKE `narrative` (den flettes deterministisk ind fra `raw_text` i trin ④).
- `date_raw` er OBLIGATORISK og VERBATIM for alle dato-fakta (fødsel/dåb/død/begravelse/floruit). Det er det vigtigste dato-felt — få det ordret rigtigt.
- `date_min`/`date_max`: **udledes nu DETERMINISTISK i trin ④ fra `date_raw`** — du MÅ udfylde dem, men de OVERSKRIVES. Brug din energi på `date_raw`, ikke på ISO-syntese. Syntetisér ALDRIG en normaliseret span i `vaerdi`.
- `koen` fra kontekst (Greve/søn→mand; Komtesse/datter→kvinde).
- Opret ALDRIG tredjeparts-personer (konger, paver, vidner, svigerforældre) — de nævnes kun i kontekst/tekst.

## kilde_span (proveniens) — BLOKERENDE (R7)
For hvert fakta og hvert ægteskab: kopiér den mindste klausul fra `raw_text` der
indeholder ankeret (dato-token, partnernavn, godsnavn). Den SKAL være en ordret
substring af `raw_text` — `validate.py` afviser poster hvor et span ikke findes
ordret. Opfind ALDRIG spanet; typografiske apostroffer/parenteser skal matche kilden.

## Hvad er rygrad (struktureres)
- Fakta: navn, tilnavn, fødsel, dåb, død, begravelse, floruit, titel, adling, dekoration (vaerdi = HVILKEN orden, fx "R."; date_raw = datoen).
- `godser`: navn + periode_raw + sogn/kreds i `sted`.
- `begivenheder` RESTRIKTIVT: kun navngivne, DELTE historiske events (slag, kroning, mord på greve Adolph 1315). Rutine-gerninger (vidne, stadfæstede, lenshyldning, immatrikulation) er IKKE events → de bliver i narrativen.
- `boern`: nr_range [lav,høj] + antal + evt. linje. (NB: udledes også deterministisk i trin ④ fra prosaen; dit felt ignoreres, men udfyld gerne.)
- `aegteskaber`: ordinal, partner_navn (uden at oprette personen), partner_ekstern_ref, type, dato_raw/date_min/date_max/sted/skilt, kilde_span. PLUS gift-ind ægtefælles rygrad: `partner_foedsel`{date_raw,date_min,date_max,sted}, `partner_daab`, `partner_doed`, `partner_erhverv`[], `partner_foraeldre` (tekst fra "(F.: …)").

## VIGTIGT — embeder vs karriere
- `embeder` = KUN institutionelle embeder/grader (amtmand, kannik, provst, abbed, militær rang, hofjægermester, kammerherre, klosterprovst, gehejmeråd, landråd). Brug ÉN ren rolle (ikke "landråd i Slesvig og Holsten" → bare "landråd"; sted/detalje udelades).
- **Civile karriere-stillinger** (Project Officer, konsulent, direktør, arkivar osv.) og **uddannelse/grader** (cand.*, ph.d., student) er IKKE rygrad — lad dem blive i narrativen, udtræk dem IKKE som embeder eller fakta. (For gift-ind ægtefæller: deres erhverv/grader hører i `partner_erhverv`.)

## Model-tier
Sonnet er default. Hvis trin ④ flagger en post, gen-kør KUN den post med Opus
(`--model opus`). De tætte middelalderposter med tredjeparts-personer er hvor
svagere modeller fejler.

Returnér kort status (antal poster + evt. tvivl), IKKE fuld JSON.
