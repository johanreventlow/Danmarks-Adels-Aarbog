# Trin 6a: 1939's klausuler og kildetekst-revision — design

**Status:** udkast, revideret efter builder-check og Fable-læsning (§11). Skrevet uden afklarende spørgsmål
(projektejeren sprang dem over 2026-10-29 og bad om bedste skøn plus reviews). Mine valg er markeret *mit valg*.
Én afgørelse venter på projektejeren (§9). Næste: projektejerens godkendelse, plan, Codex-runde på spec+plan.
**Gren:** `docs/trin6a-spec` fra `docs/trin6-spec` (`02d3e400`; PR #280 er ikke merget).
**Review-budget (B13):** builder-check (frisk agent) + én Fable-læsning af spec'en (projektejerens ja 2026-10-29;
overskridelse noteret i `docs/decisions.md`) + 1 Codex-runde på spec+plan (`gpt-6.1-sol`, Opus dømmer) + 1
Codex-runde på diffen før prod. Codex' søgekommandoer udelukker `work*/` i selve kommandoen.
**Grundlag:** overordnet spec `2026-10-29-trin6-1939-gennem-kaeden-design.md` (§5 6a, §6 pkt. 4 og 7);
`docs/decisions.md` 2026-10-28 (A6b pkt. 2-3) og 2026-10-27 (B7); målarkitekturen (»Genkørsel, stale beslutninger
og fortrydelse«); omsegmenteringen 2026-09-27 (`clause_revision`). Målt 2026-10-29 på en lokal kopi af prod
(`daa5ab_ddl_standin_20261029100000_5c2`) og på de lokale renditioner (hash tjekket mod basen). Læst er kun antal,
strukturkoder og tre 1939-poster om personer død før 1780 (§2.2).

## 1. Roadmap-kobling

1. **Roadmapmål:** trin 6, første del: klausul-leddet for 1939 og den kildetekst-revision, som A6b-resten og
   senere genkørsler bruger.
2. **Værdikædeled:** klausuler (1939: »ikke påbegyndt«) og overgangen kildetekst → klausul → fortolkning →
   binding (forældelse og genkørsel). Ingen læserflade ændres.
3. **Leverancetype:** 1939-udgaveprofil (klausulregler, tekstform) og generelle mekanismer: én regel for en
   records helpost, kildetekst-revision med forældelse og genkørselskontrakt. Ingen nye editionsnavngivne
   permanente overflader.
4. **Værdi:** 6c kan køre runneren på 1939, fordi posterne har klausuler. En posts kildetekst kan rettes i en
   GO-bundet ceremoni uden tavse tab: afhængige fortolkninger bliver synligt forældede, hver binding der falder
   ud, står på en nøglet liste, og posten kan fortolkes igen. Der er ingen redaktør-RPC eller webflade; rettelsen
   sker kun som ceremoni. Læseren mærker intet i 6a.
5. **Færdigbevis:** §8.
6. **Erstatter:**
   - (a) `clause_revision`'s blanke afvisning af poster med fortolkninger (`CLAUSE_REVISION_HAS_INTERPRETATIONS`)
     som eneste svar på ændret kildetekst.
   - (b) Antagelsen »præcis ét accepteret anker pr. record« i klausul-writeren og klausuleksporten. Migreringen
     skiftes i 6b, forslags-writeren i 6c.
   - (c) Den uafklarede B7.
7. **Review-budget:** i hovedet ovenfor.

## 2. Målt udgangspunkt

### 2.1 Postens form i de to udgaver

- **2018-20:** 591 records, hver med ét accepteret anker. Helposten er observationen `person_post`. Teksten er en
  *foldet projektion* (`segment.py` samler linjer med ét mellemrum); kun 97 af 591 har
  `længde = char_to − char_from`. 984 klausuler i aktuelle sæt.
