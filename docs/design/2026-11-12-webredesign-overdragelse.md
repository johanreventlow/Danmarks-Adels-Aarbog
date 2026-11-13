# Webredesign — overdragelse til kode (2026-11-12)

Overdragelse af redesignet af den offentlige webflade (`web/`, publikumsdelen i `Folgesvend.tsx`). Redaktionsfladen
(`/redaktion`) og mobilappen (`mobile/`) er ikke omfattet, ud over fælles tokens (fase 1).

## Kilder

| Hvad | Hvor |
| --- | --- |
| Beslutninger | `docs/decisions.md`: de to indførsler »webredesign …« fra 2026-11-12 |
| Designgennemgang med review | Claude-dok »Designgennemgang – Danmarks Adels Aarbog app« (https://claude.ai/artifact/EZwn2CNjbMZPKho87EWaEr) |
| Designsystem | »Danmarks Adels Aarbog« (https://claude.ai/artifact/QgFLNK9o4pgu791LQEFoXn): `project/README.md` og `project/tokens.json` |
| Tegninger | Canvas »Aarbogen – web redesign« (https://claude.ai/artifact/AodEDRH5DMkuMVRybHWuGd) |
| Målestok | `web/scripts/designtour/` (skærmbilleder før og efter, testdata født ≤ 1930) |

Tegningernes tekster er foreløbige; formuleringerne gennemgås samlet senere. Pladsholdere i `[…]` er data, der mangler i
testudtrækket, ikke tekst der skal bygges.

## Rækkefølge

Hver fase er en selvstændig PR med designtour-billeder før og efter. Faser markeret **blokeret** venter på et åbent
punkt (nederst).

0. **Fejlrettelser uden designafhængighed**
   - `/redaktion` kræver login, før arbejdsbordet vises.
   - Præsenslisten fjernes fra den offentlige menu, til fase 8.
   - Tomme tilstande og fejl skrives til læseren (tegning »Tomme sider og fejl«).
   - Monogrammer tager kun bogstaver (»Adelheid (Lilli)« → »AL«, ikke »A(«).
   - Kolonnevisning: navne løber ikke ind under bogmærkeikonet.
   - Login-dialog: label på adgangskodefeltet.
1. **Fælles tokens og selvhostede skrifter**
   - Én kilde til tokens for web og mobil (fx `packages/theme`), med navne og værdier fra designsystemets `tokens.json`.
     `web/src/theme.ts` og `mobile/src/theme/tokens.ts` læser derfra.
   - Hårdkodede farver i komponenter erstattes efter oversættelsestabellen i designsystemets README (»Fra den nuværende
     kode«). Ingen visuel ændring ud over rettet kontrast.
   - Skrifterne (Cormorant Garamond, Hanken Grotesk, JetBrains Mono) serveres fra egen server, ikke Google Fonts.
2. **Routing, sidehoved og slægtsbjælke** (navigation model 2)
3. **Personsiden** (anonym)
4. **Hovedsiden og feedet**
5. **Slægtens forside og stamtræet** (linjegenveje **blokeret**)
6. **Er vi i familie? og søgning**
7. **Godser**
8. **Medlemslag: personsidens B-lag, Min plads, præsensliste** (**blokeret**)
9. **Mobil web** (læselayout for personside, søgning, slægtskab og delte links)

## URL'er

Ny grammatik. Gamle stier omdirigeres (`replace`), så eksisterende links virker.

| Ny sti | Indhold | Gammel sti |
| --- | --- | --- |
| `/` | Aarbogens hovedside | `/` |
| `/slaegt/:slaegt` | Slægtens forside | `/about` |
| `/slaegt/:slaegt/stamtrae[?fokus=:person]` | Stamtræ | `/stamtrae` |
| `/slaegt/:slaegt/praesens` | Præsensliste (medlemmer) | `/praesens` |
| `/slaegt/:slaegt/godser` | Godser, liste og kort | `/estates`, `/kort` |
| `/slaegt/:slaegt/vaaben` | Våben | `/arms` |
| `/person/:id` | Personside (over slægterne) | `/person/:id` (var stamtræ med panel) |
| `/gods/:id` | Gods-side | `/estate/:id` |
| `/slaegtskab[?a=:id&b=:id]` | Er vi i familie? Resultatet kan deles | `/relate` |
| `/soeg?q=…` | Søgeresultater | (modal) |
| `/historie/artikler`, `/historie/kilder` | Historie | (kom ikke) |
| `/min-side`, `/min-side/bogmaerker` | Min plads og synlighed, bogmærker | `/bookmarks` |

`:slaegt` er et stabilt slug (`reventlow`). Linjer får **ikke** romertal i URL'en (se åbent punkt 1).

## Skærme og acceptkriterier

Tegningernes navne står i parentes.

### Sidehoved og navigation (»Navigation model 2 · …«)

- Hovedmenu: Personer · Slægter ▾ · Slægtskab · Historie ▾. Personer og Slægtskab er links. Slægter og Historie er
  knapper med `aria-expanded`, åbnes ved klik, Enter eller pil ned, lukkes med Esc og ved klik udenfor. Ingen hover-
  åbning.
- »Slægter« viser kun en vælger: »Find slægt«, A–Å, senest besøgt (ved første besøg: slægter med nyt), link til hele
  registret. Klik på en slægt → `/slaegt/:slaegt`.
- »Historie« viser Artikler og Kilder og udgaver. Kun sider, der findes; ingen »kommer«-punkter nogen steder.
- Søgefeltet i sidehovedet fører til `/soeg?q=`; »Personer« fører til samme side uden søgeord.
- Under `/slaegt/:slaegt/*`: slægtsbjælke med våben, navn (link til slægtens forside), slægtens sider med `aria-current`
  og »Skift slægt«. Ikke på `/person`, `/slaegtskab`, `/soeg`, `/historie`, `/min-side`.
- »Redaktion ↗« vises kun for brugere med rollen redaktion.

### Hovedside (»Hovedside A · Værket (valgt)«)

- Rækkefølge: titel og søgning · slægtsregistret · »Nyt i Aarbogen« og en lille indgang til »Er vi i familie?« · feedet.
- Med færre end tre slægter vises registret kompakt, og feedet bærer siden.

### Feedet (hovedside og slægtens forside)

- Korttyper: biografi-uddrag, gods, embede, forbindelse, citat fra bogen, »kun et navn i bogen«; senere »på denne dag«.
- Aldrig to ens korttyper i træk; intet kort to gange pr. bruger (genbrug `seenCards`/`feedResume`); højst ét »kun et
  navn« pr. seks kort; redaktionens fastgjorte kort (`feed_pin`) respekteres.
- Hvert kort linker til sin side og viser kilde (§). Ingen likes, tællere eller uendelig scroll på web: »Vend seks blade
  mere« og »fortsætter hvor du slap«.
- Levende personer optræder kun efter eget valg (beslutning 8).

### Personsiden (»Personside · for alle (valgt)«, »… lag for indloggede medlemmer (valgt)«)

- Egen side på `/person/:id`. Bogark med etiket (slægt · linje · nr.), navn, livsdatoer som bogen skriver dem,
  titel/embede, udgavevælger (visning C fra trin 6e), biografi ordret, familie, embeder (de første 7, så »Vis alle«),
  godser, billeder og dokumenter, »Kilde i Aarbogen«.
- Højre spalte: portræt med billedtekst (kunstner, år, ejer), slægtens våben med link, »Vis i stamtræet« (primær),
  »Find slægtskab«, »Kopiér link«.
- Mangler siges med ord (»Ikke angivet i den valgte udgave«), aldrig tomme felter.
- Tilhører personen flere slægter, vises alle i etiketten.
- Medlemslag (fase 8) på faste pladser i samme layout: slægtskab som kontekst over titlen (»Conrad er din …«, kræver
  bekræftet »Det er mig«), bogmærke i højre spalte, fakta med kilde pr. linje og »UENIGE KILDER« hvor udgaverne er
  uenige. Ingen layoutskift ved login.

### Slægtens forside (»Slægtens forside · Reventlow«, »Navigation model 2 · slægtsbjælken (web)«)

- Våben med kildenote, indledning (narrativ `slaegt`) med kilde, linjer, »Redaktionen foreslår«, slægtens feed.
- De fire indgangskort fra tegningen udgår; slægtsbjælken erstatter dem.

### Stamtræet (»Stamtræ · fokus (web)«, »Stamtræ · fokus (mobil)«)

- Rækker med etiketter: forældre · søskende · gift · børn. Hele søskendeflokken, rulles vandret, intet skæres af;
  piletaster flytter fokus.
- Alle ægteskaber med navn; børn grupperes pr. ægteskab, når data angiver det, ellers samlet med note.
- `family_member.konfidens` formodet/omstridt: stiplet kant og ordet på forbindelsen.
- Manglende forælder: »Mor ikke angivet i bogen«.
- Ægtefælle fra en anden indlagt slægt linker til den slægts træ.
- Panelet er en genvej (resumé + »Åbn personsiden«), ikke en erstatning for personsiden.
- Mobil: synlige pile mellem søskende; swipe kun som supplement.

### Er vi i familie? (»Er vi i familie? (web)«, »… (mobil, indlogget)«)

- Valgte personer ligger i URL'en; resultatet kan deles og åbnes direkte.
- Resultat: slægtskabsord (kønsbestemt hvor køn kendes), fælles ane, antal slægtled, sikkerhed. Vejen trin for trin
  med fælles ane fremhævet. Formodet led: ordet, stiplet streg og »sandsynligvis« i resultatet. Flere veje: »1 af N«.
- Mobil: »Det er mig« som første person, når det er sat.

### Søgning (»Søgeresultater (web)«)

- Filtre: type, slægt, linje, levetid (usikre datoer tæller med, hvis spændet rører perioden). Søgeord fremhævet.
- Ingen resultater: forslag til stavemåder (Reventlow/Reventlou).

### Gods (»Gods · Clausholm«)

- Ejerrækken kronologisk med perioder som bogen skriver dem; ejere uden for de indlagte slægter, når de findes.

### Min plads og præsensliste (»Min plads og synlighed«, »Præsensliste (medlemmer)«) — blokeret

- Bygges først efter åbent punkt 2 og 3. Tegningerne viser hensigten: grundniveau, »Bed om at blive skjult«, ekstra
  deling fravalgt fra start, historik over valg; præsenslisten kun for medlemmer med skjulte personer talt, ikke vist.

## Tværgående krav

- **Designsystem:** kun tokens; ingen tekst under 11 px; `gold` aldrig som tekstfarve (`gold-ink`); fokusring 2 px
  `focus` med 2 px afstand.
- **Tilgængelighed:** rigtige `<button>` og `<a href>`; alt kan bruges med tastatur; `aria-current` på aktiv side;
  `prefers-reduced-motion` respekteres.
- **Bredde:** sider uden panel udnytter bredden; intet layout må efterlade højre halvdel tom.
- **Data:** usikre datoer vises som bogen skriver dem; kilder vises; usikkerhed skjules aldrig (invariant 5–7); levende
  efter beslutning 8.
- **Designtour:** udvid `STEPS` med de nye sider, også ved 390 px bredde.

## Åbne punkter

1. **Linjernes betegnelse pr. udgave.** Blokerer linjegenveje og linjesider.
2. **Arbejdsgang for at bekræfte »Det er mig«.** Blokerer slægtskab som kontekst og Min plads.
3. **Grundlag for grundniveau for levende, børns standard og koden til at finde en levende person** (afklares med
   databeskyttelsesrådgiver). Blokerer præsensliste for medlemmer og slægtskab med levende.
4. **Tekster:** samlet gennemgang af formuleringer.
5. ~~**Heraldik:** grundvåbnet er ikke en autoriseret tegning; godkendes før offentlig brug.~~ Lukket 2026-11-13:
   præmissen var forkert. Ingen dansk instans autoriserer adelsvåben; Aarbogen bruger den tegning, den foretrækker
   (`docs/decisions.md`, 2026-11-13).
