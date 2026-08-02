# Evidensbaseret genimport, kildepersoner og multi-slægt

**Dato:** 2026-08-02

**Status:** Godkendt design. Ikke implementeret. Arbejdet sættes på pause efter dette notat.

**Scope:** Fremtidig genimport af DAA 2018–20 og DAA 1939 samt en generel model for flere slægter og kilder.

**Ikke autoriseret af dette notat:** kodeændringer, migrationer, udtræk, databasekørsler, sletning af eksisterende data, produktionsændringer eller implementeringsplan.

## 1. Beslutning

Den fremtidige genimport skal være **evidensbaseret og observationsdrevet**. Kilden udtrækkes bredt én gang til et varigt internt observationslag. Kun sikre, godkendte fortolkninger forfremmes til den kanoniske genealogiske model.

Målet er ikke at forudsige alle fremtidige forskningsspørgsmål. Målet er at bevare tilstrækkeligt granulære, ordrette og kildeforankrede observationer til, at nye klassifikationer normalt kan foretages uden ny OCR, resegmentering eller grundudtræk fra PDF.

Den valgte hovedretning er:

```text
PDF-side
  → tekstgengivelse
  → kildepost
  → kildeobservation
  → kildeomtale og kildeperson
  → fortolkningsforslag
  → godkendt kanonisk person/familie/fact/relation
```

Slægt, kanonisk linje, en bestemt kildes linjeinddeling og præsenslistens nummerering skal samtidig adskilles. Én fysisk person skal kunne optræde i mange kildeposter, kilder, slægter og linjer uden at blive vist som flere personer.

## 2. Invarianter

Designet bygger på følgende bindende invarianter:

1. **Originalen er uforanderlig.** PDF, sidebillede, OCR-versioner og rå tekst overskrives aldrig.
2. **Kildeudsagn og slutninger adskilles.** Hvad kilden siger, hvad deterministisk kode udleder, hvad en model foreslår, og hvad en redaktør godkender, er forskellige lag.
3. **Ingen evidens uden anker.** Strukturerede forslag skal pege på et præcist, ordret kildeudsnit.
4. **Ingen tavse tab.** Hver meningsbærende klausul får en disposition; uklassificeret eller usikker er gyldigt, manglende bogføring er ikke.
5. **Ingen tvungen sikkerhed.** Tvivl og alternative fortolkninger bevares, aldrig skjules gennem et vilkårligt valg.
6. **Én fysisk person i den kanoniske model.** Flere kildeoptrædener er ikke flere mennesker.
7. **Ingen automatisk identitetsgæt.** Uden tilstrækkeligt entydigt anker går identiteten til redaktionel kontrol.
8. **Kildespecifikke narrativer bevares separat.** Identitetssammenkædning betyder ikke, at kildetekster skal flettes eller ensrettes.
9. **Slægt, linje og nummerering er forskellige begreber.** Romertal er labels i en ordning, ikke globale identiteter.
10. **Indgiftning er ikke slægtsmedlemskab.** En ægtefælle får ikke automatisk ægtefællens slægtsnavn eller linjemedlemskab.
11. **Kanonisk model er konservativ.** Det brede kandidatlag må være fleksibelt; den genealogiske kerne må kun rumme afklaret, principiel struktur.
12. **Alt nyt er generelt.** Ingen permanente tabeller eller kolonner må være særlige for Reventlow, DAA 1939 eller en konkret OCR-fejlklasse.
13. **Slægtled er kontekst, ikke personidentitet.** Bogens slægtled bevares pr. kildeplacering; ægteskab flytter ikke personer mellem slægtled.
14. **Forekomstanker er ikke personanker.** En record_key identificerer en bogpost, mens personidentitet afgøres særskilt på positiv evidens.
15. **Våben og beskrivelser er selvstændige, genbrugelige entiteter.** De knyttes til relevante subjekter gennem generelle relationer og versionsstyret tekst, ikke gennem særlige kolonner på hver objekttype.

## 3. Hvorfor den nuværende selektive rygrad ikke er nok

Det eksisterende 2018–20-udtræk er allerede rigt: 591 poster rummer 1.157 fakta, 801 embeder/hverv, 361 godstilknytninger, 169 delte historiske begivenheder og 347 ægteskaber. Det er et stærkt kontrolmateriale, men ikke et tabsfrit observationsprodukt.

De vigtigste dokumenterede huller er:

- ingen af de 1.157 fakta og ingen af de 347 ægteskaber har præcist `kilde_span` i det gamle 2018–20-artefakt;
- indgiftede har ofte datoer, erhverv og forældre, men ingen struktureret kønskilde, særskilt titel eller særskilte godser;
- civile stillinger, uddannelse, rejser, bopæl og mange daterede handlinger er bevidst blevet efterladt i narrativet;
- titel, stand, hofstilling, militær rang, embede og erhverv er ikke klassificeret tilstrækkeligt stabilt til ukendte fremtidige formål;
- valideringen har især målt, om udtrukne værdier findes i segmenterens tekst, ikke om hele bogen er dækket;
- 1939 har vist, at personafgrænsning og mapping kan være en større fejlkilde end selve tegn-OCR'en.

