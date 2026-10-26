# #248 skridt 1 i prod: to navnefælle-ægtefæller afgøres igen

Beslutning: `docs/decisions.md` (#248, 2026-10-26). Scripts: `.claude/skills/daa-extract/scripts/fix_248_identitet.sql`
og `fix_248_maal.sql`. Privat runner: `~/.private/5ab-overfoersel/19-fix-248.sh` (kørt gennem `koer.zsh`).

## Hvad der skrives

To identitetsafgørelser (version 1 → 2) med webfladens RPC og GO 248's arkkontekst:

| Sag | Ægteskab | Ægtefælle | Bundet i dag | Hører til |
|---|---|---|---|---|
| 1 | Iwan (94), 4° | 624 → 625 | familie 64 | familie 65 |
| 2 | Abel (286), 2° | 744 → 745 | familie 193 | familie 194 |

Den gamle binding holder derved op med at gælde, og læseren viser ikke længere kildeteksten på familie 64/193.
Bindingen til familie 65/194 kræver genåbning (rute A) og sker ikke her. Søskendeægteskaberne (3° og 1°) røres ikke.

## Procedure (projektejerens shell)

Repoet skal stå rent på den commit, GO-filen binder. GO 248-arket og rækkefilen skal være de godkendte bytes
(runneren stopper ellers med `GO248_ARK`/`GO248_ROWS`).

1. `koer.zsh 19-fix-248.sh go` → `GO248_KODE=<8 hex>`; projektejeren skriver `GO 248 <kode>`.
2. `koer.zsh 19-fix-248.sh maal` → `FIX248_MAAL_OK fase=foer`.
3. `koer.zsh 19-fix-248.sh dump` → `DUMP_248_OK …`.
4. `koer.zsh 19-fix-248.sh identitet --jeg-mener-det --go <kode>` → `FIX248_IDENTITET_OK identiteter=2
   bindinger_ophoert=2 soeskende_uroert=2`. Runneren kræver fase `foer` før og `efter` bagefter; scriptet har
   egne for- og efterbetingelser (`FIX248_PRE_*`/`FIX248_POST_*`) i samme transaktion.
5. `koer.zsh 19-fix-248.sh maal` → `FIX248_MAAL_OK fase=efter`.

Fasen `efter` betyder pr. sag: ny identitet (version 2), tilstanden på den rigtige familie, 0 gældende bindinger
for ægteskabet, søskendeægteskabets binding uændret, 1 offentlig kildetekst tilbage på den forkerte familie (søskendens)
og 0 på den rigtige.

## Prøvet

På en stand-in-kopi af prod efter #240 (2026-10-26): forkert GO-kode og manglende flag afvises; kørslen giver
`FIX248_IDENTITET_OK` og fase `efter`; en ny kørsel stopper (`fase efter, forventede foer`). Rækkeantal i alle 96
tabeller i public og private før og efter: kun `private.source_persona_identity_event` +2. Ingen DDL, så
sikkerhedsrådgiveren køres ikke.

## Fortrydelse

Ingen fortryd-vej: en identitetsafgørelse er append-only. Dumpet fra skridt 3 er nødudvejen.

## Kendte følger

- De to ægteskaber står `accepted` uden binding og ses ikke af nogen kø, før rute A er i prod. #248 holdes åben.
- Deres to `ordinal_afvigelse`-klassifikationer bliver uden binding (historik, intet at fortryde).
