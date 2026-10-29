# Trin 6: 1939 gennem den fælles kæde — overordnet design

**Status:** udkast. Formål, omfang, opdeling og visning afklaret med projektejeren 2026-10-29 (§3); builder-check
indarbejdet (§6 pkt. 3, 7, 8). Godkendt af projektejeren 2026-10-29. Codex-runde 1 (`gpt-6.1-sol`): NO-GO, 7 fund,
alle accepteret og indarbejdet (§9). Næste: delspec for 6a.
**Gren:** `docs/trin6-spec` fra `main` (`19106f21`).
**Review-budget (B13):** denne spec: builder-check (frisk agent) + 1 Codex-runde (`gpt-6.1-sol`, Opus dømmer). Hver
delspec (6a-6e): 1 Codex-runde på spec+plan og 1 på diffen før prod. Fable én gang, før beslutningspunktet efter
trin 6, og kun efter projektejerens ja. Overskridelse kræver én linje i `docs/decisions.md`.
**Grundlag:** roadmap trin 6 (færdigbevis a-c); helhedsreviewet trin 1-5 (`docs/reviews/2026-10-27-trin-1-5/`,
rapport §5-6, `fable-koncept.md` §2.5 gruppe B pkt. 15-22); `docs/decisions.md` 2026-10-27 (B4, B6, B7, B8, B12),
2026-10-28 (A6b pkt. 2-3; projektets mål slutter med trin 6) og 2026-10-29 (vej B); kontrolmodellen 2026-09-27;
`status.md` snapshot 2026-10-29.

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6 — kæden køres ende-til-ende på begge referenceudgaver. Projektets mål slutter her.
2. **Værdikædeled:** alle led fra klausul til offentlig læseprojektion for 1939. Rendition, source records,
   forekomster, ankre og narrativpublicering for 1939 er allerede `produktionsverificeret`.
3. **Leverancetype:** 1939-udgaveprofil (klausulregler, normalisering) og generelle mekanismer, som 2018-20 også
   bruger (forældelse ved kildetekst-revision, set-baseret bindingstjek, `corroborated`, fakta pr. udgave i læseren).
   Ingen nye editionsnavngivne permanente overflader.
4. **Værdi:** læseren ser, hvad 1939 sagde om en person, sporbart til side og nummer; redaktøren afgør kun navnefæller
   og uenigheder mellem bogen og databasen og kan rette den gamle indlæsnings fejl (§3).
5. **Færdigbevis:** §8.
6. **Erstatter:** legacy-vejen for kilde 3: `person_external_id` med pladsholderen `linje='1939'` og
   `retained_legacy`-dispositionen som læserens og identitetens kilde; den uvagtede legacy-binding af 1939-fakta.
7. **Review-budget:** i hovedet ovenfor.

## 2. Udgangspunkt (målt)

Kilde: `status.md` 2026-10-29, `database-current-state.md`, afvigelsesvurderingen 2026-08-22, og en anon-måling mod prod
2026-10-29 (kun antal).

- **1939 i evidenslaget:** 1 rendition (`daa-1939-calamari-r6-clean`), 592 source records, 897 forekomster/mentions
  (hel post), **8** source personas med identitet, 0 fortolkninger, 0 placements, ingen `clause_rules` i profilen.
  Narrativpublicering er C3 (2026-08-29); ~559 narrativer er publiceret og bundet til records.
