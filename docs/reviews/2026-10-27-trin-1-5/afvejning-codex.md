# Opus-afvejning af Codex-fund (1d + 1e, 28 fund)

> To uafhængige Opus-dommere (læse-kun, ren eksport). Dom pr. fund: nødvendig / forenkl / kendt begrænsning / afvis.
> Samlet: nødvendig 4 · forenkl 11 · kendt begrænsning 10 · afvis 3. **Reelt P1 efter afvejning: 0** (Codex: 20 × P1).
>
> **Projektejerens afgørelse ved kontrolpunkt 2 (2026-10-27):** 1b-01 er **P1**, ikke P2. Begrundelsen er
> bevis-aksen, ikke data-aksen. Kernekæden i `evidence-promotion-db` køres på en migreret base
> (`ci.yml:197-233`). Men `writer-1939-v50-db` bygger kun fra `schema.sql` (`ci.yml:305`) og bærer 5b's writer-tests
> (`ci.yml:500-513`: relation-person-create v2/v3, child, ordinal, content-uuid, 2b-ii-ark). De tester altså
> id-kroppe, prod ikke kører. Paritetsvagten dækker kun 13 funktioner (1b-02). Prod-data er ikke i fare.
> 1d.1-05 er en delmængde af 1b-01 og følger den i fase 3. Afvejningens P2 i afsnittet om 1d.1-05 står som Opus'
> oprindelige dom.

---

## Afvejning A — Opus-dom over Codex-fund 1d.1-01…08, 1d.2-01…04, 1d.3a-01…03

Alle stier er relative til EKS. Alle 15 fund er efterprøvet på de citerede linjer. 1d.2-02 er desuden kørt med en
syntetisk tekst gennem den ægte segmenter. Proben kørte uden for EKS, men den lagde 4 `.pyc`-filer i
`.claude/skills/daa-extract/scripts/__pycache__`. Jeg målte dem (alle fire skabt af min kørsel få minutter
forinden, ingen andre filer i mappen) og fjernede netop dem. EKS er uændret.

## 1. Sammendrag

- **Domme:** nødvendig 4 · forenkl 7 · kendt begrænsning 3 · afvis 1.
- **Reelt P1 efter afvejning: 0** (Codex: 11 × P1). Ingen af fundene ændrer prod-data, mens vi taler, eller giver
  et bevis, der ikke beviser. De fleste af Codex' P1'ere er enten projektejerens dokumenterede valg (1d.1-01), latente
  ved den nuværende UI og skala (1d.1-04, 1d.1-06, 1d.2-01), eller procedurekontrolleret (1d.3a-02).
