# Review 37 — helhedsreview af kodebasen (2026-11-19)

**Grundlag:** main @ `880ab241`, kun trackede filer. Seks uafhængige Fable-reviewere, der kun
læste kode (DB-sikkerhed, DB-korrekthed og -ydelse, web, mobil og packages, Python/R-pipeline,
CI, config og forsyningskæde). Hovedsessionen har selv efterprøvet alle fund med alvor høj og
flere med alvor middel i koden; de er markeret ✔ i tabellerne.

**Ikke gjort:**
- Intet er kørt: ingen tests, builds, DB-forespørgsler eller prod-målinger.
- Live-ACL, Supabase-advisors, bucket-flag, Auth-indstillinger og Vercel-dashboard er ikke
  set. Det kræver projektejerens shell.
- Ingen fund er rettet.

**Baseline:** review 36 (K/P/G/D-fund) og de åbne issues. Kendte punkter gentages kun, hvis
de ikke er reelt lukket.

## 1. Samlet billede

- **Ingen kritiske fund.**
- **Sikkerheden i databasen er i god stand:**
  - Alle 44 tabeller har RLS.
  - Alle 358 SECURITY DEFINER-funktioner har `search_path` i headeren. Det er talt af
    hovedsessionen: 348 i `schema.sql` og 10 i `db-rls.sql`.
  - Alle `red_*` har en rolle-gate.
  - Dynamisk SQL bruger `%I`/`%L`.
  - I den læste kode er der ikke fundet en vej, hvor anon eller medlemmer kan læse levende
    personer.
  - Personsletningen, reimport-writerne og live-ACL'erne er ikke gennemgået (§7).
  - Delvise veje findes for en redaktør, der har været logget ind på samme browser eller enhed
    (W5, M5).

**Anden bølge** (§4b) dækkede personsletningen, den prod-skrivende apply-vej og en
dedikeret ydelsesgennemgang, som var huller i første bølge. Den tilføjer tre høje fund:
- **P1+P2:** en GDPR-sletning kan gøre en levende persons billede offentligt.
- **A1:** fuld genkørsel af `db-migrations.sql` åbner midlertidigt narrativ-gaten.
- **Y1:** kvalitetsarket genberegner hele griddet pr. side.

Y3 er desuden et latent krav, før #130 køres.

**Ydelse er kun vurderet statisk.** Intet er målt med EXPLAIN eller i browseren.
- **Fem fund med alvor høj:**
  - **W1:** redaktionen kan skrive på forkert person efter et hurtigt personskift.
  - **M1:** falske »halvsøskende«.
  - **M2:** »bekræftet« vises trods usikre led.
  - **E1, E2:** to steder kan levende personers data nå en sprogmodel, selvom reglen siger nej.

**Fire gennemgående mønstre:**

1. **Asynkrone kapløb i redaktionen** (W1-W3, W5, mobil K3). Rettelsen i review 36 (K3)
   dækkede kun `loadPerson`. Web har ingen ESLint (`react-hooks`), så fejlklassen fanges ikke
   maskinelt (W10, C5).
2. **PII-værnene sidder kun i den nye evidens-runner.** Ældre skills og scripts
   (præsensliste, hændelser, modelgennemgang, extract-SKILL og geo) har dem ikke (E1, E2,
   E7, E8, E11).
3. **Web og mobil er drevet fra hinanden.** Rettelser i web (K4 `orThrow`, K15 id-parsing,
   generationsvagter) er ikke ført over til mobil (M6, M10).
4. **Forsvar i dybden mangler i databasen og ved hostingen:**
   - Vokabular og datogrænser håndhæves ikke ved skrivning (D5).
   - Synlighedsreglen for billeder hviler kun på RPC-vagten (S4).
   - Der er ingen sikkerheds-headers på Vercel (C3/W13).
   - CI-jobs har ingen timeouts (C1).

## 2. Høj alvor

