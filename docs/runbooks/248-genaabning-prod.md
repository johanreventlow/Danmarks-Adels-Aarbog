# #248 rute A i prod: genåbning ved familieskift

Beslutning: `docs/decisions.md` (#248, 2026-10-26). Spec: `docs/superpowers/specs/2026-10-26-248-genaabning-ved-familieskift-design.md`.
Forudsætning: skridt 1 er kørt (`docs/runbooks/fix-248-identitet-prod.md`, GO 248, fase `efter`).
Scripts: `.claude/skills/daa-extract/scripts/fix_248_genaabn.sql`, `fix_248_maal.sql` og `fix_248_a_fingeraftryk.sql`.
Privat runner: `~/.private/5ab-overfoersel/20-248-a.sh` (kørt gennem `koer.zsh`). Kører i projektejerens egen shell;
AI'en har ingen prod-forbindelse.

## Hvad der skrives

1. **DDL:** genåbnings-blokken i `db-migrations.sql` (mellem `-- Genåbning ved familieskift (#248 …` og
   `-- Genåbnings-blokken slutter her.`) lægges i én transaktion. Det er tabellen `private.relation_reopen`, RPC'en
   `public.red_genaabn_relation_interpretation` og nye definitioner af `private.relation_binding_state` (vagten mod
   to ægtefæller i samme post til samme person) og `private.spouse_exception_projection` (`post_rivals`). Ingen data.
   Blokken er sha-bundet i runneren.
2. **Data:** de to ægteskaber genåbnes (ny `proposed`-version med GO 248's arkkontekst), afgøres og bindes til den
   rigtige familie i én transaktion:

| Sag | Ægteskab | Afgjort for | Bindes til |
|---|---|---|---|
| 1 | Iwan (94), 4° | familie 64 | familie 65 |
| 2 | Abel (286), 2° | familie 193 | familie 194 |

Søskendeægteskaberne (3° på familie 64, 1° på familie 193) røres ikke.

## Forventede tilstande

`20-248-a.sh maal` viser fingeraftrykket af rute A's DDL og fasen fra `fix_248_maal.sql` og stopper ved alt andet
end disse tre kombinationer:

| Efter | `ddl248a` | `fase` |
|---|---|---|
| skridt 1 (i dag) | `foer` | `efter` |
| DDL | `efter` | `efter` |
| genåbning | `efter` | `bundet` |

Fasen `bundet` betyder pr. sag: ægtefællen er den rigtige (version 2), tilstanden og den ene gældende binding er på
den rigtige familie, søskendeægteskabets binding er uændret, 1 offentlig kildetekst på hver af de to familier, og
1 række i `private.relation_reopen`.

## Forløb

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 20-248-a.sh …`. Repoet skal stå rent på
`main` efter merge af PR'en, og GO 248-arket og rækkefilen skal være de godkendte bytes (ellers `GO248_ARK`/`GO248_ROWS`).

1. `go` → `GO248A_KODE=<8 hex>` og commit. Projektejeren skriver `GO 248A <kode>`.
2. `maal` → `MAAL_248A_OK ddl248a=foer fase=efter`.
3. `dump` → `DUMP_248A_OK …` (fuldt dump i en læsetransaktion før første skrivning).
4. `advisors` → `ADVISORS_248A_OK nye=0` (mod GO 1's `advisors-after.txt`).
5. `ddl --jeg-mener-det --go <kode>` → `DDL248A_OK`. Runneren tjekker fingeraftrykket `foer`, fasen `efter` og
   blokkens sha, lægger blokken i én transaktion (statement_timeout 15 min), genindlæser PostgREST-skemaet og
   tjekker fingeraftrykket `efter` og fasen igen.
6. `maal` → `MAAL_248A_OK ddl248a=efter fase=efter`.
7. `advisors` → `ADVISORS_248A_OK nye=1`. Det ene nye fund skal være `rls_enabled_no_policy|private.relation_reopen`
   (med vilje: kun SECURITY DEFINER-RPC'en skriver i tabellen); alt andet stopper.
8. `genaabn --jeg-mener-det --go <kode>` → `FIX248A_GENAABN_OK genaabnet=2 afgjort=2 bundet=2`. Runneren kræver
   fasen `efter` før og `bundet` bagefter; scriptet har egne for- og efterbetingelser (`FIX248A_PRE_*`,
   `FIX248A_MID_*`, `FIX248A_POST_*`) i samme transaktion.
9. `maal` → `MAAL_248A_OK ddl248a=efter fase=bundet`.

## Noter

- `fix_240_maal.sql`'s `ddl151`-fingeraftryk ændres af DDL'en (den omfatter `relation_binding_state`). Det er ikke
  drift; `18-fix-240.sh maal` vil derefter melde `ddl151=ukendt`.
- Overførselsværktøjets digests afviger fra GO 2-pakken. Det er forventet.
- `public_family_sources` over alle familier må højst blive 20 % langsommere end før DDL'en.

## Prøvet

På en frisk kopi af stand-in'en af prod efter skridt 1 (dump `8d17f579…`, 2026-10-26) med
`statement_timeout='2min'` på basen, som i prod, og hele forløbet gennem runneren (øvelsens GO-kode `d65dd787`):

- Alle ni skridt gav det forventede. Advisors før: 0 nye; efter: netop `private.relation_reopen`.
- Afvist: manglende `--jeg-mener-det`, ukendt argument, forkert GO-kode, `genaabn` før DDL'en, `ddl` igen
  (fingeraftrykket er `efter`) og `genaabn` igen (fasen er `bundet`).
- Rækkeantal i alle tabeller i public og private før og efter: `private.interpretation` +4 (2 genåbnet + 2 afgjort),
  `private.interpretation_observation` +4 (1 link pr. version), `private.relation_reopen` +2,
  `private.interpretation_promotion` +2 og `private.interpretation_promotion_batch` +1. Ingen ændring i `public.*`,
  beslutnings- eller klassifikationstabeller.
- `public_family_sources` over alle familier: 258 → 260 rækker; median af 3 målt til 518 ms efter mod 463 ms
  før (+12 %).

## Fortrydelse

- **DDL'en:** de gamle definitioner af `relation_binding_state` og `spouse_exception_projection` står i dumpet fra
  skridt 3 (`pg_restore -l` / `-P`). Tabellen og RPC'en kan fjernes, så længe tabellen er tom (før skridt 8);
  ikke prøvet.
- **Data:** ingen fortryd-vej. Genåbning, afgørelse og binding er append-only. Dumpet fra skridt 3 er nødudvejen.

## Kendte følger

- De gamle bindinger til familie 64/193 står tilbage som historik; `relation_reopen.superseded_promotion_id` peger
  på dem.
- #248 kan lukkes, når skridt 9 er grønt.
