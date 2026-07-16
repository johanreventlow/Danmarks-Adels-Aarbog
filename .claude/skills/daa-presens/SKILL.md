---
name: daa-presens
description: >-
  Parser en DAA-PRÆSENSLISTE (periodisk liste over NULEVENDE familiemedlemmer,
  fx Reventlow i DAA 2012-2014) til den evidensbaserede Supabase-datamodel.
  Brug ALTID når brugeren vil udtrække/parse/importere en præsensliste,
  nulevende-medlemsliste, "presens", eller en almindelig årbogs-families-
  opslag (modsat den store stamtavle — brug /daa-extract til stamtavler).
  Pipeline: deterministisk tekstudtræk + grov gren-segmentering, LLM-
  rekonstruktion af relations-træet per gren (default Sonnet), OCR-tolerant
  validering, og R-load (append) til Supabase som en ny source.
---

# DAA-præsensliste → datamodel

## Hvornår denne vs. /daa-extract

- **/daa-extract** = stor **stamtavle** (sekventielle løbenumre, slægtled,
  historiske/døde personer). Reventlow-særudgaven 2018-20, s.93-247.
- **/daa-presens** (denne) = **præsensliste** (nulevende, relations-træ per
  gren-hoved, slægtskabs-sektioner SØSTRE/FARFARS FARBROR, OCR-støjet kilde).
  Reventlow i DAA 2012-2014, s.360-362.

Begge er bare `source`s i samme graf — evidensmodellen forener dem. UI'et kan
toggle mellem stamtavle-view (træ, historisk dybde) og præsensliste-view
(nulevende, slægtskab relativt til fokus-person, adresse/erhverv).

**Læs `docs/daa-presens-archetype.md` før udtræk** — kontrakt, OCR-tolerance,
hvad der IKKE udtrækkes. Skema: `references/presens-schema.json`.

## Pipeline

```
PDF ──①pdftotext──> raw.txt ──②segment_presens.py──> blocks.json (per gren)
   ──③LLM per gren──> extracted/gren-N.json ──④validate_presens.py──> {clean,review}
   ──⑤load_presens.R (append)──> Supabase
```

### ① + ② Tekst + grov segmentering (deterministisk)

```bash
.claude/skills/daa-extract/scripts/extract_text.sh "<pdf>" <fra> <til> > work_presens/raw.txt
python3 .claude/skills/daa-presens/scripts/segment_presens.py work_presens/raw.txt \
  --family <Slægtsnavn> > work_presens/blocks.json
```

Segmenterer i **gren-blokke** (`N. GREN`), bærer linje + sider. Slægtskabs-
sektions-headers (SØSTRE …) bevares i blok-teksten — LLM'en bruger dem.

### ③ Rekonstruér relations-træet (LLM — Sonnet default)

For **hver** gren-blok: udtræk personerne til ét JSON-objekt
`{linje, gren, personer:[…]}` efter `references/presens-schema.json`. Den
flade `personer[]`-liste rekonstruerer træet via `foraelder_lokal_id` (peger
på et andet `lokal_id` i samme blok). Strukturen kommer fra nesting
(a./1)/a)/(1) + `Børn:`/`Søn:` + `af 1./2. ægteskab:`).

Prompten skal indeholde: blokkens `raw_text`, `linje`, `gren`, hele
`docs/daa-presens-archetype.md` (især §3 fælder og §4 OCR-tolerance).

Centralt:
- **OCR-rens navne** ("C hristian"→"Christian"), tolk `f`/`j` som dødsdagger.
- **Forældre/svigerforældre** fra `(søn af …)`/`(F.: …)` = `foraeldre_note`/
  `partner_foraeldre`-tekst, ALDRIG nye person-poster.
- **Køn** udledes af titel (Greve/Komtesse) og søn/datter.
- Kollaterale sektioner: sæt `relation_til_hoved` (søster/farfars farbror/…).

Gem ét objekt per gren til `work_presens/extracted/gren-<N>.json`.

### ④ Validering (OCR-tolerant)

```bash
python3 .claude/skills/daa-presens/scripts/validate_presens.py \
  work_presens/blocks.json work_presens/extracted/ \
  --clean work_presens/clean.json --review work_presens/review.json
```

Tjekker STRUKTUR (forælder-links gyldige, lokal_id unikke, køn sat, ordinaler
stigende). Dato-verbatim er **advisory, ikke blokerende** — OCR gør streng
match upålidelig. Flaggede blokke loades ikke før review.

### ⑤ Load (append) til Supabase

```bash
Rscript .claude/skills/daa-presens/scripts/load_presens.R work_presens/clean.json "DAA 2012-2014"
```

**Append som default** (ingen TRUNCATE): præsenslisten er en ny `source` der
sameksisterer med stamtavle-data; id'er allokeres fra `MAX(id)`. `--reset` kun
hvis du vil starte forfra. Loader personer (`levende=TRUE`) + fakta + forælder-
barn/ægtefælle-familier + kollateral-relation til gren-hoved.

**Forældrefamilie-slot (Problem 2):** hver 'barn'-række ledsages af `member_evidence()`
(slot-`fact('forældrefamilie')` + `assertion(objekt=familien)` + citation + afklaret
conclusion), så slægtskabet er evidens-komplet på tværs af udgaver. **Kræver migreret DB**
(`assertion.objekt_type/objekt_id` + `family_member`-EXCLUDE) — se daa-extract SKILL §⑤.

## Principper

- Præsensliste = én `source` (`slags='præsensliste'`); forenes med stamtavler
  via evidenslaget. Identitetssammenkædning (samme person i stamtavle +
  præsensliste) holdes pragmatisk i PoC.
- Nulevende-data: `person.levende=TRUE`. (GDPR/RLS parkeret i PoC — løs før
  multi-bruger-eksponering.)
- `work_presens/` er git-ignoreret arbejdsmappe.
