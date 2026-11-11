# Trin 6d-3: 1939's relationer, dobbelt ægtefælle og 1791 — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1939's ægteskaber og forældre bindes til familierne gennem 5b's eksisterende kæde, læseren viser kilden hos
den sammenfoldede person, den dobbelte ægtefælle forsvinder hvor projektejeren bekræfter det, og 1791 skjules.

**Architecture:**
- **Spor L (TS, ingen DB):** kildefiltrene for ægteskab, forælder og børn flyttes fra `DetailPanel.tsx:52-62` til
  `packages/core/src/familieKilder.ts` og slår modparten op kanonisk.
- **Spor R (DDL + scripts):** writerens profiler bliver data (`private.relation_persona_profile`); én tekstform-afhængig
  foldning bruges af ordvinduet, ægteskabsnummeret og udtrækket (SQL og Python-tvilling med fælles fixtures). Kæden
  (persona-batch → kandidatkørsel → kontrol → korroboration → afgørelse → binding; forældre ad 2a's vej) køres på kilde 3
  med parametriserede scripts.
- **Spor D og O (data):** `red_samme_som` pr. bekræftet kort og `red_set_privat(1791, true)` under én ceremoni før R.
- **Prod:** web-deploy af L → DDL-ceremoni → dataceremoni (D, O, R) gennem en privat runner; fortryd = restore fra
  dump før D, fra ethvert præfiks.

**Tech Stack:** PostgreSQL 17 (plpgsql, psql), Python 3 (udtræk, ark), TypeScript (`packages/core`, web/vitest,
`packages/identity-candidates`), zsh (opgraderingstest, runner).

**Spec:** `docs/superpowers/specs/2026-11-10-trin6d3-relationer-design.md` (godkendt 2026-11-10). Beslutning:
`docs/decisions.md` 2026-11-10 »6d-3's afgrænsning«. Kæden for kilde 1: `docs/superpowers/plans/2026-10-23-trin5ab-overfoersel-b2-ceremoni.md`
(tabellen ~:171-185) og `docs/runbooks/transfer-5ab-data-prod.md`.

## Roadmap-kobling

Spec §1: trin 6, »samme operationer«; værdikædeled fortolkning → relationspersona → identitet → afgørelse → strukturel
binding → læserens familiekilde. Erstatter 1939-legacy-familierne som eneste spor af ægteskaberne og 1791 som ægtemand.
Færdigbevis: Task 9 trin 4 (spec §8). Review: Codex `gpt-6.1-sol` på planen (Task 0 trin 7) og på diffen (Task 9
trin 1); Opus afvejer hvert fund. Projektejeren har frigivet budgettet 2026-11-10.

## Global Constraints

- **Gren:** `feat/trin6d3` fra `docs/trin6d3-spec`. PR'er altid `--draft`. Intet push uden projektejerens ja.
- **Prod** røres kun i projektejerens shell med GO (`--jeg-mener-det --go <kode>`); AI'en kører kun mod lokale baser.
  Dump med ekstern kopi før hver skrivende ceremoni; vinduesvagt; fortryd = restore + `db-rls.sql`.
- **`schema.sql` er source of truth.** `db-migrations.sql` får én ny blok sidst:
  `-- ===== trin 6d-3: relationsprofiler som data og tekstfoldning =====`; ændrede funktioner har byte-ens krop i
  begge filer; idempotent (to kørsler). Ældre blokke redigeres ikke.
- **Ingen editionsnavngiven permanent overflade:** profilnavne og sidelabel-skabeloner er data i
  `private.relation_persona_profile`/`reimport_writer_profile`; ingen `source_id = 3`, `'1939'` eller `'2018-20'` i
  funktionskroppe eller i scripts' logik (kun i profilfiler/-rækker).
- **2018-20 uændret:** `relation_marriage_ordinals`, `relation_binding_state` og `public_family_sources` giver
  byte-ens resultat for kilde 1 før og efter DDL'en og ceremonien (md5 i `maal` på stand-in og prod; kilde 1 skrives
  ikke i 6d-3, spec §5.1.6).
- **Ingen opret-ben:** ingen `person_create`, ingen nye familier/familiemedlemmer, ingen ny dispositionsskrivning;
  ubundne forslag står `proposed` og tælles pr. årsag (spec §4).
- **Rækkefølge i dataceremonien:** D, O, så R; ændres `samme_som` efter R's kandidatkørsel, genberegnes kandidater og
  kontrol (spec §5.2).
- **Indholds-id'er:** persona/mention/kandidatkørsel er `content_uuid`; batch, autorisation, versioner, change_sets og
  `samme_som`-relationer er tilfældige. Ark og ceremoni refererer `interpretation_key`, `record_key`, `family_id` og
  person-id'er, der findes i prod før ceremonien, samt arkenes sha (memory: hash-bind menneskets godkendelse).
- **PII (invariant 8):** 1939-personer er afdøde; kortenes tekst må vises for projektejeren. Kort, svar, manifester og
  målinger kun under `~/.private/6d3/` (0600). Tests bruger opdigtede personer med negative id'er. Chat og commits:
  tal, nøgler, hashes.
- **Miljø:** `env -u PGOPTIONS` foran psql, `env -u NODE_OPTIONS` foran npm. Prods `statement_timeout` er 2 min;
  øv med `ALTER DATABASE … SET statement_timeout='2min'`. Stand-ins restores med ICU.
- **Implementer-briefs:** ingen kommando på `~/.private`, heller ikke `ls`; drop ikke databaser, list dem.
- **Commits:** atomiske, Conventional Commits på dansk, ingen Claude-attribution; trailer
  `Claude-Session: https://claude.ai/code/session_01VptDwx7y65uV3GSf7fTmx2`.

