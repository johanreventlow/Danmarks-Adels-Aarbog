# Trin 6a: 1939's klausuler og kildetekst-revision — design

**Status:** udkast. Skrevet uden afklarende spørgsmål (projektejeren sprang dem over 2026-10-29 og bad om bedste
skøn plus reviews). Mine valg er markeret *mit valg*. Næste: builder-check, Fable-læsning, projektejerens
godkendelse, plan, Codex-runde på spec+plan.
**Gren:** `docs/trin6a-spec` fra `docs/trin6-spec` (`02d3e400`; PR #280 er ikke merget).
**Review-budget (B13):** builder-check (frisk agent) + én Fable-læsning af spec'en (projektejerens ja 2026-10-29;
overskrider budgettet og noteres med én linje i `docs/decisions.md`) + 1 Codex-runde på spec+plan (`gpt-6.1-sol`,
Opus dømmer) + 1 Codex-runde på diffen før prod. Codex' søgekommandoer udelukker `work*/` i selve kommandoen.
**Grundlag:** overordnet spec `2026-10-29-trin6-1939-gennem-kaeden-design.md` (§5 6a, §6 pkt. 4 og 7);
`docs/decisions.md` 2026-10-28 (A6b pkt. 2-3) og 2026-10-27 (B7); målarkitekturen (»Genkørsel, stale beslutninger
og fortrydelse«); omsegmenteringen 2026-09-27 (`clause_revision`). Målt 2026-10-29 på en lokal kopi af prod
(`daa5ab_ddl_standin_20261029100000_5c2`) og på de lokale renditioner, hvis hash er tjekket mod basen. Læst er
kun antal, strukturkoder og tre 1939-poster om personer død før 1780 (§2.2).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, første del. Klausul-leddet for 1939 og den kildetekst-revision, som A6b-resten og
   senere genkørsler skal bruge.
2. **Værdikædeled:** klausuler (1939: »ikke påbegyndt«) og overgangen kildetekst → klausul → fortolkning
   (forældelse). Ingen læserflade ændres.
3. **Leverancetype:** 1939-udgaveprofil (klausulregler og tekstform) samt generelle mekanismer: en fælles regel
   for, hvilken forekomst der er en records helpost, en sideombruds-klassifikation, og kildetekst-revision med
   forældelse. Ingen nye editionsnavngivne permanente overflader.
4. **Værdi:** 6c kan køre runneren på 1939, fordi posterne har klausuler. Redaktøren kan rette en posts
   kildetekst uden at tabe noget i stilhed: afhængige fortolkninger bliver synligt forældede, og bindingerne,
   der falder, står på en liste. Læseren mærker intet i 6a.
5. **Færdigbevis:** §8.
6. **Erstatter:** (a) `clause_revision`'s blanke afvisning af poster med fortolkninger
   (`CLAUSE_REVISION_HAS_INTERPRETATIONS`) som eneste svar på ændret kildetekst. (b) Antagelsen »præcis ét accepteret
   anker pr. record« i klausul-writeren. Samme antagelse i migreringen (6b) og forslags-writeren (6c) skiftes ud
   dér. (c) Den uafklarede B7.
7. **Review-budget:** i hovedet ovenfor.

## 2. Målt udgangspunkt

### 2.1 Postens form i de to udgaver

- **2018-20:** 591 records, alle med ét accepteret anker. Helposten er observationen `person_post`, hvis tekst
  er en *foldet projektion* (`segment.py` samler linjer med ét mellemrum). Kun 97 af 591 har
  `længde = char_to − char_from`. Klausulerne findes (984 i aktuelle sæt).
- **1939:** 592 records og 897 accepterede ankre.
  - 349 records har ét anker. 235 har 2-5 (101 `fact`, 72 `marriage`, 62 `relationship`): helposten (observation
    `person`) plus underforekomster for fakta, ægteskaber og relationer. Alle 305 underforekomster ligger inde i
    deres records `person`-forekomst.
  - De 584 `person`-forekomster overlapper ikke hinanden. Hver har præcis én top-observation. De 8 resterende
    records (6 `structural_context`, 2 `cross_reference`) har ingen `person`-forekomst.
  - Teksten er *rå* (et ordret udsnit af renditionen): 584 af 584 har `længde = spænd`, og 560 indeholder
    linjeskift.
