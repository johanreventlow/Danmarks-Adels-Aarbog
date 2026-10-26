# Runbook: #240 (dobbeltfamilier) og dubletreglens DDL i prod

> Beslutning: `docs/decisions.md` (#240, 2026-10-26) og dubletreglen (#151, 2026-10-25, PR #260).
> Kører i projektejerens egen shell; AI'en har ingen prod-forbindelse. Skal ske før 1939's kandidatkørsel.

## Hvad sessionen gør

1. **Dubletreglens DDL:** blokken »Dubletreglen (#151 …)« sidst i `db-migrations.sql` lægges i én
   transaktion: 4 funktioner, ingen data. Det er en afvigelse fra den normale deploy (hele den idempotente
   `db-migrations.sql`). Blokken er sha-bundet og noteres i `database-current-state.md` §11.
2. **#240:** de 5 par samles i familien med børn i ét change_set (33 ændringer). Den tomme families noter og
   vielsespåstand flyttes, og den tomme familie fjernes.
3. **De 7 ægteskaber** fra 2018-20, som sammenlægningen gør bindbare, afgøres og bindes til den samlede familie.

Alle skridt går gennem `~/.private/5ab-overfoersel/18-fix-240.sh` via `koer.zsh`. Det genbruger lib.zsh's
forbindelse (kun Session pooleren), målidentiteten (`DAA_EXPECTED_TARGET` i `prod/go-env.txt`) og aktørfilen
(`b2/aktoer.txt`, hash-bundet). Ingen uuid'er eller persondata skrives ud.

## Forventede tilstande

Målingen og fingeraftrykket kører i en læsetransaktion med `statement_timeout` 15 min (prod har 2 min).
Kontrolkørslens status er ikke med i målingen, fordi den er tung at beregne. Sammenlægningen tjekker den
én gang i sin forhåndsbetingelse.

`18-fix-240.sh maal` kender netop disse tilstande (målt på to uafhængige kopier af prod efter GO 2) og stopper
ved alt andet:

| Efter | `ddl151` | `fase` | sha (første 12) |
|---|---|---|---|
| intet | `foer` | `pre` | `2b1388057151` |
| DDL | `efter` | `pre` | `2b1388057151` |
| sammenlægning | `efter` | `samlet` | `77a928c61388` |
| ægteskaber | `efter` | `bundet` | `576215b99bfe` |

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
10. `18-fix-240.sh advisors`: sikkerhedsrådgiveren (Supabase CLI, som `08-advisors.sh`); ingen nye fund mod GO 1's
    `advisors-after.txt`, `ADVISORS_240_OK nye=0`.

## Opfølgning: GO 2's ene dubletægteskab (efter trin 9)

I GO 2 svarede kontrolarket `731=753` på ét ægtefællekort (samme kvinde som to personposter). Den gamle regel bandt
hende til 731 (familie 179 med 261); ægteskabet er med 294 (familie 202 med 753) og kunne derfor ikke bindes. Efter
den nye regel er 753 familiens post og kandidat nr. 1.

1. `18-fix-240.sh go` (filmængden omfatter nu `fix_go2_dublet*.sql`; ny GO-kode) og `GO 240 <kode>`.
2. `18-fix-240.sh maal`: forventet `MAAL_240_OK ddl151=efter fase=bundet` og `DUBLET_GO2 fase=foer`.
3. `18-fix-240.sh dublet --jeg-mener-det --go <kode>`: afgør hende igen til 753 med webfladens RPC
   (`red_afgoer_source_persona`) og afgør og promoverer netop det ene ægteskab til familie 202. Forventet
   `DUBLET_GO2_OK identitet=753 decided=1 promoted=1`. For- og efterbetingelser `FIXDUB_*`.
4. `18-fix-240.sh maal`: forventet `fase=bundet` (uændret) og `DUBLET_GO2 fase=efter`.

Prøvet på en kopi af prod i dagens tilstand (2-minutters grænse). Rækkeantal før og efter i alle tabeller i
public og private: +1 i identitetshændelser, fortolkninger, observationer, promotioner og promotionsbatcher, 0 i
kanoniske tabeller. Ingen fortryd-vej; dumpet fra trin 4 er nødudvejen.

**Kørt i prod 2026-10-26** (repo `82039701`, GO 240 `ebffa718`): alle fire skridt gav det forventede, og shaen
`576215b99bfe` var uændret før og efter.

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