- **1939:** 592 records og 897 accepterede ankre.
  - 357 records har ét anker, heraf 8 uden helpost. 235 har 2-5 ankre (101 `fact`, 72 `marriage`,
    62 `relationship`): helposten (observation `person`) plus underforekomster for fakta, ægteskaber og
    relationer. Alle 305 underforekomster ligger inde i helpostens spænd.
  - De 584 `person`-forekomster overlapper ikke, og hver har præcis én top-observation. De 8 records uden helpost
    er 6 `structural_context` og 2 `cross_reference`.
  - Teksten er *rå* (et ordret udsnit af renditionen): 584 af 584 har `længde = spænd`, 560 rummer linjeskift.
- **Følge:**
  - Writerne afviser 235 af 1939's records: `clause_write_prepare` (`CLAUSE_EVIDENCE_ANCHOR_AMBIGUOUS`) og
    `write_interpretation_proposal` (`REIMPORT_WRITER_CLAUSE_FOREIGN_POST`). Klausuleksporten
    (`export_clause_source_texts.R`) giver én række pr. anker og stopper (`EXPORT_RECORD_KEY_NOT_UNIQUE`).
  - `migrate_legacy_narrative_record` lader 357 passere ankertjekket, også de 8 uden helpost. Det er helpost-reglen,
    ikke ankerantallet, der skal afgrænse 6b.
  - `build_clause_evidence_manifest` ankrer gennem 2018-20's foldning og kan ikke finde en rå 1939-post.

### 2.2 Tør kørsel af segmenteringen på 1939 (lokal, kun antal)

`clause_segment.build_record_ledger` på de 584 helposter med 2018-20's gældende regler (`clause-rules-2018-20-v3`):

| Regler | Klausuler | Median/max pr. post | Gap-brud (`\n`) | `non_gap_whitespace` | `unknown_abbreviation` |
|---|---|---|---|---|---|
| v3 uændret | 979 | 1 / 8 | 432 poster | 748 | 303 |
| v3 + `\n` i `gap_charset`, `".\n"` og `";\n"` som terminatorer | 1.027 | 1 / 8 | 0 | 0 | 324 |

- Granulariteten svarer til 2018-20's (≈1,7 klausuler pr. post). 1939's poster er kommaopdelte karriereforløb med
  `;` og `†` som skel. Prøvelæsningen af tre poster om personer død før 1780 bekræfter det.
- De hyppigste ukendte forkortelser er `bgr.`, `dbt.`, `v.`, `imm.`, `bis.`, `smst.`, `virk.`, `afsk.`, `hert.`,
  `afg.`, `kar.`, `Ltnt.` og `Till.`, desuden ordenstal (`1.`-`11.`) og initialer.
- **Sideombrud:**
  - 77 helposter krydser et sideskift. Markørlinjen `### PAGE n ###` står ordret i teksten, altid efter en blank
    linje. 48 af de 77 ombrud står midt i en sætning (ikke efter `.` eller `;`).
  - Uden særregler havner markøren inde i en klausul: en terminator før markøren splitter ikke, fordi næste tegn
    er `#`.
  - Ingen klummetitel eller sidetalslinje følger markøren inde i en post. 7 linjer andetsteds ligner sidestøj, men
    kan være indhold (et årstal på egen linje).
- 641 orddelinger ved linjeskift (`-\n`).

### 2.3 A6b-resten: de 11 posters tilstand (2018-20)

Kildeteksten er projiceret med A6b's sidehovedregel (`page_header`) i stedet for v1 (`anywhere`) og sammenlignet
med postspændene:

- 11 af de 12 genfundne linjer ligger **inde i** postens forekomstspænd: 10 poster (I-9 to gange, I-11, I-17,
  I-18, I-32, I-33, I-44, I-89, III-37, III-129). Afgrænsningen er rigtig; kun den foldede tekst er forkert.
