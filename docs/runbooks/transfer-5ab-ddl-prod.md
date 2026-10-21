# Runbook — DDL-ceremonien for 5a+5b (2018-20), GO 1

Autoritativ ceremoni for fase 0 og DDL-delen af spec
`docs/superpowers/specs/2026-10-21-trin5ab-2018-20-prod-overfoersel-design.md` (§5, §6.1, §8 GO 1 og
DDL-fortrydelsen), bygget i plan A (`docs/superpowers/plans/2026-10-21-trin5ab-overfoersel-a-ddl.md`).
Ceremonien deployer 5a+5b's DDL i prod og tager D1, som er fortrydelsespunkt og udgangspunkt for plan B
(datadelen, GO 2). Den skriver ingen kildedata; DDL'en tilføjer kun tre promotion-regler (plan A, I8).
Runbooken nævner aldrig kildetekst, navne eller aktør-uuid; kun tal, koder og hashes.

Prod rammes **kun** af projektejeren i egen shell (`! /bin/zsh -f …`). AI-sessionen kører intet mod prod.
Undtagelse: `get_advisors(security)` via Supabase-MCP på projektejerens ja i samme tur.

## 1. Forudsætninger

- **Scripts:** `~/.private/5ab-overfoersel/` (`00-freeze.sh`, `01-preflight.sh`, `02-dump.sh`,
  `03-rehearsal-ddl.sh`, `04-ddl.sh`, `05-probe-ddl.sh`, `09-undo-ddl.sh`, `lib.zsh`, `koer.zsh`,
  `rollback-preflight.sql`, `expected-new-relations.txt` med de 12 nye relationer). `koer.zsh` bærer
  GO-miljøet mellem trinnene i `prod/go-env.txt`.
- **Overrides gives kun med `koer.zsh --saet NAVN=VÆRDI`**, aldrig som miljøvariabel foran kaldet:
  `koer.zsh` indlæser `go-env.txt` efter kalderens miljø, så en miljø-override overskrives lydløst
  (fundet i plan A Task 6).
- **`DAA_REPO` er hovedcheckouten** `/Users/johanreventlow/TypeScript/danmarksadelsaarbog` på `main` ved
  GO-commit'en:

  ```
  ! git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog switch main && git -C /Users/johanreventlow/TypeScript/danmarksadelsaarbog pull --ff-only
  ```

  De 13 repo-filer i GO-inventaret skal være rene (`REPO_DIRTY`), og commit'en skal være GO's
  (`COMMIT_MISMATCH`).
- **Skrivepausen** (projektejeren 2026-10-20) gøres formel med `00 begin` før D0 og løber videre til plan
  B's `VERIFY_OK` eller en fortrydelse. Ingen andre sessioner skriver i prod imens.
- **Kun Session pooleren** (`*.pooler.supabase.com:5432`); alt andet giver `POOLER_REQUIRED`.

## 2. Fase 0 og D0 (læse-kun i prod)

```
! DAA_FREEZE_RESPONSIBLE=<kode> /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 00-freeze.sh begin
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 01-preflight.sh
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh --saet DAA_EXPECTED_TARGET=71ca6e452cc7d596d8470807e29084cd9d99f8ac24155556afd635da84ffe0f0
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh --saet DAA_EXPECTED_COMMIT=<main-commit>
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 02-dump.sh d0
```

Forventet: `FREEZE_BEGIN_OK … state=PRE`, `PREFLIGHT_OK … locale_compared=true`, `DUMP_OK kind=d0` og
`DUMP_VERIFIED`. `01`'s gates og stopkoder:

| Gate | Stopkode |
| --- | --- |
| Mål = prods identitet | `TARGET` |
| Trin 4's tre digests og tal = 2026-10-05 | `TRANSFER_DRIFT` |
| 0 `change_set` efter `2026-10-05T11:03:06Z` | `CHANGE_SINCE_TRANSFER` |
| Driftsbaselinen (skema, kanonisk, klausulsæt) | `SCHEMA_DRIFT` / `CANONICAL_DRIFT` / `CLAUSE_SET_DRIFT` |
| Ingen af de 12 nye relationer | `DDL_ALREADY_PRESENT` |
| Version ≥ 15, kontrakt v2, 587 149b-identiteter, én redaktionsprofil, `family.id` identity | `PREMISE_*` |
| `datctype` og tegnproben = trin 4's prod-preflight | `LOCALE_DRIFT` |
| Ejerskab over alt i `private`/`public` (fortrydelsen kræver det) | `RESTORE_PRIVILEGES` |
| Ingen åben global default-ACL for DDL-rollen | `DEFAULT_ACL_GLOBAL` |

`02 d0` dumper læse-kun med ACL'er, måler prod straks efter og laver en fuld lokal check-restore
(`daa5ab_ddl_d0check_<stempel>`): de portable fingeraftryk, trin 4's digests og tabelhashene skal være
prods (`RESTORE_FINGERPRINT_DRIFT`). Kun `supabase_vault`-fejl er tilladt i restoren.

