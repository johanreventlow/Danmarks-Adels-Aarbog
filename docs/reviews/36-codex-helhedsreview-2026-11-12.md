# Helhedsreview af DAA-kodebasen

Gennemført 12. november 2026 på commit `2ac193a9d0f8dae79b83c7c8ae0aef6691a78562`, fra separat worktree `/Users/johanreventlow/.codex/worktrees/ba1a/danmarksadelsaarbog`.

**Samlet vurdering:** Kodebasen har et brugbart fundament: fælles domænepakker, rene funktioner, provenance og mange målrettede tests. Den væsentligste gæld ligger ved sammensætningen af disse dele: asynkrone skærmforløb, gentagne dyre kontroller, parallelle klientadaptere og SQL-definitioner, som skal holdes manuelt synkroniserede. En gradvis konsolidering har større værdi end en samlet omskrivning. Der er desuden konkrete korrekthedsproblemer, som bør vurderes før kosmetisk oprydning.

Ingen kildefiler er rettet, ingen commits oprettet, ingen afhængigheder installeret og ingen database kontaktet. Denne rapport er skrevet separat i `/private/tmp`.

Gennemgangen omfatter arkitektur og udvalgte kritiske stier i web, mobil, core/feed/identity-candidates, SQL og fælles importværktøjer. Den er ikke en linje-for-linje-certificering af hele kodebasen. Historiske specs bruges som kontekst; fundene bygger på det aktuelle checkout.

Prioritet P1 betyder risiko for forkert datagrundlag, forkert redigering eller tab af ændringer. P2 betyder væsentlig performance-, robustheds- eller vedligeholdelsesgæld. Prioriteterne er reviewanbefalinger, ikke en ændring af roadmapet.

## Korrekthed og redaktionel sikkerhed

**1. P1 — Ugyldige modelsvar kan blive grønne resultater uden fakta.**

`evidence_runner.py:154-162` behandler `claims=null`, en streng eller et objekt som en tom iteration. `run_record` cacher derefter resultatet og returnerer `green` (`:663-671`). Den strenge validator afviser allerede disse typer, men bliver omgået. Det skjuler fejlet udtræk som en post uden fakta. Reproduceret ved kald af de faktiske Python-funktioner: `None`, streng, objekt og heltal gav alle `([], [])`, mens den strenge validator gav `RUNNER_CLAIMS_INVALID`.

Retning: Kontrollér containerkontrakten før opdeling; bevar den bevidst gyldige tomme liste. Dæk både nyt modelsvar og cachegenbrug med negative tests.

Fil: `.claude/skills/daa-extract/scripts/evidence_runner.py`.

**2. P1 — Personskift kan blande oplysninger fra to personer i editoren.**

`web/src/Redaktion.tsx:548-563` skriver alle svar direkte ind i fælles state. Vælg A, vælg B, lad B svare først og A sidst: den valgte person er B, men evidens/familie/medier kan være A's. Handlinger på det viste assertions-id kan derefter ændre A under B's skærmbillede (`:1873`, `web/src/data/redaktionWrite.ts:289-302`). Mobil har tilsvarende ubeskyttede svar i `mobile/src/app/redaktion/person/[id].tsx:109-135,161`.

Retning: Bind data og loading/error til person-id og request-generation; kassér alle forældede svar, også refresh efter gem. Test A→B med omvendt svarrækkefølge. Statisk konstateret; ikke reproduceret i browser/UI. Reacts dokumentation beskriver samme behov for at ignorere forældede svar: https://react.dev/reference/react/useEffect#fetching-data-with-effects.

**3. P1 — Generisk fortrydelse kan overskrive en samtidig nyere redigering.**

`schema.sql:9411-9425` kontrollerer først rækkens forventede tilstand og udfører bagefter inverse DML. `_version_current_row` læser uden rækkelås (`:9252-9258`), og `_version_upsert_row` opdaterer efter primærnøgle uden expected-state-betingelse (`:9296-9298`). T1 kontrollerer B; T2 gemmer C; T1 genskaber A. Dermed kan C gå tabt trods `p_force=false`. Låsen på `change_set` blokerer ikke almindelig story-redigering (`:9325-9330`, `:6872-6893`).

Retning: Lås og verificér de berørte rækker i fælles rækkefølge, eller brug atomisk sammenligning og opdatering. Inverse indsættelser kræver også beskyttelse af fravær. Dette er et konkret statisk samtidighedsscenarie; en test med to sessioner mangler.

**4. P1 — Et udestående mobilkald kan genoprette redaktionsdata efter logout.**