- Linjen til **I-84** ligger **uden for** I-84's spænd, mellem I-84 og I-85. Her er selve afgrænsningen forkert.
- **Afhængigheder i klausulsættene** (ingen menneskelige klausuldispositioner):
  - Fortolkninger: 58 nøgler (74 rækker), 16 `accepted` og 42 `proposed`.
  - **16 gældende bindinger:** 9 `assertion` og 7 `family` (`relation-child-v1` ×2, `relation-marriage-v1` ×3,
    `relation-parent-v1` ×2). Dertil kommer 13 aktuelle parts-rækker (`interpretation_party_current`) og 3
    relations-personas, hvis mention sidder på en klausul.
  - S4-spærren: 9 `interpretation_proposal`-events på posterne.
  - I-84 har 0 fortolkninger og et publiceret narrativ. III-129 har 0 fortolkninger og ingen narrativbinding.
  - 4 poster har allerede mere end ét klausulsæt.
- **Narrativ-hash:** `narrative_publication_state` hasher ankre, forekomster, placements, identiteter,
  revisioner, binding og narrativtekst, men ikke observationens tekst. En ny tekstversion på samme observation
  rører den ikke. Et ankerskifte gør et publiceret narrativ `stale_published`.
- **Komparatoren:** 149b's komparator og `migrate_legacy_narrative_record` sammenligner narrativet med
  *forekomstens* `verbatim_text`, ikke observationens.

## 3. Afgrænsning

**I 6a:**
- B7 (§4.1).
- Helpost-reglen i basen, brugt af klausul-writeren og klausuleksporten (§4.2).
- 1939-klausulregler og klausul-reimportprofil (§4.3), og 1939's klausuler skrevet i prod (§7).
- Kildetekst-revision med forældelse og genkørselskontrakt (§4.4). Den bygges og bevises på en kopi af prod på de
  10 poster, men **anvendes ikke i prod** (overordnet spec §6 pkt. 7).

**Ikke i 6a:**
- Fortolkning af 1939 og selve genkørslen og genbindingen af de 10 poster (6c).
- Migreringens skift til helpost-reglen (6b).
- Ændring af nogen prod-fortolkning, -binding eller -narrativ.
- Grænserevision og dermed I-84 (§5).
- Normalisering af 1939-tekst til modelinput: orddeling og fjernelse af sidemarkører hører til 6c's
  promptversion.

## 4. Design

### 4.1 B7: tekstform pr. udgave (*mit valg*, som foreslået i den overordnede spec)

- **Tekstformen deklareres i profilen:**
  - `raw` (1939): helpostens tekst er et ordret udsnit af renditionen.
  - `folded_projection` (2018-20): en navngiven projektionsregel med version, `project_rendition@anywhere` for de
    eksisterende tekster og `@page_header` for revisioner.
- **Nøglerne er valgfri med default:**
  - Nye nøgler i `writer_config`: `text_form` med default `folded_projection@anywhere` og `helpost_observation_kind`
    med default `person_post`.
  - De skal være valgfri både i basens lukkede nøglesæt (`validate_reimport_writer_config`) og i
    `reimport_profile.py`.
  - 2018-20's profiler røres ikke. Deres `profile_sha256` og manifester er derfor uændrede.
  - Valgfri med default frem for obligatoriske, fordi en obligatorisk nøgle ville ændre hver eksisterende profils
    hash.
- **Manifest-byggeren** ankrer efter tekstformen:
  - For `raw` er klausulens renditionsoffset = helpostens `char_from` + post-relativt offset, hash-verificeret mod
    renditionen.
  - `rendition_projection_sha256` bærer for `raw` renditionens egen hash (identitetsprojektion).
- **Basen** håndhæver for `raw` nøjagtig offset-lighed. For `folded_projection` gælder fortsat »inde i og
  monotont«.
- **På tværs af udgaver** sammenlignes kun gennem `narrative_norm_v1`. Ingen tekst genskrives.
- B7 skrives i `docs/decisions.md`, når spec'en er godkendt.