Det tidligere artefakt skal derfor genbruges som regression og fejlkatalog, ikke kopieres ukritisk som ny sandhed.

## 4. Kildelaget

### 4.1 `source_rendition`

En bestemt gengivelse af en kilde:

- original PDF eller sidebillede;
- PDF'ens indbyggede tekstlag;
- ABBYY-, Calamari- eller anden OCR;
- menneskeligt korrigeret transskription.

Rækken bærer et uigennemsigtigt rendition_key samt mindst fil-/inputhash, metode, sprog, version, oprettelsestid og henvisning til den overordnede `source`. rendition_key er identiteten; content-hash er et kontrol- og deduplikeringssignal. To forskellige metoder må derfor bevares som to renditions, selv hvis deres bytes er identiske. Flere gengivelser eksisterer samtidigt. En foretrukken gengivelse markeres uden at slette de øvrige.

### 4.2 `source_record`

En stabil, logisk post eller sektion i kilden. Den får et uigennemsigtigt varigt ID og en stabil `record_key` inden for kilden.

En kildepost kan være:

- nummereret personpost;
- oversigtsafsnit;
- indledning;
- note;
- tabel eller anden strukturel enhed.

Posttypen afgør ikke, om der oprettes en person. En oversigtsomtale må ikke blive til en kanonisk person alene, fordi segmenteringen har produceret en post.

### 4.3 `source_observation`

Den centrale nye enhed er den mindste fuldstændige, meningsbærende kildeklausul. Den bærer:

- varigt uigennemsigtigt ID;
- `source_record_occurrence_id`;
- side og fysisk placering;
- start/slut-position i en tekstgengivelse;
- eventuelle billedkoordinater;
- ordret tekst;
- kort kontekst før og efter;
- OCR-/transskriptionsversion;
- kvalitetsstatus: klar, OCR-usikker, afklippet, strukturelt tvivlsom eller ulæselig.

Position og teksthash er genfindings- og kontrolsignaler, ikke observationens identitet.

Observationen kan derfor udtrækkes, mens occurrence endnu er uforankret. Når en source_record_anchor_event accepterer forbindelsen, får observationer og mentions logisk record-kontekst gennem ankret; rå observationer omskrives ikke.

### 4.4 `source_observation_text`

Samme fysiske passage kan have flere transskriptioner. Tabellen forbinder observationen med hver gengivelses ordrette tekst og position. En menneskeligt godkendt tekst kan være foretrukken, mens rå OCR bevares.

En rettelse opretter en ny version; den gamle tekst muteres ikke.

### 4.5 Ankerkontrakt og record-versioner

Modellen skelner mellem et forekomstanker og et identitetsanker.

Et forekomstanker identificerer en bestemt logisk post eller omtale i én bogudgave. Det må ikke fortolkes som identitet for et menneske. Samme menneske kan have flere forekomstankre i samme bog, og forekomster i forskellige udgaver har som udgangspunkt forskellige ankre.

En logisk source_record tilhører den bibliografiske kilde/udgave, ikke en bestemt OCR-gengivelse. Første accepterede segmentering tildeler posten en uigennemsigtig record_key, som registreres i manifest og identitetsregister. Nøglen udledes ikke alene af navn, linje, personnummer, side, slægtled, tekstposition eller teksthash.

Den fysiske forekomst i en bestemt source_rendition registreres først selvstændigt som source_record_occurrence med:

- rendition og extraction run;
- side, spalte og eventuelle billedkoordinater;
- start-/slutposition og ordret tekst;
- fysisk og strukturel fingerprint;
- et uigennemsigtigt occurrence-ID fra segmenteringskørslen.

source_record_anchor_event er den append-only afgørelseslog, som forbinder en occurrence med en logisk source_record. Forslag, accept og afvisning er hver sin uforanderlige, versionsnummererede event; den aktuelle tilstand udledes af den seneste event. En occurrence kan have flere historiske forslag, men højst én aktuelt accepteret forankring. Ved ny OCR kan en accepteret én-til-én-afgørelse forbinde den nye occurrence med den eksisterende logiske record uden at oprette en ny record.

Aktør-id og aktørnavn fryses i afgørelseseventen som auditdata. Aktør-id'et har bevidst ingen fremmednøgle til `auth.users`: både `ON DELETE SET NULL` og cascading ville mutere en append-only event, mens `RESTRICT` ville koble historikkens levetid til kontoadministration. UUID og navnesnapshot bevares derfor uforandret, også hvis auth-kontoen senere slettes. Samme princip gælder `created_by` på append-only observationsversioner.

