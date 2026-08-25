# Evidensbaseret genimport — teknisk målarkitektur

**Myndighed:** Autoritativ teknisk retning; levende kode og schema er source of truth for aktuelle detaljer

## Formål og afgrænsning

Målarkitekturen oversætter visionen til varige systemgrænser og kontrakter for
bevægelsen fra årbog til offentlig kildevisning. Den beskriver, hvilke
identiteter, beviser og afgørelser der skal overleve hvert trin, men foreskriver
ikke aktuelle tabeller, SQL-signaturer, filnavne, batchstørrelser eller
implementeringsrækkefølge. Roadmapet styrer rækkefølgen, statusdokumentet
beskriver modenheden, og levende kode og schema afgør aktuelle detaljer.

Arkitekturen omfatter bibliografisk registrering, rendition- og
kildebevaring, afgrænsning af kildeposter, observation og fortolkning,
identitetsafstemning, promotion, publicering og offentlig læsning. Den skal
kunne bære flere årbøger gennem én fælles motor og små udgavespecifikke
profiler.

## Den fælles ende-til-ende-kæde

Den fælles kæde er:

```text
bibliografisk source
  -> uforanderlige renditions
  -> fysiske occurrences og menneskeligt accepterede source records
  -> klausulobservationer og mentions
  -> source personas og identitetskandidater
  -> proposed interpretations
  -> menneskelig afgørelse
  -> promotion til eksisterende eller nye kanoniske mål
  -> særskilt publiceringsbeslutning
  -> offentlig læseprojektion med kildehenvisning
```

Hvert trin har en fail-closed kontrakt. Et trin kan bevare uafklaret materiale
og sende det til review, men må ikke omsætte manglende bevis eller tvivl til en
positiv afgørelse.

| Trin | Input | Bevaret identitet og provenance | Tilladte beslutninger | Fail-closed udgang | Næste gate |
| --- | --- | --- | --- | --- | --- |
| Bibliografisk source | En identificeret fysisk eller digital årbog og dens katalogoplysninger | Stabil source-identitet, udgavebetegnelse, oprindelse og registreringshistorik | Optag, ret eller afvis den bibliografiske beskrivelse og fastlæg eksplicit scope | Source forbliver uoptaget eller uafklaret; intet afledt materiale autoriseres | source/rendition gate |
| Uforanderlige renditions | Den godkendte bibliografiske source og modtagne scanninger, billeder, tekstlag eller OCR-resultater | Source-binding, rendition-identitet, indholdshash, format, afledningskæde og værktøjs-/modelversion | Optag en rendition, markér den afløst eller vælg den til en bestemt behandling; aldrig overskriv dens indhold | Ukendt, ændret eller ubundet materiale sættes i karantæne og må ikke drive ekstraktion | source/rendition gate |
| Fysiske occurrences og menneskeligt accepterede source records | En valideret rendition samt profilens forslag til side-, område- og postgrænser | Rendition-hash, fysisk side/område, tekst- eller billedanker, boundary-version, reviewafgørelse og særskilt occurrence-/record-identitet | Accepter, korrigér, opdel, saml eller afvis en foreslået grænse; markér huller eksplicit | Uafklarede grænser og dækningshuller bliver synlige reviewemner og producerer ikke accepterede source records | boundary/record gate |
| Klausulobservationer og mentions | Accepterede source records med deres uforanderlige kildeindhold | Source-record-binding, præcist span/anker, rå værdi, observationstype, ekstraktionsversion og usikkerhed | Accepter, korrigér eller invalidér observationen og klassificér dækningsstatus; ikke afgør dens kanoniske betydning | Uankrede, overlappende, ufuldstændige eller ukendte observationer forbliver private og uafklarede | observation/coverage gate |
| Source personas og identitetskandidater | Mentions og øvrige observationer fra én eller flere accepterede source records | Selvstændig source-persona-identitet, alle record-/mention-bindinger, kandidatbevis, algoritmeversion og konfliktspor | Gruppér eller adskil mentions som source persona og foreslå, afvis eller genåbn identitetskandidater; ikke bind automatisk til en kanonisk person | Tvetydige eller kolliderende kandidater går til review uden aktivt kanonisk mål | interpretation gate |
| Proposed interpretations | Kildebundne observationer, source personas, kontrolleret vokabular og dokumenterede mappingregler | Observationernes ankre, fortolkningsversion, regel-/modelversion, alternative forslag, confidence og begrundelse | Foreslå struktureret betydning, relation eller narrativ klassifikation; forslag må korrigeres, afvises eller stå uafklaret | Forslag uden tilstrækkelig provenance eller kontraktdækning bliver ikke afgørelser | interpretation gate |
| Menneskelig afgørelse | Proposed interpretations og identitetskandidater med kildekontekst og konflikter | Beslutningens aktør, tidspunkt, grundlag, scope, version, begrundelse og relation til tidligere afgørelser | Accepter, korrigér, afvis, udsæt eller genåbn fortolkning og identitet som særskilte akser | Manglende, forældet eller indbyrdes modstridende afgørelser autoriserer hverken identitetsbinding eller promotion | identity gate, derefter promotion gate |
| Promotion til eksisterende eller nye kanoniske mål | Gældende menneskelige afgørelser, aktiv source persona og låst kanonisk måltilstand | Hele kæden tilbage til source record, promotion-plan, target-identitet, input- og tilstandshashes samt batchaudit | Bind til ét eksisterende mål, opret et nyt mål eller undlad promotion; promotér kun udtrykkeligt godkendte påstande | Konflikt, drift, manglende mål eller uklar identitet giver ingen kanonisk mutation | promotion gate |
| Særskilt publiceringsbeslutning | Promoveret kanonisk viden og/eller kildebundet indhold, der har bestået relevante gater | Præcis objekt-/versionsbinding, policygrundlag, beslutningsaktør, tidspunkt og revisionshistorik | Publicér, afpublicér, begræns eller undlad publicering uafhængigt af promotion | Intet bliver synligt uden en gældende positiv beslutning for den konkrete version | publication gate |
| Offentlig læseprojektion med kildehenvisning | Kun aktuelt publiceringsgodkendte kanoniske og kildebundne versioner | Stabil henvisning til kanonisk mål, source persona, source record, rendition og relevante beslutninger | Projektionen må sammensætte godkendte læsemodeller, men ikke skabe nye fakta eller identitetsafgørelser | Manglende eller brudt provenance, policy eller binding udelades fra den offentlige projektion | apply/reversal gate og efterfølgende integritetskontrol |

