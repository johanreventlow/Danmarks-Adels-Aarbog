# #150 trin 5c-1 i prod: placement og membership for 2018-20

Spec: `docs/superpowers/specs/2026-10-26-trin5c-placement-membership-design.md`. Plan:
`docs/superpowers/plans/2026-10-26-trin5c-placement-membership.md`.
Scripts: `.claude/skills/daa-extract/scripts/fix_150_placement.sql`, `fix_150_maal.sql` og `fix_150_fingeraftryk.sql`;
manifest og ark: `build_header_manifest.py`, `fix_150_eksport.sql`, `placement_control_sheet.py`.
Privat runner: `~/.private/5ab-overfoersel/21-150-5c.sh` (kørt gennem `koer.zsh`). Kører i projektejerens egen shell;
AI'en har ingen prod-forbindelse.

## Hvad der skrives

1. **GO 1, DDL:** placement-blokken i `db-migrations.sql` (mellem `-- Placement og membership (#150, trin 5c-1)` og
   `-- Placement-blokken slutter her.`) lægges i én transaktion. Det er fire `observation_kind`-koder
   (`header_linje`/`_slaegtled`/`_kuld`/`_aegteskab`), den udvidede `private.validate_source_record_placement` (sti ii),
   `private.placement_header_violations`, ledger-tabellen `private.legacy_placement_disposition` med current-view, de
   private skrivefunktioner, membership-promotionen (`red_preview_`/`red_promote_placement_memberships`,
   `red_reverse_placement_membership`) og `slaegt` i versioneringen. Ingen data. Blokken er sha-bundet i runneren.
2. **GO 2, data:** i én transaktion (`fix_150_placement.sql`):
   - 266 overskrifts-forekomster med observationer (én header-`extraction_run`);
   - record-placements for de maskinelt enige og de godkendte poster, og persona-placements for deres hovedpersoner;
   - én ledger-disposition pr. legacy-række (kilde 1: `mapped`/`unresolved`; kilde 3: `retained_legacy`);
   - slægten Reventlow `historical` → `active` under et eget change_set;
   - memberships (`member` + `agnatic`) for de placerede hovedpersoner med accepteret identitet, gennem promotions-RPC'en;
   - revalidering af hver publicering, der er blevet `stale_published`, med `red_revalider_person_narrative_record`
     (én sætning pr. post via `\gexec`; `app.change_set_id` ryddes før hvert kald). Det er de publicerede poster, der
     får placement (målt 498); de publicerede, der står uafklaret, ændrer ikke tilstand. Tallet udledes i transaktionen.

Ingen læser ændres. Ceremonien hasher fem læsere før og efter i transaktionen og stopper ved forskel
(`red_person_grid`, `red_match_personer`, `regen_person_visning`, `public_family_sources`,
`public_person_bio_source_versions_v2`).

## Før GO 2: manifest, kontrolark og token-fil

1. Eksportér legacy og forælder-barn-par fra prod (læsetransaktion, kun nøgler og tal):
   `psql -X -At -v ON_ERROR_STOP=1 -v src=1 -f fix_150_eksport.sql > ~/.private/5c/legacy.json`.
2. Byg manifestet: `build_header_manifest.py --rendition-text work/raw_full.txt --profile
   …/daa-2018-20-source-evidence-v1.json --legacy-json ~/.private/5c/legacy.json --out ~/.private/5c/manifest.json`.
   Alle seks invarianter skal være sande.
3. `placement_control_sheet.py render --manifest ~/.private/5c/manifest.json --out-kontrolark ~/.private/5c/kontrolark.txt
   --out-token ~/.private/5c/token.txt` → `ARK_OK kontrol=20 grupper=6`.
4. Projektejeren udfylder kontrolarket mod PDF'en (slægtled som tal, kuld som romertal eller `-`) og token-filen
   (6 kuld-grupper: J/N). Én afvigelse i kontrolarket stopper og sender opgaven tilbage til manifestet; arket skal
   være netop stikprøven (nøgler, rækkefølge, sider). Poster, hvor barnet står i forælderens slægtled (V-82..V-92),
   kan ikke godkendes og står uafklaret (projektejerens afgørelse 2026-10-27; opfølgning).