Hvis segmenteringen splitter eller sammenlægger logiske poster, må en eksisterende record_key ikke genbruges som om kontinuiteten var én-til-én. Der oprettes nye records og eksplicitte source_record_revision_event-rækker med maskinkoderne split_into, merged_from eller replaced_by. Et afvist forslag kan senere foreslås igen som en ny version uden UPDATE af historikken. Tvetydig kontinuitet går til menneskelig review.

Et source_mention-ID identificerer et tekstspan i en bestemt observationsversion. Et source_persona-ID er en uigennemsigtig hypotese inden for én bogudgave og kan samle flere mentions og records. Det overlever ikke stiltiende split eller merge; ændringen versionsføres.

Identitetsankeret er ikke en enkelt teknisk nøgle. Det er den redaktionelt eller fail-closed accepterede forbindelse fra source_persona til kanonisk person, underbygget af positive observationer og kontrolleret for modstrid og global injectivitet. Layoutkoordinater er kandidatbevis og genfinding, aldrig alene identitetsbevis.

## 5. Granularitet

En observation er en hel meningsbærende klausul. Én klausul kan give mange atomiske fortolkninger.

Eksempel:

> Gift 12. Maj 1814 i København med Komtesse Anna X, f. 1792, † 1867, Datter af Kammerherre Y til Z.

Observationen bevares samlet. Fortolkningslaget kan udlede:

- vielse, dato og sted;
- partneromtale Anna X;
- partnerens titel, fødsel og død;
- omtale af Y som partnerens far;
- Y's hofstilling;
- Y's tilknytning til godset Z.

Teksten må ikke splittes så småt, at grammatisk og genealogisk sammenhæng mistes. Omvendt må en hel personpost ikke være den eneste evidensenhed, når en mindre klausul kan dokumentere udsagnet præcist.

## 6. Omtaler og kildepersoner

### 6.1 `source_mention`

Et præcist tekstspan, som omtaler en person, organisation, et sted, et gods, en titel eller en anden identificerbar ting.

En omtale kan være:

- uidentificeret;
- forbundet med en `source_persona`;
- foreslået forbundet med en kanonisk entitet;
- tvetydig mellem flere kandidater;
- afvist som ikke-entitet.

Tredjepersoner som svigerforældre, vidner, monarker og arbejdsgivere bevares som strukturerede omtaler med rolle og kildeudsnit. De oprettes ikke automatisk som kanoniske personer.

### 6.2 `source_persona`

En kildeperson er en intern hypotese om et menneske, som en eller flere omtaler eller kildeposter beskriver. Den er ikke en kanonisk `person`.

Formålet er at kunne importere og redigere kildens personbillede, før det er afgjort, om personen allerede findes, optræder flere steder eller skal oprettes som ny.

Forbindelser:

```text
source_mention
  → source_persona
  → source_persona_identity
  → person
```

`source_persona_identity` er den aktuelle, versionerede identitetsafgørelse. Én kildeperson kan højst forbindes med én kanonisk person; én kanonisk person kan forbindes med mange kildepersoner.

Den aktuelle række er en projektion af en append-only `source_persona_identity_event`-log. En deferred databaseinvariant kræver, at current state og eventloggen stemmer ved commit i begge retninger. Accept, afvisning og uafklaret-status skrives atomisk gennem en `SECURITY DEFINER`-funktion med `expected_version` og persona-rækkelås. Aktør-id og navn hentes fra den autentificerede redaktionssession; importpayloadet kan ikke selv angive en menneskelig godkender.

### 6.3 Identitetsworkflow

Efter intern indlæsning foreslår systemet kandidatgrupper ud fra navn, datoer, forældre, ægtefæller, titler, godser, steder, eksterne henvisninger og kronologisk mulighed.

Redaktøren kan vælge:

- samme person;
- forskellige personer;
- delvist sammenfald i en kandidatgruppe;
- forbind med eksisterende person;
- ny person;
- uafklaret.

Uafklarede kildepersoner forbliver interne. Automatisk forfremmelse må kun ske, når identiteten er entydig efter de fastlagte globale og fail-closed gater.

### 6.4 Eksempel: samme mand gift med tre familiemedlemmer

Tre ægteskabsklausuler producerer tre kildeomtaler og eventuelt tre kildepersoner. Systemet foreslår et muligt sammenfald, men gætter ikke.

Hvis redaktøren bekræfter identiteten, bliver resultatet:

- én kanonisk mand;
- tre forskellige `family`-rækker;
- tre partnerrelationer;
- tre separate kildebelæg.

Hvis kun to omtaler er samme mand, kan redaktøren gruppere to og lade den tredje blive en anden person. `samme_som` bevares som reparationsmekanisme for kanoniske dubletter, der opdages senere, men er ikke den normale stagingmodel.

## 7. Fortolkningslaget

### 7.1 `interpretation`