### 4.2 Helposten: én regel, én definition (*mit valg*)

- **Definition:** en records helpost er den ene accepterede forekomst, hvis top-observation har profilens
  `helpost_observation_kind` (2018-20 `person_post`, 1939 `person`). Alle andre accepterede forekomster for samme
  record skal ligge inde i helpostens spænd.
  - Ingen eller flere kandidater giver `RECORD_HELPOST_AMBIGUOUS`.
  - En underforekomst uden for spændet giver `RECORD_HELPOST_SUBOCCURRENCE_OUTSIDE`.
- **Kun i basen:** reglen bor i én privat funktion. Klausul-writeren og klausuleksporten bruger den. Eksporten
  vælger helposten gennem funktionen og ikke med en R- eller Python-kopi af reglen, så der ikke opstår to
  definitioner.
- **Ledgeren** giver de 8 records uden helpost en synlig linje (»ingen helpost«) i sit summary. De får ingen
  klausuler. Det er en disposition, ikke en fejl.
- **Kontrakt for 6b og 6c:**
  - Migreringen skifter til funktionen i 6b. Det er reglen og ikke ankerantallet, der afgrænser den.
  - Forslags-writeren skifter i 6c.
  - 6a's CI-test låser funktionens adfærd på fire former: ét anker; helpost plus underforekomster; underforekomst
    uden for spændet; to kandidater.

### 4.3 1939's klausulregler

- **Profil:** 1939's extraction-profil får `clause_rules` `clause-rules-1939-v1` med 2018-20's gældende v3 som
  udgangspunkt:
  - `gap_charset` `[" ", "\n"]`.
  - Terminatorerne `". "`, `"; "`, `".\n"`, `";\n"`.
  - Forkortelseslisten bygges i planen ud fra de målte `unknown_abbreviation`-tokens, så intet opfindes.
  - Målet er færre flag end i den tørre kørsel, ikke nul. Et flag er en ærlig tvivl.
- **Sideombrud (*mit valg*, ændret efter Fable fund 6):** sidemarkøren bliver inde i klausulen. Klausulen får
  flaget `page_marker_in_clause` og bevares ordret.
  - Hvorfor ikke en række: en egen `page_layout`-række ville splitte de 48 sætninger, som ombruddet står midt i.
    Det skader 5b's navnesøgning inden for én klausul, og to ordinaler bliver til én sætning.
  - Hvorfor ikke et gap: hvis markøren lå i mellemrummet mellem klausulerne, skulle writerens gap-kontrol have et
    regex fra payloaden.
  - Står ombruddet lige efter en terminator, og begynder teksten efter markøren med versal eller ciffer, splitter
    reglen der (markøren hoppes over ved vurderingen). Markøren ligger så forrest i den næste klausul. Hvert tegn
    er stadig dækket af en klausul eller tilladt whitespace, og der kommer intet nyt vokabular og ingen
    writer-ændring.
  - 6c's normalisering af modelinput fjerner markøren deterministisk. Klausulens verbatim ændres ikke.
- **De 7 støjlignende linjer** forbliver tekst med flaget `possible_layout_line`, så et årstal ikke forsvinder.
- **Klausul-reimportprofil `daa-1939-clause-evidence-v1`** efter 2018-20's mønster:
  - `source_id` 3, rendition `daa-1939-calamari-r6-clean`, `text_form` `raw`, `helpost_observation_kind`
    `person`, `expected_counts.clause_evidence` 584.
  - Loaderen og eksporten må ikke antage kilde 1. Det tjekkes i planen.

### 4.4 Kildetekst-revision med forældelse (generel, *mit valg* af form)

**Formen.** En revision er en ny *tekstversion* af helpostens observation i samme rendition og samme spænd: en
række i `private.source_observation_text`, som findes i DDL'en uden writer. Forekomsten, ankeret, mentions og
personas står urørt.
- Det passer til det målte: 10 poster har rigtig afgrænsning og forkert projektion.
- Ankerformen (ny forekomst plus nyt anker) ville gøre publicerede narrativer `stale_published`. Den hører til
  grænserevision (§5).
