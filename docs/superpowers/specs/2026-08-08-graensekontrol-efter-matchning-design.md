# Grænsekontrol efter matchning — design

**Dato:** 2026-08-08
**Status:** fase 1 implementeret og verificeret mod rigtige data 2026-08-08 (11 commits); fase 2 ikke startet. Design godkendt efter adversarial review (Codex gpt-5.6-sol, NO-GO på første udgave)
**Anledning:** redaktøren vil kunne verificere at postgrænserne står korrekt, før 1939-teksterne importeres. Vi har importeret forkerte tekster én gang; det må ikke gentages.

## Problemet

Matchningen i menneskearket afgør *hvilken* kildepost der hører til hvilken historisk person. Den afgør ikke om kildepostens **grænser** står rigtigt. Tre uafhængige fund viser at grænserne faktisk er skæve:

- `detect_boundary_defects_1939.py` finder mod `clean_1939_v3.json` 2 grænsefejl-par, 17 poster der ikke åbner med deres eget trykte hoved, og 5 grupper hvor 2-3 poster deler ordret samme tekst.
- Calamari mistede punktum og spærring på `7. H e i n r i c h` (calamari-linje 1747), så nr. 7 aldrig blev egen kildepost; `raw.txt` linje 2206 har den intakt.
- Det eksakte tekstanker, som fladen tilbyder mærket "Forankret kildeevidens — kan accepteres direkte", er postens eget narrativ fundet i kilden. For en skævt delt post reproducerer det derfor fejlen præcist: Christine Augustas anker er alle 543 tegn inklusive Heinrichs hoved; Heinrichs er hans 156 hovedløse tegn. **15 af de 20 kendte grænsefejl-poster får tilbudt et sådant anker.**

Et accepteret anker beviser at teksten står i kilden. Det beviser ikke at grænsen er rigtig.

## Placering i kæden

Kontrollen kræver eksakte, hash-låste spænd, og den skal ligge **før materialisering**. Begge betingelser er opfyldt straks efter forankringen: `build_human_anchored_candidates()` har på det tidspunkt allerede produceret spændene (`anchor_review_choices_1939.py:558`). Komponeringen tilføjer ikke noget kontrollen har brug for.

```
menneskeark (matchning)
   ↓ eksport af kladde
anchor_review_choices_1939            ← producerer eksakte, hash-låste spænd
━━━ GRÆNSEKONTROL (dette design) ━━━
   ↓ grænse-domme + (fase 2) afløsende spænd
review_choices_1939 + compose_evidence
   ↓ sammensat evidens
materialisering til databasen          ← findes ikke endnu
```

Kontrollen lægges **før** compose, ikke efter. Grunden er praktisk: en ugyldig rettelse er billigere at kassere før komponeringen end at rulle tilbage efter. Det er også dér afløsningsproblemet nedenfor er til at håndtere, fordi `compose_human_evidence_bundle()` endnu ikke har fastlåst en positiv proveniens.

Efter materialiseringen er teksterne blevet påstande, og påstande overskrives aldrig (invariant 1). Kravet "før materialisering" er hårdt. Påstanden i første udgave af dette design — at der kun findes *ét* muligt sted — holdt ikke: hoved- og slugningssignalerne kan endda køres endnu tidligere som et præventivt filter, hvor de er et gulv og ikke en optælling (`detect_boundary_defects_1939.py:23`).

## Omfang

**Med:** alle skæringer mellem accepterede spænd, inklusive de 93 maskinafgjorte og de 5 stikprøver. De automatiske spænd er afgjort af en regel om entydige ankre, ikke af en kontrol af hvor posten holder op, så deres grænser er lige så udsatte som de menneskevalgte.

**Uden for:** rettelse af OCR-tegn (noteres her, rettes i egen opgave), og materialisering.

## Arkitektur

**Selvstændig flade**, ikke en femte fane i menneskearket. Grænsekontrollen har en anden enhed (par af spænd, ikke én post), en anden interaktion (flyt et skæringspunkt) og et andet output. `human_review_1939_ui.js` er omkring 1000 linjer og bærer en gennemgang der er i gang.

| Fil | Rolle |
|---|---|
| `make_boundary_review_1939.py` | bygger fladen, validerer input fail-closed |
| `boundary_review_1939_ui.js` | selve fladen |
| `review_ui_shared.js` | delt UI-grundstof: elementer, knapper, lokal lagring, eksport, karantæne |

