---
name: daa-extract
description: >-
  Parser Dansk Adels Aarbog (DAA) stamtavle-PDF til den evidensbaserede
  Supabase-datamodel. Brug denne skill ALTID når brugeren vil udtrække,
  parse, importere eller indlæse data fra en trykt adelsårbog / DAA-udgave /
  stamtavle-PDF — også når de blot siger "parse årbogen", "udtræk personerne
  fra PDF'en", "byg databasen fra bogen", "load stamtavlen" eller nævner
  pdftotext på adelsårbogen. Pipeline: deterministisk tekstudtræk +
  segmentering, LLM-struktureret fakta-udtræk per post (default Sonnet,
  Opus-fallback), blokerende validering, og R-load til Supabase. Bevarer
  altid prosaen som narrativ; udtrækker rygrad selektivt.
---

# DAA-udtræk: stamtavle-PDF → evidensbaseret datamodel

## Formål og filosofi

Dansk Adels Aarbog er den **autoritative kilde**. Hver post i stamtavlen er
tæt prosa med daterede gerninger. Vi gør to ting på én gang:

1. **Bevarer prosaen 100 % ordret** som `narrative` (substrat, fuldtekstsøgbar).
2. **Udtrækker rygraden selektivt** som `assertion` + `conclusion` + `citation`.

Det betyder: et *overset* fakta er kun under-strukturering (kan forfremmes
senere fra narrativen) — aldrig datatab. Den farlige fejl er *forkert* udtræk.
Hele designet optimerer derfor for at fange forkerte udtræk (validering), ikke
for at presse alt ud af prosaen.

**Læs `docs/daa-extraction-archetype.md` (i repo-roden) før udtræk** — det er
kontrakten for hvad der udtrækkes, hvad der bevidst IKKE udtrækkes (tredjeparts-
fælderne), og dato-kvalifikatorerne. Datamodellen selv: `schema.sql` i repo-roden.
Skemaet for trin ③'s output: `references/extraction-schema.json` (i denne skill).

## Pipeline (5 trin)

Trin 1-2 og 4 er **deterministisk kode** (ingen model, ingen fejlrisiko).
Trin 3 er det eneste LLM-trin. Trin 5 loader.

```
PDF ──①pdftotext──> rå tekst ──②segment.py──> posts.json
   ──③LLM-udtræk──> extracted.json ──④validate.py──> {clean.json, review.json}
   ──⑤load_daa.R──> Supabase   (kun clean.json; review.json kræver menneske)
```

### ① Tekstudtræk (deterministisk)

```bash
scripts/extract_text.sh "<pdf>" <første-side> <sidste-side> > work/raw.txt
```

PoC-scope: stamtavle s. 93-247. Scriptet bruger `pdftotext -layout` og
fjerner sidehoved/footer-støj (`.indd`-linjer, løbende sidehoved, sidetal).

### ② Segmentering (deterministisk)

```bash
python3 scripts/segment.py work/raw.txt > work/posts.json
```

Producerer én record per stamtavle-post med: `linje` (romertal-sektion),
`slaegtled`, `aegteskab_kontekst` (hvilken union børnene hører til), `nr`, og
`raw_text` (postens fulde ordrette prosa). Håndterer side-brud-fortsættelse.

**Segmenteringen er edition-følsom.** Hvis posttal eller headers ser forkerte
ud, justér regexerne i `segment.py` — det er forventet ved en ny udgave.
Verificér altid: antal poster ≈ forventet, og at `nr` er sammenhængende per linje.

### ③ Struktureret fakta-udtræk (LLM — det eneste model-trin)

For **hver** post i `posts.json`, udtræk **kun struktureret rygrad** til JSON
efter skemaet i `references/extraction-schema.json`. Kør ét nummer ad gangen
(lille kontekst = mindre drift). Default-model **Sonnet**; dispatch i batches
som subagents.

**Narrativen udledes IKKE af LLM'en.** Kerneløftet er at prosaen bevares 100%
ordret — at lade en model reproducere lang verbatim-tekst inviterer trunkering/
parafrase. `segment.py` har allerede den ordrette `raw_text` per (linje,nr), og
`validate.py` fletter den deterministisk ind i de rene records. LLM'en
udtrækker altså kun fakta/relationer/slægtskab.