- Et andet spænd end forekomstens afvises, for så ville tekstversionen påstå en anden afgrænsning.

**Én operation i reimport-writer-familien.** Navnet afgøres i planen og må ikke være editionsnavngivet.
Operationen tager én record pr. kald. Preflighten beregner afhængighedsmængden for hele batchen i én transaktion,
før noget skrives, og autorisationen binder mængden pr. post. Hvert kald er sit eget statement under prods
grænse på 2 minutter. Inden for én transaktion sker følgende i denne rækkefølge, som triggerne kræver:

1. **Tekstversion:** den nye tekst skrives med proveniens: profil, projektionsregel og version, kørsel,
   manifest-hash og aktør. Manglende kolonner tilføjes som nullable, så db-verify's eksisterende indsættelse
   stadig virker. Versionen gøres foretrukken. Basisteksten i `source_observation` bevares.
2. **Forældelse, mens det gamle sæt stadig er aktuelt:**
   - Hver fortolkning, der citerer sættet og ikke er `rejected` eller `superseded`, får en ny version med status
     `superseded`, grundlaget `source_text_revision` (tekstversion før og efter, revisionens id) og kopierede
     observations-links.
   - Det kræves af to triggere: `interpretation_has_observation` kræver mindst ét link, og links kan kun pege på
     det aktuelle sæt.
   - Overgangen fra `proposed`, `accepted` og `unresolved` er ny og udtrykkelig. `red_decide_interpretation` kan kun
     afgøre fra `proposed`.
3. **Nyt klausulsæt** mod den nye tekstversion:
   - Hver klausul bærer en reference til den tekstversion, den er skåret af (`NULL` = basisteksten).
   - `validate_clause_observation` kontrollerer den ordrette delstreng mod netop den tekst.
4. **`erstattet`** på det gamle sæt, som nu ikke længere er aktuelt.
5. **Ingen tavse tab:**
   - Operationen beregner mængden af gældende bindinger, der falder ud, over *alle* måltyper med hver sit
     gyldighedsprædikat:
     - `assertion`: `assertion_binding_current`;
     - `family`: aktuel version accepteret, og `relation_binding_state`-hashen er lig den gemte, som i
       `public_family_sources`;
     - nye måltyper skal tilføjes her, før revisionen må røre dem.
   - Mængden skal være lig den autoriserede, nøglede mængde (`..._BINDING_SET_DRIFT`; mængde, ikke antal).
   - Kvitteringen lister pr. binding promotion, måltype, fortolkningsnøgle og mål. Den lister også de
     parts-rækker og personas, hvis fortolkninger blev forældet.
   - Personas skrives ikke om. Deres mentions står gyldigt mod den klausultekst, de blev skåret af.
   - 6c's ceremoni genbinder og afstemmer mod netop den liste: 16 bindinger for de 10 poster.
