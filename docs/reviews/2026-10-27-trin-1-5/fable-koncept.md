# Fase 2 — koncept og vision (Fable)

Helhedsreview af dataarbejdet trin 1-5. Grundlag: hele BUNDT (15 filer) og 21 opslag i EKS (afsnit 6).
Stier uden præfiks er relative til EKS; `NN-…md:linje` henviser til BUNDT-filerne. Fase 1-fund citeres med id.
Ingen navne på personer; kun postnøgler og id'er.

> **Hovedsessionens screening (2026-10-27):** ingen navne på levende personer, ingen citater fra ikke-sporede filer.
> Efterprøvet mod repoet: `schema.sql:17812/17816` (`konfidens` = NULL), `docs/decisions.md:1304-1313` (regel 1-4,
> abonnement som grundlag, binding ikke oprettelse), `2018-20-fuld-koersel.md:11-14/63-65` (622 bindinger; 622/570/54/30),
> `segment.py:40-50`, og 1d.3b-01's linjer (`:17475/17482` mod `:17053-17054`, også efterprøvet i fase 1). Nuance til 2-02:
> kommentaren i `segment.py:42-43` henviser til en udgavesektion *i samme fil*, ikke til JSON-profilen; pointen
> (1939-regexer ligger i fælles kode, ikke i profilen) holder.

---

## 1. Sammendrag

1. **Metoden holder som evidens- og proveniensmodel, ikke som genimport.** Alt `produktionsverificeret` i trin 4-5 er
   bindinger ovenpå `load_daa.R`'s bestand; kæden har intet bevist opret-ben — 0 nye fakta, 0 nye personer (2-01, 1a-02).
2. **»Lille profil« gælder JSON-laget, ikke segmentering og udtræk**, som er udgavekode i Python (2-02). Det er dét lag,
   en tredje årbog møder først; for 1939 kostede det ca. tre uger og 40 specs.
3. **Læseren ser intet, og 83 % af trin 4's forslag er dødt lager uden kø** (1a-03, 2-03). Risikoen er værdi, ikke data.
4. **Prod-overførslen er det dyreste mønster** (restore-only 9×, genspilspakke; ~1 uge pr. trin, 1a-04). 5c-1's form bør
   være standard, og gate 8 skrives om til det, der faktisk gøres.
