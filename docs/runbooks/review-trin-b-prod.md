# Review trin B i prod: fire funktionsrettelser i én DDL-ceremoni

Plan: `docs/superpowers/plans/2026-10-27-review-trin-b-ddl.md`. Beslutninger: `docs/decisions.md` 2026-10-27 (B1, B2, B9).
Scripts: `.claude/skills/daa-extract/scripts/fix_trinb_fingeraftryk.sql` og `fix_trinb_maal.sql`. Privat runner:
`~/.private/5ab-overfoersel/22-trin-b.sh` (kørt gennem `koer.zsh`). Kører i projektejerens egen shell; AI'en har ingen
prod-forbindelse.

## Hvad der skrives

Blokken mellem `-- BEGIN review-trin-b` og `-- END review-trin-b` sidst i `db-migrations.sql`, i én transaktion med
`lock_timeout` 5 s: fire `CREATE OR REPLACE FUNCTION` (`private.preview_relation_promotions`, `red_edit_oplysning`,
`red_slet_oplysning`, `regen_person_visning`). Ingen data, ingen tabeller, ingen signaturændring; rettighederne bevares
(fingeraftrykket omfatter dem). Blokken er sha-bundet i runneren.

Læse-kun måling (T0, 2026-10-27, og `fix_trinb_maal.sql`): 0 ikke-afklarede cachede konklusioner, 0 påstande med
`uforanderlig` NULL, 0 accepterede relationer hvis bindingstilstand afviger fra afgørelsens familie. Ceremonien ændrer
derfor ingen visning, og ingen kø får nye afvisninger.

## Den eksterne kopi (B1, første brug)

`dump` tager et fuldt dump i en læsetransaktion og laver sha256. Derefter krypteres dumpet med `age` til den offentlige
nøgle `age17f59…q0e7`, og runneren tjekker først, at nøglefilen `~/.private/age/daa-dump.key` svarer til den. Den
krypterede fil og en sha-fil lægges på projektejerens SFTP-server (`~/.private/sftp-dump.env`, nøgle-login). Begge hentes
straks tilbage og sammenlignes byte for byte. Den hentede fil dekrypteres, sha'en skal være dumpets, og
`pg_restore --list` skal kunne læse den. Kvitteringen `…-trinb.dump.receipt.json` noterer begge hashes.

`proeve` er prøvegendannelsen. Den genskaber det **hentede og dekrypterede** dump i en ny lokal base (ICU som prod) og
måler fingeraftrykket. Prod røres ikke. `ddl` stopper med `DUMP_TRINB_MANGLER` uden en kvittering med gennemført rundtur
fra de seneste 12 timer.

