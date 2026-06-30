# Datamodel — oversigt
**Følgesvend-app til Danmarks Adelsforenings årbog · PoC: familien Reventlow**

Arbejdsgrundlag samlet fra vores samtale. Formålet er at fastlægge *hvad* der skal med i datamodellen, før der tegnes konkret skema eller bygges app/web. Modellen skal være stabil i kernen og principielt uendeligt udvidelig.

---

## 1. Grundprincipper (arkitekturfilosofien)

Disse fem principper styrer alle valg længere nede:

1. **Byg på GEDCOM 7 som udvekslings- og importstandard, men hold en rigere model internt.** GEDCOM bruges til at importere familiens eksisterende TNG-data og til eksport ud i resten af genealogiverdenen. Den interne model må gerne kunne mere, end GEDCOM kan udtrykke.
2. **Lille, fast sæt entiteter + én generel relationsmekanisme.** Nye behov bliver normalt nye *rolletyper* (data), ikke nye tabeller (skema). Det er det der gør modellen "uendeligt udvidelig" uden at skride.
3. **Alt om en person modelleres som fakta (events/attributter), ikke som faste kolonner.** Nye faktatyper kræver ingen skemaændring.
4. **Evidens før fortolkning.** Hvad en kilde *påstår* (uforanderligt) holdes adskilt fra hvad foreningen/forskeren *konkluderer* (foranderligt). Dette gælder både fakta *og* relationer.
5. **Privatliv indbygget fra start.** Levende vs. afdøde er et grundvilkår i personentiteten, ikke en eftertanke.

---

## 2. Entiteterne (byggestenene)

Hver entitet er en selvstændig "ting" i basen. Forbindelserne mellem dem håndteres af relationsmekanismen i afsnit 3.

### Genealogisk kerne
- **Person** — det centrale objekt. Reelt en *konklusion*: "den vi mener disse oplysninger handler om." Ud over en identitet og et levende-flag bærer den et lille **afledt visnings-cache** (foretrukket navn, fødsels-/dødsår, primær titel) — en ren envejs-projektion af de blåstemplede konklusioner, der aldrig redigeres direkte, men regenereres når en konklusion ændrer sig. Det holder lister, træer og slægtskabssøgning hurtige uden at konkurrere med evidenslaget. **Køn** (mand/kvinde/ukendt; NULL = ikke registreret) ligger som en arbejdsværdi direkte på personen — rygradsdata der bruges næsten overalt og i adelen driver titelform og agnatisk arvefølge; trækker på `vocab` og kan i sjældne, omstridte tilfælde forfremmes til et faktum, hvor værdien så afledes af konklusionen.
- **Familie / union** — binder partnere og børn sammen. Relationer mellem personer går *gennem* denne enhed, ikke som direkte person-til-person-kanter. Det håndterer flere ægteskaber, børn fra forskellige unioner og partnerskab uden vielse elegant. Hvert medlemskabslink bærer en `konfidens` (sikker/sandsynlig/formodet/omstridt), så ubekræftede forbindelser — bogens "formentlig søn af", "3 sønner?" — kan flages provisorisk; reelt modstridende hypoteser med kilder ligger i evidenslaget som påstande/konklusion. En grens forbindelse til træet *er* linket ved dens rod, så uvished mellem grene håndteres samme sted (og en ukendt junction kan hænges på en pladsholder-ane). Slægtskabsfinderen kan dermed vise, at en forbindelse går gennem et formodet led, i stedet for at præsentere en hypotese som kendsgerning.

### Kontekst- og biografilag
- **Sted** — geografisk lokalitet. Hierarkisk (sogn/herred/amt/land), tidsbevidst (jurisdiktioner ændrer sig), med koordinater. *Adskilt fra besiddelser* (se næste). Fingranulerede steder hører også her (fx kirkegård → gravsted med koordinater), så et gravsted er det sted, en begravelse peger på.
- **Organisation / institution** — amt, regiment, hof, lærd selskab — og **ridderordener** (Elefantordenen, Dannebrog), der netop er institutioner man *optages i*. Embeder og ordensgrader udtrykkes som *daterede roller* ind i organisationen, ikke som selvstændige entiteter.
- **Ejendom** — godser, herregårde, len, stamhuse; den juridiske form er en `slags`. Selvstændig entitet med en række ejere over tid, der *ligger på* et sted. (Selve det at eje/besidde er en *rolle* på relationen — "besiddelse" i ordets egentlige betydning.)
- **Medieobjekt** — foto, maleri, dokumentscanning, lyd, video. Behandles som et selvstændigt objekt med egne data (fx kunstner, medium, datering, nuværende placering for malerier), ikke blot som en vedhæftning.
- **Værk / kilde** — kirkebøger, folketællinger, skifter, breve, *hver enkelt trykt udgave af Adelsårbogen*, samt bøger og artikler. Spiller to roller på én gang: citationskilde (evidens) og værk *om* et emne (sekundærlitteratur).
- **Historisk begivenhed** — delt begivenhed (slag, kroning, institutionsgrundlæggelse) som flere personer kan knytte sig til med hver sin rolle.
- **Våben (heraldik)** — blasonering, billede, hvem der fører våbnet, og brisering mellem linjer.