- **1939 i den kanoniske model (legacy):** ~569 offentlige kilde 3-personer med 576 `person_external_id`
  (alle `retained_legacy`, 542 med `linje='1939'`). 7 staged personer, 16 `[NY]`-records, 16 tomme unioner (#158-#163).
- **Sammenkædning:** af de 569 kilde 3-personer, som koordinat-RPC'en viser `anon`, er 472 med i en afklaret
  `samme_som`-kobling til en anden person (typisk 2018-20); 97 står alene (anon-måling 2026-10-29).
- **2018-20 til sammenligning:** 3.739 forslag; 1.276 promoverbare klassificeret 622 `MATCH`, 570 `SKRIVEMAADE`,
  54 `REAL_DIFF`, 30 `NO_FACT`; ét ark på 74 kort (20 stikprøve + 54 uenigheder); 622 bindinger.
- **Identitet før binding:** de fem aktive regler for påstandsbinding (tekst og dato) kræver en accepteret
  `source_persona_identity`, og faktummets subjekt skal være præcis personaens kanoniske personrække
  (`schema.sql:1430-1434`, `:9750-9757`). De tre strukturelle familieregler kræver ikke persona-identitet, men har
  deres egen partsvalidering mod præcise person-id'er (`:1473-1479`, `:17139-17172`). 2018-20 fik identiteten fra
  149b's `legacy_match`, før trin 4. Migreringen afviser records, der allerede har en publiceringsbinding
  (`LEGACY_MIGRATION_ALREADY_BOUND`, `:3968`, uanset status), men understøtter ellers publicerede legacy-narrativer;
  hvor mange 1939-records den kan bruges på, er ikke målt.
- **Læseren:** anon-rollens `statement_timeout` er 3 s; `public_person_facts` koster op til ~1,9 s for de tungeste
  2018-20-personer, fordi hvert bindingstjek læser `interpretation_current` (vej B). Fakta grupperes i dag kun pr.
  faktum; udgavevælgeren styrer kun prosaen.
- **Rettelsesvejen:** `red_ret_ocr_felt` retter `navn`, `foedsel`, `doed`, `koen` på stedet (journal i
  `import_korrektion`/`change_set`), kræver én `person_external_id` og vælger selv den ene valgte påstand under en
  afklaret konklusion med citation til kilden (`schema.sql:1984-2025`). `assertion_binding_current` sammenligner
  normaliseret tekst eller `date_raw` (`:18291-18296`): en tekstrettelse gør en binding ugyldig, en rettelse af
  `koen` eller af en dato uden ændret `date_raw` gør ikke. Kontrolklassifikationens `REAL_DIFF` peger ikke på én
  bestemt påstand; den sammenligner alle personens påstande af typen
  (`.claude/skills/daa-extract/scripts/interpretation_control_classification.sql:30-37,74-77`).
- **Medlemskab:** et medlemskab har i dag ét `source_basis`, én persona-placement og ét tilstandshash; promotion
  overskriver grundlaget, og læsningen tjekker placementen mod det præcise person-id (`schema.sql:2217-2225`,
  `:2959-2970`, `:3055-3062`, `:3111-3128`).
- **Børneflokke:** 5b's børneflok-regel læser børnenes `person_external_id.linje/nr` direkte
  (`schema.sql:16083-16130`), dvs. netop 1939's syntetiske koordinater.

## 3. Formål og projektejerens afgørelser (2026-10-29)

**Det læseren skal opleve.** En 1939-person afspejler bogen korrekt, og bogens data er bragt i spil, som mediet
tillader: datoer, titler, ægteskaber og børn som strukturerede, klikbare oplysninger, ikke kun prosa. I de fleste
tilfælde er 1939-personen den samme som en 2018-20-person; så er 2018-20 hovedvisningen, og 1939 er et historisk
øjebliksbillede af, hvad man vidste eller troede man vidste.

Projektejerens afgørelser:

1. **Visning:** personen åbner med 2018-20's prosa og fakta (nyeste viden). Trykker man på 1939 i udgavevælgeren,
   ser man 1939's fakta.
2. **Kun binding:** trin 6 binder det, der allerede findes, som for 2018-20. Nye fakta, personer og familier fra 1939
   (herunder de 16 `[NY]`) venter til opret-benet (B4).
3. **Redaktørens rolle:** projektejeren afgør navnefæller og uenigheder mellem bogen og databasen. Enighed afgøres
   automatisk (kontrolmodellen).
4. **Rettelse:** når bogen og databasen er uenige, og projektejeren vælger bogen, kan trin 6 rette databasen.
5. **Fakta pr. udgave:** 2018-20-visningen (standard) viser fakta med 2018-20 som kilde plus fakta uden kilde.
   1939-visningen viser alle fakta med 1939 som kilde: bundne med postreference, ubundne som »fra den oprindelige
   import«, så intet forsvinder. Personer, der kun findes i 1939, har ingen vælger og viser 1939's fakta. Følge,
   accepteret: i dag viser en sammenfoldet person 1939's importerede fakta blandet med 2018-20's; efter 6e ses de
   først, når man vælger 1939.

**Mine valg, markeret som sådan:**

- (a) Udgavevælgeren styrer både prosa og fakta; der kommer ingen ny knap. Personer uden flere udgaver har ingen vælger.
- (b) 1939-fakta i læseren viser postreferencen som 2018-20's (»DAA 1939, s. N · nr. x«).
- (c) En 1939-rettelse er en transskriptionsrettelse af 1939's påstand (B12-vejen), aldrig en ny påstand oven på den
  forkerte, og aldrig en ændring af 2018-20's påstand eller konklusion.
- (d) Projektejerens afgørelser gives som tokenfil med forudfyldte anbefalinger, højst ~30 kort pr. ark, og delt, så
  ét ark kan tages på en aften.

## 4. Mål, ikke-mål og anti-mål

**Mål**

- Færdigbevis (a)-(c) fra roadmappet for 1939 (§8).
- 1939-fakta synlige og sporbare i læseren, valgt med udgavevælgeren.
- A6b-resten: 2018-20's 11 poster får de manglende linjer i kildetekst og klausuler.
- Vej B: læserens fakta-kald holder sig klart under anons 3 s, også efter 1939's bindinger.

**Ikke-mål**

- Opret-benet: nye fakta, personer, familier eller relationer fra 1939 (B4), herunder de 16 `[NY]`, de 7 staged og
  de 16 tomme unioner, ud over en synlig disposition.
- Nye promotionsregler (embede, dekoration, steder; `fable-koncept` pkt. 21) og `mention.place`.
- At rette 1939 efter 2018-20. En uenighed mellem udgaverne er historisk indhold, ikke en fejl.
- Trin 7, perfekt OCR, generering af `schema.sql` (B9).

**Anti-mål (ville være fejl, selv om alt teknisk virker)**

- 1939 ændrer det, læseren ser som 2018-20's viden.
- En rettelse fjerner en binding uden at nogen ser det (tavst tab).
- Projektejeren skal udfylde fulde afgørelsesark eller bruge flere dage i træk.
- Læserens personside bliver langsommere end i dag eller rammer anons grænse.
- En ny parallel 1939-vej ved siden af den fælles kæde.

## 5. Opdeling og rækkefølge

Hver del får sin egen korte spec og plan og går i prod for sig med 5c-1-formen (B2): dump med ekstern kopi (B1),
kørsel mod prod med flag og GO, måling før og efter. Rækkefølgen er bindende; grænserne kan justeres i delspec'erne.

| Del | Indhold | Afhænger af |
|---|---|---|
| **6a — klausuler og forældelse** | 1939-klausulregler i profilen (pkt. 15); den generelle kildetekst-revision, der gør afhængige fortolkninger forældede (A6b pkt. 2), bygget og bevist, men ikke anvendt på prod-data her (§6 pkt. 7); B7 (§6) | — |
| **6b — identitet** | 1939-records opdeles efter eksisterende binding, publiceringstilstand, eksisterende persona og tvetydig identitet; 149b's migrering genbruges, hvor den gælder, og en idempotent persona-indgang bygges for resten (ingen nye personas for eksisterende, ingen genpublicering); kandidater med årstal fra rå tekst og `samme_som`-klynger (pkt. 16); navnefæller til projektejeren | 6a (planlægningsvalg: records står fast; ikke en teknisk forudsætning) |
| **6c — fortolkning, rettelse og binding** | Runneren på de tilladte 1939-poster med næste promptversion (pkt. 20) og lukkede sandbox-huller (pkt. 22); kontrolmodellen; rettelsesvejen (§6); vej B før bindingerne skrives; A6b-resten for 2018-20's 11 poster (revision, genkørsel og genbinding i én ceremoni, §6 pkt. 7) | 6a; 6b (identitet kræves af promotionen) |
| **6d — placement, relationer og medlemskab** | Intern rækkefølge: (1) 1939's linjeskema og mapping til slægtslinjer, (2) placements med bogens egne numre, der afløser `linje='1939'` (pkt. 17, §6 pkt. 8), (3) relationer (ægteskaber, børneflokke, numre; 5b-vejen, pkt. 19) vurderet på placementernes koordinater, ikke legacy, (4) binding og medlemskab med B6 (§6 pkt. 3) | 6b; 6c for fakta-afhængige relationer |
| **6e — læserflade** | Fakta pr. udgave fulgt af udgavevælgeren; 1939-koordinater fra placement; browsertjek | 6c, 6d |

## 6. Tværgående beslutninger

1. **Kontrolmodellen** (2026-09-27, B8) gælder uændret: `MATCH` accepteres maskinelt, projektejeren ser `REAL_DIFF`
   og en røgtest-stikprøve på 20 `MATCH`; én R eller U i stikprøven stopper. Ikke-promoverbare forslag og
   `SKRIVEMAADE` bliver stående `proposed` og tælles. *Mit valg:* `SKRIVEMAADE` behandles som for 2018-20; viser
   6c's måling, at 1939's ældre retskrivning giver langt flere, tages det op i 6c-delspec'en.
2. **Rettelse før binding.** Vælger projektejeren »bogen har ret« til en `REAL_DIFF`, rettes 1939's legacy-påstand
   (transskriptionsrettelse, B12, originalen bevaret i journalen), og først derefter bindes den, så bindingen er
   gældende fra starten. De tre valg for projektejeren er »bogen har ret«, »databasen har ret« (intet ændres;
   uenigheden noteres) og »ved ikke« (står uafklaret). Kontrakt for rettelsen:
   - **Præcist mål:** kortet og afgørelsen bærer ét versionsbundet påstands-id, som projektejeren har set, med den
     forventede konklusion og citationsmængde. Rettelsen verificerer dem i skrive-transaktionen og afviser ved drift.
   - **Kun 1939's egen påstand:** målet skal kun være citeret af kilde 3. En påstand, som en anden udgave også
     citerer, flere kandidater eller intet mål giver ingen rettelse, men en synlig disposition (»ved ikke« med grund).
     Der oprettes aldrig en ny påstand i stedet (opret-benet).
   - *Mit valg:* rettelsesvejen udvides fra `red_ret_ocr_felt`'s fire felter til de faktatyper, påstandsreglerne
     dækker, med ovenstående mål-krav i stedet for dens selvvalgte påstand.
   - **Ingen tavse tab:** en rettelse, der ville gøre en eksisterende binding ugyldig (tekst eller `date_raw`),
     afvises eller binder igen i samme transaktion. Ændringer i strukturerede værdier (datogrænser, kalender,
     sikkerhed, `koen`) måles for sig, da bindingens gyldighed ikke viser dem.
3. **B6:** et medlemskab fra en anden kilde bekræfter (`corroborated`) i stedet for at give `conflict`, når det
   angår samme person (direkte eller gennem en afklaret `samme_som`) og samme slægtslinje; ellers er det fortsat en
   konflikt til review. Numrene sammenlignes ikke: 1939's numre er gruppe-lokale (`docs/plan-1939-produktionsklar.md`
   A3a) og kan ikke stemme med 2018-20's. Kontrakt:
   - Et medlemskab kan have **flere kildegrundlag**. Hvert gemmes og valideres for sig med sin persona, personrække,
     placement og tilstandshash; et nyt grundlag overskriver aldrig et eksisterende.
   - Læsningen af medlemskabet (projektionen) er gyldig, så længe mindst ét grundlag er gyldigt; begge udgavers
     koordinater forbliver læsbare hver for sig.
   - Mister et grundlag sin gyldighed (placement ugyldig, `samme_som` trukket tilbage, identitet skiftet), bliver
     bekræftelsen stale og går til review; det andet grundlag står uændret.
   - Datamodellen for flere grundlag afgøres i 6d's delspec.