5. `placement_control_sheet.py approvals --manifest … --kontrolark … --token … --approved-token-sha256 <sha>
   --out ~/.private/5c/approvals.json` → `APPROVALS_OK kontrol=20 godkendt=<n>`.
6. Øv ceremonien på en stand-in med netop disse filer; `~/.private/5c/expect.json` får de målte antal
   (`headers`, `placements`, `published`, `bindings`, `ledger`, `revalidated`, `memberships`).

Manifest, ark og token-fil kan nævne levende ægtefæller (ægteskabsoverskrifter): de ligger kun under `~/.private/5c/`
og sendes aldrig til en model.

## Forventede tilstande

`21-150-5c.sh maal` viser blokkens fingeraftryk og fasen fra `fix_150_maal.sql` og stopper ved alt andet end:

| Efter | `ddl150` | `fase` |
|---|---|---|
| i dag | `foer` | `foer` |
| GO 1 (DDL) | `efter` | `foer` |
| GO 2 (data) | `efter` | `bundet` |

Fasen `bundet`: placements findes, hver legacy-række har én gældende disposition, memberships = placerede
hovedpersoner med accepteret identitet, ingen ikke-gældende memberships, slægten er `active` og 0 `stale_published`.

## Forløb

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 21-150-5c.sh …`. Repoet skal stå rent på
`main` efter merge af PR'en; `go` kræver, at afgørelsesfilen er lavet af netop den bundne token-fil og det bundne
kontrolark.

1. `go` → `GO150_KODE=<8 hex>` og commit. Projektejeren skriver `GO 150 <kode>`.
2. `maal` → `MAAL_150_OK ddl150=foer fase=foer`.
3. `dump` → `DUMP_150_OK …` (fuldt dump i en læsetransaktion). `ddl` og `placement` stopper med `DUMP_150_MANGLER`
   uden et dump fra de seneste 12 timer.
4. `advisors` → `ADVISORS_150_OK nye=1`: netop `rls_enabled_no_policy|private.relation_reopen` fra #248 (GO 1's
   baseline `advisors-after.txt` er fra før #248).
5. `ddl --jeg-mener-det --go <kode>` → `DDL150_OK` (fingeraftryk `foer` → `efter`, blokkens sha, PostgREST genindlæst).
6. `maal` → `MAAL_150_OK ddl150=efter fase=foer`.
7. `advisors` → `ADVISORS_150_OK nye=2`: #248's fund plus `rls_enabled_no_policy|private.legacy_placement_disposition`
   (med vilje: kun private skrivefunktioner skriver i ledgeren).
8. **Skrivepause:** ingen redaktørskrivninger til kilde 1's poster under GO 2 (læsning er uberørt).
   `placement --jeg-mener-det --go <kode>` → `FIX150_OK headers=266 placements=<n> ledger=1167 memberships=<n>
   revalideret=<n>`. Runneren viser `statement_timeout` før `BEGIN` (prod: 2min; scriptet sætter 15 min lokalt) og
   gemmer `\timing` privat.
9. `maal` → `MAAL_150_OK ddl150=efter fase=bundet`.

## Prøvet

På kopier af stand-in'en af prod efter #248 (dump `b03b1128…`, 2026-10-26) med `statement_timeout='2min'` på basen,
som i prod, og en øvelses-afgørelsesfil uden godkendelser (543 maskinelt enige poster):

- **Gennem runneren** (stand-in `_5cr5`, øvelsens GO-kode `2ef426eb`): alle ni skridt gav det forventede. Advisors før:
  1 nyt (`relation_reopen`); efter: 2. `FIX150_OK headers=266 placements=543 ledger=1167 memberships=541
  revalideret=498` på 83 s, længste sætning 23 s.
- **Afvist:** manglende `--jeg-mener-det`, ukendt argument, forkert GO-kode, `ddl` uden dump, `placement` før DDL'en
  (fingeraftrykket), `ddl` igen og `placement` igen (fasen er `bundet`).
- **Uden for runneren:** en identitet på en uafklaret post (V-82) afgjort til en anden person end bindingens stopper
  med `FIX150_PRE_IDENTITY`; fasen forbliver `foer`.
- **Rækkeantal** i alle tabeller i public og private før og efter: kun `private.extraction_run` +1,
  `source_record_occurrence` og `source_observation` +266, `source_record_placement`(+`_decision`) +543,
  `source_persona_placement`(+`_decision`) +541, `legacy_placement_disposition` +1167,
  `narrative_publication_event` +498, `vocab` +4, `public.person_lineage_membership` og `person_slaegt_membership`
  +541, `version_pk_registry` +1 og `change_set` +500 (498 revalideringer, slægten, promotionen) med deres
  `change_event`. Ingen andre ændringer.
- **Fuld `db-verify.sql`** mod den skrevne kopi (efter `db-rls.sql` og med dblink, som efter enhver restore): grøn,
  `PLACEMENT_MEMBERSHIP_NOT_CURRENT n=0`.
- **Varighed:** uden `ANALYZE` mellem skrivefaserne tog ceremonien 1269 s (paritetshashen efter skrivningen 574 s,
  fordi planneren så de nye tabeller som tomme); med `ANALYZE` 82-83 s.
- **Efter Codex-review r1** (kopi `_5cra`, øvelsens GO-kode `61577e95`): alle skridt igen grønne; `FIX150_OK
  headers=266 placements=543 ledger=1167 memberships=541 revalideret=498` på 72 s. Identitetstjekket pr. binding tog
  uden materialisering over 15 min på en frisk restore (ingen planner-statistik); nu ca. 11 s.
- Den endelige øvelse med de godkendte filer (kontrolark og token-fil) køres, før GO 2 bindes, og noteres her.

## Fortrydelse

- **Nødudvej:** dumpet fra skridt 3. Efter en restore køres `db-rls.sql` igen (DEFAULT PRIVILEGES giver ellers
  anon/authenticated adgang tilbage). DDL'en fortrydes kun via dumpet.
- **Én post, manuelt** (prøvet i `tests/sql/test-150-ceremoni.sh`, `$fortryd_en_post$`), i denne rækkefølge og som
  redaktør, med `app.change_set_id` ryddet mellem kaldene:
  1. `red_reverse_placement_membership(person, linje, note)`;
  2. `red_decide_source_persona_placement(persona-placement, 1, 'superseded', …)` og derefter
     `red_decide_source_record_placement(record-placement, 1, 'superseded', …)`;
  3. `red_revalider_person_narrative_record(person, 1, record_key, <aktuel tilstands-sha>)`, hvis posten er publiceret;
  4. `private.record_legacy_disposition(person, 1, 'unresolved', NULL, …)` som ejer.
- Der er ingen samlet fortrydelsesceremoni.

## Kendte følger

- Overførselsværktøjets forekomst-digests for kilde 1 ændres af de nye header-forekomster (som ved 5b). Det er ikke
  drift.
- En record uden binding med én accepteret placement får `record_label` = linjens label (`narrative_record_labels`):
  rammer de poster uden publicering, der får placement (spec §5).
- De 4 sidste poster i linje I-IV har ingen hovedperson-persona: de får record-placement (hvis maskinelt enige), men
  hverken persona-placement eller membership.
- `red_slet_person` sletter memberships uden om promotions-RPC'ens reversal; de 587 er allerede blokeret af
  `PERSON_HAR_KILDEIDENTITET` (spec §5).
- `backfill_slaegtled.R` stopper, når ledgeren har dispositioner for kilden (LegacyBackfillFreeze); `post_load_fixup.R`
  arver vagten.
- Kilde 1 og 3 er asymmetriske (placement mod `existing_exact_binding`) indtil trin 6.