6. **Genkørselskontrakt (lukker Fable fund 4):** S4-spærren (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`)
   åbner for en record, når alle fortolkninger fra dens tidligere forslags-events er `superseded` med grundlaget
   `source_text_revision`. Forslagsnøglen (`interpretation_proposal_key_material`) får en `key_version 2`, der
   indeholder hashen af klausulsættets tekstversion, så en genkørsel med samme ordinal og værdi ikke kolliderer
   med den forældede nøgle. Eksisterende nøgler (version 1) er uændrede. 6a bygger og CI-tester spærrens åbning
   og nøglen. 6c bruger dem.
7. **Fortrydelse:** forældelse kan ikke rulles tilbage (`superseded` er endelig), og tekstversioner tilføjes kun.
   Fortrydelse er restore af dumpet i det deklarerede vindue (B1) eller en fremadrettet revision med en ny version
   af den tidligere tekst. 6c planlægger med det.

**Én læser af »gældende helposttekst«.** En privat funktion returnerer den foretrukne tekstversion eller
basisteksten. Planen inventerer alle læsere af en helposts tekst, både observationens og forekomstens
`verbatim_text` (ikke klausulers og mentions). Hver flyttes til funktionen eller begrundes som bevidst bundet til
basisteksten. Kendte læsere:
- **Klausullaget:** `clause_write_prepare`, `clause_write_set`, `validate_clause_observation` (linje 690-699),
  `clause_set_sha256` og `clause_evidence_projection.sql` (`parent_verbatim_sha256`).
- **Fortolkning og relationer:** `write_interpretation_proposal`, `export_43b_runner_input.R` (`post_text`;
  `evidence_runner.canonical_record_input` og `check_clauses_within_post` kræver klausulerne som delstrenge af
  netop den tekst) og `private.relation_persona_v3_input` (`post_text`).
- **Narrativ og visning:** `migrate_legacy_narrative_record` og 149b's komparator
  (`export_legacy_migration_candidates_helpers.R`, `build_legacy_migration_manifest.py`; læser forekomstens tekst)
  samt `red_source_persona_detail`.

**`clause_revision` består** for poster uden afhængigheder (ren omsegmentering). Den nye operation bruges, når
kildeteksten ændres.

## 5. I-84 og grænserevision (*mit valg*: parkeret, synligt)

- I-84's manglende linje ligger uden for postens spænd. En rettelse kræver en grænserevision: ny forekomst, nyt
  anker, det gamle afvist. Den rammer narrativets tilstandshash (publiceret → `stale_published`) og alle 21
  funktioner, der læser ankre (placement, narrativlæserne m.fl.).
- Det er en anden og større mekanisme for én post uden fortolkninger, hvis narrativ allerede har linjen (A6b).
  6a bygger den ikke.
- I-84 får en synlig disposition: »kildeteksten mangler én linje uden for postens afgrænsning; narrativet har
  den«. Grænserevision henvises til samme spor som opret-benet (B4).
- **Afvigelse fra den overordnede spec:** §4's mål »2018-20's 11 poster får de manglende linjer« bliver 10 i
  trin 6. Det kræver projektejerens ok (§9).

## 6. Følger

- Status efter 6a:
  - 1939's række »Klausuler« bliver `produktionsverificeret`.
  - Revisionsoperationen og genkørselskontrakten er `isoleret implementeret` (deployet og ubrugt) med et kopi-bevis.
- 6b's migrering og 6c's forslags-writer skal bruge helpost-reglen.
- 6c's normalisering fjerner sidemarkører og orddelinger fra modelinput.
- 6c's afstemning omfatter 16 bindinger (9 assertion og 7 family) og de 13 parts-rækker. Genbrug af de 3
  relations-personas følger 5b's regler.

## 7. Prod

1. **To PR'er.**
   - **PR 1 (DB):** helpost-funktionen; klausul-writerens og eksportens skift; valgfri profilnøgler og
     `raw`-kontrollen; tekstversions-kolonner og klausul↔tekstversion; revisionsoperationen med forældelse og
     drifttjek; S4-åbningen og `key_version 2`. Alt i `db-migrations.sql` og `schema.sql` med pg-tests, en
     opgraderingstest fra prods skema og db-verify.
   - **PR 2 (scripts og profiler):** segmenter, ledger, manifest-bygger, eksport, 1939-profilerne og pytest.
   - PR 1 merges først. PR 2 kan merges før ceremoni B, fordi intet script kører mod prod uden GO.
2. **Ceremoni A (DDL, B2-form)** fra projektejerens shell:
   - Privat runner (`maal`, `go`, `dump`, `apply --jeg-mener-det --go`). GO-koden binder commit og filer.
   - Dump med B1-disciplin. Bagefter `NOTIFY pgrst` og `get_advisors`.
   - Blokken er additiv: nye funktioner og kolonner, writerne skiftet, ingen data ændret.
   - Øves på en stand-in med prods 2-minutters grænse. Varigheden noteres, og forholdet mellem prod og stand-in
     måles før en varighed bruges som bevis.
3. **Ceremoni B (1939's klausuler):**
   - Reimport-writerens kæde (authorize → preflight → apply, ét kald pr. post) med `daa-1939-clause-evidence-v1`.
   - Manifestet bygges lokalt fra renditionen i `work_1939_stamtavle/` (hash tjekket). GO binder manifest-hash og
     antal (584 poster).
   - Måling før og efter: klausuler pr. klassifikation og disposition samt flag. Kun antal, output til fil.
   - **Røgtest før GO:** 20 poster om personer død før 1800 (den personkreds, der må sendes til en model, jf.
     overordnet spec §6 pkt. 6) gennemses af mig for oplagte fejlsnit. Fund justerer reglerne før GO. Intet ark
     til projektejeren.
4. **Fortrydelse:**
   - Ceremoni B: klausulerne har ingen afhængige, før 6c kører, så restore af dumpet i det deklarerede vindue.
     Alternativt et nyt sæt via `clause_revision`, hvis kun reglerne var forkerte.
   - Ceremoni A: de tidligere funktionskroppe fra dumpet. Nye kolonner kan stå.
5. **Revisionsoperationen anvendes ikke i prod i 6a.** Første brug er 6c's ceremoni.

## 8. Færdigbevis

- **CI (pg):**
  - Helpost-reglen på fire former. Klausul-writeren på en 1939-lignende fixture med tre ankre.
  - `raw`-offsetkontrollen afviser et forskudt offset. 2018-20's profiler validerer uændret med defaults.
  - **Revisionen:**
    - skriver tekstversion, `superseded` med kopierede links, nyt sæt og `erstattet` i den krævede rækkefølge;
    - afviser ved drift i bindingsmængden for assertion og for family, hver for sig;
    - afviser ved andet spænd eller anden rendition og ved samme tekst (noop);
    - bevarer narrativets tilstandshash.
  - **Genkørsel:** efter en revision accepteres et nyt forslag for posten med `key_version 2` og samme ordinal og
    værdi, mens et forslag på en ikke-revideret post stadig spærres af S4.
  - Opgraderingstest fra prods skema.
- **CI (python/R):**
  - 1939-regler: `\n`-gaps, terminatorer, `page_marker_in_clause`, split efter en terminator over markøren,
    `possible_layout_line`.
  - `raw`-ankring i manifest-byggeren. Eksporten vælger helposten via basens funktion.
  - 2018-20's manifester er byte-identiske med før.
- **Stand-in (kopi af prod):**
  - Ceremoni A og B øvet med prods tidsgrænse: 584 poster med klausuler, 8 records talt som »ingen helpost«, 0
    gap-brud.
  - Revisionen kørt på de 10 poster:
    - de 58 nøgler forældet (eller det antal, planen måler);
    - den nøglede liste over 16 bindinger (9 assertion, 7 family) er lig den forventede;
    - narrativernes `publication_state`-hash er uændret for alle 10;
    - læserens fakta-RPC viser de 9 fakta som »fra den oprindelige import«, og `public_family_sources` mister de
      7 (forventet, indtil 6c genbinder);
    - komparatoren gennem den gældende helposttekst viser ikke de 9 bundne poster som afvigende. Kravet gælder
      kun, hvis planens inventering flytter komparatoren til funktionen; ellers udgår punktet med begrundelse.
  - Kun antal og nøgler, output til fil.
- **Prod:** ceremoni A og B med målinger. `status.md`'s 1939-række »Klausuler« hæves med dato.

## 9. Afgørelser

**Til projektejeren:**
1. **I-84 parkeres** (§5), så A6b-resten i trin 6 bliver 10 poster, ikke 11. Anbefaling: ja. Alternativet er at
   bygge grænserevision i 6a eller 6c for én post.

**Mine egne valg (kan rettes):**
- 1939's klausuler i prod allerede i 6a: rækkerne er nye og tilføjes kun, ingen læser påvirkes, og 6c får et
  fast grundlag.
- Tekstversion frem for nyt anker som revisionsform.
- Sidemarkøren inde i klausulen med flag frem for en egen række eller et gap-mønster.
- 2018-20 v3 som udgangspunkt for 1939's regler.
- Helpost-reglen kun i basen. Eksporten og klausul-writeren skifter i 6a, migreringen i 6b og forslags-writeren
  i 6c.
- Valgfri profilnøgler med default, så 2018-20's hashes står.
- S4-åbning og `key_version 2` som genkørselskontrakt frem for at genåbne forældede nøgler.
- Ingen redaktør-RPC: kildetekst rettes kun ved ceremoni.
- Røgtesten af segmenteringen foretages af mig.

## 10. Uden for scope

Grænserevision og I-84 (§5); genkørslen og genbindingen selv (6c); 6b-6e; normalisering af modelinput (6c);
opret-benet (B4); `schema.sql`-generering (B9); `transfer_*`-scripts' kendskab til `source_observation_text`
(relevant først i 6c).

## 11. Reviewlog

**Builder-check 2026-10-29 (frisk agent, Opus):** fire spørgsmål.
1. Afhængigheder ud over fakta-bindinger → målt: 7 familiebindinger, 13 parts-rækker, 3 personas (§2.3, §4.4
   pkt. 5).
2. I-84 → projektejerens afgørelse (§9).
3. Redaktør-RPC eller ceremoni → kun ceremoni (§1.4).
4. v2 eller v3 → v3; den tørre kørsel er gentaget (§2.2).

**Fable-læsning 2026-10-29 (adversarial, læse-kun mod kode og stand-in): GO med rettelser**, 12 fund. Alle
målepåstande i §2 bekræftet undtagen de nedenfor rettede.

| # | Alvor | Fund | Afvejning (Opus) | Indarbejdet |
|---|---|---|---|---|
| 1 | P1 | 7 familiebindinger falder ud i stilhed; drifttjekket dækkede kun assertions | nødvendig (målt igen) | §2.3, §4.4 pkt. 5, §6, §8 |
| 2 | P2 | Komparatoren læser forekomstens tekst; §8-beviset uopnåeligt | nødvendig | §2.3; inventeringen omfatter forekomstlæsere; §8-punktet betinget |
| 3 | P2 | Rækkefølgen tekst → sæt → forældelse fejler mod triggerne | nødvendig (verificeret, linje 1887, 15478ff.) | §4.4 pkt. 1-4 |
| 4 | P2 | 6c kan ikke genkøre: S4-spærren og en nøgle uden tekst-hash | nødvendig (verificeret, linje 4409, 4515) | §4.4 pkt. 6, §8 |
| 5 | P2 | Eksport og ledger har deres egen helpost-definition | nødvendig | §2.1, §4.2 |
| 6 | P2 | `page_layout` splitter 48 sætninger | nødvendig; mit valg vendt | §2.2, §4.3 |
| 7 | P2 | `writer_config` er et lukket nøglesæt; nye nøgler ændrer hashes | nødvendig | §4.1 |
| 8 | P3 | Fortrydelse af revisionen udesignet | nødvendig | §4.4 pkt. 7 |
| 9 | P3 | Inventeringen mangler navne | nødvendig | §4.4 |
| 10 | P3 | 357, ikke 349 records med ét anker | rettelse af fakta | §2.1 |
| 11 | P3 | Granularitet og 2-minutters grænsen | nødvendig | §4.4, §7 pkt. 2 |
| 12 | P3 | Små klassifikations- og vokabularsteder | til planen; delvis bortfaldet (ingen `page_layout`) | planen |
