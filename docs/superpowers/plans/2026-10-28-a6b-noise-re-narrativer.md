# A6b: positionsbestemt `NOISE_RE` og 10 narrativrevisioner — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De 12 prosalinjer, som `NOISE_RE` fjerner midt på en side, kommer tilbage i læserens tekst for de 10 publicerede
2018-20-narrativer, de rammer. Segmenteringen får en ny, versioneret støjregel, som trin 6 kan bygge kildetekstrettelsen på.

**Architecture:** `segment.py` får en støjregel pr. udgaveprofil: `'anywhere'` (v1, uændret og reproducerbar) og
`'page_header'` (v2: kun første ikke-tomme linje efter `### PAGE`). En builder sammenligner v1 og v2 over den rå tekst og
skriver et privat revisionsmanifest (kun ændrede poster, kun rene indsættelser). En ceremoni-SQL anvender manifestet med
den eksisterende redaktør-RPC `red_revider_publiceret_person_narrative_record` i én transaktion; fortrydelse er samme
script i modsat retning. Kildetekst (helpost) og klausuler røres ikke: det er et navngivet hul til trin 6.

**Tech Stack:** Python 3.11 (pytest 8.4.2), PostgreSQL 17 / Supabase, psql, zsh-runner i `~/.private/`.

**Spec:** Beslutning `docs/decisions.md` 2026-10-27 »de 13 `NOISE_RE`-linjer« + den nye beslutningspost fra Task 0.
Grundlag: review-fund 1d.3a-03 (`docs/reviews/2026-10-27-trin-1-5/afvejning-codex.md:242-258`).

## Adgangskrav (roadmap)

1. **Roadmapmål:** gate før trin 6 (status.md, gates-tabellens A6b).
2. **Værdikædeled:** narrativpublicering (offentlig læseprojektion); segmenteringens grænse-/støjregel.
3. **Leverancetype:** generel (versioneret støjregel i fælles segmentering) + 2018-20-profil (`2018-20-v2`) + engangsrettelse af prod-data.
4. **Værdi:** læseren ser den fulde trykte tekst for 10 afdøde personer; trin 6 arver en dokumenteret støjregel i stedet for en uafklaret.
5. **Færdigbevis:** CI grøn med positionstestene; prod-ceremonien giver `A6B_OK retning=frem revideret=10 ubundet=1 change_sets=10`, målingen før/efter viser 10 narrativer flyttet fra gammel til ny tekst-hash, uændret `rest` og `maal_oevrigt` og de øvede tilvækster; fortrydelsen (frem → tilbage → frem) er øvet gennem runneren på en stand-in.
6. **Erstatter:** ingen parallel vej; NOISE_RE's »overalt«-regel forbliver kun som v1 for at gamle manifester kan reproduceres.
7. **Review-budget:** to Codex-runder (`gpt-6.1-sol`, adversarial): plan (gjort 2026-10-28, NO-GO → rettet, se »Review-runde 1«) og diff før prod; Opus afvejer fundene. Overskridelse = én linje i `docs/decisions.md`.

## Review-runde 1 (Codex på planen, 2026-10-28)

NO-GO med 6 fund; Opus' afvejning: (1) audit-kontekst mellem RPC-kald — nødvendig, rettet i Task 3 (SQL-CI-test afvist: engangsscript, øvelsen kører alle 10 kald på rigtige data); (2) runnerens førmåling blokerede fortrydelse — nødvendig, Task 4; (3) ubundet kun som antal — forenklet til præcise nøglemængder under lås, Task 3; (4) rest-hash for smal og write-set ufuldstændigt — nødvendig, Task 3; (5) B1-genkontrol ved apply — nødvendig, Task 4; (6) v1-reproducerbarhed bredere — forenklet til main-mod-ny for segmentering, projektion og header-manifest + `significant()`-test, Task 1.

## Review-runde 2 (Codex på diffen, 2026-10-28)

