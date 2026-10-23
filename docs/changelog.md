# Changelog

## 2026-10-22 — #151: værktøj til data-ceremonien for 5a+5b (plan B1)

Implementeret efter planen `2026-10-22-trin5ab-overfoersel-b1-vaerktoej.md` på `docs/151-5ab-overfoersel-b1`.

- **Digests:** `transfer_5ab_keymap.sql` (nøglekort), `transfer_5ab_digests.sql` (21 lag; `mode=rows`, `mode=unmapped`),
  `transfer_5ab_untouched_hash.sql` (uberørt og andre kilder) og `transfer_5ab_guards.sql` (nye personer, nummerrettelser,
  bogens »N°«). Alt læse-kun.
- **Skridt-SQL:** `transfer_5ab_step_{profile,decide,bind,disposition,reject,candidates,control,corroborate}.sql` med
  fælles ind- og udgang; eksplicit aktør; `relation_batch_apply.sql` har fået en fejlkrog mellem sine to transaktioner.
- **Python:** `identity_queue_sheet.py` (køens ark), `transfer_answers.py` (svaroverførsel), `transfer_steps.py` (pakken).
- **Tests i CI:** `test-transfer-5ab-digests.sh`, `test-transfer-5ab-steps.sh`, `test-transfer-5ab-del1-steps.sh` og tre
  pytest-filer. Beslutning: decisions 2026-10-22. Prod er uændret.

## 2026-10-22 — #151: 5a+5b's DDL i prod (GO 1)

Ceremonien efter `docs/runbooks/transfer-5ab-ddl-prod.md`, repo `7c645632`, kørt af projektejeren.

- **Fase 0 og D0** (læse-kun): skrivepause, preflight (`locale_compared=true`; DDL-rolle `postgres`, 48 skema-defaults i
  `public`, global række lukker `PUBLIC EXECUTE`), D0 12,8 MB verificeret ved fuld lokal restore.
- **Rehearsal på D0:** første kørsel stoppede på `LOCAL_PARTS_CHANGED (acl, over apply)`: den lokale DDL-rolle manglede prods
  globale funktionsrække, så `db-rls.sql` oprettede den lokalt (i prod findes den). Emuleringen i den private `lib.zsh`
  kopierer nu også den globale række; derefter `REHEARSAL_OK` (apply 1 s, open_exec 26/0/27/0, fortrydelse `0|16`).
- **Sikkerhedsrådgiver:** MCP-connectoren ser ikke DAA-basen, så `supabase db advisors` køres via det nye private
  `08-advisors.sh`. Prod før = rehearsal før (48 linjer identiske); forventet og målt: 12 nye `rls_enabled_no_policy`
  (de 12 nye `private`-tabeller). CLI'en dækker færre lint-typer end dashboardet (fx ikke
  `authenticated_security_definer_function_executable`).
- **GO 1 → `DDL_OK`** (fra `PRE`, `DATA_DELTA_OK changed=3 new=12`), `DDL_VERIFY_OK advisors=ok`, D1 13,1 MB verificeret.

## 2026-10-21 — #151: DDL-ceremonien for 5a+5b-overførslen (plan A)

Implementeret efter planen `2026-10-21-trin5ab-overfoersel-a-ddl.md` på `docs/151-5ab-overfoersel-a`.

- **Repo:** `transfer_catalog_fingerprint.sql` og `transfer_acl_fingerprint.sql` (portabel og prod-lokal del),
  `transfer_table_hashes.sql`, `transfer_ddl.py` (afbrudsfiler, fortrydelsens DROP-liste, datadelta) og
  allow-listen for DDL'ens datadelta. Tests: `test_transfer_ddl.py` og `test-transfer-fingerprints.sh` i CI;
  `test-transfer-5ab-ddl-upgrade.sh` kun lokalt (fra prods træ `b42266e`).
- **Privat ceremoni** (`~/.private/5ab-overfoersel/`) bygget og øvet på stand-in: fase 0, D0/D1 med check-restore,
  rehearsal, DDL, probe og fortrydelse. Runbook: `docs/runbooks/transfer-5ab-ddl-prod.md`.
- **Beslutning:** 5a's 31 kalibreringsafgørelser overføres ikke (decisions 2026-10-21). Prod er uændret.

## 2026-10-21 — #151: id'er af indholdet (forudsætning for overførslen af 5a+5b)

Implementeret efter planen `2026-10-21-trin5ab-indholds-id.md` på `feat/151-indholds-id`.

**Indhold:**
- **Hjælper:** `private.content_uuid(kind, key)` oven på `private.deterministic_uuid`; `kind` og `key_version` adskiller arter og nøgleversioner.
- **8 rækkearter med id af indholdet:** ægtefællepersona og omtale (`write_relation_persona`), identitetshændelse (`decide_source_persona_identity`, alle oprindelser), kandidatkørsel og kandidat (`red_record_identity_candidates`), kontrolkørsel, stikprøve og forældrekort (`red_register_identity_control_run`). Kollision ⇒ `DETERMINISTIC_ID_COLLISION: <art>`, også når den opstår som `unique_violation`.
- **Trækning efter indhold:** `control-sample-v2` og `control-display-v2` (erratum til 5b-spec'ens §23.3 pkt. 4).
- **Arkværktøjer:** 2b-i's `O`-linjer nøgles på fortolkningsnøgle og version (`spouse-exception-rows-v2`; v1 afvises med `SHEET_CONTRACT_UNSUPPORTED`/`SHEET_LINE_INVALID`); v3-arket viser ikke længere datoen for den tidligere afgørelse; kontrolarkets rækkefil har en total rækkefølge; tekstsortering med `COLLATE "C"` og låst `TimeZone`/`search_path`.
- **Migration:** én afsluttende blok i `db-migrations.sql`; CI-paritet mellem ren `schema.sql` og migreret base (`tests/sql/inspect-5ab-function-parity.sql`).

**Bevis (lokalt, ikke prod):**
- Hovedtesten `tests/sql/test-indholds-id-determinism.sh`: samme kæde i to baser (C mod ICU-`da`, UTC mod Pacific/Chatham, forskellig forhistorik). Rød mod den gamle kode (alle 8 arter og alle artefakter afveg), grøn efter.
- Opgradering fra prods træ `140a17b` med migrationerne to gange: 5a/5b-SQL-testene, hovedtesten og db-verify grønne (`tests/sql/test-indholds-id-upgrade.sh`).

Ikke deployet; deployes i overførslens DDL-ceremoni.

## 2026-10-20 — #244: ægteskabsnumrene efter skriverens vindue; 4 numre rettet på ark (#151)

Implementeret efter planen `2026-10-20-244-aegteskabsnumre.md` på `fix/244-aegteskabsnumre`.

**Indhold:**
- **Rodrettelse:** `private.relation_marriage_ordinals` finder påstandens placering med `private.relation_ordered_windows` (samme vindue som skriveren). Årsagen var en parentes midt i klausulen, ikke en overskreden klausulgrænse.
- **Værn:** `private.relation_book_ordinal` læser bogens »g. N°«/»gift N°«; `write_relation_persona` afviser med `…_ORDINAL_BOOK_MISMATCH`, og regelen i `relation_persona_extract_v3.py` giver `U nummer_modsiger_bog`.
- **Rettelse:** tabellen `private.marriage_ordinal_correction` (tilføj-kun) og skriveren `red_ret_aegteskabsnummer`, der skriver en ny ægtefællepart med `origin='ordinal_correction'`. Arket `relation_ordinal_sheet.py` med projektionen `red_marriage_ordinal_correction_input`.

**Bevis i restore (ikke prod):**
- 4 numre rettet via et hash-bundet ark med 4 linjer; 4 genbindinger i samme familie.
- 0 kanonisk delta, `family_member.ordinal` uændret, negativtest 6/6 afviser.

**Kendt begrænsning:** prod-genspil af de autoriserede payloads kræver et valg i overførsels-spec'en.

Rapport: `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md`. Ikke deployet.

## 2026-10-20 — trin 5b del 2b-iii: børneflokkene binder til familien (#151)

Implementeret efter planen `2026-10-20-trin5b-2b-iii-boernehenvisninger.md` på `docs/151-5b-2b-iii`.

**Indhold:**
- **Parser:** `private.relation_child_ref` læser bogens børnehenvisning.
- **Regel:** `private.relation_child_rule` (`relation-child-v1`).
- **Writer:** `red_afgoer_relation_interpretation` får en børnegren, der kun kan bruges via arket og uden familie-id. `RELATION_CHILD_DEFERRED` er fjernet.
- **Binding:** `relation_binding_state` genberegner reglen mod familien, som den ser ud nu.
- **Læser:** `public_family_sources` giver `slags='boern'`.
- **Ark:** `relation_child_sheet.py` med projektionen `red_relation_child_sheet_input`.
- **Web:** viser børneflokkens kilde ved forælder og barn.

**Bevis i restore (ikke prod):**
- 12 bindinger (253 synlige kilderækker) og 12 børnekilder synlige for anonyme læsere.
- 0 kanonisk delta, og negativtest A-D afviser.
- 2 påstande står `proposed`.

**Fund:** en trykfejl i bogen.

Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md`. Ikke deployet.

## 2026-10-20 — trin 5b: P-linjens forkerte ægteskabsfortolkning afvist i bevisbasen (#151)

Fortolkningen gik fra `proposed` v1 til `rejected` v2 gennem `red_decide_interpretation`. Kanonisk lag og læsning er uændrede. Se tilføjelsen »Efterfølgende« i `relationspersonas-5b-navneregel-v3-bevis.md`. Ikke deployet.

## 2026-10-20 — trin 5b del 2b-ii runde 2: navneregel v3 over de 12 `U`-ægteskaber (#151)

Implementeret efter planen `2026-10-18-trin5b-2b-ii-runde2-navneregel-v3.md` på `docs/151-5b-navneregel-v3`.

**Indhold:**
- **Navneregel v3** (`relation_persona_extract_v3.py`):
  - lukket titelliste med `rigs-`/`lens-`;
  - partiklerne und/zu/dem/genannt;
  - efternavnsbaseret partnertræf;
  - afkortningsvagt og løst dubletværn før D/N.
- **SQL-tvillingen** `private.relation_name_has_title`.
- **Persona-profil v3** med arkets hash i kvitteringen.
- **`write_relation_person_create`** afviser nu titel i navnet, forældet klausul og forældet fortolkning.
- **Ark v3** (`relation_marriage_sheet_v3.py`) med `navn:`-rettelse og `P`-linjer.
- **Læsefunktionen** `red_relation_persona_v3_input`.

**Bevis i restore (ikke prod):**
- Arket gav S 9 og U 3. P-linjen blev besvaret U, fordi fortolkningen er forkert, og den skal afvises særskilt.
- Kørslen gav 9 nye bindinger (241 synlige kilderækker) og 9 disponerede klausuler.
- 0 kanonisk delta, og negativtest A og C afviser.
- 0 nye personer: oprettelsen er stadig kun bevist på syntetiske data.

**Fund:** systemets ægteskabsnummer bliver forkert, når påstandens tekst rækker ud over klausulen. Det giver 4 falske ordinal-afvigelser, som rettes i en separat runde.

Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md`. Ikke deployet.

## 2026-10-18 — trin 5b del 2b-ii: nye afdøde ægtefæller, de 14 ægteskaber og klausul-dispositionen (#151)

Implementeret efter planen `2026-10-17-trin5b-2b-ii.md` på `docs/151-5b-2b-ii`. Indhold:
- `family.id` som identity i fersk schema (migrationen løfter kun sekvensen);
- writer-operationen `relation_person_create` (ny afdød ægtefælle efter aldersreglen ≤ 1906, `staged`, `levende=false`) med ny identitetsoprindelse;
- persona-profil v2 med entydigt minimalt ordvindue og et hash-bundet ægteskabsark (`relation_marriage_sheet.py`);
- writer-operationen `relation_disposition` (regel identitet pr. aktør);
- en opgraderingstest.

Bevis i restore (ikke prod): arkets 14 linjer gav S 2 og U 12, efter at projektejeren rettede 10 af regelens forslag. Det gav 2 nye
bindinger (232 synlige kilderækker), 0 nye personer og 122 disponerede klausuler. 0 kanonisk delta, og negativtest A-F afviser.
Fundene til næste runde er titler inde i adelsnavne, partikler i partnersammenligningen, henvisningsår i aldersreglen og
klausulopdelingen. Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-2b-ii-bevis.md`. Ikke deployet.

## 2026-10-13 — trin 5b del 2b-i: genbinding, undtagelsesark for ægtefæller og køen afgjort (#151)

Implementeret efter planen `2026-10-12-trin5b-2b-i.md` på `docs/151-5b-2b-i`. Indhold:
- genbinding efter rettelse (2a-spec §11 pkt. 6, mulighed a) med den nye klassifikation `ordinal_beholdt`;
- hash-bundet undtagelsesark (`spouse_exception_sheet.py` over `private.spouse_exception_projection`);
- webkøen viser årsagen og hovedpersonens faktiske partnere;
- en opgraderingstest fra 2a's head.

Bevis i restore (ikke prod): de 31 ægtefæller fra 2a er afgjort, 22 via arket og 9 via køen (5 samme, 3 uafklaret,
1 ny person). 20 nye bindinger, så der nu er 230 synlige kilderækker. 0 kanonisk delta og 4 negativtests. 7 ægteskaber
fejler lukket på grund af dobbelte familier (#240). Efter Opus' kode-review er to fund rettet: strengsemantikken låst
og tomt ægteskabsnummer. Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-2b-i-bevis.md`. Ikke deployet.

## 2026-10-11 — trin 5b del 2a: afgjorte ægteskaber og forældre bundet, kilden vist (#151)

Implementeret efter planen `2026-10-11-trin5b-2a-binding.md` på `docs/151-5b-2a-binding`: regeltypen
`structural_family` adskilt fra assertion-vejen, `private.relation_binding_state` (én tilstand og hash for
afgørelse, binding og læsning), versionsbundne klassifikationer, kildebundet maskinafgørelse
(`red_preview_relation_decisions`/`red_decide_relation_interpretations`), hash-autoriseret binding med replay
(`red_preview_relation_promotions`/`red_promote_relation_interpretations_batch`), offentlig
`public_family_sources` og kildelinjen i `DetailPanel`. Bevis i en kopi af del 1's bevisbase (ikke prod):
203 afgjort, 210 bundet, 210 synlige kildelinjer, 0 kanonisk delta, 4 negativtests. Rapport:
`docs/evidensbaseret-genimport/relationspersonas-5b-2a-bevis.md`. Ikke deployet.

## 2026-10-11 — trin 5b del 1: ægtefællers personas og maskinel bekræftelse, bevist i restore (#151)

Implementeret efter planen `2026-10-06-trin5b-del1-identitet.md` og tillægget `2026-10-10-trin5b-del1-kontrolkort.md`
på `feat/151-5b-del1` (#237, `ebf2022`): relationsparter og relationspersona-writer, deterministisk udtræk af
ægtefællenavne (kun navne), familiekontekst i kandidatinputtet, kontrolkørsel med blind stikprøve (alle navnefæller +
`K` = 20 tilfældige), kontrolark med ægtefælle- og forældrekort (dublet-svar `1=2`), og den private kerne med den nye
oprindelse `family_corroboration`. Bevis i en kopi af den fulde 2018-20-kørsel (ikke prod): 234 ægtefælle-personas,
203 egnede; arket (30 ægtefællekort, 9 forældrekort) gav 0 afvigelser ⇒ `passed` ⇒ 173 bekræftet maskinelt; øvre
95 %-grænse ca. 13,9 % (advarselslampe). Børn, 31 uoverensstemmelser, nye personer og familiekorrektion er del 2.
Rapport: `docs/evidensbaseret-genimport/relationspersonas-5b-del1-bevis.md`. Ikke deployet.

## 2026-10-05 — trin 5a: én identitetsvej, bevist i restore (#151)

Implementeret efter planen `2026-09-24-trin5a-identitetsvej.md` på `feat/151-identitetsvej`: kandidattabeller
og servergenberegnet writer, privat identitetskerne `private.decide_source_persona_identity(…, p_origin)` med
oprettelseskvittering og cutover-blok øverst i `db-migrations.sql`, `red_afgoer_source_persona` med kontekst og
udgangen `new_person_needed`, kø/detalje med kandidater og kollisioner, generatoren `@daa/identity-candidates`,
identitetsarket og webkøen. Bevis i en kopi af den fulde 2018-20-kørsel (ikke prod): kalibrering — std top-1
228/250 navngivne, `auto` 159/159 (øvre grænse: facit er 149b's kobling); blind genbekræftelse 30 + webspor —
25 samme, 0 anden, 6 uafklaret; negativtest ruller atomisk tilbage. Rapport:
`docs/evidensbaseret-genimport/identitetsvej-5a-bevis.md`. Ikke deployet.

## 2026-10-05 — 2018-20's fortolkningskæde overført til prod (#147)

Efter projektejerens GO er hele 2018-20's kæde skrevet i prod efter runbooken
`runbooks/transfer-2018-20-prod.md`: 3.739 forslag, 676 afgørelser (602 maskinelle, 61 A og 13 U fra
kontrolarket) og 622 bindinger fra pakken `07355ccc…`. Skrivepause, preflight og dump (10,7 MB) gik
forud; generalprøven på netop dette dump gav `REHEARSAL_OK` med pakkens tre digests og en øvet
fortrydelse tilbage til `EMPTY`. I prod: `APPLY_OK` i første forsøg (dry-run 186 s og apply 222 s over
poolerens netforbindelse mod 16 s og 12 s lokalt; ingen enkeltsætning nær grænsen), `DECIDE_OK` (36 s),
`BIND_OK` (10 s) og `VERIFY_OK`: tilstand `COMPLETE`, digests `bb808efe…`/`33fc4b56…`/`5762ceaa…` lig
pakken, alle 676 afgørelser med pakkens hash, baseline, uberørte tabeller og grants uændret, `anon`
kan ikke læse kæden. Pausen sluttede med `FREEZE_END_OK mode=verify`. Ingest og afgørelse er nu
`produktionsverificeret` for 2018-20; promotion kun for bindingsdelen. Omsegmenteringens
fortrydelsesvindue er lukket; pausens dump er det nye restorepunkt.

## 2026-10-05 — prod-overførslen af 2018-20 er klar til GO (#147, plan B)

Ceremonien for den samlede overførsel (3.739 forslag, 676 afgørelser, 622 bindinger fra pakken
`07355ccc…`) er bygget som private scripts og øvet mod lokale stand-ins af prod: hele kæden, genkørsel
(`ALREADY_APPLIED`), afbrud midt i forslagene, forkert grundlag, fortrydelse og 11 angrebstest. En
læse-kun probe af prod (2026-10-04) bestod alle gates; prods tidsgrænse på 2 min pr. sætning er
accepteret, fordi hvert trin tager højst 17 s lokalt, og `07`/`08` selv sætter 15 min. Én af 14 øvelser
hang i `07` og blev rullet tilbage af tidsgrænsen; det kunne ikke genskabes og har sin egen stopregel.
Runbook: `runbooks/transfer-2018-20-prod.md`. Intet i prod endnu; ceremonien kræver projektejerens GO.

## 2026-10-03 — hele 2018-20 gennem fortolkningskæden i én base (#147)

Efter projektejerens GO på manifest `f5a76e1b…` er alle 488 tilladte poster i 2018-20 sendt til
`gpt-5.6-terra` (365 nye kald, 123 fra cache) i en lokal kopi af et frisk prod-dump: 488/488 dækket,
3.758 gyldige claims. Ingest gav 3.739 forslag, præcis som forudsagt (#229 sorterede ét claim fra på en
post uden persona). Kontrolmodellen gav 74 kort (20 stikprøve + 54 uoverensstemmelser); projektejeren
afgjorde 61 A og 13 U (ark `25d47d5b…`), 602 blev accepteret maskinelt, og 622 er bundet i ét batch
uden kanonisk delta. Pilotens 34 poster og 46 bindinger er identiske. De 13 U er navne med titel eller
»til <gods>« i værdien — besluttet holdt ude af navnet (decisions 2026-10-03). Fund: runneren kender
ikke codex' nye kvotefejl; 138 navne-assertions i databasen har titelord. Rapport:
`evidensbaseret-genimport/2018-20-fuld-koersel.md`. Intet i prod. Næste: spec for den samlede
prod-overførsel.

## 2026-09-28 — 4.4 genbundet: piloten kørt om på de omsegmenterede klausuler (#147)

Efter P1's værn (#226, `evidence-runner-1.3`) og projektejerens GO på manifest `72b8ac59…` og
runner-input `0b51ed9a…` er de 34 pilotposter sendt til modellen igen fra `main`, i en lokal kopi af et
frisk prod-dump: 34/34 dækket, 0 værktøjsbrug, 597.185 input-tokens. Ingest gav 230 forslag, præcis som
forudsagt før kørslen. Kontrolmodellen gav 24 kort (20 stikprøve + 4 uoverensstemmelser); projektejeren
accepterede alle 24 (ark `2500531c…`), 26 blev accepteret maskinelt, og 46 er bundet i ét batch uden
kanonisk delta. Runnerens nye regler og basens fakta er målt til nul forskel mod 4.5; de to kendte
»var †«-fejllæsninger (I-11, I-7) er væk. Rapport: `evidensbaseret-genimport/genbind-44-pilot-2018-20.md`.
Intet i prod. Næste: 4.4+4.5's prod-GO-pakke (egen GO).

## 2026-09-28 — omsegmentering kørt i prod: 51 poster, `match` (#147, review 35 P3/S4)

#222's DDL (klausulsæt, `clause_revision`, S4 — og #212's hjælpefunktioner, som den bygger på) og 51
revisioner er skrevet til prod efter `docs/runbooks/clause-revision-prod-apply.md`: 116 klausuler
skrevet, 197 markeret `erstattet`, komparatoren `match`, intet kanonisk delta
(`database-current-state.md` §9). Fortrydelse er en ny revision tilbage til 4.1b's opdeling (øvet).

Operatørpakken (`~/.private/omseg-prod/`, privat) gik igennem tre review-runder. R2 fandt en blokker:
EXIT-trap'en i en zsh-funktion slettede adgangskoden straks, og stand-in-testene kunne ikke se det.
R3 fandt to blindgyder efter en afbrudt skrivning. Alle er rettet og testet på stand-ins; genkørslen
af 04 er bevist på en ægte deadlock mellem `db-rls.sql` og autovacuum. En læse-kun prøve i prod fandt,
at anon-hashen over `x::text` afhænger af serverens locale (0xA0 i `à` citeres på macOS, ikke på Linux),
så 03 ville have stoppet på dagen; prod ↔ restore sammenlignes nu med en portabel hash over
`to_jsonb(x)::text`. Næste: 4.4's GO-pakke genbindes til de reviderede klausuler.

## 2026-09-27 — omsegmentering bygget og øvet mod prod-dump: 51 poster, fortrydelse uden restore (#147, review 35 P3/S4)

#222 gav klausulerne sæt: `clause_set_seq` (NULL = sæt 1, så prods 868 klausuler er urørte), et
unikhedsindeks pr. sæt, viewet `clause_observation_current` og fire selvstændige triggere, der holder
invarianterne, også hvis en historisk migrationsblok genskaber gamle funktionskroppe. Den nye
writer-operation `clause_revision` skriver et nyt sæt og markerer det gamle `erstattet`; den afviser, når
et forslag eller et menneske allerede bygger på det aktuelle sæt, og når basen er skredet siden
manifestet. S4: ét forslagsbatch pr. post, og citater kun i det aktuelle sæt. To kodereview-runder gav
GO; seks mindre fund rettet — fem fra første og ét fra anden runde (bl.a. rækkelås i sæt-reglen, bevist med to samtidige sessioner).

Rehearsal mod et frisk læse-kun dump: DDL'en ren to gange, 51 poster revideret (116 klausuler skrevet,
197 erstattet), fortrudt med en ny revision tilbage til 4.1b's opdeling og kørt frem igen — alle tre
`match`, intet kanonisk delta, uændrede anon-hashes. Manifestet var byte-identisk med målingen fra
restore-kopien. Planfilen var aldrig nået `main` (squash-merge før push) og er lagt ind.

## 2026-09-27 — klausulerne segmenteres om før 4.4; runnerens cache kender nu klausulsættet (#147, review 35 P3/P4)

En måling af 2018-20's klausuler (kun tal) viste, at en rettet segmenter ændrer 25-42 af de 101
poster med mere end én klausul, heraf 8 af pilotens 32; begge pilotens kendte fejl ligger i dem.
Projektejeren besluttede at segmentere om før 4.4 med en ny writer-operation frem for restore
(`decisions.md` 2026-09-27). Første skridt, P4, er gennemført: klausulsættet indgår i
runnerens cache-nøgle (`evidence-runner-1.2`, nøglen udledes efter identitetens kontrakt, så
4.5's forslagsmanifest genbygges byte-identisk), runneren afviser en nøgle for en anden
segmentering, og `segmenter_version` afledes af koden i stedet for den hårdkodede `@v1`.

## 2026-09-27 — kontrolmodellen bygget og kørt: samme 43 bindinger med 26 kort i stedet for 243 (#147)

Beslutningen 2026-09-27 er implementeret uden DDL: en læse-kun klassifikation over `proposed`
(`interpretation_control_classification.sql`, bevist enig med målfindingen), rækkeeksporten som fil og
`control_model.py` (deterministisk stikprøve på 20, gate hvor `R` eller `U` i stikprøven er STOP,
maskinel accept som `machine-corroboration-v1`, mængdekontrol før binding). Første kørsel i en kopi af
restoren med 4.5's forslag genafspillet: 43 `MATCH`, 16 skrivemåde, 6 uden faktum, 6 reelle
uoverensstemmelser; 26 kort for projektejeren, 23 maskinelle; bindingerne er identiske med 4.5's.

Den rigtige kørsel fandt en fejl, testene ikke kunne se: stikprøvekontrollen kørte efter rolleskiftet
til `authenticated`, som ikke kan læse `private`, og afviste derfor af forkert grund. Rettet med test.
Projektejeren fandt under gennemlæsningen en fejl mere i 4.5 (I-7, »var † [dato], da …« læst som
dødsdag); 4.5's præcision er rettet til 241/243.

## 2026-09-26 — 4.5-piloten gennemført i restoren: kvaliteten holder, afgørelsesmodellen ikke (#147)

Projektejerens afgørelsesark (243 linjer, hash `98bb9a21…`) er skrevet i arbejdsbasen efter en
negativtest, der beviste fuld rollback ved versionskonflikt på sidste afgørelse. 242
`accepted`, 1 `rejected`; 0 afvisninger blandt 159 nye forslag. Backup før binding, derefter
43 bindinger i ét batch; `fact`/`assertion` uændrede, genkørsel giver 43 `ALREADY_PROMOTED`.
Af 27 uden bindingsmål er 16 skrivemåde, 6 mangler et kanonisk faktum, 5 er reelt forskellige.

Pilotens afgørende måling er menneskets tid: arket tog flere dage, og resten af 2018-20 ville
kræve ≈ 3.450 afgørelser. Dom (udkast): kvalitet GO, fuld kørsel NO-GO med den nuværende
afgørelsesmodel. Kontrolmodel med kun uoverensstemmelser og stikprøve FORESLÅET i
`decisions.md`.

Samme dag: runneren er `evidence-runner-1.1` — et dato-claim afvises, hvis datoen ikke står
ordret i den citerede klausul (review 35, P10). Pilotrapporten havde påstået, at 1.0 gjorde
det; den tjekkede kun formen.

## 2026-09-20 — restpunkterne fra sikkerhedsgennemgangen lukket (#198, #208, #209)

Sidste del af dagen. Sikkerhedsfladen har ingen kendt udestående gate-lækage.

**#198 — db-verify efterlod en forældreløs evidens-kobling.** Årsagen var ikke en glemt
`DELETE`, men et id: dblink-samtidighedstesten kopierer en fortolkning til et
`gen_random_uuid()`-id og hænger `interpretation_observation`-rækker på *det* id, mens
oprydningen kun slettede fire **faste** fixture-id'er. Barnet overlevede hver kørsel med
begge fremmednøgler hængende. Målt med `pg_dump -Fc` + `pg_restore --clean`: 2
fremmednøgler før → 2 restore-fejl → **0** efter; efter rettelsen 2 → 0 fejl → 2.
Oprydningen har fået tre led, hvoraf det tredje også rydder op efter tidligere kørsler.

**Slut-vagt for `red_*`-fladen.** Allow-listen læste som om dens 74 signaturer var hele den
redaktionelle flade; 37 får deres grant af senere, formålsbestemte blokke. Målt mod prod:
126 `red_*`, 111 `authenticated`-kaldbare, 0 anon-kaldbare — og **nul drift** mellem prod og
det, filen producerer. Det var altså ikke et hul; hullet var, at intet efterprøvede summen.
Vagten er versionsbevidst (v1: 102, v2: 111), tjekker **begge** retninger, dækker
`service_role`, og afviser ukendt kontraktversion.

**En ægte CI-flake lukket.** Jobbet "DAA 1939 v50 writer" faldt på
`FEJL: OCR-låseorden efterlod fixture eller dblink-session`. Det er en race:
`pg_stat_activity` tjekkes umiddelbart efter `dblink_disconnect`, men server-backenden kan
ligge et øjeblik endnu. Bevist på to måder — samme fejl fældede `bd68852`, en merge af en
ren dokumentations-PR, og en genkørsel uden kodeændring blev grøn. Rettet med afgrænset
ventetid og påstanden delt i to, så en fremtidig fejl siger hvilken årsag der fyrede.

**Tre Codex-runder, tre NO-GO.** Hver gang på noget, der krævede at måle et sted, jeg ikke
selv havde kigget: en konkurrerende definition i `db-migrations.sql` der degraderede gaten
lydløst, medlems-orakler der overlevede, og en vagt der var versions-blind og ensidig.
Alle lukket med negativ kontrol pr. vej.

**Feed-billeder i naturlig bredde (#210).** Gammelt upushet arbejde fra 6/8, hentet frem
under grenoprydningen. Bredden følger nu billedets eget forhold i stedet for en fast andel
af kortet; højden er uændret fast. 927 web-tests og 450 mobil-tests grønne.

**Grenoprydning.** Otte lokale grene uden remote er pushet som backup efter scan for
PII-stier og credentials (nul træf); `docs/prod-deploy-149b-go1` slettet efter kontrolmåling.
Fase-pakke-grenene (`codex/finish-156-158`, `docs/evidence-phase-gate-156-157`, 13.800
linjer værktøj) står bevidst — `decisions.md` fravalgte eksplicit at merge dem, og de er
ikke delmængder af hinanden.

## 2026-09-20 — rettighedsgaten: medie-tilknyttet indhold følger mediets egen synlighed

Samme dag som medie-indkapslingen (#204), og fortsættelsen af den. Codex' NO-GO på #204
pegede på `media_rettigheder_ok` som et tilbageværende eksistens-orakel. Undersøgelsen
viste, at problemet var større end et orakel.

**Den egentlige lækage.** `entitet_offentlig('media', id)` afgør, om **fakta, noter,
narrativer, relationer og tekst-henvisninger på et medie** er synlige. Den gatede kun på
rettigheder. Et rettighedsfrigivet billede af en levende person var derfor selv skjult for
gæster, mens dets fakta — fotograf, kreditlinje, datering — var læsbare. GDPR-dimensionen
faldt bort ét lag inde. Samme fejlklasse som `MM-01` (2026-08-06) rettede, hvor grenen
ubetinget returnerede `true`; rettelsen dengang tog kun halvdelen med.

Bevist mod prod-kopi med den gamle regel genindsat: `fakta levende anon=1` samtidig med
`levende=0` — faktummet læsbart, mens billedet selv var skjult.

**Ændringen** (PR #206, merget som `036176f`, 10/10 CI-jobs grønne): `entitet_offentlig`s
media-gren gater nu på `media_synlig_anon` — begge dimensioner. `media_synlig_auth` gjort
`SECURITY DEFINER`, og `media_rettigheder_ok` tilbagekaldt fra `public, anon,
authenticated`. `entitet_offentlig`s definition er **flyttet ned** under `media_synlig_anon`
i filen, fordi SQL-kroppe valideres ved `CREATE`.

**Adversarial Codex-review (`gpt-5.6-sol`) fandt to blokerende forhold, som ingen af mine
egne målinger kunne have fanget:**

1. **`db-migrations.sql` genindførte lækagen.** Blokken ved `:10880` overskrev
   `entitet_offentlig` med den gamle gren, og betingelsen krævede kun, at
   `media_rettigheder_ok` fandtes — altid sandt efter `db-rls.sql`. Rækkefølgen
   `db-rls → db-migrations` degraderede derfor gaten **lydløst**; vagten var allerede kørt,
   og CI skjulte det ved altid at køre `db-rls.sql` én gang til bagefter. Negativ kontrol:
   `efter GAMMEL db-migrations: RETTIGHEDER — LÆKAGEN ER TILBAGE`. Definitionerne er nu
   afstemt, og betingelsen kræver `media_synlig_anon`.
2. **`authenticated` beholdt to direkte medie-orakler.** Medlems-politikkerne bruger
   `media_synlig_anon`, så medlemstieren ser præcis det samme som anon indtil
   samtykkemodellen findes. `media_afbilder_privat` og `media_synlig_auth` svarede altså
   mere, end tieren selv kan se. Begge lukket for `authenticated`.

Plus to mindre: readback'en spurgte kun `anon`, og fixturen brugte samme id til person og
medie, så en forkert gren som `person_offentlig(p_id)` ville give identisk resultat.

**Anvendt i prod 2026-09-20** — hele `db-rls.sql` i ÉN transaktion. Hele læsefladen
**uændret** før/efter for både gæst og medlem: 6864 fakta (md5 ens), 2008 relationer
(md5 ens), 1115 narrativer, 987 noter, 13 medier, 33 storage-objekter. Men 0 af 13 medier
er skjulte i prod, **så et uændret før/efter beviser intet af sig selv** — den syntetiske
fixture i `db-verify` Task 8 er prøven.

**Efterprøvet mod prod efter anvendelsen:** 8 anon-kaldbare `SECURITY DEFINER`-funktioner
uden for `red_*` (som forudsagt), 0 medlems-orakler tilbage, billedet hentet som gæst
(HTTP 200, `image/jpeg`, 364 KB), og — det ændringen kunne have skjult ved en fejl — alle
15 medie-fakta stadig synlige for gæster, inkl. begge kreditlinjer og begge fotograf-fakta.

**Rettelse til posten for #204:** påstanden om, at katalog-deltaet dér var målt "med
kropshash på hver funktion", var forkert — indsættelsen af hash'en i snapshot-scriptet
ramte ikke. Målingen er siden genkørt ordentligt: deltaet står stadig på nøjagtig 11 linjer,
og kroppene bekræfter påstanden (`media_synlig_anon` har identisk kropshash før/efter, kun
`prosecdef` vippede).

Runbook: `docs/runbooks/2026-09-20-medie-rettighedsgate.md`. Rapport:
`~/.private/medie-rettighedsgate/rettighedsgate-20260920075338Z.log`.

## 2026-09-20 — medie-indkapsling: de to sidste anon-orakler lukket i prod

Fortsættelsen af anon-hærdningen 19/9 (#202), hvor `media_afbilder_skjult` og
`media_id_for_object` bevidst blev ladt åbne. De kunne ikke lukkes med et revoke alene:
begge blev kaldt fra RLS-politik-kroppe, og et politik-udtryk udføres med **kalderens**
rettigheder. Et revoke ville have slukket billedvisningen for gæster.

**Hvad de lækkede.** `media_afbilder_skjult(mid)` var et PII-orakel — den svarer, om
billede N afbilder en levende eller privat person, uden at vise billedet.
`media_id_for_object(sti)` var et eksistens-orakel over storage-stier og deres `media_id`,
uafhængigt af om objektet var synligt.

**Indkapslingen** (PR #204, merget som `2271d0b`, 10/10 CI-jobs grønne): `media_synlig_anon`
gjort `SECURITY DEFINER` med uændret krop, ny `SECURITY DEFINER`-wrapper
`media_object_synlig_anon(text)` til sti→synlighed, begge storage-politikker skrevet om til
kun at kalde den, og de to funktioner lukket i `$anon_gate_hardening$`. Blokken har fået en
vagt i samme transaktion som revoket: falder `media_synlig_anon` tilbage til INVOKER,
mangler wrapperen, mister en rolle sin EXECUTE, eller kalder en politik ikke wrapperen,
stopper deployet med `MEDIE_INDKAPSLING_BRUDT` i stedet for at slukke billederne.

**Anvendt i prod 2026-09-20** — hele `db-rls.sql` i ÉN transaktion, så alt-eller-intet.
Gæstens flade **uændret** før/efter: 13 medier, 20 varianter, 33 storage-objekter. Direkte
kald til begge funktioner som `anon` giver nu `permission denied`; den lovlige vej gennem
wrapperen svarer uændret.

**Ende-til-ende mod prod, ikke kun mod ACL'en.** Bytes serveres af Storage-API'et, som
rammer RLS ved `createSignedUrl` — det kan databasen ikke selv bevise. Målt med anon-nøglen
mod prod efter anvendelsen: signeret URL mintet, billedet hentet (HTTP 200, `image/jpeg`,
364 KB, 1280×1554), en thumb-variant hentet (HTTP 200, 34 KB, 500×579 — variantgrenen
resolver stadig efter bucket-hærdningen), og en forældreløs sti nægtet (`NoSuchKey`).

**Testdækning, der ikke fandtes.** `db-rls.sql`s storage-blok og `db-verify`s Task 12b er
begge pakket ind i `if exists storage.objects`. I CI findes skemaet ikke, så begge sprang
over — de to gæstevendte politikker var aldrig testet andre steder end i prod. En
storage-shim i bootstrap lukker det (119 → 120 OK-linjer). `db-verify-media.sql`s Task 12b
ryddede op med `DELETE FROM storage.objects` og var derfor ukørbar mod en ægte
Supabase-kopi (`protect_delete`); erstattet af transaktions-udgaven.

**Adversarial Codex-review** (`gpt-5.6-sol`) lukkede tre fund: blank sti og manglende
bucket-korrelation i `media_id_for_object` (begge no-ops på de faktiske data, men tilladt af
datamodellen), og to fixtures, der fælder regressioner Task 12b før sov igennem — et
GDPR-skjult storage-objekt og et objekt i en anden bucket.

**Efterladt bevidst:** `media_rettigheder_ok` er fortsat et eksistens-orakel (svarer `true`
for et rettighedsfrigivet medie, også når det er GDPR-skjult). Målt: 0 af 13 medier er
skjulte, så den lækker 0 i dag. Et revoke rækker ikke — `entitet_offentlig('media', id)`
reproducerer gaten og fodrer politikkerne på `note`, `narrative` og `text_mention`.
Begrundelse og åben opgave i `docs/decisions.md`.

**Advisor-fladen efter anvendelsen:** 9 `SECURITY DEFINER`-funktioner er anon-kaldbare
(ud over `red_*`) — 7 forud-eksisterende bevidst offentlige plus de 2 nye indgangspunkter
`media_synlig_anon` og `media_object_synlig_anon`. Det er hensigten, ikke et nyt hul; noten
står i `db-rls.sql`, så de ikke lukkes i god tro.

Runbook: `docs/runbooks/2026-09-20-medie-indkapsling.md`. Rapport:
`~/.private/medie-indkapsling/medie-indkapsling-20260920070141Z.log`.

## 2026-09-19 — oprydning gik galt, blev omgjort; arbejdsudlæg arkiveret

En oprydning 18/9 slettede mere, end den burde, og på et grundlag der ikke var målt. Alt er
gendannet. Optegnet her, fordi det forklarer to tilstande i arbejdstræet, som ellers ville
virke tilfældige.

**Hvad der gik galt.** Elleve worktrees blev fjernet på kriteriet "branchen er merget i main".
Det er ikke et bevis for, at mappen er undværlig: `git worktree remove` nægter ganske vist
ved ændrede eller *usporede* filer, men **gitignorerede** filer hverken tæller som urene eller
skånes — `work/` og `node_modules` ryger lydløst med. Samtidig blev tre prod-dumps slettet
som "overhalet af nyere", heriblandt `daa-prod-20260917141330.dump`, som er udtrykkeligt
fredet i sessionshukommelsen. Og en sletteliste over lokale baser omfattede
`daa43b_20260912192527`, der bærer 4.4's 84 forslag til brug i 4.5.

**Hvad der blev omgjort.** Alle fire prod-dumps er gendannet fra APFS-snapshot og
hash-verificeret mod målinger fra før sletningen (`c1c13f76…`, `3058d9aa…`, `ee4fd901…`,
`b6cd1b1b…`). Slettelisten blev afvæbnet, før den blev kørt. To uafhængige kontroller —
sessionslogge og Time Machine — viste, at ingen af de elleve worktrees indeholdt en
`work/`-mappe. **Intet gik tabt ud over `node_modules`.**

**Hvad der står tilbage med vilje.** `git worktree remove` fejlede midtvejs på
`evidensbaseret-genimport` med *"Directory not empty"* — det var ikke en beskyttelse: den nåede
at slette 201 sporede filer og afregistrere worktreet, før den gav op. Mappen (494 MB) er
mærket med en `LÆS-MIG-MAPPEN-ER-BRUDT.md` og røres ikke. Alt af værdi er flyttet til
`~/.private/1939-v50-work-arkiv/` (0700, 172 MB): `work/` med 647 filer udtræksudlæg fra
task 16-30 (bytetal efterprøvet), `sdd/` med 385 filer fra 18 august-planer, og to løse
rapporter. Udtrækket er ikke deterministisk, så rapporterne kan ikke genskabes ved at køre
pipelinen igen.

**Regel indført** i de globale arbejdsregler: sletning kræver måling først, og en egenskab ved
*noget andet* — branch merget, nyere fil findes — er aldrig bevis for, at indhold er
undværligt. Se `docs/decisions.md`.

Dagens designreview af record-nøglede person-narrativer (#152, 29/8) er samtidig reddet ind i
`docs/superpowers/reviews/`; det fandtes kun i et worktree, der var på vej til at blive fjernet.

## 2026-09-19 — anon-hærdning: familie-oraklet lukket i prod

Supabase' sikkerhedslinter (0028) flagede 14 `SECURITY DEFINER`-funktioner som kaldbare af
`anon`. Ni er bevidst offentlige og forsvarlige; fem var det ikke. De fem er lukket i prod.

**Den reelle lækage:** `family_offentlig(fid)` svarer `false` præcis når en familie rummer en
skjult (levende/privat/staged) person, og `true` både for offentlige og for ikke-eksisterende
familier. Kaldbar af `anon` var den dermed et eksistens-orakel: en uindlogget kunne gennemløbe
id'er og kortlægge, hvilke grene der har levende medlemmer. Målt før ændringen: **35 af 682
familier** svarede `false`. Identitet lækkede ikke — kun eksistens.

**To ting kun prod kunne vise:** `media_synlig_auth` var kaldbar af `anon`, skønt `db-rls.sql`
kun giver den til `authenticated` (Supabases direkte anon-grant overlever ikke et
`revoke … from public` — rollen skal navngives). Og de tre `hist_*` havde stadig `PUBLIC` i
deres ACL; rollegaten i kroppen beskyttede dem, men grantet var unødigt.

**Bevidst ikke rørt:** `media_afbilder_skjult` og `media_id_for_object`. Storage-politikken
kalder dem gennem `media_synlig_anon`, som er `INVOKER` — `anon` *skal* kunne kalde dem, ellers
holder billeder op med at loade for gæster. De lukkes i en separat ændring, der indkapsler
sti→synlighed i én `SECURITY DEFINER`-funktion og skriver politikkerne om.

**Sikkerheden er efterprøvet mod prod-katalogen, ikke kun mod filerne:** ingen RLS-politik
kalder nogen af de fem, `family_offentlig` kaldes kun fra `entitet_offentlig` (`SECURITY
DEFINER`, så det indre kald kører som ejeren), og web- og mobilfladen kalder ingen af dem.
Forud for prod blev blokken kørt mod en engangskopi af 17/9-dumpet: `anon` mistede adgang til
alle fem, `authenticated` beholdt de fire den skal have, `entitet_offentlig`-kæden svarede
uændret som `anon`, direkte kald gav `permission denied`, blokken er idempotent, og en omdøbt
signatur udløste `ANON_GATE_HARDENING_SIGNATURE_MISSING`.

Blokken bor i `db-rls.sql` (`$anon_gate_hardening$`), er fail-closed på manglende signatur og
har readback i samme transaktion. Fortrydelse: `~/.private/148c-prod/anon-haerdning-fortryd.sql`.

**Udestår fra samme advisor-runde:** indkapslingen af de to medie-funktioner, og leaked
password protection, som er slået fra i Auth.

## 2026-09-18 — 4.1c: klausulerne er skrevet i prod (#148)

Trin 4's **første datakørsel i produktion** er gennemført og afstemt. Prod har nu
klausullaget udfyldt for 2018-20: **591 records, 868 klausuler**, dispositioner 617
`afventer_fortolkning` / 251 `maskinelt_flagget`, 591 `clause_evidence`-hændelser i **én**
`finalized` batch. Klausul-projektionen (#195) svarede `match` mod prods egen målidentitet,
og de fem neutrale lister var uændrede (591/591/587/587/587) — intet kanonisk delta, ingen
`anon`-drift.

**Forløb** efter `docs/runbooks/clause-evidence-prod-apply.md`: skrivepause fra før dumpet →
læse-kun preflight → backup (`b6cd1b1b…`) → restore-rehearsal af netop den backup, inkl.
fortrydelsesøvelse → hash-låst GO → writer-profilrækken som eget skridt med readback → ét
apply → efter-projektion og afstemning → pausen ophævet.

**Rapporter** (private, 0600): preflight, rehearsal `16940a10…`, apply `7541bf7b…`,
verify `8769f9ac…`. Manifest `0b31c5a2…`, profilversion `clause-evidence-v1`, commit
`c296dd9`.

**Fortrydelsesvinduet er åbent:** backuppen fra 2026-09-18 10:19:22Z bevares, indtil
projektejeren lukker det. Fortrydelse er restore af den; alt skrevet i `private` eller
`public` siden da ville gå tabt.

## 2026-09-17 — Klausul-projektion: udgaveneutralt delta-tjek til 4.1c (#195)

Spec §11.1's klausul-projektion er bygget som vej C: en læse-kun projektion (ejer og
`anon` i ét snapshot) og en komparator uden databaseadgang. De beviser, at én
`clause_evidence`-kørsel skrev præcis manifestets klausuler, bundet til én batch og den
godkendte database, og at intet i de navngivne tabeller — heller ikke det offentligheden
ser — ændrede sig. Fortolknings-projektionen er udskudt til #196.

**Review:** Codex `gpt-5.6-sol` gav NO-GO i tre runder; GO i runde 4, efter alle fund var
rettet, overdraget eller indsnævret (decisions 2026-09-17).

**Fund til 4.1c's prod-kørsel:** writer-profilrækken for `daa-2018-20-clause-evidence-v1`
findes ikke i prod; dens indsættelse er en varig prod-skrivning, der hører til 4.1c's GO.

**Rehearsal** mod prod-tilstanden 2026-09-17 (restore + trin 4-migrationer): `match` med
591 records og 868 klausuler; en navngiven kopi gav `TARGET_MISMATCH`, en ændret forekomstnøgle `NEUTRALITY_DRIFT`, en slettet
`family_member`-række `CANONICAL_DRIFT`. Tal: `clause-evidence-148-rehearsal.md`.

**Fund:** 4.1c-rehearsalens »kanonisk lag identisk« var en hash af antal rækker. Den nye
projektion hasher hele rækker.

## 2026-09-17 — Trin 4 i prod: skema og writere, ingen data (#147/#148)

Blokkene 4.1a, 4.1c, 4.2 og 4.4 er deployet til produktionsdatabasen. Prod har nu
klausullaget, prædikat-navnerummet og writerne for klausuler og fortolkningsforslag —
**men ingen af writerne er kørt**. 0 fortolkninger, 1488 observationer, 1811 personer
før og efter. Detaljer: `docs/database-current-state.md` §8.

**Forløb (§5):** læse-kun preflight → backup → restore-rehearsal → GO → apply →
læse-kun verifikation → Security Advisor. Scripts i `~/.private/trin4-prod/`.

**Rækkefølgen er bindende.** 4.1c og 4.4 omdefinerer begge `red_finalize_reimport`,
`red_reimport_batch_result` og `validate_reimport_authorization_payload` med hver sin
lukkede operationsmængde. 4.1c kørt efter 4.4 ville stille fjerne
`interpretation_proposal`. Rehearsal og prod bekræftede, at begge funktioner kender
begge operationer.

**Fund undervejs:**

- **Backuppen blev forældet på to dage.** Dumpet fra 15/9 og det fra 17/9 havde
  identiske tal, men det nye var 15 KB større. Apply-scriptets stopport sammenlignede
  kun antal og ville have godkendt det gamle dump som rollback-punkt. Nyt dump og ny
  rehearsal blev taget, og apply fik en stopport på `change_set` oprettet efter
  backup-start. Den fanger redaktionelle ændringer, ikke loadere eller direkte SQL.
- **`SET TRANSACTION READ ONLY` beskyttede ikke.** I psql's autocommit er den et no-op
  med en WARNING. Læse-kun-scripts bruger nu
  `PGOPTIONS='-c default_transaction_read_only=on'`.
- **`db-migrations.sql` kan ikke køre som én transaktion.** Filen ejer #153's egen
  `BEGIN`/`COMMIT`. `db-rls.sql` kan: den kørte med `--single-transaction` (0,2 s i
  rehearsal), så de fem politik-udskiftninger på `entity_description` blev ét skifte.
- **En verifikationsforespørgsel fejlede efter apply** (`ORDER BY` på en kolonne, der
  ikke fandtes). Skrivningen var gennemført. Den resterende verifikation blev kørt
  separat, efter at forespørgslen var prøvet mod rehearsal-kopien, og var grøn.
  Lære: verifikationsforespørgsler hører i rehearsal, ikke kun i apply.

**Advisors:** 0 ERROR i både security og performance. Security: fire nye linjer, alle
kendte mønstre. Performance: ét nyt fund — `interpretation_predicate_fk` uden indeks, uden
praktisk betydning i dag, men skal indekseres før forslags-writeren kører på skala.
Ældre fund (bl.a. et dobbelt indeks på `private.source_persona_placement`) står i
`database-current-state.md` §8.

**Ikke gjort:** ingen datakørsel. Første datakørsel (4.1c's 868 klausuler) kræver
fortsat fortrydelseskvittering og en klausul-projektion i fase-pakke-runbooken, og
`interpretation_proposal` har ingen prod-fortrydelse (spec åbent punkt 11.5).

## 2026-09-14/15 — Trin 4, dagsværk 4.4: forslagene er i databasen (#147)

84 modeludtrukne claims fra 4.3b står nu som `proposed`-fortolkninger i en restore, bundet
til de klausuler de citerer. Kæden fra bogens prosa til en struktureret, kildebunden påstand
er dermed hel — men afgørelsen er stadig 4.5's, og intet er rørt i prod.

**Regnskabet:** 93 rå claims → 7 kontraktafviste → 2 H1-afviste → 0 dubletter → **84
ingestible** fordelt på 8 elementer. 68 `principal`, 16 `other`. 19 klausuler fik ny maskinel
disposition: 13 `fortolkning_foreslaaet`, 6 `afventer_identitet`. Kanonisk lag uændret.
Replay `already_applied` uden nye rækker.

**Den forventede fordeling blev skrevet ned FØR kørslen** og ramte på alle otte tal. Det er
forskellen på en kontrol og en efterrationalisering.

**Tre fejl i lukkede nøglesæt fældede første kørsel.** Writer-payloaden er defineret som
operationen *minus* `element_id` og `dependency_class`; builderen lagde felterne under en
`payload`-nøgle, som dermed selv blev en payload-nøgle. Autorisationen fangede det ikke —
den sammenligner kun de to sider med hinanden, ikke med formen, så begge var forkerte på
samme måde. Dertil er `writer_config` låst til otte nøgler af
`private.validate_reimport_writer_config` (operationens egne indstillinger flyttet til
`operation_settings`), og R-gateway'en manglede sin `interpretation_proposal`-gren.

**Negativ test (Task 7 Step 5).** Et `principal`-claim på `III-129` — en af fire records uden
entydig primary persona — afvises med `REIMPORT_WRITER_PRINCIPAL_WITHOUT_PERSONA`. Samme
claim med rollen `other` går igennem og rulles tilbage; uden den spejlkørsel kunne
afvisningen være kommet af hvad som helst andet i payloaden.

**`anon`-neutraliteten blev bevist strukturelt, ikke som delta.** Apply var allerede
committet, da hullet blev opdaget, så et før/efter kunne ikke måles bagudrettet. I stedet:
`anon` og `authenticated` har `SELECT = f` på alle seks berørte tabeller, ingen `public`-view
læser dem, og ingen anon-eksekverbar `public`-funktion gør det. Kombineret med det uændrede
kanoniske aggregat kan læsersidens flade ikke have flyttet sig.

**Spec §7.2 fik errata.** Specen kender kun claims om recordens persona og claims i form
`mention`/`relation`. 4.3b målte 8 `event.*`-claims om hovedpersonen uden `person.`-præfiks —
de er ingen af delene, og en regel »ikke `person.*` → `other`« ville stemple deres klausuler
`afventer_identitet`. Valgt vej: eksplicit, versioneret `persona_role_map` i genimportprofilen.
Se `docs/decisions.md`.

**To huller lukket undervejs.** R-klienten kastede writerens `interpretations_written` væk,
selv om kommentaren lovede en afstemning; batchens `expected_counts` tæller kun *elementer*,
så et tabt claim ville slippe gennem serverens finalize. Afstemningen er nu implementeret pr.
element med test. Og builderens klassifikationsregler — det sted hvor det afgøres om et claim
overhovedet kommer med — havde ingen test; ny testfil med 23 tests er føjet til CI.

**Rolleudledningen hærdet:** længste præfiks vinder nu, så et fremtidigt `event.marriage`
under `other` ikke taber til `event.` under `principal` alene på listerækkefølge. Et
selvmodsigende kort rejser frem for at vælge. Output er bit-identisk med det anvendte manifest.

**Miljøfund:** restoren manglede `dblink`, som db-verifys samtidighedstest kræver, og
ACL-revoke'en for klausullagets triggerfunktioner bor i `db-rls.sql` — ikke i
`db-migrations.sql`. En migreret base er altså ikke en verificerbar base før `db-rls.sql`
også er kørt.

**Gates:** R-suite FAIL 0 / PASS 2995 · pytest 225 passed · `db-verify.sql` grøn mod restoren
med de 84 live rækker (119 asserts).

**Rapport:** `docs/evidensbaseret-genimport/proposal-ingest-147-4-4-rehearsal.md` — regnskab,
hashes, forventet vs. målt fordeling, negativ test, gates og udestående. Regnskabet blev
**seks** tal, ikke fem: `persona_role_map` er fail-closed og har sin egen afvisningsgrund
(målt til 0). Og Task 0's uafklarede måling 2 er lukket — en read-only probe fordelte de syv
kontrakt-afviste pr. record, og **alle syv er IV-34's**.

**Ikke lukket:** intet er merget, og restoren `daa43b_20260912192527` skal bevares — 4.5
bruger den, fordi klausul-id'erne er database-genererede. `44-apply.R` re-autoriserer ved
hver kørsel og mangler `--jeg-mener-det`-guard; prod-fortrydelse for operationen findes
stadig ikke (åbent punkt 11.5).

**Task 6 afgjort 2026-09-15 — reviewsignalet bor i menneskearket.** Valget stod mellem en
additiv `proposal_flags jsonb` på `private.interpretation` og bedømmelsesarkets forudfyldte
anbefalingskolonne. Arket vandt, og det afgørende var **rækkefølgen, ikke designet**: ingesten
var allerede kørt, så de 84 forslag stod i den restore, 4.3b-4.5 deler. En kolonne skulle ind
via writerens lukkede payload-nøglesæt, men guarden er fail-closed pr. `interpretation_key` og
replay kortslutter på batch-niveau — kolonnen ville derfor koste enten en genkørsel af hele
4.4 på frisk base eller et `UPDATE` uden om `private.reimport_event`. Dertil foreskriver spec
§8.2 allerede arket, og efter at H2 er opgivet som maskinel regel er alt, et flag kunne bære,
afledeligt af `confidence`, `persona_role`, antal citerede klausuler, `clause_flags` og
`value_kind` (invariant 4). Skrevet som errata til §8.2 med genåbningskriterium; builderen
bærer nu en note om, at H2's fravær er et valg og ikke en mangel.

## 2026-09-13 — Trin 4, dagsværk 4.3b: modellen kan læse bogen (#147)

Første gang ægte DAA-prosa er sendt til en model i dette projekt. Fem poster, valgt
stratificeret fra ledgerens 488 eligible, kørt bag Seatbelt-gaten med adgangstesten bestået
umiddelbart før hvert kald.

**Alle fem tærskler bestået:** præcision 40/41 (98 %), klausulbinding 41/41 (100 %),
ordrethed 9/9 datoer (100 %), dækning 100 % (intet oversprunget noteret), brugbarhed 4/4
biografiske poster. ~17.700 input-tokens pr. post.

**Men de vigtigste fund er dem, tærsklerne ikke fanger.**

*Modellen opfandt en præcision, kilden ikke har.* I-11 fik to dødsclaims: det tvetydige
`† 1342/1353`, som bogen faktisk skriver, og `død 1353 (23. april)`, der vælger det ene år og
tilføjer en dato. Prompten forbyder udtrykkeligt at udlede, og invariant 5 findes netop for
at bære fuzzy datoer. Et claim, der ser MERE præcist ud end kilden, er farligere end et
åbenlyst forkert: det ligner kvalitet.

*Halvdelen af relations-claimene identificerer ingen.* `relation.marriage` = »NN.« og
`relation.child` = »4 sønner« er begge sande og formelt gyldige, men peger ikke på nogen.
Kontrakten kontrollerer form, ikke om et relations-claim udpeger en modpart. Hullet er i
valideringen, ikke i modellen, og det skal lukkes før 4.4's ingest.

*Seks procent af korpus er ikke biografier.* I-29 gav nul claims; projektejeren vurderede den
som en henvisning, og databasen bekræfter det (50 tegn, »se«-henvisning, intet årstal, intet
f./d.). Tavsheden var korrekt. Men 38 af 591 poster ligner den og koster fuld pris i tokens
for garanteret nul udbytte — et filter før modelkaldet ville spare ~6 % af en fuld kørsel.

**Claim-niveau afvisning, fremtvunget af kørslen.** I-11 fejlede først: ét `person.name` med
objekt hvor der skulle stå en streng fældede posten og dens seks korrekte claims. Ved
genkørsel kom alle syv igennem — fejlen er modellens variabilitet, ikke en misforstået
prompt, og man kan ikke skrive sig ud af noget, der kun sker nogle gange. Projektejeren
afgjorde, at et ugyldigt claim kun fælder sig selv; posten markeres `delvis` og tabet står i
logget. Sikkerheden er uændret — et afvist claim lagres aldrig.

**Metodefejl rettet undervejs:** den maskinelle ordrethedsforudfyldning målte alle værdier
(28/34) i stedet for planens nævner »claims m. ordret krav«, altså datoprædikaterne. De seks
afvigelser var titler, modellen med rette havde skåret ud af længere sætninger. Rigtigt tal:
9/9.

**Bundt 2 kørt samme dag.** Samlet over alle ti poster: **86 claims, 99 % præcision (85/86),
100 % klausulbinding (86/86), 100 % ordrette datoer (17/17)**, ingen udeladelser noteret,
8/8 biografiske poster brugbare. 175.840 input-tokens, ~17.600 pr. post.

IV-34 blev den første post, hvor claim-niveau afvisning trådte i kraft: nogle claims kom
igennem, resten blev afvist, posten gik ikke tabt. Under den gamle regel var alle elleve røget.

**4.3b er dermed gennemført, og sporet bærer.** To ting skal lukkes i 4.4 før promotion: et
`relation.*`-claim uden identificerbar modpart må ikke kunne blive et forslag, og et claim,
der er mere præcist end kilden, må ikke kunne promoveres.

To målefejl var mine egne: ordrethed blev først målt på alle værdier (28/34) i stedet for
planens nævner, datoprædikaterne (17/17); og optællingen meldte falsk PENDING, fordi den
talte `green` men ikke `delvis`.

Restoren og artefakterne BEVARES til efter 4.5 (spec §3: 4.3b-4.5 deler én restore). Rapport:
`docs/evidensbaseret-genimport/runner-rehearsal-147-4-3b.md`.

## 2026-09-12 — Trin 4, dagsværk 4.3a: runneren er kørt ende til ende (#147)

Gren `feat/147-eligibility-ledger`. Ingen prod-berøring, ingen rigtige records.

**Hele kæden kørt på én opdigtet post:** eligibility-ledger → preflight → call-dir →
Seatbelt-gate → `codex exec` → usage → claim-validering → cache → gentagelse. Alle otte
krav opfyldt: udelukkede og ukendte records nåede aldrig modellen (sømmen kastede ikke),
`GATE_OK` før kaldet, forbrug rapporteret, outputskemaet holdt med 4 claims, cache-hit ved
gentagelse, kanariestrengen lækkede ikke, 3/3 fejltyper klassificeret.

**Modellen udtrak det rigtige.** `person.birth` »f. 21. Juni 1710«, `mention.place`
»Fiktivborg«, `person.title` »Kammerjunker«, `person.death` »Død 4. Maj 1789« — datoerne
**ordret**, ikke omskrevet til ISO, og stedet klassificeret som omtale frem for
fødselsfaktum. Hvert claim citerer sin klausul. Forbrug: 17.376 input / 352 output / 177
reasoning mod 15.266 i probens baseline, så prompt + post koster ~2.100 tokens.

**To fejl, kun kørslen kunne finde.** Kontraktfilen validerede fint i Python og blev afvist
to gange af API'et: `oneOf` er ikke tilladt i et structured-output-skema (rettet til
`anyOf`), og **alle** felter skal stå i `required` — valgfrihed udtrykkes med `null`, ikke
med fravær. Begge er nu kommenteret i skemaet med måledato, så de ikke »ryddes op« igen.
Samme mønster som stderr-fejlen i Task 3: prisen for »ingen test starter Codex« er, at den
sti skal køres for alvor mindst én gang.

**Ærligt om kanarietesten.** Den svarede `{"claims":[]}` frem for `KAN IKKE LÆSE`, fordi
`--output-schema` tvinger svarets form. Kanarien beviser derfor kun, at strengen ikke
optrådte i strømmen; det stærke bevis er adgangstesten, som kører uden model og
deterministisk får `EACCES`. Testen er beviset, kanarien er en stikprøve.

**Task 5 samme dag:** eligibility-ledgeren. Grundreglen er, at *fravær ikke er tilladelse* —
en record, der ikke står som `eligible`, afvises, og preflighten kører før prompt, call-dir
og subproces bygges. Beviset er en søm, der kaster, hvis den overhovedet kaldes.

**Udestår:** `export_model_eligibility.R` er aldrig kørt mod en database, så §9.2's tal
(46+4 / 13 / 62 / 2) er ikke genmålt. Ledgeren må ikke bruges til et rigtigt modelkald før
den kørsel. Rapport: `docs/evidensbaseret-genimport/runner-rehearsal-147-4-3a.md`.

## 2026-09-11 — Trin 4: forbrugsproben til 4.3a lukker 4.3's stopbetingelse (#147)

Gren `feat/147-runner-forbrugsprobe`. Ingen prod-berøring, ingen rigtige data.

**Spørgsmålet.** Spec §6.6 lod ét forhold stå ubekræftet: rapporterer
`codex exec --json` overhovedet tokenforbrug? Proben 2026-09-06 kunne ikke svare,
fordi turen døde på kvote. Spec'en er kategorisk om følgen — kan CLI'en ikke
rapportere forbrug, **stopper dagsværk 4.3 med et navngivet fund**.

**Svaret er ja.** `turn.completed` bærer et `usage`-objekt med fem felter,
herunder `reasoning_output_tokens` særskilt. §6.4's regnskab kan bygges som
beskrevet. Kørt på en opdigtet post (»Testperson Opdigtsen«, Fiktivby); ingen
tekst fra `work/` eller databasen forlod maskinen. `--output-schema` blev
respekteret — outputtet var ren JSON med fire claims, der hver citerer en
klausul-ordinal, hvilket bekræfter at `evidence-claims-1.0` kan håndhæves på
CLI-niveau og ikke kun i Python-validatoren.

**Overheadet er næsten hele regningen.** Et tomt kald koster 21.554
input-tokens; den fulde prompt + record kostede 21.801. Nyttelasten var altså
~250 tokens, **1,1 %** af kaldet. Det gør §6.4's »batches 5-10 records« bærende
for økonomien frem for en optimering: én record pr. kald ville koste ~12,7 M
input-tokens for 591 records, hvoraf under 1 % er data.

**En tredjedel af overheadet er brugerens private konfiguration — og det bryder
reproducerbarheden.** Påstanden om, at overheadet var CLI'ens egen
systeminstruktion, var et gæt og blev dekomponeret: en tredje kørsel med
`--ignore-user-config` kostede 15.266 mod 21.554 input-tokens. De 6.288 tokens
er `~/.codex/AGENTS.md`, `config.toml` og tre brugerskills. Besparelsen er det
mindst interessante. Alvorligt er, at §6.2 hash-binder prompten
(`prompt_sha256`) netop for at gøre kaldet reproducerbart, mens brugerens
private AGENTS.md ligger uden for den hash og kan ændre sig usynligt mellem to
kørsler. `--ignore-user-config` bør ind i §6.2's flagliste — en rettelse af en
godkendt spec, som hører til plan 4.3a's adgangskrav.

Udbyderens prompt-cache genbrugte halvdelen af overheadet ved andet kald
(`cached_input_tokens: 11008`); effekten bør måles pr. batch i 4.3b, ikke
antages. Hændelsesstrømmene fra alle tre kørsler ligger som fixtures i
`.claude/skills/daa-extract/scripts/tests/fixtures/codex-exec/`, så 4.3a's
usage-parser kan testes uden kvote. Rapport:
`docs/evidensbaseret-genimport/runner-usage-probe-147-4-3a.md`.

**Udestår:** planerne for 4.3-4.5 er nu ublokerede og kan skrives. Fejltaksonomien
(§6.3) har stadig kun `quota_exhausted` som observation; priser er ikke aflæst og
kræver en profilversion med GO.

## 2026-09-11 — Flaky record-key-test rettet (#177)

Fundet under 4.2-arbejdet, uden sammenhæng med den gren — derfor sin egen PR.

`test_record_key_is_minted_opaque_and_not_from_layout_or_name` søgte efter delstrengene
`"Anna"` og `"101"` i én mintet nøgle. `mint_record_key()` returnerer `"record-" + uuid4`,
så `"Anna"` kan aldrig optræde i hex — mens `"101"` optræder tilfældigt i **0,47 %** af alle
nøgler (målt over 200.000 mintninger). Testen var altså rød på skift på vilkårlige PR'er,
uden at et eneste bogstav i koden havde ændret sig.

Det alvorligere problem var, hvad den **ikke** målte: den kaldte funktionen uden argumenter
og kiggede kun på resultatet, så en mintning, der faktisk afledte af navn eller layout,
ville være sluppet igennem. Invarianten er, at mintningen ikke *har* noget at aflede fra —
testen asserterer nu signaturen (ingen argumenter) plus at 256 nøgler er indbyrdes
forskellige og hver har formen `record-` + et uuid4. To prober mod `evidence_contract.py`,
begge rullet tilbage igen, viser at den nye form bider, hvor den gamle ikke gjorde.

Merget som **#177** (`a9ccc83`).

## 2026-09-10 — Trin 4, dagsværk 4.2: ét prædikat-navnerum (#147)

Gren `feat/147-praedikat-vokabular`, merget som **#176** (`c803eed`). Ingen skrivning mod prod.

**Leveret.** `private.interpretation_predicate` som eneste sandhed om, hvilke prædikater
fortolkningslaget kender — med udsagnsform, §7.3-kategori og værdiform. 42 aktive
prædikater plus 8 fixture-rækker til db-verify's egne negative tests. `private.interpretation`
har fået en **komposit-FK** på `(predicate, interpretation_kind)`, så udsagnsformen bindes
til prædikatet i stedet for blot at sameksistere med tabellens eget fireværdi-CHECK.
Promotion-reglernes `value_kind` bindes både i `add_interpretation_promotion_rule_version`
og som trigger. Extractorens hårdkodede `ALLOWED_PREDICATES` er væk: den læser nu en
byte-verificeret projektion af tabellen (`references/interpretation-predicates.json`,
SHA-256 `5e51c55b…`), og `interpretation_kind` **udledes af tabellen** frem for at gættes
af prædikatets præfiks — det gamle gæt kunne ikke skelne `event.marriage` fra
`relation.marriage`. `interpretation-schema.json` er bumpet til 1.1 med `$defs` for de seks
værdiformer, og en test asserterer, at hver værdiform i den genererede fil har et skema.

**Planen fik NO-GO og blev revideret to gange.** En uafhængig gennemlæsning (Codex
`gpt-5.6-sol`) fandt otte blokerende fund — vigtigst at `db-verify.sql` indsætter
prædikater **uden punktum** (`death_date`, `fake_approval`, `terminal_status`), som ikke kan
seedes under formatinvarianten, og at db-verify kører **mod prod**: en FK ville have
standset produktionsverifikationen. Revision 2 blev derefter selv efterprøvet (Fable), som
fandt tre ting til: et prædikat, der ikke fandtes (`assertion` er `p_target_type`, fjerde
positionelle argument, ikke et prædikat); et **overset** prædikat i en `dblink_exec`-streng
med fordoblede apostroffer (`db-verify.sql:4048`), som en almindelig tekstsøgning ikke
fanger; og at FK'en som `ALTER TABLE` mellem to tabeller ville bryde et regex i
`test_evidence_contract.py` og vælte et andet CI-job. FK'en er derfor erklæret **inline**
som tabel-constraint.

**Prod-side-assertion tilføjet.** 4.2's verifikation lå kun i `tests/sql/`, som alene kører
i CI. `db-verify.sql` har nu en `OK: #147`-blok, der dækker tabel, komposit-FK, triggere,
RLS, kategori-vokabular, regelbinding og ACL for alle fire roller. To negative prober viser,
at den bider (`PREDICATE_COMPOSITE_FK_MISSING`, `PREDICATE_RULE_BINDING_DRIFT`).

**Rigtig kørsel.** Migreret på en frisk restore af prod-dumpet og på fire lokalt byggede
CI-stier (kumulativ, frisk, `2d6aabf`-skema, `reimport_fresh`) — `OK: #147` alle fem steder,
`PREDICATE_FILE_OK`, `42 | 5`. Antagelsen om nul fortolkninger er **målt** både i restoren og
læse-kun mod prod, og prods fem promotion-regler er alle dækket af seedet, så promotion-
adfærden er uændret. To narrative tests fejler på restoren; en kontrolbase migreret med
`origin/main` fejler med præcis de samme tokens — de hører til en frisk base på
kontraktversion 1, ikke til en prod-restore. Rapport:
`docs/evidensbaseret-genimport/interpretation-predicate-147-rehearsal.md`.

**Udestår:** en selvstændig prod-GO for trin 4's tre migrationer. Prod-databasen har
hverken klausulkolonnerne, writeren eller prædikattabellen.

## 2026-09-10 — Trin 4, dagsværk 4.1c: writer-operationen `clause_evidence` (#148)

Gren `feat/148-clause-evidence-writer` (8 commits, upushet). Klausullaget har for
første gang rækker i en database.

**Leveret.** `private.write_clause_evidence` + wrapperen
`public.red_apply_reimport_clause_evidence`; writerens lukkede mængder udvidet fire
steder plus `db-rls`, `db-verify` og testlisterne; en tredje profiltype i
`reimport_profile.py`; manifest-builderen `build_clause_evidence_manifest.py`;
R-klientens dispatch, et læse-kun preview og en integrationstest; CI-trin for både
SQL- og R-testen.

**Rigtig kørsel på restoren:** 591 operationer, 868 klausuler. Dry-run `finalized` og
rullet tilbage (3,7 s), apply `finalized` og committet (2,8 s), replay
`already_applied` (0,6 s). Efter apply: 868 klausuler, ingen uden post-relativt par,
ingen med span uden for forælderens, 868 dispositioner (617 `afventer_fortolkning`,
251 `maskinelt_flagget`), 591 hændelser, 591 uændrede helposter. **Det kanoniske lag er
uændret** — samme hash før og efter — så klausullaget er ren evidens uden delta.

**Offset-blokkeren.** Codex' review fandt, at writeren gemte
`parent.char_from + post-relativ offset`. Målt på prod-restoren holder den aritmetik
ikke: kun 97 af 591 helposter har `char_to - char_from = length(verbatim_text)`, fordi
`segment.py` folder whitespace. Payloaden bærer nu `rendition_char_from/to` beregnet af
manifest-builderen gennem `project_rendition`-kortet — bevist mod restoren før koden blev
skrevet: renditionen genskabt fra PDF'en hasher til basens egen `content_sha256`, alle 591
helposter kan ankres og hash-verificeres, og alle 868 klausuler oversættes og
hash-verificeres.

**Modsigelse i spec §4.1.2, fundet af dry-run.** Spec'en kræver både rendition-absolutte
offsets og at klausulens tekst er forælderens tekst udskåret på de offsets. De to kan ikke
begge holde, når forælderens tekst er en foldet projektion: post-relativ udskæring matcher
hashen 868/868, mens triggerens subtraktion rammer forkert i 370 tilfælde. Med planens
oprindelige, forkerte offsets var triggeren tilfreds hver gang — begge sider regnede galt
på samme måde. Løst med et post-relativt par `post_char_from`/`post_char_to`, der bærer den
eksakte substring-kontrol, mens `char_from`/`char_to` forbliver rendition-absolutte for alle
observationer.

**Codex' øvrige fund lukket:** ledgerfilens SHA kræves og bindes i manifestets provenance;
`extraction_run` har fået post-conflict-lighedskontrol; klausul-objektet i payloaden har
lukket nøglesæt og flag skal være ikke-tomme strenge, så kildetekst ikke kan smugles ind i
et flag og lagres permanent i `private.reimport_event`.

Rapport: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`.

## 2026-09-10 — Trin 4, dagsværk 4.1b: deterministisk klausul-segmentering (#148)

Gren `feat/148-klausul-segmenter` (6 commits, upushet, oven på 4.1a-grenen). Ingen
modelkald, ingen netværk, ingen databaseskrivning.

**Leveret.** `clause_rules` i 2018-20-profilen som version **1.1.0** på projektejerens GO
(1939-profilen urørt); `validate_clause_rules` i `load_profile`; motoren
`clause_segment.py`; en syntetisk fixture med 17 svære tilfælde; læse-kun eksporten
`export_clause_source_texts.R` og ledger-CLI'en `build_clause_ledger.py` med testet
PII-guard (afviser output-mappe med `work`-komponent eller forkert filmode).

**Testmiljø-note.** Tallene »48 failed« i 4.1a-posten nedenfor skyldtes en ødelagt
`NODE_OPTIONS` i sessionens miljø, ikke repoet; se rettelsen dér.

**Rigtig kørsel på alle 591 helposter** fra 4.1a's prod-restore: 866 klausuler (min 1,
median 1, max 29), 0 `structural_header`, og **ingen mellemrumstegn uden for hvidlisten** —
`gap_charset` `[" "]` er dermed rigtigt målt, hvilket var dagsværkets stopport. Flag:
`unknown_abbreviation` 424, `multiple_marriages` 92, `unbalanced_parentheses` 80,
`uncertain_marker` 42, `short_clause` 29, `non_gap_whitespace_in_clause` 0.

**To fejl fundet ved at måle frem for at læse.** (1) Et dobbelt mellemrum efter et punktum
forhindrede en split uden at sætte noget flag — fundet med en stikprøve på 4000 tilfældigt
sammensatte tekster, som de tolv håndskrevne fixture-cases ikke ramte. (2) Alvorligere: 394
splits faldt lige efter en forkortelse med indlejret punktum (`s.å.` 238, `m.a.` 58,
`s.st.` 23, `cand.jur.` 14, `D.M.` 13 …) i 152 af 591 records og klippede grader, embeder og
dekorationer midt over — uden flag, fordi `bare.isalpha()` er falsk, når tokenet selv
indeholder et punktum. Motoren behandler dem nu som al anden tvivl: konservativ
segmentering plus flag. Klausultallet faldt fra 1297 til 866, og flagtallet steg fra 141 til
424, fordi tvivlen er blevet synlig i stedet for at være afgjort forkert i stilhed.

Planens egen gennemgangsmekanisme var blind for fejlklassen: summaryens
`unknown_abbreviation_tokens` opsamler kun tokens i klausuler, der allerede er flagget, så
netop de tokens ville aldrig have nået den liste, projektejeren skulle godkende.

**Regelversion 2 udført samme dag** på projektejerens GO: `clause-rules-2018-20-v2`,
profilversion **1.2.0**, 113 kuraterede forkortelser tilføjet (91 → 204).
`unknown_abbreviation` falder fra 424 til **53** flag i 45 records, og klausultallet stiger
fra 866 til 868, fordi en motorrettelse gav to ægte splits tilbage: et punktum efter en
lukkeparentes afslutter sætningen (`(5000 Kr.). Gift …`), hvor flerpunkts-reglen ellers
smeltede to klausuler sammen. 26 tokens er bevidst udeladt af profilen — enkeltbogstaver,
almindelige ord som `død.` og `maj.` og dato-intervaller — og står stadig som flag, fordi
det er dét, flaget er til. Rapport:
`docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`.

## 2026-09-10 — Trin 4, dagsværk 4.1a: klausullagets skema implementeret (#148)

Gren `feat/148-klausullag-skema` (15 commits, upushet). PR #172 er merget, og projektejeren
gav GO på extraction-profil v1.1.0 samt overdrog implementeringen til sessionen med Codex
som kode- og reviewhjælp; begge dele står i `decisions.md`.

**Leveret.** Fire nullable klausul-kolonner på `private.source_observation` med triggeren
`private.validate_clause_observation()`; `private.vocab` som privat, lukket vokabular (13
`observation_kind`-koder, 2 klausulklassifikationer, 5 maskinelle og 6 menneskelige
dispositionskoder); append-only-tabellen `private.clause_disposition` med validerende
trigger og view `clause_disposition_current`; idempotent spejling i `db-migrations.sql`
med en fail-closed kontraktassertion; hærdning af `private.migrate_legacy_narrative_record`,
så den kun tæller helpostens mentions; ACL i `db-rls.sql`, assertionsblok i `db-verify.sql`,
nyt CI-trin i `writer_1939`-jobbet; bundle-skema 1.2 i `evidence_contract.py`.

**Empirisk bevis (lokalt, ingen prod-mutation).** Kontrakttesten var rød før DDL'en med det
ventede token og er grøn på frisk skema, på migreret base og på CI's opgraderingsbaser.
`db-migrations.sql` kører rent to gange i træk ad begge CI-stier; `db-verify` skriver
`OK: #148 …`. 149b-suitens otte eksisterende tasks er fortsat grønne sammen med den nye
klausul-mention-task. Hele SQL-suiten kørt med vokabular-triggeren slækket til NOTICE gav
ingen useedede `observation_kind` ud over den bevidste negative fixture, og alle seks
writer-fixtures giver kun `person`. De fire R-integrationstests i `writer_1939`-jobbet
kører grønt mod det lukkede vokabular, også i CI's rækkefølge med SQL-trinnene efter.
Python: 37 grønne i `test_evidence_contract.py`. Hele skill-suiten gav undervejs 48 fejl,
som blev noteret som »samme node-baserede fejl som på `main`«. **Det var en fejlslutning om
årsagen:** sessionens `NODE_OPTIONS` pegede på en `--require`-fil i `/var/folders/…`, der var
blevet ryddet væk, så *enhver* `node`-start fejlede. I et rent miljø (`env -u NODE_OPTIONS`)
er facit **2458 passed / 2 failed / 41 skipped**, og de to sidste fejler kun, fordi `rg`
findes som shell-funktion og ikke som binær på PATH, så `subprocess` ikke kan starte den.
Ingen af fejlene stammer fra repoet eller fra denne ændring — men sammenligningen »før og
efter« var gyldig, fordi begge sider blev målt i samme ødelagte miljø.

**Fire planfejl fundet ved at køre planen** (append-only-blokken lå før
`reject_evidence_mutation()` defineres; migrationsstiens opskrift startede fra en tom base i
stedet for CI's allerede loadede; kontrakttesten kræver en redaktør-profil, som opskriften
ikke seeder; vokabular-inventeringens glob rammer ikke CI's fixture-byggede
opgraderingsbaser). Alle fire er rettet eller efterprøvet empirisk.

**Codex-review (`gpt-5.6-sol`).** Læsningen af planen fandt, at triggeren tillod et
snævrere sideinterval end forælderens, i strid med spec §4.1.2 (»en finere sidelokalisering
påstås ikke og fabrikeres ikke«). Den adversarial gennemgang af diffen fandt fem MAJOR:
manglende `service_role` i REVOKE, en migration der ikke konvergerer fra en afvigende tabel,
manglende håndhævelse af klausulens provenance (kvalitet, versioneret regel, flagform),
maskinelle dispositioner uden run-/manifest-hash, og en Python-kontrakt der accepterede fire
bundles, databasen afviser. Fire er rettet som selvstændige commits; den femte
(vokabularvalidering i Python) er afvist med begrundelse, fordi vokabularet ejes af
`private.vocab` og hullet ikke er nyt. Efterfølgende fandt en egen gennemgang, at
metodekontrollen brugte `LIKE`, hvor `_` er jokertegn — rettet til `starts_with`.

**Bindende for 4.1c.** Triggeren kræver nu, at klausulen arver forælderens `quality_status`,
at `extraction_method` begynder med `clause_segment_v1`, at `clause_flags` er ikke-tomme
strenge, og at en maskinel disposition bærer `manifest_sha256` (64 hex) plus mindst én
run-reference (`batch_id` eller `extraction_run_id`, uuid-formet). 4.1c-planens writer
skriver allerede alle fire, så planen behøver ingen ændring.

**Task 7 udført 2026-09-10 mod en frisk prod-restore** (dump-SHA `c1c13f76…`, base
`daa148a_rehearsal_20260910162112`): restore ren bortset fra de forventede
`supabase_vault`-fejl, migration to gange i træk, `db-verify` skriver `OK: #148 …`, tallene
er `591|0|0|t|0`, 149b-suiten og klausul-kontrakttesten grønne mod restoren. Det åbne
ACL-spørgsmål er besvaret: **ingen** af de 53 relationer i `private` giver `service_role`
adgang i prod, så der er intet efterslæb bag Codex' fund — kun defence-in-depth på de nye
relationer. Rapport: `docs/evidensbaseret-genimport/clause-evidence-148-rehearsal.md`.

Runbook-mangel fundet undervejs: et Supabase-dump bærer GRANTs til fem platformroller
(`dashboard_user`, `supabase_auth_admin`, `supabase_storage_admin`,
`supabase_realtime_admin`, `pgbouncer`), som runbookens §1 ikke nævner. Uden dem fejler 111
GRANT-sætninger, og ACL'erne restorer ikke trofast.

## 2026-09-06 — Roadmap-trin 4 planlagt: fortolkningskæde og klausulgranularitet (#147/#148)

Spec (revision 3 efter to uafhængige læsninger, 37 fund indarbejdet) og fire
implementeringsplaner (4.1a skema, 4.1b segmenter, 4.1c `clause_evidence`-writer, 4.2
prædikatnavnerum) på gren `docs/trin4-fortolkningskaede-spec` (13 commits, upushet). Planerne
er læst uafhængigt i to runder (18 + 6 fund, herunder empirisk kørsel af segmenteren mod
fixturen) og rettet; sidste rettelsesrunde er ikke genlæst. Seks projektejer-valg
registreret i `decisions.md`. Ingen kode, ingen databaseændring, ingen prod-mutation.
Planer for 4.3-4.5 (runner, ingest, pilot) skrives efter 4.1b's tegnsætsmåling og 4.3a's
forbrugsprobe; Codex-kvoten nulstilles 2026-09-09. Åbne punkter: fase-pakke-runbookens
projektioner dækker ikke observationer/fortolkninger; `status.md`/`roadmap.md` afstemmes
med GO 1-4 i samme PR.

## 2026-09-06 — GO 4: 149b legacy-migration anvendt i prod — 2018-20 er kildebundet

**Deployet til prod** (projektejer-GO 4). Writer-profil `daa-2018-20-legacy-migration-v1`
(`954f3bb3…`); læse-kun kandidateksport fra prod (591 kandidater, 544 grandfathered + 47 uden
ledger, injektiv, 0 allerede bundet); manifest `b51f83ac…` (bytes `7efcdaac…`, 587
elementer; dispositioner 541 `bound_published` / 46 `bound_draft` / 4 `unresolved_text`
= `I-133`, `II-35`, `III-129`, `IV-94` / 0 `unresolved_identity`); preview `6d19c23d…`
(149a på plads 1/591/591/591, ledger 544, kontrakt 2); dry-run `finalized`/ikke committet;
autorisation `19a2029d…`; apply `finalized`, `committed=true`, batch `0854a091…`
(observed = expected, `legacy_migrations 587`).

Efter apply (læse-kun): 587 personas og accepterede identiteter (evidens
`person_external_id`), bindinger 541 `published` + 46 `draft`, ledger source 1 = 541
`migrated` + 3 `grandfathered_publication` + 0 `withdrawn`, events 587 `draft_created` /
541 `published` / 541 `legacy_migrated`; offentlig flade (v1 og v2) for de 591 personer:
541 `source_record` (alle med »DAA 2018-20, s. N«) + 3 `legacy_narrative`, 0 rækker for de
47 levende; `person`/`fact`/`family_member`/`narrative` aggregat-hashes identiske og
`narrative.tekst/privat/side` uændret for alle 591.

Roadmap-trin 3 (2018-20 fase A-ækvivalent provenance) er dermed `produktionsverificeret`.
Restpunkter: de 4 `unresolved_text` og de 13 mulige `NOISE_RE`-prosalinjer er uændrede;
`get_advisors` skal tjekkes i Supabase-dashboardet (MCP peger på andet projekt).

## 2026-09-06 — GO 3: 149a kilderegnskab for 2018-20 anvendt i prod

**Deployet til prod** (projektejer-GO 3). Writer-profil `daa-2018-20-source-evidence-v1`
(`profile_sha256 = 5919b603…`) indsat; manifest `c7d19c01…` (bytes `db58e407…`, 591
`source_evidence`, 0 `person_create`); preview mod prod `74edd30a…` (før-billede 0/0/0/0,
nøgledækning 591/591); dry-run `finalized`/ikke committet; autorisation `c4113958…`
(service_role + redaktionsaktør); apply `finalized`, `committed=true`, batch `30469676…`
(observed = expected). Efter: 1 rendition / 591 source records / 591 forekomster / 591
accepterede ankre for source 1; aggregat-hashes for `person`, `fact`, `family_member`,
`narrative`, `narrative_record_publication` identiske før/efter. Første forsøg stoppede
fail-closed (`REIMPORT_AUTHORIZATION_REQUIRED`) pga. et fejlagtigt id-udtræk i
operatørscriptet — intet skrevet; rettet og genkørt med samme autorisation.

## 2026-09-06 — GO 2: #152-cutover i prod (kontraktversion 1 → 2)

**Deployet til prod** (projektejer-GO 2). Kæde: backup `c932273b…` (0600) → restore-rehearsal
lokalt (apply OK; postverify fejlede 3× → verifier rettet, PR #168) → frisk læse-kun eksport
(563 bindinger, 552 grandfathered legacy = 544 source 1 + 8 source 3, 8 identiteter, 592
blokerede, 11 direkte læsere; sysid `7642734024280108049`) → review + beslutninger (alle
»godkend baseline« / »bevar som grandfathered«; projektejer eneste reviewer, se decisions
2026-09-05) → konvertering (seks hashes) → preflight `preflight_rolled_back` → apply
`committed` (change set 967, nonce `71f9fc65…`, receipt `512068f804cb52ce…`, 1115
baseline-events, 0 skjulte) → postverify `postverify_passed` fra checkout `c8b76e9`.
Kontraktversion i prod: **2**. Web (main, Vercel) var v2-parat før cutover.

Konsekvens: nye bindinger og DAA-loaders er frosset indtil 149a/149b (GO 3-4);
`red_slet_person` blokerer hel-person-sletning ved publication-events (#152 §11).

## 2026-09-05 — GO 1: DB-migration main → prod (149b-forberedelse)

**Deployet til prod** (projektejer-GO 1, 2026-09-05): `db-migrations.sql` (SHA `a1a52941…`)
og `db-rls.sql` (SHA `8450caee…`) fra main `21ff44b`, hver i én transaktion, exit 0.
Preflight: kontraktfunktion fandtes ikke, sysid `7642734024280108049`. Backup før apply:
`pre-149b-prod-20260904-*.dump` (SHA `5d1dc497…`, mode 0600, uden for git);
restore-rehearsal af samme dump med samme filer: exit 0, tal uændrede.

Efter apply (læse-kun): `narrative_record_contract_version() = 1` (kun additiv: #152 fase 1,
#153 med guard-rettelsen, 149b's writer/reversal/læsegate), `reimport_batch` 1 `activated` +
2 `finalized` (1939's tre batches migreret uden guard-stop), 1811 personer / 1169 narrativer /
563 bindinger / 7197 fakta / 2258 family_member uændrede, 0 ledger-rækker, 124 `red_*`-RPC'er
(95 før), `red_apply_reimport_legacy_migration` GRANTED authenticated (ikke anon),
`reimport_event`-CHECK inkl. `legacy_migration`. Web deployes fra main via Vercel (v2-parat).

Næste: GO 2 (#152-cutover pr. runbook), GO 3 (149a), GO 4 (149b).

## 149b: legacy-migration til narrativ-binding bygget og integreret ende-til-ende (2026-09-04)

Ingen prod-skrivning, intet pushet, intet deployet. #166 (149b) leverer den
generelle `legacy_migration`-elementoperation, der binder 2018-20's 591
eksisterende narrativer til de 591 source records, 149a byggede, og afslutter
deres grandfathered legacy-streams.

**Leveret.** Én ny elementoperation `legacy_migration` i #153's generelle
writer (`private.migrate_legacy_narrative_record` +
`public.red_apply_reimport_legacy_migration`, klassificeret i #154's
ACL-arrays); egen identitetsledger pr. record (`source_persona` +
`source_persona_mention` + accepteret `source_persona_identity` med
`person_external_id` som evidens, ingen placement-kæde — valg A); en
`legacy_migrated`-gren i #152's dedikerede reversal, udvidet med
»reverse `published` → discard draft → reverse `legacy_migrated`« (valg B,
revideret efter empirisk fund: #152's reversal appender til samme stream, så
den oprindelige spec-kæde »reverse `published` → reverse `draft_created`« var
uopnåelig); en rettelse i #152's læsefunktioner
(`person_daa_narrative_publication_allowed` og record-grenene i
`public_person_bio_source_versions(_v2)` filtrerer nu på bindingsstatus, så en
kombination »withdrawn binding + grandfathered ledger« — som først opstår med
149b's fulde fortrydelseskæde — ikke længere giver en dublet på den offentlige
flade); R-gateway/preview/eksport
(`export_legacy_migration_candidates.R`, `export_reimport_preview_helpers.R`,
`apply_reimport_helpers.R` udvidet); Python-bygger og -profil
(`build_legacy_migration_manifest.py`, egen `reimport-legacy-migration-profile-v1`);
et batch-reversal-script (`reverse_reimport_legacy_migration.R`, per-narrativ
reversals i omvendt rækkefølge under én autorisation); integrationstests
(`tests/sql/test-reimport-legacy-migration.sql`,
`tests/integration/test-reimport-legacy-migration.R`) og et nyt CI-trin ved
siden af `reimport_legacy_source_evidence_153`.

**Rehearsal (2026-09-04) — GENNEMFØRT.** Restore af prod-dumpet →
migrationer → #152-cutover (kontrakt v2) → 149a-apply → 149b: manifest 587
elementer, **541 `bound_published`**, **46 `bound_draft`**, **4
`unresolved_text`** (`I-133, II-35, III-129, IV-94`), **0
`unresolved_identity`** (0,7 % under 10 %-stopgrænsen); ledger source 1 = 541
`migrated` + 3 `grandfathered_publication` + 0 `withdrawn`; 587 `source_persona`
+ 587 accepterede identiteter; offentlig v2-flade viser 541 `source_record` og
kun 3 `legacy_narrative` for source 1 (fra 544); nul kanonisk delta (4
aggregat-hashes: `person`, `fact`, `family_member`, `narrative`) og `anon`
uændret (8 hashes); replay `already_applied`; per-narrativ reversal gendanner
begge streams eksakt; batch-reversal bevist som **dry-run** (587 elementer,
`committed=false` — den fulde apply-vej er kun bevist syntetisk i
integrationstesten); `red_reverse_reimport` afvist
(`REIMPORT_WRITER_REVERSAL_INVALID`). Detaljer:
[`legacy-migration-149b-rehearsal.md`](evidensbaseret-genimport/legacy-migration-149b-rehearsal.md),
runbook:
[`legacy-migration-reimport-rehearsal.md`](runbooks/legacy-migration-reimport-rehearsal.md).

**To implementeringsfund undervejs.** (1) Fortryd-kæden i spec §8 var
uopnåelig som skrevet — #152's reversal appender et event til samme stream,
så `draft_created` ikke længere er streamens seneste event efter én
fortrydelse; rettet til den tre-trins kæde ovenfor, spec og
`docs/decisions.md` opdateret. (2) Kombinationen »withdrawn binding +
grandfathered ledger« fandtes ikke før 149b og blottede en dublet-risiko i
#152's læsefunktioner; rettet i samme leverance, ikke udskudt.

**Ikke rørt.** De 4 `unresolved_text`-narrativer forbliver `grandfathered_publication`
(hhv. ubundet for `IV-94`, som er levende); de 13 mulige `NOISE_RE`-prosalinjer
fra 149a-inventeringen (måling 8) er ikke rettet. Begge er separate, endnu
utrufne beslutninger, uden for 149b's scope.

**Intet pushet, intet deployet.** Prod-apply kræver #152-cutover → #153 (med
guard-rettelsen) → 149a i prod (alle tre kun rehearsal-bevist), projektejerens
kvittering for valg A og valg B, og en frisk neutralitetsmåling i prod før
apply.

## 149a: 2018-20 kilderegnskab bygget og bevist mod bogen, ægte rehearsal blokeret (2026-09-03)

Ingen prod-skrivning. Dagen begyndte med en læse-kun retningsvurdering (retningen
fra 25/8 følges, men roadmap-trin 3-4 stod på nul), fire styringsregler i
`docs/decisions.md`, mærkning af hele backloggen, lukning af #156 med restpunkt
(INCOMPLETE-afstemning, snapshot forseglet, draft-PR #165) og opdeling af #149 i
149a (kilderegnskab) og 149b (#166, legacy-migration til binding).

**149a bygget og målt.** Spec, plan (6 tasks) og Task 1-5 på
`feat/149-2018-20-fase-a`: profil-JSON med låste konstanter, `reimport_profile.py`
(kanonisk hash identisk med `private.reimport_canonical_json_sha256`, verificeret
mod databasen), `build_source_evidence_rendition.py` (PDF-/tekst-SHA-gate,
591/591 paritet), `build_source_evidence_manifest.py` (591 elementer, eksakt
delstreng i normaliseret projektion, `manifest_content_sha256 c7d19c01…`),
`export_reimport_preview.R` (læse-kun før-billede), idempotent integrationstest
mod syntetisk v2-base (dry-run, apply, nul kanonisk delta, anon uændret, replay
`already_applied`, reversal fail-closed) og CI-gate. Inventering mod restore af
prod-dumpet: alle stopkriterier opfyldt (`docs/superpowers/reviews/2026-09-03-2018-20-fase-a-inventering.md`).

**To fund.** (1) #153's migrationsguard afviser en base med 1939 fase A-batchen i
status `finalized` — en ren source_evidence-batch kan aldrig aktiveres, så
guarden blokerer formentlig også prod (kommentar på #153; verificeres læse-kun
før #153's prod-GO). (2) Fire 2018-20-narrativer i prod er 2.000-3.900 tegn
kortere end bogteksten, og segmenteringens støjfilter fjerner 100 linjer midt i
poster (13 muligvis prosa) — begge til 149b.

**Sen aften: guard rettet og ægte rehearsal gennemført.** Prod bekræftede fase
A-batchen som `finalized`; guarden fik en evidensbundet undtagelse (tests: positiv
fixture blokerer mod HEAD, migrerer med rettelsen; to negative cases blokerer). Derefter
restore → migrationer → #152-cutover (kontrakt v2) → profil → preview → dry-run → apply:
1 rendition / 591 records / 591 forekomster / 591 ankre, fem kanoniske aggregat-hashes
og ni `anon`-hashes identiske, replay `already_applied`, reversal fail-closed. 149a er
`integreret ende-til-ende`. Draft-PR #167. Reversal-afvigelsen kvitteret.

**Codex-begrænsning:** Codex' sandbox kan ikke nå lokal PostgreSQL; databasearbejde
kørte i Claude-subagenter, ren kode hos Codex.

## Bindende styringsgrundlag for evidensbaseret genimport indført (2026-08-25)

Dokumentpakken og dens LLM-/dokumentindgange er indført. Det stabile
[værdigrundlag](evidensbaseret-genimport/vision.md), det styrende
[roadmap](evidensbaseret-genimport/roadmap.md), den tekniske
[målarkitektur](evidensbaseret-genimport/teknisk-maalarkitektur.md) og det
daterede [statussnapshot](evidensbaseret-genimport/status.md) har nu hver sin
myndighed. Nyt genimportarbejde har obligatorisk roadmapkobling og skal opfylde
de seks adgangskrav til planer.

Det første snapshot gør C3's integration-, rehearsal- og stopport før
produktion til det aktive programmål og fastholder den generelle
ende-til-ende-kæde som uafsluttet. Ingen kode, database, produktion eller
CI-håndhævelse er ændret. Den varige beslutning er registreret i
[beslutningsloggen](decisions.md).

## Helhedsvurdering af genimporten + C3 apply-plan revideret (2026-08-22)

Ingen prod-skrivning. Dagen gik med at måle, hvor programmet faktisk står, og
at bringe C3's apply-plan i en tilstand, der kan udføres.

**Afvigelsesvurdering mod den oprindelige plan.** Fem parallelle læse-kun
kodeaudits + en prod-måling + en uafhængig Codex-analyse gav samme dom:
fundamentet er bygget (og på DB-siden stærkere end planlagt), men programmets
kerne er ikke nået. Fortolkningslaget har **0 rækker**, 2018-20 har **0**
source records, `source_record_placement` og medlemskabstabellerne er **tomme**,
og `evidence_extract.py` kalder bevidst ingen model. Det byggede er et
provenance-lag for 1939 oven på juli-loaderens data — ikke spec'ens
evidensbaserede genimport. Fuld opgørelse med dom pr. udestående i
`docs/superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`.

**12 issues oprettet: #147-#158.** Tre beslutninger truffet: fortolkningslaget
skal fyldes (#147/#148), 2018-20 skal have fase A-ækvivalent (#149), og
fase-pakke-modellen er vedtaget som den gældende prod-gate (#156).

**To egne påstande falsificeret ved måling.** `narrative` har ingen
unique-constraint på `(subjekt, source_id)` — én-pr-udgave bor i RPC'en og
læserne, så #152 er en writer-/læser-ændring, ikke en skemarestrukturering. Og
»#152 blokerer C3« var en påstand, ikke en udledning: C3's `TIL`-semantik
kræver bindingstilstand `absent`, så hver sag etablerer ét record ↔ ét narrativ
↔ én person og er fremadkompatibel. **Gaten blev ophævet, rækkefølgen byttet
om til C3 → #152 → #153 → #149.** Rettelserne står som tilføjelser, ikke
omskrivninger.

**Merge-patologien bekræftet empirisk.** Person 1017's narrativ (369 tegn)
rummer hele `record-e8bace88` (236) plus begyndelsen af `record-5fc1a041`
(150), hvis hale ligger i person 1021 (57 tegn). Ét narrativ spænder to
records, og ét record spænder to narrativer. Tre af de tolv
»midt-i-sætning«-sager viste sig at være OCR-tegnfejl (`lven`, `l. Comtesse`),
ikke grænsefejl.

**C3's apply-spec godkendt med én ændring:** den varige databaseoverflade
navngives generisk (`reimport_case_*` / `red_*_reimport_cases`) parametriseret
på kilde og fase, så C3 bliver første bruger af den generelle kontrakt frem for
otte nye udgavespecifikke objekter (spec-invariant 12, #153). Scriptfilnavne er
bevidst uændret.

**Apply-planen revideret mod 12 adversarial-fund (Codex sol, NO-GO).** Alle
tiltrådt. To af dem — manglende `source_id`/`phase`/`state_sha256` i
signaturerne og et filkort der modsagde genbrugsbeslutningen — var fejl i
samme dags egen ændring. Blandt rettelserne: to adskilte artefaktforløb
(rehearsal og prod kan ikke dele et databasebundet manifest), migrationstrin
mod den restorede base, reversal som selvstændig batch, partielt unikt indeks
på aktiv binding pr. source-record, live-guard mod `staged`/`levende`/`privat`,
og reconciliation der erhverver den globale lock før receipt-opslag.
`haendelse`-kravet blev nedskaleret til »kræv sættet tomt« på grundlag af
prod-målingen (0 rækker). Task 1 er færdig (50 tests grønne, bygget i sideløbende
session).


## C0's efterkørsel UDFØRT i prod — ni record-koblinger (2026-08-21)

De ni personer, hvis 1939-narrativ stod med fejlbehæftet tekst fra den første
import, har nu den rensede, evidensbaserede tekst og en publiceret
kildebinding. `change_set 965`, aktør `johan@reventlow.dk` som `redaktion`.

**Resultat:** bindinger **550 → 559**. Narrativer (1.169), personer (1.811),
fakta (7.197) og relationer (2.030) **uændrede** — fasen rørte tekst og
bindinger, intet andet. `anon` ser fortsat 1.734 personer.

| Person | Nu | Blev | Δ |
|---|---:|---:|---:|
| **991** | 32 | **32** | **0** — kun bindingen |
| 963 · 992 | 103 · 107 | 101 · 105 | −2 |
| 1296 · 1298 · 1299 | 278 · 349 · 666 | 275 · 344 · 655 | −3 · −5 · −11 |
| 1297 | 731 | 688 | −43 |
| **978** | 100 | **140** | **+40** nyt indhold |
| **967** | 149 | **193** | **+44** nyt indhold |

Kun 967 og 978 tilførte reelt nyt indhold. De negative delta er normalisering —
samme rensning, fase B gav de øvrige 551.

**8 change_events, ikke 9:** person 991's tekst er byte-identisk før og efter,
så UPDATE'en skrev samme værdi og triggeren så ingen ændring. Det er beviset
for fasens succeskriterium.

**Det afgørende fund undervejs:** C0's `verbatim_text` er RÅ OCR. Alle ni
fejlede fase B's slutinvarianter — enlige linjeskift, uopløste orddelinger,
`### PAGE 0063 ###` i 1299, trailing whitespace i 1297. Uden normalisering
ville fasen have indført rå tekst i en bestand af 551 rensede. `narrative_norm_v1`
blev derfor et obligatorisk trin, og efterkontrollen bekræfter: **0 narrativer
med rå sidemarkører, 0 enlige linjeskift i de ni.**

**Person 1017 blev flyttet til C3.** Dens kobling ville have slettet 149 tegn,
hvoraf de første ~92 ikke findes noget andet sted i korpus — person 1021 viste
sig at være halen af dens afsnit B), skåret over midt i det orddelte
»Revent- low«.

**Menneskeark:** otte orddelingsvalg, ikke ni biografier. Brugeren godkendte
alle otte som `merge` (Efter+slægt, For+pagter, For+mand, Folke+tinget,
Rigs+raad, Katedral+skole og to gange Legationssekre+tær). Arket var
hash-bundet (`98fbb11b…`) og verificeret byte-identisk umiddelbart før kørslen.

**Backup:** `pre-c0f-20260821-112005.dump` (5,7 MB, 0600), SHA-256
`fcfeb2253…`. Manifest `f067a4c3e…`, hash-låst ind i writeren.

**Kvalitetsarbejdet:** fem tasks, otte fix-runder, 19 commits. Alle reviews af
Codex sol. Rehearsal mod en restore af prod-dumpen — så de øvede RPC'er var de
**live** definitioner. Fail-closed verificeret mod prod: en gentagen kørsel
afvises med `C0F_APPLY_OLD_SHA_MISMATCH`, og et manifest bygget mod øvebasen
afvises med `C0F_APPLY_DATABASE_MISMATCH`.

**Udestår:** de 16 `[NY]`-records, de 7 C3-sammenlægninger plus 1017/1021, og
de 12 grænsefejl-kandidater. 963 og 967 forbliver staged — bevist ufarligt, da
`private` ikke er eksponeret gennem API'et.

---

## Fase D2 UDFØRT i prod — 21 ægtefæller publiceret (2026-08-20)

De 21 staged gift-ind-ægtefæller er nu offentligt synlige. `change_set 960`,
aktør `johan@reventlow.dk` som `redaktion`, 21 `change_events` — publiceringen
er fortrydbar ad den almindelige vej.

**Kontroltal, målt umiddelbart før kørslen:** 21 valgte · 28 staged i alt ·
7 bagefter · 0 ekstra medrevne · 0 overlap med C0's uafklarede. Id-listen
identisk med designdokumentets 21.

**Efterkontrol mod prod:** `staged 28 → 7`; personer 1.811, facts 7.197,
relationer 2.030, narrativer 1.169 — alle **uændrede**; 0 af de 21 er
ikke-kvalificerede (ingen staged, levende, private eller navnløse). Målt med
`SET LOCAL ROLE anon`: **1.734 personer synlige, 0 levende, 0 staged** —
RLS-gaten holder efter publiceringen.

**Backup før skrivning:** `work/task28-1939-v50-d2-aegtefaeller/pre-d2-20260820-222135.dump`
(5,7 MB, 0600), SHA-256 `2c974998df4b8f9fe3e73254dfbc254bdd7ec96b12959ea5f4def59cc2289f85`.
Udvalgsfil `spouse-selection-v2.json`, SHA-256
`8487ad711164d429d0adfa54984af7bbfda7fd75217868fceb8821bf725f3463` — hash-låst
ind i apply'en, som er obligatorisk.

**De 7 tilbage:** `933, 935, 940, 963, 967, 1014, 1135` — ikke én gruppe. 933,
935, 940 og 1135 er blandt C0's 9 uforklarede; 1014 står på C0's
uafklarede-liste; og **963 og 967 er `[KOBL]`-mål der selv er staged**, altså
et C0-spørgsmål frem for et D3-spørgsmål. Se
`docs/superpowers/reviews/1939-v50-fase-c0-efterkoersel-genmaaling.md`.

**Udestår:** brugerens verifikation i web-fladen — særligt at person 1662's
ægteskab nu fremgår på den collapsede person sammen med 785's. Web-fladen i
prod bygger fra `main`, så ændringen er synlig dér uden ny deploy (den ligger i
data, ikke i kode).

---

## Fase D2: Task 1+2 bygget, reviewet og rehearsal-kørt (2026-08-20)

De 21 staged gift-ind-ægtefæller, hvis partner allerede er synlig. Design i
`docs/superpowers/specs/2026-08-20-1939-v50-fase-d2-aegtefaeller-design.md`,
plan i `docs/superpowers/plans/2026-08-20-1939-v50-fase-d2-aegtefaeller.md`.
**Task 3 (prod-kørslen) er IKKE kørt** — GO-pakken ligger i
`docs/superpowers/reviews/1939-v50-fase-d2-go-pakke.md`.

Grundlaget er **konsistens**, ikke en ny evidenstærskel. De 21 har 0
narrativer, 0 record-bindinger og 0 external_ids, så D1's kriterium kan per
definition ikke bruges. Men D1 publicerede allerede 24 stubs af samme slags,
fordi `red_publicer_personer` trækker staged familiemedlemmer med. De 21
adskiller sig kun ved, at deres partner blev synlig i en tidligere runde.

Genmålt mod prod med den hærdede kode: 21 valgte → 28 → 7 staged, 0 ekstra
medrevne, 0 overlap med C0's uafklarede, 0 levende eller private. Id-listen er
identisk med designdokumentets. Udvalgsfil `spouse-selection-v2.json`
SHA-256 `8487ad71…`; backup `pre-d2-20260820-222135.dump` SHA-256 `2c974998…`.

**Et hul i planen ville have stoppet Task 3.** `red_publicer_personer` gates på
`current_rolle()='redaktion'`, udledt af `profiles WHERE id = auth.uid()`. Over
en direkte R-forbindelse er `auth.uid()` NULL → rollen bliver `medlem` → RPC'en
kaster. Planens R-kode gjorde intet ved det. Afgjort empirisk mod prod:
`auth.uid()` coalescer `request.jwt.claim.sub` **først**, aktøren sættes nu i
transaktionen og verificeres mod `profiles`, og RPC'en kaldt i en `READ ONLY`-
transaktion fejlede på `INSERT` — altså *efter* rolle-gaten.

**Adversarial review (Codex sol)** fandt fire ægte fund, alle rettet. Det
alvorligste: drift-guarden sammenlignede *antal* frem for *hvem*. Mister en
valgt person sin synlige partner mens en anden staged person får én, er
antallene uændrede, SHA-låsen passerer (filen er jo ægte), og vi ville
publicere nogen ingen har set på. Guarden sammenligner nu id-mængden, målt
inde i skrive-transaktionen. Desuden: eksporten gatede ikke på
`levende`/`privat`/navn (invariant 8), apply validerede ikke dokumentets
øvrige felter, og `--backup` er nu obligatorisk.

To fælder som testene selv fangede: `modifyList` rekurserer, så en navnløs tom
liste efterlader feltet urørt (guarden ville aldrig fyre), og `any(logical(0))`
er `FALSE`, så en manglende kolonne ville få en fail-closed gate til at tie.

**Rehearsal kørt, selv om D2's plan udelod den.** D1's plan krævede rehearsal
mod frisk restore; D2's gik backup → eksport → apply. Mod en restore af dagens
prod-dump (`daa1939_d2_rehearsal1`): 21 afstaget, `staged 28 → 7`, nul delta på
person/fact/relation/narrative, 21 `change_events`, 0 ikke-kvalificerede blandt
de 21, gentagen kørsel og induceret drift begge afvist fail-closed. Fordi
kopien er en restore af prod, var den øvede `red_publicer_personer` den
**live** definition — ikke `db-migrations.sql`'s.

---

## `red_slet_person` DEPLOYET til prod og verificeret (2026-08-20)

Migrationen er kørt mod prod i én transaktion: begge funktioner genudgivet,
`person_slaegt_membership` og `person_lineage_membership` registreret i
`version_pk_registry` med `log_change`-triggere.

Backup før skrivning:
`work/task29-red-slet-person-deploy/pre-red-slet-person-20260820-201833.dump`
(6,1 MB, 0600), SHA-256 `52b64e806fd830727db7a6f1a77591fc20e12af22472bc0637966a2dc90622d9`.

**Alle tre nye db-verify-blokke bestod mod prod** (kørt i en transaktion der
blev rullet tilbage):

- narrativ-binding + slægts-/linjemedlemskab fjernet, `source_record` bevaret
- Q's hændelse bevaret, `relation_id`-ankeret løsnet
- persona-bundet person afvist med `PERSON_HAR_KILDEIDENTITET`

**Verificeret på ægte data:** person 924 (én kildebinding) kunne slettes i en
rullet-tilbage transaktion. Præcis den operation fejlede før med
`narrative_record_publication_narrative_id_fkey`. Prod uændret: 1811 personer.

Efterkontrol: begge funktioner er `SECURITY DEFINER` med
`search_path=public`; den live kode indeholder alle fire nye elementer; begge
medlemskabstabeller har trigger. Sikkerhedslint viser 0 SECURITY
DEFINER-funktioner i `public` uden `search_path`.

**App-laget efterprøvet:** web 773/773 og mobil 426/426 tests grønne.
Typetjek: mobil 0 fejl; web uændret på 34 præeksisterende fejl (`GeoMap.tsx`,
`mediaDedup.ts`, `humanReview1939Ui.test.ts` — ingen i de rørte filer).
`SletPreview` konstrueres præcis tre steder, og alle tre er opdateret.

**Forbehold:** `get_advisors(security)` er *ikke* kørt — MCP-forbindelsen
peger på en anden Supabase-konto. Linten ovenfor dækker samme klasse af fund
(search_path), men ikke Supabase's øvrige regler. Bør køres fra dashboardet.

**Bemærk om web-fladen:** prod bygger fra `main`, så slet-modalen dér viser
stadig den gamle tekst. De nye narrativ- og bindingstal er live i databasen,
men usynlige indtil branchen merges og Vercel bygger igen. Det er forventet,
ikke en fejlet udrulning.


## Sletnings-rutinen hærdet efter dobbelt review (2026-08-20)

Fixet ovenfor blev reviewet af Codex sol og arkitekturvurderet af fable. Tre
fund blev accepteret og rettet, ét blev afvist som uopnåeligt.

**Fortrydbarhed.** Ingen af de tabeller, `red_slet_person` nu sletter fra, stod
i `version_pk_registry` — sletningerne gav altså ingen `change_events`.
`person_slaegt_membership` og `person_lineage_membership` er nu registreret med
`log_change`-triggere. `private.narrative_record_publication` kan ikke
registreres som mekanikken ser ud; vurderingen er at tabet er
publicerings-tilstand (`record_ref`, `published_at`), ikke evidens — se
`decisions.md`.

**Hændelses-ankre.** Påvist asymmetri: sletningen samler relationer på både
subjekt- og objektsiden, mens hændelses-loaderen forankrer efter subjekt alene.
En relation Q→P kan derfor bære en hændelse under Q's narrativ, som blokerer.
Ankeret løsnes nu (`SET NULL`) i stedet for at slette en anden persons hændelse.

**Kilde-identitet.** `source_persona_identity_event` er append-only, så en
person, der én gang har haft en accepteret identitetsbeslutning, kan aldrig
hard-slettes. `red_slet_person` afviser nu tidligt med
`PERSON_HAR_KILDEIDENTITET` i stedet for en rå fremmednøglefejl halvvejs
igennem. Den varige løsning — tombstone frem for hard delete — er anbefalet,
men **ikke besluttet**.

**Afvist:** `conclusion.valgt_assertion_id` blev meldt som blokerende, men
ingen writer kan producere tilstanden (`red_upsert_fakta` og retract-stien
sætter target og valgt påstand i samme operation). Ingen defensiv kode tilføjet.

`db-verify.sql` har fået to tests mere (hændelses-ankeret og persona-afvisningen).
**Ingen af de tre nye tests er kørt** — de kræver at migrationen først er deployet.

**Målt mod prod (read-only):** 550 narrativ-bundne personer, hvoraf **8** er
blokeret af kilde-identitet. Rettelsen frigør altså 542 af 550, og
tombstone-spørgsmålet angår 8 personer — ikke bestanden. Tallet vokser dog med
hver accepteret identitetsbeslutning og bør måles igen før næste udgave.


## `red_slet_person` rettet — bindinger og medlemskaber ryddes nu (2026-08-20)

Fejlen fra samme dag (se nedenfor) er rettet i kode, men **ikke deployet**.
`red_slet_person` fjerner nu `private.narrative_record_publication`-bindingerne
før narrativerne, så sletning ikke længere strander på fremmednøglen for de 551
narrativ-bundne 1939-personer.

Gennemgangen af *alle* fremmednøgler mod `person` og `narrative` fandt to
blokerende mere end den oprindelige note kendte: `person_slaegt_membership` og
`person_lineage_membership` (begge `person_id NOT NULL` uden cascade). Begge
ryddes nu. `private.source_record` røres fortsat aldrig.

`red_slet_person_preview` er udvidet med `antal_narrativer`, `antal_bindinger`
og `antal_medlemskaber`, og både web- og mobil-slet-fladen viser tallene — en
redaktør kunne før slette en biografi uden at få det at vide.

To persona-tabeller er bevidst ladt urørt og noteret som åben beslutning i
`docs/decisions.md`: deres CHECK-constraint binder `canonical_person_id` til
`decision_status`, så feltet hverken kan slettes eller nulstilles uden en
redaktionel afgørelse.

**Status:** web-suiten er grøn (773/773), og typetjekket viser samme 34
præeksisterende fejl som før ændringen (i `GeoMap.tsx`, `mediaDedup.ts` og
`humanReview1939Ui.test.ts` — ingen i de rørte filer). Den nye `db-verify`-blok
er **ikke kørt**: sessionen havde ingen base-adgang. Deploy mod prod +
`get_advisors(security)` udestår.


## Person 975 pensioneret + fund: `red_slet_person` er brudt (2026-08-20)

Brugerens gennemlæsning af de nypublicerede poster afslørede, at person 975
(»Greve Conrad til Grevskabet Reventlow, der af legitimt Afkom kun efterlod en
Datter«, s. 509) ikke er en kildepost, men en **oversigtslinje** — hovedposten
er person 1240 (s. 550), som allerede er `samme_som`-linket til 2020-udgavens
530. 975 blev slettet (`change_set 956`); prod: 1812 → **1811 personer**.
`private.source_record` urørt på 592: registreringen af, at teksten står på
s. 509, er stadig sand.

Maskinel eftersøgning bekræftede at 975 var den eneste af de 44 publicerede
med oversigtsformulering — de øvrige korte narrativer er ægte personposter om
børn, der døde som spæde.

**Sideordnet fund:** `red_slet_person` fejler på en fremmednøgle mod
`private.narrative_record_publication` for **alle 551** narrativ-bundne
1939-personer. Funktionen er ældre end bindingstabellen. Her blev det omgået
ved at slette bindingen først i samme transaktion; den egentlige rettelse er
noteret som åben i `docs/decisions.md`.

## Fase D1: 68 personer publiceret i prod (2026-08-19)

De 44 staged 1939-probander med `published` record-binding er gjort offentligt
synlige, og `red_publicer_personer` trak som designet 24 ægtefælle-stubs med
sig — i alt **68 personer**. Prod: staged 96 → **28**. Person-, fact-,
relation- og narrativtællinger uændrede (1812 / 7199 / 2031 / 577); fasen
rører udelukkende `staged`. Efterkontrol mod `change_set 955`: 68 rørte, 68
afstagede, 68 offentligt kvalificerede (0 levende, 0 private).

Udvælgelsen byggede på tre objektive kriterier, aldrig på navne — staged
person 927 hedder »Henrik« og deler navn med otte synlige personer. To gates
lå i eksporten: 0 af de 44 var berørt af C0's uafklarede, og RPC'ens EGEN
WHERE-klausul kørt mod udvalget gav 68, så partner-effekten var bevist frem
for antaget. Rehearsal mod frisk prod-restore gav samme resultat, og en
gentaget kørsel blev afvist fail-closed.

**Fejl undervejs, som brugeren efterfølgende valgte at lade stå:**
publiceringen blev kørt mod produktionen før GO-pakken var skrevet.
Wrapper-scriptet blev kaldt med et opfundet `--dryrun`-flag, som det
ignorerede — der var ingen dry-run-tilstand, og scriptet forbandt til prod.
Ændringen var indholdsmæssigt den godkendte, men rækkefølgen var forkert.
Wrapper'en kræver nu `--jeg-mener-det` og afviser ukendte argumenter.

Rest: 28 staged (7 blokerede af C0/C3, 21 ægtefæller til D2). Redegørelse:
`docs/superpowers/reviews/1939-v50-fase-d1-readiness.md`.

## Fase C0: de 41 »ægte nye« records gennemgået — afventer afgørelser (2026-08-19)

Fase B efterlod narrativer med gammel tekst, fordi 41 kilderecords var
klassificeret »ægte nye« uden baseline-tilknytning. C0 bygger grundlaget for
at omgøre de klassifikationer: read-only prod-eksport (577 narrativer, 551
bindinger), deterministisk matchning mod hele bestanden, og en token-fil med
41 udfyldte anbefalinger. **Intet skrevet til prod.**

Fordeling: 9 kobling · 1 stillingtagen · 5 for kort · 7 sammenlægning ·
11 uden kandidat · 8 allerede færdige. Lukning: 26 personer m. gammel tekst
(ikke 23 — binding-proxyen viste sig at være et supersæt af den empiriske
liste og fangede 991, 1791, 1795), 9 løst i C0, 8 udskudt til C3, **9
uforklarede** (933, 934, 935, 940, 991, 1135, 1791, 1795, 1802). Alle 11
»uden kandidat« har dækning 0.00 — de er formentlig modstykker til de
uforklarede, men teksterne er for beskadigede til maskinel afgørelse.

To fejl i C0's eget værktøj fanget af dets egne gates: (1) tekstmålet var
længde-asymmetrisk i begge udgaver — `ratio()` gav 0.015 for en perfekt
delstreng i et langt narrativ, og min-normaliseret dækning gjorde derefter
korte modparter promiskuøse (spredte bogstaver → 1.00); løst med krav om ét
sammenhængende anker. (2) Otte af de 41 var allerede materialiseret som
personer i task 25 — import-preview er fra før den kørte — og et
koblingsforslag ville have kollideret med deres UNIQUE narrativ-binding.

**Afgørelser truffet samme dag:** alle 41 afgjort, 0 uafklarede — 10 kobling,
16 ny, 7 til C3, 8 allerede færdige. De seks tvivlstilfælde blev afgjort ved at
læse kildens og databasens tekst side om side: R37 er tegn-for-tegn identisk
med person 991, de fem øvrige er strukturelle oversigtslinjer eller (R10) en
forveksling af en 1700-tals-post med en person født 1864. Bemærk til
efterkørslen: koblingen R40 → person 1017 erstatter dennes tekst med afsnit A)
alene — en reparation af en gammel grænsefejl, men den fjerner synligt indhold,
hvis B)-del hører til person 1021 og følger med i C3.

Rapport: `docs/superpowers/reviews/1939-v50-fase-c0-linkage-report.md`.
67 pytest-tests + 9 R-assertions; output byte-identisk under tre
`PYTHONHASHSEED`-værdier.

## Fase B: 551 biografier erstattet med evidensbaseret, renset tekst (2026-08-19)

Programmets oprindelige formål er nået: de fejlbehæftede narrativer fra den
første 1939-import er erstattet af tekst udtrukket direkte fra det
menneskeverificerede grænsearbejde i Calamari-OCR'en — og normaliseret til
læsbar prosa.

**Normaliseringen (`narrative_norm_v1`):** 2.304 OCR-linjeskift samlet til
mellemrum, 584 orddelinger sammentrukket (10 kompositum-navne bevaret),
**499 søskende-ordenstal strippet** (»1. Sybille Malvina Lonny« →
»Sybille Malvina Lonny«), 73 sidemarkører fjernet. Afsnit, tegnsætning,
stavning og OCR-egenheder er urørt — det er evidens, ikke redaktion.
Slutinvarianter håndhæves i koden: ingen `### PAGE`, intet enligt
linjeskift, ingen trailing whitespace.

**Menneskeligt checkpoint:** 178 usikre tilfælde (168 ubeviste
sammentrækninger + 8 tvetydige bindestreger + 2 ordenstals-varianter) blev
afgjort af brugeren i en token-fil efter grænseflade-mønstret (ret kun
tokenet; fail-closed konverter afviser enhver anden ændring). Resultat: 165
merge, 11 keep, 2 strip — bl.a. `kar-og` bevaret frem for det meningsløse
»karog«, og begge ordenstals-varianter strippet.

**Prod-apply:** 551 narrativer (543 eksisterende + de 8 nye), 543 nye
record-bindinger publiceret (551 i alt), 2 dokumenterede sidehenvisnings-
rettelser (person 975: 508→509, 986: 503→505 — gamle importfejl, fanget af
writerens værn og verificeret mod grænsematerialet). Nul kanonisk delta:
1.812 personer, 7.199 facts, 2.031 relationer, 682 familier uændret. Alle
577 narrativers samlede hash i prod er identisk med rehearsal-basens
(`8a79112e…`). Backup før apply:
`daa-production-before-phase-b-apply-20260819-172157.dump` (0600, SHA
`cfe40b7d…`). Fortryd: ét change_set med de gamle tekster bevaret.

**To fælder fanget undervejs:** writerens replay-værn dækkede kun teksten,
selv om `red_upsert_narrativ` også skriver `privat` og `side` — en post med
`privat=true` ville tavst være blevet offentlig (invariant 8). Og writerens
SQL-`digest()` var ukvalificeret; prods `search_path` mangler `extensions`,
så applyen ville være fejlet — fanget af en read-only probe før skrivning.

## Fase A: fuldt kilderegnskab i prod — 592/592 records forankret (2026-08-18 aften)

Det menneskeverificerede grænsearbejdes komplette kilderegnskab er nu i
produktionsdatabasen: fase A-applyen skrev de 584 resterende source records
(batch `328a813a…`, 584 source_evidence-events, nul kanonisk delta) oven på
de 243 eksisterende. Prod-evidenslaget står nu på 592 records / 897 byte-
ankre-occurrences-observationer-mentions, alle bundet til Calamari-
renditionen. 235 nøgler deles bevidst med task 25's claim-rækker (helpost-
vs. claim-granularitet; append-only-trigger gør kind-overskrivning
strukturelt umulig).

Bygget efter subagent-metoden (4 tasks, 2 fix-runder, uafhængige reviews
der genudledte artefakterne selv, fable-slutreview clean): deterministisk
manifest-bygger (fil-SHA `1945416b…`, content-SHA `19d72155…` = DB'ens
idempotens-nøgle), hard-låst R-writer (eksplicit `--dry-run|--apply`, delt
advisory-lås med task 25-writeren), rehearsal mod frisk prod-restore med
byte-identiske baselines og bevist idempotent replay. Backup før apply:
`daa-production-before-phase-a-apply-20260818-190120.dump` (0600, SHA
`50d62309…`). GO-pakke: `docs/superpowers/reviews/1939-v50-phase-a-readiness.md`.
Næste: fase B — narrativ-erstatning (478 ændrede) inkl.
ombrydnings-normalisering.

## Afgrænset 1939 v50-production-writer kørt i prod: publikation + cutover (2026-08-18)

Denne afgrænsede production-writer-leverance er udført og verificeret i
produktion; entryen dokumenterer ikke, at hele den evidensbaserede 1939
v50-strøm eller det generelle genimportprogram er afsluttet. Tidligere på dagen
(Codex): production apply (8 staged summary-personer 1846-1853 + 305
source-only evidensobjekter, batch `560c39f8…`) og name-completion apply (8
kildebundne navnefakta, batch `0b0055f6…`). Derefter (denne session):

- **Narrativ-publikation:** `red_publicer_narrative_record` hærdet til
  draft→published med eksakt felt-match (`FOR UPDATE`, mismatch fejler uden
  mutation); DDL deployet via `apply_migration` (RPC-md5 `6e888307…`,
  `get_advisors(security)` uden nye fund); de 8 draft-bindinger publiceret via
  hash-låst, atomisk DO-blok genereret deterministisk fra manifestet.
- **Cutover:** gennem skemaets autoriserede vej —
  `red_authorize_1939_v50_cutover` → `red_activate_1939_v50_batch` (fuld
  integritetskontrol af kæden source-batch ↔ completion ↔ facts/citations ↔
  personae) satte `staged=false` for præcis de 8. Batch `activated`,
  autorisation `consumed`.
- **Efterkontrol:** alle 8 offentligt kvalificerede (afdøde, ikke-private, navn
  sat), record-provenance synlig 8/8, nul-delta i øvrigt (1.812 personer,
  7.199 facts, 321 write-events). Umiddelbare backups før hvert skrivetrin
  (publikation: `…narrative-publication-20260818-151116.dump`; cutover:
  `…1939-v50-cutover-20260818-151949.dump`), begge 0600 + SHA-256-noteret.

Rehearsal forinden: endelig real-DBI-kørsel mod frisk produktionsækvivalent
restore med byte-identiske før/efter-baselines (0 persistens — previewets
gateway har ingen commit-operation). Rapporter i
`work/task25-1939-v50-production-writer/`. Læring: Supabase MCP `execute_sql`
kører i read-only transaktion — skrivninger går via `apply_migration` eller
direkte psql; første apply-forsøg abortede derfor fail-closed uden ændringer.
Udestår: manuel browser-test af de 8 poster i web-fladen.

## Hele 1939-bogen gennemgået i tekstfladen (2026-08-10)

Mennesket har været igennem alle 86 sider. Skæringssættet gik fra 446 forudsatte til
**651**: 414 beholdt, 32 forkastet, 237 nye — plus **132 udeladelser** af tekst der ikke
hører til nogen post (overskrifter, slægtled-etiketter og indledende oversigter). Målt
mod bogens egen evidens er dækningen lukket: **alle 68 trykte postnumre i ejerløs tekst
er nu enten skåret eller udeladt**, mod 68 uden ejer ved fase 1's afslutning.

To fejl fundet undervejs, begge af den slags ingen gate kan se:

**76 udeladelser begyndte ét tegn efter et linjeskift**, så overskriftens første bogstav
blev stående som ejet tekst (`eneralmajor` i stedet for `Generalmajor`). Brugeren fandt
én; en måling fandt de øvrige 75. Rettet maskinelt efter en entydig regel og efterprøvet
på en anden egenskab end den rettede: udeladelser der starter ved et linjeskift gik fra
53 til 129, uden overlap eller tomme områder. Fejlen kunne ikke genskabes som en levende
fejl i den nuværende flade — tre genindlæsninger, begge tag-skrivemåder og gen-indlæsning
via `--markeringer` gav alle nul afvigelse — så årsagen står åben.

**Sidetallet 598 dækker to kildesider.** Fremskridtet var nøglet på det trykte tal, så
86 af 86 var uopnåeligt, og — værre — kvittering for den ene side fik den anden til at
fremstå gennemgået. Identiteten er nu kildesiden (altid unik), det trykte tal en etiket
(`PDF-side 598 (1/2)`), og gamle eksporter oversættes fail-closed: et tvetydigt sidetal
markerer ingen af siderne og rapporteres.

Nyt: `check_graenseflade_export.py` kontrollerer en menneskelig gennemgang for de
fejlmåder byte-gaten ikke kan se (én-tegns-forskydning, overlap, skæringer midt i en
linje, trykte numre uden ejer, diff mod forrige eksport).
`docs/superpowers/plans/2026-08-10-graenseflade-overdragelse.md` er en selvstændig
overdragelsesprompt med invarianter, verifikationsveje og fem udestående opgaver.

Tre gange kaldte en kontrol korrekt arbejde for en fejl: den ledte efter en skæring
*inde i* et hul (den rigtige placering er kanten), viste linjen *før* en skæring ved et
linjeslut, og krævede at udeladelser flugtede med linjer. Verificér mod noget kilden selv
siger — bogens trykte postnumre — ikke mod din egen definition af færdig.

## Grænsekontrollen som én tekst frem for 446 kasser (2026-08-09)

Fase 1's flade besvarede "er denne skæring rigtig?" én kasse ad gangen, men fase 1's
egentlige fund var dækningen: 75,3 % af Calamari-teksten er ejet af en post, og 101
poster ejer intet. Et hul er praktisk talt usynligt i en flade, der kun viser
skæringer mellem spænd, som allerede findes. Ny flade (brugerens forslag): hele
teksten i én tekstboks, skæringerne som markørlinjer, navigation via browserens egen
søgning. Markøren siger kun "her klippes"; ejerskab afgøres i en senere runde.
Tavshed er godkendelse, så eksporten registrerer i stedet ændringen mod de 446
forudsatte. Gæt inde i huller er forslag, der kun tæller, hvis mennesket fjerner
ordet `FORSLAG?`.

Kildeteksten bruger allerede `###` til sine egne 86 sidemarkører, så fladens markører
fik `===`: ellers ville integritetskontrollen fjerne bogens egne linjer sammen med
vores, og en sletning i kilden kunne passere ubemærket. Kontrollen stripper kun
navngivne mønstre og byte-sammenligner resten med kilden, løbende og ikke først ved
eksport; eksport er umulig — ikke frarådet — mens den er brudt.

Målingen korrigerede to tal, vi troede vi kendte: de 46.015 ejerløse tegn sidder i
**97 huller, ikke 355** (258 af "hullerne" er linjeskiftet mellem to poster), og
kilden er 186.655 tegn, ikke 189.671 — det tal var bytes. Tre fejl fundet ved at køre
mod rigtige data frem for syntetiske: generatoren krævede at hver skæring lå ved et
linjestart (352 af 446 gør ikke, de ligger ved linjens slut), 256 bannere annoncerede
et linjeskift som ejerløs tekst, og **to huller med rigtig tekst — 868 og 6.330 tegn —
var helt usynlige, fordi koden krævede en nabo på begge sider.** Dokumentets kant har
ingen nabo. Samme fejlmønster som dagen før: fravær af bevis læst som bevis på fravær.

Verificeret i Chromium mod rigtige data: 21/21 kontroller, inkl. at en eksport kan
læses tilbage i en ny fil (445 forudsatte + 1 egen skæring overlevede). Suiten er
1.106 grønne. Resultatet er et skæringssæt og review-/fil-GO — ingen materialisering;
afløsning af accepteret evidens kræver fortsat en autoriseret operation (beslutning
2026-08-08).

## Medie-metadata-udvidelse (2026-08-06)

Udvider hvad der kan registreres om et medie, så eksternt hentede billeder
(fx fra Deutsche Digitale Bibliothek) kan håndteres korrekt: 12 nye
medie-faktatyper som `vocab`-seeds (kilde-URL, kilde-institution, eksternt
objekt-ID, hentedato, fotograf, rettighedshaver, kreditlinje, beskrivelse,
alt-tekst, teknik, fysiske mål, datering) — data, ikke nye kolonner
(invariant 2+3).

RLS skærpes samtidig (MM-01): `entitet_offentlig('media', id)` returnerede
hidtil ubetinget `true`, så anon og medlemmer kunne læse fakta på
upublicerede medier. Funktionen kalder nu `media_rettigheder_ok(p_id)`, så
media-fakta følger samme publiceringsgate som mediet selv. Redaktionen er
uberørt (additivt `redaktion_read`-lag).

Redaktør-overlayet (`MediaDetaljeOverlay`) får feltgrupper for kilde, ophav,
rettigheder, beskrivelse, fysisk objekt og datering, med præudfyld fra
eksisterende fakta og proveniens-værn (kun ændrede felter gensendes ved
gem, så uændrede værdier ikke degraderes til "kilde mangler"). Læser-visningen
viser kreditlinjen altid når den er udfyldt (juridisk krav ved
CC-licenser, må ikke gemmes bag fold), kilde-URL som ægte link, historik-prosa
foldbar, og `alt_tekst` på thumbnail/lightbox.

Status: 733 web-tests grønne. DB-migrationen (vocab-seeds + RLS-skærpelse)
er IKKE kørt mod prod endnu — gated, kræver eksplicit go (se
`docs/superpowers/plans/2026-08-06-medie-metadata.md`, Task 7).

## Menneskegodkendte 1939-valg kan efterforankres fail-closed (2026-08-06)

Et uafhængigt review fandt en reel blindgyde: browserens fagligt godkendte
kandidatvalg kunne eksporteres, men ingen komponent producerede den
anchored-candidates-wrapper, som slutkonverteringen kræver. Den nye
`anchor_review_choices_1939.py` validerer eksport og kildehashes, genskaber det
valgte Calamari-span deterministisk, registrerer en invariant rå-OCR-bro hvor den
findes og ellers en eksplicit menneskelig approval. Den skriver samtidig en
omskrevet choice-eksport og komponerer de nye human-entries ind i et obligatorisk,
komplet source-bundet base-evidence-bundle; ingen `presentation:`-identitet bliver
accepteret direkte. Base-entries med blockers eller eksisterende positiv evidens
kan ikke erstattes, og global retained-auto + human-injektivitet valideres før output.

Real-data-replayet bevarede alle 25 ikke-audit menneskevalg uden fejlmatch: 13 fik
bytevalideret råbro og 12 approval alene; konverteringen gav 25 `accepteret`, de
fem `no_candidate_fits` forblev parkeret som `menneskeark`, og alle fem auditvalg
blev `audit_confirmed`. En eksporteret 35-valgs kladde kan desuden genindlejres
felt-for-felt i et nyt menneskeark. Task-5-outputtet `{decisions, audit_results}`
joines som `--review` mod composed evidence som `--evidence`. Resultatet er et
review-/filworkflow; der findes ingen approval-capable privat coverage-materializer,
og resultatet er derfor ikke coverage-materialiserings-, database-, loader- eller
deployment-GO.

## Ægte links i web-fladen + tydeligere "Samme person" (2026-08-01)

Al navigation i `web/` var `<div onClick>`/`<span onClick>`: ingen højreklik →
"åbn i nyt vindue", intet cmd/ctrl-klik, intet midterklik, ingen tastaturfokus.
Ny primitiv `web/src/Link.tsx` renderer et rigtigt `<a href>` og afgiver klikket
til browseren ved modifier-/ikke-venstreklik; ~14 komponenter konverteret i
begge flader (redaktørbord + følgesvend + forsidens feed). Venstreklik-adfærden
er uændret overalt — `onNavigate` bevarer hvert kaldesteds egen handler.

Redaktørens "Samme person"-rækker viser nu `KANONISK`/`ALIAS` + årstal, og
navnet linker til modpartens post (rå id — redaktøren arbejder i
skrive-id-rummet). Teksten beskriver **relationen**, ikke resultatet: et
samme_som-link medfører ikke altid en foldning, jf. dialogens "Foldes ikke
endnu"-advarsel.

To fejl fanget undervejs, begge reproduceret før rettelse:

- **Dobbelt-navigation ved cmd-klik.** Primitiven afgav klikket til browseren
  FØR `stopPropagation`, så et kort-`onClick` omkring ankeret navigerede den
  aktuelle fane samtidig med at browseren åbnede en ny.
- **Våben-feedkortet mistede sit layout.** Den delte klikbare flade satte
  `display: 'block'` som overstyring i stedet for default, så kortets eget
  `display: 'flex'` blev slået ihjel. Regressionstest tilføjet.

Fem eksisterende tests asserterede rollen `button` på elementer der nu er
ankre. Assertionerne er rettet, ikke komponenterne: at åbne en person ER
navigation, så rollen skal være `link` — og Space aktiverer ikke et anker
(kun klik og Enter).

Status: 672 web-tests + 403 core + 129 feed grønne, `tsc -b` ren, Playwright
grøn. Manuel browser-verifikation udestår. Review-spor:
`docs/reviews/aegte-links-plan-review-2026-08-01.md`.

## Trin B: fakta-efterudtrækket i prod — v3 live (2026-07-31, aften)

Anden replace samme dag (kæden er nu rutine): terra udtrak fakta af alle 546
narrativer (22 batches, 36 retries, tom retry-kø); Codex' kvote løb tør EFTER
udtrækket, så merge/validering blev kørt deterministisk af Claude
(efterudtraek_1939.py: fail-closed merge, 11 elementer saneret med log,
R7-span-gate, byte-verificeret genmerge). Dækning i prod: dåb 0→50, titel
266→309, død 344→352, vielser 478 familie-fakta, 713 supplerede
ægteskabsfelter (bl.a. partner-datoer), +17 nye ægtefælle-stubs; fødsel
362→370 — mønster-sweep bekræftede at resten reelt ikke har fødselsdato i
bogen (tidlige poster). Prod: 1804 personer. Alle redaktionelle invarianter
grønne — inkl. det NYE redaktionelle arbejde fra i aften (45 change_events
efter eftermiddagens load), som replace-kørslen beviste sig mod. Undervejs:
delt-workdir-race (anden session skiftede branch under terra-kørslen) →
stoppet, karantænet, genkørt rent med selektivt valideret batch-genbrug.
Rest: 157 ægteskabsfelt-konflikter rapporteret (redaktionelt), 78 uopløste
barn-opslag, Codex-kvote tom til 5/8 (rammer kun kommende store opgaver).

## FØRSTE ÆGTE PROD-REPLACE: 1939-v2-artefaktet live (2026-07-31)

Replay-kæden brugt skarpt mod prod for første gang — hele dagens kæde fra
GO-betingelser til levende data i én session:

- **Registeret gjort v2-klart** (godkendelse A-D): 43 om-nøglinger anvendt
  (18 auto + 25 fra sols kalibrerede evidenspas, alle tekst-anker-krydstjekkede),
  55 nye identiteter mintet, 7 indledningsoversigter afvist som dubletter af
  navngivne detaljeposter, 23 strukturelle fund står som bortfaldne (redaktionel
  prod-oprydning senere). Reconcile: 546 entydige / 0 tvetydige / 0 uforklarede.
- **Nyt artefakt `clean_1939_v2.json`** (build_1939_v2.py): 546 poster — struktur
  fra raw.txt (v2-segmenteringens 48 unummererede stamfædre/oversigter), narrativ
  fra Calamari hvor krydstjekket match findes (415/131), grønt manifest.
- **Ny-klassen i loaderen**: replay-designets fjerde udfald implementeret
  (registerkendte poster uden prod-person oprettes ad append-vejen) — fanget af
  gate-kæden, sol-reviewet GO.
- **Prod-kørslen**: 491 matchede (person-id'er bevaret), 55 nye oprettet,
  23 bortfaldne urørte, 289 unioner genbrugt med id-stabile stubs, 1 redaktionel
  familie fredet. Uafhængigt før/efter-snapshot mod prod: samme_som, change_events,
  stub-id'er, bookmarks alle byte-identiske. Prod: 1787 personer, 569
  1939-narrativer. 14 nye poster står bevidst uden navn (fail-closed frem for
  fabrikation — redaktionel opgave).
- Kendt rest: 78 uopløste barn-opslag (work/load-unresolved.csv), 4 nr_range-mål
  peger på bortfaldne, LOW-fund (nul-match-kant i replace-guard, fail-safe).

## Replay-GO-betingelser opfyldt: destruktiv --replace-test grøn + manifest-hul lukket (2026-07-31)

Begge GO-betingelser fra replay-designet er nu opfyldt (detaljer i
`docs/replay-source-scoped-design.md` §Kendte v1-begrænsninger):

- **Destruktiv integrationstest mod lokal prod-kopi:** frisk pg_dump af prod
  (1:1 verificeret på 8 nøgletal) → skarp `--replace` af DAA 1939: 514 matchede,
  person-id'er bevaret, alle redaktionelle invarianter identiske i et
  UAFHÆNGIGT md5-snapshot før/efter (ikke kun loaderens egen verifikation),
  0 genoplivede historik-id'er, fixpoint ved gentaget kørsel. R-suiten 543/543.
- **Sekvens-gulv-migrationen APPLIED TIL PROD** (efter lokal rehearsal på
  prod-kopien): fact-sekvens 6836→6837 (eneste kollision — præcis den
  id-genoplivningsklasse dry-run-fundet forudsagde), øvrige 24 tabeller no-op.
  Efterverificeret: alle 25 sekvenser står over gulvet
  (GREATEST(levende max, historik-max)), 0 brud.
- **Manifest-hullet lukket:** convert_1939 skriver nu gate-manifest (#126) i
  samme serialisering som clean-filen; eksisterende clean_1939.json fik ægte
  manifest efter bevist byte-identisk re-serialisering (515/515 rene) — gaten
  er GRØN uden `--force-gate`.
- **Sidegevinst:** #126-gaten havde brudt den miljøgatede DB-smoke-test
  (fixture uden manifest) — testen skriver nu ærligt manifest pr. loader-input.

**Næste:** (1) sekvens-gulv til prod, (2) trin 4-designrunde (familie-graf-
replace) — indtil da bevarer `--replace` bevidst loader-oprettede familie-kanter.

## Trin 4: familie-graf-replace bygget + destruktivt testet (2026-07-31, samme dag)

Replay-kædens sidste trin (designet + implementeret + testet i én session, commit
53fd921): `--replace` erstatter nu også familie-grafen. Kerneprincip: **strukturen
(family-id + stub-person-id) genbruges via match; indholdet erstattes.** Stubs kan
aldrig slettes/genoprettes — empirien viste at 209 af 296 gift-ind-stubs bærer
redaktionelle samme_som-links (tvær-udgave-ægtefælle-matchning); deres person-id'er
er redaktionel valuta. Union-match i fire faser (navn+ordinal → navn → ordinal →
token-overlap), alle tvetydigheder fail-closed. Fredede familier (change_event-spor)
springes helt over. Testen mod lokal prod-kopi fangede to ægte fund: Iven-casen
(I-72 gift med to forskellige kvinder der begge hed Margarethe Rantzau — ordinal
afgør) og en latent nøgle-bug (pmap record_key-nøglet, pass 2 slår linje-nøglet
op — ville knække ethvert UUID-nøglet artefakt, også i append). Uafhængigt
md5-snapshot 100 % identisk før/efter; 569/569 tests.

**Sol-review: GO efter tre adversarialer runder** (77d2aa2 → b2f47d5 → 50d58fc).
Runderne fandt og lukkede: familie-ejerskab uden positiv afgrænsning (nu
to-grenet: evidens fuldt citeret mod source ELLER positivt proveniens-bevis
pr. nul-evidens-medlem via fakta-citations, fail-closed for personer uden
proveniens — begge omgåelsesklasser bevist lukket med injicerede syntetiske
legacy-familier mod prod-kopien), fase 0-fixpoint-brud ved artefakt-
navnedubletter (nu up-front fail-closed, kørsel-uafhængigt) og NA-navne-hits
i R's subsetting. Slutfacit: 582/582 tests, ægte kørsel stabil 295 genbrugte
unioner / 19 parkeringer / 1 fredet / 0 bortfaldne. **Hele replay-kæden
(trin 1-4) er hermed komplet og GO'et — klar til ægte prod-replace når
re-ekstraktionen (v2-segmentering) foreligger.**

## Helhedsreview → slutark lukket → replay-kæden bygget (2026-07-30/31)

Én sammenhængende session fra review til fungerende replace-lag:

- **Helhedsreview** (multi-agent + Codex-krydstjek + prod-verifikation): redaktør-delen,
  data-import og missed opportunities — 34 fund, rapport i `docs/reviews/helhedsreview-
  redaktoer-import-muligheder-2026-07-30.md`, affødte issue #123-#133. Hoveddomme: begge
  tilgange gode nok; strukturel kernefejl = import/redaktion som to adskilte skriveveje.
- **Slutarket afgjort**: alle 22 manuelle om-nøglings-afgørelser (21 adresser + 2.11 som
  eneste ægte dublet af de 4 mistænkte — de 3 andre var delt-narrativ-fejlklip, afgjort
  via artefaktets navn/nr_label). Registeret opdateret: 514/514 aktive med trykt adresse;
  `data/identitet/1939.json` synket. 2.11-dubletten prod-håndteret (person 1213 slettet
  FK-ordnet; overleverens fejlklippede narrativ samtidig rettet).
- **Før-næste-load-gates** (PR #134, merged): reset tømmer nu versioneringshistorik (#124),
  navn≠ref-guard mod spøgelses-unioner (#125), gate-manifest binder valideringsresultat
  kryptografisk til artefaktet (#126). Closes #124 #125 #126.
- **IDENTITY-migrationen bygget + APPLIED TIL PROD** (PR #135): 25 tabeller GENERATED BY
  DEFAULT AS IDENTITY, 26 RPC'er omskrevet fra max(id)+1 til DEFAULT-inserts, alle fire
  loadere fik lås-kontrakt (kanonisk låseorden) + fail-closed sekvens-sync; to legacy-
  writers retired. Dual-review: sol NO-GO → 6 fund lukket → GO → applied + verificeret.
- **Replay-kædens trin 2+3**: dry-run-matchrapporten (`replace_dryrun.R`, kørt mod prod:
  514/515 entydige, 0 huller; tre designfund inkl. narrativ-undtagelsen) og `--replace`-
  mode i loaderen (person-scoped replace: bevarer person-id'er, positivt source-ejerskab,
  blokerende guards + invariant-efterverifikation). To sol-runder: 3 blockers + 2 rest-
  punkter alle lukket; hærdet dry-run fangede selv id-genoplivningsklassen (change_events
  over slettede rækker > levende max) → id-gulv = GREATEST(max, historik-max) overalt +
  ny sekvens-gulv-migrationssektion (endnu ikke applied til prod — bør køres snarest).
- Forudsætning "record_key-backfill" viste sig allerede opfyldt (prods 514 nøgler =
  registerets aktive book_post_ids 1:1 — det gamle 591/1733-tal talte stub-personer
  uden external_id-række).

## 1939-identitet: fra LLM-lokatorer til bogens trykte adresse — 445/515 i mål (2026-07-29/30)

To dages sammenhængende spor der gjorde 1939-identiteten produktionsklar på registersiden:

- **Identitetsregisteret hærdet** (#116): dublet-vagt i reconcile, perturbationsharness
  (kravet er nul FORKERTE match, ikke nul tvetydige), nabo-vagt mod sidedrift, og de 59
  side-driftede registerposter afstemt via record_key (515/0/0/0 efter).
- **Codex-review (4 fund) reconciled** : R9-lokatorgaten var aldrig koblet ind (nu i validate
  OG registeret selv), sidedrift-svagheden RETTET med nabo-vagten, loaderens manglende
  upsert/replay-lag markeret som åben blocker i planen, afstem-scriptets afgrænsning
  dokumenteret.
- **Kalibrering afgjort** (#117): terra som udtræksmodel (69 % flere embeder, stikprøve-
  verificeret ægte), prompt-hærdning kontrolkørt 5/5 mod afhugget-fejlen, R10-gate
  (er_omtale mod eget nummer-anker = review, aldrig auto-gravsætning).
- **lokal_id fra trykt struktur** (#118, #119): 2018-20 = `{linje}.{nr_label}`; 1939-profil
  i segment.py med bogens firleddede adresse (`IV.Ottende.II.6`) — grammatik empirisk
  kortlagt mod OCR-teksten (af-spærrede overskrifter "O ttende S læ gtled ,", blok-linje-
  headere, pegepind-vs-header-skel via centrering). Målt: 505/505/505 unikke, delt-narrativ-
  problemet elimineret (4.814 vs 80.192 tegn), og Cay Friedrich-oversigten (den gamle
  dublet-kilde) afvises nu ved kilden.
- **Registeret om-nøglet** (#120, #121): tekst-anker-bro + l↔1-normalisering + id-afkodning
  kalibreret mod kendt facit — 445/515 flyttet automatisk, alle nummer-krydstjekkede,
  0 tvetydige. Pegepind-krydstjek i kvalitetsrapporten fandt 14 ægte OCR-tabte afsnits-
  romaner (bogens dobbeltbogføring som facitliste).
- **Udestår:** 22 ægte menneskeafgørelser (slutark i work-mappen), 48 strukturelt parkerede
  stamfædre/oversigtsposter (afventer v2-segmentering af unummererede), og loaderens
  upsert/replay-lag — den sidste store blocker før re-ekstraktion kan føre til load.

## Personers OCR-kvalitetsark — røgtest udført, arket i drift (2026-07-29)

Den manuelle redaktør-røgtest fra runbookens §4 er kørt af brugeren i browseren og meldt OK —
inklusive prøvekørsels-punktet, der bekræfter at panelet nægter at gemme mens dry-run er slået til.
`smoke_verified` er dermed opnået, og kvalitetsarket er i fuld drift for de poster der har et
importanker.

**Rækkevidde målt samme dag:** 591 af 1733 personer (34 %) er redigerbare — alle DAA 2018-20's
hovedposter, 100 %. De øvrige 1142 er blokeret af samme rod: `red_ret_ocr_felt` forankrer på
`(import_key, record_key)`, og de mangler det ene eller begge. To planer udestår, ingen af dem
skrevet: 1939-identitet (811 personer, blokeret af en åben beslutning) og ægtefælle-forankring
(627 personer, ikke blokeret af noget). De overlapper på de 296 1939-ægtefæller, som rammes af
begge.

## 1939: Den fyenske Linje fik egen linje og omstridt slægtskab (2026-07-29)

De 26 personer i DAA 1939s linje VI kan aldrig matches mod DAA 2018-20, fordi
2018-20-forfatteren bevidst udelod dem. Bogen selv er dog mere forbeholden end
"de hører ikke til": 1939 skriver at de førte Reventlowernes murtinde men et
**helt andet hjelmtegn**, at efterkommerne *"lejlighedsvis har ført
Reventlow-Navnet"* og regnede sig til slægten, *"men om den fyenske Linjes
Samhørighed med de holstenske og meklenborgske Reventlower kan intet oplyses."*
Begge udgaver er altså enige om at slægtskabet er udokumenteret; de er uenige om
hvad man så gør.

Modelleret som to adskilte påstande frem for én:

- **Navnet hævdes.** Linjen får `parent_lineage_id=6` (slægtsroden) og arver
  dermed slægtsnavnet — "Henrik Jensen" vises nu som *Henrik Jensen Reventlow*,
  som bogen ville skrive ham. `slaegtsnavn=NULL` blev forkastet: det ville
  benægte et dokumenteret faktum for at udtrykke tvivl om et andet.
- **Slægtskabet hævdes ikke.** En `gren_af`-relation (lineage 7 → 6) med
  `konfidens='omstridt'` bærer selve afstamningspåstanden, med assertions og
  citationer fra **begge** udgaver og en `conclusion` med status `omstridt`.
  Skemaet foreskriver netop dette: *"parent_lineage_id er den hurtige FK;
  'gren_af'-relationen bærer evidens/konfidens."*

Udført i `change_set` 788: ny `lineage` 7 (source 3, kode VI), `linje='VI'` på de
26 (person 1437–1462), rolle `gren_af` tilføjet vokabularet. Verificeret positivt
før kørsel: artefaktets 26 `Lfyn`-poster står i nøjagtig samme navnerækkefølge som
DB'ens nr 514–539. Rehearset i rullet-tilbage transaktion. Ingen sideeffekt: de
øvrige 489 1939-personer og alle 2018-20-personer er urørte, slægtsnavns-
karantænen er fortsat tom.

**Faldgruber fundet undervejs (vigtige for det videre arbejde):**

1. **IV og V er byttet om mellem udgaverne.** 1939 IV = "Den danske grevelige
   Linje af 1673" = 2018-20 **V**; 1939 V = "grevelige Linje af 1767" = 2018-20
   **IV**. Enhver logik der bærer et romertal på tværs af udgaver matcher stille
   to forkerte linjer. `matchUdgaver` slår heldigvis op på `${source_id}:${kode}`.
2. **1939 er uenig med sig selv:** indledningen nummererer den fyenske som IV,
   brødteksten som VI.
3. **"A. Den holstenske Linje"** i den rensede OCR er en fejllæsning; `raw.txt`
   har "I".

**Matcher-filteret er med.** `MatchLineageRow` har fået `udenforMatchning`, og
`buildMatchPersoner` sætter et tilsvarende flag pr. person. `SammenlignUdgaver`
springer dem over **før** frames bygges, så de hverken bliver arbejdsemne eller
kandidat — 2018-20 er nyeste udgave, så uden filteret lå de 26 i *kandidat*-puljen
og kunne foreslås som match for 2018-20-personer. Flaget udledes i `fetchLineages`
fra `gren_af`-relationen, så reglen står ét sted og `lineage.status` (fri tekst)
aldrig parses. Fejler relations-opslaget, undtages ingen: at vise for mange
kandidater er en irritation, at skjule en ægte kandidat er et datatab. Testet på
begge sider — også at flaget ikke smitter mellem udgaver med samme linjekode
(opslag på `(source_id, kode)`, ikke kode alene; jf. IV/V-ombytningen).

**Udestår også:** de øvrige 489 1939-personer har fortsat den syntetiske
`linje='1939'`. Strukturen findes allerede i loaderens input (`_ctx.linje`,
`lokal_id`-præfikser som `Lfyn`/`LGallentin`/`HL`), men `_ctx.linje` er
LLM-udledt og hullet (222 poster uden værdi, mange "udledt"/"ukendt"), så en fuld
omlægning er sit eget stykke arbejde — og konverteren skal med, ellers ruller en
genindlæsning ændringen tilbage.

## 2018-20: bogens apparat bløt ind i sidste posts narrativ (2026-07-29)

Brugeren bemærkede at person 391 — en nulevende, født 2001 — havde et narrativ
med indhold fra 1700-tallet. Det var ikke en anden persons biografi, men bogens
**portrætfortegnelse**: én korrekt sætning efterfulgt af billedtekster med 21
krydsreferencer.

**Rodårsag:** IV-94 er den sidste post i linje IV. Segmenteringen skar "fra
overskrift til sektionens slut" og slugte alt efterstillet apparat. Systematisk,
ikke tilfældigt: fire af fem linjers sidste post var ramt — I-133 (person 39),
II-35 (165) og III-129 (205) havde slugt linjetillægget *"Til denne linje hørte
formentlig…"*, III-129 og IV-94 (391) desuden portrætfortegnelsen. V-200 var ren.
Ingen andre af de 591 narrativer havde mønstret, målt på tre uafhængige signaler
(tillægsmarkør, billedtekst-ord, krydsreference-tæthed).

**Kontrolleret at intet manglede den modsatte vej:** alle 591 personer har et
narrativ, og de 71 helt korte er ægte ("Barn.", "Cord – † ung.", "Gottschalk von
Reventlow, se II. Linjen Gallentin."), også de 7 hvor en kort post følger en meget
lang forgænger. Indblødningen er ensidig — sidste post sluger efterstillet stof,
men stjæler ikke fra naboen.

**Ingen persondatalækage:** anon får 0 rækker for den nulevendes narrativ; RLS-
gaten holdt hele tiden. Verificeret.

Trimmet i `change_set` 787 inde i et `begin_change_set`, så `log_change`-triggeren
fangede før-billedet: **12.469 tegn bevaret i `change_event.foer`**, 1.014 tegn
tilbage. Fuldt fortrydbart — teksten er ikke destrueret. Rehearset mod prod i en
rullet-tilbage transaktion først; alle fire trimninger ender på en afsluttet
sætning. Efter: 0 tillæg, 0 billedord, max krydsreferencer i hele korpus = 0.

**Udestår:** selve segmenteringen er ikke rettet, så en genekstraktion af 2018-20
ville genindføre fejlen. Det slugte linjetillæg er reelt genealogisk indhold
(uplacerede personer, fx *"Hinrich von Reventlow – † før 1390"*) og hører hjemme
på linjeniveau — `narrative.subjekt_type='slaegt'` findes allerede og bruges. Begge
dele er separate opgaver.

## 1939-dubletter: 23 af 35 kandidater slettet (2026-07-28)

Oprydning efter dubletdiagnosen. Brugeren gennemgik kandidatlisten mod bogens sider og slettede
23 poster via redaktørfladens `red_slet_person` — 6 først, derefter 17.

**Resultat:** 1756 → 1733 personer, 1939-hovedposter 538 → 515, 2018-20 urørt på 591. Læser-lagets
huller i forældrelink faldt fra 62 til 44 (11,5 % → 8,5 % af 1939-posterne). Integritet efter
sletningerne: **0 forældreløse rækker** i `person_external_id`, `family_member`, `relation` (begge
retninger), `narrative` og `fact` — den FK-ordnede kaskade i RPC'en holdt.

**Korrektion til diagnosen.** Rapporten konkluderede at dubletterne *producerede* de konflikter der
satte `samme_som`-grupper i karantæne, og at sletningen ville frigøre dem. Det holdt ikke: antallet
af karantænerede grupper står uændret på **238**. De 12 blokerede poster forsvandt fordi de selv
blev slettet, ikke fordi blokeringen blev ophævet. Sammenfaldet (12 af 12 stod på slettelisten) var
ægte; årsagsretningen var en tilføjelse. Karantænerne skyldes uenighed om forældre mellem *rigtige*
personer og kræver fortsat manuelt matcharbejde.

**Sidetal tilføjet til kandidatlisten undervejs** — alle 538 1939-hovedposter har et sidetal i
citationen, så hvert par kan slås op uden at lede. De 35 par fordeler sig på 32 sider (s. 504-581).

**10 par udestår bevidst:** `nr` 68 (eneste bro til 2018-20 — matchet skal flyttes først), `nr` 54
og `nr` 102 (familiekanter skal flyttes; 102 er desuden matchet til en anden 2018-20-person end sin
makker og er ikke en bekræftet dublet), `nr` 44/94 (begge er prosaomtaler, klasse AA) og fem par med
kun én detektor.

**Sidebemærkning:** sletningerne kunne ikke udføres fra en service-forbindelse — `current_rolle()`
giver `medlem` uden en indlogget bruger, og både `red_slet_person` og dens preview kræver
`redaktion`. Rå `DELETE` blev fravalgt: den ville omgå `change_set` (ingen fortrydelse) og den
FK-ordnede kaskade. RLS-hærdningen virkede efter hensigten.

## Slægts-rod i lineage — LIVE i prod, begge trin (2026-07-28)

Forberedelse til at andre slægter end Reventlow kan bo i samme base. Alle fem linjer havde
`parent_lineage_id = NULL`, så intet knudepunkt repræsenterede selve slægten: slægtsnavnet stod
gentaget på fem rækker, og en ny slægts linjer ville lægge sig sideordnet uden noget der bandt dem
sammen. Nu findes én rod pr. slægt (`source_id`/`kode` = NULL, så den aldrig får medlemmer og er
usynlig i app'ens linje-liste), og linjerne hænger under den.

**Delt i to trin efter deploy-rækkefølge — begge nu kørt.** Trin 1 (rod + repegning + dublet-guard)
er forward-kompatibel med *begge* web-versioner, fordi grenene beholdt deres eget `slaegtsnavn`;
den kunne derfor køres uden at vente på app-deployet. Trin 2 (rydning af grenenes `slaegtsnavn`)
blev kørt efter at PR #109 var merget og deployet, fordi den daværende web læste feltet råt og
ellers ville have vist præsenslistens overskrift tom. Opdelingen var ikke formalitet: den fjernede
tidsvinduet helt frem for at gøre det kort.

Slægtsnavnet bor herefter kun på roden (id 6); alle fem grene har `slaegtsnavn = NULL` og udleder
`Reventlow` via `lineage_effective_slaegtsnavn()`.

**Verificeret mod prod efter hvert trin:** korpus-diff på `visning_efternavn`/`visning_fuldt_navn`
for alle 1756 personer viser 0 forskelle mod før-tilstanden, `slaegtsnavn_karantaene` står på 0, alle 5
grene udleder fortsat `Reventlow`, roden har 0 medlemmer, og `get_advisors(security)` er uændret på
133 lints uden nye lineage-relaterede. Frisk backup taget før kørslen
(`daa-prod-pre-slaegtsrod-20260728-141840.dump`, uden for git).

**Fejlrettet antagelse undervejs.** `narrative.subjekt_type='slaegt'` med `subjekt_id=1` ligner en
fremmednøgle til `lineage` 1 og blev i første omgang beskrevet som "slægtsteksten parkeret på linje
I". Det er forkert: id'et er en *sentinel* for hele slægten, båret som konstant i begge apper
(`SLAEGT_SUBJEKT_ID`), og `fetchAbout` filtrerer slet ikke på det. En planlagt flytning til roden
ville have koblet redaktørfladens skrivesti fra læsestien. Flytningen er ude af migrationen, og en
`db-verify`-assert fastholder det. `docs/reviews/flerslaegt-parathed-2026-07-28.md` er rettet.

**Ikke løst her:** to slægter i samme årbog har begge en "Linje I", og `lineage UNIQUE
(source_id, kode)` afviser den anden — bekræftet empirisk. Det er B1 i flerslægts-vurderingen og
kræver en beslutning om nøglerummet før næste slægt loades.

## Kilde vist for de 627 personer uden bog-nummer (2026-07-28)

Brugerfund: mange personer stod uden kildeangivelse i følgesvenden (`Ada Jessie Howard Grøn`).
Årsagen var visning, ikke data. `sourcesBy` bygges alene af `person_external_id`, som kun findes
for personer bogen gav et eget opslag; de 627 ægtefæller har intet bog-nummer, så opslaget var tomt
og `DetailPanel` skjulte hele "Kilde i Aarbogen"-blokken. 335 af dem er offentligt synlige.

Proveniensen fandtes hele tiden — invariant 1 kræver at hvert faktum er kildebundet, så alle 1756
personer har `fact → assertion → citation → source`. Målt mod prod har alle 627 **præcis én** kilde
(0 flertydige) og 296 endda sidetal. Rollefordelingen blev derfor: bog-nummeret (`Linje II, nr. 4`)
er den mest præcise reference og vinder hvor den findes, mens citationen er reglen der dækker alle.
Ada konkret: id 841 → `DAA 2018-20`, id 1690 → `DAA 1939, s. 578` — matchet til hinanden, men da
ingen af siderne har bog-nummer kunne `collapseSameAs` heller ikke redde det.

Reglen ligger i `@daa/core` (`kildeProveniens.ts`), så web og mobil deler formatering. Wiringen er
bevidst forskellig: web henter først når personen mangler bog-nummer (de ~1129 hovedposter betaler
ikke for opslag de ikke bruger), mobil bulk-henter kun `navn`-faktaet — det ene faktum hver person
beviseligt har. `citationRowsTilProveniens` findes fordi PostgREST returnerer et *objekt* for en
til-én-relation mens de genererede typer siger *array*; web slap afsted med en cast, mobil gjorde
ikke. Anon-adgang til `citation`/`assertion`/`fact` + det nestede source-join blev verificeret
empirisk mod REST-API'et, ikke udledt af at en service-key-forespørgsel lykkedes.

Ingen DB-ændringer. Merget som PR #105, CI grøn på alle 6 jobs (mobil-jobbet kørte de 2 suiter der
fejler lokalt pga. manglende `@testing-library/react-native` i `node_modules` — install-drift, ikke
kode). **Udestår:** visuel verifikation af blokken i den deployede web.

**Målt undervejs, ikke rettet:**

- **Køn mangler på 625 personer** — samme population (329 + 296 ægtefæller; hovedposter mangler 0).
  Testet kontrafaktisk om det bremser tværudgave-matchningen: 625 af 629 kan udledes af partnerens
  køn, men effekten er negativ (`auto` 267 → 258, `review` 3639 → 4003). `evidensNormaliseret`
  normaliserer allerede over de signaler der kan vurderes, så et manglende køn koster intet dér.
  Det er en visnings-/korrekthedssag, ikke en matchning-blokering, og kræver skrivning via
  `red_set_koen`.
- **Ægtefælle-dubletter behøver ikke egen liste.** `udledKilderForAegtefaeller` (#90) virker 100 %
  (627/627 får udgave), og med fladens egen config (`evidensNormaliseret: true`) har 394 af de 431
  umatchede ægtefæller mindst én kandidat. Arbejdet kan gøres i `SammenlignUdgaver` som det er.

## Kvalitetsark: navn_mangler-flaget var falsk på 1169 af 1757 rækker (2026-07-28)

Brugeren spurgte hvorfor `navn_mangler` stod ved alle. Måling: **1169 flag, nul
ægte** — hver eneste flaget række viste et navn korrekt. QA-koden målte på
`candidate_count`/`felt_vaerdi`, som begge er anker-gatede, mens selve
navnevisningen (siden `4d041bf`) falder tilbage til den afklarede evidens
uafhængigt af anker. Koden flagede altså reelt "kan ikke rettes", ikke "har intet
navn" — samme sammenblanding som den tomme navnekolonne, bare flyttet fra
visningen til QA-laget. Redigerbarhed udtrykkes allerede af
`kan_rettes`/`blokarsager`. Rettet til at måle præcis den værdi griddet viser.

Fundet undervejs: griddet returnerede **to rækker for samme fysiske person** når
personen står midt i en `samme_som`-kæde (både alias og kanonisk) — rækkerne
adskiller sig på `samme_som_status` og overlevede derfor `GROUP BY`'et. Præcis én
person i prod (826) stod sådan. Nu `DISTINCT ON` med alias-forrang. Kæden kan
opstå fordi `enforce_samme_som_invariants()` kun er `BEFORE INSERT` og G4 kun
tjekker `NEW.subjekt`: indsættes den inderste kant først, slipper den ydre
igennem. **Trigger-hullet er ikke lukket** — griddet er gjort robust over for
tilstanden, men invarianten kan stadig omgås via indsættelsesrækkefølge.

Verificeret mod en lokal kopi af prods rigtige data før udrulning (1169 → 0,
navn vises på alle, `kan_rettes` uændret på 588), derefter anvendt mod prod som
ren `CREATE OR REPLACE FUNCTION` — ingen data rørt, ingen DDL, `get_advisors`
uændret på 133 lints. Prod efter: 1756 rækker for 1756 personer (dubletten væk),
0 `navn_mangler`. Rollback-artefakt med den forrige definition gemt før
udrulning.

Ikke løst her: de **627 gift-ind-ægtefæller** uden egen bogpost er fortsat
ikke-redigerbare (`ingen_importanker`). Planen behandlede dem som et sjældent
legacy-hjørne; de er 36% af korpus. Kræver egen plan — nøglen ville være
forælderens `record_key` + indeks i `aegteskaber`, og `linje` SKAL være NULL,
da `regen_person_visning()` ellers ville påhæfte slægtsnavnet til indgifte
ægtefæller.

## Personers OCR-kvalitetsark — record_key-backfill for DAA 2018-20 + web-status rettet (2026-07-28)

Genindlæsning med `--reset --import-key=` blev overvejet for at gøre eksisterende
personer redigerbare, men forkastet: loaderens `has_reset_blocking_editorial_
changes()`-spærre blokerer på enhver `red_%`-operation undtagen `red_ret_ocr_felt`,
og prods `change_set` har 482 `red_samme_som`-links plus dusinvis andre
redaktørrettelser den ville have ramt. I stedet blev en smal, kun-tilføjende
`UPDATE`-backfill kørt: 591 eksisterende DAA 2018-20-personer fik
`source.import_key='daa:2018-20'` og `person_external_id.record_key` stemplet,
udledt af at filnavnene i `data/extracted-2026-06-18/*.json` selv ER `record_key`.
To `(linje,nr)`-kollisioner (basenr 15 og 41) løst entydigt ved navnematch. Rehearsed
mod en lokal kopi af prods rigtige data før kørsel; frisk krypteret backup taget
(`daa-prod-pre-record-key-backfill-20260728-074303.dump.gpg`). Resultat mod ægte
prod: 588/591 personer nu redigerbare, 0 `record_key_mangler` tilbage,
`get_advisors(security)` uændret på 133 lints. 1939-udgaven har stadig ingen stabil
identitet.

Samtidig rettet: forrige changelog-entry og runbook sagde web-laget ikke var
deployet — brugeren havde i mellemtiden selv merget PR #103 til `main` via GitHub,
og Vercel havde allerede auto-deployet featuren til prod. `web_deployed` er derfor
opnået siden 2026-07-27; kun den manuelle redaktør-røgtest udestår.

## Personers OCR-kvalitetsark — DB LIVE i prod, web IKKE deployet (2026-07-27)

Databasen er migreret mod prod (`xjnvdhajfyrcytatnzos`): `import_korrektion`-journal,
stabile importnøgler og RPC'erne `red_person_grid`/`red_ret_ocr_felt`/`red_ocr_historik`
er live. Krypteret backup taget og gendannelses-verificeret først. Verificeret mod
rigtig prod efter migration: `anon` afvist (ægte REST-kald, 401), `get_advisors`-delta
+3 (kun de kendte SECURITY DEFINER-mønstre), data uændret (1756 personer). Brugeren
valgte at migrere databasen nu og genindlæse en udgave med `--import-key=` separat
senere — eksisterende personer er derfor synlige i griddet men endnu ikke redigerbare.

Web-laget er **ikke** deployet endnu. Se `docs/runbooks/person-ocr-kvalitetsark.md` §5.1
for detaljer, inklusive en hændelse under første migrationsforsøg (en manuel
gentastning af SQL introducerede en kolonnenavne-fejl; transaktionen rullede atomisk
tilbage uden nogen skade, og genforsøget med filens eksakte indhold lykkedes).

## Personers OCR-kvalitetsark — kodeklar, IKKE deployet (2026-07-26)

Redaktør-værktøj der viser hver importeret person som én række i et regneark-lignende
grid, med et sidepanel hvor navn, fødsel, død og køn kan rettes. En OCR-rettelse er en
rettelse af *samme* importerede kildeudsagn: `fact.id`, `assertion.id`, citation og
konklusion bevares, så oprydning aldrig bliver til en ny historisk påstand. Rettelser
lever i en holdbar journal uden for loaderens reset-liste og genafspilles efter en
genindlæsning via stabile `(import_key, record_key)`-nøgler; en ændret OCR-kontekst
markerer rettelsen `stale`, så den ikke genafspilles blindt.

Fail-closed hele vejen: RPC'en afviser med mindre personen har præcis ét stabilt
importanker og feltet peger på præcis én valgt, citeret påstand. Personer uden anker
forbliver **læsbare, men låste**. Anonyme og medlemmer afvises server-side.

**Status: kodeklar og lokalt DB-verificeret — produktionsdatabasen er ikke rørt, intet
er deployet, intet pushet.** Drift, gates og udestående manuel røgtest:
`docs/runbooks/person-ocr-kvalitetsark.md`.

Verificeret: R 475, core 358, feed 120, web 613, mobil 399, validate.py 130, loader-
DB-smoke 124 — alle grønne. Frisk base + opgraderingssti på PostgreSQL 17.10 med
idempotente migrationer (kørt to gange); rolleadgang efterprøvet med efterlignede
JWT-claims. Skala-måling ved 2001 personer: `red_person_grid()` 285–301 ms, 3.470 kB.

Undervejs fandt og lukkede arbejdet fire fejl, som testene ikke selv fangede: loaderen
korrumperede stille en buffer-kolonne, fordi `jsonlite` læser JSON-null som `NULL` men
skriver det tilbage som `{}`; `red_person_grid()` manglede `ORDER BY`, så pagineret
læsning var uden ordensgaranti; en bar ISO-dato blev tolket som helår i *begge*
parsere — uskadeligt i udtrækket, men tavst tab af præcision når en redaktør selv
taster datoen (0 af 1322 `date_raw` i korpus var berørt, så rettelsen var inert); og en
rehearsal mod prods **rigtige** data (ikke syntetisk fixture) afslørede at griddets
navn/fødsel/død-visning delte anker-gate med redigerbarheden, så alle 1757 eksisterende
personer viste tomme felter. Rettet ved at falde tilbage til den allerede afklarede
evidens, uafhængigt af redigerbarhed — 0/1757 personer har nu tomt navn (var 1757 før).

## 2018-20: 18 narrativer med slaegtled-/kuld-bleed rettet — LIVE i prod (2026-07-27)

2018-20-auditen fandt 14 poster med en trailing sektionsoverskrift
(`Sjette (nittende) slægtled`) hængende på halen af forrige posts narrativ. Videre
undersøgelse fandt 4 mere alvorlige tilfælde hvor både overskriften OG den
efterfølgende kuld-markør (`Overkammerherre Detlef lensgreve de Reventlous børn`)
bløder ind — 18 poster i alt.

**Rodårsagen var allerede rettet i koden — bare ikke genindlæst.** Sporet til
`work/raw_full.txt`: `segment.py`'s `SLGT_RE` matcher en bar slaegtled-header
korrekt, når den (som her) står alene på sin egen linje. Kørt frisk mod
`raw_full.txt` gav det nuværende `segment.py` alle 18 poster ren tekst, byte-
identisk med de øvrige 573 upåvirkede poster. Bug'en sad kun i det allerede
indlæste artefakt (`work/clean_full.json`, stale ift. dagens segmenterer) —
`segment.py` er ikke ændret. To regressionstests låser adfærden fast.

`R/update-2018-narratives.R` — målrettet patch af 18 navngivne poster, nøglet på
`(linje, nr)` fordi det ikke er globalt unikt i denne udgave (I-15a/b/c deler
basenr). Bruger `jsonb_to_recordset()` af ét JSON-parameter, da hverken
`CREATE TEMP TABLE` (DDL, fejler i dry-runs READ ONLY-transaktion) eller et
array-parameter blandet med et skalar-parameter (RPostgres fortolker det som
batch-udførsel) virkede.

**Anvendt mod prod:** `change_set=532`, 18 rækker, 18 audit-events. Verificeret
efter apply — ingen bar `slægtled`-hale tilbage, legitime krydshenvisninger
(`Andet (femtende) slægtled, nr. 2‑9.`) intakte. (#98)

## Tværudgave-matchning gjort mulig for ægtefæller (2026-07-26)

Fulgte af 1939-auditen nedenfor: auditen fandt ~51 % mangelfulde forældrelink og pegede
på re-ekstraktion (trin 2). Analysen viste at det var forkert diagnose — og hver rettelse
afdækkede den næste.

**1. Hullet var allerede halvt lukket.** `collapseSameAs` omskriver `parentChild`-kanter til
kanoniske id'er, så en matchet 1939-person arver sin 2018-20-modparts forældre i visningen.
Data-lag 253/539 mangelfulde, læser-lag 86/539. Matcharbejdet lukkede ~68 % gratis.
(`docs/reviews/kryds-udgave-udfyldning-scoping-2026-07-26.md`)

**2. 287 grupper var i karantæne — ikke af uenighed.** Målt ved at køre den rigtige
`collapseSameAs` mod et prod-dump; to SQL-genimplementeringer gav upålidelige tal. Bøgerne
er enige: 1939 skriver `Bertram + Christine Rantzau` hvor 2018-20 skriver
`Bartram + Christina von Rantzau`. Forældrene var bare ikke matchet til hinanden.

**3. De kunne ikke matches.** Ægtefæller har sjældent eget bog-nummer, og `sourceIds` blev
udledt alene af `person_external_id` — uden nummer hørte de til ingen udgave og indgik aldrig
i kandidatparrene. 0 af 73 forældrepar kunne gennemføres. `udledKilderForAegtefaeller` lader
dem arve udgaven fra deres partner, entydigt eller slet ikke: 627 ægtefæller (296+331),
0 flertydige, forældrepar 0 → 77. Lukkede samtidig at 1939-ægtefæller lå i B-siden og kunne
foreslås som match for deres egen udgave. (#90)

**4. Brugerfund: "formodet nye" var en blindgyde.** 393 poster, hvoraf 392 havde en kandidat
der var fundet og smidt væk (`tier === 'none'`), og 125 havde eksakt samme navn i 2018-20.
Årsagen strukturel: overlap tæller kun når begge sider har en dato, så en person uden årstal
har loft = `wName + wSex` = præcis review-tærsklen. `svageKandidater` bevarer dem nu med
Sammenlign/Bekræft — uden for status og fremdrift, så tællerne er uændrede. (#93)

**5. Modellen rettet.** `scorePairEvidens` normaliserer over de signaler der faktisk kunne
vurderes; ukendt årstal ryger ud af nævneren, kendt-men-uenigt bliver stående. Personer med
mindst ét forslag: **442 → 815 af 835**. Første måling uden spærre viste faren konkret —
152 par uden ét eneste årstal blev markeret "stærke" (`Otto ↔ Otto`) — så `assignTiers`
kapper navn-alene til "gennemsyn": 152 → 0. (#95 opt-in, #96 slået til)

**Værktøj:** `tools/foraeldrematch/` — `status.ts` (karantænetal), `byg-liste.ts`
(arbejdsliste, 73 forældrepar sorteret efter hvor mange børn de frigiver), `effekt.ts`,
`normaliseret.ts`. Alle read-only, og de kører den rigtige kode frem for at gengive reglerne.

**Udestår:** matcharbejdet selv (73 forældrepar → 287 karantænerede par frigives).
Arbejdslisten ligger gitignoreret i `work/`.

**CI:** R-jobbet tog 42 minutter fordi `duckdb` blev kompileret fra kilde ved hver kørsel.
Cache på `R_LIBS_USER` + idempotent install: **42m10s → 45s**, hele CI under 2 minutter. (#92)

## 1939-kvalitetsvurdering + re-segmentering — LIVE i prod (2026-07-26)

Brugerspørgsmål: er 1939-indlæsningen for dårlig, og kan matcharbejdet reddes?
Svaret er kvantificeret i to rapporter under `docs/reviews/`.

**Måling.** Strukturelt: 1939 har 355/539 hovedposter med forældrelink mod 2018-20's 566/591,
og 3,76 fakta pr. person mod 5,33. Datoparsingen er derimod *bedre* (7,8 % uparsede mod 16,4 %),
og tegn-niveau-OCR var allerede rettet af Calamari-patchen. Restdefekten var **segmentering**:
280 af 539 narrativer (51,9 %) havde mindst én snitfejl.

**Stikprøve-audit (N=25, bedømt mod renderede PDF-sider, ikke mod OCR-teksten).**
~54 % af posterne har ≥1 materiel fejl — men **0 forkerte navne, 0 forkerte fødsels-/dødsår,
0 forkerte ægtefæller**. Fejlene er udeladelser og fejlklip, ikke forkerte påstande. Fund der
ikke kan ses i SQL: mor mangler bag et gyldigt far-link i ~12 % (den strukturelle måling
undervurderer altså problemet), inkonsistent linking inden for samme kuld, og en OCR-fejl i en
kildehenvisning (`Aarb. LVIII` for `XLVIII`).

**Re-segmentering (trin 1) anvendt mod prod.** Fem rettelser i `segment_1939.py`:
kuld-overskrifter som snitgrænse, bar romertalslinje, bindestreg-normalisering (orddelte navne
ved linjeskift), `_orig_nr`-præference (`nr` er en global tæller i 1939-artefaktet, så
nummer-ankeret var reelt dødt) og snap-back til postens egen nummerlinje. Defekt-union
**280 → 159**; pipelinens kvalitetsgate gik fra rød til grøn (R1/R6-proxy 88,8 % → 91,2 %) —
artefaktet der lå i prod var accepteret med fejlende gate. I stikprøven: 16 defekte narrativer
→ 5, heraf 11 nu ordret identiske med bogen.

**Anvendt:** `R/update-1939-narratives.R` mod `xjnvdhajfyrcytatnzos`, 216 rækker,
`change_set=493`, 216 audit-events. Kun `narrative.tekst` — 0 sideændringer, ingen personer,
ingen `nr`, ingen links. De 429 samme_som-matchpar er urørte og desuden sikkerhedskopieret med
navn + rå datoer i `work_1939_stamtavle/match_backup_2026-07-26.json`. Prod-fingeraftryk
verificeret identisk med artefaktet efter apply.

**Trukket tilbage undervejs:** en sjette rettelse (indsnævring af fallback-blokke) målte som en
forbedring, men stikprøven viste at den bandt post 276/277 til en anden families børn med samme
fornavne. `_orig_nr` er ikke pålideligt scopet til postens egen blok. Reverteret før apply.

**Udestår:** 12 af de 216 ændrede rækker er allerede publiceret (`staged=false`) og slog derfor
igennem i den offentlige visning med det samme. Trin 2 (re-ekstraktion af fakta mod de ~51 %
mangelfulde forældrelinks) kræver ny loader-kode og er ikke startet. 2018-20 er ikke auditeret
med samme harness.

## Mediehåndtering fase 4 — LIVE i prod (2026-07-22)

Fase 4 er deployet til produktion samme dag som lokal verifikation (PR #75 merget):
krypteret backup taget først; migrationsblokken `mediehaandtering_fase4_identitet`
anvendt; alle fire fase-4-verify-blokke kørt og bestået direkte mod prod (impersoneret
den reelle redaktion-profil, ingen testdata-rester bagefter); `get_advisors(security)`
viste kun de allerede kendte SECURITY DEFINER-mønstre (samme som alle øvrige `red_*`-
funktioner) — ingen nye fund. Web app-deployet via Vercel. Redaktøren gennemførte en
fuld røgtest af alle tre flows (erstat fil, slet permanent, sæt/fjern portræt) med
succes. Første `R/media-janitor.R`-kørsel (rapport-only) efter et reelt erstat-forløb
bekræftede at de tre gamle byte-objekter (large/medium/thumb) korrekt identificeres som
forældreløse (kategori b) med anbefalingen "afvent frist" — ingen `--slet` kørt.

## Præsensliste: patrilineær efterkommer-tilhør rettet mod rigtig prod-data (2026-07-23)

Brugerfund ved faktisk brug af den nye præsensliste: et barn af to blod-Reventlow-forældre
(to grene der giftede sig sammen) blev vist under BEGGE forældres efterkommer-liste — men DAA
er patrilineær, så barnet hører kun til under faderen. Rettet i to omgange (task-reviewer fangede
en reel regression i første forsøg — se `docs/decisions.md` for det fulde forløb): ny
`patrilinealForaelder`-hjælper i `packages/core/src/presensListe.ts`, og `blodOgGiftInd`
(klatrings-heuristikken) gjort konsekvent med den samme regel i stedet for sin egen separate
rigdoms-heuristik. Superseder `krydsReference`-mekanismen for "barn af to kendte forældre" —
ambiguiteten løses nu før krydshenvisning bliver relevant. Core-suite: 301/301. Ingen
prod-datarettelse nødvendig (kun algoritmen var forkert).

## Præsensliste-visning v1 — implementeret på feature-branch (2026-07-22)

Beregnet, anker-baseret præsensliste-læsevisning (web + mobil), designet og planlagt
samme dag (`docs/superpowers/specs/2026-07-22-praesensliste-visning-design.md` +
`docs/superpowers/plans/2026-07-22-praesensliste-visning.md`), derefter eksekveret via
subagent-driven-development: Codex (`gpt-5.6-sol`) som implementer pr. task, uafhængige
Claude-subagenter som task-reviewere. Alle 10 tasks grønne og godkendt:

- **Core (`packages/core`):** ny `presensLabels.ts` (anker-parse + dansk
  overskrift-generator: FARBROR/FARS SØSTER/SØSTRE, genitivkæder, kønssymmetri) og
  `presensListe.ts` (bottom-up-beskæring af afdøde uden levende efterkommere,
  anker-klatring, relationsgrupper, gren-partitionering via ankersæt, redaktionelle
  advarsler). Facitliste-test reproducerer DAA 2012-14 II linje 1. grens gruppestruktur.
  Suite: 297/297 (efter krydshenvisnings-tilføjelsen, se nedenfor).
- **Vokabular:** ny faktatype `overhoved` (schema.sql + db-migrations.sql + db-verify.sql)
  — udpeger linje-/gren-overhoveder som redaktionelt fakta, ingen skemaændring. Genbruger
  eksisterende `red_upsert_fakta`/`red_opret_fakta`-flow i person-editoren (web + mobil).
  **Prod-apply udført 2026-07-22** (bruger-godkendt) — se `docs/decisions.md` for verifikation.
- **Web:** ny "Præsensliste"-fane i Følgesvend-navigationen (`/praesens`), redaktion-gated,
  "Vis i præsensliste"-genvej fra person-detaljepanelet. Suite: 427/427.
- **Mobil:** ny `/praesens`-skærm + drawer-punkt 09, spejler webbens gating/tomtilstande/
  partner-visning. Suite: 348/348.
- **Fund undervejs (rettet, se `docs/decisions.md` for detaljer):** en Vitest-dobbelt-
  test-registrering pga. sibling-test-import (rettet: udtrukket delte fixtures til egen
  fil); mobil-skærmens manglende partner-visning + indlejrede komponenter (rettet); mobil
  manglede `canonicalIdById` på modellen (gjorde samme_som-kanonisering til en no-op på
  mobil — rettet, fanget af slut-reviewet).
- **Struktur-begrænsning RETTET 2026-07-22 (bruger-beslutning "vis én gang +
  krydshenvisning"):** en levende person nået ad to veje inden for SAMME ankers
  undertræ/gren (fx et dobbelt-fætterskab) blev tidligere enten stille droppet eller vist
  dobbelt. `pruneUndertrae` deler nu ét `alleredeVist`-sæt på tværs af hele grenens
  opbygning; første forekomst vises fuldt, senere forekomster bliver en
  `krydsReference`-stub med en synlig note i UI'et. Krydsning MELLEM grene
  (`dobbelt_naaet`-advarslen) er uændret. Se `docs/decisions.md`.
- **Trust-note:** Codex' selv-rapportering viste sig ved ét task at være opdigtet (beskrev
  ikke-eksisterende kode); den faktiske kode var korrekt i alle 10 tasks, fanget fordi hver
  task blev uafhængigt genverificeret (kontrollør kørte selv test-suiter, reviewer læste
  kun diffen).
- **Branch:** `feat/praesensliste` — [PR #76](https://github.com/johanreventlow/Danmarks-Adels-Aarbog/pull/76)
  (draft), afventer brugergodkendelse af merge.

## Mediehåndtering fase 4 — implementeret og verificeret lokalt (2026-07-22)

Fase 4 ("identitet & endeligt farvel") er implementeret lokalt via subagent-drevet
udvikling (Claude på DB-tasks, Codex gpt-5.6-sol på TS/React-tasks, dobbelt-review pr.
task): `red_erstat_media_fil` (M4, erstat bytes men behold identitet — id/relationer/
mentions/rettigheder uændret, filhistorik er fortryd-historikken), `red_udrens_media`
+ preview (M11, den rigtige permanente sletning — kun fra `'fjernet'`, blokeret af ALLE
polymorfe ankre: relation, text_mention, fakta m. evidenskæde, story, narrativ, note,
og — fundet under implementering, ikke i den oprindelige spec — `suggestion`; guard+slet
er ét atomisk statement), og `red_saet_portraet` + `relation.kvalifikator` (M10,
portræt-valg som redaktionelt fravalg af heuristikken, ikke dens erstatning).

Dual-reviewet design (`docs/reviews/34-mediehaandtering-fase4-plan-dual-review.md`) fandt
og rettede tre fund FØR implementering (manglende fakta-/story-/narrativ-anker, en
check-then-delete-race, NULL-blinde test-assertions) samt ét under implementeringen
(den manglende `suggestion`-anker). Per-task-review fandt yderligere fem reelle fund,
alle rettet: en check-then-act-race i erstat-filens statustjek, manglende oversættelse af
domænefejl, en foldet-samme_som-dedup der kunne tabe portræt-flaget til rækkefølge
(fundet og rettet på BÅDE web og mobile), en fejlagtig "mislykkedes"-besked efter en
allerede gennemført permanent sletning, og manglende dobbeltklik-beskyttelse på de nye
handlinger. To fund blev bevidst accepteret som restrisiko frem for at udvide scope:
en resterende (indsnævret, ikke elimineret) race på tværs af eksisterende, urørte
skrive-RPC'er (§10.2-afvejningen), og en tilsvarende resterende race i mobilens delte,
allerede-eksisterende `SkrivePreviewSheet`-komponent (prod-dato fra før fase 4, bruges
af fire andre skærme — uden for denne fases filscope).

Verificeret: frisk `schema.sql`-install og migrationssti (`mediehaandtering_fase4_identitet`)
konvergerer til identisk flade (tomt `diff`); alle fire fase-4-verify-blokke grønne ad
begge veje; web (tsc + 460 tests + build) og mobile (tsc + 375 tests) grønne; empirisk
ende-til-ende bekræftet mod lokal Postgres (erstat bevarer identitet, udrens
blokeres/lykkes korrekt, portræt sættes/ryddes korrekt). Ingen janitor-kodeændring
(kategori b dækker allerede erstat-/udrens-efterladenskaber); ingen RLS-fil ændret.
**Prod-deploy udestår som separat, gated trin** (egen runbook, fase 3-præcedensen);
mobile er dev-only i dette projekt, så app-deploy dækker kun web.

## Mediehåndtering fase 3 — LIVE i prod (2026-07-21)

Fase 3-koden er implementeret lokalt: nye uploads hashes over de genkodede large-bytes,
bruger deterministiske sha-stier og kan genoptages idempotent; web og mobil tilbyder
tilknytning til et allerede eksisterende medie. Biblioteket viser alder på strandede
uploads og en heuristisk dubletkø med blødt flet-flow. `R/media-janitor.R` er
rapport-first; destruktiv DB/Storage-oprydning kræver `--slet`, og sha-backfill kræver
sit separate `--backfill-sha`-flag.

Slutreviewet lukkede tre dataintegritetskanter: blød flet bruger nu en atomisk RPC, der
afviser evidensbærende relationer; janitoren bærer PostgreSQL `BIGINT`-id'er tabsfrit som
tekst; og normal web-/mobilupload bekræfter først `klar`, når alle varianter er uploadet
og registreret. Lokal slutverifikation efter merge af `origin/main`: web TypeScript +
422 tests + build, mobil TypeScript + 345 tests, core TypeScript + 267 tests og
R/testthat 420 tests var grønne. DAA-loaderens COPY-rækkefølge er samtidig låst af en
import-smoke, så relationer skrives før deres assertion/citation/conclusion-evidens.
Isoleret PostgreSQL 17 bekræftede både frisk skema og
den præcist scoped migrationssti fra præ-fase-3-basen; migrationen var idempotent ved to
gennemløb, bevarede ukendt historisk `created_at` som `NULL`, ryddede kun evidensfri
relationsdubletter og fejlede højlydt på en evidensbærende dublet. En reel to-session-test
bekræftede begge rækkefølger: writer-før-unlink afviser sletningen med relation og
evidens bevaret; unlink-før-writer afviser writeren uden orphan-data. Fresh og migration
gav samme fase 3-flade (`media.created_at`, `relation_afbildet_uidx`, `ix_note_target`,
relationsevidens-triggerne, `red_relation` og `red_slet_medierelation_uden_evidens`).
Ingen RLS-fil eller gamle storage-stier er ændret.

Tre implementeringsskøn er nu fastholdt: janitorens standardfrist er 7 dage og UI's
"muligvis i gang"-grænse er 1 time; dubletkøens nøgle er præcis
`(byte_size, bredde, hoejde)` uden `mime_type`; mobil bruger `expo-crypto` frem for
`@noble/hashes`. Tilføjelsen af det native Expo-modul kræver genbygning af dev- og
release-builds — en JavaScript-only opdatering er ikke tilstrækkelig.

**Prod-cutover afsluttet:** Den scoped blok blev anvendt mod
`xjnvdhajfyrcytatnzos` fra `caeb6a3`; web-produktionen og en ny native iOS Release blev
verificeret, og redaktør-røgtesten er udført. Første janitor-kørsel var rapport-only og
fandt 0 strandede uploads, 0 forældreløse objekter, 2 variant-huller og 6
SHA-backfill-kandidater. Der blev ikke kørt `--slet` eller `--backfill-sha`; begge er
fortsat særskilte, eksplicitte opt-ins. Se den lukkede
`docs/db-backups/2026-07-20-mediehaandtering-fase3-runbook.md` for deployloggen.

## Mediehåndtering fase 3 — implementeringsplan skrevet + dual-reviewet (2026-07-20)

Implementeringsplan (10 TDD-tasks, skrevet af Fable): `docs/superpowers/plans/2026-07-20-mediehaandtering-fase3-hygiejne.md`,
mod den mergede fase 3-spec. Dual-reviewet (`docs/reviews/33-mediehaandtering-fase3-plan-dual-review.md`)
— to uafhængige gennemgange (Codex var ikke tilgængeligt som værktøj i denne sessions miljø,
så anden-reviewer-rollen blev udfyldt af en fuldt uafhængig subagent i stedet, dokumenteret
eksplicit i reviewet). Fund: en fjerde, udokumenteret FK (`haendelse.relation_id → relation`)
i den evidens-sikre oprydnings-DELETE — verificeret strukturelt uskadelig i dag (kun skrives
for conclusion-bærende relationer, som DELETE'en allerede udelukker), men nu dokumenteret +
en defensiv `foreign_key_violation`-fangst tilføjet til janitorens sletning som fremtidssikring;
en accepteret race-vindue-restrisiko i dedup-guardens fejltekst (ingen kodeændring); og en
rækkefølge-fix i "Flet ind i…"-flowet (parkér kopien i papirkurven FØR relationerne flyttes,
så et afbrudt flet altid lander i en allerede håndteret tilstand). Klar til PR — implementering
ikke påbegyndt.

## Mediehåndtering fase 1+2 + levende feed fase 2-3 + K2 selektiv publicering — LIVE i prod (2026-07-20)

Deployet direkte til produktionsdatabasen via Supabase MCP (bruger-godkendt, kørt fra
sessionen — ikke den forberedte manuelle `psql`/dashboard-runbook). Et live objektinventar
(tabeller + `pg_proc`-funktionsnavne sammenlignet mod `db-migrations.sql`) afslørede at
`docs/database-current-state.md`s "sidst afstemt 2026-07-01" var stærkt forældet: alt
arbejde dateret 2026-07-02–2026-07-17 (samme_som, udledt slægtsnavn, dato-hærdning,
Problem 2 fase 1, K2 staging-gate) var reelt allerede live, blot udokumenteret. Kun tre
ting manglede: `haendelse` (levende feed fase 2), `story`/`story_kilde`/`feed_pin`
(levende feed fase 3) og `red_publicer_personer` (K2 selektiv publicering, samme dags dato)
— alle tre nu deployet, samt mediehåndtering fase 1+2 (se tidligere entries) og hele
`db-rls.sql` (retter `text_mention`s manglende `GRANT SELECT` + `tm_read`s fail-open
media-gren). `get_advisors(security)` efter apply: 117 fund, alle kendte mønstre
(SECURITY DEFINER-eksponering af `red_*`, bevidst deny-all på historiktabeller) — ingen nye.
Se `docs/database-current-state.md` for den fulde, ajourførte status.

**Ikke-oplagt:** de to store `apply_migration`-kald (2.9k-linjers `db-migrations.sql` og
723-linjers `db-rls.sql`) blev IKKE sendt i fuld længde — at læse begge filer ind i sin
helhed ville have brugt langt mere kontekst end rådighed. I stedet blev et præcist
objekt-diff (forventet vs. faktisk) brugt til at finde de tre manglende regioner, som
derefter blev udtrukket med `sed`/`grep` og verificeret linje-for-linje før anvendelse;
`db-rls.sql` blev læst i sin helhed (mindre fil, sikkerhedskritisk indhold) og kørt uændret.
Undervejs droppede Supabase-MCP-forbindelsen midt i et `apply_migration`-kald (brugerens
togforbindelse) — ingen skade, da alle statements er idempotente og hele kaldet var én
transaktion, der rullede atomisk tilbage; blev opdaget og genkørt efter reconnect.

## Operatørguide afstemt mod read-only prod-facit (2026-07-20)

**Denne audit var read-only og forud for deploy-entryen ovenfor** — dens "ikke live"-
konklusion for levende feed fase 2/3 og mediefase 1–2 er indhentet af samme dags deploy;
bevaret som historik for selve audit-fundet (dokumentationsdrift), ikke som aktuel status.

`docs/database-current-state.md` blev omskrevet fra det forældede 1. juli-snapshot til
en aktuel skelnen mellem repo, app og prod. Read-only katalog-/aggregatqueries mod
prod `xjnvdhajfyrcytatnzos` bekræftede: 1.758 personer, 835 staged, 77 levende;
`anon` og almindelig `authenticated` ser begge 853 personer og 0 levende/staged;
921 forældrefamilie-facts; 22 versionerede tabeller; 6 media-rækker (2 klare, 4
fjernede); samt at `_delete_relation_evidence` ikke er API-eksekverbar for anon/auth.

Problem 2/A1/K2 og media Slice 0 var live. 1939-source 3 forbliver staged og usynlig.
Gældende beslutning er **ingen publicering** før nyt OCR-udtræk og gentaget
artefakt-/komplethedsgate. Den ældre 1939-plan er bevaret som fasehistorik, ikke som
aktuel publiceringsordre. Ingen prod-skrivning eller schemaændring blev udført i denne
dokumentationsrunde.

## Mediehåndtering fase 3 — hygiejne-spec skrevet (2026-07-20)

Design-spec skrevet (ingen kode): `docs/superpowers/specs/2026-07-20-mediehaandtering-fase3-hygiejne-design.md`
— aktiverer den hidtil døde dedup-mekanisme (klienten beregner sha256 af large-bytes:
Web Crypto på web, expo-crypto på mobile), skifter til deterministiske sha-stier
(`redaktor/<xx>/<sha>-{tier}.jpg`, idempotent genupload) og oversætter DB-guardens fejl
til et "Billedet findes allerede → tilknyt i stedet"-flow oven på fase 2's tilknyt-mekanisme,
inkl. selvhelende genoptagelse af strandede kladder. Additiv `media.created_at` (to-trins
ALTER — ét-trins DEFAULT now() ville stemple alle gamle rækker med migrations-tidspunktet)
giver strandede-køen alder, og et partielt unikt index (`WHERE rolle='afbildet'`) lukker
fase 2's kendte relations-dublet-gap uden at røre periode-bårne roller som `ejer`.

Ikke-oplagte valg: sha tages af de GENKODEDE bytes, så dedup fanger samme pipeline-upload
men ikke web-vs-mobile-dubletter; da `media_sha256_uidx` gør sha-dubletter strukturelt
umulige, kører bibliotekets nye "Mulige dubletter"-kø på en (byte_size,bredde,hoejde)-
heuristik, mens janitorens sha-backfill leverer den ægte dublet-liste. "Flet ind i…" er
klient-orkestreret af eksisterende RPC'er og stopper ved blødt fjern — udrensning er
fortsat fase 4. Janitoren (`R/media-janitor.R`) er rapport-first: `--slet`/`--backfill-sha`
er eksplicitte flag, frist-gated, og rækker med ukendt alder røres aldrig.

## Mediehåndtering fase 2 — biblioteket implementeret lokalt (2026-07-19)

Web og mobil har nu et samlet mediebibliotek med søgning, køerne Rettigheder/Løse/
Strandede/Papirkurv, format-defensive thumbnails og en filside med “bruges på”.
Eksisterende medier kan tilknyttes personer, godser, våben og linjer gennem den
eksisterende GDPR-gatede `red_relation`; sletning er fail-closed, indtil anvendelser
er hentet, og relationer kan fjernes enkeltvis. Indsættelsespickere og Lightbox viser
fortsat kun klare billedmedier.

Databasekoden udvider `red_doede_links` med media-mål, mens RLS skelner mellem
redaktionens fulde mention-overblik og anon/medlems synlighed. Implementeringen og
dens migration er verificeret lokalt; intet er deployet til prod. Prod-trinnet er
fortsat gated og skal samle fase 1 + fase 2, `db-rls.sql`, verify-filer og app-deploy
efter read-only backup og eksplicit brugeraccept.

Kendt follow-up: pickerene skjuler allerede tilknyttede mål, og bibliotekstællinger
deduplikerer mål, men `relation` har endnu ingen databaseunikhed for identiske
`afbildet`-relationer. Direkte eller samtidige RPC-kald kan derfor stadig skabe en
dublet, som skal afkobles række for række.

## Mediehåndtering fase 2 — implementeringsplan (2026-07-19)

Plan skrevet (ingen kode): `docs/superpowers/plans/2026-07-19-mediehaandtering-fase2-bibliotek.md`
— 7 tasks med TDD-tjekbokse oven på fase 2-spec'en, forankret i kortlægningens
fil:linje-referencer. Ikke-oplagte punkter: NY Global Constraint "CI-hygiejne" (læring
fra fase 1-kørslen: ingen workflow-ændringer, aldrig `contents: write`, aldrig
selv-committende jobs — normal CI skal køre på den endelige HEAD, hvilket også står i
Definition of Done); biblioteks-query'en må IKKE filtrere `upload_status` (køerne er
pointen) mens pickers/Lightbox fortsat filtrerer `'klar'`; `klassificerMedie` holdes
tegn-for-tegn i sync web/mobile; prod-runbook'en samler fase 1-migrationen (endnu ikke
deployet) med fase 2's view-ændring i ét gated deploy.

## Mediehåndtering — dokumenter/transskription besluttet som fase 5 (2026-07-19)

Bruger-rejst behov (PDF/indscannede kilder + rå tekst-version af fx artikler; teoretisk
lyd/video) er designafklaret og skrevet ind: koncept-§4.8 + fasetabel-fase 5,
beslutningsnotat i `docs/decisions.md`. Kerne: samme media-system (tabellen er allerede
format-agnostisk; kun klient-laget er billede-specifikt), transskription som
narrativ-på-media (polymorf `narrative`, fts-søgbar — kræver egen GDPR-designrunde),
lyd/video kun som åben dør. Eneste fase 2-konsekvens indskrevet i spec-§6.1: defensiv
thumb-rendering (ikke-billede-mime → dokument-ikon, udeladt af Lightbox) — additiv
regel, ingen scope-udvidelse.

## Mediehåndtering fase 2 — design-spec for biblioteket (2026-07-19)

Spec skrevet (ingen kode), efter fase 1 er merget til main (PR #59):
`docs/superpowers/specs/2026-07-19-mediehaandtering-fase2-bibliotek-design.md` omsætter
konceptets fase 2 (M5–M7 + M9's synlighed) til 6 skiver. Empirisk forankret i den
mergede fase 1-kode: web's "Medier"-fane FINDES allerede men er tom
(`fetchEntityRecords('media')` → `[]` — fanen skal fyldes, ikke opfindes);
`red_relation(...,'afbildet')` findes server-side med GDPR-guard men er ueksponeret i
UI (ny Change-art `tilknytMedia` med klient-sidet retningsforgrening, server-guard som
bagstopper); `text_mention`+`ix_text_mention_maal` dækker allerede media ("bruges på"
er tre små queries, on-demand pr. filside). Kun ÉN DB-ændring: `red_doede_links` får
media-gren (kun ikke-eksisterende media = dødt link; fjernet medie er IKKE dødt — det
kan genoprettes og synliggøres via papirkurven). Kø-klassifikation som ren, testbar
funktion; strandede-køen UDEN aldersfilter (media har ingen `created_at` — kolonnen
udskudt til fase 3's janitor, åbent punkt §9.1). Lukker koncept-§10.5: mobile får
kø-tællere + tappbare rækker + fuld filside, web er primærflade for kø-arbejde.

## Mediehåndtering fase 1 — implementeringsplan (2026-07-19)

Plan skrevet (ingen kode): `docs/superpowers/plans/2026-07-19-mediehaandtering-fase1-filside.md`
— 9 tasks med TDD-tjekbokse oven på fase 1-spec'en. Ikke-oplagte valg: RPC-asserts
lægges i `db-verify.sql` efter det ETABLEREDE impersonerings-mønster (Task 5/5b:
`request.jwt.claim.sub` + profiles-seed + ROLLBACK_TEST_OK) — ikke i
`db-verify-media.sql`, hvis kontrakt er RLS-only uden redaktør-kontekst (den får kun
en anon-gating-assert for fjern→genopret-cyklussen via direkte UPDATE). Migrationens
DROP af gamle `red_upload_media` skal afskrives eksplicit fra git-historikken
(14-parameter-signaturen). Task 5/6 (læse-lag viser `'fjernet'`) og Task 7/8 (UI-
filtrene) er markeret som sammenhørende — mellemtilstanden kan vise fjernede thumbs.
Prod-deploy er eksplicit UDEN FOR planen (controller-gated runbook-trin i Task 9).

## Mediehåndtering fase 1 — design-spec for filsiden (2026-07-19)

Spec skrevet (ingen kode): `docs/superpowers/specs/2026-07-19-mediehaandtering-fase1-filside-design.md`
omsætter konceptets fase 1 (M1–M3) til 6 skiver: `red_opdater_media` (NULL=uændret/''=ryd),
`red_genopret_media` (kun fra `'fjernet'`, RAISE ved 0 rækker), `red_upload_media`-
signatur-udvidelse med kunstner/datering (⚠ kræver DROP+CREATE — `CREATE OR REPLACE`
ville skabe en PostgREST-tvetydig overload OG knække det navnebaserede grant-loop),
tre nye Change-arter (`opdaterMedia`/`genopretMedia`/`mediaRettigheder` — alle uden
fil-bytes, kan degradere til red_suggest), udvidet redaktions-read hvor `'fjernet'`
nu VISES for redaktionen (med to udpegede fail-open-fælder: narrativ-billedvælgeren
og Lightbox skal eksplicit filtrere `'klar'` — redaktionens storage-politik signerer
også fjernede stier), filside-overlay (web) / `MediaDetaljeSheet` (mobile) og udvidet
upload-ark. Kendt accepteret hul: fjernet medie uden relation kan først genoprettes
når fase 2-biblioteket lander.

## Mediehåndtering — koncept for robust medieforvaltning (2026-07-19)

Nyt konceptdokument `docs/design/2026-07-19-mediehaandtering-robust-koncept.md`
(ingen kode): analyse af redaktørens nuværende medie-muligheder (empirisk kortlægning
af web+mobile+DB) og et Wikimedia-inspireret målbillede — filside pr. medie,
mediebibliotek med arbejdskøer, komplet livscyklus (genopret/udrens), rettigheds-
workflow-UI oven på det eksisterende `red_set_media_rettigheder`, erstat-fil med
stabil identitet, samt aktivering af den i praksis inaktive sha256-dedup (klienten
hasher aldrig — DB-guarden fødes ikke). 11 konkrete mangler (M1–M11) prioriteret,
4 faser, ingen nye tabeller — kun 4–5 nye `red_*`-RPC'er efter etableret konvention.
Lukker de kendte udeståender "løse billeder"-oversigt + rettigheds-UI (Slice 0h-
changelog) som del af én sammenhængende plan i stedet for spredte features.

## 1939-narrativer — deterministisk kvalitetsrettelse (2026-07-19)

1939-segmenteringen er hærdet efter empirisk fund af gruppe-/vinduesduplikering,
grænse-bleed, kørende sidehoveder og bogstavspredning. `segment_1939.py` bruger nu
flere kildefaste ankre og bogens egne post-/sektionsmarkører, lokale og eksplicit
navngivne fallback-metoder samt 1939-specifik tekstrensning; `extract_text.sh`
filtrerer også 1939-sidehovedet ved fremtidige udtræk. QA-loggen måler nu bl.a.
duplikatklynger, flerpost-narrativer, sidehoveder, bogstavspredning, fremmede unikke
datoer og længdehale.

Lokalt facit for 539 poster: vinduesstore narrativer 42→0, maks-længde
80.192→4.377, eksakt duplikerede poster 98→25, flerpost-narrativer 208→13,
sidehovedforekomster 625→0 og narrativer med bogstavspredning 486→0. Ingen
prod-opdatering er udført; rettet staged data kræver separat backup, rehearsal og
eksplicit godkendt 1939-only opdatering. Se
`docs/reviews/2026-07-19-1939-narrativ-kvalitet.md`.

## Levende feed fase 3 — implementeret og lokalt verificeret (2026-07-19)

Fase 3 er gennemført efter
`docs/superpowers/plans/2026-07-19-levende-feed-fase3.md`: additivt
`story`/`story_kilde`/`feed_pin`-skema med RLS, syv kontrollerede redaktions-RPC'er og
versionering; delt story-/pin-logik i `@daa/feed`; tolerant load og `historie`-kort i begge
klienter; inline story-editorer; web-feedstyring; samt portræt-pins som startpersoner med den
hidtidige kuraterede liste som fallback.

**Ekstra review og rettelser:** Medlemsflowets `red_suggest`-payload mistede tidligere
`storyId` ved redigering og medtog ikke storyens kilder. Forslaget indeholder nu både
routing-id, tekstfelter og hele kildelisten. Den direkte web-editor gemmer fortsat story og
kilder via de to eksisterende RPC'er, men udsætter person-reload til begge er lykkedes. Hvis
kildekaldet fejler efter en oprettelse, forbliver editoren åben med det persistente story-id,
så næste forsøg redigerer samme story i stedet for at oprette en dublet. Begge forløb er låst
af nye regressionstests. Slutreviewet fangede desuden et muligt overlap mellem to samtidige
gemninger: editoren har nu en single-flight/generations-guard, relevante handlinger er låst
mens begge RPC'er kører, og sene resultater ignoreres efter navigation/editor-skift. Et
vellykket medlemsforslag lukker editoren, så samme forslag ikke indsendes igen ved et ekstra
klik. Publicerings-RPC'en er samtidig gjort fail-closed: kladder må fortsat stå uden kilder,
men status kan ikke skiftes til `publiceret`, før mindst én `story_kilde` findes. Den nye
databaseassert blev først kørt rød mod den uhærdede funktion og derefter grøn mod både
clean-slate- og migrationsstien. Web-feedstyringen genbruger nu de eksisterende theme tokens
i stedet for at indføre lokale farve- og fontkopier.

**Verificeret automatisk/lokalt og i CI:** `@daa/feed` 107/107 tests + typecheck,
`@daa/core` 264/264 tests, mobil 224/224 tests + typecheck og web 235/235 tests +
produktions-build. Alle nye tests ligger i de eksisterende `feed`, `web` og `mobile`-jobs i
`.github/workflows/ci.yml`; der er ikke tilføjet fase 3-jobs, og R-jobbet er urørt. CI-kørsel
`29705889967` på commit `4b9a1d2` er grøn for feed, core, mobil, web, R og pipeline.

**Verificeret i lokal PostgreSQL:** både frisk `schema.sql` og migrationsstien fra fase 2
(`db-migrations.sql` kørt to gange, derefter `db-rls.sql`) er kørt. Den afgrænsede fase
3-blok i `db-verify.sql` er grøn for CHECK/UNIQUE/RPC-gates, anon/authenticated-RLS,
`story_kilde`-cascade og fortryd af både statusskift og hel story. En afsluttende read-only
kontrol af migrationsdatabasen bekræftede de tre tabeller, RLS/policies, story-RPC'erne og
`trg_log_story`/`trg_log_feed_pin`. Det komplette historiske `db-verify.sql` stopper fortsat
tidligere på en ældre fixture-afhængig cache-test i den tomme lokale base; fase 3-blokken er
kørt selvstændigt. Task 13-gaten blev gentaget 2026-07-20 mod den verificerede prod-backup:
3 tabeller, 7 RPC'er, 8 policies, 2 versioneringstriggers, RLS på alle tre og 0 ugyldige
constraints; anon kunne kalde 0/7 RPC'er, mens authenticated kunne kalde 7/7.

**Rollback-beredskab:** Den separate `db-rollback-fase3.sql` er lokalt rehearsed. Den kører i
én transaktion og afbryder ved fase 3-data eller -historik, så den kun kan fjerne det tomme
additive lag efter en fuld backup. Task 13-gaten kørte rollbacken to gange og bekræftede
idempotens, 0 resterende fase 3-objekter og bevaret fase 2-`haendelse`; det er ikke en
prod-migrering eller et prod-bevis.

**Manuel UI-status og resterende deploy-gates:** Et lokalt browser-smoke dækkede kort-views,
editor-/feedstyringsflader og staging-preview, men Task 8/10/11's komplette LIVE-forløb
(opret/publicér/arkivér/fortryd story, pin/skjul/fjern og authenticated medlemsstaging) er
ikke kørt mod en Supabase-kopi, fordi en sådan kopi ikke er tilgængelig. Derfor er rigtig
PostgREST-nesting, JWT-rolleoverførsel, schema-cache og Supabase security advisors heller ikke
end-to-end-verificeret. De punkter er deploy-gates, ikke skjult som lokale testresultater.

**Prod-status:** Ingen prod-migration eller prod-skrivning er udført.
`docs/database-current-state.md` er bevidst uændret og må først opdateres efter en eksplicit
gated prod-migrering.

## Levende feed fase 2 — implementeret i kode (2026-07-18)

Fase 2 er gennemført efter `docs/superpowers/plans/2026-07-18-levende-feed-fase2.md`:
additiv `haendelse`-projektion med RLS, kontrolleret status-RPC og versionering; hændelses-load
i begge klienter; hændelsesdrevne `arkiv`-, `citat`- og `paadennedag`-kort; den nye
`.claude/skills/daa-haendelser`-pipeline; samt redaktionens kronologiske hændelsestidslinje
og statusmarkering på web og mobil. Fase 1-reviewfund er samtidig indarbejdet.

**Verificeret automatisk/lokalt:** frisk schema-installation og migrationsstien (migrationen
kørt to gange) mod lokale PostgreSQL-databaser; fase 2's målrettede CHECK/RLS/RPC/versionerings-
asserts; GDPR-eksportens optælling mod den samme lokale kopi (544 eksporterede, 47 ikke-
offentlige kandidater udeladt); H1–H8-validatorens og den fail-closed Opus-promotions
Python-tests; R-loaderens merge-tests;
loader-`--dry-run` med rollback; samt genkørsel oven på en markeret hændelse, hvor både id og
`feed_status='interessant'` blev bevaret. Klient-, core-, feed-, R- og pipeline-suiterne samt
web-build er kørt lokalt; CI har fået et særskilt `pipeline · unittest`-job.

**Ikke manuelt verificeret:** den samlede redaktør-UI mod en autentificeret PostgREST-session
i browser/simulator. UI'ens data-, status-, staging- og tidslinjelogik er dækket af tests og
typecheck/build. Det komplette historiske `db-verify.sql` når fase 2-blokken, men stopper senere
i en allerede eksisterende rolle-gating-test for `red_slet_oplysning`; fase 2's målrettede
DB-verifikation er grøn.

**Prod-status:** Ingen prod-migration og intet prod-pipeline-load er udført. Det er fortsat
separate, eksplicit godkendte deploytrin; `docs/database-current-state.md` er derfor uændret.

## Levende feed fase 2 — implementeringsplan skrevet (2026-07-18)

`docs/superpowers/plans/2026-07-18-levende-feed-fase2.md` (13 tasks, TDD task-for-task efter
fase 1-planens skabelon) omsætter design-specen til konkrete skridt: skive 1 (DB) → task 1,
skive 3 (klient-load) → task 2-4, skive 4 (motor: arkiv/paadennedag/citat/kort-views) → task
5-7, skive 2 (offline pipeline `daa-haendelser`) → task 8-10, skive 5 (redaktions-tidslinje)
→ task 11-12, skive 6 (CI+afstemning) → task 13. Skrevet af en Fable-subagent, der undersøgte
den faktiske kodebase (ikke kun specen) for præcise filstier/linjenumre/funktionssignaturer —
egen efterfølgende verifikation fandt og rettede én reel fejl: agentens påstand om at
versionerings-infrastrukturen (`version_pk_registry` + trigger-loop) kun findes i
`db-migrations.sql` var forkert (den findes i BÅDE `schema.sql` og `db-migrations.sql`, med
forskellig håndtering nødvendig i hver — se planens Self-review-noter); uden rettelsen ville
en frisk clean-slate-deploy mangle `trg_log_haendelse`. Øvrige åbne verifikationspunkter
(fx om PostgREST tillader dobbelt-nestede selects) er ærligt flagget i planen som
implementer-verifikation, ikke påstået som fakta. Ingen kode er ændret; implementeringen
starter ikke før eksplicit anmodning.

## Levende feed fase 2 — design-spec skrevet (2026-07-18)

`docs/superpowers/specs/2026-07-18-levende-feed-fase2-design.md` (6 skiver) beskriver
hændelses-skelettet: ny tabel `haendelse` (regenerérbar projektion oven på fact/
assertion/conclusion — aldrig ny evidens), offline LLM-ekstraktionspipeline
(`.claude/skills/daa-haendelser/`, samme eksport→LLM→valider (H1–H8)→load-mønster
som daa-extract) med bevarelses-mergende genkørsel via en stabil nøgle (normaliseret
klausul + #N-suffiks ved dubletter), RLS via `entitet_offentlig`-kaskade, ny RPC
`red_set_haendelse_status`, `arkiv`-korttype + udvidet `paadennedag` + klausul-baseret
`citat` i `@daa/feed`, og redaktionens hændelses-tidslinje (begge apps). Skrevet af en
Fable-subagent efter eksplicit anmodning; ni DB-mekanismer verificeret uafhængigt mod
`schema.sql`/`db-migrations.sql`/`db-rls.sql` (funktion-signaturer, `vocab`-PK-form,
`staged`-kolonnen, `entitet_offentlig`-brug) — alle stemmer. Endnu ikke implementeret;
ingen plan skrevet.

## Levende feed fase 1 — implementeret (2026-07-18)

Fase 1 (dynamik & uendelig scroll) af `docs/design/2026-07-18-levende-feed-koncept.md` er
gennemført task-for-task efter `docs/superpowers/plans/2026-07-18-levende-feed-fase1.md`.
12 tasks, alle grønne (`@daa/core` 254 tests · `@daa/feed` 59 tests · mobil tsc+jest 196
tests · web tsc+vitest 188 tests + build + 3× stabil Playwright-e2e).

**Ny pakke `@daa/feed`** (`packages/feed/`, eget CI-job): kandidat-pool (builders porteret
fra mobilens v3-`buildFeed`, caps fjernet) → forklarlig scoring (BASE-vægte pr. kind,
timeliness/personal/seen-faktorer) → seedet vægtet trækning uden tilbagelægning
(mulberry32) med rytme-regler (R1 ikke-samme-kind, R2 person-afstand, R3 mindst ét
portræt pr. 6) og eskalerende relaksering når kind-diversitet løber tør → positionslåse
(dagensperson, slaegt) via byt (ikke fjern+genindsæt — undgår at sammenføje naboer) →
strøm-API (`createFeedStream`/`resumeStream`) med bevist `next(a)+next(b) ≡ next(a+b)`.
To nye korttyper: `paadennedag` (dag-præcis, med måneds-fallback) og `dagensperson`
(dagligt roterende, disjunkt fra portræt/citat). Livsdato-join (fact→conclusion→assertion)
er delt logik; hver app henter selv (mobil: parallelt med hoved-batchen i `load.ts`; web:
ved feed-mount i `feedAux.ts`/`livsdato.ts`) — `visning_foedt/doed` er rå datotekst og kan
ikke bære dag-præcision.

**Mobil:** forsiden doserer nu via `createFeedStream` (seed = dagsdato + tilfældig nonce,
det eneste sted `Math.random` optræder), ægte `onEndReached`-append, pull-to-refresh =
nyt seed, footer med tre reelle tilstande. Set-hukommelse i AsyncStorage (LRU 300,
decay-vægte 0.25/0.5/0.75). Gamle `buildFeed.ts`/`feedHash.ts` + deres testsuite slettet
(ingen forbrugere tilbage — alle imports peger nu på `@daa/feed`).

**Web:** ny `FeedStreamView` monteret under forsidens hero/kuraterede sektion (samme motor
og kort-katalog som mobil, egne kort-views i webbens idiom). Bio hentes og stemples ind i
en model-kopi ved feed-mount (`fetchFeedBios`/`withFeedBios`); ved ankomst genopbygges
strømmen med samme seed og genoptages via `resumeStream`, uden at nulstille allerede viste
kort. **Reel bug fanget af den nybyggede e2e-test (Playwright, bootstrappet fra bunden —
ingen opsætning fandtes forud):** uendelig-scroll-sentinellen brugte en
`IntersectionObserver` med standard-root (viewporten), men Følgesvendens rodlayout scroller
i en indre `[data-scroll]`-container (`height:100vh; overflow:hidden` på roden) — observeren
så derfor aldrig sentinellen krydse ind/ud og fejlede helt stille. Erstattet med en
`scroll`-lytter direkte på `[data-scroll]` + en synkron "fyld skærmen"-efterkontrol (dækker
både ægte scroll og "indhold ankommer uden at brugeren scroller", fx bios der forlænger en
kort forside). 18/18 e2e-kørsler grønne efter fixet.

**Oprydning:** `interleave` (ubrugt — rytmen er vægtet trækning, ikke round-robin) fjernet
fra `@daa/feed`s offentlige API. v3-spec'en (2026-07-05) har fået en status-note: §3
(feed-datamodellen) er afløst; §4-6 (UI/drawer/bogmærker) er fortsat gældende. Ingen
backend-/skemaændringer i hele fasen.

## Plan: levende feed fase 1 — klar til implementering (2026-07-18)

Implementeringsplan for fase 1-spec'en: **`docs/superpowers/plans/2026-07-18-levende-feed-fase1.md`**
— 12 tasks i TDD-stil (fejlende test → implementér → grøn → commit) i eksekverbar rækkefølge:
pakke-skelet+prng → typer+pool → tidslige kort → scoring+ordning → strøm → mobil livsdato/seen/dosering
→ web datalag/views/e2e → oprydning. Pakke-invariant fastlagt: `@daa/feed` er netværksfri (rene
join-/decay-helpers i pakken, fetch i app-lagene); `resumeStream` definerer den append-sikre
genoptagelse ved webs bio-ankomst. Punkter implementer skal slå efter frem for at gætte er markeret
eksplicit (core-exportmekanisme, Aux-feltformer, pickPreferredBio-signatur, web-nav-handlers,
Playwright-placering). Dokumentationssporet (koncept → spec → plan) er hermed komplet — implementering
kan køres af en eksekverende session/model uden yderligere designbeslutninger.

## Spec: levende feed fase 1 — dynamik & uendelig scroll (2026-07-18)

Design-spec for feed-konceptets fase 1: **`docs/superpowers/specs/2026-07-18-levende-feed-fase1-design.md`**.
6 skiver: (1) ny delt pakke `@daa/feed` (lukker konceptets ○a) med motor-kernen pool → score → seeded
sampling (mulberry32) → rytme-regler, caps/interleave udgår; (2) strøm-API `createFeedStream` med
`next(n)`-stabilitet og ærligt terminalkort; (3) mobil: ægte dosering via `onEndReached`, pull-to-refresh
= nyt seed, set-hukommelse i AsyncStorage (LRU 300, decay-vægte); (4) tidslige kort — `paadennedag` +
`dagensperson` + dag-præcise jubilæer via tolerant klient-load af konklusionsdatoer (fact→conclusion→
assertion.date_min; `visning_foedt/doed` er rå datotekst og kan ikke bære dag-præcision); (5) web-feed-MVP
under forsidens hero (aux-adapter, embede-kort bevidst udeladt, bio-strategi med målt payload + chunket
fallback); (6) oprydning + afløsnings-note i v3-spec'en. Ingen backend-ændringer — kun nye læsninger af
eksisterende tabeller under eksisterende RLS.

## Idékatalog: formidling oven på kildematerialet (2026-07-18)

Brainstorm-runde i forlængelse af feed-konceptet, dokumenteret til senere bearbejdning:
**`docs/design/2026-07-18-formidlingskatalog.md`** — 19 idéer i 7 klynger (evidens-formidling som
attraktion, serier/udstillinger, kort & sted, personalisering, objekter, distribution ud af appen, leg),
hver med databasegrundlag, afhængigheder og indsats, plus et vejledende prioriteringsbillede (mest
særegne: kildeuenigheds-serien, årbogens egen udvikling, efterlysninger; billigst: føljetoner,
våben-forklaringer, delekort). Intet besluttet — hver idé løftes til eget koncept når den vælges.
Krydsrefereret fra feed-konceptet og indekseret i `docs/README.md`.

## Koncept: Det levende feed (2026-07-18)

Idéudviklings-runde (ingen kode) der samler feed-videreudviklingen i ét styringsdokument:
**`docs/design/2026-07-18-levende-feed-koncept.md`**. Baseret på kodebase-analyse af mobil-feed'en
(`buildFeed` — deterministisk, ingen paginering, `FeedOverride` no-op), web-forsiden (statisk PoC uden
highlights-tabel) og narrativ/fakta-laget (intet beskrivelsesfelt på `fact`; daterede gerninger bevidst
kun i prosaen). Hovedgreb: (1) feed-motor 2.0 — kandidat-pool + scoring + seeded sampling + rytme-regler
+ lazy strøm-API (ægte uendelig scroll), delt web↔mobil-pakke; (2) nyt **formidlingslag** oven på uændret
evidensmodel: `haendelse` (narrativ-afledt dateret hændelses-skelet, offline LLM-pass) + `story`
(redaktionelle minihistorier m. kildefod) + `feed_pin`; (3) redaktionelt historieværksted
(hændelses-tidslinje, markér interessant, skriv/godkend) med "Foreslå historie"-knap via auth-gated Edge
Function — LLM-kladder publiceres aldrig uden redaktørgodkendelse, kun afdøde. 4 faser; lukker samtidig
web-konceptets åbne §9.f (forside = faste indgange + feed). Indekseret i `docs/README.md` (ny sektion
"Design & koncepter").

## Sikkerhedshærdning fra Codex-fundament-review (2026-07-17)

Et helrepo-"fundament-review" (Codex, 21 fund F-01..F-21) blev triageret ind i waves med fokus på: dels at
få 1939-stamtavlen indlæst til prod, dels at lukke de fund der bør løses. **1939-loadet er nedstrøms Fase
4-cutoveren**, så alt der skal på prod-skemaet samles i én gated deploy; resten er app/loader/CI uden prod.

**Wave 0 (pre-cutover, ingen prod-berøring) — merged til main:**
- **F-01 (#42):** `_delete_relation_evidence` (SECURITY DEFINER, muterende) var anon-kaldbar via PostgREST →
  anon kunne slette relations-evidens som ejer (omgår RLS). REVOKE + `current_rolle()`-guard. Præcis analyse:
  kun denne var et reelt hul; version-helperne (SECURITY INVOKER) fik REVOKE som defense; `_regen_mentions_for`
  bevidst urørt (trigger kalder den som skriveren → REVOKE ville bryde narrative/note-writes).
- **F-02 (#43 person + #45 media):** authenticated-tier (enhver logget-ind bruger) kunne læse alle ikke-private
  LEVENDE personer + deres fakta/relationer/narrativer/evidens **og fotos** uden samtykke (brød invariant #8).
  `auth_read` filtrerede kun `privat`, ikke `levende`. Fail-close: spejler nu anon via `person_offentlig`;
  media/media_variant/storage via `media_synlig_anon`. Redaktion beholder fuld adgang (additivt `redaktion_read`).
- **F-02c (PR #46, draft):** Codex-genkørsel (med reel fil-adgang) fandt at `<> 'person'`-mønstret er en HEL
  KLASSE af fail-open — media var #1, `family`/ukendt-type #2: en levende families vielse-/skilsmisse-fakta +
  noter var synlige for anon OG authenticated (family_member skjult, men family-fact ikke). Nye SECURITY
  DEFINER-helpers `entitet_offentlig(type,id)` + `family_offentlig(fid)` erstatter alle 8+ `<> 'person'`-
  klausuler i fact/relation/narrative/note/text_mention; fact/relation-mål cascader gennem targetets RLS;
  fail-closed på ukendt type. db-verify Task 8b+8c tester begge retninger (læk skjult + ingen over-hiding).
- **F-16 (#44):** CI gatede ikke `@daa/core`-typecheck eller R-testene → en tsc-fejl (`Koen`-type i
  tree.test.ts) akkumulerede ufanget. Fix + eksplicit vitest-import i buildGeo.test.ts + nye CI-jobs
  (core-typecheck + R/testthat via duckdb, DB-service-frit). Alle 4 CI-jobs grønne.

**Fase 4 cutover forberedt (ikke udført — gated på prod-godkendelse):** `docs/fase4-runbook.md` fik **Trin 1b**
(gen-anvend `db-rls.sql`) — kritisk fordi `db-migrations.sql` ikke gen-anvender RLS-laget, så F-01/F-02/F-02c
ellers aldrig ville nå prod. Plus GATE-0 blast-radius-query (f) for F-02c's over-hiding af død-familie-fakta.

**Metode:** TDD mod lokal `daa_test2` (RED→GREEN + regression begge retninger); dual-review (Codex adversarial
+ selv-audit); advisor-konsultation før den polymorfe RLS-omskrivning. Prod aldrig rørt — klassifikatoren
kræver at brugeren eksplicit navngiver prod-målet.

## `packages/core` — delt web↔mobil-logik (review 27 Bølge 3 #13, 2026-07-14)

**Den rene, DOM/RN/netværks-frie domænekerne er samlet i ÉN npm-workspace-pakke `@daa/core`**, som
både web (Vite) og mobil (Metro/Expo SDK 56) importerer source-only (rå `.ts`, ingen build). Lukker
rodårsag #2 fra review 27: ~15 spejlede moduler uden delingsmekanisme, hvor drift allerede var begyndt.
Repoet er nu et npm-workspace (root `package.json`, konsolideret lockfile).

Flyttet til core (kanonisk én kopi): `collapseSameAs`, `relationship`, `generations`, `buildModel`,
`sammeSomPreflight`, `buildGeo`, `geoSelectors`, `fields`, `pickPreferredBio`, `collation`, `mentions`,
`getAll` (paginering — fik sin første test), samt tree-kernen (`columnLabel`, `columnGen`, `buildDirection`,
`unknownParentRing`, `unknownChildSection`, `buildBidirectionalColumns`). Den snævre delte type-grænse
(`Model`-superset m.m.) bor i `packages/core/src/types.ts`; begge apps re-eksporterer den + beholder app-
specifikke typer lokalt. **Bliver bevidst i apps** (ægte platform-forskelle): fetch-orkestrering
(`model.ts`/`load.ts`), redaktør-skrivelaget, bogmærker, og graf-traverseringerne `childrenOf`/`parentsOf`
(web `childIdx` vs mobil `childrenByUnion`). `buildBidirectionalColumns` parameteriseret over de to
traverseringer, så den kunne deles trods app-specifik graf-adgang.

Alle `parity.test.ts`-vagter pensioneret (funktionerne er nu single-source). Tests dedupликeret: ~669 →
538 (211 core + 146 web + 181 mobil), ingen dækning tabt — de delte tests kører nu én gang. Begge apps
`tsc` rene; Vercel-deploy verificeret (installCommand kører fra repo-rod så workspace-symlinket resolves).

Eksekveret spike-first (ét modul + 5 tooling-checkpoints før fuld flytning), dual-reviewet spec (Codex:
5 fund indarbejdet — bl.a. at `linjeByPerson`-konflikten sidesteppes ved at holde `Aux` app-specifik frem
for at forsone den), og subagent-drevet per-task-review. Spec: `docs/superpowers/specs/2026-07-13-*`,
plan: `docs/superpowers/plans/2026-07-13-*`.

## Slankning af `claude.md` (2026-07-12)

CLAUDE.md-audit (`/claude-md-improver`): filen gik fra ~382 til ~53 linjer. Fjernet historisk
handoff-framing, forældet onboarding (§6/§8), og en artefakt-tabel der pegede på 4 filer der ikke
findes (`diagram-1/2-*.mermaid`, `supabase_load.py`, `import_test.py`). Tilføjet en `## Kommandoer`-tabel
(web/mobile/R/DB — det største hul). De 9 invarianter bevaret ordret i substans (kondenseret til én linje
hver), §7-dubletter foldet ind i dem. Ny struktur: kun stabilt/ufravigeligt bor resident; status, historik
og backlog peger ud i `docs/`. Tidligere kontekst arkiveret ordret i `docs/claude-md-context-archive.md`
(commit `dc9908f`). Pushet til `origin/main` (`dc9908f` + `bfc7f6c` review-docs 24-27).

## Review 27 — dual-review af review-26-rettelserne (web+mobil, branch `feat/generations-browser-v2`, 2026-07-11)

Claude+Codex dual-review af selve review-26-rettelserne (`docs/reviews/27-review26-fixes-dual-review.md`).
Code-analyzer: 0 bugs. **Codex hævede den rigtige robustheds-/scoping-flanke** (alle claims verificeret
empirisk — ingen laundering):

- **MEDIUM (rettet):** `red_tilbagetraek_fakta` åbnede et change_set FØR den tjekkede om noget blev ramt →
  forkert/dobbelt-klik gav tomt change_set + falsk succes. Nu fail-closed `IF NOT EXISTS(... afklaret) THEN
  RAISE` før `begin_change_set` (schema.sql + db-migrations.sql). Rollback-test udvidet: dobbelt-retract
  rejser nu ærlig fejl. **Kræver prod-re-apply** (idempotent CREATE OR REPLACE).
- **Determinisme (rettet):** `fetchForaeldreUkendtMarkering` manglede `order` (PU-loaderen har `.order('id')`)
  → `.order('target_id')` tilføjet (begge platforme).
- **NaN-guard (rettet):** `buildRpcCall`-guarden afviste kun `null`; `Number('')===0` slap igennem. Nu
  afvises tom/blank + ikke-endelige eksplicit (begge platforme; tests +2).
- **Stale kommentar (rettet):** `Redaktion.tsx` sagde stadig `red_slet_oplysning (fjern)`.
- **HIGH surfacet (pre-eksisterende, IKKE regression):** samme_som-collapse gør Fjern ufuldstændig —
  editoren opererer på rå `personId`, projektionen er kanonisk; to foldede medlemmer begge markeret →
  Fjern rammer kun én. Eskalering af review-26 MEDIUM 3. Afventer bruger-beslutning (kaskadér / vis konflikt
  / PoC-grænse). Sjældent (kræver to samme_som-linkede personer begge hånd-markeret).
- **Kvalitet:** web 243/243 + mobil 332/332 + tsc rent + lokal rollback-test grøn (inkl. guard-assertion).

## Review 26 (Codex) — rettelser af generationsbrowseren (web+mobil, branch `feat/generations-browser-v2`, 2026-07-11)

Codex-review af `feat/generations-browser-v2` (brief: `docs/reviews/26-foraeldre-ukendt-generationsbrowser-review-brief.md`).
Fund verificeret mod koden (advisor-gate + `superpowers:receiving-code-review`): HIGH 2 = ægte bug,
HIGH 1 = reel over-implikation (delvist), MEDIUM 2 = dokumenteret PoC-grænse, MEDIUM 1 + 3 = backlog.

- **HIGH 2 (bug — rettet):** "Fjern markering" kaldte `red_slet_oplysning`, som re-peger konklusionen
  til den ÆLDSTE tilbageværende påstand. Efter Markér → Opdatér (to påstande) → Fjern genoplivede den
  derfor den oprindelige markering i stedet for at fjerne den. **Fix:** ny generisk RPC
  `red_tilbagetraek_fakta(p_fact_id)` sætter fakta-slottets konklusion `'afklaret' → 'tilbagetrukket'`
  (læse-gates kræver `afklaret`, så markeringen holder op med at projicere; re-Markér reaktiverer via
  `red_upsert_fakta`s `ON CONFLICT`). Append-sikkert (påstande uforanderlige, invariant 1), fortrydbart
  (`conclusion` er `version_pk_registry`-sporet). App: ny `tilbagetraekFakta`-art (web+mobil buildRpcCall),
  `fetchForaeldreUkendtMarkering` returnerer nu `factId`, Fjern-knappen ruter om. Per-oplysnings-🗑
  uændret (`sletOplysning` er korrekt der). **Verificeret:** lokal rollback-test mod prod-kopien
  (`daa_test2`) beviste både bug-reproduktion OG fix i én rullet-tilbage transaktion (retract → 0
  afklarede + 2 bevarede påstande + virkende re-Markér). `schema.sql` + idempotent `db-migrations.sql`.
- **HIGH 1 (over-implikation — ordlyd skærpet):** nedad-projektionen ligger inde i en mands børne-kolonne
  og kunne læses som "hans mulige børn". Kandidat-visningen beholdt (bruger-ønske om inline-bladring),
  men ordlyden skærpet: header "Uforbundne i dette slægtled" → "Uforbundne — placeret efter slægtled,
  ikke forældreskab"; grad-1-note "Muligt barn — …" → "Muligt barn **i linjen** — forælderen er ikke
  navngivet". Rene string-ændringer, delt kerne holdt byte-identisk.
- **Bevidst udskudt:** MEDIUM 2 (kilde gemt som fritekst i `citat_tekst` frem for struktureret
  `source_id`/side + ordret formulering) — dokumenteret PoC-grænse (`schema.sql` linje 536); det rigtige
  fix er skema+UI-arbejde, holdt ude af dette changeset for at bevare stramhed. MEDIUM 1 (`usikker` tabes
  i `backfill_slaegtled.R` — anden akse: usikkert *medlemskab* vs. ingen *forbindelse*, ingen forbruger
  endnu, YAGNI) + MEDIUM 3 (flere markeringer efter samme_som-collapse: "første vinder", deterministisk,
  sjælden) = backlog.
- **Kvalitet:** web 242/242 + mobil 331/331 + tsc rent begge steder. `red_tilbagetraek_fakta`
  **anvendt mod prod 2026-07-11** (ren additiv `CREATE OR REPLACE`, bekræftet FALSE→TRUE, signatur
  `p_fact_id bigint`) — Fjern-knappen virker nu i live-appen. **UDESTÅR:** empirisk E2E på device
  (markér→opdatér→fjern via redaktør-login) + dual-review + merge.

## "Forældre ukendt"-markering + inline marker-gatet kandidat-kolonne (web+mobil, branch `feat/generations-browser-v2`, IKKE merget, 2026-07-09)

Løser problemet fra `docs/reviews/25-generationer-ukendt-forbindelse-analyse.md`: stamtræets ene
signal "ingen `family_member`-kant" dækkede over FIRE virkeligheder (bevist / formodet / kilden
angiver ingen forbindelse / kant ikke udtrukket endnu). v1/v2's fallback tolkede ALT fravær som
"ukendt" → forkerte kandidater (person 210 under 208). Den manglende epistemiske primitiv: at KILDEN
ikke angiver en forbindelse opad er selv en kildepåstand.

**Beslutninger (bruger-interview 2026-07-09):** (a) skeln TO grader ('forælder ukendt' vs 'ingen
forbindelse angivet'); (b) INLINE distinkt kolonne i træet — IKKE et separat side-panel-register
(det var netop det spor der gled væk fra ønsket om inline-bladring); (c) markér én reel klynge til
verifikation.

- **Phase A:** fjernet den ugatede fallback + activeCoord-maskineriet (T6-review-effekten). Kun
  beviste kanter + slægtled-labels læst fra faktisk koordinat (`columnGen`, løser review 20 H1
  "-7. slægtled"). Slettet `fallbackRing`/`buildAnchorPeers`/`adjacentGen` founder-hop (inert i prod).
  **Rydder også v1's aner-fallback der stadig er live på main/prod** ved merge.
- **Phase B:** INGEN skema-ændring (invariant 2). Markeringen = `fact(faktatype='forældre_ukendt')`
  + assertion (grad) + citation (proveniens) + afklaret konklusion, skrevet via `red_upsert_fakta`.
  Ren `buildParentsUnknown`-resolver (byte-identisk web↔mobil) + `fetchParentsUnknownRows`
  (overlapper hoved-batchen) → `parentsUnknownByPerson` på model/store. Vokabular seedet i
  `db-migrations.sql`.
- **Phase C:** `unknownParentRing` — inline marker-gatet kandidat-kolonne (forrige slægtled,
  kuld-grupperet). Fyrer KUN på en tilstedeværende afklaret markering, aldrig på fravær af en kant.
  Cross-linje-bladring (founder → moderlinjen) emergerer af samme_som-collapse uden founder-hop.
  Grad afgør ordlyden. Distinkt render (stiplet/amber, "muligt slægtled"-tag, Kilde-footer); klik
  re-ankrer (ren navigation). Web `Folgesvend` + mobil `tree.tsx`.
- **Nedad-projektion (efterkommer-retning):** `unknownChildSection` — samme markeringer vist NEDAD:
  når man bladrer fra en (mandlig) stamfader, augmenteres børne-kolonnen med en "Uforbundne i dette
  slægtled"-sektion (markerede-uforbundne i næste slægtled, samme linje). Ren projektion af de
  eksisterende markeringer (ingen ny authoring — evidens-hygiejne: kun projektionen har altid et ægte
  kilde-citat). Marker-gate + bevist-forælder-eksklusion + patrilineær køns-gate (bruger-beslutning).
  Proveniens pr. person; grad-splittet ordlyd ('ingen forbindelse angivet' aldrig som barn-claim).
  Fable-agent-eksploreret (4 optioner) → Option 1. Data-fit bekræftet mod prod.
- **Authoring (redaktion):** markér/opdatér/fjern med grad + kilde via `submitChange`/`setPending`
  (dry-run/LIVE, fortrydbar change_set). `markerForaeldreUkendt`-art + `sletOplysning` til fjern.
  Web `ForaeldreUkendtControl` + mobil person-editor-kontrol. `fetchForaeldreUkendtMarkering`-læser.
- **Kvalitet:** TDD, byte-identisk delt kerne (paritets-test på `buildGenCoords`/`buildParentsUnknown`/
  `columnLabel`/`columnGen`/`buildDirection`/`buildBidirectionalColumns`/`unknownParentRing`),
  4-agent `/simplify`-pass (5 fund anvendt). **web 231/231 + mobil 328/328 + tsc + build grønne.**
- **UDESTÅR:** empirisk verifikation mod prod (markér én reel klynge via §6-query + redaktør-UI, se
  ringen rendere) — kræver prod-adgang/redaktør-login. Dual-review + merge.

## Datafix: person 1 fejlagtigt "gift med" eget barnebarn person 104 (2026-07-06)

Bruger opdagede at person 1 (Gottschalk von Reventlow, 1. slægtled, linje I) stod registreret som
"gift med" person 104 (Hartwich, 3. slægtled — Gottschalks barnebarn via person 82) i familie 74.
Undersøgt og bekræftet: en loader-fejl fra den oprindelige DAA-indlæsning (familie 74 havde ingen
`change_event`-historik, dvs. aldrig rørt af redaktør siden) — samme fejlklasse som de tidligere
"spøgelses-union"-fund, men IKKE en af de allerede oprydede (change_sets 3-7). Bogteksten for
Hartwich siger "Gift med NN" (ukendt hustru); intet sted nævnes Gottschalk. Iwan (person 44,
familie 74's barn) kaldes gentagne gange "søn af ridderen Hartwich von Reventlow" — aldrig
Gottschalk.

**Rettet mod prod** via en manuelt forfattet, fortrydbar `change_set` (id 30): fjernede person 1
som partner i familie 74 (`DELETE family_member WHERE family_id=74 AND person_id=1 AND
rolle='partner'`), efterlader Hartwich (104) som eneste partner + Iwan (44) som barn — matcher
det etablerede enkelt-partner-mønster for ukendt ægtefælle (7 lignende tilfælde findes allerede
i basen, inkl. Hartwichs egen union med sin far). Verificeret: ingen flere spøgelse-par tilbage
(bred søgning på partner-par ≥2 slægtled fra hinanden i samme linje — ikke udtømmende, fanger
ikke tværlinje-tilfælde).

**Opfølgning noteret i `claude.md` §9:** redaktøren har stadig ingen flade til at rette den slags
fejl selv — denne rettelse krævede direkte SQL. Se også separat bug-rapport: mobilapp crasher ved
åbning af person i redaktør-delen (urapporteret root cause).

## Konto-bogmærker: dual-review 22 af IMPLEMENTERINGEN + 4 fund rettet (2026-07-06)

Efter skive 1-6 (nedenfor) kørt en ANDEN dual-review-cyklus (Claude+Codex) — denne gang af den
faktiske KODE, ikke spec'en (spec allerede dual-reviewet, review 21). Fandt og rettede:

- **H1:** mobil `count` var `idsList.length` (ikke session-gated) → viste stale badge-tal efter
  log-ud selvom `ids`/`has()` korrekt gik tomme. Fix: `count: ids.size`.
- **N1 (HIGH):** web's `useBookmarks(session ? {userId} : null, ...)` byggede et NYT objekt-
  literal hver render → ustabil effekt-dependency → gentaget refetch på HVER render. Fix: begge
  hooks (web+mobil) tager nu `userId: string | null` (primitiv, stabil) i stedet for et
  session-objekt.
- **M1:** hurtig dobbelt-toggle af samme id kunne race'e (add+remove krydsende, out-of-order
  netværkssvar). Fix: `toggle` ignorerer gentaget tryk mens id'et allerede er in-flight.
- **N3:** web-login manglede busy-guard (dobbelt-klik → overlappende `signIn`-kald) + rejection-
  handler på `currentSession()`. Begge rettet.
- **N2 (recalibreret MEDIUM):** ingen bruger-nøglet rydning af bogmærke-listen ved brugerskift.
  Reconcile-verifikation bekræftede RLS forhindrer reel cross-account data-korruption (skrivninger
  scopes altid til `auth.uid()` server-side — kun en misvisende UI-glimt, og scenariet er slet
  ikke nået via appens faktiske UI-flow, som ikke understøtter konto-skift uden log-ud). Mitigeret
  med ryd-ved-reelt-brugerskift.
- **Selv-fanget regression under fixet:** den FØRSTE N2-mitigering (ubetinget `setIdsList([])` i
  effekt-kroppen) genintroducerede en uendelig render-loop identisk med den allerede-hærdede
  udlogget-gren (fanget af `vitest` der hang/OOM'ede) — rettet med en ref-sporet "kun ved reelt
  brugerskift"-betingelse.
- **Bevidst udskudt (H2):** mobil har to uafhængige `useBookmarks`-instanser (Home-skærm +
  Bogmærker-skærm) uden delt state — fjern et bogmærke på Bogmærker-skærmen opdaterer ikke Home's
  badge/ikoner før genmontering. Codex' reconcile bekræftede et ægte fix kræver en ny Zustand-
  bogmærke-slice, ikke en hurtig patch — udskudt til separat brainstorm/plan (jf. projektets
  konvention for ikke-trivielle arkitektur-ændringer). Se `docs/reviews/22-*.md`.
- **Verificeret:** web 23/23 filer, 208/208 tests (2 nye); mobil 23/23 filer, 337/337 tests,
  tsc+eslint rene.

## Konto-bogmærker — login-eksklusive, cross-device-synkroniserede bogmærker (web+mobile, branch feat/bogmaerker-konto, 2026-07-06)

Bogmærker opgraderet fra lokal PoC (AsyncStorage/localStorage) til et **login-eksklusivt gode**
lagret i Supabase — følger brugeren på tværs af web og mobil. Ingen hybrid/merge-logik, ingen
offline-cache (bevidst PoC-afgrænsning, jf. spec 2026-07-06).

- **DB-lag:** ny `bookmark`-tabel (`user_id=auth.uid()` default, `person_id` FK ON DELETE CASCADE,
  unik `(user_id,person_id)`) + RLS (own-row select/insert/delete) + **eksplicit** `GRANT/REVOKE`
  (dual-review 21 N1 — Supabase auto-grant'er default-privilegier til anon/authenticated, RLS alene
  er ikke nok). Idempotent DDL (`schema.sql`+`db-migrations.sql`+`db-rls.sql`). Ny `db-verify.sql`
  Task 14: RLS-isolation, dublet-sikring, cascade, anon-blokering.
- **Empirisk fund under lokal test (ikke antaget):** anon har INGEN grant overhovedet på
  `bookmark` — et bart `SELECT` som anon rejser `permission denied`, ikke et tomt resultat (stærkere
  end RLS-alene-filtrering). Testens assertion rettet til at forvente `insufficient_privilege`.
- **Repository-lag (web+mobil):** `RemoteRepository` (Supabase-backet, erstatter lokal lagring) +
  auth-gated `useBookmarks(session, canon)`: udlogget → tom, `canSave:false`, `toggle` no-op;
  logget-ind → hent-ved-mount, optimistisk toggle m. **race-guard** (dual-review H2: en fokus-
  refetch klobrer ikke en igangværende skrivning). `person_id` sendes altid som **streng** til
  PostgREST (N2 — bigint > 2^53 korrumperes af `Number()`).
- **Web:** minimal login-session + modal tilføjet i den offentlige Folgesvend-læser (genbruger
  eksisterende `data/auth.ts`); alle bogmærke-gem-steder gates via `saveOrPrompt` (udlogget tap →
  login-modal, ikke stille no-op). Mobil havde allerede login (Konto-fanen) — kun wiring nødvendig.
- **Empirisk fund under web-test-kørsel (fanget FØR mobil-porten, undgået der fra start):** den
  udloggede gren kaldte `setIdsList([])` med en FRISK array-reference hver effekt-kørsel →
  kombineret med en ustabil `canon`-reference gav det en uendelig render-loop (OOM i test-
  runneren). Rettet med bail-safe funktionel updater; samme fix indbygget i mobil-porten fra start.
- **Mobil eslint-fund (React Compiler-lint, kun mobil har denne strenge config):** `pendingRef`
  skiftet fra `useMemo` til `useRef` (mutation af en useMemo-værdi er ikke tilladt); fjernede
  synkron `setState` i effekt-krop for udlogget-grenen (afledt i stedet for lagret+ryddet).
- **Test-scope-justering (empirisk afprøvet, ikke antaget):** `@testing-library/react-native@14`
  (react-native 0.85/react 19) virker ikke i dette repos jest-opsætning — selv en triviel
  `useState`-hook giver `renderHook() → { result: undefined }`. Afhængigheden droppet igen;
  mobil-testen dækker det renderer-uafhængige repository-lag (5 tests); hook-adfærd verificeret
  empirisk i iOS-simulatoren i stedet (web derimod har fuld `renderHook`-dækning, 10 tests).
- **Verificeret:** web tsc+vitest (23/23 filer, 206/206 tests) grøn; mobil tsc+eslint+jest (23/23
  filer, 337/337 tests) grøn; DB Task 14 grøn lokalt (frisk `daa_test`-genopbygning fra
  `schema.sql`+`db-migrations.sql`+`db-rls.sql`, ingen prod-berøring). iOS-simulator (idb): app
  booter uden crash, ingen badge udlogget, gem-ikon-tap→`/konto` (login-gate bekræftet), Bogmærker-
  skærm viser korrekt login-CTA.
- **Udestår:** DB-migrationen er **ikke anvendt mod prod** (kræver eksplicit bruger-godkendelse,
  git-gate). Fuld login+cross-device-persistens-verifikation kræver netværk (sim-fetch fejler,
  kendt begrænsning) — næste skridt er fysisk enhed (mobil) + browser (web) mod rigtig prod-konto.
  Se `docs/superpowers/{specs,plans}/2026-07-06-konto-bogmaerker*` + `docs/reviews/21-*`.

## Følgesvend v3 — forsidefeed, menu-drawer & bogmærker (mobile, branch feat/folgesvend-v3, 2026-07-05)

Mobil-appen bragt op til v3-designet (`Reventlow-folgesvend-v3.dc.html`). Tre nye elementer +
afgrænset visuel afstemning (sidstnævnte udestår). **Ingen backend-/model-ændringer** — feedet er
ren læsning ovenpå den eksisterende `Model`/`Aux`.

- **Forsidefeed (`data/buildFeed.ts`):** ren, deterministisk selector der udleder et redaktionelt
  `FeedCard[]` (9 korttyper: portrait/citat/gods/forbundet/slaegt/embede/jubilaeum/vaaben/samle).
  Portrait+citat i **disjunkt** hash-partition (ingen dobbelt-optræden); `today` injiceres
  (jubilæum = runde ≥100 år); per-kind `FEED_CAPS` før round-robin-`interleave`; `overrides`-krog
  til senere redaktionel kilde (hybrid-beslutning). 17 unit-tests.
- **Forside (`app/(tabs)/index.tsx`):** omskrevet til `FlatList`-feed + kollapsende hero +
  `HomeTopBar` (hamburger, brand-på-scroll, bogmærke-badge). `slaegt`-kort sætter `relA/relB` før
  `push('/relate')`. Den gamle nummererede 01–08-liste **flyttet ud** af forsiden.
- **Menu-drawer (`components/MenuDrawer.tsx`):** venstre slide-in (reanimated) m. slægt-header,
  nav-liste 01–08 (+ Bogmærker) og konto-footer.
- **Bogmærker (`lib/bookmarks.ts` + `app/bogmaerker.tsx`):** async AsyncStorage-lager + synkron
  render-state-hook (spejler web's person-kun kontrakt). Gem-ikon iff kort har `personId`.
- **Dual-review (Claude+Codex, `docs/reviews/20`):** 11 fund, alle empirisk verificeret mod koden
  og rettet i spec FØR implementering (bl.a. BM1 async-race, BM2 recollapse-miss, NEW1 forbundet-
  data findes ikke, NEW2 relate-slots). advisor-gate fangede `samle`-dødkode (nu wiret).
- **Verificeret:** tsc + eslint rene, **327 jest grønne** (305 eksisterende + 22 nye). **iOS-
  simulator mod SEED-data (idb):** feed renderer, hamburger→drawer, bogmærke-toggle→badge "1",
  **persistens over app-genstart**, Bogmærker-skærm — alle bekræftet empirisk. Krævede frisk
  native dev-client-build (`expo run:ios`) da den installerede binary var stale (manglede
  `react-native-webview` → `RNCWebViewModule`-crash ved boot; pre-eksisterende, ej vores kode).
- **Skive 5 (visuel afstemning):** iOS-sim-audit af eksisterende sub-skærme (Om slægten, Stamtræ,
  Slægtens våben, Persondetalje) mod v3-designet fandt dem **allerede pixel-tæt konforme** — de blev
  bygget til v3 i tidligere sessioner (delt `TopBar` + tokens). **Ingen substantielle ændringer nødvendige.**
  Godser/søg/slægtskab deler samme komponenter+afstamning (forventet konforme; endelig visuel pass
  bør ske på fysisk enhed mod live-data).
- **Udestår:** verifikation mod live-Supabase-data (sim-fetch fejler → SEED-fallback; kræver fysisk
  enhed, jf. memory `mobil-sim-rn-fetch-1005`) + merge/push. Se `docs/superpowers/{specs,plans}/2026-07-05-folgesvend-v3-*`.

## Generations-reparation af stamtræet — hul-reparation via slægtled (web+mobile, PROD-LIVE + merget, 2026-07-05)

Ny navigations-vej for de tidligste, ubeviste generationer: når aner-ringen i Kolonner-
stamtræet er tom (ingen bevist forælder), vises nu generations-naboerne fra samme linjes
forrige slægtled som **ubeviste kandidater** (stiplet/amber, "muligt slægtled"-tag,
slægtled-header, kuld-gruppering). Klik re-ankrer — skriver **aldrig** en kant.

- **Datalag (PROD-LIVE):** `segment.py` fanger nu bogens dobbelt-nummererede slægtled
  ("Første (tolvte)") → `slaegtled_lokal`/`slaegtled_gennem` + `kuld` på `person_external_id`
  (3 additive kolonner + trigger-hærdning så generation/kuld-UPDATE ikke regenererer
  `visning_*`). Deterministisk backfill (ingen LLM): `change_set 20` (fortrydbar),
  **591/591 lokal-dækning**, join på `(source_id, linje, nr)`, fail-closed source-valg,
  suffix-variant-assert, data-aware idempotens (overlever `--force-reset`), wiret reload-
  durabelt i `post_load_fixup.R` (subproces-isoleret). Conrad V-1=(1,12)/III-58=(12) valideret
  som founder-bro. Migration advisor-ren.
- **App-lag:** ren `buildGenCoords`/`previousAncestorGen` (founder-krydshop via `parent_lineage_id`,
  fail-closed) → parametriseret `genCoords` i den delte `buildDirection`-bygger (web `tree.ts` +
  mobil `selectors.ts`, byte-identisk). Source/lineage-scoped kandidat-match.
- **Proces:** 11 TDD-tasks m. per-task-review, 5× `/simplify`, samlet dual-review (Claude opus +
  Codex) → ingen Critical, write-invariant bekræftet af begge, 7 fund rettet (F1-F7) + re-review.
  web 189/189, mobil 304/304. Merget til main efter ren integration med geo-kort-UI-featuren.
- **v2 (dok. spec §12b):** founder-hop over flere linje-niveauer + active-line-kontekst for ring-valg
  (begge ureachable i nuværende single-source-data). **Udestår:** empirisk UI-verifikation
  (web-browser + mobil-enhed) mod live-data. Se `docs/superpowers/{specs,plans}/2026-07-05-generations-reparation*`.


## Mediehåndtering — Slice 0h: runtime-fix + slet/afkobl + objekt-foto (2026-07-05)

Tre ting i forlængelse af Slice 0g, udløst af brugerens egen prod-test af upload-featuren:

- **Reel bug fanget ved runtime-verifikation (rettet på begge platforme):** `submitChange`
  kaldte aldrig `red_bekraeft_media_upload` efter `red_upload_media` — uploads sad derfor
  fast som `upload_status='kladde'` for evigt (aldrig synlige efter gating). Brugeren
  uploadede 3 rigtige testbilleder (Conrad/Anna Sophie Reventlow-portrætter) mod prod, som
  afslørede fejlen; rettet, og de tre rækker flyttet til `'klar'` via det nu-virkende RPC-kald
  (ikke en rå UPDATE — change-log intakt). Præcis den slags fejl unit-tests ikke fanger, fordi
  `buildRpcCall` testes rent/netværksfrit og selve netværkskæden aldrig eksekveres af nogen test.
- **Slet/afkobl billede (bruger-anmodet):** to distinkte, bevidst forskellige handlinger.
  *Afkobl* ("Fjern") genbruger det eksisterende generiske `red_slet_relation`-RPC uændret —
  den sletter kun selve `afbildet`-relationen (+ evidens), rører hverken `media`-rækken eller
  Storage-bytes, så mediet kan stadig være tilknyttet andre. *Slet billede* er et nyt, lille
  RPC (`red_fjern_media`) der sætter `upload_status='fjernet'` — elegant fordi
  `media_rettigheder_ok` allerede kræver `upload_status='klar'`, så et fjernet billede
  automatisk forsvinder fra al anon/auth-synlighed uden ny RLS-politik, og `media` har
  allerede versionerings-triggeren (`trg_log_media`), så handlingen er gratis fortrydbar via
  den eksisterende redaktionelle historik. Storage-bytes røres aldrig → Supabases
  `storage.protect_delete()`-beskyttelse kommer aldrig i spil. En ægte hård sletning
  (fjerne bytes fra Storage) er bevidst IKKE eksponeret i redaktør-UI'et — forbliver en
  sjælden, manuel admin-handling.
- **Objekt-foto-upload (gods/våben):** samme upload/galleri-mønster som person-portrætter,
  nu også for `estate`/`coat_of_arms` via `red_upload_media`s eksisterende `p_objekt_type`-gren
  (fandtes allerede server-side, kun UI manglede). Web: ny delt `renderMateriale()` i
  `Redaktion.tsx` bruges af både person-editoren og `renderGenericEditor()` (estate/arms).
  Mobile: ingen generisk entitets-detail-editor findes endnu, så en bevidst minimal,
  selv-mærket "ikke en fuld editor"-skærm (`entitet/materiale.tsx`) blev tilføjet, nået via
  tappbare gods/våben-rækker i `entitet/[type].tsx`; galleri + upload-sheet delt med
  person-editoren via nye `MediaGallery`/`MediaUploadSheet`-komponenter.
- **Arbejde udført i separat worktree** (`.claude/worktrees/media-slet-objektfoto`,
  branch `feat/media-slet-objektfoto`) efter brugerens ønske.
- **`/simplify` (4 agenter parallelt) anvendt — 4 reelle fund, alle rettet:**
  (1) *simplification* — web's `run()` opdaterede kun objekt-editorens medie-refetch-
  betingelse til at inkludere de nye `fjernMedia`/`sletRelation`-arter, men glemte
  person-editorens parallelle `skipMedia`-betingelse (stadig kun `!== 'uploadMedia'`) — reelt
  fund, ikke bare stil: ville have efterladt et lige-fjernet billede synligt i galleriet.
  Rettet ved at udlede begge fra samme `mediaChanged`-boolean.
  (2) *reuse* — mobile duplikerede hele galleri-markup'en (thumb + status + Fjern/Slet-knapper)
  og tre style-objekter mellem person-editoren og den nye objekt-skærm, i stedet for at dele
  den som web gjorde via `renderMateriale`; udtrukket til en ny delt `MediaGallery`-komponent
  (og en `CenterMsg`-komponent, der samtidig lukkede en allerede-eksisterende 3-vejs
  duplikering af "Henter…/fejl"-beskeden på tværs af person-editor og entitetsliste).
  (3) *efficiency* — ingen fund (agenten bekræftede den nye `mediaFromRelPairs`-hale er en
  reel dedup, ikke ekstra I/O; de to nye `useEffect`'er er korrekt gensidigt udelukkende).
  (4) *altitude* — reelt datahazard: `red_bekraeft_media_upload`s ubetingede
  `UPDATE ... WHERE id=p_media_id` kunne i teorien genoplive en blødt-slettet
  (`'fjernet'`) række til `'klar'` igen ved et forsinket/gentaget bekræft-kald (ikke nået via
  nuværende app-flow, men RPC'et bør ikke være afhængigt af det). Hærdet med
  `AND upload_status <> 'fjernet'` i WHERE-klausulen, anvendt til prod via MCP samme dag.
  Mindre fund også rettet: hoistede en pr.-række-genberegnet konstant i mobile, og udtrak
  web's 3× gentagne `entity==='estate'||'arms'`-tjek til en delt `HAR_OBJEKT_MATERIALE`-Set
  (spejler mobiles `HAR_MATERIALE`). **Bevidst sprunget over:** en SQL-verify-test for
  `red_fjern_media`/guarden i `db-verify-media.sql` — filens etablerede mønster er specifikt
  scopet til RLS-tests uden redaktør-kontekst (`SET LOCAL ROLE anon/authenticated`); en
  RPC-kaldende test kræver JWT-claim-impersonering, som ikke passer den etablerede fil-kontrakt.
  tsc + 272/272 jest (mobile) + tsc + 155/155 vitest + build (web) alle grønne efter fixene.
- **Udestår:** samme kendte gap som Slice 0g — ingen automatiseret runtime-verifikation af
  selve slet/afkobl/objekt-foto-UI'en (ingen browser-driver/iOS-simulator-tap-værktøj i
  repo'et); "løse billeder"-admin-oversigt og rettigheds-workflow-UI (`red_set_media_rettigheder`)
  forbliver separate, ikke-startede opgaver.

## Mediehåndtering — Slice 0g: redaktør-upload porteret til web (2026-07-05)

Samme redaktør-portræt-upload som mobile (se ovenfor), nu også i web-arbejdsbordet
(`web/src/Redaktion.tsx`) — bruger-anmodet efter at have opdaget web kun havde en generisk
læse/forslag-"Medier"-fane, intet reelt upload. Browser-nativt: et `<input type="file">`s
`File`-objekt uploades direkte til `supabase.storage` (intet `expo-file-system`-ækvivalent
nødvendigt). Ny "Materiale"-sektion i person-editoren, ny `web/src/data/mediaUpload.ts`
(`buildStoragePath`/`performUpload`), ny `Change`-art `uploadMedia` i `redaktionWrite.ts`,
ny `fetchRedPersonMedia` i `redaktionRead.ts` (adskilt fra `data/media.ts`s offentlige,
RLS-begrænsede `fetchPersonMedia` — redaktøren skal se `kladde`/spærrede egne uploads).
- **Rolle-gating, web-specifikt:** web's skrive-lag har (modsat mobile) en rolle-baseret
  fallback til `red_suggest` for ikke-redaktion. Upload kan IKKE degradere til et forslag
  (intet ejerskab af fil-bytes) — gated to steder: UI'en skjuler knappen for ikke-redaktion,
  OG `submitChange` afviser eksplicit hvis kaldet alligevel ville route til `red_suggest`.
- **`/simplify` (4 vinkler) anvendt:** (1) reuse — mindre, accepteret duplikering af en
  5-linjers relations-query-form ift. `data/media.ts`s `fetchMediaByRelation` (sprunget over:
  ægte genbrug kræver at omstrukturere en delt, allerede-testet offentlig modul for
  marginal gevinst — samme afvejning som mobile allerede har); (2) simplification — foldede
  signering ind i `fetchRedPersonMedia` selv (som `media.ts`s eget `loadMediaItems`-mønster)
  i stedet for en separat `mediaUris`-state + `useEffect` med kun ét kaldested (mobile beholdt
  sin tilsvarende to-trins-opdeling, fordi `useMediaUris` der er en reelt genbrugt hook på
  tværs af flere skærme — web havde ingen sådan begrundelse); (3) efficiency — medie-refetch
  var føjet ind i den allerede eksisterende "genindlæs ALT efter enhver gemt ændring"-liste;
  nu kun ved en faktisk `uploadMedia`-ændring (ny `loadPerson(id, {skipMedia})`-parameter);
  (4) altitude — en `uploadMedia`-ændring der (fejlagtigt eller pga. rolle-skift) falder
  igennem til `red_suggest` ville serialisere et rå `File`-objekt til `'{}'` og rapportere
  falsk succes; `submitChange` afviser nu eksplicit før det kan ske (bekræftet: DB/RLS er
  den reelle autoritetsgrænse, UI-gaten er kun UX — statisk-import-valget for
  `mediaUpload.ts` blev også bekræftet korrekt, ingen native afhængigheder på web modsat mobile).
  tsc + 152/152 vitest + build alle grønne efter fixene.
- **Udestår:** samme som mobile — objekt-foto-upload-UI (estate/våben), og reel browser-
  runtime-verifikation (ingen browser-driver i repo'et, kun tsc/test/build).

## Mediehåndtering — Slice 0g: redaktør-upload (mobile, 2026-07-05)

Sidste stykke af Slice 0's "0f"-punkt: portræt-upload fra redaktør-person-editoren
(`mobile/src/app/redaktion/person/[id].tsx`). Nye dependencies `expo-image-picker`
(`~56.0.19`) + `expo-file-system` (`~56.0.8`), installeret via `npx expo install` —
begge SDK-56-versionerede docs læst FØR kode (mobile/AGENTS.md-mandat); brugte SDK 56's
nye `File`-klasse (`.bytes()`) i stedet for den deprecated `readAsStringAsync`.
- **Ny `mobile/src/lib/mediaUpload.ts`:** `pickImage` (biblioteksvælger m. tilladelses-
  request), `readFileBytes`, `buildStoragePath`, `performUpload` (læs+upload som én enhed).
- **`redaktionWrite.ts`:** ny `Change`-art `uploadMedia` → `red_upload_media`. To-fase-upload
  (bytes til Storage FØR RPC'en) sker KUN i LIVE, aldrig dry-run — ellers ville "Forhåndsvis"
  efterlade en rigtig fil i den private bucket. Dynamisk `import('../lib/mediaUpload')` i
  `submitChange` holder `buildRpcCall` netværks-/native-fri til test.
- **`redaktionRead.ts`:** ny `fetchPersonMedia` (relation→media-join, samme mønster som
  `fetchPersonFamilie`).
- **UI:** ny "Materiale"-sektion + `MediaUploadSheet` i person-editoren (vælg billede →
  slags/titel/må-publiceres → delt dry-run/LIVE-flow via `SkrivePreviewSheet`).
- **`/simplify` (4 vinkler) anvendt:** (1) `fetchPersonMedia`s media-query manglede
  `getAll`-wrapping ift. filens etablerede mønster — rettet; (2) `PersonMedia.relationId`
  blev beregnet men aldrig brugt af UI'en — fjernet (YAGNI, tilføjes når en slet/erstat-
  handling faktisk får brug for den); (3) `refreshMedia()` kørte ubetinget efter ENHVER
  gemt ændring i editoren, ikke kun upload — nu gated på `pending?.art === 'uploadMedia'`;
  (4) selve Storage-uploadet sad i `redaktionWrite.ts` og læste stien tilbage fra det
  allerede-byggede (utypede) RPC-args-objekt — flyttet til `mediaUpload.ts`s nye
  `performUpload`, kaldt direkte med payload-værdierne. Sprunget over: en 3. kopi af
  pille-vælger-mønstret (ville kræve refaktorering af BarnSheet/UnionTypeSheet uden for
  diffen); objekt-foto-grenen i `buildRpcCall` (ingen UI-kalder endnu, men RPC'en
  understøtter det og der er en unit-test — bevidst dækning, ikke spekulativ kode).
  tsc + 269/269 jest + lint alle grønne efter fixene.
- **Udestår:** objekt-foto-upload-UI (estate/coat_of_arms, samme RPC-gren findes allerede);
  runtime-verifikation på device/simulator (ingen fysisk enhed tilgængelig i denne session).

## Mediehåndtering — DB/RLS-lag LIVE i prod (Slice 0, 2026-07-05)

Kørt direkte mod prod (`xjnvdhajfyrcytatnzos`) via Supabase MCP fra en maskine med adgang —
runbook-Trin 1+2 anvendt som to navngivne, sporede migrationer (`mediehaandtering_slice0_schema`,
`mediehaandtering_slice0_rls`), verbatim delta fra `db-migrations.sql`/`db-rls.sql`. `media`-bucket
(privat) var allerede oprettet af brugeren (Trin 3).
- **Verificeret:** Task 8 (afbildet-gating) + Task 12 (rettigheds-gating + storage-mapping) kørt
  direkte mod prod med negative test-ID'er, selv-oprydende — begge OK.
- **Task 12b (storage.objects-politikker) IKKE funktionelt afprøvet mod prod:** kræver
  `SET LOCAL storage.allow_delete_query='true'` for at omgå Supabases `protect_delete`-trigger
  til testens egen oprydning — auto-mode-klassifikatoren blokerede dette korrekt som en
  sikkerheds-bypass på en produktions-tabel, i tråd med brugerens eksplicitte forsigtigheds-krav.
  Verificeret i stedet **read-only** via `pg_policies`: alle 5 forventede politikker
  (`media_obj_anon/auth/redaktion/write/update/delete`) findes med nøjagtig de `qual`/`with_check`-
  udtryk koden tilsigter. Reel end-to-end-funktionstest af disse politikker udestår (kræver enten
  brugerens eget samtykke til delete-bypasset, eller en rigtig fil uploadet via Storage API/UI).
- **`get_advisors(security)` efter DDL:** 8 nye medie-funktioner udløser samme
  "SECURITY DEFINER public-exec"-advarsel som 32 allerede eksisterende `red_*`-RPC'er (etableret
  mønster — adgang håndhæves internt via `current_rolle()`, ikke via GRANT). Ingen nye huller.
- **Ny divergens fundet lokal-stub vs. rigtig Supabase:** vores lokale Postgres-testklynge
  (bootstrap.sql) har ingen `storage.protect_delete()`-trigger, så `db-verify-media.sql`s Task 12b
  passerede lokalt men ville fejle uændret mod rigtig Supabase. Filen er endnu ikke opdateret til
  at håndtere dette (kræver en bevidst bruger-beslutning om delete-bypasset, ikke en stille fix).

## Mediehåndtering — code-review-fixes (Slice 0, 2026-07-04)

High-effort `/code-review` (5 finder-vinkler) på Slice 0-diff'en fandt 10 fund; alle rettet:
- **#1 (sikkerhed) `red_upload_media`:** afviser nu `p_objekt_type='person'` i objekt-grenen —
  ellers kunne en omvendt `media→person afbildet`-relation omgå GDPR-gatingen (schema.sql + db-migrations.sql).
- **#2 (web fejl-isolation):** `fetchPersonMedia`/`fetchObjectMedia` er nu selv-tolerante (try/catch → []),
  så en medie-/storage-fejl ikke længere blanker hele personpanelet/våben-listen.
- **#3 (portræt):** `pickPortrait` normaliserer `slags` (case/trim) i web+mobile; mobile vælger portræt
  blandt *signerbare* medier (ingen permanent placeholder når første medie fejler signering).
- **#4 (test):** ny `db-verify.sql` Task 12b udøver de faktiske `storage.objects`-politikker under
  `SET LOCAL ROLE anon`/`authenticated` (ikke kun helper-kald) — springes over uden `media`-bucket.
- **#5 (efficiency):** `fetchObjectMedia` batchet til array-signatur (`Map<objektId, MediaItem[]>`);
  `fetchArms` gik fra N×3 til én relation+media+sign-triade.
- **#6 (session-læk):** mobile signed-URL-cache ryddes ved `onAuthStateChange`.
- **#7:** `red_opret_media` giver domæne-fejl ved sha256-dublet (ikke rå 23505).
- **#8:** `ArmsView` vælger første *signerbare* billede (ikke blindt `media[0]`) + fast .82-aspekt.
- **#9:** `media_obj_update`-storage-politik fik `WITH CHECK`.
- **#10 (vocab):** `licens`/`kildehenvisning`/`gengivelsestilladelse` (faktatype), `rettighedshaver` (rolle),
  nyt `media_rettigheder_status`-scheme tilføjet `vocab.json`.
- **Ryddet/afvist:** id-alloc-race (accepteret husstil), RPC schema↔migrations-mirror (konvention),
  transient-placeholder (selv-heler), "eksisterende billeder forsvinder" (media-tabel tom i prod + fail-closed tilsigtet).
- **Re-verificeret:** hele SQL-kæden lokalt (Task 8/12/12b grønne, #1+#7-guards rejser); web tsc+147+build;
  mobile tsc+264 (4 nye pickPortrait-tests).

**`/simplify` (4 vinkler) oven på fixes:**
- **Altitude (sikkerhed):** GDPR-retnings-guarden løftet ind i `red_relation`-primitiven (afvis
  `afbildet` med person på objekt-siden) — lukker fail-open for ALLE kaldere, ikke kun `red_upload_media`.
  De to gating-dimensioner komponeret i `media_synlig_anon`/`media_synlig_auth`, delt af media-tabel-
  OG storage.objects-politikkerne (ingen split-brain-drift, ét objekt→media-opslag pr. række).
- **Reuse/efficiency:** web `signPaths` fik mobile's TTL-cache + `onAuthStateChange`-clear (ingen
  re-signering/billed-re-download pr. visning); `MediaThumb` flyttet til `components/primitives.tsx`.
- **Altitude/simplification:** web `fetchPersonMedia`/`fetchObjectMedia` samlet i én retnings-parametriseret
  `fetchMediaByRelation`; mobile signable/portræt/galleri konsolideret i en `usePersonMedia`-model-hook;
  `firstSignable`-helper delt i ArmsView; `red_set_media_rettigheder` 3 IF-blokke → én VALUES-løkke;
  `fetchEstateInfo` kører nu medie-fetchen samtidig med narrativ/sted-kæden.
- **Skippet (bevidst):** stribet-placeholder-ekstraktion (præeksisterende), `red_upload_media`-dobbelt-gate
  (tilsigtet fail-fast + change-set-label), render-memoization (negligibel ved nuv. datastørrelser).

## Mediehåndtering — DB/Storage/RLS-fundament (Slice 0, 2026-07-04)

Første skive af den samlede medie-design-session (`CLAUDE.md` §6.6/§9, udskudt "samlet,
ikke stykvis"). **Kun DB-laget** i denne omgang; frontend (portræt/objekt-visning,
redaktør-upload) og bulk-import følger som senere slices. Fuld plan i
`docs/superpowers/plans/2026-07-04-mediehaandtering.md`.

**Designprincip:** fysisk byte-metadata → kolonner på `media` (eneste legitime "fedning"
af den tynde tabel); semantiske links → `relation` (`afbildet` findes allerede);
rettigheds-*dokumentation* → `fact` på `subjekt_type='media'`; publikations-*gating* →
kontrol-kolonne (som `person.levende`/`privat`).

- **`media`-skema udvidet** (`schema.sql` + idempotente ALTER'er i `db-migrations.sql`):
  storage-metadata (`bucket`, `storage_path`, `mime_type`, `byte_size`, `bredde`, `hoejde`,
  `sha256`, `original_filnavn`, `upload_status`) + unikke indekser på `(bucket,storage_path)`
  og `sha256`. To-fase upload: række (`'kladde'`) → bytes → `'klar'`.
- **Rettigheder fra dag 1:** `maa_publiceres BOOLEAN DEFAULT false` (fail-closed) +
  `rettigheder_status`. To **ortogonale** gating-dimensioner: GDPR-person-gating (fandtes)
  + ny copyright/publikations-gating. Begge skal opfyldes for offentlig visning.
- **RLS** (`db-rls.sql`): nye SECURITY DEFINER-helpers `media_rettigheder_ok` (kun
  `maa_publiceres AND upload_status='klar'`) + `media_id_for_object` (objekt→media-mapping).
  De tre `media`-tabel-politikker udvidet med rettigheds-gating. **Én privat bucket `media`**
  + `storage.objects`-politikker der spejler media-stakken (signed URLs, ikke offentlige URLs
  — begge dimensioner er tilbagekaldelige). Forældreløst objekt → fail-closed.
- **RPC'er** (`schema.sql` + `db-migrations.sql`, husstil: SECURITY DEFINER, `current_rolle`-
  gate, `begin_change_set`, `max(id)+1`): `red_opret_media`, `red_bekraeft_media_upload`,
  `red_upload_media` (media + `afbildet`-relation i ét change_set via re-entrant B7),
  `red_set_media_rettigheder`. Tilknytning af eksisterende media = eksisterende `red_relation`.
- **Verify:** `db-verify.sql` Task 8 opdateret (fixturer sætter rettigheds-felter så afbildet-
  testen isoleres) + ny **Task 12** (rettigheds-gating + storage-mapping). **Empirisk verificeret
  LOKALT:** hele kæden `schema → db-migrations → db-rls → db-verify` kørt mod en frisk Postgres 16
  med Supabase-stub (roller/auth/storage); begge medie-tasks grønne under faktisk RLS (rolle `anon`).
- **Udestår (bruger-gatet):** anvendelse til prod (migration + `db-rls.sql` + bucket-oprettelse);
  vocab-seed for rig rettigheds-dokumentation (Slice 1); redaktør-upload (Slice 0g).

**Frontend read-path (web + mobile, samme session):**
- **Web** (`web/src/data/media.ts` nyt): signed-URL-helper (`createSignedUrls`, batch, 600s) +
  `fetchPersonMedia` (person→media afbildet) + `fetchObjectMedia` (media→objekt). `fetchPersonDetail`
  udvidet med `media`; portræt i `DetailPanel` (fald tilbage til placeholder) + "Materiale"-galleri;
  objekt-billeder i `ArmsView` (hovedvåben + varianter) og `EstatesView`. Delt `MediaThumb`
  (klik → fuld signed URL i ny fane). tsc + 147 web-tests + build grønne.
- **Mobile** (`mobile/src/lib/media.ts` nyt): `signPaths` (TTL-cache) + `useMediaUris`-hook +
  `pickPortrait`. **Rettet latent bug:** `buildAux.mediaBy` nøglede på `m.person_id` (kolonne findes
  ikke → altid tom); nu koblet via relation person→media `afbildet` (2 nye enheds-tests).
  Header-portræt + Materiale-galleri (`expo-image`, allerede installeret) i `person/[id].tsx`.
  tsc + 260 mobile-tests grønne. **Empirisk device-verifikation udskudt** (RN-sim-fetch-bug,
  se memory `mobil-sim-rn-fetch-1005`) — kræver prod-migreret base + fysisk enhed.

## TNG-analyse opfølgning + backlog-prioritering (2026-07-03)

Fuld gennemgang af `jr_tng_reventlow.sql` (alle 37 `CREATE TABLE`-blokke + reelle
rækketal via quote-aware parsing, ikke kun stikprøver som juni-analysen). Nye fund
tilføjet som §7 i `docs/tng-reventlow-analyse.md` (git-ignoreret, levende-data):
foto-regionmarkering/albums/event-scoped medielink (46/5/119 reelt brugte rækker),
`frel`/`mrel` er per-forælder ikke pr. familie (44 reelle adopted/foster-rækker),
gemte rapporter reelt brugt 193 gange, finkornet TNG-rettighedsmodel som RLS-
reference. Status opdateret: barn-rolle-vokabular, `person.privat` og
`citation.citat_tekst/citat_dato` (alle fra juni-analysen) er allerede rettet i
schema.sql.

**Bruger-prioritering (§8):** DNA **afvist** (ikke udskudt). Foto/medie-rigdom
**udskudt samlet** til én fælles design-session (ikke stykvis). Gemte rapporter/
smart-lister = **næste fokus**. Navnepartikel ("von"/"af") udskudt. **Nyt,
ikke-designet krav rejst i samme samtale:** flersproget stamtræ (tysk/svensk/norsk/
engelsk) — kræver egen brainstorm om UI-i18n vs. indholds-i18n og hvor oversættelse
lander i evidenslaget/`narrative`. Se `docs/decisions.md` + `CLAUDE.md` §9.

Ingen kodeændringer denne session — kun dokumentation/prioritering.

## Flere narrativer pr. person — udgave-nøglede narrativer (DB + web + mobile, 2026-07-03)

En person kan nu bære **én biografi pr. DAA-udgave** (`source`) i stedet for præcis én. Spec +
dual-review + plan i `docs/superpowers/{specs,plans}/2026-07-03-*` og `docs/reviews/18-*`.
Implementeret på feature-branch `feat/flere-narrativer-per-person`; **prod-cutover udskudt** til
koordineret merge + web-deploy (RPC-DROP er en cross-client breaking change — se decisions).

**DB.** `red_upsert_narrativ` nøgles nu på `(subjekt_type, subjekt_id, source_id)` (var: første
række by id). Ny additiv `source.aar SMALLINT` bærer udgave-kronologi (source-id ≠ kronologi, og
`source.udgave` er upålidelig fritekst). `red_opret_kilde` udvidet med `p_aar`. Gamle 4-arg-
signaturer droppes eksplicit (undgår PostgREST-overload-tvetydighed). `side = COALESCE(p_side, side)`
så en udeladt side ikke slettes. Tabellen selv var uændret (flere rækker pr. person var altid lovligt).
Verificeret lokalt mod `daa_test`-prod-kopi: to udgaver = to rækker, re-upsert bevarer side,
**fortryd er per narrativ-id** (fortryd af udgave B lader udgave A urørt), 4-arg back-compat.

**Delt selector.** `pickPreferredBio` (ren, spejlet identisk i web+mobile) vælger den foretrukne
offentlige biografi pr. subjekt: `aar DESC NULLS LAST, source_id DESC, narrative_id DESC`, filtreret
til `slags='DAA-udgave'` (ingen vilkårlig TNG-stub-fallback). Bruges af begge læsere.

**Web-redaktør.** Udgave-faner under "Narrativ · biografi" + "+ Ny udgave" (vælg eksisterende kilde
eller opret DAA-udgave). textarea/privat/side binder til aktiv udgave; Gem sender `p_source_id`.

**Mobil-redaktør (minimal, obligatorisk).** Read henter `source_id`, Gem sender `p_source_id`
(default 1) → knækker ikke af RPC-DROP. Single-narrativ-UI bevaret; faner er follow-up.

**Læsere.** Web `public.ts` + mobil `load.ts` vælger foretrukne DAA-udgave pr. medlem/person via
`pickPreferredBio` (deterministisk, i stedet for "første by id"/"første mødte"). Adfærd uændret i
dag (alle 591 narrativer = DAA source 1). Cross-medlem-concat (web founder-først) urørt.

**Tests:** web 124/124 (+`pickPreferredBio`, `mapNarrativer`, arg-buildere inkl. `opretKilde`),
mobil 257/257, tsc + build grønne. DB verificeret mod lokal prod-kopi + skema-shape-asserts i
`db-verify.sql`. FK-embed-formen (objekt, ikke array) bekræftet mod eksisterende prod-kode
(`joinEvidence`'s `citation→source(titel)`).

**Udestår (bevidst):** (1) **Prod-cutover** — migrationerne er kun kørt mod lokal `daa_test`; den
rigtige `DROP`-transition (gammel 4-arg → 6-arg) fyrer først ved koordineret merge + web-deploy.
(2) **Udgave-byline i læseren** er udskudt (source-metadata dropfiltreres i `public.ts`/`load.ts`;
kun værdi ved >1 udgave). Se spec §6.

## Redaktør: klikbar familie-navigation + fødsels/dødsår (web+mobile, 2026-07-03)

Redaktør-familieoversigten kan nu **navigeres** og viser mere kontekst. Merget til `main`
(`bffdfc2`) + pushet.

**Navigation.** Partnere, børn og forældre i familie-sektionen er nu klikbare og åbner den
pågældende persons redaktør-flade. Web: `setRecordId` (samme flade); mobile: `router.push`
(ny editor-skærm) — sidstnævnte genbruger nøjagtig `PersonRad`-primitiven der allerede drev
forældre-navigation. Ugemte narrativ-edits kasseres stille ved navigation, bevidst identisk med
person-listens eksisterende adfærd.

**Fødsels/dødsår.** Børn (og partnere) viser nu årstal i oversigten. Kilden er den allerede
loadede `model.byId[pid].years` (samme cache som navne-opslaget) — **ingen ekstra DB-query**.
Nyt `aar`-felt tilføjet `FamilieBarn`/`FamiliePartner` i read-laget (`mapFamilieRows`), spejlet
web+mobile for at holde "hold i sync"-kontrakten.

**Modellen urørt:** navigation er ren læsning; edit/slet gik i forvejen gennem de append-baserede /
fortrydbare `red_*`-RPC'er. Ingen invariant-brud.

**Verifikation:** web 112/112 + mobile 249/249 tests + tsc grønne; web build ok; ny
`redaktionRead.test.ts` (web) + opdateret mobil-test dækker år-propagering. iOS-simulator-
runtime-verifikation **udskudt til fysisk enhed** pga. et RN-fetch-miljøbug på simulatoren
(-1005 "network connection was lost" mens host-curl + sim-Safari når Supabase fint) — ikke en
fejl i ændringen. Se memory `mobil-sim-rn-fetch-1005`.

## TNG-QA Etape 3+4 + spøgelses-union-oprydning (2026-07-03)

Adresserede TNG-QA-rapportens 5 dato-uenigheder (Etape 3) + 10 manglende links (Etape 4).
Undervejs afdækkedes en **systematisk spøgelses-union-fejl** i data.

**Etape 3 — vores datoer stod fast (change_set 3):** alle 5 dato-uenigheder blev adjudikeret mod
DAA-kilden (narrativen) — vores `date_raw` matcher bogen i alle 5; TNG havde fejlene (1-10 år). I
stedet for korrektion blev TNG oprettet som `source` (id 2) + TNG's 5 datoer loadet som
**konkurrerende assertions** på død-fakta, med vores konklusion uændret blåstemplet (evidenslag §1).

**Etape 4 — 8/10 falske positiver:** V-1/IV-1's "manglende far" fandtes allerede via samme_som;
V-56/V-95 var allerede ægtefæller; QA-pipelinen traverserer bare ikke samme_som/stub-dubletter.
Reelt: **V-121-dedup** (change_set 4 — ægtefælle-stub 826 = samme som V-114/409, intra-slægt-ægteskab)
+ **I-103-grenen** var strukturelt ødelagt.

**I-103-gren-reparation (change_set 5):** loaderen havde skabt spøgelses-unioner mellem I-103 og hans
far (I-97) + 3 sønner, efterladt 10 børn (I-109-118) forældreløse, og moderen uoprettet. Bogen: "Gift
1673 med Maria Elisabeth von Buchwaldt til Tresdorf ... 10 børn". Genopbyggede fam 4 (bar det ægte
vielse-1673-fakta): oprettede Maria Elisabeth, tilknyttede de 10 børn, slettede 3 spøgelses-unioner.

**Spøgelses-union-oprydning (change_sets 6+7):** systematisk scan fandt **26 barnløse unioner** hvor et
barn var fejl-"gift" med sin egen far/ane (fx I-19 Johann m. far I-11; I-12/13/15 m. progenitoren I-1).
11 direkte-forælder + 15 ane-spøgelser slettet. Diskriminator: barnløs + begge interne + **navn≠ref**
(se nedenfor). Én kryds-linje-union (fam 11, I-112 m. III-79 Hinrich) bekræftet ÆGTE af bruger, bevaret.

**Rodårsag (dokumenteret, endnu ikke rettet i loader):** spøgelserne opstår når et barns mor-grupperings-
heading ("med X (se nr. Y)") bliver til en fake-`aegteskab` hvor `partner_navn` (moderen) og
`partner_ekstern_ref` ("se nr. Y" → en ane) er UENIGE; `load_daa.R` (~l.280) linker ref'en og ignorerer
navnet → barn "gift" med ane. **Guard (næste skridt):** afvis intern-ref-link når navnet ikke matcher
`partner_navn`. Et reload gen-skaber ellers alle 26 spøgelser. Alle 7 change_sets er fortrydbare.

## Børn af flergifte forældre knyttet til korrekt union (2026-07-03)

Loaderen hang tidligere ALLE børn af en flergift forælder på forælderens FØRSTE union
(`load_daa.R`, `fam <- fams[[1]]`), så børn af 2./3./4. ægteskab blev fejl-tilknyttet 1.
ægteskab. Generelt problem: 20 flergifte forældre, 65 børn berørt — fx alle Conrad de
Reventlows 10 andet-ægteskabs-børn (inkl. dronning Anna Sophie) lå på Anna Margaretha Gabel
i stedet for Sophia Amalia Hahn. Dataene til at rette det lå der hele tiden i hvert barns
`aegteskab_kontekst`.

**Loader (`load_helpers.R` + `load_daa.R`):** delt DB-fri matcher `match_barn_union()` — barnets
`aegteskab_kontekst` → rette union; partnernavn primær anker, ordenstal kryds-tjek, NA ved
uenighed/ukendt partner (gætter aldrig). Wired i child-loop via `recmap` (nøgle→rec); kun ved
2+ ægteskaber; uafklarede parkeres på partnerløs union frem for fejl-link. 34 testthat-tests.
Eksekveret write-frit mod alle 591 records via `--dry-run` (parkerede præcis 1: III-85).

**Prod-data (`fix_boern_multi_union.R`, samme matcher):** 64 børn flyttet, 1 parkeret, i ét
`change_set` (id 1, fortrydbart via `red_fortryd_change_set(1)`); idempotens-guard. Verificeret:
Conrad Gabel 6 / Hahn 10; 132 change-events (64×2+2+2 → intet barn tabt); kun family/family_member
berørt; acceptance-gate grøn (Anna Sophie nu på Hahn).

**III-85 (Detlef) — efterfølgende løst (`change_set 2`):** den automatiske parkering var her
et falsk-negativt. `aegteskab_kontekst` var en ekstraktionsfejl (indeholdt en fremmed persons
ægteskab "Margaretha von Rumohr"; Detlef døde som spæd og var aldrig gift). Bogens tekst: "af
første ægteskab med Catharina von Brockdorff" — moderen ER Brockdorff (Friedrichs 1. ægteskab).
Flyttet tilbage til fam 175 + park-union 380 slettet (`red_fortryd_change_set(2)`); kildefeltet i
`clean-v2.json` rettet så reload rammer rigtigt (matcher: idx 1 via begge). Læring: parkering
beskytter mod falske påstande, men et menneske med kilden er facittet.

## Redaktør-web-cohesion: v2-header + person-browse (2026-07-03)

Bragte redaktør-fladen (`web/`) i tråd med publikums-web-v2 (Følgesvend). Committet `91b7797` på
`feat/samme-som-collapse`; header-ændringerne ført både i design-mockuppen og den kørende app.

**Header (`design/project/Reventlow-redaktion.dc.html` + `web/src/Redaktion.tsx`):** DAF-logo-lockup +
"Danmarks Adels Aarbog" + mono "Redaktion · Dansk Adels Forening" (erstatter R-firkant + "Redaktion ·
Reventlow"); slægt-chip m. crest-ring + "Reventlow ▾" (verbatim fra web-v2); header-mål 66px/gap 22/
padding 0 26px; mockup-link "Åbn publikumsvisning" → web-v2 (v1→v2).

**Person-liste (spejler Følgesvend §9.1/§9.2):** A–Å grupperet liste + alfabet-hop, sortér navn/fødeår
(`RedPerson.born`, aldrig dødsår), linje-filter som chips fra `model.lineage` (filtrerer KUN listen —
redaktør har intet stamtræ at hoppe fokus i). `buildBrowse` generaliseret strukturelt (`BrowsePerson`)
så samme testede motor driver både `ModelPerson` og `RedPerson` via et `name`-alias; id-rummene flugter
fordi redaktør-modellen loades `collapse:false`. Ikke-person-entiteter beholder den flade søgeliste.

**/simplify (4 parallelle agenter):** `personBrowse` gated til person-entiteten (ellers null — sparer en
900+-personers browse ved hvert tastetryk under andre entiteter); to næsten-ens række-renderere gen-forenet
til én `listRow`-helper; `browseInput`-memo inlinet; memo-dep smalnet til `lineage.byPerson`. Udskudt (uden
for diff): udtræk delt `LinjeChip`/`<BrowseControls>` på tværs af Følgesvend+Redaktion.

**Verifikation:** `tsc` rent · 94/94 web-tests (18 browse) · prod-build OK. **Ikke** visuelt/runtime-verificeret
i browser (ingen browser-driver i repo'et).

## Redaktionel samme_som-linking implementeret + DB live i prod (2026-07-02)

Redaktør-funktion til at markere to `person`-poster som samme fysiske person (producenten til det
allerede-live collapse). Fuld cyklus: brainstorm → 3× Codex-review (design+spec) → 7-task TDD-impl → /simplify.

**DB (LIVE i prod, ende-til-ende-verificeret):** `enforce_samme_som_invariants`-**trigger** (BEFORE INSERT
på `relation`) håndhæver graf-invarianterne (self-link, unik sink/ingen multi-sink, ingen re-root) for ALLE
insert-veje — ikke kun RPC'en (Codex-3-fund: en RPC-lokal check kan omgås af `red_relation`/undo/load/manuel).
`red_samme_som` (evidens-komplet wrapper: relation+assertion+afklaret-conclusion, advisory-lås, idempotent) +
`red_fjern_samme_som` (komplet evidens-slet via delt `_delete_relation_evidence`-helper) + `red_relation`
afviser `rolle='samme_som'`. Anvendt via MCP `apply_migration`; verificeret mod prod med rollback-DO-blok
(opret/idempotens/G3-multi-sink/self-link/fjern) — 0 muterede rækker, 2 rigtige links intakte.

**App (web+mobile spejlet, testet):** `sammeSom`/`fjernSammeSom` Change-arter, `fetchSammeSomLinks` +
retnings-mapping, rådgivende `previewSammeSom` (kører collapse med hypotetisk kant), og UI i person-editorens
relations-sektion ("Samme person"-liste + fjern + "Marker som samme person" → PersonPicker → retningsvælger +
pre-flight-hint → dry-run/LIVE). Mobile 247, web 94, tsc rent.

**Codex-fund (3 runder, alle løst):** invariant → trigger (H1); enten-retning skjuler re-root → modsat-retning
afvist, re-root=fjern+opret (H2); slette-orden fejler på citations → genbrug komplet sekvens (H3); pre-flight
ikke-autoritativt (RLS-datasæt-afvigelse); evidens-kontrakt (valgt_assertion_id/blaastemplet_af); concurrency
→ advisory-lås; `max(id)+1`-race = arvet codebase-begrænsning (bruger-accepteret v1). /simplify: delt
delete-helper + fjernet død G5-trigger-walk. Spec: `docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md`.

**Udestår:** manuel live-verifikation af UI'et (web-browser + Expo).

## Stamtræ: Kolonner-visning + bidirektionel aner/efterkommere (web + mobile) (2026-07-03)

Stamtræets **Kolonner-visning (variant B)** færdiggjort og udvidet til begge retninger, i
**både web og mobile**.

**Trin 1 — Kolonner på web (lukker item 8 fra web-v2-porten):** segmenteret kontrol
Fokus/Kolonner + vandret-scrollende drill-down-kolonner (matcher mobilens eksisterende variant B).
Ren `buildTreeColumns` i `web/src/data/tree.ts`; drill-valg gennem historik-fri `onFocus` (adskilt
fra `onPick` så dyb drill ikke fylder tilbage-stakken). `/simplify` (4 fund anvendt) + advisor.

**Trin 2 — bidirektionelle kolonner (aner + efterkommere):** fokus er nu et fast **anker** i
midten; aner folder ud til venstre (Forældre → Bedsteforældre → Oldeforældre → Tipoldeforældre →
**N× Tipoldeforældre**), efterkommere til højre (Børn → Børnebørn → …). Bilineal ane-drill via
`parentsByChild` (vælg forælder → dens to forældre). Delt retnings-parametriseret bygger
(`buildBidirectionalColumns` med visited-`Set`-cyklusguard + stabile `kind:depth`-keys), spejlet
web (`data/tree.ts`) + mobile (`data/selectors.ts`). Web parentsOf tilføjet; mobile genbruger sin.

**Tilstands-arkitektur:** web = lokal `useState` (`anchorId`/`up`/`down`) med **frontier-reset**
(kun yderste ane/efterkommer bevares ved fokus-skift — ellers ekstern nav → nulstil); mobile =
zustand-slice (`path` → `anchorId`/`up`/`down`), navigations-mutatorer nulstiller eksplicit, drill-
mutatorer bevarer ankeret. Auto-scroll: centrér anker + kompensér prepend (web `useLayoutEffect`;
mobile scroll-events). Variant A/C urørt.

**Codex-review af design-spec (1 BLOCKER + 5 SHOULD-FIX indarbejdet):** BLOCKER = reset måtte være
frontier-baseret, ikke fuldt medlemskab (ekstern nav til en mid-strip-node skal folde drillen);
plus rigtig cyklus-guard, kollisionsfri kolonne-keys, platform-specifik scroll, forældre-antal ej
antaget=2, dansk genealogisk label-kortform. Se `docs/superpowers/specs/2026-07-03-kolonner-aner-
efterkommere-design.md`.

**Verificeret:** web tsc + 109 tests + build; mobile tsc + 249 tests. **Web visuelt bekræftet af
bruger.** **Mobile empirisk verificeret i iOS-simulator mod prod-Supabase** (idb-drevet): bidirektionel
default (begge forældre), 3 niveauer ane-drill m. korrekte labels/chevrons, glidende up-scroll, og
samme_som-collapse gennem traverseringen (Conrad → Detlef). Descendant-drill på mobile ikke separat
gentestet denne session (barnløs fokus-linje), men samme mekanisme + web-verificeret.

## samme_som-collapse implementeret (web + mobile) (2026-07-02)

Frontend identitets-projektion: en person der optræder som flere DB-poster (linket via
afklarede `samme_som`-relationer) vises nu som ÉN person i søgning, person-visning og
slægtskabsfinder — i **både web og mobile**. 9-task plan (`docs/superpowers/plans/`)
implementeret TDD, dual-reviewet efter hvert logisk trin.

**Kerne (`collapseSameAs.ts`, spejlet web+mobile):** ren funktion der grupperer `samme_som`-
linkede id'er (union-find), vælger kanonisk = unik sink, **validerer og karantænerer** konflikter
(self-forælder/-ægtefælle, global cyklus, konkurrerende forældre, hard vital/køn-konflikt) på den
kombinerede projicerede graf via en **fixed-point-løkke**, fletter person-posterne (coalesce,
`years`-regen, `privat=OR`, konfidens-stærkeste kant-dedup) og omskriver alle graf-kanter til
kanoniske id'er FØR `buildModel`. Motoren (`buildModel`/`relationship`) er URØRT. Reversibel:
returnerer `canonicalIdById` + `mergedFrom` + `quarantined`.

**Integration:** `load.ts`/`model.ts` henter godkendte `samme_som` (relation + afklaret conclusion,
polymorf → to fetches + JS-match) og folder før `buildModel`. Alle person-id-bærende Aux-strukturer
kanoniseres; `linjeByPerson` er nu multi-linje. Rute/fokus/rel/mig-id'er resolves gennem alias-map
(inkl. `meId` ved read-site). Person-visningen viser multi-linje badge + proveniens-note
("Optræder i Aarbogen som …"). Redaktion collapser IKKE (ser separate DB-poster).

**Dual-review (7 kerne-fund + 3 integrations-fund, alle rettet):** Codex opgraderede to "defer"
til reelle silent-corruption-bugs (konkurrerende forældre maskeret af rejekteret gruppe →
fixed-point; konfidens-nedgradering ved dedup). code-analyzer fangede et meId-read-site-bug
(★ Dig-badge brød for foldede personer). Se `docs/reviews/16-samme-som-collapse-kerne.md`.

**Empirisk valideret mod prod:** de 2 eksisterende `samme_som` (Conrad III-58→V-1, Detlef
III-104→IV-1) er begge `afklaret`, cross-linje, konflikt-fri → folder rent; founder'en arver
sit forælder-link (der før manglede på founder-posten). Suiter: mobile 236, web 84.

**Udestår (manuel):** Expo-simulator + web-browser-verifikation af selve skærmene (navigation
via begge alias-ruter → samme samlede person + badge).

## DAA-reimport Etape 1+2, data-tab-genopretning, grundlægger-links, samme_som-design (2026-07-02)

**Etape 1 — loader/validate-hærdning (merget til main, pushet):** 9-task subagent-drevet
forløb (final-reviewet af Opus). Partner-dedup via `partner_ekstern_ref` (dry-run: 41 færre
dubletter); børne-løkke rewrite (15a/15b-opslag + observerbar logging af uopløste — kun 3
uopløste i hele stamtavlen); deterministisk `date_min/max` fra `date_raw` (+ floruit-spans);
`--dry-run` + RESET-guard (fail-closed) + `--force-reset`; frossen trin ③-prompt
(`references/extract-prompt.md`). Union-heuristik reverteret efter Opus-review (brugte
forkert kontekst-entitet, 0-impact). Suiter: R 181, validate 38, escalate 16.

**Data-tab-hændelse + Etape 2-reload:** Live-basen (`xjnvdhajfyrcytatnzos` — appen, R og MCP
peger alle her) var i en TIDLIGERE session overskrevet til 3 test-personer. Bruger godkendte
reset-reload af fuldt datasæt: `load_daa.R clean-v2.json --reset --force-reset` → **922
personer** (41 færre dubletter), cache regenereret, 70 levende. TRUNCATE CASCADE ramte også
`profiles`/`lineage`/`suggestion` → genoprettet (redaktør-profil for johan@reventlow.dk;
5 lineage-navne) i et durabelt, idempotent `post_load_fixup.R` (par-opslag på linje/nr =
reload-sikkert). Ryddet 32 orphaned `change_set` + 191 `change_event`.

**TNG-QA-måling (docs/reviews/tng-qa-rapport-2026-07-02.md):** manglende relations-links
**125 → 10** (Etape 1 genindvandt 92%), enig 177 → 288, 0 falske links. Bekræfter empirisk
at de manglende links var et linking-problem (bucket c=0), ikke et udtræks-problem — re-udtræk
var ikke nødvendigt. Rest: 10 kryds-linje-links (Etape 4) + 5 dato-uenigheder (fejl-attribueret
`date_raw`).

**Grundlægger-identitets-links:** Conrad de Reventlow (III-58↔V-1) + Detlef de Reventlou
(III-104↔IV-1) — samme person i to linjer — linket via `samme_som`-relation (evidenslag),
bekræftet via TNG-crosswalk. Løser samtidig 2 af de 10 manglende links.

**samme_som-collapse — design + plan (dual-reviewet, ikke implementeret):** frontend
identitets-projektion så en person med flere DB-poster vises som ÉN (søgning/person-visning/
slægtskabsfinder). Spec `docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md`
(Codex-reviewet: valideret reversibel projektion, completeness-baseret GDPR, konflikt-karantæne).
Plan `docs/superpowers/plans/2026-07-02-samme-som-collapse.md` (9 tasks, web+mobile). **Klar til
implementering næste session.**

## Flere-forældrepar datafix (2026-07-01)
* **Bruger observerede** at personer så ud til at have flere forældrepar. Undersøgt:
  90 personer med beviseligt modstridende forældrepar, 163 fejlagtige `barn`-links i alt
  (af 559). Rodårsag: `load_daa.R`'s child-linje-fallback prøvede et upålideligt LLM-udtrukket
  `boern.linje`-felt FØR forælderens egen linje — når feltet var forurenet, matchede et
  genbrugt løbenummer nogle gange en helt anden gren/generation.
* **Rettet:** `load_daa.R:246-260` dropper nu `stated`-fallback helt, matcher
  udelukkende egen linje (så en gen-indlæsning ikke kan genskabe fejlen). Prod-data
  korrigeret ved SQL-sletning af de 163 spuriøse rækker (kørt som versioneret `change_set`
  #3, fuldt fortrydbart), lokal backup af `family_member` gemt i `work/`. 4 personer uden
  linje-match + 46 nu-forældreløse personer er sandsynligvis rescuable via en målrettet
  gen-kørsel af den fixede loader (ikke gjort her — kræver egen plan). Sideeffekt: løste
  også den tidligere kendte era-tie-break-fejl (børn født før forældre) fuldt ud.
  Se `docs/reviews/11-flere-foraeldre-datafix.md`.

## Versionering + hyperlinks — real-device Expo-verifikation + DB-bugfix (2026-07-01)
* **App-lag afprøvet på ægte iPhone-simulator mod rigtig prod-Supabase** (`idb`-baserede taps,
  ikke kun statisk `tsc`/jest). Konfirmeret empirisk: hyperlink-rendering/navigation,
  bio-klamp, MentionPicker insert-at-cursor, fortryd-flow, redo-knap på reversal-post.
  Konflikt-retry (B9-divergens) forbliver utestet.
* **DB-bug fundet + rettet:** `_version_upsert_row` (fortryd-restore-helper) manglede eksklusion
  af `GENERATED ALWAYS`-kolonner fra sin dynamiske `INSERT`/`ON CONFLICT`-kolonneliste —
  Postgres tillader slet ikke en eksplicit værdi for disse. Ramte `narrative.fts` (aktiv
  fuldtekstsøgning i prod, selvom CLAUDE.md §9 hævdede den var kommenteret ud — schema-drift).
  Konsekvens: fortryd fejlede hårdt for ENHVER tabel med en generated-kolonne. Transaktionen
  rullede korrekt atomisk tilbage (ingen delvis korruption), fundet + rettet + genverificeret
  ved en ægte LIVE-testskrivning + fortryd på en obskur testperson (godkendt af bruger).
  Migration anvendt til prod; `schema.sql`/`db-migrations.sql` opdateret.
* **UI-bug fundet + rettet (brugerfund):** dry-run-toggle-switchen i `redaktion/person/[id].tsx`
  havde omvendt polaritet ift. den identiske switch på Konto-/dashboard-skærmen — samme felt,
  modsat "til højre = sikker"-betydning afhængig af skærm.
* Se `docs/reviews/10-app-lag-hyperlinks.md` for fuld verifikations-log.

## Versionering + hyperlinks (App-lag, RN/Expo) — kode-komplet, dual-reviewet, IKKE Expo-kørt (2026-06-30)
* **Hyperlink-tokens i narrativ:** `mentions.ts` (parser/encoder, ren funktion, 17 jest-tests)
  + `NarrativRenderer` (klikbar visning, wrapper `Typography.Body` 1:1) + `MentionPicker`
  (@-mention-søgning, indsæt-ved-cursor i redaktør-editoren).
  Token-grammatik (spec §5.1): `[[type:id|tekst]]`, 10 fast entity-typer, `\|[]`-escape.
* **Redaktionel historik-skærm** (`redaktion/historik/[id].tsx`): change_set-liste m. "Fortryd"
  + en samlet døde-links-rapport (D1/D3). Fortryd ruter gennem den eksisterende
  `pending`+`SkrivePreviewSheet`-modal (dry-run/LIVE-bekræftelse) — IKKE et direkte
  `submitChange`-kald, som var en tavs no-op i dry-run (fanget proaktivt før review).
* **Dual-review (cycle 10, Claude+Codex):** H1 [HIGH] escape-asymmetri — `makeToken` eskaperede
  ikke `\` selv, så et label der ender på backslash fik scanneren til at sluge afgrænserens `]`
  og hele tokenet lækkede som synlig tekst. Min første fix-recipe (narrow scanner-regex) var
  selv FORKERT — Codex korrigerede til encode-siden (escape `\` i `makeToken`); empirisk
  verificeret med 7 round-trip-cases. H2 [MEDIUM] `reverteret`-feltet havde omvendt semantik
  (`reverterer_id` peger FRA den nye fortrydelse TIL den originale, ikke omvendt) — Fortryd-
  knappen forblev aktiv på allerede-fortrudte poster. M3 [MEDIUM, Codex-only fund] stille
  fejl-svælgning i `MentionPicker` umuliggjorde at skelne netværksfejl fra reelt nul personer.
  Se `docs/reviews/10-app-lag-hyperlinks.md`.
* **`/simplify`:** 6 behavior-preserving cleanups (NarrativRenderer→Body-wrapper, dødt
  TYPES-sæt + dead defensiveness i mentions.ts, `erFortrydKonflikt`-ekstraktion + regressionstest,
  unødig Number/String-tur-retur fjernet, `useRef` i stedet for `useState` til cursor-position).
* **Verifikation: `tsc --noEmit` 0 fejl, jest 197/197 grøn.** Det er taget for hvad det er — det
  dækker rene funktioner og mappere, IKKE render/interaktion (cursor-indsætning i `TextInput`,
  nested-`Text`-clamp, `Alert`-flow). **Ikke Expo-kørt i denne session** (intet device/simulator
  tilgængeligt) — se manuel punch-list i review-dokumentet, §"Manuel Expo-verifikation".
  Vigtigst deri: eksisterende narrativer i basen har INGEN `[[...]]`-tokens endnu (funktionen
  er ny), så `NarrativRenderer` over LIVE-data i dag tester reelt kun plain-text-fallbacken.
* **Branch `feat/versionering-hyperlinks-app-lag` ikke merget/pushet** — afventer brugerens
  beslutning (git-gate).

## Versionering + hyperlinks (DB-lag) — implementeret, dual-reviewet, applied til prod (2026-06-30)
* **Fortryd-bar redaktionel ændringshistorik:** hybrid change-set-log (`change_set`/
  `change_event`) — hver `red_*`-skrive-RPC åbner et re-entrant `change_set`, og en generisk
  `log_change`-trigger på alle 22 versionerede tabeller snapshotter før/efter-tilstand
  (kolonne-projektion: `visning_*`/`email`/`rolle` ekskluderet). `red_fortryd_change_set`
  inverse-applier ét sæt i én transaktion med optimistisk divergens-tjek.
* **Append-baseret `red_edit_oplysning`:** ny påstand + re-peg konklusion (ærer invariant #1);
  returtype `void→jsonb` (`ny_assertion_id`). App-laget upåvirket (consumer læser ikke retur).
* **Hyperlinks i fri-tekst:** `[[type:id|tekst]]`-tokens → `parse_mentions` + afledt
  `text_mention`-indeks (regen-trigger på narrative/note) + døde-links-view. RLS dobbelt-gating.
* **Historik-API:** `hist_for_subjekt`/`hist_events` (redaktion-only, SECURITY DEFINER);
  deny-all RLS på historik-tabeller.
* **TDD mod lokal prod-kopi** (free tier → ingen branch; postgresql@17 + auth-shim + read-only
  pg_dump). **5 bugs fanget før prod:** 3 under impl (begin_change_set-placering ved flerlinjet
  rolle-tjek, assert-filter-fejlklassificering, `FOREACH IN ARRAY NULL`-crash) + 2 HIGH i
  dual-review (Claude+Codex+code-analyzer, konvergent): DELETE-inverse manglede divergens-tjek
  (blind PK-overskrivning) og `_version_upsert_row` nulstillede NOT NULL skip_cols
  (`profiles.rolle`-crash). Begge empirisk reproduceret + regressions-testet. Se
  `docs/reviews/09-versionering-hyperlinks-db.md`.
* **Applied til prod Supabase (atomisk, --single-transaction):** verificeret — 4 tabeller,
  22 log-triggere, RLS aktiv, `red_edit_oplysning`→jsonb, 963 personer uændret. Pre-apply
  schema+data-backup taget lokalt. 24 verify-asserts grønne + clean-slate-konsistent.
* **Bevidst deferret:** TOCTOU (single-writer PoC), parse_mentions open-token (delt-parser/app-lag),
  `red_doede_links` dækker 3/10 mention-typer (completeness).

## TNG-QA: pipeline komplet ende-til-ende (Trin 1-6) + kalibrering (2026-06-30)
* **Forbindelses-bug fixet:** top-level `on.exit()` under `source()` fyrede
  `dbDisconnect(shutdown=TRUE)` FØR næste query → "Invalid connection". Lukker nu
  forbindelser efter sidste brug.
* **Trin 3-4-glue (`scored` → `crosswalk`):** `our_match_frame`/`tng_match_frame`/
  `build_scored` — blokering på fornavns-initial + fødselsår-vindue, vektoriseret
  overlap, top-K pr. person rangeret på score. Fix: `person.id` bigint→integer
  (data.frame recycler ikke integer64); DATE→år-konvertering.
* **Auto-tier bootstrap-kalibreret:** den uniforme "Reventlow" gjorde `unique_block`
  ubrugelig (auto=0). Erstattet med ambiguitets-margin (`ambiguity_margin=0.05`):
  auto kræver score≥0.90 OG bedste kandidat klart foran nr. 2 OG top-kandidat.
  Kalibreret mod bootstrap-ankre (entydige eksakte matches). `calibrate.R` ny.
* **Dato-overlap som scoring-evidens:** `birth/death_overlap` er nu kun TRUE ved
  reel dato på begge sider (`.overlap_evidence`) — fjerner 0.3 "gratis" vægt på
  dato-løse par. Auto kræver nu reel fødselsårs-korroboration. auto≈347, review≈658.
* **Trin 5 gen-kørsels-crash fixet:** review-køen skrives nu med udfyldelig
  `afgoerelse`-kolonne; `merge_review_decisions` tåler tom/manglende afgørelse.
* **Trin 6 aktiveret — relations-QA mod TNG:** sammenligner ægteskaber/forælder-barn/
  datoer/køn; producerer `docs/reviews/tng-qa-rapport-<dato>.md`. **GDPR PII-gate =
  input-gating** (filtrér begge sider til afdøde-ikke-private FØR sammenligning,
  fail-closed) — verificeret 0/70 levende-id i rapporten. Første kørsel: 183
  handlingsorienterede uenigheder.
* **Tests:** 35 (match/report/review/extract/pull), alle grønne.

## Slægtskabsfinder: bilineal multi-linje + konfidens på stien (2026-06-30)
* **Bilineal:** "Er vi i familie?" (`mobile/src/data/relationship.ts`) traverserer nu BEGGE
  forældre-linjer (BFS over `parentsByChild`) i stedet for kun den primære forælder-kæde.
  Slægtskab via mor-linjen blev før tavst overset — en reel korrekthedsfejl i en sammengift slægt.
* **Multi-linje:** returnerer alle distinkte forbindelses-linjer (`lines[]`), nærmeste først.
  Anepar grupperes til ÉN linje (helsøskende vises ikke som to). Klassisk dobbelt-fætterskab
  giver to anepar-linjer. "Halv" markeres kun når den anden forælder faktisk er kendt og
  forskellig (ingen falske halvsøskende fra datahuller).
* **Køn:** kønsbestemte moderne etiketter (Fætter/Kusine, Onkel & niece, Mor & søn) via
  `person.koen`, med kønsneutral fallback der matcher de oprindelige strenge.
* **Konfidens på stien (invariant #7):** `family_member.konfidens` trækkes nu ind i modellen
  (loader + kant-indeks `konfByEdge`). Hver linje beregner sit SVAGESTE staterede led; en sti
  gennem et formodet/omstridt led flages (`usikker`) — på resultat-kortet, pr. trin på
  tidslinjen, og på øvrige linjer. Uangivne led larmer ikke. Samme kant med flere påstande
  beholder den stærkeste konfidens. *Hage:* de fleste eksisterende links er `NULL` (bulk-load),
  så visningen viser usikkerhed i takt med at konfidens-data berigt (fx de 97 kendte fejl-links).
* **Datalag:** `koen` + `konfidens` tilføjet til visningsmodellen (types + loader), bagudkompatibelt.
* **Tests:** relationship-suiten udvidet 6 → 27 (bilineal, anepar-collapse, halv, dobbelt
  fætterskab, kønsetiketter, konfidens-svageste-led). Hele suiten 141/141 grøn, tsc + eslint rene.
* **Roadmap:** `docs/moed-en-slaegtning-roadmap.md` — telefon-til-telefon slægtskab ved fysisk
  møde (NameDrop-stil dobbelt-aktiv-handling, QR-MVP → BLE → UWB, GDPR-samtykke-design).

## Opret-ny-entitet — Tilføj-fanen (2026-06-29)
* **Hvad:** Redaktøren kan oprette ny person/gods/kilde/organisation fra "Tilføj"-fanen gennem
  dry-run→live-gate; person → lander i editoren, øvrige → vises i listen.
* **4 nye SECURITY DEFINER RPC'er (deployet prod):** `red_opret_person` (INSERT + navn/født/død/titel
  som facts via `red_upsert_fakta`, privat=true default), `red_opret_estate`, `red_opret_kilde`,
  `red_opret_organisation`. id=max+1, NULL/whitespace-navn afvist. Grants tilføjet i
  `db-migrations.sql` (schema.sql bærer ingen grants by design; db-rls.sql grant-loop dækker red_*).
* **B1/B2 (Codex-review):** `loadRedaktionModel(force)` tvinger reload (var no-op på 'ready');
  `SkrivePreviewSheet.onApplied(result)` bærer ny id til navigation.
* **`OpretSheet`:** grid + per-type formularer; `buildRpcCall`-cases for 4 opret-arter; enkelt-Modal
  (kun én Modal synlig ad gangen via `visible={visible && !pending}`); wire til Tilføj-fanen.
* **Privatliv:** ny person privat=true (levende=false=anon-læsbar → glemt toggle ville publicere).
* **Udskudt:** sted-picker til gods (ingen place-picker/placeListe); inline-opret fra PersonPicker;
  medie/våben/majorat; dedup-UNIQUE; id-sequence (post-PoC).
* **Test:** jest (`buildRpcCall` opret-arter) + DB rollback-test + manuel web-e2e.
* **Codex-review-fix (2026-06-30):** nestet native Modal fjernet — OpretSheet rendrer nu én Modal
  ad gangen + SkrivePreviewSheet som søskende; Task 1 happy-path-test omskrevet fra psql-`\gset`
  til `DO`-blok med `RAISE EXCEPTION`-asserts (eksekverbar via `execute_sql`).
* **GDPR-hærdning cycle-08 (2026-06-30):** `p_privat`-param fjernet fra `red_opret_person` — privat
  er nu FORCERET `true` i INSERT-kroppen; gammel 7-arg-signatur DROPpet på PROD (ny 6-arg erstatter).
  Synlighed skiftes herefter udelukkende via `red_set_privat`. `OpretSheet` og `buildRpcCall`
  fjerner `privat`-feltet fra payload; jest-test opdateret (30/30). Lukker anon-eksponerings-footgun:
  en crafted RPC-kald med `p_privat=false` kunne gøre en afdød person anon-læsbar ved opret.

## Plan 2C-2b — redigerbar familie-sektion (partner + barn + konfidens) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og afkoble ægtefælle/partner, tilføje og afkoble børn
  samt justere konfidens på familie-links direkte i person-editoren — alt via det eksisterende
  SkrivePreviewSheet-gate (dry-run → live). HVERV/GODSER/KILDER er uændrede fra 2C-2a.
* **4 nye SECURITY DEFINER RPC'er (deployet mod prod 2026-06-29):**
  - `red_opret_union(p_partner_a, p_partner_b, p_type, p_ordinal)` — opretter ny family-entitet
    + 2 partner-links. INGEN auto-dedup: samme par kan gifte sig igen — par-dedup ville flette
    børn og event-tidslinjer fra to selvstændige ægteskaber (Codex H2). partner_a==b og ugyldig
    type afvises med RAISE.
  - `red_tilfoej_barn(p_family_id, p_barn_id, p_rolle, p_konfidens)` — tilføjer barn-link til
    eksisterende family. Cyklus-guard via recursiv CTE: tilføjer en ane som barn → RAISE (Codex H3).
    Selv-forælder (barn==en af familiens partnere) afvises. PK-dublet = no-op. Ugyldig
    rolle/konfidens afvises.
  - `red_set_familie_konfidens(p_family_id, p_person_id, p_rolle, p_konfidens)` — UPDATE
    `family_member.konfidens` for præcist ét link; ukendt link → RAISE; ugyldig konfidens → RAISE.
  - `red_slet_familie_link(p_family_id, p_person_id, p_rolle)` — sletter KUN `family_member`-rækken.
    Sletter ALDRIG `family`-entiteten (heller ikke når det er det sidste link), da family bærer
    276+ facts og 700+ notes uden FK — en family-sletning ville efterlade al evidens forældreløs
    (Codex H1).
* **`fetchPersonFamilie`** — per-person familie-fetch (unioner + barn-af-links), separat fra
  `redaktionAux` der ikke eksponerer `family_member.konfidens` eller de primærnøgler
  (`family_id`/`person_id`) som slet- og konfidens-kaldene kræver.
* **`eraAdvarsel`** — klient-side blød dato-advarsel (barn født udenfor forældrenes plausible
  livsrum). Advarer og tillader — afviser ikke. 27 verificerede historisk-inkonsistente tilfælde
  i eksisterende data ville trigger en hard-reject uberettiget.
* **`PersonPicker`** — sheet-komponent til valg af person (søg + tryk), brugt ved
  "+ Tilføj partner" og "+ Tilføj barn" i editoren.
* **`buildRpcCall`-cases** for `opretUnion` / `tilfoejBarn` / `setFamilieKonfidens` /
  `sletFamilieLink`; type `Change` udvidet med `familyId`, `personId` (familie-kontekst)
  og de 4 nye Change-arter.
* **Redigerbar ÆGTEFÆLLE/BØRN/FORÆLDRE-sektion** i person-editoren: tilføj partner
  (PersonPicker → opretUnion), tilføj barn (PersonPicker → tilfoejBarn, m. era-advarsel),
  juster konfidens (KonfidensVaelger → setFamilieKonfidens), afkobl
  (sletFamilieLink). FORÆLDRE-sektionen (personen som barn): forældre-NAVNE er read-only, men
  konfidens kan justeres og forkert forælder kan afkobles ("🗑 afkobl forælder" → sletFamilieLink).
* **Test:** 121/121 jest, tsc rent.
* **Controller-gate kørt (2026-06-29):** schema-backup (15 funktioner →
  `docs/db-backups/2026-06-29-prod-red-functions-2c2b-pre.sql`), 4 RPC'er deployet + grant-loop re-kørt,
  rollback-tests bestået (nul mutation): H2 samme par → 2 selvstændige unioner (ingen kollaps); H3
  cyklus-guard + selv-forælder afvist + PK-dublet no-op; konfidens-UPDATE + valideringer; H1 slet alle
  family-links → family-entitet + 276+ facts + 700+ notes INTAKT.
* **Final-review-fix:** era-advarsel medtager nu fokus-forælderens egne datoer (manglede → eget barn-tilføj
  ikke era-tjekket, dødt for én-forælder-unioner).
* **Udestår:** kun manuel web-e2e. Bredere redaktionModel-invalidering efter familie-write = §9-follow-up.


## Plan 2C-2a — redigerbar sektion-relationer (hverv/godser) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og slette hverv- og godser-relationer direkte i person-editoren.
  Familie (family_member) og kilder (external_id) forbliver read-only i denne plan; familie-redigering
  er udskudt til 2C-2b. Alle ændringer passerer igennem det eksisterende SkrivePreviewSheet-gate
  (dry-run → live).
* **To nye SECURITY DEFINER RPC'er (deployet mod prod 2026-06-29):**
  - `red_slet_relation(p_relation_id)` — FK-ordnet evidens-cascade:
    citation → conclusion → assertion → note → relation. Nødvendigt fordi relations bærer ~955
    evidens-rækker uden FK (target_type/target_id er polymorft, ingen cascade-constraint).
  - `red_tilfoej_relation(p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)` —
    validerer objekt_type + eksistens, dup-guard (returnerer eksisterende id ved gentagelse,
    ingen dublet), indsætter relation.
* **`fetchPersonRelationer`** — ny pagineret per-person relations-fetch (ikke via `redaktionAux`,
  som dropper relation-id'er og ikke kan bruges til slet-kald).
* **`EntitetPicker`** — sheet-komponent til valg af entitet (gods, organisation m.fl.) med
  type-menu + navne-liste, brugt ved "+ Tilføj hverv/gods" i editoren.
* **`buildRpcCall`-cases** for `sletRelation` + `tilfoejRelation` (relations-kald vha. eksisterende
  write-gate); type `Change` udvidet med `relationId`, `sletRelation`, `tilfoejRelation`.
* **Test:** 109/109 jest, tsc rent.
* **Controller-gate kørt (2026-06-29):** schema-backup (13 funktioner + 43 policies →
  `docs/db-backups/2026-06-29-prod-red-functions-policies.sql`), begge RPC'er deployet mod prod +
  grant-loop re-kørt (kaldbare af `authenticated`), rollback-test bestået (FK-ordnet slet rydder
  al evidens uden orphans; dup-guard returnerer samme id; 4 valideringer afviser ugyldig
  objekt_type/ikke-eksisterende objekt) — alt i rollback-txn, nul mutation mod prod data.
* **Udestår:** kun manuel web-e2e (klik gennem editor). Bredere cache-invalidering efter relation-write
  (public person / gods-ejer-tidslinje / 2C-1 ownerCount stale til model-reload) er spec §9-follow-up.


## Plan 2C-1 — entitetslister (read-only) i redaktions-appen (2026-06-28)
* **Hvad:** Entiteter-tab er nu en type-menu med 6 typer (Personer · Godser · Kilder ·
  Organisationer · Medier · Våben), hver med tæller → read-only liste. Personer åbner 2A-listen →
  editor; de øvrige er read-only browse (ingen entitets-write-RPC'er endnu = 2C-2/2C-3).
* **Data:** `buildAux` udvidet med fem flade lister (`kilde/org/medie/gods/vaabenListe`) fra de rå
  arrays den allerede modtager + ét nyt `coat_of_arms`-fetch (våben). Læses fra redaktion-modellens
  aux (2B) — ingen ekstra fetch for de fire. `godsListe` er komplet (inkl. ejerløse godser, modsat
  `estateList`); ejer-tæller bevaret.
* **Auth-state:** lister/menu viser "Kræver redaktør-rolle" for ikke-redaktører (Codex fangede at de
  ellers ville sidde fast på "Henter…" permanent). "Henter…" kun under redaktør-load.
* **Korrektion (Codex):** `coat_of_arms` (våben) FINDES — tidligere fejlpåstand om manglende tabel
  rettet; våben inkluderet. `majorat` korrekt udeladt (en `slags` af estate, ingen egen tabel).
* **Review:** Codex-spec-review (auth-state + våben) + per-task spec+quality. 104/104 jest, tsc rent.
  Relations-redigering = 2C-2; entitets-write + detail-editor = 2C-3.


## Plan 2B — editor-dybde: selv-forsynende editor + køn + familie/sektion (2026-06-28)
* **Hvad:** Person-editoren åbner nu for ALLE personer inkl. de 70 levende (før: "Personen blev
  ikke fundet" fordi den lænede sig på den delte anon-model på 893). Tilføjet: køn-editor
  (redigerbar: mand/kvinde/ukendt → `red_set_koen`), familie (forældre/ægtefæller/børn) +
  sektioner (hverv/godser/kilder) **read-only**.
* **Separat redaktion-model:** ny store-slice (`redaktionModel`/`redaktionAux`) loades via
  redaktion-sessionen (`loadFromSupabase({includePrivat:true})` → 963 inkl. levende, getAll-
  pagineret), adskilt fra publikums-modellen → ingen GDPR-læk i publikums-faner. Editoren bruger
  de EKSISTERENDE selektorer (`parentsOf`/`childrenByMarriage`) + aux uændret → ingen divergens
  fra publikums-visningen (Codex-aligned, se decisions).
* **Narrativ-privat-fix:** `fetchPersonNarrativ` henter første narrativ by id (= præcis skrive-
  målet for `red_upsert_narrativ`) og editoren bevarer privat-flaget på Gem — før kunne en privat
  bio overskrives + gøres offentlig (Codex 2B #1).
* **Privat-toggle** initialiseres nu fra `person.privat` (før hardkodet false). `AppPerson.privat`
  tilføjet; publikums-load uændret default.
* **Review:** Codex-spec-review (skiftede arkitektur fra per-person re-derivation → separat model,
  fangede pagination + familie/hverv-divergens + narrativ-tab) + per-task spec+quality + idle-race-
  fix. 100/100 jest, tsc rent. Relations-redigering + medier + generisk editor = 2C.


## Plan 2A — person-liste & navigation i redaktions-appen (2026-06-28)
* **Hvad:** Entiteter-tab'en har nu en rigtig person-liste (søg + alfabet-hop + alfabetisk/fødeår-sort)
  → tap → person-editor. Dashboardets "Personer"-celle navigerer dertil. Løser URL-tastnings-smerten
  (ingen in-app-vej til en person → web-reload → skrivemode nulstillet).
* **Separat redaktion-fetch:** ny `fetchRedaktionPersoner` (mobile/src/data/redaktionRead.ts) henter ALLE
  personer inkl. levende/privat via redaktion-sessionen — **pagineret** (genbrug `getAll`/`.range`,
  PostgREST capper ved 1000 lydløst). Den delte publikums-model (`load.ts`) røres ikke → ingen GDPR-læk
  i publikums-faner. Verificeret live: redaktion ser 963, anon 893 (70 levende skjult fra publikum).
* **DRY:** `buildSearch` refaktoreret til pool-baseret `searchPool` (genbrugt af publikum + redaktion);
  publikums-`search.tsx` uændret.
* **Tags:** levende/privat-personer markeres i listen ("levende"/"privat"). `born` udledes direkte af
  visning_foedt (ikke dødsår — Codex 2A M1). Fejl-tilstand i listen (ikke tom-som-clean — cycle 03 NEW1).
* **Review:** Codex-review af spec (pagination + born-sort indarbejdet før impl); per-task spec+quality.
  94/94 jest, tsc rent. Andre entiteter + generisk editor = 2C; køn/familie-visning = 2B.


## Redaktions-UI kerne-skive — implementeret + DB-deploy (2026-06-27)
* **Hvad:** Vertikal kerne-skive af redaktør-appen (mobil editor): `redaktion/`-route-segment
  med native `(red-tabs)`-navigation, dashboard (rolle-kort + dry-run + konflikt-kø +
  entitets-grid), person-editor (evidens-lag: kerne-fakta navn/foedt/doed/titel med
  konklusion←oplysninger, redigér/slet/gør-til-konklusion/tilføj via inline-editor + narrativ),
  konto + login-sheet, skrive-preview-sheet (dry-run/live) og slet-bekræft m. cascade-advarsel.
* **Nyt evidens-read-lag** (`mobile/src/data/redaktionRead.ts`): `fetchPersonEvidence` henter
  den polymorfe model (fact/assertion/conclusion/citation) som N flade queries + klient-join
  (target_type/target_id har ingen FK → nested-select 400'er; citation→source nestes via FK).
  `fetchKonflikter` (konflikt-kø) + `fetchSletPreview` (cascade).
* **Write-lag udvidet** (`redaktionWrite.ts`): `buildRpcCall`-cases for redigerOplysning/
  sletOplysning/setKonklusion/setPrivat/sletPerson + `oversaetFejl` (dansk). Alle writes via
  én path (dry-run preview ELLER live RPC); cache regenereres af DB-trigger.
* **DB additivt (deployet live 2026-06-27):** `red_konflikt`-view (`security_invoker=true` —
  KRITISK, ellers omgår viewet RLS og lækker private personers konflikter); redaktion-read-RLS
  (rolle=redaktion ser private rækker, så privat-toggle ikke låser redaktøren ude);
  `red_slet_person_preview`-RPC (cascade-advarsel der spejler red_slet_person's indgående+udgående
  relations-slet). Backup taget før deploy (`~/daa-backup-20260627-redaktion-ui.sql`).
  Live-verificeret: view returnerer konflikt-rækker, RPC rolle-gated (P0001), privat-læk lukket (anon ser 0 private).
* **Review:** Codex-review af spec (8 fund indarbejdet før impl); per-task spec+quality-review;
  final whole-branch review (opus) READY — RPC-kontrakt app↔DB, evidens-join, GDPR/RLS,
  write-data-flow alle verificeret rene. 81/81 jest grøn, tsc rent.
* **Udestår (plan 2, bevidst):** køn-editor i UI (red_set_koen-path findes+testet, intet kort);
  familie/sektioner read-only-visning; entitetslister; generisk record-editor; opret-flow;
  relations/sektion-redigering. Operationelt: seed en `redaktion`-profil (auth.users +
  profiles.rolle='redaktion') for at teste happy-path-writes mod live; manuel e2e på device.

## `levende`-GDPR-cache udledt + RLS-deploy-bug rettet (2026-06-25)
* **Root cause:** `load_daa.R:64` hardkodede `levende=FALSE` på hver person — flaget
  blev aldrig udledt. Alle 963 stod FALSE, inkl. nulevende (fx Johan Martin, id 488,
  f. 1977). Med RLS aktiv ville selv korrekt filter eksponere dem.
* **Regel (bruger):** levende = født inden for seneste 100 år (ift. load-dato) UDEN
  død/begravelse/dødsårsag-fakta og uden `visning_doed`. Fail-closed: ukendt fødselsår
  → FALSE (de udaterede er tidlige aner). Udledt fra **struktureret** fødedato
  (`assertion.date_min/max` via blåstemplet `conclusion`), ikke display-cachen.
* **Backfill (live, committet):** 70 personer → `levende=TRUE`. To uafhængige metoder
  (display-regex + struktureret fakta) konvergerede på præcis 70; risiko-bucket (166 uden
  fødsels/død-fakta) verificeret til 0 levende (alle tidlige aner; edge-case id 940 =
  1785-ægtefælle). `load_daa.R` fået derivations-pass så næste load ikke nulstiller.
* **`db-rls.sql`-bug:** oprettede `anon_read` men droppede ALDRIG den midlertidige
  `dev_anon_read` (USING true). Postgres OR'er permissive politikker → deploy as-is =
  fuld læk (anon ser alle 70 levende). Verificeret via transaktionel sim mod live
  (apply → SET ROLE anon → tæl → ROLLBACK): A=70 lækket, B (dev droppet)=0. Rettet:
  `db-rls.sql` dropper nu `dev_anon_read` på alle tabeller først. Re-sim: 0 lækket,
  893 afdøde + data loader stadig (narrative 550, relation 961, family_member 1205).
* **Deployet mod live (2026-06-25):** `db-rls.sql` kørt via `work/rls_deploy.R`
  (verificer-og-commit). Verificeret som anon: 893 afdøde synlige, 0 levende lækket,
  helper-fn på plads, `dev_anon_read` væk. anon-tier GDPR-lag er nu aktivt i prod.
* **Udestår:** `authenticated`-tier (medlem/forsker ser levende slægtninge m. samtykke)
  — skitse nederst i `db-rls.sql`, bygges når login/profiles er på plads. `media`-tabel
  er deny-all indtil afbildet-gating skrives (tom nu).

## Slægtslinjer navngives — `lineage`-entitet, trin (a) (2026-06-23)
* Linjer levede kun som bart `'I'..'V'`-token på `person_external_id.linje`. Ny entitet
  `lineage(id, source_id, kode, navn, UNIQUE(source_id,kode))` giver dem navne:
  I=Den holstenske linje, II=Linjen Gallentin, III=Den mecklenburgske linje,
  IV=Den lensgrevelige linje af 1767, V=Den grevelige linje af 1673.
* `schema.sql` (source of truth) + idempotent migration i `db-migrations.sql`. Backfill
  er **data-drevet**: `source_id` + `kode` udledes via `SELECT DISTINCT` fra
  `person_external_id` (ingen hardcodet source-id); `ON CONFLICT DO NOTHING` → re-kørbar.
* App (`mobile/`): `load.ts` henter `lineage` (tolerant `.catch(()=>[])` indtil migration
  kørt), `buildAux.ts` bygger `linjeNavn`-map + `navn` på `linjeList`. UI viser navn med
  fallback til `Linje {kode}`: linje-chips (tree), gen-header (VariantC), persondetalje-badge.
* **Trin (b) bevidst udskudt:** adling→ny slægt, forgrening (`gren_af`), eget våben,
  person↔linje m. konfidens. Tabellen er forward-kompatibel — (b) er ren `ALTER ADD` +
  relationer senere. Se `docs/decisions.md` + datamodel-oversigt §5/§9.
* Tests: `buildAux.test.ts` udvidet (navn-map, fallback til null, bagudkompatibilitet);
  8/8 grøn, `tsc --noEmit` ren.
* **Udestår:** migrationen er IKKE kørt mod live-basen endnu (auto-mode blokerede
  produktions-skrivning); runner klar i `/tmp/run_lineage.R`.

## Ægtefælle-rygrad for hele slægten + deterministisk boern (2026-06-17)
* Re-load af hele stamtavlen med ægtefælle-rygrad for HELE slægten (ikke kun nær
  familie): 591 poster → 925 personer (591 hoved + 334 ægtefæller). Backup-dump af
  forrige base gemt (`work/dump_before_reload_*.rds`, 22.702 rækker).
* Loader-fixes: `sp_date()` tåler nu både struktureret (object) og rå string
  partner-datoer (udtræk var inkonsistent: 198 string vs 29 object for fødsel);
  ægtefælle-bio-note flyttet fra person til `family` (så appen viser den);
  begivenheder uden navn skippes + fallback-rolle "deltager".
* **`boern` udledes nu DETERMINISTISK** i `validate.py` (`derive_boern`) — LLM-trinnet
  missede børne-referencer systematisk (Codex fangede 38/123). Regex hærdet mod alle
  fraseringer (plural sønner/døtre, "?"-markør, "5 (7?) børn", bar "børn:", linjebrudt
  range). Fanger 123 ægte, afviser hallucinerede uden tekst-belæg.
* Bugs fundet+fixet: forkerte forældre (dato-linje læst som post-header i ad-hoc patch);
  manglende ægtefælle-info (string-datoer ej parset).
* Undersøgt: 145 kryds-gren-tvetydige boern-links (`boern.linje` = bogens interne
  gren-tæller, IKKE JSON-linje). 97 verificerede fejl, 38 ægte kryds-gren. Era-tie-break
  anbefalet (next-step). Rammer også linje V (fx V-73→V-106).

## App-skive + slægtskabs-UI (2026-06-15/16)
* Minimal Vite/React/Supabase-app der renderer lagdelte evidens-data.
* Relations-visning centreret på en fokus-person (forældre/søskende/ægtefælle/børn),
  klikbar graf-navigation; start på Johan Martin (V-186).
* Viser: lagdelte fakta (vaerdi + dato), dekoration (hvilken · hvornår), fuld narrativ,
  vielsesdato(er) + skilsmisse på ægtefælle-kort, ægtefælle-bio-noter + person-fakta.
* s.å./s.m. ekspanderes i visning via opløst ISO-dato (rå tekst bevaret i basen).
* Midlertidig dev-RLS udvidet til alle læse-tabeller (erstattes af rigtigt RLS-lag).

## DAA-parsere som skills (2026-06-15)
* `/daa-extract` — stamtavle-PDF → evidensmodel. Pipeline: pdftotext → segment.py
  (deterministisk) → LLM-udtræk → blokerende validering → R bulk-load.
* `/daa-presens` — præsensliste (nulevende medlemmer, OCR-tolerant, relations-træ).
* Segmentering håndterer: gren-headere (DEN…LINJE + LINJEN GALLENTIN), per-linje
  løbenr, under-numre (15a/b/c), ?-præfiks (usikkert medlemskab → konfidens).

## Datamodel + load (2026-06-15/16)
* Fuld Reventlow-stamtavle loadet: 591 poster → 934 personer (Sonnet-udtræk).
* Evidenslag på relationer (ikke kun fakta); steder normaliseret til `place`;
  ejendom/org/begivenhed dedupes (get-or-create); ægteskab → familie-fakta.
* Bulk-insert loader (dbAppendTable/COPY): 30+ min, skrøbelig → ~14 sek, pålidelig.
* Indekser på relations-/evidens-opslag. Kontrolleret vokabular (vocab) + V9-validering.
* Forkortelsesnøgle (bogens bagstof) seedet i vocab(scheme='forkortelse').
* Nær families ægtefæller (V-175/186/187/188/199) beriget: fødsel/dåb/død + bio-note.
* erhverv/uddannelse holdt UDE af rygrad (ligger i narrativ/bio-note).

## TNG-analyse (2026-06-15)
* `jr_tng_reventlow.sql` (25k personer) analyseret som senere enrichment-kilde;
  gaps dokumenteret i docs/tng-reventlow-analyse.md (git-ignoreret, levende-data).

## Kendte issues / næste
* Haiku-fuld-broaden af ægtefælle-rygrad FEJLEDE (parallelle agenter clobberede delt
  output-mappe) — ingen data tabt, men ~10% kvote spildt. Genoptag KUN med isolerede
  output-mapper/worktrees + terse agent-output. Se memory parallel-agenter-isoleret-output.
* RLS-lag (rigtigt) mangler — kritisk før multi-bruger pga. nulevende-data.
* Dekorations-nøgle hentes fra anden DAA-udgave (koder bevaret rå).
* ~16% relative datoer uopløst ved udtræk (rå tekst bevaret).

## 2026-07-19 — Mediehåndtering fase 1: filside og fuld CRUD

- Tilføjer redigerbar filside på web og mobile med metadata, rettigheder, publiceringsgate og filstatus.
- Tilføjer `red_opdater_media` og `red_genopret_media`; upload gemmer nu også kunstner og datering.
- Fjernede medier bevares i redaktionens læselag og kan genoprettes, men filtreres fortsat fra lightbox og narrativ-mention-pickere.
- Ingen produktionsmigration er kørt fra dette ændringssæt. Kør `db-migrations.sql`, derefter `db-verify.sql`, `db-verify-media.sql` og til sidst `db-rls.sql` efter runbooken.

## 2026-08-01 — Karantænen opløst + union-redigering (PR #141)

**Diagnose.** Sybille Malvina Lonny (456/1346) foldede ikke, selvom begge hendes
forældre var matchede. Årsagen lå **otte generationer oppe**: 1939-loaderen lagde børn
af mænd med flere ægteskaber i en separat "børne-familie" med kun faderen som partner,
mens ægteskaberne lå i egne familier uden børn. Sæt-uligheden `{far}` vs `{far,mor}`
afviser gruppen, og fixed-point-løkken i `collapseSameAs` kaskaderer nedad til alle
efterkommere. UI-hintet peger på nærmeste forældre — roden kan ligge vilkårligt langt oppe.

**Prod-datarettelser (begge fortrydbare change_sets).**
* 65 børn flyttet fra 15 mor-løse 1939-familier til de korrekte ægteskaber
  (`change_set 858`, 390 hændelser). Hustru pr. barn afledt maskinelt af de allerede
  matchede 1930-poster — 0 tvetydige. De øvrige 26 børn i mor-løse familier har ingen
  `samme_som`-modpart og kan pr. konstruktion ikke konflikte.
* 7 resterende forældre matchet på tværs af udgaverne (Iwan/Iven ×2, Augusta Sophia,
  Elly Stein, Cecilie/Tzile, Hartwich/Hartvig, Ghese).
* **Karantænerede grupper: ~70 → 0.** Verificeret med den rigtige `collapseSameAs` mod
  et friskt prod-dump (`tools/foraeldrematch/`), ikke med genimplementeret SQL.

**Union-redigering (PR #141, DDL applied til prod).**
* `red_tilfoej_partner` — tilføj manglende part til en EKSISTERENDE union. Præcis det
  hul der gjorde de 65 flytninger nødvendige.
* `trg_partner_loft` — maks to parter pr. union som tabel-invariant; dækker også
  fortryd-stien og samtidige kald. Prod havde 0 overtrædelser ved indførelsen.
* `_samme_som_gruppe()` + identitets-bevidst cyklus-guard i BEGGE retninger
  (`red_tilfoej_barn` sammenlignede før kun rå person-id'er).
* `samme_som`-rolle/endepunkter gjort uforanderlige (slet+genopret), så en påstands
  evidens ikke genbruges til en ny identitetspåstand.
* `red_doede_links` udvidet 4 → 10 måltyper; de manglende blev rapporteret som
  "ingen døde links".
* UI: "+ Tilføj part" pr. forhold (skjult ved to parter), ✕ på hver part med
  bekræftelse der siger hvor mange børn der mister en forælder.
* `.gitignore`: `tmp/` — `dump-prod.R` skriver et fuldt persondump dertil, og mappen
  var ikke ignoreret (invariant 8).

**Review.** Otte adversarial runder med Codex `gpt-5.6-sol`; afvist 1-7, accepteret i
runde 8. `red_slet_union` blev bygget og droppet igen undervejs. `get_advisors(security)`
efter DDL: 139 → 135 lints (revoke på de to nye trigger-funktioner).

**Udestår.** Manuel UI-test af de nye knapper mod prod · PR #141 er draft ·
loader-låsen (parkeret, se decisions) · 1235/1237 peger begge på 1930-id 527
(sandsynlig dublet i 1939-posten) · 15 mor-løse skaller står tilbage med én part og
0 børn, bevidst ikke slettet.

## Grænsekontrol fase 1 + 1939-matchningen færdiggjort (2026-08-08)

**Matchningen er komplet.** Alle 453 `human_required`-poster og alle 5 stikprøver er
afgjort (402 kandidatvalg, 55 "ingen kandidat passer", 1 uafgjort). De 88 uden afgørelse
er præcis de automatiske ikke-stikprøver, som fladen forbyder valg på. Forankret:
**352 spænd, 45 parkerede, ingen injektivitetsfejl** — den risiko vi havde udpeget som
utestet med 131 tekstankre i spil holdt. Parkeringsårsager: 26 `pdf_pages_mismatch`
(alle tekstankre, koncentreret på s. 571-573 og 596-598 = sidekortets grovkornede
område), 19 overlap.

**To fejl rettet i menneskeark-generatoren før det.** (1) Fladen viste kun de tre
øverste kandidater bag "Vis alle kandidater"; nu vises alle, foldet ud. (2) Calamari
mangler 18 PDF-sider (plancher), men generatoren regnede sidetal lineært i stedet for
at bruge `CALAMARI_R6_TO_PDF_V1`. Målt: tabellen rammer trykt side 321/362, lineær
149/362 — og opdelt ved side 547 er lineær **0/205**. Sidefiksen alene gjorde det værre
(101 → 57 korrekte kandidater), fordi korrekte sider fortrængte det eksakte tekstanker;
ankeret tilbydes nu altid og først: **101 → 301**.

**Detektor for skævt delte baseline-poster** (`detect_boundary_defects_1939.py`): 2
grænsefejl-par, 17 poster uden eget hoved, 5 grupper der deler ordret samme narrativ.
Bruger den trykte søskendenummerering; resultatet er et gulv, ikke en optælling.

**Grænsekontrol fase 1 bygget** (17 commits, `c150ae7..59c75fa`): delt UI-modul
udtrukket fra menneskearket, grænser dannet af accepterede spænd med revisionsbærende
id, klausul-regnskab, fire spænd-signaler, view-model med eksplicit kald af den
kanoniske globale injektivitetskontrol, selvstændig browserflade med fem domme,
OCR-noter og karantæne, samt CLI med hash-validering. 1083 Python-tests, 773 web-tests,
menneskearkets 88 uændret gennem refaktoren.

**Kørt mod rigtige data:** 446 grænser (= 445 spænd + 1), 248 med signal.
`slugt_hoved` 2 · `nummerspring` 80 · `mangler_eget_hoved` 10 · `hoved_i_raa_ocr` 5.

**Fase 1's egentlige svar:** grænserne er overvejende i orden — kun 12 bærer et signal
om en forskubbet skæring. Det der mangler er **dækning**: 101 poster ejer intet spænd,
og **46.015 tegn** af kilden ejes af ingen, i 355 huller (største 8.996 tegn).

**Fem fejl fundet af reviews, én af et tal, fire af brugerens browsertest.** Se
decisions for mønsteret. Brugerens fund: uparsebar genereret fil (blank side), to tomme
kasser der læstes som frikendelse, manglende fremdrift/navigation i en flade til 446
poster, manglende sidetal, og kontekst der rakte ud over spændets kant (352 af 446).

**Udestår.** Ikke pushet, ikke merget · `manglende_post` registrerer ikke *hvilken*
post der mangler (struktureret felt foreslået, ikke bygget) · brugeren vil diskutere en
anden fremgangsmåde i næste session · fase 2 bør planlægges forfra på tallene ovenfor ·
eksport-knappen er ikke verificeret i en rigtig browser.
