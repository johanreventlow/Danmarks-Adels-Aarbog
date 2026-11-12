# Delspec 6e — læserfladen: én udgave ad gangen, den anden som note

**Status:** udkast 2026-11-12, brainstormet med projektejeren samme dag (Conrad Reventlow som gennemgående eksempel;
skitse og valg i §3). Afventer byggertjek og projektejerens godkendelse. Valg markeret *mit valg* er mine, ikke
projektejerens.
**Overordnet spec:** `docs/superpowers/specs/2026-10-29-trin6-1939-gennem-kaeden-design.md` §3 (læseroplevelsen,
afgørelse 1 og 5, mine valg a-b), §5 (6e-rækken), §6 pkt. 8 (1939 hører hjemme på kilde 3-rækken), §7 (»hvordan
fakta-RPC'en og `buildPersonFacts` grupperer pr. udgave«), §8 (b).
**Arv:** decisions 2026-11-08 (6d's opdeling: »læserens visning af 1939-koordinaterne hører til 6e«; B6's
læservisning er 6e), 2026-11-09 pkt. 3-4 (koordinat-RPC'en entydig på `(entry, printed_number)`; 6e gør den billigere),
2026-11-09/10 (biografilæserens fart i feedet er udskudt — ikke 6e), 2026-11-09 (6d-2a's oversigtsregel).
**Review-budget (B13):** byggertjek (frisk agent) på spec'en; 1 Codex-runde (`gpt-6.1-sol`) på spec+plan og 1 på
diffen før prod pr. del (§4); Opus afvejer hvert fund.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, færdigbevis (b): »læseren ser fakta med kildehenvisning i persondetaljen«; trin 6-specens
   §8 (b) og læservisningen af (c) (B6, decisions 2026-11-08).
2. **Værdikædeled:** det sidste — offentlig læseprojektion med kildehenvisning (målarkitekturen: »forståelig
   kildehenvisning«, »må ikke skjule uenighed«).
3. **Leverancetype:** generel og editionsneutral. Reglerne kender »udgave« som `source_id` og årstal, aldrig 1939 eller
   2018-20 ved navn. Ingen ny udgaveprofil. Ingen nye `lineage`-rækker (opret-benet).
4. **Værdi for læseren:** en sammenfoldet person viser hver oplysning én gang i den valgte udgaves ord, med den anden
   udgave som kort note; kildehenvisninger, en læser forstår (»DAA 1939, s. 525 · II, 10. slægtled, nr. 3« i stedet
   for »record-cd8ef79c-…«); 1939's linjer og numre fra bogen; biografien åbner på den fulde post, ikke en henvisning.
5. **Færdigbevis:** §8.
6. **Erstatter:** `buildPersonFacts`' sammenblanding af alle udgavers rækker; `record_key` som synlig etiket;
   `legacy-source:<id>:<kode>` og legacy-linjen `1939` i læseren; koordinat-RPC'ens fald til legacy for hele kilde 3.

## 2. Målt udgangspunkt

Målt 2026-11-12 på stand-in `daa5ab_ddl_standin_20261111191901_slut` (= prod efter 6d-3 + de 6 omvendte
`samme_som`-kanter). Genmåles i plan-Task 0. Kun afdøde personer nævnes ved id.

### 2.1 Conrad Reventlow (255 III-58, 392 V-1, 1198 1939)

Tre personrækker i én `samme_som`-komponent. Læseren viser i dag 10 fakta-rækker for 4 oplysninger (navn ×3, født
×2, titel »greve« ×3, død ×2), fordi `public_person_facts` kaldes med alle komponentens id'er, og `buildPersonFacts`
grupperer pr. `fact_id`, dvs. pr. personrække (`packages/core/src/personFacts.ts`, `web/src/data/public.ts:263-267`).

- **Den valgte værdi er ikke bogens.** For 255 og 392 har navnekonklusionen valgt »Conrad« (påstand uden kilde);
  bogens »Conrad de Reventlow« står som andet udsagn. Skitsen fra brainstormen viste fejlagtigt bogens navn som
  overskrift; reglen er konklusionens valg (§5.2).
- **Datoer:** 2018-20 »21. april 1644« (tolket `1644-04-21`), 1939 »21 April 1644« (`date_min` NULL). 1939's
  dødsdato er kun tolket til året.
- **1939-posten er en af de 64 uden placement** (`record_kind='relationship'`, `retained_legacy`). »Linje 1939, nr.
  275« er den gamle imports løbenummer, ikke bogens. Biografi-etiketten er `record-07565168-…`.
- **Biografi:** III-58 er 61 tegn (»Conrad greve de Reventlow, se V. Den grevelige linje af 1673«), V-1 er 6679 tegn.
  Den aktive chip starter på indeks 0 i den sorterede liste (`web/src/components/DetailPanel.tsx:36`), mens
  `selectDefaultPublicBioSourceVersionV2` (`packages/core/src/bioVersions.ts:147-153`) vælger for sig — de to kan
  divergere. 255 har et gældende medlemskab i linje III, så 6d-2a's oversigtsregel (`schema.sql:3175-3227`) dækker
  ikke III-58.
- **Børn:** 16 forskellige børn i 2018-20; navne genbrugt efter barnedød (Ulrica Eleonora 1686 og 1690, Anna Sophia
  1688 og 1693). 1939's 7 børn er alle foldet ind. Chips viser kun initialer + fornavn, så det ligner dubletter
  (`DetailPanel.tsx:211-226`; `born`/`years` findes på objektet).
- **Embeder:** organisationen hedder for nogle roller det samme som rollen (236 »landråd i Slesvig og Holsten«), så
  »rolle · organisation« gentager teksten (`public.ts:293-309`).
- **Godser:** 392 har 7, 1198 har 9 — separate `estate`-rækker, intet koblet. 1939's navne bærer årstal og noter
  (»Clausholm (1683)«) og én udtræksfejl: »Kain« hvor bogen skriver »Kalø (1690)«. Uden for 6e (§4).

### 2.2 Bestanden

- **Komponenter:** 480 par 1939→2018-20 via `samme_som`. 574 offentlige kilde 3-personer, 91 uden `samme_som`
  (vises kun i 1939; ingen vælger).
- **Biografier:** 5 komponenter har flere tekster fra samme udgave; i alle 5 er den længste den fulde post (Conrad
  V-1, Detlef IV-1, Joachim 1035, Hartvig, Christiane Benedicte).
- **Datoer:** 1939's fødsler har `date_min` på 20 af 369 (2018-20: 371 af 371). Tolkede datoer kan derfor ikke bære
  lighed. Normaliseret datotekst (små bogstaver, tegnsætning væk, månedsnavne → tal) giver ens fødsel i 257 af 356
  par, død 180 af 333, dåb 21 af 49. Resten er især foranstillet `†`/`*`, sted eller årsag efter datoen (»29.1.1792
  på Pronstorf«), »s.A.« og »ca.«/»o.« — og reelle forskelle.
- **Tekstfakta:** navn ens (uden forskel på store/små bogstaver) i 170 af 477 par, titel 98 af 248 (titel er
  flerværdi: 2018-20 kan have »Greve«, »hvid ridder«, »storkansler« på samme person).
- **1939-etiketter:** alle 1939-rækker i `public_person_facts` og biografien bærer `record-<uuid>`, også de 528
  placerede (`private.narrative_record_labels`, `schema.sql:14579`). Placementen har linjekode, linjenavn
  (»II. Linjen Gallentin.«), slægtled (»Tiende«), gruppe (kan være lang: »Kapitain-Hartvig-Heinrich-Reventlows-Børn-
  med-Catharina-von-dem-Bussche«) og trykt nr.
- **Koordinat-RPC:** `public_person_source_coordinates()` som anon 600 ms på stand-in (prod-faktor 2,5-4,5 →
  ≈1,4 s i prod, målt 1.414 ms 2026-11-10). Kilde 3 falder til legacy, fordi 1939's numre er gruppelokale.
- **B6:** 441 `corroborated`, 3 `conflict` (bl.a. 137↔937), læse-kun i `private.membership_component_states()`.
- **Linjeskemaets etiket** for 1939's III lyder »… Linje af iesendorf.« (OCR; tabt begyndelsesbogstav).

### 2.3 Fund uden for 6e

- **Mulige fejlkoblinger:** komponent 527 har to 1939-tekster om »Comtesse Christiane Benedicte« med forskellig
  fødselsdag (23.9.1743 og 22.7.1745); komponent 66 har to om »Hartvig« (Ridder 1257 / »nævnes 1410«). Ligner to
  personer hver. Identitetssager → backlog (decisions).
- **Godsnormalisering** (navn/periode-opdeling, Kain→Kalø, godsidentitet på tværs af udgaver) → backlog.

## 3. Projektejerens afgørelser (brainstorm 2026-11-12)

1. **Visning C — valgt udgave forrest, den anden som note.** Udgavevælgeren (biografi-chips) styrer både biografi,
   fakta og linjer. Hver oplysning står én gang i den valgte udgaves ord og kilde. Den anden udgave nævnes kort:
   »✓ også i DAA 1939«, når den er enig, »DAA 1939 skriver: …«, når den afviger. Fravalgt: A (kun den valgte udgave)
   og B (én linje med alle kilder; kræver en regel for, hvilken udgave der vinder ved uenighed).
2. **Gentagelser inden for samme udgave lægges sammen** (III-58 og V-1's »Greve« → én linje, begge poster som kilde).
3. **Fakta, der kun findes i den ikke-valgte udgave, skjules ikke**, men står som note (»kun i DAA 1939: …«).
4. **Biografien åbner på den fulde post**, når personen står i flere linjer i samme udgave; en post, der kun henviser
   videre, vælges aldrig først.
5. **Godserne holdes ude af 6e.** Hver visning viser sin udgaves godser; normaliseringen bliver en backlogopgave.
6. **1939-personer uden placement** viser kun sidetallet (»DAA 1939, s. 541«), ikke legacy-løbenummeret.
7. **Den læsbare 1939-etiket skrives som ny publicering** (§9 pkt. 1, vej b): »så ligger det fast, og vi skal ikke
   bruge tid på beregninger ved alle visninger«.
8. **Linjeskemaets OCR-fejl rettes:** III hedder »… Linje af Ziesendorf.« (§5.7).
9. **Kilder og redaktion adskilles:** kilder kan skrive et navn forskelligt (Conrad de Reventlow i 2018-20, Conrad
   Reventlow i 1939, Conrad Comte de Reventlow i adelspatentet); redaktionen bestemmer, hvordan navnet vises i app og
   på web. I 6e: fakta-blokken viser bøgernes ord, navnet øverst redaktionens valg (§5.2). Backlog: et redaktionelt
   visningsnavn på identiteten (komponenten) med begrundelse og historik, adskilt fra påstandene — i dag må
   beslutningen låne en kilde og sidde på én personrække.

## 4. Opdeling og afgrænsning (*mit valg*: to dele)

| Del | Indhold | DDL | Prod |
|---|---|---|---|
| **6e-1 — klienten** | §5.1-5.5 og §5.8: udgavens fakta, sammenlægning og noter; biografiens standard; børneår; embedsdubletter; tomme værdier; linjer i hovedet følger vælgeren for 2018-20 | nej | web-deploy |
| **6e-2 — kildehenvisninger og koordinater** | §5.6-5.7: publiceringswriteren skriver den læsbare 1939-etiket, og en ceremoni genpublicerer de berørte bindinger; koordinat-RPC'en entydig på 1939's nøgle og billigere; offentlig læsning af B6; linjer og »Optræder i Aarbogen« for 1939; Ziesendorf | ja | DDL + ceremoni + web |

6e-1 kan gå i prod alene og giver det meste af værdien. 6e-2 kræver DDL, en dataceremoni og generalprøve på stand-in.

**Ikke-mål:** mobilen (dev-only; deler ikke `buildPersonFacts`, *mit valg*: backlog); godsnormalisering; nye fakta,
personer, familier eller linjer (opret-benet); rettelse af de mulige fejlkoblinger (§2.3); feedets biografifart
(decisions 2026-11-10); ændring af konklusioner eller påstande — 6e er ren projektion.

**Anti-mål:** et »✓ også« på noget, udgaverne ikke er enige om (en falsk enighed er værre end en ekstra »skriver:«-
note); at en udgaves fakta forsvinder uden spor; en tom eller teknisk etiket (`record-…`, `legacy-source:…`) i
læseren; at personsiden bliver langsommere.

## 5. Design

### 5.1 Hvilken udgave en faktarække tilhører (*mit valg*)

En faktarækkes udgave er dens **personrækkes kilde** (`person_external_id.source_id` / koordinatrækkens `source_id`),
ikke citationens. Det følger trin 6-specens §6 pkt. 8 (1939's påstande ligger på kilde 3-rækken) og giver kildeløse
fakta en udgave. *Kildeløs* = en påstand, hvis citation ikke peger på en `source`-række (læseren viser i dag »Kilde
ikke registreret«). **Målt:** alle importerede påstande har en kilde; de kildeløse i fakta-listen er ~15 påstande
skrevet af redaktøren, fordi redaktørens fire faktawritere (`red_tilfoej_oplysning`, `red_opret_fakta`,
`red_edit_oplysning`, `red_upsert_fakta`) altid gemmer `source_id = NULL` og kilden som fritekst i `citat_tekst`
(oftest »Dansk Adels Aarbog – DAA 2018-20«; 3 gange »(kilde mangler)«). 392's »Conrad« er sådan en og hører til
2018-20, fordi 392 er en 2018-20-post — selv om redaktørens fritekst lyder »DAA 1939«. Målt: 17 påstande på 13
personer, skrevet 4/7-1/8 2026; 9 navnerettelser og 2 datorettelser (`red_edit_oplysning`) og 6 overhoved-markeringer
(`red_upsert_fakta`/`red_edit_oplysning`); 13 af fritekstkilderne navngiver en udgave, 6 med side. (De 65 strukturelle `forældrefamilie`-påstande uden kilde vises ikke som fakta.) En personrække uden kilde vises i alle udgaver.
**Målt:** hver personrække har højst én `person_external_id`-række (0 med flere), og kun kilder med
`source.slags='DAA-udgave'` (1 og 3) har rækker. »Udgave« = en sådan kilde; regler skal fejle lukket (vise rækken i
alle udgaver), hvis en række en dag får flere.

### 5.2 Fakta i den valgte udgave

- **Fakta-blokken viser bøgernes ord; navnet øverst er redaktionens valg** (projektejerens afgørelse 9).
  Overskriften pr. oplysning er den valgte påstand (`chosen`), **når den er udgavens egen**: bundet til udgavens post,
  med citation til udgaven, eller en redaktørrettelse, hvis fritekstkilde navngiver samme udgave som personrækken
  (OCR-rettelser som 1073's). Er den valgte påstand en redaktørbeslutning uden udgavens egen kilde (392's »Conrad«
  med fritekst »DAA 1939« på en 2018-20-række), viser udgavens linje udgavens egen påstand (»Conrad de Reventlow ·
  DAA 2018-20, V-1«), og den anden udgaves form står som note efter §5.3. Redaktionens valg ses i personens navn
  (overskrift, søgning, træ via `visning_*`), ikke som »redaktionen« i fakta-blokken. Ikke-valgte påstande fra
  udgaven vises fortsat som »andre udsagn«. Plan-Task 0 måler, hvilke af de 17 redaktørpåstande (§5.1) der falder i
  hver gruppe; tvivlstilfælde forelægges projektejeren.
- **Sammenlægning inden for udgaven:** rækker fra flere personrækker i samme udgave med samme faktatype og ens værdi
  (§5.4) bliver én linje, hvis kildeliste samler posterne (»DAA 2018-20 · III-58, V-1«). Uens værdier står som hver
  sin linje (flerværdi-typer som titel) — de er ikke uenighed, men flere oplysninger.
- **Kildeetiketten** for en bundet 1939-række er §5.6's læsbare etiket.

### 5.3 Noten om den anden udgave

For hver linje i den valgte udgave søges den samme faktatype i hver anden udgave i komponenten:

- **Enig** (§5.4) → »✓ også i DAA 1939« (udgavens kortnavn). *Mit valg:* enig betyder, at den valgte udgaves
  viste værdi er ens med **et hvilket som helst** af den anden udgaves udsagn af typen (valgt eller ej) — ellers ville
  Conrads kildeløse »Conrad« give »DAA 1939 skriver: Conrad Reventlow«, selv om 2018-20 selv skriver det samme.
- **Uenig** (begge har en værdi, intet ens) → »DAA 1939 skriver: <den anden udgaves valgte værdi>«.
- **Uenighed inden for samme udgave** (to personrækker i samme udgave har valgt forskellige enkeltværdier, fx to
  fødselsdatoer): begge står som linjer uden mærke (*mit valg*; det er en datasag, ikke læserens at afgøre). *Mit valg:* for flerværdi-typer (titel,
  dekoration) gives kun »✓ også«, når en af den anden udgaves værdier er ens; ellers ingen note pr. linje, men den
  anden udgaves uparrede værdier samles under »kun i DAA 1939«.
- **Kun i den anden udgave** → samlet til sidst i fakta-sektionen: »Kun i DAA 1939: Begravet …«.
- Noten har ingen kildelinje; man ser kilden ved at vælge udgaven. Konflikt mellem flere andre udgaver (fremtidige
  årbøger) gives én note pr. udgave, nyeste først.

### 5.4 Lighedsreglen (*mit valg*)

Ligger i `packages/core` (DOM-fri, testbar), ikke i SQL. Den er bevidst en anden regel end
`assertion_binding_current`'s normalisering (`schema.sql:18291-18296`): den svarer på »er bindingens tekst ændret?«,
denne på »siger to udgaver det samme?«. Konservativ — ved tvivl: ikke ens.

- **Datotyper** (fødsel, dåb, død, begravelse, når der er en dato): ens når normaliseret datotekst er ens, eller når
  begge har `date_min`/`date_max` og intervallerne er ens. Normalisering: små bogstaver; `†`, `*`, `⚭` og tegnsætning
  væk; danske og 1939-månedsnavne/-forkortelser → tal; mellemrum samlet. Bygherren må fjerne efterfølgende sted/årsag
  (»… på Pronstorf«) og løse »s.A.« og »ca./o.« hvis målingen i plan-Task 0 viser, at det løfter dækningen uden en
  eneste falsk enighed på stikprøven.
- **Tekst** (navn, titel, dekoration, begravelsessted): ens når teksten er ens efter små bogstaver, samlede mellemrum,
  fjernet tegnsætning og bindestreg-/apostrofvarianter. Ingen stavemåde-ækvivalenser (»Ditlev«≠»Detlef«), ingen
  forkortelser (»Kmhre.«) — de står som »skriver: …«, hvilket er sandt.
- **Tomme værdier** (»—«, kun tegnsætning) er ingen oplysning: de vises ikke som linje og indgår ikke i noter
  (*mit valg*; 1939's »Begravet —«).
- **Bevis:** plan-Task 0 måler dækningen pr. type og en stikprøve på 40 »✓ også«-par, som projektejeren ser. *Mit
  valg:* stikprøven er en kontakt pr. faktatype: et falsk par slår »✓ også« fra for den type (dens noter bliver
  »skriver: …«), indtil reglen er rettet og en ny stikprøve for typen er ren. Den blokerer ikke resten af 6e-1.

### 5.5 Biografiens standard og vælgerens chips

- **Én funktion** vælger både den aktive chip og den viste tekst (fjerner divergensen §2.1).
- **Standardudgave:** nyeste årstal (som i dag; 2018-20 før 1939).
- **Inden for udgaven** (*mit valg* som deterministisk form af projektejerens afgørelse 4): den længste tekst. Målt
  rigtig i alle 5 tilfælde (§2.2). Henvisningsposten (III-58) forbliver en chip.
- **Chippen er en post, fakta er en udgave:** III-58 og V-1 viser samme fakta (2018-20's); kun biografien skifter.
- **Vælgeren bygges af udgaverne i komponenten** (biografier ∪ fakta), *mit valg*. Målt: 11 offentlige 1939-rækker
  har fakta, men ingen offentlig biografi. Har en udgave fakta uden biografi, får den én chip (»DAA 1939«), der viser
  »Ingen biografi fra denne udgave« og udgavens fakta. Har komponenten kun én udgave, vises ingen chips.

### 5.6 Læsbar kildeetiket for poster (6e-2)

**Byggertjekkets fund (bekræftet):** læserne kalder ikke `private.narrative_record_labels`. `public_person_facts`
(`schema.sql:21427`), biografilæseren v2 (`:16795`, `:16930`) og `public_family_sources` (`:20891`) læser
`after_state #>> '{labels,record_label}'` fra seneste `private.narrative_publication_event` for bindingen — etiketten
blev frosset ved publiceringen, før 1939 havde placements. Målt: 1.359 af 4.124 hændelser bærer en `record-`-etiket;
på stand-in er det den seneste hændelse for 563 af 1.151 bindinger (alle kilde 3's publicerede).

**Vej (projektejerens afgørelse 7):** publiceringswriteren lærer formen nedenfor, og en ceremoni skriver én ny
publiceringshændelse pr. binding, hvis seneste hændelse har en etiket lig `record_key`. Den gamle hændelse bevares
(versioneret, som målarkitekturen foreskriver for rettelser); læserne er uændrede og læser den nye. Krav til
ceremonien, som de tidligere: frys, dump før, vinduesvagt, generalprøve på frisk stand-in, afstemning pr. binding
(kun `labels.record_label` må afvige mellem før- og efterstatus; tekst, synlighed og kilde byte-ens), paritet for
kilde 1 og fortrydelse. Hvordan ændringen hedder som hændelsestype, og om den kan genbruge revalideringsstien fra
6d-1, er bygherrens — under kravet, at `stale_published` forbliver 0.

**Etikettens form** (uanset vej):

1. Én accepteret placement med trykt nr. → `<linjekode>, <slægtled>. slægtled, nr. <trykt nr.>`
   (»II, 10. slægtled, nr. 3«); uden trykt nr. → `<linjekode>, <slægtled>. slægtled`. 2018-20's etiket er uændret
   (»V-1«) — byte-ens for kilde 1 er en del af beviset. *Mit valg:* gruppen udelades (kan være en hel sætning); den
   står i hovedet (§5.7).
2. Ingen placement → ingen postdel; kun citationens »DAA 1939, s. 541«.

`record_key` vises aldrig. **Indtil 6e-2** (*mit valg*): 6e-1's klient viser ikke en postdel, der er lig postens
`record_key` (mønster `record-<uuid>`), men kun citationens udgave og side. Så overholder 6e-1 anti-målet alene. Præcis form (fx når slægtled mangler) er bygherrens, under kravet om, at den er
entydig på siden.

### 5.7 Koordinater, linjer og B6 (6e-2)

- **Koordinat-RPC'ens entydighedsnøgle** udvides fra `(entry, printed_number)` til
  `(scheme_entry_id, generation_local, kuld_label, printed_number)`, så kilde 3 bruger placement. **Målt:** entydig for
  alle 507 nummererede 1939-placements (0 kollisioner); `section_path` i stedet for gruppe giver 13 kollisioner. De 21
  placements uden trykt nr. (stamfædre, decisions 2026-11-09) tæller ikke som kollision, men vises med linje og
  slægtled uden nr. (*mit valg*). Kildegaten (hele kilden til legacy ved kollision) bevares som sikkerhedsnet.
  Kilde 1 byte-ens (`KOORD_SRC`).
- **Fart:** RPC'en må som anon højst koste, hvad den gjorde før 6d-1 (≈225 ms på stand-in, ≈0,6 s i prod). Fx ved at
  beregne `membership_is_current` mængdebaseret i stedet for pr. række. Måles på stand-in efter `ANALYZE`, median af 3.
- **Hovedets linjer** følger vælgeren: 2018-20 viser 2018-20's linjer (som i dag); 1939 viser 1939's linjeskema-entry
  (»IV. Den danske grevelige Linje af 1673.«) med slægtled, gruppe og nr. Ingen placement → ingen linje.
  `legacy-source:…` vises aldrig.
- **»Optræder i Aarbogen som …«** og **»Kilde i Aarbogen«** bruger §5.6's etiketter pr. udgave.
- **B6 i læseren** (*mit valg*): en offentlig, læse-kun projektion af `membership_component_states` for den viste
  komponent. `corroborated` → »✓ også i DAA 1939 (IV. Den danske grevelige Linje af 1673)« ved linjen; `conflict` →
  »DAA 1939 placerer i: …«. Kun `afklaret` `samme_som`, som funktionen allerede gør.
- **Linjeskemaets OCR-etiket** (afgørelse 8): entry `III` (stand-in id 61) får etiketten »III. Den ældre meklenborgske
  Linje af Ziesendorf.« som en lille dataændring i 6e-2's ceremoni, med sporbarhed (før/efter i ceremoniens log eller
  `change_event`, hvis skemaets writer har en). Øvrige entries er uændrede.
- **De 21 uden trykt nr.** Projektejerens forventning: nummeret er underforstået 1, fordi forfatteren ikke nummererer en
  gruppe med kun én person. **Målt:** 20 af 21 står alene i deres gruppe (linje, slægtled, kuld) — forventningen
  holder. Undtagelsen er `Stamme-holstenske`, slægtled 1: én unummereret og nr. 1-4 i samme gruppe; et underforstået
  »1« ville kollidere med det trykte nr. 1. *Mit valg:* etiketten viser ikke et nummer, bogen ikke trykker
  (»II, 5. slægtled«) — læseren skal kunne slå op i bogen, og linje + slægtled finder posten entydigt i de 20 tilfælde.
  Nøglen behøver ingen udfyldning (NULL kolliderer ikke, målt). Undtagelsen gives en etiket, der skelner den fra
  nr. 1-4, fx med gruppens overskrift; bygherren viser formen i planen.

### 5.8 Små rettelser i persondetaljen (6e-1, *mit valg*)

- **Dobbelt værdi:** `factValue` sætter `vaerdi_tekst` og `date_raw` sammen; redaktørens datorettelser gemmer samme
  tekst i begge, så læseren viser »15. febr. 1878., 15. febr. 1878.« (målt: 11 påstande). Er de ens, vises den én gang.
- **Børn:** chip viser fornavn + fødselsår, når det findes (»Ulrica · 1686«).
- **Embeder:** organisationsnavnet udelades, når det er lig rollen (uden forskel på store/små bogstaver).
- **Godser:** hver visning viser kun sin udgaves godser (§5.1 på `relation`), uden note for de andre (afgørelse 5;
  normaliseringen gør noten meningsfuld senere).

## 6. Prod og fortrydelse

- **6e-1:** web-deploy. Fortrydelse = redeploy af forrige build. Ingen data ændres.
- **6e-2:** DDL i `db-migrations.sql` (idempotent) + `schema.sql` + `db-verify.sql`-asserts, derefter dataceremonien
  (§5.6 genpublicering, §5.7 Ziesendorf) efter samme mønster som 6d-1: dump før DDL og før data, vinduesvagt,
  generalprøve på frisk stand-in. Fortrydelse = restore af data-dumpet under meldt frys (6d-1's kendte begrænsning
  gælder) og forrige funktionsdefinition (gemt i runbooken før apply). Kør
  `get_advisors`-ækvivalent statisk (Supabase-MCP ser ikke DAA-projektet). Prod-kald via projektejerens shell.

## 7. Kort

Ingen afgørelseskort. Projektejeren ser stikprøven af »✓ også«-par (§5.4) og browsertjekket.

## 8. Færdigbevis

Browsertjek som anon mod prod (trin 6-specens §8 b, opdateret af §3 og §9 her):

- **Conrad (392):** åbner på V-1 med 2018-20's fakta; navn, født, titel, død én gang hver; »✓ også i DAA 1939« ved
  født/titel/død; tryk på 1939 viser 1939's fakta med »DAA 1939, s. 541« og 2018-20 som note.
- **En placeret, sammenfoldet 1939-person** (fx 1093→149): 1939-visningen har etiket og linje fra placement, ikke
  `record-…`/`1939`; B6 vises ved linjen.
- **En 1939-person uden 2018-20-modpart:** ingen vælger, 1939's fakta, læsbar etiket.
- **En reel uenighed** viser »… skriver: …«; **konfliktkomponenten 137↔937** viser »placerer i«.
- **Ingen `record-` eller `legacy-source:` i DOM'en** på de tjekkede sider.
- **Tal:** stikprøven (§5.4) uden falske par; dækning pr. faktatype; koordinat-RPC'en som anon i prod ≤ 0,6 s;
  kilde 1's koordinater og etiketter byte-ens.
- **Ceremonien (6e-2):** antal genpublicerede bindinger = antal med `record-`-etiket før (stand-in: 563), 0 bagefter;
  pr. binding afviger kun `labels.record_label`; `stale_published` 0 før og efter; linjeskemaets III lyder
  »… Ziesendorf.« i læseren.
- **Status:** `status.md`'s 1939-kolonne for »Læsere på placement/membership« og »Læserflade: fakta med
  kildehenvisning« hæves til `produktionsverificeret` med dato.

## 9. Afklaret af projektejeren (2026-11-12)

1. **Etikettens vej:** (b) ny publiceringshændelse, ikke beregning ved læsning (afgørelse 7, §5.6). Fravalgt (a): to
   sandheder (gemt og vist) og fartbudgettet i hver læser.
2. **OCR-etiketten** rettes til »Ziesendorf« (afgørelse 8, §5.7).
3. **De unummererede** (projektejerens spørgsmål): underforstået nr. 1 bekræftet for 20 af 21; visningen udelader
   nummeret (§5.7, *mit valg*).

4. **Redaktørens kildeløse fakta** (§5.1): visningen er *ikke afgjort*. »Tilføjet af redaktionen · <kildetekst>« gør
   redaktionen for synlig for læseren; alternativer (vis kun udgaven, når fritekstkilden entydigt navngiver en; eller
   udelad kildelinjen) måles senere. 6e-1 ændrer ikke denne visning. Backlog (godkendt): Redaktion skal koble kilden
   til en `source`-række i stedet for fritekst — hører til søge- og koblingsværktøjet efter trin 6.

## 10. Sammenligning: det, specen ville have bygget på uden brainstormen

Projektejeren bad om sammenligningen. Uden spørgsmål ville 6e have fulgt trin 6-specens §3 og 6d-beslutningerne:

| Emne | Uden brainstorm | Efter brainstorm | Hvorfor ændret |
|---|---|---|---|
| Fakta pr. udgave | §3 pkt. 5: 2018-20-visningen viser kun 2018-20-fakta + kildeløse; 1939's ses kun ved valg af 1939 (= skitse A) | C: den anden udgave som note (»✓ også«/»skriver«/»kun i«) | A skjuler, at udgaverne er enige eller uenige; målarkitekturen: projektionen må ikke skjule uenighed. Kræver decisions-post (justerer §3 pkt. 5) |
| Gentagelser inden for udgave | ikke nævnt — III-58 og V-1 ville stadig give to »Greve« | lægges sammen | Conrad-eksemplet |
| Datoformater | ikke nævnt | lighedsregel i core (§5.4) | »21. april« vs »21 April«; 1939's datoer er næsten ikke tolket |
| Kildeetiket | §3 valg (b) og §8: »DAA 1939, s. N · nr. x« | »s. N · linje, slægtled, nr. x«; uden placement kun »s. N«; skrevet som ny publicering | 1939's numre er gruppelokale — »nr. x« alene er ikke en reference; Conrad har intet nummer; etiketten er frosset i publiceringen |
| Biografiens standard | ikke nævnt (indeks 0) | længste tekst i udgaven | III-58's henvisning vistes først |
| Koordinater + fart | 6d-beslutningerne: placement for 1939, RPC billigere | uændret, med konkret nøgle og loft | — |
| B6 i læseren | 6d: »læservisningen er 6e«, form uafklaret | »✓ også i DAA 1939 (linje)« ved linjen | samme mønster som fakta (C) |
| Børn, embeder, godser | ikke nævnt | små rettelser; godser til backlog | Conrad-eksemplet; Kain/Kalø |
| Mulige fejlkoblinger | ikke kendt | backlog | fundet ved målingen |

## 11. Reviewlog

- **Byggertjek 2026-11-12** (frisk Opus-agent, 6 spørgsmål): (1) etiketten er frosset i publiceringshændelsen →
  bekræftet, §5.6 omskrevet, vejen til §9 pkt. 1, 6e-1's klientfilter tilføjet; (2) udgave pr. række → målt, svaret i
  §5.1; (3) vælgeren når biografi og fakta ikke dækker de samme udgaver → målt (11), §5.5; (4) hvilke værdier noten
  sammenligner → §5.3; (5) hvad et falsk par stopper → kontakt pr. faktatype, §5.4; (6) nøglens kolonner og
  entydighed → målt (0 kollisioner), §5.7.
- **Projektejerens svar 2026-11-12:** §9 pkt. 1 → (b); pkt. 2 → Ziesendorf; de unummererede målt (20/21 alene i
  gruppen, én undtagelse), §5.7. 6e-2 får derfor en dataceremoni (§4, §6).
