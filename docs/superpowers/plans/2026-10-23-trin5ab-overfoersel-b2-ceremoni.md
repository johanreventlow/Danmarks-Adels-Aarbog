# Trin 5a+5b-overførslen, plan B2: arbejdskørsel, genspilsprøve og data-ceremonien (GO 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (**native**) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Kun Task 1 og 2 (repo-filer, syntetiske baser) må gives til en subagent, og aldrig med adgang til `~/.private/`, `work*/` eller en restore. Task 0 og 3-8 rører restores med persondata eller private scripts og køres i hovedsessionen.

**Goal:** 2018-20's 5b-kæde (del 1 → 2a → 2b-i → 2b-ii → navneregel v3 → 2b-iii) køres én gang med den endelige kode på en restore af D1 (arbejdskørslen), kontrolleres mod beviskæden (§6.3), genspilles uden menneske på en anden restore (`REHEARSAL_OK` (data)) og derefter i prod efter GO 2 (`VERIFY_OK`), hvorefter skrivepausen ophæves.

**Architecture:** B1's værktøj (`transfer_5ab_*.sql`, `transfer_steps.py`, `transfer_answers.py`, `identity_queue_sheet.py`) bruges uændret, bortset fra Task 1's rettelser. En privat runner i `~/.private/5ab-overfoersel/` (samme `lib.zsh` som plan A, nye scripts `10`-`17`) kører en fast **kædefil** skridt for skridt: i arbejdskørslen i `capture`, så hvert skridt lægges i pakken med indgangs- og udgangsdigest; i genspil og prod i `replay`, med classify før hvert skridt. Menneskelige punkter er stop i runneren. To nye repo-filer (Task 2) gør indholdskontrollen (§6.3) til en maskinel sammenligning med en nøglet liste over forventede forskelle.

**Tech Stack:** zsh (`/bin/zsh -f`), psql/pg_restore 17 (`/opt/homebrew/opt/postgresql@17/bin`), Python 3 stdlib (`/usr/bin/python3 -I`, pytest via `/usr/bin/python3 -m pytest`), Node (`env -u NODE_OPTIONS npm run cli -w @daa/identity-candidates`), Supabase Session pooler.

**Spec:** `docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§6.2-§6.5, §7, §8 GO 2 og datafortrydelsen, §9, §10). Plan B1: `docs/superpowers/plans/2026-10-22-trin5ab-overfoersel-b1-vaerktoej.md` (afsnittet »Til plan B2«). Kortlægningen af kæden (afsnit A-H, citeret »kortlægningen §X«): privat `~/.private/5ab-overfoersel/b2/kaede-opskrift.md` (2026-10-22, læse-kun over repoet; ingen persondata). Runbook for GO 1: `docs/runbooks/transfer-5ab-ddl-prod.md`.

## Roadmap-adgangskrav

| Krav | Svar |
| --- | --- |
| Roadmapmål | Trin 5 (#150/#151), 5a+5b for 2018-20 |
| Værdikædeled | Identitetsafstemning og promotion af relationer (binding til familien) i prod |
| Leverancetype | Midlertidig overførsel (engangsceremoni) over generelle repo-mekanismer (B1); den private kædefil er 2018-20's profil |
| Redaktionel/læserrettet værdi | Projektejerens ark og køafgørelser bliver gældende i prod; læseren ser kildehenvisninger for ægteskaber, forældrelinjer og børneflokke; redaktørens identitetskø virker i prod |
| Færdigbevis | `REHEARSAL_OK` (data) og `VERIFY_OK` i prod, hvor alle nøglede digests er lig arbejdskørslens (spec §9) |
| Erstatter | De 7 bevisbaser som eneste bærer af 5b; trin 4's `transfer-2018-20-prod.md` som mønster |

## Errata mod spec'en og B1

| Spec / B1 | Plan B2 | Begrundelse |
| --- | --- | --- |
| §6.2 »5a → 5b del 1 …«, 5a's webafgørelse | Udgår (som B1) | `decisions.md` 2026-10-21 pkt. 1 |
| B1 Task 3b: kandidatkørsel 1 | Genskabes ikke; én kørsel (top-k 10) | H3, projektejeren 2026-10-22 |
| §6.2 »projektejeren får vist en forskel før arket hashes« | **Kræver projektejerens ja (Task 5 Step 1):** runneren godkender selv et overført ark, kun når (a) `transfer_answers.py` giver `ANSWERS_OK … aendret=0`, (b) hvert bortfald er en `-`-linje (gammelt svar uden ny linje), hvis nøgle står på arkets egen bortfaldsliste (`sheet:<kind>`, M6), og (c) kind ∉ {`control`, `marriage_v3`}. Alt andet ⇒ `VENTER_GODKENDELSE`. En `+`-linje (ny linje uden gammelt svar, fx fordi stikprøven er ny) kræver altid et frisk svar fra projektejeren. Alle rapporter læses samlet før GO 2 og bindes i GO 2 | Arbejdskørslen er lokal. En afvisning ved Task 7 Step 5 koster en frisk restore, genspil af pakken til skridtet før den afviste linje og ny capture derfra; kontrolarkets svar ligger i pakken, så de 30 blinde kort aldrig skal besvares igen. Holder menneskelig tid til undtagelser (hukommelse »ingen flere fulde afgørelsesark«) |
| §6.3 indholdskontrol »på nøgleniveau« | Over en semantisk projektion (Task 2), ikke over digest-rækkerne | Digest-rækkerne bærer arkhashes i evidensen, som er nye pr. konstruktion; en rækkesammenligning ville flage alle identiteter |
| §6.4 »anden, frisk restore« | Påkrævet: andet databasenavn og klient-`PGTZ=Pacific/Chatham`; arbejds- og genspilsbaser oprettes som prod med ICU (`createdb -T template0 --locale-provider=icu --icu-locale=en-US --locale=en_US.UTF-8`), og tegnprøven er en gate (`LOCALE_PROBE`, Task 3). Desuden en diagnostisk kørsel med libc, der rapporteres, men ikke er en gate | Målt 23/10 (Task 0): prod er ICU en_US (`datlocprovider=i`, tegnprøve `6bf1ee80`), alle lokale baser libc. Mod prods tegnprøve afviger libc på 10 tegn (bl.a. `İ`, `ǅ`, græske med tonos), ICU på 5 tegn fra nyere Unicode (U+088F, U+0C5C, U+0CDC, U+1C89, U+1C8A); ingen af de 15 findes i D1's 370 tekstkolonner. `lower()` afhænger af locale (#251's kendte minor), så en afvigelse ville give falsk stop i prod, ikke lokalt |
| §7 »Kanonisk delta 0« | Mod D1's `baseline.canonical_sha256` `a51323ac…` | `decisions.md` 2026-10-21 pkt. 2 |

## Global Constraints

- **Ingen prod fra AI-sessionen.** Prod rammes kun af projektejeren: `! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh <script> …`. Læse-kun `16-hold-varm.sh` er også projektejerens.
- **Skrivepausen** (`freeze-begin-20261022161315`, ansvarlig `jr`) løber til `VERIFY_OK` eller en fortrydelse; `00-freeze.sh end` (uden flag; koden kræver allerede `verify-ok.json` med `VERIFY_OK`, så plan A's nævnte `--efter-verify` tilføjes ikke) afslutter den; `14-verify-data.sh` skriver markøren i plan A's format (`write_marker`). Supabase free tier pauser efter 7 dage uden trafik: runbooken kræver `16-hold-varm.sh` mindst hver 5. dag, til prod-ceremonien er kørt.
- **Ingen kildetekst, navne, noter, uuid'er eller aktør-uuid** på stdout, i chat, i repoet eller i commits. Kun tal, koder og hashes. psql-stderr går til 0600-filer og er privat log: tæl linjer, udtræk kun koder `^[A-Z][A-Z0-9_]+$`, aldrig `tail` i chat.
- **Aktør:** projektejerens profil, læst fra `~/.private/5ab-overfoersel/b2/aktoer.txt` (0600, én uuid), verificeret mod `actor_sha256` `3c4984c769aa63a4c4f81be7f001abf162f016eb72704656dcbc6618ceb71e59`, givet eksplicit som `-v actor`. Aldrig valgt af et script.
- **Konventioner som plan A:** `/bin/zsh -f`, `assert_no_rcs`, `emulate -R zsh`, `set -euo pipefail`, `umask 077`; skrivende scripts kræver præcis `--jeg-mener-det`; ukendte argumenter exit 2; I1 (samme bytes lokalt og i prod), I3 (GO-hashfil, rent repo, `DAA_EXPECTED_COMMIT`), I4 (`DAA_FAULT`, `DAA_LOCAL_*`, `DAA_STANDIN_*` afvist i prod), I6 (mål-identitet `DAA_PROD_TARGET`).
- **Lokale baser** matcher `^daa5ab_data_(arbejd|genspil|diag|fortryd|roeg)_[0-9]{14}(_[a-z0-9]+)?$`. Bevisbaserne og `daa5ab_ddl_d1check_20261022180917` læses kun; intet droppes (oprydning er en separat, målt opgave).
- **Repoet fryses før capture:** pakkens inventar er `repo:<sti>` + sha, og GO 2 binder commit og inventar. Task 1 og 2 skal være merget, før Task 5 starter; senere repo-ændringer må kun være docs.
- **Enhver uforudset forskel stopper** med en kode og exit ≠ 0 og forelægges projektejeren (spec §6.3 sidste linje). Runneren fortsætter aldrig selv efter et stop.
- **Commits:** én pr. task, `type(151): …` på dansk, afsluttet med `Claude-Session: https://claude.ai/code/session_014CxSBLeSAQHZznEhPJ3Y6M`. Privat kode committes aldrig. Push og PR (altid `--draft`) kun efter ja.
- **Lokal CI før push:** jobbene `python` og `writer-1939-v50-db` køres hele lokalt (`env -u NODE_OPTIONS`, `/usr/bin/python3 -m pytest`).

