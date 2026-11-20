# Runbook: OCR-rettelse af kildepåstand i prod (PR #407)

Udført 2026-11-20 (`database-current-state.md` §36). Runner `~/.private/ocr-paastand-407/prod.zsh` (privat, aldrig i
repoet), kørt med `/bin/zsh -f` i projektejerens shell; prod-skrivninger er spærret for agenten.

## Handlinger

| Handling | Hvad |
|---|---|
| `standin <dump> <suffiks>` | lokal stand-in fra et læsedump (`~/.private/5ab-overfoersel/koer.zsh 39-laesedump.sh`) |
| `tal` | læse-kun: funktion, CHECK med `ocr`, ACL; journal pr. grund; 1559's fødselspåstand (assertion 13833) |
| `apply [--jeg-mener-det]` | én transaktion; uden flaget ROLLBACK; nægter, hvis funktionen findes |
| `proeve1559` | kun stand-in, altid ROLLBACK: retter 1559 som redaktør med webbens payload, fortryder |
| `fortryd [--jeg-mener-det]` | DROP FUNCTION + CHECK tilbage; nægter, hvis journalen har `ocr`-rækker |

## Blok og invarianter

- Blokken `-- ===== ocr-rettelse af kildepåstand =====` … `-- END ocr-rettelse af kildepåstand` fra `db-migrations.sql`
  @ `f7dcf575`, sha `6d299c81f37c949b2444b44231516c18fd9897bece8a6c0b8d6e9db422a8da6c`.
- Efter blokken i samme transaktion: funktionen findes, er security definer med search_path, anon kan ikke kalde den,
  authenticated kan; CHECK nævner `bogen_har_ret`, `linjeskift-v1` og `ocr`; antal i `person`, `fact`, `assertion`,
  `paastand_korrektion`, `change_set`, `change_event` og en hash over `visning_foedt/doed` er uændrede.

## Generalprøve (stand-in `daa5ab_ddl_standin_20261120202826_ocr1`, dump `6ac3a0a9…`)

| Skridt | Resultat |
|---|---|
| tal | funktion 0; journal 27/70; 1559: 1 påstand »25 Marts 157«, ingen fortolkning |
| apply (prøve) | invarianter OK; 34 ms; ROLLBACK |
| apply --jeg-mener-det | invarianter OK; 27 ms; anon 0, authenticated 1, secdef 1 |
| apply igen | `OP_ALLEREDE_ANVENDT` |
| proeve1559 | »25 Marts 1578«, 1578-01-01..1578-12-31, 1 påstand, cache følger, grund `ocr`; fortryd gendanner; ROLLBACK |
| fortryd (prøve, commit) → apply | ren rundtur |
| fortryd med en committet `ocr`-række | `OP_FORTRYD_JOURNAL_HAR_OCR` |

## Prod (2026-11-20)

| Skridt | Resultat |
|---|---|
| tal | funktion 0; journal 27/70; 1559 som i generalprøven |
| apply (prøve) | invarianter OK; 1,4 s; ROLLBACK |
| apply --jeg-mener-det | invarianter OK; 695 ms; COMMIT |
| tal (ny forbindelse) | funktion 1; CHECK `ocr` 1; anon 0, authenticated 1, secdef 1; journal uændret |
| 1559 i Redaktion (projektejeren), derefter tal | 13833 = »25 Marts 1578« (1578-01-01..12-31), 1 påstand, cache følger; journal `ocr`=1 med original »25 Marts 157« |

## Fortrydelse

Er der lavet rettelser, fortrydes de først med `red_fortryd_change_set` (journalrækkerne står, og så nægter
`fortryd` stadig: rækkerne skal da blive, og funktionen med dem). Uden `ocr`-rækker:
`/bin/zsh -f ~/.private/ocr-paastand-407/prod.zsh fortryd --jeg-mener-det`, og revert af web-delen fra #407. Efter merge
genskaber en kørsel af `db-migrations.sql` funktionen; fortryd før merge, eller revert blokken sammen med web-delen.