## Review Focus

1. **En post med flere ægteskaber, hvor et tidligt står over en orddeling eller sidemarkør.** Nummeret skal følge
   tekstens rækkefølge, ikke sende det tidlige ægteskab sidst. Låses af `$fold_ordinal_blandet$` (Task 3).
2. **2018-20's eksisterende bindinger og numre.** DDL'en må ikke flytte et eneste nummer eller ugyldiggøre en
   binding (ellers forsvinder 241 kilder). Låses af `$kilde1_uaendret$` (Task 3) og `K1_*`-md5 på stand-in'en med
   prod-data (Task 5 trin 2; ikke-tom mængde krævet).
3. **Sammenfoldet person med samme ægtefælle i to udgavers familier.** Én ægtefælle-linje med begge kilder; en
   modpart, der ikke findes i modellen (skjult/privat), giver ingen fejl og ingen kilde. Låses af
   `aegteskab_alias_to_familier` og `ukendt_modpart` (Task 1).
4. **Drift mellem kort og ceremoni:** en D-kandidat har fået `samme_som`, eller tvillingens ægtefæller er ændret.
   Ceremonien afbryder med `T6D3_PRE_MANIFEST` og skriver intet. Låses i Task 7 trin 1.
5. **Læserens kald efter ~250 nye bindinger:** `public_family_sources` for den tungeste person må ikke blive mere end
   10 % langsommere end før (median af 3, anon). Låses af `anon`-målingen i Task 8 trin 3.

---

### Task 0: Måling, D/O-kort og Codex på planen (kun lokalt; ingen kode-commits)

Noter, prober, kort og svar i `~/.private/6d3/` (0600). Stand-in: frisk restore af prod efter 6d-2b
(`daa5ab_ddl_standin_<ts>_6d3a`), oprettet fra projektejerens `dump-kopi`.

- [x] **Trin 1: Genmål spec §2** (2026-11-10, stand-in `daa5ab_ddl_standin_20261110214451_6d3a` fra prods
  `dump-kopi` sha `f10943f4…`): alt som spec §2 (281/271/6/4, `principal_ok`, 333 familier, 62/9/34, retning 237/237
  og 2 ikke-alias hovedpersoner, 59 uden position, gate 265/6, 1791-topologi og de skjulte). Én definitionsafvigelse,
  samme tal på den gamle stand-in (ingen drift): **42 D-kandidater hos 41 personer** (hovedperson koblet, ægtefælle
  ikke, tvillingens familie uden for 1939 har en ægtefælle) mod specens øvre grænse 44/43; 35 har én
  tvillingægtefælle, 7 har to. Klasse 226/2 måles som 228/0 med komponent-sink.
- [x] **Trin 2: v3-udtrækket på 1939 uden foldning** (271 ægteskaber): S 77, D 7, N 6; U 181 (`navn_uklart` 67,
  `intet_vindue` 54, `partner_ligner` 46, `navn_afkortet` 7, `flere_klausuler` 6, `nummer_modsiger_bog` 1).
  Nulpunktet for Task 4.
- [x] **Trin 3: Forældrenes kandidater:** kilde 3's 6 har 0 i dag, fordi principal-parten først sættes af
  persona-batchen; simuleret med postens primary-persona: 1 af 6 med præcis én kandidat, 5 uden; de 4 børn uden.
  Genmåles efter Task 6 trin 1. Kilde 1: 1 forældreforslag, 0 kandidater.
- [x] ~~Trin 3b~~ udgår: kilde 1 skrives ikke i 6d-3 (projektejerens valg 2026-11-10, spec §5.1.6): v3 giver I-103
  `I`/`intet_navn` og V-159 `U`/`flere_klausuler`, og arket tillader kun `I`/`U`.
- [x] **Trin 4:** erstattet af `collapseSameAs`/`buildModel` på stand-in'ens data (= prod): 18 har to ægtefæller
  (598/1537), 815 og 816 hver to ægtemænd (392/1791), 0 karantæner. Browsertjekket som anon sker i Task 9 trin 4.
