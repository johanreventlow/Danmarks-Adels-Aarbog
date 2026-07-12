# Designbrief — Følgesvend (web): navigation, søgning & stamtræ

**Formål:** en gennemarbejdet UX-/designbeskrivelse af en ny navigations- og
læsemodel for **web-browser-versionen** (`web/`, publikums-følgesvenden). Dokumentet
er en *brief til visuel implementering* (Claude design) — det beskriver struktur,
adfærd og hensigt, ikke pixels. Det er et levende koncept, vi videreudvikler over tid.

**Scope:** kun web-browser (desktop, mus). React Native-appen (`mobile/`) er **ude
af scope** — genbrug af koncepter til mobil er en bonus, ikke et krav. Smal/touch-
browser er et *senere spor* (se §10 Ikke-mål).

---

## 1. Hvad appen er (kontekst for designeren)

Følgesvenden er en digital ledsager til *Danmarks Adels Aarbog* — et levende,
slægtskabssøgende supplement til det trykte værk. Proof-of-concept dækker familien
**Reventlow** (~920 personer). Slægtskabssøgning ("er vi i familie?") er en vigtig
funktion i projektet, men i *denne* designs navigation behandles den som ét view
blandt flere — ikke som et visuelt omdrejningspunkt (se §5.6). Oplevelsens tyngde
ligger i at *udforske slægten*: personer, deres biografier, godser og værket.

**Visuelt sprog (skal bevares — det er allerede etableret):**

| Rolle | Token | Værdi |
|---|---|---|
| Baggrund (side) | `pageBg` | `#ece6da` |
| Papir/kort | `paper` | `#fbf8f1` |
| Panel | `panel` | `#f4efe6` |
| Blæk (tekst) | `ink` | `#221f1a` |
| Primær (bordeaux) | `bordeaux` | `#881A33` |
| Guld (accent) | `gold` | `#b9a06a` |
| Dæmpet tekst | `muted / muted2 / muted3` | `#6f675b` / `#9a8f78` / `#a99f8c` |

- **Serif** (overskrifter, navne): Cormorant Garamond
- **Sans** (brødtekst, UI): Hanken Grotesk
- **Mono** (etiketter/kickers, årstal): JetBrains Mono — brugt til korte
  versal-etiketter med bred `letter-spacing`.

Følelsen er **rolig, redaktionel, arkiv-agtig** — ikke et "SaaS-dashboard". Meget
whitespace, serif-navne, diskrete guld-accenter, våbenskjold-motiver som lette
vandmærker. Bevar dette udtryk; redesignet handler om *struktur og flow*, ikke om
et nyt visuelt sprog.

---

## 2. Problemet vi løser

Den nuværende flade har:

- En **flad header-nav** (Stamtræ · Godser · Kort · Våben · Om slægten · Slægtskab)
  der behandler alle destinationer som ligeværdige — også selvom slægten rummer
  langt flere emnetyper end der er plads til på én linje.
- En **søgefunktion gemt bag en "Søg"-knap** der åbner et modalt overlay. Søgning
  er person-appens vigtigste indgang, men den føles som en sidefunktion.
- Et **detalje-panel til højre** der altid deler pladsen med træet, selv når man
  ikke har valgt nogen.

Målet er en navigation der **skalerer til mange emnetyper**, en søgning der er
**central i stamtræsoplevelsen**, og en læseflade hvor **træet får hele scenen
indtil man bevidst dykker ned i én person**.

---

## 3. Header & navigation — den ekspanderende mega-menu

### 3.1 To tilstande

**Kollapset (hviletilstand):** en lav, rolig bjælke. Navigationens rygrad er **de tre
temaer selv** — ikke enkeltdestinationer. Tre ord, der skalerer til vilkårligt mange
emnetyper uden at bjælken vokser:

```
┌──────────────────────────────────────────────────────────────┐
│ [logo]     Slægten   Godser & steder   Historie     ⌕  R▾  ● │
└──────────────────────────────────────────────────────────────┘
  hjem (forside)     de tre temaer              søg  slægt  konto
```

