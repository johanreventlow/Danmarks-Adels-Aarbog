# DAA-udtræk: arketypisk model for den selektive rygrad

> Kontrakt for hvordan en stamtavle-post i Dansk Adels Aarbog parses til
> vores datamodel. Grundet i den faktiske tekst (Reventlow-særudgaven,
> stamtavle s. 93-247). Eksempler bruger kun historiske/middelalderlige
> personer. Mål: narrativ bevares 100 %; rygrad udtrækkes selektivt.

## 1. Postens grammatik (observeret)

En post har konsekvent form:

```
<nr>.  <Titel?> <Fornavn> [tilnavn/"kaldet X"] til <Gods1, Gods2 ...> (<tenure>) (<linje, nr ref?>)
       – <fødsel/død-linje med † og datoer> –
       <kronologisk prosa: daterede gerninger, embeder, godser, rejser ...>
       – Gift [1°|2°] med <Partner> (<DAA-krydsref>) (F.: <svigerforældre>) –
       – <N> børn|sønner: <slægtled>, <linje>, nr. <a-b>.
```

Grupperings-linjer mellem poster styrer forælder/ægteskab-kontekst:
- `Andet slægtled` / `Ellevte slægtled` → generation.
- `af andet ægteskab med Anna von Buchwaldt:` → følgende børn hører til den union.
- Sidehoved `von Reventlow – i linje` + `…indd…`-footer → **støj, fjernes**.

## 2. Rygrad der UDTRÆKKES (→ schema.sql)

Hvert udtræk bliver `assertion` (+ `conclusion` blåstemplet "DAA <udgave>") +
`citation` (source = DAA-udgaven, side). Datoer bærer altid `date_raw`.

| Element i prosaen | Mål-tabel | Faktatype/rolle | Eksempel |
|---|---|---|---|
| Løbenummer + linje | `person_external_id` | (linje, nr) | I, 1 |
| Navn | `fact` | `navn` | "Gottschalk von Reventlow" |
| Tilnavn | `fact` | `tilnavn` | "kaldet Kale (den Skaldede)" |
| Køn (afledt: søn/datter/Gift med/titel) | `person.koen` | — | mand |
| Fødsel | `fact` | `fødsel` | dato+sted hvis givet |
| Død (†) | `fact` | `død` | "† 11. febr. 1604" |
| Floruit (kun aktiv-span) | `fact` | `floruit` | "-1223-1247-" |
| Begravelse/dåb | `fact` | `begravelse`/`dåb` | hvis nævnt |
| Titel/rang | `fact` | `titel` | "ridder", "Tysk kansler", "greve" |
| Adling/patent | `fact` | `adling` | monark + dato + patent |
| Dekoration/orden | `fact` + `relation`→organisation | `dekoration` | Elefantordenen |
| Embede | `relation` person→organisation | rolle (dateret) | "kaptajn over Livgarden" 1563 |
| Godsbesiddelse | `relation` person→`estate` | rolle `ejer` + periode | "til Rixdorf (1561-†)" |
| Forælder→barn | `family` + `family_member` | rolle `barn` (+`konfidens`) | "5 børn: …, nr. 83-87" |
| Ægteskab | `family` (type) + `family_member` | rolle `partner`, `ordinal` | "Gift 1° med …", "Gift 2° med …" |
| Deltagelse i markant begivenhed | `relation` person→`historical_event` | rolle (deltager/...) | mordet på greve Adolph 1315; kroning; slag |
| Hele posten ordret | `narrative` | — | substrat, fuldtekst |

## 3. Hvad der IKKE udtrækkes (kritiske fælder)

Dette er fejlkilderne der afgør model-valg:

- **Tredjeparts-personer nævnt i prosaen er IKKE Reventlow-entiteter.** Karl 4.,
  pave Gregor 11., greve Johan 1. af Holsten, Robert Coppens (stenhugger) m.fl.
  optræder kun som kontekst — opret dem **ikke** som personer. (Kan blive
  pladsholder-relationer senere, ikke nu.)
- **Svigerforældre `(F.: …)`** noteres som tekst på ægteskabet, ikke som fuldt
  genealogiseret personhierarki i PoC.
- **Krydsref til andre udgaver `(DAA 1930, II, 71)`** = en `source`-reference /
  identitetslink, ikke en ny påstand. Bevares som note/citation til ekstern udgave.