`record_key` er en locator eller identitet for en kildepost og må aldrig
beskrives eller bruges som personidentitet. En source persona har højst ét
aktivt kanonisk mål ad gangen. En kanonisk person kan derimod have mange source
personas og mange source records, fordi hver historisk optræden bevares
særskilt.

## Fælles motor og udgavespecifik profil

Den fælles motor ejer de varige tværgående kontrakter: identiteter,
hashes/manifester, versions- og eventhistorik, kontraktvalidering,
reviewtilstande, promotion, publication gates, batchaudit og reversering. Den
skal kunne behandle en ny udgave uden at få nye permanente begreber, som kun
giver mening for den udgave.

En udgaveprofil ejer kun de forskelle, der følger af kildens fysiske og
sproglige form: sideudvalg, renditionvalg, layoutgrammatik,
header-/postgenkendelse, udgavespecifik normalisering og dokumenterede
vokabularafvigelser. Profilen må producere kandidater og signaler til den
fælles kæde, men må ikke omgå dens identiteter, reviewtilstande eller gater.

Private arbejdsartefakter må være editionsnavngivne, når navnet hjælper med at
afgrænse en konkret kørsel eller reviewflade. Permanente databaseoverflader og
fælles workflows må ikke være editionsnavngivne uden en udtrykkelig,
dokumenteret undtagelsesbeslutning.

## Identiteter og kildeoptrædener

Identitet findes på flere niveauer og må ikke kollapses: bibliografisk source,
rendition, fysisk occurrence, source record, mention, source persona og
kanonisk mål har hver sin identitet og livscyklus. Afledte identiteter bindes
til deres konkrete inputversioner; de udledes ikke alene af rækkefølge,
visningslabel eller flygtige parserpositioner.

En source record er den accepterede afgrænsning af en konkret kildepost. En
source persona samler de mentions, som redaktionen vurderer hører til samme
personoptræden i kildens kontekst. Hverken source record, `record_key` eller
source persona er i sig selv en fysisk person. Identitetsafstemning er en
begrundet og auditerbar relation fra source persona til højst ét aktivt
kanonisk mål, ikke en omskrivning af kildeidentiteten.