Et versioneret forslag til, hvad en observation betyder. Kandidatlaget må bruge skemavalideret JSON, fordi det skal kunne rumme nye forskningskategorier uden at ændre den kanoniske model for hver ny idé.

Hver fortolkning bærer:

- skemaversion;
- ekstraktionskørsel, model og promptversion;
- eksplicit kildeudsagn, deterministisk afledning, modeludledning eller menneskelig vurdering;
- sikkerhed og status;
- reference til alle bærende observationer og omtaler;
- struktureret værdi, tid, sted, aktører og roller.

En fortolkning er append-only og versioneres med en stabil `interpretation_key`, versionsnummer og `supersedes_id`. En afgørelse opretter en ny version og kopierer de bærende observationslinks; den tidligere version opdateres ikke. En deferred constraint kræver mindst én observation ved commit, så fortolkning og links stadig kan indsættes atomisk i samme transaktion.

Usikre eller uklassificerede fortolkninger bevares internt. De kasseres ikke og tvinges ikke ind i en upræcis faktatype.

### 7.2 Fire generelle udsagnsformer

1. **Egenskab:** subjekt → egenskab → værdi, fx navn, titel eller dødsårsag.
2. **Relation:** subjekt → rolle → person/sted/organisation/gods.
3. **Hændelse:** en forekomst med deltagere, roller, dato/periode, sted og eventuel genstand.
4. **Omtale:** en aktør eller ting findes i teksten, men er endnu ikke identificeret eller kanoniseret.

### 7.3 Kontrollerede biografiske kategorier

Den ordrette betegnelse bevares altid. Normaliseringen skelner mindst mellem:

- adelig eller standsmæssig titel;
- embede;
- hofstilling;
- militær rang;
- erhverv eller civil stilling;
- uddannelse eller grad;
- dekoration eller æresbevisning.

Derudover udtrækkes alle eksplicitte biografiske oplysninger, herunder rejser, bopæl, tjeneste, køb/salg/arv, udnævnelse/afsked, uddannelse og andre daterede handlinger. De behøver ikke straks blive kanoniske fakta.

## 8. Forfremmelse til den kanoniske model

### 8.1 `interpretation_promotion`

Forbindelsen dokumenterer, hvad en godkendt fortolkning blev til, fx `fact`, `assertion`, `relation`, `family`, `person`, medlemskab eller en senere generel hændelse.

Forfremmelse kræver:

- præcist kildebelæg;
- entydigt subjekt eller eksplicit tvivlsstatus;
- gyldig type og kontrolleret vokabular;
- sporbare værdier, datoer og roller;
- tydelig adskillelse mellem udsagn og slutning;
- ingen skjult konflikt med andre kilder.

`interpretation_promotion` refererer den konkrete accepterede fortolkningsversion og et eksisterende kanonisk mål. Promotions er append-only og bærer sessionsafledt aktør, tidspunkt og beslutningsevidens; en senere ny fortolkningsversion omskriver ikke den historiske promotion.

### 8.2 Mapping

- egenskab → `fact + assertion + citation`;
- relation → `relation + assertion + citation`;
- familieudsagn → `family/family_member` med evidens;
- linje-/slægtsmedlemskab → første-klasses medlemskab med evidens;
- kompleks hændelse → kandidatfortolkning og, når et konkret behov er bevist, en generel kanonisk hændelse.

Der bygges ikke nu en stor specialiseret hændelsesmodel. Kandidatlaget bevarer den fulde struktur, så den kan forfremmes senere uden nyt grundudtræk.

## 9. Slægt, linje og nummereringsordning

Den nuværende `lineage` blander slægtsrod, historisk gren, udgavens linje og præsensnummerering. Det er ikke tilstrækkeligt til flere slægter.

### 9.1 `slaegt`

En kanonisk slægt med egen identitet, navn, normalt slægtsnavn og alternative/historiske navneformer. Reventlow er en slægt, ikke en kode-løs kunstig linjerod.

Slægtsnavne med evidens modelleres som påstande. Et praktisk standardnavn kan caches til visning, men er ikke identisk med en kildes ordrette navneform.

### 9.2 Kanonisk `lineage`

En historisk linje eller gren under én `slaegt`:

- `slaegt_id`;
- navn;
- `parent_lineage_id`;
- status;
- eventuel afvigende slægtsnavneform.

Linjehierarkiet er kildeuafhængigt. En grundlægger kan tilhøre både oprindelseslinjen og den nye gren med forskellige medlemsroller.

### 9.3 `lineage_scheme`

En bestemt opstilling eller nummereringsordning, fx:

- DAA 2018–20-stamtavlen;
- DAA 1939-stamtavlen;
- DAA 2018–20-præsenslisten;
- en fremtidig præsensliste.

Ordningen tilhører én slægt og kan pege på en kilde og udgave. `kind` skelner mindst mellem `stamtavle`, `presensliste` og `redaktionel`.

### 9.4 `lineage_scheme_entry`

