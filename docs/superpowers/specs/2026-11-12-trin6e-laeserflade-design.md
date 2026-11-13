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
   2018-20 ved navn. Én lille udgaveprofil som data: 1939's sidekort fra PDF-side til trykt side (§12.3, tillæg
   2026-11-13; afløser »ingen ny udgaveprofil«). Ingen nye `lineage`-rækker (opret-benet).
4. **Værdi for læseren:** en sammenfoldet person viser hver oplysning én gang i den valgte udgaves ord, med den anden
   udgave som kort note; kildehenvisninger, en læser forstår og kan slå op med (»DAA 1939, s. 49 · IV, nr. 3« med trykt side i stedet
   for »record-cd8ef79c-…« og PDF-side, §12); 1939's linjer og numre fra bogen; biografien åbner på den fulde post, ikke en henvisning.
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
10. **Uplacerede 1939-poster får også ny publicering** (efter Codex-reviewet): en lille schema-ændring tillader en tom
    postdel, så alle 563 genpubliceres, og afgørelse 7 gælder helt (§5.6).
12. **Relative datoer opløses** (projektejeren efter stikprøven, 2026-11-12): »29. s.m.«, »6. febr. s.å.«, »s.d.« giver
    ingen mening uden den foregående dato. Dåb opløses ud fra fødslen og begravelse ud fra døden, i samme udgave og på
    samme personrække; læseren ser **kun den opløste dato** (»29. april 1644«) (§5.4a).
11. **Ingen tomme biografichips:** har ingen af udgaverne en biografi (typisk ægtefæller), vises vælgeren som et lille
    udgaveskift over fakta uden biografitekst (§5.5).

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
(`red_upsert_fakta`/`red_edit_oplysning`); 13 af fritekstkilderne navngiver en udgave, 6 med side. (De 65 strukturelle `forældrefamilie`-påstande uden kilde vises ikke som fakta.)
**Målt:** hver personrække har højst én `person_external_id`-række (0 med flere), og kun kilder med
`source.slags='DAA-udgave'` (1 og 3) har rækker. »Udgave« = en sådan kilde.
**Rækker uden ekstern nøgle** (Codex-fund 5; målt: 546 offentlige rækker i komponenter, ægtefæller; 263 komponenter
består kun af dem): udgaven er den ene DAA-udgave, rækkens citationer peger på (målt entydig for alle 546). Kun en
række uden begge dele (eller med citationer til flere udgaver) vises i alle udgaver, og den indgår aldrig i en note.
En række bekræfter aldrig sig selv.

### 5.2 Fakta i den valgte udgave

- **Fakta-blokken viser bøgernes ord; navnet øverst er redaktionens valg** (projektejerens afgørelse 9).
  Overskriften pr. oplysning er den valgte påstand (`chosen`), **når den er udgavens egen**: bundet til udgavens post,
  med citation til udgaven, eller en redaktørrettelse, hvis fritekstkilde navngiver samme udgave som personrækken
  (OCR-rettelser som 1073's). Er den valgte påstand en redaktørbeslutning uden udgavens egen kilde (392's »Conrad«
  med fritekst »DAA 1939« på en 2018-20-række), viser udgavens linje udgavens egen påstand (»Conrad de Reventlow ·
  DAA 2018-20, V-1«), og den anden udgaves form står som note efter §5.3. Redaktionens valg ses i personens navn
  (overskrift, søgning, træ via `visning_*`) **uden nogen markering** — navnet står der bare; læseren får ikke at vide,
at redaktionen har valgt, og ser ikke »redaktionen« i fakta-blokken. Normalt følger valget nyeste udgave; en
redaktionel afvigelse er sjælden (projektejeren 2026-11-12). Ikke-valgte påstande fra
  udgaven vises fortsat som »andre udsagn«. Plan-Task 0 måler, hvilke af de 17 redaktørpåstande (§5.1) der falder i
  hver gruppe; tvivlstilfælde forelægges projektejeren. **Ingen udgaveegen påstand** (fx et faktum oprettet af
  redaktøren med »(kilde mangler)«): faktummet vises som i dag (§9 pkt. 4) og indgår ikke i noter.
  **Klientens input** (Codex runde 2): `public_person_facts` returnerer ikke `citat_tekst`. 6e-1 henter den med et
  supplerende anon-opslag i `public.citation` (læsbar for anon, gatet på målet; `db-rls.sql:541-544`) kun for valgte
  påstande uden `source_id` — ingen DDL.
- **Sammenlægning inden for udgaven:** rækker fra flere personrækker i samme udgave med samme faktatype og ens værdi
  (§5.4) bliver én linje, hvis kildeliste samler posterne (»DAA 2018-20 · III-58, V-1«). Uens værdier står som hver
  sin linje (flerværdi-typer som titel) — de er ikke uenighed, men flere oplysninger.
