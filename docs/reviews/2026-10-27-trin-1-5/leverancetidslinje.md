# Fase 0e — leverancetidslinje (hvad der faktisk blev lavet)

> Mekanisk sammenstillet af hovedsessionen: changelog-overskrifter, titler på mergede PR'er (GitHub) og antal
> commits pr. scope (Conventional Commits) på `main` siden 2026-06-01, pr. ISO-uge. Ingen vurdering. Formål: at
> fase 1a kan sammenligne det, der blev lavet, med det, der blev besluttet (0b), og finde glidning uden beslutning.


> **Læsevejledning:** Fra ca. september merges PR'er som squash, så én PR = én commit på `main`; det lave
> commit-tal fra uge 38 betyder **ikke** mindre arbejde. Brug PR-titlerne og changelog-posterne som mål for aktivitet.
Totaler: 165 daterede changelog-poster (+1 udateret), 222 mergede PR'er, 1943 commits (ekskl. merges).

## 2026-U25 (uge fra 2026-06-15) — 56 commits

Commits pr. scope: daa-extract 18, docs 10, web 7, validate 3, feat 3, load 3, loader 2, daa-presens 2, … (+7 scopes)

Changelog:
- 2026-06-15 App-skive + slægtskabs-UI (`changelog.md:4340`)
- 2026-06-15 DAA-parsere som skills (`changelog.md:4349`)
- 2026-06-15 Datamodel + load (`changelog.md:4356`)
- 2026-06-15 TNG-analyse (`changelog.md:4366`)
- 2026-06-17 Ægtefælle-rygrad for hele slægten + deterministisk boern (`changelog.md:4322`)

## 2026-U26 (uge fra 2026-06-22) — 115 commits

Commits pr. scope: mobile 34, redaktion 25, db 14, specs 11, data 10, reviews 5, docs 5, plans 4, … (+5 scopes)

Mergede PR'er:
- 2026-06-27 #8 feat(mobile): Følgesvend RN/Expo — tynd skive + §9 alfabet-/linje-hop

Changelog:
- 2026-06-23 Slægtslinjer navngives — `lineage`-entitet, trin (a) (`changelog.md:4303`)
- 2026-06-25 `levende`-GDPR-cache udledt + RLS-deploy-bug rettet (`changelog.md:4278`)
- 2026-06-27 Redaktions-UI kerne-skive — implementeret + DB-deploy (`changelog.md:4251`)
- 2026-06-28 Plan 2A — person-liste & navigation i redaktions-appen (`changelog.md:4235`)
- 2026-06-28 Plan 2B — editor-dybde: selv-forsynende editor + køn + familie/sektion (`changelog.md:4215`)
- 2026-06-28 Plan 2C-1 — entitetslister (read-only) i redaktions-appen (`changelog.md:4199`)

## 2026-U27 (uge fra 2026-06-29) — 357 commits

Commits pr. scope: tng-qa 45, web 33, db 29, redaktion 24, docs 22, mobile 19, media 17, web,mobile 16, … (+38 scopes)

Mergede PR'er:
- 2026-06-30 #10 "Dobbelt/tredobbelt"-label ved flere slægtskabs-linjer i samme afstand
- 2026-06-30 #11 Korroborations-visning — bekræftet ad uafhængige slægtskabs-linjer
- 2026-06-30 #12 Web: redaktørbord + publikums-følgesvend fra Claude Design-handoff
- 2026-06-30 #9 Bilineal multi-linje slægtskabsfinder + konfidens på stien
- 2026-07-02 #13 feat(web): portér Reventlow-web-v2-design ind i følgesvenden (Fase 1+2)
- 2026-07-03 #14 feat: samme_som identitets-projektion (collapse) + redaktionel linking
- 2026-07-03 #15 feat(web,mobile): stamtræ Kolonner-visning + bidirektionel aner/efterkommere
- 2026-07-05 #16 feat(web): ren URL-routing — dybe-links til person/gods + browser-back
- 2026-07-05 #17 feat(media): mediehåndtering Slice 0 — DB/RLS + redaktør-upload (mobile+web)
- 2026-07-05 #18 feat(media): slet/afkobl billeder + objekt-foto-upload (Slice 0h)
- 2026-07-05 #19 feat(stamtræe): generations-reparation — hul-reparation via slægtled (web+mobile)
- 2026-07-05 #20 feat(media): lightbox — klik-for-at-forstørre (Slice A)
- 2026-07-05 #21 feat(media): billedstørrelser Slice B — thumb/medium/large + variant-tabel
- 2026-07-05 #22 feat(narrativ): billeder i narrativer + slægts/linje-narrativ-editor (Slice C)
- 2026-07-05 #23 feat(mobile): Følgesvend v3 — forsidefeed, menu-drawer & bogmærker