En post i ordningen med kode, navn, rækkefølge og eventuel forælderpost. Koden er kun unik inden for ordningen:

```text
UNIQUE (scheme_id, code)
```

Dermed kan alle slægter have en `I linje`, og samme kanoniske linje kan være `IV linje` i stamtavlen og `I linje` i præsenslisten.

En forbindelsestabel mellem ordningspost og kanonisk linje tillader nul, én eller flere mappings. Dermed kan en kildes opdeling være grovere eller finere end den kanoniske linjemodel uden at tvinge dem til at være identiske.

### 9.5 `person_slaegt_membership` og `person_lineage_membership`

Medlemskab er mange-til-mange og evidensbåret. Det har mindst rolle/type, sikkerhed, gyldighedsperiode og status.

Roller kan fx være medlem, grundlægger eller dokumenteret optaget/adopteret. Indgiftning registreres gennem familieforbindelsen og er ikke automatisk medlemskab.

### 9.6 Person i flere linjer

En grundlægger, der står som barn i én linje og rod i en anden, bliver:

- én kanonisk person;
- to eller flere `source_record`-optrædener;
- medlemskab af oprindelseslinjen;
- medlemskab af den nye linje med rollen `grundlaegger`.

Personen oprettes ikke flere gange i den færdige model.

### 9.7 Bogens slægtled er kildeplacering

Slægtled i en stamtavle er en strukturel koordinat i en bestemt kildeopstilling, ikke en global egenskab ved personen.

source_record_placement forbinder en source_record med en lineage_scheme_entry og bevarer:

- bogens trykte nummer og ordrette slægtledslabel;
- lokalt og eventuelt gennemgående slægtledstal;
- kuld eller anden undergruppe;
- hierarkisk section path;
- observationen af den overskrift, som placeringen bygger på.

Alle source_record_placements skal have en header-observation. En tabsfri overgang fra de nuværende felter kan ikke opfinde hverken en source record eller en sådan observation; derfor må legacy-felterne ikke migreres til denne tabel, før det relevante kildeudtræk findes og forbindelsen er verificeret.

source_persona_placement forbinder en kildepersona med recordplaceringen og en rolle såsom hovedperson, medhovedperson, omtalt_ægtefælle eller barnehenvisning. Kun en dokumenteret medlemsrolle kan danne grundlag for kanonisk lineage-medlemskab. En ægtefælle arver ikke postens slægtled eller medlemskab.

Eksisterende slaegtled_lokal, slaegtled_gennem og kuld bevares ordret som kompatibilitetsinput, også hvis forskellige udgaver nummererer forskelligt. Efter fuld extraction migreres de kun til kildeplacering, når en accepteret source record og dens header-observation giver positiv provenance; uafklarede rækker forbliver legacy og går til review. De eksisterende læsefelter og projektioner udfases først, når alle SQL-, core-, web-, mobil- og loaderskrivere er inventeret, flyttet og verificeret med paritet. Cutover må ikke efterlade uforklarede legacy-rækker.

### 9.8 Ægteskab på tværs af slægtled

En mand kan gifte sig med sin niece eller med et andet medlem, som bogen placerer i et andet slægtled. Det er ikke en modelkonflikt:

- hver person beholder sin egen kildeplacering og sit eget lineage-medlemskab;
- familie-/ægteskabsrelationen forbinder personerne uden at udligne deres slægtled;
- en omtalt ægtefælle i mandens post får rollen omtalt_ægtefælle og flyttes ikke til mandens slægtled;
- hvis niecen har egen post, bevares den som hendes selvstændige hovedplacering;
- patrilineær medlemskabsregel og ægteskabsrelation behandles som forskellige akser.

Genealogisk afstand eller generation beregnes kun ud fra parent-child-relationer og et angivet udgangspunkt. Spouse edges indgår aldrig i generationsberegningen. Der gemmes ingen enkelt global generation på personen, fordi flere aner, linjer, pedigree collapse og forskellige kilders nummerering kan give flere gyldige kontekster.

## 10. Slægtsnavn og visningsnavn

Bogens ordrette navn forbliver en uforanderlig kildepåstand. Et manglende efternavn i en stamtavlepost må ikke omskrives i evidenslaget.

Slægtsnavnet tilføjes som afledt visning fra dokumenteret medlemskab:

- medlem af flere linjer med samme effektive slægtsnavn → navnet kan afledes entydigt;
- indgiftet uden eget medlemskab → ægtefællens slægtsnavn tilføjes ikke;
- person med medlemskab af egen slægt og ægteskab ind i en anden → eget slægtsnavn bevares;
- flere forskellige slægtsbærende medlemskaber → intet vilkårligt globalt valg; brug kontekstafhængig visning eller redaktionel karantæne.

Brugerfladen viser altid slægtskontekst ved tvetydige linjelabels, fx `Reventlow · II linje` eller det fulde deskriptive linjenavn. En rå label som `II linje` må kun bruges, når slægtskonteksten allerede er entydig.

