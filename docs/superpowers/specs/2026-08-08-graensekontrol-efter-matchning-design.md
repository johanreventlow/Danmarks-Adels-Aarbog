# Grænsekontrol efter matchning — design

**Dato:** 2026-08-08
**Status:** godkendt design, implementering ikke startet
**Anledning:** redaktøren vil kunne verificere at postgrænserne står korrekt, før 1939-teksterne importeres. Vi har allerede importeret forkerte tekster én gang; det må ikke gentages.

## Problemet

Matchningen i menneskearket afgør *hvilken* kildepost der hører til hvilken historisk person. Den afgør ikke om kildepostens **grænser** står rigtigt. Tre uafhængige fund viser at grænserne faktisk er skæve:

- `detect_boundary_defects_1939.py` finder mod `clean_1939_v3.json` 2 grænsefejl-par, 17 poster der ikke åbner med deres eget trykte hoved, og 5 grupper hvor 2-3 poster deler ordret samme tekst.
- Calamari mistede punktum og spærring på `7. H e i n r i c h` (calamari-linje 1747), så nr. 7 aldrig blev egen kildepost; `raw.txt` linje 2206 har den intakt.
- Det eksakte tekstanker, som fladen tilbyder mærket "Forankret kildeevidens — kan accepteres direkte", er postens eget narrativ fundet i kilden. For en skævt delt post reproducerer det derfor fejlen præcist: Christine Augustas anker er alle 543 tegn inklusive Heinrichs hoved; Heinrichs er hans 156 hovedløse tegn. **15 af de 20 kendte grænsefejl-poster får tilbudt et sådant anker.**

Et accepteret anker beviser at teksten står i kilden. Det beviser ikke at grænsen er rigtig.

## Placering i kæden

Kontrollen kan først køre når valg er oversat til eksakte kildespænd, og den skal køre før noget skrives til databasen. Der er præcis ét sted hvor begge ting er sande:

```
menneskeark (matchning)
   ↓ eksport af kladde
anchor_review_choices_1939            ← oversætter valg til eksakte kildespænd
   ↓ forankrede kandidater + omskrevne valg
review_choices_1939 + compose_evidence
   ↓ sammensat evidens: ét calamari_span pr. accepteret post
━━━ GRÆNSEKONTROL (dette design) ━━━
   ↓ grænse-domme + rettede spænd + OCR-noter
(tilbage gennem forankringen, hvis noget blev rettet)
   ↓
materialisering til databasen          ← findes ikke endnu
```

Før forankringen findes spændene ikke — et kandidatvalg er kun et id. Efter materialiseringen er teksterne blevet påstande, og påstande overskrives aldrig (invariant 1); en rettelse ville da koste ny påstand plus ny konklusion. I dette punkt er spændene præcise **og** stadig blot filer, så en rettet grænse er blot et andet spænd i samme kladde. Det sparer hele afløsnings-maskineriet — og det er derfor kontrollen **skal** ligge før import.

## Omfang

**Med:** alle skæringer mellem accepterede spænd, inklusive de 93 maskinafgjorte og de 5 stikprøver. De automatiske spænd er afgjort af en regel om entydige ankre, ikke af en kontrol af hvor posten holder op, så deres grænser er lige så udsatte som de menneskevalgte.

**Uden for:** selve rettelsen af OCR-tegn (noteres her, rettes i egen opgave — se nedenfor), og materialisering til databasen.

## Arkitektur

**Selvstændig flade**, ikke en femte fane i menneskearket. Grænsekontrollen har en anden enhed (par af spænd, ikke én post), en anden interaktion (flyt et skæringspunkt) og et andet output (rettede spænd). `human_review_1939_ui.js` er omkring 1000 linjer og bærer en gennemgang der er i gang; at presse en fremmed enhed ind i den lægger risikoen på igangværende arbejde.