**Fingeraftryk.** Katalog og ACL har en *portabel* del (objekter og grants i `public`/`private`; den
sammenlignes mellem prod og lokale restores) og en *prod-lokal* del (andre skemaer, `storage`-politikker,
`pg_default_acl`; den sammenlignes kun i samme base og samme kørsel, lige før og lige efter en skrivning).
Supabase ændrer selv de lokale dele over tid; en forskel mod preflight stopper derfor ikke.

## 3. Rehearsal (lokalt, på netop D0)

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 03-rehearsal-ddl.sh
```

Forventet: `REHEARSAL_OK apply_s=… open_exec=…/0/…/0 drop=89 DATA_DELTA_OK changed=3 new=12`. Rehearsal:

- **R1:** restore af D0 (portabelt katalog/ACL = preflight), prods default-ACL'er for DDL-rollen
  emuleret, apply to gange (idempotens), trin 4's digests uændrede, tabelhash-deltaet inden for
  `.claude/skills/daa-extract/references/transfer-5ab-ddl-allowed-data-delta.txt`, de lokale dele uændrede,
  og `db-verify.sql` grøn i en kopi. I kopien rulles de emulerede default privileges tilbage, fordi
  db-verify's egen probe (`EVIDENCE_PUBLIC_RED_DEFAULT_ACL_ANON_OPEN`) forudsætter lukkede defaults; prod
  har `postgres|public|f|anon`, og migrationerne lukker hver funktion eksplicit. A1-sammenligningen beviser
  kun, at rehearsal og prod er ens, ikke at de er lukkede; lukketheden bevises i den lokale upgrade-test
  (`anon_exec_public`: den eneste nye anon-kaldbare `public`-funktion er `public_family_sources(bigint[])`).
- **R2:** fire afbrud på hver sin restore (efter #153's `COMMIT`, i 5a-cutover-vinduet, i et funktionsvindue,
  hele migrationsfilen uden `db-rls.sql`), derefter fuld apply ⇒ samme fingeraftryk.
- **R3:** fortrydelsen (afsnit 6) på R1's base ⇒ `UNDO_OK`, og restoren skal ikke tilbagekalde noget
  (`UNDO_OPEN_WINDOW`; målt `0|16`).

Rapporten (`rehearsal-ddl.json`) og GO-hashfilen (24 linjer) gemmes i GO-miljøet.

**Målt på stand-in (kopi af `daa2018f_20261001133125`, 2026-10-21):** restore 3 s, apply 1-2 s,
db-verify 35 s; `open_exec` 26/0/27/0; fortrydelsen dropper 89 objekter, restoren giver 5 forventede
fejllinjer, og afstemningen tilbagekalder de emulerede grants og giver 16 `PUBLIC EXECUTE` tilbage
(public-funktioner med standard-ACL, som restoren genskaber under db-rls' globale default).

## 4. GO 1

**GO 1 binder** (alt står i `prod/go-env.txt`): D0-kvitteringen og dumpets hash, `preflight.json`,
`rehearsal-ddl.json`, GO-hashfilen, freeze-rapporten, `DAA_EXPECTED_COMMIT`, `advisors-before.txt` og
`advisors-expected.txt`.

- **`advisors-before.txt`:** `get_advisors(security)` før DDL'en, én linje `lint|objekt` pr. fund.
- **`advisors-expected.txt`:** de lint-typer, projektejeren godkender for 5a/5b's nye objekter (fra
  rehearsalens fortrydelsesliste); skrives og godkendes før GO 1.

## 5. DDL i prod (GO 1 skrivende)

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 04-ddl.sh --jeg-mener-det
```