- **Logo-lockup (lille) = hjem/forside.** DAF-mærke + "Danmarks Adels Aarbog" + mono-
  underlinje. Klik fører til **forsiden** (§6) — det er appens hjem, og grunden til at
  ingen enkelt destination behøver at ligge i den kollapsede bjælke.
- **De tre temaer** (Slægten · Godser & steder · Historie — §3.2) er den synlige
  navigation. De fungerer som ankre for den ekspanderede menu; hvert tema *kan* have en
  oversigtsside, men behøver det ikke.
- **Højre-klynge (utility):** søge-indgang (⌕), slægt-chip (Reventlow ▾),
  konto-indikator (● / "Log ind"), redaktion-link (↗). Se §7.

Denne model nedtoner bevidst enhver enkelt funktion (inkl. Slægtskab): alt indhold er
ligeværdige punkter *under* et tema. Førstegangs-opdagelse bæres af forsiden (§6) og
den prominente søgning i stamtræet (§4) — ikke af enkeltpunkter i menubjælken.

**Ekspanderet (mus hen over bjælken):** bjælken **vokser nedad** og afslører:

- Et **større logo/lockup** (mere højtideligt — værket træder frem).
- Alle destinationer **opdelt i logiske temaer** (§3.2), i kolonner.
- **Live vs. kommer** markeret tydeligt (✓ vs. dæmpet + "kommer").

```
┌──────────────────────────────────────────────────────────────┐
│                                                                │
│   [STORT LOGO]        Danmarks Adels Aarbog                    │
│                       Følgesvend · Dansk Adels Forening        │
│                                                                │
│   SLÆGTEN            GODSER & STEDER         HISTORIE          │
│   · Stamtræ      ✓   · Godser          ✓    · Artikler     ○   │
│   · Slægtskab    ✓   · Kort            ✓    · Kilder/værk  ○   │
│   · Våben        ✓   · Steder (register)○   · Tidslinje    ○   │
│   · Om slægten   ✓   · Organisationer  ○    · DAA-udgaver  ○   │
│                                             · Billeder     ○   │
│                                                                │
└──────────────────────────────────────────────────────────────┘
```

**Adfærd:**
- Åbner på hover (evt. lille intent-delay så den ikke "blafrer").
- Lukker når musen forlader den udvidede flade.
- Den aktive destination er markeret (bordeaux) uanset tilstand.
- Overgangen (kollaps ↔ ekspanderet) skal føles blød og bevidst — værket "åbner
  sig", ikke en dropdown der smækker op.

### 3.2 Temaer og indhold

Datamodellen har et fast entitetssæt; hvert emne i menuen svarer til en entitet
eller et view over den. Foreslået gruppering:

| Tema | Punkter | Status | Entitet |
|---|---|---|---|
| **Slægten** | Stamtræ | live ✓ | person |
| | Slægtskab ("er vi i familie?") | live ✓ | relation-traversal |
| | Våben | live ✓ | coat_of_arms |
| | Om slægten | live ✓ | lineage/narrative |
| **Godser & steder** | Godser | live ✓ | estate |
| | Kort | live ✓ | place (punkter) |
| | Steder (register) | kommer ○ | place |
| | Organisationer | kommer ○ | organisation |
| **Historie** | Artikler | kommer ○ | narrative |
| | Kilder / værker | kommer ○ | source / repository |
| | Tidslinje | kommer ○ | historical_event / fact |
| | DAA-udgaver | kommer ○ | source (slags = DAA-udgave) |
| | Billeder / galleri | kommer ○ | media |

*(Grupperingen og etiketterne er et forslag — se §9.b. Pointen er at layoutet
rummer den fulde vision nu, så det ikke skal bygges om når nye views kommer til.)*

**Kommer-punkter** skal se *inviterende men tydeligt inaktive* ud — de fortæller
brugeren "her kommer mere", uden at føles som fejl eller døde links. Ingen
klik-handling; evt. en diskret "kommer"-etiket eller nedtonet farve.

---

## 4. Søgning — flyttet ind i stamtræet

Søgning er i dag gemt bag en knap. **Ny model:** person-søgning er en **integreret
del af stamtræsvisningen**, øverst.

### 4.1 Flow