`human_review_1939_ui.js` flyttes over på det delte modul i samme ombæring. Regressionsværnet er at menneskearkets 88 tests består **uændret** — ændrer de sig, er adfærd flyttet og ikke kun kode.

### Input

| Fil | Hvad den giver |
|---|---|
| `human-anchored-candidates-*.json` + `rewritten-choices-*.json` | de accepterede, hash-låste spænd med id og godkendelse |
| kø-manifestets automatiske kandidater | de maskinafgjorte spænd, som også er grænseejere |
| `clean_1939_v2.json` | navn, trykt nummer (`_orig_nr`), søskendegruppe (`_gruppe_nr`, ellers `_v2_lokal_id`-gren) |
| `full_ocr_calamari_r6_clean.txt` | kildeteksten spændene peger ind i |
| `raw.txt` | anden gengivelse: bekræfter skæringspunkter og OCR-fejl, og bruges i den negative kontrol nedenfor |

Klausul-regnskabet udledes i processen af den hash-låste Calamari-tekst (`segment.py --emit-evidence-ledger`), samme mønster som `make_human_review_1939.py` bruger til segmentering.

### Output

- `menneskeark-graenser-<version>.html` — selvbærende fil, alt indlejret, gemmer lokalt, eksporterer JSON
- `graense-domme.json` — kildens hash-blok + én dom pr. grænse-revision
- `ocr-noter.json` — noter hængt på poster, til den senere rettelsesopgave

## Kontrollens form: dækning, ikke bare skæringer

Hvert tegn i kilden skal enten ligge inde i et accepteret spænd eller i et stykke der udtrykkeligt er erklæret ejerløst. Grænserne er de steder hvor status skifter.

Ejerløs tekst er legitim og almindelig: generationsoverskrifter ("Sjette Slægtled"), linjeoverskrifter, romertal, gruppebeskrivelser, sidemarkører, kildelinjer.

**Randene hører med.** Spændene sorteres eksplicit efter `char_from`, og kildeteksten får en start- og en slut-sentinel, så hullet før det første og efter det sidste accepterede spænd også bliver en grænse. Uden dem ville dækningskravet være usandt ved bogens to ender. Nul accepterede spænd giver én grænse (hele teksten ejerløs); ét spænd giver to.

### Signaler

| Signal | Virkning | Betydning |
|---|---|---|
| Hul med ejerløs brødtekst | Sorteres tidligt | hullet indeholder `record_text` — prosa ingen post ejer |
| Hoved i rå OCR | Sorteres først | et positivt fund viser et trykt hoved i det etablerede råvindue |
| Overlap | Hård fejl | to spænd dækker samme tegn |
| Mangler eget hoved | Sorteres først | spændet åbner ikke med sin posts trykte hoved (OCR-tolerant match) |
| Slugt hoved | Sorteres først | spændet bærer en senere søskendes trykte hoved |
| Nummerspring | Sorteres først | de accepterede spænd i en søskendegruppe ligger i anden rækkefølge end de trykte numre, eller et nummer mangler blandt dem |
| Længdeafvigelse | Kun sortering | spændet er markant kortere eller længere end sine søskende; aldrig en advarsel i sig selv |

Hoved- og slugningslogikken findes og er testet i `detect_boundary_defects_1939.py` (`fold_ocr`, `_opens_with_own_head`, `_swallowed_heads`); den skal pege på de accepterede spænd i stedet for på de gamle narrativer. Nummerspring, længdeafvigelse og det positive rå-OCR-signal tilføjes i grænsefladen.

### Ingen massebekræftelse med de nuværende rå-broer

Klausul-regnskabet klassificerer linjer med brede regler og kalder alt andet `record_text` (`segment.py:978`). Det bruger de generelle `LINJE_NAME`, `ROMAN_RE`, `SLGT_RE` og `MARR_RE` — ikke 1939-v2-profilens fulde strukturlogik (`segment.py:981`). Det er derfor et sorteringssignal, ikke en godkendelsesport.

