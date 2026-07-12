# Review 26 — UX & navigation: web + mobil (koncept-review)

**Dato:** 2026-07-09
**Scope:** Navigations- og UX-*konceptet* i begge produkter — webbens v4-model
(mega-menu + forside + søgning-i-træ, jf. design-brief
`docs/design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md`, reviews 23+24)
og mobilens v3-model (5 tabs + drawer + forsidefeed). Ikke et kode-review; fund
handler om struktur, forståelighed og sammenhæng. Meget er endnu ikke bygget —
reviewet vurderer det *planlagte* koncept mod den faktiske implementeringstilstand.

**Metode:** kodekortlægning af `web/src/` (nav.ts, Folgesvend.tsx, HomeView) og
`mobile/src/` (tabs, MenuDrawer, buildFeed, person/tree-skærme), læsning af
design-briefet + reviews 23/24, samt interview med produktejeren (fire
retningsspørgsmål, se §1).

---

## 1. Præmisser (afklaret ved interview 2026-07-09)

Disse fire beslutninger er reviewets grundlag — fund måles mod dem, ikke mod en
generisk "best practice":

1. **Bevidst forskellige paradigmer.** Web er opslagsværket/arkivet
   (temaer, mega-menu, split-skærm); mobil er lomme-ledsageren (feed, tabs).
   De skal *ikke* konvergere strukturelt — men hver især være stringent.
2. **Mobil beholder både tabs og drawer** — med en tydeligere rollefordeling
   end i dag.
3. **Målgruppen er bred:** ældre foreningsmedlemmer, nysgerrige nybegyndere,
   forskere/genealoger *og* unge medlemmer der vil lære slægten at kende.
   Konsekvens: navigationen skal være selvforklarende før den er kompakt —
   ingen funktion må afhænge af hover, gestures eller indforståede labels.
4. **Web-forsiden forbliver hybrid** (søge-hero + kuraterede indgange + levende
   element), men med **flere startpersoner og mere dynamik** — indholdet skal
   opleves opdateret ved genbesøg.

---

## 2. Status-billede (verificeret mod koden)