### Evidens- og fortolkningslag
- **Påstand** — én kildes udsagn om ét forhold. Uforanderlig. Der kan være mange påstande om samme forhold.
- **Konklusion** — den begrundede, blåstemplede vurdering oven på påstandene. Foranderlig, kan versioneres og bære proveniens.
- **Citation** — knytter en påstand til den kilde der understøtter den (med sidehenvisning, kvalitetsvurdering m.m.).
- **Arkiv (repository)** — hvor en kilde fysisk findes.

### Tværgående
- **Note** — fritekst, der kan hænges på stort set alt.

---

## 3. Relationsmekanismen (arbejdshesten)

Personen er navet; alt andet hænger på via relationer. Hver relation bærer fire ting:

- **Rolle** — *hvilken slags* forbindelse (ejer, indehaver, afbildet, skabt af, forfatter, deltager, fadder, værge …)
- **Tid** — i hvilken periode forbindelsen gælder
- **Kilde** — hvorfra vi ved det
- **Konfidens** — hvor sikkert forholdet er

Fordi relationen kan bære en rolle, bliver "alle disse ting relaterer sig på *forskellig måde*" til ren data: en ny måde at forbinde på = en ny rolletype, ikke en ny struktur. Og fordi relationen bærer en kilde, kan også *relationer* have konkurrerende påstande (se afsnit 6) — fx omstridt ejerskab af et len.

Eksempler på relationer i praksis:
- Person —[ejer, 1720–1745]→ Gods
- Person —[afbildet i]→ Maleri · Person(kunstner) —[skabt af]→ Maleri · Maleri —[placeret på]→ Gods
- Person —[emne for]→ Biografi(værk) · Person(forfatter) —[skrev]→ Biografi
- Slægt —[emne for]→ Artikel
- Person —[deltager: befalingsmand]→ Historisk begivenhed
- Gods —[ligger på]→ Sted

---

## 4. Fakta om personer (events og attributter)

Det meste biografiske indhold modelleres her, hver med dato, sted og kilde:

- **Person-events:** fødsel, dåb, konfirmation, vielse, død, begravelse/bisættelse, adoption, emigration, immigration, testamente, skifte, samt "ting de har gjort" (deltog i slag, bestred embede, modtog orden).
- **Person-attributter:** erhverv, bopæl, uddannelse, nationalitet, religion, fysisk beskrivelse — og **titel** (bro til adelslaget).
- **Familie-events:** forlovelse, vielse, ægtepagt, skilsmisse, annullering.

**Narrativ vs. struktureret.** De trykte biografier er lange opremsninger af daterede begivenheder i prosaform. De skal *ikke* alle omdannes til strukturerede fakta. Den fulde prosa bevares ordret som et **narrativ** knyttet til personen og dens kilde (substratlag, fuldtekstindekseret), og fakta udtrækkes selektivt som et overlag — kun hvor strukturen køber noget. En post fortjener strukturering hvis den (a) hører til rygraden (fødsel/død/vielse/forældreskab/hovedtitler/ejendomssuccession/adling/våben), (b) forbinder to entiteter appen skal navigere mellem, (c) fodrer en planlagt funktion (tidslinje, kort, embeds-forespørgsel), eller (d) er historisk markant og skal kunne kobles på tværs af personer. Alt andet bliver i prosaen — bevaret, fuldtekstsøgbart og altid muligt at "forfremme" senere. Det er samme substrat-plus-overlag-mønster som evidensmodellen, og det bevarer samtidig den redaktionelle dom (udvalg, vægtning, rækkefølge), som fuld strukturering ville flade ud.

