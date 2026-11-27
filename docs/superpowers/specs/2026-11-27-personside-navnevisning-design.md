# Navnevisning på personsiden og i stamtræet — design

**Dato:** 2026-11-27 · **Gren:** `feat/personside-navnevisning` · Bygger på #499 (linjernes adelsnavn, §56).
**Status:** godkendt af projektejeren 2026-11-27. Bygget på grenen `feat/personside-navnevisning` (core, web, mobil og to runbooks; runbookene er ikke kørt i prod).

## Hvorfor
Personsiden skrev navnet seks gange og »Greve« tre gange (brødkrumme, H1, titellinje, »I Aarbogen«, Fakta·Navn med
1939-variant, billedtekst). Projektejeren ønsker en samlet og logisk brug af navnet: ét navn i overskriften, én linje
der siger personens stand og titel, og samme regel i web, mobil og stamtræ.

## Afgjort af projektejeren (26.–27. november)
1. **H1 = brugsformen** (fornavne + fødeslægt), som lister, søgning og træ. Ingifte står under fødenavnet
   (»Beke Ahlefeldt-Laurvig«).
2. **Én statuslinje under H1** erstatter både titellinjen (»Greve«) og blokken »I Aarbogen«.
3. **Partikelform:** stamtavlens skik med linjens adelsnavn (»greve af Reventlow«, »greve de Reventlou«) — ikke
   præsenslisternes »greve Reventlow«.
4. **Algoritmens hof-/rangtitel** står forrest i statuslinjen: »Kammerherre, greve af Reventlow«. Den kaldes ikke
   »bogens titulatur«.
5. **Titel gennem ægteskab er en regel** og kræver ingen kilde: hustruen får mandens adelstitel i feminin form. Mand
   uden adelstitel → ingen titel (en komtesse gift med en mand uden titel er »Komtesse«). Flere ægteskaber → højeste
   titel opnået gennem ægteskab. Et ægteskab med en skilsmisse tæller ikke. Kun kvinder.
6. **»gift«**, ikke »ved ægteskab«, og intet »·«: »Komtesse, gift lensgrevinde af Reventlow«.
7. **Titlen følger navnet:** et sted, der viser fødenavnet, viser fødselstitlen. Bekes kort i stamtræet er
   »Beke Ahlefeldt-Laurvig · Komtesse«, ikke lensgrevinde. Ægteskabets titel står kun sammen med »gift … af …«.
8. **Stamtræet** viser ét titelord, ikke hele statuslinjen.
9. **Fakta:** etiketten »Navn« bliver »Fornavne«.
10. **Billedtekster og biografi røres ikke.** Søgning på gift navn (»Beke Reventlow«) droppes.
11. **Køn for ingifte udfyldes efter en regel** (se Data).
12. **Titulatur-rækken** (bogens ordlyd fra slægtledsoverskrifterne) er **ikke** med her; den hører under
    genimport-styringen, fordi 2018-20's forældreoverskrifter ikke er i kildelaget.

## Mål, ikke-mål, anti-mål
- **Mål:** statuslinjen på personsiden (web + mobil), titelordet i stamtræet (web + mobil), »Fornavne«, køn udfyldt,
  skilsmisse vist overalt hvor ægteskabet vises, skilsmissedatoer udfyldt.
- **Ikke-mål:** tyske former (Graf zu/von) — venter til en eventuel tysk udgave. Brødkrumme, billedtekster,
  biografi, præsenslisten, søgning, Titulatur-rækken, udtræk af stillinger fra biografierne.
- **Anti-mål:** statuslinjen viser **aldrig en titel, personen ikke havde**. Ved tvivl vises mindre, ikke noget
  gættet. En ingift kvinde må aldrig fremstå som født Reventlow.

## Statuslinjen — regel
Statuslinjen sættes sammen af højst tre dele, i denne rækkefølge, adskilt af », «:

```
[hof-/rangtitel], [egen adelstitel][ partikel-adelsnavn][, gift <feminin mandstitel> <mandens adelsnavn>]
```

Første bogstav i linjen er stort; resten står med lille som i bogen.