Changelog:
- 2026-06-29 Opret-ny-entitet — Tilføj-fanen (`changelog.md:4101`)
- 2026-06-29 Plan 2C-2a — redigerbar sektion-relationer (hverv/godser) i redaktør-person-editoren (`changelog.md:4171`)
- 2026-06-29 Plan 2C-2b — redigerbar familie-sektion (partner + barn + konfidens) i redaktør-person-editoren (`changelog.md:4125`)
- 2026-06-30 Slægtskabsfinder: bilineal multi-linje + konfidens på stien (`changelog.md:4079`)
- 2026-06-30 TNG-QA: pipeline komplet ende-til-ende (Trin 1-6) + kalibrering (`changelog.md:4055`)
- 2026-06-30 Versionering + hyperlinks (App-lag, RN/Expo) — kode-komplet, dual-reviewet, IKKE Expo-kørt (`changelog.md:4000`)
- 2026-06-30 Versionering + hyperlinks (DB-lag) — implementeret, dual-reviewet, applied til prod (`changelog.md:4030`)
- 2026-07-01 Flere-forældrepar datafix (`changelog.md:3967`)
- 2026-07-01 Versionering + hyperlinks — real-device Expo-verifikation + DB-bugfix (`changelog.md:3982`)
- 2026-07-02 DAA-reimport Etape 1+2, data-tab-genopretning, grundlægger-links, samme_som-design (`changelog.md:3932`)
- 2026-07-02 Redaktionel samme_som-linking implementeret + DB live i prod (`changelog.md:3838`)
- 2026-07-02 samme_som-collapse implementeret (web + mobile) (`changelog.md:3899`)
- 2026-07-03 Børn af flergifte forældre knyttet til korrekt union (`changelog.md:3786`)
- 2026-07-03 Flere narrativer pr. person — udgave-nøglede narrativer (DB + web + mobile, (`changelog.md:3691`)
- 2026-07-03 Redaktør-web-cohesion: v2-header + person-browse (`changelog.md:3814`)
- 2026-07-03 Redaktør: klikbar familie-navigation + fødsels/dødsår (web+mobile, (`changelog.md:3730`)
- 2026-07-03 Stamtræ: Kolonner-visning + bidirektionel aner/efterkommere (web + mobile) (`changelog.md:3864`)
- 2026-07-03 TNG-QA Etape 3+4 + spøgelses-union-oprydning (`changelog.md:3755`)
- 2026-07-03 TNG-analyse opfølgning + backlog-prioritering (`changelog.md:3670`)
- 2026-07-04 Mediehåndtering — DB/Storage/RLS-fundament (Slice 0, (`changelog.md:3622`)
- 2026-07-04 Mediehåndtering — code-review-fixes (Slice 0, (`changelog.md:3584`)
- 2026-07-05 Følgesvend v3 — forsidefeed, menu-drawer & bogmærker (mobile, branch feat/folgesvend-v3, (`changelog.md:3372`)
- 2026-07-05 Generations-reparation af stamtræet — hul-reparation via slægtled (web+mobile, PROD-LIVE + merget, (`changelog.md:3406`)
- 2026-07-05 Mediehåndtering — DB/RLS-lag LIVE i prod (Slice 0, (`changelog.md:3560`)
- 2026-07-05 Mediehåndtering — Slice 0g: redaktør-upload (mobile, (`changelog.md:3528`)
- 2026-07-05 Mediehåndtering — Slice 0g: redaktør-upload porteret til web (`changelog.md:3495`)
- 2026-07-05 Mediehåndtering — Slice 0h: runtime-fix + slet/afkobl + objekt-foto (`changelog.md:3432`)

## 2026-U28 (uge fra 2026-07-06) — 38 commits

Commits pr. scope: stamtræ 6, bogmaerker 5, web 4, review 4, mobile 3, changelog 3, claude 2, redaktion 2, … (+7 scopes)

Mergede PR'er:
- 2026-07-06 #24 feat(web): søg/gennemse som modalt overlay — stamtræ og detalje deler skærmen
- 2026-07-06 #25 feat: konto-bogmærker — login-eksklusive, cross-device-synkroniserede bogmærker
- 2026-07-10 #26 fix(data): person 1↔104 spøgelses-union + backlog-noter
- 2026-07-10 #27 feat(web): v4-navigation — mega-menu, forside, søgning-i-træet & split-skærm
- 2026-07-12 #28 feat(stamtræ): generationsbrowser med marker-gatet forældre-ukendt (web+mobil)
- 2026-07-12 #29 fix: review 27 Bølge 1 — CI + sikkerheds-/robusthedsfixes (web+mobil)

Changelog:
- 2026-07-06 Datafix: person 1 fejlagtigt "gift med" eget barnebarn person 104 (`changelog.md:3273`)
- 2026-07-06 Konto-bogmærker — login-eksklusive, cross-device-synkroniserede bogmærker (web+mobile, branch feat/bogmaerker-konto, (`changelog.md:3328`)
- 2026-07-06 Konto-bogmærker: dual-review 22 af IMPLEMENTERINGEN + 4 fund rettet (`changelog.md:3296`)
- 2026-07-09 "Forældre ukendt"-markering + inline marker-gatet kandidat-kolonne (web+mobil, branch `feat/generations-browser-v2`, IKKE merget, (`changelog.md:3230`)
- 2026-07-11 Review 26 (Codex) — rettelser af generationsbrowseren (web+mobil, branch `feat/generations-browser-v2`, (`changelog.md:3197`)
- 2026-07-11 Review 27 — dual-review af review-26-rettelserne (web+mobil, branch `feat/generations-browser-v2`, (`changelog.md:3176`)
- 2026-07-12 Slankning af `claude.md` (`changelog.md:3166`)

## 2026-U29 (uge fra 2026-07-13) — 167 commits

Commits pr. scope: feed 32, chore 13, core 11, (uden type) 9, 1939 9, mobile 9, plan 8, web 8, … (+24 scopes)

Mergede PR'er:
- 2026-07-13 #30 fix(mobile): GeoMap U+2028/U+2029 syntaksfejl (rettelse til merged #29) + mobil-tsc i CI
- 2026-07-13 #31 feat: review 27 Bølge 2 — perf, parity-test, meId-fix, ErrorBoundaries (web+mobil)
- 2026-07-13 #32 test(web): hærd parity-normalizer mod skjult kode-drift (opfølgning, review 29)
- 2026-07-14 #33 refactor(core): packages/core — delt web↔mobil-logik (review 27 Bølge 3 #13)
- 2026-07-14 #34 refactor(web): split Folgesvend-monolitten — 8 views → components/ (review 27 W-K1)
- 2026-07-14 #35 refactor(mobile): split person-editoren — inline-sheets → components/redaktion/ (review 27 M-K2)
- 2026-07-14 #36 perf: udskyd geo-kæden (place+fact) til første kort-brug (review 27 P3)
- 2026-07-16 #37 Flere DAA-udgaver: roadmap + specs + divergens-rapport
- 2026-07-16 #38 feat: Sammenlign udgaver-UI (Problem 3 §5)
- 2026-07-16 #39 feat: Problem 2 Fase 1+2 — konkurrerende forældrefamilie (DB-lag + loader-evidens)
- 2026-07-16 #40 feat: Problem 2 Fase 3 — app-lag (data + UI): forældrefamilie-adjudikation
- 2026-07-16 #41 chore: Problem 2 Fase 4 prod-cutover prep (backfill-separation + runbook)
- 2026-07-16 #42 fix(sikkerhed): luk anon-eksponering af interne muterende _-helpers
- 2026-07-16 #43 fix(sikkerhed): fail-close authenticated levende-læk (F-02)
- 2026-07-16 #44 fix(ci): gater core-typecheck + R-tests; ret typefejl (F-16)
- 2026-07-16 #45 fix(sikkerhed): fail-close media-laget for F-02 (levende-foto-læk)
- 2026-07-17 #46 fix(sikkerhed): luk polymorf family/unknown fail-open i RLS (F-02c)
- 2026-07-17 #47 docs: session-handoff — sikkerhedshærdning (changelog + decisions)
- 2026-07-17 #48 docs(plan): prioriteret styringsplan for 1939-load + dato-hærdning + cutover
- 2026-07-17 #49 feat(dato): A1 + A2 runde 1 — dato-hærdning (model + qualifier-aware parser)
- 2026-07-17 #50 feat(1939): A3a — versioneret konverter til load_daa.R-format
- 2026-07-17 #51 feat(K2): staging-gate — skjul ny-udgave-poster indtil matchet
- 2026-07-18 #52 docs(runbook): K2 i cutover + Fase 2 1939-load-checkliste
- 2026-07-18 #53 docs(1939): K3 prod-load udført — efterslæb efter PR #52
- 2026-07-18 #54 feat(redaktion): udvid redigerbare felter til dåb/begravelse/floruit/naturalisering
- 2026-07-18 #55 feat(samme-som): synlig karantæne-feedback + udgave-versionsvælger
- 2026-07-19 #57 docs(feed): fase 3 — spec + implementeringsplan (minihistorier & redaktionel styring)
- 2026-07-19 #58 Fix 1939 narrative segmentation quality
- 2026-07-19 #59 Mediehåndtering fase 1: filside, fuld CRUD og rettighedsflow
- 2026-07-19 #60 Mediehåndtering fase 2: spec + implementeringsplan + dokument-fase-beslutning (kun dokumentation)
- 2026-07-19 #61 Karantæne-hints + handlingsanvisning i Sammenlign udgaver
- 2026-07-19 #62 feat(media): implementér mediebibliotek og anvendelser
- 2026-07-19 #63 chore(feed): afslut levende feed fase 3-dokumentation

Changelog:
- 2026-07-14 `packages/core` — delt web↔mobil-logik (review 27 Bølge 3 #13, (`changelog.md:3140`)
- 2026-07-17 Sikkerhedshærdning fra Codex-fundament-review (`changelog.md:3107`)
- 2026-07-18 Idékatalog: formidling oven på kildematerialet (`changelog.md:3082`)
- 2026-07-18 Koncept: Det levende feed (`changelog.md:3092`)
- 2026-07-18 Levende feed fase 1 — implementeret (`changelog.md:3013`)
- 2026-07-18 Levende feed fase 2 — design-spec skrevet (`changelog.md:2998`)
- 2026-07-18 Levende feed fase 2 — implementeret i kode (`changelog.md:2955`)
- 2026-07-18 Levende feed fase 2 — implementeringsplan skrevet (`changelog.md:2981`)
- 2026-07-18 Plan: levende feed fase 1 — klar til implementering (`changelog.md:3057`)
- 2026-07-18 Spec: levende feed fase 1 — dynamik & uendelig scroll (`changelog.md:3069`)
- 2026-07-19 1939-narrativer — deterministisk kvalitetsrettelse (`changelog.md:2879`)
- 2026-07-19 Levende feed fase 3 — implementeret og lokalt verificeret (`changelog.md:2896`)
- 2026-07-19 Mediehåndtering fase 1 — design-spec for filsiden (`changelog.md:2851`)
- 2026-07-19 Mediehåndtering fase 1 — implementeringsplan (`changelog.md:2838`)
- 2026-07-19 Mediehåndtering fase 1: filside og fuld CRUD (`changelog.md:4378`)
- 2026-07-19 Mediehåndtering fase 2 — biblioteket implementeret lokalt (`changelog.md:2778`)
- 2026-07-19 Mediehåndtering fase 2 — design-spec for biblioteket (`changelog.md:2821`)
- 2026-07-19 Mediehåndtering fase 2 — implementeringsplan (`changelog.md:2798`)
- 2026-07-19 Mediehåndtering — dokumenter/transskription besluttet som fase 5 (`changelog.md:2810`)
- 2026-07-19 Mediehåndtering — koncept for robust medieforvaltning (`changelog.md:2866`)

## 2026-U30 (uge fra 2026-07-20) — 194 commits

Commits pr. scope: presens 45, media 38, feed 14, redaktion 13, docs 11, web 10, sammenlign-udgaver 10, db 8, … (+23 scopes)

Mergede PR'er:
- 2026-07-20 #64 Mediehåndtering fase 3: hygiejne-spec (dedup, sha-stier, janitor) — kun dokumentation
- 2026-07-20 #65 Selektiv publicering af staged personer (K2) + løsn 1939-narrativ-gate
- 2026-07-20 #66 docs: ret prod-deploy-runbook til fuld-fil-kørsel
- 2026-07-20 #67 docs: prod-status efter live-deploy af mediehåndtering + levende feed + K2
- 2026-07-20 #68 Mediehåndtering fase 3: implementeringsplan + dual-review (kun dokumentation)
- 2026-07-20 #69 docs: ret fase 3-planens red_relation-fangst efter Codex-fund
- 2026-07-20 #70 docs(feed): udskyd levende-feed fase 4 (LLM-assist)
- 2026-07-20 #71 docs(feed): runbook for levende-feed fase 2+3 prod-cutover
- 2026-07-20 #72 feat(sammenlign-udgaver): brugbar identitetsvurdering for redaktøren
- 2026-07-20 #73 feat(sammenlign-udgaver): vis tydeligt hvilken udgave bliver kanonisk
- 2026-07-21 #74 feat(media): implementér fase 3 mediehygiejne
- 2026-07-22 #75 feat(media): fase 4 — erstat fil, udrensning, portræt-valg
- 2026-07-23 #76 feat(presens): beregnet præsensliste-visning (web+mobil)
- 2026-07-23 #77 fix(presens): patrilineær efterkommer-tilhør + kilde-visning for redaktionelt fakta
- 2026-07-23 #78 docs(media): afstem fase 4 — LIVE i prod
- 2026-07-24 #79 feat(presens): redesign af præsenslistens visning
- 2026-07-24 #80 fix(presens): match designets streger og whitespace nøjagtigt
- 2026-07-24 #81 fix(redaktion): UX-oprydning af Sammenlign udgaver + bulk-publicering
- 2026-07-24 #82 feat(feed): midlertidig disable af korttyper med tyndt DB-indhold
- 2026-07-24 #83 fix(presens): gift-ind titel, indrykningsfixes + fold-ud narrativ ved navneklik
- 2026-07-24 #84 docs(media): dokumentér fase 3-hygiejne prod-cutover (2026-07-21)
- 2026-07-24 #85 docs(presens): markér våben+intro-runbook som udført
- 2026-07-24 #86 feat(sammenlign-udgaver): stale-while-revalidate-cache + skeleton
- 2026-07-24 #87 feat(presens): portér mobil-præsenslisten til dagens web-redesign
- 2026-07-24 #88 perf(sammenligning): red_match_personer() batchet RPC (Fase 4.1)
- 2026-07-25 #89 feat(feed): udeluk levende/muligvis-levende personer + korte narrativer fra feedet
- 2026-07-26 #100 perf(sammenlign): bøt parentChild pr. barn — undgår O(rows×edges) pr. klik
- 2026-07-26 #101 perf(sammeSomPreflight): inkrementel fast-path — undgår fuld collapse pr. kandidatpar
- 2026-07-26 #90 fix(segment-1939): re-segmentering af 1939-narrativer (anvendt mod prod)
- 2026-07-26 #91 feat(feed): sociale personposter med billedstribe (web + mobil)
- 2026-07-26 #92 ci(r): cache R-biblioteket — duckdb kompileres ikke længere ved hver kørsel
- 2026-07-26 #93 fix(sammenlign): vis de kandidater der falder under tærsklen
- 2026-07-26 #94 fix(sammenlign): vis de kandidater der falder under tærsklen
- 2026-07-26 #95 feat(match): evidens-normaliseret score som opt-in
- 2026-07-26 #96 feat(sammenlign): slå evidens-normaliseret score til
- 2026-07-26 #97 docs(changelog): tværudgave-matchning for ægtefæller
- 2026-07-26 #98 fix(2018-20): patch 18 narrativer hvor slaegtled-/kuld-overskrift bloedte ind
- 2026-07-26 #99 docs(changelog): 2018-20 slaegtled-bleed rettet, anvendt mod prod

Changelog:
- 2026-07-20 Mediehåndtering fase 1+2 + levende feed fase 2-3 + K2 selektiv publicering — LIVE i prod (`changelog.md:2713`)
- 2026-07-20 Mediehåndtering fase 3 — hygiejne-spec skrevet (`changelog.md:2758`)
- 2026-07-20 Mediehåndtering fase 3 — implementeringsplan skrevet + dual-reviewet (`changelog.md:2698`)
- 2026-07-20 Operatørguide afstemt mod read-only prod-facit (`changelog.md:2739`)
- 2026-07-21 Mediehåndtering fase 3 — LIVE i prod (`changelog.md:2658`)
- 2026-07-22 Mediehåndtering fase 4 — LIVE i prod (`changelog.md:2557`)
- 2026-07-22 Mediehåndtering fase 4 — implementeret og verificeret lokalt (`changelog.md:2623`)
- 2026-07-22 Præsensliste-visning v1 — implementeret på feature-branch (`changelog.md:2582`)
- 2026-07-23 Præsensliste: patrilineær efterkommer-tilhør rettet mod rigtig prod-data (`changelog.md:2570`)
- 2026-07-26 1939-kvalitetsvurdering + re-segmentering — LIVE i prod (`changelog.md:2517`)
- 2026-07-26 Personers OCR-kvalitetsark — kodeklar, IKKE deployet (`changelog.md:2411`)
- 2026-07-26 Tværudgave-matchning gjort mulig for ægtefæller (`changelog.md:2472`)

## 2026-U31 (uge fra 2026-07-27) — 142 commits

Commits pr. scope: replay 14, docs 13, redaktion 11, plan 10, feat 9, db 7, loader 6, web 5, … (+30 scopes)

Mergede PR'er:
- 2026-07-27 #103 feat(redaktion): personers OCR-kvalitetsark
- 2026-07-28 #104 docs(redaktion): record_key-backfill for 2018-20 + web-deploy-status
- 2026-07-28 #105 fix(kilde): vis kilde for de 627 personer uden bog-nummer
- 2026-07-28 #106 fix(grid): navn_mangler måler den viste værdi + én række pr. person
- 2026-07-28 #107 docs(changelog): kilde for de 627 personer uden bog-nummer
- 2026-07-28 #108 docs(flerslægt): vurdering af parathed til andre slægter end Reventlow
- 2026-07-28 #109 feat(lineage): slægts-rod så flere slægter kan bo i samme base (B2)
- 2026-07-28 #110 docs(changelog): slægts-rod trin 2 kørt — begge trin live i prod
- 2026-07-28 #111 docs: 1939-løbenummer som åben beslutning + spec for redaktørens udgave-faner
- 2026-07-29 #102 docs(1939): diagnosticér dubletter + værktøj til parvis afgørelse
- 2026-07-29 #112 1939: fyenske Linje som egen linje + ude af matchning; narrativ-apparat trimmet
- 2026-07-29 #113 docs(decisions): delmængde-forældre — konflikt eller blot mindre detalje? (ÅBEN)
- 2026-07-29 #114 feat(matcher): indgifte i den fyenske linje arver undtagelsen
- 2026-07-29 #115 docs: kvalitetsark i drift + ægtefælle-forankringsplan efter dual-review
- 2026-07-29 #116 feat(identitet): identitetsregister, perturbationstest og side-afstemning for 1939
- 2026-07-29 #117 feat(kalibrering): terra valgt med R10-omtale-gate og kontrolkørt prompt
- 2026-07-29 #118 feat(segment): deterministisk lokal_id fra trykt struktur (2018-20); 1939-skema forkastet på måling
- 2026-07-29 #119 feat(segment): 1939-udgaveprofil — bogens trykte adresse som lokal_id (505/505 unikke)
- 2026-07-29 #120 feat(identitet): register om-nøglet til bogens trykte adresse (417/417 nummer-enige)
- 2026-07-30 #121 feat(segment): pegepind-krydstjek + l↔1-tekstanker (437 auto-om-nøglet)
- 2026-07-30 #122 docs: session-log 1939-identitet + to beslutninger
- 2026-07-31 #134 feat(loader): før-næste-load-gates + slutark-register + replay-designbeslutning
- 2026-07-31 #135 feat(db): replay-forudsætninger — IDENTITY-migration + lås-kontrakt for id-writers
- 2026-07-31 #136 feat(replay): replay-kæden trin 2-4 — dry-run, --replace, familie-graf + gates
- 2026-07-31 #137 feat(register): kalibreret evidenspas — v2-om-nøglinger + strukturelle fund
- 2026-07-31 #138 feat(typografi): løft skriftstørrelser ét trin i web + mobil
- 2026-07-31 #139 feat(1939): registeranvendelse + v2/v3-artefakter + ny-klassen — begge prod-replaces
- 2026-08-01 #140 feat(web): ægte links + tydeligere "Samme person" i redaktøren
- 2026-08-01 #141 feat(redaktion): tilføj part til eksisterende union + identitets-invarianter

Changelog:
- 2026-07-27 2018-20: 18 narrativer med slaegtled-/kuld-bleed rettet — LIVE i prod (`changelog.md:2445`)
- 2026-07-27 Personers OCR-kvalitetsark — DB LIVE i prod, web IKKE deployet (`changelog.md:2396`)
- 2026-07-28 1939-dubletter: 23 af 35 kandidater slettet (`changelog.md:2237`)
- 2026-07-28 Kilde vist for de 627 personer uden bog-nummer (`changelog.md:2302`)
- 2026-07-28 Kvalitetsark: navn_mangler-flaget var falsk på 1169 af 1757 rækker (`changelog.md:2340`)
- 2026-07-28 Personers OCR-kvalitetsark — record_key-backfill for DAA 2018-20 + web-status rettet (`changelog.md:2374`)
- 2026-07-28 Slægts-rod i lineage — LIVE i prod, begge trin (`changelog.md:2267`)
- 2026-07-29 1939-identitet: fra LLM-lokatorer til bogens trykte adresse — 445/515 i mål (`changelog.md:2100`)
- 2026-07-29 1939: Den fyenske Linje fik egen linje og omstridt slægtskab (`changelog.md:2142`)
- 2026-07-29 2018-20: bogens apparat bløt ind i sidste posts narrativ (`changelog.md:2201`)
- 2026-07-29 Personers OCR-kvalitetsark — røgtest udført, arket i drift (`changelog.md:2128`)
- 2026-07-30 Helhedsreview → slutark lukket → replay-kæden bygget (`changelog.md:2069`)
- 2026-07-31 FØRSTE ÆGTE PROD-REPLACE: 1939-v2-artefaktet live (`changelog.md:1992`)
- 2026-07-31 Replay-GO-betingelser opfyldt: destruktiv --replace-test grøn + manifest-hul lukket (`changelog.md:2017`)
- 2026-07-31 Trin 4: familie-graf-replace bygget + destruktivt testet, samme dag) (`changelog.md:2042`)
- 2026-07-31 Trin B: fakta-efterudtrækket i prod — v3 live, aften) (`changelog.md:1974`)
- 2026-08-01 Karantænen opløst + union-redigering (PR #141) (`changelog.md:4385`)
- 2026-08-01 Ægte links i web-fladen + tydeligere "Samme person" (`changelog.md:1941`)

## 2026-U32 (uge fra 2026-08-03) — 225 commits

Commits pr. scope: fix 74, feat 52, docs 50, 1939 29, web 7, test 6, db 2, refactor 1, … (+4 scopes)

Mergede PR'er:
- 2026-08-03 #142 docs: session-log + spec og plan for evidensbaseret genimport
- 2026-08-06 #143 fix(db): registrér story_kilde i version_pk_registry (#127)
- 2026-08-06 #145 feat(redaktion): historik-panel + fortryd-knap i web-redaktøren (#144)
- 2026-08-07 #146 feat(medie): 12 nye medie-metadatafelter + RLS-gate på media-fakta

Changelog:
- 2026-08-06 Medie-metadata-udvidelse (`changelog.md:1891`)
- 2026-08-06 Menneskegodkendte 1939-valg kan efterforankres fail-closed (`changelog.md:1918`)
- 2026-08-08 Grænsekontrol fase 1 + 1939-matchningen færdiggjort (`changelog.md:4429`)
- 2026-08-09 Grænsekontrollen som én tekst frem for 446 kasser (`changelog.md:1858`)

## 2026-U33 (uge fra 2026-08-10) — 30 commits

Commits pr. scope: docs 11, feat 10, fix 3, test 3, 1939 3

Changelog:
- 2026-08-10 Hele 1939-bogen gennemgået i tekstfladen (`changelog.md:1823`)

## 2026-U34 (uge fra 2026-08-17) — 282 commits

Commits pr. scope: 1939 216, docs 29, identity 15, c3 14, plan 4, db 3, db-state 1

Changelog:
- 2026-08-18 Afgrænset 1939 v50-production-writer kørt i prod: publikation + cutover (`changelog.md:1790`)
- 2026-08-18 Fase A: fuldt kilderegnskab i prod — 592/592 records forankretaften) (`changelog.md:1768`)
- 2026-08-19 Fase B: 551 biografier erstattet med evidensbaseret, renset tekst (`changelog.md:1730`)
- 2026-08-19 Fase C0: de 41 »ægte nye« records gennemgået — afventer afgørelser (`changelog.md:1693`)
- 2026-08-19 Fase D1: 68 personer publiceret i prod (`changelog.md:1667`)
- 2026-08-20 Fase D2 UDFØRT i prod — 21 ægtefæller publiceret (`changelog.md:1455`)
- 2026-08-20 Fase D2: Task 1+2 bygget, reviewet og rehearsal-kørt (`changelog.md:1490`)
- 2026-08-20 Person 975 pensioneret + fund: `red_slet_person` er brudt (`changelog.md:1647`)
- 2026-08-20 Sletnings-rutinen hærdet efter dobbelt review (`changelog.md:1581`)
- 2026-08-20 `red_slet_person` DEPLOYET til prod og verificeret (`changelog.md:1540`)
- 2026-08-20 `red_slet_person` rettet — bindinger og medlemskaber ryddes nu (`changelog.md:1619`)
- 2026-08-21 C0's efterkørsel UDFØRT i prod — ni record-koblinger (`changelog.md:1397`)
- 2026-08-22 Helhedsvurdering af genimporten + C3 apply-plan revideret (`changelog.md:1343`)

## 2026-U35 (uge fra 2026-08-24) — 39 commits

Commits pr. scope: genimport 10, db 9, docs 8, fix 3, web 3, evidens 1, test 1, mobile 1, … (+3 scopes)

Changelog:
- 2026-08-25 Bindende styringsgrundlag for evidensbaseret genimport indført (`changelog.md:1327`)

## 2026-U36 (uge fra 2026-08-31) — 143 commits

Commits pr. scope: genimport 48, test 30, fix 21, db 15, docs 15, prod 4, decisions 4, feat 3, … (+2 scopes)

Mergede PR'er:
- 2026-09-04 #167 feat(genimport): 149a — 2018-20 kilderegnskab gennem den generelle writer (#149)
- 2026-09-05 #168 fix(genimport): cutover-postverify følger v2-ACL, publiceringspolitik og kanonisk nøgleorden
- 2026-09-06 #169 docs(prod): GO 2-4 — #152-cutover, 149a og 149b anvendt i prod 2026-09-06
- 2026-09-06 #170 docs(genimport): fase-gate-runbook og #156-rapport fra #165, C0-reviewark hash-bundet
- 2026-09-06 #171 docs(genimport): status.md — næste tilladte arbejde er roadmap-trin 4 (#147/#148)

Changelog:
- 2026-09-03 149a: 2018-20 kilderegnskab bygget og bevist mod bogen, ægte rehearsal blokeret (`changelog.md:1290`)
- 2026-09-04 149b: legacy-migration til narrativ-binding bygget og integreret ende-til-ende (`changelog.md:1222`)
- 2026-09-05 GO 1: DB-migration main → prod (149b-forberedelse) (`changelog.md:1205`)
- 2026-09-06 GO 2: #152-cutover i prod (kontraktversion 1 → 2) (`changelog.md:1190`)
- 2026-09-06 GO 3: 149a kilderegnskab for 2018-20 anvendt i prod (`changelog.md:1177`)
- 2026-09-06 GO 4: 149b legacy-migration anvendt i prod — 2018-20 er kildebundet (`changelog.md:1154`)
- 2026-09-06 Roadmap-trin 4 planlagt: fortolkningskæde og klausulgranularitet (#147/#148) (`changelog.md:1141`)

## 2026-U37 (uge fra 2026-09-07) — 82 commits

Commits pr. scope: evidens 32, genimport 22, db 20, docs 4, test 2, changelog 2

Mergede PR'er:
- 2026-09-10 #172 docs(genimport): roadmap-trin 4 — spec og planer 4.1a-4.2 (#147/#148)
- 2026-09-10 #173 feat(evidens): klausullagets skema — trin 4 dagsværk 4.1a (#148)
- 2026-09-10 #174 feat(evidens): deterministisk klausul-segmentering — trin 4 dagsværk 4.1b (#148)
- 2026-09-10 #175 feat(evidens): writer-operationen clause_evidence — trin 4 dagsværk 4.1c (#148)
- 2026-09-11 #176 feat(evidens): ét prædikat-navnerum for fortolkningslaget (#147 4.2)
- 2026-09-11 #177 fix(test): record-key-testen målte tilfældet, ikke invarianten
- 2026-09-11 #178 docs: trin 4's dagsværk 4.1a-4.2 er merget — status, beslutning og changelog
- 2026-09-11 #179 docs(genimport): forbrugsproben til 4.3a lukker 4.3's stopbetingelse (#147)
- 2026-09-11 #180 docs(genimport): plan for dagsværk 4.3a — runner, cache, udelukkelsesliste (#147)
- 2026-09-12 #181 feat(evidens): claim-kontrakt + isolationsgate — 4.3a Task 1 og 2 (#147)
- 2026-09-12 #182 feat(evidens): trin 4 dagsværk 4.3a — gate, claim-kontrakt, runner, prompt-binding (#147)
- 2026-09-12 #183 feat(evidens): eligibility-ledger + runneren kørt ende til ende (#147 4.3a Task 5+6)
- 2026-09-12 #184 docs(genimport): plan for dagsværk 4.3b — første kald mod rigtige data (#147)
- 2026-09-12 #185 fix(evidens): luk hul i eligibility-værnets inputbinding (#147)
- 2026-09-13 #186 feat(evidens): dagsværk 4.3b — modellen kan læse bogen (#147)
- 2026-09-13 #187 docs(genimport): plan for dagsværk 4.4 — proposed-ingest (#147)
- 2026-09-13 #188 fix(evidens): record_key ind i cache-nøglen — tre kollisioner i data (#147)
- 2026-09-13 #190 docs(genimport): plan 4.4 omskrevet fra bunden + rettet fejldiagnose i 4.3b (#147)

Changelog:
- 2026-09-10 Trin 4, dagsværk 4.1a: klausullagets skema implementeret (#148) (`changelog.md:1073`)
- 2026-09-10 Trin 4, dagsværk 4.1b: deterministisk klausul-segmentering (#148) (`changelog.md:1029`)
- 2026-09-10 Trin 4, dagsværk 4.1c: writer-operationen `clause_evidence` (#148) (`changelog.md:985`)
- 2026-09-10 Trin 4, dagsværk 4.2: ét prædikat-navnerum (#147) (`changelog.md:939`)
- 2026-09-11 Flaky record-key-test rettet (#177) (`changelog.md:920`)
- 2026-09-11 Trin 4: forbrugsproben til 4.3a lukker 4.3's stopbetingelse (#147) (`changelog.md:875`)
- 2026-09-12 Trin 4, dagsværk 4.3a: runneren er kørt ende til ende (#147) (`changelog.md:839`)
- 2026-09-13 Trin 4, dagsværk 4.3b: modellen kan læse bogen (#147) (`changelog.md:781`)

## 2026-U38 (uge fra 2026-09-14) — 18 commits

Commits pr. scope: docs 5, rls 4, genimport 2, runbook 2, evidens 2, feed 1, fix 1, db 1

Mergede PR'er:
- 2026-09-14 #191 feat(db): 4.4 Task 0-3 — writer-operationen interpretation_proposal (#147)
- 2026-09-15 #192 feat(evidens): 4.4 proposed-ingest — builder, R-klient og rigtig kørsel (#147)
- 2026-09-15 #193 docs(genimport): afstem status efter merge af 4.4 (#147)
- 2026-09-17 #194 docs: trin 4's skema og writere er i prod — ingen data (#147/#148)
- 2026-09-17 #197 feat(evidens): udgaveneutral klausul-projektion til afstemning af 4.1c (#195)
- 2026-09-18 #199 docs(runbook): prod-procedure for 4.1c's klausulkørsel, øvet og hærdet (#148)
- 2026-09-18 #200 docs(runbook): tre rettelser fundet ved rehearsal mod den rigtige prod-backup (#148)
- 2026-09-18 #201 docs(genimport): klausulerne er skrevet i prod (4.1c, #148)
- 2026-09-19 #202 fix(rls): luk anon-adgang til family_offentlig og fire gate-funktioner
- 2026-09-20 #203 docs: sessionsafslutning 19/9 — oprydningsfejl omgjort, arbejdsudlæg arkiveret
- 2026-09-20 #204 fix(rls): medie-indkapsling — luk de to sidste anon-kaldbare gate-funktioner
- 2026-09-20 #205 docs: medie-indkapslingen er anvendt i prod
- 2026-09-20 #206 fix(rls): rettighedsgaten — medie-tilknyttet indhold følger mediets egen synlighed
- 2026-09-20 #207 docs: rettighedsgaten er anvendt i prod — medie-fladen er færdig
- 2026-09-20 #208 fix: #198-oprydning + slut-vagt for red_*-fladen
- 2026-09-20 #209 fix(rls): vagten var versions-blind og ensidig — tre rettelser efter Codex-review
- 2026-09-20 #210 feat(feed): billeder i naturlig bredde med fast højde
- 2026-09-20 #211 docs: sessionsafslutning 20/9 — sikkerhedsfladen lukket

Changelog:
- 2026-09-14 Trin 4, dagsværk 4.4: forslagene er i databasen (#147) (`changelog.md:701`)
- 2026-09-17 Klausul-projektion: udgaveneutralt delta-tjek til 4.1c (#195) (`changelog.md:636`)
- 2026-09-17 Trin 4 i prod: skema og writere, ingen data (#147/#148) (`changelog.md:657`)
- 2026-09-18 4.1c: klausulerne er skrevet i prod (#148) (`changelog.md:614`)
- 2026-09-19 anon-hærdning: familie-oraklet lukket i prod (`changelog.md:579`)
- 2026-09-19 oprydning gik galt, blev omgjort; arbejdsudlæg arkiveret (`changelog.md:543`)
- 2026-09-20 medie-indkapsling: de to sidste anon-orakler lukket i prod (`changelog.md:486`)
- 2026-09-20 restpunkterne fra sikkerhedsgennemgangen lukket (#198, #208, #209) (`changelog.md:385`)
- 2026-09-20 rettighedsgaten: medie-tilknyttet indhold følger mediets egen synlighed (`changelog.md:426`)

## 2026-U39 (uge fra 2026-09-21) — 11 commits

Commits pr. scope: 147 6, 196 2, klausuler 1, reviews 1, ci 1

Mergede PR'er:
- 2026-09-23 #212 feat(196): fortolkningsforslag-projektion og comparator (prod-gate-bevis, ingen prod)
- 2026-09-23 #213 ci: færre Actions-minutter — kun PR-kørsler, 12 → 7 jobs
- 2026-09-23 #214 fix(196): fire review-minors — bytea_output, CI-logs, input-hash, preview/principal-binding
- 2026-09-24 #215 docs(147): 4.4 prod-wrapper — GO-pakke færdig, prod-kørsel parkeret
- 2026-09-27 #216 feat(147): 4.5-pilot — afgørelse, binding og dom for 2018-20
- 2026-09-27 #217 feat(147): kontrolmodellen — uoverensstemmelser og stikprøve i stedet for fulde afgørelsesark
- 2026-09-27 #218 docs(reviews): helhedsreview 35 — genimporten 1/8-25/9
- 2026-09-27 #219 fix(147): klausulsættet i runnerens cache-nøgle + omsegmentering før 4.4 besluttet (review 35 P3/P4)
- 2026-09-27 #220 fix(klausuler): profil daa-2018-20-v2 — romertal og forkortelser splitter ikke sætninger (#189, review 35 P3)
- 2026-09-27 #221 docs(147): spec — omsegmentering af klausulsæt + S4 (review 35)
- 2026-09-27 #222 feat(147): omsegmentering af klausuler (clause_revision) + S4

Changelog:
- 2026-09-26 4.5-piloten gennemført i restoren: kvaliteten holder, afgørelsesmodellen ikke (#147) (`changelog.md:368`)
- 2026-09-27 klausulerne segmenteres om før 4.4; runnerens cache kender nu klausulsættet (#147, review 35 P3/P4) (`changelog.md:344`)
- 2026-09-27 kontrolmodellen bygget og kørt: samme 43 bindinger med 26 kort i stedet for 243 (#147) (`changelog.md:354`)
- 2026-09-27 omsegmentering bygget og øvet mod prod-dump: 51 poster, fortrydelse uden restore (#147, review 35 P3/S4) (`changelog.md:329`)

## 2026-U40 (uge fra 2026-09-28) — 9 commits

Commits pr. scope: 147 9

Mergede PR'er:
- 2026-09-28 #223 docs(147): omsegmentering øvet mod prod-dump (REHEARSAL_OK) + prod-runbook
- 2026-09-28 #224 docs(147): prod-runbook for omsegmentering peger på prod-pakken (R1+R2-rettet, stand-in-testet)
- 2026-09-28 #225 docs(147): omsegmentering kørt i prod 2026-09-28 — database-state §9, status, changelog, runbook
- 2026-09-28 #226 fix(147): P1 — runner-gaten lukket før piloten om (genbinding af 4.4) + plan
- 2026-10-01 #227 docs(147): 4.4 genbundet — piloten kørt om på de omsegmenterede klausuler
- 2026-10-01 #228 feat(147): udgaveneutral udvalgsbygger — alle eligible poster i bundter
- 2026-10-02 #229 fix(147): proposal-byggeren sorterer principal-claims på poster uden persona fra
- 2026-10-03 #230 docs(147): hele 2018-20 kørt gennem fortolkningskæden — rapport + to beslutninger
- 2026-10-04 #231 feat(147): overførselspakke, nøglede digests og lokal genafspilning (plan A)

Changelog:
- 2026-09-28 4.4 genbundet: piloten kørt om på de omsegmenterede klausuler (#147) (`changelog.md:303`)
- 2026-09-28 omsegmentering kørt i prod: 51 poster, `match` (#147, review 35 P3/S4) (`changelog.md:314`)
- 2026-10-03 hele 2018-20 gennem fortolkningskæden i én base (#147) (`changelog.md:290`)

## 2026-U41 (uge fra 2026-10-05) — 7 commits

Commits pr. scope: 151 4, 147 2, roadmap 1

Mergede PR'er:
- 2026-10-05 #232 docs(147): plan B — prod-overførslen af 2018-20 klar til GO (ceremoni, runbook, review-rettelser)
- 2026-10-05 #233 docs(147): 2018-20's fortolkningskæde overført til prod (VERIFY_OK)
- 2026-10-05 #234 docs(roadmap): trin 4 afsluttet for 2018-20, trin 5 aktiveret (5a først)
- 2026-10-05 #235 docs(151): spec og plan for trin 5a — én identitetsvej med kandidater og spor
- 2026-10-05 #236 feat(151): trin 5a — én identitetsvej med kandidater, kvittering og spor
- 2026-10-11 #237 feat(151): trin 5b del 1 — ægtefællers relationspersonas og maskinel bekræftelse efter blind kontrol
- 2026-10-11 #238 docs(151): færdigbevis og status for trin 5b del 1

Changelog:
- 2026-10-05 2018-20's fortolkningskæde overført til prod (#147) (`changelog.md:266`)
- 2026-10-05 prod-overførslen af 2018-20 er klar til GO (#147, plan B) (`changelog.md:280`)
- 2026-10-05 trin 5a: én identitetsvej, bevist i restore (#151) (`changelog.md:255`)
- 2026-10-11 trin 5b del 1: ægtefællers personas og maskinel bekræftelse, bevist i restore (#151) (`changelog.md:244`)
- 2026-10-11 trin 5b del 2a: afgjorte ægteskaber og forældre bundet, kilden vist (#151) (`changelog.md:233`)

## 2026-U42 (uge fra 2026-10-12) — 4 commits

Commits pr. scope: (uden type) 2, 151 2

Mergede PR'er:
- 2026-10-16 #239 Trin 5b del 2a: bind afgjorte ægteskaber og forældre, vis kilden (#151)
- 2026-10-17 #241 feat(151): trin 5b del 2b-i — genbinding, undtagelsesark for ægtefæller og køen afgjort
- 2026-10-17 #242 fix(151): arkværktøjerne låser standard_conforming_strings i deres SQL
- 2026-10-18 #243 Trin 5b del 2b-ii: nye afdøde ægtefæller og klausul-disposition (#151)

Changelog:
- 2026-10-13 trin 5b del 2b-i: genbinding, undtagelsesark for ægtefæller og køen afgjort (#151) (`changelog.md:220`)
- 2026-10-18 trin 5b del 2b-ii: nye afdøde ægtefæller, de 14 ægteskaber og klausul-dispositionen (#151) (`changelog.md:206`)

## 2026-U43 (uge fra 2026-10-19) — 15 commits

Commits pr. scope: 151 14, 244 1

Mergede PR'er:
- 2026-10-20 #245 feat(151): 2b-ii runde 2 — navneregel v3 binder 9 af de 12 ægteskaber (restore)
- 2026-10-20 #246 docs(151): P-linjens forkerte ægteskabsfortolkning afvist i bevisbasen
- 2026-10-20 #247 feat(151): 2b-iii — børneflokkene binder til familien (restore)
- 2026-10-20 #249 fix(244): ægteskabsnummeret efter skriverens vindue; 4 numre rettet på ark
- 2026-10-21 #250 docs(151): spec for prod-overførsel af trin 5a+5b (2018-20)
- 2026-10-21 #251 feat(151): id'er af indholdet — forudsætning for 5a+5b-overførslen
- 2026-10-21 #252 docs(151): plan A for 5a+5b-overførslen — fase 0 og DDL-ceremonien (GO 1)
- 2026-10-22 #253 docs(151): runbook for DDL-ceremonien efter privat review af scripts
- 2026-10-22 #254 docs(151): 5a+5b's DDL i prod (GO 1)
- 2026-10-23 #255 feat(151): plan B1 — værktøj til 5a+5b-data-ceremonien
- 2026-10-23 #256 docs(151): plan B2 + indholdskontrol og forudfyldning til 5a+5b-overførslen (G0)
- 2026-10-24 #257 fix(151): svaroverførslen sammenligner ægteskabsarkenes S med den bundne person
- 2026-10-25 #258 docs(151): runbook for data-ceremonien (GO 2) og beslutninger
- 2026-10-25 #259 docs(151): 5a+5b's data i prod (GO 2)
- 2026-10-25 #260 fix(151): dubletreglen — familiens post vinder, uafklarede dubletter venter på redaktøren

Changelog:
- 2026-10-20 #244: ægteskabsnumrene efter skriverens vindue; 4 numre rettet på ark (#151) (`changelog.md:137`)
- 2026-10-20 trin 5b del 2b-ii runde 2: navneregel v3 over de 12 `U`-ægteskaber (#151) (`changelog.md:180`)
- 2026-10-20 trin 5b del 2b-iii: børneflokkene binder til familien (#151) (`changelog.md:154`)
- 2026-10-20 trin 5b: P-linjens forkerte ægteskabsfortolkning afvist i bevisbasen (#151) (`changelog.md:176`)
- 2026-10-21 #151: DDL-ceremonien for 5a+5b-overførslen (plan A) (`changelog.md:108`)
- 2026-10-21 #151: id'er af indholdet (forudsætning for overførslen af 5a+5b) (`changelog.md:120`)
- 2026-10-22 #151: 5a+5b's DDL i prod (GO 1) (`changelog.md:93`)
- 2026-10-22 #151: værktøj til data-ceremonien for 5a+5b (plan B1) (`changelog.md:80`)
- 2026-10-25 #151: 5a+5b's data i prod (GO 2) (`changelog.md:64`)

## 2026-U44 (uge fra 2026-10-26) — 9 commits

Commits pr. scope: 248 4, 151 2, 240 2, 150 1

Mergede PR'er:
- 2026-10-26 #261 fix(240): saml de 5 dobbeltfamilier og bind deres 7 ægteskaber (+ dubletreglens DDL i prod)
- 2026-10-26 #262 docs(240): dubletreglen og dobbeltfamilierne i prod
- 2026-10-26 #263 fix(151): ret GO 2's ene dubletægteskab efter den nye dubletregel
- 2026-10-26 #264 docs(151): GO 2's ene dubletægteskab rettet i prod
- 2026-10-26 #265 fix(248): afgør de to navnefælle-ægtefæller igen (skridt 1)
- 2026-10-26 #266 docs(248): skridt 1 kørt i prod — to navnefælle-ægtefæller afgjort igen
- 2026-10-26 #267 feat(248): genåbning ved familieskift (rute A)
- 2026-10-26 #268 docs(248): rute A kørt i prod
- 2026-10-27 #269 feat(150): trin 5c-1 — placement og membership for 2018-20

Changelog:
- 2026-10-26 #240 og dubletreglen i prod (`changelog.md:46`)
- 2026-10-26 #248 rute A i prod: genåbning ved familieskift (DDL + data) (`changelog.md:3`)
- 2026-10-26 #248 skridt 1 i prod: to navnefælle-ægtefæller afgjort igen (`changelog.md:18`)
- 2026-10-26 GO 2's ene dubletægteskab rettet i prod (`changelog.md:34`)