`04` verificerer GO-hashes, rent repo og commit før første forbindelse; derefter mål, pause fra før D0,
`NO_WRITE_SINCE_DUMP` (0 `change_set` og restore-hash = D0's) og tilstanden:

| Tilstand | Handling |
| --- | --- |
| `PRE` (portabelt katalog og ACL = preflight) | gate-markør, DDL |
| `POST` (= rehearsalens F1/A1) | `ALREADY_APPLIED`, intet skrevet |
| `PARTIAL` | kun med `DAA_DDL_GENKOERSEL=ja` (sat med `--saet`) og gate-markøren fra samme pause |
| `ACL_DRIFT` / andet | STOP før skrivning |

Efter apply: portabelt katalog/ACL = F1/A1, lokale dele uændrede, trin 4's digests uændrede og
`DATA_DELTA_OK` mod D0 ⇒ `DDL_OK`. Derefter `get_advisors(security)` → `advisors-after.txt`, og:

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 05-probe-ddl.sh
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 02-dump.sh d1
```

Forventet: `DDL_VERIFY_OK advisors=ok` og `DUMP_VERIFIED`. `05` kræver `POST`, at `anon` ikke kan læse
nogen privat tabel eller bruge skemaet `private`, RLS på alle private tabeller, og at nye advisors-fund
står i `advisors-expected.txt`. **PostgREST-reloaden** kan ikke testes lokalt: åbn redaktørens identitetskø
i webfladen; den skal svare uden schema-cache-fejl (tom kø).

**Afbrudt `04`: kør det igen straks, eller fortryd.** Migrationsfilen kører sætning for sætning. Med
Supabases default privileges kan `anon` kalde en `public`-funktion, fra migrationen (gen)opretter den, til
dens `REVOKE` kører. Rehearsal målte op til 27 sådanne funktioner ved et afbrud; alle er `red_*`-RPC'er,
og mange findes allerede i prod (fx `red_authorize_reimport`, `red_begin_reimport`), men genskabes af
migrationen. Efter projektets konvention afviser `red_*` kald uden redaktørrolle; det er ikke efterprøvet
pr. funktion, så vinduet skal lukkes. Genkørsel: `koer.zsh --saet DAA_DDL_GENKOERSEL=ja`, derefter `04` igen.

## 6. Fortrydelse (DDL)

```
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 09-undo-ddl.sh --jeg-mener-det
! /bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 00-freeze.sh end --efter-fortrydelse
```

`09` kører netop rehearsalens kommandofølge: (a) nye objekter droppes i én transaktion efter en liste
udledt af preflightens katalog mod det aktuelle, og listen skal være en delmængde af rehearsalens
(`UNDO_LIST_UNEXPECTED`); kolonne-ejede sekvenser (fx `public.family_id_seq`) droppes ikke, de forsvinder
med restoren; (b) DDL-rollens skema-defaults i `public`/`private` fjernes (`ALTER DEFAULT PRIVILEGES …
IN SCHEMA … REVOKE`); (c) `pg_restore --clean --if-exists --no-owner --schema=private --schema=public` af D0;
(d) skema-defaults genskabes fra **preflightens** linjer; (e) grant-afstemning over de portable grants (inkl.
`service_role` og skemaer); (f) `NOTIFY pgrst, 'reload schema'`; (g) portabelt katalog/ACL = preflight,
DDL-rollens skema-defaults = preflight, øvrige lokale dele = før fortrydelsen, trin 4's digests og
tabelhashes = D0's ⇒ `UNDO_OK`. Kør `get_advisors(security)` efter restoren.
Prisen: alt skrevet i `private`/`public` efter D0's start går tabt; under pausen er det kun DDL'en.

**Hvorfor (b) og (d).** `pg_dump` skriver rettigheder i forhold til PostgreSQL's indbyggede standard, ikke
i forhold til Supabases skema-defaults (`postgres|public|…|anon` m.fl.). Uden (b) fik alt, restoren opretter i
`public`, ALL/EXECUTE til `anon`, `authenticated` og `service_role` (målt: 511 grants), indtil (e) tog dem
igen. Med (b) åbner restoren intet; rehearsalens R3 kræver 0 tilbagekaldte (`UNDO_OPEN_WINDOW`). Den
globale række (`REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC`) røres ikke, så restoren mister i stedet 16
`PUBLIC EXECUTE`, som (e) giver tilbage; det er den lukkede retning.

**Afbrudt `09`: kør det igen.** Stopper `09` mellem (b) og (d), står prod uden skema-defaults: nye objekter
får ingen grants til `anon`/`authenticated`/`service_role` (lukket, ikke åbent). En genkørsel genskaber dem
fra preflighten, ikke fra tilstanden ved start, og er bevist lokalt (afbrud efter (b), genkørsel ⇒ `UNDO_OK`).

**To funktioner kan restoren ikke erstatte.** `public.current_rolle()` og
`public.media_object_synlig_anon(text)` bruges af fem `storage.objects`-politikker, så `--clean` kan ikke
droppe dem (»already exists«), og de beholder prods aktuelle tilstand. DDL'en ændrer dem ikke
(`outside_dependents_unchanged` i `tests/sql/test-transfer-5ab-ddl-upgrade.sh`); gør en fremtidig DDL det,
stopper rehearsalens R3 på katalogdrift før GO.

## 7. Efter `DDL_VERIFY_OK` og D1

- Pausen fortsætter. D1-kvitteringen (`DAA_D1_RECEIPT`) bærer efter-DDL-tilstanden (restore-, uberørt- og
  kanonisk hash efter DDL'en) som plan B's udgangspunkt; plan B's »kanonisk delta 0« måles mod den, ikke
  mod rodbasen.
- Plan B (arbejdskørsel, svaroverførsel, pakke, genspil, GO 2) skrives mod D1.
- **Oprydning** af stand-in-, rehearsal- og check-baser (`daa5ab_ddl_*`): kun efter måling og
  projektejerens ja. Dumps og `go-env.txt` bevares.