Den målte kontrol af evidensen viste, at **0 af 352 forankrede spænd er spændpræcise**. For 349 spænd er det forankrede Calamari-spænd kun et delspænd inde i en forekomst, mens `raw_structure_bridge` dækker hele den parrede rå-forekomst; kun 110 spænd har overhovedet en rå-bro. Det afledte råvindue begynder derfor for sent i hvert enkelt tilfælde. Et hoved kan ligge tidligere i samme rå-forekomst og blive overset, så fravær af et fund er et muligt falsk negativ.

Massebekræftelses-bunken er derfor fjernet. Alle grænser vises i én liste. Signaler ud over `laengdeafvigelse` sorteres først, derefter huller med brødtekst og til sidst resten.

Rå-OCR-kontrollen bevares asymmetrisk: et positivt fund af et trykt hoved tilføjer signalet `hoved_i_raa_ocr`. Et manglende vindue eller fravær af et fund tilføjer intet signal og beviser intet. En massebekræftelses-bunke kan først genindføres, når `align_renditions` producerer en spændpræcis rå-kontrol.

### Visning

- **Alle grænser:** én skæring pr. skærm med fuld tekstkontekst, mistankesorteret som ovenfor.

Ingen skæring er utilgængelig, og ingen dom kan sættes på flere grænser ad gangen.

## Grænsens identitet og revision

Identiteten udledes af de to nabospænd **plus et revisionsnummer**. Uden revisionsnummeret kan forløbet A → B → A give det oprindelige grænse-id igen, og en gammel `graense_ok` ville da fremstå som gyldig for en grænse der har været igennem to rettelser. Domme er append-only med en forældrekæde: en ny revision arver ikke en tidligere dom, og en tidligere dom kan aldrig genaktiveres alene ved id-lighed.

En flytning ændrer **begge** nabospænd og kan derfor invalidere op til **tre** grænser: den flyttede plus de to yderligere skæringer som de ændrede spænd har mod deres andre naboer. Alle tre får ny revision og skal bekræftes igen.

## Fase 1 — se og dømme

Fase 1 ændrer ingen spænd. Den kan derfor kun rumme domme der ikke kræver et skæringspunkt:

| Dom | Ledsagende felt |
|---|---|
| `graense_ok` | — |
| `graense_forkert` | begrundelse |
| `hul_ejerloest` | — |
| `manglende_post` | — |
| `kan_ikke_afgoeres` | begrundelse |

`graense_flyttet` og `hul_lagt_til_post` hører til fase 2, fordi de kræver et valgt skæringspunkt og en afløsning af accepteret evidens. At love dem i fase 1 var en fejl i første udgave af dette design.

**Hvad fase 1 er værd alene:** en importspærring og en optælling. Den svarer på hvor mange grænser der er gale, hvilket er den viden der mangler mest — og som afgør om fase 2 er værd at bygge. Den giver ikke redaktøren en reparationshandling. Det skal siges tydeligt, så forventningen er rigtig: efter fase 1 er de gale grænser kendte og standset, ikke rettede.

## Fase 2 — rette

### Skæringsvinduet

Starter som de sidste 10 linjer af det foregående spænd + hele hullet + de første 10 linjer af det efterfølgende; navngiven konstant. Er et spænd kortere, tages hele spændet.

**Vinduet kan udvides på stedet:** *vis 20 linjer mere* og *vis hele spændet*. Er en lang tekst skåret over, ligger det rigtige punkt måske længere væk end 10 linjer, og et fast tal ville skjule netop det. Udvidelsen ændrer kun hvad der er fremvist — ikke hvilke punkter der er gyldige. Et skæringspunkt er gyldigt hvis det er en linjestart inden for de to spænd og hullet mellem dem.

Hvert punkt er mærket:

| Mærke | Hvorfra |
|---|---|
| trykt hoved | linjen matcher `POST_1939_RE`, eller matcher postens eget navn OCR-tolerant |
| rå OCR har hoved her | den anden gengivelse har et trykt hoved hvor Calamari mangler det |
| overskrift · brødtekst · layout | klausul-regnskabets klassifikation |

### Fire slags rettelse

1. **Flyt skæringen** — begge nabospænd afløses.
2. **Læg hullet til den ene nabo** — ét spænd afløses.
3. **Erklær hullet ejerløst** — intet spænd ændres.
4. **Her mangler en post** — hullet rummer en person ingen har matchet; går tilbage i matchningskøen frem for at blive skjult som en grænsejustering.

### Autoriseret afløsning — designets tungeste del