5. **Afvejningen holder for prod i dag, ikke for metoden:** 1d.3b-01 er P1 for trin 6 (samme fejlklasse som #248);
   1d.3a-01, 1d.1-02 og 1d.3c-04 er P2. 10-års-reglen og behandlingsgrundlaget skal afklares før foreningens data (2-04).
6. **Før trin 6:** fase 1's fire P1, 1d.3b-01, 1d.3a-03, 1d.1-03, 1d.2-02 og fem beslutninger (afsnit 2.5 A).

---

## 2. Svar pr. spørgsmål

### 2.1 Virker metoden for årbogen?

**Hvad der bærer (og bør bevares uændret):**

- Evidenslaget i `private.*` med append-only-triggere (`11-fund-1b.md:146-147`), source record → occurrence →
  anker → observation → mention → persona som adskilte identiteter (`03-teknisk-maalarkitektur.md:79-96`).
  149a beviste det på den rigtige bog med nul kanonisk delta (`04-status.md:174`).
- Én generel writer med autorisation → begin → apply → finalize (#153) og profil-bundne operationer
  (`08-systemkort.md:176-181`). Trin 4 og 5 kunne faktisk lægges oven på den som nye operationer; det er
  generaliseringens bedste bevis til dato.
- Klausullaget (`clause_observation`, sæt, revision) og runneren: præcision 99 %, ordrette datoer 100 %
  (`04-status.md:160`). Det er en reel kontrakt mellem bog og model.
- Kontrolmodellens *idé*: mennesket ser kun uoverensstemmelser og en stikprøve (`07-beslutningskronologi.md:181`).
  Den afgørelse (2026-09-27) var rigtig og er den eneste, der gør skalering til 3.450 afgørelser mulig.
- Indholds-id'er (`private.content_uuid`) og nøglede digests — rigtige redskaber, blot brugt til et forkert formål
  (afsnit 2.2).

**Hvad der knækker ved næste udgave eller næste familie:**

1. **Intet opret-ben.** Trin 4's promotion er pr. beslutning »binding, ikke oprettelse« (`docs/decisions.md:1311-1313`,
   trin 4-spec åbent punkt 11.3 `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md:669-677`).
   Hele 2018-20 gav 3.739 forslag → 1.276 promoverbare → **622 bindinger til eksisterende assertions, 0 nye fakta**
   (`docs/evidensbaseret-genimport/2018-20-fuld-koersel.md:11-14`, `:63-65`). 5b's familiebekræftelse matcher mod
   `family_member`-rækker, »som den gamle loader skrev fra de samme poster … næsten selvbekræftende«
   (`docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md:82-84`). `relation_person_create` har
   0 elementer på rigtige data og er `isoleret implementeret` også efter GO 2 (`04-status.md:166`). 5a's facit
   er cirkulært (`docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md:64-66`). 5c-1 lægger placement på
   legacy-`person_external_id` (`09-udestaaende-raa.md:128`, 0d pkt 102). **For en ny slægt findes ingen bestand at binde til.**
   Den vej, der kan oprette 1.800 personer, er `load_daa.R` (1a-02), som samtidig er årsagen til dobbeltfamilier,
   spøgelses-unioner og 16 tomme unioner. Se 2-01.
2. **Segmentering er udgavekode, ikke profil.** `extraction-profiles.json` har for `daa-1939-v1` otte nøgler og ingen
   `clause_rules` (opslag 15); `segment.py:46-80` bærer ca. 20 1939-specifikke regexer i koden med kommentaren
   »Regexerne bor samlet i udgaveprofilen nedenfor« (`segment.py:42-43`); navneregel v1-v3 er tre Python-moduler
   (1c-10); titelordene står i SQL (`schema.sql:18030-18034`); 23 udgavenavngivne DB-objekter står i `schema.sql`
   (opslag 13) — alle fra 1939 v50-writeren, som 1b anerkender som et lukket, allowlistet kompatibilitetsnavnerum
   (`db-verify.sql:564-567`); det reelle problem er 1a-13's: den generiske case-familie *kalder* to af dem.
   JSON-profilerne under `reimport-profiles/` er tilsammen 252 linjer (opslag 6) — det er dét lag, visionen lover,
   og det holder. Men en tredje årbog starter i `segment.py`. Se 2-02.
3. **Identitet uden årstal.** 1939-personer har `date_min/max` på 18 af 370 fødselsassertions, så kandidater får
   »næsten kun navnesignal« (`identitetsvej-5a-bevis.md:111-114`); generatoren kender ikke de 719 `samme_som`
   (`:107-110`); kandidatvisningen viser kun navn og leveår (`:115-118`). #248 opstod med 2018-20's få navnefæller;
   1939 har »langt flere« (`09-udestaaende-raa.md:112`). 1d.3b-01's hul (afsnit 2.6) rammer præcis dér.
4. **Membership tåler kun én kilde.** Et gældende medlemskab fra 2018-20 gør 1939's placement til `conflict`, og én
   konflikt stopper hele promotionen (1d.1-07, `15-afvejning-codex.md:140-152`). Trin 6 er netop »begge udgaver«.
5. **Samme kolonne, to betydninger.** `verbatim_text` er rå OCR for 1939 og normaliseret projektion uden
   NOISE-linjer for 2018-20 (1d.3a-01, `15-afvejning-codex.md:221-225`). Trin 6 læser dem sammen.
6. **Den levende halvdel er uden for metoden.** 103 af 591 poster (17 %) er udelukket fra modelkald
   (`2018-20-fuld-koersel.md:30`). For en moderne slægt eller en præsensliste er det flertallet. Visionen
   er rigtig i at holde levende ude af automatikken; men roadmappet lover »foreningens samlede data«
   (`05-CLAUDE.md:5-7`), og præsenslister er årbogens anden hovedfunktion (`docs/flere-daa-udgaver-roadmap.md:9-13`).
   Der findes ingen vej for dem — hverken i kæden eller i RLS (`authenticated`-tier ikke designet,
   `09-udestaaende-raa.md:38`).

**Dom:** Kæden trin 1-5 er et solidt *proveniens- og bindingslag for en bestand, der allerede findes*. Som grundlag
for trin 6 (1939 gennem samme kæde) holder den med de gates, der står i 2.5. Som grundlag for trin 7 holder den
ikke, før opret-benet er designet og bevist. Det er ikke en detalje; det er den halvdel af »genimport«, der ikke er
bygget.

### 2.2 Overengineering

Målt mod en PoC med én redaktør, 1.811 personer og 4 kilder (`docs/database-current-state.md:7-8`):

| Hvad | Mål | Hvad det kostede | Hvad det købte |
|---|---|---|---|
| Prod-overførsel som genspilspakke (indholds-id'er på 8 rækkearter, nøglede digests over 21 lag, 25 skridt, `FREEZE`/`PREFLIGHT`/D0/D1) | `04-status.md:169-172` | 10 af 15 PR'er i U43 (`10-fund-1a.md:51`), ca. 1 uge pr. trin (1a-04) | At flytte data, der allerede var bevist i en restore. 5c-1 gik direkte mod frisk dump på 2 dage (`10-fund-1a.md:152`) |
| Restore-only fortrydelse, valgt 9 gange | 1a-04 | Udløste hele punktet ovenfor (tilfældige id'er kunne ikke sammenlignes → indholds-id'er) | Ingenting, der ikke også fås af »dump før, mål efter« |
| C3's atomiske apply/reverse: ~900 linjer SQL for fem sager, nu spærret | 1b-08 | Museumskode i `schema.sql`, db-verify-blokke | Fem bindinger i prod |
| 4.4's GO-pakke: »~2200 linjer bibliotek, fejlmatrix på 30 cases, 4+4 reviewrunder« for 84 forslag, aldrig brugt | 1a-06, `10-fund-1a.md:187-190` | U38-U39 | Ingenting; »erstattet« |
| Kontrolmodellens *ceremoni*: forseglede ark, hash-bundne trækninger, `-v2`-trækning af indhold | 1a-10 | Kode + projektejertid | En »advarselslampe mod maskinfejl, ikke et værn mod redaktøren« (`07-beslutningskronologi.md:160`); i 5c-1 var den ikke blind |
| Reviewrunder: 7 for 5b, 4 Codex-runder → spec 290→539 linjer | 1a-05 | Specs vokser; »8 teoretiske risici står som kendte begrænsninger« | Ægte fund, men ud over det besluttede budget |
| `db-verify.sql` 10.389 linjer, 137 `DO`-blokke; tokentjek af variabelnavne | 1b-14, `11-fund-1b.md:329` | Vedligehold; falsk tryghed (1e) | Stærke katalogtjek — behold dem, ikke resten |
| Dokumentation: specs 101/27.231 linjer, planer 132/92.665, `daa-extract/scripts` 112.813 linjer | `10-fund-1a.md:307-310`, `docs/reviews/2026-10-27-trin-1-5/maalinger.md:68-70` | Hver ny agent skal genkortlægge | 64 % af scripts er 1939-engangskode (1c-07) |

**Fællesnævner:** Hver enkelt beslutning var forsvarlig lokalt; ingen har besluttet proportionen (1a-12). Mekanismen er,
at »fail-closed« blev oversat til »kryptografisk genspilbar«, selv om der ikke er nogen modstander: én redaktør, som
også er projektejeren, og — så vidt det kan ses — ingen eksterne læsere (`10-fund-1a.md:311-312`).

**Hvad kan fjernes uden at miste det, invarianterne kræver:**

1. **Genspilspakken.** Invarianterne kræver append-only evidens, audit og kildeanker — ikke at prod-skrivningen er en
   byte-tro genafspilning af en restore. Standard fremover (5c-1's form): dump → kørsel mod prod med
   `--jeg-mener-det` → før/efter-måling med nøglede digests → fortrydelsesvindue. Indholds-id'erne beholdes (de er
   billige og gør målinger sammenlignelige), nøglekortet og de 25 skridt droppes.
2. **Forsegling og hash-ceremoni om stikprøven.** Behold blindhed og »én fejl stopper«; drop segl, `-v2`-trækning og
   fingerprint. Kald det en røgtest (1a-10's valg 1).
3. **Reversal pr. operation.** Hold op med at designe fortrydelse for hver writer-operation (det er allerede
   opgivet 9 gange). Formalisér i stedet restore-only som *den* fortrydelse i et vindue (afsnit 2.4, forslag til gate 8).
4. **Arkivér** 1939 v50/C0-C3/D1-D2-kæden (1c-07), C3's spærrede funktioner (1b-08), 4.4-pakken (1a-06), C3-deployfilen
   (1b-04/1c-05) og de røde R-tests (1c-04). Flyt dem ud af CI.
5. **Generér `schema.sql`** fra en migreret base (1b-05). Det fjerner 1b-01..04 som klasse og er mindre arbejde end at
   portere 17 kroppe i hånden.
6. **Review-budget som hård regel** (1a-05): en linje i spec-hovedet; overskridelse kræver en linje i decisions.

**Hvad der ikke skal fjernes, selv om det ser tungt ud:** writerens autorisation/manifest-binding (#153), de
append-only-triggere, RLS-gaten (1b: solidt), klausulsæt med revision (det *er* den billige fortrydelse for klausuler),
og de hash-bundne menneskeark (de er sporbarheden for ejerens afgørelser; prisen er lille).

### 2.3 Blinde pletter

**Redaktionelt (hvad en redaktør eller læser mangler):**

1. **Fakta er usynlige for læseren** (1a-03). Efter 10 uger og ca. 45 PR'er i trin 4 er den eneste læsergevinst én
   kildelinje i `DetailPanel` (`10-fund-1a.md:120-121`). Vision:19-20 nævner læserværdi som succeskriterium;
   intet trin i roadmappet leverer den.
2. **Ingen kø for det, kæden ikke kan afgøre** (2-03). 570 `SKRIVEMAADE`, 54 `REAL_DIFF`, 30 `NO_FACT` og 2.463
   ikke-promoverbare forslag ligger `proposed` uden nogen flade. 5a's webkø dækker kun identitet.
3. **Ingen redaktionel rettelsesvej for kanoniske fejl** (2-08). #240 og #248 krævede fire prod-ceremonier på én dag
   (`10-fund-1a.md:52`); allerede 2026-07-06 stod det, at »redaktøren har ingen flade til at rette den slags fejl«
   (`07-beslutningskronologi.md:422`). `red_slet_union` blev bygget og droppet (`:35`).
4. **Modstridende udgaver håndteres ikke indfødt — endnu** (2-09). Datamodellens kernepåstand (»to udgaver = to
   påstande, vis årbogens udvikling«, `06-datamodel-oversigt.md:99-102`) er aldrig udøvet: trin 4 binder kun
   tekstidentiske assertions, og de 4 accepterede uoverensstemmelser står »accepteret og ubundet«
   (`09-udestaaende-raa.md:61`). Der skrives ingen konkurrerende påstand og ingen `omstridt` konklusion.
5. **Konfidens fodres ikke af kæden** (2-05). Slægtskabsfinderen (»er vi i familie?«) viser konfidens på stien
   (`docs/reviews/2026-10-27-trin-1-5/leverancetidslinje.md:46`, PR #9), men værdien kommer alene fra loaderen.
   `write_relation_person_create` indsætter `family_member` med `konfidens = NULL` (`schema.sql:17812`, `:17816`).
6. **Levende medlemmer og samtykke.** Forretningsmodellen (invariant 8, `authenticated`-tier) er »kun skitseret«
   (`09-udestaaende-raa.md:38`). Præsenslister, der er 100 % levende, har ingen vej (afsnit 2.1 pkt 6).

**Teknisk:**

7. **Opret-benet** (2-01) — den vigtigste.
8. **Segmentering som profil** (2-02) og CI-dækning af netop den kerne: `validate.py` 0/30 funktioner, `segment.py`
   1/25 (1c-02). Trin 7 starter dér.
9. **Trin 6 og 7 har hverken spec, plan eller kandidat-årbog** (2-07). `04-status.md:179` kalder tredje-årbogsprøven
   `specificeret`; `08-systemkort.md:457-483` finder intet. `docs/flere-daa-udgaver-roadmap.md:3-6` siger, at det
   eneste indlæste er 2018-20 — teksten er fra før 1939 kom ind.
10. **Fortrydelsens ene fejlpunkt er et dump på en laptop** (2-06). Free tier har ingen backup (`05-CLAUDE.md:59`),
    fortrydelse er restore (1a-04), og et fredet prod-dump blev slettet 18/9 (`07-beslutningskronologi.md:232`).
11. **Juridisk afgrænsning** (2-04): »afdød« er ikke »død for mere end 10 år siden«; behandlingsgrundlaget er et
    personligt abonnement.
12. **Skemadrift** (1b-01/1b-05) og **loaderen som dokumenteret indgang** (1a-02, 1d.3c-01/04/05) — fase 1 har dem;
    jeg nævner dem, fordi de er forudsætninger for 7 og 8.

### 2.4 Visionen og roadmappet

**Dom:** `vision.md` holder som værdigrundlag og bør ikke omskrives i substansen. To af dens løfter er dog ikke
dækket af det byggede: »en lille profil, ikke en parallel permanent arkitektur« (`01-vision.md:13-15`) og »ingen
tavse tab« (`:28-29`, jf. 1d.3a-03 i publiceret tekst). `roadmap.md` holder i rækkefølgen, men trin 6-7 er for
tynde til at styre noget, og roadmappet mangler to led, som visionen kræver: læseprojektionen og opret-benet.

**Konkrete forslag (ændringer, der kræver projektejerens beslutning i `docs/decisions.md`):**

1. **Vision, »Definition af succes«** — tilføj to kriterier:
   > »… giver læseren en troværdig, sporbar kildevisning, *som læseren kan se i appen uden redaktørrolle*. Metoden
   > kan *oprette* kanoniske personer, familier og fakta fra en kilde uden en forudgående kanonisk bestand, gennem
   > samme gater som bindinger.«
   Koster: trin 7 bliver ærligt større. Lader man være: trin 7 »bevises« med en profil, der binder til ingenting.

2. **Vision, »Ikke-mål«** — tilføj:
   > »Det er ikke et mål, at hver produktionsskrivning er kryptografisk genspilbar fra en øvebase. Målet er, at den
   > er målt før og efter og kan fortrydes inden for et deklareret vindue.«
   Koster: intet. Lader man være: det næste trin bygger en ny overførselspakke.

3. **Målarkitektur, gate 8 (apply/reversal)** — ændr fra »rammer præcis den godkendte mængde« (`03-teknisk-maalarkitektur.md:158-160`) til:
   > »Anvendelse rammer præcis den godkendte mængde og måles før og efter. Fortrydelse sker enten som en særskilt,
   > auditeret handling med eget write-set *eller* som restore af et dateret dump inden for et deklareret vindue;
   > vinduet lukkes udtrykkeligt, og alt skrevet i vinduet efter dumpet er kendt tab.«
   **Dette omgør ikke en ejerbeslutning; det skriver ni ejerbeslutninger (1a-04) ind i arkitekturen.** Koster: en
   svagere garanti på papiret end i dag — men i dag er garantien allerede brudt (en restore til 10-05 ville tabe
   GO 1, GO 2, #240, #248, 5c-1). Alternativet er at bygge reversal pr. operation, hvilket er fravalgt 9 gange.

4. **Roadmap, trin 6** — omformulér:
   > »6. Kæden køres ende-til-ende på begge referenceudgaver. Færdigbevis: (a) 1939's klausuler, fortolkning, identitet,
   > placement og publicering gennem de samme operationer som 2018-20; (b) *læseren ser* fakta med kildehenvisning i
   > persondetaljen; (c) uafgjorte forslag har én redaktionel kø; (d) ét medlemskab kan bæres af to kilder.«
   Koster: trin 6 får læserarbejde (ca. en dags skive, 1a-03) og to beslutninger. Lader man være: 1a-03 forlænges.

5. **Roadmap, trin 7 — del i to**, for de er forskellige problemer:
   > »7a. En *ny udgave af samme slægt* (fx en ældre stamtavle eller en præsensliste) beviser identitetsafstemning mod
   > en eksisterende bestand med kun profil og vokabular.
   > 7b. En *ny slægt* beviser oprettelse fra ingenting: segmenteringsprofil, opret-ben, placement og publicering,
   > uden `load_daa.R`.«
   Koster: 7b kræver den spec, der mangler (2-01). Lader man være: »tredje årbog« bliver endnu en Reventlow-udgave,
   og »foreningens samlede data« forbliver uden vej.

6. **Roadmap, »Modenhedstilstande«** — tilføj én regel:
   > »En tilstand angives altid med udgave og led (`produktionsverificeret for 2018-20, bindingsdelen`). `i prod` er
   > ikke en tilstand.«
   (`08-systemkort.md:359`, `:530`). Koster: intet.

7. **Roadmap, »Kontrollerede afbrydelser«** — tilføj, at #240/#248-typen registreres med én linje (grund, slut,
   retur). Det blev besluttet 2026-09-03 og ikke brugt (1a-09).

8. **Målarkitektur, »Fælles motor og udgavespecifik profil«** (`03-teknisk-maalarkitektur.md:60-77`) — gør
   begrebet ærligt:
   > »En udgaveprofil består af en deklarativ del (JSON: renditioner, regler, vokabularafvigelser) og højst ét
   > udgavemodul pr. lag (segmentering, udtræk) bag en navngiven grænseflade. Modulet må ikke eksistere permanent i
   > fælles kode.«
   Koster: en refaktorering af `segment.py` ved trin 7. Lader man være: 1939-regexerne er allerede i den fælles fil.

9. **GDPR-regel 1-4** (`docs/decisions.md:1304-1307`) — foreslået skærpelse, afhængig af juridisk afklaring:
   »afdød« → »død før (indeværende år − 10)«. Koster: få poster i 2018-20 (14 døde 1990 eller senere,
   trin 4-spec:655); mange i en moderne slægt. Se 2-04.

**Ejerbeslutninger, jeg foreslår at omgøre, og hvad det koster:**

| Beslutning | Forslag | Koster |
|---|---|---|
| »Promotion i trin 4 er binding, ikke oprettelse« (2026-09-06 pkt 6) | Beholdes for trin 4; ophæves som princip ved en spec for opret-benet før 7b | En spec og et bevis på 16 `[NY]`-records (#160) som første rigtige prøve |
| Restore-only (9×) | Beholdes, men skrives ind i gate 8 (forslag 3) | Papirgaranti svækkes; maskineri spares |
| »Fortrydelse kun ved restore« + »byg i restore, overfør samlet« | Omgøres: byg mod frisk dump, kør i prod (5c-1's form) | Ingen genspilsprøve før prod; kræver dump-disciplin (2-06) |
| OCR-rettelse er ikke ny påstand (2026-07-26) | Beholdes; men genbekræftes mod visionen (25/8), som kom bagefter | Intet |
| »Ingen flere fulde afgørelsesark« (2026-09-27) | Beholdes — rigtig | — |

### 2.5 Udestående — samlet og prioriteret

Råmateriale: 0d's 126 punkter og fase 1-fund. Dubletter er slået sammen; 0d-numre i parentes.

**A. Gates før trin 6 (skal lukkes; de fleste er små):**

1. 1b-01 + 1d.1-05: porter RED-8 til `schema.sql`, udvid paritetsvagten (1b-02) — eller generér skemaet (1b-05).
2. 1c-01: fjern/vagt `--reset` i `load_presens.R`; frys præsensloaderen.
3. 1a-02 + 1d.3c-01/04/05: **én beslutning om de gamle skriveveje** (`load_daa.R`, `post_load_fixup.R`,
   `backfill_slaegtled.R`): frys med `--jeg-mener-det` og kontraktport, ret CLAUDE.md:23 og SKILL.md samme dag.
4. 1a-01: skriv `status.md` om til ét snapshot; forbyd tillæg; ret `roadmap.md:21-25` (0d:117, 0d:107).
5. **1d.3b-01 (min P1):** én `WHEN`-linje i `judged` for ægteskab/forælder mod `decision_evidence.family_id` + test.
6. 1d.3a-03: projektejeren læser de 13 `NOISE_RE`-linjer mod kilden; én disposition pr. linje (0d:4).
7. 1d.1-03 (+1d.1-04): `ON CONFLICT DO NOTHING`, kopiér `date_certainty`, statusfilter i cachen.
8. 1d.2-02: ny klausulregelversion med parentesfletning (= 1c-14).
9. Beslutning 1d.1-07: medlemskab fra anden kilde → `corroborated`, ikke `conflict`.
10. Beslutning 1d.3a-01: `verbatim_text`-semantik pr. udgave i trin 6-spec.
11. Beslutning 1a-07: promotion-kontrakt v2 (oprettelse + membership via promotion).
12. Beslutning 1a-10: røgtest eller strengt blind — ét af dem.
13. 2-04: 10-års-regel og behandlingsgrundlag — juridisk afklaring, ikke kode.
14. De fire `unresolved_text` (I-133, II-35, III-129, IV-94) — tekstrettelse besluttes (0d:3, 0d:101).

**B. Trin 6's indhold (1939 gennem kæden):**

15. 1939-klausulregler i profilen (0d:109) — i dag ingen `clause_rules` for 1939 (opslag 15).
16. 1939-årstal udledt af rå tekst, så kandidater får mere end navn (0d:60); `samme_som`-klynger i
    generatoren (0d:59); kandidatvisning med embede/titel/post (0d:61); dubletreglen for navnefæller (0d:89).
17. 1939-placement og legacy-asymmetrien kilde 1/3 (0d:100, 0d:102); `linje='1939'` pladsholder 542 rækker (`08-systemkort.md:120`).
18. #158-#163: 16 `[NY]`, 7 staged, 16 tomme unioner, grænsekandidater — **brug de 16 `[NY]` som første rigtige prøve af
    `relation_person_create`/`person_create`** (0d:9, 0d:15-16, 0d:67-68).
19. Én påstand → flere familier (0d:73); `F`-kort familiekorrektion (0d:74); `samme_som` for dubletter (0d:75);
    »(F.: …)«-fejllæsning (0d:76); unavngiven forælder (0d:77); 5b's M1-M10 (0d:78).
20. Næste promptversion + 138 navne-assertions + runnerens kvotefejl (0d:38, 0d:40, 0d:42) — og 1a-15's
    ejerskab af navnereglen (prompt eller navneregel v3).
21. `mention.place` og stedsentiteter (0d:80); promotion-regler for embede/dekoration m.fl. (0d:45).
22. Sandbox-huller i runneren (0d:54); `44-apply.R` uden `--jeg-mener-det` (0d:55); #189 segmentering (0d:55).

**C. Læser- og redaktørværdi (det, der mangler for »et godt, færdigt produkt«):**

23. Fakta-sektion i persondetaljen med kildehenvisning (1a-03, 0d:21) — én beslutning, én dags skive.
24. Binding synlig for læseren (0d:49); 5c-2 læserskift (0d:96).
25. Én redaktionel kø for uafgjorte forslag + normaliseringsregel for `SKRIVEMAADE` (2-03, 0d:49).
26. Redaktionel rettelsesflade for familiefejl (2-08) i stedet for prod-ceremonier.
27. Konfidens afledt af bindingens oprindelse (2-05).
28. `authenticated`-tier og samtykke (0d:24); 120-års-regel i RLS (0d:23); `samtykke_offentlig`.
29. Hændelsesudtræk #130 (0d:20), fuldtekst #132, suggestion-apply #128, geo #131 — uden for genimport, men det
    er dem, læseren ville mærke.
30. 627 gift-ind-ægtefæller uden `person_external_id` (0d:30).

**D. Hygiejne og arkiv (billigt, men det afgør, om trin 6 kan læses):**

31. Arkivér 1939-engangskode (1c-07), C3-funktioner (1b-08), C3-deployfil (1b-04/1c-05), røde R-tests (1c-04),
    4.4-pakken (1a-06), `evidenspas_v2` (1c-09), `supabase_load.R` (1c-15), upgrade-scripts (1c-13).
32. Dubletdefinitioner i `schema.sql` (1b-09); `koen` ud af invariant 4 (1b-12); invariant 1's undtagelser i tekst
    (1a-08/1b-06); `pg_temp` i `search_path` (1b-11, teoretisk).
33. CI: `discover` med udelukkelsesliste (1c-02); skipif for `rg`/`node` (1c-03); ret dækningstallene (1c-06).
34. Døde planer og »næste fokus« (1a-14); `flere-daa-udgaver-roadmap.md` (2-07); upushede docs-grene (0d:122);
    718 lokale baser (0d:121, måles før sletning).

**E. Lovligt parkeret (ingen handling før en beslutning):** spor H/M, C1/C2, DNA, mediefase 5, flersproget,
leaked-password (tier), `max(id)+1`-race ved flerbruger (0d:25, teoretisk ved én redaktør).

**Hvad der slet ikke står i 0d (nyt):** 2-01 opret-ben, 2-02 segmenteringsprofil, 2-03 kø, 2-04 jura, 2-05 konfidens,
2-06 dump-disciplin, 2-07 trin 6/7-spec, 2-08 rettelsesflade, 2-09 modstridende udgaver.

### 2.6 Efterprøv afvejningen

**Rammen.** Opus efterprøvede alle 28 fund på de citerede linjer og læste koden rigtigt i hvert tilfælde, jeg har
kontrolleret (1d.3b-01, 1d.3a-03, 1d.1-07, 1d.3a-01; opslag 1-5). Alvoren blev derimod sat ud fra *nuværende skala*:
én redaktør, én familie, ingen kendt forekomst. Briefets spørgsmål er, om *metoden* holder for trin 6-7. Det er en
anden horisont, og under den er tre af nedjusteringsargumenterne ugyldige:

- **»Latent ved nuværende skala« / »ingen kendt forekomst«** er ikke en nedjustering for et fund i en vagt, hvis eneste
  formål er den situation (1d.3b-01, 1d.1-02). Det er netop i trin 6, skalaen ændrer sig.
- **»Procedurekontrolleret«** (1d.3a-02, 1d.2-04) holder, så længe proceduren er den samme person. Det er den.
  Men for trin 7 er værktøjerne ikke længere »kørt én gang«.
- **»Projektejerens dokumenterede valg«** er gyldigt — og Opus bruger det rigtigt for 1d.1-01, 1d.3b-02 og 1e-02.
  Ét forbehold: 1d.1-01's valg (2026-07-26) ligger *før* visionens »originalen er uforanderlig« (2026-08-25).
  Ejeren bør genbekræfte det én gang; jeg foreslår ikke at omgøre det.

**Hvor Opus har ret, og jeg er enig:** 1d.1-01 (afvis), 1d.1-06 og 1d.3c-02 (teoretiske; skrivepause og én operatør),
1d.1-08 (CI har generel opgraderingssti), 1d.2-01 (regenererbart lag, #130 ikke kørt), 1d.2-04 (kontrolmodellen er
ikke et værn alligevel), 1e-02 (NOTICE med vilje), 1e-04 (allerede håndteret), 1e-01 (klassifikator, ikke bevis),
1e-05 (formulering), 1d.3c-03 (afsluttet ceremoni; ret ved genbrug), 1d.1-03 og 1d.2-02 (nødvendige, P2).

**Hvor jeg er uenig** — se tabellen i afsnit 4. Det vigtigste:

- **1d.3b-01 → P1.** Jeg har efterprøvet det (opslag 1-2): `judged` sammenligner for ægteskab/forælder kun tilstandens
  familie med den *anmodede* (`schema.sql:17475`), `REBIND_FAMILY_CHANGED` kræver en tidligere binding (`:17482`), og
  børnegrenen har præcis den manglende vagt (`:17053-17054`). Opus' egen tekst siger, at hullet »modsiger
  projektejerens egen begrundelse« for at fravælge rute B og at »konsekvensen kan være offentlig«
  (`15-afvejning-codex.md:367-369`, `:380`). Det er samme fejlklasse som #248, der *var* offentlig og kostede to
  ceremonier. Rettelsen er én linje. En P1 med en éns-linje-rettelse er stadig P1; alvor og pris er to akser.
- **1d.3a-01 → P2 for metoden.** Samme kolonne med to betydninger på tværs af udgaver er et brud på »fælles kæde«,
  som er selve generaliseringskriteriet (`03-teknisk-maalarkitektur.md:208`). Det skal *besluttes* i trin 6-spec'en,
  ikke noteres.
- **1d.1-02 → P2 for metoden.** UI'et tilbyder sletning af importerede påstande med `uforanderlig=true`
  (`15-afvejning-codex.md:77-79`), og trin 4-5's bindinger peger på assertions. Opus' egen mindste rettelse (én vagt)
  er rigtig; alvoren bør følge med, fordi vagten er den eneste håndhævelse af invariant 1 (1b-06).
- **1d.3c-04 → P2.** »Loaderen er lukket« hviler på en kontraktversion, mens CLAUDE.md:23 og SKILL.md:189 sender nye
  indlæsninger netop dertil (1a-02). `levende = FALSE` som standard er fail-*open* for privatliv (Opus siger det selv,
  `15-afvejning-codex.md:517-518`) — et direkte brud på visionens »fail-closed skjult« (`01-vision.md:38-39`).
  P2, indtil 1a-02 er besluttet; derefter P3 eller lukket.
- **1a-03 → P1 for produktet.** Fase 1's P1-definition er »risiko for data« eller »bevis, der ikke beviser«. Under den
  er 1a-03 korrekt P2. Men for spørgsmålet »dækker det behovet« er det den største risiko i projektet: ti uger uden
  synlig værdi. Jeg markerer det som P1 *for produktet*, ikke for data.
- **1d.1-07:** samme alvor (P2), men status »gate før trin 6-spec«, ikke »forenkl«. Enig i Opus' løsning (`corroborated`).

**Samlet:** Opus' 0 reelle P1 holder for »kan noget gå galt i prod i dag«. For »holder metoden« er svaret 1 P1
(1d.3b-01) plus 2-01 fra dette spor, og fire P2, som skal lukkes eller besluttes før trin 6.

---

## 3. Nye fund (2-NN)

### 2-01 — Kæden har intet bevist opret-ben
- **Område:** promotion / trin 7 · **Alvor: P1** (metode; ikke data i dag)
- **Sted:** `docs/decisions.md:1311-1313` (pkt 6); `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md:669-677`
  (11.3); `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md:82-84`;
  `docs/evidensbaseret-genimport/2018-20-fuld-koersel.md:11-14`, `:63-65`; `04-status.md:166`;
  `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md:64-66`
- **Påstand:** Alt, der er `produktionsverificeret` i trin 4-5, binder til eller bekræfter kanoniske rækker, som
  `load_daa.R` skrev. Ingen del af kæden har oprettet en kanonisk person, familie eller faktum fra kilde på rigtige data.
- **Evidens:** 3.739 forslag → 622 bindinger, 0 nye fakta; 5b's familiesignal er loaderens eget output; 5a's facit er
  149b's kobling; `relation_person_create` 0 elementer; D-reglen (≤ 1906) gav 0 tilfælde.
- **Konsekvens:** Trin 7 for en ny slægt kan ikke køres. Den dokumenterede vej er den gamle loader (1a-02), hvis
  fejlklasser (dobbeltfamilier, spøgelses-unioner) ville komme med.
- **Forslag:** Spec for opret-benet før 7b: `person_create` + familieplads + placement gennem identity- og
  promotion-gaten; første rigtige prøve på 1939's 16 `[NY]`-records (#160). Mål: 0 brug af `load_daa.R`.
- **Sikkerhed:** verificeret.

### 2-02 — »Lille profil« gælder ikke segmentering og udtræk
- **Område:** ekstraktion/segmentering, generalisering · **Alvor: P2** (metode)
- **Sted:** `.claude/skills/daa-extract/scripts/segment.py:42-43`, `:46-80`;
  `.claude/skills/daa-extract/references/extraction-profiles.json` (`profiles.daa-1939-v1`: 8 nøgler, ingen
  `clause_rules`; `daa-2018-20-v2`: `clause_rules` med 11 nøgler); `.claude/skills/daa-extract/references/reimport-profiles/`
  (5 filer, 252 linjer); `schema.sql:18030-18034`; 1c-10; `01-vision.md:13-15`; `03-teknisk-maalarkitektur.md:68-72`
- **Påstand:** Udgavens fysiske og sproglige form (det, målarkitekturen siger profilen ejer) ligger i kode:
  ca. 20 1939-regexer i `segment.py`, tre navneregel-moduler, titelord i SQL. JSON-profilerne er små, fordi det
  tunge ikke er i dem.
- **Evidens:** opslag 6, 13, 15, 20 (afsnit 6).
- **Konsekvens:** En tredje årbog er en kodeopgave i den fælles fil, ikke en profil. 1939's segmentering kostede
  U32-U34 (537 commits, ~40 specs; `10-fund-1a.md:43`). Det er det skøn, 7b skal regne med.
- **Forslag:** Profilkontrakt = JSON + ét udgavemodul pr. lag bag en navngiven grænseflade; `segment.py`'s 1939-del
  flyttes ud som første modul; mål »lille« i linjer ved 7b.
- **Sikkerhed:** verificeret.

### 2-03 — 83 % af trin 4's forslag er dødt lager uden kø
- **Område:** fortolkning, redaktionel værdi · **Alvor: P2**
- **Sted:** `docs/evidensbaseret-genimport/2018-20-fuld-koersel.md:63-65`; `07-beslutningskronologi.md:181` (pkt 1:
  »ikke-promoverbare forslag forbliver `proposed`«); `09-udestaaende-raa.md:66`, `:68`
- **Påstand:** 2.463 ikke-promoverbare forslag (mentions og events uden promotion-regel — bevidst udskudt i spec'ens
  åbne punkt 11.2, ikke en fejl i runneren) og 654 afgjorte-men-ubundne/uafgjorte (570 `SKRIVEMAADE`, 54 `REAL_DIFF`,
  30 `NO_FACT`) har ingen redaktionel flade og ingen læserflade.
- **Evidens:** kontrolmodellens tal (`2018-20-fuld-koersel.md:63-65`); 1.276 promoverbare af 3.739; beslutningen
  2026-09-27 pkt 1 lader ikke-promoverbare blive `proposed`; 0d:49 og 0d:51 bekræfter, at ingen har set dem.
- **Konsekvens:** Trin 4's udbytte for læseren er 0, og for redaktøren en privat tabel. `SKRIVEMAADE` (570) er det
  største enkeltudestående og kræver kun én normaliseringsregel (0d:49).
- **Forslag:** (a) normaliseringsregel for skrivemåde som beslutning; (b) én kø (5a-webkøens form) for
  `REAL_DIFF`/`NO_FACT`; (c) beslut for mention/event enten promotion-regel eller »narrativet bærer det« — og luk dem.
- **Sikkerhed:** verificeret (tal); konsekvens sandsynlig.

### 2-04 — 10-års-reglen og behandlingsgrundlaget ved skalering
- **Område:** GDPR/proces, trin 7 · **Alvor: P2** (metode; kræver juridisk afklaring)
- **Sted:** `docs/decisions.md:1304-1310` (regel 1-4; pkt 5 »ChatGPT-abonnementet … som grundlag«);
  `docs/superpowers/specs/2026-09-06-trin4-…-design.md:655` (»14 døde 1990 eller senere«); `04-status.md` (fuld
  kørsel 488/591); `05-CLAUDE.md:5-7` (»foreningens samlede data«)
- **Påstand:** Udelukkelsen bruger »afdød«, ikke »død for mere end 10 år siden«. Databeskyttelsesloven lader
  forordningen gælde for afdøde i 10 år (§ 2, stk. 5). Behandlingsgrundlaget er projektejerens personlige abonnement,
  ikke foreningens aftale.
- **Evidens:** regel 1-4 bruger dødsevidens uden tidsgrænse (`docs/decisions.md:1304-1307`); 14 hovedpersoner døde 1990
  eller senere (trin 4-spec:655); pkt 5 vælger abonnement frem for API-nøgle med databehandlervilkår (`:1308-1310`).
- **Konsekvens:** Ved 2018-20 er det få poster. Ved en moderne slægt eller foreningens data er foreningen
  dataansvarlig, og et abonnement er ikke en databehandleraftale. Det stopper trin 7, ikke trin 6.
- **Forslag:** Regel »død før (år − 10)« i udelukkelsen (billig, deterministisk); én beslutning på foreningsniveau om
  behandlingsgrundlag før 7a/7b. Jeg afgiver ikke juridisk vurdering; jeg flager, at ingen har gjort det.
- **Sikkerhed:** tallene verificeret; den juridiske præmis sandsynlig (efterprøves af jurist).

### 2-05 — Evidenskæden skriver ikke konfidens
- **Område:** datamodel (invariant 7), læserværdi · **Alvor: P3** (P2 for metoden)
- **Sted:** `schema.sql:17812`, `:17816` (`INSERT INTO public.family_member(… konfidens) VALUES (…, NULL)`);
  `schema.sql:16948` (5b læser `omstridt`/`formodet`); `05-CLAUDE.md:37`; `leverancetidslinje.md:46` (PR #9)
- **Påstand:** Nye personer fra kæden får `konfidens = NULL`; `structural_family`-bindinger rører ikke
  `family_member.konfidens`. Slægtskabsfinderens konfidens stammer alene fra loaderen.
- **Evidens:** grep `konfidens` i `schema.sql` (41 hits; de 10 efter linje 15000 læser eller indsætter NULL, ingen
  skriver en værdi fra en afgørelse); finderen leverer »konfidens på stien« siden PR #9 (`leverancetidslinje.md:46`).
- **Konsekvens:** Kernefunktionen »er vi i familie?« viser usikkerhed, som kæden aldrig opdaterer — hverken
  maskinel accept, ordinal-afvigelse eller menneskelig afgørelse afspejles.
- **Forslag:** Afled konfidens af bindingens oprindelse ved promotion (`machine-corroboration` → sandsynlig,
  menneskeark → sikker, `ordinal_beholdt`/afvigelse → formodet). Få linjer i promotion-RPC'en.
- **Sikkerhed:** verificeret (kode); konsekvens for finderen sandsynlig (finderen ikke læst).

### 2-06 — Fortrydelsens ene fejlpunkt er et dump på en laptop
- **Område:** publicering/prod-overførsel, beviser · **Alvor: P2** (delvist = 1a-04 + 0d:33; synteseen er ny)
- **Sted:** `05-CLAUDE.md:59` (ingen backup, free tier); 1a-04 (restore-only 9×); `07-beslutningskronologi.md:232`
  (`docs/decisions.md:3507`: »oprydning 18/9 slettede et fredet prod-dump«); `04-status.md:45` (»pausens dump er det
  nye restorepunkt«)
- **Påstand:** Hele fortrydelsesgarantien for trin 4-5 er ét dateret dump, som ingen tjeneste tager, og som én gang
  er blevet slettet ved en fejl.
- **Evidens:** restore valgt som eneste fortrydelse 09-17, 09-23, 10-01, 10-06, 10-21 m.fl. (1a-04's ni steder);
  free tier uden backup (`05-CLAUDE.md:59`); regel »sletning kræver måling først« indført, fordi et fredet dump blev
  slettet (`docs/decisions.md:3507`).
- **Konsekvens:** Målarkitekturens gate 8 er i praksis »hvis filen findes«. Risikoen er lav i dag (få læsere), men
  den er den eneste garanti, og den er ikke målt.
- **Forslag:** Når gate 8 omformuleres (2.4 forslag 3): krav om to kopier af hvert restorepunkt (én uden for
  maskinen), hash i `database-current-state.md`, og »dump findes og hash passer« som første skridt i enhver ceremoni.
- **Sikkerhed:** verificeret (dokumenter).

### 2-07 — Trin 6 og 7 findes kun som overskrifter
- **Område:** roadmap, generalisering · **Alvor: P2**
- **Sted:** `08-systemkort.md:457-483` (ingen spec/plan/kode); `04-status.md:179` (`specificeret`);
  `02-roadmap.md:36-38`; `docs/flere-daa-udgaver-roadmap.md:3-6` (»ingen kode … afventer en konkret PDF«;
  »det eneste der er indlæst i dag — DAA 2018-20«)
- **Påstand:** Generaliseringsbeviset (`03-teknisk-maalarkitektur.md:203-214`) har ingen spec, ingen kandidat-årbog og
  en forældet produktroadmap, der ikke ved, at 1939 findes. »Tredje årbog« blander ny udgave af samme slægt og ny
  slægt — to forskellige problemer.
- **Evidens:** systemkortets enheder for trin 6 og 7 har 0 specs, 0 planer, 0 kode (`08-systemkort.md:460-466`,
  `:474-480`); roadmappets status er »specificeret, ikke implementeret … afventer en konkret PDF«
  (`docs/flere-daa-udgaver-roadmap.md:3-5`) og »det eneste der er indlæst i dag — DAA 2018-20« (`:11`).
- **Konsekvens:** Trin 6 planlægges fra nul oven på 126 udestående; trin 7 har intet mål at bevise mod.
- **Forslag:** Opdel 7 i 7a/7b (afsnit 2.4), vælg kandidat-årbog nu, og skriv trin 6-spec'en med de ti beslutninger
  fra 2.5 A som indgang. Markér `flere-daa-udgaver-roadmap.md` historisk eller skriv den om.
- **Sikkerhed:** verificeret.

### 2-08 — Ingen redaktionel rettelsesvej for kanoniske familiefejl
- **Område:** redaktionel flade, proces · **Alvor: P2** (1a-12 har ceremoni-omkostningen; manglen i fladen er ny)
- **Sted:** `07-beslutningskronologi.md:422` (`docs/changelog.md:3273`: »redaktøren har ingen flade til at rette den
  slags fejl — rettelsen krævede direkte SQL«, 2026-07-06); `:35` (`red_slet_union` bygget og droppet);
  `10-fund-1a.md:52` (fire prod-ceremonier 26/10); `09-udestaaende-raa.md:113` (#248: ingen web-vej til genåbning)
- **Påstand:** Fejl i familiestrukturen (dobbeltfamilier, forkert partner) kan kun rettes med scripts og ceremoni.
  Det har været kendt siden juli og er ikke taget op som redaktørbehov.
- **Evidens:** #240's sammenlægning er `fix_240_saml.sql` + runbook (`08-systemkort.md:416`, `:422`), ikke en RPC;
  #248's genåbning har »ingen web-vej« (0d pkt 90); `red_slet_union` droppet 2026-08-01.
- **Konsekvens:** Hvert datafund i trin 6 (1939 har flere) bliver en runbook. Det er den største enkeltkilde til
  ceremoni-omkostning i U44.
- **Forslag:** Én redaktørhandling »saml to familier« og »flyt partner« gennem `change_set` (som #240's SQL, men bag
  RPC + preview), før trin 6 begynder at finde 1939-fejl.
- **Sikkerhed:** verificeret (dokumenter).

### 2-09 — »Modstridende udgaver håndteres indfødt« er uprøvet
- **Område:** datamodel/fortolkning · **Alvor: P2** (metode)
- **Sted:** `06-datamodel-oversigt.md:99-102`; `docs/decisions.md:1311-1313` (tekstidentiske assertions);
  `09-udestaaende-raa.md:61` (4 accepterede uoverensstemmelser »står accepteret og ubundet«);
  `2018-20-fuld-koersel.md:63-65` (54 `REAL_DIFF`)
- **Påstand:** Datamodellens salgsargument — to udgaver, to påstande, synlig udvikling — er aldrig udøvet. Når
  mennesket accepterer en reel uoverensstemmelse, skrives hverken en konkurrerende påstand eller en `omstridt`
  konklusion; forslaget står accepteret og ubundet.
- **Evidens:** pkt 6 binder kun til »eksisterende, tekstidentiske assertions« (`docs/decisions.md:1311-1313`);
  54 `REAL_DIFF` i fuld kørsel; de 4 accepterede (I-24, I-43, V-18, IV-19) »står accepteret og ubundet« (0d pkt 44).
- **Konsekvens:** Trin 6 (1939 mod 2018-20) er netop dét tilfælde i stor skala. Uden en vej fra `REAL_DIFF` til
  påstand+konklusion bliver trin 6's uenigheder også liggende.
- **Forslag:** Design »accept som konkurrerende påstand« som promotion-regel: ny `assertion` (kildebundet), ny
  `conclusion` med status `omstridt` eller uændret valgt. Det er opret-benets mindste udgave og kan bevises på de 4.
- **Sikkerhed:** verificeret (tal og dokumenter); hvad A-afgørelsen skriver, er aflæst af 0d/bevisrapport, ikke af kode.

---

## 4. Uenig med fase 1

| Fund | Fase 1 | Min alvor/dom | Begrundelse (én linje) |
|---|---|---|---|
| 1d.3b-01 | P2 forenkl (Opus) | **P1**, gate før trin 6 | Vagt uden sin eneste funktion; samme fejlklasse som #248 (offentlig); 1939's navnefæller gør rækkefølgen sandsynlig; verificeret `schema.sql:17475/17482` mod `:17053-17054` |
| 1d.3a-01 | P3 forenkl | **P2** (metode), beslutning i trin 6-spec | Én kolonne med to betydninger bryder »samme kæde«, som er generaliseringskriteriet |
| 1d.1-02 | P3 forenkl | **P2** (metode) | UI sletter `uforanderlig=true`-påstande, som bindinger peger på; vagten er invariant 1's eneste håndhævelse |
| 1d.3c-04 | P3 kendt begrænsning | **P2** indtil 1a-02 er besluttet | »Lukket« hviler på kontraktversion, mens CLAUDE.md:23 peger dertil; `levende=FALSE` er fail-open for privatliv |
| 1d.1-07 | P2 forenkl | P2, **gate før trin 6-spec** | Ikke en forenkling, men en beslutning trin 6 ikke kan starte uden |
| 1a-03 | P2 | **P1 for produktet** (P2 for data) | Ti uger uden læserværdi er projektets største risiko; fase 1's P1-definition dækker den ikke |
| 1a-12 | P2 | P2, men **den samlede dom** for proces | Ikke et fund blandt andre; proportionen er årsagen til 1a-04/05/06/10 |
| 1d.1-01 | afvis | afvis, **med genbekræftelse** | Ejerbeslutning 07-26 ligger før visionen 08-25 (»originalen er uforanderlig«); én linje i decisions |
| 1e-01 | P3 forenkl | P3 (enig), men ret runbook l. 69 nu | »Bundet« lover fuldstændighed, som kun `expect.json` beviser |

Hvor jeg er **enig uden forbehold**: 1b-01 (ejerens P1 er rigtig — bevis-aksen), 1d.1-03, 1d.2-02, 1d.3a-03 (P2 hård
gate; jeg tilføjer kun, at det er et brud på »ingen tavse tab« i publiceret tekst), 1d.1-06/1d.3c-02/1b-07/1b-11
(teoretiske ved projektets skala), 1e-02, 1e-04, 1d.2-01, 1d.2-04, 1d.1-08, 1d.3c-03, 1d.3b-02, 1d.3b-03 (lukkes af
3b-01's vagt).

---

## 5. Dom pr. område

| Område | Dom | Begrundelse |
|---|---|---|
| Datamodel og invarianter | **solidt men overbygget** | Modellen (påstand/konklusion, generisk relation, source record ≠ person) er projektets bedste aktiv og holder mod bogen (`06-datamodel-oversigt.md:124-137`). Men tre af ni invarianter er tekst: 1 (1b-06), 4's `koen` (1b-12), 7 (2-05), 9 (0d:26) — og 2-09 viser, at modellens kerneløfte ikke er udøvet |
| Ekstraktion/segmentering | **bør laves om** | Udgavelogik i fælles kode (2-02), `NOISE_RE` uden disposition (1d.3a-03), parentesfletning død (1d.2-02), 0/30 og 1/25 CI-dækning (1c-02). Det er laget, trin 7 møder først |
| Source records/personas | **solidt** | 149a/149b beviste proveniens på den rigtige bog med nul delta; persona ≠ person holdes konsekvent. Rester: semantik pr. udgave (1d.3a-01), ubundet side/nøgle i builder (1d.3a-02) |
| Fortolkning | **solidt men overbygget** | Runner og klausullag er en reel kontrakt (99 % præcision). Men 83 % af udbyttet ligger dødt (2-03), kontrolmodellens ceremoni overstiger dens bevisværdi (1a-10), og 4.4-pakken var spildt (1a-06) |
| Identitet | **hul** | Facit cirkulært (5a-bevis:64-66), kandidater uden årstal for 1939, `samme_som` ukendt for generatoren, navnefæller gav #248, og 1d.3b-01 står åbent. Kernen (`decide_source_persona_identity`, låsning, versioner) er derimod solid |
| Promotion | **hul** | Kun binding; intet opret-ben (2-01); kontrakten modsiges (1a-07); modstridende udgaver uprøvet (2-09); første binding efter familieskift uvagtet (1d.3b-01) |
| Publicering/prod-overførsel | **bør laves om** | Restore-only + genspilspakke kostede ~1 uge pr. trin og gav en garanti, der hviler på ét dump (1a-04, 2-06). 5c-1's form er bedre og bør være standard; gate 8 skal skrives om |
| Beviser og verify | **solidt men overbygget** | Beviserne er ærlige om deres afgrænsning (1e), og katalogtjek er stærke (1b). Men digests beviser binding, ikke indhold; tokentjek (1b-14), `SKIP`=grøn (1e-03), og »bundet« lover mere end målt (1e-01) |
| Test/CI | **hul** | Skemaet, CI bygger fra, er ikke prods (1b-01/02); kernen i importen kører ikke i CI (1c-02); dækningstallene var målt forkert (1c-06); 64 % af testlinjerne er 1939-engangskode (1c-07) |
| Proces og beslutningsstyring | **hul** | Visionen og model 2 er rigtige; disciplinen om ét mål holdt i oktober. Men orakelet (`status.md`, roadmappets status) modsiger sig selv (1a-01), budget og afbrydelser håndhæves ikke (1a-05/09), og ingen har besluttet proportionen (1a-12). Hul, fordi det er dét, der skal læses først |

---

## 6. Opslag i EKS (21 af loftet på 25)

1. `schema.sql:17440-17505` — `preview_relation_promotions`/`judged` (1d.3b-01)
2. `schema.sql:17045-17060` — `relation_binding_state`, børnegrenens `family_id`-vagt (1d.3b-01)
3. `.claude/skills/daa-extract/scripts/segment.py:35-45` og `:195-210` — `NOISE_RE` og overspring (1d.3a-03)
4. `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md:655-690` — §10-§12, åbne punkter 11.1-11.7
5. `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md:55-100` — beslutninger, arkitektur, »Ærligt om beviset«
6. `.claude/skills/daa-extract/references/reimport-profiles/` — `ls` + `wc -l` (5 filer, 252 linjer)
7. `docs/moed-en-slaegtning-roadmap.md:1-45`
8. `docs/flere-daa-udgaver-roadmap.md:1-45`
9. `docs/reviews/2026-10-27-trin-1-5/maalinger.md:1-75`
10. `_issues.txt` (hele, 14 linjer)
11. `docs/evidensbaseret-genimport/2018-20-fuld-koersel.md:1-70`
12. `.claude/skills/daa-extract/references/reimport-profiles/daa-2018-20-interpretation-proposal-v1.json` (hele)
13. `schema.sql` — grep af `CREATE FUNCTION|TABLE|VIEW` med `1939|2018|v50|reventlow` i navnet (23 unikke) og `:18028-18040` (`relation_title_words`)
14. `.claude/skills/daa-extract/references/` — `ls`
15. `.claude/skills/daa-extract/references/extraction-profiles.json` — nøglestruktur (to niveauer; ingen regex-indhold læst)
16. `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md:60-120`
17. `docs/database-current-state.md:1-60`
18. `docs/reviews/2026-10-27-trin-1-5/leverancetidslinje.md:1-70`
19. `docs/decisions.md:1286-1312` — trin 4's seks valg
20. `.claude/skills/daa-extract/scripts/segment.py:46-80` — 1939-regexer i koden
21. `schema.sql` — grep `konfidens` (41 hits; 10 efter linje 15000, heraf `:17812`, `:17816`)

Ikke læst: `work*`, `~/.private`, dumps, manifester, kontrolark, tokens, `.env*`. Ingen database, intet netværk, ingen git.

---

## 7. Hvad jeg ikke nåede

- Jeg har ikke læst slægtskabsfinderen (`mobile/src/data/relationship.ts`, web's `RelateView`) og kan derfor ikke
  sige, *hvordan* konfidens vises (2-05's konsekvens er sandsynlig, ikke målt).
- 1d.1-03, 1d.1-04, 1d.3c-01, 1e-01 og 1e-03 er efterprøvet gennem Opus' linjecitater, ikke genlæst af mig.
- Hvad en `A`-afgørelse på et `REAL_DIFF`-kort faktisk skriver i databasen (2-09), er aflæst af bevisrapport/0d,
  ikke af RPC-koden.
- Den juridiske præmis i 2-04 (10-års-reglen, abonnement ≠ databehandleraftale) er ikke efterprøvet af en jurist.
- Jeg har ikke målt, hvor meget af `segment.py` der er fælles vs. udgavespecifikt i linjer (2-02 bygger på
  intervallet 46-80 og kommentaren i 42-43).
- Ugeomkostninger er fase 1's (0e-afledte), ikke mine.
- Augusts ca. 40 1939-specs er kun set gennem 0b del 2; om dele af dem kan genbruges som 1939-profil i trin 6, er
  ikke vurderet.
- Jeg har ikke vurderet web/mobile-koden eller de formidlingsfunktioner (feed, medier, præsens-visning), der ligger
  uden for trin 1-5, ud over at konstatere, at de findes og at mobil er dev-only (0d:116).