- **Følge:** `clause_write_prepare` afviser 235 af 1939's records (`CLAUSE_EVIDENCE_ANCHOR_AMBIGUOUS`).
  `migrate_legacy_narrative_record` (`LEGACY_MIGRATION_ANCHOR_AMBIGUOUS`) og `write_interpretation_proposal` har
  samme »præcis ét«-krav. 6b's migrering kan altså højst bruges på 349 records, et tal den overordnede spec ikke
  kendte. `build_clause_evidence_manifest` ankrer helposten gennem 2018-20's foldning (`project_rendition`) og kan
  ikke finde en rå 1939-post.

### 2.2 Tør kørsel af segmenteringen på 1939 (lokal, kun antal)

`clause_segment.build_record_ledger` på de 584 helposter:

| Regler | Klausuler | Median/max pr. post | Gap-brud (`\n`) | `non_gap_whitespace` | `unknown_abbreviation` |
|---|---|---|---|---|---|
| 2018-20 v2 uændret | 1.000 | 1 / 8 | 432 poster | 756 | 311 |
| + `\n` i `gap_charset`, `".\n"`, `";\n"` som terminatorer | 1.049 | 1 / 10 | 0 | 0 | 331 |

- Granulariteten svarer til 2018-20's (≈1,7-1,8 klausuler pr. post). 1939's poster er kommaopdelte
  karriereforløb med `;` og `†` som skel. Prøvelæsningen af tre poster om personer død før 1780 bekræfter det.
- Hyppigste ukendte forkortelser: `bgr.`, `dbt.`, `v.`, `imm.`, `bis.`, `smst.`, `virk.`, `afsk.`, `hert.`,
  `afg.`, `kar.`, `Ltnt.`, `Till.` samt ordenstal (`1.`-`11.`) og initialer.
- **Sideombrud:** 77 helposter krydser et sideskift. Markørlinjen `### PAGE n ###` står ordret i helpostens tekst,
  altid efter en blank linje (54 efterfulgt af tekst, 23 af endnu en blank linje). Ingen klummetitel eller
  sidetalslinje følger markøren inde i en post. 7 linjer andetsteds ligner sidestøj (`PAGE_NOISE_1939_RE`), men
  kan være indhold (et årstal på egen linje).
- 641 orddelinger ved linjeskift (`-\n`).

### 2.3 A6b-resten: de 11 posters tilstand (2018-20)

Kildeteksten projiceret med A6b's sidehovedregel (`page_header`) i stedet for v1 (`anywhere`) og sammenlignet
med postspændene:

- 11 af de 12 genfundne linjer ligger **inde i** postens eksisterende forekomstspænd (10 poster: I-9 to gange,
  I-11, I-17, I-18, I-32, I-33, I-44, I-89, III-37 og III-129). Den fysiske afgrænsning er rigtig. Kun den
  foldede tekst er forkert.
- Linjen til **I-84** ligger **uden for** I-84's spænd, mellem I-84 og I-85. Her er selve afgrænsningen forkert.
- Afhængigheder i de aktuelle klausulsæt: 58 fortolkningsnøgler (74 rækker over alle versioner; 16 accepterede),
  16 promotions, hvoraf **9 bindinger er gældende** i dag. Ingen menneskelige klausuldispositioner.
  - I-84 har 0 fortolkninger og et publiceret narrativ. III-129 har 0 fortolkninger og ingen narrativbinding.
    Resten har publicerede narrativer.
  - 4 af posterne har allerede mere end ét klausulsæt (omsegmenteringen 2026-09-28).
- Narrativets publiceringstilstand hasher ankre og forekomstens fingeraftryk, ikke observationens tekst
  (`narrative_publication_state`). Et ankerskifte gør et publiceret narrativ `stale_published`. En ny tekstversion
  på samme observation gør det ikke (skal bevises, §8).