| id | område | fund | belæg |
|---|---|---|---|
| **W1** ✔ | web | `run()`/`fortrydChangeSet` kalder `loadPerson(recordId)` med den person, der gjaldt, da skrivningen startede. Skifter redaktøren til B, før svaret kommer, indlæses A's evidens under B's navn, og B's svar kasseres via generationstælleren. Næste »Vælg konklusion«, »Slet« eller »Tilføj« sender A's assertion- og fact-id'er. Producerbart i dag: hovedsessionen fandt ingen busy-lås eller overlay, der spærrer personlisten, mens `submitChange` kører. Ikke dækket af `Redaktion.personSkift.test.tsx`. | `web/src/Redaktion.tsx:765`, `:813`, `:649` |
| **M1** ✔ | core | `isHalfThrough` afgør »halv« ved at sammenligne id'et på den anden forælder. Er faderen foldet på tværs af udgaver, mens moderen står som to ulinkede rækker, giver det »halvsøskende« for helsøskende og »halvbrødre« mellem samme persons to rækker. Forekomst i prod er ikke målt (9 karantænegrupper). | `packages/core/src/relationship.ts:107-115`, `collapseSameAs.ts:169-179` |
| **M2** ✔ | core | `uafhaengigeAntal` tæller node-disjunkte stier uden at se på stiernes konfidens. Flere linjer, der alle hviler på samme »formodede« barn-link, vises som »Bekræftet ad N uafhængige linjer«. »En anden, sikker linje« vises også, når den anden linje blot er uangivet. Det bryder invariant 7. | `relationship.ts:310-317, 351, 410`; `mobile/src/app/(tabs)/relate.tsx:26-27`; `web/src/components/RelateView.tsx:145` |
| **E1** ✔ | pipeline, PII | Hændelses-eksporten filtrerer kun på hovedpersonen (`levende=false`). Afdødes 2018-20-biografier, der omtaler levende ægtefæller eller børn, sendes til LLM'en. Evidens-runnerens eligibility (regel 2-4) udelukker netop dem; ifølge `decisions.md:2820` drejer det sig om 13 + 62 + 2 poster. Rammer ved næste kørsel (#130). **Forbehold:** det fremgår ikke entydigt, om regel 2-4 formelt binder dette LLM-pas eller kun evidens-runneren. Det er en beslutning for projektejeren, før #130 køres. | `.claude/skills/daa-haendelser/scripts/export_narratives.R:23-34` |
| **E2** ✔ | pipeline, PII | `daa-presens`-skillen instruerer i at sende `raw_text` fra `work_presens/` (nulevende med navn, fødsel og bopæl) til en LLM, med noten »GDPR/RLS parkeret i PoC«. Det strider direkte mod CLAUDE.md. Validatoren skriver desuden levende personers `date_raw` til stderr. | `.claude/skills/daa-presens/SKILL.md:50-59, 105`; `scripts/validate_presens.py:66-67, 92-94` |

## 3. Middel alvor

### Web
| id | fund | belæg |
|---|---|---|
| W2 | `HistorikPanel` har ingen vagt mod forældede svar og intet `key`: A's historik, og »Fortryd« med A's `changeSetId`, kan vises under B. `loadPerson` nulstiller ikke `sammeSom`. | `web/src/components/HistorikPanel.tsx:23-29`; `Redaktion.tsx:1423, 573` |
| W3 | Slægt/linje-editoren og objekt-medier har ingen generationsvagt. Et forkert udkast kan gemmes på den nu valgte linje. En fejlet hentning ligner »ingen tekst endnu«. | `Redaktion.tsx:544-553, 682, 692, 769` |
| W4 ✔ | Fejlbeskeden i produktionskoden råder til at »køre web/dev-rls.sql i Supabase«. Scriptet laver `using (true)` på person, fact, narrative osv. for anon. Følges rådet i prod, forsvinder gaten for levende personer. | `web/src/Folgesvend.tsx:660`; `web/dev-rls.sql:31` |
| W5 | Kun `media.ts` lytter på `onAuthStateChange`. Ved logout ryddes modellen med redaktørens levende personer ikke, og `loadData` har ingen generationsvagt. | `Folgesvend.tsx:106, 123-127, 430-439` |
| W6 ✔ | `rolleFor` ignorerer `error` og falder tilbage til `'medlem'`. Et forbigående udfald gør redaktøren til medlem resten af sessionen, så rettelser bliver stille til forslag. Rest af K4. | `web/src/data/auth.ts:9-16` |
| W7 | Signerede medie-URL'er (TTL 600 s) fornyes aldrig, så Lightbox giver brudt billede efter 10 minutter. | `web/src/data/media.ts:40` |
| W8 | Lightbox og kortoverlay har ingen `role="dialog"`, ingen fokusstyring og `<span onClick>`-knapper. `MediaThumb` kan ikke nås med tastatur. | `components/Lightbox.tsx:52-70`, `MapLightbox.tsx`, `primitives.tsx:57-63` |
| W9 | E2E kører aldrig i CI. `auth.ts` og kapløbene W1-W3 har ingen tests. | `ci.yml`; `web/e2e/` |
| W10 | Web har ingen ESLint, men har fem `eslint-disable react-hooks/exhaustive-deps`. | `web/package.json` |

