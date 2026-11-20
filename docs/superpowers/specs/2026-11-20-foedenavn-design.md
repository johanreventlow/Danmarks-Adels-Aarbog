# Fødenavn som faktatype (#401) — kort design

Dato: 2026-11-20. Projektejeren valgte løsning B.

## Hvorfor

Præsenslistens født-klausul (»Grevinde Anna … Reventlow, født ‹pigenavn›«) bygger i dag på kvindens cachede
`visning_efternavn`. For ingifte uden slægtslinje har den værdi ingen kilde; for 811 er den en rest, som forsvinder
første gang hun redigeres (#396). Uden klausulen ligner hun en født Reventlow, fordi hun kun bærer mandens navn
(projektejeren 20/11). `visning_efternavn` betyder i databasen »slægtsnavnet, der sættes bag navnet«; præsenslisten
bruger det som »eget fødenavn«. De to betydninger kan ikke dele ét felt.

## Mål

- En ingift kvindes fødenavn er en kildebundet påstand (invariant 1), af en ny faktatype (invariant 2: nyt behov =
  ny faktatype, ikke ny kolonne).
- Præsenslistens født-klausul læser den påstand direkte, som den allerede læser adelstitler direkte.
- 811 får sit fødenavn indtastet med kilde; bagefter kan hendes cache følge reglen (`prod.zsh rest`) uden at
  præsenslisten ændrer sig.

## Ikke-mål

- Fødenavn for alle ~730 ingifte (løsning C; evidenskæden). Feltet åbner for det, men intet udtrækkes nu.
- Ændring af `visning_efternavn`'s betydning eller af `regen_person_visning` (#396's regel står).
- GEDCOM-eksport af fødenavn.

## Anti-mål

- Præsenslisten må aldrig få en ingift kvinde til at se født ind i mandens slægt ud. Klausulen må ikke forsvinde for
  811 før fødenavnet står som faktum.

## Tilgange

- **A. Lad 811's cache være** — billigst, men værdien er kildeløs og forsvinder ved næste redigering. Fravalgt.
- **B. Faktatype `fødenavn`, præsenslisten læser den direkte** — valgt. Følger præcedensen `overhoved`
  (spec 2026-07-22: vocab + redaktørfelt + præsenslisten læser faktaet).
- **C. B + udtræk for alle ingifte** — stort; ikke bedt om. Kan bygges oven på B senere.

## Design

1. **Vocab:** `('faktatype','fødenavn','Fødenavn — slægtsnavn ved fødslen (ingifte); titel er et eget titel-faktum')`
   i `schema.sql` og en idempotent blok i `db-migrations.sql` (`ON CONFLICT DO NOTHING`). Værdien er kun
   slægtsnavnet (»Ahlefeldt-Laurvig«), ikke fornavne eller titel.
2. **Redaktion (web):** felt `foedenavn` → faktatype `fødenavn` i `FELT_FAKTATYPE` (`web/src/data/redaktionWrite.ts`)
   og `['foedenavn', 'Fødenavn']` i `FELT_DEFS` (`web/src/Redaktion.tsx`). Skrives via de eksisterende RPC'er
   (`red_upsert_fakta`/`red_opret_fakta`) med kilde som fritekst.
3. **Præsenslisten (web):** `fetchPresensNavneDele` henter også afklarede, valgte `fødenavn`-påstande for de samme
   personer (samme fact→conclusion→assertion-join som adelstitlerne). `fodtKlausul` bruger fødenavnet, hvis det
   findes, ellers `visning_efternavn` som i dag (født i en slægtslinje — de 4 andre koner). Resten af formatet er
   uændret.
4. **Personsiden:** `fødenavn` i `FAKTA_RAEKKEFOELGE` lige efter `tilnavn` (`packages/core/src/personFacts.ts`).
5. **Mobil (kun dev):** samme felt og samme præsensregel i `mobile/` (filerne er porteret og skal holdes i sync).
6. **Prod-rækkefølge:** vocab-rækken i prod før merge (web skriver faktatypen, så rækken skal findes først) →
   merge → projektejeren indtaster 811's fødenavn med kilde → `prod.zsh rest` regenererer 811 → kontrol af
   præsenslisten.

## Overladt til den, der bygger

- Testform: unit-tests af `mapPresensNavneDele`/`fodtKlausul` (fødenavn vinder; uden fødenavn som i dag), db-verify
  for vocab-rækken, paritet web↔mobil hvor den findes i dag.
- Visningsnavn for faktatypen på personsiden, hvis det ikke kommer af vocab-label automatisk.