Den hemmelige nøgle ligger i `~/.private/age/` og i projektejerens adgangskodemanager. Uden den kan kopien ikke åbnes.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 22-trin-b.sh …`. Ceremonien kører fra grenen
`fix/review-trin-b` før merge (ikke fra `main` som 5c-1). GO-filen noterer commit'en, og PR'en kontrolleres senere mod den.
De bundne repo-filer skal være uændrede.

1. `maal` → `MAAL_TRINB_OK ddl=foer`. Først, fordi `TRINB_FOER` er målt på en kopi: afviger prod, stopper `maal` med
   `MAAL_TRINB_UKENDT`, før en GO-kode er udstedt.
2. `go` → `GO_TRINB_KODE=<8 hex>` og commit. Projektejeren skriver `GO trinb <kode>`.
3. `dump` → `DUMP_TRINB_OK …` og `EKSTERN_TRINB_OK … rundtur=ok`.
4. `proeve` → `PROEVE_TRINB_OK standin=daa5ab_ddl_standin_<stempel>_tb personer=<n>`, fingeraftryk `(foer)`.
5. `advisors` → `ADVISORS_TRINB_OK nye=2 … ddl=foer`, altså 5c-1's to kendte fund
   (`legacy_placement_disposition`, `relation_reopen`).
6. `ddl --jeg-mener-det --go <kode>` → `DDL_TRINB_OK` (fingeraftryk `foer` → `efter`, målingen 0/0/0 før og efter,
   PostgREST genindlæst).
7. `maal` → `MAAL_TRINB_OK ddl=efter`.
8. `advisors` → `ADVISORS_TRINB_OK nye=2 … ddl=efter`, ingen nye fund.

`db-verify.sql` lægger testrækker ind og køres aldrig mod prod. Dens bevis ligger på stand-in-kopien (`verify`, kun i
stand-in), se nedenfor.

## Prøvet (2026-10-28)

På en kopi af stand-in'en `_5cf` (prod efter 5c-1), gennem runneren:

- **Afvist:** ingen handling, ukendt handling, ukendt argument, `ddl` uden `--jeg-mener-det` eller `--go`, flag på en
  læse-handling, `verify` uden stand-in, `ddl` uden dump (`DUMP_TRINB_MANGLER`), forkert GO-kode (`GO_MISMATCH`), `ddl`
  igen efter blokken (`TRINB foer`).
- **`dump` og `proeve`** med SFTP erstattet af en lokal mappe: kryptering, rundtur, dekryptering og genskabelse af den
  hentede kopi i en ny base (1811 personer). Fingeraftrykket er det samme som på kilden (`foer`).
- **Blokken** lagt to gange på en separat kopi gav samme fingeraftryk (idempotent).
- **Fuldt forløb** på den genskabte kopi: `go`, `maal` (foer), `dump`, `advisors` (nye=2), `ddl` (`DDL_TRINB_OK`),
  `maal` (efter), `advisors` (nye=2).
- **Fuld `db-verify.sql`** efter blokken og `db-rls.sql`: grøn på 32 s, 0 `ERROR`/`WARNING`.
  `TRIN_B_DECISION_FAMILY_CHANGED_UNBOUND n=0`, og RED-8-blokken (`OK: RED-8 — 25 id-tabeller er identity`) er hermed
  første gang kørt på prod-data.
- **Rigtig SFTP** med runnerens egne `load_sftp` og `sftp_cmd`: en prøvefil lagt op, hentet tilbage (samme bytes) og
  slettet igen; mappen var tom bagefter.

## Fortrydelse

- **Funktionerne** (prøvet 2026-10-28 på kopien efter blokken: fingeraftrykket stod derefter på `foer` igen). Ingen
  data er ændret, så en fuld restore er ikke nødvendig. De gamle definitioner står i dumpet fra skridt 3:
  ```
  pg_restore -l <dump> | grep -E ' FUNCTION (private preview_relation_promotions|public red_edit_oplysning|public red_slet_oplysning|public regen_person_visning)\(' > fortryd.list   # 4 linjer
  pg_restore -L fortryd.list -f - <dump> | sed -E 's/^CREATE FUNCTION /CREATE OR REPLACE FUNCTION /' > fortryd.sql
  psql -X -v ON_ERROR_STOP=1 --single-transaction -f fortryd.sql
  ```
  Derefter `NOTIFY pgrst, 'reload schema'` og `maal` → `ddl=foer`.
- **Nødudvej:** fuld restore af dumpet (lokalt eller den eksterne kopi) inden for vinduet, der lukkes efter
  efterkontrollen (gate 8, B1). Efter en restore køres `db-rls.sql` igen (DEFAULT PRIVILEGES giver ellers anon/authenticated
  adgang tilbage).

## Kendte følger

Se planens »Kendte begrænsninger«: mobil viser fortsat slet-knappen (RPC'en afviser), `red_source_persona_detail` har
intet statusfilter, `RELATION_PROMOTION_REBIND_FAMILY_CHANGED` skygges, `red_set_konklusion` er latent, genspil af en
5ab-pakke optaget før ceremonien kan give `STEP_ITEMS_MISMATCH`, og datogrænserne følger den gamle påstand.

Åbent valg for projektejeren (ikke en del af ceremonien): `authorized_keys` på SFTP-serveren har stadig en `ssh-rsa`-nøgle
fra 2015. Den nye nøgle er tilføjet ved siden af, og den gamle version af filen ligger lokalt i `~/.private/dh_ak.orig`.
