# Beslutninger

Kun ikke-oplagte arkitektur-/design-valg. Detaljer i changelog + memory.

## NOTERET: falsk »formodet« på 1939-forældreled — 30 links tjekkes mod bogens »?«, åben backlog (2026-11-13)

> Projektejeren bemærkede, at person 458's forældre står som »formodet«, selv om de er sikre.
>
> **Årsag:**
> - 458 (2018-20) er foldet sammen med 1939-posten 1347. Dennes forældrelink i familie 617 har `konfidens='formodet'`.
> - Læseren viser det svageste af de sammenfoldede led (invariant 7).
> - `load_daa.R` (ca. linje 936) sætter `formodet`, når udtrækket har `usikker=true`. Det skulle afspejle bogens »?«
>   foran nummeret eller »(?)« efter det.
> - Posten (PDF 580, trykt s. 74, nr. 3) har ingen »?« i nogen af OCR-kørslerne, så flaget stammer ikke fra bogen.
>
> **Omfang:**
> - 30 `family_member`-rækker har `formodet`. 5 af dem kommer fra rettelsen `flyt_boern_moerloes_familie`, de 25 andre
>   fra importen.
> - 39 af 1939-udtrækkets poster har `usikker=true`.
>
> **Slutkriterium:**
> - Hvert af de 30 links er tjekket mod bogens markør, og listen er vist for projektejeren.
> - Links uden markør i bogen er rettet sporbart, enten via redaktørvejen eller via en lille ceremoni med historik.
> - Links med markør bevares som `formodet`.
>
> Tages efter 6e-2.

## NOTERET: 2 staged 1939-poster får ikke læsbar etiket i 6e-2, åben backlog (2026-11-13)

> 6e-2's ceremoni springer 2 publicerede kilde 3-bindinger over. De tilhører personer, der endnu ikke er offentlige
> (staged), og ingen af dem har placement. Revalideringen afviser dem (`NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED`),
> og 6d-1's ceremoni springer dem over efter samme kriterium.
>
> - De beholder `record-<uuid>` og PDF-siden i `citation_label`.
> - Læseren ser dem ikke i dag.
> - **Slutkriterium:** når en af dem bliver offentlig, skal dens binding have den læsbare etiket, enten ved samme ceremoni
>   eller ved en revalidering efter `narrative_record_wanted_labels`.

## BESLUTTET: 6e-2's kildeetiket — hver bog sin egen opslagsnøgle med linjens navn, 1939 med trykte særtryksider; sidekortet er en lille profil som data (2026-11-13)

> Projektejeren, før 6e-2's plan. Detaljer og målinger: `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` §12.
>
> 1. **Hver bog beholder sin egen nøgle.** 2018-20's postetiket »V-1« er uændret. Bogen henviser selv sådan:
>    »se III. Den mecklenburgske linje, nr. 58«. 1939 får »IV, nr. 3« med siden i kildeangivelsen
>    (»DAA 1939, s. 49 · IV, nr. 3«), fordi 1939 kun henviser med sidetal (»se S. 75«).
> 2. **Linjens navn vises altid med romertallet.** Romertallene betyder forskellige linjer i de to bøger: IV og V er
>    byttet om.
> 3. **Tvetydighed accepteres (valg A).** 87 grupper med 194 af 528 placements deler etiket. Side og navn identificerer
>    personen, og poster holdes adskilt på id.
> 4. **Sidetal er særtrykkets trykte sidetal, ikke PDF-siden.** Kortet er fastlagt af trykkeriets arksignaturer og
>    bekræftet af bogens gensidige krydshenvisninger.
>    - Det ligger som data på kilden med én omregningsfunktion. Det er en lille udgaveprofil og justerer 6e-spec'ens
>      §1.3 (»ingen ny udgaveprofil«).
>    - PDF-siden bevares som anker. Ingen påstande eller citationer ændres; kun projektion og genpublicerede etiketter.
> 5. **Linjeskemaets etiketter rettes til bogens ordlyd i 6e-2's ceremoni:** Ziesendorf, »I.«, »VI.« og
>    stammeafsnittenes »A.« og »B.«. Stammeafsnittenes etiket er f.eks. »A, nr. 2«.
> 6. **2018-20's sidetal er allerede trykte sider** (stikprøve: Conrad V-1 på s. 201). 2018-20 får intet sidekort.

## BESLUTTET: redaktøren læser levendes biografi som kladde; udgivelsesreglen røres ikke (2026-11-13)

> Retter pkt. 1 i posten nedenfor (»narrativernes udgivelsesregel ... får en redaktør-gren«). Udgivelsesreglen kan ikke
> få en redaktør-gren: `publication_allowed` (personen afdød, ikke privat, ikke staged, og narrativet ikke privat) er
> bagt ind i den hash-bundne udgivelsestilstand, så en levende persons biografi kan aldrig udgives — med vilje, så den
> aldrig når gæster. Målt på stand-in ≈ prod: 79 ikke-offentlige personer, 56 med biografi, 46 som kladde.
> Projektejeren valgte:
>
> 1. **Kladden vises for redaktøren, mærket.** Personsiden henter, kun for en redaktør og kun for medlemmer gæster
>    ikke kan se, posterne fra den eksisterende redaktør-RPC `red_person_narrative_records` (kladde, udgivet eller
>    forældet-udgivet, med tekst) og viser dem med mærkatet »Ikke udgivet — kun synlig for redaktionen. Kilde:
>    <udgave, side>«. Ingen databaseændring; `person_daa_narrative_publication_allowed` og de offentlige biografi-RPC'er er
>    uændrede.
> 2. Fakta for levende forbliver uden henvisning til bogens post (den følger narrativets udgivelse); familiekilder
>    ligeså. En redaktør-RPC med posthenvisning for fakta blev fravalgt (større, ny overflade).

## BESLUTTET: POC'ets regel for levende: kun redaktionen ser dem; »Det er mig« i to trin; lukker webredesignets åbne punkt 2 og 3 for POC'et (2026-11-13)

> Projektejeren (fase 8): »De levende kommer også med i POC. Jeg er redaktør i dette POC og jeg skal kunne se dem. De
> levende skal bare ikke vises, hvis man ikke er logget ind som bruger.« Derefter valgt: kun redaktørerne ser alt på
> alle; »lav dette til poc, og noter at vi senere skal tage stilling til hvad brugere skal kunne se og på hvilke
> niveauer«.
>
> 1. **Levende i POC'et:** gæster og almindelige indloggede brugere ser ingen levende, private eller staged personer
>    (uændret). Redaktionen ser alt. Tabellerne gør det allerede (`redaktion_read`); det, der mangler, er de
>    SECURITY DEFINER-funktioner bag personsiden (biografi, fakta, familiekilder, kildekoordinater) og narrativernes
>    udgivelsesregel, som i dag kun viser offentlige personer uanset rolle. De får en redaktør-gren
>    (`current_rolle() = 'redaktion'`); gæsternes og brugernes regler røres ikke.
> 2. **Følger:** præsenslisten og slægtskab med levende er kun for redaktionen i POC'et. »Min plads« (at styre en
>    levende persons synlighed) udskydes, til brugere kan se levende.
> 3. **»Det er mig« i to trin:** selverklæret er nok til slægtskab som kontekst (vises kun for personen selv);
>    »Min plads« kræver redaktionens godkendelse. Accepterer foreningen POC'et, skal bekræftelsen kunne kobles til et
>    medlemsregister.
> 4. **Senere stillingtagen (backlog):** hvad almindelige brugere skal kunne se af levende og på hvilke niveauer
>    (det todelte lag med grundniveau og ekstra deling fra 2026-11-12 pkt. 8, børns standard, koden til at finde en
>    levende person), sammenhængen mellem konto og medlemskab, og medlemmer, der ikke selv står i bogen. Invariant 8's
>    forslag til ny ordlyd indføres ikke før da.

## BESLUTTET: »Besiddelser« i læserfladen; godser og stamhuse skilles i data, ikke på siden (2026-11-13)

> Projektejeren (fase 7): »gods« er ikke det bedste ord, og der bør være en adskillelse mellem godser/gårde/steder og
> egentlige majorater og stamhuse — der er sammenhænge, men de er ikke det samme.
>
> 1. **Navnet er »Besiddelser«** i menu, overskrifter, søgning og feed: det, slægten ejede eller besad. Det dækker gods,
>    gård, len og stamhus og svarer til datamodellens rolle »ejer/besidder«. Adresserne følger:
>    `/slaegt/<slug>/besiddelser` og `/besiddelse/<id>`; `/slaegt/<slug>/godser`, `/gods/<id>` og `/soeg?type=godser`
>    omdirigeres eller forstås. Interne navne (`estate`, `EstateItem`) og redaktionen er uændrede.
> 2. **Opdelingen er backlog.** Data skelner ikke i dag: alle ejendomme har `slags = 'gods'` (testudtrækket: 186 af 186);
>    grevskab, baroni og stamhus står kun i navnet (7 i testudtrækket), og hvilke godser der hørte under et stamhus står
>    kun i ejerperiodens fritekst (»lagt under Frisenvold«). Opdelingen kræver (a) et kontrolleret ordforråd for
>    `estate.slags` (gods, gård, len, stamhus, grevskab, baroni …), sat redaktionelt, og (b) en relation »hører under«
>    (ejendom → stamhus, med periode). Det er data, ikke nye tabeller (invariant 2; `majorat` er en `slags`, jf. 2C-1).
>    Siden grupperer først, når data siger det; et gæt ud fra navnets forled er fravalgt.
> 3. **Indtil da vises `slags` ikke** for læseren (den ville kalde »stamhuset Frisenvold« for »gods«).

## BESLUTTET: slægtsvåben — Aarbogen vælger selv tegningen; ingen autorisation, note kun efter behov; lukker webredesignets åbne punkt 5 (2026-11-13)

> Overdragelsens åbne punkt 5 (»grundvåbnet er ikke en autoriseret tegning; godkendes før offentlig brug«) og
> designsystemets heraldik-note byggede på en forkert præmis. Projektejeren: der findes ingen instans i Danmark, der
> autoriserer adelsvåben på den måde. Aarbogen bruger den tegning, den bedst kan lide.
>
> 1. **Ingen godkendelse før offentlig brug.** Grundvåbnet fra designsystemet bruges som slægtens våben på forsiden
>    og i sepia som lille mærke (slægtsbjælke, slægtsregister, personside).
> 2. **Ingen fast kildenote.** Designsystemets »Våben efter DAA 1939« er ikke underbygget og bruges ikke. Noten er
>    valgfri (`SLAEGTER[].vaaben.note` i `web/src/data/nav.ts`) og sættes kun, når der er en konkret grund.
> 3. **Tegningen kan skiftes** ved at lægge nye filer i `web/public/vaaben/`.
> 4. Webbens tekst »Autoriseret våben · Dansk Adels Forenings gældende gengivelse« på våben-siden er fjernet af samme
>    grund.

## NOTERET: datoer sammenlignes som tekst — 2018-20's 59 skrivemåde-forskelle venter på en datobaseret sammenligning, åben backlog (2026-11-13)

> Efter datobindingerne i prod (decisions 2026-11-12, `database-current-state.md` §28) står 59 af 2018-20's fødsler og
> dødsfald `proposed` som `SKRIVEMAADE` (13 fødsler, 46 dødsfald). Målt 2026-11-13 mod importens påstande (modellens
> v2-værdi mod `date_raw` på personens fødsel/død): **alle 59 er samme dato i en anden form**, ingen reel uenighed.
>
> | Forskel | Antal | Eksempel (bogen/modellen → importen) |
> |---|---|---|
> | Importen har sted og/eller markør med | 32 | `24. jan. 1733` → `† 24. jan. 1733 i Kiel` |
> | Et ord om dødsmåden i den ene side | 10 | `faldt 24. okt. 1914` → `24. okt. 1914`; `mellem 1. og 4. juni 1697` → `faldt mellem …` |
> | Alder i stedet for dato | 6 + 1 | `ung.` → `† ung`; `18 måneder gammel.` → `† 18 måneder gammel` |
> | Tegnsætning, parentes, `* og †`, relativ dato | 10 | `-1353` → `(-1353)`; `1684.` → `* 1684`; `15. s.m. s.st.` → `15. s.m.` |
>
> **Konsekvens for læseren:** de 59 datoer vises allerede korrekt; de mangler kun postens koordinat (»DAA 2018-20,
> s. N · <post>«). Det er 59 af ca. 720 fødsler og dødsfald med koordinat.
>
> **Projektejerens valg:** spec'ens del 2 (§4.3, kort over de 59 med eget GO) køres ikke nu. Runneren
> (`38-dato-bindinger.sh`) har ingen del 2-tilstand, så det ville kræve udvidelse, øvelse, review og en ceremoni for at
> sætte koordinater på datoer, der allerede står rigtigt.
>
> **Den bedre vej (backlog):** `private.binding_value_matches` sammenligner datoer som normaliseret tekst
> (`date_raw`), så sted, markør og tegnsætning gør ens datoer forskellige. En sammenligning på datoens indhold
> (`date_min`/`date_max` + kvalifikator, invariant 5) ville fange de fleste af de 59 uden kort og gælder alle udgaver
> (1939 og de næste). Ordene om dødsmåden (`faldt`, `dræbt`, `henrettet`, `dødfødt`) og alderen (`ung`) skal da afgøres
> særskilt: de er oplysninger, ikke skrivemåde. Kræver en lille spec; `binding_value_matches` bruges af flere writere,
> så ændringen skal måles mod alle eksisterende bindinger (ingen må falde ud).

## BESLUTTET: webredesign, runde 2 — hovedside »Værket«, personside med medlemslag, feedet, stamtræet og navigation model 2 (2026-11-12)

> Projektejeren har valgt mellem designvarianterne på canvas'et »Aarbogen – web redesign« (Claude Design) og godkendt
> reviewet i designgennemgangen. Bygger videre på indførslen »webredesign — Aarbogens hovedside over slægtsforsider …«
> samme dato. Overdragelse til kode: `docs/design/2026-11-12-webredesign-overdragelse.md`.
>
> 1. **Hovedside A »Værket«:** søgning på tværs, slægtsregistret, »Nyt i Aarbogen« og feedet. Variant B er fravalgt;
>    dens læsespalte-feed kan genbruges på mobil.
> 2. **Personsiden:** variant A er siden for alle. Indloggede medlemmer får et lag oveni på faste pladser i samme layout
>    (slægtskab som kontekst, bogmærke, fakta med kilde pr. linje); siden skifter ikke layout ved login.
> 3. **Feedet »Et blad, tilfældigt vendt«** er fast del af hovedsiden (på tværs af slægter) og slægtens forside (kun
>    egne). Blandede korttyper, aldrig to ens i træk, intet kort to gange, højst ét »kun et navn« pr. seks kort, kilde på
>    hvert kort, ingen likes eller tællere. Web: knappen »Vend flere« frem for uendelig scroll. Mobil: forsidens
>    hovedindhold.
> 4. **Stamtræet** hører til slægten (`/slaegt/<navn>/stamtrae`) og omtegnes: hele søskendeflokke, alle ægteskaber med
>    navn, børn samlet når bogen ikke angiver ægteskab, usikre slægtskaber med stiplet kant og ord, mangler sagt med ord.
>    Visninger: Fokus, Kolonner, Anespor (web); Fokus, Anespor, Liste (mobil). Swipe kun som supplement til synlige pile.
> 5. **Navigation model 2:** »Slægter« i hovedmenuen er kun en vælger (søg, A–Å, senest besøgt) og fører til slægtens
>    forside. Inde i en slægt navigerer en slægtsbjælke under sidehovedet (Forside · Stamtræ · Præsensliste · Godser ·
>    Våben · Artikler · Skift slægt). Personer, Slægtskab og Historie ligger over slægterne og har ingen slægtsbjælke.
>    Model 1 (todelt megamenu) er fravalgt.
>
> **Åbne punkter fra reviewet (blokerer de nævnte dele):**
> - Linjernes betegnelse afhænger af udgaven (V. linje i udtrækket, II. linje i præsenslisten for den grevelige linje af
>   1673). URL'er bruger faste id'er; overskrifter viser udgavens betegnelse med kilde. Blokerer linjegenveje og
>   linjesider.
> - Arbejdsgang for at bekræfte »Det er mig« mangler. Blokerer slægtskab som kontekst og »Min plads«.
> - Grundlag for grundniveauet for levende (punkt 8 i forrige indførsel), børns standard og forslaget om en kode til
>   at finde en levende person. Blokerer præsenslisten for medlemmer og slægtskab med levende.

## BESLUTTET: webredesign — Aarbogens hovedside over slægtsforsider, navigation efter opgaver, personen får egen side, synlighed af levende i to lag (2026-11-12)

> Projektejeren har taget stilling til otte punkter i designgennemgangen (Claude-dok »Designgennemgang – Danmarks Adels
> Aarbog app«, afsnittet »Beslutninger før redesign«), alle efter anbefalingen. Grundlag: gennemgang af designoplæggene
> (web-v4, følgesvend-v3 m.fl.), af `web/src` og af den kørende webapp med testdata (`web/scripts/designtour/`).
> Beslutningerne styrer det kommende redesign; intet er bygget endnu.
>
> 1. **To niveauer (beslutning 6, tages først):** Aarbogens hovedside på `/` med søgning og slægtskab på tværs og et
>    register over slægterne. Hver slægt får en forside på `/slaegt/<navn>` med våben, indledning, linjer, stamtræ,
>    præsens og godser. Personer og slægtskab ligger over slægterne med én adresse pr. person. Strukturen indføres nu,
>    selvom kun Reventlow findes; hovedsiden viser registeret med én slægt og fører videre.
> 2. **Forsiderne (1):** hovedsiden får søgefeltet på tværs, slægtsregistret, »Nyt i Aarbogen« og feedet på tværs;
>    »Er vi i familie?« er en indgang, ikke det dominerende. Slægtens forside får våben, indledning og linjer, indgange
>    til stamtræ, præsensliste, godser og artikler, »Redaktionen foreslår« og slægtens eget feed. De fire ens personkort
>    på den nuværende forside udgår.
> 3. **Navigation efter opgaver (2):** slå en person op · er vi i familie? · gennemse slægten · læs historien. Menuen
>    kan klikkes og bruges med tastatur, ikke kun åbnes ved hover. Punkter, der ikke er bygget, vises ikke som »kommer«.
> 4. **Personen får egen side (3):** `/person/:id` bliver en selvstændig side over slægterne; panelet i stamtræet
>    bliver en genvej til den. Det er en ny permanent læserflade.
> 5. **Mobil web (4):** simpelt læselayout, så personside, søgning og slægtskab kan læses på telefon, også fra et
>    delt link.
> 6. **Præsenslisten (5):** kun for indloggede medlemmer (redaktionen er også medlemmer), fordi den viser levende.
>    Indtil det er bygget, står den ikke som klar i den offentlige menu.
> 7. **»Er vi i familie?« (7):** på mobil et hurtigt værktøj med egen fane (»Det er mig« sættes én gang). På web vises
>    slægtskabet som kontekst på personsiden (»din oldefars bror«), og værktøjet ligger i menuen. Resultatet kan deles
>    som link. Indgår en levende person, kræver det login; synligheden styres af punkt 8.
> 8. **Synlighed af levende personer (8):** to lag. *Grundniveau:* det, der står i den trykte Aarbog (navn,
>    fødselsår, plads i slægten), vises for indloggede medlemmer; alle kan bede om at blive skjult. *Ekstra deling:*
>    hvert medlem vælger i sin profil, hvem der kan se mere (billede, »det er mig«, at kunne findes i »Er vi i
>    familie?«): kun redaktionen, egen slægt eller alle medlemmer. Standardvalget er det mest lukkede; børn får
>    strammere standarder; samtykke og tilbagetrækning gemmes med dato. **Grundlaget for grundniveauet afklares med
>    foreningens databeskyttelsesrådgiver, før det bygges.**
>
> **Følger af punkt 8 — forslag til ny ordlyd af invariant 8 i CLAUDE.md** (ikke indført; afventer punkt 8's afklaring):
> »**GDPR indbygget.** `person.levende` styrer synlighed: afdøde er offentlige; levende ses kun af indloggede medlemmer
> og kun på grundniveau (den trykte Aarbogs oplysninger), med ret til at blive skjult. Mere kræver medlemmets eget
> synlighedsvalg i profilen (standard: mest lukket; børn strammere). Kortlagt på RLS.«
>
> **Næste skridt:** designsystem (ét fælles sæt tokens for web og mobil), derefter navigation og varianter af
> hovedside, slægtsforside og personside i alle tilstande (mobilbredde, tom, indlogget), derefter overdragelse i
> `docs/design/`.

## BESLUTTET: 2018-20's fødsler og dødsfald bindes efter normaliseringsregel `dato-markoer-v2`; udføres før 6e-2 (2026-11-12)

> Projektejeren 2026-11-12, efter kommentaren på Conrad (392): hans fødsel og død står uden postens koordinat. Årsag:
> modellen skrev datomarkøren med (`* 21. april 1644`), og 6c-2's normalisering (`dato-markoer-v1`, `f.`/`†`, målt på
> 1939) blev aldrig kørt på 2018-20. Lukker decisions 2026-09-27 pkt. 3's åbne normaliseringsregel for datomarkører.
>
> - **Vej 1:** nye forslagsversioner med markøren fjernet (`red_normaliser_forslag`), derefter maskinel accept med
>   stikprøve på 20 og binding med de eksisterende writere. `binding_value_matches` ændres ikke.
> - **Variant (a):** én lille DDL (regel v2: `*` tilføjes for `person.birth`; markøren følger prædikatet) og én
>   datagang for fødsler og dødsfald sammen (≈ 509 bindinger: 267 + 242).
> - Kortark over resten (målt: 0 `REAL_DIFF`, 59 dato-`SKRIVEMAADE`, 15 `NO_FACT`) er en valgfri del 2 med eget GO.
> - **Rækkefølge:** indskydes før 6e-2 (lille, uafhængig af 6e-2's skrivninger). Roadmappet ændres ikke: leverancen
>   tjener trin 6's færdigbevis (b) for 2018-20.
> - Spec: `docs/superpowers/specs/2026-11-12-2018-20-dato-bindinger-design.md`.

## BESLUTTET: læserens fakta viser kun kildeteksten — mærkerne »bundet til bogens post« og »fra den oprindelige import« fjernes; justerer B11-spec'ens §4.4 (2026-11-12)

> Projektejeren efter 6e-1 i prod (Conrad, 392): mærkerne er underlige og unødvendige formuleringer. De beskrev vores
> arbejdsgang (trin 4-binding kontra citation fra importen), ikke bogen, og læseren skal ikke se redaktionens
> maskinrum (jf. afgørelse 9 i 6e). Kildeteksten skelner stadig: bundet kilde bærer postens koordinat
> (»DAA 2018-20, s. 201-202 · V-1«), importens kun bogen og evt. side (»DAA 2018-20«, »DAA 1939, s. 541«).
> »Kilde ikke registreret« bliver stående (spec 6e §9 pkt. 4 er stadig åben). Datamodel og RPC uændret; `kind`
> bevares i `PersonFactSource`, så færdigbeviser fortsat kan tælle andelen bundne.

## BESLUTTET: 6e's læserflade — valgt udgave forrest, den anden som note (visning C); justerer trin 6-spec'ens §3 pkt. 5 og §8 (b) (2026-11-12)

> Delspec 6e (`docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md`) godkendt af projektejeren efter
> brainstorm med skitser, byggertjek og to Codex-runder (projektejerens ja til flere runder i sessionen).
>
> - **Visning C:** udgavevælgeren styrer biografi, fakta og linjer; hver oplysning står én gang i den valgte udgaves ord
>   og kilde; den anden udgave nævnes som »✓ også i DAA 1939«, »DAA 1939 skriver: …« eller »Kun i DAA 1939: …«.
>   **Justerer trin 6-spec'ens §3 pkt. 5** (der lod 2018-20-visningen vise kun 2018-20's fakta = skitse A): A skjuler
>   enighed og uenighed mellem udgaverne, og målarkitekturen kræver, at projektionen ikke skjuler uenighed.
> - **Justerer trin 6-spec'ens §8 (b):** 1939's kildeetiket er »linje, slægtled, nr.« fra placement, ikke »s. N · nr. x«
>   (1939's numre er gruppelokale). Etiketten skrives som **ny publiceringshændelse** i en ceremoni (afgørelse 7: »så
>   ligger det fast«), også for de 35 uplacerede med tom postdel via en lille schema-ændring (afgørelse 10).
> - **Bøgernes ord og redaktionens valg adskilles** (afgørelse 9): fakta-blokken viser hver udgaves egne ord; navnet
>   øverst er redaktionens valg, uden markering. Normalt følger det nyeste udgave.
> - **Ziesendorf:** linjeskemaets OCR-etiket for 1939's III rettes i 6e-2's ceremoni (afgørelse 8).
> - **Opdeling:** 6e-1 er klient-only (web); 6e-2 er DDL + ceremoni + web. Mobilen er backlog.

## NOTERET: åben backlog fra 6e's brainstorm og review (2026-11-12)

> 1. **Godsnormalisering:** godsnavne varierer mellem udgaverne og har OCR-fejl (»Kain« skal være »Kalø«). 6e viser
>    hver udgaves godser for sig.
> 2. **Mulige fejlkoblinger** fundet under målingen: komponent 527 (to fødselsår, 1743/1745) og komponent 66 (personerne
>    1257 og 1410). Skal vurderes af projektejeren; 6e ændrer ingen koblinger.
> 3. **Mobilen** deler ikke `buildPersonFacts` og får ikke 6e's læserflade; paritet når mobilen går i prod.
> 4. **Kildekobling i Redaktion** (godkendt): redaktørens fire faktawritere (`red_tilfoej_oplysning`, `red_opret_fakta`,
>    `red_edit_oplysning`, `red_upsert_fakta`) gemmer altid `source_id = NULL` og kilden som fritekst. Redaktøren skal
>    vælge kilden fra listen. Målt: 17 offentlige påstande; 13 fritekster navngiver en udgave, 6 med side, så de gamle
>    kan kobles mekanisk. Hører til søge- og koblingsværktøjet efter trin 6.
> 5. **OCR-rettelser gemt som påstande:** projektejerens navnerettelser fra juli 2026 på 1939-personer (1073, 1117,
>    1123, 1353, 1770) er OCR-rettelser, ikke nye påstande; de blev skrevet før `red_ret_ocr_felt`. Vurderes sammen
>    med punkt 4.
> 6. **Redaktionelt visningsnavn:** redaktionens navnevalg bør være en beslutning på identiteten (komponenten) med
>    begrundelse og historik, adskilt fra påstandene. I dag må det låne en kilde og sidde på én personrække (Conrad 392:
>    »Conrad« med fritekst »DAA 1939«). Evt. adelspatentets »Conrad Comte de Reventlow« som navneform (ny faktatype).
> 7. **Testrest:** et ikke-valgt overhoved-udsagn på person 476 har kildeteksten »Redaktionelt udpeget (præsensliste
>    v1-test)«. Tjekkes mod prod og fjernes, hvis det er en testrest.
> 9. **Relative datoer uden for personens fakta** (projektejeren 2026-11-12: »fx borgerlig og kirkelig vielse eller
>    andre lignende tilfælde der hænger sammen«): 6e-1 opløser dåb←fødsel og begravelse←død (spec §5.4a). Ikke opløst:
>    vielse (familiefaktum, 8 relative af 478; borgerlig/kirkelig vielse hænger sammen), embedernes periode (46 relative
>    af 1.256, fx »s.å.« om det foregående embede). Kræver bogens rækkefølge eller en eksplicit reference pr. påstand.
> 8. **Redaktørens visning af kildeløse fakta i læseren** (spec'ens §9 pkt. 4): ikke afgjort; »Tilføjet af
>    redaktionen« gør redaktionen for synlig. Alternativer måles senere.

## BESLUTTET: 6d-3's afgrænsning — 5b-vejen på 1939 med profil som data, dobbelt ægtefælle, læserrettelse og 1791 skjult (2026-11-10)

> Delspec 6d-3 (`docs/superpowers/specs/2026-11-10-trin6d3-relationer-design.md`) godkendt af projektejeren efter
> byggertjek og tre Codex-runder (budgettet overskredet med to runder; projektejeren frigav det for dagen).
>
> - **Spor R:** 1939's ægteskaber og forældre går gennem 5b's eksisterende RPC'er og writere. Writerens profiler
>   (i dag literalerne `relation-persona-2018-20-v1..v3`) bliver data; 1939 får én profil med foldning af linjeskift,
>   orddelinger og sidemarkører, også i beregningen af ægteskabsnummeret. Ægtefællens identitet er 1939's
>   legacy-række (trin 6-specen §6 pkt. 8). Maskinel accept følger 5b's hele eligibility-kontrakt.
> - **Spor D (projektejerens valg):** ≤44 kort, hvor en sammenfoldet person viser samme ægtefælle to gange;
>   »samme« skrives med `red_samme_som`, »ingen af dem« skrives ikke i basen.
> - **Spor L (projektejerens valg):** læserens familiekilde slår modparten op kanonisk for ægteskab, forælder og
>   børn; deployes før dataceremonien.
> - **Spor O (projektejerens valg, ændret efter Codex runde 2):** 1791 skjules med `red_set_privat`, ikke
>   `samme_som` til Conrad, fordi 1791's uforanderlige `navn`- og `død`-fakta så ville stå i Conrads faktaliste.
>   742/743's vielser findes med samme datoer på 540/541.
> - **Ændrer 6d-spec §7:** ingen `relation-child-v2`; 1939's 4 børneforslag står `proposed`, fordi børnebindingen
>   kræver `relation-child-v1`, som læser 1939's syntetiske koordinater. Ingen `person_create`: 1939's 7 ægteskaber
>   uden familie/ordinal og 2018-20's I-11 og II-35 står `proposed`. De 6 ægteskaber med to klausuler står `proposed`
>   (læserens gate kræver én). Forslag, der ikke bindes, tælles pr. årsag i runneren og `status.md`; ingen ny
>   dispositionsskrivning.
> - **Lukket fra 6d-2b's arv:** de 29 records uden narrativbinding har 0 relationsforslag; 933/935/940/1135 har ingen
>   familier eller `samme_som` og berører ikke relationerne.
> - **Fortrydelse:** ét regime — restore af dump taget før spor D, fra ethvert præfiks af ceremonien; efter
>   `VERIFY_OK` almindelig redigering, ingen selektiv ceremoni-fortrydelse.
> - **Ændret i plan-Task 0 (projektejerens valg 2026-11-10): kilde 1 udgår af 6d-3.** v3-reglen giver I-103 `I`
>   (`intet_navn`) og V-159 `U` (`flere_klausuler`); arket tillader kun `I`/`U`, så ingen persona kan oprettes, og
>   V-159 ville fejle læsergatens `n_support=1`. Alle 4 partsløse 2018-20-ægteskaber står `proposed` med årsag;
>   kilde 1 er byte-ens før og efter (spec §5.1.6). D-kandidaterne er målt til 42 hos 41 personer (specens 44 var en
>   øvre grænse).
>
> **I prod 2026-11-11** (`database-current-state.md` §27): 69 bindinger for kilde 3 (68 ægteskaber + 1 forælder),
> 42 `samme_som` (dobbelt 42 → 0), 1791 og 1795 private; kilde 1 uændret; browsertjek som anon OK.

## NOTERET: 1939-hovedperson ukoblet mens ægtefællen er koblet — det omvendte af 6d-3's D-tilfælde, åben backlog (2026-11-11)

> Fundet ved 6d-3's browsertjek: 612 (Mette von Rantzau) viser to ægtemænd, 2018-20's 75 (»Nicolaus von Reventlow«,
> familie 45) og 1939's 955 (»Claus [Reventlow] til Gaarz«, familie 392). Ægtefællens 1939-række 1474 → 612 var koblet
> før 6d-3; hovedpersonen 955 har ingen `samme_som` (Claus = kortform af Nicolaus). D-kortene dækkede kun »hovedperson
> koblet, ægtefælle ikke«. 6d-3 ændrede ikke tilstanden, men gav ægteskabet sin 1939-kilde. Årsagen: D's `p39`
> (personer med egen 1939-post, `person_external_id`) rummer kun hovedpersoner; 1939's ægtefællerækker har ingen
> ekstern nøgle, så definitionen kunne kun se det ene tilfælde.
> **Målt 2026-11-11** (stand-in `…_slut` = prod efter 6d-3; D's tvillingregel med rollerne byttet): 9 familier, heraf
> 742/743 = 1791 (privat via O). **7 kandidater** (1939-familie: hovedperson → 2018-20-kandidat): 392: 955 → 75,
> 395: 960 → 210, 438: 1036 → 112, 515: 1156 → 282, 638: 1376 → 312, 740: 1787 → 236, 748: 1803 → 290.
> **Næste skridt:** projektejerens afgørelse pr. par, som redaktionel `samme_som` (955 → 75 tages af projektejeren) eller
> en lille kortrunde. Hænger sammen med 1939-navnereglen (»til <gods>«)
> og de 60 personer, der efter 6d-3 stadig har to eller flere ægtefæller (98 → 60).

## BESLUTTET: 6d-2b indsnævres til at trække forkert tilskrevne 1939-tekster tilbage; resten bliver kendte begrænsninger (2026-11-10)

> Målt 2026-11-10 på stand-in `daa5ab_ddl_standin_20261110150105_6d2afb` (= prod efter 6d-2a). 6d-2a §9 beskrev
> 6d-2b som tre nye mekanismer: binding af de viste tekster, 1939-profil til kildetekst-revision og grænsemekanisme.
> Målingen viser, at de næsten intet ændrer for læseren:
>
> - **Binding af de viste tekster:** 13 af 1939's 576 narrativer er ubundne (8 `grandfathered_publication`, 5
>   staged uden publicering). 5 er oversigtsomtaler (974, 977, 1013, 1014, 1802), som ikke må bindes (6d-2a §9). Ingen
>   af de 8 andre har en ledig post. Deres tekst står helt eller delvist i en post, der allerede er bundet til en anden
>   person (andel af narrativets tegn i posten: 1791 → 1198's post 94 %; 934, 933 og 935 → 931's 100 %; 929 → 930's 69 %;
>   1135 → 1130's 100 %; 940 → 1810's 56 %; 1795 bedst 64 %). 149b's migration passer heller ikke: den opretter en ny
>   persona fra `person_external_id.record_key`, og 1939's eksterne nøgler er gamle uuid'er, ikke `record-…`-nøgler.
> - **De 38 tekstrettelser** (6m, `kun_rapport`): 14 af de 15 poster har hverken narrativ, persona eller placement, og
>   10 ligger i oversigtszonerne. 8 er normaliseringer (4 sidemarkører, 4 orddelinger), ikke fejl i bogen; 7 ligger på
>   poster uden helpost (p83, p235, p278). 23 ændrer længden, og under 1939's `raw`-tekstform giver det enten
>   `CLAUSE_EVIDENCE_RENDITION_SPAN_INVALID` eller lydløst forskudte klausul-offsets (`schema.sql:4570-4577`).
> - **De 6 grænsefejl:** der findes ingen writer, der flytter tekst mellem records (afvist anker, anker v2,
>   `source_record_revision_event`), heller ikke for 2018-20. En sådan writer ville gøre 4 publicerede narrativer
>   forældede (601, 607, 704, 977) og tabe 7 bindinger. 6c-3's afstemningswriter har desuden en kendt fejl, der skal
>   rettes før en ny kalder (6c-3-spec, Codex-fund 2).
>
> **Projektejerens valg 2026-11-10:** 6d-2b bliver smal, og derefter følger 6d-3. Projektejeren godkendte alle fire
> kort (»fundene er korrekte, teksterne skal trækkes tilbage«). **I prod 2026-11-10** (`database-current-state.md` §26):
> fire tilbagetrukket, synlige 1939-narrativer 569 → 565.
>
> - **Indhold:** de forkert tilskrevne 1939-tekster, som læseren ser i dag, trækkes tilbage med den eksisterende
>   redaktørhandling (`red_tilbagetraek_legacy_narrative`, redaktionens narrativredigering). Kandidaterne er 1791
>   (navnet er et tekststykke fra Conrads post), 934 (en omtale i Hartvigs post), 929 (for det meste Dosos post) og
>   1795 (22 tegn, intet navn). Projektejeren afgør hvert tilfælde på et lokalt kortark med bogposten ved siden af. En
>   tilbagetrækning skjuler teksten uden at slette den og kan fortrydes (`red_fortryd_person_narrative_publication_event`
>   dækker `legacy_withdrawn`). 929 og 934 beholder deres tekst fra 2018-20 gennem `samme_som`. Ingen DDL, ingen ceremoni.
> - **Roadmap:** trin 6, led publicering, midlertidig legacy-afvikling. Værdi: læseren ser ikke længere en anden
>   persons tekst under et forkert navn. Erstatter 6d-2a §9's tre mekanismer. Review-budget: ingen kodeændring, intet
>   review.
> - **Færdigbevis:** hver tilbagetrukket henvisning har status `withdrawn` i prod med et `legacy_withdrawn`-event.
>   Biografilæseren leverer ikke længere teksten til anon. De øvrige 1939-narrativer er uændrede.
> - **Kendte begrænsninger (ikke i trin 6):** de 38 tekstrettelser, de 6 grænsefejl og rettelsen af afstemningswriteren.
>   Trin 6's færdigbevis (a) kræver de samme operationer som 2018-20, og grænsemekanismen findes heller ikke dér. Vision'en
>   gør det ikke til et mål at gøre 1939 internt perfekt. Rettelsen på narrativ 632 (person 963, staged) trækkes kun ud
>   af rapporten. *Billigere delvej (Codex-review 2026-11-10, fund 1):* de 13 rettelser af samme længde på 6 poster
>   med helpost (p9, p10, p11, p50, p68, p82) har ikke offset-problemet. Den eksisterende writer accepterer `raw`
>   (`schema.sql:3735`, `:4906`); kun Python-værktøjet mangler en raw-profil og et rettelsesmanifest
>   (`reimport_profile.py:299` kræver i dag foldet projektion), og 6m's offsets skal genfindes i helpostens tekst.
>   Ingen af posterne har læsertekst, så delvejen står i backloggen og ikke i trin 6.
> - **Flyttes til 6d-3's måling:** de 29 records uden narrativbinding (sider 498-539; 21 uden persona, 8 uden helpost),
>   som 6d-1-spec'en §7 lagde i 6d-2 og 6d-2a ikke nævnte. 6d-3 afgør, om relationerne kræver personas for dem.
>   Desuden de skjulte dubletter 1135 (af 1130) og 940 (af 1810) samt de skjulte 933 og 935 (staged, uden
>   publicering), hvis tekst er den samme omtale i Hartvigs (931) post som 934's (Codex-review fund 2).
> - **6d-3 skal rydde op i levnspersonerne** (ikke kun måle): en tilbagetrækning skjuler kun teksten, ikke personen.
>   1791 er offentlig og står som `partner` i familie 742 (med 1823) og 743 (med 1824). Formodentlig er det Conrads
>   (1198) to ægteskaber, så læseren ser »fyenske Rytterreg.)« som ægtefælle. 6d-3 bygger 1939's ægteskaber om og skal
>   flytte eller fjerne de to partnerskaber og afgøre, hvad der bliver af personen og dens 2 fakta. Afgøres 1795 som
>   et levn, gælder det samme for den (offentlig, 1 faktum, ingen familier).
> - **Ændrer** 6d-2a §9 og decisions 2026-11-07 (færdigbeviset »de 13 har record-binding«): af de 13 bindes ingen. 5
>   er oversigtsomtaler under reglen, de synlige forkerte trækkes tilbage efter kortene, og de skjulte står som ovenfor.

## BESLUTTET: 6d-2a's brud på tidsbudgettet accepteres; biografilæserens fart udskydes til før projektets afslutning (2026-11-10)

> **Målt i prod** (runner 34, `anon`, median af 3, samme base): `bio_alle` 12.679 ms i fase `foer` → 25.123 og
> 24.858 ms efter DDL'en (to kørsler) → 25.941 ms efter data (`verify`). Øvrige kald inden for budgettet (`facts_289`
> og `facts_529` lå over i første/anden DDL-kørsel, men DDL'en rører ikke faktalæserne, FAKTA er uændret, og begge
> var inden for ved `verify`: støj). Spec rev. 4 §4.1's grænse er max(basis × 1,10; basis + 20 ms) →
> `T6D2A_ANON_BUDGET_BRUDT`, runbookens stoppunkt før data.
>
> - **Hvorfor accepteret:** feedets kald med alle personer lå allerede over anon's 3 s før 6d-2a (fejlede i prod,
>   2026-11-09-noten). Personsidens kald (én persons foldede id'er, `web/src/data/public.ts`) er **målt i prod efter
>   data**: projektejeren, logget ud (anon), `/person/134` (1048's kort), browserens netværksfane: tre kald af
>   `public_person_bio_source_versions_v2` på 339, 209 og 487 ms, alle `200`; hele siden 5,62 s (alle sidens kald).
>   Den ekstra tid ligger altså i den del af `private.overview_mention_narratives`, der vokser med antal id'er.
>   Fortryd-DDL (restore under frys) blev vurderet ikke at ændre noget, brugerne mærker.
> - **Uforklaret:** samme DDL gav +2-8 % på stand-in'erne (6d2ab-6d2ae, efter `ANALYZE`), men +97 % i prod.
>   Generalprøven forudsagde det altså ikke. En rettelse skal først genskabe fordoblingen lokalt (fx stand-in uden
>   `ANALYZE`), ellers beviser en lokal måling intet.
> - **Projektejerens valg 2026-11-10:** 6d-2a's data går i prod trods bruddet (valg B frem for fortryd-DDL), og
>   optimeringen flyttes fra »næste opgave« (2026-11-09-noten) til **før projektets afslutning**.
> - **Kandidater, når den tages:** (1) oversigtsomtalerne (10 narrativer i alt) gemmes som afledt projektion, der
>   opdateres ved ændret `samme_som`/medlemskab, i stedet for at beregnes over hele `samme_som`-grafen i hvert kald
>   (ændrer rev. 4's »live uden gemt markering« — kræver ny beslutning); (2) feedet henter kun biografier for de
>   viste personer; (3) `EXPLAIN` i prod af planen for `bio_alle` (plan-forskel prod ↔ stand-in).
> - **Vagt indtil da:** basis for personsidens biografikald som anon er 209-487 ms (ovenfor). Hvert senere trins
>   `anon`-måling ser på personsidens kald; nærmer det sig anon's 3 s,
>   forsvinder biografien lydløst, og optimeringen rykker frem. Prod-runnere bør derfor måle et enkelt-persons
>   biografikald ud over `bio_alle`.

## BESLUTTET: 6d-3's kortomfang — kontrol, forælder og en diagnostisk stikprøve af de parkerede ægteskaber (2026-11-11)

> Målt på stand-in (prod-data + 6d-3's DDL + D/O): af 1939's 271 ægteskaber parkerer v3's navneregel 161 i udtrækket
> (`navn_uklart` 89, `partner_ligner` 52, `navn_afkortet` 8, `intet_vindue` 6, `flere_klausuler` 6); 110 bliver personas,
> 68 er maskinelt egnede, 22 af dem i den blinde kontrolstikprøve; 42 er ikke egnede (`name_or_rank` 22,
> `count_mismatch` 20). Specens overslag (≈220 maskinelle) holdt ikke. **Projektejerens valg:** kort for kontrollen (22)
> og forælderen (1) samt en lagdelt stikprøve på 20 parkerede ægteskaber; stikprøven er diagnostisk og binder intet i
> 6d-3. Fravalgt: det fulde kortsæt (≈226 kort, jf. memory »ingen flere fulde afgørelsesark«) og kun de nødvendige
> kort uden stikprøve. **Opfølgning (åben backlog):** en 1939-variant af navnereglen, målt på stikprøvens svar, så en
> større del af de 161 kan gå maskinelt.
> **Stikprøvens svar (2026-11-11):** 19 af 20 er rigtige match, som v3's navneregel parkerede på grund af 1939's
> navneform (»til <gods>« i legacy-navnet, titler foran og inde i navnet, rester af sidemarkør/orddeling inde i linjen,
> navnepartikler, omlyd); 1 påstand er selv forkert. Grundlag for opfølgningen; detaljer i planens Task 6.

## NOTERET: samme par i flere familier efter sammenfoldningen — stamtræet ikke tjekket, åben backlog (2026-11-11)

> Fundet under 6d-3's D-kort (spec §2.4): når både 1939-hovedpersonen og -ægtefællen er koblet med `samme_som` til
> et 2018-20-par, står parret som flere familier (fx 2018-20's familie + én fra hver af de to 1939-poster). Målt med
> core's `collapseSameAs`/`buildModel` på stand-in'ens data (= prod): **225 par med mere end én familie** (3 med tre).
> Tilstanden stammer fra 1939-importen; 6d-3 ændrer ikke tallet. Personpanelet viser hver ægtefælle og hvert barn én
> gang. **Ikke tjekket:** stamtræ og kolonner, der traverserer unionerne (`childrenByUnion`), kan vise parret to gange
> med børnene delt mellem familierne. **Projektejerens valg:** uden for 6d-3. Næste skridt: browsertjek af et par i
> stamtræ/kolonner; viser det dubletter, er rettelsen sandsynligvis i projektionen (forene unioner med samme kanoniske
> par), ikke i data.

## NOTERET: den fælles 5ab-runner sender ikke `profile_file` — åben backlog (2026-11-11)

> Fundet i Codex' review af 6d-3 (fund 4). Efter 6d-3 kræver `relation_persona_apply.sql`, `relation_batch_apply.sql`
> og `transfer_5ab_step_disposition.sql`/`_profile.sql` en `-v profile_file=<profil>` (relationsprofiler som data).
> Repo'ets kald og tests sender den; det gør den private fælles runner (`lib.zsh`'s persona- og ark-stier) ikke. 6d-3's
> egen runner bruger ikke de stier. **Konsekvens:** en senere ceremoni gennem den fælles runner stopper med
> `RELATION_PROFILE_FILE_REQUIRED` før skrivning (fail-closed). **Projektejerens valg:** udskudt; rettes, når den
> fælles runner bruges næste gang (profilfilen bindes da også i GO og replay). Begrundelsen er, at intet skrives
> forkert; at det også sparer en ny generalprøve af `lib.zsh` nu, er nævnt åbent.

## NOTERET: biografilæseren med alle personer og den direkte narrativlæsning ligger allerede om 3 s — åben backlog (2026-11-09)

> Målt i 6d-2a's Task 0 som anon på stand-in `…_6d1c` (prod + 6d-1, efter `ANALYZE`; median af 3):
> `public_person_bio_source_versions_v2` med alle personer (feedets form, `web/src/data/feedAux.ts`) ≈ 3080 ms;
> `select` på `public.narrative`, 1000 rækker pr. side ≈ 3000-3100 ms (RLS kalder publiceringsvagten pr. række).
> Anon-grænsen i prod er 3 s, og 6d-1 målte prod 2,5-2,7 gange langsommere end stand-in'en for koordinat-RPC'en —
> feedets biografikald fejler derfor sandsynligvis allerede i prod. Ikke målt i prod endnu (kun i projektejerens
> shell). **Projektejerens valg:** uden for 6d-2a; 6d-2a's budget er relativt (højst +10 %, spec rev. 4 §4.1).
> Næste skridt: én læsemåling i prod; derefter en løsning (fx feedet sender kun de viste personer, eller vagtens
> tilstandssammenligning gøres billigere), så den er klar før 6e.
>
> **Målt i prod 2026-11-10** (projektejerens shell, før 6d-2a): `bio_alle` 13.053 ms (≈4,5 × stand-in'en; koordinater
> 1.414 ms). Feedets biografikald fejler altså i prod i dag. **Projektejerens valg 2026-11-10:** 6d-2a går i prod
> først; biografilæserens hastighed er næste opgave bagefter. *Ændret samme dag: udskudt til før projektets
> afslutning (beslutningen ovenfor).*

## NOTERET: 6d-2a's kendte begrænsning — appens karantæne kan skjule både oversigt og detaljepost (2026-11-10)

> Codex-review af grenen (fund B1, = spec rev. 4 fund 8): reglen tæller kun offentlige personer på stien, men appens
> `collapseSameAs` kan sætte en komponent i karantæne af andre grunde. Gør den det for en komponent med en
> oversigtsomtale, mister oversigtspersonen sin biografi i læseren uden at få detaljepersonens i stedet. Målt på en
> prod-kopi med 6d-2a: ingen af de 11 komponenter er i karantæne (9 karantænegrupper før = efter). Færdigbeviset i prod
> gentager karantænetjekket; en fremtidig ændring af karantænereglerne skal tage hensyn til reglen.

## BESLUTTET: 6d-2 deles i 6d-2a og 6d-2b; oversigtsomtaler vises ikke som biografi (2026-11-09)

> Delspec `docs/superpowers/specs/2026-11-09-trin6d2a-oversigtsregel-identitet-design.md` (godkendt, rev. 3; rev. 4
> efter Codex-runden: reglen beregnes live i biografilæseren uden gemt markering, narrativ-RLS uændret, relativt
> tidsbudget — projektejerens valg 2026-11-09).
>
> - **Opdeling:** 6d-2a = oversigtsreglen, retningen i `samme_som`, 1014's kobling og tre oversigtspersonas'
>   identitet. 6d-2b = binding af de viste tekster (149b's migration kræver `record_key`, som kun 8 af 1939's 576
>   legacy-rækker har), 1939-profil til kildetekst-revision (38 rettelser), grænsemekanisme (6 grænsefejl). Grund:
>   to bygherre-tjek viste, at 2b kræver ny DDL i tre skriveveje.
> - **Oversigtsreglen (projektejeren):** en 1939-tekst vises ikke som biografi, når personen selv er uden gældende
>   1939-medlemskab, og komponenten har en anden, offentlig person med et og en synlig tekst. Maskinel, afledt,
>   automatisk og reversibel; skjult er ikke slettet; fakta og hændelser beholder kildelinjen. Er oversigtens tekst
>   den eneste om personen (Henning 1849), vises den.
> - **Retning:** redaktøren vælger *om*, systemet vælger *retningen*, når data kan afgøre den.
> - **Ændrer decisions 2026-11-07:** færdigbeviset »de 13 har record-binding« erstattes af 6d-2a §8 og 6d-2b.
> - **Ændrer decisions 2026-11-09 B:** dubletternes læservirkning løses af reglen (de fire par er allerede koblet via
>   deres 2018-20-person); den redaktionelle sammenlægning (identitet peget om, person udgår) bliver backlog.

## NOTERET: 6d-1 i prod — ledger via identitet, afledt B6 og afgørelse 4 som bygget (2026-11-09)

> Kørt i prod 2026-11-09 (GO `c8f09536` og `79609895`; færdigbevis `evidensbaseret-genimport/placement-6d1-prod.md`).
> Tre valg fra spec'en (§5.3, §5.4, afgørelse 4) står nu som bygget:
>
> 1. **Ledgeren kobler via identitet.** `record_legacy_disposition` godtager `mapped`, når legacy-rækkens person er det
>    accepterede kanoniske mål for en persona med accepteret persona-placement på placementens record — ikke via
>    postnøgle. 528 `mapped`. En uændret disposition får ingen ny version, så de 48 `retained_legacy` beholder 5c-1's
>    version 1; planens grund er kontrolleret i transaktionen, men ikke gemt. Skal grunden kunne læses senere, skal en
>    ny version skrives bevidst (ikke 6d-1).
> 2. **B6 er en læse-kun funktion.** `private.membership_component_states()` afleder `corroborated`/`conflict`/
>    `single`/`none` pr. `samme_som`-komponent (kun `afklaret`). Efter 6d-1: 441 / 3 / 212 / 224. Trin 6's færdigbevis
>    (c) er dermed opfyldt i data; læservisningen er 6e.
> 3. **Afgørelse 4 (læseren uændret for 1939):** `public_person_source_coordinates` bruger kun placement for en kilde,
>    når dens placements er entydige på `(entry, printed_number)`. 1939's numre er gruppelokale, så læserens
>    1939-rækker er byte-ens (`KOORD_SRC` uændret); prisen er ≈1,25 s for RPC'en som anon (før ≈0,55 s), accepteret
>    til 6e (decisions 2026-11-09 pkt. 4).

## BESLUTTET: 6d-1's generalprøve — helpost-regel, henvisningspost uden placement, staged biografier og læsertid (2026-11-09)

> Generalprøven på en stand-in fra prod-dumpet `1653c8f7…` (9/11) fandt tre fejl i ceremonien og to forhold, som
> projektejeren afgjorde.
>
> 1. **Helposten følger skemaets regel** (`be4001dc`). 1939's records har accepterede under-forekomster (fakta,
>    ægteskaber, relationer) med egne rod-observationer, så »den eneste rod-observation« fandtes ikke for 228 records.
>    Ceremonien bruger nu `private.record_helpost_status` med profilens helpost-type (`helpost_kind=person`).
> 2. **En henvisningspost placeres ikke** (`cf3ef35a`, projektejerens valg). Kortrunden modelgodkendte en
>    `cross_reference`-post (PDF 539, nr. 2 i gruppe III), som ingen personpost har. `approvals_1939` springer
>    `cross_reference` og `structural_context` over; kortene er uændrede. 528 records placeres i stedet for 529.
>    Henvisningerne tages op med dubletpersonerne i 6d-2/6d-3.
> 3. **Staged biografier uden for placeringen stopper ikke ceremonien** (`c32b414d`). Personerne 963 og 967 (staged
>    siden C0) har publicerede biografier, hvis baseline ved kontrakt-cutover fangede den blokerede tilstand; deres
>    records ligger i oversigtszonen. Kravet om tilladt publicering gælder kun records, der placeres.
> 4. **Læsertiden accepteres i 6d-1; 6e gør koordinat-RPC'en billigere** (projektejerens valg).
>    `public_person_source_coordinates` kalder `membership_is_current` pr. medlemskab (≈0,5 ms), og 6d-1 tilføjer 528:
>    som anon 225 → 580 ms på stand-in, i prod målt 563-612 ms før (faktor 2,5-2,7), forventet ≈1,45-1,57 s efter,
>    to kald pr. indlæsning (1113 rækker, sider à 1000), anon-grænse 3 s. 1939's rækker vises som legacy til 6e og
>    giver intet output for prisen. 6e, der alligevel omskriver RPC'en, skal gøre den billigere, før en ny udgave
>    lægges på; alternativet (kildegaten før aktualitetstjekket) ændrer læserens regel og blev fravalgt nu.
>
> **Åben backlog (konfliktkort, spec §6 pkt. 3):** komponenten 137↔937 (`samme_som` afklaret) bliver `conflict`:
> 2018-20 linje II nr. 1 (slægtled 1, linjens stamfader), 1939 Stamme-holstenske nr. 3 (slægtled 4), som mappingen
> fører til linje I. Sandsynligvis en linjegrundlægger, der står sidst i stammen og først i grenen. 6d-1 skriver
> intet om den; projektejeren afgør senere. De to andre konflikter fandtes før (178: 2018-20 III/IV, 1939 bekræfter
> IV; 255: kun 2018-20).

## BESLUTTET: 1939's nedstigningsoversigter er oversigtszoner uden placement; 4 dubletpersoner er åben backlog (2026-11-09)

> Opdaget af projektejeren: PDF 496-510 (trykt s. 7-21) forklarer sammenhængen mellem linjerne i kort form med
> henvisninger til detaljeposten (»Cay Friedrich … (se S. 75)«). Målt mod siderne rummer afsnittet tre slags tekst:
> **fællesstammen** (A holstenske, B ældre meklenborgske: ægte detaljeposter for middelalderens slægtled, kun her),
> **to nedstigningsoversigter** (PDF 504 »Fra ovennævnte Joachim …« til 505 »… ugift 1773.«; PDF 508 »En Sønnesøn (?)
> af Henning …« til 510 »… Mandsstammen i 1773.«, inkl. C's Gallentin-indledning) og intet andet. Oversigternes
> nummererede punkter (»1. Geheimeraad Ditlev«) havde narret alignmentet: guidens Stamme-ældre-meklenborgske.VI.1/VI.2
> blev parret med to oversigtspunkter (machine_ok), mens de ægte Henrik og Henning stod `ikke_alignet`.
>
> **A (gjort, 6d-1):** profilen `header-1939-v1.json` får `oversigtszoner` (to ankerpar, hvert entydigt i både Calamari
> og raw.txt, fail-closed `HEADER_OVERSIGTSZONE_ANKER`). Records, der begynder i en zone, får `unresolved` med
> `['uden_post', 'oversigtszone']` (ingen placement; ledger `ingen_nummereret_post`, ceremonien uændret) og indgår
> hverken i alignmentet eller hulparringen; guidens v2-oversigtsposter i zonen (Oversigt.Indledning.U1-U7) fjernes fra
> hullerne. En parret stamfader uden guidens slægtledsoverskrift (PDF 505: B's »I.« er »1.« i raw.txt og tabt i
> Calamari) får et gruppekort med v2-segmenteringens slægtled. En stammegruppe, der kun er en beskrivelse (PDF 503:
> »VII C. / Lyder Reventlows Søn:«), får gruppekort med beskrivelsens slug som værdi og besvares J/N af projektejeren.
> Manifestet efter: 27 records i zonerne (8 med persona), 414 machine_ok / 178 unresolved, 21 gruppekort, 20
> strukturkort, alle invarianter sande. Kortrunden bygges om (57 kort genbruger modelsvaret, 9 er nye).
>
> **Følge:** af de 8 personas i zonerne har 7 en detaljepost andetsteds. Den ottende, **1849 Henning (levede
> 1456-94)**, står kun i oversigten på PDF 508 og får ingen 1939-placement og intet 1939-medlemskab. Det er ikke nyt:
> før zonerne lå hans record som strukturkort (`ikke_parret`), forudfyldt N efter Gate A pkt. 3. Personen består med
> sine påstande; en placering som stammeperson kan tages op senere.
>
> **B (åben backlog — ikke 6d-1):** fire 1939-personer er oprettet alene fra en oversigtsomtale og dublerer personen
> fra detaljeposten (målt på stand-in c3h, prod-kopi 8/11): **991↔995** Iven †1569 (PDF 512), **992↔996** Sivert
> (PDF 513), **1017↔1071** Detlev †1783 (PDF 520), **978↔1136** Frederik til Neudorf / Friedrich †1728 (PDF 532).
> Oprydning via evidenskæden: oversigtspersonaens identitet peges om til detaljepostens person, og den overflødige
> person udgår (redaktionel sammenlægning; 1017 har historik i C0-efterkørslen). Desuden tre oversigtspersonas uden
> accepteret identitet (Ditlev †1664, Cay Friedrich †1762, Ditlev †1690) kan bindes til detaljepostens person. Ikke
> dublet: 1849 Henning (levede 1456-94) findes kun i oversigten; sønnen »se S. 39« er 960. Sidehenvisningerne i
> oversigterne er det stærkeste bevis ved parringen. evidenspas_v2 (7/2026) fangede 7 andre oversigtsdubletter.

## BESLUTTET: 6d-1's kort besvares af en model mod PDF-siden; projektejeren ser undtagelser og 5 stikprøver (2026-11-09)

> Ændrer kortrundens udførelse i beslutningen nedenfor (samme dag). Projektejeren: »bruge sonnet eller opus til disse,
> for at minimere mit arbejde med at genlæse ting« (præcedens: 6m's modelgennemgang og beslutningen 2026-11-05 om
> 1939-tekst til en model). Grundlaget før kortene, efter to rettelser i manifestet: (1) 1939's legacy-nøgler for gren
> VI er et løbenummer i bogens orden, ikke gruppens trykte nummer, så 26 falske `uenig:legacy_nr` forsvandt (391
> maskinelt godkendte, 201 uafklarede); (2) overskrifternes sider var Calamari-sider, mens databasens forekomster i
> samme rendition bruger PDF-sider — nu `CALAMARI_R6_TO_PDF_V1` i profilen, 592/592 sider = recordens `page_from`.
> Kortene (81): 20 blinde stikprøver; **18 gruppekort** for 98 poster (13 gruppe-romertal, 5 slægtled; ikke 19/121 —
> stamme-rettelserne flyttede tallene); 32 strukturkort; **nye:** 6 stammegruppe-kort (23 poster, beskrivelse i
> fællesstammen uden nyt romertal: slægtleddet bekræftes, ellers forbliver posterne uafklarede) og 5 nummerkort (nummeret
> springer i guiden). 45 poster får ingen placement (44 `uden_post`, 1 barn i forælderens slægtled).
>
> **Beslutning:**
> - **Opus læser PDF-siden** (sidebilleder af `Dansk Adels Aarbog - Reventlow 1939.pdf`, s. 496-598) og besvarer hvert
>   kort **blindt**: inputtet rummer ikke guidens værdi, maskinens slægtled/gruppe eller legacy-tal. Svaret rummer den
>   ordret læste linje og en sikkerhed. Inputtet bygges af et script i en jobmappe; modellen læser aldrig `~/.private`
>   eller `work*/`.
> - **Enighed** mellem modellens læsning og guiden/maskinen godkender kortet. **Uenighed eller ulæselig side** → en kort
>   undtagelsesliste til projektejeren (side, spørgsmål, modellens læsning, guidens værdi); hans svar afgør kortet.
>   Projektejeren slår desuden **5 tilfældige af stikprøvens enige poster** op. En afvigelse i stikprøven, som han
>   bekræfter, stopper og går tilbage til Task 1 (som før); modellens fejllæsning alene stopper ikke.
> - **Evidensen siger, hvem der læste:** placements fra model-godkendte kort får basis `model_page_review` med model og
>   briefens sha i `human_review`-feltet (`reviewer_kind`), projektejerens svar `human_group_review`. DB-feltnavnet
>   `human_header_levels` bevares (nærmeste-reglens undtagelse læser det); niveauet er bekræftet mod den trykte side,
>   uanset læser.
> - Kortfladen bliver undtagelseslisten (lokal HTML) i stedet for 6c-1-kortsiden med 81 kort.
>
> **Resultat (9/11, efter oversigtszonerne og rettelsen af slugte romertal; tallene ovenfor er forældede):** 66 kort
> (20 K, 21 GK, 20 SK, 5 NK; ingen SG). Opus enig på 54; projektejeren besvarede 12 undtagelser og 5 kontroller
> (alle J, ingen afvigelse). Approvals: 15 record-godkendelser + 21 gruppekort (35 model, 1 projektejer: Dr. Lyders
> beskrivelsesgruppe). **529 af 592 records placeres** (414 maskinelt, 115 via kort). Uden placement: 27 i
> oversigtszonerne, 26 `uden_post` (Gate A), 7 unummererede ægte stammeposter (PDF 499, 506 »III. Af den tredje
> Slægtsfølge …«, 541), 3 under en overskrift, Calamari har tabt (PDF 508, 532, 533).
>
> **Opfølgning (åben backlog):** de 7 unummererede stammeposter og de 3 under tabte overskrifter kan placeres i et
> senere skridt (strukturkortet kræver et trykt nummer; overskriften skal forankres). Projektejerens spørgsmål om
> fællesstammens model blev afklaret mod bogen: romertallet er slægtleddet (PDF 506 »den tredje Slægtsfølge«,
> henvisningerne »— Sønner: VI.«), mens linjerne trykker »Ottende Slægtled.« + gruppe-romertal (PDF 520).

## BESLUTTET: 6d-1's kortrunde — gruppekort for 19 manglende overskrifter og nærmeste-reglens undtagelse (2026-11-09)

> Plan `docs/superpowers/plans/2026-11-08-trin6d1-placement-medlemskab.md` (Task 3b, 1c, 7 r2, 8). 121 personposter står
> under 19 overskrifter (14 grupper, 5 slægtled), som raw.txt kender, men Calamari-renditionen ikke har. Projektejeren
> valgte **19 gruppekort**: han bekræfter mod PDF'en overskriftens værdi (romertal/ordinal), og bekræftelsen er
> evidensen for det niveau (basis `human_group_review`, som 5c-1's gruppegodkendelser; guidens linje-hash følger med).
> Det ændrer Gate A's regel »værdier kun fra Calamari« for netop disse poster: værdien kommer fra projektejerens
> læsning af siden. Konsekvens i DB: `private.placement_header_violations` springer nærmeste-tjekket over for præcis
> det bekræftede niveau, når placementens evidens har `human_header_levels` med niveauet og `header_ids` ikke angiver
> et id for det (linje kan aldrig undtages; lavere niveauer tjekkes stadig). Målt: uden undtagelsen ville databasens
> nærmeste-regel give 64 af de 121 poster den forrige gruppes eller det forrige slægtleds overskrift (55 slægtled, 9
> grupper). db-verify tæller placements med menneskelige niveauer. Fravalgt: at forankre en bekræftet overskrift i
> renditionen ved posthullet (fabrikeret evidens) og at angive den forrige overskrift (forkert evidens). Desuden: **32
> poster med ukendt struktur** (17 uparrede, 4 OCR-tabte numre, 11 uden nummer-match) kommer på kort med nærmeste
> Calamari-overskrifter og projektejerens nummer fra PDF'en.

## BESLUTTET: 6d-1's Gate A — 1939's overskrifter guides af raw.txt og forankres i Calamari-renditionen (2026-11-08)

> Plan `docs/superpowers/plans/2026-11-08-trin6d1-placement-medlemskab.md`, Task 0 (stand-in c3h). Calamari-
> renditionen, som 1939's records er forankret i, har mistet centreringen: segment.py's 1939-grammatik finder 5
> linjeoverskrifter (I mangler), 5 slægtled og 0 gruppe-romertal (raw.txt: 6, 48, 75; stammen 43 poster under 2
> sektioner). Overskrifternes tekst står der dog: søgt i vinduet mellem samme naboposter genfindes linje 6/6, stamme 2/2,
> slægtled 44/48, gruppebeskrivelser 68/77, romertal 29/75. Projektejeren sagde ja til alle seks anbefalinger:
> 1. **Kilde (6a):** raw.txt (sha `efab316b…`) er guide og kontrol; overskrifterne skrives som uankrede observationer på
>    Calamari-renditionen, hvor de genfindes. Ikke genfundne → kort. Validatoren ændres ikke. Samme princip som
>    build_1939_v2 (»struktur fra raw, prosa fra Calamari«). Fravalgt: raw.txt som ny rendition + validator på tværs af
>    renditioner (ændring af proveniensmodellen).
> 2. **Fællesstammen:** hver stammesektion bliver en entry i 1939's linjeskema; linjearket afgør dens linje.
> 3. **Records uden nummereret post — revideret samme dag** (godkendt på et forkert grundlag: 37 målt via Calamari-
>    segmenteringen). Målt mod raw.txt's 1939-v2-segmentering er de 83 records uden nummer i Calamari: 18 oversigtsposter,
>    18 stamfædre (17 i grenene, 1 i stammen; uden nummer i bogen selv), 4 med OCR-ødelagt nummer og 43 uparrede (17 med
>    persona). Et første genspørgsmål antog fejlagtigt, at stammens 38 var stamfædre (raw: 43 nummererede stammeposter);
>    projektejerens endelige svar på de rettede præmisser: **stamfædrene placeres uden nummer** (gren, slægtled og
>    gruppe fra overskrifterne; maskinelt kun med én stamfader i gruppen, ellers kort); **de 4 og de 17 uparrede med
>    persona går på kort** med raw.txt's forslag; **oversigtens 18 og de 26 uparrede uden persona** får ingen placement
>    (`retained_legacy` med grund).
> 4. **Læseren:** `public_person_source_coordinates` bruger kun placementkoordinater for en kilde, når dens gældende
>    placements er entydige på `(entry, printed_number)`; ellers legacy for hele kilden. 1939's numre er gruppelokale
>    (53 numre deles af 389 poster), så 1939 vises som i dag indtil 6e; 2018-20 byte-ens.
> 5. **Tre personas uden accepteret identitet:** record-placement, ingen persona-placement eller medlemskab. Antallet af
>    persona-placements beregnes af manifestet (højst 534: 29 personas sidder på records uden nummereret post; rettet
>    efter Codex r1 #1 — »560« var en regnefejl). De 29 får intet 1939-medlemskab i 6d-1.
> 6. Task 0 måles på c3h i stedet for en frisk prod-kopi (`dump-kopi` læser prod og er ikke på allowlisten; 6c-3 rørte
>    kun 2018-20). Frisk stand-in til generalprøven (Task 9).

## BESLUTTET: 6d deles i 6d-1, 6d-2 og 6d-3; medlemskab før relationer; 1939's »linje« er grenen (2026-11-08)

> Delspec 6d godkendt med specens §3 og §9: 6d-1 (overskrifter, placement, revalidering, ledger, medlemskab og afledt
> B6), 6d-2 (personas for de 21 records uden, de 13 narrativer, identitetsflytningerne, de 39 tekstrettelser), 6d-3
> (relationer; børn på placementkoordinater). Justerer trin 6-specens §5's interne rækkefølge: medlemskab/B6 rykker
> før relationerne, fordi færdigbevis (c) kun afhænger af placement og medlemskab. 1939's grene er entries i
> linjeskemaet; slægtled og gruppe står i `section_path`. Læserens visning af 1939-koordinaterne hører til 6e.

## BESLUTTET: B6 bygges som afledt bekræftelse på komponentniveau, ikke som flere grundlag pr. medlemskab (2026-11-08)

> Delspec 6d (`docs/superpowers/specs/2026-11-08-trin6d-placement-relationer-medlemskab-design.md` §5.4). Justerer
> trin 6-specens §6 pkt. 3 (»et medlemskab kan have flere kildegrundlag … datamodellen afgøres i 6d«).
>
> - **Grund (målt på stand-in fra prod, Fable-review):** 1939's personas peger på kilde 3-personrækker (trin 6-specen
>   §6 pkt. 8), mens de 458 medlemskaber, de kunne bekræfte, ligger på 2018-20-rækker i samme `samme_som`-komponent.
>   Et medlemskab har PK `(person_id, lineage_id)`, og fem funktioner plus læseren læser dets ene `source_basis`. Et
>   1939-grundlag på 2018-20-rækkens medlemskab ville kræve dem alle omskrevet og fortrydelse pr. grundlag.
> - **Afgørelse (projektejeren):** hver udgave giver sin egen personrække medlemskab som i 5c-1; `corroborated`,
>   `conflict` og `single` afledes af en læse-kun funktion over komponentens medlemskaber, kun gennem `samme_som` med
>   `afklaret` konklusion. Promotionen får en vagt, så et medlemskab aldrig overskrives af en anden kildes grundlag.
> - **Følge:** trin 6's færdigbevis (c) opfyldes, når mindst én komponent er `corroborated` (to kilder, samme linje);
>   læservisningen af det hører til 6e.

## NOTERET: review-budget for delspec 6d overskredet med én Fable-læsning af udkastet (2026-11-08)

> Projektejeren bad om et review af udkastet. Fable (stående ja, memory) gav NO-GO med 10 fund, alle indarbejdet
> (specens §11). Budgettet i spec-hovedet (1 Codex-runde på spec+plan, 1 på diffen) står uændret.

## BESLUTTET: 6c-3's modelsvar er sammensat pr. post af tre kørsler — godkendt af projektejeren, valg A (2026-11-08)

> Det forslagsmanifest, data-ceremonien binder (`manifest_content_sha256` 95928243…, runner-manifest 5cc7f719…), er
> ikke én modelkørsel. Det er sat sammen pr. post af tre kørsler med samme model (`gpt-5.6-terra`), prompt (1.0.0) og
> runner-manifest. Hvert valgt svar er et uredigeret modelsvar fra cachen, og alle har været gennem kortene
> (stikprøve 10 × B, 3 × D) og T/V-arket.
>
> - **Hvem afgjorde hvad:** projektejeren godkendte 8/11 en genkørsel af de 5 poster med tab, efter T/V-arket fra
>   kørsel 1 viste 6 tilbagetrækninger. *Reglen for at vælge mellem kørslerne* afgjorde hovedsessionen selv
>   (»Ruling« i SDD-ledgeren). Den er ikke forelagt projektejeren. Reglen er: pr. post vælges den kørsel, der
>   genfinder flest gamle bindinger, og derefter flest ubundne gamle nøgler.
> - **Valget** (`~/.private/6c3/model-final/sammensaetning.json`, cache-nøgle og fil-sha pr. post): kørsel 1 (alle
>   9 poster) for I-17, I-18, I-32, I-33 og III-37; kørsel 2 (5 poster) for I-44, I-89 og I-9; kørsel 3 (2 poster)
>   for I-11.
> - **Hvad det betyder i tal:** kørsel 1 alene giver 10 genbundne og 6 tilbagetrukne kildehenvisninger. Det sammensatte
>   svar giver 14 genbundne og 2 tilbagetrukne. De fire, der kommer tilbage, er I-11's børn, I-44's forældre og
>   navnene på I-89 og I-9. I-9's titel og III-37's børn tabes i alle tre kørsler.
> - **Indvendingen:** at vælge den kørsel, der stemmer bedst med den gamle import, belønner overensstemmelse med de
>   gamle data. Det svarer til at plukke de bedste resultater. Prod får et bedre tal, end én kørsel ville give.
>   Variationen mellem kørslerne viser samtidig, at modellens læsning af disse poster ikke er stabil.
> - **Argumentet for:** en binding genskabes kun, hvis den nye påstand matcher den gamle i SQL
>   (`binding_value_matches`) og bogen stadig siger det (stikprøven). Udvælgelsen kan altså ikke skabe en binding, der
>   ikke står i bogen. Den kan kun vælge mellem læsninger, hvor modellen fandt den.
> - **Valgmuligheder, der blev forelagt:** A) behold det sammensatte svar (klar, øvet på c3e/c3f/c3g). B) kørsel 1
>   alene (kræver svar på dens T/V-ark med 6 linjer, en ny pakke og en ny generalprøve). C) én frisk kørsel af alle 9
>   poster, brugt som den er (ca. 180.000 tokens og nye kort, T/V og generalprøve; viser samtidig stabiliteten).
> - **Afgørelse (projektejeren 8/11): A.** De fire ekstra bindinger er efterprøvet mod bogen. Navnene på I-89 og I-9
>   blev besvaret B på faktakortet. I-44's forældre og I-11's børn blev godkendt på forælder- og børnearket, som de var
>   forudfyldt. Projektejeren så derudover I-44's linje igen i kontekst-siden før afgørelsen. Ustabiliteten mellem
>   kørslerne er et fund til 6d, ikke en grund til at genkøre her.
> - **Fremover:** udvælgelsesreglen var valgt efter kørslerne. Bliver genkørsel pr. post normal praksis, skal reglen
>   være et værktøj med et fast kriterium, besluttet før kørslen (Task 8-note 7).

## BESLUTTET: 6c-3's afgrænsning — specens §8 pkt. 1-6, `BEGGE` flyttet til opret-benet/6e (2026-11-07)

> Delspec 6c-3 (`docs/superpowers/specs/2026-11-07-trin6c3-a6b-resten-design.md`) godkendt med anbefalingerne:
> genkørsel med den oprindelige model og prompt (pkt. 1); de 4 forælder/barn-afgørelser genbesvares på kort (2);
> `BEGGE` (fakta, der både er rettelse og ny oplysning) flyttes fra 6c-3 til opret-benet/6e (3); I-84 forbliver
> parkeret (4); DDL-blok 6c-3a med genbrug af ægtefælle-persona, så de 3 ægteskaber genbindes (5); afstemningen
> kvitteres i en ny generel tabel (`private.text_revision_reconciliation`) i samme blok (6).

## NOTERET: værktøjsrettelser fra 6c-3's kortrunde — åben backlog (2026-11-08)

> Fra Task 7's kort- og T/V-runder. Ingen af dem påvirker prod-ceremonien, som kun genbruger svarene. De gør næste
> kortrunde (6d) lettere:
>
> - forælderarket mangler kontekst: HTML-siden med post, side, barn og familiens forældre og børn (nr = `row_no`)
>   blev bygget privat og bør være et repo-værktøj;
> - T/V-siden skal vise den gamle påstand (familie med navne) og sige »bogen siger det stadig; modellen udtrak det
>   ikke«;
> - kortet viser bevidst ikke klassen, så mærket »B = bogen og databasen er enige« findes ikke. Vejledningen skal
>   stå på kortet;
> - genkørsel og sammensætning pr. post (cachekort + sammensæt) bør være et værktøj, hvis det bliver praksis (se
>   ovenfor);
> - `relation_persona_input.sql` skal køres med `psql -q`, ellers kommer `SET`/`COMMIT` ind i JSON'en;
>   `run_evidence_43b.py --out` er en fil, ikke en mappe.

## NOTERET: manuel indtastning af en påstand efter bogen, når modellen ikke udtrækker den — åben backlog (2026-11-08)

> Fundet i 6c-3's genkørsel (Task 7). Efter tekstrevisionen kan en binding kun genskabes, hvis modellens nye
> læsning af posten indeholder samme påstand. To påstande kom ikke med i nogen af tre kørsler, selvom bogen stadig
> siger dem: I-9's titel (påstand 379) og III-37's børn (familie 157). Projektejeren trak dem tilbage (T); faktum og
> familie står uændret, men uden kildelinje til 2018-20-posten.
>
> - **Behov:** en redaktør skriver påstanden ind efter bogen (prædikat, værdi, citeret klausul) som en
>   menneskelæsning, der derefter afgøres og bindes som en modelpåstand, med samme proveniens som 6m del 2's
>   `menneske-laesning-v1` (`red_ret_forslag`), som kun kan rette et eksisterende forslag.
> - **Første brug:** de to tilbagetrukne henvisninger fra 6c-3 kan genskabes.
> - **Retning (ikke besluttet):** ny skrivevej eller udvidelse af `red_ret_forslag`; placering i roadmapet afgøres af
>   projektejeren.

## BESLUTTET: 6c-3's genkørsel — de 10 % afviste claims accepteres, og det nye I-11-ægteskab udskydes (2026-11-08)

> Fra Task 7's øvelse på stand-in'en (`daa5ab_ddl_standin_20261107211140_c3b` + blok 6c-3a). Modellen
> (`gpt-5.6-terra`, prompt 1.0.0) dækkede 9/9 poster med 69 claims; runnerens kontraktværn afviste 7 (10,1 % mod
> 2018-20's 5,1 %). Det er to mønstre: 4 × `mention.organization` (ukendt prædikat) og 3 × `person.name` afleveret
> som objekt `{raw, normalized}` i stedet for tekst (I-17, I-89, I-9).
>
> - **Afviste claims (projektejerens valg 1):** accepteres. Af de 9 bundne fakta genfindes 6; de 3 andre (I-89 navn,
>   I-9 navn, I-9 titel) trækkes tilbage via T/V-arket. De to navne-tab skyldes den afviste form. For læseren står
>   navnene uændret, men som »fra den oprindelige import« i stedet for bundet til bogens post.
> - **Nyt ægteskab på I-11 (valg A):** modellen fandt et ægteskab uden gammel nøgle (sandsynligvis i de genindsatte
>   linjer). Det filtreres fra partsbatchen, så 6c-3 ikke opretter en ny ægtefælle-persona (specens §6). Forslaget
>   står `proposed` uden parter og indgår derfor ikke i ceremoniens maskinelle ægteskabsmængde
>   (`private.relation_decision_set` kræver parter). Det kan tages ind senere med de eksisterende trin
>   (`relation_persona`-batch for nøglen → identitet for ægtefællen → afgørelse og binding), naturligt i 6d.
>
> Gate-afvigelsen er samme type som 6c-1's pilot (7,4 %, decisions 2026-11-01): afviste claims når aldrig basen.

## NOTERET: forslagsbyggeren afviser navne afleveret som `{raw, normalized}` — åben backlog (2026-11-08)

> Fundet i 6c-3's genkørsel (se ovenfor): 3 af 69 claims var `person.name` som objekt med rå og normaliseret form,
> hvor kontrakten kræver tekst (`RUNNER_CLAIM_VALUE_INVALID`). Det kostede 2 genbindinger.
>
> - **Retning (ikke besluttet):** runnerens/forslagsbyggerens kontrakt accepterer formen og bruger den rå tekst,
>   med test og review som kontraktændring. Alternativt strammes prompten.
> - **Hvorfor det er værd at gøre:** fejlen er systematisk, ikke tilfældig, og rammer igen i 1939/6d og senere
>   udgaver. Placering i roadmapet afgøres af projektejeren.

## NOTERET: review-budget for delspec 6c-3 overskredet med én Fable-læsning af specen (2026-11-07)

> B13-overskridelse. Projektejeren bad om et review af udkastet til delspec 6c-3
> (`2026-11-07-trin6c3-a6b-resten-design.md`) før planen. Fable: NO-GO, 12 fund (3 HIGH: komparatoren, ægteskabernes
> genbinding kræver DDL, ingen kvitteringstabel), alle afvejet og indarbejdet (specens §10). Budgettet for resten af
> 6c-3 er uændret: én Codex-runde på spec+plan, én på diffen.

## NOTERET: 1939's datoer uden punktum efter dagen får årsgrænser — åben backlog (2026-11-07)

> Fundet ved 6m del 2's stikprøve (person 1080, »8 Okt. 1746«). `validate.derive_date_info` afgrænser kun formen
> »8. okt. 1746« (punktum efter dagen); 1939's form »8 Okt. 1746« falder tilbage til hele året (`1746-01-01` –
> `1746-12-31`). Teksten (`date_raw`) er rigtig; det er intervallet, søgning og sortering bruger, der er for groft.
>
> - **Målt** på en prod-kopi fra 7/11 (før 6m del 2's A, stand-in `_6m3`): af påstandene med `date_raw`, citeret af
>   1939 (kilde 3), har 261 af 1.301 årsgrænser, heraf 187 hvor teksten har dag og måned. Kilde 1 (2018-20): 2 af 3.171.
>   7 af 6m del 2's 9 rettede datoer har årsgrænser (den gamle påstand havde de samme).
> - **Ikke en regression:** 6m har ikke ændret grænserne; de stammer fra 1939's import.
> - **Retning (ikke besluttet):** parseren lærer 1939's form; grænserne rettes som en evidensbåret rettelse (ny
>   påstand eller en ceremoni som 6c-2's), ikke ved direkte UPDATE (invariant 1). Placering i roadmapet afgøres af
>   projektejeren.

## BESLUTTET: trin 6m del 2 — skriveveje for faktaforslag (2026-11-07)

> Del 1 er i prod (decisions 2026-11-06). Del 2 skal give projektejerens læsning af bogen en vej ind i databasen for
> de faktaforslag, modellen markerede, uden at overskrive påstande
> ([plan](superpowers/plans/2026-11-07-trin6m-del2-faktaforslag.md),
> [spec](superpowers/specs/2026-11-05-trin6m-modelgennemgang-1939-design.md) §4.4).
>
> - **Fuld del 2 frem for en minimal del 2 uden DDL** (projektejeren 7/11).
> - **Ny generel skrivevej `red_ret_forslag`** (blok 6m-a): opretter en ny `proposed`-version af et forslag med en
>   menneskeligt godkendt værdi (`method='menneske-laesning-v1'`, `derivation_kind='human_judgement'`). Kontrollen af
>   bindingen er udskudt til commit (`FORSLAG_BINDING_TABT`), så et genåbnet, bundet accepteret forslag genbindes i
>   samme transaktion. Basis `menneske-laesning-v1` er reserveret i `red_decide_interpretation`.
> - **Genåbning kun ved udtrykkeligt `F`:** et `F` på kortet må genåbne en afgørelse fra 6c-2; kortet viser den
>   tidligere afgørelse. Uden `F` står afgørelsen.
> - **Samlet `F` for de klasser, der ikke ændrer databasens værdi** (svarfil side 1001): `VERSION` (forslaget får
>   bogens læsning og forbliver `proposed`) og `BIND` (fakta, hvor databasen allerede siger det samme som bogen, får
>   1939 som kilde). Projektejeren ser kun kortene for `RET_OG_BIND`, hvor databasens værdi rettes. Foreløbige tal,
>   målt 7/11 på en prod-kopi fra 6/11 (før del 1's B-ceremoni; forslag uændret af den): VERSION 56, BIND 23,
>   RET_OG_BIND 14, SPÆRRET 4 (navn forkortes 2, dato uden grænser 1, mål bundet af anden 1), rapport 144. De
>   genmåles mod prod, før svarfilen skrives.
> - **Registreres til 6c-3/6d uden skrivning:** relationer, omtaler og hændelser; `BEGGE` (62, heraf 41 titler; input
>   til 6c-3's spørgsmål om et svar »begge rigtige«) og `TVIVL`.
> - **Ændrer decisions 2026-11-06:** de 13 1939-narrativer uden record-binding og de 39 tekstrettelser uden
>   læsertekst at rette (38 på 14 poster uden narrativ, 1 på et narrativ, der kun må trækkes tilbage) flyttes fra del 2 til **6d**. Målt: der er ingen skrivevej under kontrakt v2 uden placements
>   (`red_upsert_narrativ` afviser DAA-kilder med `NARRATIVE_RECORD_REQUIRED`), og 1939 får først placements i 6d.
>   6d ejer dem; færdigbevis: »de 13 har record-binding og er læst efter spor B«.
> - **I prod 2026-11-07** (PR #303, `database-current-state.md` §22): prod-målingen gav de samme tal som de foreløbige
>   (VERSION 56, BIND 23, RET_OG_BIND 14, SPÆRRET 4, rapport 144); projektejeren svarede F på alle 14 kort.

## BESLUTTET: trin 6m (modelgennemgang af 1939) indsættes mellem 6c-2 og 6c-3 (2026-11-06)

> 6c-2 er i prod 2026-11-06 (tilstand d). Dens kort dækkede kun 150 af 1939's 2.774 forslag, og øvelsen 5/11 viste, at
> en model finder OCR-fejl, der ellers kun findes ved at læse hele bogen (spec §1, §3).
>
> **Beslutning:** trin 6m indsættes i roadmappets trin 6 mellem 6c-2 og 6c-3
> ([spec](superpowers/specs/2026-11-05-trin6m-modelgennemgang-1939-design.md), PR #299; plan del 1, PR #300).
>
> - **Vej (a)** (projektejeren 5/11): spor B retter *læserteksten* (narrativet) via
>   `red_revider_publiceret_person_narrative_record`; klausuler, forslag, afgørelser og 6c-2's bindinger rører sig ikke.
>   Kildeteksten rettes kun sag for sag (svaret `K`), fordi en tekstrevision erstatter alle postens forslag, også
>   godkendte.
> - **Del 1** (denne gren): værktøjet, hele modelkørslen (spor A og B), projektejerens B-kort og ceremonien for
>   læsertekst. **Del 2** (senere plan): A-kortene, ny DDL for en forslagsversion med menneskelig læsning (spec §4.4),
>   kildetekstsagerne fra `K` og skrivevejen for narrativer uden record-binding.
> - Modellen er Opus-underagenter i Claude Code under afgrænsningen i decisions 2026-11-05 (filter, ingen interne id'er,
>   svar kun som antal). Modellen foreslår; projektejeren afgør.
> - **Filteret gælder databasens værdier, ikke forslagene** (projektejeren 6/11, ændrer spec §4.2.1): 221 forslag om 111
>   personer uden fødsels- og dødsår i databasen går til modellen *uden* databasens værdi for personen, i stedet for at
>   gå udenom. Modellen læser alligevel bogens tekst om dem i spor B, og forslagene er udtrukket af samme tekst; det,
>   filteret beskytter, er databaseværdier, der kan stamme fra senere udgaver.
> - De 13 1939-narrativer uden record-binding kan ikke knyttes til en post (1939 har ingen placements før 6d) og går
>   derfor ikke til modellen i del 1; de står i eksporten til del 2 (flyttet til 6d 2026-11-07, se ovenfor).
> - **Grænsen for projektejerens gennemgang gælder pr. del** (projektejeren 6/11 efter piloten, ændrer spec §4.3.3):
>   piloten (bid 1 af 24) gav 22 svarbare tekstrettelser og 7 markerede faktaforslag, dvs. ca. 530 + 170 punkter i
>   alt. Del 1 retter kun læsertekst; faktapunkterne vises på del 2's kort og tæller ikke i del 1. Projektejeren
>   godkendte ca. 530 tekstpunkter i flere omgange; vagten i `saml` er 600 B-grupper.
> - **Samlet svar på de billedbekræftede rettelser** (projektejeren 7/11): efter at have godkendt alle 328 rettelser på
>   kortside 1-8 (heraf 63 i tvivl, ingen afvist) besluttede projektejeren L på alle 224 rettelser, modellen så på
>   sidebilledet, på side 9-15. Beslutningen ligger som én svarfil med sidenummer 1001 og kildenoten ved de øvrige
>   svar, bundet af manifestet og GO-koden. Projektejeren besluttede samme dag L også på de 54 tvivlsrækker på
>   side 9-15 (svarfil 1002), så alle 606 svarbare rettelser er L; tvivlsrækkerne er ikke kontrolleret mod
>   sidebilledet af nogen, men på side 1-8 holdt alle 63 tvivlsrækker.
>   Modellens forslag bliver kun til en rettelse gennem denne udtrykkelige beslutning, ikke af sig selv.

## BESLUTTET: tekst fra DAA 1939 må sendes til en model som beslutningsstøtte — bogens personer lever ikke (2026-11-05)

> Spørgsmålet opstod før 6c-2's ceremoni 4: 121 persona-kort med 150 felter skal besvares af projektejeren, og
> projektejeren spurgte, om en model kan hjælpe. Invariant 8 og `CLAUDE.md` forbyder at sende arbejdsmappernes prosa
> til en model, fordi den omtaler levende personer. DAA 1939 rummer personer født senest 1936.
> **Projektejeren oplyser:** den ældste nulevende Reventlow er født i 1946, så ingen af bogens personer lever.
> Databasen kan ikke vise det selv: på en prod-kopi (5/11) er `person.levende` false for alle 559 personer bundet til
> 1939, men 28 af dem, født 1900 eller senere, har intet dødsfaktum (16 født 1915 eller senere, den yngste 1936).
> Kilden er altså projektejerens viden, ikke data.
>
> **Beslutning:** tekst fra DAA 1939 (poster, posttekst, 1939-forslag og deres kontekst) må sendes til en model som
> beslutningsstøtte. Afgrænsning:
>
> - Kun 1939-tekst og værdier om personer i 1939-bogen. Andre udgaver (2018-20, præsenslisten 2012-14) er uændret
>   omfattet af invariant 8.
> - Databasens værdier kan stamme fra senere udgaver. Kortenes familieliste kan derfor rumme personer født efter 1939
>   (børn, børnebørn), som kan leve. Et modelinput bygges af et script, der kun medtager personer født senest 1939
>   eller med dødsfaktum; andre udelades. Modellen læser kun det input, aldrig `~/.private` eller arbejdsmapperne
>   direkte.
> - Modellen foreslår; projektejeren afgør. Modellen skriver aldrig i et ark eller i databasen, og et
>   modelforslag er ikke et `human`-svar.
> - Projektejeren bekræftede (5/11), at oplysningen også dækker ægtefællerne i bogen.

## BESLUTTET: »højst én gældende binding pr. påstand« under samtidige REPEATABLE READ-kald — åben backlog + driftsregel (2026-11-04)

> Codex-reviewet af 6c-2 (T12) fandt, at 6c-2's nye værn `ALREADY_BOUND_OTHER` (en påstand bindes kun af én
> fortolkningsnøgle) kan omgås, når to transaktioner binder forskellige nøgler til samme påstand samtidig, og mindst
> én kører `REPEATABLE READ`: låsen serialiserer kaldene, men fornyer ikke snapshottet, og unikhedsindekset dækker kun
> (fortolkning, mål). `transfer_pack.py` (bindingstrinnet) vælger `REPEATABLE READ` og binder via batch-RPC'en, der
> også kan kaldes af `authenticated`-redaktion; redaktørfladen kalder den ikke. Efterkontrollerne opdager kun
> bagefter (`MAAL_FLERE_BINDINGER`). 6c-2's egen ceremoni (én session, `READ COMMITTED`) er ikke ramt, og værnet
> fandtes ikke før 6c-2, så det er ikke en regression. **Projektejeren valgte:** åben backlog; rettes i en senere lille
> PR (batch-RPC'en kræver `READ COMMITTED`, transferens bindingstrin tilpasses, to-sessionstest). **Driftsregel indtil
> da:** ingen anden binding, overførsel eller redaktion mod de berørte fakta, mens en ceremoni eller en overførsel med
> bindingstrin kører.

## BESLUTTET: 6c-2's afgrænsning — A6b-resten bliver 6c-3; fjerde svar »forkert person«; linjeskift-rettelse uden kort (2026-11-02)

> Projektejeren i spec-runden for 6c-2 (`docs/superpowers/specs/2026-11-02-trin6c2-1939-bundet-til-bogen-design.md`).
> **Mål:** 1939-fakta bundet til bogen i læseren; fakta pr. udgave er fortsat 6e. **6c-3:** A6b-resten for 2018-20's
> 10 poster skilles ud og kører efter 6c-2 med eget B13-budget; overordnet spec §6 pkt. 7's begrundelse (»hvor
> runneren alligevel kører«) holder ikke, da runneren kørte i 6c-1. **`NO_FACT`** (personer uden navnepåstand m.fl.)
> venter på opret-benet og står synligt uafklaret. **Fjerde svar** ud over overordnet spec §6 pkt. 2's tre: »forkert
> person« (`P` / `P <person-id>`) pr. persona; kortene grupperes pr. persona, så en navnefælle-fejl kan ses på dato og
> titel. **De 70 datoer med linjeskift i importens `date_raw`:** deterministisk transskriptionsrettelse (mellemrum
> samles) af 1939's egen påstand uden kort, originalen i journalen — en afvigelse fra §6 pkt. 2's krav om et svar pr.
> rettelse, begrænset til påstande som alene kilde 3 citerer og som er eneste mål for et datoforslag. **Retning 2's
> ubekræftede identiteter** (ca. 440) behandles som alle andre; stikprøven på 20 stratificeres med 10 blandt dem. **Identitetsflytning** (kort 122 og
> `P <id>`) flytter også postens narrativpublicering til den nye person, så prosa og fakta står samme sted; kan
> narrativvejen ikke det uden ny DDL, falder 6c-2 tilbage til at udskyde flytningerne. **Faldet til (c) samme
> dag:** narrativvejen kræver accepterede placements, og kilde 3 har 0 (de kommer i 6d; målt i prod, Codex-runden på
> spec+plan). Kort 122 og `P`-svar sætter identiteten `unresolved` med `ønsket_person_id`; narrativet bliver stående som
> 6c-1's F; flytningen sker i 6d.

## BESLUTTET: 1939's identiteter (6b's C) — C3-bindingen er identiteten, kun konflikter på kort (retning 2) (2026-11-02)

> Øvelsen af 6b's ceremoni C gav 550 kort mod et loft på 90. Projektejeren valgte 2026-11-01 retning 2 blandt tre (ret
> C's regler: ~445 kort; C3-binding som identitet; udskyd 1939's identiteter). **Automatisk** på den publicerede
> C3-binding (oprindelsen `publication_binding`): `enig`, `svag` (alle årsager; `partner_hoejere` og `under_margin` er
> målt til bindingspersonens egen `samme_som`-partner) og `ingen_kandidat` (ingen kandidatrækker). **Kort:** `uenig`,
> `navnefaelle` og, efter måling og projektejerens valg 2026-11-02, de 45 personas med kandidatrækker, hvor
> bindingspersonen ikke er med (klassificeres `uenig/egen_ikke_kandidat`). Stikprøven på 20 trækkes blandt de
> automatiske; ét F/U stopper C. Loftet hæves til 125 (forventet 124). Konsekvens: ca. 440 personas, heriblandt de 61
> fra `excluded` poster, får identitet på C3-bindingen fra august uden at generatoren bekræfter den; udfaldet står i
> evidensen, så 6c-2 kan tage dem op. Delspec 6c-1 §4.8; 6b §4.3 pkt. 3-6 er ændret for 1939.

## NOTERET: review-budget for 6c-1 overskredet med én Codex-runde på retning 2's diff (2026-11-02)

> B13-overskridelse. Retning 2 ændrer C's klassifikator og writer efter, at 6c-1's to runder er brugt. Én Codex-runde
> (`gpt-6.1-sol`, Opus afvejer) på diffen før prod.

## BESLUTTET: delspec 6c deles i 6c-1 (runner + 6b's identiteter) og 6c-2 (kontrol, rettelse, binding) (2026-11-01)

> Projektejeren 2026-11-01: 6c deles i to, identiteterne først. **6c-1** kører runneren på 1939's tilladte poster,
> lægger forslagene i prod og kører 6b's ceremoni C. **6c-2** rummer kontrolmodellen på 1939's forslag,
> rettelsesvejen, bindingerne, vej B og A6b-resten for 2018-20 (overordnet spec §5 6c, §6 pkt. 2, 5 og 7). Rækkefølgen
> i den overordnede spec er uændret; delingen justerer kun grænsen (»grænserne kan justeres i delspec'erne«). Hver
> halvdel får sit eget B13-budget: 1 Codex-runde på spec+plan og 1 på diffen før prod. Begrundelse: én 6c ville samle
> syv leverancer og en ceremoni fra 6b bag én spec, så intet kom i prod, før det hele var færdigt.
> Delspec: `docs/superpowers/specs/2026-11-01-trin6c1-runner-og-identitet-design.md`.

## BESLUTTET: 6c-1 — restrisikoen i 1939's eligibility accepteres; lokal Postgres beholder `trust` i 6c-1 (2026-11-01)

> Projektejeren godkendte delspec 6c-1 og valgte anbefalingerne i §8 pkt. 1-2. **Eligibility:** politikken
> `exclusion-1939-v1` (årstal ≥ 1915 hvor som helst i posten, streng + OCR-tolerant læsning; levende/privat/staged
> hovedperson, `samme_som`-partner eller familiemedlem) er værnet. Restrisikoen — en levende slægtning nævnt i prosaen
> uden et årstal, reglen kan finde — accepteres som for 2018-20's 488 poster. **`trust`:** den lokale Postgres skifter
> ikke til `scram-sha-256` i 6c-1; Seatbelt-profilens spærring af socket og TCP og `gate-access-test.sh` før hvert
> rigtigt kald er værnet (review 35 P1 (2) står åben som egen opgave efter trin 6).

## NOTERET: 6b's ceremoni C kan køres igen efter fortrydelse (2026-10-31)

> Afsluttende review I2: efter `red_reverse_reimport_publication` gik personaerne før til den menneskelige webkø, og en
> ny C døde på versionskonflikt. Projektejeren valgte genkørsel. En *fortrudt publikationsidentitet* er en
> identitetsrække i `superseded`, hvis seneste overgang er fortrydelsen af en `publication_identity`-batch
> (`private.publication_identity_reverted`: den fortrudte batch, dens reversal-hændelse og C's kvittering for den
> forrige version). Den tæller som ingen identitet i køvagten, finalize's kontrolmængde og stikprøvens population. Den
> eneste kerneændring er snæver: oprindelsen `publication_binding` godtager en version ≠ 0, når og kun når identiteten
> er en fortrudt publikationsidentitet. C-writeren håndhæver det samme for alle udfald (også `human`/S/F/U). Den eneste
> udgang for en ventende persona er en ny C (controller-beslutning efter I2-reviewet): mens den venter, er den skjult i
> webkøen og spærret for `red_afgoer_source_persona`, så 6b har ingen menneskelig nødudgang. Kan C ikke gennemføres
> igen, forbliver personaerne skjulte, indtil en ny beslutning tages. Tilstandsmodel og andre kaldere er uændrede.
> Spec §6; `db-migrations.sql` blok »trin 6b opfølgning: C kan genkøres efter fortrydelse«.

## NOTERET: 6b's identitetswriter kalder kernen med `human` direkte (2026-10-31)

> 5a §4.2 siger, at oprindelsen `human` kun kommer fra `red_afgoer_source_persona`. I trin 6b skriver
> `publication_identity` også projektejerens S/F/U fra kortarket med `human` (`basis='human_sheet'`, arkets hash og
> linje), fordi wrapperen ikke kan sætte `reason` (`publication_binding_disputed`, `unknown`) og afviser personas, der
> venter på kontrol. Kernens krav til `human` er uændrede. Plan: `2026-10-31-trin6b-identitet.md` Task 6.

## NOTERET: review-budget for delspec 6b overskredet med én Codex-runde på specen (2026-10-31)

> B13-overskridelse. Projektejeren bad om et review af udkastet til delspec 6b
> (`2026-10-31-trin6b-identitet-design.md`) før planen. Codex (`gpt-6.1-sol`): NO-GO, 11 fund, alle afvejet og
> indarbejdet (specens §10). Budgettet for resten af 6b er uændret: én runde på spec+plan, én på diffen.

## BESLUTTET: I-84 parkeres i trin 6; B7 som deklareret tekstform pr. udgave (2026-10-29/30)

> Projektejerens valg 2026-10-29 (I-84). B7 er mit valg i delspec 6a
> (`2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md` §4.1 og §5); projektejeren sprang de
> afklarende spørgsmål over og bad om bedste skøn. Projektejeren godkendte delspec 6a som helhed, herunder B7,
> 2026-10-30.

1. **I-84 parkeres.** Den genfundne linje ligger uden for postens forekomstspænd (mellem I-84 og I-85), så en
   rettelse kræver grænserevision (ny forekomst og nyt anker). Den gør publicerede narrativer `stale_published`
   og rammer alle læsere af ankre. Posten har 0 fortolkninger, og narrativet har linjen siden A6b. I-84 får en
   synlig disposition; grænserevision følger opret-benets spor (B4). *Justerer* posten 2026-10-28 pkt. 2: trin 6
   retter 10 af de 11 poster.
2. **B7 besluttet:** helpostens tekstform deklareres pr. udgave i profilen (`raw` for 1939,
   `folded_projection` med projektionsregel og version for 2018-20). Basen håndhæver nøjagtige offsets for `raw`.
   Sammenligning på tværs af udgaver går kun gennem `narrative_norm_v1`, og ingen tekst genskrives. *Lukker*
   2026-10-27 pkt. 7 (B7).

## NOTERET: review-budget for delspec 6a overskredet med én Fable-læsning (2026-10-29)

> B13-overskridelse. Projektejeren bad om reviews og gav ja til Fable 2026-10-29. Fable læste delspec 6a
> (`2026-10-29-trin6a-klausuler-og-kildetekst-revision-design.md`) adversarialt før planen: GO med rettelser,
> 12 fund (heriblandt 7 familiebindinger, som drifttjekket ikke dækkede). Budgettet for resten af 6a er uændret.

## BESLUTTET: 5c-2 + B11's efterkontrol rettes uden ny DDL (vej A); set-baseret bindingstjek i trin 6 (vej B) (2026-10-29)

> Projektejerens valg 2026-10-29. Runbook: `docs/runbooks/5c2-b11-prod.md`; tilstand: `database-current-state.md` §16.

**Baggrund:** Blokken blev committet i prod, men målingen efter stoppede på prods `statement_timeout` (2 min) i
`assertion_binding_current`: hvert bindingstjek læser `private.interpretation_current` (~130 ms pr. kald i prod mod
~3 ms på stand-in'en). Læsernes kald holdt (koordinater 0,7 s; fakta for én person typisk under 1 s), men hele
målingen tog ~3 min og RPC-gatens bidder på 500 personer over 80 s.

**Besluttet:**
1. **Vej A nu:** målingen hæver grænsen lokalt i sin læse-kun transaktion (`SET LOCAL statement_timeout = '10min'`),
   og RPC-gaten kalder fakta én person ad gangen, som læseren (PR #278 og docs-opfølgningen). Ingen ny DDL og ingen
   tilbagerulning: projektet har ingen offentlige læsere endnu.
2. **Vej B i trin 6:** bindingstjekket gøres set-baseret, så fakta-RPC'en ikke læser `interpretation_current` én gang
   pr. binding. Det haster med trin 6's bindinger: i dag koster de tungeste personer op til ~1,9 s mod anon-rollens
   grænse på 3 s.
3. **Kontrolleret afbrydelse (B13):** grund: efterkontrollen timede ud i prod; slut: maal + diff og gaten grønne
   2026-10-29; retur: trin 6-spec'en.

## BESLUTTET: A6b afgrænses til narrativerne; kildetekst og klausuler følger i trin 6 (2026-10-28)

> Projektejerens valg 2026-10-28 (»smal nu, resten i trin 6«). Afgrænser opfølgningen i posten 2026-10-27 om de 13
> `NOISE_RE`-linjer (punkt 3). Plan: `docs/superpowers/plans/2026-10-28-a6b-noise-re-narrativer.md`.

**Baggrund:** Posten 2026-10-27 forudsatte, at narrativer *og* klausuler kunne rettes ad »den normale
tekstrettelsesvej«. Kortlægningen og en læse-kun måling på en genskabt kopi af prod 2026-10-28 viste:
- De 12 prosalinjer ligger i 11 poster (I-9 har to; I-11, I-17, I-18, I-32, I-33, I-44, I-84, I-89, III-37, III-129).
  En positionsbestemt regel (kun første ikke-tomme linje efter `### PAGE`) flytter ingen postgrænser: 591 poster, samme
  nøgler, kun de 11 posters tekst ændres. L22 står før første post og forbliver uden for enhver post.
- 10 af posterne har et publiceret narrativ om en afdød person uden hændelser; teksten er uredigeret siden importen og
  kan revideres med `red_revider_publiceret_person_narrative_record` (en ny `narrative_publication_event` med før- og
  eftertilstand; intet overskrives uden audit).
- Kildeteksten (helpost/occurrence) har ingen skrivevej: `source_observation_text`, anker-version 2 og
  `source_record_revision_event` findes i DDL'en uden writer. `clause_revision` kan ikke tilføje tekst og afviser poster
  med fortolkninger; 9 af posterne har 74 fortolkninger.
- III-129 er ubundet (en af 149b's fire `unresolved_text`). Årsagen er ikke de manglende linjer — de mangler både i
  narrativ og kildetekst — og den er ukendt. Der er ingen rettelsesvej for posten.

**Besluttet:**
1. **Nu (A6b):** `segment.py` får en versioneret støjregel (profil `2018-20-v2`, kun sidehoveder); `2018-20` (v1) er
   frosset, så tidligere manifester kan genbygges. De 10 publicerede narrativer revideres i én ceremoni med dump,
   måling og GO; fortrydelse er samme ceremoni baglæns.
2. **Trin 6:** helpostens kildetekst og klausulerne for de 11 poster får linjerne gennem en kildetekst-revision, der gør
   afhængige fortolkninger forældede. Trin 6 skal alligevel kunne gøre forældet; mekanismen bygges én gang dér.
3. **Kendt følge:** efter A6b er `narrative.tekst` ≠ helpostens `verbatim_text` for de 10 poster, indtil trin 6 retter
   kildeteksten. En genkørsel af 149b's komparator vil vise dem. III-129 røres ikke.
   *Omformuleret efter 6c-3 (i prod 2026-11-08):* revisionen har givet de 10 poster nye tekstversioner med de manglende
   linjer, så helpostens gældende tekst (`helpost_text_current`) følger narrativet (byte-ens med generalprøverne; ikke
   målt særskilt i prod). Narrativ ≠ *forekomstens* `verbatim_text` består som kendt, begrundet følge (forekomsten
   ændres bevidst ikke, 6a R13-b), så 149b's komparator viser fortsat de 10.
4. **Review-budget (B13):** to Codex-runder i stedet for én — planen fik NO-GO i runde 1 (6 fund, rettet), og diffen
   reviewes før prod.

## BESLUTTET: projektets mål slutter med trin 6; skalering er en mulig fortsættelse, ikke et mål (2026-10-28)

> Projektejerens afgørelse 2026-10-28 efter spørgsmålet, om reviewets fund (særligt Fables 2-01 og 2-04) kan
> adresseres, så projektet når i mål.

**Baggrund:** Roadmappet fører fra trin 6 (begge referenceudgaver gennem kæden) til trin 7a/7b og videre mod
foreningens samlede data. Reviewet viste, at de egentlige fejl kan rettes på få dage (trin A og B er gjort), men at
skalering kræver to ting, projektet ikke selv råder over: et opret-ben, som endnu ikke er designet (2-01, B4), og et
behandlingsgrundlag for foreningens data, som kræver en jurist (2-04, B10). Foreningens data er desuden kun relevant,
hvis foreningen vil fortsætte.

**Besluttet:**
1. **Projektets mål er PoC'en for Reventlow:** trin 1-6 med trin 6's færdigbevis (begge referenceudgaver gennem samme
   operationer, læseren ser fakta med kildehenvisning (B11), medlemskab fra to kilder (B6)).
2. **Beslutningspunkt efter trin 6:** projektejeren vurderer, om PoC'en leverer værdi for læser og redaktør, og hvad
   en fortsættelse koster. Udfaldet registreres som en ny post her: stop, fortsæt med 7a, eller forelæg foreningen en
   fortsættelse.
3. **Trin 7a og 7b samt foreningens samlede data er en mulig fortsættelse,** ikke en del af projektets mål. 7b og
   foreningens data forudsætter foreningens accept. Opret-benet (B4) og behandlingsgrundlaget (B10's juristdel) hører
   til fortsættelsen og planlægges ikke før beslutningspunktet.
4. **Konsekvens for prioritering:** arbejde, der kun tjener skalering (opret-benet ud over 1939's 16 `[NY]`-records,
   udgavelogik ud af fælles kode (2-02), GDPR på foreningsniveau), tages ikke ind før beslutningspunktet. Visionens krav om
   at metoden *kan* udvides til nye udgaver står uændret.

## BESLUTTET: de 13 `NOISE_RE`-linjer midt på en side — 12 er prosa, der mangler i 2018-20's tekst (2026-10-27)

> Review-handling A6 (fund 1d.3a-03). Ark og konverter i `work/noise-re-13/` (gitignoreret); ark-sha `5dbc5e20d83c…`,
> dispositioner-sha `2b383d0f6dfd…`. Projektejeren bekræftede de forudfyldte anbefalinger.

**Baggrund:** `segment.py`'s `NOISE_RE` (`von\s+R\s*E.*|Ridder\s+.+sønner`) springer linjer over midt i en post. Af 100
træf i 2018-20's rå tekst står 87 lige efter et sideskift (alle korte, uden komma og tal: sidehoveder), 13 midt på
en side.

**Besluttet:**
1. **12 linjer er prosa** (L190, L210, L294, L427, L440, L619, L627, L795, L1284, L1350, L2606, L3430 i
   `work/raw_full.txt`): de begynder midt i en sætning med »von Reventlow …« og mangler i den publicerede
   `narrative.tekst` for kilde 1 og i klausulerne bygget på den.
2. **L22** (»Ridder … sønner«, side 93) er en overskrift, ikke prosa; den forbliver udeladt.
3. **Opfølgning (gate før trin 6, egen plan og GO):** `NOISE_RE` strammes til sidehovedpositionen (lige efter
   `### PAGE`), ny segmenteringsversion, og de berørte narrativer og klausuler rettes gennem den normale
   tekstrettelsesvej. Det er en ændring af prod-data.

## BESLUTTET: helhedsreview trin 1-5 — 13 beslutninger før trin 6 (B1-B13) (2026-10-27)

> Grundlag: `docs/reviews/2026-10-27-trin-1-5/rapport.md` §5 (fase 3) med fund i samme mappe. Projektejeren sagde ja
> til alle hovedsessionens anbefalinger 2026-10-27. Tekstændringer i vision, roadmap og målarkitektur følger i en
> særskilt rettelse (review-handling A4).

**Baggrund:** Reviewet fandt, at kernen (evidenslaget, writeren, klausullaget) holder, men at overførslen til prod er
dyr, at de gamle loadere aldrig blev lukket, at kæden ikke kan oprette noget nyt (2-01), og at læseren ikke ser
resultatet (1a-03). Beslutningerne nedenfor lukker eller udskyder det, før trin 6 specificeres.

**Besluttet:**
1. **B1 — gate 8 omformuleres:** fortrydelse er enten en særskilt, auditeret handling med eget write-set *eller*
   restore af et dateret dump inden for et deklareret vindue, som lukkes udtrykkeligt. Betingelse (2-06): hvert
   restorepunkt findes i to kopier (én uden for maskinen), hashen noteres i `database-current-state.md`, og »dump
   findes og hash passer« er første skridt i enhver ceremoni. Dumpet indeholder levende personer (invariant 8):
   kopien uden for maskinen skal være **krypteret** og ligge et sted, projektejeren selv kontrollerer (fx et krypteret
   eksternt drev) — aldrig ukrypteret hos en skytjeneste. **Valgt 2026-10-27:** projektejerens SFTP-server hos en
   udbyder. Dumpet krypteres lokalt med `age` før upload (`<dump>.age`); den hemmelige nøgle ligger kun hos
   projektejeren (adgangskodemanager / `~/.private/`), aldrig på serveren, så udbyderen kun ser krypterede bytes.
   Serverens adresse og login ligger i `~/.private/`, ikke i repoet. Hashen noteres for både dumpet og `.age`-filen;
   ceremoniens første skridt tjekker den lokale kopi og den eksterne fils størrelse og hash. Én prøvegendannelse
   (hent, dekryptér, `pg_restore --list`) udføres, før reglen bruges første gang. Scriptet bygges med trin B's
   ceremoni. *Formaliserer* restore-only-posterne 2026-09-17,
   2026-09-23 og deres efterfølgere (1a-04: ni steder).
2. **B2 — genspilspakken droppes som standard:** prod-skrivning sker i 5c-1's form (frisk dump → kørsel mod prod med
   `--jeg-mener-det` → før/efter-måling med nøglede digests). Indholds-id'erne (2026-10-21) beholdes. *Afløser*
   »hele 2018-20 køres i restoren og overføres samlet« (2026-10-01) som mønster for nye trin.
3. **B3 — trin 7 deles:** 7a = ny udgave af samme slægt (identitetsafstemning mod eksisterende bestand); 7b = ny slægt
   fra ingenting. Kandidat-årbog vælges, før trin 7 specificeres.
4. **B4 — opret-benet specificeres før 7b**, med 1939's 16 `[NY]`-records (#160) som første rigtige prøve. *Afløser*
   »promotion er binding, ikke oprettelse« (2026-09-06 pkt. 6) som princip for 7b; for trin 4 gælder det fortsat.
   Rækkefølge: efter trin 6.
5. **B5 — de gamle loadere fryses:** `load_daa.R` er lukket ved kontrakt v2 (porten er frysningen);
   `post_load_fixup.R` og `backfill_slaegtled.R` får samme port og kræver `--jeg-mener-det`. CLAUDE.md og
   `daa-extract/SKILL.md` peger på evidenskæden, ikke loaderen. Genåbning kræver en ny post her. *Afløser* SKILL.md's
   »fremadrettede loader« og lukker kursskiftet i #240-posten (2026-10-26).
6. **B6 — medlemskab fra en anden kilde bliver `corroborated`, ikke `conflict`** (1d.1-07). Specificeres i trin 6.
7. **B7 — `verbatim_text`'s betydning på tværs af udgaver er *ikke* besluttet;** den afgøres i trin 6-spec'en
   (1d.3a-01).
8. **B8 — kontrolmodellens stikprøve er en røgtest:** forsegling, hash-bundet trækning og `-v2`-trækning bortfalder;
   »én fejl stopper« og stikprøvens størrelse består. *Justerer* 2026-09-27; »ingen fulde afgørelsesark« består.
9. **B9 — `schema.sql` bringes i paritet ved håndportering nu** (RED-8: 17 kroppe, 16 tabeller; 1b-01). At generere
   skemaet fra en migreret base (1b-05) er en særskilt beslutning efter trin 6.
10. **B10 — GDPR ved skalering:** udelukkelsen fra modelkald strammes fra »afdød« til »død før (indeværende år − 10)«.
    Behandlingsgrundlaget (2026-09-06 pkt. 5) afklares med en jurist på foreningsniveau, før foreningens data
    behandles. Det standser trin 7, ikke trin 6.
11. **B11 — læserværdi er en del af trin 6's færdigbevis:** fakta med kildehenvisning i persondetaljen (1a-03),
    leveret sammen med 5c-2.
12. **B12 — genbekræftet:** OCR-rettelse er ikke en ny påstand (`docs/superpowers/specs/2026-07-26-person-ocr-kvalitetsark-design.md:38-40`)
    og strider ikke mod visionens »originalen er uforanderlig« (2026-08-25): originalen bevares i
    `import_korrektion` og `change_event`. Ingen ny beslutning; CLAUDE.md's invariant 1 skal nævne undtagelsen (1a-08).
13. **B13 — review-budget og kontrollerede afbrydelser håndhæves:** hver spec har én linje med sit review-budget;
    overskridelse eller en afbrydelse som #240/#248 kræver én linje her (grund, slut, retur). *Håndhæver*
    2026-09-03 og 2026-09-23.

## BESLUTTET: #150 trin 5c-1 — overskrifter som strukturelle forekomster; legacy-ledger; membership gælder kun ved passende tilstand (2026-10-26/27)

> Spec `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md` (Fable-reviewet), plan
> `docs/superpowers/plans/2026-10-26-trin5c-placement-membership.md` (Codex/Opus-reviewet), runbook
> `docs/runbooks/150-placement-prod.md`. Implementeringen Codex-reviewet (r1 NO-GO → Opus-dom: GO efter rettelser).

**Baggrund:** 2018-20's slægt, linje og generation lå kun i `person_external_id`. Placement-skelettet kunne ikke
opfyldes, fordi bogens overskrifter står *mellem* posterne, mens validatoren krævede en header i postens egen
forekomst.

**Besluttet:**
1. **Overskrifter som strukturelle forekomster (sti ii):** hver overskrift i renditionen er en uankret
   `source_record_occurrence` med én observation af kind `header_linje`/`_slaegtled`/`_kuld`/`_aegteskab` i én
   header-kørsel. Validatoren udvides (den gamle sti i bevares til 1939/trin 6); »nærmeste foregående overskrift pr.
   niveau, et højere niveau annullerer de lavere« står i placementens evidence og efterprøves af
   `private.placement_header_violations` (db-verify og ceremoniens POST), ikke af triggeren.
2. **Maskinel accept kun ved enighed og strukturinvarianter** (5 linjer ↔ 5 entries, fortløbende slægtled og nr. —
   et nr-hul er kun tilladt, når et trykt interval »N.-M.« dækker det præcist — og stigende kuld), plus et
   forælder-barn-krydstjek: barn og forælder i samme linje skal stå præcis ét slægtled fra hinanden. Målt:
   543 maskinelt enige, 37 uenige om kuld (legacy arvede kuld over slægtledsgrænser; 6 gruppelinjer i token-filen),
   11 børn i forælderens slægtled (V-82..V-92: mulig umarkeret slægtledsfald eller forkert relation; **står
   uafklaret i 5c-1** og kan ikke godkendes i token-filen — opfølgning).
3. **Blind kontrolstikprøve** K=20 (stratificeret, fast seed): projektejeren skriver selv slægtled og kuld mod PDF'en;
   arket skal være netop stikprøven, og én afvigelse stopper. Udfyldt 2026-10-27 (20/20 efter én rettelse af en
   forvekslet post, II-1). Arket blev aflæst i dialog med agenten, der anvendte reglens definition (kuld = romertal
   alene på en linje; »X's børn med Y:« = ægteskabsoverskrift), så det bekræfter overskrifternes tilknytning, ikke
   definitionen; projektejeren har efterfølgende bekræftet definitionen mod alle 20 poster og fravalgt en ny blind
   stikprøve. Token-filen (6 × J) er projektejerens egen afgørelse.
4. **Legacy-ledger** `private.legacy_placement_disposition`: tilføj-kun, én disposition pr. legacy-række
   (`mapped`/`retained_legacy`/`archived_by_editor`/`unresolved`) med værdi-hash; en senere ændring af legacy gør
   dispositionen forældet. Legacy røres ikke; `backfill_slaegtled.R` fryses for kilder med dispositioner.
5. **Membership gælder kun ved passende tilstand:** promotionen skriver `member` + `agnatic` med `source_basis` =
   tilstanden (placements, identitetsversion, regelversion) og dens sha; en senere identitets- eller
   placement-rettelse gør den ikke-gældende uden yderligere vagt, og db-verify tæller ikke-gældende som NOTICE.
   5c-2's læsere skal filtrere på gældende. Gifte-ind får aldrig membership; poster uden hovedperson-persona får
   record-placement, men ingen membership.
6. **Revalidering i samme transaktion** af hver publicering, der bliver `stale_published` (målt 498 af 541; de
   publicerede poster, der står uafklaret, ændrer ikke tilstand og kan ikke revalideres) — projektejerens afgørelse
   2026-10-27, spec §4.5 rettet. 0 `stale_published` og uændret eligibility er efterbetingelser.
7. **ACL i prod:** Supabase's DEFAULT PRIVILEGES giver `service_role` EXECUTE på nye funktioner; nye `red_*`-RPC'er
   skal også fratage `service_role`. Placement-blokken retter samme drift på #248's `red_genaabn_relation_interpretation`
   (fuld db-verify mod en kopi af prod: `EVIDENCE_PUBLIC_RED_ACL_DRIFT`).
8. **Ceremoniens ydelse:** `ANALYZE` efter hver skrivefase og materialiserede view-joins; uden dem tog øvelsen
   21 min (tomme-tabel-planer), med dem ca. 70 s.

## BESLUTTET: #248 — to navnefælle-ægtefæller rettes; genåbning ved familieskift bygges (rute A) (2026-10-26)

> Issue #248 (kommentar 2026-10-26). Projektejerens svar på to hash-bundne ark: GO 248 `1556cec6…` (F, F) og
> navnefælle-kontrollen `b7ada21b…` (6 × V). Runbook: `docs/runbooks/fix-248-identitet-prod.md`. Ruterne er
> reviewet af en uafhængig Fable-reviewer (GO til A med ændringer).

**Baggrund:** #248's to »N°«-afvigelser er ikke forkerte familienumre. I begge poster har bogen to ægteskaber med
navnefæller (Iwan 3°/4°: to Margaretha von Rantzau; Abel 1°/2°: to Hans von Rantzau), og 2b-i's ægtefælleark
(ark 9 i GO 2, `6ff659f4…`) forudfyldte »S = kandidat nr. 1« og viste kun kandidat 1. Begge ægtefæller blev
derfor afgjort til samme person, og 4°/2° blev bundet til 3°/1°'s familie. Læseren viser kildeteksten på den
forkerte, offentlige familie. Familienumrene er rigtige (projektejerens afgørelse 2026-10-20 holder). Et tjek af
alle 16 accepterede identiteter med en navnefælle blandt kandidaterne fandt ingen flere fejl.

**Besluttet:**
1. **Skridt 1 nu (rute C, ingen DDL):** de to ægtefæller afgøres igen til partneren i den ubundne familie
   (kandidat nr. 2) med `red_afgoer_source_persona` og GO 248's arkkontekst (`fix_248_identitet.sql`). Den gamle
   binding holder op med at gælde, så kildeteksten forsvinder fra den forkerte familie. Ægteskaberne står
   derefter `accepted` uden binding; #248 holdes åben, til de er bundet.
2. **Rute A bygges:** en genåbning af et accepteret ægteskab, når dets nuværende tilstands familie ≠ familien i
   afgørelsen. Den nye version er `proposed`, og den eksisterende afgørelses- og bindingsvej binder den til den
   rigtige familie; den gamle binding bliver historik. Det lukker hullet, som 2b-i-spec'en (§13 pkt. 1) udskød til
   2b-ii, og som 2b-ii ikke leverede. 2b-i-beslutningens punkt 2 præciseres: ingen genbinding til en anden familie
   *uden en ny version*. Egen spec; DDL- og dataceremoni.
3. **Rute B fravalgt** (løsne `RELATION_PROMOTION_REBIND_FAMILY_CHANGED`): den gemte afgørelse ville sige den
   gamle familie, mens bindingen sagde den nye.
4. **Forebyggelse med i A's DDL:** bindingstilstanden skal være fail-closed, når to ægtefællepersonas i samme post
   er afgjort til samme person (maskinvejens `FAMILY_CORROBORATION_DOUBLE_TARGET` har ingen modpart på
   menneskevejen). Identitetsark skal vise, når kandidat nr. 1 allerede er partner i posten, og tunge
   prod-rettelser bruger ikke-forudfyldte ark.
5. **Kendte følger af skridt 1:** to gældende `ordinal_afvigelse` bliver uden binding; kun to rækker i
   `source_persona_identity_event` (målt over alle tabeller i public og private); 0 kanonisk delta. Ingen
   fortryd-vej; dumpet før skrivning er nødudvejen.
6. **Præcisering af punkt 4 for ægtefællearket (spec §3.3, rute A):** arket forudfylder ikke et svar, når kandidat
   nr. 1 også er kandidat nr. 1 eller accepteret identitet for en anden ægtefælle i samme post
   (`post_rivals` > 0 i `spouse_exception_projection`). Linjen får en advarsel og står `?`, og et ark med `?`
   afvises (`SHEET_UNANSWERED`), før der skrives SQL. Ark uden navnefæller er byte-identiske med før. Runbook for
   rute A: `docs/runbooks/248-genaabning-prod.md`.

## BESLUTTET: #240 — de 5 dobbeltfamilier samles; vielsespåstanden flyttes, ikke slettes (2026-10-26)

> Issue #240. Projektejerens valg i chatten (valg A). Runbook: `docs/runbooks/fix-240-dobbeltfamilier-prod.md`.
> Scripts: `.claude/skills/daa-extract/scripts/fix_240_*.sql`. Reviewet af en uafhængig Opus-reviewer før scripts.

**Baggrund:** 5 par står hver i to familier: én med børn og én tom (188/11, 282/256, 354/363, 361/371, 377/372).
Indlæseren oprettede én familie og én vielse pr. ægtefælles post, når posterne henviste til hinanden. Fordi
`relation_binding_state` er fail-closed ved mere end én familie, kunne 7 ægteskaber fra 2018-20 (par 1, 3, 4, 5)
ikke bindes; de stod som `proposed`. Målt på en kopi af prod efter GO 2: den tomme familie har 0 børn, samme
partnere (ordinal 1), kun noter og (par 2-5) ét vielsesfaktum, der peger på den. Intet andet i public/private
henviser til den.

**Besluttet:**
1. **Familien med børn overlever.** Den tomme families noter (indlæserens kildenoter) flyttes til den.
2. **Vielsespåstanden flyttes som endnu et belæg** (valg A). Dato, sted, værdi og kilde er ens, men citatet er
   den anden ægtefælles post, altså et selvstændigt sted i bogen. Påstanden og dens citat flyttes til familiens
   vielsesfaktum; familiens konklusion beholder sin valgte påstand. Kun den tomme families konklusion og det nu
   påstandsløse faktum slettes. Invariant 1 holdes; konventionen »én påstand pr. vielse« er ikke et krav i
   skemaet, og promotion kræver kun ét vielsesfaktum pr. familie. Fravalgt: at slette påstanden som dublet.
3. **Ægteskaberne afgøres maskinelt bagefter**, med samme RPC'er som GO 2's decide- og bind-skridt
   (`red_decide_relation_interpretations`, `red_promote_relation_interpretations_batch`), og kun når
   beslutnings- og promotionsmængden er netop de 7 i den samlede familie. Webfladen afgør ikke ægteskaber.
4. **Kendt følge: 2018-20's kontrolkørsel beregnes nu som `failed` (`kandidatinput_aendret`).** Den er brugt op:
   korroborationen af de 174 identiteter skete i GO 2, hændelserne står `sealed → passed`, og kun
   `red_evaluate_identity_control_run` og `red_corroborate_family_identities` læser den beregnede status (ingen
   af dem kaldes fra web, og der er intet tilbage at korroborere). Afgørelser læser kun forseglingen. En fremtidig
   evaluering vil skrive `failed`; det er forventet og ikke en fejl.
5. **Fortryd** (`red_fortryd_change_set`) er byte-trofast, men kun indtil ægteskaberne er afgjort; bagefter ville
   den genskabe en anden familie under 7 accepterede tolkninger.
6. **Synlighed:** par 2's familie med børn er ikke offentlig (et medlem er ikke offentligt), mens den tomme var.
   Efter sammenlægningen ser anonyme læsere ikke længere parrets vielse og noter. Strammere, i tråd med
   invariant 8.
7. **Prod:** én session i projektejerens shell (`18-fix-240.sh`): måling → dump → dubletreglens DDL (#260) →
   måling → sammenlægning → ægteskaber → måling. Før 1939's kandidatkørsel registreres, så 1939 ser én familie
   pr. par. Grundårsagen i indlæseren rettes ikke nu (`load_daa.R` er historisk; genimport går gennem
   evidenskæden), men en genindlæsning med den gamle indlæser ville genskabe dobbeltfamilierne.

## BESLUTTET: #151 — dubletreglen: familiens post vinder, uafklarede dubletter venter på redaktøren (2026-10-25)

> Retter punkt 6 i GO 2-beslutningen nedenfor. Spec 5b §23.4 (rettelse samme dato). Projektejerens valg i chatten.

**Baggrund:** Et dubletsvar på kontrolarket (`1=3`: »de to personposter er samme individ, og ægtefællen er
ham/hende«) bandt identiteten til den laveste visningsplads. Pladserne blandes pr. stikprøve, så udfaldet var
tilfældigt; i GO 2 blev ét ægteskab derfor stående som forslag (252 bindinger, ikke 253). 1939 har langt flere
navnefæller.

**Besluttet:**
1. **Den post, der står i familien, vinder:** bindes til den dubletpost, der står som partner i en familie med
   hovedpersonen (`persona_family_context`). Det er netop den post, ægteskabet kan bindes til. Punkt 6's »bedst
   rangerede« er kun reserven.
2. **Ingen eller flere i familien ⇒ sag til redaktøren:** identiteten bindes til den bedst rangerede kandidat
   (uafhængig af visningspladsen), evidensen får `duplicate_binding = 'rank'` og `duplicate_family_matches`, og
   `relation_binding_state` binder ikke ægteskabet maskinelt. Redaktøren afgør identiteten igen i den eksisterende
   identitetskø (filter `duplicate_unresolved`, årsag »dublet uafklaret«); den nye evidens frigiver bindingen.
   Ingen ny webflade. Reserven vælger aldrig hovedpersonen selv; `duplicate_family_matches` er `null`, når
   familiekonteksten mangler (hovedpersonen er ikke afgjort).
3. **Kontrolkørslen holder:** status læser arkets afgørelse som hændelsen for den samplede version + 1. »Den seneste
   status er autoritativ« (5b §7.2) gælder fortsat, med én undtagelse: en senere accepteret afgørelse, der peger på
   en af de poster, mennesket selv nævnte som samme individ, er en afklaring af dubletten, ikke en ændret
   stikprøveafgørelse, og vælter ikke kørslen. En afgørelse uden for dubletmængden giver stadig `failed`.
4. **Rækkefølgen på arket er uden betydning** (`1=3` = `3=1`; arkværktøjet sorterer allerede).
5. **Fravalgt:** at fjerne `1=2`-svaret (et korrekt svar på navnefællen ville igen tælle som afvigelse), at lade
   rækkefølgen bære valget (fejlbart i en tekstfil), et nyt webvalg (sideprojekt) og en regel om »samme udgave«
   (personposter har ingen udgave; reglen ville fastholde udgavelokale dubletter og afgør ikke dubletter inden
   for én udgave).
6. **Prod:** kun DDL (`red_afgoer_source_persona`, `control_run_status`, `relation_binding_state`,
   `red_source_persona_queue`) og webkøens filter; eksisterende afgørelser er uændrede. Deployes efter GO 2's
   `VERIFY_OK` (2026-10-25) i en DDL-ceremoni før 1939; GO 2-pakken er optaget mod de gamle funktioner. Det ene ægteskab fra 2018-20 afgøres separat.
   *Tillæg 2026-10-26:* DDL'en kom i prod med #240 (PR #261). Ægteskabet rettes med `fix_go2_dublet.sql`:
   ægtefællen afgøres igen til familiens post 753 (kandidat nr. 1 i dubletmængden `731=753`), som den nye regel
   ville have valgt; derefter afgøres og bindes ægteskabet til familie 202 (runbook `fix-240-dobbeltfamilier-prod.md`).

## BESLUTTET: #151 — data-ceremonien (GO 2): godkendelsespolitik, 252 bindinger, dubletreglen til rettelse (2026-10-25)

> Plan B2: `docs/superpowers/plans/2026-10-23-trin5ab-overfoersel-b2-ceremoni.md` (Task 5-7). Runbook:
> `docs/runbooks/transfer-5ab-data-prod.md`. Spec: `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md`
> (§3 beslutning 4 og 8, §6.3, §11). Punkt 1 og 5 er projektejerens beslutninger 2026-10-23 og 2026-10-25.

**Baggrund:** Arbejdskørsel 3 (commit `1edb762b`, #257) er pakken, prod genspiller (`PACK_OK`, `pack_sha256`
`46f5d1e5…`; genspilsprøven `REHEARSAL_OK`). Indholdskontrollen mod beviskæden fandt 42 uventede forskelle,
som projektejeren har afgjort.

**Besluttet:**
1. **Godkendelsespolitikken:** runneren godkender selv et overført ark, kun når overførslen giver `aendret=0`,
   hvert bortfald står på arkets egen bortfaldsliste, og arket hverken er kontrolarket eller v3-ægteskabsarket.
   Alt andet venter på projektejeren; en ny linje uden gammelt svar kræver altid et frisk svar. Alle
   overførselsrapporter læses samlet før GO 2 og bindes i GO 2. Udfald: fem ark godkendt af projektejeren
   (kontrol, 2b-i, kø, v2, v3), børnearket automatisk; kontrol-, 2b-i-, kø- og v2-arket er byte-ens med
   arbejdskørsel 2's.
2. **Kandidatkørsel 1 (top-k 3) og dens kontrolkørsel genskabes ikke (H3);** de står som forventede bortfald.
3. **#244 opstod aldrig i prod** (spec beslutning 4). Arbejdskørslen regenererede persona-manifesterne med rigtige
   ægteskabsnumre; prod har aldrig haft de 4 fejlnumre. Rettelsesvejen (`red_ret_aegteskabsnummer`) er deployet,
   men ubrugt, og genbindingen med `supersedes` er ikke øvet i prod. Svaroverførslen sammenligner derfor
   ægteskabsarkenes `S` med den person, svaret bandt i bevisbasen, ikke med et genberegnet gammelt forslag (#257).
4. **Aktørforskellen:** 2a's bevisbase havde en ekstra redaktørprofil, der traf 2a's afgørelser og ikke findes i
   de senere baser. I prod er aktøren prods ene redaktørprofil for alle skridt; det er en forventet forskel, som
   indholdsprojektionen ikke ser.
5. **252 bindinger, ikke 253 (afgørelse A).** Kontrolarket bruger en ny stikprøve og blander kandidaternes
   visningspladser. Spec 5b §23.4's dubletregel binder et svar som `1=3` (to personposter er samme individ) til
   den **laveste visningsplads**. På ét kort stod i beviskæden den personpost øverst, som familien bruger; i
   arbejdskørslen den anden. Ægtefællen bindes derfor til den anden post, og ægteskabet bliver stående som
   forslag uden binding og kildehenvisning, til dubletten slås sammen. Desuden skifter 38 identiteter oprindelse
   mellem kontrolark og familieopslag, fordi stikprøven er ny (19 hver vej; samme personer). Begge dele står som
   forventede forskelle. Fravalgt: at rette reglen før GO 2 (ny DDL-ceremoni og ny arbejdskørsel for ét
   ægteskab) og at ændre det blinde kontrolsvar efter udfaldet.
6. **Dubletreglen rettes før 1939 (åben backlog, DDL):** en dublet skal binde til den bedst rangerede kandidat i
   dubletmængden, uafhængigt af den blandede visningsplads. Det er latent i 2018-20 (ét tilfælde), men 1939 har
   langt flere navnefæller.
7. **Modenhed (spec beslutning 8):** efter `VERIFY_OK` er 5a og 5b's personas, identiteter, bindinger,
   børnehenvisninger, dispositioner, klassifikationer og P-afvisningen for 2018-20 `produktionsverificeret`.
   Oprettelse af nye kanoniske personer (0 i hele kæden) og #244's rettelsesvej forbliver `isoleret
   implementeret`.
8. **Udgavenavne (spec §11):** ingen nye i permanente overflader. Kædefilen er privat, og
   `transfer_5ab_content.sql` tager kilden som argument.

## BESLUTTET: #151 — plan B delt i værktøj (B1) og ceremoni (B2); data-ceremoniens errata (2026-10-22)

> Plan B1: `docs/superpowers/plans/2026-10-22-trin5ab-overfoersel-b1-vaerktoej.md` (to Opus-review-runder, GO med
> rettelser). Spec: `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§6.2, §6.3, §7-§10).
> Punkt 6 er projektejerens beslutning 2026-10-22.

**Baggrund:** Data-ceremonien (GO 2) genspiller beviskæden på en restore af D1 og derefter i prod. Beviskædens
skridt fandtes delvis kun som private scripts, og dens hashes indeholder basens identitet og tilfældige versions-id'er,
så de kan ikke sammenlignes mellem baser.

**Besluttet:**
1. **Plan B deles:** B1 er repo-værktøj med CI-tests; B2 er den private ceremoni (runner, arbejdskørsel, genspilsprøve
   på D1, GO 2). B2's tests kan ikke køre i CI.
2. **Nøglede digests:** hver uuid i en hashet række oversættes via et nøglekort til en nøgle af indholdet; en uuid,
   kortet ikke kender, bliver stående og tælles (`n_uuid_unmapped`), så en forskel aldrig skjules af en pladsholder.
   Base-bundne evidensnøgler (`set_sha256`, `preview_sha256`, `batch_id`, `manifest_sha256` m.fl.) udelades.
3. **Beviskædens private skridt får repo-versioner med test** (profil, afgør, bind, disposition, afvisning,
   kandidater, kontrol, korroboration). Items nøgles i pakken; hashes genberegnes altid i basen.
4. **Errata til spec'en:** autorisationernes manifest-hash sammenlignes kun for `relation_persona` (dispositionernes
   manifest bærer tilfældige versions-id'er); writer-profilen indsættes som sit eget skridt før første writer;
   kontrol af alle skridts tilstand bagefter er ikke mulig, fordi lagene overlapper (`decide` og `reject` skriver begge
   fortolkninger), så runneren klassificerer kun det næste skridt.
5. **Aktøren angives eksplicit** i hvert skridt og skal være en navngiven redaktørprofil; skridtene vælger den aldrig
   selv. Hver afgørelse bærer aktørens navn permanent (D1 har én redaktørprofil, målt 2026-10-22).
6. **Kandidatkørsel 1 (top-k 3) genskabes ikke** (projektejeren); den står som forventet bortfald i §6.3-listen.
   Køens note bærer arkets hash, så en ny kø giver ny note og dermed et nyt v3-ark (forventet kaskade).

## BESLUTTET: #151 — 5a's kalibreringsafgørelser overføres ikke; DDL-ceremoniens errata (2026-10-21)

> **Besluttet af projektejeren 2026-10-21** under planlægningen af overførslen (plan A:
> `docs/superpowers/plans/2026-10-21-trin5ab-overfoersel-a-ddl.md`; spec
> `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md`).

**Baggrund:** 5a ligger ikke i beviskæden. 5b del 1's bevisbase er en kopi af roden, ikke af 5a's base, og
5a's bevisbase blev droppet 2026-10-17. 5a's 31 afgørelser var en blind genbekræftelse af eksisterende
149b-koblinger (24 bekræftet med kandidat 1, 6 sat til uafklaret, 1 via webkøen). De findes kun i en privat
mappe uden for Git, som bevares. De 6 uafklarede berører ingen relationer eller bindinger.

**Besluttet:**
1. **De 31 afgørelser overføres ikke.** Prod beholder alle 587 149b-koblinger. 5a's kode deployes; identitetsvejen
   bevises i prod af 5b's egne afgørelser, der går gennem samme `decide_source_persona_identity`. Kun webkøens
   `web_detail`-spor er ubrugt i prod.
2. **Errata til spec'en** (plan A's tabel): prods DDL-træ er `b42266e` (2026-09-28), ikke `140a17b`; del 1's og 2a's
   bevisbaser er omdøbt tilbage fra karantæne og er input til plan B; dumps er 0600 på krypteret disk som tidligere
   ceremonier; fingeraftryk har en portabel og en prod-lokal del; DDL'en skriver tre promotion-regler og to nye
   felter (tilladt datadelta), så plan B måler »kanonisk delta 0« mod D1, ikke mod rodbasen.
3. **db-verify i rehearsal** køres i en kopi uden de emulerede default privileges: dens egen probe forudsætter lukkede
   defaults, mens prod giver `anon` adgang til nye `public`-funktioner. Vinduet måles i stedet direkte og lukkes af
   migrationernes eksplicitte `REVOKE`; et afbrudt `04` køres igen straks eller fortrydes (runbook §5). Kopien
   beviser ikke lukkethed for funktioner uden for `red_%`; det gør upgrade-testens `anon_exec_public` (finalreview).
4. **Fortrydelsen fjerner DDL-rollens skema-defaults under restoren** og genskaber dem fra preflightens linjer
   (finalreview): ellers åbnede restoren alt i `public` for `anon`/`authenticated`/`service_role` (511 grants), til
   grant-afstemningen lukkede dem. Den lokale del sammenlignes derfor for DDL-rollens skema-defaults mod
   preflighten, ikke mod tilstanden ved fortrydelsens start (et afbrud + genkørsel må ikke bage den tomme tilstand ind).
5. **Fortrydelsen sletter ikke data lydløst** (privat review): ændrer tabellerne sig siden D0 ud over DDL'ens tilladte
   delta, stopper `09` (`UNDO_DATA_LOSS`); projektejeren kan acceptere tabet, bundet til netop det målte deltas hash.
   `09`'s linjefiler er hash-bundne før brug, og en DDL kan ikke køres igen i en pause, hvor den er fortrudt.

## BESLUTTET: #151 — id'er af indholdet; forudsætning for 5a+5b-overførslen (2026-10-21)

> **Besluttet af projektejeren 2026-10-21** i brainstormen og ved godkendelsen af spec'en.
> - Spec: `docs/superpowers/specs/2026-10-21-trin5ab-indholds-id-design.md`.
> - Overordnet: `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§4).

**Besluttet:**
1. **Serveren afleder id'et selv** (tilgang A) med `private.content_uuid(kind, naturlig nøgle)`. Fravalgt: klientleverede id'er i manifestet (B), fordi serveren så skulle stole på klienten, og payloads og signaturer skulle ændres.
2. **8 rækkearter:** ægtefællepersona, omtale, identitetshændelse, kandidatkørsel, kandidat, kontrolkørsel, stikprøve og forældrekort. De øvrige tilfældige id'er bliver og verificeres pr. nøgle i overførslen.
3. **Trækning `-v2`:** stikprøve og kortvisning trækkes efter (input, config, persona_key[, kandidatperson]) i stedet for tilfældige id'er; garantierne i 5b §23.3 er uændrede.
4. **Ark-SQL uden tilfældige id'er:** 2b-i's `O`-linjer slår den gældende afgørelsesversion op ved kørsel.

**Kendt begrænsning (fundet ved implementeringen, accepteret af projektejeren 2026-10-21):** trækningen kan beregnes på forhånd for enhver config, så en redaktør kunne vælge en config med en gunstig stikprøve. Den gamle trækning kunne også fornyes med en ny config, og kontrollen er en advarselslampe mod maskinfejl, ikke et værn mod redaktøren.

**Note til overførslens plan:** klassifikationshændelsers evidensfelt `decision_interpretation_id` føjes til listen over udeladte felter i overførsels-spec'ens §7 (spec §4 pkt. 6). Rettelsen hører til overførslens gren.

## BESLUTTET: #244 — ægteskabsnummeret efter skriverens vindue; 4 numre rettet på ark; afløser pkt. 4's »genafgør« (2026-10-20)

> **Besluttet af projektejeren 2026-10-20** i brainstormen af #244 og ved gennemgangen af spec og ark.
> - Spec: `docs/superpowers/specs/2026-10-20-244-aegteskabsnumre-design.md`.
> - Rapport: `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md`.

**Besluttet:**
1. **Roden rettes i funktionen.** `private.relation_marriage_ordinals` nummererer efter det eneste minimale ordnede ordvindue, som skriveren allerede bruger. Er vinduet ikke entydigt, er positionen NULL som før.
2. **Værn mod bogens eget nummer.** Skriveren afviser en ægtefællepart, hvis bogens »g. N°« modsiger systemets nummer. Udtrækket giver `U nummer_modsiger_bog`.
3. **De 4 skæve numre rettes på et lille hash-bundet ark** (4 linjer, `B`/`U`), ikke med en automatisk regel. Rettelsen er en ny partversion (`origin='ordinal_correction'`) med en rettelsesrække som kilde. Fortolkningen røres ikke, og der skrives ingen nye klassifikationshændelser.
4. **Genbinding via 2b-i-vejen** i samme familie (`supersedes_promotion_id`). Det **afløser** 2026-10-18/20 pkt. 4's »genafgør de 2 ældre bindinger«: intet genafgøres, kun nummeret rettes.
5. **Prod-genspil skal løses udtrykkeligt i overførsels-spec'en.** De autoriserede `relation_persona`-payloads bærer det gamle nummer og afvises med `SPAN_INVALID` af den rettede funktion. Overførsels-spec'en skal vælge mellem ny autorisation af de berørte batches eller genspil med den gamle funktion efterfulgt af rettelse og genbinding, bevise valget i restore og håndtere synlighedshullet mellem rettelse og genbinding.

**Uændret:** restore-only. Familiernes numre (`family_member.ordinal`) røres ikke.

## BESLUTTET: trin 5b 2b-iii — børnehenvisningerne binder flokken til familien; ét ark for alle; drift via reglen (2026-10-20)

> **Besluttet af projektejeren 2026-10-20** i brainstormen af 2b-iii og ved gennemgangen af spec og ark.
> - Spec: `docs/superpowers/specs/2026-10-20-trin5b-2b-iii-boernehenvisninger-design.md`.
> - Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md`.

**Besluttet:**
1. **Målet er kildehenvisning, ikke oprydning.** De 14 `relation.child` er krydshenvisninger til hele børneflokke. Det er et erratum til hovedspecen §22.9, der antog ét barn pr. påstand. Alle børn sad allerede i familien, så 2b-iii skaber ingen nye slægtskaber.
2. **Flokken binder til forælderens familie (tilgang A).** Der oprettes ingen barn-part, og der indføres ingen ny påstandstype.
3. **Reglen `relation-child-v1`** består af krav og afvigelser:
   - **Krav (kan ikke tilsidesættes):** hovedperson og post, én familie med børn, køn, postnumre i forælderens linje, romertal = linje eller kuld, og slægtled.
   - **Afvigelser (kan tilsidesættes af mennesket):** antal, »(?)« og manglende henvisning.

   Køn blokerer.
4. **Ét hash-bundet ark for alle, der opfylder kravene.** Der er ingen særskilt maskinel vej. `U` lader påstanden stå, fordi en afgjort fortolkning ikke kan genåbnes.
5. **Drift håndteres via reglen, ikke via et øjebliksbillede.** Bindingen genberegner kravene mod familien, som den ser ud nu. En ændring, der stadig passer med bogen, kan genbindes uden ny afgørelse.

**Uændret:** restore-only. Én påstand bundet til flere familier er udskudt.

## BESLUTTET: `mention.place` udsættes; aldersregel v2 designet, men ubrugt; strammere partnertræf i navneregel v3; falske ordinal-afvigelser bindes og noteres (2026-10-18/20)

> **Besluttet af projektejeren.**
> - **18/10:** i brainstormen af 2b-ii runde 2 (spec §17.3).
> - **20/10:** valget om ordinal-afvigelserne efter rundens slutreview.
>
> Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md`.

**Besluttet:**
1. **`mention.place` udsættes.** 246 klausuler (spec §17.3) stod i `afventer_identitet`, fordi et sted-aktørforslag mangler en persona. Ingen af rundens 12 ægteskaber afhang af det. Det tages op sammen med stedsentiteterne, ikke i 2b-ii.
2. **Aldersregel v2 er designet, men ikke brugt.** Den udelader årstal inde i en DAA-henvisning. Ingen af de 12 havde nul partnertræf og et årstal efter »DAA«, der ville have vendt sagen. Derfor er `aarstal-120-v1` og `red_afgoer_source_persona` uændrede.
3. **Partnertræf i navneregel v3 (slutreviewets fund F2; indført af sessionen efter slutreviewet, projektejeren bekræfter ved merge).**
   - **`S`** kræver efternavnet plus mindst ét fælles kerneord mere. Efternavnet alene giver ikke `S`.
   - **`D`/`N` og P-linjen** kræver 0 *løse* træf. Et løst træf er v2's halvdelsregel eller blot ét fælles kerneord. Ved en `navn:`-rettelse gælder kravet både regelens navn og det rettede navn.

   Det løse værn er bevidst groft. Det skal fange en mulig dublet, før en ny person oprettes. Prisen er flere `U`, og dem afgør et menneske.
4. **Falske ordinal-afvigelser bindes og noteres** (2026-10-20). Når en påstands tekst rækker ud over klausulen, nummererer `private.relation_marriage_ordinals` forkert. Det gælder 2 poster og 4 påstande i 2018-20.
   - De 2 ægteskaber i runde 2 er bundet trods fejlen, fordi partneren er rigtig og bekræftet.
   - Alle 4 falske `ordinal_afvigelse` skal besvares »behold familiens nummer«.
   - Rodfejlen rettes i en separat runde, der også genafgør de 2 ældre bindinger.

   > Rettet 2026-10-20 (#244): årsagen er en parentes midt i klausulen, ikke en overskreden klausulgrænse; se aegteskabsnumre-244-bevis.md. »Genafgør« er afløst af rettelse og genbinding (se #244-posten øverst).

**Uændret:** restore-only. P-linjens forkerte ægteskabsfortolkning er afvist med `red_decide_interpretation` i bevisbasen (2026-10-20).

## BESLUTTET: trin 5b 2b-ii — nye personer kun som afdøde efter aldersregel; disposition pr. aktør; børnene til 2b-iii (2026-10-17)

> **Besluttet af projektejeren 2026-10-17** i brainstormen af 2b-ii, efter råd fra en uafhængig rådgiver (fable)
> om synlighed. Spec: `docs/superpowers/specs/2026-10-17-trin5b-2b-ii-nye-personer-og-disposition-design.md`.
> Bygger på posten 2026-10-12 nedenfor.

**Besluttet:**
1. **Omfang:** 2b-ii = `family.id` som identity, vejen til nye personer (`relation_person_create`), de 14
   ægteskaber uden ægtefælle-persona (deterministisk andet gennemløb og et privat ark; ingen model læser
   teksten) og klausul-dispositionen. De 14 børnepåstande flyttes til en egen skive, **2b-iii**.
2. **Nye personer oprettes kun som afdøde.** Arkets token `D` kræver, at alle årstal i klausulen er ≤ 1906
   (2026 − 120; skærpet samme dag fra »gift senest 1921«, fordi hvert årstal kan være et fødselsår, spec errata §15.5):
   ægtefællen er da mindst 120 år, samme grænse som feedets nødbremse. Projektejeren bekræfter hver linje. Det giver
   `levende = false` med grundlaget i kvitteringen. En ny person, der ikke kan erklæres afdød (`N`), oprettes
   ikke. Den venter, til ægtefællens dødsforslag kan knyttes til personaen. **Det ændrer posten 2026-10-06
   pkt. 3** (»`levende = true`, indtil dødsfakta afgøres af et menneske«). Grunden: en levende ny person ville
   være skjult, og den ville også skjule hele sin familie for læserne (`family_offentlig`).
3. **Klausul-disposition pr. aktør.** En klausul går fra `afventer_identitet` til `fortolkning_foreslaaet`,
   når hver aktør ud over hovedpersonen har en persona med afgjort identitet. Om forslagene er afgjort, er
   uden betydning. Aktørforslag uden persona blokerer. Det erstatter hovedspecens krav om, at alle citerende
   påstande skal være afgjort, som kun ville have frigjort 16 af 390.

**Uændret:** restore-only. Nye personer er `staged`, indtil prod-overførslen aktiverer dem.

## BESLUTTET: trin 5b 2b deles i 2b-i og 2b-ii; genbinding som ny binding ved siden af den gamle; review-fund afvejes mod opgaven (2026-10-12)

> **Besluttet af projektejeren 2026-10-11/12** i brainstormen af 2b og efter spec-reviewet. Spec:
> `docs/superpowers/specs/2026-10-11-trin5b-2b-i-genbinding-og-aegtefaeller-design.md`. Bygger på posten
> 2026-10-11 nedenfor.

**Besluttet:**
1. **2b deles:** 2b-i = genbinding efter rettelse, de 3 ordinal-afvigelser og de 31 uafgjorte ægtefæller
   (22 i et undtagelsesark, 9 i webkøen med partnerkontekst); 2b-ii = nye personer og klausul-dispositionen.
2. **Genbinding er en ny binding ved siden af den gamle** (append-only), unik pr. fortolkning og tilstand;
   ingen genbinding, hvis strukturen er flyttet til en anden familie. Tabellens generelle unikhedsregel bliver
   partiel for ikke-familiemål.
3. **Arket følger del 1's mekanik** (udtræk + psql-script i én transaktion): ingen nye RPC'er eller tabeller.
   `F` (behold familiens nummer) skrives som klassifikationshændelsen `ordinal_beholdt`.
4. **Review-fund afvejes mod opgaven.** Fire Codex-runder voksede spec'en fra ca. 290 til 539 linjer; Opus
   afvejede fundene (nødvendig / forenkl / kendt begrænsning / afvis), og otte teoretiske risici ved denne
   skala står som kendte begrænsninger, som overførsels-spec'en skal tage stilling til før prod.

**Uændret:** restore-only fortrydelse; prod først efter 5a's ceremoni og gennem en overførsels-spec.

## BESLUTTET: trin 5b del 2 i tre skiver; 2a binder det afgjorte og viser kilden for læseren (2026-10-11)

> **Besluttet af projektejeren 2026-10-11** i brainstormen af del 2. Spec:
> `docs/superpowers/specs/2026-10-11-trin5b-2a-binding-design.md`. Bygger på posterne 2026-10-06 og
> 2026-10-10 nedenfor.

**Baggrund.** Del 2 rummer fire forskellige slags arbejde: binding af det afgjorte, menneskelig
behandling af uoverensstemmelser og nye personer, børn med eget kortdesign samt to særsager. Samlet ville
det blive én stor spec og én stor plan, og læseren ville først se noget, når det hele var færdigt.

**Besluttet:**
1. **Del 2 skæres i tre skiver:** 2a binder de 203 ægteskaber med afgjorte parter og de 7 accepterede
   forældre; 2b tager de uafklarede (31 uoverensstemmelser, nye personer, »(F.: …)«-fejllæsningen, klausul-dispositionen, M1-M3
   og M5-M10); 2c tager børnene.
2. **Læseren skal se kilden.** 2a tilføjer en offentlig læsefunktion `public_family_sources`, så web viser
   »Kilde: DAA 2018-20 · ‹post›« ved et ægteskab og en forældrelinje. Kilden tages fra bindingen og den
   publicerede post, ikke fra loaderens vielse-citation (som mangler side og ikke findes for 24 familier).
3. **Bind trods ordinal-afvigelse.** Afviger bogens ægteskabsnummer fra familiens, men har hovedpersonen
   kun én familie, bindes ægteskabet og klassificeres `ordinal_afvigelse` til 2b (3 påstande, hver hos en hovedperson med kun én familie).
   Identitetskernen gør det samme (final review M9).
4. **Forældrene bindes i 2a,** fordi de allerede er afgjort af projektejeren i del 1.

**Parkeret** (kræver hver sin beslutning): familiekorrektion for `F`-kortet og `samme_som` for dubletten.
**Uændret:** restore-only fortrydelse; prod først efter 5a's ceremoni og gennem en overførsels-spec.

## BESLUTTET: trin 5b — menneskets kontrol omdesignet til korte, besvarlige kort; børn og uoverensstemmelser til del 2 (2026-10-10)

> **Besluttet af projektejeren 2026-10-10** efter design-review (Claude + Codex `gpt-5.6-sol`) af det
> første kontrolark og et Opus-review af spec-teksten. Spec: `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md` §22.9
> og §23. Ændrer betydningen af punkt 2 i posten fra 2026-10-06 nedenfor.

**Baggrund.** Det første kontrolark (63 linjer) kunne ikke besvares: det viste hverken hvem
hovedpersonen er, hvad bogen skriver, eller forældrelinjens anden forælder, og alle linjer skulle udfyldes,
også uoverensstemmelser uden for målingen. For børn pegede »familievalget« på flere børn i samme familie.
Et »bestået« kunne dermed bygge på gæt og autorisere 181 maskinelle afgørelser.

**Besluttet:**
1. **Børn (`relation.child`) tages ud af del 1** og får deres eget design i del 2 (kandidaten er barnet).
2. **Arket rummer kun de kort, der skal afgøres:** blinde ægtefællekort (alle navnefæller + `K`
   tilfældige) med hovedperson, bogens ordrette sætning og kandidaternes leveår, titler, forældre og egen
   post — men uden score eller maskinens svar — og forældrekort som udsagn (A/R/F/U). Tidsmæssigt umulige
   kandidater vises ikke; er rang 1 selv umulig, udelukkes personaen fra den maskinelle bekræftelse.
3. **Ægtefællekontrollen er en advarselslampe, ikke en statistisk validering.** 0 afvigelser tillader
   maskinel bekræftelse; én afvigelse stopper den, og en ny kontrolkørsel kræver en dokumenteret
   årsagsrettelse. Rapporten angiver den øvre fejlgrænse, beregnet alene af de tilfældige kort.
4. **Forældrene afgøres af mennesket** og hverken autoriserer eller blokerer ægtefællernes identitet;
   `F` (familien i basen passer ikke) og `U` skriver intet og går til del 2.
5. **Uoverensstemmelserne (31) og forældren uden kandidat behandles i del 2**, prioriteret: først de 9, der
   kan pege på fejl i databasen. En rettelse af en kanonisk familie kræver sit eget workflow og en ny beslutning.
6. **Dubletter på et kort besvares `1=2`** (tilføjet samme dag under udfyldningen). Står samme individ to
   gange i basen, nævner mennesket begge pladser; kortet er enigt med maskinen, hvis maskinens kandidat er
   blandt dem, og dubletten gemmes til del 2's `samme_som`-arbejde (spec §23.4).

**Uændret:** forseglingen og hashbindingen; ingen fulde afgørelsesark. `family_corroboration`-kernen får
én ekstra afvisning (udelukket persona). Ægteskaber afgøres maskinelt i del 2 uden kontrolkørsel som
betingelse, når begge identiteter er afgjort.

**Erratum 2026-10-21 (#151, indholds-id):** stikprøven trækkes efter `sha256('control-sample-v2:' ‖ input_sha256 ‖ ':' ‖
config_sha256 ‖ ':' ‖ persona_key)` og kortene vises efter `…'control-display-v2:'… ‖ candidate_person_id` i stedet
for kørsels- og persona-id'er, så trækningen kan genspilles i prod; garantierne er uændrede (indholds-id-spec §3).

## BESLUTTET: trin 5b — familie-forankret maskinel identitet (`family_corroboration`) ændrer 5a §4.2 (2026-10-06)

> **Besluttet af projektejeren 2026-10-06** ved godkendelsen af 5b-specen
> (`docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md`) efter brainstorm og syv
> review-runder (Claude + Codex).

**Baggrund.** 5a §4.2 lukkede enhver identitetsskrivning ud fra lighed: kun menneskelige afgørelser,
oprettelse med kvittering, 149b's faste 1:1-kobling og reversal. 5b skal give de cirka 248
ægtefæller i 2018-20 en identitet, og et fuldt menneskeark strider mod beslutningen om ingen flere
fulde afgørelsesark (2026-09-27).

**Besluttet:**
1. **Ny smal kerne-oprindelse `family_corroboration`.** Den må kun acceptere en ægtefælle-persona
   som den eneste partner i hovedpersonens familie med det matchende ordenstal. Kernen efterprøver
   selv proveniens, struktur, kandidat og familiekontekst under rækkelåse (spec §6.2). Alle andre
   lighedsmatch forbliver lukkede.
2. **Maskinen må kun skrive efter en bestået kontrolkørsel:** serveren vælger en blind stikprøve,
   projektejeren afgør den i et forseglet ark, og én afvigelse stopper al maskinel bekræftelse
   (spec §7).
3. **Ny oprindelse `relation_person_create`** til nye personer efter et menneskeligt `N`. Nye
   personer oprettes `staged` og med `levende = true`, indtil dødsfakta afgøres af et menneske.
4. **Relationer bindes strukturelt til familien** med en ny regeltype `structural_family` ved siden af
   trin 4's tekstbinding.
5. **Fortrydelse sker kun ved restore**, som for 4.1c og 4.4. Rettelser i drift sker fremad via
   menneskelige afgørelser.

**Uændret:** ingen automatisk accept uden for disse to oprindelser; prod kræver en separat
overførsels-spec og GO; 5a deployes først for sig.

## BESLUTTET: roadmap-trin 4 afsluttet for 2018-20 — trin 5 aktiveret, 5a først (2026-10-05)

> **Besluttet af projektejeren 2026-10-05** efter prod-overførslen af 2018-20's fortolkningskæde
> (`VERIFY_OK`, changelog 2026-10-05).

**Baggrund.** Trin 4's færdigbevis (trin 4-spec §2 punkt 5 og §8.5) var kæden `klausul →
forslag → afgørelse → binding` `integreret ende-til-ende` i én restore for 2018-20,
hovedpersonens persona. Det blev nået med 4.5 (2026-09-26), gentaget for hele 2018-20
(2026-10-03) og er nu kørt i prod (2026-10-05): 3.739 forslag, 676 afgørelser og 622 bindinger
med pakkens tre digests. Ingest og afgørelse er `produktionsverificeret` for 2018-20; promotion
kun for bindingsdelen. Det er mere, end trin 4 krævede.

**Besluttet:**
1. **Trin 4 er afsluttet for 2018-20.** 1939's kæde hører til trin 6 (trin 4-spec §11.4).
   Issues lukkes: #147 og #148 (leveret); #195 (klausul-projektionen, merget i #197 og brugt til
   afstemningen af 4.1c i prod); #196 som **erstattet** — projektionen er merget (#212/#214), men
   dens DDL blev aldrig deployet, og overførslen verificerer i stedet med tre nøglede digests
   (overførsels-spec 2026-10-03 §3.2, beslutning 7).
2. **Trin 5 er aktiveret** i rækkefølgen fra brainstormen 2026-09-24: **5a** én identitetsvej
   (#151) → **5b** personas for ægtefæller og børn samt oprettelse af nye kanoniske personer
   (trin 4-spec §11.3/§11.7) → **5c** slægt, linje og generation som placement/membership (#150).
   Hver del får sin egen spec og plan.
3. **5a starter med en genbekræftelse, ikke med Task 0.** Spec og plan (2026-09-24, gren
   `docs/151-identitetsvej`, ikke pushet) er skrevet før 4.5, kontrolmodellen, omsegmenteringen og
   overførslen kom på `main`. De holdes op mod den nuværende kode og skema, og afvigelser rettes
   i planen, før udførelsen begynder. Planens to forudsætninger — 4.5 merget og trin 5 aktiveret
   — er hermed opfyldt.
4. **Restpunkter fra trin 4 er egne opgaver, ikke forudsætninger for trin 5:**
   - næste promptversion med »var † [dato], da …«-reglen og titel/gods-reglen (2026-10-03).
     Kontraktfrysen (2026-10-01) gjaldt til den fulde kørsel og er dermed ophørt; selve
     promptversionen kræver sin egen GO, og dens nye fortolkninger erstatter de 13 `U`-kort;
   - oprydning af de 138 navne-assertions med titelord;
   - runnerens håndtering af Codex' nye kvotefejl.

**Uændret:** prod-mutationer kræver fortsat en udtrykkelig GO pr. apply, og roadmappens
rækkefølge (trin 5 → 6 → 7) står.

## BESLUTTET: titler og »til <gods>« er ikke en del af navnet — heller ikke i fortolkningsforslag (2026-10-03)

> **Besluttet af projektejeren 2026-10-03** under kontrolarket for den fulde 2018-20-kørsel (#147).
> Skærper navne/titel-princippet fra 2026-06-15 (titel ≠ navn) og udvider det til godsbetegnelser
> og til `person.name`-forslag fra fortolkningskæden.

**Udløser.** Af de 22 `person.name`-uoverensstemmelser (`REAL_DIFF`) i kontrolarket har 12 en titel
i værdien (»greve«, »komtesse«, »friherreinde«) og én en godsbetegnelse (III-15: »til
<gods>«). Prompten siger ikke, at titler og godser holdes ude af navnet. Ingen af de 241
`MATCH`-navne har titelord. Databasen selv har 138 navne-assertions med titelord fra tidligere
indlæsninger.

**Besluttet:**
1. **Titler er aldrig en del af `person.name`.** De er `person.title`/`titel`-fakta; visningen
   komponerer navn + titel. Undtagelse, der skal formuleres i navneregelen: tyske grene efter 1919,
   hvor titlen juridisk er en del af efternavnet.
2. **»Til <gods>« er aldrig en del af navnet.** Det er et ejerskab: `person.estate` → relation
   person →[ejer, periode]→ gods-entiteten. Ejerskab skifter over livet og mellem udgaver; i
   navnet ville det give falske navnevarianter, ødelægge navnematchningen og tabe perioden.
3. **Identifikation sker i trin 5, ikke i navnefeltet.** At »til <gods>« skiller navnefæller
   ad, er et ægte behov — men som identitetssignal (ejerskabsfakta, placering, løbenummer) i
   identitetsafstemningen, ikke bagt ind i en navnestreng. Det ordrette navn bevares i klausul og
   narrativ og kan altid gengives.

**Afvejet og forkastet:** at forslaget gengiver kilden ordret. Et forslag skal være kildetro
*inden for sit prædikat*; et dødsforslag tager heller ikke resten af sætningen med.

**Konsekvens nu:** de 13 kort afgøres `U` (»titel i navn« / »godsbetegnelse i navn«) og er
ubundne. `unresolved` er en endestation for RPC'en (`red_decide_interpretation` afgør kun
`proposed`), så de genåbnes ikke: vejen frem er nye fortolkninger fra næste promptversion, der
erstatter dem. Kontraktfrysen (2026-10-01) står ved magt: regelen i prompten venter på næste
promptversion, sammen med »var †«-reglen. III-15's ejerskab findes kun i
navneforslaget (intet `person.estate`-forslag, intet faktum) — et overset udsagn, ikke et tab:
narrativet bærer det.

**Åbent:** oprydning af de 138 navne-assertions med titelord i databasen er sin egen opgave.

## BESLUTTET: 2018-20 fortsætter med `gpt-5.6-terra` — Sonnet er målt og noteret som kandidat (2026-10-02)

> **Besluttet af projektejeren 2026-10-02.** Kontraktfrysen i beslutningen 2026-10-01 står ved
> magt. Projektejeren gav samme dag tilladelse til, at Anthropic måtte modtage pilotens 34 poster,
> **kun** til en måling via Claude-abonnementet. Det ændrer ikke behandlingsgrundlaget fra 2026-09-06
> for kæden.

**Målingen** (spike, kun tal; script og svar privat i `~/.private/model-maaling/`). Samme prompt
(`d46cda80…`), samme claims-skema og samme validering (`partition_record_claims`) som terra. Kaldet
`claude -p --model claude-sonnet-5 --tools ""` med fast output-skema, uden MCP, indstillinger eller
sessionslog: 0 værktøjskald, 0 subagenter.

| Pilotens 34 poster | terra | Sonnet |
| --- | ---: | ---: |
| Gyldige claims | 233 | 427 |
| Afvist af valideringen | 16 (6 %) | 48 (10 %), heraf 29 prædikater uden for ordforrådet |
| Præcision mod projektejerens domme | 165/165 | 142/143 |
| Claims uden dom | 68 | 284 |
| `mention.place` / `mention.person` | 26 / 0 | 120 / 59 |
| Input-tokens | 597.000 | 355.000 (150.000 fra cache) |
| Output-tokens | 23.000 | 200.000 (137.000 tænkning) |
| Tid pr. post | ≈ 20 s | ≈ 70 s |

**Vurdering.** Præcisionen er reelt ens, hvor der findes en dom. Sonnets ekstra mængde er især
omtaler, som ikke kan promoveres og forbliver `proposed` (beslutningen 2026-09-27), så de giver ingen
læserværdi i dag. Output-forbruget er 8½ gange terras. Målingen kan ikke afgøre, om Sonnets udømte
claims er sande, eller om terra overser fakta: matchet er ordret på værditekst, og dommene blev
afgivet på terras formuleringer, hvilket favoriserer terra.

**Besluttet:**
1. 2018-20 fortsætter med terra. Kørslen over de 488 poster er færdig under manifest `f5a76e1b…`.
2. Sonnet er kandidat til omtaler af personer og steder (trin 5) og til næste årbog. Et skift kræver en
   ny beslutning og en spec for en Claude-backend: værktøjer slået fra, sandbox, ny kontraktversion og
   behandlingsgrundlag for hele kæden. Det kræver også en måling af Sonnets udømte claims på et blindt
   ark.

## BESLUTTET: ingen særskilt prod-overførsel af piloten — hele 2018-20 køres i restoren og overføres samlet (2026-10-01)

> **Besluttet af projektejeren 2026-10-01**, inkl. underpunkt 1 og 2. Ændrer skridt 5 i
> beslutningen 2026-09-27 om omsegmentering (»derefter 4.4+4.5 i prod«) og afløser parkeringen
> 2026-09-23: 4.4+4.5 får ikke deres egen prod-GO. Kontrolmodellen (2026-09-27) gælder uændret.

**Baggrund.** Piloten er kørt om på de omsegmenterede klausuler (`genbind-44-pilot-2018-20.md`):
34 poster, 230 forslag, 46 bindinger, 24 kort. Den særskilte prod-vej (spec 2026-09-24 på
`docs/147-pilot-prod-vej`) blev designet til at redde 243 afgørelser, der havde taget dage; nu er
det 24 kort fra én session. En særskilt overførsel af 32 poster ville koste en fuld prod-ceremoni
(spec, plan, review, rehearsal, GO) for data, ingen læser ser (beslutningen 2026-09-27: 4.4 giver
ingen læserværdi i sig selv).

**Besluttet:**
1. **Pilotens egen overførsel springes over.** Alle 488 `eligible` poster i 2018-20 køres gennem
   kæden i en restore af et frisk prod-dump: modelkald, ingest, kontrolmodel, binding. Derefter
   overføres resultatet til prod **én gang**. Prod får præcis restorens forslag og afgørelser via
   den nøglede pakke (afsnit 1 i 24/9-spec'en: `interpretation_key`, `decision_fingerprint`,
   `pack_sha256`), aldrig et nyt modelkald mod prod. 4.4's gamle GO-pakke (#196) genbindes ikke;
   den afløses af overførslens egen spec og GO.
2. **Pilotens arbejde går ikke tabt.** Runnerens cache-identitet er profil, model, `prompt_sha256`,
   `record_key`, postens input-hash, `clause_set_sha256`, claims-skema og kontraktversion — ikke
   manifest eller bundt. De 34 pilotposter kommer derfor tilbage fra cachen, forslagene bliver
   identiske, `interpretation_key` ligeså, og de 24 afgørelser kan forudfylde kortene. Det holder
   kun, hvis restorens kildetekst og klausulsæt er som i dump `ddbe94b8…`, og intet i
   cache-identiteten ændres (underpunkt 1).

**Underpunkter:**
1. **Kontrakten fryses til den fulde kørsel:** ingen ny prompt-, profil- eller kontraktversion før
   den er kørt. Promptreglen for »var † [dato], da …« venter derfor. En ændring ville ændre
   `prompt_sha256`, så alle 488 poster — også pilotens — sendes til modellen igen, og
   pilotafgørelserne skal tages om.
2. **Omsegmenteringens fortrydelsesvindue lukker ved den samlede overførsels GO** (ikke ved en
   pilot-GO, som tidligere planlagt). Prisen er, at `~/.private/omseg-prod/` bevares til da.
   Projektejeren kan lukke vinduet tidligere; intet i prod afhænger af de gamle klausuler.

**Skøn** (skaleret fra piloten, 34 → 488 poster; piloten har længere poster end gennemsnittet,
så tallene er snarere for høje end for lave):

| | Skøn | Grundlag |
| --- | ---: | --- |
| Nye modelkald | 454 poster | 488 − 34 i cachen |
| Input-tokens | ≈ 8,0 mio. | 597.185 / 34 pr. post |
| Forslag i alt | ≈ 3.300 | 230 / 34 |
| Bindinger (`MATCH`) | ≈ 660 | 46 / 34 |
| Uoverensstemmelser (`REAL_DIFF`) | ≈ 57 | 4 / 34 |
| Forbliver `proposed` | ≈ 2.600 | ikke-promoverbare + `SKRIVEMAADE` + `NO_FACT` |

**Kortantal afhænger af, hvad der er »én kørsel«.** Kontrolmodellen trækker 20 stikprøvekort pr.
kørsel og stopper hele kørslen ved én fejl. Som én kørsel: ≈ 57 + 20 ≈ 77 kort, tre ark à højst
30. Flere kørsler koster 20 kort ekstra hver, men et stop rammer mindre. Opdelingen afgøres i
planen.

**Konsekvens for prod:** 4.4's oprindelige præmis var, at prod har 0 fortolkninger. Overførslen
giver prod ≈ 3.300 fortolkninger, heraf ≈ 660 bundne. Restoren tages af et frisk dump. Drift
mellem restore og prod ved overførslen — redaktionelle rettelser, ændrede klausuler — er
overførsels-spec'ens opgave (`decision_fingerprint`, `CLAUSE_SET_DRIFT` fra 24/9-designet).

**Rækkefølge:** (a) plan for den fulde kørsel i restoren (pilotplanens Task 1-3 i stor skala;
manifest over 488 poster kræver GO på hashes før modelkald); (b) spec for den samlede overførsel
med pakken som kerne. (b) kan skrives, mens (a) kører.

## BESLUTTET: GO til profil `daa-2018-20-v2` — regler `clause-rules-2018-20-v3` (2026-09-27)

> **Besluttet af projektejeren 2026-09-27**, jf. profilens `requires_human_go_for_change`. Skridt 2
> i beslutningen nedenfor (omsegmentering før 4.4).

**Indhold** (additivt; `daa-2018-20-v1` står uændret, så 4.1c's prod-klausuler kan reproduceres
591/591):
- `section_numeral_pattern` `^[IVX]{1,4}\.$` (#189): et fritstående romertal mellem to
  sætningstegn klipper ikke sætningen; klausulen bliver længere og flages `section_numeral`.
- `abbreviation_match` = `case_insensitive` (review 35, P3): forkortelseslisten slås op uden
  hensyn til store/små bogstaver.
- `Sr.`, `Pol.`, `Jahrg.` tilføjet listen (204 → 207).

**Virkning på 2018-20** (målt mod prod-teksterne, kun tal): 868 → 787 klausuler, 42 poster
ændret, klausuler under 8 tegn 26 → 2. En generel regel for korte versal-ord er fravalgt, fordi
106 af 153 ramte ord også står uden punktum i bogen.

**Afgrænsning:** GO'et gælder profilen. Prod ændres først af writer-operationen (skridt 4), der
får sin egen spec, rehearsal og GO.

## BESLUTTET: 2018-20's klausuler segmenteres om FØR 4.4 kører i prod — med en ny writer-operation, ikke restore (2026-09-27)

> **Besluttet af projektejeren 2026-09-27** på grundlag af en måling samme dag. Afgør review 35's
> P3/P4/S4 (§3.1, anbefaling 1). Ændrer rækkefølgen i beslutningen 2026-09-23 (4.4 parkeret):
> 4.4+4.5's prod-kørsel venter nu også på omsegmenteringen.

**Målingen** (kun tal; scripts og detaljer privat i `~/.private/p3-maaling/`). Den nuværende
segmenter genskaber prod-klausulerne fra 4.1c eksakt (591/591 ledger-hashes).

| | Prod | #189 (romertal) | #189 + kendte forkortelser |
| --- | ---: | ---: | ---: |
| Klausuler | 868 | 819 | 787 |
| Klausuler < 8 tegn | 26 | 5 | 2 |
| Poster ændret (af 101 med mere end én klausul) | — | 25 | 42 |
| Pilotposter ændret (af 32) | — | 7 | 8 |
| Pilotforslag / bindinger, hvis citerede klausul erstattes | — | 57 / 13 | 57 / 13 |

490 af 591 poster har kun én klausul og kan ikke rammes. Pilotens to kendte fejl (I-7, I-11)
ligger begge blandt de 25 romertals-poster. Ingen binding bliver usand; dens citat peger på en
klausul, der erstattes. Review 35's forslag om at spærre split efter ethvert kort versal-ord er
**forkert**: 106 af 153 ramte steder er ord, der også står uden punktum i bogen. Den sikre
rettelse er profilens egen forkortelsesliste slået op uden hensyn til store/små bogstaver, plus
`Sr.`, `Pol.`, `Jahrg.`.

**Hvorfor ikke restore (valg a):** restoren fra 18/9 ville rulle anon-hærdningen og
medie-indkapslingen (#204/#206), bogmærker og redaktionelle rettelser tilbage, og øvelsen
2026-09-17 viste, at en restore ikke er trofast. **Hvorfor før 4.4:** prod har i dag 0
fortolkninger, så en omsegmentering har intet, der afhænger af de gamle klausuler. Efter 4.4
skulle operationen også håndtere forslag, der citerer dem (S4). 4.4 giver ingen læserværdi i sig
selv, så ventetiden koster kun tid.

**Rækkefølge:**
1. **P4** — klausulsættet i runnerens cache-nøgle (kontrakt `evidence-runner-1.2`) og en
   `segmenter_version`, der afledes af koden. Kræver ingen afgørelse; gennemført 2026-09-27.
2. **Segmenteren** — #189 (romertal) + forkortelsesopslaget ovenfor som ny profil- og
   regelversion. Profilændringer kræver projektejerens GO (`requires_human_go_for_change`).
3. **S4** — en ny forslags-kørsel for en post med åbne forslag skal afvises fail-closed eller
   erstatte med en menneskelig superseded-beslutning (spec'ens krav), før piloten køres om.
4. **Writer-operationen** — omsegmentering af en post uden afhængige fortolkninger: spec, plan,
   rehearsal i en restore. Prod-DDL ⇒ review-budget efter beslutningen 2026-09-23.
5. **Piloten om** og kontrolmodellen på de nye forslag; derefter 4.4+4.5 i prod. Pilotens cache
   er skrevet under kontrakt 1.0 og genbruges ikke af en 1.2-runner, så alle 32 poster sendes
   igen; fra 1.2 rammer en senere omsegmentering kun de ændrede posters cache.

**Pilotens tal** (4.5-rapporten, kontrolmodel-kørslen) er målt på den defekte segmentering og
står med det forbehold.

## BESLUTTET: mennesket ser kun uoverensstemmelser og en stikprøve — ingen fulde afgørelsesark (2026-09-27)

> **Besluttet af projektejeren 2026-09-27** (forslag 2026-09-26), punkt 1-5 og stikprøve på
> 20. Ændrer spec 2026-09-06 §8.2 (»afgørelsen
> bruger projektets menneske-ark«) og berører åbent punkt 11.2.

**Baggrund (4.5-pilotrapporten, `interpretation-pilot-2018-20.md`).** Projektejeren afgjorde
et ark på 243 linjer for 32 poster. Det krævede flere arbejdssessioner over flere dage, og
projektejeren har meddelt, at flere fulde ark ikke er en farbar vej. Samtidig viste arket:

- **0 afvisninger blandt 159 nye forslag** (rettet 2026-09-27: 1 fejl fundet ved genlæsning, præcision
  241/243 — se `kontrolmodel-koersel-2018-20.md`). Præcision 242/243; den ene afvisning var et claim,
  4.3b allerede havde dømt usandt.
- **71 % af forslagene kan ikke føre nogen vegne.** Kun 70 af 243 har et promoverbart prædikat.
- **En binding ændrer intet kanonisk.** Den kobler en kildehenvisning til et faktum, der allerede
  findes (spec §8.3). En forkert binding er en forkert kildehenvisning, der kan fortrydes — ikke
  forkerte data.
- **Kun 5 af 70 er reelle uoverensstemmelser** med databasen; 43 matcher, 16 er skrivemåde, 6
  mangler et kanonisk faktum.
- **Pilotens eneste fejl ville være fanget af punkt 3 nedenfor:** det afviste dødsclaim matcher
  ikke personens eksisterende dødsfaktum og ville være vist som uoverensstemmelse.

Med den nuværende model kræver resten af 2018-20 ≈ 3.450 afgørelser (≈ 14 ark). Menneskets tid
er kædens flaskehals, ikke model, pris eller kode.

**Besluttet:**
1. **Ingen fulde afgørelsesark.** Forslag med ikke-promoverbare prædikater afgøres ikke; de
   forbliver `proposed`. Intet går tabt — de kan afgøres senere, hvis et læser-udløb (fx en
   fakta-sektion med kilde pr. faktum) gør dem værdifulde.
2. **Maskinel accept, når to læsninger er enige.** En promoverbar fortolkning, hvis værdi matcher
   en eksisterende assertion under RPC'ens egen normalisering (`MATCH`), accepteres og bindes
   maskinelt: `red_decide_interpretation` med `decision_evidence.method =
   'machine-corroboration-v1'`, kørt under projektejerens redaktionsprofil med henvisning til
   denne beslutning. Metodefeltet skiller maskinelle fra menneskelige afgørelser, så de kan
   tælles, efterprøves og fortrydes for sig. Ingen DDL. Forbehold: databasens værdi stammer fra en tidligere
   udtrækning af samme bog, så enigheden er to uafhængige *læsninger* af samme tekst, ikke to
   kilder. En fejl, begge læsninger deler, fanges kun af stikprøven (punkt 4).
3. **Mennesket ser kun uoverensstemmelserne:** promoverbare fortolkninger, hvor værdien er
   reelt forskellig fra databasens (i piloten 5 af 243). Skrivemåde-forskelle sorteres maskinelt
   fra først og tælles; de forbliver `proposed`, indtil en normaliseringsregel er besluttet.
4. **Stikprøve som kvalitetskontrol:** 20 tilfældige, maskinelt accepterede forslag pr. kørsel
   (fast seed, trukket før kørslen). Findes én fejl, stopper kørslen, og årsagen afklares før
   næste. Ved pilotens fejlrate (1 af 243) udløser stikprøven et stop i ca. 8 % af kørslerne.
5. **Kortformat:** et ark er højst ca. 30 kort, så det kan afgøres i én arbejdssession.

**Konsekvens for pilotens tal:** i stedet for 243 kort ville projektejeren have set ≈ 25 (5
uoverensstemmelser + 20 i stikprøven). For resten af 2018-20: ≈ 70 uoverensstemmelser plus én
stikprøve pr. kørsel, frem for ≈ 3.450.

**Hvad det koster:** et lille script (maskinel accept + stikprøvetræk) og en errata til spec
§8.2. Kræver en variant af målfindingen (`interpretation_promotion_targets.sql` ser i dag kun på
`accepted`; matchet skal beregnes over `proposed`, før noget accepteres). Genbruger
`red_decide_interpretation` og `red_promote_interpretations_batch` uændret.

**Hvad det ikke løser:** bindingen er stadig usynlig for læseren (review 35, §2.3 og U1), og en
normaliseringsregel for skrivemåde (16 af 27 `NO_MATCH`) kræver sin egen beslutning, fordi den
ændrer RPC'ens sammenligning.

**Næste skridt:** en errata til spec §8.2 og scriptet (variant af målfindingen over `proposed`,
maskinel accept, stikprøvetræk) planlægges som eget dagsværk. Review-budget efter
beslutningen 2026-09-23: kun restore ⇒ 1 + 1.

## BESLUTTET: 4.4's prod-kørsel parkeres, til 4.5 er bevist i restoren (2026-09-23)

**Besluttet (projektejer):** GO-pakken for 4.4's forslags-kørsel gøres færdig —
rehearsal på de endelige bytes, sidste uafhængige kodereview, runbook committet — men
selve kørslen i prod og deployet af #196's DDL, som den forudsætter, venter, til dagsværk
4.5 er gennemført mod restoren `daa43b_20260912192527`.

**Hvorfor, i vægtrækkefølge.**
1. **4.5 kræver ikke prod.** Spec §8.2 kører hele kæden — klausuler, runner, ingest,
   afgørelse, binding — i én restore, og §8.5 gør intet `produktionsverificeret`.
   Prod-kørslen er ikke på den kritiske vej mod trin 4's bevis.
2. **Forslag i prod har ingen værdi alene.** De bliver først brugbare, når et menneske kan
   afgøre dem, og den vej bygges i 4.5.
3. **En tidlig kørsel er dyr at gøre om.** 4.5 kan vise, at forslagenes facon skal ændres.
   Fortrydelse sker kun ved restore (beslutningen nedenfor), og en restore sletter alt
   skrevet i prod siden backuppen; backuppen lige før 4.4 lukker desuden 4.1c's
   fortrydelsesvindue.

**Konsekvens.** GO-pakken er bundet til commit, prod-dump og rehearsal. Når kørslen
genoptages, bindes den igen: nyt prod-dump, rehearsal mod det, nyt GO. Scripts og runbook
genbruges uændret, medmindre 4.5 ændrer writerens facon. Modenheden for
"Proposed-ingest" flyttes ikke af GO-pakken.

**Genoptages når** 4.5's pilotrapport (`interpretation-pilot-2018-20.md`) foreligger, og
projektejeren har besluttet, om 4.4's forslag og 4.5's afgørelser skal i prod samlet.

## BESLUTTET: review-budget og gater efter konsekvens (2026-09-23)

**Baggrund.** 4.4's prod-wrapper kostede fire uafhængige reviewrunder på planen og fire på
koden, et bibliotek på ~2200 linjer og en fejlmatrix på 30 cases — for en kørsel, der
skriver 84 usynlige `proposed`-forslag uden kanonisk delta. Hver runde fandt ægte fejl,
men af aftagende konsekvens; de sidste handlede om, hvad to samtidige genoptagelser gør.
Det er mønstret fra 2026-09-03 igen: sikkerhed på et mellemtrin fortrænger fremdrift mod
programmålet.

**Besluttet (projektejer):**
1. **Review-budget efter konsekvens.** Antal uafhængige reviewrunder (plan + kode):

   | Skrivningens konsekvens | Budget | Undtagelsesrunde |
   |---|---|---|
   | Kanonisk, `anon`-synlig, DDL, RLS/sikkerhed eller ikke fortrydelig | 2 + 2 | Ja, med projektejerens ja og begrundelse |
   | Kun det private lag, fortrydelig ved restore | 2 + 2 | Kun undtagelsesvis |
   | Kun restore eller disponibel base | 1 + 1 | Nej |

   En undtagelsesrunde er **smal**: den efterprøver kun de rettede fund og den kode, som
   rettelserne ændrede — ikke en ny, fri gennemgang. Efter budgettet tæller kun fund, hvor
   noget kan blive *skrevet* forkert (i prod eller i den bundne restore). Et fund, hvis
   værste udfald er et falsk STOP, er højst MINOR og dokumenteres i stedet for at rettes.
2. **Gate efter konsekvens.**
   - *Kanonisk eller `anon`-synlig prod-skrivning:* fuld gate — runbook,
     restore-rehearsal, fejlmatrix, uafhængigt review, udtrykkeligt GO.
   - *Prod-skrivning kun i det private lag, uden kanonisk delta:* runbook, backup, én
     rehearsal af den normale vej og fortrydelse ved restore; ingen fejlmatrix.
   - *Kun i restore eller disponibel base:* ingen prod-gate; færdig = én rigtig kørsel
     (regel 4 fra 2026-09-03).
3. **Værdi eller måling.** Hvert dagsværk ender med noget, en redaktør eller læser kan
   bruge, eller med en måling, der afgør et åbent spørgsmål — fx pris og redaktionel byrde
   ved en fuld udgave.

**Afgrænsning.** Reglerne gælder fremadrettet. 4.4's GO-pakke afsluttes efter sin egen
stopregel: kode-runde 4 er den sidste, og en tilbageværende BLOCKER parkerer pakken som
»ikke GO-klar« med fundlisten i stedet for en femte runde.

## BESLUTTET: 4.4's forslags-kørsel i prod fortrydes kun ved restore (2026-09-23)

**Kvittering fra projektejeren** for spec åbent punkt 11.5
(`docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`
§7.4): der bygges ingen fortryd-funktion for `interpretation_proposal` i prod. Går
kørslen galt, er vejen tilbage en restore af backuppen, taget umiddelbart før apply.
Målt i koden samme dag: `red_reverse_reimport` håndterer kun `person_create`- og
`name_completion`-batches, så der findes heller ingen delvis fortryd-vej.

**Grundlaget.** Kørslen skriver kun `proposed`-fortolkninger, observationslinks og
maskinelle klausuldispositioner i det private lag — intet kanonisk delta, intet
`anon`-synligt. Forkerte forslag afvises af mennesket i 4.5 og bliver `rejected`; en
restore er kun til en ødelagt batch.

**Konsekvensen, sagt højt:** en restore sletter alt, der er skrevet i prod siden
backuppen — bogmærker og redaktionelle rettelser inklusive. Og fordi backuppen tages
lige før 4.4, bliver den det nye restorepunkt: 4.1c's åbne fortrydelsesvindue
(backup 2026-09-18) lukkes reelt, når 4.4 er kørt. Skrivepausen fra 4.1c-runbooken
(før dump → efter `VERIFY_OK`) gælder også her.

**Afgrænsning:** kvitteringen gælder kun `interpretation_proposal`. Den er ikke et
prod-GO for kørslen, som fortsat kræver sin egen runbook, rehearsal mod dagens backup
og et udtrykkeligt GO.

**Forkastet:** en batch-reversal-RPC — ny, utestet kode på den mest følsomme vej, med
egen plan, review og DDL-deploy, for en operation hvis fejl kun rammer det private
evidenslag. Samme begrundelse som for klausulerne (2026-09-17).

## BESLUTTET: `red_*`-fladen efterprøves af en vagt, ikke af allow-listen alene (2026-09-20)

**Baggrund.** Allow-listen i `db-rls.sql` nulstiller hele `red_*`-fladen og genåbner 74
eksakte signaturer. Den læste som om de 74 *var* fladen. Det er de ikke: 37 får deres grant
af senere, formålsbestemte blokke (1939 v50-writeren, reimport-writeren, #152's
narrative-record-flade). Målt mod prod: 126 `red_*`, 111 `authenticated`-kaldbare, 0
anon-kaldbare — og **nul drift** mellem prod og det, filen selv producerer.

**Det var altså ikke en sårbarhed.** Problemet var, at ingenting efterprøvede *summen*:
blev tallet 112, ville allow-listens egen `RAISE` ikke opdage det — den fanger kun en
*omdøbt* signatur blandt de 74.

**Valgt:** en fail-closed slut-vagt, der kræver at hver `authenticated`-kaldbar `red_*`
står på den samlede gennemgåede flade, at ingen er anon-kaldbar, og at `service_role` holder
sig inden for en eksakt autorisations-liste. De 74 leveres af allow-listen selv gennem en
session-lokal tabel.

**Fravalgt: at duplikere de 74 i vagten.** Så ville kontrolmekanismen selv blive en kilde
til drift — to lister der kan komme fra hinanden.

**Fravalgt: præfiks-match på de 37.** En ny `red_apply_reimport_*` ville glide igennem
ubemærket, og det er netop den slags, en allow-liste skal fange.

**Versionsbevidst, fordi ACL-autoriteten er det.**
`private.apply_narrative_record_contract_acl(narrative_record_contract_version())` anvender
forskellige splits pr. version: v1 åbner fire legacy-indgange (i alt 102), v2 åbner 13 andre
(i alt 111). En flad liste over begge ville acceptere et v2-grant på en v1-base og omvendt.
Ukendt eller NULL version afvises eksplicit — en fremtidig v3 må ikke lydløst få v2's
forventningsmængde påtvunget.

**Prisen, sagt højt:** en ny writer-signatur kræver nu en tilføjelse to steder (allow-listen
eller vagtens liste). Det er hensigten — et grant uden en gennemgang er præcis det, vagten
findes for at forhindre. Fejlbeskeden siger det.

## BESLUTTET: leaked password protection kan ikke slås til på Free tier (2026-09-20)

Supabase-advisoren flager `Leaked Password Protection Disabled`. Fundet kan **ikke** lukkes
på den nuværende plan: dokumentationen siger direkte, at funktionen er *"available on the
Pro Plan and above"*. Projektejeren har bekræftet, at knappen er utilgængelig i dashboardet.

Funktionen ville slå brugernes kodeord op mod HaveIBeenPwned's Pwned Passwords API og afvise
kendte lækkede kodeord.

**Status: parkeret på tier, ikke på prioritering.** Den skal ikke stå som en åben opgave,
nogen forsøger at løse igen — der er intet at gøre uden en planopgradering. Genbesøg, hvis
projektet nogensinde flytter til Pro (samme sted som backup-manglen, der også er en
tier-begrænsning, jf. `CLAUDE.md` §Faldgruber).

**Gratis og uafhængigt af dette**, samme skærm (`Authentication → Sign In / Providers →
Email`): minimum kodeordslængde (mindst 8) og krav om tegntyper (cifre + små + store +
symboler). De to har selvstændig værdi og er ikke afhængige af Pro.

## BESLUTTET: medie-indkapslingen sendes uden at lukke rettighedsorakelet (2026-09-20)

**Afgjort af projektejeren** efter adversarial Codex-review (`gpt-5.6-sol`), som gav
NO-GO på grenen `fix/medie-indkapsling`.

**Fundet.** `media_rettigheder_ok(mid)` er `SECURITY DEFINER` og kaldbar af `anon`. Den
svarer `true` for et medie der er rettighedsfrigivet (`maa_publiceres` + `upload_status
='klar'`), **også når mediet er skjult** fordi det afbilder en levende/privat person.
En gæst kan dermed skelne "skjult medie findes og er frigivet" fra "findes ikke". Det er
samme orakel-standard, som filen selv anvendte på `family_offentlig` 2026-09-19, hvor
blot eksistensen blev regnet for en lækage.

Et revoke på funktionen alene lukker det ikke: `entitet_offentlig('media', id)`
reproducerer nøjagtig samme gate og er selv grantet til `anon`, fordi politikkerne
bruger den.

**Målt på prod-kopien (2026-09-20):** 0 af 13 medier er skjulte overhovedet, og dermed
0 rettighedsfrigivne-men-skjulte. Orakelet har i dag intet at fortælle. Latent, ikke
harmløst — det afgør hastegraden, ikke om det skal rettes.

**Valgt:** send indkapslingen nu; rettighedsorakelet får sin egen opgave.

**Hvorfor.** Grenen er en ren forbedring: den lukker to *aktive* orakler
(`media_afbilder_skjult` = PII-orakel, `media_id_for_object` = sti-eksistens-orakel)
uden at røre rettighedsgaten. Codex' NO-GO handler om noget grenen *ikke* lukker, ikke
om noget den ødelægger.

**Fravalgt: at lukke det i samme gren.** `entitet_offentlig`s media-gren fodrer
politikkerne på `note`, `narrative` og `text_mention`. Ændres den, kan noter og
narrativer, der i dag er synlige, forsvinde fail-closed. Det kræver sin egen
før/efter-måling mod læsefladen og hører ikke hjemme i en ændring, hvis hele pointe er
at anons synlige mængder skal være byte-identiske.

**LUKKET SAMME DAG** (PR #206, `036176f`, anvendt i prod 2026-09-20). Kontraktspørgsmålet
viste sig ikke at være et spørgsmål: `entitet_offentlig`s media-gren gatede kun på
rettigheder og lod derfor fakta om et GDPR-skjult billede være læsbare — det var en ægte
lækage, ikke kun et orakel, og skulle rettes uanset hvordan man svarede på orakel-spørgsmålet.
Grenen gater nu på `media_synlig_anon`, og `media_rettigheder_ok` er lukket for både anon og
authenticated. Se changelog 2026-09-20.

## BESLUTTET: klausul-projektionen er et udgaveneutralt delta-tjek, ikke en udvidelse af 1939-gaten (2026-09-17)

**Afgjort af projektejeren** (vej C af tre) for spec §11.1, issue #195.

**Baggrund.** Fase-pakke-runbookens værktøj (`reconcile_evidence_phase_gate.py` m.fl.,
~9.000 linjer) ligger kun på den umergede gren `codex/finish-156-158`. #170 udelod det
bevidst som udgavespecifikt og INCOMPLETE. Det er låst til 1939/source 3's otte
historiske faser (`HISTORICAL_PHASE_CONTRACTS`), mens 4.1c's 591 records er 2018-20
(source 1), skrevet af 149a/149b, som gaten ikke kender. En prøve-merge gav én
docs-konflikt og 215 grønne tests — koden virker, men passer ikke til opgaven.

**Valgt (C):** en læse-kun projektion (ejer + `anon` i ét snapshot) og en komparator uden
databaseadgang, som beviser én kørsels delta mod en godkendt måldatabase.

**Fravalgt:**
- **A — håndskrevet bidrag i runbooken, som 149a/b.** Runbooken forbyder selv manuelt
  konstruerede bidrag; afstemningen ville være en erklæring, ikke et bevis.
- **B — merge og generalisér 1939-gaten.** Omgør #170, kræver et nyt historisk scope
  (149a → 149b → 4.1c), og 149a/b kan formentlig ikke bindes bagudrettet.

**Prisen, sagt højt:** C beviser ikke historisk fuldstændighed og dækker kun de navngivne
tabeller; helrækkehashes kræver redaktionspause i vinduet. Fortolknings-projektionen
(4.4) står i #196.

**Review:** Codex `gpt-5.6-sol` gav NO-GO i tre runder før kode (runde 1: 7 BLOCKER; runde
2: 1 ny BLOCKER + 5 delvist lukkede; runde 3: yderligere fund), GO i runde 4. Rettet:
manifest-hashen genberegnes, én batch og én
kørsel bundet til writer-profilen, writer-invarianter tjekkes, klausulinventaret filtreres
ikke på ankre og sammenlignes på hele rækker og dispositionshistorik, ældre hændelser skal
være bevaret, `anon`-hashes er med, målidentiteten er bundet til en eksplicit DSN,
rehearsal-stop er kode. Overdraget/indsnævret: profilrækkens prod-indsættelse hører til
4.1c's GO-pakke; autorisations-, batch- og kørselsrækker afstemmes kun i projekterede
felter; resttilliden er, at DSN'en er prod.

**Fund:** 4.1c-rehearsalens »kanonisk lag identisk« (`kanonisk()` i det private
apply-script) var en hash af `count(*)` pr. tabel. Den erstattes af helrækkehashes.

## BESLUTTET: 4.1c's klausulkørsel i prod fortrydes kun ved restore (2026-09-17)

**Kvittering fra projektejeren** for spec §4.1.5
(`docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`):
der bygges ingen fortryd-funktion for `clause_evidence` i prod. Går klausulkørslen galt,
er vejen tilbage en restore af backuppen, taget umiddelbart før apply.

**Konsekvensen, sagt højt:** en restore sletter også alt andet, der er skrevet i prod siden
backuppen — redaktionelle rettelser inklusive. Apply-scriptets stopport på `change_set`
oprettet efter backup-start (indført ved skemadeployet 2026-09-17) mindsker vinduet, men
lukker det ikke.

**Afgrænsning:** kvitteringen gælder kun `clause_evidence`. Den arver ikke til
`interpretation_proposal` (4.4), hvor prod-fortrydelse fortsat ikke er designet (spec åbent
punkt 11.5), og den er ikke i sig selv et prod-GO for kørslen. Klausulkørslen kræver
fortsat en klausul-projektion i fase-pakke-gaten (spec åbent punkt 11.1) og sit eget GO.

**Forkastet:** en reversal-RPC for klausuler. Klausuler er append-only evidens uden
kanonisk delta; en særlig fortryd-sti ville være ny, utestet kode på den mest følsomme
vej, for en operation hvis fejl kun rammer det private evidenslag.

## BESLUTTET: reviewsignalet bor i menneskearket, ikke i en kolonne (2026-09-15)

**Baggrund.** 4.3b's ene usande claim var en **sproglig** fejl: »…var død 1353 (23. april),
**da** hans sønner … solgte landsbyen« — datoen er salgets, ikke dødsfaldets. Begge claims
stod ordret i teksten. Fejlen kan altså ikke fanges maskinelt, men 4.5's menneske skal
alligevel kunne se, hvilke claims der fortjener ekstra opmærksomhed. Hvor bor det signal?
En klausul-disposition kan ikke bære det: flere claims kan citere samme klausul.

**Forkastet: `proposal_flags jsonb` på `private.interpretation`.** Forespørgbar og følger
claimet — men **rækkefølgen havde allerede afgjort prisen**. 4.4's ingest var kørt, så de 84
forslag stod i den restore, 4.3b-4.5 deler (spec §3). Kolonnen skulle ind via writerens
lukkede payload-nøglesæt, og writerens guard er fail-closed pr. `interpretation_key`
(`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`), mens replay kortslutter på batch-niveau.
Valget ville derfor koste enten en genkørsel af hele 4.4 på frisk base — altså kassere den
base, 4.5 skal bruge — eller et `UPDATE` uden om `private.reimport_event` og uden om
tabellens versionsdisciplin (`interpretation_key`/`version`/`supersedes_id`).

**Forkastet: udskyd valget til 4.5.** Planens eget krav var et valg, ikke et »eller«. Efter
4.4's ingest bliver kolonnen kun dyrere, aldrig billigere.

**Besluttet: bedømmelsesarkets forudfyldte anbefalingskolonne er eneste kanal.** Spec §8.2
foreskriver allerede arket (token pr. linje, forudfyldt anbefaling, hash-bundet ved
godkendelse), og `build_43b_judgement_sheet.py` renderer det mønster i forvejen. Ingen DDL i
trin 4, ingen fjerde umigreret migration oven i de tre, der allerede venter på prod-GO.

Dertil: efter at H2 er opgivet som maskinel regel, er alt et flag kunne bære i dag
**afledeligt** af eksisterende kolonner — `confidence`, `persona_role`, antal citerede
klausuler, klausulens `clause_flags` (`unknown_abbreviation`, #189's 3-tegns `VI.`) og
`value_kind`. Datamodellens invariant 4 siger netop, at afledte værdier ikke persisteres.

**Prisen, sagt højt:** signalet lever uden for databasen, indtil afgørelsen skrives ind med
`red_decide_interpretation`. Mistes arket, mistes signalet — derfor er hash-bindingen ikke
valgfri.

**Genåbningskriterium:** måler 4.5, at redaktøren har brug for signalet forespørgbart *efter*
afgørelsen (fx til trin 6's UI), er `proposal_flags` en additiv kolonne på en base, der
alligevel skal bygges om. Beslutningen lukker ikke den dør; den omvendte vej findes ikke.

Skrevet som errata til §8.2 i
`docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`.

## BESLUTTET: `persona_role` bor i genimportprofilen, ikke i prædikatvokabularet (2026-09-15)

**Baggrund.** Spec §7.2 deler claims i to: dem om recordens persona (`principal`) og dem i
form `mention`/`relation`, som får `source_persona_id IS NULL` og stempler deres klausuler
`afventer_identitet`. 4.3b målte 8 `event.*`-claims — `event.appointment`, `event.dismissal`,
`event.acquisition` — som handler om hovedpersonen, men ikke har `person.`-præfiks. Det samme
gælder `heraldry.*`, `lineage.*`, `genealogy.*` og `image.*`. De er ingen af §7.2's to slags.

**Forkastet: »ikke `person.*` → `other`«.** Den ville give de otte persona `NULL` og stemple
deres klausuler `afventer_identitet` — claims om hovedpersonen ville se ud som claims om en
uidentificeret tredjepart.

**Forkastet: udled rollen af præfiksets form.** Det er 4.2's kind-afledningsfejl igen. Det gæt
kunne ikke skelne `event.marriage` fra `relation.marriage`, og et gæt her kan det heller ikke.

**Forkastet: rollekolonne i `private.interpretation_predicate`.** Den ville kræve DDL og
hævde, at rollen er en egenskab ved prædikatet globalt. Det er den ikke: `relation.marriage`
og `event.marriage` kan beskrive samme begivenhed og have hver sin rolle, fordi rollen
handler om *hvis record* claimet sidder i — en operations-egenskab, ikke en vokabular-egenskab.

**Besluttet: et eksplicit, versioneret `persona_role_map` i genimportprofilen.** Profilen er
under `requires_human_go_for_change`, så en ændring kræver en ny profilversion; kortets
version skrives i manifestets `provenance`, så hver kørsel bærer hvilket kort der gav
rollerne. Kortet er fail-closed — et ukendt prædikat giver ingen rolle, og builderen afviser
claimet frem for at gætte (»ukendt rolle« er et af femtals-regnskabets tal, og det var 0).

**Prisen, sagt højt:** kortet er udgavespecifikt og skal skrives igen for 1939. Og matchningen
er præfiksbaseret, så et nyt prædikat under et kendt præfiks arver rollen stiltiende. Det er
acceptabelt, fordi 4.5 er menneskegatet, men et prædikat hvis rolle afviger fra præfiksets
**skal** have sin egen længere nøgle. Derfor vinder længste præfiks, og et selvmodsigende kort
rejser frem for at vælge.

Skrevet som errata til §7.2 i
`docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`.

## BESLUTTET: tærskler og opdeling for dagsværk 4.3b (2026-09-12)

**Baggrund.** Plan 4.3b afgør, om modellen kan udtrække brugbare fakta af ægte DAA-prosa.
Anden læser påpegede, at et enkelt procenttal kun måler præcision: en model, der returnerer
ét sikkert claim og overspringer resten, ville score 100 % og dermed få grønt lys til et
ubrugeligt spor. Kriteriet blev derfor delt i fem mål, og planen fik til opgave at foreslå
tal frem for at bede projektejeren opfinde målemetoden.

**Besluttet (projektejer, 2026-09-12):** de foreslåede tærskler gælder, og afvigelse E
(ti records kørt som 5 + 5) er godkendt.

| Mål | Nævner | Tærskel |
| --- | --- | --- |
| Præcision — claimet er sandt ifølge teksten | alle claims | ≥ 90 % |
| Klausulbinding — citerer den rigtige klausul | alle claims | ≥ 90 % |
| Ordrethed — værdien er ordret hvor prædikatet kræver det | claims m. ordret krav | ≥ 95 % |
| Dækning — andel af annoterede udsagn, modellen fandt | annoterede udsagn | ≥ 60 % |
| Brugbarhed — records med mindst ét korrekt claim | ti records | 10/10 |

Uanset procenterne standser sporet øjeblikkeligt ved to fejltyper: et claim om en **levende**
person, eller et claim der citerer en klausul fra en **anden** record.

**Grundlaget er et kvalificeret skøn, ikke empiri.** Projektejeren tilkendegav, at der ikke
foreligger et informeret grundlag for at ændre tallene, og accepterede dem som de er. Det er
en bevidst afgørelse, ikke en forglemmelse: pointen er ikke, at 90 er det rigtige tal, men at
**der står et tal før kørslen**, så et resultat ikke kan bortforklares bagefter. Første
kørsel er netop det grundlag, der mangler — tærsklerne revideres efter 4.3b, hvis den viser,
at de sidder forkert.

**Afvigelse E.** §6.5 kræver ti records. De køres som to bundter på fem, så prisen for at
opdage en promptfejl halveres. Alle ti defineres **før** første kald og køres under samme
frosne profil, prompt, model og outputskema; ændres prompten undervejs, nulstilles beviset,
og ti nye records køres under den nye version.

## BESLUTTET: ingen prisberegning i fortolkningskæden — afvigelse D (2026-09-12)

**Baggrund.** Spec §6.4 (godkendt 2026-09-06) kræver, at manifestet bærer en omkostning
regnet ud fra en pinnet `pricing`-tabel pr. model, og at en model uden pris stopper kørslen.
`cost_usd` har ligget som felt i `BatchManifest` siden før trin 4. Plan 4.3a's Task 4 skulle
fastlægge skema og cost-formel; anden læser (R10) påpegede, at formlen krævede flere
selvstændige afgørelser — tæller `reasoning_output_tokens` som output, hvordan prissættes
`cached_input_tokens` og `cache_write_input_tokens`, valuta, kildedato, afrunding.

**Besluttet (projektejer, 2026-09-12): prisberegningen udgår.** Kørslerne afregnes over
abonnement, ikke pr. token (§6.7 anerkender det selv), så en kroneomregning ville være et tal
uden modstykke i virkeligheden — og et tal, der ville se lige så autoritativt ud i manifestet
som et målt. Vurderingen er, at det er overengineering i forhold til opgaven: at importere
årbøgerne.

**Hvad der beholdes.** De rå tokental fra Codex' `usage` (fem felter) registreres fortsat.
De koster intet at samle op, de kommer med svaret, og de er det, der faktisk afgør, om en
større kørsel kan gennemføres inden for kvoten. Det er kvoten, ikke kronebeløbet, der er den
bindende grænse.

**Samme afgørelse omfatter eskaleringsgaten.** §6.4 kræver også, at kun validator-flaggede
records må bruge `gpt-5.6-sol`. Den implementeres ikke: runneren vælger ikke selv model, og
der findes ingen automatisk eskalering at gardere sig imod — gaten ville værne mod noget, der
ikke kan ske af sig selv. `escalation_reason` håndhæves fortsat af den eksisterende kode.
Tilføjes den dag, en kørsel faktisk har brug for den stærkere model.

**Virkning.** `pricing_version` er fjernet fra `BatchManifest` og fra `reusable`. Task 4's
Step 2-3 og Step 7 udgår, så dagsværkets Task 4 er reduceret til prompt-bindingen alene.
Budgetter opgøres i tokens. `BatchManifest` bærer en kommentar om, at fraværet er bevidst, så
en senere læser ikke tilføjer det igen som en oversigelse.

## BESLUTTET: Tre spec-afvigelser for dagsværk 4.3a — A, B og C (2026-09-11)

**Baggrund.** Plan 4.3a (`docs/superpowers/plans/2026-09-11-trin4-4-3a-runner-og-forbrug.md`)
rejste tre afvigelser fra den godkendte trin 4-spec. To blev fundet ved måling, én ved
kodeeftersyn. Codex `gpt-5.6-sol` læste planen som anden læser (decisions 2026-09-06, valg 3)
og fandt 12 fund, heraf tre blokerende.

**Besluttet (projektejer, 2026-09-11): GO til alle tre.** C blev givet betinget — »hvis det er
muligt« — og muligheden er efterprøvet empirisk samme dag, se nedenfor.

**A. `--ignore-user-config` ind i §6.2's flagliste.** `--ignore-rules` dækker kun
execpolicy-filer; brugerens `~/.codex/AGENTS.md`, `config.toml` og tre brugerskills injiceres
stadig og udgør 6.288 af 21.554 input-tokens. Afgørende er ikke besparelsen, men at §6.2
hash-binder prompten (`prompt_sha256`) for at gøre kaldet reproducerbart — mens brugerens
private AGENTS.md ligger uden for hashen og kan ændre sig usynligt mellem to kørsler.
*Fravalgt:* at leve med en hash, der kun dækker en del af konteksten.

**B. `extract-prompt.md` omdøbes ikke; der skrives en ny prompt.** Spec §6.2's formulering
byggede på en antagelse, som ikke holdt ved eftersyn: ingen kode binder profilens
`prompt_version` til en fil (det er en ren streng), versionerne er forskellige
(`evidence-extract-1.0.0` mod filens `2026-07-29b`), filens indhold er den gamle trin ③-vej
(skriver `work/extracted/*.json` med Write, validerer mod `extraction-schema.json`), og
`SKILL.md:104` bruger den stadig. En omdøbning ville give en fil, hvis navn lyver om
indholdet, og samtidig bryde den gamle vej. *Fravalgt:* omdøbning som spec'en foreskrev.

**C. »Én record ad gangen« håndhæves af operativsystemet, ikke af prompten.** Kanarietesten
viste, at `--sandbox read-only` ikke er en læsegrænse: modellen eksekverede en
shell-kommando og læste en fil uden for `-C`. Kravet er derfor en OS-håndhævet grænse.

**C's mulighed er MÅLT, ikke antaget (2026-09-11).** macOS Seatbelt (`sandbox-exec`) kan
håndhæve grænsen om `codex exec`:

- Deterministisk adgangstest uden model: `work/`, `work_1939_stamtavle/`, `work_presens/`
  og `~/.private/` gav alle `rc=1` (nægtet), mens `docs/` og call-dir forblev tilgængelige.
- Modeltest mod en **syntetisk** spærret mappe: modellen forsøgte aktivt (»med en alternativ
  læsemetode«) og svarede `KAN IKKE LÆSE`. Kanariestrengen optrådte ikke i hændelsesstrømmen.
- Codex kører normalt inde i profilen (`usage` rapporteres; 15.256 input-tokens).

**Formen blev strammet samme dag til en ægte allowlist.** Første udgave var deny-baseret
(nægt de kendte PII-mapper) med den svaghed, at en ny mappe ikke ville være dækket. Den
endelige form lukker **hele hjemmemappen** for læsning og åbner kun `~/.codex`, `~/.local` og
call-dir. De tidligere `EPERM`-fejl skyldtes ikke manglende stier, men at kaldet blev startet
fra en mappe, profilen selv spærrede — processens arbejdsmappe skal ligge uden for
spærringen.

**Restpunkt.** Codex' egen `~/.codex/auth.json` er stadig læsbar for modellen; det er en
forudsætning for at CLI'en kan køre. Ingen forværring i forhold til i dag, men ikke lukket.
Registreret som Task 2 Step 1c.

**Konsekvens for planen:** Task 2's isolationsgate er bestået i princippet, så 4.3 standser
ikke. Task 2 strammer profilen mod en allowlist og gør adgangstesten til et fast trin.

## BESLUTTET: Prædikatvokabularet ejes af databasen, ikke af extractoren (2026-09-11)

**Baggrund.** Fortolkningslagets lovlige prædikater fandtes to steder: en hårdkodet
`ALLOWED_PREDICATES` i `evidence_extract.py` og ingenting i databasen. De to kunne drive
fra hinanden, uden at noget opdagede det.

**Besluttet.** `private.interpretation_predicate` er eneste sandhed — navn, udsagnsform
(`interpretation_kind`), §7.3-kategori og værdiform (`value_kind`). Extractoren læser en
**genereret, byte-verificeret projektion** af tabellen
(`references/interpretation-predicates.json`), som CI sammenligner med databasen på begge
migrationsstier. Filen kan kun ændres via `--write` mod en base med gældende skema.

**Afvist alternativ:** en oversættelsestabel mellem extractorens navne og databasens. Den
ville have bevaret to navnerum og gjort driften mulig igen, blot ét led længere væk.

**Udsagnsformen udledes af tabellen, ikke af præfikset.** Det gamle gæt
(`life_event.*` → event, `relationship.*` → relation, ellers property) kan ikke skelne
`event.marriage` fra `relation.marriage`, som er to forskellige udsagn om samme begivenhed.

**Komposit-FK frem for to uafhængige kontroller.** `private.interpretation` refererer
`(predicate, interpretation_kind)` samlet, så udsagnsformen bindes til prædikatet i stedet
for blot at sameksistere med tabellens eget fireværdi-CHECK. FK'en er erklæret **inline**
som tabel-constraint, ikke som `ALTER TABLE`: en kontrakttest matcher på, at
`CREATE TABLE private.interpretation` og `CREATE TABLE private.interpretation_observation`
står som naboer, og en `ALTER TABLE` imellem dem ville vælte et andet CI-job.

**Fixture-prædikater omdøbt frem for at slække formatinvarianten.** `db-verify.sql` — som
kører **mod prod** — indsatte fire prædikater uden punktum (`death_date`, `fake_approval`,
`terminal_status` og ét skjult i en `dblink_exec`-streng med fordoblede apostroffer). De er
omdøbt til `verify.*`, så PK-formatet `^[a-z_]+(\.[a-z_]+)+$` kan stå uændret. Alternativet
— at løsne formatet, så fixtures passede — ville have gjort produktionsverifikationens
behov til datamodellens regel.

**Prod-siden skal have sin egen assertion.** 4.2's verifikation lå først kun i
`tests/sql/`, som alene kører i CI. `db-verify.sql` har nu en `OK: #147`-blok; seed-antallet
asserteres som `>= 42`, så senere dagsværk kan tilføje prædikater uden at gøre
produktionsverifikationen rød, mens fixture-rækkerne tælles præcist.

**Målt før beslutningen.** Prod har 0 fortolkninger og 5 promotion-regler, alle dækket af
seedet med samme udsagns- og værdiform — så FK'en kan indføres uden at ændre prods
promotion-adfærd. Rapport:
`docs/evidensbaseret-genimport/interpretation-predicate-147-rehearsal.md`.

## BESLUTTET: Regelversion 2 for klausul-segmenteringen — profil v1.2.0 (2026-09-10)

**Baggrund.** 4.1b's kørsel på alle 591 helposter viste 424 klausuler flagget
`unknown_abbreviation`, fordelt på 332 records. De 153 tokens, der faktisk blokerede en
split, blev udtrukket og lagt frem for projektejeren som tokens uden kontekst — jf.
profilens `requires_human_go_for_change`.

**Besluttet (projektejer, 2026-09-10):** GO til `clause-rules-2018-20-v2` og profilversion
`1.2.0`.

**Sådan blev listen kurateret.** 113 tokens er tilføjet (91 → 204 forkortelser): almindelige
danske forkortelser, flerpunkts-forkortelser (`s.å.`, `m.a.`, `bl.a.` …), akademiske grader
(`cand.*`, `dr.*`, `Ph.d.` …), ordener og dekorationer (`D.M.`, `R.St.`, `Pr.R.Ø.1.` …) og
militære enheder. **Kun tokens, der med sikkerhed er standardforkortelser, kom med.** 26
tokens er bevidst udeladt og står stadig som flag: enkeltbogstaver (`a.`, `u.`, `(b.`),
almindelige ord foran et ægte punktum (`død.`, `maj.`) og dato-/talintervaller
(`febr.-31.`, `95.-97.`). At tilføje dem ville slukke et flag uden at vide hvorfor; flaget er
netop den redaktionelle kø for ægte tvivl.

**Virkning.** Tilføjelserne ændrer ikke segmenteringen — tokenerne blokerede allerede — kun
flagtallet: 424 → 53, fordelt på 45 records. En separat motorrettelse gav to klausuler
tilbage: et punktum efter en lukkeparentes afslutter sætningen.

## BESLUTTET: GO på extraction-profil v1.1.0 + implementering af trin 4 (2026-09-10)

**Baggrund.** PR #172 (spec rev. 3 + planer 4.1a-4.2) blev merget til `main` 2026-09-10.
Beslutning 1 ovenfor kræver projektejerens GO, før profilen får en ny version; plan 4.1b
indfører `clause_rules` i 2018-20-profilen som version 1.1.0.

**Besluttet (projektejer, 2026-09-10):**
1. **GO på profil v1.1.0.** `clause_rules` må tilføjes additivt til 2018-20-profilen i
   `.claude/skills/daa-extract/references/extraction-profiles.json` som version 1.1.0.
   En senere v1.2.0 (fx justeret `gap_charset` efter 4.1b's måling) kræver et nyt GO.
2. **Implementeringen udføres af sessionen, ikke af projektejeren.** Den oprindelige plan
   (»jeg implementerer selv med en anden model«) er ændret: Claude implementerer planerne
   ét dagsværk ad gangen, og Codex (`gpt-5.6-sol`/`terra`) bruges til kodning og især til
   review — herunder anden-læser-rollen i beslutning 3 ovenfor, nu hvor Codex-kvoten er
   nulstillet.

## BESLUTTET: Roadmap-trin 4 aktiveret — seks valg for fortolkningskæden (2026-09-06)

**Baggrund.** Trin 1-3 (#152, #153, #149) blev anvendt og efterverificeret i prod
2026-09-05/06 (GO 1-4). Projektejeren bad om at fortsætte til trin 4 (#147/#148).
Spec'en `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md`
blev skrevet af PM-rollen, godkendt sektionsvis, læst uafhængigt to gange (Opus; Codex-kvoten
var opbrugt til 2026-09-09) og revideret til revision 3. Fire planer (4.1a-4.1c, 4.2) er
skrevet; planer for 4.3-4.5 afventer målinger fra 4.1b/4.3a.

**Besluttet (projektejer, 2026-09-06):**
1. **Model-backend:** `codex exec` med profilens frosne `gpt-5.6-terra`/`gpt-5.6-sol`;
   modelpolitikken ændres ikke, profilen får additive nøgler i nye versioner med GO.
   Fravalgt: `claude -p`/Sonnet.
2. **Skrivevej:** to nye elementoperationer i #153's generelle writer (`clause_evidence`,
   `interpretation_proposal`). Fravalgt: separate ingest-RPC'er.
3. **Anden læser:** uafhængig maskinel læser (Opus; Codex `gpt-5.6-sol` når kvoten tillader)
   af spec og hver plan, derefter projektejerens afgørelse.
4. **GDPR-udelukkelse for modelkald:** regel 1-4 (hovedperson levende/uafklaret; partner
   eller barn markeret levende; partner uden dødsdato med vielse 1950+ eller uden vielsesdato;
   tekstfilter "f." + fødselsår 1950+), målt 2026-09-06: 541 afdøde hovedpersoner, 13 ekstra
   udelukkes af regel 2, 62 poster berørt af regel 3's grundlag, 2 af regel 4.
5. **Behandlingsgrundlag:** projektejeren accepterer ChatGPT-abonnementet (ikke API-nøgle med
   særskilte databehandlervilkår) som grundlag for behandling af afdødes kildetekst; skift til
   API-nøgle er en ny beslutning.
6. **Promotion i trin 4 er binding, ikke oprettelse:** accepterede fortolkninger bindes til
   eksisterende, tekstidentiske assertions; nye fakta/personer fra fortolkninger er uden for
   trin 4.

**Målt undervejs (læse-kun, lokal prod-kopi):** begge udgaver har én helpost-observation pr.
record med 1:1-mention; 2018-20 har ingen strukturelle records; helposter har ingen
linjeskift; promotion-RPC'en opretter intet kanonisk; `red_decide_interpretation` og
promotion-RPC'erne findes men kaldes af ingen.

## BESLUTTET: #152-cutover-runbookens reviewer-krav tilpasset enkeltmandsprojekt (2026-09-05)

**Baggrund.** `docs/runbooks/narrative-record-key-cutover.md` kræver to navngivne lokale
reviewere (én for record-/legacy-beslutningerne, én for hashes, mængder og databaseidentitet)
samt en skriftlig foreløbig autorisation og en ekstern ejer af writer-traffic-holdet.
Projektet har én udvikler.

**Besluttet (projektejer, 2026-09-05):** Projektejeren er eneste menneskelige reviewer og
godkender beslutningslisterne (alle record-baselines »godkend«, alle legacy-kandidater »bevar
som overgangsdata« — samme som rehearsalen). Kontrol-sessionen (Claude) udfører den
uafhængige verifikation af hashes, ID-mængder, tællinger og databaseidentitet og dokumenterer
den i cutover-rapporten. Projektejerens »GO 2« i chatten er både foreløbig autorisation og
slut-GO; writer-traffic-holdet ejes af projektejeren (ingen redigering under cutover).
Prod-skrivninger udføres af projektejeren selv via forberedte scripts, fordi harnesset
blokerer sessionens egne prod-skrivninger. Fravalgt: at finde en anden reviewer (ingen findes)
eller at springe hash-verifikationen over (den er billig og fanger drift).

## BESLUTTET: Styringsregler efter PM-gennemgang + opdeling af #149 (2026-09-03)

**Baggrund.** En læse-kun gennemgang 2026-09-03 viste, at retningen fra 25/8
følges (C3 → #152 → #153 → #154/#155 → #157), men at roadmappens trin 3-4
(#149, #147/#148) stod på nul, mens ~180 commits/~54k linjer siden 29/8 gik
til trin 1-2, hærdning og tests. Styringsdokumenterne holdt ikke alene, fordi
(a) "ét aktivt programmål ad gangen" ikke blev håndhævet — seks spor kørte
parallelt samme uge — og (b) den, der skrev planen, også besvarede de seks
adgangskrav selv.

**Besluttet (projektejer):**
1. **Ét aktivt programmål ad gangen** håndhæves: nye worktrees åbnes kun for
   det aktive mål og for en registreret kontrolleret afbrydelse.
2. **Anden læser før kode.** Adgangskravene i `roadmap.md` besvares af den,
   der planlægger, og efterprøves af en anden (PM-rollen) før implementering.
3. **Én dags synligt trin.** En plan leverer ét synligt, testbart trin på højst
   én dag; større arbejde deles.
4. **Færdig = én rigtig kørsel.** Definition of done for enhver task er én
   kørsel mod rigtige data i en øvebase (restore), ikke grønne syntetiske
   fixtures alene.
5. **Issues mærkes** `roadmap` / `afventer-prod-GO` / `parkeret` /
   `uden-for-genimport` / `kontrolleret-afbrydelse`; #160-#163 er parkeret,
   #164 er kandidat til kontrolleret afbrydelse, #159 er løst i kode.

**#149 opdelt i 149a og 149b.** #152's kontrakt afviser upsert på
legacy-narrativer (§6.2), kræver accepteret persona-identitet og reserverer
`legacy_migrated` til #149 uden writer (§4.3). 149a = kilderegnskab (rendition,
591 records, forekomster, ankre) gennem #153's writer, nul kanonisk delta.
149b = generel `legacy_migrated`-writer + identitet fra `person_external_id`,
egen spec efter inventeringen. Roadmap-trin 3 er uændret; rækkefølgen inden i
trinnet er 149a → 149b.

**149a: afvigelser målt i koden (2026-09-03 aften).** (1) *Reversal findes ikke for
en ren source_evidence-batch*: `red_reverse_reimport` kræver `activated` + ét
name_completion-barn, og der er ingen sletningsvej for source records/ankre.
Erstatningsbevis: nul kanonisk delta (aggregat-hash), observeret fail-closed
`REIMPORT_WRITER_REVERSAL_INVALID`, gendannelse ved restore fra 0600-backup.
**Kvitteret af projektejeren 2026-09-03 aften** (spec §10): fortryd af 149a sker ved restore, ikke ved et kald. (2) »Eksakt
delstreng« måles i en whitespace-normaliseret projektion med offset-kort, fordi
`segment.py` selv normaliserer; ingen fuzzy-match. (3) Anker-evidens bæres i
payload (`anchor_method`, `segment_version`, `verbatim_sha256`), da writeren
hardkoder evidensfeltet. (4) Paritet mod juni-udtrækket måles på mængden af
post-adresser. (5) `preview_sha256` bindes til preview-artefaktets filbytes;
batchen kan derfor ikke kædes til name_completion (irrelevant for 149a).
**Fund mod #153:** migrationsguarden `REIMPORT_LEGACY_IN_FLIGHT_MIGRATION_BLOCKED`
afviser `finalized` reimport-batches; 1939 fase A-batchen er og forbliver
`finalized` → blokerer 149a's ægte rehearsal og formentlig #153 i prod.

**BESLUTTET (projektejer, 2026-09-03 sen aften): #153-guarden rettes generelt.** Prod
bekræftede læse-kun, at 1939 fase A-batchen `328a813a…` står `finalized` (584
source_evidence / 0 person_creates); `reimport_writer_upgrade`-guarden ville derfor
blokere #153 i prod. Valgt vej (a): `finalized` accepteres som terminal for
reimport-batches uden personoprettelser, evidensbundet (consumed autorisation,
observed = expected = autorisationens expected; ingen børn, kun source_evidence-events
i autoriseret antal, intet name_completion-resultat, ingen cutover/reversal-
autorisation). Fravalgt (b): et engangs-terminaltrin i prod for netop denne batch —
dækker ikke næste bog. Bevist: positiv fixture blokerer mod HEAD uden rettelsen og
migrerer med den; to negative cases blokerer fortsat; migration gennemført på restore
af prod-dump, hvorefter 149a's ægte rehearsal gav 1/591/591/591 med nul kanonisk delta.

**#156 (fase-pakke-afstemning): fund.** Runbookens bundle-sti var opdigtet, og
auditorens receipt-skemaer (`daa-evidence-phase-receipt-*-v1`) er yngre end de
kørsler, de skal beskrive; ingen historisk apply-kvittering bærer dem, og C3
manglede som bidrag. Valgt vej: adaptere bindes til de faktiske manifester og
apply-JSON'er med tilstanden `afterdocumented`, C3-adapter tilføjes, derefter
ét autoriseret læse-kun prod-snapshot og én afstemning. INCOMPLETE/DRIFT er en
lukning med restpunkt, ikke anledning til nye adaptere.

**149b-spec skrevet af PM-rollen (2026-09-03, sen aften) — to valg kræver projektejerens
kvittering før prod-GO** (`docs/superpowers/specs/2026-09-03-2018-20-fase-b-legacy-migration-design.md`):
**(A) Identitet uden placement-kæde.** #152 §6.1(9) beregner »entydig identitetsmængde«
gennem record-placement → persona-placement → persona-identitet. Placement kræver en
`header`-observation (`EVIDENCE_PLACEMENT_HEADER_REQUIRED`); ingen udgave har dem, og prod
har 0 placements — kæden er ubrugt uden for tests og er roadmap-trin 5 (#150/#151). 149b
skriver derfor persona + mention + accepteret identitet med `person_external_id` som evidens
(egen ledger, som #166 kræver), men ingen placements. Bindingens autoritet bliver
`existing_exact_binding` — samme som 1939's 550 bindinger. Kendt pris: når #150/#151
bagudfylder placements, bliver publiceringerne `stale_published` og skal revalideres; det
gælder 1939 i samme grad, så udgaverne forbliver symmetriske. Fravalgt: at bygge
placement-kæden for 2018-20 alene (omprioriterer roadmappen, giver asymmetri).
**(B) Reversal.** Per narrativ gennem #152's dedikerede reversal, udvidet med en
`legacy_migrated`-gren gatet på at record-bindingen allerede er trukket tilbage
(published → draft → withdrawn → ledger tilbage til grandfathered). Batch-reversal =
per-narrativ reversals i omvendt rækkefølge under én autorisation; `red_reverse_reimport`
afviser fortsat (som 149a). Fravalgt: kun restore (for grov, når offentlig synlighed
ændres) og en ny hel-batch-RPC (ny mekanik uden for #152's kontrakt).
**Målt grundlag** (dump 2026-08-21): 544 ikke-levende / 47 levende / 0 NULL; 4 tekstulige
(3 ikke-levende, 1 levende) → forventet 541 `bound_published`, 46 `bound_draft`,
4 `unresolved_text`, 0 `unresolved_identity` (0,7 % < 10 %-stopgrænsen).

**KVITTERET af projektejeren 2026-09-04: valg A og valg B.** (A) Identiteten record ↔ person
for 2018-20 indlæses som accepteret persona-identitet med `person_external_id` som evidens,
uden placement-kæde; bindingens autoritet er `existing_exact_binding` som for 1939's 550
bindinger, og begge udgaver revalideres samlet, når #150/#151 leverer placements. (B)
Fortrydelse sker pr. narrativ gennem #152's dedikerede reversal (reverse published → discard
draft → reverse legacy_migrated); fuld fortrydelse er endelig for narrativet, batch-fortrydelse
er per-narrativ trin under én autorisation. Projektejeren godkendte samtidig merge af PR #167
og prod-rækkefølgen #152-cutover → #153 (m. guard-rettelse) → 149a → 149b som én samlet
prod-dag med tre GO'er.

**149b, leverance 1 implementeret (2026-09-04) — to præciseringer af valg B og én #152-rettelse.**
(1) Fortryd-kæden er »reverse published → discard draft → reverse legacy_migrated«, ikke
»reverse published → reverse draft_created«: #152's reversal appender til samme stream, så
`draft_created` er ikke seneste event efter første fortrydelse (bekræftet empirisk). (2) Fuld
fortrydelse er endelig for narrativet: `narrative_record_publication.narrative_id` er UNIQUE og
writeren afviser enhver eksisterende binding; genmigrering kræver en ny beslutning. (3) #152's
læsefunktioner rettes i 149b: `person_daa_narrative_publication_allowed` så kun aktive bindinger
(`draft`/`published`) blokerer legacy-grenen, og record-grenene i `public_person_bio_source_versions(_v2)`
kræver `binding.status='published'` — ellers forsvandt et fuldt fortrudt grandfathered narrativ
fra den offentlige flade (målt), og étlinje-rettelsen alene ville give en dublet. Kombinationen
(withdrawn binding + grandfathered ledger) findes først med 149b. Kvittering: indgår i valg B's
kvittering før prod-GO.

**149b: rehearsal gennemført (2026-09-04) med de forventede tal** (541
`bound_published`, 46 `bound_draft`, 4 `unresolved_text`, 0
`unresolved_identity`; se `docs/evidensbaseret-genimport/legacy-migration-149b-rehearsal.md`).
Batch-status forbliver `finalized` efter batch-reversal — reversal-`reimport_event`
er markøren, fordi `red_begin_reimport`s replay-opslag filtrerer på `finalized`,
ikke på batchens tilstand efter reversal. Valg A og valg B afventer fortsat
projektejerens kvittering før prod-GO.

## BESLUTTET: #152's målte overgangsomkostning og sikkerhedsminimum (2026-08-29)

Et eksternt read-only review af den reviderede #152-spec rapporterede et
produktionssnapshot med 563 eksisterende publication-bindinger, 591 ubundne
2018-20-personnarrativer og kun 8 accepterede `source_persona_identity`-rækker.
Tallene skal genmåles ved en senere production-gate, men konsekvensen er
arkitektonisk allerede klar: eksisterende eksakte bindinger kan fortsætte,
mens hovedparten af nye bindinger og alle direkte DAA-loaderkørsler fryses
fail-closed efter cutover, indtil senere roadmapmål leverer den generaliserede
writer, recordproveniens og fælles identitetsvej.

Append-only publication-events gør også den eksisterende åbne
tombstone-/retentionsbeslutning konkret: `red_slet_person` må efter #152 ikke
slette en projektion og ødelægge eller efterlade inkonsistent historik. Indtil
den permanente beslutning er truffet, afviser den derfor personer med
publication-events tidligt; den granulære withdrawal dækker offentlig
nedtagning af den enkelte biografi.

Designspecifikationen er revideret, så denne omkostning ikke er skjult. Den
tilføjer samtidig et nødvendigt sikkerhedsminimum: én grandfathered
legacy-biografi kan tages ned gennem en særskilt, append-only og reversibel
legacy-withdrawal uden at skjule hele personen eller gøre legacy-teksten
redigerbar.

Projektejeren godkendte 2026-08-29 både denne målte overgangsomkostning som
designpræmis og den midlertidige fail-closed blokering af `red_slet_person` for
personer med publication-events. Godkendelsen autoriserer implementeringsplanen,
men hverken kodearbejde eller production cutover. Før production-GO skal den
friske bestand genmåles; væsentlig afvigelse fra den godkendte konsekvens kræver
ny projektejerbeslutning.

## BESLUTTET: #152 bruger privat recordbinding, append-only publication-versioner og stabil offentlig record-reference (2026-08-29)

Projektejeren har valgt og efter tværgående DAA-arkitekturgennemgang bedt om
revision af
[designspecifikationen](superpowers/specs/2026-08-29-narrative-source-record-key-design.md).

Følgende er den gældende retning for person/DAA-narrativer:

1. `private.narrative_record_publication` forbliver den aktuelle binding mellem
   narrativ og source record. Der tilføjes ikke en privat
   `source_record_id`-kolonne til den offentligt læsbare narrative-tabel.
2. Redaktionelle RPC'er adresserer recorden med `(source_id, record_key)` og
   resolver den private UUID internt. `record_key` er ikke personidentitet.
3. `private.source_record` får en tilfældig, unik og uforanderlig `public_ref`.
   Den gamle publication-bindings `record_ref` bevares for kompatibilitet, men
   er ikke en stabil source-record-reference og bruges ikke i nye eksterne
   links eller citationer.
4. En editionsneutral append-only `private.narrative_publication_event`
   bevarer hver draft-, publicerings-, revisions-, revalidation-, withdraw- og
   reversalbeslutning med konkret tekst-, occurrence-, rendition-, identity-,
   policy- og tilstandshash. Den mutable binding/narrative-række er kun aktuel
   projektion.
5. En publiceret tekst kan ikke ændres gennem almindelig save. En eksplicit
   `Publicér ændring` opretter en ny publiceret eventversion. Drift i tekst,
   provenance, identity, privacy eller policy gør publiceringen stale og
   fail-closed usynlig, indtil en ny eksplicit revision eller revalidation.
6. Publication-change sets fortrydes kun gennem en dedikeret, append-only
   reversal. Den generiske `red_fortryd_change_set` må ikke fortryde narrative
   uden samtidig at håndtere den private publication-projektion.
7. Offentligt synlige ubundne legacy-narrativer bevares kun gennem et eksakt,
   hash-låst og menneskegodkendt grandfathered manifest. Nye eller driftede
   ubundne rækker er usynlige. Exit er eksplicit record-disposition; 2018-20
   får provenance gennem #153 → #149.
8. Eksisterende eksakte C3-/recordbindinger kan fungere som en kontrolleret
   stående redigeringsautoritet for samme record, narrativ og person, når ingen
   accepted identity peger på en anden person. Der konstrueres ingen identity-
   backfill; legacy-broen får disposition ved #151.
9. Web får den fulde recordredaktør. Mobilen får kun den minimale
   capability-aware, fail-closed klientmigration, der kræves for at lukke den
   gamle writer; det parkerede fulde mobilredaktørspor genåbnes ikke.

Beslutningen erstatter for person/DAA-sporet både 2026-07-03-beslutningens
source-nøgle `(subjekt, source_id)` og 2026-08-22-afsnittets illustrative
`public.narrative.source_record_id`-backfill. De historiske afsnit bevares som
beslutningshistorik, men er ikke implementeringskontrakt for #152.

Udrulningen er additiv forberedelse efterfulgt af ét atomisk write-authority-
cutover med hash-låste baselines, RLS-/ACL-gate, gamle writer-revokes og
contract-version som sidste logiske skridt. Beslutningen giver ikke i sig selv
produktions-GO.

## BESLUTTET: model 2 — lagdelt styringsmodel for evidensbaseret genimport (2026-08-25)

[Designspecifikationen](superpowers/specs/2026-08-25-evidensbaseret-genimport-styringsgrundlag-design.md)
vedtages som model 2: fire autoritative dokumenter med adskilte roller og
myndighed. [Visionen](evidensbaseret-genimport/vision.md) fastlægger det stabile
værdigrundlag, [roadmapet](evidensbaseret-genimport/roadmap.md) den bindende
prioritering, [målarkitekturen](evidensbaseret-genimport/teknisk-maalarkitektur.md)
den stabile tekniske retning og [status](evidensbaseret-genimport/status.md) et
dateret, driftfølsomt snapshot. Status er ikke kilde til stabile værdier eller
til tekniske detaljer, som levende kode og schema har ændret.

Vision og målarkitektur må kun ændres ved projektejerens udtrykkelige
beslutning. Roadmaprækkefølgen må kun ændres gennem en begrundet
beslutningspost. Roadmapet har ét aktivt programmål, og nye planer inden for
scope skal opfylde alle seks adgangskrav i roadmapet.

CI-håndhævelse er bevidst udskudt, indtil den manuelle styringsmodel er
afprøvet. Beslutningen giver ingen produktions-GO og ændrer ikke andre
projektspors styring.

## C3 apply: fire ikke-oplagte valg i apply-kontrakten (2026-08-22)

Truffet under revisionen efter Codex sols adversarial review. Alle fire kunne
være gået den anden vej, og begrundelsen er ikke synlig af koden alene.

**1. Tekstgodkendelsen bindes til `text_bundle_sha256`, ikke til manifestet.**
Finalmanifestet binder databasenavn og system identifier, så et prod-bundet
manifest afvises mod rehearsal-basen og omvendt — der er nødvendigvis **to**
databasebundne artefaktforløb. Havde godkendelsen været bundet til manifestet,
skulle mennesket godkende de samme fem tekstdiffs to gange. *Afvist alternativ:*
lade det ske. Begrundelse for at afvise: den anden godkendelse ville blive en
formalitet, man klikker igennem, og en godkendelse man ikke reelt læser er
værre end ingen. Teksten afhænger af record-verbatim og normaliseringsprofil,
ikke af databasen, så bindingen til en teksthash er den ærlige afgrænsning.
Manifestet binder fortsat bundle-hashen, så tekstændringer stadig invaliderer
alt.

**2. Source-record-eksklusivitet håndhæves deklarativt, ikke kun med låse.**
`narrative_record_publication` har unikhed på `narrative_id` og `record_ref`,
men **ikke** på `source_record_id`. En binding, der ikke findes, kan ikke
`FOR UPDATE`-låses, så to writere kan hver oprette en binding for samme record
og begge committe. *Valgt:* partielt unikt indeks
(`WHERE status IN ('draft','published')`) **plus** delt lås på
`private.source_record`. *Afvist alternativ:* kun låsedisciplin — den beskytter
ikke mod en fremtidig writer, der glemmer låsen, og det er præcis den slags
regression, ingen opdager før den rammer produktion.

**3. `phase` og `operation` holdes ortogonale.** Spec'en foreslog
operationskoder `c3_apply|c3_reversal`. Valgt i stedet: `phase='c3'` +
`operation='apply'|'reversal'` som separate felter. Begrundelse: fasen er et
kontrolleret vokabular, senere faser udvider det med en migration, og
sammensatte koder ville betyde, at hver ny fase fordobler antallet af
operationsværdier. `payload_schema_version` tilføjet, så en senere fase ikke kan
flytte C3-eventets betydning.

**4. `haendelse`-kravet nedskaleret fra regenerering til »kræv sættet tomt«.**
`red_upsert_narrativ` opdaterer kun `narrative`; `haendelse` er en
tekstafhængig envejsprojektion uden regenereringstrigger, så en tekstændring
kan efterlade forældede spans. Måling: `haendelse` har **0 rækker** i hele
prod. Derfor bygges ingen regenerering — previewet måler ID-sættet og kræver
det tomt. Kravet skal genbesøges, hvis hændelsesudtrækket køres (#130). Dette
er anvendelsen af princippet om, at målingen afgør *hvor meget der skal bygges*
— ikke om problemet er reelt.

**Metodisk sidegevinst:** tre af rettelserne lå oprindeligt kun i planens
filkort og noter uden et step, der udførte dem — samme fejltype som
reviewfundet H6. En udførende agent følger tasken, ikke indledningen. Enhver
rettelse skal derfor være et step med sin egen test, ikke en note.

## BESLUTTET: evidensbaseret genimport — retning efter afvigelsesvurderingen (2026-08-22)

Fem uafhængige audits + læse-kun prod-måling + Codex-krydskontrol viste, at
programmet pivoterede ~2026-08-06 uden skriftlig beslutning: det byggede er et
provenance-lag for 1939 (592 records, 559 bindinger) oven på juli-loaderens
data — ikke spec'ens evidensbaserede genimport (fortolkningslag 0 rækker,
2018-20 0 records, placement/membership 0 rækker). Fuld opgørelse:
`docs/superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`.

**Tre beslutninger (brugeren, 2026-08-22):**

1. **Fortolkningslaget SKAL fyldes.** Provenance-laget er ikke det færdige
   produkt. Extractor-runner + `proposed`-ingest + vokabular-mapping til
   promotion bygges (#147), med klausulgranularitet som forudsætning (#148).
   Spec §20 er fortsat målet.
2. **2018-20 SKAL have fase A-ækvivalent** (rendition, records, ankre,
   bindinger) uafhængigt af udtræk (#149) — kildeversionerne i UI skal være
   symmetriske. Forudsætter at writeren generaliseres først (#153).
3. **Fase-pakke-modellen er den gældende prod-gate** i stedet for planens
   parallelle DB + samlet cutover: backup (0600+SHA) → restore-rehearsal m.
   byte-identiske baselines → hash-låst manifest → brugergodkendelse → ét
   apply. Kendt svaghed: ingen uafhængig gammel↔ny-sammenligning; kompenseres
   af en »prod = sum af manifester«-afstemning (#156).

**Anti-creep-regler, der følger af beslutningerne:**

- Ingen ny v50-fase (C3-apply, `[NY]`, C1, C2) før narrativ-nøglen (#152) er
  afgjort — C3 må ikke bygges på en model, der skal skiftes.

  **Præcisering 2026-08-22 (efter måling):** reglen blev skrevet på påstanden
  om, at #152 »blokerer« C3. Den påstand var ikke udledt, og målingen viste
  desuden, at der ikke findes nogen unique-constraint på
  `(subjekt, source_id)` — én-pr-udgave bor i `red_upsert_narrativ` og
  læserne, ikke i skemaet. Reglen gælder derfor kun, indtil ét spørgsmål er
  besvaret: **er C3's apply-operationer bindinger eller tekstkirurgi?**
  Bindinger (»pensionér person X, ombind record R til person Y«) er
  fremadkompatible med en senere nøgleændring, og så kan C3 køre først.
  Tekstkirurgi (»føj fragment til 1017's `tekst`, slet 1021's narrativ«)
  skal rulles tilbage af en nøgleændring, og så går #152 først. Afgøres af
  gennemgangen af `2026-08-22-1939-v50-c3-atomisk-apply.md` — ikke af skøn.
  Merge-patologien er til gengæld nu empirisk bekræftet (1017 rummer hele
  record A + starten af record B; 1021 rummer B's hale), så #152's
  berettigelse står, uanset hvordan sekvensen falder ud. Se
  afvigelsesvurderingens §7.6b-c.

  **AFGJORT samme dag — gaten ophæves.** Gennemgangen af
  `specs/2026-08-22-1939-v50-fase-c3-apply-design.md` viser, at C3's fem
  sager er **bindinger, ikke tekstkirurgi**, og dermed fremadkompatible:

  - `TIL`-semantikken kræver, at target-narrativet under lås har
    bindingstilstand `absent` (eller en eksakt draft til samme record), og at
    **ingen anden binding findes for samme source-record** (§Record- og
    publiceringsinvarianter). Hver sag etablerer altså præcis ét
    record ↔ ét narrativ ↔ én person — nøjagtig den invariant, record-nøgling
    ville håndhæve.
  - »Implicit rebind eller withdrawal af eksisterende publiceringer« og »de
    øvrige lowercase-start- eller `[NY]`-sager« er eksplicit **uden for
    scope**. Merge-sagerne (1017/1021, 929/930, 1013/1014, 1791) er parkeret
    og røres ikke; 1017 og 1021 nævnes slet ikke i C3's apply-dokumenter.
  - Teksten skrives ganske vist om, men konvergerer mod netop den tilstand,
    en senere `narrative.source_record_id` ville udtrykke. Backfill efter
    #152 bliver triviel og tabsfri:
    `UPDATE narrative SET source_record_id = pub.source_record_id FROM
    narrative_record_publication pub WHERE pub.narrative_id = narrative.id`.

  **Ny rækkefølge: C3-apply først, #152 derefter.** C3 leverer redaktionel
  værdi nu uden at male os op i et hjørne, og #152 tager bagefter præcis de
  sager, C3 måtte parkere — de bliver først *udtrykkelige* med en
  record-nøglet model i stedet for at kræve tekstkirurgi. Rækkefølgen for
  resten er uændret: #153 (generalisér writer) før #149 (2018-20 fase A).

  Forbehold: verifikationen hviler på designets invarianter og dets
  menneskelige før/efter-tekstgodkendelse, ikke på en optælling af de fem
  konkrete personer — beslutnings-JSON'en ligger i gitignoreret `work/`.
- Ingen ny plan uden henvisning til et §7-punkt i afvigelsesvurderingen eller
  et af issues #147-#158.
- Ingen prod-skrivning uden committet GO-pakke.
- Spor H (heraldik) og M (mobil redaktør) er parkeret, ikke glemt; de får
  ingen issues, før kernen (#147-#150) står.

Øvrige issues fra vurderingen: #151 (én identitetsvej), #154 (global REVOKE
EXECUTE), #155 (DB-hærdning), #157 (dokumentationsdrift), #158 (1939 v50
lukning).

## ÅBENT: hvor langt er bio-udtrækket nået? (2026-08-20)

Målt mod prod, så spørgsmålet »har vi udtrukket de ekstra bio-oplysninger?«
kan besvares med tal frem for indtryk.

**Rygraden er bredt dækket.** 7.197 fakta på 15 typer:

| Mål | Antal | Af 1.811 |
|---|---:|---:|
| Har mindst ét faktum ud over navn | 1.473 | 81 % |
| Har fødsels- eller dødsdato | 1.335 | 74 % |
| Har narrativ | 1.167 | 64 % |
| Har gods (`relation`→`estate`) | 308 | 17 % |
| Har embede (`relation`→`organisation`) | **150** | **8 %** |
| Har kun navn og intet andet | 263 | 15 % |

Typefordeling: navn 1.815 · død 1.137 · fødsel 1.104 · forældrefamilie 922 ·
titel 806 · begravelse 325 · dåb 293 · dekoration 131 · floruit 105 ·
dødsårsag 21 · klosterindgang 8 · tilnavn 5 · forældre_ukendt 4 · overhoved 4 ·
adling 4.

**Det rige lag er derimod aldrig kørt.** `haendelse`-tabellen indeholder
**0 rækker**. Hændelsesudtrækket (`/daa-haendelser`) blev parkeret som issue
#130 til efter genimporten — og genimporten er nu nået til fase D2/C0. Det er
her de daterede begivenheder fra prosaen skulle blive struktur: udnævnelser,
slag, rejser, godskøb, studier.

**Størrelsesordenen af det uudnyttede:** 1939-narrativerne alene er 166.518
tegn prosa fordelt på 576 biografier. Til sammenligning er kun 150 personer
knyttet til et embede, selv om embedsroller optræder tæt i teksten
(amtmand 34, kaptajn 14, gehejmeråd 11, landråd 12 …). Rygraden er udtrukket;
karriereforløbene ligger stadig i prosaen.

**Ikke besluttet:** om hændelsesudtrækket skal køres nu, hvor genimporten har
stabiliseret teksten. Det er forudsætningen for både det levende feed og for
at persondetaljen kan vise mere end leveår — jf. »strukturerede fakta er
usynlige i fladen« nedenfor. De to hænger sammen: der er ingen grund til at
udtrække mere, før der er et sted at vise det, og ingen grund til at bygge
visningen, hvis den kun kan vise fødsel og død.

## UDFØRT: C0-efterkørslen kørt i prod 2026-08-21 — 1017 flyttet til C3 (2026-08-20)

Afgjort ved måling, ikke ræsonnement. Fuld dokumentation i
`docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-afklaringer.md`.

**Person 1017 hører ikke til C0.** Koblingen ville fjerne afsnit B) (149 tegn),
og fragmentet findes ikke ordret nogen steder i korpus. Længste delvise match
er 57 tegn — og det match *er* person **1021's samlede narrativ**, som begynder
midt i det orddelte »Revent- low«. 1021 er altså ikke en post, men halen af
1017's afsnit B). C0's antagelse om at B)-delen »følger med i C3« holder kun
for de sidste 57 tegn; de første ~92 ville forsvinde. **Den rigtige rettelse er
en C3-sammenlægning af 1021 ind i 1017's afsnit B).** Den, der scoper C3, skal
kende dette.

**Person 1297 bliver i batchen.** Det fjernede er »Børn: Ottende Slægtled IIl.«
— en trykt krydshenvisning, samme klasse som de 73 sidemarkører og 499
søskende-ordenstal, fase B allerede fjernede.

**963/967's synligheds-spørgsmål er ikke reelt.** `private` er ikke eksponeret
gennem API'et, `anon` har nul grants på `narrative_record_publication` og får
»permission denied for schema private«, og ser 0 af de 7 staged personer og 0
af deres narrativer. Rækkefølgen mellem »bind record« og »publicér person« er
derfor ligegyldig for synligheden.

**Status 2026-08-21: UDFØRT.** De ni koblinger er skrevet til prod (`change_set 965`, bindinger 550 → 559). Se changelog. 1017/1021 er stadig åben og hører til C3. Det oprindelige forbehold nedenfor er indfriet ved at bygge en dedikeret writer med en gate-kæde stærkere end D2's:
`narrative_record_publication` står ikke i `version_pk_registry`, så en forkert
kobling kan ikke fortrydes — dumpen er eneste udvej. Gate-kæden skal være
stærkere end D2's, og fasen erstatter narrativtekst frem for at sætte et flag.
Det kræver egen spec.

## ÅBENT: 1021 er ikke enestående — 12 narrativer begynder midt i en sætning (2026-08-20)

Scannet over alle 576 1939-narrativer for 1021's signatur (teksten begynder med
lille bogstav = fortsættelse af noget afskåret):

```
 929 (302 tegn)   930 (302 tegn)   956 (433)   977 (79)   1013 (127)
1014 (127)       1021 (57)        1308 (110)  1413 (191) 1771 (58)
1772 (66)        1791 (1439)
```

To iøjnefaldende mønstre: **929/930 og 1013/1014 er par med byte-identisk
tekst** — altså både afskårne *og* duplikerede. Og fem af de tolv (929, 930,
977, 1013, 1014) står på C0's uafklarede-liste, mens 1014 desuden er en af de
7 staged.

Ingen narrativer *ender* på en bindestreg, så modstykkerne er enten allerede
afkortet eller ligger i en anden post, som 1021's gør hos 1017.

**Dette er ikke fikset — kun talt.** Tallet er relevant, fordi det antyder
C3's reelle størrelse: grænsefejlene er en klasse på mindst 12, ikke et
enkelttilfælde.

## ÅBENT: strukturerede fakta er usynlige i fladen (2026-08-20)

**Fundet under D2's web-verifikation.** Persondetaljen viser aldrig en
fakta-liste. `fetchPersonDetail` (`web/src/data/public.ts:171`) henter
narrativ, embeder, godser, medier og evt. kilder — den forespørger **ikke**
`fact`. De eneste fakta, der når skærmen, er:

- `p.years` — leveårene som lille monospace under navnet (`DetailPanel.tsx:88`),
  bygget af cache-kolonnerne `visning_foedt`/`visning_doed`
- `p.title` — titel som badge (`DetailPanel.tsx:96`)

Fødsel, dåb, død, navneformer og alt andet står i basen med afklarede
konklusioner, men har ingen vej til brugeren. Verificeret hele kæden ned for
person 1651 og 1268: fakta findes, konklusioner er `afklaret`, cachen er
udfyldt, `anon` får dem udleveret, og `getAll` paginerer korrekt. Der er
**ingen fejl** — visningen findes bare ikke.

**Hvorfor det først falder i øjnene nu:** fase D2 publicerede 21 gift-ind-
stubbe uden narrativ. Deres sider består af navn + leveår og intet andet, så
det tomrum, der hidtil var skjult bag lange biografier, blev synligt.

Det er en spænding mod invariant 6: prosaen bevares ordret *og* rygraden
udtrækkes selektivt — men kun prosaen vises. For en person uden prosa er der
derfor intet at se, selv om rygraden er der.

**Ikke besluttet:** om persondetaljen skal have en fakta-sektion, og i så fald
om den skal vise konklusionen alene eller også påstand/kilde (evidenskæden).
Redaktionsfladen viser allerede fakta; læserfladen gør ikke.

## ÅBENT: 16 tomme unioner i prod (2026-08-20)

Målt under D2's efterkontrol: 16 af 682 familier har **præcis én partner og
nul børn** — altså et registreret ægteskab uden nogen at være gift med.

```
familie 396→977 · 715→931 · 717→995 · 718→996 · 719→998 · 720→1025
        721→1040 · 723→1112 · 724→1136 · 725→1148 · 726→1198 · 727→1220
        728→1291 · 729→1356 · 730→1367 · 731→1403
```

To ting gør dem mistænkelige frem for blot ufuldstændige:

1. **Familie-id 715–731 er en næsten sammenhængende blok.** Det peger på én
   loader-kørsel, ikke på spredte redaktionelle fejl. Det passer med den
   udestående loader-guard (`navn ≠ ref`), som ellers genskaber
   spøgelses-unioner ved reload — samme klasse som oprydningen i change_sets 3-7.
2. **977, 1220 og 1291 står på C0's uafklarede-liste**, så der er overlap med
   et spor, der allerede er åbent.

**Ingen af fase D2's 21 sidder i en tom union**, og alle 16 fandtes før D2.
Fasen har hverken skabt eller forværret dem. Men de vises formentlig som
"ægteskab" i fladen, og person 996 er en af dem — netop den person, D2's
nye ægtefælle 1487 blev koblet til.

**Ikke besluttet:** om de skal ryddes, eller om loader-guarden skal komme
først, så oprydningen ikke bliver gjort om ved næste reload.

## RETTET OG DEPLOYET: `red_slet_person` var brudt for alle 551 narrativ-bundne personer (2026-08-20)

**Symptom:** `red_slet_person(p_person_id)` fejler med

```
update or delete on table "narrative" violates foreign key constraint
"narrative_record_publication_narrative_id_fkey"
```

for enhver person, hvis 1939-narrativ har en binding i
`private.narrative_record_publication`. Det er **alle 551**, fase B bandt —
altså hovedparten af 1939-bestanden. Redaktørfladens slet-knap vil fejle på
dem alle.

**Årsag:** funktionen er ældre end bindingstabellen (som kom med v50-arbejdet
i august) og kender den ikke. Dens sletteorden går
citation → assertion → fact/relation → narrative → person, og FK'en fra
`narrative_record_publication.narrative_id` blokerer narrativ-sletningen.
`red_slet_person_preview` er tilsvarende ufuldstændig: den rapporterer fakta
og relationer, men hverken narrativer eller bindinger.

**Opdaget** da person 975 skulle pensioneres (2026-08-20). Dér blev det løst
ved at slette bindingen først i samme transaktion — en engangsomgåelse, ikke
en rettelse.

**Rettelse (skrevet 2026-08-20, IKKE kørt mod nogen base):** begge funktioner
er genudgivet som en ny blok i bunden af `db-migrations.sql` og opdateret i
`schema.sql`. De tidligere blokke (linje 451 og 1714) står urørt som historik —
det er husets konvention i en replayet migrationsfil, og den sidste definition
vinder. `red_slet_person` fjerner nu bindingerne før narrativerne.

Gennemgangen fandt **to blokerende fremmednøgler mere**, som noten ovenfor ikke
kendte: `person_slaegt_membership` og `person_lineage_membership` har begge
`person_id NOT NULL` uden `ON DELETE CASCADE`. De ryddes nu i samme omgang.

`red_slet_person_preview` returnerer nu også `antal_narrativer`,
`antal_bindinger` og `antal_medlemskaber`, og begge slet-flader (web
`Redaktion.tsx`, mobil `SletBekraeftSheet.tsx`) viser tallene — ellers var
udvidelsen usynlig for redaktøren.

**Fælde værd at huske:** begge funktioner er `SECURITY DEFINER` med
`SET search_path=public`, så `private.`-tabeller **skal** skema-kvalificeres.
Uden præfikset fejler funktionen ved *deploy* med »relation does not exist«,
ikke ved kørsel.

**Status:** deployet til prod 2026-08-20 efter backup. Alle tre nye
db-verify-blokke bestod, og sletningen er verificeret på ægte data (person 924
med kildebinding, i en rullet-tilbage transaktion). Eneste udestående er
`get_advisors(security)`, som kræver dashboard-adgang — en SQL-lint for
`search_path` på SECURITY DEFINER-funktioner gav 0 fund.

**Bemærk om semantikken:** bindingen siger »dette narrativ stammer fra denne
kilderecord«. Når narrativet slettes, er udsagnet meningsløst, så bindingen
skal med. `private.source_record` skal derimod **aldrig** røres af en
person-sletning — registreringen af, at teksten står på siden, er stadig sand.

---

## ÅBEN: hvad skal en person-sletning gøre ved `source_persona_identity`? (2026-08-20)

**Spørgsmålet dukkede op** under rettelsen af `red_slet_person` ovenfor.
`private.source_persona_identity` og `private.source_persona_identity_event`
har begge `canonical_person_id` med fremmednøgle mod `person(id)` og **uden**
`ON DELETE`. De blokerer altså en sletning på præcis samme måde som
bindingstabellen gjorde — men de er bevidst **ikke** rørt af rettelsen.

**Hvorfor ikke:** en source persona er bogens beskrivelse af en person — en
påstand fra kilden, ikke et faktum om vores kanoniske person. At slette den,
fordi vi sletter personen, er samme kategorifejl som at slette
`private.source_record` (invariant 1: påstande overskrives aldrig).
`_event`-tabellen er desuden et append-only beslutningsspor.

Nulstilling er heller ikke en udvej: `source_persona_identity_target_check`
kræver at `canonical_person_id IS NOT NULL` præcis når
`decision_status='accepted'`. Man kan altså ikke nulstille feltet uden samtidig
at flytte beslutningen til fx `superseded` — og *det* er en redaktionel
afgørelse (»denne identifikation gælder ikke længere«), ikke en teknisk
oprydning der hører hjemme i en slette-rutine.

**Konsekvens indtil videre:** sletning af en person, som har en *accepteret*
persona-identifikation, vil stadig fejle på fremmednøglen. Det rammer ikke de
551 (de blokerede på bindingen), men skal afklares før persona-materialiseringen
bruges bredt.

**Rettelse efter review (Codex sol, 2026-08-20):** forslag (a) — »supersede og
tillad så sletning« — **virker ikke**. `source_persona_identity_event` er
append-only (kun en `BEFORE INSERT`-trigger, ingen UPDATE/DELETE-sti), og hver
historisk event bærer sin egen `canonical_person_id` med fremmednøgle mod
`person`. En ny `superseded`-event fjerner altså ikke den gamle accepterede
events reference. Konsekvensen er skarpere end først noteret: **har en person
én gang været mål for en accepteret identitetsbeslutning, kan den aldrig
hard-slettes** — uanset hvad `red_slet_person` gør. Det er en egenskab ved
v50'ens auditdesign, ikke en fejl i slette-rutinen.

**Valgmuligheder, revideret:** (b) lade `red_slet_person` afvise tidligt med en
forståelig domænefejl (»personen har en accepteret kilde-identifikation — træk
den tilbage først«) i stedet for en rå FK-fejl. Det er ærligt og billigt, men
løser ikke det underliggende. (c) soft-delete/tombstone af kanoniske personer,
så identitetshistorikken kan pege på et bevaret id. (d) et auditdesign hvor
historiske person-id'er bevares uden blokerende fremmednøgle.

**Dette er et arkitekturvalg, ikke en oprydning** — (c) og (d) ændrer hvad
»slet en person« overhovedet betyder i modellen, og bør besluttes bevidst.

**Status:** (b) er implementeret — `red_slet_person` afviser nu tidligt med
`PERSON_HAR_KILDEIDENTITET` i stedet for at lade en rå FK-violation slippe ud
midt i en halvt udført sletning. Det er en ærlig fejlbesked, ikke en løsning.

Gaten fyrer **præcis** når fremmednøglen alligevel ville blokere, så den gør
ingen sletning umulig, der før var mulig. Men den rejser et spørgsmål, som ikke
kan besvares uden et opslag i basen: **hvor stor en del af de 551 narrativ-bundne
er også persona-bundne?** De er i så fald fortsat ikke-slettelige — ikke på grund
af bindingen, som nu er rettet, men på grund af det uforanderlige beslutningsspor.
V50-materialiseringen skrev `identity_status: "accepted"`, og cutover-kontrollen
omfattede personae, så overlappet er sandsynligt, men ikke målt.

Kør dette mod prod for at afgøre, hvor meget rettelsen faktisk frigør:

```sql
SELECT
  count(*)                                              AS narrativ_bundne_personer,
  count(*) FILTER (WHERE EXISTS (
    SELECT 1 FROM private.source_persona_identity_event e
     WHERE e.canonical_person_id = nb.person_id))       AS blokeret_af_kildeidentitet
FROM (
  SELECT DISTINCT n.subjekt_id AS person_id
    FROM public.narrative n
    JOIN private.narrative_record_publication p ON p.narrative_id = n.id
   WHERE n.subjekt_type = 'person'
) nb;
```

**MÅLT mod prod 2026-08-20 (read-only):**

| | |
|---|---:|
| narrativ-bundne personer | **550** |
| heraf blokeret af kilde-identitet | **8** |

550 og ikke 551, fordi person 975 blev slettet samme morgen — tallet stemmer med
den kendte historik. **Rettelsen frigør altså 542 af 550.** De 8 er dem fra
v50-cutoveren, hvis integritetskontrol netop omfattede personae.

**Konsekvens for tombstone-valget:** det haster ikke. Det angår 8 personer, ikke
hovedparten af bestanden, og hard delete med dokumenteret forbehold er derfor et
holdbart valg indtil videre. Bemærk dog at tallet vokser, efterhånden som flere
identitetsbeslutninger accepteres — det er ikke et engangstal, og det bør måles
igen før den næste udgave lægges ind.

**Anbefaling fra arkitekturvurdering (fable, 2026-08-20): vælg (c), i varianten
tombstone + udtømning.** `red_slet_person` ville da tømme alt det, den allerede
sletter (fakta, evidenskæde, narrativer, bindinger, medlemskaber, external ids,
`visning_*`), men bevare den nøgne person-række med et eksplicit slettet-state,
så `canonical_person_id`-fremmednøglerne forbliver gyldige. Begrundelsen ligger
i modellens egne invarianter: personen er reelt en *konklusion*
(`datamodel-oversigt.md`), og rettelse sker ved ny tilstand ovenpå — aldrig ved
destruktion (invariant 1). Hard delete er anomalien i denne model, ikke normen.
Huset praktiserer i forvejen tombstones: 1939-reversal sletter ikke personer,
den sætter `staged=true, status='reimport_1939_reversed'`.

GDPR (invariant 8) taler ikke imod: en udtømt tombstone er et nøgent surrogat-id
uden persondata. Den reelle eksponering ved en sletteanmodning ligger i
`private.source_persona`/`source_record` — bogens egen tekst — og den består
uanset om person-rækken slettes hårdt. Hard delete ville altså ikke have løst
det GDPR-problem, tombstonen får skylden for.

**Vigtigste indvending mod (c):** tombstones skal ekskluderes konsistent i
*alle* læseflader — RLS, anon-RPC'er, finderen, `samme_som`-collapse, tællinger.
Én overset gate genopliver en »slettet« person offentligt. `staged` kan ikke
genbruges (det betyder kuratering, ikke sletning), så det kræver et nyt,
distinkt state plus en audit af samtlige læsestier og lockstep-opdatering af
web og mobil. **Beslutningen er ikke truffet — den afventer brugeren.**

---

## Hændelses-ankre: subjekt/objekt-asymmetrien (2026-08-20)

`red_slet_person` samler relationer hvor personen er **subjekt eller objekt**,
mens hændelses-loaderen (`load_haendelser.R`) forankrer hændelser efter
**subjekt alene**. En relation Q→P kan derfor bære en hændelse under *Q's*
narrativ, som ikke cascade-slettes når P's narrativer forsvinder — og
`haendelse.relation_id` har fremmednøgle uden `ON DELETE`. Sletningen af P ville
strande på Q's hændelse.

**Løsning:** ankeret løsnes (`SET NULL`) i stedet for at slette en anden persons
hændelse. Hændelseslaget er per design regenererbart, og begge kolonner er
allerede `skip_cols` i versioneringen, så en nulstilling er konsistent med
husets eget valg om ikke at versionere dem.

`haendelse.fact_id` tages med for symmetri, men den sti er **ikke** påvist:
loaderen filtrerer fakta til narrativets egen person, så et krydsanker kan i dag
ikke opstå. Det er billig forsikring mod en fremtidig writer, ikke en rettelse
af en kendt fejl.

---

## Narrativ-bindingens tab ved fortryd er publicerings-tilstand, ikke evidens (2026-08-20)

`private.narrative_record_publication` kan ikke registreres i
`version_pk_registry`: registret er nøglet på skemaløst `tabel TEXT`,
trigger-loopet bruger `%I` uden skema, og `_version_pk_where` slår kolonner op
med `table_schema='public'` hårdkodet. Sletning af en binding giver derfor ingen
`change_event` og kan ikke fortrydes.

**Vurdering:** koblingen narrativ→kilderecord er *funktionelt* rekonstruerbar for
1939-flowets rækker — labels dannes efter en deterministisk konvention, og
`record_key` er unik pr. kilde. Reelt tabt er derimod `record_ref` (en
`gen_random_uuid()`, UNIQUE og uforanderlig — en genopbygget binding ville mønte
en **ny** offentlig identitet), `published_at`, og de frit kalder-leverede labels
på den manuelle publiceringssti.

**Det er ikke tabt evidens** i invariant 1's forstand: evidensen er
`private.source_record`, som aldrig røres. Det er tabt *publicerings-tilstand*.
Alvoren i dag er lav — `record_ref` eksponeres for `anon` via
`public_person_bio_source_versions`, men ingen konsument fastholder den (kun
listenøgle og sorterings-tiebreak i web/mobil). Alvoren bliver reel, hvis
`record_ref` nogensinde bruges som citérbar reference udadtil — hvilket er
præcis, hvad den er designet til. **Bør genbesøges før den bruges eksternt.**

---

---

## Fase C1 udskudt: værdien udløses først af den anden udgave (2026-08-19)

**Beslutning:** C1 (promovering af 1.078 literal fakta + 212 ægteskaber til
det private fortolkningslag) bygges ikke nu. Fase D tages i stedet.

**Hvad målingen viste.** Programplanen kaldte C1 »mekanisk: manifest + writer
efter fase A-mønstret«. Tre tal modsiger det:

- `private.interpretation` og `private.interpretation_promotion` er **tomme**
  (0 rækker). Der er intet at promovere; fortolkningerne skal først skabes.
- Promotion-reglerne dækker **979 af 1.078** fakta (fødsel/titel/død). Dåb (50)
  og begravelse (49) mangler regler; alle **212 ægteskaber** mangler en
  regelklasse, fordi de fem eksisterende regler er `person.*`-prædikater mod
  `assertion`, mens et ægteskab er en relation.
- Fakta er **allerede kildebundne**: 3.211 citations mod DAA 1939, alle med
  `assertion_id`, fordelt på 87 sider. De 1.233 uden `citat_tekst` er
  hovedsagelig `forældrefamilie` (356, en relation uden naturligt citat) og
  `navn` (337, hvor citatet ville gentage værdien). Indholdsfakta — fødsel,
  død, titel, vielse — har citat i 366-369 tilfælde og mangler kun i 80-93.

**Hvad der reelt mangler** er koblingen fra faktum til den granulære
`source_record` (posten på siden), som narrativerne fik i fase A og B. Én side
rummer flere personer, så »DAA 1939, s. 574« er grovere end »posten om
Ferdinand, s. 574-575«. Det betyder lidt for én udgave og meget når 2018-20
skal stilles op mod 1939.

**Hvorfor udskydelsen ikke koster noget.** Fase A's 592 source records ligger
allerede uforanderligt i prod. Fakta kan bindes til dem når som helst —
rækkefølgen er fri. Det omvendte gælder ikke: bygger vi regelklassen for
ægteskaber nu, låser vi et design **før** vi har set 2018-20's ægteskabsdata.
Døren lukker sig af at gå i gang, ikke af at vente.

**Hvis C1 alligevel skal give noget nu:** det billigste med reel effekt er at
udfylde de 80-93 manglende citater på fødsel og død — de tal folk læser efter
— uden at røre fortolkningslaget og uden DDL.

---

## Grænsekontrollen som redigerbar tekst: tre valg der bærer resten (2026-08-09/10)

**Annoteringssyntaksen må ikke dele tegn med det, den annoterer.** Kildeteksten
indeholder allerede 86 `### PAGE nnnn ###`-linjer, så fladens egne markører fik `===`.
Havde begge brugt `###`, ville integritetskontrollens strip fjerne bogens egne linjer
sammen med vores — og en sletning i kilden kunne passere ubemærket. Reglen er derfor
skarp: `===` er fladens, `###` er bogens, og strip matcher eksakte navngivne mønstre,
aldrig et catch-all.

**Tavshed er godkendelse for den enkelte skæring — men ikke for en side.**
Brugervalgt: en urørt markør er en accepteret skæring (446 klik ville flytte den
gamle arbejdsbyrde ind i en ny flade). Eksporten registrerer derfor *ændringen* mod
det forudsatte sæt, ikke en dom pr. grænse. Men "antal manglende sider" kan kun være
ærligt, hvis noget markerer en side som set, så sidevisningen fik en kvittering pr.
side: 86 klik, ikke 446 domme. Kvitteringen er deaktiveret mens siden har en fejl.
*Fravalgt:* auto-besøgt (et hurtigt gennemblad ville tælle som en gennemgang).

**Identitet skal være entydig, ikke bare trykt.** Sidefremskridtet blev først nøglet
på det trykte PDF-sidetal — men bogens to sidste sider bærer begge tallet 598, så to
sider delte én plads: 86/86 var uopnåeligt, og kvittering for den ene fik den anden
til at fremstå gennemgået. Nøglen er nu kildesiden (1-86). Samme mønster som
lokal_id-valget 2026-07-30: alt beregnet eller genbrugt taber, kun entydige etiketter
står fast. Gamle eksporter oversættes fail-closed — et tvetydigt tal markerer ingen
side, fordi et gæt ville påstå at en uset side var gennemgået.

**Fladen giver review-/fil-GO, ikke materialisering.** Grænsen fra 2026-08-08 står:
afløsning af accepteret evidens kræver en selvstændig, autoriseret operation. Runde 2
— hvem der ejer hvilket stykke — er bevidst adskilt fra runde 1, så "hvor brydes
teksten" (afgøres af teksten selv) ikke blandes med "hvem er det" (kræver bogens numre).

## Menneskevalg: approval er identitetsankeret; råbroen er valgfri (2026-08-06)

**Besluttet:** Et valideret menneskevalg bindes til det eksakte, hash-fastlåste
Calamari-span med `approval.kind = human_approved_span_v1`. En invariant
Calamari↔rå-OCR-occurrence-bro registreres, når den findes entydigt, men er ikke
et krav for et menneskegodkendt valg: mennesket har allerede truffet
identitetsafgørelsen, og råbroen tilføjer redundant proveniens. Automatiske
afgørelser beholder kravet om dual-rendition-evidens. Globale krav om entydigt
ejerskab, kandidat-id-injektivitet og ikke-overlappende spans er uændrede.

**Evidence- og GO-grænse:** Adapteren kræver et komplet source-bundet
base-evidence-bundle og erstatter kun samme evidensfrie baseline-key med en
valideret human-entry. Task-5-filen `{decisions, audit_results}` og dette composed
bundle joines i `prepare_review_queue_1939.py`. Der findes ingen approval-capable
privat coverage-materializer; workflowet stopper ved review-/fil-GO. En senere
materialisering kræver selvstændigt design, godkendelse og replay.

**Udskudt backlog:** Slutarkets store occurrence på side 597–598 resegmenteres
ikke nu. Approval-stien gør den manglende invariante råbro ikke-blokerende, mens en
resegmentering ville ændre occurrence-identiteter og alignment på tværs af de
fastlåste artefakter uden at tilføje identitetssikkerhed til de allerede
menneskegodkendte valg. Arbejdet genåbnes kun, hvis senere automatisk behandling
kræver finere occurrence-grænser.

## Hvad der bevidst IKKE blev et link (2026-08-01)

**Besluttet ved link-konverteringen af web-fladen.** Reglen er "ingen fabrikerede
links": et element får kun `href` hvis målet faktisk er adresserbart i
URL-grammatikken. Tre fravalg — ret dem ikke uden at læse hvorfor:

- **`RelateView`s stitrin** (`components/RelateView.tsx`) bruger `focusOnly`:
  venstreklik skifter fokus **uden** at navigere, fordi Slægtskabs-fanen bevarer
  sit mode. Et `href` ville stå i browserens statuslinje og love en side klikket
  ikke går til. Rigtige næste skridt er ikke et anker, men en beslutning om
  hvorvidt `/relate/<aId>/<bId>` skal være adresserbar (delbare slægtskabs-links).
- **Kort-punkter** (`components/OverviewMapView.tsx`) navigerer via kort-rendererens
  `onPointPress`-callback; rendereren kan ikke levere ankre. Teknisk undtagelse.
- **Feed-kort af typen `slaegt`, `forbundet`, `samle`** får `null` fra
  `hrefForCard`: deres mål (A/B-parret, browse-tilstanden) ligger uden for
  URL-grammatikken.

**Åben opfølgning:** fire håndbyggede `/redaktion/person/${id}`-strenge
(`Redaktion.tsx`, `OcrKildepanel.tsx`, `PersonKvalitetsark.tsx` ×2) strider mod
den regel `data/nav.ts` opstiller for sig selv. Rettelsen kræver at
`redaktionPath`/`parseRedaktionPath` flyttes ud af `Redaktion.tsx` — at
eksportere dem derfra ville give en import-cyklus, fordi `Redaktion.tsx`
importerer begge komponenter. Bevidst udskudt, ikke overset.

## Kanonisk låseorden + id-gulv over versioneringshistorik (2026-07-31)

**Besluttet (af sol-review-cyklussen):** (1) Alle scripts/migrationer der LOCKer flere
model-tabeller bruger ÉN kanonisk rækkefølge — forældre-først, relation FØR assertion
(RPC'ernes naturlige skriveorden; definitionen bor ved `id_tables` i load_daa.R).
Inversion mellem samtidige LOCK-statements = deadlock. (2) Id-allokering bruger aldrig
rå `max(id)` som gulv men `GREATEST(levende max, versioneringshistorikkens max pr. tabel)`
— rækker slettet via red_slet-* efterlader change_events med højere id'er end levende max,
og id-genbrug dér "genopliver" historik på nye, forkerte rækker (fundet empirisk af
--replace-dry-runens invariantvagt). Gælder alle fire loadere + sekvens-setval i migrationer.

## Replay-laget: source-scoped replace, ikke generaliseret journal (2026-07-30)

**Besluttet (bruger-valg efter helhedsreview, issue #123):** re-load af en udgave bevarer
person-id'er via record_key-match mod identitetsregisteret; kun source-ejede rækker (uden
change_event-spor) erstattes, redaktionelt arbejde består automatisk. **Fravalgt:**
generaliseret journal-mønster (reload-invariante ankre i alle ~60 red_*-RPC'er + migration
af eksisterende samme_som-change_sets) — (b)'s forudsætninger var netop færdigbygget
(register 514/514, book_post_id = record_key, perturbationstestet reconcile), mens (a)'s
hovedomkostning netop var migrationen. Fuldt design inkl. forudsætninger (record_key-
backfill i prod, IDENTITY-migration, dry-run-match-rapport først) og åbne spørgsmål:
`docs/replay-source-scoped-design.md`. Ledsagende gates landet samme dag: #124 (reset
tømmer versioneringshistorik), #125 (navn≠ref-guard), #126 (gate-manifest).

## 1939-lokal_id: bogens trykte firleddede adresse — der tælles ikke, der læses (2026-07-30)

**Besluttet (bruger-anvist):** en 1939-posts identitetsadresse er `{linje}.{slægtled}.{afsnit}.{nr}`
(fx `IV.Ottende.II.6`) — alle fire led læst af bogens egne overskrifter og numre.

**Forkastede alternativer, begge på måling — ikke på smag:**
- *Position på siden:* en indskudt post forskyder alle efterfølgende; reconcile accepterer
  eksakte hit, så post N+1 arver tavst post N's id (perturbationstesten beviste det).
- *Beregnet gruppeindeks* (`G7.3`): 127 nabogruppe-par deler trykt nr + side, så ét forskudt
  indeks fejl-tildeler i stor stil. Samme sygdom, gruppeniveau.

Mønstret efter tre faldne kandidater: alt BEREGNET (løbenummer, position, indeks) taber
forskydningstesten, fordi én opdaget fejl omnummererer resten. Kun trykte etiketter står fast.
Enhver fremtidig lokator-kandidat skal bestå perturbationstesten (nul FORKERTE, ikke nul
tvetydige) FØR entydighed overhovedet måles.

## Register-broer valideres mod facit man allerede ejer (2026-07-30)

Om-nøglingen af identitetsregisteret (LLM-æra-lokatorer → trykt skema) brugte tre
evidenskilder, hver med indbygget kontrol: (1) tekst-anker — gammel og ny post kommer fra
samme kildetekst, så normaliserede vinduer skal stå ordret (l↔1-OCR kollapses); (2) bogens
trykte nummer som uafhængigt krydstjek — BLOKERENDE ved én uenighed (målt 445/445 enige);
(3) afkodning af de gamle LLM-id'ers indlejrede sti — men først efter kalibrering mod de
437 allerede-sikre match (0 hårde fejl på 281 afkodelige). Princip: et signal uden målt
fejlrate er et gæt; injektivitet håndhæves (to gamle om samme nye adresse → begge til
menneske). Alternativ forkastet: score-baseret matching uden margin/injektivitet (Codex-
reviewets hovedindvending mod første udkast).

## Delmængde-forældre: konflikt eller blot mindre detalje? ÅBEN (2026-07-29)

`collapseSameAs` sætter to udgavers version af samme person i karantæne når deres forældresæt er
"forskellige ikke-tomme sæt". Spørgsmålet: skal `{far}` mod `{far, mor}` tælle som **konflikt**
(som i dag) eller som **forenelig, blot mindre detaljeret** — sådan som vi allerede har besluttet
for datointervaller?

**Målt 2026-07-29** på de 142 resterende karantæner (efter dubletoprydning og ~119 forældre-match):

| Type | Antal | Betydning |
|---|---|---|
| **Delmængde** — den ene udgave siger mindre | **38** (27 %) | 1939 nævner kun faren; 2018-20 har begge. Den fælles forælder er allerede matchet |
| **Delvist** — én fælles, hver side har én ekstra | 79 (56 %) | Blandet; nogle bliver delmængder når den ekstra forælder matches |
| **Disjunkt** — ingen fælles forælder | 25 (18 %) | Overvejende stavevarianter (`Iven`/`Iwan`, `Hartvig`/`Hartwich`) der endnu ikke er matchet |

To ting følger af tallene:

- **De 38 kan aldrig løses ved matchning.** Der findes ingen 1939-person at koble moderen til —
  bogen nævner hende ikke. De bliver stående uanset hvor meget matcharbejde der lægges i.
- **De 25 disjunkte kan.** Der er præcis 25 umatchede forældre tilbage; tallene passer på hinanden.
  Matches de, bliver parrene til delmængder — altså flytter de bare over i den første kategori.

### Argumentet for at kalde det forenelighed

Det er samme mønster som datoerne, hvor vi målte at bøgerne næsten aldrig er uenige — de er
forskelligt præcise — og hvor reglen blev: *indeholdelse = enige, vis den fineste*. `{far}` ⊂
`{far, mor}` er den samme relation. Konsekvens hvis kriteriet ændres: **38 grupper folder sammen
med det samme**, og matcharbejdet får en langt lavere bund.

### Argumentet imod

Datointervaller er entydige; forældresæt er det ikke. To forskellige mænd ved navn Siwert med hver
deres børn ville også folde sammen, hvis 1939 kun nævnte faren. Karantænen er i dag den
konservative default — den gætter ikke, den parkerer — og den har vist sig at ramme rigtigt hidtil.

### Hvad der skal afgøre det

Ikke om delmængde *kan* betyde enighed, men om der findes en **diskriminator** der skiller de to
tilfælde. Kandidater, ingen af dem undersøgt:

- kræv at den fælles forælder er matchet **og** at barneparret i forvejen er enigt om navn og
  datoer (så forældresættet ikke er eneste bevis)
- begræns til det konkrete mønster: præcis 1 forælder på den ene side, præcis 2 på den anden, hvor
  den ene er fælles — altså "moderen er ikke nævnt", ikke vilkårlige delmængder
- lad det være et redaktionelt valg pr. tilfælde frem for en global regel: vis dem som en egen
  kø ("den ene udgave nævner kun én forælder — er det samme person?")

**Konsekvens for læseren så længe det står åbent:** de 38 vises som to personer i stedet for én.
Det er synligt, men ikke forkert — og at folde dem forkert sammen ville være værre.

Beslægtet: dato-reglen i
`docs/superpowers/specs/2026-07-28-redaktoer-udgavefaner-design.md` §"Hvornår er to udgaver uenige
om en dato?".

## Model-tier til GPT: terra som default, sol til eskalering (2026-07-29)

Brugervalg efter kalibrering, jf. `tools/kalibrering/` og
`docs/reviews/re-ekstraktion-forberedelse-2026-07-29.md`. Erstatter ikke
juni-beslutningen om Claude-tierne; den gælder GPT-sporet til
1939-re-ekstraktionen, valgt for at holde tokenforbruget ude af Claude-konteksten.

**Kalibreringen:** 30 poster, stratificeret hvor det gik galt sidst — 10 gravsatte
omtaler (facit kendt uden bogopslag), 10 med flere ægteskaber, 10 tætte biografier.
Samme frosne prompt til begge modeller.

| | `gpt-5.6-terra` | `gpt-5.6-luna` |
|---|---|---|
| Ugyldig JSON | 0 | 0 |
| `er_omtale` på stratum A | **10/10** | **10/10** |
| `kilde_span` ordret (blokerende, R7) | 96/96 | 82/82 |
| Ægteskaber m. partnerdata | 26/26 | 26/26 |
| `koen_kilde` sat | 24/30 | 18/30 |
| **Embeder fundet** | **59** | **35** |
| Godser fundet | 67 | 67 |

- **Besluttet: `terra` på max effort som default, `sol` til poster valideringen flagger.**
  Eskaleringsmønsteret findes allerede (`escalate_merge.py`).
- **Begge modeller løser rygraden.** Ingen ugyldig JSON, ingen opfundne `kilde_span`,
  alle ægtefæller dekomponeret, og begge fandt samtlige ti omtaler. Kontrakt-ændringen
  bar mere end modelvalget gjorde.
- **Forskellen er udtræksdybde:** terra finder 69 % flere embeder og mærker køn-kilden
  oftere. Det er samme dimension juni-beslutningen målte for Haiku — klassifikations-
  nuancer, ikke grundlæggende korrekthed.

⚠ **Forbehold der ikke er lukket:** embede-forskellen (59 vs 35) er et *antal*, ikke en
korrekthed. Om terras 24 ekstra er rigtige fund eller falske positiver kræver et
menneskeligt facit på C-strata. Brugeren valgte bevidst at gå videre uden — beslutningen
hviler derfor på at terra ikke er *dårligere* på nogen målt dimension, ikke på at de
ekstra embeder er verificeret. `work/kalibrering/uenigheder.md` har de 24 uenige poster,
hvis det senere skal afgøres.

**Addendum 2026-07-29 (uenigheds-gennemgang, bruger-godkendt: terra + to betingelser):**

- **er_omtale UDEN FOR stratum A afgjort mod kendt facit** (B/C-poster ER rigtige
  personer): terra kasserede 4 (alle med afhugget tekststart), luna 1. Ingen af dem
  satte `tekst_afhugget` en eneste gang. Det var kalibreringens alvorligste fund —
  den dyreste fejltype i omvendt retning (rigtige mennesker gravsat).
- **Prompt-hærdningen virker, empirisk:** afhugget-sektionen i `extract-prompt.md`
  (skrevet fra netop disse fund) blev kontrolkørt med terra på de 5 fejlposter —
  **5/5 nu korrekte** (`er_omtale=false` + `tekst_afhugget=true`), se
  `work/kalibrering/terra-kontrol/`.
- **Embede-forbeholdet delvist lukket ved stikprøve:** terras 5 ekstra embeder på
  B:275 (Hofjkr., Hof- og Kancelliraad, Amtmand, Landraad, Oberst) er alle ordrette
  citater fra prosaen — luna fandt 0 af dem. Merudtrækket er ægte fund, ikke støj.
  (Stikprøve, ikke fuldt facit — resten af forbeholdet står.)
- **Betingelse 2 implementeret som R10-gate** (`validate.tjek_omtale`):
  `er_omtale=true` på en post segmenteringen har forankret til sit EGET trykte nummer
  er en selvmodsigelse (omtaler har intet eget nummer) → blokeres til menneskelig
  afgørelse, aldrig auto-gravsat. Fail-soft uden anker-signal.
- Bifund: `er_omtale`/`tekst_afhugget`/`koen_kilde` manglede i validates `ALLOWED_TOP`,
  så R5 ville have flagget ethvert kontrakt-konformt udtræk. Rettet.
- C:3 og C:29 viste sig at have IDENTISK gruppetekst — det kendte delt-narrativ-problem
  ramte selve kalibreringsbatchen (2 af 10 C-poster). Re-segmenteringen fjerner den
  fejlkilde ved roden.

**Kalibreringens største udbytte var ikke modelvalget.** Den afslørede en fejl i
kontrakten: `er_omtale`-kriteriet sammenblandede "dette er en omtale" med "denne tekst
er klippet forkert", så terra loyalt markerede fire rigtige personer som omtaler. Ved
fuld kørsel var de forsvundet tavst ud af korpus. Rettet med et selvstændigt felt
`tekst_afhugget` (prompt-version 2026-07-29b); kontrolkørsel bekræftede at alle fem
omstridte poster nu klassificeres rigtigt uden tab af data. **60 kald fandt en fejl der
ellers ville være ramt 515 poster.**

## 1939-posternes permanente løbenummer: ÅBEN, og bevidst ikke sat endnu (2026-07-28)

Brugerspørgsmål: er der en plan for at 1939-posterne får et permanent løbenummer
(`person_external_id.record_key`)? **Nej — det er noteret tre gange samme dag af to
uafhængige arbejdsspor, men aldrig planlagt.** Denne sektion findes for at det ikke skal
genopdages en fjerde gang.

**Hvorfor DAA 2018-20 kunne backfilles, og 1939 ikke kan.** 2018-20's `record_key` blev
udledt af at filnavnene i `data/extracted-2026-06-18/*.json` selv *er* nøglen — identiteten
fandtes i forvejen, den var bare ikke skrevet ind i basen. 1939 har ikke det: løbenumrene
1–539 tildeles af `convert_1939_stamtavle.py` som en gennemløbende tæller hen over hele
bogen. Konverterens egen header fastslår at nummer-ankeret derfor er "reelt dødt".

- **Beslutning: ingen nøgle før korpuset ligger fast.** En permanent nøgle skal overleve at
  bogen segmenteres om. Re-segmenteringen 2026-07-26 flyttede postgrænser i 216 narrativer;
  havde numrene været brugt som nøgle, ville redaktionelle rettelser bagefter have hængt på
  de forkerte personer. Fraværet af `record_key` er derfor **det rigtige valg indtil videre**,
  ikke en forglemmelse.
- **Konsekvens i dag:** 1939 kan læses og bruges som kilde — `red_set_konklusion` tager kun
  et assertion-id og har intet ankerkrav, så en 1939-oplysning kan udmærket vælges som den
  gældende. Kun `red_ret_ocr_felt` (transskriptionsrettelse) er spærret, fordi den forankrer
  på `(import_key, record_key)`.
- **Rækkefølge, når det tages op:** (1) dubletgennemgangen fra
  `docs/reviews/dubletter-1939-2026-07-27.md` — ~30 par betyder at nogle poster skal væk, og
  man giver ikke nøgler til poster der forsvinder; (2) nøglen på et korpus der ligger fast;
  (3) redigerbarhed af 1939.
- **Kandidater, ikke undersøgt:** artefaktet bevarer postens egen nummerering inde i sin
  gruppe (`lokal_id`) og en intern post-id (`_id`) — begge fra kilden frem for opfundet af
  konverteren. Om nogen af dem er stabil på tværs af re-segmentering er præcis det
  spørgsmål en plan skal besvare.
- - **⚠ Artefaktet og prod er drevet fra hinanden (opdaget 2026-07-29).** `linked_clean.json` og
  `clean_1939.json` indeholder begge **539** poster; prod har **515** efter at 23 dubletter blev
  slettet. Sletningerne findes **kun i basen**. `person_external_id` står på loaderens reset-liste
  (`load_helpers.R`), så en genindlæsning fra artefaktet ville **genskabe alle 23 dubletter** og
  efterlade enhver nøgle mintet i mellemtiden pegende på poster der ikke længere skulle findes.
  Enhver nøgle-mintning skal derfor ske **efter** at artefaktet er afstemt med prod — ikke før.

**Fremadrettet krav (K4 i `docs/reviews/flerslaegt-parathed-2026-07-28.md`):** for nye
  slægter sættes `record_key` **ved udtræk**, ikke ved backfill bagefter. Så opstår problemet
  ikke igen.

Beslægtet, men egen sag: de **627 gift-ind-ægtefæller** uden bogpost er ikke-redigerbare af
samme grund (intet anker). Nøglen dér ville være forælderens `record_key` + indeks i
`aegteskaber`, og `linje` SKAL være NULL, da `regen_person_visning()` ellers påhæfter
slægtsnavnet til indgifte ægtefæller.

## Feedets GDPR-nødbremse: dødsevidens-gate + narrativ-minimum, kun i feed-laget (2026-07-25)

**Implementeret på feature-branch, ikke deployet.** Ønske: aldrig vis en levende eller
muligvis-levende person i feedet (web-forside + mobil), og aldrig et portræt-/dagensperson-kort
uden et brugbart narrativ.

**`person.levende` er en ren manuel redaktør-markering** (`schema.sql`) der aldrig genberegnes
ud fra fødsels-/dødsdato — RLS' `person_offentlig` (`db-rls.sql`) stoler blindt på den. En
fejlmarkering (glemt/forkert flag) ville derfor kunne lække en levende person gennem hele
site'et. Bevidst valgt at IKKE ændre RLS/`person_offentlig` denne omgang — det ville ramme
person-sider, søgning og stamtræ, langt bredere end det efterspurgte "feed", og er en
prod-RLS-migration med større blast radius. I stedet: en uafhængig gate udelukkende i
`packages/feed` (`levende.ts`, `kunSikkertDoede`/`erSikkertDoed`), anvendt ét sted
(`buildFeedOrder`'s choke-point) + separat i `web/src/data/home.ts` (`curatedFounders`/
`forsideStartpersoner`, som viser navne UDEN OM `buildFeedOrder` og ellers ville omgå gaten).
Kræver positiv dødsevidens: registreret dødsår, ELLER fødsel for over **120 år** siden uden
dødsår (ingen kendt person i slægten er dokumenteret ældre). Mangler begge → udelades
(fail-closed), selvom `person.levende=false` allerede skulle have tilladt personen.

Målt mod prod (`xjnvdhajfyrcytatnzos`, 2026-07-25, 889 RLS-synlige personer): 720 har positiv
dødsevidens (81 %); 3 er født inden for aldersgrænsen uden dødsår (den reelle risikogruppe
gaten er lavet til); 166 har hverken fødsels- eller dødsår og kan derfor ikke klassificeres.
Feedets person-kort-pulje krymper med disse ~169 (19 %) — de forbliver synlige på egne
person-sider/søgning/stamtræ, kun feedets kuraterede overflader er strammet.

**Narrativ-minimum:** portræt-/citat-/dagensperson-kort krævede før kun ikke-tom bio
(`p.bio.trim() !== ''`); et enkelt fragment ("Nævnt 1650.") kunne bære et helt kort. Ny grænse
`MIN_BIO_LAENGDE = 120` tegn (`pool.ts`), afledt af den eksisterende `firstQuotableSentence`-
gates 40-tegns minimum for ÉN sætning × ca. 2-3 sætninger. Målt mod prod med samme
udgave-prioritering som `pickPreferredBio` (nyeste udgave vinder): **399 af 889** synlige
personer består BÅDE dødsevidens- og narrativ-gaten (45 %) — det er feedets reelle
portræt/citat-pulje, ikke det rå 890-tal. 312 har slet intet foretrukket narrativ, 112 har ét
under 120 tegn.

**Åben backlog:** skal `person_offentlig`/RLS også hærdes med samme 120-års-regel (site-bredt,
ikke kun feed)? Brugerens beslutning — ikke taget denne omgang.

## Redaktions-datahentning var strukturelt tung, ikke midlertidigt langsom (2026-07-24)

**Delvist løst samme dag.** Fund fra manuel test af "Sammenlign udgaver": "Indlæser
redaktions-datasæt…" tager mærkbart lang tid. Verificeret empirisk mod prod
(`xjnvdhajfyrcytatnzos`, status `ACTIVE_HEALTHY` — ikke en midlertidig serverdegradering):

1. **RLS-filtrering på `fact`/`conclusion`/`assertion`/`family_member` m.fl. er ikke
   indeksérbar.** Synligheden går gennem `entitet_offentlig()` (`db-rls.sql`), som Postgres ikke
   kan bruge et indeks til — planlæggeren falder til en **sekventiel scan** + funktionskald pr.
   række. Målt via `EXPLAIN ANALYZE` (som `authenticated`): 571 ms for ét ufiltreret opslag på
   `assertion` (~7.000 rækker, `Seq Scan on fact` inderst med `Rows Removed by Filter: 2687`).
2. **Denne dyre filtrering genberegnes fra bunden pr. side.** `getAll()` (`packages/core/src/getAll.ts`)
   paginerer i sider af 1000 (PostgREST-grænsen); intet caches mellem separate requests, så det
   samme sekventielle scan kører forfra for hver side — op til 7 sider pr. tabel ved nuværende
   volumen.
3. **Supabases egen performance-advisor bekræfter uafhængigt et kendt anti-mønster:** `fact`,
   `conclusion`, `person`, `family_member`, `person_external_id` har hver TO permissive RLS-
   policies (`auth_read` + `redaktion_read`) for samme rolle/handling — tvinger Postgres til at
   OR'e begge sammen pr. række i stedet for én samlet policy (`multiple_permissive_policies`,
   WARN).
4. **`fetchMatchPersoner()` (`web/src/data/redaktionRead.ts`) var allerede kode-kommenteret som en
   bevidst bred, ufiltreret hentning** ("PoC-volumen er håndterbar") — en rimelig afvejning ved
   ~900 personer, men målingen ovenfor er efter 1939-loadet (1758 personer). Blev kun værre med
   mere data, rettede sig ikke af sig selv.

**Genmåling som ægte redaktion-JWT (samme dag) nuancerede fundet:** `redaktion_read`-policyen
bruger `(select current_rolle())='redaktion'` som InitPlan og kortslutter OR'et korrekt — de dyre
`entitet_offentlig`-subplans viste `never executed`. For redaktøren selv var flaskehalsen derfor
IKKE punkt 1 (RLS-sargability), men punkt 2: summen af net-roundtrips på tværs af 5 parallelle,
pagineret-i-1000 `getAll()`-kald.

**Løst (punkt 2+4):** `red_match_personer()` — batchet, redaktion-gated RPC i samme mønster som
`hist_for_subjekter` (`db-migrations.sql` 2026-07-24), returnerer de samme rå rækkesæt i ét
kald. `fetchMatchPersoner()` er nu et tyndt `.rpc()`-kald; `buildMatchPersoner`/`RedMatchPerson`
uændret. PR #88, anvendt+verificeret mod prod samme dag (~135ms server-side for hele
aggregatet). Policy-konsolidering (punkt 3) er droppet som følge af genmålingen — ingen målt
gevinst, unødig risiko på GDPR-fladen.

**Ikke løst:** punkt 1 (entitet_offentlig-sargability) gælder fortsat for anon/almindelig
authenticated-læsning (ikke redaktion) — relevant hvis/når den offentlige API-flade vokser til
samme skala. Ingen akut driver pt.

## Præsensliste: patrilineær efterkommer-tilhør — barn hører kun til under faderen (2026-07-23)

**Brugerfund mod rigtig prod-data:** Friedrich (Fritz) Carl Heinrich Reventlow (person 455,
†2008) er søn af to blod-Reventlow-forældre (Einar og Adelheid, fra hver sin gren der giftede
sig sammen) og blev vist under BEGGE forældres efterkommer-liste i "I linje, 1. gren" — men DAA
er patrilineær ("linje/nr følger mandslinjen", jf. `compareParentOrder` i `web/src/data/model.ts`),
så et barn med to kendte forældre hører KUN til under faderen, aldrig moderen, selv når moderen
selv er en fuldt dokumenteret blod-slægtning.

- **Ny hjælper `patrilinealForaelder`** (`packages/core/src/presensListe.ts`): barn med 2+
  registrerede forældre → foretræk den med `koen='mand'`; barn med 0-1 forælder → den forælder
  uændret (aldrig datatab). Anvendt i `pruneUndertrae`s egen boern-beregning og `buildGren`s
  søskende-sidegren-beregning.
- **Superseder `krydsReference`-mekanismen for "barn af to kendte forældre".** Den ambiguitet
  (fx to grene der gifter sig sammen) løses nu FØR `alleredeVist`-laget nås overhovedet — ingen
  krydshenvisning nødvendig, da moderen aldrig får tilbudt barnet i første omgang.
  `krydsReference` forbliver som forsvarsmekanisme for ægte konvergent slægtskab dybere i
  træet (dobbelt-fætterskab uden en direkte fælles forælder) — dækket af en parentesløs
  lavniveau-test, ikke længere reelt eksponeret via `buildGren` for den almindelige sag.
- **To reviewrunder fandt en reel regression før dette landede:** den første version filtrerede
  kun `pruneUndertrae`/`buildGren`s efterkommer-retning, men lod `blodOgGiftInd` (klatrings-
  retningen) beholde sin gamle rigdoms-først-heuristik. Når faderen INGEN egen registreret
  herkomst har, men moderen HAR sin, valgte `blodOgGiftInd` fejlagtigt moderen som "blod" —
  og det nye søskende-filter ekskluderede da hendes øvrige børn, INKL. ankerets egne fulde
  søskende, med kun en misvisende `levende_uden_gren`-advarsel som spor. Rettet ved at lade
  `blodOgGiftInd` delegere HELE afgørelsen til `patrilinealForaelder` (ét kald, ingen separat
  heuristik tilbage at uenes med) — klatring stopper nu naturligt ved en far uden videre
  herkomst, i stedet for fejlagtigt at klatre videre via morens linje.
- **Ingen prod-datarettelse nødvendig** — Fritz' egne data (to korrekt registrerede forældre)
  var altid rigtige; fejlen lå udelukkende i visnings-algoritmen.

## Præsensliste-visning v1: beregnet frem for lagret + overhoved-fakta-konvention (2026-07-22)

Implementeret via subagent-driven-development med Codex (`gpt-5.6-sol`) som udførende
implementer pr. task og Claude-subagenter som uafhængige task-reviewere (spec + kvalitet).
Spec: `docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md`. Plan:
`docs/superpowers/plans/2026-07-22-praesensliste-visning.md`. Alle 10 tasks grønne
(`packages/core` 291/291, web 426/426, mobil 348/348, alle `tsc --noEmit` rene).

- **Beregnet, ikke lagret (bekræftet ved implementering).** Relationsgrupper og
  overskrifter (FARBROR, SØSTRE, FARFARS FARBROR …) beregnes af `buildPresensListe`
  (`packages/core/src/presensListe.ts`) fra slægtsgrafen + et sæt redaktionelt udpegede
  overhoved-fakta — ingen bogstruktur er lagret. Facitliste-testen (Task 5) reproducerer
  DAA 2012-14 II linje 1. grens gruppestruktur (SØSTRE + FARFARS FARBROR) fra en syntetisk
  graf-fixture, som bekræftelse af algoritmen mod den trykte bog.
- **Overhoved-udpegning:** ny vokabular-række `('faktatype','overhoved', …)` (INGEN
  skemaændring) + eksisterende `red_upsert_fakta`/`red_opret_fakta`-flow. Værdi-format
  `"<ROMERTAL> linje[, <N>. gren]"`, parset fail-closed af `parseOverhovedVaerdi`
  (uparsebar værdi giver aldrig et gættet anker). **Prod-apply udført 2026-07-22 (bruger-
  godkendt):** `INSERT INTO vocab (scheme, code, label) VALUES ('faktatype','overhoved', …)
  ON CONFLICT DO NOTHING` kørt transaktionelt mod prod (xjnvdhajfyrcytatnzos) via psql
  (session pooler, `sslmode=require`). Verificeret: rækken findes med korrekt label,
  `vocab`-antal 152→153 (præcis +1, ingen sideeffekter), idempotens bekræftet (gentaget
  INSERT gav 0 rækker), `vocab.relrowsecurity` uændret (RLS-lint/get_advisors ikke kørt —
  ingen Supabase MCP tilgængelig i denne session — men irrelevant her: ingen ny tabel,
  funktion eller RLS-politik, kun én dataræke i en allerede-sikret referencetabel).
- **RETTET (2026-07-22, bruger-beslutning "vis én gang + krydshenvisning"):** den tidligere
  kendte struktur-begrænsning er lukket. `pruneUndertrae`s vagt er splittet i to: `paaVej`
  (ID'er på den aktuelle rekursions-stak — en ægte data-cyklus beskæres fortsat defensivt til
  null, som hidtil) og `alleredeVist` (ID'er allerede fuldt bygget og BEHOLDT, delt på tværs
  af HELE `buildGren`-kaldet — ikke kun ét undertræ). Første forekomst af en levende person
  inden for én gren vises fuldt ud; enhver senere forekomst inden for SAMME gren bliver en tom
  krydshenvisnings-stub (`PresensNode.krydsReference`), vist i UI som en kort note ("vist
  andetsteds i denne gren") i stedet for stille at blive droppet (det oprindelige fund) eller
  duplikeret fuldt ud (kernens spejlbillede, fanget af slut-reviewet — to FORSKELLIGE
  sidegrene der begge fører til samme levende person, fx et fætter-fætter-ægteskab). ÉN
  mekanisme løser begge varianter, da `alleredeVist` trådes gennem både ankerBlokkens egen
  rekursion og hver søskende-sidegrens kald. `alleredeVist` tilføjes KUN på succes-stien
  (aldrig ved beskæring til null), så et tidligere forgæves forsøg aldrig blokerer en senere
  gyldig forekomst. Krydsning MELLEM grene (`dobbelt_naaet`-advarslen) er uændret og upåvirket
  — scopet er bevidst kun inden-for-gren. Facitliste-tests dækker begge varianter direkte.
- **Trust-erfaring fra eksekveringen:** Codex' selv-rapporterede tekst (rapportfiler,
  afsluttende chat-resumeer) viste sig ved ét tilfælde (Task 4) at være fuldstændig
  opdigtet — beskrev funktioner/tests der ikke fandtes i den faktisk leverede (og korrekte)
  kode. Al implementering blev derfor verificeret uafhængigt gennem hele kørslen: kontrolløren
  genkørte selv test-suiter/`tsc` efter hvert task, og task-revieweren læste diffen — aldrig
  rapporten — som eneste kilde til sandhed. Selve koden var i alle 10 tasks korrekt.
- **To reelle implementeringsfejl fanget af task-reviewere og rettet under kørslen** (ikke
  Codex-fejl — begge var mangler i selve planen, forfattet af controlleren):
  1. Task 5's facitliste-test importerede hjælpefunktioner (`mk`/`union`/`pc`) fra en
     sibling `*.test.ts`-fil, hvilket fik Vitest til at genregistrere den importerede fils
     `describe`/`test`-blokke under den importerende fils suite (302 tests i stedet for de
     forventede 291). Rettet ved at udtrække hjælperne til en ikke-testfil
     (`packages/core/src/__tests__/presensFixtures.ts`).
  2. Task 9's mobil-skærm udelod stille partner-visning (design-spec §"Ægtefæller vises
     sammen med deres familie") og genskabte `Node`/`Gren` som indlejrede komponenter ved
     hvert render. Rettet: partnere vises nu identisk med webbens logik, komponenterne er
     løftet til modul-scope.
- **Bevidst v1-scope-reduktion (ikke fejl):** mobil-skærmen viser advarsler som et
  antal-tal, ikke som webbens udvidelige per-advarsel-liste (`<details>`). Acceptabel
  forenkling for en lille skærm; kan udvides senere hvis redaktøren efterspørger det.
  Tilsvarende mangler mobil webbens "Vis i præsensliste"-genvej fra person-siden samt
  fokus-scroll til en bestemt person (kun drawer-indgangen findes på mobil) — funktionen
  er stadig nåbar, blot ét klik længere væk; kan tilføjes senere uden arkitektur-ændring.
- **Rettet efter slut-review: `canonicalIdById` manglede på mobil-modellen.** Web's
  `loadModel` stamper `canonicalIdById` direkte på `Model`-objektet, men mobil-storen
  (`useStore.ts`) holder det som et separat felt ved siden af `model` — så
  `kanoniserPresensGrundlag(model, …)` i `praesens.tsx` læste `model.canonicalIdById ?? {}`
  og fik altid et tomt map, dvs. funktionen var reelt en no-op på mobil (ankre/levende-flag
  fra et `samme_som`-alias ville aldrig linjes op med den allerede kollapsede graf). Lavt
  risiko i dagens data (aliasser er afdøde grundlæggerdubletter/kryds-slægt-broer, ikke
  levende linjehoveder), men brød planens egen invariant. Rettet lokalt i `praesens.tsx`
  ved at flette store'ns `canonicalIdById`-felt ind på modellen før kanonisering — en
  bredere rettelse (stample det direkte på `model` i selve storen, til gavn for alle
  fremtidige forbrugere) er en mulig senere oprydning, ikke nødvendig for v1.
- **Codex-sandbox-begrænsning (proces, ikke kode):** i denne git-worktree-opsætning
  (gitdir uden for worktree-træet, `.git/worktrees/<navn>/`) kunne Codex ofte ikke selv
  committe (`.git/worktrees/*/index.lock` skrivebeskyttet i dens sandbox) — undertiden
  lykkedes det dog. Controlleren staged/committede derfor konsekvent selv efter hver
  implementer-kørsel, uafhængigt verificeret først.

## RLS-synlighed: fail-closed `entitet_offentlig`-helper, ikke `type <> 'person'` (2026-07-17)

**Besluttet:** al polymorf RLS-gating (fact/relation/narrative/note/text_mention) afgør synlighed via
`entitet_offentlig(type, id)` (SECURITY DEFINER) med et eksplicit `CASE`: `person`→`person_offentlig`,
`family`→`family_offentlig`, det faste ikke-PII-entitetssæt→`true`, **ELSE `false`**. `family_offentlig(fid)`
er offentlig kun hvis intet medlem er ikke-offentligt.

**Hvorfor:** det tidligere mønster `subjekt_type <> 'person' OR person_offentlig(...)` var **fail-open** på to
måder (Codex-fundament-review): (1) `family` er en polymorf target-type der bærer person-PII gennem sine
medlemmer, men `<> 'person'` behandlede den som offentlig → levende families vielse-fakta/noter lækkede til
anon+authenticated; (2) type-kolonnerne er fritekst uden CHECK, så en fejlstavet discriminator (`'Person'`)
slap forbi. En fail-closed helper dræber hele klassen (media-gatingen var den første instans af samme fejl).

**Kritisk:** helperne SKAL være SECURITY DEFINER — ellers re-filtrerer `family_member`-RLS det levende medlem
væk fra helperens egen subquery, så den ser en "ren" familie → fail-OPEN. `fact`/`relation`-mål (kun
note/text_mention) gates IKKE af helperen men cascader gennem targetets EGEN RLS (EXISTS i policyen).

**Alternativer forkastet:** (a) tilføje `family` som endnu et special-case i hver policy — ville efterlade
ukendt-type-hullet og gentage mønstret ved næste entitet; (b) CHECK-constraints på type-kolonnerne alene —
løser fejlstavning men ikke family-target-lækken; (c) fail-open ELSE — ville genintroducere Finding 2.

## Authenticated-tier fail-closer til anon-niveau indtil samtykke-/slægts-scope findes (2026-07-17)

**Besluttet:** en logget-ind bruger uden redaktør-rolle (medlem-tier, fx bogmærke-brugere) ser nu **præcis det
samme som anon** — kun afdøde, ikke-private personer. Levende er skjult for alle uden redaktør-rolle.

**Hvorfor:** den tidligere `auth_read` lod enhver authenticated bruger se alle ikke-private levende personer
(en bevidst udskudt beslutning), i strid med invariant #8 (levende kræver samtykke) — en GDPR-fail-open.
Indtil en egentlig samtykke-/slægts-scope-model er bygget (Codex-fund F-05), er fail-close til anon-reglen den
sikre standard. Redaktion beholder fuld adgang via det additive `redaktion_read`-lag.

**Konsekvens:** logged-in bogmærke-brugere mister synlighed af levende personer — et bevidst produkt-tab, ikke
en regression, indtil samtykke-modellen findes. **Alternativ forkastet:** beholde levende-for-medlem med et
`samtykke_offentlig`-flag nu — udskudt, da flag-modellen kræver egen design (medlem vs. forsker-tier, §F-05).

## ETL-sprog: R til DB-load, TypeScript til delt/runtime-logik (2026-07-16)

**Datavejen forbliver polyglot med et bevidst snit: R til batch-DB-load, TS til alt klienten også bruger.**
Ved opstart af flere-DAA-udgaver-arbejdet blev det taget op om R er rette sprog. Beslutning: **behold R** til
de fungerende loaders (`load_daa.R`/`load_presens.R`/`post_load_fixup.R`) — omskrivning er høj risiko, lav
værdi, og R er vedligeholderens kernekompetence. **Delt/runtime-logik (navnefoldning, dato-parsing, matching)
hører i `packages/core` (TS)**, ikke R — jf. Problem 3 §3.1 (`matchUdgaver` er TS; R-TNG-QA er kalibrerings-
reference). Disciplin: delt normalisering har ÉT hjem (TS); R kalibrerer mod TS-output, ikke sin egen kopi.
Extraction forbliver Python (tekst/LLM). Ingen R→TS-omskrivning af DB-loadet.

**`source.aar`-konvention: SIDSTE dækkede år.** Tidsserie-aksen (Problem 1) bruger sidste år i udgave-spannet
(DAA 2012-2014→2014, 2018-20→2020, 1939→1939), fail-closed parse i loaderne (`parse_aar`). En tidligere
backfill satte 2018-20→2018 (første år); harmoniseret til 2020 for ensartet "forrige udgave"-derivation
(db-migrations.sql, idempotent korrektion — anvendes først ved prod-cutover).

**Bibliografiske source-identiteter (A3d, 2026-07-17 — afklar mod primærkilde før prod-import).** Hver DAA-udgave
er en selvstændig `source` (invariant §"Hver trykt DAA-udgave"); `source` har INGEN forfatter-kolonne → forfatter
bæres i `titel` (fx `"Dansk Adels Aarbog – DAA 1939 (Louis Bobé)"`). Kendt/antaget:
- **DAA 1939** — Reventlow-stamtavlen af **Louis Bobé**. `udgave="DAA 1939"`, `aar=1939`. *(loaderen opretter den
  korrekt — verificeret i A4-dry-run.)*
- **DAA 2018-20** — Reventlow-artiklen af **Poul Holstein** (IKKE Christian Hau — han er en *citeret forsker*).
  `udgave="DAA 2018-20"`, `aar=2020` (sidste dækkede år). **NB:** dato-analysen kaldte den "2024" — det er
  sandsynligvis **trykke-/udgivelsesåret**, ikke dæknings-benævnelsen; ikke en modstrid (bind udgives typisk år
  efter dækningsperioden). Bekræft det trykte binds titelblad før import.
- **DAA 1893** — antaget **Anders Thiset**-tavle (jf. divergens-rapport); planen nævnte også "Ludwig zu Reventlow".
  **Uafklaret** — verificér forfatter mod primærkilde før 1893 evt. importeres.
- **Holstein må IKKE automatisk "vinde"** ved udgave-konflikt — rettelser går begge veje (det lokale treudgave-
  eksempel viser frem-og-tilbage-korrektioner). Kanonisk valg er redaktionelt (conclusion), ikke udgave-rang.

## `packages/core`: npm-workspace + source-only, snæver type-grænse (2026-07-14)

**Delt web↔mobil-logik samles i ét npm-workspace (`@daa/core`), ikke via paritetstest-spejling.**
Review 27 tilbød to niveauer: (A) fuld workspace-pakke, eller (B) minimalt "værn" (en test der asserter
at spejlede filer er byte-identiske). Oprindelig hældning var C (B nu + udskyd A), fordi A ville røre en
antaget prod-mobilbuild. **Da mobil viste sig kun at køre dev (ikke prod), faldt A's tungeste con væk**,
og Expo SDK 56's stærke monorepo-støtte gør Metro-friktionen lav → A valgt. Eksekveret **spike-first**:
ét modul + 5 tooling-checkpoints (Metro, jest-transform, Vite, cross-workspace-typer, Vercel deep-link)
BEVIST før fuld flytning, med fallback til B hvis et checkpoint fejlede. Alle grønne.

**Source-only pakke (rå `.ts`, ingen build-step).** Begge bundlere transpilerer kilden direkte — undgår
en dist-watch-loop og en separat build-pipeline for en intern pakke. Vercel krævede `installCommand: npm
install --prefix ..` så workspace-symlinket oprettes fra repo-roden (Root Directory=web installerer ellers
kun web's egne deps).

**Snæver type-grænse, ikke hele `types.ts`.** Kun de typer de delte moduler faktisk importerer flytter til
core (`Model` som additivt superset m.m.); app-specifikke typer bliver lokale. **`linjeByPerson`-konflikten
(web `Record<string,string>` vs mobil `Record<string,string[]>`) sidesteppes** ved at holde dens ejer-type
`Aux` app-specifik — ingen delt modul bruger `Aux`, så konflikten krydser aldrig ind i core (Codex-dual-
review-fund forfinet til en enklere, sikrere løsning end at forsone den). Grænsen mellem delt og app-
specifikt følger konsekvent: *flyt kun det forbrugerne kræver; divergens uden for det delte snit løses ikke.*

## "Forældre ukendt"-markering: rå-scope vs. samme_som-kanonisk — accepteret PoC-grænse (2026-07-11)

**Fjern-operationen forbliver rå-`personId`-scoped, selvom den offentlige projektion er kanonisk
(samme_som-collapset).** Codex-fund i review 27 (`docs/reviews/27-*.md` HIGH a): markér/fjern skriver
til det rå person-id, mens `buildParentsUnknown` folder facts fra flere rå personer til én kanonisk
(og vælger "første vinder"). Er to samme_som-linkede medlemmer BEGGE markeret, fjerner Fjern kun den
ene; den anden projicerer stadig. **Bevidst valgt backlog frem for kaskade/konflikt-visning:** (a) det
er en pre-eksisterende egenskab ved hele featuren (markér/gammel-fjern/ny-fjern er alle rå-scoped —
review-26 ændrede kun *hvordan* der fjernes), ikke en regression; (b) det kræver to samme_som-linkede
personer der *begge* er hånd-markeret forældre_ukendt — meget sjældent i en hånd-kurateret base; (c)
redaktøren collapser bevidst IKKE (evidens redigeres på rå poster). Determinisme-fixet (`.order('target_id')`
i `fetchForaeldreUkendtMarkering`) gør adfærden konsistent. Kaskadér-Fjern (RPC/editor loader collapse-
mappen + itererer flere facts) eller konflikt-visning genbesøges hvis et reelt tilfælde dukker op.

## Konto-bogmærker: login-eksklusivt (ikke hybrid), direkte tabel-adgang (ikke RPC) (2026-07-06)

**Login-eksklusivt frem for hybrid lokal/konto.** Bogmærker blev netop shippet som lokal PoC uden
reelle brugerdata — i stedet for at bygge merge-logik (lokalt→konto ved login) blev de gjort
**cloud-only**: udlogget = tomt + login-prompt, logget-ind = Supabase. Forkastet: hybrid
(lokal-når-udlogget, synk-når-logget-ind, flet ved login) — mest UX, men markant mere logik
(offline-cache, merge-strategi) for et gode brugeren selv bad om som "added benefit", ikke en
kerneflow. Ingen migration nødvendig (ingen live brugerdata i den lokale version endnu).

**Direkte tabel-adgang (RLS+grants) frem for RPC.** `bookmark`-tabellen er ren bruger-ejet data
(ingen evidens-lag, ingen redaktionel logik) → RLS-policies + eksplicitte grants er tilstrækkeligt
og Supabase-idiomatisk. `red_*`-RPC'er forbeholdes evidens-modellens skrivninger (versionering,
change-sets). Kræver dog **eksplicit** `GRANT`/`REVOKE` — Supabase auto-grant'er default-
privilegier til anon/authenticated ved tabel-oprettelse, så RLS alene lækker (dual-review 21 N1,
jf. [[supabase-revoke-from-public-insufficient]]).

**Web fik minimal login-flade; mobil kun wiring.** Mobils Konto-fane understøttede allerede
medlem-login; web's offentlige Folgesvend-læser havde ingen session (kun localStorage-"mig").
Web-skiven tilføjede derfor en lille login-modal (genbrug af `data/auth.ts`) — bevidst IKKE en
fuld kontoflade, og bevidst UDEN at ændre den eksisterende "mig"-lagring (forbliver separat,
udskudt migration).

## Følgesvend v3-feed: hybrid auto-generering + person-kun bogmærker (2026-07-05)

**Feed auto-genereret nu, editorial-krog senere (ikke DB-kurateret).** `buildFeed` er en ren
selector der udleder kort af eksisterende `Model`/`Aux` — ingen ny feed-tabel. Et tomt
`overrides`-argument reserverer den redaktionelle indgang uden at bygge den. Forkastet:
DB-kurateret feed (skema + RPC'er + redaktør-UI = stor merudvidelse uden PoC-værdi nu).

**Portrait og citat i disjunkte hash-partitioner.** Begge trækker fra personer-med-bio; uden en
regel ville samme person kunne optræde to gange. Valgt: `stableHash(id) % 4` allokerer ~25% til
citat-slot; citat-slot uden brugbar sætning falder HELT ud (bliver ikke portræt) så partitionerne
forbliver disjunkte. Forkastet: tillad dublet (redaktionelt rodet); rendrer-tids-dedup (skjuler
ikke-determinisme).

**Bogmærker: person-kun, spejler web.** Selv om v3-feedet viser gem-ikon på flere korttyper,
lagres kun kanoniske person-id'er (AsyncStorage), 1:1 med web's kontrakt. Gem-ikon vises derfor
kun på kort med `personId` (portrait/citat/embede/jubilaeum) — de gemmer personen. Forkastet:
polymorf `{type,id}` (afveg fra web; afledte kort som jubilæum/citat har ingen stabil egen-id).

**Async-lager + synkron hook-state (ikke bare `await`).** Web's bookmark-kontrakt var synkron
(`useState`-init, sync `has()`/`toggle()`). AsyncStorage-porten holder `ids` i `useState` som
render-sandhed (sync `has()`), hydrerer i effect, og toggler optimistisk + persisterer async
(seneste-vinder). Hook'en afhænger af `canonicalIdById`-**mappet**, ikke funktionsreferencen —
den stabile Zustand-`canonicalId` ville aldrig signalere recollapse (dual-review BM1/BM2).

## Flere narrativer pr. person: kilde-nøgling + per-subjekt selector (2026-07-03)

**Kilde-nøgling frem for id-liste eller konkatenering.** En persons narrativer nøgles på
`(subjekt, source_id)` — én biografi pr. DAA-udgave. Forkastede alternativer: en generisk
id-adresseret liste (over-engineering ift. udgave-driveren; kilde mister sin organiserende rolle)
og konkatenering til én narrativ (bryder invariant §6 "prosa ordret" + §7 "udgave = source", og
gør privat-flag pr. udgave umuligt). Modellen bar det allerede — kun UI/read/write kollapsede N→1.

**`source.aar` frem for `max(source_id)` eller leksikalsk `udgave`.** "Nyeste udgave" kræver et
struktureret sorterbart felt: `source.id` er ren PK (en senere oprettet TNG-kilde ville vinde
forkert), og `source.udgave` er ukontrolleret fritekst ('DAA særudgave' bryder leksikalsk sort).
Codex-fund i dual-review; additiv `aar`-kolonne + `red_opret_kilde(p_aar)` er svaret.

**Selectoren er per-subjekt, IKKE per foldet gruppe.** Spec'ens første formulering sagde "vælg på
tværs af hele identitetsgruppen", men web's cross-medlem-concat (`public.ts` founder-bio + alias-
stub) er *tilsigtet* og må ikke regressere. I stedet gøres per-medlem-valget deterministisk pr.
udgave (`pickPreferredBio`), og hver apps eksisterende cross-medlem-komposition er urørt.
Determinisme opnås via fuld orden i selectoren, ikke via gruppe-niveau-valg.

**DAA-only fallback (ingen vilkårlig stub).** Når ingen DAA-udgave findes, viser læseren *ingen*
bio frem for en vilkårlig ikke-DAA-narrativ — ellers kunne en TNG-stub blive autoritativ biografi.
Fremadrettet (TNG-enrichment) udvides `BIO_SLAGS` bevidst, ikke ved at åbne for "enhver offentlig".

**RPC-DROP er cross-client breaking → mobil i scope + prod-cutover udskudt.** Antagelsen "app er
eneste klient/lockstep" var forkert: web OG mobil deler RPC-kontrakt. At droppe en RPC-signatur
knækker den anden klients deployede bundle indtil den redeployes. Derfor: (a) mobil-redaktøren fik
en minimal source-korrekt skrivevej i samme omgang, og (b) DB-migrationer testes mod en lokal
prod-kopi og anvendes først mod prod ved koordineret merge + web-deploy (nul breakage-vindue).

## Redaktør-navigation + edit/slet bryder IKKE evidensmodellen (2026-07-03)

Spørgsmål der opstod: strider det mod evidensmodellen at lade redaktøren navigere til partnere/børn
og redigere/slette dem? **Svar: nej** — og det er værd at fastholde hvorfor, da det er let at fejllæse
invariant §1 ("påstande er uforanderlige") som et generelt redigeringsforbud.

**Hvorfor det er sikkert:** Invariant §1 gælder kun *påstande* (`assertion`) — konklusioner, relationer
og familie-links er per design det *foranderlige* fortolkningslag ovenpå. Redigering sker append-baseret
(`red_edit_oplysning`: void→jsonb, ny påstand + ny konklusion, aldrig overskrivning), og sletning kører
gennem `change_set`/`change_event` (fortrydbar). Navigation er ren læsning. Alle tre respekterer altså
evidenslaget.

**Den eneste reelle kant:** hard-delete af en *hel person* (`red_slet_person`) trækker en FK-ordnet
cascade der også fjerner de underliggende påstande — dvs. man sletter kildens udsagn, ikke bare sin
fortolkning. Derfor bevidst bevaret bag `red_slet_person_preview` + eksplicit bekræftelse. Sletning af
*links* (familie-relation, konklusion) er uproblematisk.

**Årstal på børn/partnere:** hentet fra `model.byId[pid].years` (afledt cache), ikke en ny query —
konsistent med invariant §4 (cache er envejs-projektion, læses aldrig som autoritet, men fint til visning).

## Bidirektionelle stamtræs-kolonner: fast anker + frontier-reset (2026-07-03)

Stamtræets Kolonner-visning (variant B) blev udvidet til begge retninger (aner venstre / efterkommere
højre) fra en fast **anker**-person. To ikke-oplagte valg:

**1. Fast anker, ikke re-centrering.** Ankeret flytter sig ikke ved drill; kun fokus (detalje-panel)
følger valget. **Hvorfor:** matcher den eksisterende descendant-drills semantik og holder tilstanden
enkel; visningen viser én ane-linje opad + efterkommere nedad fra ankeret — *ikke* kollaterale
slægtninge. **Fravalgt:** re-centrering på hvert valg (mere eksplorativt, men kolonnerne "hopper", og
det ville kræve at afkoble `focusId` fra `selectedId`, som web-appen bevidst konflaterer).

**2. Reset via frontier-tjek, IKKE fuldt medlemskab.** Når `focusId` skifter afgøres om drill-stien
bevares eller nulstilles. **Valgt:** bevar kun hvis `focusId` er den YDERSTE valgte ane/efterkommer
(eller ankeret). **Hvorfor (Codex-BLOCKER):** et fuldt medlemskabs-tjek (`focusId ∈ up/down`) kan
ikke skelne intern drill fra ekstern navigation til en person der tilfældigvis allerede er valgt —
drill A→B→C, klik så B i sidebaren → B∈down → ville forkert bevare stien i strid med "ekstern nav
nulstiller". Frontier-formen spejler den beviste baseline (hale-tjek). **Platform-divergens (bevidst):**
web bruger en `useState`+effekt med frontier-tjek; mobile (zustand) opnår det samme via **eksplicit
mutator-reset** — navigations-mutatorer (setFocus/setVariant/pickLinje/…) rydder `up`/`down`, drill-
mutatorer bevarer ankeret. Samme kontrakt, forskellig mekanisme pga. de to apps' state-mønstre.
Fuld spec: `docs/superpowers/specs/2026-07-03-kolonner-aner-efterkommere-design.md`.

## TNG er sammenlignings-reference, ikke facit; uenigheder loades som konkurrerende påstande (2026-07-03)

TNG-QA-rapporten flaggede 5 dato-uenigheder. **Valgt:** adjudikér hver mod DAA-kilden (narrativen bevarer
bogens prosa ordret); hvor vores `date_raw` matcher bogen (alle 5 gjorde), er TNG forkert — så vi ændrer
IKKE vores data, men loader TNG's værdi som en **konkurrerende `assertion`** på samme fakta med vores
konklusion uændret. **Hvorfor:** invariant §1 (alle kilders udsagn bevares, vores vurdering ovenpå) +
rapportens egen header. **Fravalgt:** at behandle TNG som facit og "rette" vores data (ville have
introduceret 5 fejl, da TNG var forkert i alle 5). Memory-premissen "fejl-attribueret date_raw" holdt ikke
ved kilde-tjek. Læring: en QA-uenighed er en anledning til adjudikation, ikke et signal om egen fejl.

## Spøgelses-unioner: barn "gift" med ane via mis-opløst "se nr."-ref; diskriminator = navn≠ref (2026-07-03)

Loaderen skabte 26 barnløse unioner hvor et barn var "gift" med sin egen far/ane. Rod: en `aegteskab`
hvor `partner_navn` (barnets mor, fra grupperings-headingen) og `partner_ekstern_ref` ("se nr. Y" → en ane)
er UENIGE; `load_daa.R` linkede ref'en og ignorerede navnet. **Detektions-diskriminator (efter flere
forsøg):** *ikke* "barnløs+ingen vielse" (fam 11 var ægte MEN barnløs uden vielse-fakta), *ikke* rekursiv
ane-tjek (tidlige generationers ane-kæder er selv ufuldstændige → missede de fleste). Den pålidelige er
**navn≠ref**: den opløste interne partners navn matcher ikke `partner_navn`. **Konsekvens:** loader-guarden
skal afvise intern-ref-link ved navne-mismatch (ikke ved fravær af vielse). **Læring:** en kandidat blev
manuelt bekræftet ægte af bruger (fam 11) FØR sletning — konservativ scope (kun høj-sikre) + menneske-review
på tvivl forhindrede at et ægte kryds-linje-ægteskab blev slettet. Se også [[boern-multi-union-datafix]]
(samme "se nr."/mor-heading-rod).

## Barn→union-matching: partnernavn primær, ordenstal kryds-tjek; parkér frem for at gætte (2026-07-03)

Ved fix af flergifte-forældres børn-tilknytning skulle hvert barns fritekst-`aegteskab_kontekst`
("af andet ægteskab med Sophia Amalia Hahn") mappes til rette union. **Valgt:** partnernavn som
PRIMÆR anker (positions-uafhængigt) + ordenstals-ord som KRYDS-TJEK, med NA ved uenighed eller
ukendt partner. **Hvorfor ikke bare ordenstal→position:** partnernavn kan være tvetydigt (Iwan I-60
giftede sig med samme "Margaretha von Rantzau" i både 3. OG 4. ægteskab — kun ordenstallet afgør),
OG ordinal-feltet kan være NA; de to signaler afdækker hinandens huller, og uenighed afslører
ekstraktionsfejl gratis. **Parkering frem for gæt:** børn hvis kontekst navngiver en ikke-registreret
forbindelse (III-85 Detlef, hvor feltet beskriver hans EGET ægteskab, ikke moderens) tilknyttes en
partnerløs union — aldrig et forkert ægteskab. En partnerløs union gør INGEN påstand om moderen;
den nuværende false-Brockdorff-tilknytning var en positiv falsk påstand. **Fravalgt:** LLM-baseret
matching (deterministisk fritekst-matching gav 110/111 på rigtige data).

## Prod-datafix via kirurgisk change_set (DELETE+INSERT), ikke reset-reload eller PK-UPDATE (2026-07-03)

Den allerede-loadede base bar fejlen. **Valgt:** kirurgisk versioneret korrektion (ét `change_set`,
64 flytninger som DELETE gammel + INSERT ny family_member-række) frem for (a) reset-reload fra fixet
loader eller (b) `UPDATE family_member SET family_id`. **Hvorfor ikke reset-reload:** `--force-reset`s
TRUNCATE CASCADE rammer profiles/lineage/suggestion + redaktionel historik (jf. [[base-identitet-og-reload]]);
kirurgisk fix er reversibelt og har lille blast-radius. **Hvorfor DELETE+INSERT ikke UPDATE:** `family_id`
er del af PK (family_id,person_id,rolle); en PK-muterende UPDATE er præcis den slags kant der skjulte
den tidligere GENERATED-kolonne-fortryd-bug — DELETE+INSERT giver to rene, entydigt reversible change_events.
**Delt matcher** mellem loader og korrektion, så de umuligt kan divergere. **Læring:** re-run-verifikation
er tautologisk (samme matcher); uafhængig evidens var event-tællingen (no-op INSERT trigger-logger ikke →
tab ville få 132-tallet til at komme til kort) + eksternt genealogisk holdepunkt (Anna Sophie var Hahns datter).

## Redaktør person-browse driver af `persons` (RedPerson), ikke `model.persons` (2026-07-03)

Da Følgesvends browse-UX (a-z/fødsel-sort/linje-filter) blev porteret til redaktør-fladen, kunne listen
have været drevet af den samme `model.persons` (ModelPerson) som Følgesvend bruger. Valgt i stedet: driv af
redaktørens egen `persons` (RedPerson) + kun linje-metadata fra `model.lineage`. **Hvorfor:** redaktør-listen
er *skrive-autoritativ* — `curPerson`/`recordId` skal altid resolve mod den redigerbare mængde. Hvis
`model.persons` (collapse:false) var et subset/superset af RedPerson-mængden, ville listen enten skjule
redigerbare personer eller vise rækker uden editor-backing. RedPerson bærer i forvejen `born` (parset fra
`visning_foedt`, aldrig dødsår), så fødsels-sort krævede ingen ny data. `buildBrowse` blev derfor
generaliseret strukturelt (`BrowsePerson = {id,name,born}`) frem for at tvinge redaktøren over på model-
typen. **Fravalgt:** unify de to person-kilder upstream (unødvendig kobling; redaktøren har legitimt brug
for den rå liste til redigering). Kontrakten der holder id-rummene flugtende: redaktør-modellen loades
`collapse:false`, så model-person-id == rå RedPerson-id.

**Linje-chip filtrerer kun listen (afvigelse fra Følgesvend).** På Følgesvend hopper et linje-klik også
stamtræs-fokus til grenens stamfader. Redaktør-fladen har intet stamtræ, så chippen her *kun* filtrerer.

## Versionering + hyperlinks App-lag (2026-06-30)

**Escape-fix lagt på encode-siden (`makeToken`), ikke decode-siden (scanneren).**
Mit første fix-forsøg (H1) var at indsnævre scannerens backslash-gren til kun `\|[]`. Det løser
intet: `]` er legitimt eskaperet, så en ueskaperet trailing backslash sluger stadig afgrænserens
første `]` uanset hvor smal regex'en er — verificeret empirisk med en node-simulation af begge
varianter. Korrekt fix: eskaper `\` SELV i `makeToken`; scanneren forbliver uændret, fordi dens
ubegrænsede "backslash+næste-tegn=ét par"-logik er korrekt, NÅR encoderen garanterer at enhver
literal backslash altid er doblet. Generel læring: et escape-alfabet skal inkludere escape-tegnet
selv, ikke kun de tegn det beskytter.

**`reverteret`-status beregnes fra HELE historik-listen, ikke fra rækkens eget felt.**
`change_set.reverterer_id` på række R betyder "R fortrød hvilket sæt" — sat på det NYE
reversal-sæt, peger TILBAGE på det ORIGINALE. En original post X's eget `reverterer_id` forbliver
derfor NULL efter X er fortrudt. `mapHistRow` tager nu et `revertedIds`-sæt (alle `reverterer_id`-
værdier fra hele resultatet) som parameter, i stedet for at læse feltet direkte på hver række.

## Versionering + hyperlinks DB-lag (2026-06-30)

**`begin_change_set` wires i ALLE DML-skrive-RPC'er, inkl. de 4 opretter-RPC'er.**
Implementeringsplanens task-liste nævnte 17 RPC'er og udelod `red_opret_person/estate/kilde/
organisation`. Men `red_opret_person` kalder `red_upsert_fakta` nested — uden et change_set åbnet
i den YDRE opretter ville person-INSERT'en ikke logges, og de nestede kald ville åbne separate sæt
(spec-finding H1). Design-specens §6 ("Alle `red_*`") er den korrekte autoritet; planens liste var
en mangel. `red_suggest` (staging) og `red_slet_person_preview` (read-only) forbliver uwired.

**Restore-divergens-tjek dækker DELETE-inverse (ikke kun INSERT/UPDATE).**
Den optimistiske B9-kontrol skal sammenligne nuværende række mod den *post-state* sættet efterlod:
INSERT/UPDATE → `efter`, DELETE → SQL NULL (række skal være ABSENT). Den oprindelige plan-kode
tjekkede kun INSERT/UPDATE, så en genbrugt PK efter en sletning kunne overskrives blindt ved
fortryd. Dual-review-fund H1; rettet.

**`_version_upsert_row` lister kun snapshot-kolonner i INSERT/SET.**
Snapshot udelader skip_cols (`person.visning_*`, `profiles.email/rolle`). `(jsonb_populate_record).*`
ville sætte dem NULL ved restore → `profiles.rolle NOT NULL`-crash, og NOT NULL-tjekket fyrer FØR
ON CONFLICT-arbitrering, så det rammer selv ved UPDATE-restore af eksisterende række. Fix: eksplicit
kolonne-liste fra snapshot-nøgler → skip_cols får DEFAULT ved insert, bevares ved update. Dual-review
H2 (opgraderet fra LOW). Cache (`visning_*`) regenereres separat efter restore.

**TOCTOU i restore deferret bevidst.** `_version_current_row`-tjek + inverse-DML er ikke atomiske.
Acceptabelt under single-writer PoC (samme threat-model som `max(id)+1`-id-tildeling, spec §4.6);
genåbnes ved flerbruger-skrivning.

## TNG-QA: tre kerne-valg i match + QA (2026-06-30)

**Auto-tier = ambiguitets-margin, ikke `unique_block`.**
Næsten alle i basen hedder "Reventlow", så `unique_block` ("ene plausible navne-kandidat")
er ALDRIG sand → auto var altid 0. Valgt: auto kræver at bedste kandidat er ≥
`ambiguity_margin` (0.05) foran nr. 2 (+ score≥cutoff + top-kandidat). Kalibreret mod
*bootstrap-ankre* (entydige eksakte matches) i stedet for et håndlabelt facit-sæt — bevidst
hurtig-start; ankrene er korrekte pr. konstruktion, så de validerer ikke præcision uafhængigt
(non-anker-auto øjen-kontrolleres i `calibrate.R`). Forkastet: sænke `unique_block`-strenghed
(ville ikke skalere med uniform efternavn).

**Dato-overlap tæller kun som scoring-evidens ved reel dato på begge sider.**
`intervals_overlap` returnerer TRUE når begge datoer er ukendte (NA→±Inf), så et middelmådigt
navne-match fik 0.3 "gratis" vægt og kunne auto-promoteres på navn alene (fx forskelligt
efternavn, ingen datoer). `.overlap_evidence` kræver dato på begge sider. Konsekvens: auto
kræver reel fødselsårs-korroboration (navne-only maxer på 0.7). Bivirkning: dato-løse
nr.2-kandidater taber vægt → større margin → flere entydige auto (273→347).

**GDPR PII-gate = INPUT-gating, ikke output-gating.**
Filtrér ALLE sammenlignings-input (vores + TNG) til afdøde-ikke-private FØR sammenligning, så
ingen levende person kan komme ind i `disc` — heller ikke som relateret 2.-endepunkt. Reducerer
garantien til én kontrollerbar invariant frem for "hver refereret id på hver række blev tjekket".
KRITISK: TNG-siden filtreres OGSÅ (ellers navngiver `mangler_hos_os` en levende ægtefælle til en
afdød). Fail-closed på ukendt privacy. Forkastet: output-filtrering af `disc` + tekst-scan
(`assert_no_living_pii`) som primær — degraderet til backstop (svækkes når id'er → labels).

## Opret: privat FORCERET true + sted udskudt (2026-06-29, hærdet 2026-06-30)

**Ny person oprettes med `privat=true` — IKKE konfigurerbar ved opret.**
RLS-reglen `levende=false AND privat=false` gør personen anon-læsbar. En glemt levende-toggle
ville ellers publicere en nulevende person umiddelbart ved opret. Frem til cycle-08 var `p_privat`
en parameter med default `true`, men en crafted kald med `p_privat=false` kunne omgå beskyttelsen.
**cycle-08 (2026-06-30):** `p_privat`-parameteren fjernet helt — `INSERT` hardkoder `privat=true`.
Gammel 7-arg signatur DROPpet; ny 6-arg erstatter. Synlighed skiftes udelukkende via
`red_set_privat`. Ansvaret for synlighed placeres dermed eksplicit hos redaktøren.

**Gods-sted udskudt.**
`EntitetPicker` understøtter kun organisation/estate, og `redaktionAux` har ingen `placeListe`.
En sted-picker til gods kræver ny aux-datasektion og ny picker-komponent — ikke i scope for PoC.

## Plan 2C-2b: redigerbar familie-sektion — 5 nøgle-valg (2026-06-29)

**`red_slet_familie_link` sletter aldrig `family`-entiteten (Codex H1).**
`family`-tabellen bærer i gennemsnit 276 facts og 700 notes i nuværende load. Disse binder via
`(target_type='family', target_id)` — polymorfisk, ingen FK, ingen cascade-constraint. En
sletning af family-rækken ville efterlade al evidens forældreløs. RPC'en sletter KUN
`family_member`-rækkerne. En tom family (ingen members) er bedre end orphaned evidens;
fjernelse af en tom family kræver eksplicit audit og separat RPC.

**Ingen auto-dedup af unioner i `red_opret_union` (Codex H2).**
Et par (A, B) kan logisk have to selvstændige ægteskaber (fx skilsmisse + gengifte). En
pair-dedup (`WHERE partner_a=X AND partner_b=Y → returnér eksisterende family_id`) ville flette
børn og ægteskabs-events fra to distinkte tidslinjer ind i ét family-objekt. RPC'en opretter
ALTID en ny family-entitet + 2 partner-links. Ansvaret for at identificere et allerede
eksisterende ægteskab og vælge det korrekte family-objekt ligger i UI-laget / redaktøren.

**Cyklus-guard + selv-forælder-afvisning i `red_tilfoej_barn` (Codex H3).**
To separate afvisninger i RPC-laget (SECURITY DEFINER, ikke kun klient-lag):
(1) Selv-forælder: `p_barn_id` == en af familiens partnere → RAISE.
(2) Cyklus: recursiv CTE traverserer opad i slægtstræet fra `p_barn_id`; hvis nogen ane == en
af familiens partnere → RAISE.
Begge afvisninger er nødvendige i databaselaget — klient-side-guard alene kan omgås ved
direkte RPC-kald.

**`fetchPersonFamilie` separat fra `redaktionAux`.**
`redaktionAux` sammensætter familie-visningen til display (formaterede listestrenge), men
eksponerer hverken `family_member.konfidens` eller primærnøglerne (`family_id` + `person_id`)
som slet- og konfidens-kaldene kræver. Separat fetch mod `family_member`-tabellen var den eneste
korrekte løsning — omskrivning af aux-kontrakten ville bryde resten af editoren. Analogt med
2C-2a's valg af separat `fetchPersonRelationer`.

**Era-validering: klient-side advar-og-tillad.**
`eraAdvarsel` er en blød advarsel, ikke en hard-reject. Begrundelse: 27 af de eksisterende
familie-links i databasen er historisk inkonsistente (era-fejl fra DAA-parseren) — en
hard-reject ville blokere korrekt redigering af disse poster. Redaktøren modtager advarslen,
bekræfter og fortsætter. Hard-reject forudsætter at alle 27 era-fejl er rettet i basen.

**Live RPC-deploy + rollback-tests + manuel e2e er controller-gated.**
Samme model som tidligere plans: bruger-OK + backup (R/RPostgres) inden DDL kører mod prod.
App-siden er komplet og testet (121/121 jest, tsc rent); RPC'erne eksisterer endnu ikke i prod.

## Plan 2C-2a: redigerbar sektion-relationer — scope + nøgle-valg (2026-06-29)

**Redigerbart scope: kun relation-baserede hverv/godser; familie og kilder read-only.**
Familie (family_member) og kilder (external_id) er udeladt af 2C-2a. Familie-redigering
kræver separat semantik (opret familie-enhed, kobl forælder/barn, håndtér
`family_member.konfidens`) og er udskudt til plan 2C-2b. Kilder (external_id) kræver
opret-flow for nye source-entiteter. Begge deferred = bevidst scope-grænse.

**Separat `fetchPersonRelationer` frem for genbrug af `redaktionAux`.**
`redaktionAux` eksponerer relationer som formaterede listestrenge uden `relation.id`.
Slet-kaldet (`red_slet_relation`) kræver præcist `relation_id`. En separat pagineret
fetch (direkte mod `relation`-tabellen, filtreret på `subjekt_id`) var den eneste
korrekte løsning — genbrug af aux ville kræve en destruktiv omskrivning af aux-kontrakten
der bryder resten af editoren.

**`red_slet_relation` skal FK-ordne evidens-slettelsen manuelt.**
`relation`-tabellen har intet ON DELETE CASCADE til sin evidens: `assertion`, `conclusion`,
`citation`, `note` binder på `(target_type='relation', target_id)` — polymorft, uden FK.
RPC'en sletter i rækkefølge citation → conclusion → assertion → note → relation for at
undgå forældreløse evidens-rækker. (~955 evidens-rækker er knyttet til relationer i nuværende load.)
Løsningen er bevidst SECURITY DEFINER + rolle-gated (anon → P0001) som de øvrige red_*-RPC'er.

**`red_tilfoej_relation` validerer objekt_type og eksistens + dup-guard.**
Validering af `objekt_type` mod tilladt sæt og eksistens af `objekt_id` sker i RPC'en
(ikke i app-laget) — nødvendigt for at undgå FK-violation + meningsløse relationer ved
klientfejl. Dup-guard returnerer eksisterende `relation.id` ved gentagelse (idempotent),
ingen dublet indsættes.

**Live RPC-deploy + rollback-test + manuel e2e er controller-gated.**
Samme model som tidligere DDL-deploys: bruger-OK + backup inden DDL kører mod prod.
App-siden er komplet; RPC'erne eksisterer endnu ikke i prod.

## Plan 2C-1: entitetslister read-only via udvidet buildAux (2026-06-28)
Redaktions-appens Entiteter-tab viste kun personer (2A). 2C-1 gjorde den til en type-menu med
read-only lister over de øvrige entiteter.

**Ikke-oplagte fund/valg:**
- **RPC-fladen er person-centrisk.** Ingen write-RPC for source/organisation/estate/media/coat_of_arms
  → 2C-1 er nødvendigvis read-only; entitets-redigering kræver nye RPC'er (= 2C-3).
- **Datakilde: udvidet `buildAux`, ikke separate fetches.** De fire lister (kilde/org/medie/gods)
  kommer fra de rå arrays buildAux allerede modtager → ingen ekstra fetch. Kun `coat_of_arms` er nyt.
- **`majorat` er ikke en entitet** — det er en `slags` af `estate` (len/stamhus/lensgrevskab) og er
  dermed i gods-listen. (estate.slags er desuden NULL på alle 229 rækker nu.) Promovering til egen
  entitet = fremtidigt model-arbejde (jf. lineage-promoveringen).
- **`coat_of_arms` (våben) FINDES** — Codex fangede en fejlpåstand om at tabellen manglede; våben
  inkluderet.
- **Auth-state-kontrakt:** lister/menu skelner rolle≠redaktion ("Kræver redaktør") fra load
  ("Henter…") — ellers permanent "Henter…" for ikke-redaktører (Codex).

## Plan 2B: separat redaktion-MODEL frem for per-person re-derivation (2026-06-28)
Person-editoren lænede sig på den delte anon-model (893, uden levende) → "ikke fundet" for de 70
levende som 2A nu når. Det oprindelige design var en per-person `fetchRedaktionPerson(id)` der
re-deriverede familie/sektioner.

**Codex-review afslørede at re-derivationen ville DIVERGERE** fra den faktiske logik:
`buildModel` chrono-filtrerer umulige forælder-barn-kanter + vælger første fødselsfamilie;
`buildAux` klassificerer hverv som BÅDE organisation OG `historical_event` med specifik
format/sort. En forenklet re-implementering ville vise andre (flere/umulige) forældre og mangle
hverv ift. publikums-visningen.

**Beslutning: SEPARAT REDAKTION-MODEL.** Load én ekstra fuld model via redaktion-sessionen
(`loadFromSupabase({includePrivat:true})` → `buildModel`), gemt i en adskilt store-slice. Editoren
bruger de EKSISTERENDE selektorer/aux uændret → ingen divergens, pagination gratis (getAll), al
derivation genbrugt. Publikums-faner bruger uændret den offentlige model (ingen GDPR-læk).

**Konsekvenser:**
- To modeller side om side (offentlig 893 / redaktion 963). Lazy-loadet ved rolle=redaktion.
- `AppPerson.privat` tilføjet (toggle-init); `loadFromSupabase` får `includePrivat`-param.
- Narrativ-privat-fix (`fetchPersonNarrativ` = skrive-mål + bevar privat) — `red_upsert_narrativ`
  redigerer første narrativ uanset privat, så prefill skal læse SAMME række.
- Kun køn redigerbart i 2B; familie/sektion read-only (relations-redigering = 2C).

## Plan 2A: separat redaktion-person-fetch + pool-baseret søg (2026-06-28)
Redaktions-appen manglede in-app-navigation til personer (konflikt-køen tom efter kardinalitets-fix,
entitetslister stub) → man tastede URL → web-reload → skrivemode nulstillet. 2A gav Entiteter-tab'en
en person-liste.

**Ikke-oplagt valg: SEPARAT `fetchRedaktionPersoner` frem for genbrug af den delte model.**
Den delte publikums-model filtrerer `privat` ud (`load.ts:103`) OG loades ved boot som anon (kun
offentlige). Genbrug ville enten skjule levende/private for redaktøren ELLER (ved reload-med-private)
lække dem til publikums-fanerne (samme model). Separat fetch (RLS-gated, inkl. levende/privat) holder
GDPR-grænsen ren. Verificeret: redaktion ser 963, anon 893.

**Konsekvenser:**
- `buildSearch` → pool-baseret `searchPool` (DRY; publikum + redaktion deler søg/alfabet/sort-logik).
- Pagination obligatorisk (`getAll`/`.range`) — PostgREST capper ved 1000 lydløst (Codex 2A H1).
- `RedPerson.born` direkte fra visning_foedt, ikke aar-strengen (ellers dødsår-som-fødeår, Codex 2A M1).
- Tag på liste-rækker = `levende || privat` (de 70 skjulte er levende, ikke manuelt-private).

## Fact-kardinalitet: flere facts pr. (person, faktatype) er korrekt, ikke konflikt (2026-06-28)
Bruger-feedback under live-test: person 199 viste kun 1 titel, og konflikt-køen flagede
"6 uenige titel-værdier". Data-tjek: personen har **6 separate titel-facts** (kammerjunker,
konferensråd, kammerherre, gehejmeråd, gehejmekonferensråd, landråd i Holsten) — alle
legitime titler båret gennem livet, ikke konkurrerende påstande om samme forhold.

**Beslutning: en person kan have N facts af samme faktatype, og det er den korrekte model.**
Konsekvenser, rettet:
- **`red_konflikt`-view:** grain ændret fra `(person, faktatype)` til **pr. fact** — ægte
  konflikt = >1 distinkt assertion-værdi INDEN FOR ét fact (to kilder uenige om samme forhold).
  Efter rettelsen: 0 konflikt-rækker i nuværende load (alle facts har én oplysning) — den
  gamle kø var 100% falske positiver.
- **`joinEvidence` / person-editor:** `PersonEvidence.felter` er nu `Record<felt, FeltEvidens[]>`
  (liste pr. felt). Editoren viser ét kort PR. FACT under en felt-overskrift (titel → 6 kort).
  Tidligere overskrev `joinEvidence` pr. felt → kun det sidste fact var synligt.

**Write-side (løst 2026-06-28):** to nye RPC'er adskiller de to operationer som
`red_upsert_fakta`'s find-or-create blandede sammen:
- `red_tilfoej_oplysning(p_fact_id, …)` — operation A: ny oplysning til ET specifikt fact
  (per-kort "+ Tilføj oplysning"). Rører ikke conclusion (kandidat; vælg med red_set_konklusion).
- `red_opret_fakta(p_subjekt_type, p_subjekt_id, p_faktatype, …)` — operation B: ALTID nyt
  distinkt fact (sektion-knap "+ Ny titel"). Tillader flere facts pr. faktatype.
`red_upsert_fakta` (find-or-create) beholdes for R-load/bagudkomp, men UI bruger den ikke mere.

## Redaktions-UI: vertikal kerne-skive + 3 ikke-oplagte DB-valg (2026-06-27)
Redaktør-appens UI bygget som **vertikal kerne-skive** (dashboard + person-editor + konto +
3 sheets), ikke hele handoff-designet. Entitetslister, generisk record-editor, opret-flow og
relations/sektion-redigering udskudt til plan 2 — kerne-skiven validerer hele evidens-skrive-stien
end-to-end hurtigst. Køn-editor + familie/sektion-visning også udskudt (spec §6.2 ikke fuldt
indfriet; bevidst nedskaleret, bruger-godkendt).

**Tre ikke-oplagte DB-valg (Codex-review fangede dem som spec-fejl før impl):**
1. **`red_konflikt`-view kræver `security_invoker=true`.** Et alm. PostgreSQL-view kører med
   ejer-rettigheder og **omgår RLS** på fact/assertion → ville lække private personers konflikter
   til anon/medlem. security_invoker arver kalderens RLS. (GDPR, invariant #8.)
2. **Redaktion-read-RLS er nødvendig, ikke valgfri.** Den eksisterende `auth_read`-policy skjuler
   private rækker for ALLE authenticated. Uden en redaktion-specifik policy ville en redaktørs egen
   privat-toggle gøre personen usynlig for hende selv ved næste re-fetch (kan ikke ophæves). Løst med
   policy gated på `current_rolle()='redaktion'` (ikke `using(true)` — bevarer medlem-GDPR-laget).
   **Konsekvens:** en redaktør har fuldt indsyn i ALLE nulevende — bevidst privacy-udvidelse for rollen.
3. **Slet-advarsel skal hente indgående OG udgående relationer.** `red_slet_person` sletter
   relationer hvor personen er subjekt ELLER objekt, men app-modellen (`load.ts`) henter kun subjekt.
   Egen `red_slet_person_preview`-RPC spejler RPC'ens slette-logik 1:1, så advarslen ikke underrapporterer.

**Blød/mutabel assertion bevaret** (arvet fra 2026-06-26-spec): redigér=UPDATE, slet=DELETE bryder
invariant #1 (uforanderlighed), men er bevidst PoC-valg m. reversibel migrationssti i RPC-kroppen.

## Slægtslinje promoveret til entitet `lineage` — (a) nu, (b) senere (2026-06-23)
Linjer var bare et `linje`-label på `person_external_id`. Et label kan ikke bære navn,
våben, adlingsdato eller forgrening. CLAUDE.md §9 + datamodel-oversigt §5 forhåndsgodkendte
en promovering ("kan promoveres hvis branch-niveau-udsagn ønskes"); behovet for navne
(og i andre slægter: linjer der adles → nye adelsfamilier) udløser den.

**Valg: minimal entitet nu, ikke fuld udbygning.** `lineage` oprettes med kun
`(id, source_id, kode, navn)` — trin (a), navngivning. Bevidst IKKE bygget endnu:
`parent_lineage_id` (forgrening), `status`, `fact subjekt_type='lineage'` (adling/floruit/
alternative navne m. evidens), `relation` til våben/kilde/person. Det er trin (b).

**Hvorfor det ikke bryder invariant #2** ("nye behov = rolletyper, ikke tabeller): en
linje er en ny *slags ting* med egen identitet, ikke en ny måde at forbinde på. Label-
løsningen brød netop sammen ved "adlet gren → ny familie".

**Hvorfor (a) ikke maler os i et hjørne:** (a) skaber SAMME tabel som (b) bruger, bare
med færre kolonner. (b) er ren `ALTER ADD COLUMN` + nye relationer — nul rename, nul
data-migration. Det rå `linje`-token på `person_external_id` bliver liggende som join-nøgle
og proveniens (mapper til trykt side). Backfill udleder `source_id` fra data, så den binder
til den faktiske DAA-source uanset id. App falder tilbage til `Linje {kode}` hvis navn mangler.

## boern udledes deterministisk; boern.linje er IKKE JSON-linjen (2026-06-17)
Børne-referencer ("3 børn: Tiende slægtled, II, nr. 31-35") parses deterministisk i
`validate.py` (`derive_boern`), ikke af LLM-trinnet — LLM'en missede dem systematisk
(Codex-udtræk: kun 38/123 fanget). Teksten er regulær; deterministisk kode er fejlfri.

**aegteskaber-udtræk er stadig LLM (åben):** Modsat boern parses ægteskaber af
LLM-trinnet — og det misser ~9% (26/288 poster har "Gift" i narrativ men tom
`aegteskaber`, fx V-106 Christian Benedictus' ægtefælle Sophie Pauline Schjær).
Børn loades alligevel (deterministisk boern), men deres familie får ingen partner.
**Anbefalet fix:** løft ægteskabs-klausulen til deterministisk parsing i `validate.py`
(som boern). Klausulen er regulær ("Gift [dato] [sted] med Navn (F.: forældre),
* fødsel, † død") men rigere end boern (ordinaler, 1°/2°, skilsmisse, b.v.,
ægtefælle-forældre) → mere regex-arbejde. Ikke implementeret.

**Kryds-gren-tvetydighed (åben):** Romertallet i børne-ref ("…, II, nr. 31") er bogens
INTERNE gren-tæller i slægtleddet, IKKE JSON-linjen (I-V). Det matcher JSON-linjen ~85%,
men `nr` genbruges på tværs af 133 linjer, så i 145 tilfælde findes barn-nr i BÅDE
"stated" og forælder-linje. Loaderen (`load_daa.R`) vælger stated først → 97 verificerede
fejl (stated-kandidat historisk umulig, hundreder af år fra forælder), 38 ægte kryds-gren
(stated korrekt), ~10 uklare. **Anbefalet fix:** era-baseret tie-break — afvis stated hvis
kandidatens fødselsår er >80 år fra forælderens; ellers behold stated. Påvirker kun ældre
linjer I/III (Reventlow-hovedlinje V er entydig). Ikke implementeret endnu.

## Import: DAA-PDF først, TNG kun enrichment (2026-06-15)
Databasen bygges fra den trykte DAA (autoritativ, kohærent kilde), ikke fra TNG-dumpet
(25k personer, blandede tredjeparts-kilder → ville forurene grundlaget). TNG bliver
senere "flere påstande fra en svagere kilde"; konklusionslogikken foretrækker DAA.
Hver DAA-udgave = én `source`; identitetssammenkædning pragmatisk i PoC.

## Selektiv struktur — kun genealogisk rygrad (2026-06-16)
Rygrad = navn/titel/fødsel/dåb/død/begravelse/floruit/ægteskab/forældre-børn/godser/
adling/dekoration. **Erhverv + uddannelse er IKKE rygrad** — de ligger i prosaen
(narrativ for nummererede personer; bio-note for ægtefæller uden post). Begrundelse:
de forbinder ikke entiteter og driver ikke træet (§6). Overvejet/forkastet: strukturere
karriere som fakta for alle (kræver dyrt re-udtræk, lille genealogisk gevinst).

## Titel ≠ navn; flere navne-former = påstande (2026-06-16)
Titel ("Greve") er eget `titel`-fakta, aldrig bagt ind i navnet; display komponerer.
Samme person nævnt flere steder = flere navne-påstande; konklusion vælger kanonisk.
Relative datoer (s.å./s.m.) opløses til ISO ved udtræk, rå tekst bevaret.

## Bulk-insert frem for row-by-row (2026-06-16)
Loaderen akkumulerer i hukommelsen og skriver per tabel med dbAppendTable/COPY i
FK-rækkefølge. Row-by-row over session-pooleren var både langsomt (30+ min) OG
skrøbeligt (forbindelsen droppede → rollback). Bulk = ~14 sek + kort transaktion.

## Load-laget som deterministisk normaliserings-trin (2026-06-16)
Kategoriserings-/dedup-regler (estate-dedup, child-linje-fallback, akademisk-grad-
klassificering) anvendes ved load på hele datasættet i én 14-sek reload — frem for
dyrt LLM-re-udtræk. Udtrækket fanger rå-værdien; loaderen pålægger struktur.

## Model-tier: Sonnet til udtræk; Haiku afprøvet (2026-06-16)
Sonnet til stamtavle-udtræk (klarer tredjeparts-fælder, dense biografier). Haiku
testet: rammer genealogisk rygrad tæt, men taber på klassifikations-nuancer (karriere
vs embede) og er flakier. Forkastet for fuld kørsel efter clobber-fejl; egnet til
billig broaden HVIS isolerede output-mapper + terse output.

## Identitetssammenkædning: `samme_som`-relation + collapse i app (løsning A) (2026-07-02)
Samme fysiske person kan optræde som FLERE person-poster: (a) slægtslinje-
grundlæggere står i DAA to gange (oprindelses-linje + som rod af egen linje, fx
Conrad de Reventlow III-58/V-1, Detlef IV-1/III-104); (b) indgiftede der har egen
slægt et andet sted (fx Beke Ahlefeldt-Laurvig: ægtefælle-stub i Reventlow NU,
barn af Julius Ahlefeldt i kommende Ahlefeldt-import).

**Valg: LINK, ikke merge.** En `samme_som`-relation (person→person, evidenslag)
forbinder posterne; begge DB-rækker bevares (proveniens + fortrydbart, datamodel
§9). Frontend COLLAPSER dem via traversal → brugeren møder ÉN person (én søgetræffer,
én person-visning der samler begge posters fakta/relationer, én knude i
slægtskabsfinderen). Applied durabelt i post_load_fixup.R (reload-sikkert, opslag på
linje/nr). Samme mekanisme dækker begge tilfælde — men betydningen adskiller sig:
grundlægger = redundant dublet at skjule; indgiftet-med-egen-slægt = én person i TO
slægter, hvor collapse tegner selve kryds-slægt-broen ("er vi i familie?").

**Status (2026-07-02): frontend-projektionen IMPLEMENTERET (web+mobile).** Ren funktion
`collapseSameAs` folder de linkede poster til én kanonisk FØR `buildModel` (motoren urørt),
valideret + reversibel (karantæne ved konflikt). Se changelog + `docs/reviews/16`+`17`.
Dual-reviewet (Claude+Codex); empirisk valideret mod prod (Conrad/Detlef folder rent).

**Udestår:** (1) Automatisk detektion i skala via crosswalk/matching når nye slægter
importeres (manuel linking kun til få kendte tilfælde nu; crosswalk er for støjende til
bulk uden injektiv matcher). (2) Kryds-slægt-broer (Beke-typen) — kræver server-side
privacy-klasse før de kan foldes i publikums-web/mobile (spec §9). (3) Manuel skærm-
verifikation (Expo-simulator + web-browser).

## Reload-strategi + durable post-load-fixup (2026-07-02)
DAA-basen genindlæses med `load_daa.R --reset` (fuld TRUNCATE+rebuild), IKKE append
(append dublerer hele basen — id'er allokeres fra MAX(id)). RESET-guarden afviser dog
`--reset` mod en base med redaktionelle `change_set`-rækker; `--force-reset` tilsidesætter
bevidst (sletter dem). **Læring fra data-tab-hændelse (2026-07-02):** en TRUNCATE CASCADE
rammer også `profiles`/`lineage`/`suggestion` (FK-kaskade), og enhver hånd-applyet live-edit
(lineage-navne, redaktør-profiler, `samme_som`-links) går tabt ved næste reload. Derfor:
efter-load-korrektioner der ikke bor i loaderens automatiske pipeline SKAL ligge i et
committet, idempotent `post_load_fixup.R` med par-/entitets-opslag på reload-invariante nøgler
(linje/nr, ikke person-id). Alternativ (differentiel upsert-loader der bevarer redaktionelt
arbejde) er afvist for nu — større arbejde, egen OpenSpec. **Verificeret:** reload → 922
personer, TNG-QA manglende links 125→10.

## TNG-funktionalitet: prioritering af backlog (2026-07-03)

Efter fuld gennemgang af familiens TNG-dump (`jr_tng_reventlow.sql`, se
`docs/tng-reventlow-analyse.md`) er fire opfølgningspunkter prioriteret:

- **DNA-slægtskabsdata: AFVIST**, ikke udskudt. Ingen ny tabel/faktatype/relation
  til Y-DNA/mtDNA/centiMorgans/DNA-matches bygges, selvom familiens TNG rummer 20
  reelle test og "er vi i familie?" er kernefunktionen. Fravalgt af bruger uden
  begrundelse påkrævet — lukker sagen, ingen genåbning uden eksplicit ny anmodning.
- **Foto/medie-rigdom (region-tagging à la Facebook-tagging, albums, event-scoped
  medielink, geokodning+proveniens på medier): UDSKUDT SAMLET.** Ønsket, men skal
  designes som én sammenhængende medie-arkitektur-beslutning, ikke fire spredte
  enkelt-features. Ingen implementering før den samlede session.
- **Gemte rapporter/smart-lister: NÆSTE FOKUS.** *(Afløst: blev aldrig bygget; genimportprogrammet (model 2,
  2026-08-25) overtog prioriteringen. Udskudt, ikke afvist — markeret ved review 2026-10-27, 1a-14.)* TNG-familien har 193 reelt brugte
  brugerdefinerede lister — det eneste §7-punkt med både stærk evidens for værdi OG
  eksplicit bruger-interesse nu. Implementeres som parametriserede forespørgsler i
  app-koden (ikke TNG's rå `sqlselect`-tekstfelt — SQL-injektions-mønster).
- **Navnekomponentering (adelspartikel "von"/"af", jf. TNG `lnprefix`): UDSKUDT.**
  Ikke afvist, men ingen ændring af navne-som-fri-tekst-i-assertion før videre
  overvejelse.

**Nyt, ikke-designet krav rejst i samme samtale: flersproget stamtræ** (tysk,
svensk, norsk, engelsk). Ikke en del af TNG-analysen — et selvstændigt fremtidigt
scope-punkt. Rejser ubesvarede spørgsmål (UI-i18n vs. indholds-i18n; hvor
oversættelse lander i evidenslaget; hvad der sker med `narrative`s ordret-prosa-
invariant på tværs af sprog) der kræver egen brainstorm, ikke besvaret her. Se
`docs/tng-reventlow-analyse.md` §8.

## Generation som kolonne, ikke fact; hul-reparation skriver aldrig (2026-07-05)

- **Slægtled = strukturel bog-koordinat pr. udgave** (som `nr`/`linje`), IKKE en omstridt
  påstand → plain kolonner på `person_external_id`, ikke evidenslag. Følger præcedensen
  `lineage.slaegtsnavn` (bevidst kolonne-ikke-fact). To tal fordi bogen selv nummererer
  dobbelt ("Første (tolvte)"): lokalt i linjen + gennemgående gennem moderlinjen.
- **Fallback-ringen er en ren read-time projektion.** En generations-nabo er en UBEVIST
  kandidat; at vælge den re-ankrer (navigation), og der oprettes ALDRIG en `relation`-kant.
  Fail-closed founder-hop (præcis ét moderlinje-mål, ellers ingen ring) frem for at gætte.
  Dual-review bekræftede invarianten på begge platforme.
- **Join-nøgle `(source_id, linje, nr)`** — `nr` resetter pr. gren (ikke globalt); NULL-linje
  karantænes. Backfill fail-closer på tvetydigt source-valg (TNG-source id 2 har 0 Roman-linjer,
  så DAA-source 1 resolves entydigt).

## Mediehåndtering: dokumenter/PDF/tekst-transskription — samme fundament, egen fase (2026-07-19)

Bruger-rejst behov: indscannede kilder (PDF/scanning, fx avisartikel om en person) +
artiklens rå tekst til læsbar visning/søgning; teoretisk også lyd/video.

- **Besluttet: samme media-system, IKKE et separat dokument-system.** `media` er
  allerede format-agnostisk (`mime_type`/`byte_size`/`slags`; vocab har `'scanning'`;
  `bredde`/`hoejde` nullable), og hele forvaltningsapparatet (rettigheds-workflow,
  gating, blødt slet/genopret, versionering, filside, bibliotek/køer) er
  format-neutralt — et separat system ville duplikere det hele. Kun klient-laget er
  billede-specifikt (variant-pipeline, Lightbox, `accept="image/*"`).
- **Transskription = narrativ-på-media** (`narrative` er allerede polymorf) —
  Wikisource-mønsteret: scanning + fts-søgbar læsetekst koblet 1:1. ⚠ Egen
  GDPR-designrunde påkrævet før implementering: tekst om (potentielt levende) person
  skal arve mediets afbildet-gating fail-closed.
- **Tilføjet som fase 5** i mediekonceptet (`docs/design/2026-07-19-mediehaandtering-robust-koncept.md`
  §4.8 + §9); uafhængig af fase 3–4. Lyd/video: kun "døren åben" (mime_type bærer
  dem), intet bygges før konkret behov.
- **Eneste konsekvens for fase 2 (biblioteket), indskrevet i spec'en:** defensiv
  rendering — ikke-billede-mime/manglende thumb → dokument-ikon, aldrig knækket
  thumbnail; udeladt af Lightbox.

## Levende feed fase 4 (LLM-assist): udskudt, ikke annulleret (2026-07-20)

Fase 3 (minihistorier & redaktionel styring) er kode-komplet på `main`. Fase 2+3-
skemaet (`haendelse`/`story`/`story_kilde`/`feed_pin`) blev deployet til prod samme
dag (se sektionen nedenfor) — men det ændrer ikke fase 4-vurderingen: Fase 4
("Foreslå historie"-Edge Function + proveniens, koncept §8+§10) sættes bevidst i
bero før spec-arbejdet påbegyndes.

- **Begrundelse:** PoC-korpusset har for få kilder indlæst til at LLM-assist giver
  reel værdi endnu, og scopet (Edge Function, kontekst-sammensætning på tværs af
  udgaver, proveniens) er for detaljeret at kaste sig over nu.
- **Ikke tabt arbejde:** rammen ligger allerede i koncept §8 (teknisk ramme) og
  fase 3-design §12, som bevidst efterlod ○b (hændelses-gruppering på tværs af
  udgaver) og ○c (skal `historie`-kort vise AI-oprindelse) åbne til fase 4. `story`
  har allerede `llm_model`/`llm_promptversion`/`llm_naar`-kolonner (forward-compat,
  ingen ny migration nødvendig ved genoptagelse).
- **Genoptages** når kilde-korpusset er vokset nok til at hændelses-mængden
  retfærdiggør redaktionel LLM-hjælp — ingen fast dato.

## Levende feed fase 2+3 prod-cutover: skema nu, hændelsesudtræk senere (2026-07-20)

Bruger vil have fase 2 (`haendelse`) + fase 3 (`story`/`story_kilde`/`feed_pin`)-skemaet i
prod. Fase 2's offline LLM-hændelsesudtræk (narrativ → `haendelse` via `daa-haendelser`-
skillen) er derimod aldrig kørt — hverken lokalt eller mod prod.

- **Besluttet: adskil skema-deploy fra dataudtræk.** Skemaet (tabeller/RLS/RPC'er) kræver
  ingen LLM-kørsel og er harmløst tomt — feed-motoren degraderer bevist gracefult til
  fase 1-adfærd (`packages/feed/src/pool.ts:32-44`), og `story` kræver ikke et
  `haendelse_id`-anker. Runbook:
  [`levende-feed-fase2-3-runbook.md`](levende-feed-fase2-3-runbook.md).
- **Opdatering samme dag:** skemaet blev deployet til prod 2026-07-20 — ikke via den
  forberedte `psql`-runbook, men direkte via Supabase MCP fra en parallel session
  (`docs/database-current-state.md` §3). Bundlingen med mediehåndtering fase 1+2 (næste
  punkt) indtraf som forudsagt. `db-rollback-fase2.sql`/`db-rollback-fase3.sql` fra
  runbooken er stadig relevante som rollback-beredskab.
- **Hændelsesudtrækket udskydes fortsat bevidst**, samme begrundelse som fase 4 (PoC har
  for få kilder til at retfærdiggøre en LLM-batch-kørsel over hele korpusset endnu) — men
  noteret eksplicit som en kommende opgave, ikke annulleret.
- **Bifund:** `db-migrations.sql`/`db-rls.sql` er monolitiske kumulative filer, så en
  fase 2+3-cutover bundler mediehåndtering fase 1+2-skema (samme filsektion, interleaved) —
  se runbookens ⚠-afsnit.

## Replay-dagen: fire beslutninger fra første ægte prod-replace (2026-07-31)

Hele replay-kæden (design → implementering → to skarpe prod-kørsler) landede på én
dag. Fire beslutninger med varig virkning:

- **De 48 unummererede genbruger identiteter — mint kun for beviseligt identitetsløse.**
  Sols fail-closed-stop afslørede at de "48 nye" stamfædre/oversigtsposter allerede
  havde parkerede registeridentiteter (legacy-lokatorer). Mint ville have skabt
  dublet-identiteter; i stedet om-nøgledes lokatorerne (#120-mønstret). Alternativet
  (mint + senere sammenlægning) blev forkastet: registerprincippet er "id mintes ÉN gang".
- **Strukturelle bortfald tombstones IKKE før prod-oprydning.** De 23 legacy-identiteter
  hvis person i v2 ligger i samleposter forbliver AKTIVE som "bortfaldne" — replace-
  designet lader bortfaldne bestå urørt, mens tombstone ville udløse loaderens
  tombstone-guard og blokere alle fremtidige replaces indtil prod-personerne er
  håndteret. Tombstone + oprydning er en senere samlet redaktionel operation.
- **Kildetekst-strategi for 1939: struktur fra raw, prosa fra Calamari.** De unummererede
  poster kan kun findes i raw.txt (centreringsinfo); Calamari-teksten giver bedre
  narrativ-kvalitet. build_1939_v2 kombinerer (415 Calamari / 131 raw) med krydstjekket
  match — hverken ren-raw eller ren-Calamari kunne levere begge dele.
- **Ny-klassen i --replace (replay-udfald 4).** Registerkendte record_keys uden
  prod-person oprettes ad append-vejen; hullet-guarden består for nøgler uden hverken
  prod-person eller artefaktpost. Aktiveret af mint-arbejdet; sol-reviewet GO.

Driftslæring: delt-workdir-racen ramte igen (anden session skiftede branch under en
kørende terra-batch) — stoppet, karantænet, genkørt med selektivt valideret genbrug.
Parallelle sessioner bør bruge git worktrees.

## Union-redigering + identitets-invarianter (2026-08-01)

- **`red_slet_union` bygget og derefter droppet.** Funktionen krævede referentiel
  integritet i en model der bevidst ikke har fremmednøgler på polymorfe referencer.
  Hver rettelse skubbede kravet videre ud: rækkelås → ni tabellåse → en fælles
  låseprotokol på tværs af loadere og RPC'er. Og racet kunne ikke lukkes med låse
  overhovedet — en ventende `red_suggest` fortsætter EFTER sletningens commit.
  Værdien var samtidig nær nul: de 15 mor-løse 1939-skaller kan **ikke** slettes
  alligevel, fordi bogens oprindelige forældrepåstande peger på dem (familie 726 er
  refereret 14 steder). Skallerne er ikke affald, men evidens der har mistet sin krop.
  Alternativet (byg en tombstone-/valideringsmekanisme) er selvstændigt arbejde.
- **Invarianter i triggere, ikke i RPC'er.** To-parts-loftet og identitets-guardsne
  ligger på `family_member` og `relation`, ikke i `red_tilfoej_partner`. En RPC-tælling
  dækkede hverken fortryd-stien (`_version_upsert_row` skriver rækker direkte tilbage)
  eller samtidige kald. Samme begrundelse som `enforce_samme_som_invariants` i sin tid.
- **Håndhævelsen skal være symmetrisk.** "Alias tilføjes som part nr. 2" og "to parter
  linkes bagefter som samme person" giver samme forbudte sluttilstand; med kun én guard
  afhang udfaldet af redaktørens klik-rækkefølge. Begge veje er nu spærret, i hver sin
  trigger.
- **`samme_som`-rolle og -endepunkter er uforanderlige.** Ændring kræver slet+genopret.
  Evidensen hænger på relationens stabile id, så en `UPDATE` ville genbruge en gammel
  kildehenvisning til en ny identitetspåstand. Alternativet (en `OLD`-ekskluderende
  graf-guard på UPDATE) blev forkastet: det ville tillade at en påstand skifter mening
  uden at skifte identitet.
- **Krydsracet mellem de to triggere er BEVIDST ikke lukket.** Advisory-låsen der ville
  lukke det inverterede rækkefølgen mod `load_daa.R` (loaderen tager EXCLUSIVE på
  `relation` og flusher `family_member` først, mens `red_samme_som` holder advisory-låsen
  og venter på `relation`) — en ægte deadlock-cyklus der kan abortere en hel load.
  Cyklussen kan ikke omarrangeres væk. Fuld lukning kræver BEGGE dele: låsen i
  `load_daa.R`/`load_presens.R`/`post_load_fixup.R` før deres `LOCK TABLE`, OG i
  partner-triggeren. Restrisikoen kræver to samtidige transaktioner og fanges bagefter
  af projektionen som karantæne, ikke som stille korruption — samme single-writer-
  antagelse som `red_tilfoej_barn`s cyklus-tjek allerede hviler på.

Review-læring: otte adversarial Codex-runder, og fundene skrumpede først da en
**funktion blev fjernet**, ikke da endnu en guard blev tilføjet — at droppe
`red_slet_union` lukkede tre HIGH på én gang. To gange rettede en Codex-rettelse ét
problem og skabte et nyt (alfabetisk låseorden inverterede projektets kanoniske orden;
advisory-låsen gav deadlock). Peer-review er ikke monotont forbedrende. Og
`get_advisors(security)` fangede efter deploy noget ingen af de otte runder så: to nye
`SECURITY DEFINER`-trigger-funktioner stod åbne for `anon` via Supabases default-grants.
Codex læser SQL; advisoren læser den kørende bases ACL.

## Grænsekontrollen ligger før materialisering, og massebekræftelse er droppet (2026-08-08)

**Placering.** Grænsekontrollen kræver eksakte, hash-låste spænd og skal ligge før
materialisering. Begge betingelser er opfyldt straks efter forankringen, så kontrollen
lægges der — ikke efter komponeringen, hvor en ugyldig rettelse er dyrere at kassere.
Efter materialisering er teksterne påstande, og påstande overskrives aldrig (invariant 1).
Første udgave hævdede at der kun fandtes ét muligt sted; det holdt ikke.

**Afløsning af accepteret evidens er forbudt i dag, og guarden skal ikke løsnes.**
`compose_human_evidence_bundle()` afviser at menneske-evidens erstatter en entry med
kandidater eller positiv proveniens. En grænserettelse ER en sådan erstatning, så fase 2
kræver én navngiven, autoriseret afløsningsoperation med eksplicit invalideringsgraf —
seks punkter, herunder stikprøve/audit og op til tre incidente grænser, fordi en flytning
ændrer begge nabospænd. Kandidat*formatet* kræver derimod ingen ny evidensart; det er
producent-neutralt. Formatet rakte, operationen manglede.

**Massebekræftelses-bunken er fjernet.** Den lovede at et hul var positivt bevist tomt,
herunder at der ikke var et trykt hoved i rå OCR's modsvarende stykke. Men det modsvarende
stykke findes ikke: et menneskeforankret Calamari-spænd er et delspænd inde i en
forekomst, mens dets `raw_structure_bridge` dækker hele den parrede rå-forekomst. **Målt:
0 af 352 forankrede spænd er spændpræcise; 349 er delspænd; kun 110 har en rå-bro.** Rå-
vinduet begyndte derfor at læse for sent i hvert enkelt tilfælde. Valgt løsning: drop
bunken, alle 446 grænser til individuel vurdering. Rå-kontrollen er ikke slettet men
**vendt** — et positivt fund er troværdigt, fraværet af et fund beviser intet — så den er
nu signalet `hoved_i_raa_ocr`. En spændpræcis kontrol via `align_renditions` er
forudsætningen for at genindføre en bunke. Afvist: at portere på Calamari alene, fordi det
er præcis den fejlmåde designet findes for.

**Revision 0 i fase 1 er tilsigtet.** Grænse-id bærer et revisionsnummer, men fase 1
ændrer aldrig et spænd, så der findes ingen anden revision. Bumpning og forældrekæde bygges
i fase 2 sammen med afløsningen. Reviewet kaldte det en spec-fejl; afgjort at planen gælder.

**Dagens gennemgående fejlmønster: fravær af bevis læst som bevis på fravær.** Otte
tilfælde. Sidemodellen der talte sider i stedet for at slå dem op; porten der kaldte et
ukontrolleret hul tomt; en opsummering hvor `har_broedtekst=0` slap igennem; et
injektivitetskald der udregnede sin egen godkendelseshash og dermed gjorde kontrollen
indholdsløs; et rå-OCR-vindue der ledte i den forkerte tekst; søskendegrupper bygget kun af
spænd-ejere, så `slugt_hoved` fyrede **0 gange** i et datasæt med fire kendte grænsefejl; en
tom kasse i UI'et der læstes som frikendelse; og kontekst der rakte ud over spændets kant
uden nogen markering. Fælles: koden bestod sine tests, fordi testene fodrede den med
sandheden. **Nul er et signal** — et signal bygget til en kendt fejl, der aldrig fyrer, er
et resultat om koden, ikke om dataene.

**Testværn skal måle egenskaben, ikke teksten.** Task 8's tests hævdede at de rigtige
strenge stod i den genererede HTML; filen var alligevel uparsebar, fordi generatoren skrev
`";\\n"` i stedet for et linjeskift — blank side, fundet af brugeren efter otte tasks, tre
reviews og en fix-bølge. Begge generatorer har nu en test der **parser** scriptblokken med
`node --check`, mutationstestet ved at genindsætte fejlen. Og gaten for det delte UI-modul
var **tallet 88**, ikke "grønne tests": et tal fanger en adfærdsændring som en farve skjuler.

**Delegering til Codex: arbejdsdelingen blev omvendt af sandkassen.** Delegaten kan ikke
committe (`index.lock` nægtet) og har ingen PyPI-adgang, og runtimen kører kun én opgave ad
gangen — et parallelt dispatch afvises, og en død proces kan efterlade en forældet
"kører"-lås der blokerer alt. Arbejdsdeling: delegaten skriver kode og tests, kontrol-
sessionen kører testene og committer med delegaten navngivet.

**ACL-ændringer afgøres af kalderens sikkerhedskontekst, ikke af funktionens egen.** Når
sikkerhedslinteren flager en `SECURITY DEFINER`-funktion som kaldbar af `anon`, afhænger det af
**kalderen**, om grantet kan fjernes: kaldes den kun inde i en anden `SECURITY DEFINER`-funktion,
kører det indre kald som ejeren, og `anon` kan undværes; kaldes den fra en RLS-politik eller en
`INVOKER`-funktion, kører kaldet som kalderens rolle, og et `revoke` lukker fladen fail-closed i
stedet for hullet. `media_synlig_anon`/`media_synlig_auth` er netop **ikke** DEFINER, hvilket er
let at overse, fordi alt omkring dem er det. Derfor blev `family_offentlig` lukket med et rent
`revoke`, mens `media_afbilder_skjult` og `media_id_for_object` kræver en indkapsling i én
DEFINER-funktion plus omskrivning af storage-politikkerne. Fravalgt: at fjerne grants efter
linterens liste alene — det ville have slukket billedvisningen for uindloggede.

**Forbrugersøgning skal omfatte projektets egen SQL-suite.** Før en ACL-ændring blev der søgt
efter forbrugere i `web/src`, `mobile` og `packages` — nul træf blev læst som "ingen". Men
`db-verify.sql` kaldte selv `family_offentlig` som `anon`, og tre CI-jobs faldt på den ene
linje. Prod tog ikke skade, alene fordi db-verify aldrig køres mod produktion (#198). Søg altid
også i `db-verify.sql` og `tests/sql/`. Testen blev rettet til at efterprøve den nye kontrakt
frem for at blive gjort tavs: gatens logik som ejer, anons faktiske vej gennem
`entitet_offentlig`, og at det direkte kald nægtes — den sidste påstand fanger et fremtidigt
genudstedt grant i CI i stedet for i prod.

**Sletning kræver måling først (global arbejdsregel, indført 2026-09-19).** En egenskab ved
*noget andet* — branch merget i main, nyere fil findes, git kender den ikke — er aldrig bevis
for, at indhold er undværligt; `.gitignore` er netop listen over, hvor de to ting ikke falder
sammen. Indholdet skal måles og vises i samme besked som forespørgslen, artefaktets navn slås op
i de store memory-filer, og reversible skridt foretrækkes: omdøb til `slet_<dato>__…` med frist
frem for `dropdb`, flyt til karantæne frem for `rm -rf`. En arbejdsmappe fjernes aldrig, mens en
agent kan arbejde i den. Baggrund: en oprydning 18/9 slettede et fredet prod-dump og var ved at
slette 4.4's restore; se changelog 2026-09-19.