| Person | Statuslinje |
|---|---|
| Født, V-linjen, kammerherre | Kammerherre, greve af Reventlow |
| Født, IV-linjen | Greve de Reventlou |
| Født datter, V-linjen | Komtesse af Reventlow |
| Født, linje uden adelsnavn-regel (fx friherre) | Friherre |
| Født, ingen adelstitel, kammerherre | Kammerherre |
| Ingift, komtesse, gift lensgreve af V-linjen | Komtesse, gift lensgrevinde af Reventlow |
| Ingift uden egen titel, gift greve af IV-linjen | Gift grevinde de Reventlou |
| Ingift komtesse, gift mand uden adelstitel | Komtesse |
| Født komtesse, gift greve fra anden slægt (titel kendt) | Komtesse af Reventlow, gift grevinde Ahlefeldt-Laurvig |
| Ingen titler overhovedet | (ingen statuslinje) |

**Delene:**
- **Egen adelstitel** = `person.title` (`visning_titel`), kun hvis den står på `ADELS_TITLER`
  (`packages/core/src/adelsTitler.ts`). Målt i prod 27/11: ingen person har mere end én adelstitel, så »højeste egne
  titel« er i dag det samme som den ene. Funktionen skal alligevel vælge efter rang, hvis der kommer flere
  (lensgreve > greve; for kvinder kun fødselstitlen, jf. punkt 7). Bogens stavning bevares (128 har »comtesse«).
  *Min beslutning:* en kvindes titel regnes som ægteskabstitel — og flyttes til gift-delen — når den er lig den
  feminine form af en ægtefælles adelstitel; ellers er den hendes egen. Så gælder punkt 7 som regel, ikke som et
  tilfælde af dagens data.
- **Rangfølge** (*min beslutning*): komtesse/comtesse < friherreinde = baronesse < grevinde < lensgrevinde <
  rigsgrevinde; friherre = baron < greve < lensgreve < rigsgreve. `feminiserTitel` dækker allerede greve, lensgreve,
  baron, friherre og rigsgreve; komtesse er aldrig en ægteskabstitel.
- **Partikel-adelsnavn** = `personensAdelsnavn(id, lineage, adelsnavne)` som i #499, med samme fail-closed-regler
  (ingen regel, linjens stifter, modstridende linjer → intet adelsnavn). Uden adelsnavn står adelstitlen alene. Det er
  præcis `formelNavneform` uden fornavnene.
- **Gift-delen** (kun `koen = 'kvinde'`): for hver ægtefælle i `spousesBy`, hvis ægteskabet ikke står i
  skilsmisse-indekset (se Skilsmisse) og mandens `title` er en adelstitel med en feminin form (`feminiserTitel`, i dag i
  `web/src/data/presens.ts` — flyttes til `packages/core`). Højeste rang vinder ved flere (lensgrevinde > grevinde >
  friherreinde/baronesse). Mandens adelsnavn = `personensAdelsnavn(mandens id, …)`; uden det bruges mandens
  **slægtsnavn uden partikel** (»gift grevinde Ahlefeldt-Laurvig«) — projektejeren 27/11. Slægtsnavnet er slægtens
  navn (`model.slaegtsnavn`), når manden har en linje i slægten; ellers udelades hele gift-delen i denne leverance.
  (Mænd uden linje har i dag ingen adelstitel som faktum, så intet går tabt; deres slægtsnavn — fx via
  `fødenavn` — følger med, når deres titler hentes ud, jf. Skal løses senere.)
  Gift-delen gælder **alle kvinder**, også født Reventlow (»Komtesse af Reventlow, gift grevinde
  Ahlefeldt-Laurvig«) — projektejeren 27/11.
  *Målt 27/11:* ingen ingift mand har en adelstitel som faktum (deres titler står i prosaen og vielsesteksterne). Født
  Reventlow-kvinder gift uden for slægten får derfor ingen gift-del med dagens data; reglen står klar, til mændenes
  titler er hentet ud.
- **Hof-/rangtitel** = algoritmen (næste afsnit). Højst én. Kun mænd i denne leverance (se Skal løses senere).

## Titelalgoritmen
Kilde: personens afklarede `titel`-fakta (personsidens `faktaInput.rows`) og embedernes rolle (`detail.offices`; mobil
tilsvarende). Algoritmen er målt mod 109 koblede forældreoverskrifter i 2018-20 (memory, 26/11): 72 % rigtige, aldrig
en titel personen ikke havde, ca. hver femte uden overskrift får en titel.