- **Relative henvisninger** (`s.å.`, `s.st.`, `se nr. 25`) opløses til absolutte
  værdier; **den rå tekst bevares altid** i påstanden.
- **Rutine-handlinger oprettes IKKE som `historical_event`.** Stamtavlen er fuld
  af daterede gerninger ("vidne 1247", "stadfæstede 1258", "lenshyldning 1580",
  "immatr. i Rostock") — de er personens biografi og **bliver i narrativen**, ikke
  selvstændige begivenheds-entiteter. Et `historical_event` er en **navngiven,
  delt** begivenhed som *flere distinkte personer* knytter sig til (slag, kroning,
  mordet på greve Adolph 1315, institutionsgrundlæggelse). Tommelfingerregel: kan
  begivenheden bære deltagere fra *andre* poster? Hvis nej → narrativ, ikke entitet.
- Alt der ikke er rygrad (rejse-detaljer, anekdoter) **bliver i narrativen** —
  kan forfremmes senere.

## 4. Fuzzy-dato kvalifikatorer (→ assertion.date_qualifier)

| Tekst i bogen | qualifier | (date_min, date_max) |
|---|---|---|
| "11. febr. 1604" | `exact` | min = max |
| "† før 1243" | `before` | kun max |
| "nævnt fra 1561" | `after` | kun min |
| "ca. 1620" | `about` | spand om årstal |
| "1353/1356" | `between` | min < max |
| "-1223-1247-" | `floruit` | aktiv-span (≠ levetid) |
| "(1561-†)" | `until_event` / `open_end` | min sat, åben til død |
| "1966–" | `ongoing` | max NULL |

## 4b. Forkortelser

To slags, håndteres forskelligt:
- **Relative referencer** (`s.å.`=samme år, `s.m.`=samme måned, `s.st.`/`sst.`=samme
  sted, `s.d.`=samme dag) opløses til ABSOLUT ved udtræk vha. konteksten (forrige
  dato/sted i posten); rå tekst bevares i date_raw. (Aktuelt ~84% opløst.)
- **Domæne-forkortelser** = kontrolleret vokab. Bogens "Generelle forkortelser"
  (bagstof) er seedet i `vocab(scheme='forkortelse')` via
  `references/forkortelser.json` (S.=Sogn, H.=Herred, Kr.=Kreds, F.=Forældre,
  bibliografi m.m.).
- **Dekorations-/orden-koder** (`R.`, `D.M.`, `S.K.`, `Ty.J.1.`, `Pr.R.Ø.1.`,
  `F.Æ.L.4.` …) er DAA-standard og har INGEN nøgle i denne særudgave. De bevares
  rå (`dekoration`-fakta). Nøglen hentes fra en ANDEN DAA-udgave senere og seedes
  i `vocab(scheme='dekoration')` — fabrikér dem ikke.

## 5. Valideringsregler (gør et svagere udtræk forsvarligt)

Køres efter hvert post-udtræk; flagér til review ved brud:
1. Hver udtrukket dato-værdi SKAL forekomme ordret i postens rå tekst.
2. `nr` i forælder/barn-ref skal være et gyldigt løbenummer i samme linje.
3. Antal børn matcher "N børn/sønner: …".
4. Ægteskabs-`ordinal` stiger monotont (1°, 2°, 3°).
5. Ingen udtrukket person uden for postens egne navne (tredjeparts-fælde).
6. `narrative` er gemt og ikke-tom FØR fakta-udtræk accepteres.

**Sikkerhedsnet:** fordi hele posten altid bevares i `narrative`, betyder en
*manglende* udtrækning kun under-strukturering (kan forfremmes senere) — aldrig
datatab. Det sænker risikobarren for en mindre model markant; den farlige fejl er
*forkert* udtræk (fælderne i §3), som §5-reglerne fanger.

## 6. Pipeline-trin (deterministisk hvor muligt)

1. **pdftotext -layout** (deterministisk, ingen model) → rå tekst/side.
2. **Segmentering** (regex på `^<nr>.` + slægtled/ægteskabs-headers, håndtér
   side-brud-fortsættelse, fjern sidehoved/footer) — deterministisk.
3. **Per-post strukturering** (LLM, ét nummer ad gangen, skema-tvunget JSON).
4. **Validering** (§5, regelbaseret) → flag.
5. **Load** til Supabase via R (narrative + assertions + conclusions + citations).