| | Web (`web/`) | Mobil (`mobile/`) |
|---|---|---|
| **Paradigme** | Temaer (Slægten · Godser & steder · Historie) i hover-mega-menu; forside som indgang; søgning integreret i stamtræet | Forsidefeed (9 korttyper) + 5 bund-tabs (Hjem · Stamtræ · Slægtskab · Søg · Konto) + hamburger-drawer (8 nummererede punkter) |
| **Implementeret** | §3 mega-menu + §6 forside + §4 søgning-i-træ (ukommitteret, dual-reviewet 23+24) | v3 merget (PR #23) + konto-bogmærker (PR #25) |
| **Udestår** | §5 split-skærm; konto-klynge (bogmærkers hjemsted); 7 "kommer"-punkter | Editorial feed-overrides (no-op-krog); våben-medier; bogmærker i træet |
| **Kendte huller** | `/bookmarks` uden synlig indgang (planlagt, review 24 M2) | Redaktør-crash ved person-åbning (urapporteret root cause, separat spor) |

---

## 3. Tværgående fund — det der SKAL være fælles trods forskellige paradigmer

Beslutningen "bevidst forskellige" flytter konsistenskravet fra *struktur* til
*ordforråd og primitiver*. Medlemmer bruger begge produkter; de tilgiver
forskellige menuer, men ikke at samme ting hedder noget forskelligt.

### T1 · Samme destination, tre navne (HØJ, lav indsats)

Slægtskabssøgningen — projektets kernefunktion — optræder i dag under tre labels:

| Kontekst | Label |
|---|---|
| Web mega-menu | **Slægtskab** |
| Web view-titel + detalje-knap | **"Er vi i familie?"** / **"Find slægtskab"** |
| Mobil tab | **Slægtskab** |
| Mobil drawer punkt 06 | **"Er vi i familie?"** |
| Mobil person-knap | **"Slægtskab"** |

Bemærk at inkonsistensen findes *inde i mobilen selv* (tab vs. drawer). Forslag
til kanonisk regel: **nav-label = "Slægtskab"** (kort, konsistent),
**sidetitel = "Er vi i familie?"** (krogen, det plain-language spørgsmål),
**handling fra en person = "Find slægtskab"** (verbum, siger hvad der sker).
Tre roller, tre former — men altid den samme form i den samme rolle, i begge
produkter.

### T2 · "Godser & steder" vs. "Godser & ejendomme" (MELLEM, lav indsats)

Webbens tema hedder *Godser & steder*; mobilens drawer-punkt 03 hedder *Godser &
ejendomme*, og 04/05 hedder *Slægtens kort* / *Slægtens våben* hvor web blot
siger *Kort* / *Våben*. Vælg én form. Anbefaling: webbens korte former som
kanoniske ("Godser", "Kort", "Våben") — mobilens "Slægtens …"-præfiks er
stemningsfuldt men gør skanning langsommere, og i en drawer med sektioner
(se M2) bærer sektionen konteksten.

### T3 · Kanonisk ordliste mangler som artefakt (MELLEM)

Ingen fil ejer i dag vokabularet. Anbefaling: en kort `docs/design/ordliste.md`
(destination → nav-label → sidetitel → handlingsverbum) som begge produkter
refererer. Den er billig at skrive nu (13 destinationer) og forhindrer at hver
ny skive genopfinder navne. Samme liste bør fastfryse de gennemgående
primitiver, der allerede *er* fælles og fungerer: person-kortet
(avatar + serif-navn + mono-år), bogmærke-ribbon, konfidens-visning,
A–Å/Født-sortering og linje-chips.

### T4 · Bogmærker: to produkter, to modenhedsgrader (HØJ)

Mobil har fuld bogmærke-flade (badge i topbar + drawer 08 + login-synk). Web har
funktionen (ribbon på kort + filter-chip i søgningen + `/bookmarks`-view) men
**ingen synlig indgang** til listen — den planlagte konto-klynge (§7/§9.e) er
ikke bygget. Det er en bevidst mellemtilstand (review 24 M2), men den bør have
kort levetid: en bruger der bogmærker på mobilen og åbner web, kan ikke *finde*
sine bogmærker. Anbefaling: prioritér konto-klyngen som næste web-skive efter
§5-splitten — en lille dropdown ved konto-indikatoren med
**Bogmærker · Det er mig · Log ud** dækker behovet.

### T5 · Slægtskabs prominens divergerer — gør det til en bevidst beslutning (LAV)

Web nedtoner bevidst Slægtskab (ét punkt under et tema, brief §5.6); mobil løfter
det til top-level-tab. Under "bevidst forskellige" er det forsvarligt — mobilen
er krog-enheden ("er vi i familie?" ved middagsbordet), webben er fordybelsen.
Men skriv rationalet ned (fx i `docs/decisions.md`), så en fremtidig
"hvorfor er det ikke ens?"-diskussion har et svar.

---

## 4. Web-fund

Konceptet er stærkt: temaerne skalerer til mange emnetyper, "live ✓ / kommer"-
ærligheden matcher tonen, URL-som-sandhed er gennemført, og søgningen-i-træet
(review 24) løser briefets kerneproblem. Fundene er kalibrering, ikke omvæltning.

### W1 · Hover-only mega-menu er utilgængelig for dele af målgruppen (HØJ)

Mega-menuen åbner på hover med 120 ms intent-delay (`Folgesvend.tsx:216-221`).
Med målgruppe-præmissen (§1.3) er det tungeste fund:

- **Touch har ingen hover.** Briefet afgrænser til desktop/mus, men smal/touch-
  browser er erklæret "senere spor" — og hover-only gør det spor dyrere, fordi
  navigationens rygrad så skal gentænkes i stedet for genbruges.
- **Keyboard-brugere kan ikke åbne den.** Tre midter-labels uden klik-mål er
  reelt døde for tastatur (og skærmlæsere).
- **Ældre brugere med nedsat finmotorik** rammer "musen forlod fladen → menuen
  lukkede"-fælden oftere end unge.

Anbefaling (bevarer designet, ændrer kun aktivering): **klik/Enter åbner og
fastholder** menuen (hover som progressiv forbedring ovenpå), Escape/klik-udenfor
lukker, og tema-labels får `aria-expanded`. Overvej desuden briefets egen åbning
(§3.1: hvert tema "*kan* have en oversigtsside") — en simpel tema-landingsside
pr. tema giver et klik-mål, der fungerer på alle inputtyper og er et naturligt
hjem for "kommer"-punkternes løfter.

### W2 · 7 af 13 menupunkter er "kommer" (MELLEM)

Historie-temaet er 100 % "kommer" (5/5), Godser & steder 50 %. Ærligheden er
rigtig (brief §8.4) — men *doseringen* kan kalibreres: en menu hvor over
halvdelen er uindfriede løfter, risikerer at læse som "appen er ikke færdig"
frem for "her kommer mere". Anbefaling: behold strukturen (den er pointen —
layoutet skal rumme visionen), men komprimér visningen: vis fx de første 1-2
kommer-punkter pr. tema + en samlelinje ("… og 3 emner mere på vej"), eller giv
Historie-kolonnen én samlet, indbydende "under opbygning"-tekst i stedet for fem
grå punkter. Genbesøg når første Historie-punkt går live.

### W3 · §9.d-underspørgsmålet (detalje-åben i URL?) har et naturligt svar (MELLEM)

Briefet lader det stå åbent om split-tilstanden skal i URL'en. Anbefaling: **lad
URL-grammatikken, der allerede findes, bære det** — `/person/:id` *betyder*
"detalje åben for denne person", `/stamtrae` *betyder* "fuldt træ, ingen
detalje". Luk-handlingen navigerer altså til `/stamtrae` (med `replace` for ikke
at forurene historikken). Det giver delbare links med korrekt tilstand gratis,
ingen ny state-dimension, og back-knappen opfører sig forudsigeligt. Undgå en
separat `?detail=open`-dimension — to sandhedskilder om samme tilstand.