1. **Normalisér** hver værdi: små bogstaver; fjern parentes; tag teksten før første komma; fjern præfikserne
   `karakt.`, `karakteriseret`, `titulær`, `virkelig`, `preussisk`, `tysk`, `dansk`, `kgl.`, `kongelig`; skær ved
   første ` i | hos | af | à | ved | for | under | til | in | over ` (»amtmand over …« → »amtmand«).
2. **Frasortér** adelstitler (`ADELS_TITLER`), ordener (`hvid ridder`, `blå ridder`, `storkors`,
   `kommandør af dannebrog`) og alt, der ikke står på den tilladte liste.
3. **Stiger:** kun det højeste trin pr. stige tæller.
   - kammerjunker < kammerherre < overkammerherre
   - jagtjunker < hofjægermester < overhofjægermester
   - justitsråd < etatsråd < konferensråd < gehejmeråd < gehejmekonferensråd < gehejmestatsminister
   - sekondløjtnant < løjtnant < premierløjtnant < kaptajn = ritmester < major < oberstløjtnant < oberst <
     generalmajor < generalløjtnant < general
4. **Vælg én** efter rangfølgen (højest først) — det er også den tilladte liste:
   storkansler, kansler, gehejmestatsminister, statholder, højesteretspræsident, regeringspræsident, overkammerherre,
   gehejmekonferensråd, geheimekonferensråd, general, gehejmeråd, generalløjtnant, generalmajor, gesandt, rigshofråd,
   konferensråd, stiftamtmand, kammerherre, hofjægermester, oberst, oberstløjtnant, verbitter, landdagsmarskal,
   amtmand, etatsråd, professor, landråd, major, kaptajn, ritmester, høvedsmand, ridder, premierløjtnant, løjtnant,
   kammerjunker, foged — plus stigernes øvrige trin (sekondløjtnant, justitsråd, jagtjunker, overhofjægermester).
   Et ord uden for listen giver ingen titel (fail-closed).

Titel-fakta og embedsroller er ligestillede input (som i målingen); begge normaliseres ens. Embedet skal give
algoritmen sin **rå rolle**, ikke etiketten »rolle · organisation«: `PersonOffice` (web) og `OfficeRef` (mobil) får
feltet `rolle`. Målt 27/11: ingen født kvinde har en titel, der er den feminine form af sin mands titel, så reglen om
ægteskabstitler flytter ingen fødselstitel i dag. Levende personer ses kun
af redaktører, som har detaljerne, så de får samme behandling.

Algoritmen er en ren funktion i `packages/core` med målescriptets tilfælde som tests. Statuslinjen vises med adelsdelen
med det samme og får hof-titlen, når personens detaljer er hentet (samme linje, ingen ny række).

## Stamtræet
Kortet viser `person.title`, når det er en adelstitel — personens **egen** titel, aldrig ægteskabets (punkt 7). Det er
i dag allerede tilfældet, fordi ingen ingift har en ægteskabstitel som eget faktum (målt 27/11: kun 2 ingifte har en
adelstitel — en komtesse og en grevinde; grevinden vises som hun står, se Åbne punkter). Ændringen er derfor, at
titelordet udvælges af samme kernefunktion som statuslinjens egen adelstitel, så de ikke kan skilles ad. Web:
`web/src/components/FokusTrae.tsx:61`. Mobil: `mobile/src/app/(tabs)/tree.tsx:441` og `:527`.
Hof-titlen kommer **ikke** i træet.

## Fakta
`packages/core/src/faktaVisning.ts:7`: `navn: 'Navn'` → `navn: 'Fornavne'`. Gælder web og mobil.

## Data: køn for ingifte (prod-skrivning)
659 personer har tomt køn (målt 27/11). Regel: ser man på **alle** personens familier, og er alle modparter mænd, er
personen kvinde; er alle kvinder, er personen mand. Blandede modparter → redaktørlisten (målt: 0).

| Udfald | Antal | heraf levende | Håndtering |
|---|---|---|---|
| Alle modparter mænd → kvinde | 319 | 14 | regel (afdøde); levende på redaktørliste |
| Alle modparter kvinder → mand | 317 | 8 | regel (afdøde); levende på redaktørliste |
| Ingen ægtefælle registreret | 21 | 0 | redaktørliste |
| Modparten har også ukendt køn | 2 | 0 | redaktørliste |

- Projektejeren valgte reglen for hustruer; at den også gælder spejlvendt for ægtemænd er *min beslutning* (samme
  logik, og »Far/Mor« i træet har brug for begge).