En grænserettelse på en post der allerede har accepteret evidens er **en erstatning af positiv evidens**, og det er udtrykkeligt forbudt i dag: `compose_human_evidence_bundle()` afviser at menneske-evidens erstatter en base-entry der har kandidater eller `positive_provenance` (`anchor_review_choices_1939.py:419-420`). Det rammer både automatisk og tidligere menneskegodkendt evidens, altså praktisk taget alle grænseejere.

Guarden er rigtig og skal ikke løsnes. Der skal i stedet indføres én **navngiven, autoriseret afløsningsoperation** med eksplicit semantik:

- det gamle accepterede spænd markeres **afløst**, ikke slettet; det nye bærer en henvisning til hvad det afløser
- afløsningen er kun lovlig med en registreret grænsedom som årsag — ikke som en almindelig genkomponering

Kandidat*formatet* kræver derimod ingen ny evidensart. Kontrakten er producent-neutral: den kræver spænd, postklasse, PDF-sider og godkendelse eller bro (`coverage_1939.py:115`), og human-kontrakten genberegner id'et uden reference til en parser-post (`prepare_review_queue_1939.py:710`). Første udgave af dette design konkluderede derfra at "kun en ny producent" manglede. Det var for hurtigt: formatet rækker, men operationen mangler.

### Hvad en afløsning invaliderer

Kandidat-id'et udledes deterministisk af spændet (`coverage_1939.py:76`), så et ændret spænd er et nyt id. Følgende skal genberegnes eller invalideres, og planen skal behandle hvert punkt eksplicit:

1. den gamle `positive_provenance` og dens composed-evidence-entry
2. den omskrevne choice, der peger på det gamle kandidat-id
3. kø-manifestets automatiske kandidat og `rule_id`, hvis posten var maskinafgjort
4. stikprøven og dens audit-resultat, som valideres mod det aktuelle manifest og `rule_id` (`prepare_review_queue_1939.py:501`)
5. alle grænsedomme der er incidente til de to ændrede spænd — op til tre grænser
6. `pdf_pages` for det nye spænd (se nedenfor)

### PDF-sider efter en flytning

`_resolve_pdf_pages()` bruger den ene forekomst der dækker spændet, og falder ellers tilbage til baseline-postens trykte sider (`anchor_review_choices_1939.py:241`). Et flyttet spænd kan krydse de gamle forekomstgrænser, og så er faldgruben netop den fejl vi lige har rettet et andet sted: sider hentet fra det forkerte sted. Det nye spænds `pdf_pages` skal derfor udledes af sidemarkørerne **inde i spændet** gennem `CALAMARI_R6_TO_PDF_V1`, med samme oversættelse som `make_human_review_1939._pdf_page_for` nu bruger — aldrig fra baseline-postens sider.

## OCR-noter

Noter hænger på **posten**, ikke på skæringen — posten bærer teksten. Felter: hvad der står, hvad der burde stå, om rå OCR bekræfter, fri bemærkning. De havner i `ocr-noter.json` og rører ikke grænsedommene.

**Gengivelsesfilen ændres aldrig.** Kæden validerer mod `calamari_sha256`, og hvert spænd bærer en `calamari_excerpt_sha256` over sin tekst. Rettes tegn i filen, ophører den med at være en gengivelse af det trykte, og alle hidtidige spænd og hashes falder. En OCR-rettelse er en ny påstand om hvad den trykte side siger, med egen proveniens, oven på en uforanderlig gengivelse. Egen opgave — men **skal være gennemført før materialisering**, ellers importeres forkert tekst.

## Lagring

Browserens lokale lager mens der arbejdes; eksport er den portable tilstand. `file://`-dokumenter får hvert sit lager pr. fil, så en ny fil betyder altid: eksportér først. Generatoren kan indlejre en tidligere eksport ved genbygning, og fladen viser hvor længe siden der sidst blev eksporteret.

## Overlap: hvem der faktisk garanterer det

Første udgave af dette design tilskrev overlap-garantien den forkerte kontrol. Den korrekte kæde:

- `anchor_review_choices_1939` parkerer manuel-mod-automatisk og manuel-mod-manuel overlap (`anchor_review_choices_1939.py:347`) — men sammenligner **ikke** automatiske kandidater indbyrdes
- automatiske indbyrdes dækkes tidligere: køklassifikationen demoterer alle kandidatkrav med overlap (`review_queue_1939.py:438`)
- den kanoniske slutkontrol sammenligner alle effektive accepterede kandidater (`validate_effective_candidate_injectivity`, `prepare_review_queue_1939.py:1205`)