**Fakta er ikke begrænset til personer.** Samme mekanisme gælder enhver entitet: et gravsted (opført, flyttet, ødelagt), et gods (sammenlagt, delt, frasolgt) eller et våben kan have sin egen daterede tidslinje. `fact.subjekt_type` er derfor polymorf — ikke kun person/familie.

---

## 5. Adelslaget (det der gør modellen til foreningens egen)

- **Titler / rang** modelleres som *fakta* med rolle og periode — ikke som statiske tekstfelter. Perioden er *fleksibel*: afgrænset (eksplicitte datoer), livslang (forankret til fødsel→død, fx en arvet grevetitel — arver dermed datofakta og deres usikkerhed), eller afledt af en ejendom (en lensgrevetitel følger lenets besiddelsesperiode). Faktummet bærer desuden en **erhvervelsesmåde**: ved fødsel/arvet · tildelt (med dato + monark) · knyttet til ejendom. (Senere mulig udvidelse: en titel kan bære sin egen successionsregel — fx "føres af alle i linjen" vs. "kun af slægtens hoved".)
- **Embeder og ordener** modelleres ens: en *dateret rolle* ind i en institution (organisation/ridderorden), med "udnævnt af" og — for ordener — graden som rolle (ridder, kommandør, storkors).
- **Ejendom (godser, len, stamhuse, lensgrevskaber)** er førsteklasses entiteter med en række ejere over tid; det at eje er rollen "ejer/besidder" med en periode.
- **Slægtslinjer / grene** — fx de forskellige Reventlow-linjer (svarer til TNG's "branches").
- **Adling / naturalisation** som event (af hvilken monark, hvornår, hvilket patent).
- **Heraldik** — våben knyttet til person/slægt/linje, med blasonering (skjold, hjelmklæde, hjelmtegn). Et våben kan være *delt* mellem beslægtede slægter (Reventlow/Walstorp/Muggele) og have *varianter* over tid, dokumenteret via daterede segl; konkurrerende tolkninger håndteres af påstand/konklusion-modellen.
- **Krydsreference til den trykte årbog** — felt på person/familie der peger på udgave + sidetal. Den tekniske tråd der binder appen til bogen som *følgesvend*, ikke konkurrent.

---

## 6. Evidens- og autoritetsmodellen

Det historiker-kritiske lag. Princippet: **påstande overskrives aldrig; fortolkning lægges ovenpå.**

- **Påstande** er én kildes udsagn, alle bevaret. Eksempel — dødsdato: DAA 1884 siger 1738; sognekirkebogen har begravelse 1739; DAA 1952 siger "ca. 1738"; familiens indberetning 2020 siger 1738. Fire påstande, fire kilder.
- **Konklusionen** vælger den gældende værdi (fx kirkebogen → 1739), markerer status (afklaret / omstridt / forældet) og bærer **proveniens**: hvilken udgave eller beslutning blåstemplede den, hvornår, af hvem.
- **Hver trykt årbog er en selvstændig kilde.** Modstridende fakta mellem udgaver er derfor bare to påstande fra to kilder — håndteres indfødt. Det gør det også muligt at vise *årbogens egen udvikling* over tid.
- **Samme model gælder relationer** (omstridt ejerskab, usikker afstamning) og **identitet** (er to kilders "Christian Reventlow" samme person?). Identitetssammenkædning kan holdes pragmatisk i PoC'en og strammes senere.

Resultat: variation forbliver *synlig*, samtidig med at der er en eksplicit, sporbar autoritet.

---

## 7. Privatliv / GDPR

- **Levende vs. afdøde** som grundfelt på personen. Afdøde/historiske data kan være relativt åbne; levende kræver samtykke og dataminimering.
- **Granularitet pr. levende person** — den enkelte kan styre synlighed (fx kun fødeår, ingen børn).
- Denne opdeling er *også* forretningsmodellen: det historiske arkiv kan åbnes for forskere (betalt), mens det levende netværk forbliver privat for medlemmer.

---

## 8. Interoperabilitet

- **Import:** seed PoC'en med en GEDCOM-eksport fra familiens TNG-base.
- **Eksport:** fladgør til den gældende konklusion; bevar afvigelser som alternative fakta/noter så vidt GEDCOM tillader.
- **Udvidelse:** adelsbegreber der ikke findes i standarden defineres som dokumenterede GEDCOM 7 extension-tags (SCHMA), så TNG-kompatibiliteten bevares.

---

## 9. Forfininger fra stresstest mod virkelige data (DAA Reventlow-særudgaven)

Modellen blev holdt op mod hele værket — det heraldiske forsatsstof (s. 1-92), alle fem linjer i stamtavlen (s. 93-247), portræt-/maleri-galleriet (s. 248-384) og bagstoffet med forkortelser, bibliografi og register (s. 385-414), inkl. de fyldige biografier omkring C.D.F. Reventlow. Ingen strukturelle huller fandtes; nedenstående er justeringer, modellen skal bære:

- **Periodemodellen skal have et fuldt kvalifikatorsæt.** Ud over eksakte og afgrænsede perioder optræder: åben/igangværende ("1966–"), indtil en begivenhed ("1952–†"), cirka ("ca. 1976"), før/efter, og **floruit** — en *dokumenteret-aktiv* periode ("-1272-1314-"), distinkt fra levetiden og uundværlig for personer uden fødsels- eller dødsdato. En post/rolle kan desuden bære mere end én dato: en beslutnings-/resolutionsdato og en virkningsdato ("…9. dec. 1776, fra 1. jan. 1777 at regne").
- **Ejendom har sin egen tidslinje.** Godser oprettes, ophøjes til grevskab, sammenlægges, deles og får parceller frasolgt (Bukkehave → Danstedgaard → grevskabet Christianssæde 1777; Lungholm frasolgt 1784). Event- og relationsmekanismen gælder derfor også Ejendom↔Ejendom, ikke kun person→ejendom.
- **Bevar bogens eget løbenummer + udgave som eksternt kilde-ID** på personen. Det opløser interne henvisninger ("se nr. 25") og mapper tilbage til den trykte side.
- **Kontrollerede ordlister** for dekorationer (Fr.IX.M.T., D.Ht. …), roller og forkortelser (m.a., fmd., cand.phil.) — referencedata, så de ikke gemmes som fri tekst.
- **Relative dato-/stedhenvisninger** (s.å., s.st., s.m.) opløses til absolutte værdier ved import; påstanden bevarer den oprindelige tekst.
- **Krydsreferencer rækker ud over DAA.** Henvisninger peger også på internationale referenceværker (Gotha GGT/GHdA, Europäische Stammtafeln, ADB/NDB, DBL). KILDE_VÆRK og krydsreference-feltet skal kunne pege på eksterne værker, ikke kun DAA-udgaver.
- **Stedgranularitet er godsforankret.** Sogn/herred/amt/kreds anføres primært ved godser, ved første forekomst i slægtens eje. STED-data bliver derfor sparsom og knyttet til Ejendom ved import.
- **Status for kendte huller.** Bogen dokumenterer sin egen ufuldstændighed (flere hundrede middelalderdokumenter endnu ikke indarbejdet). En linje eller person bør kunne bære en status som "kendt hul / endnu ikke undersøgt".
- **Segl som dokumenterende artefakter.** Et segl afbilder våbnet og er knyttet til en person og et dateret dokument — rummes som medie/kilde med afbilder- og brugt-af-relationer.
- **Caveat — ujævnt kildeapparat.** Kildebelægget er uensartet: de heraldiske essays og biografierne har fodnoter, mens stamtavlen har implicitte datoer-som-kilder. En bibliografi findes dog på listeniveau (anvendt litteratur, kildesamlinger, forkortelsesnøglens referenceværker), så KILDE_VÆRK-entiteterne kan opregnes fra bagstoffet. Modellen er klar til rig kildebelæg, men koblingen påstand→citation skal genskabes — tæt for heraldik/biografier, tynd for stamtavlen. Modstridende fakta forekommer eksplicit på tryk (fx "† 18. jan. 1821 (1. jan. 1820?)") og bekræfter påstand/konklusion-modellen direkte.

---

## 10. Beslutninger

**Besluttet:**
- **Embede vs. organisation:** rolle ind i en organisation som standard; "forfremmes" til egen entitet hvor successionen er interessant.
- **Medie-metadataniveau:** alle medier er objekter, men kun de tunge (malerier, portrætter) får rig metadata; tilfældige fotos holdes lette.
- **Identitetssammenkædning:** pragmatisk i PoC, strammes senere når I går længere tilbage.
- **Tenure-mønsteret** som langtidsløsning for titler/godser/embeder, med *fleksibel periode* (afgrænset, livslang forankret til fødsel→død, eller afledt af en besiddelse) og en *erhvervelsesmåde* på relationen.
- **Den fulde påstand/konklusion-model.**

Ingen åbne beslutninger pt.