### Database
| id | fund | belæg |
|---|---|---|
| D2 ✔ | `red_fortryd_change_set` sammenligner hele den nuværende række med `efter`-snapshot. En kolonne tilføjet efter snapshot (fx `source.sidekort`, `person.staged`) giver altid »nyere ændring rører …«, så gamle sæt kan kun fortrydes med `force`, som slår al divergensbeskyttelse fra. Hovedsessionen har efterprøvet, at ingen af de senere tilføjede kolonner står i `version_pk_registry.skip_cols` (`schema.sql:9053-9088`), og at ingen migration retter `change_event.efter`. Gælder kun sæt fra før den pågældende kolonne blev tilføjet. | `schema.sql:9327-9335, 9541` |
| D1 | `regen_person_visning` udleder slægtsnavn via `person_external_id.linje`. Genimport-writeren sætter kun `record_key`, så personer oprettet gennem evidenskæden får intet efternavn i cachen. Medlemskab via placement læses ikke og udløser ikke regenerering. Prod-effekt ikke målt; beslægtet med #150. | `schema.sql:6436-6439, 4235` |
| D3 | Cachen tager `max()` over afklarede fakta af samme type (alfabetisk største titel), mens `red_upsert_fakta` rammer `LIMIT 1` uden `ORDER BY`. »Ret titel« kan derfor ramme et andet faktum end det viste. | `schema.sql:6444-6447, 6596-6597, 6655` |
| D4 | `red_set_konklusion` genaktiverer ikke en `tilbagetrukket` konklusion. Kaldet melder succes uden synlig effekt. | `schema.sql:6700-6705` |
| D5 | Ingen FK eller CHECK mod `vocab` for `faktatype`, `rolle`, `konfidens`, `status` og `date_qualifier`, og intet tjek af `date_min ≤ date_max` i `red_upsert_fakta`/`red_opret_fakta`/`red_relation`. Polymorf-triggeren validerer kun person og family (invariant 9). | `schema.sql:6581-6684, 7160-7194, 23639-23652` |
| D6 | `db-rollback-foraeldrefamilie.sql` er udløbet (juli-cutover) og har hverken preflight eller flag. Kørt i dag sletter den 922 forældrefamilie-slots og genskaber gamle RPC-versioner. | `db-rollback-foraeldrefamilie.sql:21-104` |
| ~~S1~~ | **Tilbagekaldt af hovedsessionen.** `tm_read` bruger `EXISTS (SELECT … FROM narrative …)`, og den underforespørgsel kører under kalderens egen RLS på `narrative`. Dermed gælder `anon_read`/`auth_read` (publiceringsgaten, `db-rls.sql:486, 587`) allerede, og den gamle regel er kun et ekstra filter. Det er ikke et hul. | `db-rls.sql:1050-1071` |

### Mobil og packages
| id | fund | belæg |
|---|---|---|
| M3 | K8 er ikke reelt lukket. `droppedParentEdges` har ingen forbruger, og vagten dropper stadig kanter på rå årstal i stedet for `foedtSpaend`/`doedSpaend`. | `packages/core/src/buildModel.ts:27-44, 136` |
| M4 | Mobilens `childrenOf` fjerner ikke dubletter på tværs af unioner efter samme_som-fold. Det giver dobbelte børn, dublerede React-nøgler og forkerte trin. Web er ikke ramt. | `mobile/src/data/selectors.ts:19-58` |
| M5 | Mobilen indlæser den offentlige model under redaktørens session og nulstiller den ikke ved logout. Levende og staged personer bliver liggende til genstart. | `mobile/src/store/useStore.ts:180-222, 418-424`; `mobile/src/data/load.ts:91` |
| M6 | Web bruger `orThrow` 17 steder, mobil 0. En netfejl i `fetchPersonEvidence` viser en person uden påstande, så der er risiko for dubletter. | `mobile/src/data/redaktionRead.ts:233-283, 746-766` |
| M7 | Matcheren beregner kun margin pr. A-person. To A-rækker med samme B: den anden bliver `none` og ender som `formodet_ny`. Kun rådgivende. | `packages/core/src/matchUdgaver.ts:232-258` |