1. Et **søgefelt sidder øverst i stamtræs-fladen** ("Søg i slægten…").
2. Mens man skriver, vises træffere som **de samme små personkort** som selve
   stamtræet bruger (samme avatar + serif-navn + mono-årstal). Genkendeligheden er
   pointen: resultaterne *er* mennesker fra træet, ikke en fremmed liste.
3. Når brugeren **vælger et kort**, bliver personen **centrum i den egentlige
   stamtræsvisning** (variant A "Fokus" centrerer på dem), og søgeresultaterne
   viger for træet.

```
INDEN VALG (søgning aktiv)          EFTER VALG (træet centrerer)
┌────────────────────────────┐      ┌────────────────────────────┐
│ 🔍 Søg i slægten…          │      │ 🔍 Søg i slægten…          │
│ [Personer] Godser Steder … │      │            ┌──────┐        │
│ ┌──────┐ ┌──────┐ ┌──────┐ │  →   │  ┌─────┐   │VALGT │  ┌────┐│
│ │ kort │ │ kort │ │ kort │ │      │  │ far │───│person│──│barn││
│ └──────┘ └──────┘ └──────┘ │      │  └─────┘   └──────┘  └────┘│
│ ┌──────┐ ┌──────┐          │      │         stamtræet          │
│ └──────┘ └──────┘          │      │                            │
└────────────────────────────┘      └────────────────────────────┘
```

### 4.2 Universel-klar (men person nu)

Søgningen søger **personer** i denne omgang. Men layoutet skal fra start rumme et
**fane-/filter-bånd** (Personer · Godser · Steder · Artikler …) hvor kun "Personer"
er aktiv nu. Så en senere udvidelse til universel søgning ikke kræver ombygning —
kun at tænde de øvrige faner og lade dem returnere deres egne korttyper.

### 4.3 Forhold til gennemse-funktioner

Den nuværende søge-modal bærer også **gennemse-værktøjer**: A–Å-alfabet-hop,
sortering (navn/født), og linje-filter-chips (slægtens grene). Disse hører logisk
sammen med søgning og skal **flyttes med ind i den nye søgeflade i træet** — enten
altid synlige eller foldet ud på forlangende. De må ikke tabes; de er hvordan man
*browser* slægten frem for at søge målrettet.

**Header-søgeknappen** (⌕) i §3.1 kan enten (a) scrolle/fokusere til søgefeltet i
træet, eller (b) reserveres til en fremtidig **universel global søgning**. *(Åbent
— se §9.c.)*

---

## 5. Stamtræ + detalje — split-skærmen

### 5.1 Grundprincip

- **Før noget er valgt** (kold start) møder man **søge-hero'en** (§6), ikke træet.
  Et **fuldt-bredt stamtræ uden detalje** ses først når man har valgt en person og
  *derefter lukker* detaljen igen.
- **Ingen person valgt → detaljen er skjult**, og den flade man er på får **hele
  bredden**.
- **Person valgt → detaljen glider ind og fylder ~halvdelen; træet reducerer til
  den anden halvdel.** De to deler skærmen (ca. 50/50).

**Split er et generelt "flade + detalje"-mønster, ikke kun for personer.** Det tages i
brug for Stamtræ + Slægtskab nu (fordi persondetaljen — biografien — er den rige tekst
vi har). Men mønsteret er bevidst tænkt til at **generalisere**: når der kommer
artikler om godser (og senere steder), skal et gods kunne åbne sin **artikel/detalje i
den ene halvdel** præcis som en person gør — samme split, samme kort-i-listen →
detalje-i-halvdelen-idé. Designeren bør tegne split-mønsteret så det er entitets-
agnostisk, selvom kun person bruger det i første omgang. Views uden detalje-indhold
(fx Våben-galleriet) ejer deres fulde bredde.

```
INGEN VALGT                          EN PERSON VALGT
┌────────────────────────────┐      ┌─────────────┬──────────────┐
│                            │      │             │              │
│      STAMTRÆ (fuld)        │  →   │   STAMTRÆ   │   DETALJE    │
│                            │      │    ~50%     │    ~50%      │
│                            │      │             │              │
└────────────────────────────┘      └─────────────┴──────────────┘
```

### 5.2 Hvornår åbner/lukker detaljen?