## 3. Afgrænsning

**I 6a:**
- B7 besluttet og håndhævet (§4.1).
- Én fælles regel for helposten (§4.2), brugt af klausul-writeren.
- 1939-klausulregler og en klausul-reimportprofil. Sideombrud som egen klassifikation (§4.3).
- 1939's klausuler skrevet i prod (§7).
- Kildetekst-revision med forældelse, bygget og bevist på en kopi af prod på de 10 poster, men **ikke anvendt i
  prod** (§4.4, overordnet spec §6 pkt. 7).

**Ikke i 6a:**
- Fortolkning af 1939 (6c).
- 6b's og 6c's writere skiftes til helpost-reglen i deres delspecs. Reglen og dens test bygges her.
- Ændring af nogen prod-fortolkning, -binding eller -narrativ.
- Grænserevision (ny forekomst og nyt anker for en eksisterende record) og dermed I-84 (§5).
- Normalisering af 1939-tekst til modelinput (orddeling, sidemarkører): 6c's promptversion.

## 4. Design

### 4.1 B7: tekstform pr. udgave (*mit valg*, som foreslået i den overordnede spec)

- **Profilen deklarerer helpostens tekstform:**
  - `raw`: et ordret udsnit af renditionen (1939).
  - `folded_projection` med navngivet projektionsregel og version (2018-20: `project_rendition@anywhere` for de
    eksisterende tekster, `@page_header` for revisioner).
  - Nøglen ligger både i `extraction-profiles.json` og i klausul-reimportprofilens `writer_config`, så basen kan
    håndhæve den.
- **Manifest-byggeren** vælger ankring efter tekstformen. For `raw` er klausulens renditionsoffset =
  helpostens `char_from` + post-relativt offset, og offsettet hash-verificeres mod renditionen. Foldningen bruges
  ikke.
- **Basen** håndhæver for `raw`, at renditionsoffset = helpostens `char_from` + post-relativt offset, nøjagtigt
  (for `folded_projection` gælder fortsat kun »inde i og monotont«, fordi kortet ikke kan regnes i basen).
- **På tværs af udgaver** sammenlignes kun gennem `narrative_norm_v1`. Ingen tekst genskrives for at få én fælles
  betydning.
- Beslutningen skrives i `docs/decisions.md` (B7 besluttet), når spec'en er godkendt.

### 4.2 Helposten: én regel for alle writere (*mit valg*)

- **Definition:** en records helpost er den ene accepterede forekomst, hvis top-observation har profilens
  helpost-kind (2018-20 `person_post`, 1939 `person`). Alle andre accepterede forekomster for samme record skal
  ligge inde i helpostens spænd.
  - Ingen eller flere kandidater giver `RECORD_HELPOST_AMBIGUOUS`.
  - En underforekomst uden for spændet giver `RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE`.
- Én privat hjælpefunktion bærer reglen. Klausul-writeren bruger den i stedet for sin `count(*) <> 1`. Adfærden for
  2018-20 er uændret (ét anker, `person_post`).
- Helpost-kind'en kommer fra writer-profilen (data). Hvor den gemmes i basen, afgøres i planen.
- **Kontrakt for 6b og 6c:** migreringen og forslags-writeren skifter til samme funktion i deres delspecs. 6a's
  CI-test låser funktionens adfærd på begge former (ét anker; helpost plus underforekomster; underforekomst uden
  for; to kandidater).
- De 8 records uden helpost (6 `structural_context`, 2 `cross_reference`) får ingen klausuler og tælles som
  »ingen helpost« i ledgeren. Det er en synlig disposition, ikke en fejl.

### 4.3 1939's klausulregler og sideombrud

- **Profil `daa-1939-v1` får `clause_rules` `clause-rules-1939-v1`.** Udgangspunkt er 2018-20 v2:
  - `gap_charset` `[" ", "\n"]`.
  - Terminatorerne `". "`, `"; "`, `".\n"`, `";\n"`.
  - Forkortelseslisten bygges i planen ud fra de målte `unknown_abbreviation`-tokens, så intet opfindes.
    Ordenstal og initialer går gennem de eksisterende mønstre.
  - Målet er færre flag end i den tørre kørsel. Det er ikke et krav om nul, for et flag er en ærlig tvivl.