### Konstanter (målt 2026-10-22/23)

| Navn | Værdi |
| --- | --- |
| D1-kvittering | `~/.private/5ab-overfoersel/prod/daa-prod-20261022180917-d1.dump.receipt.json`, sha `7eec3b142cefe5a5de87686d15bbb24b79cf7e27e55b01bea3e7e4809ba4f597` |
| D1 `restore_hash` / `dump_sha256` / `dump_start_utc` | `a60e02a85cf1ae56c7421aa46dba31f60cfcab257b6acc513dbd265ff4c02f50` / `7f7304ce40272230d6988caf2be0c71f09c3f9295092af94ce756d982b20e295` / `2026-10-22T18:09:17Z` |
| D1 `baseline` | `canonical_sha256` `a51323acf02a74556abaffbb2ab0a1db205291b62a3048cfddafeebb8f9985aa`; `schema_sha256` `6b89c9e58e3636f125192f0c00e38a09d66c60932d4bca75f3e5539e90417e82`; `clause_set_sha256` `113a1d12…` |
| D1 `acl_portable` | `e64f9d7255d427d8176a513f601edf0be29155207a498e25bdbf953e30a04693` |
| D1 digests (`transfer_5ab_digests.sql`, kilde 1) | `n_uuid_unmapped` 0; personas 587, identities 587, interpretations 4.415, bindings 622, dispositions 1.747, 5b-lagene 0; `authorizations_issued` 1 (fra før 5b; kun rapport). 3 s |
| Nøglekortet | Kører på alle 7 bevisbaser og D1 (0 s), 0 dubletter på uuid. `daa244_bevis_…`: 4 dubletter i klassen `binding:` = #244's genbindinger (forventet; basen bruges kun til §6.3, aldrig som svarkilde) |
| Uoversatte uuid'er i bevisbaserne | 0 i del 1 og 2a; 416 fra 2b-i og frem: `interpretation.decided_by` 203, `interpretation_promotion.promoted_by` 210, `relation_classification_event.created_by` 3. Årsag: 2a's base havde en ekstra redaktørprofil (»ANDEN«), som traf 2a's afgørelser og er væk i de senere baser. I arbejdskørslen er aktøren prods ene redaktør (forventet forskel, §6.3) |
| #244's 4 nøgler (H2) | K4: ægtefællepersona fra del 1, ikke egnet (`name_or_rank`) i begge kandidatkørsler, S-linje på 2b-i-arket, falsk `ordinal_afvigelse` i 2b-i's efterkørsel; K1: persona fra 2b-ii; K2, K3: personas fra v3; hver med 1 falsk `ordinal_afvigelse`; 0 `ordinal_beholdt` for de 4. Listen: 4 × `classification` `absent_new`, K4's S-linje som tilladt bortfald (`sheet:spouse`), K4's oprindelse `may_differ` |
| Del 1-basens forhistorik (H3/H4) | 2 kandidatkørsler (top-k 3: 702 kandidater; top-k 10: 2.327), hver med én kontrolkørsel (31 stikprøver uden hændelser; 30 stikprøver + 9 forældrekort, `sealed`→`passed`). Kørsel 1 og kontrol 1 genskabes ikke; de ligger uden for indholdsprojektionen |
| Gamle ark (Task 0 Step 5) | Alle 6 ark og rækkefiler fundet med de forventede hashes; 2b-i: 22 S, 3 O (alle `F`, 0 `B`); kontrol: 30 D, 9 R; kø: 9 Q (9/9 noter i formatet `kø 2b-i <12 hex> sag <n> — `) |
| Bevisbase pr. svarkilde | kontrol: `daa5b_bevis_20261010093638`; undtagelsesark og kø: `daa5b_2b_i_bevis_20261012093656`; 2b-ii: `daa5b_2b_ii_bevis_20261017132417`; v3: `daa5b_navnv3_bevis_20261019200958`; børn: `daa5b_2b_iii_bevis_20261020182757`; §6.3-facit: `daa244_bevis_20261020222244` (gældende rækker) |
| Godkendte arkhashes i beviskæden (præfiks) | kontrol `afe87f46`, 2b-i `02c8cc0f`, kø `a2f6474c`, 2b-ii `bb313586`, v3 `fb53ab46`, børn `cd5edca3` |

## Review Focus