| Fil | Rolle |
|---|---|
| `make_boundary_review_1939.py` | bygger fladen, validerer input fail-closed |
| `boundary_review_1939_ui.js` | selve fladen |
| `review_ui_shared.js` | delt UI-grundstof: elementer, knapper, lokal lagring, eksport, karantæne |

`human_review_1939_ui.js` flyttes over på det delte modul i samme ombæring. Ellers divergerer de to flader. Regressionsværnet er at menneskearkets 88 tests skal bestå **uændret** — ændrer de sig, er adfærd flyttet og ikke kun kode.

### Input

| Fil | Hvad den giver |
|---|---|
| `composed-evidence-*.json` | postens accepterede `calamari_span` — de entries der har positiv proveniens og præcis én kandidat. Entries med `conflicts` eller `source_blockers` har intet accepteret spænd og indgår ikke som grænseejere; de tælles som ubesluttede i dækningsregnskabet |
| `clean_1939_v2.json` | navn, trykt nummer (`_orig_nr`), søskendegruppe (`_gruppe_nr`, ellers `_v2_lokal_id`-gren) |
| `full_ocr_calamari_r6_clean.txt` | kildeteksten spændene peger ind i |
| `raw.txt` | anden gengivelse, til at bekræfte skæringspunkter og OCR-fejl |
| `review-queue-manifest-*.json` | kø-klasse, så automatiske og stikprøver kan mærkes |

Klausul-regnskabet (se nedenfor) findes ikke som fil og udledes i processen af den hash-låste Calamari-tekst — samme mønster som `make_human_review_1939.py`, der kalder `segment._segment_1939_v2` undervejs.

### Output

- `menneskeark-graenser-<version>.html` — selvbærende fil, alt indlejret, gemmer lokalt, eksporterer JSON
- `graense-domme.json` — kildens hash-blok + én dom pr. grænse
- `ocr-noter.json` — noter hængt på poster, til den senere rettelsesopgave

## Kontrollens form: dækning, ikke bare skæringer

Kontrollen er en **dækningskontrol af hele kildeteksten**: hvert tegn skal enten ligge inde i et accepteret spænd, eller i et stykke der udtrykkeligt er erklæret ejerløst. Grænserne er de steder hvor status skifter.

Ejerløs tekst er legitim og almindelig: generationsoverskrifter ("Sjette Slægtled"), linjeoverskrifter, romertal, gruppebeskrivelser, sidemarkører, kildelinjer. Den kategori findes allerede i datamodellen: `segment.py --emit-evidence-ledger` deler kildeteksten linje for linje i `record_text`, `structural_header`, `layout` og `noise` (validerede værdier i `clause_ledger.py`). Et hul kan derfor **slås op** frem for at gættes.

### Signaler

| Signal | Bunke | Betydning |
|---|---|---|
| Hul med ejerløs brødtekst | Kræver vurdering | hullet indeholder `record_text` — prosa ingen post ejer |
| Hul med kun overskrift/layout | Hurtig bekræftelse | forventet; vises med hvad der står |
| Overlap | Hård fejl | to spænd dækker samme tegn; adapteren parkerer den slags, så optræder det, er noget galt højere op i kæden |
| Mangler eget hoved | Kræver vurdering | spændet åbner ikke med sin posts trykte hoved (OCR-tolerant match) |
| Slugt hoved | Kræver vurdering | spændet bærer en senere søskendes trykte hoved |
| Nummerspring | Kræver vurdering | de accepterede spænd i en søskendegruppe ligger i anden rækkefølge end de trykte numre, eller et nummer mangler blandt dem |
| Længdeafvigelse | Kun sortering | spændet er markant kortere eller længere end sine søskende; aldrig en advarsel i sig selv |

De fire midterste signaler er logik der allerede findes og er testet i `detect_boundary_defects_1939.py` (`fold_ocr`, `_opens_with_own_head`, `_swallowed_heads`). De skal pege på de accepterede spænd i stedet for på de gamle narrativer. Nummerspring og længdeafvigelse er nye.