- **Åbner** når brugeren *vælger* en person med hensigt: klik på et søgeresultat-kort,
  eller klik på en person i træet.
- **Lukker** via en tydelig luk-affordance (× / "Luk detalje"), Escape, eller ved at
  klikke den valgte person igen. Så er man tilbage til fuldt træ.
- **Deep-link / "mig":** åbner man `/person/:id` direkte (delt link) eller har markeret
  "mig i slægten", lander man med den person centreret **og** detaljen åben.

*(Præcis regel for "centrerer et træ-klik altid detaljen, eller kan man navigere i
træet uden at åbne detaljen?" — se §9.d.)*

### 5.3 Detaljens indhold (bevares fra nuværende `DetailPanel`)

Portræt/avatar, navn, leveår, floruit, biografi (narrativ med hyperlinks og
billeder), embeder, godser, våben, bogmærke-flag, "det er mig"-markering, samt
handlingsknapper ("Find slægtskab", "Sæt i fokus"). Redesignet skal give dette
**mere plads og bedre læsbarhed** når det nu fylder halvdelen — det er her den lange,
redaktionelle prosa lever.

### 5.4 Smal browser (minimal fallback)

I en smal browser stakkes de to: den valgte person åbner som et **fuldskærmslag over
træet** (træet er "under"). Dette er en *graceful fallback*, ikke fokus for
konceptet (jf. scope: rent desktop nu).

### 5.5 Stamtræets egne varianter (bevares)

Træet har allerede to visninger via en segmenteret kontrol:
- **Fokus (A):** fokus-personen i centrum med forældre/søskende/ægtefæller/børn omkring.
- **Kolonner (B):** bidirektionel — aner mod venstre, efterkommere mod højre, drill
  kolonne for kolonne.

Begge bevares. Split-skærmen (§5.1) skal fungere for **begge** varianter — dvs. både
Fokus og Kolonner skal kunne leve i den reducerede ~50%-bredde.

### 5.6 Slægtskab — "er vi i familie?"

Slægtskab er **ét view blandt flere** under temaet Slægten — en nyttig funktion, men
den skal *ikke* fremhæves som app'ens omdrejningspunkt visuelt. Den nævnes her kun
fordi den interagerer lidt anderledes med søgning og split end Stamtræ, og en designer
skal kende afvigelsen. Her vælger man **to personer (A og B)** og får slægtskabsstien
mellem dem med konfidens.

- **Søgningen (§4) er den samme flade og de samme person-kort**, men et valg **fylder
  en A/B-plads** i stedet for at centrere træet. Fladen kommunikerer tydeligt hvilken
  plads man udfylder ("Vælg person A" → "Vælg person B"). Har brugeren markeret "mig",
  fylder en genvej A med ét klik.
- **De to halvdele:** venstre = slægtskabs-resultatet (A/B-kort, stien, konfidens,
  kilder); højre = detalje for den person man inspicerer langs stien (samme
  detalje-panel som i Stamtræ).
- **Overgang:** fra en persons detalje-panel kan "Find slægtskab" forudfylde A (eller
  B) med den person man kom fra — så man ikke starter forfra.

*(Behandl Slægtskab som en almindelig hovedflade, ikke en fremhævet helt. Den deler
søgning + person-kort + detalje-panel; kun resultat-halvdelen er dens egen. Åben
A/B-slot-detalje: se §9.d.)*

---

## 6. Forsiden / landingstilstand — **bevidst åben**

Logoet fører hjem til en **forside**, og fordi detaljen nu er skjult indtil valg, er
forsiden appens reelle indgang (i dag lander man altid tvunget på en default-person).
**Selve forsidens form holdes åben** — det er en designretning vi vil udforske, ikke
låse nu. To hovedretninger (kan kombineres):

- **A · Feed/stream** — à la mobil-appens forside (Instagram/Twitter-agtig strøm):
  kort om nyt indhold, fremhævede personer/godser, "dagens/månedens" opslag, seneste
  redaktionelle tilføjelser. Levende, invitérer til at browse uden mål.
- **B · Faste indgange** — et roligt sæt kuraterede indgange: "Udforsk stamtræet",
  "Find en person", "Slægtens godser", udvalgte artikler. Mere redaktionelt/opslagsværk.

**Uanset form skal forsiden rumme (dit ønske fra §5.1):**

- **Prominent søgning** som en primær indgang ("Find en person i slægten").
- **3–5+ foreslåede startpersoner** som udgangspunkt for eksplorativ udforskning, for
  dem der ikke kender slægten. Vist som de samme person-kort. **Redaktionen udpeger
  kandidaterne** (et lille kurateret "highlights"-udvalg) — så en nybegynder har et
  meningsfuldt sted at starte i stedet for et tomt søgefelt og 920 fremmede navne.

**Øvrige indgangstilstande (uændret uanset forsidens form):**
- **"Mig" sat / deep-link** (`/person/:id`): land direkte på den person (centreret træ
  + åben detalje).
- **Retur fra en anden fane:** rimelig default (fx sidst valgte person).

*(Forsidens endelige form er et selvstændigt designspor — se §9.f. For nu skal
designeren blot vide at der ER en forside, at logoet fører dertil, og at søgning +
kuraterede startpersoner hører til der.)*

---

## 7. Sekundære elementer — hvor havner de?

| Element | Nuværende | Forslag i ny model |
|---|---|---|
| **Slægt-chip** (Reventlow ▾) | header højre | bliv i header-højre (kollapset) + fremhævet i logo-området (ekspanderet). Åbner slægt-vælger (kun Reventlow nu). |
| **Log ind / konto** | header højre | bliv i header-højre som diskret konto-indikator; login åbner modal. |
| **Bogmærker** | kun i søge-modal ("Se alle") | egen indgang under en **personlig/konto-klynge** (evt. i ekspanderet menu eller ved konto-ikonet) **og** som filter i søgningen. Se §9.e. |
| **"Mig i slægten"** | avatar i header når sat | bevar avatar-genvej i header; det er brugerens egen indgang til træet. |
| **Redaktion ↗** | header højre | bevar som diskret utility-link (redaktører logger ind til en separat flade). |

Princippet: **utility og personligt** samles i header-højre og/eller konto-klyngen;
**indhold og emner** bor i den tematiserede mega-menu. Bland ikke de to.

---

## 8. Sammenhæng & konsistens (de tværgående beslutninger)

Disse binder delene sammen — de er "de øvrige væsentlige beslutninger":

1. **Én korttype, overalt.** Person-kortet (avatar + serif-navn + mono-år) bruges
   *identisk* i søgeresultater, i træet, i ctx-lister og i detalje-panelets relationer.
   Det er den visuelle konstant der får appen til at føles som ét system.
2. **Fokus er delt tilstand.** "Den valgte person" driver samtidig: træets centrum,
   detaljens indhold, og ctx-genveje. Ét fokus, ikke tre konkurrerende.
3. **URL som sandhed.** `/person/:id` og `/estate/:id` skal forblive delbare deep-links;
   fane-skift og fokus-skift afspejles i URL'en (allerede tilfældet). Split-tilstanden
   (detalje åben/lukket) kan enten ligge i URL'en eller være ren view-tilstand — vælg
   bevidst (§9.d).
4. **Live vs. kommer, ærligt.** Overalt hvor et emne ikke er bygget endnu, vises det
   som "kommer" — aldrig som et dødt link der ser aktivt ud. Ærlighed om ufærdighed
   er en del af tonen.
5. **Redaktionel ro.** Undgå tætpakkede toolbars. Hver flade har luft, en tydelig
   overskrift (serif) og en mono-kicker. Guld bruges sparsomt som accent, bordeaux
   som primær handling/markering.

---

## 9. Beslutninger — besluttet ✓ / åbent ○

- **a. Navigationens rygrad ✓ BESLUTTET.** De **tre temaer selv** er den kollapsede
  menu (ikke enkeltdestinationer). Ingen enkelt funktion fremhæves i bjælken; alt
  indhold er ligeværdige punkter under et tema. Se §3.1.
- **b. Menu-temaernes navne og gruppering ✓ BESLUTTET.** De tre temaer er
  **Slægten · Godser & steder · Historie**. ("Historie" foretrukket frem for
  "Arkiv" (dødt/bagudskuende), "Kilder" (for snævert + navnekollision med
  under-punktet) og "Værket" (for DAA-bundet).) Fordelingen af enkeltpunkter under
  hvert tema kan stadig finjusteres når nye views kommer til.
- **c. Hvad gør header-søgeikonet (⌕)? ○** *Forslag:* scroller/fokuserer til søgefeltet
  i træet nu; reserveres til universel global søgning senere.
- **d. Åbner ethvert træ-klik detaljen? ✓ BESLUTTET.** Ja — et klik på en person
  centrerer træet **og** åbner/opdaterer detaljen; en separat luk-handling giver fuldt
  træ igen. *(Underspørgsmål ○: skal "detalje åben" ligge i URL'en? — vælges ved
  implementering.)*
- **e. Bogmærkers hjemsted ✓ BESLUTTET.** En personlig-klynge ved konto + et filter i
  søgningen. Ikke en tung, separat "fane".
- **f. Forsidens form ○ ÅBENT (bevidst).** Feed/stream vs. faste indgange vs. en
  kombination — udforskes som selvstændigt spor. Fast uanset form: prominent søgning +
  3–5+ redaktionelt kuraterede startpersoner. Se §6.
- **g. Kort-søgning for godser/steder ○ (udskudt).** At kunne søge godser/steder via
  kortet er en mulighed, men **udskydes til person-søgningen står** — så vi ikke
  designer to søgeparadigmer på én gang.

---

## 10. Ikke-mål (eksplicit uden for scope nu)

- **React Native-appen (`mobile/`)** ændres ikke i denne omgang.
- **Touch-først / smal-browser** er ikke drivende for designet. En simpel stak-fallback
  (§5.4) er nok; en fuld responsiv touch-oplevelse er et senere spor.
- **De "kommer"-markerede views** (steder-register, organisationer, artikler, kilder,
  tidslinje, DAA-udgaver) bygges ikke her — de skal kun have en *plads* i menuen.
- **Universel søgning** implementeres ikke nu — kun *layoutet forberedes* (§4.2).
- **Nyt visuelt sprog.** Paletten, fontene og den redaktionelle tone bevares.

---

## 11. Til Claude design — hvad vi ønsker

**Leverance:** en visuel implementering / mockup af web-følgesvenden der realiserer:

1. Den kollapsede header hvor **de tre temaer er navigationen** + den hover-
   ekspanderende mega-menu med større logo og tematiserede, status-mærkede punkter (§3).
2. Søgning integreret øverst i stamtræet med person-kort-resultater og et
   universel-klart fane-bånd (§4).
3. Split-skærmen som et generelt "flade + detalje"-mønster: fuldt træ når intet er
   valgt → ~50/50 træ+detalje når en person er valgt, for **begge** træ-varianter, og
   tegnet så det senere kan rumme gods-/sted-artikler (§5).
4. En forside/landingstilstand — form holdes åben (feed vs. faste indgange), men med
   prominent søgning + kuraterede startpersoner (§6).
5. Placering af utility/personlige elementer (§7).

**Bevar:** paletten og fontene (§1), person-kortet som gennemgående primitiv (§8.1),
den redaktionelle ro (§8.5), og de eksisterende træ-varianter Fokus/Kolonner (§5.5).

**Succeskriterier:**
- En førstegangsbruger — også en der ikke kender slægten — har et meningsfuldt sted at
  begynde: forsiden tilbyder søgning *og* konkrete startpersoner, ikke et tomt felt.
- Navigationen kan rumme mange emnetyper uden at føles overfyldt i hviletilstand, og
  ingen enkelt funktion dominerer bjælken.
- Når man læser om én person (eller senere et gods), får både visningen og den
  redaktionelle prosa plads at ånde.
- Det hele føles som ét arkiv-værk — ikke et dashboard.

---

*Kilde-kontekst for designeren: nuværende implementering i `web/src/Folgesvend.tsx`
(header-nav, søge-modal, `TreeView` variant A/B, `DetailPanel`), designtokens i
`web/src/theme.ts`, og de tidligere mockups i `design/project/Reventlow-web-v2.dc.html`
/ `…-v3.dc.html`.*