Skift af kanonisk mål opretter en ny identitetsafgørelse og afløser den gamle;
det omskriver ikke historikken. Kollisions-, dublet- og en-til-mange-konflikter
skal vises som uafklarede, indtil en eksplicit afgørelse lukker dem.

## Observation, fortolkning og promotion

En observation gengiver noget lokaliserbart i kilden: tekst, værdi, mention
eller fravær inden for en dokumenteret coverage-kontrakt. En fortolkning
foreslår, hvad observationen betyder. En identitetsafgørelse fastslår, hvilket
kanonisk mål en source persona må knyttes til. Promotion ændrer først derefter
den kanoniske model. Disse hændelser versioneres og auditeres hver for sig.

Automatik må skabe observationer, foreslå fortolkninger, rangere
identitetskandidater og validere kontrakter. Den må ikke gøre confidence til
en menneskelig afgørelse, fortolke manglende coverage som kildebevist fravær
eller promovere uden en gældende godkendelse. Når den kanoniske model ikke kan
rumme meningsbærende kildeindhold, bevares indholdet kildebundet frem for at
blive tabt eller tvunget ind i en forkert struktur.

## Narrativer og kildeversioner

Et narrativ tilhører den konkrete source record og rendition, hvor teksten
optræder. Narrativer fra forskellige udgaver flettes ikke til én kildetekst,
selv når deres source personas peger på samme kanoniske person. Den offentlige
læsemodel kan vise flere narrativer sammen, men skal bevare deres separate
kildehenvisninger og versioner.

Rå tekst, normaliseret tekst, redaktionelle rettelser og publicerbare
narrativversioner bevares som adskilte, afledte versioner med kendt ophav.
Rettelser og ny ekstraktion afløser tidligere versioner i stedet for at
overskrive dem. Promotion af strukturerede fakta og publicering af et narrativ
er særskilte beslutninger; ingen af dem følger automatisk af den anden.

## Redaktionel afgørelse og audit

Redaktionen bruger én varig beslutningsvej på tværs af udgaver. Review viser
original kontekst, maskinforslag, alternativer, konflikter, usikkerhed og
konsekvensen af valget. Det skal være muligt at vælge "ukendt", afvise et
forslag eller udsætte en afgørelse uden at skabe skjult standardadfærd.

Alle afgørelser er versionsbundne, aktørbundne og append-only auditerede. En
ny afgørelse refererer til den, den afløser, og historikken bevarer både
begrundelse og det eksakte inputgrundlag. Batchhandlinger registrerer de
enkelte omfattede objekter og deres forventede før- og eftertilstand; et
summeret antal er ikke tilstrækkeligt bevis.

## Gater og tilstandsforløb

Gaterne anvendes i denne rækkefølge:

1. **source/rendition gate:** beviser bibliografisk binding, uforanderligt
   indhold, hash, afledningskæde og tilladt renditionvalg.
2. **boundary/record gate:** beviser menneskeligt accepterede, entydige
   source-record-grænser og synlig disposition for huller og overlap.
3. **observation/coverage gate:** beviser ankre, kontraktgyldige observationer
   og eksplicit coverage uden at gøre stilhed til fravær.
4. **interpretation gate:** beviser, at proposed interpretations kan føres til
   observationer, regler, versioner og en gældende redaktionel afgørelse.
5. **identity gate:** beviser en entydig, aktiv og menneskeligt besluttet
   relation fra source persona til højst ét kanonisk mål.
6. **promotion gate:** beviser den eksakte, godkendte write-set, låst
   måltilstand, kontraktgyldighed og fravær af uafklarede konflikter.
7. **publication gate:** beviser en særskilt positiv beslutning, korrekt
   versionsbinding, synlighedspolicy og komplet kildehenvisning.
8. **apply/reversal gate:** beviser, at en anvendelse eller fortrydelse rammer
   præcis den godkendte mængde, bevarer audit og kan efterprøves mod før- og
   eftertilstand.

Hver gate producerer et versionsbundet resultat: bestået, afvist eller
uafklaret. Kun et bestået resultat åbner næste relevante tilstand. En senere
ændring i input, kontrakt, beslutning eller måltilstand gør afhængige
gate-resultater stale; de skal genberegnes eller genafgøres, ikke genbruges
stiltiende.

## Genkørsel, stale beslutninger og fortrydelse

Genkørsel starter fra de uforanderlige renditions og deklarerede profil- og
motorversioner. Manifester og hashes binder input, afledte artefakter,
beslutninger og måltilstand sammen, så identisk input kan reproduceres, og
ændret input opdages. En genkørsel må hverken remint'e stabile identiteter uden
grund eller overskrive tidligere versioner.

