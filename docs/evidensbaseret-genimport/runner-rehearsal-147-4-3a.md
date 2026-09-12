# Dagsværk 4.3a — den rigtige kørsel

**Kørt:** 2026-09-12. **Grundlag:** spec §6.5, plan Task 6.
**Script:** `.claude/skills/daa-extract/scripts/run_evidence_43a_rehearsal.py` (kan gentages).

Hele kæden er kørt ende til ende på **én opdigtet post**:

```
eligibility-ledger → preflight → call-dir → Seatbelt-gate → codex exec
→ usage → claim-validering → cache → gentagelse
```

Ingen database, ingen `work/`, ingen produktion. Posten (»Testperson Opdigtsen«,
Fiktivborg, 1710-1789) er fri fantasi.

## Resultat

| Krav | Udfald |
| --- | --- |
| Udelukket record når aldrig modellen | **ja** — sømmen kastede ikke |
| Ukendt record afvises (fravær ≠ tilladelse) | **ja** |
| Adgangstesten før kaldet | `GATE_OK` |
| Forbrug rapporteret | **ja** |
| Outputskemaet holder | **ja**, 4 claims |
| Cache-hit ved gentagelse | **ja** — modellen blev ikke spurgt igen |
| Gaten holdt under kaldet | **ja** — kanariestrengen lækkede ikke |
| Fejltyper klassificeret | 3/3 korrekt |

## Forbrug

| | input | output | reasoning |
| --- | ---: | ---: | ---: |
| Kaldet med posten | 17.376 | 352 | 177 |
| Tomt kontrolkald | 15.746 | 14 | 0 |

Baseline fra forbrugsproben var 15.266 tokens ved et minimalt kald. Prompten og
posten koster altså tilsammen ~2.100 tokens — hvoraf hovedparten er den nye
record-scoped prompt, ikke posten. Overhead-billedet fra proben står: det er
opkaldet, ikke indholdet, der dominerer.

## Hvad modellen udtrak

```
person.birth    ordinal=[1]  conf=1.0   "f. 21. Juni 1710"
mention.place   ordinal=[1]  conf=0.9   {"raw": "Fiktivborg"}
person.title    ordinal=[2]  conf=1.0   "Kammerjunker"
person.death    ordinal=[3]  conf=1.0   "Død 4. Maj 1789"
```

Bemærk, at datoerne er **ordrette** — `"f. 21. Juni 1710"`, ikke `1710-06-21`.
Det er promptens krav, og det er hele pointen: den ordrette form er det, der kan
efterprøves mod siden. Stedet er klassificeret som en *omtale*, ikke som et
fødselsfaktum. Hvert claim citerer den klausul, det står i.

## To fejl, kun en rigtig kørsel kunne finde

Kontraktfilen `evidence-claims-1.0.json` validerede fint i Python og blev afvist
to gange af API'et:

1. **`oneOf` er ikke tilladt** i et structured-output-skema
   (`invalid_json_schema`). Rettet til `anyOf`.
2. **Alle felter skal stå i `required`.** Valgfrihed udtrykkes med `null`, ikke
   med fravær. `source_persona_id` og `normalized` er derfor nu påkrævede felter
   med nullable type.

Begge er skrevet ind i skemaet som kommentarer med måledato, så de ikke
»ryddes op« igen af en senere læser, der finder formen omstændelig.

Det er samme mønster som stderr-fejlen og `-`-argumentet i Task 3: fejl, der kun
findes i den ene sti, testene bevidst ikke rører. Prisen for »ingen test starter
Codex« er, at den sti skal køres for alvor mindst én gang.

## Et forbehold ved kanarietesten

Kanariekaldet svarede `{"claims":[]}` frem for `KAN IKKE LÆSE`. Årsagen er
banal: `--output-schema` tvinger svarets form, så modellen *kan ikke* svare
frit, uanset hvad prompten beder om.

Kanarien beviser derfor kun det svage udsagn — at strengen ikke optrådte i
hændelsesstrømmen. Det stærke bevis er **adgangstesten**, som kører uden model og
deterministisk får `EACCES` på hver spærret sti. Sådan skal de to læses: testen
er beviset, kanarien er en stikprøve.

## Hvad kørslen ikke viser

- **Ingen rigtige records.** Det er 4.3b og kræver sin egen GO samt en
  eligibility-ledger, der faktisk er kørt mod en database.
- **Ledgeren her er syntetisk.** `export_model_eligibility.R` er stadig aldrig
  kørt mod en base (Task 5 Step 3), så §9.2's tal er ikke genmålt.
- **`timeout` og `validation_failed`** er ikke fremprovokeret ende til ende; de
  er dækket af enhedstests mod syntetiske fixtures.

## Udestår før 4.3b

1. Kør `export_model_eligibility.R` mod en restore og sammenlign med §9.2's tal
   fra 2026-09-06 (46+4 / 13 / 62 / 2).
2. Projektejerens GO til første kald mod rigtige records, med ledgerens hash og
   budget.