## 11. Narrativer og flere kildeversioner

Narrativ tilhører `source_record` og `source_persona`, ikke primært den kanoniske `person`.

Hvis samme mand optræder tre steder i 1939 og én gang i 2018–20, bevares fire separate tekster:

```text
én kanonisk person
  ├─ DAA 1939, opslag A, egen narrativ
  ├─ DAA 1939, opslag B, egen narrativ
  ├─ DAA 1939, opslag C, egen narrativ
  └─ DAA 2018–20, opslag D, egen narrativ
```

Teksterne flettes ikke, og rettelser i én tekst kopieres ikke til de andre.

Personvisningen har to lag:

1. **Samlet oversigt:** redaktionelt valgte kanoniske facts, relationer, familie og kronologi.
2. **Kildernes beskrivelser:** alle særskilte narrativer og påstande, grupperet og mærket med kilde, udgave, slægt, ordning, linje, nummer og side.

Tre opslag i samme bog vises som tre opslag/attestationer i samme kilde, ikke fejlagtigt som tre uafhængige kilder.

Modstridende oplysninger bevares som flere assertions. `conclusion` vælger eller markerer omstridt; den sletter aldrig alternative kildepåstande.

Eksisterende rækker i narrative er en overgangskilde, indtil de kan forbindes med accepterede source records. Overgangen er eksplicit og tabsfri: hver legacy-narrativ skal enten mappes ved positiv kilde-/persona-evidens, bevares gennem en navngivet kompatibilitetsprojektion eller arkiveres ved redaktionel beslutning. Tekstlig lighed alene må ikke skabe forbindelsen, og offentlig record-visning må ikke antage fuld source_record-dækning før denne afstemning er grøn.

## 12. Våben, afbildninger og generelle beskrivelser

coat_of_arms er en selvstændig kanonisk entitet, ikke en enkelt kolonne på slægt eller lineage. En evidensbåret relation forbinder et våben med nul, én eller flere slægter, kanoniske linjer eller grene, personer og andre relevante entiteter.

Relationen bærer rolle eller varianttype, gyldighedsperiode, status og provenance. Dermed kan en slægt have flere historiske våben, en gren have en variant, og samme våben kan være dokumenteret for flere enheder uden kopiering.

Et kanonisk våben kan have flere media-afbildninger: bogscanning, fotografi, tegning eller rekonstruktion. Hver media-række beholder filmetadata, kunstner, datering, rettigheder og publikationsstatus. Forbindelsen mellem media og coat_of_arms angiver, at billedet afbilder eller fortolker netop dette våben.

Tre teksttyper holdes adskilt:

1. ordrette kildebeskrivelser bevares som source_record, observationer og assertions;
2. struktureret blasonering er en eller flere kildepåstande om coat_of_arms med en redaktionel conclusion;
3. redaktionel beskrivelse eller billedtekst gemmes i en generel, versionsstyret entity_description.

entity_description kan knyttes til alle kanoniske entitetstyper, herunder person, slægt, lineage, coat_of_arms, media og estate. Den har mindst kind, sprog, tekst, status, offentlighed og version. Kinds omfatter overblik, historie, billedtekst og blasoneringsforklaring. Dens eventuelle source_record-proveniens ligger i en junction-tabel i private schema, som peger ind mod den offentlige beskrivelse; en public tabel eller API må aldrig indeholde private source_record-ID'er. Der oprettes ikke særlige beskrivelseskolonner pr. entitetstype.

entity_description erstatter ikke source_record-narrativer og er ikke en story. source_record bevarer, hvad en kilde skriver; story er en redaktionel formidlingshistorie; entity_description er den stabile redaktionelle beskrivelse af en kanonisk entitet. Den eksisterende narrative-tabel behandles som overgangsmodel og må ikke fortsætte som en fjerde konkurrerende sandhed.

En beskrivelse af et våben og en beskrivelse af en bestemt våbenafbilledning er forskellige poster. Den første knyttes til coat_of_arms; den anden til media. Begge kan have egne kilder og redaktionel historik.

## 13. Indgiftede personer

Indgiftede udtrækkes næsten lige så grundigt som hovedpersonen:

- navn og navnevarianter;
- køn og kønskilde;
- fødsel, dåb, død og begravelse;
- titel, stand, rang, embede, erhverv og uddannelse;
- godser og bopæle;
- forældre som strukturerede omtaler;
- eksterne DAA-henvisninger;
- alle oplysninger om ægteskabet.

Data forankres i ægteskabsklausulen. En indgiftet uden egen nummereret post kan stadig blive en kanonisk person efter identitetsafgørelse. Hvis personen senere importeres fra sin egen slægt, forbindes den nye kildeperson med den eksisterende kanoniske person.

## 14. Udtræks- og korrektionshistorik

### 14.1 `extraction_run`