- **Ny klassifikation `page_layout` (*mit valg*):** markørlinjen og de blanke linjer omkring den bliver en
  klausul-række af typen `page_layout`.
  - Alternativet var at lade markøren indgå i mellemrummet mellem klausulerne. Det ville kræve, at writerens
    gap-kontrol fik et regex fra payloaden, og markøren ville ikke stå som en sporbar række. Med en række er
    hvert tegn i helposten fortsat dækket af en klausul eller tilladt whitespace.
  - Ny maskinel disposition `sidelayout`. Står ombruddet midt i en sætning, får begge nabo-klausuler flaget
    `page_break_split`.
  - Kun markørlinjen og blanke linjer ved siden af den klassificeres. De 7 støjlignende linjer andetsteds forbliver
    tekst med flaget `possible_layout_line`. Det er den konservative linje: et årstal må ikke forsvinde.
- **`page_layout` kan aldrig citeres:** `write_interpretation_proposal` afviser en fortolkning, der citerer en
  `page_layout`-klausul. Runnerens eksport og `evidence_contract.py` kender klassifikationen. Vokabular,
  `clause_ledger.py`, manifest-byggerens `PROJECTED_CLASSIFICATIONS` og writerens startdisposition udvides.
- **Klausul-reimportprofil `daa-1939-clause-evidence-v1`** efter 2018-20's mønster:
  - `source_id` 3, rendition `daa-1939-calamari-r6-clean`, tekstform `raw`, helpost-kind `person`.
  - `expected_counts.clause_evidence` = 584.
  - Loaderen (`reimport_profile.py`) må ikke antage kilde 1. Det tjekkes i planen.

### 4.4 Kildetekst-revision med forældelse (generel, *mit valg* af form)

**Formen.** En revision er en ny *tekstversion* af helpostens observation i samme rendition og samme spænd: en
række i `private.source_observation_text`, som findes i DDL'en uden writer. Observationen, forekomsten, ankeret,
mentions og personas står urørt.
- Det passer til det målte: 10 af posterne har rigtig afgrænsning og forkert projektion.
- Ankerformen (ny forekomst plus nyt anker) ville ændre narrativernes tilstandshash og gøre publicerede narrativer
  `stale_published`. Den er forbeholdt grænserevision (§5).
- Hvis en tekstversion fik et andet spænd end forekomsten, ville den påstå en anden afgrænsning, end forekomsten
  gør. Derfor kræver revisionen samme rendition og samme spænd.

**Én operation i reimport-writer-familien.** Navnet afgøres i planen og må ikke være editionsnavngivet. I én
transaktion skal den, bundet af GO og manifest:
1. **Tekstversion:** skriver den nye tekst med proveniens (profil, projektionsregel og -version, kørsel,
   manifest-hash, aktør) og gør den til den foretrukne version. Kolonner, der mangler i den tomme tabel, tilføjes.
   Basisteksten i `source_observation` bevares.
2. **Klausulsæt:** skriver et nyt sæt mod den nye tekstversion. Hver klausul bærer en reference til den
   tekstversion, den er skåret af (`NULL` = basisteksten). `validate_clause_observation`'s ordrette
   delstrengskontrol sker mod netop den tekst. Det gamle sæt får `erstattet`.
3. **Forældelse:** hver fortolkning, der citerer det gamle sæt og hverken er `rejected` eller `superseded`, får en
   ny version med status `superseded` og grundlaget `source_text_revision` (tekstversion før og efter samt
   revisionens id). Det er en ny, udtrykkelig overgang. `red_decide_interpretation` kan kun afgøre fra `proposed`.
   Menneskelige klausuldispositioner på det gamle sæt bevares i audit, mister autoritet og står i kvitteringen.