En afgørelse er stale, når dens source-, occurrence-, record-, observations-,
fortolknings-, persona-, kontrakt- eller target-binding ikke længere svarer
til det aktive grundlag. Stale afgørelser bevares i audit, men mister
autoriserende virkning og sendes til den relevante gate eller redaktionelle
beslutningsvej igen.

Promotion og publicering skal kunne forberedes, valideres og auditeres uden at
udføre mutation. Anvendelse kræver kontrol af den aktuelle tilstand umiddelbart
før write. Fortrydelse er en særskilt, autoriseret og auditeret handling med
egen identitet og forventet write-set; den må ikke fremstilles som sletning af
historik. Hvis en fuld semantisk fortrydelse ikke er sikker, stopper systemet
med en eksplicit recovery- eller manuel dispositionsopgave.

## Kanonisk model og offentlig projektion

Den kanoniske model indeholder konservativt promoveret viden om fysiske
personer og relationer. Den er ikke lager for alle kildeudsagn og erstatter
ikke source records, source personas eller kildeversioner. Nye kanoniske mål
oprettes kun gennem samme identitets- og promotiongater som eksisterende mål.

Den offentlige læseprojektion er afledt og genopbyggelig. Den sammensætter kun
objekter og versioner med en gældende publiceringsbeslutning og viser en
forståelig kildehenvisning tilbage gennem source record og rendition til den
bibliografiske source. Projektionen må ikke udfylde ukendte værdier, skjule
uenighed eller gøre en foreslået fortolkning til faktum. Tilbagetrukket,
privat, stale eller uafklaret materiale er fail-closed usynligt.

## Bevis for generalisering

Generalisering er først bevist, når alle følgende forhold er demonstreret
ende-til-ende:

- både 2018-20 og 1939 bruger samme kæde;
- en tredje årbog kan tilføjes uden nye permanente editionsnavngivne
  overflader eller permanente databaseoverflader;
- kun profil, kontrolleret vokabular og dokumenterede mappingregler ændres;
- redaktøren bruger én varig beslutningsvej;
- det publicerede resultat kan spores tilbage og reproduceres eller
  reverseres.

En fælles funktionssignatur, genbrugt kode eller en grøn isoleret test er ikke
alene et generaliseringsbevis. Beviset omfatter den faktiske kæde, gaterne,
redaktionel håndtering, kanonisk effekt, publicering og fortrydelse.

## Overgang fra legacy og parallelle workflows

Den gamle loader og lokale 1939-veje udvides ikke som parallel målarkitektur.
De behandles som tidsafgrænsede legacy-veje og må kun ændres, når det er
nødvendigt for sikker drift, migration eller udfasning mod den fælles kæde.
Nye udgavebehov implementeres i profilkontrakten eller i fælles mekanismer,
ikke som endnu et varigt sidespor.

Hver legacy-vej udfases først, når den fælles vej har funktionel og
redaktionel paritet, en eksplicit disposition for alle berørte legacy-rækker
og et grønt ende-til-ende-bevis. Indtil da skal parallel drift have tydeligt
ejerskab, afgrænset write-authority, afstemning mellem vejene og en
dokumenteret exit-betingelse. Udfasning må ikke slette provenance eller gøre
tidligere publicerede resultater irreproducerbare.

## Tekniske ikke-mål

Målarkitekturen kræver ikke perfekt OCR, fuld automatisk sikkerhed eller
strukturering af alt kildeindhold som kanoniske fakta. Den gør ikke en bestemt
udgave til facit for fælles begreber og kræver ikke, at kildetekster flettes
for at undgå kanoniske dubletter.

Dokumentet er heller ikke en dagsstatus, en fil-for-fil-plan, et fysisk
datamodeldiagram eller en kopi af levende DDL. Det giver ikke produktions-GO,
fastlægger ikke aktuelle rækketal og gør ikke mange tests eller et sikkert
enkeltbatch-run til bevis for en færdig fælles kæde.

## Ændringsmyndighed

Målarkitekturen ændres kun, når et bindende arkitekturprincip ændres, og kun
efter projektejerens udtrykkelige beslutning. Ændringen skal samtidig
registreres i `docs/decisions.md`. Implementeringsplaner skal argumentere mod
denne målarkitektur, men må ikke ændre den stiltiende gennem lokale valg.
