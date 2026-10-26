# Runbook: #240 (dobbeltfamilier) og dubletreglens DDL i prod

> Beslutning: `docs/decisions.md` (#240, 2026-10-26) og dubletreglen (#151, 2026-10-25, PR #260).
> Kører i projektejerens egen shell; AI'en har ingen prod-forbindelse. Skal ske før 1939's kandidatkørsel.

## Hvad sessionen gør

1. **Dubletreglens DDL:** blokken »Dubletreglen (#151 …)« sidst i `db-migrations.sql` lægges i én
   transaktion: 4 funktioner, ingen data.
2. **#240:** de 5 par samles i familien med børn i ét change_set (33 ændringer). Den tomme families noter og
   vielsespåstand flyttes, og den tomme familie fjernes.
3. **De 7 ægteskaber** fra 2018-20, som sammenlægningen gør bindbare, afgøres og bindes til den samlede familie.

Alle skridt går gennem `~/.private/5ab-overfoersel/18-fix-240.sh` via `koer.zsh`. Det genbruger lib.zsh's
forbindelse (kun Session pooleren), målidentiteten (`DAA_EXPECTED_TARGET` i `prod/go-env.txt`) og aktørfilen
(`b2/aktoer.txt`, hash-bundet). Ingen uuid'er eller persondata skrives ud.

## Forventede tilstande

`18-fix-240.sh maal` kender netop disse tilstande (målt på to uafhængige kopier af prod efter GO 2) og stopper
ved alt andet:

| Efter | `ddl151` | `fase` | sha (første 12) |
|---|---|---|---|
| intet | `foer` | `pre` | `acdfe92b9736` |
| DDL | `efter` | `pre` | `acdfe92b9736` |
| sammenlægning | `efter` | `samlet` | `7878ba82020f` |
| ægteskaber | `efter` | `bundet` | `eb87b132f8b5` |

## Forløb

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh <script> …`.

1. Gå til `main` (efter merge af denne PR) og sørg for, at repoet er rent.
2. `18-fix-240.sh go`: binder filerne og viser `GO240_KODE=<8 hex>` og commit. Projektejeren skriver
   `GO 240 <kode>`.
3. `18-fix-240.sh maal`: forventet `MAAL_240_OK ddl151=foer fase=pre`. Ved en afvigelse stopper vi; intet er skrevet.
4. `18-fix-240.sh dump`: fuldt dump (læsetransaktion) før første skrivning, `DUMP_240_OK`.
5. `18-fix-240.sh ddl151 --jeg-mener-det --go <kode>`:
   - tjekker fingeraftryk `foer`, fasen `pre` og blokkens sha;
   - lægger blokken i én transaktion (statement_timeout 15 min) og genindlæser PostgREST-skemaet;
   - tjekker fingeraftryk `efter`. Udfald: `DDL151_OK`.
6. `18-fix-240.sh maal`: forventet `ddl151=efter fase=pre`.
7. `18-fix-240.sh saml --jeg-mener-det --go <kode>`: forventet `SAML_240_OK cs=<id>` og fortryd-linjen. **Notér
   cs.** Scriptets forhåndsbetingelser (`FIX240_PRE_*`) stopper ved enhver afvigelse og ruller tilbage.
8. `18-fix-240.sh aegteskaber --jeg-mener-det --go <kode>`: forventet `AEGTESKABER_240_OK decided=7 promoted=7`.
9. `18-fix-240.sh maal`: forventet `MAAL_240_OK ddl151=efter fase=bundet`.
10. `get_advisors` (security) som efter enhver DDL.

## Fortrydelse

- **Efter trin 7 og før trin 8:** `18-fix-240.sh fortryd <cs> --jeg-mener-det --go <kode>` giver
  `FORTRYD_240_OK` og fasen `pre` igen (byte-trofast i prøven). Scriptet afviser et andet eller allerede
  fortrudt change_set.
- **Efter trin 8:** fortryd er spærret, fordi fasen er `bundet`. En tilbagerulning kræver at fortryde
  promotion og afgørelse først. Det er ikke bygget; restore fra dumpet i trin 4 er nødudvejen.
- **DDL'en:** de gamle funktionsdefinitioner står i dumpet fra trin 4 (`pg_restore -l` / `-P`).

## Kendte følger

- 2018-20's kontrolkørsel beregnes nu som `failed` (`kandidatinput_aendret`); den er brugt op (decisions #240
  punkt 4).
- Indtil DDL'en ligger i prod, kan webkøens filter `duplicate_unresolved` (merget i #260) give en fejl, hvis det
  vælges. Øvrige filtre er uberørte.