Binder inputhash, OCR-/tekstversion, segmenter, prompt, model, skemaversion, manifest og resultater sammen. En kørsel er reproducerbar og kan sammenlignes med tidligere kørsler.

### 14.2 Redaktionelle rettelser

Redaktøren kan:

- sammenligne tekstgengivelser;
- rette transskription gennem en ny version;
- godkende, ændre, forkaste eller erstatte en fortolkning;
- forbinde omtaler og kildepersoner;
- forfremme eller trække en forfremmelse tilbage;
- se hele kæden fra kanonisk oplysning til PDF-side.

Varige beslutninger forankres i `record_key`, observations-ID, omtale-ID og kildeperson-ID, ikke i midlertidige person-ID'er, tekstpositioner eller ægteskabsordinaler alene.

Hvis en ny tekstversion ændrer evidensgrundlaget, markeres afhængige beslutninger som mulige `stale` og sendes til kontrol. De genbruges ikke tavst.

## 15. Fuldstændighed og kvalitetsgater

### 15.1 Klausulregnskab

Hver meningsbærende klausul får præcis én primær disposition:

- struktureret;
- relevant, men uklassificeret;
- ikke-biografisk;
- layout-/bibliografisk støj;
- ulæselig OCR;
- kræver menneskelig vurdering.

### 15.2 Blokerende gater

**Kilde og segmentering**

- alle forventede sider og kildeposter er til stede;
- stabile `record_key` er unikke inden for kilden;
- ingen uforklarede overlap eller huller;
- poststart og -slutning kontrolleres mod PDF;
- sidehoveder og næste post må ikke lække ind.

**Observationer**

- ordret tekst findes i den angivne gengivelse;
- side, position og koordinater er gyldige;
- observationen har nødvendig kontekst;
- alternative gengivelser forbindes med samme fysiske passage.

**Fortolkninger**

- alle bærende værdier kan spores til tekstspans;
- udsagn og slutninger er adskilt;
- referencer er entydige eller markeret tvivlsomme;
- kontrollerede vokabularer bruges konsekvent;
- flere oplysninger i samme klausul overskriver ikke hinanden.

**Identitet**

- en kildeperson forbindes højst med én kanonisk person;
- kandidatgrupper vurderes globalt, ikke isoleret række for række;
- dubletter, splits og tvetydighed parkeres frem for at gættes;
- ingen offentliggørelse før afstemningens gate er grøn.

### 15.3 Korpusplausibilitet

Kørslen sammenlignes med tidligere korpus og forventede signaler for mindst:

- livshændelser;
- ægteskaber og skilsmisser;
- indgiftedes egne oplysninger;
- forældre og børn;
- titler, rang, embeder, erhverv og uddannelse;
- godser, bopæl, rejser og andre daterede handlinger;
- dekorationer og adling;
- tredjepersonsomtaler;
- uklassificerede eller ulæselige klausuler.

En teknisk gyldig JSON-fil er ikke en kvalitetsgodkendelse. Absurd lav eller høj kategoridækning blokerer kørslen.

## 16. 2018–20 som referencekorpus

2018–20 bruges til at udvikle og fryse metoden, fordi PDF'en har et pålideligt tekstlag, postgrænserne er forholdsvis klare, de 591 nuværende record keys giver en stærk kontinuitetsbaseline, og det gamle udtræk giver en stærk regression. Kontinuiteten verificeres efter den nye ankerkontrakt; baseline-ID'er genbruges ikke alene, fordi de allerede findes.

2018–20 og 1939 behandles som de to referenceprofiler for moderne DAA-stamtavler. De skal først definere en fælles layoutgrammatik for post, linje, slægtled, nummer, ægteskab og strukturelle afsnit; hver udgave har derefter kun en lille, versionsstyret profil for faktiske afvigelser. Ældre årbøger kan senere få egne profiler uden at ændre record-, observations-, persona- eller identitetsmodellen.

Rækkefølge:

1. frys PDF, sider, tekstudtræk og hashes;
2. opbyg klausulfortegnelse for de 591 poster;
3. vælg et stratificeret pilotfacit med korte/lange, middelalderlige/moderne, flerægteskabelige, ægtefællerige og karrieretunge poster;
4. gennemgå piloten menneskeligt mod PDF;
5. kalibrér vokabular, granularitet, model og gater;
6. frys kontrakten;
7. kør alle 591 poster én gang;
8. sammenlign automatisk mod det gamle artefakt;
9. gennemgå alle undtagelser og en tilfældig grøn stikprøve;
10. frys det varige observationsartefakt.

Nulevende personer behandles i et privat, godkendt miljø og må ikke sendes til ekstern modelbehandling uden særskilt databeskyttelsesgodkendelse.

## 17. Overførsel til 1939

1939 bruger samme observations-, fortolknings-, kildeperson-, slægts- og identitetsmodel. Kun tekstgengivelse og segmenteringsprofil er udgavespecifikke.