`mobile/src/store/useStore.ts:375-386` accepterer resultatet af `loadRedaktionModel` ubetinget. Logout rydder modellen (`:398-402`), men et allerede igangværende kald kan derefter lægge den tilbage. To tvungne reloads kan også slutte i omvendt rækkefølge, så den ældste vinder.

Begge forløb er reproduceret med den faktiske store-kode, transpileret i hukommelsen, med simuleret I/O. Det beviser forkert state og genoprettelse af den indlæste model; det beviser ikke i sig selv omgåelse af alle UI-rollegates eller serverens adgangskontrol.

Retning: En auth-/load-generation, der invalideres ved logout, brugerskift og ny indlæsning. Koden har allerede et beslægtet generationsværn til geo, som kan bruges som lokal reference.

**5. P1 — Matcherens tidlige top-K bruger en anden score end slutrangeringen.**

`packages/core/src/matchUdgaver.ts:189-195` beskærer med `scorePair`; `:214-216` kan derefter bruge `scorePairEvidens`. Web aktiverer denne kombination i `web/src/components/SammenlignUdgaver.tsx:227`. Den bedste kandidat kan derfor være slettet før den egentlige rangering.

Reproduceret med faktisk matcherkode og direkte MatchFrame-input: A har navn johann, født 1700/død 1770; ti kandidater har samme navn, født 1700/død 1800; kandidat 99 har samme navn, ukendt fødsel/død 1770. Med topK=10 forsvinder 99; med topK=100 får 99 score 1,0 og tier auto. Dette er en rangering, ikke en automatisk databaseskrivning. `packages/identity-candidates/src/rank.ts:16-19` omgår allerede problemet lokalt med MAX_SAFE_INTEGER.

Retning: Fælles endelig scoring før beskæring; behold forskellige forretningsregler for injektiv tildeling og persona-rangering ovenpå.

**6. P2 — To samtidige portrætvalg kan begge blive primære.**

`schema.sql:8958-8965` rydder eksisterende flag og sætter derefter det valgte. Når ingen relation er primær, kan to transaktioner rydde nul rækker og sætte hvert sit medie. Kommentaren om serialisering via max(id)+1 (`:8944-8947`) er forældet: `begin_change_set` bruger nu IDENTITY (`:9184-9187`). Det eksisterende unikke indeks beskytter kun person/medie-parret (`:3592-3594`).

Retning: Serialisér portrætvalg pr. person, og håndhæv højst ét primærvalg med en databaseconstraint/et partielt unikt indeks. Medtag fortrydelsesvejen. Statisk scenario, ikke runtime-testet.

**7. P2 — Databasefejl præsenteres som manglende evidens.**

`web/src/data/redaktionRead.ts:134-159` ignorerer `error` fra flere Supabase-kald og erstatter manglende data med tomme arrays. En queryfejl kan derfor blive en normal tom evidensmodel, uden at skærmens catch aktiveres. Mobilens tilsvarende læser har samme mønster (`mobile/src/data/redaktionRead.ts:166-190`).

Retning: Fælles fejlkontrol og eksplicit fejltilstand for editorens nødvendige datagrundlag. Tolerant fravalg af ekstra feedindhold kan fortsat være en særskilt, dokumenteret kontrakt. Statisk konstateret.

## Performance og gentaget arbejde

**8. P2 — Biografilæsningen gentager dyb gyldighedskontrol.**

`schema.sql:3198-3223` gennemløber identitetskomponenter pr. narrativ og undersøger medlemskaber/publicering gentagne gange for overlappende personer, kilder og detaljenarrativer. `membership_is_current` rekonstruerer tilstand og hash (`:3054-3067`). Bio-v2 henter seneste event (`:16818-16824`), hvorefter publiceringsgaten igen henter event, bygger tilstand og beregner hashes (`:16640-16665`). Fakta- og familiekildelæsere genbruger også gaten pr. række (`:21446`, `:20921`).

Retning: Beregn komponenter, aktuelle medlemskaber og publiceringsgyldighed for distinkte relevante nøgler én gang inden for hvert statement og genbrug resultatet. Bevar fail-closed og provenance. En permanent cache bør først overvejes, når alle invalidationsafhængigheder er kortlagt.

Statusdokumentet angiver en tidligere målt stigning fra 12,7 til cirka 25 sekunder for alle-personer-biografilæsning (`docs/evidensbaseret-genimport/status.md:37-38`). Tiden er ikke genmålt her, og andelen fra de enkelte delberegninger er ukendt. Næste bevis bør være faktiske query plans og HTTP-tider på en repræsentativ kopi, inklusive enkelte personer og hele korpus. Metodegrundlag: https://www.postgresql.org/docs/17/using-explain.html.

