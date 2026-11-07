# Runbook: trin 6m del 2 i prod — faktaforslag rettet efter bogen

Plan: `docs/superpowers/plans/2026-11-07-trin6m-del2-faktaforslag.md`. Beslutning: `docs/decisions.md` 2026-11-07.
Runner: `~/.private/5ab-overfoersel/31-trin6m-del2.sh` (aldrig i repoet), kaldt via
`/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 31-trin6m-del2.sh <handling>` fra operatørens cwd. Alle linjer er
kun antal, nøgler og hashes. Prod-skrivning (`apply-*`, `fortryd*`) kun i projektejerens shell med
`--jeg-mener-det --go <kode>`.

## To ceremonier

1. **DDL** (blok `-- ===== trin 6m-a …`) + `db-rls.sql` i én transaktion (`lock_timeout 5s`). Fortrydelse:
   `fortryd-ddl` dropper triggeren `interpretation_forslag_binding`, `public.red_ret_forslag` og
   `private.kontroller_forslag_binding_v1` og genskaber `red_decide_interpretation` fra snapshottet taget lige før;
   kræver, at data-ceremonien ikke er kørt (`laesninger=0`).
2. **A** (data): `apply-a.sql` fra repo-roden (repo-relative `\i`), med `statement_timeout=10min` og
   `lock_timeout=5s` (R12: målingerne før/efter svarer til `maal_trin6c2.sql`; prod ca. 13× stand-in; stand-in
   6,1 s og 6,7 s pr. måling). Fortrydelse: `fortryd` restorer dumpet taget mellem DDL og A (`ddl_6ma=1`).

## Rækkefølge

| Trin | Handling | Forventet |
|---|---|---|
| 0 | `maal` | `T6M2_MAAL_OK tilstand=d ddl_6ma=0 laesninger=0` |
| 1 | `maal-a` | `T6M2_MAAL_A_OK forslag=241 …`, `DAA_T6M2_MAPPE=…/del2-<stamp>` (egen mappe; del 1's filer kopieres sha-bundet) |
| 2 | `klasse-a` | `FF_KLASSE_OK version=56 bind=23 ret_og_bind=14 spaerret=4 drift=0 rapport=144 manifest_a=…` (målt på prod-kopi 7/11) |
| 3 | projektejeren ser tallene og bekræfter det samlede F → `samlet-f` | `FF_SAMLET_OK f=79` |
| 4 | `kort-a` → projektejeren svarer på de 14 kort i browseren og gemmer svarfilen | `FF_KORT_OK … svarbare=14` |
| 5 | `flet-a <mappe>/svar-a-1001.json <kortsvar.json>` | `FF_FLET_OK f=… n=… ubesvaret=…` |
| 6 | `sql-a` | `FF_SQL_OK … svar_sha256=… sha256=…` |
| 7 | øvelse på frisk stand-in med de rigtige svar (se nedenfor) | som prod |
| 8 | `dump` (prod) | `DUMP_6M2_OK … ddl_6ma=0` |
| 9 | `go-ddl` → projektejeren: `apply-ddl --jeg-mener-det --go <kode>` | `T6M2_APPLY_DDL_OK ddl_6ma=1 tilstand=d …` |
| 10 | `dump` (prod) | `DUMP_6M2_OK … ddl_6ma=1` |
| 11 | `go-a` (viser `ark BIND:F=… RET_OG_BIND:F=… VERSION:F=…`) → projektejeren: `apply-a --jeg-mener-det --go <kode>` | `T6M2_APPLY_A_OK versioner=… rettelser=… afgoerelser=… bundet=… \| … bindinger_k=… k1_bindinger_hash=d5bedf7d… vejb=t` |
| 12 | `verify-a` | `T6M_VERIFY_A_OK …` |
| 13 | projektejeren: tre stikprøver i læserfladen (rettet værdi med 1939-kildehenvisning) | |

Fryse: ingen redigering i prod fra dump (trin 8) til trin 13 er godkendt.

## Øvelsen 7/11 (stand-in `_6m3`, `ALTER DATABASE … statement_timeout='2min'`, syntetisk F på alle 14)

- DDL 0,2 s; A 14,0 s: `versioner=93 rettelser=14 afgoerelser=37 bundet=37`, `bindinger_k` 1.106 → 1.136
  (= 1.106 − 7 + 37), rettelser 83 → 97, k1 uændret.
- `fortryd` → tilstand d, `ddl_6ma=1`, `laesninger=0`.
- Drift på et `BIND`-mål efter `sql-a` → `CEREMONI_A fejlede (PAASTAND_DRIFT)`, intet skrevet.
- `fortryd-ddl` → `ddl_6ma=0`, tilstand d, `red_decide_interpretation` byte-ens med før (md5 af definitionen).
- Længste enkeltstatement 6,7 s (målingen efter); alle øvrige < 0,3 s.

## Stoppunkter

- `ARK_AFVIGER` ved `sql-a`: arket stemmer ikke med svarfilerne i mappen. Fjern `ark-a.txt` (og en løs svarfil, der
  ikke var med i fletningen) bevidst og flet igen.
- `KONTEKST_AFVIGER`/`MAAL_DRIFT` ved `kort-a`: mappens input er ændret; lav en ny mappe med `maal-a`.
- `T6M2_*_AFVIGER_FRA_GO` ved `apply-a`: de bundne filer giver ikke den bundne SQL; intet er skrevet.
- `CEREMONI_A fejlede (…)`: rullet tilbage; koden (fx `PAASTAND_DRIFT`, `FORSLAG_DRIFT`, `T6M_BINDING_ANDET_MAAL`,
  `FORSLAG_BINDING_TABT`) siger hvorfor. Intet er skrevet.
- `T6M2_VERIFY_A` efter `T6M2_APPLY_A_OK`: ceremonien er committet; kør `verify-a` igen, og ved fortsat fejl
  `go-fortryd` → `fortryd`.
