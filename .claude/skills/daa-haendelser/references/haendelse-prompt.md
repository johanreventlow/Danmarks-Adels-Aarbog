<!-- prompt-version: 2026-07-18-v1 -->
<!-- Frossen, autoritativ prompt for hændelsesudtræk. Rediger kun denne fil og
     bump prompt-versionen ved enhver ændring. -->

# DAA-hændelsesudtræk fra narrativ

Læs `references/haendelse-schema.json` og `references/vocab.json`. For hvert
inputnarrativ skal du skrive præcis ét JSON-objekt til
`work/haendelser/extracted/<narrative_id>.json`.

## Opgave

Find alle daterede hændelser, som narrativets subjekt selv deltager i. Returnér
`narrative_id` og en liste `haendelser` efter skemaet.

## Blokerende klausulregel

`klausul` SKAL være det mindste sammenhængende, ordrette substring af `tekst`,
der bærer hændelsen og dens dato, typisk ét prædikat med dato. Kopiér tegn,
typografi og mellemrum nøjagtigt. Parafrasér, ret eller opfind aldrig tekst.

## Dato

`date_raw` skal kopieres ordret fra klausulen. Du må foreslå `date_min` og
`date_max`, men de overskrives deterministisk. Brug qualifier-koderne
`exact`, `before`, `after`, `about`, `between`, `floruit`, `until_event`,
`open_end` eller `ongoing`; brug `about` for `ca.`/`o.`, aldrig `circa`.

## Kategori

Brug én kode fra `references/vocab.json`. Er du i tvivl, brug `andet`.

## Udeladelser og tredjepartsfælden

- Rene attributter uden dato er ikke hændelser.
- Fødsel, dåb, død og begravelse må medtages, men skal ikke opsøges; de
  deduplikeres mod rygraden ved load.
- En tredjeparts handling er ikke subjektets hændelse. En konges kroning tæller
  kun, hvis klausulen siger, at subjektet deltog.
- Lever aldrig `span_start`, `span_laengde`, `noegle`, `fact_id` eller
  `relation_id`; de beregnes deterministisk.

Returnér til sidst kun en kort status med antal behandlede narrativer og tvivl,
ikke JSON-indholdet i chatten.
