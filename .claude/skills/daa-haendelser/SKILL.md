---
name: daa-haendelser
description: >-
  Udtrækker daterede hændelser fra allerede bevarede DAA-narrativer til det
  regenererbare haendelse-formidlingslag. Brug denne skill ved eksport af
  narrativer, LLM-udtræk af hændelsesklausuler, H1-H8-validering, Opus-
  eskalering eller markering-bevarende merge-load af hændelser. Må aldrig
  bruges til at sende levende eller private personers prosa til en model.
---

# DAA-hændelser: narrativ prosa til levende feed

## Formål

Pipelinen finder daterede gerninger i eksisterende `narrative.tekst` og bygger
et regenererbart `haendelse`-lag. Den ændrer ikke evidenslaget. Kun
`feed_status` er en varig redaktionel dom.

Tre forskelle fra `daa-extract` er afgørende:

1. Input er færdige narrativer fra databasen, ikke PDF-tekst.
2. Output er `haendelse`-rækker, ikke personer, fakta eller familier.
3. Load er en markering-bevarende merge, ikke append af entiteter.

## Pipeline

```text
narrative ──① export_narratives.R──> work/haendelser/narrativer.json
  ──② LLM pr. narrativ──> work/haendelser/extracted/<narrative_id>.json
  ──③ validate_haendelser.py──> clean.json + review.json + escalation.json
  ──③b ét Opus-forsøg på flaggede narrativer──> deterministisk revalidering
  ──④ load_haendelser.R──> haendelse (feed_status bevares)
```

### ① Eksport

```bash
Rscript .claude/skills/daa-haendelser/scripts/export_narratives.R
```

Eksporten filtrerer GDPR i SQL og stopper hårdt, hvis et levende, privat eller
staged subjekt eller et privat narrativ kan findes i outputmængden. Kør kun mod
en godkendt databasekopi, medmindre brugeren udtrykkeligt har godkendt andet.

### ② Modeludtræk

Læs og brug uændret:

- `references/haendelse-prompt.md`
- `references/haendelse-schema.json`
- `references/vocab.json`

Kør ét narrativ ad gangen med Sonnet som standard. Modellen leverer aldrig
offsets, nøgler eller evidens-id'er. Gem output som
`work/haendelser/extracted/<narrative_id>.json`.

### ③ Blokerende validering

```bash
python3 .claude/skills/daa-haendelser/scripts/validate_haendelser.py \
  work/haendelser/narrativer.json work/haendelser/extracted \
  --clean work/haendelser/clean.json \
  --review work/haendelser/review.json \
  --escalate work/haendelser/escalation.json
```

H1-H3 er blokerende for hele narrativet. H4-H6 beregnes deterministisk.
H7 normaliserer ukendt kategori til `andet`; H8 sender år-rig prosa uden fund
til eskalering. Validatoren printer alle advisory-beskeder, også for rene poster,
så vokabulardrift ikke forsvinder i `clean.json`.

Opus må kun bruges én gang på de flaggede narrativer. Gem først det oprindelige
Sonnet-output som `<narrative_id>.sonnet.json`, og gem Opus-genudtrækket i en
separat mappe. Promovér derefter fail-closed med:

```bash
python3 .claude/skills/daa-haendelser/scripts/escalate_haendelser.py \
  work/haendelser/narrativer.json work/haendelser/reextracted work/haendelser/snapshots \
  work/haendelser/escalation.json work/haendelser/clean.json work/haendelser/review.json \
  --diff work/haendelser/escalation-diff.json
```

Helperen kræver et snapshot og kører altid samme H1-H8-validator igen. Kun et
blokkeringsfrit output uden nye H8-advisory-typer kan erstatte `clean.json`;
resten fjernes fail-closed fra clean og bliver i review.

### ④ Merge-load

```bash
Rscript .claude/skills/daa-haendelser/scripts/load_haendelser.R \
  work/haendelser/clean.json --dry-run
```

Begynd altid med `--dry-run`. Loaderen genlæser den aktuelle narrativtekst,
genberegner spans og ruller hele transaktionen tilbage i dry-run. Den berører
kun narrativer i inputtet. `feed_status` og stabile ids bevares ved nøglematch;
mistede markeringer logges og må aldrig forsvinde tavst.

## Principper

- Klausulen er altid et ordret substring af det aktuelle narrativ.
- Dato-bounds kommer fra den fælles deterministiske DAA-parser.
- En hændelse er formidling, ikke en ny assertion eller conclusion.
- Rygrads-match er konservativt; falsk kobling er værre end manglende kobling.
- `work/` er git-ignoreret og kan indeholde følsomt kildemateriale.