- **Vigtigst at rette:** 1d.3a-03 (op til 13 mulige prosalinjer mangler måske i publiceret tekst; åbent siden
  09-03). Den lander på P2 og ikke P1, fordi mængden er afgrænset og kendt, og fordi lukningen er billig. Den skal
  være en **hård gate før trin 6**, ikke et ønske. Derefter kommer 1d.1-03 (en ægte redigeringsfejl med UI-vej) og
  1d.2-02 (parentesfletningen er reelt død kode, og testfixturen vidner falsk). Codex læser koden rigtigt i 13 af
  15 (ikke 1d.1-01, et bevidst valg, og 1d.1-08, som overså CI's generelle opgraderingssti); det er alvoren og
  forslagenes størrelse, der er for høj.

## 2. Tabel

| id | Codex-alvor | dom | justeret alvor | overlap | efterprøvet |
|---|---|---|---|---|---|
| 1d.1-01 | P1 | afvis | P3 (kun dokumentgæld) | = 1a-08, 1b-06, 1b-12 | ja |
| 1d.1-02 | P1 | forenkl | P3 | = 1a-08, 1b-06 | ja |
| 1d.1-03 | P1 | nødvendig | P2 | ⊃ 1a-08 (1a-08 er ufuldstændig) | ja |
| 1d.1-04 | P1 | forenkl | P3 | supplerer 1b-12 | ja |
| 1d.1-05 | P2 | nødvendig | P2 | = 1b-01 (delmængde), 1b-02 | ja |
| 1d.1-06 | P1 | kendt begrænsning | P3 | — | ja |
| 1d.1-07 | P2 | forenkl | P2 | (1a-07 tilstødende) | ja |
| 1d.1-08 | P2 | kendt begrænsning | P3 | = 1c-13 | ja |
| 1d.2-01 | P1 | forenkl | P3 | — (1c: daa-haendelser »solidt«) | ja |
| 1d.2-02 | P1 | nødvendig | P2 | = 1c-14 (samme sted) | ja + kørt |
| 1d.2-03 | P1 | forenkl | P3 | ~ 1c-01, 1c's »ingen tests« for præsens | ja |
| 1d.2-04 | P2 | kendt begrænsning | P3 | ~ 1a-10 | ja |
| 1d.3a-01 | P1 | forenkl | P3 | (1c-08 tilstødende) | ja |
| 1d.3a-02 | P1 | forenkl | P3 | — | ja |
| 1d.3a-03 | P1 | nødvendig | P2 (hård gate før trin 6) | — | ja |

## 3. Fund for fund

### 1d.1-01 — OCR-rettelse overskriver assertion og skriver `person.koen` · **afvis** · P3
- **Læst:** `schema.sql:2035-2085` (`red_ret_ocr_felt`: `UPDATE assertion` ved navn/dato, `UPDATE person SET koen`
  ved køn, plus en journalrække i `import_korrektion` med `importeret` og `korrigeret`);
  `docs/superpowers/specs/2026-07-26-person-ocr-kvalitetsark-design.md:38-40` og `:51`; `datamodel-oversigt.md:25`;
  `docs/decisions.md:3134-3135`, `:2774-2778`.
- **Begrundelse:** Projektejeren har eksplicit besluttet: »OCR-rettelse er ikke en ny historisk påstand … må derfor
  ikke skabe en konkurrerende assertion eller en ny conclusion« (spec:38-40). Det samme valg står i
  begrebsdefinitionen (spec:51). Den oprindelige værdi er bevaret i journalen (`schema.sql:2074-2075`) og i
  `change_event`. Køn er efter datamodellen »en arbejdsværdi direkte på personen« (`datamodel-oversigt.md:25`), så
  den direkte skrivning er korrekt. Selve fundet er altså forkert læst som fejl. Den reelle rest er, at CLAUDE.md's
  invariant 1 og 4 ikke nævner undtagelserne. Det er allerede 1a-08 og 1b-12 og skal ikke genåbnes her.
- **Mindste rettelse:** ingen i koden. Ret invariantteksten i CLAUDE.md (følger 1a-08/1b-12).

### 1d.1-02 — `red_slet_oplysning` sletter assertion og vælger den ældste · **forenkl** · P3
- **Læst:** `schema.sql:5928-5960` (DELETE af citation og assertion; ved valgt påstand ompeges der til
  `ORDER BY id LIMIT 1`); `schema.sql:5962-5970` (kommentaren til `red_tilbagetraek_fakta` kender selv
  »ældste«-problemet); `docs/decisions.md:3134-3135` (»slet=DELETE bryder invariant #1 … bevidst PoC-valg«);
  `web/src/Redaktion.tsx:1849` (slet-knappen vises på alle oplysninger, også importerede).
- **Begrundelse:** Det er et dokumenteret PoC-valg, og det kan fortrydes via `change_set`/`change_event`. Codex'
  forslag om at modellere tilbagetrækning som auditeret hændelse er et redesign. Det, der gør fundet til mere end
  et »afvis«, er, at UI'et tilbyder sletning af *importerede kildepåstande* (`uforanderlig=true`), og at det er
  her, evidensen kan forsvinde.
- **Mindste rettelse** (samme vagt som 1b-06 foreslår, så de to forslag stemmer overens): én linje, der afviser
  sletning når `uforanderlig` er sand. Redaktørens egne påstande kan fortsat slettes, og »ældste«-ompegningen kan
  blive, fordi den er synlig og kan fortrydes. **Hvornår:** næste gang funktionen røres, senest når trin 6 begynder
  at binde kildepåstande, som en sletning så kunne ramme.

### 1d.1-03 — Redigering af en ikke-valgt oplysning ompeger konklusionen · **nødvendig** · P2
- **Læst:** `schema.sql:5889-5927` og den gældende migrationskrop `db-migrations.sql:4131-4166` (identisk logik).
  `UPDATE … AND valgt_assertion_id=p_assertion_id` finder ingen række, når den redigerede ikke var valgt. Så kører
  `INSERT … ON CONFLICT (target_type,target_id) DO UPDATE SET valgt_assertion_id=v_new`, som ompeger den
  eksisterende konklusion. UI-vejen findes: `web/src/Redaktion.tsx:1848` og `:1859` viser »Redigér« også på
  rækker, der ikke er konklusion, og `web/src/data/redaktionWrite.ts:293-298` sender kaldet.
- **Begrundelse:** Codex har ret, og 1a-08 er ufuldstændig: påstanden tilføjes ganske rigtigt (append), men
  konklusionen skifter stille, tværtimod kodekommentaren (`schema.sql:5915`). Det er en ægte adfærdsfejl i en
  levende redaktørvej. Alvoren er P2 og ikke P1: der er én redaktør, ændringen er synlig med det samme (den
  redigerede række bliver grøn »konklusion«), og den kan fortrydes via `change_set`. `date_certainty` kopieres
  heller ikke (INSERT'en på `:5903-5907`).
- **Tilstødende, samme funktion og samme rettelse (ikke et nyt fund):** ved datofelter sender web
  `p_date_raw = vaerdi` (`redaktionWrite.ts:296`), men `date_min`/`date_max` kopieres fra den gamle påstand. Den nye
  påstands grænser passer derfor ikke til dens rå tekst.
- **Mindste rettelse:** `ON CONFLICT … DO NOTHING` (opret kun en konklusion, hvis der ingen er), kopiér
  `date_certainty`, og nulstil eller genberegn `date_min/max`, når `p_date_raw` er givet. Én SQL-test for valgt og
  ikke-valgt. Rettelsen laves i både `schema.sql` og `db-migrations.sql`. **Hvornår:** før trin 6. Den er lille og
  uafhængig.

### 1d.1-04 — Cachen filtrerer ikke på `conclusion.status` · **forenkl** · P3
- **Læst:** `schema.sql:5604-5693` (`regen_person_visning` joiner conclusion uden statusfilter; triggere på
  conclusion og assertion); `schema.sql:225-236` (`red_person_grid` filtrerer `cn.status='afklaret'` og skriver
  udtrykkeligt, at den undgår `visning_*` af netop denne grund); `schema.sql:5971-5986`, `:7079`, `:7446` (hvem der
  sætter `tilbagetrukket`/`omstridt`); `web/src/data/model.ts:67` (læseren bruger cachen).
- **Begrundelse:** Hullet er reelt og kendt i koden (`schema.sql:236-237`), men latent. Alle veje, der i dag sætter
  en status forskellig fra `afklaret`, rammer faktatyper uden for cachen: »forældre ukendt«-markering, mediefakta og
  forældrefamilie (`Redaktion.tsx:1754`, `:2502`; `schema.sql:7079`, `:7446`). Cachen projicerer kun
  navn/fødsel/død/titel. RPC'en er dog generisk, så en redaktør kan i princippet trække et navnefaktum tilbage via
  API'et. Latent er ikke det samme som harmløst, men hastegraden er lav.
- **Mindste rettelse:** `AND c.status='afklaret'` i `navn_agg` plus én test (tilbagetræk et navn, og så skal cachen
  blive NULL). Codex' forslag om at regenerere »berørte caches« er unødvendigt, så længe ingen cachet faktatype har
  en anden status (sandsynligt, ikke målt i prod). **Hvornår:** sammen med 1d.1-03.

### 1d.1-05 — `max(id)+1` i skemaet mod sekvens i migrationen · **nødvendig** · P2
- **Læst:** `schema.sql:5765-5785` (`max(id)+1` på `fact` og `citation`), `db-migrations.sql:4700-4720` (DEFAULT),
  `.github/workflows/ci.yml:160-171` (et schema-only-job).
- **Begrundelse:** Fundet er en delmængde af 1b-01, som har den fulde opgørelse (17 kroppe, 16 tabeller). Codex
  begrunder det med samtidighed, og det er den svage side: ved én redaktør er racen teoretisk. Den reelle fejl er
  deterministisk (en blanding af eksplicit id og DEFAULT giver duplicate key i en schema-only-base), og
  `schema.sql` er ikke source of truth. Jeg holder P2 mod 1b-01's P1, fordi fejlen er højlydt og prod kører
  migrationskroppene.
- **Mindste rettelse:** som 1b-01: porter RED-8 til `schema.sql`, og udvid paritetsvagten (1b-02). **Hvornår:**
  før trin 6, fordi trin 6's testbaser bygges fra skemaet.

### 1d.1-06 — Placement-promotionen låser ikke · **kendt begrænsning** · P3
- **Læst:** `schema.sql:2985-3063` (`placement_membership_set` og `red_promote_placement_memberships`: preview-hashen
  genberegnes *inde i* skrivefunktionen og sammenlignes; konflikt giver RAISE før skrivning);
  `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md:154` (»kort skrivepausevindue«), `:214-219`
  (Fable D6: forældelse via sha i stedet for vagter, accepteret).
- **Begrundelse:** Kun vinduet inde i én transaktion står tilbage. Det kræver en samtidig placement- eller
  identitetsskrivning midt i en ceremoni, som efter spec'en køres i et skrivepausevindue af den eneste redaktør.
  `membership_is_current` gør desuden en senere ændring synlig som »ikke gældende«. Codex' forslag (låserækkefølge
  plus en toforbindelsestest) er for tungt til skalaen.
- **Mindste rettelse:** ingen. Notér det som kendt begrænsning.

### 1d.1-07 — Ét kildegrundlag pr. medlemskab · **forenkl** · P2
- **Læst:** `schema.sql:2985-3016` (`same_person>1` eller et eksisterende `source_basis` fra en anden placement →
  `conflict`; `:3048-3049` afviser hele promotionen ved én konflikt); spec 5c `:123-131`, `:209-210` (§9: »1939's
  placering (trin 6)« er uden for scope).
- **Begrundelse:** Afgrænsningen er bevidst, og den holder for 5c-1. Men roadmappets trin 6 er netop begge udgaver
  ende-til-ende. Når 1939's placements promoveres for personer, der allerede er medlem via 2018-20, bliver de
  klassificeret som `conflict`, og hele promotionen for kilden stopper. Det er ikke en fejl i dag, men en
  designbeslutning, der skal være truffet, før trin 6 starter. Codex' forslag om at skille medlemskab fra flere
  kildegrundlag (ny tabel og livscyklus) er for tungt.
- **Mindste rettelse:** en beslutningspost i `docs/decisions.md` før trin 6-spec'en. Den nemmeste løsning: et
  eksisterende *gældende* medlemskab fra en anden kilde giver `corroborated` (skrives ikke, tælles og logges) i
  stedet for `conflict`. Spørgsmålet om flere grundlag tages først op, hvis en kilde trækkes tilbage.
  **Hvornår:** gate før trin 6-spec.

### 1d.1-08 — 5c-opgraderingstesten kører ikke i CI · **kendt begrænsning** · P3
- **Læst:** `tests/sql/test-150-upgrade.sh:1-26` (»Kun lokalt«, base = `git merge-base origin/main HEAD`);
  `.github/workflows/ci.yml:323-418` (en generel opgraderingssti fra `2d6aabf` findes i CI).
- **Begrundelse:** Valget er bevidst, og scriptet er et PR-tidsværktøj. Efter merge peger basen på et commit, der
  allerede har featuren (1c-13). CI har en generel opgraderingssti, og 5c-1 er i prod. Med CI-minutbudgettet giver
  det ikke mening at lægge et specifikt upgrade-script i CI. Codex' »fandt ikke et opgraderingsbevis i CI« passer
  kun på det 150-specifikke script.
- **Mindste rettelse:** ingen her. 1c-13's ene parametriserede script er nok, hvis nogen vil rydde op.

### 1d.2-01 — H8-tomt udtræk havner i `clean` og kan slette hændelser · **forenkl** · P3
- **Læst:** `.claude/skills/daa-haendelser/scripts/validate_haendelser.py:157-215` (H8 går til `escalation`, ikke
  `issues`, og rækken lander derfor i `clean` med tom liste); `load_haendelser.R:120-143` (merge, `DELETE` af
  forældreløse); `load_haendelser_helpers.R:103-144` (markerede forældreløse logges som `mistede`);
  `.claude/skills/daa-haendelser/SKILL.md` ③b (»resten fjernes fail-closed fra clean«), ④ (dry-run først);
  `escalate_haendelser.py:35`; `_issues.txt:13` (#130 OPEN: passet er aldrig kørt).
- **Begrundelse:** Mekanikken er rigtig læst. Hullet opstår dog kun, hvis trin ③b springes over. Og selv da gælder
  det et *regenererbart formidlingslag*, hvor kun `feed_status` er varig, og mistede markeringer logges (ikke
  tavst). #130 står åben (»kør hændelses-LLM-passet«), så tabellen er sandsynligvis tom i prod (ikke målt). Det ligger uden for
  genimportprogrammet.
- **Mindste rettelse:** én vagt i loaderen. Hvis den nye mængde for et narrativ er tom, og den gamle indeholder
  markerede rækker, så stop (eller spring narrativet over med en logning). **Hvornår:** når #130 tages op.

### 1d.2-02 — Parentesfletningen fletter aldrig over et layout-span · **nødvendig** · P2
- **Læst:** `.claude/skills/daa-extract/scripts/clause_segment.py:104-230`. Splitpunktet ligger *efter* whitespace
  (`:116-117`), så den foregående klausul altid får et efterfølgende layout-span (`:162-163`). Fletningen kræver, at
  `merged[-1]` ikke er layout (`:183`), og den »opslugning«, der skulle løse det, er en tom `pass` (`:187-190`, =
  1c-14).
- **Kørt** (syntetisk tekst, ægte regler `daa-2018-20-v1` og `-v2`): `Alpha Bravo, f. 1800 (Beta Charlie. Gamma
  Delta) Echo Foxtrot.` giver **2** klausuler, begge flagget. Den eneste fletbare form uden mellemrum
  (`Charlie.Gamma`) splitter slet ikke. Fletningen kan altså reelt ikke nås. Testfixturen `ubalanceret-parentes`
  (`docs/superpowers/plans/2026-09-06-trin4-4-1b-klausul-segmenter.md:229-230`, `tests/fixtures/evidence-clauses.synthetic.json:68-71`)
  giver 1 klausul, men kun fordi `nr. 5.` aldrig splitter. Fixturen vidner falsk om fletningen.
- **Begrundelse:** Det er en reel kontraktfejl i trin 4's segmenter. Flaget `unbalanced_parentheses` holder
  problemet synligt (80 flag i 2018-20, `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md:81`), så
  ingenting er skjult, og den konservative linje er bevaret i den forstand. Derfor P2 og ikke P1.
- **Mindste rettelse:** når `merged[-1]` er layout, `merged[-2]` er en klausul og `open_depth>0`, så fjern
  layout-spannet og udvid `merged[-2]`. Slet den døde blok, og lav en test med Codex' eksempel. **Begrænsning:**
  klausulreglerne er profillåste (regressionsvagter pr. profilversion; 866 klausuler i prod). Rettelsen skal derfor
  være en **ny klausulregel- eller profilversion**, ikke en rettelse på stedet. **Hvornår:** før trin 6, hvor
  1939's klausuler segmenteres.

### 1d.2-03 — Præsensvalidatoren accepterer selvreference og tom liste · **forenkl** · P3
- **Læst:** `.claude/skills/daa-presens/scripts/validate_presens.py:31-90` (S1 tjekker kun, at forælderen findes;
  ingen kontrol for selvreference eller tom liste); `load_presens.R:189-198` (en selvreference giver en familie med
  personen som både partner og barn).
- **Begrundelse:** Det er rigtigt læst, men præsensvejen er legacy og kørt én gang, og 1c-01 anbefaler at fryse
  loaderen helt (den uvagtede `--reset` er det alvorlige problem dér). Er loaderen frosset, har en rettelse i
  validatoren ingen levende vej før trin 6/7.
- **Mindste rettelse:** to linjer, hvis vejen genbruges: `par == who` og `not persons` som brud. **Hvornår:** sammen
  med 1c-01's frysning, eller når præsens flyttes til den generelle writer.

### 1d.2-04 — Stoppet efter fejlet stikprøve håndhæves ikke på tværs af kørsler · **kendt begrænsning** · P3
- **Læst:** `.claude/skills/daa-extract/scripts/control_model.py:1-25` (docstring: »værktøjet håndhæver ikke det«),
  `:36-100`; `docs/decisions.md:749-751`.
- **Begrundelse:** Det er erkendt i koden og givet i opgaven: én projektejer kører alle kontrolkørsler. En
  håndhævelse ville tilføje mere ceremoni til en kontrolmodel, som 1a-10 allerede finder overbygget og med lav
  erklæret bevisværdi. Bemærk også, at stikprøven er deterministisk pr. id (`SEED` fast, `:39`). En ny plan
  trækker derfor stort set den samme stikprøve, og det er værd at vide, men det er ikke et hul.
- **Mindste rettelse:** ingen.

### 1d.3a-01 — `verbatim_text` er den normaliserede projektion · **forenkl** · P3
- **Læst:** `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py` (hele; `:59-77` projektion uden
  PAGE- og NOISE-linjer, `:119-150` `verbatim_text = post.raw_text`, rå offsets og roundtrip-kontrol på `:137-138`);
  `schema.sql:3679-3712` (writeren gemmer offsets og tekst); `docs/decisions.md:1375-1377` (»eksakt delstreng måles i
  en whitespace-normaliseret projektion«, kvitteret 09-03);
  `docs/superpowers/specs/2026-08-21-1939-v50-fase-c0-efterkoersel-design.md:48` (1939's `verbatim_text` er rå OCR);
  `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md:121-122`.
- **Begrundelse:** Projektionen er en dokumenteret afvigelse, og rå tekst kan genskabes præcist
  (`rendition[char_from:char_to]` med låst renditions-sha). Proveniensen er altså ikke brudt, og Codex'
  »evidenshul« er for stærkt. Det reelle problem er, at **samme kolonne betyder to ting** på tværs af udgaverne:
  rå OCR for 1939 og normaliseret med udeladte NOISE-linjer for 2018-20. Her gælder
  `rendition[span] ≠ verbatim_text`. Det bider i trin 6, når begge udgaver læses sammen.
- **Mindste rettelse:** ingen ny kolonne og ingen omskrivning af prod. Skriv semantikken pr. udgave ind i
  trin 6-spec'en og målarkitekturen (evt. som et `text_form`-felt i profilen), og vælg én konvention for nye
  udgaver. **Hvornår:** i trin 6-spec'en.

### 1d.3a-02 — Side og record-nøgle er ikke bundet til spannet · **forenkl** · P3
- **Læst:** `build_source_evidence_manifest.py:94-150`, `:181-195` (`--posts` er en fri inputfil);
  `reimport_profile.py:29-39` (posts er ikke hash-bundet i profilen);
  `docs/superpowers/specs/2026-09-03-2018-20-fase-a-provenance-design.md:48-62` (byte-identitet mod juni-udtrækket og
  mængdelighed mod `external_id` som procedurel gate).
- **Begrundelse:** Det er rigtigt, at builderen stoler på postfilen. For 2018-20 blev input lukket proceduremæssigt
  (byte-identitet og mængdetjek, 149a §4), og den fremadgående søgning (`cursor`, `:129`) bevarer rækkefølgen. Det
  er en manglende gate i et internt værktøj, som er kørt én gang. Den bliver relevant ved genbrug i trin 6/7.
- **Mindste rettelse:** builderen importerer allerede `segment`. Lad den køre segmenteringen på renditionen og
  kræve, at `(linje, nr_label, sider, raw_text)` er lig postfilens. Det er få linjer og ingen ny gate-type.
  **Hvornår:** ved første genbrug (trin 6/7).

### 1d.3a-03 — Mulige prosalinjer fjernes af `NOISE_RE` · **nødvendig** · P2, hård gate før trin 6
- **Læst:** `.claude/skills/daa-extract/scripts/segment.py:40` (`NOISE_RE`), `:202` (linjen springes over midt i en
  post); `docs/superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md:126-172` (100 match midt i poster, 87 på
  afstand 1 fra sidemarkøren, »op til 13 kan være prosa«, og hvis det er tilfældet, er det »et potentielt datatab i
  den eksisterende `narrative.tekst` for source 1«); `docs/evidensbaseret-genimport/legacy-migration-149b-rehearsal.md:184-187`;
  `docs/evidensbaseret-genimport/status.md:248-249` (uændret restpunkt).
- **Begrundelse:** Det er det tungeste af de 15. Er blot én af linjerne prosa, mangler indhold i allerede
  publiceret, læserrettet tekst, og trin 4's klausuler og observationer bygger på den samme tekst. P1-kriteriet
  »risiko for data« er derfor tæt på. Jeg lander på P2, fordi mængden er afgrænset (≤ 13 linjer, kendt position),
  restpunktet er dokumenteret, og lukningen er billig. Men det har stået åbent i otte uger gennem 149b, GO 4 og
  status. Derfor skal det være en **hård gate før trin 6**: trin 6 genbruger segmenteringen, og 1939's egne
  NOISE-regler ville arve den uafklarede praksis.
- **Mindste rettelse:** projektejeren læser de 13 linjer mod kilden (PII, så et menneske og ikke en model) og
  registrerer én disposition pr. linje i én decisions-post. Er nogen af dem prosa: stram `NOISE_RE` til
  sidehovedpositionen (afstand 1 fra `### PAGE`), lav en ny `segment_version`, og ret de berørte narrativer via den
  normale tekstrettelsesvej. Codex' »udeladelser som dækningshændelser fremover« er først nødvendigt, hvis linjerne
  viser sig at være prosa.

## 4. Læst fuldt (21; loft 40)

Hele filer:
1. `f1/_faelles.md` · 2. `f1/_afvejning-brief.md` · 3. `f1/afv-A/brief.md` · 4. `f1/1d-samlet.md` ·
5. `f1/1a/fund-1a.md` · 6. `f1/1b/fund-1b.md` · 7. `f1/1c/fund-1c.md`
8. `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py`
9. `.claude/skills/daa-haendelser/SKILL.md`
10. `tests/sql/test-150-upgrade.sh`

Sektioner (hele funktioner eller afsnit):
11. `schema.sql:2035-2085` (`red_ret_ocr_felt`, skrivedelen) · 12. `schema.sql:5880-5995` (edit/slet/tilbagetræk) ·
13. `schema.sql:5600-5695` (regen og triggere) · 14. `schema.sql:2930-3095` (5c-1-membership) ·
15. `schema.sql:3679-3712` (`ensure_reimport_source_evidence`)
16. `db-migrations.sql:4125-4166` (gældende `red_edit_oplysning`)
17. `.claude/skills/daa-extract/scripts/clause_segment.py:100-230`
18. `.claude/skills/daa-haendelser/scripts/validate_haendelser.py:140-215` og `load_haendelser.R:90-179`
19. `.claude/skills/daa-presens/scripts/validate_presens.py:1-90`
20. `.claude/skills/daa-extract/scripts/control_model.py:1-100`
21. `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md:118-160`, `:200-230`

Udsnit (ikke talt): `schema.sql:225-245`, `:3313-3322`, `:7060-7085`, `:7436-7450`; `db-migrations.sql:368-400`,
`:4700-4720`; `docs/decisions.md:740-760`, `:1366-1385`, `:2768-2780`, `:3128-3138`; OCR-spec `:20-56`;
`datamodel-oversigt.md:20-30`; `web/src/Redaktion.tsx:1830-1875`; `web/src/data/redaktionWrite.ts:285-300`;
`load_haendelser_helpers.R:90-144`; `load_presens.R:175-215`; `segment.py:30-60`, `:140-150`, `:195-210`;
målarkitektur `:112-128`; 149a-spec `:36-90`; C0-efterkørsel `:44-56`; `status.md:242-252`; 149b-rehearsal
`:180-195`; inventering `:121-173`; plan 4.4-1b `:222-234`; 148-rehearsal `:70-90`; `ci.yml:160-175` og grep på
`2d6aabf`.

De vigtigste søgninger: `red_edit_oplysning`/`redigerOplysning` (db-migrations, web, mobile, tests);
`tilbagetrukket`/`omstridt`/`tilbagetraek` (schema, web); `visning_` (web/src/data); `unbalanced_parentheses` (hele
EKS); `NOISE_RE` (docs); `verbatim_text` + `normalis`/`ordret` (specs, decisions); `posts`/`raw_text_sha`
(`reimport_profile.py`); `Kun lokalt` (tests/sql); `2d6aabf`/`upgrade` (ci.yml); `#130` (`_issues.txt`).

Kørt: én syntetisk probe af `clause_segment.segment_clauses` med profilerne `daa-2018-20-v1/v2` (ingen filer fra
`work/`). Bytecode-sideeffekten i EKS er målt og fjernet (se indledningen).

## 5. Hvad jeg ikke nåede

- Intet er kørt mod en database. At ingen cachet faktatype har status ≠ `afklaret` (1d.1-04), er sandsynligt ud fra
  kodevejene, ikke målt i prod.
- Om 1d.1-03's ompegning faktisk er sket i prod (change_events med `red_edit_oplysning` på ikke-valgte påstande), er
  ikke undersøgt.
- 1d.3a-03: de 13 linjers indhold er bevidst ikke læst (PII og opgavens mandat).
- Codex' runde 3b og 3c (1d.3b-*, 1d.3c-*) ligger uden for min liste og er ikke afvejet her.

---

## Afvejning B — Codex-fund 1d.3b, 1d.3c og 1e (13 fund)

Dommer: Opus. Læse-kun, kun i EKS og `f1/`. Ingen DB, ingen kørsel. Stier er relative til EKS.

## 1. Sammendrag

- **Domme:** nødvendig 0 · forenkl 4 (`1d.3b-01`, `1d.3c-01`, `1d.3c-03`, `1e-01`) · kendt begrænsning 7
  (`1d.3b-02`, `1d.3b-03`, `1d.3c-02`, `1d.3c-04`, `1d.3c-05`, `1e-03`, `1e-05`) · afvis 2 (`1e-02`, `1e-04`).
- **Reelt P1 efter afvejning: ingen.** Codex satte 9 af de 13 til P1. Kun ét fund er en reel fejl i en vagt, der
  skal rettes før trin 6: **`1d.3b-01`** (en accepteret, ubundet ægteskabs- eller forældrerelation kan førstebindes
  til en anden familie end den afgjorte). Den bliver P2, fordi der ikke kendes et aktuelt tilfælde, og fordi
  rettelsen er én linje, der kopierer en vagt, børnegrenen allerede har.
- De fleste andre P1'ere gælder skriveveje, der er lukket i prod (`load_daa.R` stopper ved kontrakt v2). Andre er
  ceremonier, der er afsluttet, og hvor hovedbeviset ligger et andet sted end det, Codex læste (`1e-01`). Eller
  også er de bevidste valg, som projektejeren har dokumenteret (`1d.3b-02`, `1e-02`).
- `1d.3c-01` (`post_load_fixup.R`) er den eneste aktive, ikke-gatede prod-skrivevej i listen. Den er P2 og hører
  til 1a-02's »træf én beslutning om de gamle loadere«.

## 2. Oversigt

| id | Codex | dom | justeret | overlap | efterprøvet |
|---|---|---|---|---|---|
| 1d.3b-01 | P1 | forenkl | **P2** (før trin 6) | ≈ 1a-11 (samme udskudte punkt, rest) | ja |
| 1d.3b-02 | P1 | kendt begrænsning | P3 | — | ja |
| 1d.3b-03 | P1 | kendt begrænsning | P3 | lukkes af 3b-01's vagt | ja |
| 1d.3c-01 | P1 | forenkl | P2 | 1a-02 (princip), 1c-01 (princip: ufrosne loadere) | ja |
| 1d.3c-02 | P1 | kendt begrænsning | P3 | — | ja |
| 1d.3c-03 | P1 | forenkl | P3 | — (princip som memory »mængde, ikke antal«) | ja |
| 1d.3c-04 | P1 | kendt begrænsning | P3 | = 1a-02 (samme loader), princip 1c-01 | ja |
| 1d.3c-05 | P1 | kendt begrænsning | P3 | = 1a-02 | ja |
| 1e-01 | P1 | forenkl | P3 | — | ja |
| 1e-02 | P2 | afvis | P3 | — | ja |
| 1e-03 | P2 | kendt begrænsning | P3 | 1c-09 (princip: spring ≠ dækning) | ja |
| 1e-04 | P2 | afvis | P3 | — | delvist (SQL privat) |
| 1e-05 | P2 | kendt begrænsning | P3 | — | ja |

## 3. Fund for fund

### 1d.3b-01 — første binding efter familieskift · forenkl · P2 (ret før trin 6)

**Læst:** `schema.sql:17041-17158` (`relation_binding_state`), `:17406-17503` (`preview_relation_promotions`),
`:17255-17295` (`red_decide_relation_interpretations` gemmer `family_id` i `decision_evidence`, l. 17282-17284),
`:16317-16404` (`red_afgoer_relation_interpretation` gemmer også `family_id` for forælder, l. 16397),
`:17329-17371` (genåbning), `tests/sql/test-relation-binding.sql:907-1000`, decisions #248 (`docs/decisions.md:50-86`)
og spec'en `docs/superpowers/specs/2026-10-26-248-genaabning-ved-familieskift-design.md`.

**Efterprøvet:** Påstanden holder.
- For ægteskab og forælder sammenligner `judged` kun tilstandens familie med den *anmodede*
  (`schema.sql:17475`). Den sammenligner aldrig med `decision_evidence->>'family_id'`.
- `RELATION_PROMOTION_REBIND_FAMILY_CHANGED` kræver en tidligere binding (`:17482`).
- Børnegrenen har derimod netop den vagt: `schema.sql:17053`
  (`(v_rule->>'family_id')::bigint IS DISTINCT FROM (v_i.decision_evidence->>'family_id')::bigint`).
- Genåbning kræver en binding (`:17371`, `RELATION_REOPEN_BINDING_INVALID`). Tabellens `superseded_promotion_id`
  er `NOT NULL` (`:17303`).
- I testen er `g4` »aldrig bundet«. Den prøves kun mod genåbningen (`'ingen_binding'` → `g4`, l. 969). Ingen
  førstebinding af `g4` til den nye familie forsøges.

**Er det #248's hul?** Nej, det er det tilstødende hul, og det står stadig åbent. 2b-i §13 pkt. 1 udskød
»genafgørelse af en accepteret relation, hvis struktur er flyttet« (1a-11). Rute A lukkede kun delmængden
*bundet ægteskab*. Det siger spec'en selv (§2: »er afgjort og bundet«; §7: forælder og barn er uden for scope).
Decisions #248 pkt. 3 fravalgte rute B med begrundelsen: »den gemte afgørelse ville sige den gamle familie, mens
bindingen sagde den nye«. Det er præcis den tilstand, en førstebinding af en ubundet, accepteret relation
skaber i dag. Hullet modsiger altså projektejerens egen begrundelse.

**Kan det ske i prod i dag?** Ifølge dokumenterne er der ikke noget kendt tilfælde:
- #240's 7 ægteskaber blev stående `proposed`, ikke `accepted`.
- #248's to var accepteret og ubundne med vilje i et par timer og blev bundet via rute A
  (`docs/database-current-state.md:547-554`).
- GO 2's dubletægteskab var `proposed`.

Kæden er dog plausibel. En accepteret relation, hvis tilstand bliver NULL (fx en part går `unresolved`), står
accepteret og ubundet. Afgøres identiteten senere til en anden person, peger tilstanden på en anden familie, og
preview binder uden en ny afgørelse. Med 1939's mange navnefæller (rute A-spec §3.3) bliver det mere sandsynligt.
Konsekvensen kan være offentlig: kildeteksten står ved den forkerte familie, som i #248.

**Mindste rettelse:** Én `WHEN`-linje i `judged` for `relation.marriage` og `relation.parent`:
`(c.st#>>'{family,family_id}')::bigint IS DISTINCT FROM (q.decision_evidence->>'family_id')::bigint` →
`RELATION_PROMOTION_DECISION_FAMILY_CHANGED`. Rettelsen er fail-closed, og relationen bliver stående ubundet og
synligt uafsluttet. Hertil en test af rækkefølgen afgørelse → familieskift → førstebinding for både ægteskab og
forælder.

**Hvad der fravælges:** Codex' »eksplicit genafgørelsesvej for ubundne« kræver DDL
(`superseded_promotion_id NOT NULL`). Den bygges først, når et tilfælde opstår, ligesom rute A-spec §7 gør med
forælder.

**Hvorfor P2 og ikke P1:** Der er ingen kendt forekomst, vinduet kræver en bestemt rækkefølge, og rettelsen er
billig. Det er dog en reel adfærdsfejl i en vagt, hvis eneste formål er dette. Den skal derfor være lukket, før
trin 6 begynder at afgøre og rette identiteter i 1939.

### 1d.3b-02 — `flock_digest` håndhæves ikke · kendt begrænsning (bevidst valg) · P3

**Læst:** `schema.sql:16006-16098` (`relation_child_rule`), `:16100-16139` (`decide_relation_child`),
`:17049-17055`, `tests/sql/test-relation-child.sql:153-200` og
`docs/superpowers/specs/2026-10-20-trin5b-2b-iii-boernehenvisninger-design.md` (udsnit).

**Dom:** Adfærden er beskrevet og godkendt af projektejeren:
- spec l. 172: `flock_digest` er »kun et revisionsspor og bruges ikke som drift-vagt«;
- l. 183: »Grenen tjekker reglen, ikke et øjebliksbillede (projektejerens valg 2026-10-20)«;
- l. 187: et barn uden egen post tilføjet ⇒ »bindes den aktuelle flok«;
- l. 191: konsekvensen accepteres.

Testen i l. 170 (»Review Focus 2a«) låser netop den adfærd. Det er altså ikke en fejl.

**Den uheldige del, som Codex rammer:** `relation_binding_state` tjekker kun H-brud (`v_rule->>'ok'`). En *ny*
A-afvigelse, fx `A1_antal_familie` efter et ekstra barn, blokerer derfor ikke bindingen. Det gælder, selv om
afgørelsen gemte de afvigelser, mennesket så (`afvigelser` i evidensen, `schema.sql:16130`).

**Mindste stramning, hvis den ønskes:** I børnegrenen sammenlignes afgørelsens `afvigelser` med de aktuelle, ikke
digesten. Det er ikke nødvendigt ved 12 familier og én redaktør. Tages op, når trin 6 udvider børnehenvisningerne.

### 1d.3b-03 — generisk `red_decide_interpretation` for relationsprædikater · kendt begrænsning · P3

**Læst:** `schema.sql:8722-8783` (ingen prædikatbegrænsning), grants i `:9482-9495`, `:17280-17284` (relationsvejen
kalder selv den generiske RPC), `tests/sql/test-relation-binding.sql:548-575` og grep i
`web/src mobile packages` (ingen klientkald).

**Efterprøvet:** Det er sandt, at en redaktør kan acceptere et ægteskab med `{"note":…}` og derefter binde det.
Preview kræver ikke `method='family-structure-v1'`.

Fire ting trækker ned:
1. Den generiske RPC er det fælles grundlag, som relationsvejene selv bygger på, og den bruges bevidst til
   afvisninger (`docs/decisions.md:334`).
2. Der er én redaktør, og det er projektejeren.
3. Ingen web- eller mobilklient kalder den.
4. Kravet er rollen `redaktion`; anonyme brugere har ingen adgang.

**Vigtigst:** Den vagt, der er foreslået i 3b-01, lukker konsekvensen uden at røre grants. Et generisk accepteret
ægteskab uden `family_id` giver `IS DISTINCT FROM` = sand og kan ikke bindes. Prisen er, at låsetesten
(`test-relation-binding.sql:574`) skal have `family_id` med i evidensen. Kommentaren i l. 557-560 forklarer,
hvorfor testen går uden om relations-RPC'en: den ville ellers hænge på advisory-låsen.

**Hvad der fravælges:** At gøre kernen privat, som Codex foreslår, er unødvendigt.

### 1d.3c-01 — `post_load_fixup.R` med valgfri udgave · forenkl · P2

**Læst:** `.claude/skills/daa-extract/scripts/post_load_fixup.R` (hele) og `schema.sql:141-153`
(`person_external_id`: PK `(person_id, source_id)`; `(source_id, linje, nr)` er ikke unik).

**Efterprøvet:**
- Første argument vælger udgaven (l. 39-44). Opløsningen er fail-closed ved 0 eller 2+ sources, så det er ikke
  »vilkårlig« i den forstand.
- Derefter skrives fem faste Reventlow-linjenavne (l. 69-74), og to grundlægger-`samme_som`-links bygges på faste
  `(linje, nr)` (l. 114-115).
- `pid_of` tager første række (`one()`, l. 28 og 92-93). Backfillens kommentar bekræfter, at 15a/15b deler `nr`
  (`backfill_slaegtled.R:107-110`).
- Der er ingen kontraktport, ingen `--jeg-mener-det`, og login er `~/.Renviron`, dvs. prod.
- Scriptet skriver kanoniske `relation`/`assertion`/`citation`/`conclusion`-rækker direkte (l. 102-110).

**Afbødning:** Scriptet er idempotent for den tilsigtede kilde 2018-20, og dets links findes allerede i prod.
Risikoen ligger i en kørsel mod en anden udgave, fx 1939 i trin 6.

**Dom:** Det er en reel, aktiv skrivevej uden den port, `load_daa.R` har. Den bryder projektets egen regel om, at
prod-scripts skal kræve et flag.

**Mindste rettelse:**
- Tillad kun udgaven `DAA 2018-20`, eller stop ved kontrakt v2 som `load_daa.R:289-297`.
- Kræv `--jeg-mener-det`.
- Lad `pid_of` stoppe ved `count<>1`.

Rettelsen hører til 1a-02's beslutning om de gamle loadere (frys eller pensionér) og skal laves før trin 6.

**Hvad der fravælges:** En ny »versionsbundet apply-vej« er overbygning.

### 1d.3c-02 — backfillens fryse- og idempotensvagt ligger før transaktionen · kendt begrænsning · P3

**Læst:** `.claude/skills/daa-extract/scripts/backfill_slaegtled.R:60-130` og `schema.sql:2894-2905`
(`record_legacy_disposition` låser rækken og gemmer en værdi-hash).

**Efterprøvet:** De to `SELECT count(*)` (l. 82-96) køres før `dbBegin` (l. 98). Rækkefølgen er korrekt
beskrevet.

**Hvorfor det er teoretisk:**
- Kilde 1 er permanent frosset (1167 dispositioner efter 5c-1, runbook `150-placement-prod.md:79-81`).
- Placement-ceremonien kører under en skrivepause.
- Der er én operatør.
- Selv ved et sammenfald vil en ændret legacy-værdi gøre dispositionen forældet, fordi den bærer en værdi-hash
  (`docs/decisions.md:28-30`). Det opdages altså.

**Mindste rettelse, hvis scriptet skal leve videre:** Flyt de to tællinger ind efter `begin_change_set`. En fælles
låsekontrakt er unødvendig.

### 1d.3c-03 — `DATA_DELTA_OK` accepterer enhver ændring i tre tilladte tabeller · forenkl (ved genbrug) · P3

**Læst:** `.claude/skills/daa-extract/scripts/transfer_ddl.py:103-133`,
`references/transfer-5ab-ddl-allowed-data-delta.txt` (hele), `scripts/test_transfer_ddl.py:145-160` og
`docs/runbooks/transfer-5ab-ddl-prod.md:70-85` og `:110-140`.

**Efterprøvet:** En ændret hash accepteres alene på grund af allowlisten, og en forsvundet allowlistet tabel
tælles som `changed` (l. 121-125). Testen l. 157-159 låser det.

**Afvejning:**
- De tre tabeller er små konfigurations- og batch-tabeller, der får `ADD COLUMN`. Hver række ændrer derfor
  nødvendigvis hash, så en hel-tabel-hash kan ikke skelne.
- Plan A er kørt i prod (GO 1, 22/10) med yderligere efterkrav: portabelt katalog, trin 4's digests uændrede og
  rehearsalens `changed=3 new=12`.
- Det er en afsluttet ceremoni.

**Mindste rettelse ved næste genbrug af `transfer_ddl.py`** (sandsynligt i trin 6):
- en forsvundet eksisterende tabel er `DATA_DELTA_UNEXPECTED`;
- rækkeantallet i allowlistede tabeller skal være uændret;
- eventuelt en hash over `to_jsonb(r) - '<ny kolonne>'`.

**Hvad der fravælges:** Codex' »forventet før/efter-indhold pr. tabel« er tungere end nødvendigt.

### 1d.3c-04 — `load_daa.R` nulstiller `levende` globalt · kendt begrænsning · P3

**Læst:** `load_daa.R:281-300` (porten) og `:1037-1053`. Prod-status i `docs/database-current-state.md:265-271`:
kontraktversion 2 siden 2026-09-06.

**Efterprøvet:** `UPDATE person SET levende = FALSE` rammer hele basen, og ukendt fødselsår giver `FALSE`.
Kommentaren kalder det »fail-closed«, men efter invariant 8 er `FALSE` den *mere* åbne synlighed. Det er reelt
fail-open for privatliv.

**Dog:** Porten (`:289-297`) stopper loaderen før skrivning, når versionen ≠ 1. Prod er v2, og alle evidens-RPC'er
kræver v2 (`schema.sql:3608` m.fl.). En nedgradering sker kun via restore.

**Dom:** Ingen aktuel prod-skrivevej. Hører under 1a-02: frys eller pensionér `load_daa.R`, og ret `CLAUDE.md:23`,
der stadig siger »Load går gennem skill'ens `load_daa.R`«. Bliver loaderen nogensinde genåbnet, er dette fund P1.

### 1d.3c-05 — børnematcherens ordenstals-fallback før flertydig partner · kendt begrænsning · P3

**Læst:** `load_helpers.R:360-399` og `load_daa.R:905-925`.

**Efterprøvet:** `if (length(uo) == 1L)` (l. 396) returneres før `if (length(up) > 1L)` (l. 397). Ved flere
partnertræf plus ét ordenstal vælges ordenstallet. Påstanden holder.

**Ærligt forbehold:** 2018-20's eksisterende kanoniske data blev indlæst gennem denne kode. Porten lukker
fremtidige kørsler, men ikke data, der allerede er indlæst. Fundet bliver dog ikke et bevis for fejl i prod-data:
`match_barn_union` kaldes kun ved `multi` (flere ægteskaber), og uopløste tilfælde parkeres ellers.

**Dom:** Som 3c-04, under 1a-02. Rettes kun, hvis loaderen genåbnes. Rettelsen er én omrokering af to linjer.

### 1e-01 — `fase=bundet` kan være grøn med 0 persona-placements · forenkl · P3

**Læst:** `.claude/skills/daa-extract/scripts/fix_150_maal.sql` (hele), `fix_150_placement.sql` (grep-udsnit
l. 80-81, 184-192, 254-263, 321-328) og `docs/runbooks/150-placement-prod.md:55-125`.

**Efterprøvet:** Prædikatet (l. 56-58) kræver `memberships=med_identitet`, og begge kan være 0. Codex' statiske
modeksempel holder. Desuden tæller `memberships` på tværs af alle kilder (l. 35), mens `med_identitet` er pr.
kilde. Det giver en falsk rød, ikke en falsk grøn, når trin 6 tilføjer 1939-memberships.

**Men beviset for fuldstændighed er ikke `maal`.** Det er ceremoniens egne assertions i skrivetransaktionen:
- PRE `FIX150_PRE_MEMBERSHIPS` (l. 184-187): placerede hovedpersoner med accepteret identitet = forventet;
- `FIX150_MID_MEMBERSHIP_PREVIEW` (l. 254-263);
- POST `FIX150_POST_MEMBERSHIPS` (l. 321-328): promoveret = forventet = begge membership-tabeller, og
  `not_current=0`.

Det forventede tal kommer fra `expect.json`, der er forudsagt skrivebeskyttet fra skabelonen (runbook l. 109-115:
`memberships=576`). Prods `FIX150_OK 580/1167/576/530` (oplyst i briefen; EKS' `database-current-state.md` har
endnu ingen 5c-1-post) svarer til den forudsagte `expect.json`.

**Dom:** Fasemålingen er en klassifikator, som runneren bruger som gate mod genkørsel. Den er ikke beviset.
Runbookens l. 69 lover mere, end den leverer.

**Mindste rettelse:** Tilføj `persona_placements>0 AND memberships>0` i prædikatet og filtrér `memberships` på
kilden. Skriv i runbook l. 69, at fuldstændigheden bevises af `FIX150_OK` mod `expect.json`.

**Hvad der fravælges:** Anti-joins i begge retninger er unødvendige.

### 1e-02 — `PLACEMENT_MEMBERSHIP_NOT_CURRENT` er en NOTICE · afvis · P3

**Læst:** `db-verify.sql:10378-10392`, decisions #150 pkt. 5 (`docs/decisions.md:31-34`) og
`fix_150_placement.sql:327`.

**Dom:** Det er bevidst og dokumenteret: »db-verify tæller ikke-gældende som NOTICE«. En identitetsrettelse skal
*lovligt* kunne gøre et membership ikke-gældende (5c-2's læsere filtrerer). Ville verify fejle, var hver
redaktionel rettelse en rød verify.

Hvor det skal være 0, asserter man det allerede: ceremoniens POST (l. 327) og `fix_150_maal.sql:57`
(`ikke_gaeldende=0`). Ingen rettelse.

### 1e-03 — storage-testen springer over uden bucket · kendt begrænsning · P3

**Læst:** `db-verify.sql:7985-8000`, `db-verify-media.sql:383-396`, `tests/sql/run-db-verify-disposable.sql:70-95`,
`tests/sql/evidence-promotion-bootstrap.sql:45-78` og grep i `.github/workflows/ci.yml`.

**Efterprøvet:** Spring ved manglende katalog eller bucket med `NOTICE`, og wrapperen har ingen storage-gate.

**Afgørende:** CI kører `evidence-promotion-bootstrap.sql` før verify i alle PostgreSQL-jobs (`ci.yml:167`, 197, 226,
304, 325, 342, 349, 363, 373, 388). Bootstrap'en opretter `storage.buckets`/`storage.objects` og bucketen `media`
(l. 49-78). Prod har bucketen. Springet rammer altså kun ad hoc-baser uden bootstrap, og #153-rapporten melder det
selv. Storage er desuden uden for trin 1-5.

**Kan tages billigt, hvis det ønskes:** `set_config('daa.verify_storage','executed')` og en advarsel i wrapperen,
samme mønster som de syv dblink-gates. Det er ikke nødvendigt.

### 1e-04 — 2a's tupel-digest dækker kun 210 bindinger · afvis · P3

**Læst:** `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md:28-48` og
`relationspersonas-5b-2b-iii-bevis.md:80-95`.

**Dom:** Allerede håndteret. #244-rapporten (l. 37) forklarer begrænsningen, dækningen (210) og den bredere digest
over gældende bindinger, som dækker de senere. Tilbage er et formuleringsproblem i ældre rapporter:
2b-iii-rapportens tabel (l. 88) viser »2a's tupel-digest uændret« uden mængde.

**Mindste:** Én errata-linje (»dækning: de 210 bindinger fra før 2b-i«) i de rapporter, der citerer den.
Valgfrit. Den private måle-SQL er ikke efterprøvet (læseforbud).

### 1e-05 — 5a's webspor er RPC-paritet, ikke browser ende til ende · kendt begrænsning · P3

**Læst:** `docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md:1-20` og `:88-100`, samt
`relationspersonas-5b-2b-i-bevis.md:130-160`.

**Dom:** Rapporten siger det selv: »Webkøen blev ikke startet mod arbejdsbasen«, payloaden er den, vitest
fastlåser (l. 92-95). »Kort svar« (l. 11) siger også »webkøens RPC«, ikke webkøen. I 2b-i godkendte
projektejeren, at Playwright udelades (l. 137 og 158). Kun formuleringen »virker ende til ende« (l. 10) er bredere
end beviset.

**Mindste:** Ret sætningen. Den første reelle brug af webkøen mod prod er i praksis røgtesten. Serverens vagter
afhænger ikke af klienten.

## 4. Læst fuldt (24 af loftet 40)

1. `f1/_faelles.md`
2. `f1/_afvejning-brief.md`
3. `f1/afv-B/brief.md`
4. `f1/1d-samlet.md:391-618` (runde 3b og 3c)
5. `f1/1e/fund-1e.md`
6. `schema.sql:16006-16141`
7. `schema.sql:16291-16410`
8. `schema.sql:17041-17165`
9. `schema.sql:17195-17564`
10. `schema.sql:8715-8830`
11. `docs/superpowers/specs/2026-10-26-248-genaabning-ved-familieskift-design.md`
12. `docs/decisions.md:1-100`
13. `.claude/skills/daa-extract/scripts/fix_150_maal.sql`
14. `.claude/skills/daa-extract/scripts/post_load_fixup.R`
15. `.claude/skills/daa-extract/scripts/backfill_slaegtled.R:60-130`
16. `.claude/skills/daa-extract/scripts/transfer_ddl.py:95-140`
17. `.claude/skills/daa-extract/references/transfer-5ab-ddl-allowed-data-delta.txt`
18. `docs/runbooks/150-placement-prod.md:55-125`
19. `tests/sql/test-relation-binding.sql:900-1000`
20. `tests/sql/test-relation-child.sql:150-200`
21. `docs/database-current-state.md:540-580`
22. `.claude/skills/daa-extract/scripts/load_helpers.R:360-399`
23. `docs/evidensbaseret-genimport/relationspersonas-5b-2b-i-bevis.md:130-160`
24. `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md:28-48`

**Udsnit (≤ 30 linjer, ikke regnet som fuldt læst):**
- `schema.sql`: 141-153, 1840-1895, 2890-2905, 9480-9500, 9808-9818
- `load_daa.R`: 281-300, 905-925, 1030-1060
- `db-verify.sql`: 7985-8000, 10378-10392
- `db-verify-media.sql:383-396`
- `run-db-verify-disposable.sql:70-95`
- `evidence-promotion-bootstrap.sql:45-80`
- `ci.yml:175-190`
- `test-relation-binding.sql:540-575`
- `test_transfer_ddl.py:145-170`
- `transfer-5ab-ddl-prod.md`: 70-85, 110-140
- `database-current-state.md:252-280`
- `identitetsvej-5a-bevis.md`: 1-20, 88-100
- `relationspersonas-5b-2b-iii-bevis.md:80-95`
- 1a-02, 1a-06, 1a-07, 1a-10, 1a-11, 1b-06, 1b-14 og 1c-01 i Opus-sporenes fundfiler

**Vigtigste grep:**
- `relation.parent`
- `rute A|ubund|første binding|SHEET_UNANSWERED|REBIND_FAMILY_CHANGED` i decisions
- `flock_digest|uden egen post` i 2b-iii-spec'en
- `red_decide_interpretation` i web/mobile/packages og decisions
- `red_promote_interpretation`
- `contract_version|kontraktversion`
- `FIX150_OK|RAISE EXCEPTION|membership` i `fix_150_placement.sql`
- `storage|bucket|evidence-promotion-bootstrap` i CI
- `post_load_fixup`
- `person_external_id`-indekser

## 5. Hvad jeg ikke nåede

- Jeg har ikke kontrolleret, om prod i dag har accepterede, ubundne **forældre**relationer. Dokumenterne nævner
  kun ægteskaber, og jeg har ingen DB.
- Den private runner og målescripts (`~/.private/…`) er uden for læseforbuddet. 1e-04's SQL og 3c-03's øvrige
  ceremonikontroller er derfor kun efterprøvet via runbook og rapport.
- `fix_150_placement.sql` er læst via grep-udsnit, ikke fuldt.
- Jeg har ikke søgt efter, om valget af allowlist frem for forventet efter-hash (3c-03) er begrundet i ICU/libc. Jeg
  fandt intet om det i spec'en eller runbooken.