**Forbehold:** regnskabets klassifikation hviler på de samme linjebaserede regler der tabte `7. H e i n r i c h`. En overskrift kan blive læst som brødtekst og omvendt. Regnskabet **sorterer og forklarer**; den faktiske tekst vises altid. Ved tvivl vises frem for at skjules.

### Visning

- **Kræver vurdering:** én skæring pr. skærm med fuld tekstkontekst — hvad det foregående spænd slutter med, hvad det efterfølgende begynder med, og hvad der eventuelt ligger imellem.
- **Hurtig bekræftelse:** flere skæringer pr. skærm i en tabel, godkendes i stræk.

Fuld dækning i begge tilfælde: ingen skæring er utilgængelig, men de mistænkte kommer først, så en halvfærdig gennemgang stadig har dækket det farligste.

## Rettelsen

**Skæringsvinduet** er de sidste 10 linjer af det foregående spænd + hele hullet + de første 10 linjer af det efterfølgende. Tallet er en navngiven konstant, ikke et skøn pr. sag, så vinduet er ens for alle grænser og kan ændres på ét sted. Er et spænd kortere end 10 linjer, tages hele spændet. Hver linjestart i vinduet er et muligt skæringspunkt, mærket:

| Mærke | Hvorfra |
|---|---|
| trykt hoved | linjen matcher `POST_1939_RE`, eller matcher postens eget navn OCR-tolerant |
| rå OCR har hoved her | den anden gengivelse har et trykt hoved hvor Calamari mangler det — Heinrich-tilfældet |
| overskrift · brødtekst · layout | klausul-regnskabets klassifikation |

Mærket "rå OCR har hoved her" er det stærkeste, fordi det er to uafhængige gengivelser af samme trykte side frem for en læsning mod en maskine.

### Fire slags rettelse

1. **Flyt skæringen** mellem to naboer — begge spænd ændres.
2. **Læg hullet til den ene nabo** — ét spænd forlænges.
3. **Erklær hullet ejerløst** — intet spænd ændres, dækningsregnskabet lukker.
4. **Her mangler en post** — hullet rummer en person ingen har matchet. Kan ikke løses ved at flytte en grænse; får sin egen dom og går tilbage i matchningskøen. Ellers skjules en manglende person som en grænsejustering.

### Hvorfor rettelsen ikke kræver nye evidensbegreber

Et flyttet spænd er stadig et eksakt, sammenhængende udsnit af den hash-låste kilde. Det hash-låses som i dag: id fra `coverage_1939.deterministic_human_candidate_id`, godkendelse `human_approved_span_v1` med `calamari_excerpt_sha256`. Kæden får ingen ny *slags* bevis — kun en ny **producent** af spænd (fladen) ved siden af den bestående (parserens post). Netop den producent manglede, da det viste sig at Heinrich ikke kunne forankres: `anchor_review_choices_1939` udleder spænd *fra* en valgt parser-post, og uden parser-post findes intet spænd at godkende.

Før fladen udsender noget, skal de rettede spænd bestå kædens bestående kontroller: ingen overlap, og global injektivitet — ét spænd må kun tilhøre én post.

## Domme, lagring og vejen tilbage

**Grænsens identitet** udledes deterministisk af de to spænd den ligger imellem. Flyttes en grænse, ændrer de tilstødende spænd sig, og grænsen får ny identitet og skal bekræftes igen. Det er tilsigtet: en rettelse skaber en ny grænse frem for en rettet gammel.

| Dom | Ledsagende felt |
|---|---|
| `graense_ok` | — |
| `graense_flyttet` | valgt skæringspunkt |
| `hul_ejerloest` | — |
| `hul_lagt_til_post` | hvilken nabo der får teksten |
| `manglende_post` | — |
| `kan_ikke_afgoeres` | begrundelse |

**OCR-noter hænger på posten**, ikke på skæringen — posten bærer teksten. Felter: hvad der står, hvad der burde stå, om rå OCR bekræfter, fri bemærkning. De havner i `ocr-noter.json` og rører ikke grænsedommene.