### W4 · Forsidens dynamik: byg på data I allerede har (MELLEM — jeres ønske fra §1.4)

Nuværende forside: hero + 4 kuraterede startpersoner + "Nyt i arkivet" med
månedens gods. Ønsket er flere startpersoner og mere levende indhold ved
genbesøg. Konkrete, billige greb (alle datakilder findes allerede):

1. **Rotér de kuraterede startpersoner deterministisk** — et kurateret udvalg på
   fx 12-20 personer, hvoraf 4-6 vises pr. dag/uge (dato-seedet udvælgelse, som
   `pickMaanedensGods` allerede gør). Redaktionen kuraterer poolen; rotationen
   giver dynamikken.
2. **"Nyt i arkivet" fra `change_set`** — redaktionelle tilføjelser logges
   allerede i databasen; de seneste N ændringer ("3 personer opdateret i denne
   uge") er ægte nyhedsværdi uden nyt redaktionelt arbejde.
3. **"På denne dag i slægten"** — fakta med datoer (fødsler, dødsfald, bryllupper)
   matchet på dagens dato. Mobilens `buildFeed` har allerede jubilæums-logik
   (korttypen `jubilaeum`) — genbrug *beregningen*, ikke feed-formen.
4. **Månedens gods** findes — overvej samme mønster for "månedens våben/linje".

Vigtig afgrænsning ift. præmis §1.1: web-forsiden skal genbruge mobilens
*datakilder*, ikke dens *feed-form*. Formen forbliver rolige, kuraterede
sektioner med faste pladser — det er indholdet på pladserne, der roterer. Så
opnås "dynamisk ved genbesøg" uden at arkivet bliver et scrollfeed.

### W5 · Header-søgeikonet: kontekst-hop kan desorientere (LAV)

⌕ i headeren hopper til stamtræet og fokuserer søgefeltet (§9.c-forslaget,
implementeret i review 24). Fra forsiden er det fint (hero'en gør det samme).
Fra fx Godser er "klik søg → du står pludselig i stamtræet" et kontekstskifte,
brugeren ikke bad om. Acceptabelt nu (søgning ER personsøgning), men når
universel søgning kommer, bør ⌕ åbne søgning *over* den flade man står på.
Ingen handling nu — blot: byg ikke mere logik oven på "⌕ = gå til træet".

### W6 · Småting (LAV)

- **Slægt-chippen (Reventlow ▾)** er kosmetisk med én slægt. Fint — men giv den
  ingen dropdown-affordance (▾) før der ER noget at vælge; en chip der ligner en
  menu men intet gør, koster tillid hos netop de brugere, der tøver mest.
- **`home`/`bookmarks` ligger uden for tema-strukturen** i `nav.ts` — korrekt
  (utility ≠ indhold, brief §7), bare hold linjen når nye views kommer til.

---

## 5. Mobil-fund

Feedet som levende indgang fungerer (9 korttyper, alle med klare klik-mål), og
tabs'ene dækker kerneflows. Fundene samler sig om drawer'ens uafklarede rolle.

### M1 · Tabs og drawer overlapper uden rollefordeling (HØJ)

I dag dublerer draweren tre af fem tabs (01 Stamtræ, 06 Er vi i familie?
[= Slægtskab-tab'en], 07 Søg) og tilføjer fem punkter, tabs'ene ikke har (Om
slægten, Godser, Kort, Våben, Bogmærker). Brugeren kan ikke se noget system i,
hvad der bor hvor — og det er præcis den "tydeligere rollefordeling",
interviewet efterspurgte. Anbefalet kontrakt:

- **Tabs = handlinger/flows** (Hjem · Stamtræ · Slægtskab · Søg · Konto) —
  urørt.
- **Drawer = emnekataloget** — alt det, tabs'ene ikke er: Om slægten, Godser,
  Kort, Våben, Bogmærker (+ fremtidige Historie-emner). **Fjern de tre
  dubletter.** En destination har ét hjem; genveje er feedets job (feed-kort
  linker allerede til relate/search).
- Draweren bliver dermed funktionelt mobilens pendant til webbens
  "emne-temaer" — konceptuel slægtskab uden strukturel konvergens (præmis §1.1
  respekteret).

Bonus: en drawer på 5-6 emnepunkter + konto-footer er kort nok til at sektioner
(se M2) kan stå med luft, i det redaktionelle udtryk.

### M2 · Drop nummereringen 01-08; brug sektioner (MELLEM)

Drawer-punkterne er nummererede (01 Stamtræ … 08 Bogmærker). Nummerering
signalerer *sekvens* — men der er ingen rækkefølge i et emnekatalog; det er
dekoration, der ligner information. Med M1-oprydningen: erstat numrene med 2-3
sektionsoverskrifter (fx **Slægten** / **Godser & steder** / *Personligt*), i
mono-kicker-stilen. Sektionerne kan genbruge webbens temanavne — ordforråds-
konsistens (T3) uden struktur-konvergens.

### M3 · Feedet er eneste Hjem-indhold — giv genkendelighed et anker (MELLEM)

Hjem = hero (tællere) + feed. Feedet er stærkt til opdagelse, men svagt til
*genfinding*: en ældre bruger, der "vil ind til det der stamtræ igen", skal
enten kende tab'en eller scrolle et feed, der har byttet indhold siden sidst.
To billige greb: (a) en fast, lille række "faste indgange" mellem hero og feed
(Stamtræ · Godser · Våben — spejler drawerens emner, lærer brugeren dem at
kende); eller (b) lad hero'ens tællere være klikbare (personer→Søg,
linjer→Stamtræ, godser→Godser). (b) er nul ny UI. Feedets `opts.overrides`-krog
(editorial pin) er i øvrigt stadig no-op — når den bygges, dækker "pinnet kort
øverst" samme behov redaktionelt.

### M4 · Bogmærkers placering: badge + drawer, men ikke Konto (LAV)

Bogmærker nås via topbar-badge og drawer 08, og er login-eksklusive — men
*Konto*-tab'en, hvor login bor, nævner dem ikke. Webbens beslutning (§9.e:
bogmærker hører til i en personlig/konto-klynge) er rigtig også her: tilføj en
"Bogmærker"-række på Konto-skærmen. Så er der ét forudsigeligt sted, hvor alt
personligt (login, "det er mig", bogmærker, redaktion-adgang) samles — og
drawer-punktet kan flytte til drawerens *Personligt*-sektion (M2).

### M5 · Redaktions-fladen: god adskillelse; kendte tekniske huller (LAV — separat spor)

Adskillelsen publikum/redaktion er rigtig (eget segment, egen tabbar, exit via
"Følgesvend"-tab'en). To tekniske noter fra kortlægningen, der hører til
crash-sporet (kendt: redaktør-crash ved person-åbning): kun 4 redaktions-ruter
er eksplicit registreret i Stack'en (`redaktion/_layout.tsx:18-20` — bl.a.
`historik/[id]` og flere `entitet/*`-ruter mangler), og `router.push(... as
never)`-kaldene omgår typedRoutes-tjekket. Uden for dette reviews scope, men
registreringen bør med, når crashen debugges.

---

## 6. Prioriterede anbefalinger (samlet)

| # | Anbefaling | Produkt | Effekt | Indsats |
|---|---|---|---|---|
| 1 | **Kanonisk ordliste** — én term pr. destination/rolle (T1-T3); ret "Er vi i familie?"-drawer-punktet og "Godser & ejendomme" | Begge | Høj | Lav |
| 2 | **Mega-menu: klik/Enter som primær aktivering** + aria; overvej tema-landingssider (W1) | Web | Høj | Lav-mellem |
| 3 | **Konto-klynge med Bogmærker-indgang** — lukker den usynlige `/bookmarks` (T4) | Web | Høj | Lav |
| 4 | **Drawer-kontrakt: fjern tab-dubletter, sektioner i stedet for numre** (M1+M2) | Mobil | Høj | Lav |
| 5 | **Forside-dynamik fra eksisterende data**: roterende startpersoner, change_set-drevet "Nyt i arkivet", "på denne dag" (W4) | Web | Mellem-høj | Mellem |
| 6 | **§9.d-regel: URL'en ER split-tilstanden** (`/person/:id` = åben, `/stamtrae` = lukket) — lås inden §5 bygges (W3) | Web | Mellem | Nul (beslutning) |
| 7 | **Bogmærker-række på Konto-skærmen** (M4) | Mobil | Mellem | Lav |
| 8 | **Komprimér "kommer"-visningen** i Historie-kolonnen (W2) | Web | Mellem | Lav |
| 9 | **Klikbare hero-tællere / faste indgange på Hjem** (M3) | Mobil | Mellem | Lav |
| 10 | **Nedskriv Slægtskab-prominens-rationalet** i `docs/decisions.md` (T5) | Docs | Lav | Nul |

Rækkefølge-logik: 1-4 er lav-indsats-fund, der kan tages før/sammen med
§5-splitten; 5 er et selvstændigt forside-spor; 6 er en beslutning, der *skal*
tages inden §5-implementeringen alligevel.

---

## 7. Det, der allerede er rigtigt (bevar)

- **Temaerne som webbens rygrad** — skalerer, og "logo = hjem"-modellen frigør
  bjælken. Beslutning §9.a/b holder.
- **Søgning-i-træet med person-kort som resultater** — genkendeligheds-idéen
  (resultater ER træets kort) er konceptets bedste enkeltgreb.
- **"Live ✓ / kommer"-ærligheden** — behold princippet; kun doseringen (W2)
  kalibreres.
- **URL som sandhed** (web) og **feed-kort med klare klik-mål** (mobil).
- **Person-kortet som fælles primitiv på tværs af begge produkter** — det er
  dét, der får to forskellige paradigmer til stadig at føles som ét værk.
- **Publikum/redaktion-adskillelsen** i begge produkter.

---

*Grundlag: kodekortlægning 2026-07-09 (web: `nav.ts`, `Folgesvend.tsx`,
`HomeView.tsx`, `browse.ts`; mobil: `(tabs)/_layout.tsx`, `MenuDrawer.tsx`,
`buildFeed.ts`, `person/[id].tsx`, `tree.tsx`, `redaktion/_layout.tsx`),
design-brief 2026-07-08, reviews 23+24, produktejer-interview (§1). Fund markeret
efter vurderet vægt (HØJ/MELLEM/LAV); alle kodehenvisninger verificeret af
kortlægningen, anbefalinger er forslag til beslutning.*