4. **Ingen tavse tab:** operationen beregner mængden af gældende bindinger (`assertion_binding_current`), der
   falder ud, og afviser, hvis mængden ikke er lig den forventede, nøglede mængde i det autoriserede manifest
   (`..._BINDING_SET_DRIFT`; mængde, ikke antal). Kvitteringen lister pr. binding: promotion, fortolkningsnøgle og
   assertion. 6c's ceremoni genbinder og afstemmer mod netop den liste (overordnet spec §6 pkt. 7).

**Én læser af »gældende helposttekst«.** En privat funktion returnerer den foretrukne tekstversion eller
basisteksten.
- Planen inventerer alle funktioner, views og projektions-SQL, der læser en helposts `verbatim_text` (ikke
  klausulers og ikke mentions). Hver flyttes til funktionen eller begrundes som bevidst bundet til basisteksten.
- Kandidater fra rekognosceringen: `clause_write_prepare`, `clause_write_set`, `validate_clause_observation`,
  `clause_set_sha256`, `write_interpretation_proposal`, `migrate_legacy_narrative_record`,
  `red_source_persona_detail`, runnerens og projektionernes SQL (`clause_evidence_projection.sql`,
  `interpretation_proposal_projection.sql`) og 149b's komparator.
- **Mentions og personas** bevarer deres spænd mod basisteksten. Ingen ny mention eller persona skrives. Planen
  viser, at ingen læser genvaliderer en mention mod den aktuelle tekst.

**`clause_revision` består** for poster uden afhængigheder (ren omsegmentering). Den nye operation bruges, når
kildeteksten ændres.

## 5. I-84 og grænserevision (*mit valg*: parkeret, synligt)

- I-84's manglende linje ligger uden for postens spænd. En rettelse kræver en grænserevision: ny forekomst, nyt
  anker, det gamle afvist. Den rammer narrativets tilstandshash (publiceret → `stale_published`) og alt, der læser
  ankre (placement, narrativlæserne, 21 funktioner i alt).
- Det er en anden og større mekanisme for én post uden fortolkninger, hvis narrativ allerede har linjen (A6b).
- 6a bygger den derfor ikke. I-84 får en synlig disposition: »kildeteksten mangler én linje uden for postens
  afgrænsning; narrativet har den«. Grænserevision henvises til samme spor som opret-benet (B4).
- **Afvigelse fra den overordnede spec:** §4's mål »2018-20's 11 poster får de manglende linjer« bliver 10 i
  trin 6. Det kræver projektejerens ok (§9).

## 6. Følger

- Status efter 6a:
  - 1939's række »Klausuler« bliver `produktionsverificeret`.
  - 2018-20's række er uændret.
  - Revisionsoperationen er `isoleret implementeret` (deployet og ubrugt) med et kopi-bevis.
- 6b's migrering og 6c's forslags-writer kan bruge helpost-reglen. Uden den kan migreringen kun bruges på 349
  records.
- `page_layout` er den første klassifikation, som ingen fortolkning må citere. 6c's prompt får den ikke.

## 7. Prod

1. **To PR'er.**
   - **PR 1 (DB):** helpost-funktionen, klausul-writerens skift, `page_layout`, tekstversions-kolonner,
     klausul↔tekstversion, revisionsoperationen og forældelse, alt i `db-migrations.sql` og `schema.sql`. Dertil
     pg-tests, en opgraderingstest fra prods skema og db-verify.
   - **PR 2 (scripts og profiler):** segmenter, ledger, manifest-bygger, 1939-profilerne og pytest.
   - PR 1 merges først. PR 2 kan merges før ceremoni B, fordi intet script kører mod prod uden GO.
2. **Ceremoni A (DDL, B2-form)** fra projektejerens shell:
   - Privat runner (`maal`, `go`, `dump`, `apply --jeg-mener-det --go`). GO-koden binder commit og filer.
   - Dump med B1-disciplin. Bagefter `NOTIFY pgrst` og `get_advisors`.
   - Blokken er additiv: nye funktioner og kolonner, nyt vokabular, writerne skiftet. Ingen data ændres.
   - Øves på en stand-in med prods 2-minutters grænse. Varigheden noteres.