1. **Et overført svar rammer en anden person eller familie, end projektejeren mente** (fx søstrene, hvis #244's rigtige numre gør dem egnede i del 1, så 2b-i-arket får andre linjer). Forventet: `ANSWER_PERSON_MOVED`/`ANSWER_NO_TARGET` stopper, eller linjen står i Task 0's tilladte bortfald. Test: Task 0 Step 2 (H2-sporet) + Task 3 Step 1 (`ro_answer_moved`).
2. **Runneren genoptages efter et afbrud midt i arbejdskørslen** (en ny session dage senere). Forventet: `next` peger på første ufærdige skridt; et skridt, der døde før commit, klassificeres `WRITE` og køres igen; et efter commit `ALREADY_APPLIED`; en efterladt `issued`-autorisation ændrer ingen digest. Test: Task 3 Step 1 (`ro_resume`) og Task 6 Step 3.
3. **Kontrolarkets blinde svar afviger fra maskinen.** Forventet: `CONTROL_FAILED` stopper kæden før korroborationen; intet efterfølgende skridt køres; det forelægges som en sag for sig. Test: Task 3 Step 1 (`ro_control_failed`).
4. **Prod har ændret sig siden D1** (en skrivning trods pausen, eller en Supabase-vedligeholdelse, der rører grants). Forventet: `12-genspil.sh` stopper ved indgangen (`NO_WRITE_SINCE_DUMP`, `ENTRY_RESTORE_HASH`, `ENTRY_ACL`) før første skrivning. Test: Task 6 Step 4 (stand-in med én ændret række og én ekstra grant).
5. **Genspillet i prod dør mellem to skridt eller midt i et `writer`-skridt.** Forventet: genkørsel af `12-genspil.sh` fortsætter fra første ikke-`ALREADY_APPLIED` skridt; `MIXED` ⇒ STOP og fortrydelse med `15-undo-data.sh`. Test: Task 6 Step 3 (fault i ét `hash_gated`- og ét `writer`-skridt, derefter genkørsel).

---

## Filoversigt

| Fil | Ansvar | Task |
| --- | --- | --- |
| `.claude/skills/daa-extract/scripts/transfer_5ab_step_{control,corroborate,reject,disposition,begin}.sql`, `transfer_5ab_step_items.sql` | B1's udskudte minors | 1 |
| `tests/sql/test-transfer-5ab-{steps,del1-steps}.sh` | asserts for minors | 1 |
| `.claude/skills/daa-extract/scripts/transfer_5ab_content.sql` | semantisk projektion til §6.3 (læse-kun) | 2 |
| `.claude/skills/daa-extract/scripts/transfer_5ab_content_check.py` (+ `test_…`) | sammenligning mod forventede forskelle | 2 |
| `tests/sql/test-transfer-5ab-digests.sh` | `ct_*`-asserts for projektionen | 2 |
| `~/.private/5ab-overfoersel/b2/maalinger/`, `forventede-forskelle.json`, `gamle-ark.txt` | Task 0's målinger | 0 |
| `~/.private/5ab-overfoersel/lib.zsh` (udvidet), `kaede-5ab.txt`, `koer.zsh` (regex) | runnerens kerne | 3 |
| `~/.private/5ab-overfoersel/10-arbejdskoersel.sh` … `17-go2.sh` | scripts (se Task 3) | 3 |
| `docs/runbooks/transfer-5ab-data-prod.md` | runbook for GO 2 | 7 |
| `docs/decisions.md`, `docs/evidensbaseret-genimport/status.md`, `docs/changelog.md`, `docs/database-current-state.md` | beslutninger og status | 7, 8 |

---

### Task 0: Målinger i bevisbaserne og D1 (læse-kun, privat)

**Files:**
- Create (privat, 0600): `~/.private/5ab-overfoersel/b2/maalinger/<base>.{km,rows,unmapped}`, `maalinger.json`, `forventede-forskelle.json`, `gamle-ark.txt`

**Interfaces:**
- Produces: `forventede-forskelle.json` = `{version: "5ab-expected-v1", entries: [{layer, key, kind: "absent_new"|"absent_old"|"may_differ", fields?: [...], reason}]}` — formatet, Task 2's `content_check.py` læser. Ark-bortfald står i lag `sheet:<kind>` (kind som `transfer_answers.py --kind`) med nøglen i `transfer_answers.py`'s form (`persona:<src>:<key>`/`ikey:<uuid>`); `human_point` udleder heraf én flad tekstfil pr. kind til `--expected-dropouts`, så en nøgle tilladt på ét ark aldrig tillader bortfald på et andet; `gamle-ark.txt` = linjer `<kind> <sti-til-godkendt-ark> <sha256> <sti-til-rækkefil> <sha256> <bevisbase>`; `maalinger.json` med tallene nedenfor.

- [ ] **Step 1: Nøglekort, digest-rækker og uoversatte** for hver bevisbase og `daa5ab_ddl_d1check_20261022180917` (målt 23/10 for kort og digests; gentag med `mode=rows`). Expected: som Konstanter.
- [ ] **Step 2: H2 — de 4 nøgler fra `marriage_ordinal_correction`** i `daa244_bevis_…`, sporet gennem del 1 → 2a → 2b-i → v3: identitetsoprindelse og `eligibility_reason` for ægtefællepersonaen, arklinje på 2b-i-arket (S) og v3-arket (OBS), klassifikationshændelser (nøgle, løbenummer, `ordinal_afvigelse`/`ordinal_beholdt`). Resultat i `forventede-forskelle.json`: de 4 falske `ordinal_afvigelse` som `absent_new`; deres eventuelle `ordinal_beholdt` som `absent_new`; deres 2b-i-S-linjer og v3's 2 OBS-linjer som tilladte bortfald (`absent_new` i arklaget). De 6 ægte afvigelser står ikke på listen.
- [ ] **Step 3: H4 og dubletter (H3/H4):** antal `identity_control_run`/`_event` og kandidatkørsler i del 1-basen pr. (kørselsnøgle); de forkastede kørsler og kandidatkørsel 1 (top-k 3) skrives som `absent_new` i lagene `candidate_runs`, `candidates`, `control_*`.
- [ ] **Step 4: H6 — køens note:** noteformatet i 2b-i-basens `source_persona_identity_event` for køens 9 afgørelser (kun: matcher `^kø 2b-i [0-9a-f]{12} sag [0-9]+ — ` ja/nej, antal) og v3-rækkefilens `previous.note` for P-rækken. Bekræfter kaskaden kø-ark → note → v3-rækkefil → v3-arkhash → v3-payloads → P-evidens; noteres i `maalinger.json`.
- [ ] **Step 5: Gamle ark:** find de godkendte ark og rækkefiler i `~/.private/5b-*/`; verificér hvert arks sha mod præfikset i Konstanter og rækkefilens sha mod bevisrapporten. Mangler et, ⇒ STOP (svaroverførslen kan ikke køre). Assertér 0 `O … : B`-linjer i det gamle 2b-i-ark (en B-linje kalder `red_set_familie_ordinal` = kanonisk skrivning og `change_set`, `schema.sql:6866`). Skriv `gamle-ark.txt`.
- [ ] **Step 6: Øvrige forventede forskelle** i `forventede-forskelle.json` (aktør og evidens står ikke i Task 2's projektion og skal derfor ikke på listen; aktørforskellen i 2a's base og P-evidensens nye nøgler `sheet_line`, `reason`, `decided_on`, `report` noteres kun i `maalinger.json` og decisions): identitetsoprindelse `human`/`family_corroboration` (`may_differ`, felt `origin`; mængden af accepterede er ikke på listen); #244's 4 genbindinger og partversioner med `origin='ordinal_correction'` (`absent_new`).
- [ ] **Step 7: D1's sessionsforhold:** `datcollate`/`datctype`/`datlocprovider` i D1-restoren lig plan A's preflight; nøglekortets GUC-størrelse (`length(current_setting('daa.t5_km'))`) og køretid noteret.
- [ ] **Step 7b: Stikprøvens bortfald kan ikke måles her** (D1 har ingen kandidatkørsel; den nye stikprøve, `control-sample-v2`, tager andre personas ud af 2b-i-arket og køen, R7): listen færdiggøres i Task 3 Step 5 (røgtesten trækker præcis den stikprøve, arbejdskørslen trækker, da trækningen er af indholdet) med et målt, nøglet tillæg (`sheet:spouse`, `sheet:queue`: den gamle stikprøves personas giver `+`-linjer, den nye giver `-`-linjer), som projektejeren godkender (ruling).
- [ ] **Step 8:** Ingen commit (alt privat). Rapportér tal og fund til projektejeren; ét fund, der ændrer kædens form, stopper planen til en ruling.

### Task 1: B1's udskudte minors og forudfyldning af nye linjer (repo)

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/transfer_5ab_step_control.sql`, `transfer_5ab_step_corroborate.sql`, `transfer_5ab_step_reject.sql`, `transfer_5ab_step_begin.sql`, `transfer_5ab_step_items.sql` (eller den fil, der skriver `capture`-items), `transfer_answers.py`
- Test: `test_transfer_answers.py`
- Test: `tests/sql/test-transfer-5ab-steps.sh`, `tests/sql/test-transfer-5ab-del1-steps.sh`

**Interfaces:**
- Uændrede for kaldere; nye fejlkoder: `STEP_FAULT_UNKNOWN`, `STEP_REJECT_TARGET_MISSING`, `STEP_RUN_MISSING`, `STEP_CONTROL_NOT_PASSED`.
- **Forudfyldning (projektejeren 2026-10-23):** `transfer_answers.py transfer` får `--prefill-control-sheet <gammelt kontrolark> --prefill-control-rows <gammel kontrolrækkefil>`, kun for `--kind spouse|queue`. For en `+`-linje (ny linje uden gammelt svar) slås personaens gamle blinde D-svar op (rang → `person_id` via den gamle rækkefil, persona via nøglekortet). Står samme `person_id` på den nye linje, forudfyldes tokenet (`spouse`: `S`, når personen er linjens kandidat 1; `queue`: `same <person_id>`); gamle `U`/`N`/`X` forudfyldes som samme token, hvor arkets grammatik har det. Ellers står linjen tom. Rapporten markerer linjen `+ forslag (kontrolsvar 10/10)`; stdout får `forudfyldt=<n>`. En forudfyldt linje er stadig en `+`-linje og godkendes aldrig automatisk.

- [ ] **Step 1: Skriv asserts:** pytest `prefill_match` (gammelt D-svar rang 2 = person P, P er kandidat 1 på den nye S-linje ⇒ `S`, markeret `forslag`), `prefill_moved` (P står ikke på den nye linje ⇒ tom linje), `prefill_queue` (`same P`), `prefill_not_auto` (rapporten med en forudfyldt linje giver stadig `+` og `forudfyldt=1`), `prefill_kind` (`--prefill-*` med `--kind marriage` ⇒ exit 2); `d1_corroborate_failed` (kontrolkørsel med status `failed`: `red_corroborate_family_identities` returnerer 0 uden fejl, `schema.sql:16489-16491` ⇒ skridtet skal stoppe med `STEP_CONTROL_NOT_PASSED` før kaldet, målt som ejer med `private.control_run_status(ctl)`; ved `passed` skal RPC'ens returværdi = items' antal, ellers `STEP_ITEMS_MISMATCH`); `d1_untouched` (del1-testen: `transfer_5ab_untouched_hash.sql` uændret over de tre skridt); `st_fault_unknown` (`-v fault=foo` på hvert skridt ⇒ `STEP_FAULT_UNKNOWN` før første skrivning; også `disposition` med `fault=before_commit`, som i dag ignoreres stille); `st_reject_none` (persona uden ægteskab som `spouse` ⇒ `STEP_REJECT_TARGET_MISSING`, ikke `STEP_REJECT_AMBIGUOUS`); `d1_run_missing` (`control` og `corroborate` uden kandidatkørsel ⇒ `STEP_RUN_MISSING`, ikke en psql-`\gset`-fejl); `st_items_atomic` (capture med `fault=before_commit` efterlader ingen items-fil, kun intet eller en `.tmp`, der ikke er målstien); `st_bind_mismatch_ineligible` (replay af `bind` med ét ændret **uegnet** item ⇒ `STEP_ITEMS_MISMATCH`).
- [ ] **Step 2: Kør** `bash tests/sql/test-transfer-5ab-steps.sh t5abst && bash tests/sql/test-transfer-5ab-del1-steps.sh t5abd1` — Expected: FAIL på de nye asserts.
- [ ] **Step 3: Implementér:** `step_begin` afviser `fault` ∉ {`before_commit`, `after_authorize`} og `after_authorize` uden for `writer`-skridt; control/corroborate henter kørslen (og kontrolkørslen) med `max()`/`count()` og rejser `STEP_RUN_MISSING`, så den døde `\if :{?t5_run}`-gren udgår (begge filer, `step_corroborate.sql:12-19`); corroborate tjekker `control_run_status` og returværdien som Step 1; reject skelner 0 og >1; capture skriver items med `\o` til `<sti>.tmp` og omdøber efter `COMMIT` med `\setenv T5_ITEMS :'items'` og `\! /bin/mv -- "$T5_ITEMS.tmp" "$T5_ITEMS"` (`\!` interpolerer ikke psql-variabler; `\setenv` gør).
- [ ] **Step 4: Kør** — Expected: `STEPS5AB_OK`, `DEL1STEPS5AB_OK` og pytest grøn.
- [ ] **Step 5: Commit** `fix(151): B1's udskudte minors i skridt-SQL og forudfyldning af nye linjer`.

### Task 2: Indholdskontrollens projektion og sammenligner (repo)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/transfer_5ab_content.sql`, `transfer_5ab_content_check.py`
- Test: `.claude/skills/daa-extract/scripts/test_transfer_5ab_content_check.py`; Modify: `tests/sql/test-transfer-5ab-digests.sh`; `.github/workflows/ci.yml` (pytest-listen)

**Interfaces:**
- `transfer_5ab_content.sql -v src=<id>` (læse-kun, låste sessionsindstillinger som digests): linjer `<lag>|<nøgle>|<værdi-json>` sorteret `COLLATE "C"`, kun **gældende** rækker, ingen tilfældige id'er, ingen arkhashes, ingen aktør. Lag og værdi:
  - `binding`: nøgle `<interpretation_key>`; værdi `{target_type, target_id, rule_key, rule_version}` (kun gældende, ikke-overtrufne)
  - `ordinal`: nøgle `<interpretation_key>:<party_role>:<persona_key>`; værdi `{marriage_ordinal}` (gældende partversion)
  - `identity`: nøgle `<persona_key>`; værdi `{status, person_id}`; `origin`: nøgle `<persona_key>`; værdi `{origin}`
  - `classification`: nøgle `<interpretation_key>:<seq>`; værdi `{classification}`
  - `interpretation`: nøgle `<interpretation_key>`; værdi `{status, predicate}` (gældende version)
  - `disposition`: nøgle `<observation_id>`; værdi `{disposition}` (gældende version)
  - `family_source`: nøgle `<family_id>:<interpretation_key>`; værdi `{slags}` (som `anon`)
  - `persona`: nøgle `<persona_key>`; værdi `{n_mentions}`
- `transfer_5ab_content_check.py --old <fil> --new <fil> --expected <forventede-forskelle.json> --report <sti>`: sammenligner pr. (lag, nøgle). En forskel er tilladt, hvis en post i `expected` dækker (lag, nøgle) med `kind` og, for `may_differ`, kun de nævnte felter. Stdout `CONTENT_OK same=… allowed=… unused_expected=…` eller `CONTENT_UNEXPECTED n=… report_sha256=…` (exit 3). Rapporten (0600, `O_EXCL`) har pr. afvigelse lag, nøgle og gamle/nye værdi. `unused_expected > 0` er ikke en fejl (bortfald, der ikke indtraf), men tælles.
- Consumed by: Task 5 Step 10.

- [ ] **Step 1: Skriv pytest:** ens filer ⇒ `CONTENT_OK`; én ændret `binding.target_id` uden post ⇒ exit 3; samme med `may_differ` på et andet felt ⇒ exit 3; med `may_differ` på feltet ⇒ OK; `absent_new` dækker en nøgle, der mangler i new; `absent_new` på en nøgle, der findes i new ⇒ exit 3; en ekstra nøgle i new uden post ⇒ exit 3; ukendt `kind` ⇒ `EXPECTED_INVALID`; stdout uden uuid.
- [ ] **Step 2: Udvid `test-transfer-5ab-digests.sh`:** `ct_same` (projektionen er ens i A og B trods forskellige tilfældige id'er, collation og tidszone); `ct_value` (`dg_value`'s ændrede nummer ⇒ præcis én `ordinal`-linje afviger); `ct_readonly` (kører under `default_transaction_read_only=on`).
- [ ] **Step 3: Kør** pytest og testen — Expected: FAIL.
- [ ] **Step 4: Implementér** de to filer; tilføj pytest-filen til CI's `python`-job.
- [ ] **Step 5: Kør** — Expected: pytest grønne, `DG5AB_OK`. Kør hele jobbene `python` og `writer-1939-v50-db` lokalt: `CI_JOB_OK`.
- [ ] **Step 6: Commit** `feat(151): indholdskontrol for 5a+5b-overførslen (projektion og sammenligner)`.
- [ ] **Step 7 (gate G0):** draft-PR for Task 1+2 efter projektejerens ja; CI grøn; merge efter ja. Notér merge-commit som `DAA_EXPECTED_COMMIT` for capture. Ingen af Task 3-6 starter før merge.

### Task 3: Den private runner

**Files (privat, 0700/0600):**
- Modify: `~/.private/5ab-overfoersel/lib.zsh` (nye funktioner, plan A's uændrede), `koer.zsh` (script-regex `^[01][0-9]-[a-z0-9-]+\.sh$`)
- Create: `kaede-5ab.txt`, `10-arbejdskoersel.sh`, `11-indholdskontrol.sh`, `12-genspil.sh`, `13-rehearsal-data.sh`, `14-verify-data.sh`, `15-undo-data.sh`, `16-hold-varm.sh`, `17-go2.sh`, `test-runner.sh`

**Interfaces:**
- **Kædefilen** `kaede-5ab.txt`: én linje pr. skridt `<n> <navn> <type> <script> <led> layers=<lag,…> [menneske=<kind>]`, i denne rækkefølge (kortlægningen §A R1-R10 og §B). `layers` går til `add-step --layers` og er de lag (B1 Task 1), skridtet skriver i; et skridt med to transaktioner skal dække begge, så et afbrud imellem klassificeres `MIXED`, ikke `ALREADY_APPLIED`. Writer-skridt har desuden `authorizations_consumed,counts`.

  | n | navn | type | script | lag | før skridtet |
  | --- | --- | --- | --- | --- | --- |
  | 1 | `profile` | sql | `transfer_5ab_step_profile.sql` | writer_profiles | |
  | 2 | `persona_v1` | writer | `relation_persona_apply.sql` | personas, parties, interpretations | input `relation_persona_input.sql` → `relation_persona_extract.py` |
  | 3 | `candidates` | hash_gated | `transfer_5ab_step_candidates.sql` | candidate_runs, candidates | `export-input.sql mode=undecided` → `generate --family-name-min 0.95 --top-k 10` |
  | 4 | `control` | sql | `transfer_5ab_step_control.sql` | control_runs, control_samples, control_exclusions, control_parent_cards | straks efter 3 (R2) |
  | 5 | `control_sheet` | sql (2 tx) | genereret af `identity_control_sheet.py sql` | control_events, identities, identity_events, interpretations, parties, control_parent_events | **menneske=control**: D blinde, R overført |
  | 6 | `corroborate` | hash_gated | `transfer_5ab_step_corroborate.sql` | control_events, identities, identity_events | gate: efter skridt 5 måler runneren `control_run_status` (læse-kun, som ejer); ≠ `passed` ⇒ `CONTROL_FAILED`, skridt 6 køres ikke (skridtet selv stopper desuden med `STEP_CONTROL_NOT_PASSED`, Task 1) |
  | 7-8 | `decide_2a`, `bind_2a` | hash_gated | `step_decide`, `step_bind` | interpretations, classifications / bindings, family_sources, counts | |
  | 9 | `spouse_sheet` | sql | `spouse_exception_sheet.py sql` | identities, identity_events, classifications | menneske=spouse |
  | 10 | `queue_sheet` | sql | `identity_queue_sheet.py sql` | identities, identity_events | menneske=queue |
  | 11-12 | `decide_2bi`, `bind_2bi` | hash_gated | | som 7-8 | |
  | 13 | `persona_v2` | writer | `relation_persona_apply.sql` | personas, parties, interpretations | menneske=marriage; manifest fra `relation_marriage_sheet.py sql` |
  | 14 | `identity_v2` | sql | det genererede identitetsscript | identities, identity_events | værn `person_create_elements=0` efter |
  | 15-16 | `decide_2bii`, `bind_2bii` | hash_gated | | som 7-8 | |
  | 17 | `disposition_2bii` | writer | `transfer_5ab_step_disposition.sql` | dispositions | |
  | 18 | `persona_v3` | writer | `relation_persona_apply.sql` | personas, parties, interpretations | menneske=marriage_v3 (de 2 OBS-linjer genaccepteres udtrykkeligt) |
  | 19 | `identity_v3` | sql | det genererede identitetsscript | identities, identity_events | værn efter |
  | 20-21 | `decide_v3`, `bind_v3` | hash_gated | | som 7-8 | |
  | 22 | `disposition_v3` | writer | `step_disposition` | dispositions | |
  | 23 | `reject_p` | sql | `transfer_5ab_step_reject.sql` | interpretations | evidens med det **nye** v3-arks sha, `sheet_line`, `reason`, `decided_on` `2026-10-20`, `report` (R9) |
  | 24 | `child_sheet` | sql | `relation_child_sheet.py sql` | interpretations | menneske=child |
  | 25 | `bind_2biii` | hash_gated | `step_bind` | bindings, family_sources, counts | |

  `relation_persona_apply.sql` printer `counts` og `relation_results` (uuid'er, `:28-29`): runneren sender writer-skridtenes stdout til en 0600-fil og udtrækker kun tal og koder. Efter hvert `writer`-skridt: kvitteringens `year_interpretations = 0` og 0 `ORDINAL_BOOK_MISMATCH` i stderr-koderne. Efter skridt 25: `transfer_5ab_guards.sql` ⇒ `person_create_elements=0`, `ordinal_correction_rows=0`, `ordinal_book_mismatch=0`, `book_ordinal_match` 40/40.
- **lib.zsh, nye funktioner** (alle tager mål-db fra `CTX`, skriver kun koder/tal):
  - `measure_5ab <run-mappe> <præfiks>` ⇒ digests, untouched + other_sources, guards, `transfer_baseline.sql`, `transfer_restore_hash.sql` til 0600-filer; `REPLY` = sha over dem.
  - `step_capture <n>` / `step_replay <n>`: kør skridtet (B1's `-v src=1 -v mode=… -v items=… -v actor=…`; writer-skridt via `relation_persona_apply.sql`/`relation_batch_apply.sql` med manifestet; ark-skridt med den genererede SQL), mål digests før og efter over skridtets lag, `transfer_steps.py add-step` (capture) eller `classify` før og efter (replay). Replay af et persona-writer- eller ark-skridt regenererer input/rækkefil i basen og kræver sha lig pakkens (`RUNNER_INPUT_DRIFT`), før filen køres. `disposition_*` er undtaget: manifestet bærer tilfældige versions-id'er og sammenlignes via skridtets nøglede items (`transfer_5ab_step_disposition.sql:14-25`). **Undtagelse `queue_sheet`:** kødetaljedumpet (`red_source_persona_detail`) er ikke platformssikkert (`ORDER BY created_at`, `jsonb_agg(DISTINCT …)` uden `COLLATE "C"`; kortlægningen 3.5), og kæde-skabte rækker har andre `created_at` i prod. Drift er her ulighed i mængden af persona-id'er (B1's `KOE_ROWS_STALE`); dumpets sha er kun evidens og genspilles ordret i den genererede SQL. `bind` i en genkørsel sammenlignes ikke på `items_sha256` (B1-minor 6). Fejlkrog kun lokalt: `DAA_FAULT=step:<navn>:<before_commit|after_authorize>` giver skridtet `-v fault=…`; i prod afvist (I4).
  - `classify_next`: kun det næste skridt (`transfer_steps.py next` → `classify`); `MIXED` ⇒ exit 3.
  - `human_point <kind>`: byg nyt ark og rækkefil, kør `transfer_answers.py transfer --kind <kind> --old-* <fra gamle-ark.txt> --new-* … --expected-dropouts <pakke/bortfald-<kind>.txt>`; erratumets politik opfyldt ⇒ godkend selv (arkets sha i `godkendelser.txt` med `auto`), ellers `VENTER_GODKENDELSE <kind> report_sha256=…` og exit 10. `control` og `marriage_v3`: altid exit 10 (`VENTER_KONTROLARK` hhv. `VENTER_GODKENDELSE`), kontrolarkets D-linjer tomme.
  - **Pakkemappen** `<run>/pakke/` rummer kun pakkens input (manifester, ark, items, genereret SQL, rækkefiler, kandidatfil) og er `--private` for `inventory`, der kræver, at hver fil i mappen står i pakken (`transfer_steps.py:186-190`). Logs, digest-målinger, rapporter og `godkendelser.txt` ligger i `<run>/log/` og `<run>/rapport/`, uden for inventaret.
  - **Run-tilstand:** `12-genspil.sh` har en run-mappe pr. mål med done-loggen til `transfer_steps.py next --done`. Uden done-log (`PRE`) gælder indgangsvagterne (restore-hash, `acl_portable`, `NO_WRITE_SINCE_DUMP`, digests = pakkens start); med done-log (`PARTIAL`) er vagten alene `classify_next`. `15-undo-data.sh` arkiverer run-mappen (`<run>.fortrudt-<ts>`), og et nyt `12` efter `UNDO_OK` starter i en frisk run-mappe som `PRE`.
  - `pack_inventory_all`: `transfer_steps.py inventory-add` for hvert skridt-script, alle `\ir`-filer, digests/keymap/guards/untouched/content, arkværktøjerne og `export-input.sql`; `transfer_steps.py inventory` ⇒ ellers `INVENTORY_MISMATCH`.
- **Scripts:**
  - `restore_icu <db> <dump>` (lib): `createdb` med ICU som erratumet, `pg_restore` af D1, derefter tegnprøven (`chars_json`'s forespørgsel med `sha256()`) sammenlignet pr. tegn med prods `preflight-…/chars.json`: afvigelser ⊆ de 5 kendte, og ingen afvigende tegn i basens tekstkolonner, ellers `LOCALE_PROBE`.
  - `10-arbejdskoersel.sh init` (`restore_icu` af D1 som `daa5ab_data_arbejd_<ts>`, `measure_5ab … start`, `transfer_steps.py init`); `naeste` (kør skridt til næste menneskepunkt eller slut); `godkend <kind> <ark-sha256>` (projektejerens ja; kontrolarket kun via denne); `status`. Kun lokal: afviser prod-forbindelse.
  - `11-indholdskontrol.sh` ⇒ Task 2's projektion på arbejdsbasen og `daa244_bevis_…` + sammenligneren.
  - `12-genspil.sh <lokal-db>|prod [--jeg-mener-det]`: indgang (prod: GO 2-hashfil, freeze aktiv, restore-hash og `acl_portable` = D1's, `NO_WRITE_SINCE_DUMP`, digests = pakkens start); løkke `classify_next` → `step_replay` til slut; derefter `measure_5ab … slut`. Genkørbar.
  - `13-rehearsal-data.sh` (Task 6), `14-verify-data.sh <db>|prod` (læse-kun; `VERIFY_OK` + `verify-ok.json` via `write_marker`), `15-undo-data.sh <db>|prod --jeg-mener-det` (`undo_restore` af D1, `reconcile_grants` mod D1's ACL-linjer, `NOTIFY pgrst, 'reload schema'`, `transfer_restore_preconditions.sql`; `UNDO_OK` når restore-hash og `acl_portable` = D1's), `16-hold-varm.sh` (læse-kun `SELECT 1` mod prod), `17-go2.sh` (bygger `go2-hashes.txt`, Task 7).

- [ ] **Step 1: Skriv `test-runner.sh`** (kun syntetiske baser fra `tests/sql/fixtures/transfer-5ab-chain.sql` og `transfer-5ab-del1.sql`, ingen persondata; samme lib-funktioner med en testkædefil): `ro_args` (ukendt argument exit 2; skrivende uden `--jeg-mener-det` exit 2); `ro_prod_guards` (`DAA_FAULT` i prod-tilstand afvist før forbindelse; forkert `DAA_EXPECTED_COMMIT` ⇒ STOP; én ændret byte i en fil i `go2-hashes.txt` ⇒ `GO_HASH_MISMATCH`); `ro_capture_replay` (capture på A, `12-genspil.sh` på B ⇒ alle `WRITE` → `ALREADY_APPLIED`, digests = A's); `ro_resume` (afbrud efter skridt k i begge tilstande, genstart ⇒ fortsætter ved k+1; skridt dræbt før commit ⇒ `WRITE` igen); `ro_mixed` (én række ændret i B's lag ⇒ `MIXED`, exit 3, intet skrevet); `ro_pack_dir` (en log- eller rapportfil i `<run>/log/` giver ikke `INVENTORY_MISMATCH`; en ubundet fil i `<run>/pakke/` gør); `ro_partial` (genkørsel af `12` efter ét commit'et skridt går forbi indgangsvagterne og fortsætter; efter `15-undo-data.sh` er run-mappen arkiveret, og `12` starter som `PRE`); `ro_policy` (rapport med én `+`-linje ⇒ `VENTER_GODKENDELSE`; `marriage_v3` med kun `=` ⇒ `VENTER_GODKENDELSE`; bortfald af en nøgle, der kun står på en anden kinds liste ⇒ stop); `ro_two_tx` (et ark-skridt med to transaktioner afbrudt mellem dem ⇒ næste classify giver `MIXED`, ikke `ALREADY_APPLIED`); `ro_queue_dump` (kødumpets rækkefølge ændret, samme persona-id'er ⇒ ingen `RUNNER_INPUT_DRIFT`; én persona fjernet ⇒ `KOE_ROWS_STALE`); `ro_input_drift` (rækkefil ændret i B før et ark-skridt ⇒ `RUNNER_INPUT_DRIFT`); `ro_answer_moved` (syntetisk gammel/ny rækkefil, hvor rang 1 er en anden person ⇒ `ANSWER_PERSON_MOVED`, exit ≠ 0, runneren stopper); `ro_control_failed` (kontrolark med ét afvigende D-svar ⇒ `CONTROL_FAILED`, `corroborate` køres ikke); `ro_no_uuid` (al stdout fra alle scripts uden uuid-mønster). Slut `RUNNER_OK`.
- [ ] **Step 2: Kør** `/bin/zsh -f ~/.private/5ab-overfoersel/test-runner.sh` — Expected: FAIL.
- [ ] **Step 3: Implementér** lib-funktionerne, kædefilen og scripts 10-17.
- [ ] **Step 4: Kør** — Expected: `RUNNER_OK`.
- [ ] **Step 5: Røgtest på rigtige data:** `10-arbejdskoersel.sh` mod en engangsrestore `daa5ab_data_roeg_<ts>` til og med skridt 4, derefter `12-genspil.sh` på en anden engangsrestore ⇒ skridt 1-4 `WRITE` → `ALREADY_APPLIED`, digests ens. Noter varigheder. **Stikprøvens bortfald måles her** (Task 0 Step 7b): nøglet, hvilke ægtefællepersonas den nye stikprøve tager ud af og lægger ind i 2b-i-arket og køen sammenlignet med beviskæden, og hvor mange nye linjer der kan forudfyldes; tillægget til `forventede-forskelle.json` forelægges projektejeren som tal og godkendes (ruling) før Task 5. Kontrolarket besvares **ikke** (stikprøven er projektejerens blinde opgave i Task 5); røgbaserne kasseres efter måling.
- [ ] **Step 6:** Ingen commit (privat).

### Task 4: Uafhængigt review af runneren (før arbejdskørslen)

- [ ] **Step 1:** Kopiér kun kodefilerne (`lib.zsh`, `koer.zsh`, `kaede-5ab.txt`, scripts 10-17, `test-runner.sh`) til scratchpad; ingen data, rækkefiler, ark eller kvitteringer. Opus-agent (`model: opus`) uden databaseadgang reviewer mod denne plan, spec §6.2-§8 og B1's filer: classify kun næste skridt, inventarets dækning, prod-vagter, stderr-håndtering, genoptagelse, menneskepunkternes godkendelsespolitik, `MIXED`-vejen.
- [ ] **Step 2:** Opus afvejer hvert fund (nødvendig / forenkl / kendt begrænsning / afvis); ret, kør `test-runner.sh` igen ⇒ `RUNNER_OK`. Review og afvejning noteres privat; antal fund pr. alvor rapporteres til projektejeren.

Begrundelse for placeringen: en runnerfejl midt i capture koster projektejerens 30 blinde kontrolsvar igen.

### Task 5: Arbejdskørslen (privat; projektejerens ark)

- [ ] **Step 1: Godkendelsespolitikken** (erratum ovenfor) er godkendt af projektejeren 2026-10-23, sammen med G0 og forudfyldningen (Task 1).
- [ ] **Step 2:** `10-arbejdskoersel.sh init` ⇒ `INIT_OK` og start-målingen lig D1's (`restore_hash` `a60e02a8…`, `n_uuid_unmapped` 0).
- [ ] **Step 3:** `naeste` ⇒ skridt 1-4, `VENTER_KONTROLARK`. Projektejeren besvarer arkets D-linjer blindt (R-linjerne er overført; deres rapport læses med). Antal kort oplyses (≤ 40, H11).
- [ ] **Step 4:** `godkend control <sha>` + `naeste` ⇒ skridt 5-6; ved `CONTROL_FAILED` stopper planen (sag for sig).
- [ ] **Step 4b:** Stikprøven i arbejdsbasen er lig røgtestens (samme `stikproeve:`-nøgler); ellers STOP. Tillægget fra Task 3 Step 5 gælder derfor uændret.
- [ ] **Step 5:** `naeste` gentages; ved hvert `VENTER_GODKENDELSE` læser projektejeren rapporten (kun `~`/`+`/`-`-linjer vises øverst), besvarer `+`-linjerne og godkender med `godkend <kind> <sha>`. Forventet stop: v3 altid (de 2 OBS-linjer); 2b-i-arket og køen, hvis stikprøven giver `+`-linjer; kø-rapporten kan bære `~ plads`-markeringer. Efter skridt 9: 0 nye `change_set`.
- [ ] **Step 6:** Efter skridt 25: værn som kædefilen; `measure_5ab … slut`; kanonisk delta 0 (`canonical_sha256` = `a51323ac…`); `n_uuid_unmapped` 0; `family_sources` 253; bindinger 253 nye.
- [ ] **Step 7:** `11-indholdskontrol.sh` ⇒ `CONTENT_OK`. `CONTENT_UNEXPECTED` ⇒ STOP; rapporten forelægges (antal og lag i chat, detaljer kun i filen).
- [ ] **Step 8:** `transfer_steps.py validate` og `pack_inventory_all` ⇒ `PACK_OK`, `pack_sha256` noteret.

### Task 6: Genspilsprøven (privat) ⇒ `REHEARSAL_OK` (data)

- [ ] **Step 1:** `13-rehearsal-data.sh` laver `daa5ab_data_genspil_<ts>` (`restore_icu` af D1, `PGTZ=Pacific/Chatham`) og kører `12-genspil.sh` på den ⇒ alle 25 skridt `WRITE` → `ALREADY_APPLIED`, slut-digests = arbejdskørslens, `14-verify-data.sh` ⇒ `VERIFY_OK`.
- [ ] **Step 2:** Anden gennemkørsel af `12-genspil.sh` på samme base ⇒ alle `ALREADY_APPLIED`, intet skrevet.
- [ ] **Step 3: Genkørselsprøve** på en ny restore, kørt som stand-in med prod-tilstandens vagter aktive (GO 2-hashfil, indgangsvagter): `DAA_FAULT=step:decide_2a:before_commit` og `DAA_FAULT=step:disposition_2bii:after_authorize` ⇒ fejl, digests = før; genkørsel (`PARTIAL`) ⇒ fortsætter og ender som Step 1; `authorizations_issued` +1 rapporteret; `14-verify-data.sh` udelader `authorizations_issued` fra sammenligningen.
- [ ] **Step 4: Indgangsvagter** på en stand-in (restore af D1 med én ændret `change_set` efter `dump_start` og én ekstra grant) ⇒ `NO_WRITE_SINCE_DUMP` hhv. `ENTRY_ACL` før første skrivning.
- [ ] **Step 5: Fortrydelsesøvelse:** `15-undo-data.sh` på Step 1's base ⇒ `UNDO_OK` (restore-hash og `acl_portable` = D1's, `transfer_restore_preconditions.sql` bestået, `pg_restore`-fejllisten læst og talt).
- [ ] **Step 6: Diagnostisk locale-kørsel** (libc `en_US.UTF-8`, som de tidligere lokale baser): `12-genspil.sh` + `14-verify-data.sh`; resultatet (lag, der afviger, eller `VERIFY_OK`) skrives i rapporten; ikke en gate (erratum).
- [ ] **Step 7:** Alt i Step 1-5 bestået ⇒ `REHEARSAL_OK` (data) i `rehearsal-data.json` med varighed pr. skridt.

### Task 7: GO 2-pakken, review og runbook

**Files:**
- Create: `docs/runbooks/transfer-5ab-data-prod.md`
- Modify: `docs/decisions.md`

- [ ] **Step 1: `17-go2.sh`** bygger `go2-hashes.txt`: D1-kvitteringens sha, `restore_hash`, `acl_portable`; `pack_sha256`; arbejdskørslens start- og slut-digests; hvert nyt arks sha med gammel arkhash, de to nøglekortfilers sha (oversættelsestabellen), oversættelsesrapportens sha og godkendelsesmåde (`auto`/`menneske`); kontrolarkets sha; indholdskontrollens rapport-sha; `rehearsal-data.json`'s sha; `actor_sha256`; repo-commit (`DAA_EXPECTED_COMMIT` = main efter Task 7's docs-merge; inventaret binder stadig Task 1-2's bytes); inventaret (som mængde, `verify_go_hashes`).
- [ ] **Step 2: Runbook** efter `transfer-5ab-ddl-prod.md`'s afsnit: forudsætninger, hold varm, indgang, GO 2, genspil i prod, `VERIFY_OK` og `00-freeze.sh end`, fortrydelse (`15-undo-data.sh`), efter `VERIFY_OK`. Kommandoer som `! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh <script> …`.
- [ ] **Step 3: decisions.md:** én post: godkendelsespolitikken (Task 5 Step 1), H3, #244 »opstod aldrig i prod« (spec beslutning 4), aktørforskellen i 2a's bevisbase, modenheden efter beslutning 8. Udgavenavne (spec §11): ingen nye i permanente overflader; kædefilen er privat, og `transfer_5ab_content.sql` tager kilden som argument.
- [ ] **Step 4: Fable-review** (stående ja til reviews) af `go2-hashes.txt`'s struktur, runbooken og en kodekopi som Task 4 Step 1; Opus afvejer fundene; ret.
- [ ] **Step 5: Projektejeren læser alle overførselsrapporter samlet** (også de auto-godkendte) og bekræfter i chatten; bindes i GO 2.
- [ ] **Step 6: Commit** `docs(151): runbook for data-ceremonien (GO 2) og beslutninger`; draft-PR efter ja.

### Task 8: Data-ceremonien i prod (projektejeren)

- [ ] **Step 1:** `16-hold-varm.sh`; indgang `12-genspil.sh prod` uden `--jeg-mener-det` ⇒ `ENTRY_OK` (intet skrevet).
- [ ] **Step 2:** GO 2 (projektejerens ord i chatten, bundet til `go2-hashes.txt`'s sha).
- [ ] **Step 3:** `12-genspil.sh prod --jeg-mener-det` ⇒ 25 skridt `WRITE` → `ALREADY_APPLIED`. Ved afbrud: kør igen (`PARTIAL`). `MIXED` eller uoprettelig fejl ⇒ `15-undo-data.sh prod --jeg-mener-det`, ret, genspil.
- [ ] **Step 4:** `14-verify-data.sh prod` ⇒ `VERIFY_OK` (digests = arbejdskørslens, kanonisk delta 0, uberørt og andre kilder uændrede, `anon`-matrix = D1's, 0 nye personer); `08-advisors.sh` ⇒ kun kendte mønstre; `00-freeze.sh end` ⇒ skrivepausen ophævet.
- [ ] **Step 5: Docs:** `status.md` (5a og 5b's personas, identiteter, bindinger, børnehenvisninger, dispositioner, klassifikationer og P-afvisningen ⇒ `produktionsverificeret`; nye personer og #244's rettelsesvej forbliver `isoleret implementeret`), `changelog.md`, `database-current-state.md`; hukommelsen opdateres. Commit `docs(151): 5a+5b's data i prod (GO 2)`.

## Revision efter Fable-review (2026-10-23)

GO med rettelser i alle task-grupper; 0 BLOCKER, 7 MAJOR, 7 MINOR. Efterprøvet mod koden før afgørelsen
(`schema.sql:16489-16491`, `transfer_steps.py:186-190`, `transfer_answers.py:275`, `relation_persona_apply.sql:28-29`).

| Fund | Afgørelse |
| --- | --- |
| M1 ny stikprøve flytter linjer på 2b-i-arket og køen | Godtaget: Task 0 Step 7b, målt i Task 3 Step 5, kontrolleret i Task 5 Step 4b; `+`-linjer kræver altid frisk svar, forudfyldt med det gamle blinde kontrolsvar, hvor personen står på linjen (Task 1) |
| M2 korroboration returnerer 0 ved fejlet kontrol | Godtaget: Task 1 `STEP_CONTROL_NOT_PASSED`; gate i kædefilen n=6 |
| M3 `child_sheet` mangler `parties` | **Afvist:** børnegrenen returnerer før part-indsættelsen (`schema.sql:15841-15842`); `decide_relation_child` kalder kun `red_decide_interpretation` |
| M4 indgangsvagt mod genkørsel; tilstand efter fortrydelse | Godtaget: `PRE`/`PARTIAL`, arkivering af run-mappen; `ro_partial`, Task 6 Step 3 |
| M5 auto-politikken | Godtaget: præcis politik i erratumet; `ro_policy` |
| M6 flad bortfaldsliste | Godtaget: lag `sheet:<kind>`, én fil pr. kind |
| M7 inventar over hele run-mappen | Godtaget: `<run>/pakke/` adskilt fra log og rapport; `ro_pack_dir` |
| m1 døde `may_differ`-poster | Godtaget (Task 0 Step 6) |
| m2 `O … B`-linjer er kanonisk skrivning | Godtaget (Task 0 Step 5, Task 5 Step 5) |
| m3 `00-freeze.sh end --efter-verify` | Delvis: `end` uden flag kræver allerede `verify-ok.json`; præciseret i Global Constraints |
| m4 `actor_sha256` og commit i GO 2 | Godtaget (Task 7 Step 1) |
| m5 writer-stdout bærer uuid'er | Godtaget (kædefilen) |
| m6 `RUNNER_INPUT_DRIFT` for dispositioner; `authorizations_issued` | Godtaget (Task 3, Task 6 Step 3) |
| m7 død `\if` i corroborate | Godtaget (Task 1 Step 3) |