**Gengivelsesfilen ændres aldrig.** Hele kæden validerer mod `calamari_sha256`, og hvert spænd bærer en `calamari_excerpt_sha256` over netop sin tekst. Rettes tegn i filen, ophører den med at være en gengivelse af det trykte og bliver en redigeret afskrift, og alle hidtidige spænd og hashes falder. En OCR-rettelse er en ny påstand om hvad den trykte side siger, med egen proveniens, oven på en uforanderlig gengivelse. Rettelsesmekanismen designes som sin egen opgave, men **skal være gennemført før materialisering** — ellers importeres forkert tekst.

**Lagring:** browserens lokale lager mens der arbejdes, eksport som den portable tilstand. `file://`-dokumenter får hvert sit lager pr. fil, så en ny fil betyder altid: eksportér først. Generatoren kan indlejre en tidligere eksport ved genbygning, og fladen viser hvor længe siden der sidst blev eksporteret.

**Videre i kæden:**

- `graense_flyttet` og `hul_lagt_til_post` → rettede spænd med id og godkendelse, ind i den bestående forankringskæde
- `manglende_post` og `kan_ikke_afgoeres` → parkeringsliste med maskinlæsbar årsag
- OCR-noter → egen fil til den senere rettelsesopgave

## Fejlhåndtering

Fail-closed på: kildehash der ikke matcher; spænd der overlapper allerede i inputtet; et klausul-regnskab der ikke kan udledes af samme tekst; en dom der peger på en grænse som ikke længere findes; et rettet spænd der bryder injektivitet eller overlapper; et skæringspunkt der ikke er en linjestart i vinduet.

Karantæne frem for kassering: en ugyldig gemt dom ryger i karantæne med en dansk årsag og vises. Den forsvinder aldrig stille. Samme adfærd som menneskearket har i dag.

## Test

- én enhedstest pr. signal: hul klassificeret af regnskabet, manglende hoved, slugt hoved, nummerspring, overlap som hård fejl
- grænse-id er stabilt på tværs af genbygning
- en rettelse bliver en gyldig forankret kandidat med korrekt `calamari_excerpt_sha256`
- injektivitetsbrud afvises
- rundtur: eksportér → genbyg → domme indlejret
- menneskearkets 88 tests består uændret efter udtrækket af det delte UI-modul
- én manuel kørsel mod de rigtige data som verifikation — ikke som test

## Faseopdeling af implementeringen

Designet er større end én sikker leverance, så planen deler det i to. Fase 1 kan bruges alene: den fortæller hvor mange grænser der er gale, hvilket er den viden der mangler mest.

**Fase 1 — se og dømme.** Delt UI-modul udtrukket, signaler beregnet, flade med begge bunker, de seks domme, eksport, OCR-noter. Ingen rettelse af spænd. Resultat: en dækningsopgørelse over hele kildeteksten og en maskinlæsbar liste over hvilke grænser der er gale.

**Fase 2 — rette.** Skæringsvindue med mærkede punkter, de fire rettelsesformer, rettede spænd som forankrede kandidater med hash og id, injektivitetskontrol før udsendelse, tilbagevejen gennem forankringskæden.

Grunden til rækkefølgen: fase 2's værdi afhænger af fase 1's tal. Er der 12 gale grænser, kan de måske rettes hurtigere gennem matchningskøen end gennem ny kode. Er der 150, er fase 2 uundgåelig.

## Kendte begrænsninger

- Klausul-regnskabets klassifikation er heuristisk og bygger på de regler der allerede har fejlet én gang. Den sorterer; den afgør ikke.
- Nummerspring kan kun ses inden for en søskendegruppe. En grænse der er skredet på tværs af grupper er kun synlig gennem hoved-signalerne.
- Adapterens globale injektivitetskontrol har endnu ikke kørt mod rigtige data med de omkring 200 ekstra tekstankre som ændringen af ankerreglen bragte i spil. Den konflikt kan først vise sig ved forankring.