### Pipeline
| id | fund | belæg |
|---|---|---|
| E3 ✔ | `run-geo-enrich.R --apply` genberegner crosswalken og overskriver den CSV, mennesket har godkendt (`anvend=TRUE`). Godkendelser læses aldrig og slettes. Rammer #131. | `R/geo-enrich/run-geo-enrich.R:64-67, 74` |
| E4 | `for (id in plan$deletes$id)` over integer64 fjerner klassen, så `DELETE … WHERE id=$1` får det rå double-bitmønster. Sletninger rammer intet eller fejler, mens tælleren melder N. Rammer ved #130-genkørsel. | `.claude/skills/daa-haendelser/scripts/load_haendelser.R:139-140` |
| E5 | `load_presens.R` skriver `person.visning_*` direkte for alle personer med `visning_navn IS NULL` (også gamle, jf. #388), med en anden afledning end `regen_person_visning`. Det bryder invariant 4. | `.claude/skills/daa-presens/scripts/load_presens.R:200-207` |
| E6 | `load_presens.R` har intet `import_key`, intet tjek for eksisterende kilde og ingen dry-run. En genkørsel dublerer alle levende personer. | `load_presens.R:140-142` |
| E7 | `model_gennemgang` har ingen binding til udgave eller eligibility. Kørt med 2018-20-kilden sendes tekst om levende personer til modellen. Latent (operatørfejl). | `.claude/skills/daa-extract/scripts/model_gennemgang_eksport.sql:3, 11`; `model_gennemgang.py:43-48` |
| E8 | `daa-extract/SKILL.md` trin ③/④b instruerer stadig i LLM over `work/posts.json` (2018-20) uden GDPR-forbehold. | `.claude/skills/daa-extract/SKILL.md:84-89, 134-141` |
| E9 | `relation_batch_apply.sql`/`relation_persona_apply.sql` autoriserer med selvberegnet hash (manifest = preview), så der er ingen ekstern forventet hash. `` `cat :manifest_file` `` er uciteret. | `relation_batch_apply.sql:5, 12, 45-47`; `relation_persona_apply.sql:4-5, 40-42` |

### CI, config og forsyningskæde
| id | fund | belæg |
|---|---|---|
| C1 | Ingen `timeout-minutes` i `ci.yml`. En hængende låsetest kører til 360 min (ca. 18 % af månedens minutter). | `.github/workflows/ci.yml` |
| C2 | `web/` og `mobile/` udelukker `**/__tests__/**` i tsconfig, så 109 + 35 testfiler typetjekkes aldrig. Mocks kan glide fra produktionsformen. | `web/tsconfig.json:20`, `mobile/tsconfig.json:20` |
| C3 / W13 | Ingen sikkerheds-headers (CSP, `frame-ancestors`, `nosniff`, `Referrer-Policy`). Målt mod prod: kun HSTS. Redaktørens session ligger i localStorage, så ét XSS-hul giver fuld redaktøradgang. Forsvar i dybden; der er ingen kendt XSS (ingen `dangerouslySetInnerHTML`, og `kilde_url` er begrænset til http(s)). | `web/vercel.json` |
| C4 | CI kan ikke håndhæves (branch protection kræver GitHub Pro) og kører ikke på main. Kendt; procedure-værn mangler. | `ci.yml:19-29` |
| C5 | Playwright og `expo lint` kører aldrig. Web og packages har ingen linter. | `web/package.json:12`, `mobile/package.json:65` |
| C6 | Problemer i `.gitignore` og AI-ignore-filerne:<br>• `.gitignore` lister `work_*`-mapper ved navn, så en ny `work_x/` er ikke ignoreret.<br>• `*.dump`, `*.sql.gz` og `docs/db-backups/` er heller ikke ignoreret.<br>• De tre AI-ignore-filer mangler bl.a. `work_1939_stamtavle/`, `work_2018_saerudgave/`, `tmp/` og `.env*`.<br>• Der er intet `permissions.deny`.<br>• CLAUDE.md siger »hold et dump i repo'et«, mens `fase4-runbook.md:67` siger det modsatte. | `.gitignore:19-38`, `.claudeignore` m.fl. |

## 4. Lav alvor (kort)

**Database**
- **S2:** bogmærke-INSERT tjekker ikke `person_offentlig`, så FK-fejl afslører, om skjulte id'er findes (`db-rls.sql:639-640`).
- **S3:** `family_offentlig` er sand for familier uden medlemmer, så fakta på tomme unioner bliver offentlige (#163) (`db-rls.sql:119-126`).
- **S4:** billed-gaten afhænger af case og retning håndhævet kun i `red_relation`; den bør være en tabel-CHECK (`db-rls.sql:133-146`).
- **S5:** intet assert på `storage.buckets.public=false` for 'media'.
- **S6:** `red_suggest` har ingen størrelses- eller antalsgrænse og ingen vokabular-whitelist.
- **S7:** `search_path` uden `pg_temp` sidst (latent).
- **S8:** anon læser interne kolonner (`story.skabt_af`, `feed_pin.oprettet_af`, `media.original_filnavn`/`storage_path`).
- **S9:** ACL-vagten matcher kun `red\_%`.
- **S10:** rolle-gate efter advisory-lås i `red_apply_reimport_cases`.
- **D7 ✔:** `red_publicer_udgave` åbner intet ændringssæt, så der er ingen historik og intet fortryd (`schema.sql:7828-7850`).
- **D8:** `red_ret_ocr_felt` beregner hele `red_person_grid` pr. rettelse.
- **D9:** fortryd låser assertion → citation → conclusion, mens slette-RPC'erne låser i modsat rækkefølge, så deadlock er mulig.
- **D10:** en ny forældre-påstand på et tilbagetrukket slot giver `omstridt`.
- **D11:** `red_set_koen`/`red_set_privat`/`red_slet_oplysning` giver falsk succes og tomme ændringssæt ved ukendt id.
- **D12:** dybdeloftet i `lineage_descendants` tæller knuder; triggeren dækker ikke DELETE eller `kode`-ændring.

**Web**
- **W11:** `localStorage` uden try/catch (`Folgesvend.tsx:76, 447`).
- **W12:** `bookmarks.list()` returnerer `[]` ved fejl.

**Mobil og packages**
- **M8:** `.in()` med ca. 1.756 id'er i én URL (`mobile/src/data/load.ts:493-496`).
- **M9:** redaktør-token i AsyncStorage.
- **M10:** mobilens skrivelag bruger rå `Number()` på id'er, `opretKilde` sender ikke `p_aar`, og `error.code` tabes.
- **M11:** fold-prognosen bygger på et beskåret grundlag.
- **M12:** ane-par-valg ved ulige afstande; kvadratisk antal BFS-søgninger; `localeCompare` i `tree.ts:216`.
- **M13:** feedets dato for foldede personer.
- **M14:** tests mangler for M1, M2, M4, M7 og M12.

**Pipeline**
- **E10:** prod-skrivere (`load_haendelser.R`, `load_presens.R`, `media-janitor.R`, geo) binder ikke målbasen (ingen forventet project-ref) og har intet sslmode-værn.
- **E11:** geo sender stednavne (også fra præsenslistens bopæle) til Nominatim; en personlig kontakt-e-mail står hardkodet i User-Agent; netfejl caches som »intet resultat«.
- **E12:** `media-janitor` genprøver ikke status i DELETE og downloader alle filer uden sha i rapporttilstand.
- **E13:** gateway-preflight returnerer klientens egne værdier som »serverbevis«.
- **E14:** `splitlines()` på Codex-JSONL deler også på U+2028.

**CI, config og forsyningskæde**
- **C7:** 45 Python-skips; hele `test_build_name_completion_manifest_1939_v50.py` springes over i CI.
- **C8:** Dependabot-alarmer er slået fra, og actions er pinnet til tags (`r-lib/actions@v2`).
- **C9:** Vercel bruger `npm install` i stedet for `npm ci` og har ingen `engines`.
- **C10:** SPA-rewrite giver HTML på `/robots.txt` og manglende assets; ingen robots-politik; ingen immutable cache.
- **C11:** `@testing-library/user-event` er ikke deklareret i web; versionsdrift i vitest, TS, React og supabase-js.
- **C12:** kortet bruger `demotiles.maplibre.org`.
- **C13:** testvagten ser ikke `.mjs`-browsertesten; spike-filer ligger i `tests/sql/`.

## 4b. Anden bølge (samme dag): personsletning, prod-skrivende apply-vej, ydelse

Tre Fable-reviewere, der kun læste kode, med samme regler som første bølge. Intet er kørt eller målt.

### Fuld personsletning (P)
| id | alvor | fund | belæg |
|---|---|---|---|
| **P1+P2** ✔ | **høj** | En GDPR-sletning kan gøre en levende persons billede offentligt. Et portræt, der kun afbilder P, men har egne fakta (rettigheder skrives som fakta på mediet, `schema.sql:8717`), bevares som »S37b«. Kun `afbildet`-relationen slettes. Dermed bliver `media_afbilder_skjult` falsk, og med dokumenterede rettigheder bliver billedet, varianterne og storage-objektet synlige for anon. Det samme sker for delte gruppebilleder og for vielsesfakta i bevarede familier (`family_offentlig` bliver sand). Ingen advarsel i forhåndsvisningen og ingen test. Forekomst i prod ukendt; de ni sletninger den 18/11 var uden medier. | `schema.sql:22586-22601, 22712, 22882`; `db-rls.sql:120-124, 133-146, 229-232` |
| P3 | middel | Kontrollisten skanner ikke `story`, `entity_description` eller andres `assertion.vaerdi_tekst`/`citation.citat_tekst` for P's navn i ren tekst. | `schema.sql:23371-23449, 22969-22994` |
| P4 | middel-lav | Historiklukningen kender kun historiske rækker med person-subjekt. `change_event` for tidligere slettede story- og relationsrækker med familie-subjekt beholder `foer`-teksten. | `schema.sql:22468-22527` |
| P5 | middel | Tabt svar efter commit: klienten kalder aldrig `onDeleted` og kører ikke `executePurgeOprydning`. `PURGE_FINDES_IKKE` vises som rå fejl, og filerne bliver liggende i udbakken. | `web/src/components/SletHeltDialog.tsx:33-58`; `web/src/data/personPurge.ts:53-66, 115-123` |
| P6 | lav-middel | Dialogen viser ikke `storage`, `vielser_staar`, `forældes`, `historik` eller `samme_som_komponent` (spec §2/§6.1), og steder vises som rå koder (»S37b«). | `personPurge.ts:6-14`; `SletHeltDialog.tsx:63-93` |
| P7 | lav (middel ved ægte GDPR-sletning) | Færdigbevis og runbook i git rummer slettede id'er og bogreferencer. Det strider mod spec §1/§5.1 (»ingen linje om, at sletningen fandt sted«). | `docs/superpowers/plans/personsletning/task-13-faerdigbevis.md:19-29`; `docs/runbooks/personsletning-prod.md:52-116` |
| P8 | lav | Fil-oprydningen er aldrig kørt mod rigtig Storage. Kvitteringen sletter udbakkerækken uden at tjekke, at objektet er væk, og buckets ud over `media` kan aldrig kvitteres. | `schema.sql:24065-24071`; `personPurge.ts:38-45` |
| P9 | lav | `set_config('statement_timeout','30s',true)` inde i funktionen påvirker ikke det kald, der allerede kører, så »30 s i alt« findes ikke (jf. 8 s-backlog). | `schema.sql:23814` |
| P10 | lav | Kontrollistens id-søgning matcher årstal og datoer (id < ca. 2100), så ægte navnefund drukner i støj. | `schema.sql:23367-23368, 23450-23453` |

### Prod-skrivende apply-vej og ulæste schema-regioner (A)
Hovedsvar: alle ni element-writere sammenligner payloaden med `authorized_elements`, og `red_finalize_reimport` tæller pr. operation. En apply kan altså ikke skrive andet indhold end det autoriserede.

| id | alvor | fund | belæg |
|---|---|---|---|
| **A1** ✔ | **høj (latent)** | Fuld genkørsel af `db-migrations.sql` mod prod: fra linje 11258 til 15993 svarer `narrative_record_contract_version()` 1. Narrativ-gaten (`IF … <2 THEN RETURN true`) slipper så kladder og tilbagetrukne tekster om offentlige personer igennem til anon, og legacy-writerne genåbnes. Filen er ikke én transaktion (#153 har sin egen BEGIN/COMMIT), så standser kørslen i vinduet, bliver tilstanden stående. Levende personer lækker ikke. Hele filen blev kørt 17/9 (`database-current-state.md:412-416`). | `db-migrations.sql:11258, 15993, 7858`; `schema.sql:16952` |
| A2 | middel | `has_haendelse` indgår i narrativets hashede tilstand. Når `/daa-haendelser` tilføjer eller fjerner en hændelse, forsvinder publicerede tekster lydløst fra personsiden. Grandfathered legacy-tekster har ingen vej tilbage. Rammer ved #130. | `schema.sql:15222, 15541-15545, 17035-17040, 15631-15635` |
| A3 | middel | `ensure_reimport_source_evidence` genbruger en eksisterende `source_record` (ON CONFLICT DO NOTHING) uden efterkontrol, så posten får to helposter (`RECORD_HELPOST_AMBIGUOUS`). | `schema.sql:4119-4126, 871-898` |
| A4 | middel | `LOCK TABLE change_set IN ACCESS EXCLUSIVE MODE` holdes i hele manifest-transaktionen, så redaktørskrivninger står i kø. Legacy-migrering og mutation låser i modsat rækkefølge, så der er risiko for deadlock. | `schema.sql:4302, 15269`; `apply_reimport_helpers.R:263-325` |
| A5 | middel-lav | Legacy-reversal lader batchen stå `finalized`. Genkørsel af samme manifest melder `already_applied`, selvom bindingerne er trukket tilbage. | `schema.sql:4190-4197, 5855-5860, 5520-5586` |
| A6 | middel | `legacy_migrated`-fortrydelse mangler den brede vagt (person + kilde) fra `legacy_withdrawn`. N1 kan vises som »Overgangsdata« ved siden af N2. | `schema.sql:16690-16712` |
| A7 | middel | `red_afgoer_source_persona` henter stikprøverækken `WHERE …='sealed'` uden `ORDER BY` og uden krav om den gældende kandidatkørsel. Efter en opgivet forsegling kan der vælges forkert ark. | `schema.sql:11280-11289` |
| A8 | middel (latent) | Generisk runner: serveren får `manifest_content_sha256` fra manifestet (kun regex-tjekket), og `--preview-sha256` er en fri etiket. Fase A autoriserer sig selv i samme transaktion. C3 genberegner aldrig sine hashes. Samme klasse som E9/E13. | `apply_reimport_helpers.R:28`; `apply_phase_a_1939_v50_helpers.R:287`; `apply_c3_1939_v50_helpers.R:492-498` |
| A9 | middel (latent) | `env_or` falder tilbage pr. variabel. Er `PGDATABASE` sat og `PGHOST` glemt, rammes prod med `sslmode=disable`. De generiske runnere sætter slet ingen sslmode (jf. E10). | `apply_phase_a_1939_v50.R:54-57` m.fl. |
| A10 | lav | Fejler `dbCommit`, kaldes rollback på en død forbindelse. Operatøren ser en almindelig fejl, selvom prod kan være ændret. Der mangler et særskilt udfald for »commit ukendt«. | `apply_reimport_helpers.R:325-327, 438-439` m.fl. |
| A11 | lav | NULL-usikre vagter: `NOT IN`/`<>` på NULL slipper igennem. | `schema.sql:11242, 11273, 5300, 4212, 4225, 14215` |
| A12 | lav (latent) | `reimport_authorization` og `reimport_batch` har ingen mutations-trigger. `narrative_publication_event` og `narrative_record_cutover_receipt` mangler TRUNCATE-trigger. | `schema.sql:3961-3963, 14101, 17490` |
| A13 | lav | Dobbeltdefinitioner i `schema.sql` (3716/3900, 13824/17345, 15478/17438, 6226/17206). Den sidste vinder; de første er døde eller vildledende og er roden til A1. | — |
| A14 | lav (latent) | Case-ledger: `max(id)+1` på identity-kolonnen `narrative.id`, rå 23505 ved genanvendelse af en fortrudt batch, og reversal-autorisationen binder ikke til batchens principal. | `schema.sql:12680-12682, 9172, 12927, 13252-13316` |
| A15 | lav (latent) | 1939-engangsscripts: drift-guard på antal i stedet for id-mængde, preflight uden FOR UPDATE, preview uden REPEATABLE READ, filen læses to gange og `max(id)` bruges som rapporteret id. Alle er gennemført eller spærret af kontrakt v2. | `apply_narrative_replacement_1939_v50_helpers.R:471-475, 661-672` m.fl. |

### Ydelse og effektivitet (Y): statisk vurdering, intet målt
| id | alvor | fund | belæg |
|---|---|---|---|
| **Y1** ✔ | høj (redaktion) | Kvalitetsarket offset-paginerer `red_person_grid` (plpgsql) via `getAll`, så hver side genberegner hele griddet. Det er P2-mønstret, som `getAll` selv forbyder. Genindlæsning af én række henter hele griddet. Alle cirka 1.800 × 20 celler tegnes ved hvert tastetryk. Kompleksitet O(n²/1000). | `web/src/data/personKvalitetsark.ts:166-167`; `Redaktion.tsx:420`; `PersonKvalitetsark.tsx:519` |
| **Y2** ✔ | middel-høj | Opstarten henter alle afklarede relationskonklusioner (med en RLS-kaskade på op til 6 DEFINER-kald pr. række), men bruger kun dem for `samme_som`. Fejl sluges, så dubletpersoner dukker op uden fejlbesked. | `web/src/data/model.ts:87-88` |
| Y3 | høj (latent) | `haendelse`-politikkens `EXISTS narrative` kører hele publiceringsgaten (SHA-256 og subtransaktion) pr. hændelsesrække. Feedet mister stille kort ved anon-grænsen på 3 s, når #130 køres. Bør være færdigkrav for #130. | `db-rls.sql:494-499`; `schema.sql:16922-17050`; `web/src/data/haendelser.ts:44`, `feedGrundlag.ts:34` |
| Y4 | middel | `public_family_sources`/`public_person_facts` joiner `*_current`-views (`DISTINCT ON` over hele tabellen) på en nøgle, der ikke kan skubbes ind. Prisen pr. personside vokser lineært med korpus. Skal bekræftes med EXPLAIN. | `schema.sql:21341, 21356, 21872, 848-852, 1749-1753` |
| Y5 | middel | Fakta, konklusion og påstand joines i browseren med serielle bidder à 200: cirka 36 rundture pr. forsidevisning i dag, cirka 3.600 ved 100×. | `web/src/data/livsdato.ts`; `haendelser.ts:27-33`; `story.ts:49-55`; `presens.ts:38-47` |
| Y6 | middel | RLS-kaskaden på evidenstabellerne giver 2-6 ikke-inlinede DEFINER-kald pr. række, ganget med offset-effekten. Forudsætningen »tabellerne er små« holder ikke ved 50-100×. | `db-rls.sql:505-545, 1050-1070` |
| Y7 | lav-middel | Søgningens stavemådeforslag bygger ordbogen forfra og kører op til tre ekstra fulde `soeg()`. | `web/src/components/SoegView.tsx:44-51`; `soeg.ts:182-203` |
| Y8 | lav-middel | Der mangler et indeks på `interpretation_promotion(target_type, target_id)`. | `schema.sql:1624-1627` |
| Y9 | lav | FK'er uden indeks på `haendelse.fact_id/relation_id`, `story.fact_id/relation_id/historical_event_id` og `bookmark.person_id`. | `schema.sql:6312-6318, 6346-6348, 3524` |
| Y10 | lav | Intet indeks på `fact(faktatype, …)`/`sted_id`. | `schema.sql:6828` |
| Y11 | lav | Regen-triggerne er `FOR EACH ROW`, så skrivning af F konklusioner for samme person giver O(F²). | `schema.sql:6501-6562` |
| Y12 | lav | Reimport-applieren laver én rundtur pr. operation i én åben transaktion. | `apply_reimport_helpers.R:292-322` |
| Y13 | lav | `bn`-CTE'en i `public_person_facts` er O(A×B). | `schema.sql:21899` |

## 5. Kendte, stadig åbne punkter (ikke nye fund)

- `data/extracted-2026-06-18/` (591 filer) er tracket med strukturerede data om 47 levende personer (review 35). Repoet er privat, men data ligger i git-historikken og hos GitHub (jf. C8: en kompromitteret action kan læse dem).
- Fra review 36: K16, D5 (ulåste R-pakker), D6 (»PWA-først« uden manifest), G2 (82 klikbare div/span), P3, P5, P10 og P15.

## 6. Bekræftet rettet fra review 36

- **Database:** K5, K6, P6, P2.
- **Web:** K3-hovedstien, K14, P1, P4, K7 og K4 i `redaktionRead`/`public`.
- **Pipeline:** K1, K2, K10, D3.
- **Packages:** K9, K11, K12, K13.
- **Ikke reelt lukket:**
  - K8 (M3).
  - K4/K15 på mobil (M6, M10).
  - K3's øvrige stier (W1-W3).

## 7. Ikke dækket

Live-tilstand i prod er ikke undersøgt: ACL'er, default privileges, bucket-flag, om selvtilmelding er åben, advisors, kontraktversion og Vercel-indstillinger.

Følgende er ikke gennemgået linje for linje:
- **Database:** fuld personsletning (`schema.sql:21950-24096`), reimport-, fortolknings- og placement-maskineriet, narrative-record-kontrakten og medie-RPC'erne. Desuden `db-verify*.sql` og hovedparten af `db-migrations.sql` (kun stikprøver).
- **Pipeline:** `*_1939_v50`-apply-helperne, ca. 100 SQL-scripts, ark-scripts, `R/tng-qa` og `tools/`.
- **Web:** dele af `web/src` (PersonKvalitetsark, mediaUpload/Merge/Dedup, GeoMap, TreeView, SoegView).
- **Mobil:** de fleste skærme.

Ydelse er ikke målt nogen steder.

Efter anden bølge er stadig ulæst:
- **Database:** `schema.sql` 440-2000 (undtagen 871-1024), 4790-5003, 5345-5417, 2667-2770 og writerne efter linje 17500 (kun stikprøver). Desuden kroppen af den gamle `red_slet_person` og purge-delen af `db-verify.sql`.
- **Pipeline:** ceremoni-`.sql`-scripts og den private runner/apply-wrapper i `~/.private`.

## 8. Forslag til rækkefølge (ikke besluttet)

0. **GDPR-sletning (P1+P2) før næste »Slet helt« af en person med billeder.** Indtil da
   bør sletning af personer med medier undgås.
0b. **Fuld genkørsel af `db-migrations.sql` mod prod må ikke ske** (A1), før de forældede
   kroppe er fjernet, eller der er lagt en vagt ind.
1. **PII-værn og forudsætninger før næste kørsel af #130/#131/præsens** (husk også A2 og Y3 ved #130):
   - E1, E2 og E8 (spær eller gate LLM-trinnene).
   - E3 (geo-godkendelser).
   - E4 (integer64-sletning).
   - E5 og E6 (præsensloaderen).
   - W4 (fjern dev-rls-hintet).
2. **Redaktions-kapløb:** W1-W3 og W5-W6, plus ESLint med react-hooks i web (W10).
3. **Slægtskabsmotoren:** M1, M2 og M3, med tests (M14).
4. **Databasen:**
   - D2 (fortryd ved nye kolonner).
   - D1 og D3 (cache).
   - D5 (vokabular og CHECK, herunder S4).
   - D7 (historik ved udgavepublicering).
   - S2.
   - Arkivér D6.
5. **CI og hosting:**
   - C1 (timeouts).
   - C2 (typetjek af tests).
   - C3 (headers og CSP).
   - C6 (ignore-filer og deny-regler).
   - C8 (Dependabot).
6. **Mobil-paritet** (M4-M6, M10), når mobil nærmer sig prod.