4. **B7, *mit valg*:** `verbatim_text`'s betydning deklareres pr. udgave i profilen (rå OCR eller normaliseret), og
   enhver sammenligning på tværs af udgaver går gennem `narrative_norm_v1`. Én fælles betydning ville kræve, at
   1939's eller 2018-20's tekst genskrives.
5. **Vej B** bygges i 6c, før 1939's bindinger skrives: bindingstjekket bliver set-baseret, så fakta-RPC'en ikke
   læser `interpretation_current` én gang pr. binding. Måles mod prod-størrelser, ikke stand-in-tid.
6. **Persondata:** kun poster om afdøde, offentlige personer sendes til en model (som 2018-20's 488 tilladte poster);
   arbejdsmapper med prosa forbliver gitignorerede og sendes aldrig til en model.
7. **A6b-resten uden tab, *mit valg*:** 9 af de 11 poster har 74 fortolkninger, nogle bundne. Gøres de forældede for
   sig, falder bindingerne ud af læseren. Kildetekst-revisionen af de 11 poster, genkørslen og genbindingen sker derfor
   i én ceremoni i 6c, hvor runneren alligevel kører; 6a bygger og beviser kun mekanismen. Afstemningen er nøglet:
   hver binding, der var gældende før ceremonien, ender enten genbundet til en gældende, accepteret fortolkning eller
   som en udtrykkelig, projektejer-godkendt tilbagetrækning, der er synlig i læseren som »fra den oprindelige import«.
   Et antal før og efter er ikke bevis; afstemningen listes pr. binding.
8. **Hvor 1939 hører hjemme, *mit valg*:** 1939's personas peger på kilde 3-personrækken, hvor 1939's påstande ligger,
   så faktabindingen virker uden at flytte fakta, og 1939 forbliver sin egen stemme. Sammenhængen med 2018-20 bæres af
   den afklarede `samme_som`. Hvor reglerne skal se på tværs af udgaver (B6 og familiebinding i 6d, fakta pr. udgave
   i 6e), lærer de at følge afklarede `samme_som`-koblinger som en generel, editionsneutral mekanisme; det gælder også
   familieopslaget og partsvalideringen i 5b-vejen, hvor et relevant familiemedlem kan stå på en anden række i
   komponenten. Tilfælde, mekanismen ikke dækker, får en synlig disposition; der indsættes aldrig familiemedlemmer
   eller familier (opret-benet). 1939-placements bærer bogens egne
   linjer og numre (læseren skal se bogen); om 1939's grupper svarer til eksisterende slægtslinjer, måles i 6d, og
   kræver det nye linjer, er det opret-benet og parkeres synligt.

## 7. Overladt til delspec'erne

- 6b's konkrete indgang til personas for allerede publicerede records (ny writer eller udvidet migrering), og hvordan
  de 472 `samme_som`-koblinger bruges: som kandidat, ikke som afgørelse.
- Rettelsesvejens tekniske form (§6 pkt. 2).
- Hvordan fakta-RPC'en og `buildPersonFacts` grupperer pr. udgave (6e).
- Disposition af #158, #159, #161, #162, #163 (synlig, ikke løst, medmindre de blokerer).
- Batchstørrelser, tidsmålinger og runbooks.

## 8. Færdigbevis

- **(a) Samme operationer:** 1939's klausuler, fortolkning, identitet, placement og publicering er gået gennem de
  samme RPC'er og writere som 2018-20, uden nye editionsnavngivne permanente overflader (tjekliste i hver delspec).
- **(b) Læseren** (browsertjek som `anon` mod prod):
  - en sammenfoldet person åbner på 2018-20; tryk på 1939 viser 1939's fakta med »DAA 1939, s. N · nr. x«;
  - en 1939-person uden 2018-20-modpart viser bundne 1939-fakta;
  - en rettet værdi viser bogens værdi og er bundet;
  - en 1939-person har linje og nr. fra placement, ikke `linje='1939'`;
  - personsiden for de tungeste personer svarer under anons grænse med god margen (mål sættes i 6c).
- **(c) To kilder:** mindst ét medlemskab er båret af både 2018-20 og 1939 og står `corroborated`; antal målt.
- **Tal i prod:** forslag, `MATCH`/`SKRIVEMAADE`/`REAL_DIFF`/`NO_FACT`, afgørelser (maskine/menneske), rettelser,
  bindinger, uafklarede. Hver binding, der var gældende før en ceremoni, er gældende efter eller står i den nøglede
  afstemning som godkendt tilbagetrækning (§6 pkt. 7); antal alene beviser det ikke.
- **A6b-resten:** de 11 posters kildetekst og klausuler har linjerne; afhængige fortolkninger er forældede og
  genafgjort, eller de står synligt uafklarede uden at have båret en binding, der ikke er afstemt.
- **Status:** `status.md`'s 1939-kolonne hæves led for led til `produktionsverificeret` med dato; derefter
  beslutningspunktet (roadmap).

## 9. Codex-runde 1 (2026-10-29, `gpt-6.1-sol`): NO-GO, 7 fund — afvejet

Alle fund er korrekte mod koden og ændrer ingen af projektejerens afgørelser i §3. De strammer den overordnede kontrakt.

| # | Alvor | Fund | Afvejning | Indarbejdet |
|---|---|---|---|---|
| 1 | HIGH | Rettelsen har intet sikkert mål: `REAL_DIFF` peger ikke på én påstand; RPC'en vælger selv | nødvendig | §6 pkt. 2: versionsbundet påstands-id, kun kilde 3's egen påstand, ellers synlig disposition |
| 2 | HIGH | B6 kræver flere kildegrundlag pr. medlemskab og deres livscyklus | nødvendig | §6 pkt. 3: flere grundlag, projektion, stale ved tab af grundlag eller `samme_som` |
| 3 | HIGH | 6d: børneflok-reglen læser legacy-koordinater; familieopslag kræver præcise person-id'er | nødvendig | §5 6d's interne rækkefølge; §6 pkt. 8 udvidet til familieopslag og partsvalidering |
| 4 | MEDIUM | A6b: »uafklaret« og »ingen binding falder ud« modsiger hinanden; antal beviser ikke | nødvendig | §6 pkt. 7 nøglet afstemning; §8 |
| 5 | MEDIUM | Ikke alle aktive regler kræver persona-identitet (strukturelle familieregler) | rettelse af fakta | §2 |
| 6 | MEDIUM | Publicering er ikke grunden til, at 149b-vejen er lukket; kun eksisterende publiceringsbinding | rettelse af fakta; forenkler 6b | §2; §5 6b genbruger migreringen, hvor den gælder |
| 7 | LOW | En rettelse gør ikke altid en binding ugyldig (`koen`, dato uden ændret `date_raw`) | rettelse af fakta | §2; §6 pkt. 2 måler strukturerede værdier for sig |

Codex bemærkede desuden, at 6b ikke teknisk afhænger af 6a; rækkefølgen er nu markeret som planlægningsvalg (§5).