Kæden er altså dækket, men den nye generator **skal kalde den kanoniske globale kontrol eksplicit**. `validate_source_bound_evidence()` validerer kandidater enkeltvis og beviser ikke globalt fravær af overlap (`prepare_review_queue_1939.py:838`).

## Fejlhåndtering

Fail-closed på: kildehash der ikke matcher; spænd der overlapper allerede i inputtet; et klausul-regnskab der ikke kan udledes af samme tekst; en dom der peger på en grænse-revision som ikke længere findes; et afløsende spænd der bryder global injektivitet eller overlapper; et skæringspunkt der ikke er en linjestart inden for de to spænd og hullet.

Karantæne frem for kassering: en ugyldig gemt dom ryger i karantæne med en dansk årsag og vises. Den forsvinder aldrig stille — samme adfærd som menneskearket har i dag.

## Test

**Fase 1**

- én enhedstest pr. signal: hul med brødtekst, hoved i rå OCR, manglende hoved, slugt hoved, nummerspring, overlap som hård fejl
- rå-OCR-kontrollen: et hoved som kun rå OCR har bevaret, giver `hoved_i_raa_ocr`; et manglende vindue giver intet signal
- view-model og UI har én liste over alle grænser og ingen massebekræftelses-kontrol
- randene: hul før første og efter sidste spænd; nul og ét accepteret spænd
- grænse-id og revisionsnummer er stabile på tværs af genbygning; en A → B → A-cyklus genaktiverer ikke en gammel dom
- rundtur: eksportér → genbyg → domme indlejret
- menneskearkets 88 tests består uændret efter udtrækket af det delte UI-modul

**Fase 2**

- en afløsning bliver en gyldig kandidat med korrekt `calamari_excerpt_sha256` og deterministisk id
- afløsning uden registreret grænsedom afvises
- alle seks invalideringspunkter dækkes, hvert med sin egen test — særligt stikprøve/audit og de op til tre incidente grænser
- `pdf_pages` for et flyttet spænd udledes af spændets egne sidemarkører gennem sidekortet, ikke af baseline-postens sider
- global injektivitet kaldes og afviser et kolliderende afløsende spænd

Dertil én manuel kørsel mod de rigtige data som verifikation — ikke som test.

## Kendte begrænsninger

- Klausul-regnskabets klassifikation er heuristisk og bygger på regler der allerede har fejlet én gang. Den sorterer kun.
- De nuværende `raw_structure_bridge`-værdier er forekomst-brede, ikke spændpræcise: 0 af 352 forankrede spænd er spændpræcise, 349 er delspænd, og kun 110 har en rå-bro. Fravær af et rå-OCR-hoved kan derfor ikke bruges negativt. En sikker genindførelse af massebekræftelse kræver spændpræcis rå-kontrol via `align_renditions`.
- Nummerspring kan kun ses inden for en søskendegruppe. En grænse der er skredet på tværs af grupper er kun synlig gennem hoved-signalerne.
- Adapterens globale injektivitetskontrol har endnu ikke kørt mod rigtige data med de omkring 200 ekstra tekstankre som ændringen af ankerreglen bragte i spil. Den konflikt kan først vise sig ved forankring.
- Fase 1 standser og optæller; den retter ikke. Uden fase 2 skal rettelserne gå gennem matchningskøen.

## Reviewhistorik

Første udgave blev afvist (NO-GO) i adversarial review, Codex gpt-5.6-sol, 2026-08-08. Otte fund, alle efterprøvet i koden og indarbejdet ovenfor. De tre alvorligste: afløsningsforbuddet i `compose_human_evidence_bundle` (kritisk — designet havde ingen lovlig vej tilbage i kæden), den manglende invalideringsgraf, og at klausul-regnskabet ikke er stærkt nok til at porte massebekræftelse. Dertil: grænseidentitet kunne cykle, fase 1 lovede en dom den ikke kunne indfri, overlap-garantien var tilskrevet den forkerte kontrol, placeringen var overhævdet som unik, og randtilfælde samt `pdf_pages` efter en flytning manglede.