Den eksisterende 600 dpi-scanning er tilstrækkelig som original. Rå layouttekst, Calamari og eventuelle andre OCR-versioner bevares som parallelle gengivelser.

En ny fuld OCR-kørsel besluttes kun efter en afgrænset, repræsentativ prøve, der måler både tegnkvalitet og person-/postafgrænsning. En ny OCR accepteres ikke alene, fordi den ser sprogligt pænere ud.

Det eksisterende 1939-v3-artefakt, identitetsregister, manuelle rettelser, tombstones og tidligere match bruges som regression og efterkontrol. De er ikke automatisk facit for den nye uafhængige udtrækning og matchning.

## 18. Internt, kanonisk og offentligt

Der er tre adskilte tilstande:

1. **Internt kilde-/kandidatlag:** observationer, omtaler, kildepersoner, fortolkningsforslag og tvivl.
2. **Kanonisk redaktionel model:** godkendte personer, familier, facts, relationer, medlemskaber og conclusions.
3. **Offentlig projektion:** kun publicerede, privatlivs- og staging-godkendte data.

Kildelaget er ikke offentligt som standard. Nulevende, private, staged og uafklarede identiteter er fail-closed skjult. RLS skal beskytte alle nye tabeller i et eksponeret schema; et privat schema foretrækkes til råt observations- og kandidatmateriale.

## 19. Token- og arbejdsøkonomi

Dyre modeltrin begrænses til fortolkning og undtagelser. Følgende er deterministisk eller lokalt:

- PDF-tekst/OCR;
- segmentering;
- klausulfortegnelse;
- hashes og manifests;
- schema- og substringvalidering;
- kandidatsøgning og korpusdiff;
- databaseprojektion.

Modellen ser én klausul/post ad gangen. Profilen fastlåser eksplicit model-ID, promptversion og eskalationsmodel; extractoren må ikke arve et ambient/default modelvalg. Kørslens manifest registrerer de effektive værdier, og ukendt eller ændret model blokerer merge uden en ny godkendt profilversion. Resultater caches uforanderligt. Kun ændrede, tvivlsomme eller fejlende poster genkøres, og den dyrere eskalationsmodel bruges kun til markerede undtagelser med særskilt budgetregnskab. Sidebilleder beskæres til det relevante område frem for at sende hele PDF-sider, når visuel kontrol er nødvendig.

## 20. Definition af færdigt grundudtræk

Et grundudtræk kan erklæres afsluttet, når:

- original og alle anvendte tekstgengivelser er bevaret;
- alle logiske kildeposter har stabil record_key, og hver rendition-forekomst har fysisk provenance;
- split, merge og re-OCR er bogført med eksplicitte revision-events uden tvetydigt automatisk genbrug;
- alle meningsbærende klausuler er registreret og bogført;
- alle eksplicitte biografiske oplysninger er fortolket eller synligt parkeret;
- personer, steder, organisationer og godser er markeret som omtaler;
- alle fortolkninger har præcist kildebelæg;
- alle afledte oplysninger kan genberegnes;
- trykt slægtled er bevaret som kildeplacering uden at blive global personegenskab;
- slægts-, linje- og våbenbeskrivelser samt billedtekster er bevaret med korrekt tekstrolle og subjekt;
- identitets- og publiceringsgater er fail-closed;
- fremtidige klassifikationer kan foretages fra observationslaget uden ny OCR, resegmentering eller grundudtræk.

En fremtidig forskningsidé kan kræve en ny fortolkning eller kanonisk projektion. Den bør normalt ikke kræve, at PDF'en grundudtrækkes igen.

## 21. Fremtidig arbejdsrækkefølge

Når pausen ophæves, er den godkendte rækkefølge:

1. design fysisk schema og syntetiske fixtures;
2. byg 2018–20-pilotfacit;
3. kør og kalibrér pilot;
4. frys udtrækskontrakt og kvalitetsgater;
5. udtræk alle 591 poster til varigt artefakt;
6. gennemgå undtagelser og stikprøver;
7. byg kanonisk projektion i parallel database;
8. foretag uafhængig identitetsafstemning;
9. brug gamle match som efterkontrol;
10. overfør metoden til 1939 med OCR-/segmenteringspilot først;
11. skift først senere og særskilt godkendt fra gammel til ny database.

Den kritiske vej er evidenskontrakt, privat lag, kildeplacering, identitetsafklaring, extraction, projektion, bogpiloter og cutover-rehearsal. Heraldik-/entity-description-editoren og mobil redaktørparitet er selvstændige, udskydelige spor: de må ikke blokere de første extraction- og identitets-GO'er, men skal have egne gater før de funktioner publiceres.

Den særskilte implementeringsplan beskriver arbejdet. Hverken dette designnotat eller planen giver i sig selv tilladelse til at iværksætte extraction, databaseændringer eller cutover.