3. **Ceremoni B (1939's klausuler):**
   - Reimport-writerens kæde (authorize → preflight → apply) med `daa-1939-clause-evidence-v1`. Manifestet er bygget
     lokalt fra renditionen i `work_1939_stamtavle/` (hash tjekket).
   - GO binder manifest-hash og forventet antal (584 poster). Måling før og efter: antal klausuler pr.
     klassifikation og disposition og antal flag. Kun antal, output til fil.
   - **Røgtest før GO:** 20 poster om personer død før 1800 (samme personkreds, som må sendes til en model, §6 pkt.
     6 i den overordnede spec) gennemses for oplagte fejlsnit. Fund justerer reglerne før GO, ikke efter. Ingen
     ark til projektejeren.
4. **Fortrydelse:**
   - Ceremoni B: klausulerne har ingen afhængige, før 6c kører. Fortrydelse er restore af dumpet i det deklarerede
     vindue. Alternativt et nyt sæt via `clause_revision`, hvis kun reglerne var forkerte.
   - Ceremoni A: genindlæsning af de tidligere funktionskroppe fra dumpet. Nye kolonner og tomme rækker kan stå.
5. **Revisionsoperationen anvendes ikke i prod i 6a.** Første brug er 6c's ceremoni.

## 8. Færdigbevis

- **CI (pg):**
  - Helpost-reglen på alle fire former (§4.2). Klausul-writeren på en 1939-lignende fixture med 3 ankre.
  - `raw`-offsetkontrollen afviser et forskudt offset.
  - `page_layout` kan skrives, men ikke citeres.
  - Revisionen:
    - skriver tekstversion, nyt sæt, `erstattet` og `superseded`;
    - afviser ved bindingsmængde-drift, ved andet spænd eller rendition og ved samme tekst (noop);
    - bevarer narrativets tilstandshash.
  - Opgraderingstest fra prods skema.
- **CI (python):** 1939-regler (`\n`-gaps, terminatorer, `page_layout`, `page_break_split`,
  `possible_layout_line`), `raw`-ankring i manifest-byggeren og 2018-20's manifester byte-identiske med før.
- **Stand-in (kopi af prod):**
  - Ceremoni A og B øvet med prods tidsgrænse: 584 poster med klausuler, 8 records talt som »ingen helpost«, 0
    gap-brud.
  - Revisionen kørt på de 10 poster i én transaktion:
    - 58 nøgler forældet (eller det antal, planen måler);
    - den nøglede liste over de 9 bindinger, der falder ud, er lig den forventede;
    - narrativernes `publication_state`-hash er uændret for alle 10;
    - 149b-komparatoren viser ikke længere de 9 bundne poster som afvigende;
    - læserens fakta-RPC viser de 9 fakta som »fra den oprindelige import« (forventet, indtil 6c genbinder).
  - Alt kun som antal og nøgler, output til fil.
- **Prod:** ceremoni A og B med målinger. `status.md`'s 1939-række »Klausuler« hæves med dato.

## 9. Afgørelser

**Til projektejeren:**
1. **I-84 parkeres** (§5), så A6b-resten i trin 6 bliver 10 poster, ikke 11. Anbefaling: ja. Alternativet er at
   bygge grænserevision i 6a eller 6c for én post.

**Mine egne valg (kan rettes):**
- 1939's klausuler i prod allerede i 6a: rækkerne er nye og tilføjes kun, ingen læser påvirkes, og 6c får et
  fast grundlag.
- Tekstversion frem for nyt anker som revisionsform.
- `page_layout` som klausul-række frem for gap-mønster.
- Helpost-reglen i 6a, writerne skiftes i 6b og 6c.
- B7 som deklareret tekstform.
- Røgtesten af segmenteringen foretages af mig, ikke af projektejeren.

## 10. Uden for scope

Grænserevision og I-84 (§5); 6b-6e; normalisering af modelinput; opret-benet (B4); `schema.sql`-generering (B9).

## 11. Reviewlog

(udfyldes)
