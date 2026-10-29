# 5c-2 + B11 i prod: læseren ser placering og fakta med kilde

Spec: `docs/superpowers/specs/2026-10-29-5c2-b11-laeserflade-design.md`. Plan:
`docs/superpowers/plans/2026-10-29-5c2-b11-laeserflade.md`. Beslutninger: `docs/decisions.md` 2026-10-27 (B11) og
spec'ens §8 (projektejeren 2026-10-29). Scripts: `.claude/skills/daa-extract/scripts/maal_5c2_b11.sql` og
`check_5c2_coordinate_diff.sql`; forventningerne `5c2_forventet_maal.txt` og `5c2_forventet_diff.txt` samme sted.
Privat runner: `~/.private/5ab-overfoersel/24-5c2-b11.sh` (kørt gennem `koer.zsh`). Kører i projektejerens egen shell;
AI'en har ingen prod-forbindelse.

## Hvad der skrives

Additiv DDL, ingen data. Blokken `-- BEGIN 5c2-b11` … `-- END 5c2-b11` i `db-migrations.sql` (sha `97a69759…`) lægger
tre funktioner i én transaktion:

- `private.assertion_binding_current(uuid)`: genkontrollerer en trin 4-bindings identitet, faktatype og værdi mod
  promotionens gemte regel. Ingen grants.
- `public.public_person_facts(bigint[])`: personfakta med kilde; bindingen til bogens post, hvor den gælder.
  SECURITY DEFINER, EXECUTE til `anon` og `authenticated`.
- `public.public_person_source_coordinates()`: koordinater fra gældende placement, ellers legacy. SECURITY DEFINER,
  EXECUTE til `anon` og `authenticated`.

`person_source_coordinate_legacy`, validatoren og alle tabeller er uændrede. Klienten (PR 2) merges først efter
ceremonien og merge-gaten.

## Forløb (projektejerens shell)

Alle kommandoer køres som `/bin/zsh -f ~/.private/5ab-overfoersel/koer.zsh 24-5c2-b11.sh …` fra `main` efter merge af
PR 1.

1. `maal` → `C2B11_MAAL_OK tilstand=foer` (`C2B11_MAAL funktioner=0`).
2. `go` → `GO_5C2_KODE=<8 hex>` og commit. Projektejeren skriver `GO 5c2 <kode>`. Koden binder commit'en,
   `db-migrations.sql`, de to SQL-filer, begge forventningsfiler, målidentiteten, runneren og dens hjælpere.
3. `dump` → `DUMP_5C2_OK …` og `EKSTERN_5C2_OK … rundtur=ok` (B1: `age`-krypteret kopi på SFTP-serveren, hentet
   tilbage, sammenlignet og dekrypteret).
4. `apply --jeg-mener-det --go <kode>` →
   - `B1_5C2_OK …`: dumpet og den eksterne kopi er kvitteringens bytes.
   - blokken i én transaktion med `lock_timeout` 5 s, derefter `NOTIFY pgrst, 'reload schema'`.
   - `C2B11_APPLY_OK funktioner=3 C2B11_DIFF n=37 noegler=ens genparitet=ok log=…`: målingen efter er
     `5c2_forventet_maal.txt` byte for byte, og koordinatdiffen er præcis `5c2_forventet_diff.txt`.
5. `maal` → `C2B11_MAAL_OK tilstand=efter`.
6. `get_advisors` (sikkerhed): forventet at de to nye RPC'er meldes som SECURITY DEFINER-funktioner, der kan kaldes af
   `anon`/`authenticated`, som `public_family_sources`; intet andet nyt.
7. Merge-gate for PR 2: `node web/scripts/verify-public-rpcs.mjs` mod prod → `resultat=OK`.

## Prøvet (2026-10-29)

Stand-in `daa5ab_ddl_standin_20261029100000_5c2` (A6b-dumpet `58351421…`, ICU, `db-rls.sql`, `ANALYZE`, prods
2-minutters `statement_timeout`): blokken under 1 s; målingen 6 s.

| | Før | Efter |
|---|---|---|
| Målingen | `funktioner=0` | `funktioner=3 definer=2 anon=true auth=true` |
| Koordinater | — | 1.113 rækker: 530 placement, 583 legacy |
| Fakta | — | 6.473 rækker: 622 bundet til bogens post, 5.765 fra den oprindelige import, 86 uden kilde |
| Personer uden narrativ med fakta | — | 621 |
| Bindinger, der falder ud | — | 0 i alt, 0 på publiceringen |
| Koordinatdiff mod legacy-viewet | — | 37 felter: 32 kuld, 5 nr.-etiketter (15a/15b/15c, 41a/41b); `genparitet=ok` |

Tre af de 35 kuld-rettede personer er levende og skjules af persongaten; derfor 32. Stand-in'en mangler A6b's ti
narrativrevisioner (kun tekst), som ingen af tallene afhænger af.

## Fortrydelse

- **Særskilt handling:** revert af PR 2 (Vercel redeployer). Funktionerne bliver stående, så åbne klienter med den
  nye kode ikke degraderer; de fjernes først med en senere, besluttet `DROP FUNCTION`. Ingen data er skrevet, og
  legacy-viewet står.
- **Nødudvej:** restore af dumpet fra skridt 3. Efter en restore køres `db-rls.sql` igen.

## Kendte følger

- Læseren ser 32 kuld og 5 numre ændre sig. Det er rettelser fra 5c-1 (decisions 2026-10-26 pkt. 2). For de 4
  `mapped` uden identitet står legacy-værdierne tilbage.
- Kilde 1 og 3 er asymmetriske (placement mod legacy) indtil trin 6.