NO-GO med 3 fund (P2); Opus' afvejning: (1) mængdetjekket læste bindingerne før låsen, og den ubundne post blev aldrig
låst — nødvendig, rettet: alle manifestets source records låses `FOR UPDATE` først, bindingerne genlæses under låsene
(prøvet: en `FOR KEY SHARE` på III-129 i en anden session giver lock timeout); (2) GO-koden bandt hverken commit'en eller
`clause_evidence_target_identity.sql`, og forbindelsen blev åbnet før GO-tjekket — nødvendig, rettet i runneren;
(3) en eksisterende 0644-manifestfil blev skrevet i før chmod — forenklet: ny 0600-fil + atomisk erstatning, symlink
afvises. Codex fandt v1 uændret (729 syntetiske kombinationer mod `main`) og ingen umålte skriveeffekter.

## Global Constraints

- PII (invariant 8): `work/raw_full.txt`, manifestet og alt med postttekst ligger i `work/a6b/` (gitignoreret) eller `~/.private/`; ingen tekst i stdout, chat, commits eller testfixtures. Scripts udskriver kun antal, nøgler og hashes. Probes sender stdout og stderr til fil.
- Profilen `'2018-20'` og `project_rendition`'s default skal give **byte-identisk** output som før (149a-, klausul- og header-manifester skal kunne genbygges). `build_source_evidence_rendition.py:137` kalder `segment.py <fil>` uden `--udgave`, så CLI-default forbliver `'2018-20'`.
- Header-builderen (`build_header_manifest.py:109`) bliver på v1 i denne leverance.
- Prod skrives kun fra projektejerens shell (`! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 23-a6b.sh …`); `maal` før `go`; GO-koden binder repo-sha, manifest-sha og SQL-sha.
- Ingen DDL. `db-verify.sql` køres aldrig mod prod.
- Commits: Conventional Commits på dansk, én pr. task, kun taskens filer.

## Review Focus

1. **Sidehoved efter blank linje:** `### PAGE n ###`, blank linje, `von REVENTLOW` skal stadig springes over i v2 (87 af de 100 træf ser sådan ud). Testes i Task 1.
2. **Støjlinje som allerførste linje i filen (ingen PAGE før):** v2 må ikke kalde den sidehoved. Testes i Task 1.
3. **`significant()`'s lookahead:** romertal-/LINJE-afgørelsen ser frem over støj; i v2 er en midtsidelinje betydende. Postgrænserne må ikke flytte sig (målt: 591 poster, samme nøgler). Testes i Task 2's grænsevagt.
4. **Narrativ redigeret efter import:** ceremonien må kun revidere, når prods `text_sha256` = manifestets `old_sha256`; ellers stop. Øves i Task 3 Step 4 (manipuleret stand-in).
5. **Gentagen kørsel:** anden `apply` efter succes skal stoppe rent (`A6B_PRE_ALLEREDE_ANVENDT`), ikke revidere igen. Øves i Task 3 Step 3.
6. **Flere RPC-kald i én transaktion:** `mutate_person_narrative_record` afviser et allerede sat `app.change_set_id` (`schema.sql:13921`, `NARRATIVE_RECORD_FOREIGN_CHANGE_SET`); hvert kald skal have ryddet konteksten først, som `fix_150_placement.sql:271`. Øves i Task 3 Step 3 (10 kald, 10 forskellige change_sets).

---

### Task 0: Beslutningspost og status

**Files:**
- Modify: `docs/decisions.md` (ny post øverst, over 2026-10-28-posten)
- Modify: `docs/evidensbaseret-genimport/status.md` (A6b-rækken)
- Create: `docs/superpowers/plans/2026-10-28-a6b-noise-re-narrativer.md` (denne fil)

