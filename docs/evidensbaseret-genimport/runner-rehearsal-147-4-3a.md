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

## Eligibility-ledgeren kørt mod en restore (Task 5 Step 3)

**Kørt 2026-09-12** mod en frisk restore af prod-dumpet `daa-prod-20260910161728.dump`
(10. september), migreret op med `db-migrations.sql`, fordi trin 4's migrationer endnu
ikke er i produktionen. Basen havde 1.811 personer og 1.183 source records; 2018-20 er
`source_id = 1` med 591 records, alle koblet til en person.

**Resultat: 591 records, 488 `eligible`, 103 `excluded`.**

| Regel | Ramt (inkrementelt) | §9.2 (2026-09-06) | |
| --- | ---: | ---: | --- |
| 1. hovedperson levende/uafklaret | 47 | 50 (46+4) | −3 |
| 2. partner eller barn levende | 10 | 13 | −3 |
| 3. partner uden dødsdato | 46 | 62 | −16 |
| 4. tekstfilter | 2 | 2 | ✓ |

**Alle afvigelser går i den usikre retning** — færre udelukkede end §9.2 — så de er
efterprøvet frem for accepteret.

**Regel 1 er kontrolleret direkte mod rådata:** 47 records har `levende IS TRUE`, og
**nul** har `levende IS NULL`. §9.2's »46 + 4« bestod af 46 levende plus 4 *uafklarede*;
de fire uafklarede findes ikke længere i dumpet. Forskellen er altså **data, ikke kode** —
dumpet er fra 10. september, §9.2 målte 6. september, og 149a/149b blev anvendt i
produktionen 5.-6. september. Det er ikke et bevis, men det er den forklaring, tallene
peger på, og implementeringen er efterprøvet korrekt mod de data, der faktisk ligger der.

**Regel 3's −16 har samme karakter:** 297 records har en partner, 225 af dem har en
partner med dødsdato, og **nul** har et dødsfaktum uden dato. §9.2's 62 talte »poster med
en partner markeret ikke-levende uden dødsdato« — en beslægtet, men ikke identisk
måling.

### To fejl fundet ved kørslen

1. **Tekstfilteret fandt 0 i stedet for 2.** Mønsteret krævede årstallet umiddelbart
   efter `f.`, men bogen skriver `f. 12. Maj 1955`. Udvidet til at tillade op til 20
   ikke-cifre imellem. De to træf viser sig at være *falske* positiver — »f. Bechs Legat,
   1966«, hvor `f.` betyder født som pigenavn — og det er netop meningen: §9.2 kalder selv
   reglen en **manuel** udelukkelse, så filteret skal rejse tvivlen, ikke afgøre den.
2. **Ledgerens JSON-form var forkert.** `jsonlite` skrev `{"status":["excluded"]}` og
   `{"reasons":[["…"]]}` frem for skalarer og en flad liste. **Python-validatoren afviste
   den korrekt** med `LEDGER_STATUS_INVALID` — værnet fangede sin egen eksports fejl,
   hvilket er den bedste slags bekræftelse på, at det virker.

### Værnet prøvet på ægte data

Efter rettelsen validerer alle 591 rækker. En `eligible` record slipper igennem; en
`excluded` afvises med sine årsager (`RECORD_EXCLUDED … reasons=spouse_undated_marriage`);
en ukendt record afvises som `RECORD_UNKNOWN`.

**Ledgerfilen er ikke committet.** Den nævner ingen navne, men den udpeger hvilke poster
der rummer levende personer, og det er indirekte persondata. Kun tal er rapporteret her.

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