- **Kildeetiketten** for en bundet 1939-række er §5.6's læsbare etiket.

### 5.3 Noten om den anden udgave

For hver linje i den valgte udgave søges den samme faktatype i hver anden udgave i komponenten:

- **Enig** (§5.4) → »✓ også i DAA 1939« (udgavens kortnavn). Enig sammenligner de **viste** værdier (§5.2) i begge
  udgaver, ikke ikke-valgte udsagn (Codex-fund 1). For en enkeltværdi-type kræver »✓ også«, at **alle** den anden
  udgaves viste værdier er ens med linjen.
- **Uenig** → »DAA 1939 skriver: a; b« med alle den anden udgaves forskellige viste værdier (målt: 1939 har flere
  personrækker med forskellige valgte værdier i 8 komponenter for død, 10 for navn, 1 for fødsel). Uden valgt påstand
  (`omstridt`; målt 0) indgår alle udsagn som »skriver: …«, aldrig som »✓«.
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

- **Datotyper** (fødsel, dåb, død, begravelse): ens når hele den viste værdi (`vaerdi_tekst` + datotekst) er ens
  efter normalisering: små bogstaver; `†`, `*`, `⚭` væk; øvrig tegnsætning **erstattes af mellemrum** (ikke fjernet:
  `1.12.1700` ≠ `11.2.1700`); danske og 1939-månedsnavne/-forkortelser → tal; mellemrum samlet. »ca./o.« og »s.A.«
  må kun mappes til et fælles ord, ikke fjernes, og `?` bevares som tegn (`1644?` ≠ `1644`); et sted på kun den ene
  side er en forskel (målt: 85 af 560 par med
  ens datotekst). Ingen intervalvej (Codex-fund 2; målt: 19 af 20 interval-ens par har forskellig `date_qualifier`).
  Core-tests med negative par: ca. ↔ eksakt, `1.12` ↔ `11.2`, med ↔ uden sted.
- **Tekst** (navn, titel, dekoration, begravelsessted): ens når teksten er ens efter små bogstaver, samlede mellemrum,
  fjernet tegnsætning og bindestreg-/apostrofvarianter. Ingen stavemåde-ækvivalenser (»Ditlev«≠»Detlef«), ingen
  forkortelser (»Kmhre.«) — de står som »skriver: …«, hvilket er sandt.