- [ ] **Step 1:** Skriv posten `## BESLUTTET: A6b afgrænses til narrativerne; kildetekst og klausuler til trin 6 (2026-10-28)` med: baggrund (ingen skrivevej for helpost-/occurrence-tekst; `clause_revision` kan ikke tilføje tekst og afvises af 74 fortolkninger på 9 af posterne; målt på genskabt prod-kopi 2026-10-28), besluttet (v2-regel + 10 narrativrevisioner nu; III-129 er ubundet, årsag til `unresolved_text` ukendt, ingen rettelsesvej; helpost og klausuler for de 11 poster mangler linjerne til trin 6's kildetekstrevision med forældelse af afhængige fortolkninger), konsekvens (efter A6b er `narrative.tekst` ≠ helpostens `verbatim_text` for 10 poster — kendt og navngivet; en genkørsel af 149b-komparatoren vil vise dem). Henvis til denne plan.
  Tilføj også én linje om review-budgettet: to Codex-runder i stedet for én (planen fik NO-GO i runde 1; B13).
- [ ] **Step 2:** A6b-rækken i status: »afgrænset 2026-10-28 (decisions): narrativer nu, kildetekst/klausuler i trin 6; plan …«.
- [ ] **Step 3: Commit** `docs(a6b): afgræns A6b til narrativerne; plan`

### Task 1: Versioneret støjregel i `segment.py`

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/segment.py` (`NOISE_RE` :40, `significant` :152-160, `_segment_2018_20` :186-258, `UDGAVE_PROFILER` :911-920, CLI :1044-1058)
- Modify: `.claude/skills/daa-extract/scripts/build_source_evidence_manifest.py:59-79`
- Modify: `.github/workflows/ci.yml:142` (pytest-listen)
- Test: `.claude/skills/daa-extract/scripts/test_segment.py`, `.claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py`

**Interfaces:**
- Produces: `segment.NOISE_RULES = ('anywhere', 'page_header')`; `segment.is_noise(lines: list[str], i: int, rule: str) -> bool`; `segment.significant(lines, k, rule='anywhere')`; profil `UDGAVE_PROFILER['2018-20-v2']` = `'2018-20'` med `'noise_rule': 'page_header'` (og `'2018-20'` får `'noise_rule': 'anywhere'`); CLI `segment.py raw.txt --udgave 2018-20-v2`; `build_source_evidence_manifest.project_rendition(text: str, noise_rule: str = 'anywhere') -> tuple[str, list[int]]`.

- [ ] **Step 1: Skriv de fejlende tests** i `test_segment.py` (ny klasse `TestStoejregel`), alle på opdigtet tekst (navne som »Testesen«, ingen rigtige poster):
  - `test_v1_springer_midtsidelinje_over`: PAGE, post `1.  Anders Testesen …`, linjen `von Reventlow, der ejede Testgaard.` midt på siden, mere prosa → `'Testgaard' not in posts[0]['raw_text']` med `udgave=None`.
  - `test_v2_bevarer_midtsidelinje`: samme tekst, `udgave='2018-20-v2'` → `'von Reventlow, der ejede Testgaard.' in posts[0]['raw_text']`.
  - `test_v2_springer_sidehoved_over_ogsaa_efter_blank_linje`: post over to sider; `### PAGE 12 ###`, blank linje, `von REVENTLOW` → linjen ikke i `raw_text` under v2.
  - `test_v2_stoej_foer_foerste_page_er_ikke_sidehoved`: `Ridder Testesens sønner` som første linje i filen (ingen PAGE før) og efterfulgt af en post → `is_noise(lines, 0, 'page_header') is False`, og under v2 er linjen ikke i nogen posts `raw_text` (den står før første post).
  - `test_profilerne_er_ens_bortset_fra_stoejregel`: `{k: v for k, v in P['2018-20-v2'].items() if k != 'noise_rule'} == {… '2018-20' …}`.
  - `test_ukendt_stoejregel_afvises`: `is_noise(['x'], 0, 'overalt')` → `ValueError`.
  - `test_significant_ser_forbi_sidehoved_men_ikke_forbi_midtsidelinje`: `significant(lines, k, 'page_header')` springer en støjlinje lige efter PAGE over, men returnerer indekset for en støjlinje midt på siden; `significant(lines, k)` (v1) springer begge over.
  I `test_build_source_evidence_manifest.py`: `test_project_rendition_v2_bevarer_midtsidelinje` (projektionen indeholder linjen med `noise_rule='page_header'`, ikke med default) og `test_project_rendition_default_fastlaast` (default på en lille fast tekst med PAGE, blank, støj midt på siden og mellemrum giver en fastlåst forventet tekst **og** offsetliste, skrevet som literals i testen).
- [ ] **Step 2: Kør og se dem fejle:** `uv run --with pytest==8.4.2 pytest .claude/skills/daa-extract/scripts/test_segment.py .claude/skills/daa-extract/scripts/test_build_source_evidence_manifest.py -q` → FAIL (`AttributeError: is_noise` / ukendt udgave).
- [ ] **Step 3: Implementér.** `is_noise`: `NOISE_RE.match(lines[i])` og, for `'page_header'`, at der findes en `PAGE_RE`-linje før `i` med kun blanke linjer imellem. `_segment_2018_20` og `significant` bruger `is_noise(lines, i, profile['noise_rule'])`. `project_rendition` splitter teksten i linjer og kalder `segment.is_noise(lines, idx, noise_rule)`. CLI accepterer `--udgave 2018-20-v2` i 4-argumentsformen (ikke med `--emit-evidence-ledger`). Kommentar ved `NOISE_RE`: hvorfor v2 findes (decisions 2026-10-27/-28) og at v1 er frosset for reproducerbarhed.
- [ ] **Step 4: Kør alle segment- og builder-tests:** samme kommando + `test_segment_slaegtled.py test_segment_1939.py test_build_header_manifest.py test_build_clause_evidence_manifest.py` → alle PASS.
- [ ] **Step 5: CI.** Tilføj `test_segment.py test_segment_slaegtled.py test_segment_1939.py` til pytest-listen i `ci.yml:142`.
- [ ] **Step 6: Reproducerbarhed på rigtig tekst (PII-sikkert):** `git show main:.claude/skills/daa-extract/scripts/segment.py > work/a6b/segment_main.py`; kør `PYTHONPATH=.claude/skills/daa-extract/scripts python3 work/a6b/segment_main.py work/raw_full.txt > work/a6b/v1-main.json 2>&1` og `python3 .claude/skills/daa-extract/scripts/segment.py work/raw_full.txt > work/a6b/v1-ny.json 2>&1` → `shasum -a 256` af de to filer er identiske. Gør det samme for `project_rendition` (main-versionen af `build_source_evidence_manifest.py` mod den nye; dump `json.dumps([tekst, offsets])` til fil) og for header-manifestet (`build_header_manifest.py` fra main mod ny, samme input som 5c-1) → identiske hashes. Udskriv kun hashes.
- [ ] **Step 7: Commit** `feat(segment): positionsbestemt støjregel som profil 2018-20-v2`

### Task 2: Revisionsmanifest-builder

**Files:**
- Create: `.claude/skills/daa-extract/scripts/build_narrative_revision_manifest.py`
- Test: `.claude/skills/daa-extract/scripts/test_build_narrative_revision_manifest.py` (+ CI-listen `ci.yml:142`)

**Interfaces:**
- Consumes: `segment.UDGAVE_PROFILER`, profilernes `segmenter`.
- Produces: `build_revision_manifest(raw_text: str, fra: str, til: str, source_id: int) -> dict`; CLI `build_narrative_revision_manifest.py --raw <fil> --fra 2018-20 --til 2018-20-v2 --source-id 1 --out <fil>`. Manifest: `{"kind": "narrative_revision", "source_id", "fra", "til", "elements": [{"record_key", "old_text", "new_text", "old_sha256", "new_sha256", "inserted_tokens"}], "manifest_sha256"}`; elementer sorteret efter `record_key`; `manifest_sha256` = sha256 over kanonisk JSON (`sort_keys=True, separators=(',', ':'), ensure_ascii=False`) af manifestet uden feltet. `record_key` = `f"{linje}-{nr_label}"` (som `build_source_evidence_manifest.record_key_of`). Stdout: kun `NARRATIVE_REVISION_MANIFEST elements=<n> keys=<kommasepareret> sha=<sha>`.

- [ ] **Step 1: Fejlende tests** (opdigtet tekst): `test_kun_aendrede_poster_med_ren_indsaettelse` (to poster, én med midtsidelinje → ét element, `inserted_tokens` = linjens antal ord, `old_sha256` = sha af v1-`raw_text`); `test_graenseaendring_afvises` (monkeypatch en profil, så postantal/nøgler afviger → `ManifestError('NARRATIVE_REVISION_BOUNDARY_CHANGED')`); `test_andet_end_indsaettelse_afvises` (monkeypatch `til`-segmenteren til at fjerne et ord → `NARRATIVE_REVISION_NOT_PURE_INSERTION`); `test_manifest_sha_er_deterministisk`.
- [ ] **Step 2:** Kør → FAIL (modul findes ikke).
- [ ] **Step 3: Implementér.** Grænsevagt: samme nøgler i samme rækkefølge og alle felter undtagen `raw_text` ens. Ren indsættelse: `difflib.SequenceMatcher(None, old.split(' '), new.split(' '), autojunk=False).get_opcodes()` har kun `equal`/`insert`.
- [ ] **Step 4:** Kør → PASS. Tilføj filen til `ci.yml:142`.
- [ ] **Step 5: Rigtig tekst:** `mkdir -p work/a6b && python3 -I …/build_narrative_revision_manifest.py --raw work/raw_full.txt --fra 2018-20 --til 2018-20-v2 --source-id 1 --out work/a6b/manifest.json > work/a6b/build.out 2> work/a6b/build.err`; `cat work/a6b/build.out` → `elements=11 keys=I-11,I-17,I-18,I-32,I-33,I-44,I-84,I-89,I-9,III-129,III-37` (I-9 har to indsættelser). `chmod 600 work/a6b/manifest.json`.
- [ ] **Step 6: Commit** `feat(a6b): builder til narrativ-revisionsmanifest`

### Task 3: Måling og ceremoni-SQL

**Files:**
- Create: `.claude/skills/daa-extract/scripts/fix_a6b_maal.sql` (læse-kun)
- Create: `.claude/skills/daa-extract/scripts/fix_a6b_narrative_revision.sql`

**Interfaces:**
- Consumes: manifestet fra Task 2 (klientside: `\set m \`cat :'manifest_path'\``, som `fix_150_placement.sql:16`).
- Produces: `psql … -v manifest_path=… -f fix_a6b_maal.sql` → én linje `A6B_MAAL gammel=<n> ny=<n> ubundet=<n> andet=<n> rest=<sha16> maal_oevrigt=<sha16> events=<n> change_sets=<n> change_events=<n> mentions=<sha16>`; `psql … -v actor=<uuid> -v src=1 -v manifest_path=… -v manifest_sha=… -v go=… -v retning=frem|tilbage -v bundne=<kommasepareret nøglemængde> -v ubundne=III-129 -f fix_a6b_narrative_revision.sql` → `A6B_OK retning=<r> revideret=10 ubundet=1 change_sets=10`.

- [ ] **Step 1: `fix_a6b_maal.sql`** (`BEGIN READ ONLY … ROLLBACK`). For manifestets nøgler via `private.narrative_record_publication` → `narrative`: `gammel` = antal med `sha256(tekst)` = `old_sha256`, `ny` = antal = `new_sha256`, `ubundet` = nøgler uden publikation, `andet` = resten. `rest` = sha over `to_jsonb(n)` (hele rækken) for alle narrativer **uden for** målene, ordnet efter `id`. `maal_oevrigt` = sha over `to_jsonb(n) - 'tekst'` for de 10 mål (skal være uændret: kun teksten må ændre sig). `events`, `change_sets`, `change_events` = antal rækker i `private.narrative_publication_event`, `public.change_set`, `public.change_event`. `mentions` = sha over `text_mention`-rækkerne for de 10 måls `kilde_id` (triggeren `trg_mentions_narrative`, `schema.sql:8664`, genberegner dem; forventet ændring dokumenteres, ikke forbydes). Brug den portable hash over `to_jsonb(x)::text`, ikke `x::text` (locale-forskel macOS/Linux). Forventet før frem: `gammel=10 ny=0 ubundet=1 andet=0`.
- [ ] **Step 2: `fix_a6b_narrative_revision.sql`** i én transaktion efter `fix_150_placement.sql`'s mønster (`SET LOCAL statement_timeout`, `set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null`, så aktøren ikke ekkoes). Retning `frem` bruger (old→new), `tilbage` (new→old). **Forhåndsvagter** (`RAISE EXCEPTION`): `A6B_PRE_AUDIT_KONTEKST` (`app.change_set_id` er ikke tom ved indgang); `A6B_PRE_ROLLE` (aktøren har ikke `profiles.rolle='redaktion'`, jf. `schema.sql:5742`); `A6B_PRE_MANIFEST_SHA` (manifestets eget felt `manifest_sha256` ≠ `:manifest_sha`; runneren læser feltet med `jq`, og GO-koden binder filens sha); `A6B_PRE_MAENGDE` (mængden af bundne nøgler ≠ `:bundne`, eller mængden af ubundne ≠ `:ubundne` — mængder, ikke antal; læst efter `private.narrative_record_state(pid, src, rk, true)`, der tager låsen); `A6B_PRE_ALLEREDE_ANVENDT` (alle bundne står allerede på til-hash); `A6B_PRE_TEKST_DRIFT` (aktuel `text_sha256` ≠ fra-hash); `A6B_PRE_STATUS` (ikke `published`, eller `publish_revision` mangler i `allowed_actions`). **Skrivning:** klientdrevne sætninger via `\gexec`, én pr. post, hver af formen `SELECT set_config('app.change_set_id','',true), public.red_revider_publiceret_person_narrative_record(pid, src, rk, til_tekst, state_sha256)` under `SET LOCAL ROLE authenticated` (som `fix_150_placement.sql:271-276`); `RESET ROLE` bagefter. Teksten hentes fra temp-tabellen i sætningen, ikke indsat som literal i stdout. **Eftervagter:** `A6B_POST_STATUS` (`published`, ikke `stale_published`), `A6B_POST_TEKST` (`text_sha256` = til-hash), `A6B_POST_MAENGDE` (de reviderede nøgler = `:bundne`), `A6B_POST_EVENTS` (præcis 10 nye events, med 10 forskellige `change_set_id`). Til sidst `A6B_OK …` og `COMMIT`.
- [ ] **Step 3: Øv på en genskabt prod-kopi** (stand-in fra seneste dump, ICU, `ANALYZE` efter restore): maal → `gammel=10 ny=0 ubundet=1 andet=0`; apply frem → `A6B_OK retning=frem revideret=10 ubundet=1 change_sets=10`; maal → `gammel=0 ny=10`, samme `rest` og `maal_oevrigt`, `events`/`change_sets` +10, `change_events` +N (N noteres som forventet tal til prod); apply frem igen → `A6B_PRE_ALLEREDE_ANVENDT`; apply tilbage → OK; maal → `gammel=10 ny=0`, samme `rest`/`maal_oevrigt`, `mentions` = førværdien; apply frem → OK. Mål køretiden mod prods `statement_timeout` (2 min).
- [ ] **Step 4: Driftprøve:** på en ny stand-in: ret én af de 10 narrativers tekst direkte (som ejer), kør apply frem → `A6B_PRE_TEKST_DRIFT`, intet skrevet (maal uændret).
- [ ] **Step 5: Læserprøve:** på stand-in efter apply frem: den offentlige læser for én af personerne (som `anon`) returnerer narrativet med den nye tekst (kun længde og sha udskrives).
- [ ] **Step 6: Commit** `feat(a6b): måling og ceremoni-SQL til narrativrevisionerne`

### Task 4: Runner og runbook

**Files:**
- Create (privat, ikke i git): `~/.private/5ab-overfoersel/23-a6b.sh` (kopi af `22-trin-b.sh`'s skelet: `go`, `maal`, `dump`, `proeve`, `apply --jeg-mener-det --go X [--tilbage]`; ukendte argumenter afvises)
- Create: `docs/runbooks/a6b-narrativ-revision-prod.md`

- [ ] **Step 1: Runner.** `go [--tilbage]` binder repo-sha, retning og sha af manifest, `fix_a6b_narrative_revision.sql` og `fix_a6b_maal.sql`, og viser GO-koden. `dump` er B1-kæden fra `22-trin-b.sh` (pg_dump → sha → age → SFTP → hent → sammenlign → dekryptér). `apply --jeg-mener-det --go X [--tilbage]`: (a) B1 som første skridt — dumpets lokale sha = kvitteringens, og den eksterne `.age`-fils størrelse og sha (hentet igen) = kvitteringens; begge hashes skrives i ceremoniens log før skrivningen; (b) `maal` skal give retningens førværdier (frem: `gammel=10 ny=0 ubundet=1 andet=0`; tilbage: `gammel=0 ny=10 ubundet=1 andet=0`); (c) GO-koden skal være lavet til samme retning. stdout+stderr fra psql til private filer; kun `A6B_*`-linjer vises. Ukendte argumenter afvises.
- [ ] **Step 2: Fuld generalprøve på stand-in** med runneren (Stand-in-tilstand: `DAA_STANDIN_DB=…`, lokal SFTP-mappe): frem → tilbage → frem, hver gennem `maal`, `go`, `apply`, `maal`.
- [ ] **Step 3: Runbook** efter `docs/runbooks/review-trin-b-prod.md`'s afsnit: Hvad der skrives (ingen DDL; 10 `narrative.tekst`, 10 `narrative_publication_event`, 10 `change_set`, N `change_event` fra øvelsen, genberegnet `text_mention` for de 10 narrativer), Forløb (projektejerens shell, kommandoer + forventet sidste linje), Prøvet (dato, tal), Fortrydelse (`apply --tilbage`, øvet), Kendte følger (narrativ ≠ helpost for 10 poster indtil trin 6; III-129 urørt).
- [ ] **Step 4: Commit** `docs(runbook): A6b narrativrevision i prod` (kun runbooken).
- [ ] **Step 5: Review.** Codex-runde på plan + diff (`main..HEAD`), Opus afvejer; rettelser som egne commits.

### Task 5: Prod (projektejerens GO)

- [ ] **Step 1:** PR (draft) → CI grøn → projektejeren merger. Ceremonien kører fra `main`.
- [ ] **Step 2:** Projektejeren: `maal` → forventet `gammel=10 ny=0 ubundet=1 andet=0`; `go` → GO-kode; `dump`; `apply --jeg-mener-det --go <kode>` → `A6B_OK retning=frem revideret=10 ubundet=1 change_sets=10`; `maal` → `gammel=0 ny=10 ubundet=1 andet=0`, samme `rest` og `maal_oevrigt`, tilvækster som i øvelsen.
- [ ] **Step 3:** Docs: `docs/database-current-state.md` ny sektion (dump-sha, GO, tal), `status.md` (A6b gjort; narrativ ≠ helpost som kendt hul til trin 6), `docs/changelog.md`. Commit `docs(status): A6b i prod`.