- [x] **Trin 5: Tabet vist** og godkendt 2026-11-10: D 42 kort, O 1791 + kort for 1795, R som trin 2-3; kilde 1 ude.
- [x] **Trin 6: D/O-kort** — besvaret 2026-11-11: 43 kort, D 42 × `S`, 0 × `I`; O1 (1795) `P`. Valgmulighederne
  er kanoniske personer (en ægtefælle registreret flere gange = ét valg; D24/D26/D40 havde aliasvalg i første
  manifest, rettet; svarene var de kanoniske og er præget om til manifest v2 med sporbarhed). Manifest v2 sha256
  `85ead8a7b7e03c3d67342eda16aaf7e733d14a1743efe6bc5d92eb9eebb9ce9d`; flettet svarfil sha256
  `f4b05011d4148c701e50d1bd7a58d34e3698c8a580e0dc4ae0d380d9c1099000` (privat, aldrig i repo'et). Oprindelig opgave:
  D/O-kort (lokal HTML, flettet ind i token-arket; memory: kortark kræver kontekst + HTML): pr. kandidat
  1939-ægtefællens navn, datoer, posttekst og side mod *alle* tvillingens ægtefæller (navn, datoer, familie-id);
  ingen forudfyldning. Svar `S <n>` / `I` (ingen af dem). Kort for 1795: `P` (privat) / `B` (bevar). Manifest =
  kanonisk JSON pr. kort (person-id'er, førtilstand: ingen `samme_som` for 1939-ægtefællen, tvillingens
  ægtefællemængde, tekst-sha); svarfilen refererer manifestets sha.
- [x] **Trin 7: Codex `gpt-6.1-sol` på denne plan** (kørt 2026-11-10 før trin 1-6, efter projektejerens ønske):
  NO-GO, 9 MAJOR. Opus-afvejning, godkendt af projektejeren: nødvendig 3, 4, 5, 6, 7, 9; forenklet 2 (kun
  `--profile`, ingen særskilt vej for maskinelle personas), 8 (kilde 1-md5 på stand-in i stedet for tomme
  opgraderingsbaser), 1 (commit-grænser listet + ét ekstra afbrudspunkt; intet fuldt katalog-/ACL-aftryk). Rettet
  i Task 2, 3, 5-9 (»Codex plan-fund n«). Smal runde 2 på rettelserne: NO-GO, 3 MAJOR, alle nødvendige med enkel
  løsning (kilde 1 via eksisterende `mode=list` + måling af forældrekort; `K1_NYE` på UUID og promotion-definition;
  profilnøgle `(profile, source_id)` + shelltest-fixtures). Rettet (»plan-r2 fund n«); kilde 1-delen udgik senere
  i trin 3b. Ingen runde 3 på planen;
  næste Codex-runde er diffen (Task 9).

### Task 1: Spor L — kildefiltre med kanonisk modpart

**Files:**
- Modify: `packages/core/src/familieKilder.ts`, `web/src/components/DetailPanel.tsx:52-62`
- Test: `packages/core/src/__tests__/familieKilder.test.ts`, `web/src/components/__tests__/DetailPanel.familieKilder.test.tsx`

**Interfaces:**
- Produces (core, eksporteret fra `@daa/core`):
  `aegteskabsKilder(kilder: FamilieKilde[], ider: FamilieIder, spouseId: string | null, focusId: string, canon: Record<string, string>): FamilieKilde[]`,
  `foraelderKilder(kilder, ider, parentId: string, canon): FamilieKilde[]`,
  `boerneKilder(kilder, ider, focusId: string, canon): FamilieKilde[]`, hvor
  `FamilieIder = ReturnType<typeof familieIderForPerson>`. Modpart normaliseres som `canon[id] ?? id` (decimalstreng).
- Consumes: `model.canonicalIdById` (valgfri på `Model`, `packages/core/src/types.ts:178`; sat i
  `web/src/data/model.ts:159`) → `DetailPanel` sender `model.canonicalIdById ?? {}`.

- [x] **Trin 1: Fejlende tests (core):** `aegteskab_alias_modpart` (modpart = alias-id, `spouseId` = kanonisk → 1
  kilde); `aegteskab_alias_to_familier` (to familier, én pr. udgave, samme kanoniske ægtefælle → begge kilder under
  den ene ægtefælle); `aegteskab_anden_families_modpart` (kanonisk match, men familien er ikke parrets → 0);
  `foraelder_alias` (modpart alias for `parentId` → 1); `boern_alias` (modpart alias for fokuspersonen → 1);
  `ukendt_modpart` (id ikke i `canon` → sammenlignes uændret, ingen fejl).
- [x] **Trin 2: Kør** `env -u NODE_OPTIONS npm run test -w @daa/core` → FAIL (funktionerne findes ikke).
- [x] **Trin 3: Implementér** de tre funktioner; `DetailPanel` kalder dem med `model.canonicalIdById` (adfærd
  uændret for ikke-sammenfoldede personer).
- [x] **Trin 4: Web-test:** `DetailPanel.familieKilder.test.tsx` får et tilfælde med alias-modpart, der vises. Kør
  core- og web-suiterne → PASS; `tsc --noEmit` for web.
- [x] **Trin 5: Commit** `feat(web): familiekilder slår modparten op kanonisk (6d-3 spor L)`.

### Task 2: Relationsprofiler som data

**Files:**
- Modify: `schema.sql` (ny tabel efter `reimport_writer_profile`-seeds ~:3950; `private.write_relation_persona`
  :17554-17700), `db-migrations.sql` (ny blok), `db-rls.sql` (tabellen privat, ingen grants), `db-verify.sql:10376`
  (tekstinspektionen efter `relation-persona-2018-20-v3` i writerens krop erstattes af asserts over profilrækkerne
  og af, at writeren slår op i `relation_persona_profile`; Codex plan-fund 5)
- Modify: testhjælperen `pg_temp.f5b_profile` (`tests/sql/fixtures/relation-5b.sql:95`, brugt af alle 5b-testene) (indsætter en syntetisk `relation_persona_profile`-
  række for testens negative kilde, fx −5201/−5341; produktionskontrollen svækkes ikke; Codex plan-fund 6), og
  fixtures i `tests/sql/test-relation-marriage-sheet.sh` (kilde −22501) og `-v3.sh` (−22601), der skriver via
  `relation_persona_apply.sql` uden `f5b_profile`: de indsætter selv `(profil, kilde)`-rækken og kalder scriptet med
  `-v profile_file` (2018-20-filen); profilnavnene er uændrede, så v3-testens navne-assert (:27) står (Codex plan-r2 fund 3)
- Modify: `.claude/skills/daa-extract/scripts/relation_persona_apply.sql`, `relation_batch_apply.sql`,
  `transfer_5ab_step_profile.sql` (literalerne → `-v profile_file`)
- Create: `.claude/skills/daa-extract/profiles/relation-persona-2018-20.json`, `relation-persona-1939.json`
- Test: `tests/sql/test-relation-persona-profile.sql`; eksisterende `test-relation-persona-writer.sql`, `-v2.sql`, `-v3.sql`,
  `test-relation-marriage-sheet.sh`, `test-relation-marriage-sheet-v3.sh`

**Interfaces:**
- Produces: `private.relation_persona_profile(profile text NOT NULL, source_id bigint NOT NULL, predicate_forms jsonb NOT NULL, text_form text NOT NULL CHECK (text_form IN ('folded','raw')), PRIMARY KEY (profile, source_id))`
  (sammensat nøgle, så tests kan registrere samme profilnavn på en negativ kilde; Codex plan-r2 fund 3).
  Seeds: `relation-persona-2018-20-v1` `{"relation.marriage":"v1","relation.child":"v1","relation.parent":"v1"}`,
  `-v2` `{"relation.marriage":"v2"}`, `-v3` `{"relation.marriage":"v3"}`, alle `source_id=1`, `folded`;
  `relation-persona-1939-v1` `{"relation.marriage":"v3","relation.parent":"v1"}`, `source_id=3`, `raw`.
  Seeds står i `schema.sql` (data, ikke logik). Writeren vælger gren efter `predicate_forms->>predicate` og afviser
  `RELATION_PERSONA_PROFILE_INVALID`, når der ikke findes en række for (profil, batchens kilde), eller prædikatet ikke
  er i profilen.
- Profilfil (JSON): `{"profile_id","profile_version","relation_profile","writer_config":{…,"citation_label_template":…}}`;
  2018-20-filen gengiver de nuværende literaler byte-ens (`"DAA 2018-20 s. {page_from}"`, `pdf_text_layer`).

- [x] **Trin 1: Fejlende tests** (`test-relation-persona-profile.sql`): `$profil_ukendt$` → `RELATION_PERSONA_PROFILE_INVALID`;
  `$profil_forkert_kilde$` (1939-profil på kilde 1-batch) → afvist; `$praedikat_uden_form$` (`relation.child` på
  1939-profil) → afvist; `$parent_v1_form_1939$` (forælder med v1-payload på 1939-profil) → skrevet.
- [x] **Trin 2: Kør** → FAIL. **Trin 3: Implementér** tabel, seeds og writerens opslag; scripts læser profilfilen.
- [x] **Trin 4: Kør** de nye og de eksisterende writer-tests (v1/v2/v3/reuse) → PASS; testenes asserts er uændrede,
  kun hjælperens profilrække er ny. `run-db-verify-disposable.sql` → PASS med den nye profil-assert.
- [x] **Trin 5: Commit** `feat(db): relationsprofiler som data (6d-3)`.

### Task 3: Tekstfoldning i ordvindue og ægteskabsnummer

**Files:**
- Modify: `schema.sql` (`private.relation_ordered_windows` ~:17438, `private.relation_marriage_ordinals` :17472, v2/v3-
  writerens spændtjek), `db-migrations.sql`
- Create: `tests/fixtures/relation-fold-cases.json` (delt med Python, Task 4)
- Test: `tests/sql/test-relation-fold.sql`

**Interfaces:**
- Produces: `private.relation_text_form(p_source_id bigint) RETURNS text` (`'raw'` hvis kilden har en raw-profil i
  `relation_persona_profile`, ellers `'folded'`); ny `private.relation_ordered_windows(p_text text, p_raw text, p_text_form text)`
  (ingen default) med samme returkolonner som i dag. Den eksisterende 2-arg-funktion bliver en tynd indpakning, der
  kalder 3-arg med `'folded'` (en default ville give en ekstra overload ved siden af den gamle i opgraderet prod;
  Codex plan-fund 3); begge får `REVOKE` som i dag. Ved `raw` sammenlignes på en foldet projektion (linjeskift →
  mellemrum, `-\n` → intet, linjer `### PAGE nnnn ###` → intet), og vinduets positioner føres tilbage til
  originalteksten. `relation_marriage_ordinals` og writerens spændtjek (:17478, :17649-17650 og migrationernes
  kopier) kalder 3-arg med `relation_text_form(kilden)`.
- Fixture-format: `[{"id","text","raw","text_form","w_from","w_to"}]`; Python-tvillingen (Task 4) asserter de samme.

- [x] **Trin 1: Fejlende tests:** `$fold_linjeskift$`, `$fold_orddeling$`, `$fold_sidemarkoer$` (fixture-tilfælde
  giver præcis ét vindue med originalens positioner); `$fold_ordinal_blandet$` (opdigtet post med 3 ægteskaber, det
  første over en orddeling → numrene 1, 2, 3 i tekstrækkefølge); `$kilde1_uaendret$` (`folded` giver samme vinduer
  som før for de eksisterende v2-testtilfælde); `$to_arg_indpakning$` (2-arg = 3-arg med `'folded'`; præcis to
  overloads i `pg_proc`).
- [x] **Trin 2: Kør** → FAIL. **Trin 3: Implementér.** **Trin 4: Kør** + `test-relation-persona-v2.sql`, `-v3.sql`,
  `test-marriage-ordinal-correction.sql`, `test-relation-family-context.sql` → PASS.
- [x] **Trin 5:** På stand-in'en (lokal kopi): 1939's ægteskaber uden position 59 → tal; kilde 1's
  `relation_marriage_ordinals` md5 uændret. Noter tallene.
  **Målt 2026-11-11** (kopi af stand-in'en `…_6d3a` + DDL): 1939's ægteskaber uden position **59 → 10**; kilde 1
  uændret (ægteskabsnumre 248 rækker `daa14961…`, bindingstilstand 281 `d46cd448…`, familiekilder 259 `aab432fb…`).
  Codex-runde på Task 3 (NO-GO, 1 MAJOR + 1 MINOR, begge rettet): navne fra raw-kilder sammenlignes foldet
  (`relation_name_compare_text` i kandidatinput, genbrugstjek og kvitteringskontrol; mentionen gemmes ordret);
  paritetslisten 55 → 61. Konsekvens målt: kandidatinputtet for kilde 3 ændres for 178 af 563 eksisterende personas
  (kun `name`, alle `name_origin=mention`); kilde 1 uændret. Den gemte kilde 3-kørsel `8d2ab8a4…` (2026-11-02) kan
  derfor ikke genverificeres efter DDL'en; det sker kun ved finalize af en ny publiceringsidentitetsbatch, ingen batch
  er åben, og Task 6 trin 2 laver en ny kørsel, der afløser den. Ingen ny publiceringsidentitet på den gamle kørsel
  mellem DDL- og dataceremonien.
- [x] **Trin 6: Commit** `feat(db): tekstfoldning i relationernes ordvindue og ægteskabsnummer (6d-3)`.

### Task 4: Udtrækket læser profilen

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/relation_persona_extract.py`, `_v2.py` (`windows`), `_v3.py`
- Test: `test_relation_persona_extract_v3.py`, ny `test_relation_fold.py`

**Interfaces:**
- Produces: CLI `relation_persona_extract_v3.py --input <json> --out <manifest> --profile <profilfil>`; uden
  `--profile` er adfærden 2018-20-v3 byte-ens. `windows(text, raw, text_form='folded')` spejler SQL'en. Med 1939-
  profilen: ægteskaber med v3's navneregel, forældre med v1's payloadform (intet navn), børn parkeres
  `praedikat_ikke_i_profil`.

- [x] **Trin 1: Fejlende tests:** `test_fold_fixture` (alle tilfælde i `relation-fold-cases.json` giver SQL'ens
  vinduer); `test_profile_1939_parent_v1_payload`; `test_profile_1939_child_parked`; `test_default_profile_unchanged`
  (eksisterende v3-manifest for en fixture er byte-ens).
- [x] **Trin 2-4:** kør (FAIL) → implementér → PASS (hele `scripts`-pytest).
- [x] **Trin 5:** Lokalt på stand-in'ens input (Task 0 trin 2): elementer og parkeringer pr. årsag med foldning.
  Mål: de 160 linjeskift-sager er elementer. Noter tallene.
  **Målt 2026-11-11** (kopi af stand-in'en + DDL, ICU; CLI `--input` v1 + `--v3-input` v3 + 1939-profilen): ægteskaber
  (271) elementer **110** (nulpunkt 90); parkeret `navn_uklart` 89, `partner_ligner` 52, `navn_afkortet` 8,
  `intet_vindue` 6 (nulpunkt 54), `flere_klausuler` 6; forældre 5 elementer + 1 `ikke_ordret`; børn 4
  `praedikat_ikke_i_profil`. Foldningen giver 48 flere vinduer, men kun 20 flere elementer: resten parkeres af
  navnereglerne og går til ægteskabsarket (Task 6 trin 3 forelægger omfanget). Codex-runde (NO-GO, 3 MAJOR + 1 MINOR):
  ægteskaber afgøres fra v3-inputtet med partnerne (fail-closed sammenkobling på alle fælles felter); ægteskabsarket
  læser profilen (Task 6 trin 5 rykket hertil, samme commit, fordi arket og udtrækkets paritetstest afhænger af hinanden);
  begge inputfilers sha i manifestet og serverens `input_sha256` genberegnet (ceremonien hash-binder manifestfilen;
  databasebinding af input er som i 2018-20's v1-flow en kendt begrænsning); CLI'en parkerer dubletter bevidst.
- [x] **Trin 6: Commit** `feat(udtraek): relationsudtrækket læser profil og folder 1939's tekst (6d-3)`.

### Task 5: Opgraderingstest og hele CI lokalt

**Files:** Create `tests/sql/test-6d3-upgrade.sh` (kopi af `tests/sql/test-6d1-upgrade.sh`).

- [x] **Trin 1:** Byg fra `git merge-base origin/main HEAD`; kør nye `db-migrations.sql` + `db-rls.sql` to gange;
  assert funktionskroppe = `schema.sql` (`pg_get_functiondef`-sha), præcis to overloads af
  `relation_ordered_windows`, tabellens ACL (ingen anon/authenticated), seeds; kør Task 2-3's testfiler og
  `run-db-verify-disposable.sql`; `echo UPGRADE_OK`. Ingen kilde 1-md5 her: opgraderingsbaserne er tomme, så md5
  ville sammenligne tomt med tomt (Codex plan-fund 8).
- [x] **Trin 2:** Kør den og `test-6d1-upgrade.sh` → `UPGRADE_OK` fra begge. **Kilde 1 uændret** bevises på
  stand-in'en med prod-data: `maal_trin6d3.sql` før og efter DDL'en → `K1_ORD`, `K1_BIND`, `FAMKILDER` ens, og
  antallene bag dem er ikke nul (241 kilder; ellers fejler målingen).
- [x] **Trin 3:** Hele CI-jobbet lokalt (alle PostgreSQL-jobs, python, R-suiten, node med `tsc --noEmit`) → grønt
  (memory: kør hele CI-jobbet lokalt).
- [x] **Trin 4: Commit** `test(6d): opgraderingstest for 6d-3`.
  **Udført 2026-11-11:** `test-6d3-upgrade.sh` (base `aafbbcfb`) → UPGRADE_OK, også genkørt af forælderen; 6d-1 og 6d-2a
  → UPGRADE_OK. Kilde 1 på stand-in'en før/efter den endelige DDL: `K1_ORD` 248 `daa14961…`, `K1_BIND` 281 `d46cd448…`,
  `FAMKILDER` 259 `aab432fb…`, alle ens. Hele CI lokalt grønt (node, R 3930, python, alle PostgreSQL-jobs) undtagen den
  kendte lokale `test_segment_1939`-OCR-test, der i CI springes over.

### Task 6: R på stand-in op til kortene

Ingen kode-commits ud over værktøjet i trin 4. Stand-in: Task 0's base + Task 2-3's DDL + D/O fra kortsvarene
(Task 7's SQL køres i en øvelsestransaktion, eller midlertidigt med samme kald).

- [x] **Trin 1: Persona-batch** med 1939-profilen: `relation_persona_input.sql -v source_id=3` → Task 4's udtræk →
  `relation_persona_apply.sql -v source_id=3 -v profile_file=…/relation-persona-1939.json`. Tæl personas. Kilde 1
  køres ikke (spec §5.1.6). Genmål forældrenes kandidater (Task 0 trin 3).
- [x] **Trin 2: Kandidater og kontrol** (kun kilde 3): `packages/identity-candidates/sql/export-input.sql -v source_id=3 -v mode=undecided`
  → `npm run cli -w @daa/identity-candidates -- generate --source-id 3 --top-k 10 --family-name-min 0.95` →
  `write-candidates.sql` → `red_register_identity_control_run`. Tæl kort (homonymer + K=20 + forældre).
- [x] **Trin 3: Mål maskinpopulationen** som `red_corroborate_family_identities` vil se den (dry-run i rullet-tilbage
  transaktion efter et forseglet testark): accepteret / afvist pr. årsag. Forelæg projektejeren tallene og
  kortomfanget før kortene (memory: vis tab før kortrunde), side om side med spec §2.1's overslag (≈220 maskinelle,
  200-250 bundne) og Task 0 trin 2's v3-nulpunkt (S 77, `partner_ligner` 46, `navn_uklart` 67, `intet_vindue` 54).
  Store R-kortmængder forelægges som valg (stikprøve/undtagelser), aldrig som fuldt ark.
  **Målt 2026-11-11** på stand-in `t6d3t6_r` (Task 0's base + DDL + D/O: 42 `samme_som`, 1791 og 1795 private):
  persona-batch 115 elementer → 110 nye personas (563 → 673); kandidatkørsel (undecided, top-k 10, navnetærskel 0,95;
  årstalsreserven ændrer intet) rang 1: 68 `ok`/auto, 22 `name_or_rank`, 20 `count_mismatch`; kontrolkørsel: 22
  stikprøvekort, 0 eksklusioner, 1 forælderkort. Maskinelt bundet, hvis kontrollen består: **46**; med kontrolkortene
  68. Specens overslag (≈220) forudsatte, at udtrækket gav personas for næsten alle 271; v3's navneregel parkerer 161.
  **Projektejerens valg (2026-11-11): valg 2** — kort for kontrol (22) og forælder (1) plus en lagdelt stikprøve på 20
  af de 161 parkerede (proportionalt pr. årsag, mindst 1 pr. årsag, deterministisk efter md5 af
  `interpretation_key`). Stikprøven er diagnostisk (grundlag for en 1939-variant af navnereglen efter 6d-3) og giver
  ingen bindinger i 6d-3; de 42 ikke-egnede og de 161 parkerede står `proposed` og tælles pr. årsag.
- [x] **Trin 4: Forælderarkets kontekst** (6c-3's værktøjsnote): `relation_parent_rows.sql` udvides med post-
  tekst, side, barnets navn/datoer og familiens forældre og børn (i dag kun nøgler og id'er, :13-26; Codex plan-fund
  7); rækkefilens sha indgår fortsat i arkets hash-binding. `relation_parent_sheet.py render --html` viser
  konteksten; test i `test_relation_parent_sheet.py` (`test_render_html_has_context`) på en rækkefil i den
  udvidede kontrakt (opdigtede personer) og en SQL-test, der kører `relation_parent_rows.sql` på en fixture-base.
  Commit `feat(udtraek): forælderarket viser kontekst som HTML (6d-3)`.
- [x] **Trin 5: Ægteskabsarket læser profilen** (udført i Task 4's commit, 2026-11-11): `relation_marriage_sheet_v3.py` får `--profile <profilfil>` i
  stedet for den importerede `PROFILE` (:16, :144); uden flaget er adfærden 2018-20-v3 byte-ens
  (`test_default_profile_unchanged`); med 1939-profilen bærer persona-manifestet 1939-profilen
  (`test_profile_1939_manifest`). Arket bruges kun til de parkerede, ikke-maskinelle ægteskaber; maskinelle
  personas går ad kontrolarket (Codex plan-fund 2). Commit `feat(udtraek): ægteskabsark v3 læser profil (6d-3)`.
- [x] **Trin 6: R-kort:** kontrolark (`identity_control_sheet.py`), ægteskabsark for ikke-maskinelle
  (`relation_marriage_sheet_v3.py --profile`), forælderark; lokal HTML, flettet ind i ét token-ark; projektejeren
  svarer; sha på ark og svar.

  **Udført 2026-11-11** på stand-in `t6d3t6_r`: én HTML over to hash-bundne tekstark (privat værktøj `kort6.py`); 43 kort
  besvaret (svarfil sha `65ea8c32…`): kontrolarket 22 ægtefællekort (7 × 1, 11 × 2, 4 × 3; ingen X/N/U) + forældrekortet
  A, flettet ark sha `22b1cd51…` (rækkefil `a6f60b53…`) → kontrollen `passed`, korroboration 46 → **68 accepterede
  ægtefælleidentiteter**, 1 forælder `accepted`. Forælderarket: 4 forslag med hovedperson, 0 strukturelle kandidater →
  ingen kort; de står `proposed`. Stikprøven (20 parkerede, ark sha `7be570f3…`): 19 × S (rigtige match, fejlagtigt
  parkeret), 1 × U (påstanden selv forkert). Fejlgrupper til en 1939-navneregel: »til <gods>« og ejerår i legacy-navnet
  (alle `partner_ligner`), titler foran navnet, Baron/Greve inde i navnet, sidemarkør og »- «-orddeling inde i linjen
  (undtagelse »Geheime- og«), navnepartikler (vom) og omlyd. Datafund: datoer med indbygget linjeskift; én forkert
  påstand (dødsdato læst som vielsesdato, nr. 2 for 1°).

### Task 7: Dataceremoniens SQL og målescript

**Files:**
- Create: `.claude/skills/daa-extract/scripts/samme_som_kort_ceremoni.sql` (D), `privat_kort_ceremoni.sql` (O),
  `maal_trin6d3.sql`, `test_maal_trin6d3.py`
- Test: `tests/sql/test-samme-som-kort-ceremoni.sh`
- R genbruger `transfer_5ab_step_*.sql` med `-v src=3` og profilfil (Task 2).

**Interfaces:**
- D: tager manifest + svar (JSON) og deres sha. Pr. `S <n>` i én transaktion: `pg_advisory_xact_lock(hashtext('samme_som_mutation'))`,
  efterprøv førtilstand for alle kort før første mutation (ingen `samme_som` for 1939-ægtefællen i nogen retning;
  tvillingens ægtefællemængde = manifest; kortets tekst-sha genberegnet fra basen = manifest; Codex plan-fund 9),
  ellers `T6D3_PRE_MANIFEST` og intet skrevet; `red_samme_som(1939-række, mål)`; assert faktisk retning (1939-rækken er alias) og
  komponent-sink; nulstil `app.change_set_id` mellem kald. Kvittering pr. par i en change_set med kilden som subjekt:
  relation-id, retning, change_set. `T6D3_D_OK links=<n> ingen=<n>`.
- O: `red_set_privat(1791, true)` (og 1795 ved `P`) efter førtjek (`privat=false`, familier 742/743 uændrede);
  `T6D3_O_OK privat=<n>`.
- `maal_trin6d3.sql` printer én linje: `T6D3_MAAL fase=<foer|ddl|d|o|r> forslag_k3=<m/p/c> bundne_k3=<n> samme_som=<n>
  dobbelt=<n> privat_1791=<0|1> uden_position=<n> K1_ORD=<md5> K1_BIND=<md5> FAMKILDER=<md5>`
  (`dobbelt` = de 42 kandidaters tæller fra Task 0 trin 1; `K1_ORD`/`K1_BIND` = kilde 1's numre og bundne
  forslag med tilstand, hvor »bundet« = promotion findes, den promoverede version er den aktuelt accepterede, og
  gemt state-hash = genberegnet `relation_binding_state`-hash (samme definition som `schema.sql:20891`; en
  ikke-NULL `relation_binding_state` alene betyder kun »kan bindes«; Codex plan-r2 fund 2). Kilde 1 skrives ikke i
  6d-3, så begge er byte-ens i alle faser (spec §5.1.6). `FAMKILDER` = `public_family_sources` som anon for alle
  offentlige familier; tom mængde bag en md5 → fejl).

- [x] **Trin 1: Fejlende tests:** målescriptets format; D på en lokal base med opdigtede personer: `S` → link med
  1939-rækken som alias; `I` → intet skrevet; forkert svar-sha → `T6D3_PRE_SHA`; eksisterende link før ceremonien →
  `T6D3_PRE_MANIFEST` og intet skrevet; ændret posttekst for ét kort → `T6D3_PRE_MANIFEST`, intet skrevet for
  nogen kort; tvillingen har fået en ekstra ægtefælle → `T6D3_PRE_MANIFEST`, intet skrevet; gentaget kørsel → `T6D3_PRE_FASE`; O: privat sat, `family_offentlig(742)` falsk.
- [x] **Trin 2-4:** kør (FAIL) → implementér → PASS.
- [x] **Trin 5: Commit** `feat(6d): D/O-ceremoni og målescript for 6d-3`.

  **Udført 2026-11-11.** Med projektejerens rigtige kort på en frisk stand-in-kopi med DDL'en: alle 42 tekst-sha'er og
  førtilstande matchede → `T6D3_D_OK links=42 ingen=0`; O → `T6D3_O_OK privat=2`; genkørsel af D → `T6D3_PRE_FASE`.
  Målelinjer: foer `uden_position=59`, ddl/d/o `=10`; `samme_som` 720 → 762, `dobbelt` 42 → 0, `privat_1791` 0 → 1;
  `K1_ORD=1857a95c…`, `K1_BIND=9e0db348…` ens i alle faser. R-øvelse på `t6d3t6_r` (decide 68, bind 69): læseren som anon
  viser DAA 1939 på 68 ægteskaber + 1 forælder, 2018-20 uændret (241/11/7). D's ordning af klausuler er
  `record_key COLLATE "C"`; tekst-sha'en bygger på `relation_persona_input` og gælder derfor kun før R (D før R).

### Task 8: Runner, runbook og generalprøve

**Files:**
- Create (privat, aldrig i repoet): `~/.private/5ab-overfoersel/36-trin6d3.sh` (+ `36-trin6d3-vindue.sql`) efter
  `34-trin6d2a.sh`: `maal`, `anon`, `dump`, `dump-kopi`, `standin`, `go-ddl`, `apply-ddl`, `go-data`, `apply-d`,
  `apply-o`, `apply-r`, `verify`, `fortryd`. `apply-r` kører kæden (persona → kandidater → kontrol med det forseglede
  ark → korroboration → afgørelse → binding → forælderark) med fastlåste sha'er.
- Create: `docs/runbooks/trin6d3-prod.md`.

- [x] **Trin 1: Runner:** GO binder sha over DDL-blok, alle SQL-/Python-artefakter, profilfiler, manifester, svar,
  runner, vinduesvagt og commit. Dump + ekstern kopi før `apply-d`; vinduesvagten accepterer ethvert **præfiks** af
  ceremoniens egne skrivninger (D, D+O, D+O+R-delmængde, nøglet på ceremoniens change_sets og batches) og intet andet,
  også fra samme aktør (spec §6). R's commit-grænser listes eksplicit i vinduesvagten (Codex plan-fund 1):
  `reimport_writer_profile`-rækken (autocommit, `relation_persona_apply.sql:7-9`), autorisationen (egen
  transaktion, :14-20), batchen (:22-30), og `transfer_5ab_step_*`'s COMMIT før kvitteringsfilen
  (`transfer_5ab_step_end.sql:8-18`).
- [x] **Trin 2: Runbook:** `vercel-deploy (L, efter merge) → maal → anon → dump → dump-kopi → go-ddl → apply-ddl →
  maal → anon → dump → dump-kopi → go-data → apply-d → apply-o → apply-r → verify → anon`, stoppunkter og fortryd
  under meldt frys. L rulles ikke tilbage.
- [ ] **Trin 3: Generalprøve** fra operatørens cwd på en stand-in fra en frisk `dump-kopi`: hele rækkefølgen;
  `anon`-tiden for `public_family_sources` ≤ +10 % (Review Focus 5); `collapseSameAs`/`buildModel` på stand-in'ens
  anon-data: de bekræftede D-par og Gabel/Hahn har én ægtefælle, 0 nye karantæner; læsergaten afstemt pr. planlagt
  binding (spec §5.1.5).
- [x] **Trin 4: Fortryd fra præfiks** på fire stand-ins: efter `apply-d`, efter `apply-o`, midt i `apply-r` efter
  autorisationen før batchen, og midt i `apply-r` efter persona-batchen → vinduesvagten godkender præfikset →
  restore → `maal` = `foer`-linjen, `db-verify` grøn, `anon` som før.
- [x] **Trin 5: Negativer:** forkert GO, manglende flag, gentaget `apply-d`, ændret svarfil, fremmed skrivning i
  vinduet.
- [x] **Trin 6: Commit** `docs(6d): runbook for 6d-3 i prod` (runneren committes ikke).

  **Udført 2026-11-11** på stand-ins fra prods `dump-kopi` 10/11 (`g1` iteration, `g2` capture, `g3` replay med alt
  fastlåst); detaljer i `docs/runbooks/trin6d3-prod.md` »Generalprøven 11/11«. Afvigelser fra planen:
  - Vinduesvagten er en kæde af fulde aftryk (hvert skridt kræver basen lig forrige skridts aftryk og tager sit eget
    efter commit eller fejl) i stedet for undtagelseslister pr. commit-grænse. Den dækker også R's grænser
    (profil, autorisation, batch, kandidater, kontrolkørsel, kontrolarkets to transaktioner, korroboration, afgørelse,
    binding), uden at de skal opregnes. Ingen genoptagelse: ethvert fejlet skridt efter en commit fortrydes til
    ddl-dumpet (rådgiverens anbefaling; konsekvensen er meldt frys fra `apply-d` til `verify`).
  - R's skridt kører i replay mod generalprøvens items (prod genberegner og sammenligner, før RPC'en kaldes).
  - Tidsbudgettets kald over alle familier sammenlignes pr. returneret kilde (R tilføjer 69 kilder; +27 % absolut på
    stand-in, uændret pr. kilde); tre familier med en ny 1939-kilde er lagt til de tunge.
  - `db-verify.sql` køres ikke mod prod-kopier (kræver dblink og skriver testdata); fortrydelsens bevis er runnerens
    lighedstjek mod dumpet.
  - Rådgiverens review samme dag: fejlgrenene (O-før-fejl, R-skridtfejl) prøvet på `g4`; budgetfamilierne rettet til
    1939-familier, der faktisk får en kilde; katalogaftryk i DDL-fejlgrenen.
  Trin 3 udestår i sin endelige form: slut-generalprøven på en frisk `dump-kopi` (prod-læsning i projektejerens
  shell), efter Codex på runneren.

### Task 9: Review, prod og færdigbevis

- [ ] **Trin 1:** Codex `gpt-6.1-sol` over hele grenens diff (eksport uden `work*/`); Opus dømmer; ret det godkendte
  efter projektejerens ja; hele CI lokalt igen.
- [ ] **Trin 2:** Spørg om push og draft-PR; CI grøn; projektejeren merger; Vercel deployer L; browsertjek som anon
  (ingen ændring uden 1939-bindinger).
- [ ] **Trin 3: Prod** i projektejerens shell efter runbooken; AI'en læser kvitteringer og mål.
- [ ] **Trin 4: Færdigbevis** (spec §8) i `status.md` (relationsrækken for 1939 → `produktionsverificeret`),
  `database-current-state.md` og changelog: elementer, parkeringer pr. årsag, identiteter (maskine/kort), afgørelser,
  bindinger; D-links; 1791 privat; ubundne `proposed` pr. årsag med nøgle (inkl. kilde 1's 4 partsløse, spec
  §5.1.6); kilde 1's `K1_ORD`/`K1_BIND`/`FAMKILDER` uændret; browsertjek som anon
  (»DAA 1939« på et ægteskab hos en sammenfoldet person; én ægtefælle hos et D-par; Gabel/Hahn én ægtemand).
- [ ] **Trin 5:** `docs/decisions.md`: noter 6d-3 i prod; commit `docs(6d): færdigbevis for 6d-3 i prod`.