**9. P2 — Feedordningen har stadig kvadratisk arbejde.**

`packages/feed/src/order.ts:245-267` filtrerer restpuljen og fjerner elementer med indexOf/splice inde i løkken. Når portrætter er opbrugt, kan filtreringen gentages for hvert resterende kort. Den indledende sortering gør derfor ikke hele algoritmen O(n log n). Web bygger hele strømmen igen, når flere asynkrone datalag ankommer (`web/src/components/feed/FeedStreamView.tsx:187-216`).

Retning: Køer/indekser for relevante korttyper og fjernelse uden gentagen arrayflytning; undgå unødvendige fulde genberegninger. En syntetisk måling af udvælgelsesløkken understøttede skaleringsproblemet, men er ikke en måling af den nuværende app på en telefon. Effekten ved aktuelle datamængder skal profileres, før denne opgave prioriteres over læsekæden.

**10. P2 — Et enkelt matchningsklik genkører hele kandidatberegningen.**

`web/src/components/SammenlignUdgaver.tsx:209-233` samler framebygning, navnematchning og projektion af redaktionelle beslutninger i én memo. Ændringer i afviste/linkede udløser dermed hele beregningen, selv om de alene ændrer arbejdslistevisningen. Foldeprognoser bygges også for alle åbne kandidatpar (`:252-265`).

Retning: Adskil stabile kandidatberegninger fra beslutningsprojektion; beregn dyre prognoser ved behov. Overvej en worker, hvis profilering viser mærkbar blokering. Unødvendig genberegning er konstateret; konkret kliklatens er umålt.

**11. P2 — Importen genvaliderer hele ledgeren pr. record og alle klausuler pr. claim.**

`evidence_runner.py:836` genkalder `load_ledger` (`:795-815`). Orkestratoren foretager kontrollen både direkte og via guarded-runneren (`run_evidence_43b.py:161,199`), efter batchens indledende validering. N records og L ledgerrækker giver cirka 2·N·L rækkevalideringer. Claimopdelingen kalder desuden validatoren pr. claim (`evidence_runner.py:157`), som genbygger klausulindekset og hashes alle klausuler (`:125-135,175`).

Retning: Én uforanderlig, valideret ledger pr. batch og ét valideret klausulindeks pr. record. Bevar den konkrete records nøgle-/hashkontrol ved brug. Dette er redundant arbejde; dets andel af total køretid er ikke målt.

Filerne ligger under `.claude/skills/daa-extract/scripts/`.

**12. P2 — Cachegenkørsel udfører forberedelse, som kun er nødvendig ved modelkald.**

`run_evidence_43b.py:171-180` bygger call-dir og kører sandbox-adgangstest før cacheopslaget i `evidence_runner.py:603`. Dermed starter en cachet genkørsel stadig en række hjælpeprocesser. Adgangstesten kan desuden lave lokale databaseprober; den blev derfor ikke kørt i dette review.

Retning: Gør call-dir og sandbox-test dovne bag gated_run, efter cachemiss. Bevar eligibility, versionsbinding og validering af cacheindhold. Tidsgevinsten er umålt.

## Robusthed, gentagelser og vedligeholdelse

**13. P2 — Cachefiler skrives direkte til deres endelige navn.**

`evidence_runner.py:523-525` kan efterlade en trunkeret fil ved procesafbrydelse. Næste læsning laver uindpakket json.loads (`:508-512`), før cachevalideringens try (`:603-610`), så én korrupt post kan stoppe hele genkørslen.

Retning: Atomisk privat skrivning og synligt, afgrænset udfald for korrupt cache. Bevar konfliktkontrol og validering ved genbrug. Statisk konstateret.

**14. P2 — Privat fil-I/O har flere forskellige sikkerhedskontrakter.**

`identity_decision_sheet.py:158,175`, `identity_control_sheet.py:221,237` og `interpretation_decision_sheet.py:194-208,230-231` skriver først og ændrer derefter til 0600. I en delt mappe med umask 022 kan privat tekst derfor kortvarigt være læsbar; et forkert outputvalg kan også placere den i Git. Nyere relationsark har allerede stikontrol.

Retning: En neutral fælles hjælper med kontrol af privat rod, Git og symlinks samt sikre rettigheder før første byte og atomisk publicering. Eksisterende filers rettigheder skal også håndteres før skrivning. Dette er et konkret betinget scenario, ikke bevis for allerede lækkede filer.

Filerne ligger under `.claude/skills/daa-extract/scripts/`.

**15. P2 — Web og mobil vedligeholder betydelig fælles datalogik hver for sig.**