- **Tomme værdier** (»—«, kun tegnsætning) er ingen oplysning: de vises ikke som linje og indgår ikke i noter
  (*mit valg*; 1939's »Begravet —«).
- **Bevis:** plan-Task 0 måler dækningen pr. type og en stikprøve på 40 »✓ også«-par, som projektejeren ser. *Mit
  valg:* stikprøven er en kontakt pr. faktatype: et falsk par slår »✓ også« fra for den type (dens noter bliver
  »skriver: …«), indtil reglen er rettet og en ny stikprøve for typen er ren. Den blokerer ikke resten af 6e-1.

### 5.4a Relative datoer (afgørelse 12)

Målt på stand-in: ~365 offentlige påstande med »s.m.«/»s.d.«/»s.å.« (dåb 201, begravelse 127, død 28, titel/dekoration
9); ingen for kilde 1 og 3 har udregnet `date_min`. Regel: for **dåb** er referencen personrækkens viste **fødsel** i
samme udgave, for **begravelse** dens viste **død**. »s.m.« erstattes af referencens måned og år, »s.å.« af dens år,
»s.d.« af hele dens dato; resten af teksten bevares (»hjemmedøbt 6. febr. s.å.« → »hjemmedøbt 6. febr. 1644«). Den
opløste værdi er den viste og den, lighedsreglen sammenligner. Kan datoen ikke opløses (reference mangler, mangler den
nødvendige del eller er selv relativ), vises bogens tekst, og den giver aldrig »✓« (noten bliver »skriver: …«). Død,
titel og dekoration med relativ dato opløses ikke og giver aldrig »✓« på grund af den relative del. Påstanden i
databasen ændres ikke (ren projektion; invariant 5).
*Under bygningen (7b, konservativt — ved tvivl bogens tekst):* desuden uopløselig, når referencen er usikker (»ca.«,
»?«, »før«, »/«) eller flertydig (to datoer/måneder), når datoen er flertydig i teksten (»begravet s.d.« efter
»bisat …«), eller når den opløste dato ville ligge før referencen. Initialkæder (»S. M. Kirke«, »R.S.A.O.«) er ikke
relative datoer. Relative værdier giver aldrig »✓« for andre typer end navn/tilnavn.
*Slutreviewet (Opus + Codex, 2026-11-12):* desuden uopløselig, når referencetypen har flere forskellige værdier på
rækken eller er omstridt/uden valg, når referencen har ekstra dagnumre (også uden punktum), når den opløste dato ikke
findes i kalenderen (»31. april«), og når datofeltet er relativt, mens teksten selv bærer en dato eller et relativt led
(datokæden kan henvise til noget andet, fx »bisat 5. april s.å. og begravet« + »s.d.«). »S.M.«/»S.D.«/»S.Å.« direkte
efter et dagnummer er relative. `?` fjernes aldrig ved dobbeltværdi-tjekket. Målt efter runden: 273 opløste, 91
uopløste (før: 313/51); ingen »✓« berørt.

**Kendt begrænsning (6e-1):** relative datoer uden for personens fakta opløses ikke — ægteskabets **vielse** (familie-
faktum; 8 relative af 478; vises i dag kun som kortpunkt, ikke som tekst i persondetaljen) og **embedernes periode**
(46 relative af 1.256 relationer, fx »s.å.« om det foregående embede; vises i »Embeder, rang & hverv«). Embedets
reference afhænger af bogens rækkefølge, som relationerne ikke bærer sikkert. Backlog (decisions 2026-11-12).

### 5.5 Biografiens standard og vælgerens chips

- **Én funktion** vælger både den aktive chip og den viste tekst (fjerner divergensen §2.1).
- **Standardudgave:** nyeste årstal (som i dag; 2018-20 før 1939).
- **Inden for udgaven** (*mit valg* som deterministisk form af projektejerens afgørelse 4): den længste tekst. Målt
  rigtig i alle 5 tilfælde (§2.2). Henvisningsposten (III-58) forbliver en chip.
- **Chippen er en post, fakta er en udgave:** III-58 og V-1 viser samme fakta (2018-20's); kun biografien skifter.
- **Vælgeren bygges af udgaverne i komponenten** (biografier ∪ fakta), *mit valg*. Målt: 11 offentlige 1939-rækker
  har fakta, men ingen offentlig biografi. Har en udgave fakta uden biografi, får den én chip (»DAA 1939«), der viser
  »Ingen biografi fra denne udgave« og udgavens fakta. Er der kun én chip, vises ingen vælger. Har **ingen** af
  udgaverne en biografi (afgørelse 11; typisk de 263 ægtefællekomponenter, §5.1), vises vælgeren som et lille
  udgaveskift over fakta, uden biografitekst og uden »Ingen biografi«.

### 5.6 Læsbar kildeetiket for poster (6e-2)

> **Tillæg 2026-11-13:** etikettens form, udvælgelsen af bindinger, sidetallene og de tilladte afvigelser er afløst
> af §12. Resten af afsnittet gælder.

**Byggertjekkets fund (bekræftet):** læserne kalder ikke `private.narrative_record_labels`. `public_person_facts`
(`schema.sql:21427`), biografilæseren v2 (`:16795`, `:16930`) og `public_family_sources` (`:20891`) læser
`after_state #>> '{labels,record_label}'` fra seneste `private.narrative_publication_event` for bindingen — etiketten
blev frosset ved publiceringen, før 1939 havde placements. Målt: 1.359 af 4.124 hændelser bærer en `record-`-etiket;
på stand-in er det den seneste hændelse for 563 af 1.151 bindinger (alle kilde 3's publicerede).

**Vej (projektejerens afgørelse 7):** publiceringswriteren lærer formen nedenfor, og en ceremoni skriver én ny
publiceringshændelse pr. binding, hvis seneste hændelse har en etiket lig `record_key`. Den gamle hændelse bevares
(versioneret, som målarkitekturen foreskriver for rettelser); læserne er uændrede og læser den nye. Krav til
ceremonien, som de tidligere: frys, dump før, vinduesvagt, generalprøve på frisk stand-in, paritet for kilde 1 og
fortrydelse. **Én transaktion** (Codex-fund 3): Ziesendorf-etiketten (§5.7) først, så én ny hændelse pr. berørt
binding med `after_state` = den aktuelle publiceringstilstand — publiceringsgaten kræver fuld lighed, så en etiket
ændret uden ny hændelse skjuler biografien (Ziesendorf alene rører 103 publicerede bindinger). **Afstemning pr.
binding** mod forrige hændelse; tilladte afvigelser: `binding.record_label` (den gemte kolonne opdateres),
`labels.record_label` og, for linje III's 103, `provenance.placements[].scheme_entry_label` med provenance- og
state-hash. Alt andet byte-ens; antal offentlige biografier og bundne fakta ens før og efter; `stale_published` 0.
Hændelsestypen og genbrug af 6d-1's revalideringssti er bygherrens.

**Etikettens form** (uanset vej):

1. Én accepteret placement med trykt nr. → `<linjekode>, <slægtled>. slægtled, nr. <trykt nr.>`
   (»II, 10. slægtled, nr. 3«); uden trykt nr. → `<linjekode>, <slægtled>. slægtled`. 2018-20's etiket er uændret
   (»V-1«) — byte-ens for kilde 1 er en del af beviset. *Mit valg:* gruppen udelades (kan være en hel sætning); den
   står i hovedet (§5.7).
2. Ingen placement → ingen postdel; kun citationens »DAA 1939, s. 541« (målt: 35 publicerede bindinger). Afgørelse
   10: `record_label` er i dag `NOT NULL CHECK (btrim<>'')` (`schema.sql:3667`), og v2-mapperen kræver en streng
   (`bioVersions.ts:102`). Tom postdel = **tom streng** med bevaret `NOT NULL` (ikke NULL). Én kontrakt gennem alle
   aktive veje (Codex runde 2): bindingens CHECK, publiceringswriteren, genimportvalidatoren
   (`schema.sql:12072`) og dens efterkontrol (`:12849`), v2-biografimapperen, familiekildemapperen
   (`familieKilder.ts:98`, kasserer i dag ikke-strenge) og redaktørens narrativmapper (`redaktionRead.ts:442`); alle
   visninger udelader en tom postdel uden tom chip eller separator. Bevis: Conrad (1198) i biografi, fakta,
   familiekilder og Redaktion.

`record_key` vises aldrig. **Indtil 6e-2** (*mit valg*): 6e-1's klient viser ikke en postdel, der er lig postens
`record_key` (mønster `record-<uuid>`), men kun citationens udgave og side. Så overholder 6e-1 anti-målet alene. Præcis form (fx når slægtled mangler) er bygherrens, under kravet om, at den er
entydig på siden.

### 5.7 Koordinater, linjer og B6 (6e-2)

> **Tillæg 2026-11-13:** linjenavne, linjeskemaets etiketter, »Kilde i Aarbogen« og de unummererede er justeret i §12.

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
- **B6 i læseren** (Codex-fund 4 og 8): regnes kun ud fra **offentlige** personrækkers gældende medlemskab i den
  komponent, klienten faktisk har foldet (ikke karantæne) — ikke fra `membership_component_states()`, der hverken har
  persongate eller kobler kilde til linje. Noten tilskrives pr. kilde: »✓ også i DAA 1939 (IV. Den danske grevelige
  Linje af 1673)«, når den anden kilde har samme linje; »DAA 1939 placerer i: …«, når den har en anden. Flere linjer
  inden for samme udgave (Conrad III/V) vises som linjer uden note. Ingen private id'er eksponeres. Målt: 3
  `corroborated`-komponenter hviler kun på et ikke-offentligt medlem og vises uden mærke. Mekanismen er bygherrens.
- **Linjens hoved** (Codex-fund 10; `lineage.ts:105-108`, hjemmesidens anker `home.ts:26`): laveste slægtled, dernæst
  laveste trykte nr., unummereret før nummereret. Målt: entydigt i alle 8 1939-entries (3-25 personer med nr. 1 pr.
  entry); kilde 1's 5 hoveder uændrede.
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
- **Ledende tegn** (projektejeren 2026-11-12): et ledende `*`, `†` eller `⚭` i en vist værdi fjernes i visningen —
  typen (»Født«, »Død«) siger det allerede. Påstanden er uændret.
- **Sideform** (projektejeren 2026-11-12): kildeetiketter viser altid »<udgave>, s. N«; bundne 1939-etiketter med
  »DAA 1939 side 532« vises som »DAA 1939, s. 532«.
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
- **Trykte sider (tillæg §12):**
  - Conrad 1198 viser »DAA 1939, s. 52« (PDF 541).
  - Ingen 1939-side over 92 i DOM'en.
  - En stikprøve på 5 placerede 1939-personer slået op i bogen på den viste side og det viste nr.
  - »Kilde i Aarbogen« viser linjens navn for begge udgaver.
- **Tal:** stikprøven (§5.4) uden falske par; dækning pr. faktatype; koordinat-RPC'en som anon i prod ≤ 0,6 s;
  kilde 1's koordinater og etiketter byte-ens.
- **Ceremonien (6e-2):** antal genpublicerede bindinger = antal med `record-`-etiket før (stand-in: 563, heraf 35
  uden placement og 103 i linje III), 0 bagefter; pr. binding kun §5.6's tilladte afvigelser; offentlige biografier og
  bundne fakta talt ens før og efter; `stale_published` 0; linjeskemaets III lyder »… Ziesendorf.« i læseren.
- **Personsidens fart:** biografikaldet som anon for Conrad (392) før og efter 6e-2, inden for basen 209-487 ms
  (decisions 2026-11-10), og samlet indlæsning af personsiden uden regression.
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
- **Codex-review 2026-11-12** (gpt-6.1-sol, 1 runde på spec'en; dom »ikke klar«, 11 fund) → Opus afvejede: 1+6, 3, 5,
  4+8, 10 nødvendige; 2, 7, 9, 11 forenklet. Projektejeren valgte schema-ændring for tom postdel (afgørelse 10) frem
  for Opus' »ingen genpublicering af de 35«, og udgaveskift uden tomme biografichips (afgørelse 11). Rettet i §3,
  §5.1, §5.3-5.7, §8. Fundet viste desuden 546 ægtefællerækker uden ekstern nøgle, som §5.1's første måling overså.
- **Codex runde 2 2026-11-12** (projektejerens ja til flere runder): 9 af 11 fund løst, 2 delvist; 3 nye. Afvejet af
  Opus (hovedsessionen; claims verificeret i koden): alle fire små og nødvendige — `?` bevares (§5.4); fakta uden
  udgaveegen påstand vises som i dag (§5.2); `citat_tekst` hentes via anon-opslag i `citation` (§5.2, ingen DDL i
  6e-1); tom postdel = tom streng med én kontrakt gennem alle veje (§5.6).

- **Tillæg 2026-11-13 (§12):** genmåling (Task 0) og projektejerens afgørelser 13-16 om etiket, trykte sider og
  linjenavne; advisor-tjek før skrivning (sidetal vist to gange, omregning pr. vej, profil som data, kollisioner
  genmålt for den endelige form). Review-budget for 6e-2 uændret: 1 Codex-runde på tillæg + plan, 1 på diffen.

- **Codex runde 1 på tillæg + plan 2026-11-13** (gpt-6.1-sol; dom »ikke klar«, 7 fund):
  - Afvejet af hovedsessionen (Opus); alle claims er tjekket i koden. 6 er godkendt, og #5 er løst ved en præcisering.
  - Rettet i planen: migrationens ældre blokke (#1), kompatibel `SourceRef` (#2), side ved tom postdel (#3),
    stamtavleskema (#4), fartloft på klientens vej (#6) og db-verify (#7).
  - Rettet i spec'en: §12.4 (hovedet viser linjetitler) og §12.6 (fartloftet).

## 12. Tillæg 2026-11-13: etiket, sider og linjenavne (før 6e-2's plan)

Grundlag: genmåling på frisk stand-in (`daa5ab_ddl_standin_20261113070325_6e2`, prod 2026-11-13) og 1939's rå OCR
(`work_1939_stamtavle/raw.txt`; projektejeren 2026-11-13: må læses, ingen levende i 1939). Afløser de dele af §5.6-5.7,
der står nedenfor.

### 12.1 Projektejerens afgørelser

13. **Hver bog beholder sin egen opslagsnøgle, og linjens navn står med.** Begrundelse: bøgerne henviser forskelligt.
    2018-20 henviser med linje og nr. (»se nr. 58«, 61 gange; »se III. Den mecklenburgske linje, nr. 58« over
    Conrads V-1); 1939 henviser kun med side (»se S. 75«, 8 gange) og bruger aldrig sine numre, der tælles pr. kuld.
    Romertallene betyder forskellige linjer i de to bøger (IV og V er byttet: 2018-20's V = 1939's IV = »af 1673«),
    så romertallet alene vildleder; navnet gør ikke.
14. **Etiketten må være tvetydig (valg A).** Side og navn identificerer personen; poster holdes adskilt på id, ikke på
    etiket. **Målt for den endelige form** (trykt side, linje, nr.): 87 grupper med 194 af 528 placements deler
    etiket; heraf én gruppe med 5 unummererede (stammeafsnittet). (De tidligere 50/104 havde slægtled i nøglen.)
15. **1939's sidetal er særtrykkets trykte sidetal**, ikke PDF-sidetallet. I dag gemmer og viser alt PDF-siden
    (`narrative.side` 496-598; 2.886 af 2.889 `citation.side`; alle 563 bindingers `citation_label`), og læseren viser
    allerede »DAA 1939, s. 541« for det, der i bogen er s. 52.
16. **s. 22 (PDF 511):** bogen trykker »I« over »Den holstenske Linje.«; Calamari-kørslen tabte det.

### 12.2 Etikettens form (afløser §5.6 »Etikettens form« pkt. 1)

Postetiketten (`record_label`) er bogens egen opslagsnøgle uden side; siden bæres af `citation_label`, som for
2018-20 i dag.

| Bog | `record_label` | `citation_label` |
|---|---|---|
| 2018-20 | »V-1« (uændret, byte-ens) | »DAA 2018-20, s. 45« (uændret) |
| 1939, nummereret | »IV, nr. 3« | »DAA 1939 side 49« (trykt side; i dag PDF-side) |
| 1939, uden trykt nr. | »IV« | som ovenfor |
| 1939, stammeafsnit | »A, nr. 2« (afgørelse 17) | som ovenfor |
| 1939, ingen placement (35) | `''` (§5.6 pkt. 2, uændret) | som ovenfor |

- **Linjekoden** er det trykte romertal eller bogstav foran linjens navn i den rettede skemaetiket (§12.5), ikke
  `lineage_scheme_entry.code` (`Stamme-holstenske` er en intern nøgle). Slægtled og kuld udelades (afgørelse 14).
- **Udvælgelse (afløser »etiket lig `record_key`«):** reglen rammer alle 1.150 bindinger, fordi 2018-20's
  `record_key` er etiketten. Den nye form gælder poster, hvis `record_key` er `^record-[0-9a-f-]{36}$` (posten har
  ingen bogtrykt nøgle). Reglen er editionsneutral og rammer målt 563 bindinger, alle kilde 3, 0 kilde 1. Writeren
  `narrative_record_labels` (`schema.sql:14590`) må ikke ændre kilde 1's etiketter (i dag holdes »V-1« kun af
  bindingens tilsidesættelse, `:14595-14604`).
- **Tilladte afvigelser i ceremonien** (udvider §5.6): `binding.record_label`, `binding.citation_label`,
  `labels.record_label`, `labels.citation_label` og `provenance.placements[].scheme_entry_label` for de entries,
  §12.5 retter. Alt andet byte-ens.

- **Staged personer (målt under Task 9, 2026-11-13):** 2 af de 563 bindinger tilhører personer, der endnu ikke er
  offentlige (staged). Begge er uden placement, og revalideringen afviser dem (`NARRATIVE_RECORD_PUBLICATION_POLICY_BLOCKED`).
  - Ceremonien springer dem over efter 6d-1's kriterium, så tallene bliver 561 genpublicerede, heraf 33 tomme.
  - De oversprungne bliver byte-ens og tælles i kvitteringen.
  - Bliver de offentlige senere, mangler de deres læsbare etiket (backlog i decisions 2026-11-13).

### 12.3 Sidekortet: 1939's profil som data

**Kortet** (PDF-side → trykt side), fastlagt fra trykkeriets arksignaturer i den rå OCR: PDF 490 = s. 1, 506 = s. 17,
538 = s. 49, 571 = s. 65, 587 = s. 81.

| PDF | Trykt |
|---|---|
| 490-545 | PDF − 489 (s. 1-56) |
| 546 | planche, ingen trykt side |
| 547-548 | PDF − 490 (s. 57-58) |
| 549 | planche |
| 550-555 | PDF − 491 (s. 59-64) |
| 556-570 | 15 plancher |
| 571-598 | PDF − 506 (s. 65-92) |

**Bevis:**
- De fem signaturer går op med præcis 17 ikke-nummererede sider mellem s. 49 og s. 65. Det er netop de 17 sider med
  under 450 tegn OCR (billedtekster).
- Bogens egne krydshenvisninger går gensidigt op i tre zoner: PDF 533 ↔ 538 (S. 44 ↔ 49), 552 ↔ 554 (S. 61 ↔ 63) og
  576 ↔ 592 (S. 70 ↔ 86).
- Kun 547-548 er sluttet (mellem to plancher), ikke direkte bekræftet.
- Ingen citation eller binding ligger på en planche (målt 0).

**Uden for kortet:**
- 3 citationer har `side` < 496: 2 × »490« (= s. 1, indledningen) og 1 × »4«.
- En værdi uden for kortets PDF-interval vises **uden side** (kun »DAA 1939«), aldrig uomregnet; planens Task 0
  opklarer »4«.

**Hvor kortet bor** (*mit valg*): som data på kilden, fx en `sidekort`-kolonne på `public.source` (NULL = siden er
allerede trykt side, som for alle andre kilder), med én SQL-funktion `source_trykt_side(source_id, side)` som
eneste omregningsregel. Ingen klientkonstant. Leverancetypen i §1.3 er rettet; decisions får en post.

**Omregningen pr. vej** (planen tjekker listen udtømmende i Task 0):

| Vej | Bærer i dag | 6e-2 |
|---|---|---|
| Bindingens `citation_label` og hændelsens `labels.citation_label` (fakta, biografi, familiekilder) | »DAA 1939 side 541« (PDF) | Ceremonien skriver trykt side for de 563; en tilladt afvigelse |
| `public_person_facts.side` (`c.side`; `personFacts.ts:101`, ubundne fakta) | PDF | RPC'en returnerer `source_trykt_side(...)` |
| `citation.side`, læst direkte af klienten (`kildeProveniens.ts:42`, `:66`) | PDF | Læses gennem en offentlig RPC eller visning med omregningen; klienten regner ikke selv om |
| `citation.citat_tekst` »DAA 1939 side N« (navnefuldendelse, `schema.sql:5731`) | PDF | Task 0 finder, om den når læseren; i så fald samme RPC-vej |
| `narrative.side` | PDF | Kun Redaktion. Uændret i 6e-2: redaktøren ser PDF-siden, som er ankeret til PDF'en. Backlog: mærk feltet. |
| De fire `citation_label_template`-profiler (`schema.sql:3910-3942`) | `{page_from}` = PDF | Historiske kørsler, ikke ændret. Publiceringswriteren, som ceremonien bruger, omregner via funktionen. |
| Koordinat-RPC'en | ingen side | Ny kolonne: postens trykte startside (§12.4) |

**2018-20** er ikke omfattet: dens »s. N« er allerede trykt side (§12.8 pkt. 2), og den har intet sidekort.

### 12.4 Visningen pr. sted

Eksempler:
- 1939-person placeret i IV, nr. 3, på PDF 538 (s. 49).
- Conrad 392 (V-1, »DAA 2018-20, s. N«).
- Conrad 1198 (ingen placement, PDF 541 = s. 52).

| Sted | 1939 | 2018-20 |
|---|---|---|
| Fakta (`factSource`, uændret kode) | »DAA 1939, s. 49 · IV, nr. 3«; 1198: »DAA 1939, s. 52« | »DAA 2018-20, s. N · V-1« (uændret) |
| Biografichip (`editionSelector.ts` `postLabel`) | »DAA 1939, s. 49 · IV, nr. 3« | »DAA 2018-20, s. N · V-1« |
| Familiekilder (`familieKilder.ts` `kildeLinje`) | »Kilde: DAA 1939, s. 49 · IV, nr. 3« | »Kilde: DAA 2018-20, s. N · V-1« |
| Redaktion (`PersonNarrativeRecordEditor.tsx:233-234`) | h3 »IV, nr. 3«; tom etiket → `citation_label` | »V-1« (uændret) |
| »Kilde i Aarbogen« (`buildSources`, `sources.ts:21`) | »DAA 1939: IV. Den danske grevelige Linje af 1673, s. 49, nr. 3«; ingen placement: »DAA 1939, s. 52« | »DAA 2018-20: V. Den grevelige linje af 1673, nr. 1« |
| Personsidens og feedets nummer (`bogensNummer`) | »IV, s. 49, nr. 3« | »V, nr. 1« |
| Linjehoved og B6-note (§5.7) | linjens rettede skemaetiket | uændret |

Hovedet viser linjetitler (»IV. Den danske grevelige Linje af 1673«), ikke personens slægtled, gruppe og nr. Det
afløser §5.7's »med slægtled, gruppe og nr.«: siden og nr. står i »Kilde i Aarbogen«, og slægtled og gruppe udelades
efter afgørelse 14.

**Ændringer i præsentationen:**
- Chip og familiekilder bruger `citation_label` i stedet for `source_label` (*mit valg*). Begrundelse: 1939's nr. er
  uden side ikke en henvisning. For 2018-20 tilføjes siden; data er uændret.
- `bogensNummer` vælger i dag første ref efter `person_id`. Det er en sideeffekt, og Conrad viser III-58.
  - Ny regel (*mit valg*, plan-review 2026-11-13): nyeste udgave, dernæst laveste slægtled, dernæst laveste id.
  - Den fulde post står i den linje, hvor personen er stamfar. Conrad får derfor V-1 (slægtled 1) frem for III-58
    (slægtled 12).
  - Personside og feed bruger samme regel uden biografidata.
- `printed_page` gives kun for poster uden bogtrykt nøgle, så 2018-20 forbliver »V, nr. 1«.
- Linjens navn i »Kilde i Aarbogen« kommer fra linjeskemaets etiket, som klienten allerede henter
  (`web/src/data/lineage.ts`). Bygherren bekræfter feltet. Etiketten fryses ikke ind i `record_label`, så fakta og
  chips forbliver korte.
- Koordinat-RPC'en returnerer for kilde 3 postens trykte startside, også for de 39 offentlige 1939-rækker uden
  gældende medlemskab. De viser kun »DAA 1939, s. N« (afgørelse 6), aldrig »Linje 1939, nr. N«.
- `unikkeEfterLabel` (`editionFacts.ts`) må ikke folde to forskellige poster med samme etiket (afgørelse 14). Nøglen
  er `record_ref`.

### 12.5 Linjeskemaets etiketter (udvider afgørelse 8)

Ceremonien retter, med før og efter i sin log (ingen `change_event`-writer på `lineage_scheme_entry`, målt):

| Entry | Før | Efter |
|---|---|---|
| 61 | III. Den ældre meklenborgske Linje af iesendorf. | III. Den ældre meklenborgske Linje af Ziesendorf. |
| 59 | Den holstenske Linje. | I. Den holstenske Linje. (afgørelse 16) |
| 6 | Den fyenske Linje | VI. Den fyenske Linje. |
| 57 | Den holstenske Linje. | A. Den holstenske Linje. (afgørelse 17) |
| 58 | Den ældre meklenborgske Linje. | B. Den ældre meklenborgske Linje. (afgørelse 17) |

60 (»II. Linjen Gallentin.«), 62 og 63 er bogens ordlyd og uændrede. Bogens stammeafsnit C (»Den yngre meklenborgske
Linje af Gallentin«, s. 20-21) er indledende prosa uden placements og uden entry.

**Hvad etiketten ikke rører:**
- Etiketten indgår ikke i medlemskabernes `source_basis`, i placement-evidensen eller i `membership_state` (målt for
  61). Planen måler det samme for 6, 57, 58 og 59.
- Den indgår i hændelsernes `provenance.placements[].scheme_entry_label`. De berørte hændelser skal alle være blandt
  de 563 (målt for 61: 103 af 103).

### 12.6 Klientrettelser fra genmålingen

Ud over §12.4:
- **Linjens hoved** (`lineage.ts:111`, `nr ?? 9999`): skal følge §5.7, dvs. slægtled først og unummereret før
  nummereret. I dag vælges et vilkårligt nr. 1 blandt 3-25 og aldrig det unummererede hoved (7 af 8 entries).
- **Redaktion:** tom `<h3>` ved tom postdel (`PersonNarrativeRecordEditor.tsx:233-234`).
- **`getAll` offset-paginerer koordinat-RPC'en** (1.111 rækker > 1.000), så den beregnes to gange pr. indlæsning.
  - Fartloftet i §5.7 måles på klientens vej: summen af de to sider ≤ 2 × 225 ms på stand-in. Siden før 6d-1 hentede
    også to sider.
  - Prods ≤ 0,6 s i §8 gælder det enkelte kald.
- **B6 inden for samme kilde:** komponent 255 er `conflict`, fordi dens to 2018-20-rækker står i III og V. Noten
  skelner konflikt inden for én kilde (vises som linjer uden note, §5.7) fra konflikt mellem kilder (137, 178).

### 12.7 Tal, der er ændret siden spec'en (genmålt 2026-11-13)

| Emne | Spec | Nu |
|---|---|---|
| Bindinger med hændelser | 1.151 | 1.150 (ikke opklaret; ingen hændelser efter 2026-11-10) |
| B6 `corroborated` | 441 | 446 (sandsynligvis prods 6 `samme_som` 2026-11-12; ikke opklaret) |
| Koordinat-RPC som anon (lokalt) | 600 ms | 555 ms; heraf ≈490 ms `membership_is_current` pr. række. Målet ≈225 ms står. |
| Offentlige kilde 3-personer | 574 / 91 | 567 / 86 gennem læserens offentlighedsgate |

Flyttede `schema.sql`-henvisninger (+11 efter linje 9669) og klientstier står i Task 0-rapporten. Planen bruger de
nye.

### 12.8 Afklaret af projektejeren 2026-11-13

1. **Valg A står** med de genmålte tal (87 grupper / 194 af 528 placements).
2. **2018-20's sidetal er trykte sider.** Stikprøve: Conrad V-1 har »DAA 2018-20, s. 201-202«, og bogen har ham på
   s. 201. 2018-20 får intet sidekort.
3. **Afgørelse 17: stammeafsnittene får bogens bogstav.** Bogen trykker »A.« (s. 7) og »B.« (s. 16) over dem.
   Etiketten bliver »A, nr. 2«, og skemaetiketterne bliver »A. Den holstenske Linje.« og »B. Den ældre meklenborgske
   Linje.«, ligesom romertallene.