- **Levende tages ikke med i reglen** (*min beslutning*): et nutidigt ægteskab kan være mellem to af samme køn. De 22
  sættes af en redaktør via `red_set_koen`.
- Skrives som én runbook i samme form som `docs/runbooks/2026-11-26-linjernes-adelsnavn.sql`: prøvekørsel som
  standard, ét ændringssæt (kan fortrydes med `red_fortryd_change_set`), backup før, kørt via Supabase MCP efter
  projektejerens ja. Redaktørlisten (person-id'er, ingen navne) lægges i `~/.private/`, aldrig i repo'et.
- Ingen DDL. Ingen ny anon-grant.
- Bivirkning, ønsket: »Forælder« bliver »Far«/»Mor« i stamtræet (`packages/core/src/fokusTrae.ts:52`), og
  præsenslisternes kønsafhængige ord bliver rigtige for flere.

## Skilsmisse — vises, hvor ægteskabet vises (projektejeren 27/11)
Udløser: en levende, skilt person vises i dag som gift alle steder.

**Visning** — bogens form »gift …, skilt 12. okt. 1901« (2018-20 skriver »…, skilt <dato>« efter vielsen):

| Hvor | I dag | Efter |
|---|---|---|
| Personsiden, »Gift med« | X · ⚭ 3. maj 1890 | X · ⚭ 3. maj 1890, skilt 12. okt. 1901 |
| Stamtræet, rækken »Gift« (web + mobil) | ⚭ X | ⚭ X, skilt |
| Præsenslisten | · g. m. X | · g. m. X, skilt 1901 |
| Statuslinjen | — | skilt ægteskab giver ingen gift-del (ovenfor) |

Uden dato står blot »skilt«. Den skilte ægtefælle bliver stående (forælder til børnene, og bogen nævner hende/ham).
Personsiden viser hele datoen; træet intet år (pladsen); præsenslisten kun året (listens korte form).

**Data i appen:** 20 skilsmisse-fakta i prod, alle på `family` og afklarede. Målt 27/11 som anon: 15 er offentlige
(afdøde par), 4 er skjult (begge partnere levende) og 1 er skjult af `family_offentlig` af anden grund;
anon ser 15. De hentes **én gang i modellen** (som `adelsnavne`: fact → afklaret conclusion → assertion) til et
indeks familie-id → skilsmisse, som personside, træ, præsensliste og statuslinje deler.
**Fejl i opslaget er fail-closed** (rettet efter review): opslaget giver `null` (ukendt), ikke `{}`. Mens det er
ukendt, vises ingen »skilt«, men **ingen gift-del i statuslinjen og ingen overtaget ægtefælle-titel i præsenslisten**
— en skilt kvinde må aldrig fremstå som gift, fordi et opslag fejlede.

**Præsenslisten har tre steder, der behandler en ægtefælle som gift** (alle tre retter sig efter indekset):
1. »· g. m. X« → »· g. m. X, skilt 1901«.
2. Navnet: en ingift kvinde vises med mandens titel og efternavn (`mapPresensNavneDele` via `aegtefaelleIdById`,
   web og mobil). En skilt ægtefælle springes over, så hun står under sit eget navn.
3. Enke-gruppen (»Enke efter afdød blodforfader«, `presensListe.ts`) og `efterlevendePartner`: en levende, skilt
   ægtefælle er ikke enke og tæller ikke som efterlevende — *min beslutning*.

**Datoerne (prod-skrivning):** alle 20 påstande har i dag `date_raw = 'skilt'` og ingen `date_min`/`date_max` —
importen tabte datoen. 2018-20's råtekst har ca. 18 omtaler af »skilt«, heraf 17 med dato (målt 27/11 i
`work/raw_full.txt`), så alle skilsmisser kom med; kun datoerne mangler.
- Et deterministisk script (SQL/regex, **ingen model**: nogle tekster handler om levende) finder datoen i partnernes
  biografi i `narrative` **fra den udgave, skilsmisse-påstanden citerer** (2018-20: »skilt <dato>«; 1939 også
  »ægteskabet opløst/ophævet <dato>« og datoer uden punktum som »7 Mar. 1920«). **Kun entydige fund skrives:**
  partneren har præcis én skilt familie, biografierne giver præcis én dato, og datoen ligger ikke før vielsen (så en
  ægtefælles tidligere skilsmisse ikke tages). Resten → redaktørlisten i `~/.private/`.
  Målt 27/11 (kun antal): 14 skilsmisser citerer 2018-20 og 6 citerer 1939 (1939's råtekst har ca. 6 omtaler, så
  1939's skilsmisser kom også med). Alle 20 har en biografi i egen udgave; 14 entydige (10 + 4), 2 flertydige, 4 uden
  dato i teksten → ca. 6 på redaktørlisten, før vielses-tjekket.
- Skrivevej: `red_upsert_fakta('family', id, 'skilsmisse', NULL, date_min, date_max, NULL, date_raw, kilde_fritekst)`
  — en **ny påstand** med afklaret konklusion; den gamle (»skilt«) bevares (invariant 1). Kilden er fritekst, der
  nævner »Dansk Adels Aarbog 2018-20« (`red_upsert_fakta` sætter `source_id` NULL, kendt begrænsning #389).
  OCR-rettelsens veje passer ikke: `red_ret_ocr_paastand` tager kun personfakta, og `red_ret_paastand` kræver et
  fortolkningsforslag. `date_raw` = bogens tekst (»12. okt. 1901« / »1901«); `date_min`/`date_max` = dagen eller
  året.
- Runbook som køn-rettelsen: prøvekørsel som standard, ét ændringssæt, kan fortrydes, backup før, kørt via MCP efter
  projektejerens ja. **Output er kun antal** — datoer og navne vises aldrig i chat eller repo.

## Hvad rammer prod
- **Data:** køn på op til 614 afdøde personer (et ændringssæt) og skilsmissedatoer på op til 20 familier (et
  ændringssæt). Intet andet skrives.
- **Skema:** intet. **RLS/grants:** intet nyt.
- **Web:** ny statuslinje, »Fornavne«, træets titelord via kernefunktion, »skilt« på personside, træ og præsensliste.
  Mobil er dev-only, men følger med (paritet).
- Rækkefølge: runbookene kan køres før eller efter merge; uden køn mangler »gift …« blot for de berørte, og uden dato
  står der »skilt« uden dato.

## Tilgange (overvejet)
1. **Beregn i klienten med en kernefunktion (valgt).** Alt input findes allerede i appen (`title`, `spousesBy`,
   `lineage`, `adelsnavne`, personens titel-fakta og embeder); kun skilsmisse er et nyt, lille opslag. Ingen DDL,
   ingen prod-ceremoni, og web og mobil deler logikken.
2. **Ny cachekolonne `visning_status` i databasen.** Én sandhed for alle flader, men statuslinjen afhænger af
   *andre* personer (ægtefællens titel og linje), så `regen_person_visning` skulle regenerere på tværs af personer —
   en ny klasse af cache-afhængigheder, plus DDL, upgrade-test og prod-ceremoni.
3. **Gem statuslinjen som et redaktionelt faktum.** Ordret og kildebundet, men 2.000+ håndskrevne linjer, og det
   modsiger punkt 5 (ægteskabstitlen er en regel, ikke en kilde).

## Overladt til builderen
- Filplacering og navne i `packages/core` (fx `statuslinje.ts`, `titelAlgoritme.ts`).
- Hvordan web og mobil får fat i titel-fakta og embedsroller (findes i detaljerne begge steder).
- Tests: målescriptets kategorier som fixtures; eksemplerne i tabellen ovenfor som enhedstests; paritetstesten
  dækker det nye skilsmisse-opslag i begge apps.
- Typografi for statuslinjen (genbrug den nuværende bordeaux-titellinje).

## Skal løses senere (noteret 27/11)
- **Kvinders egne hof-/embedstitler** (Bekes »dekanesse, lektor«) skal ultimativt med i statuslinjen
  (projektejeren 27/11), men algoritmen er kun målt på mænd. I denne leverance får **kun mænd** algoritmens titel.
  Kræver: måling på kvinder (fx mod »med …«-overskrifter og vielser) og en kvindelig titelliste. Funktionen tager
  `koen` som input, så udvidelsen ikke ændrer signaturen.
- **Ingifte mænds adelstitler** findes kun i prosa/vielsestekster; uden dem får født Reventlow-kvinder gift uden for
  slægten ingen gift-del (se Statuslinjen).
- **Den ene ingifte med »grevinde« som eget faktum**: kan være en ægteskabstitel registreret som egen. Står på
  redaktørlisten.