En tekstsammenligning viste bl.a. 719 identiske linjer mellem redaktionRead-adapterne, 463 mellem redaktionWrite og 150 mellem presens. Story-loaderne har 62 identiske linjer og næsten samme dataflow (`web/src/data/story.ts:8-55`, `mobile/src/data/story.ts:8-57`). Tallene er eksakte linjematches, ikke en vurdering af at alt overlap kan fjernes. Platformspecifik upload, auth og UI har legitime forskelle.

Retning: Udvid det fælles lag med rene RPC-payloads, datamapping, validering og klientinjicerede læsere. Bevar tynde platformadaptere til storage, native API'er og præsentation. Flyt ikke alt ind i core; definer en tydelig ansvarlig pakke for delt datatilgang. Matcherens lokale workaround i fund 5 viser allerede en reel konsekvens af splittede regler.

Skærmstørrelse alene er ikke en fejl, men Redaktion.tsx på 2.660 linjer blander hentning, editor-state og mange operationer. Udtræk personbundne dataforløb og selvstændige editors med udgangspunkt i konkrete races og testbehov.

**16. P2 — SQL-paritetskontrollen efterlader centrale funktioner uden dækning.**

`tests/sql/inspect-5ab-function-parity.sql:23-42` og CI anvender en håndholdt liste på 62 funktioner. Centrale biografi-/publiceringsfunktioner er udenfor. Der findes aktuel drift: schema.sql:14978-14983 låser alle bundne narrativer; migrationens definition på db-migrations.sql:14005-14012 filtrerer yderligere på source.slags=DAA-udgave. Det kan give forskellige låsesæt ved ændret/andet kildeslag. Det dokumenterer forskel mellem definitionerne, ikke et observeret produktionssvigt.

Retning: Katalogbaseret sammenligning af relevante applikationsfunktioner, signaturer, konfiguration og rettigheder med eksplicitte undtagelser. Afklar derefter én vedligeholdt definition pr. funktion og reproducerbar generering af schema-snapshot. Historiske migrationer skal ikke blot omskrives. De store filer — schema.sql 21.451 linjer og db-migrations.sql 35.162 — øger værdien af en mekanisk paritetskontrakt.

## Hvad bør bevares, og hvad giver størst værdi?

Bevar de rene funktioner i core/feed, de eksplicitte kilde- og identitetsmodeller, validering ved cachegenbrug, hashbinding og de målrettede SQL-/konkurrenstests. De er et godt fundament for forbedringerne. Proveniens- og privatlivskontroller bør gøres billigere gennem genbrug af samme beregning, ikke ved at springe kontroller over.

Den højeste forventede værdi ligger i at lukke korrekthedshullerne i editor/runner/matcher/fortrydelse, måle den tunge læsekæde og samle fælles datakontrakter. Feed- og importoptimeringerne har tydeligt redundant arbejde, men mangler produktionsmålinger til indbyrdes prioritering. En generel omskrivning eller en samling af alle historiske engangsscripts i en stor frameworkstruktur er ikke begrundet af disse fund.

For genimport er aktivt roadmapmål fortsat trin 6e. Rapporten er et review og et beslutningsgrundlag, ikke en ny implementeringsplan. Importrelaterede opgaver skal ved en eventuel plan kobles til roadmapmål, værdikædeled, leverancetype, læser-/redaktørværdi, færdigbevis og den vej, de erstatter. De frosne legacyloadere skal ikke genåbnes som permanent parallel arkitektur.

## Verifikation og begrænsninger

- Faktiske Python-validatorer blev kaldt i hukommelsen uden pycache; ugyldige claimstyper blev reproduceret.
- Faktisk mobilstore blev transpileret i hukommelsen med simuleret I/O; logout- og reload-races blev reproduceret med assertions.
- Faktisk matcherkode blev kørt med syntetiske MatchFrames; top-K-fejlen blev reproduceret. Importerede normaliseringsfunktioner var stubs og blev ikke brugt til disse direkte frames.
- Statisk kodegennemgang og linjesammenligning underbygger de øvrige fund. SQL-samtidighedsscenarier er ikke kørt med to sessioner.
- Ingen fuld testsuite, build, browserprofilering eller DB/HTTP-måling er udført. Det tilgængelige python3-miljø har ikke pytest; der blev ikke installeret noget. Eksisterende CI-testdefinitioner er gennemgået, men deres aktuelle grønne status er ikke verificeret.
- Officiel React-/PostgreSQL-dokumentation blev slået op som metodekontrol. Ingen tilsluttede projektdata eller produktionssystemer blev tilgået.
- Hovedcheckout og review-worktree kontrolleres med Git-status før aflevering. Rapporten er en midlertidig separat fil og indgår ikke i repositoryet.