Prompten til hver post (skema-tvunget output) skal indeholde:
- postens `raw_text`, `linje`, `nr`, `slaegtled`, `aegteskab_kontekst`
- hele `docs/daa-extraction-archetype.md`-kontrakten (især §3 fælderne og §4 datoer)
- kravet: **hver udtrukket dato-værdi skal forekomme ordret i raw_text**
- **dato-fakta:** `date_raw` er obligatorisk og verbatim (også floruit) — syntetisér
  aldrig en normaliseret span i `vaerdi`; spanet hører i `date_min`/`date_max`.
- **begivenheder restriktivt:** kun navngivne, *delte* historiske events (slag,
  kroning, mord på greve Adolph 1315). Rutine-gerninger (vidne, stadfæstede,
  lenshyldning, immatrikulation) er IKKE events — de bliver i narrativen.

Gem ét JSON-objekt per post til `work/extracted/<linje>-<nr>.json`.

**Model-tier:** Sonnet er default. Hvis trin ④ flagger en post, gen-kør KUN
den post med Opus (`--model opus`). Opus er fallback, ikke standard — de tætte
middelalderposter med tredjeparts-personer er hvor svagere modeller fejler.

### ④ Validering (deterministisk, BLOKERENDE)

```bash
python3 scripts/validate.py work/posts.json work/extracted/ \
  --clean work/clean.json --review work/review.json
```

Tjekker de 6 regler (se `references/archetype.md` §5). En post med ÉT brud
ryger i `review.json` og **loades ikke**. Scriptet udskriver en review-rapport
med præcis hvilken regel der brød og hvor. Et menneske skal gennemgå
`review.json`, rette (eller gen-køre med Opus), og flytte godkendte poster til
`clean.json` før load.

Dette er bevidst blokerende: vi hellere mangler en post end loader en forkert.

### ⑤ Load til Supabase (R)

```bash
Rscript scripts/load_daa.R work/clean.json
```

Loader hver post som: `narrative` (fuld prosa, source = DAA-udgaven) +
`fact`/`assertion`/`conclusion`/`citation` for rygraden + `family`/
`family_member` for slægtskab + `relation` for godser/embeder/begivenheder.
Login fra `~/.Renviron` (samme som `supabase_load.R`). Regenererer til sidst
`person.visning_*`-cachen fra konklusionerne.

**Erstatter** det håndtransskriberede udsnit i `supabase_load.R` — det var kun
en opstart. `load_daa.R` er den fremadrettede loader.

## Hurtig kørsel (hele PoC-scope)

```bash
cd <repo>
mkdir -p work/extracted
.claude/skills/daa-extract/scripts/extract_text.sh \
  "Dansk Adels Aarbog - Reventlow - Særudgave.pdf" 93 247 > work/raw.txt
python3 .claude/skills/daa-extract/scripts/segment.py work/raw.txt > work/posts.json
# trin ③: udtræk per post (se ovenfor) -> work/extracted/*.json
python3 .claude/skills/daa-extract/scripts/validate.py \
  work/posts.json work/extracted/ --clean work/clean.json --review work/review.json
# gennemgå work/review.json (menneske) -> godkend -> derefter:
Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean.json
```

`work/` er en arbejdsmappe — git-ignorér den (kan indeholde levende-persondata).

## Vigtige principper

- **Hver DAA-udgave er én `source`.** Modstridende udgaver = separate kilder,
  håndteret indfødt af påstand/konklusion. Sæt source-udgaven korrekt i load.
- **Påstande er uforanderlige.** Rettelser = ny påstand + ny konklusion, aldrig
  overskrivning.
- **Cache-felter** (`visning_*`, `koen`) skrives aldrig direkte — regenereres.
- **Tredjeparts-personer** nævnt i prosaen (konger, paver, vidner) oprettes
  IKKE som entiteter (archetype §3).
- Senere TNG-import er **enrichment** (anden, svagere kilde) — forurener ikke
  dette DAA-grundlag.
