# Runbook: rettighedsgaten mod prod (2026-09-20)

> **Status: UDFØRT.** PR #206 merget som `036176f` (10/10 CI-jobs grønne), anvendt i prod,
> hele læsefladen uændret, 8 anon-kaldbare gates tilbage som forudsagt, 0 medlems-orakler,
> billedet hentet som gæst, og alle 15 medie-fakta inkl. kreditlinje og fotograf stadig
> synlige. Rapport: `~/.private/medie-rettighedsgate/rettighedsgate-20260920075338Z.log`.

Lukker `media_rettigheder_ok` for gæster og medlemmer — og retter den lækage, der gjorde
et revoke umuligt i første omgang. Fortsættelsen af medie-indkapslingen (#204, `2271d0b`).

## Hvad der var galt

`entitet_offentlig('media', id)` afgør, om **fakta, noter, narrativer, relationer og
tekst-henvisninger på et medie** er synlige. Den gatede kun på rettigheder. Et
rettighedsfrigivet billede af en levende person var derfor selv skjult for gæster, mens
dets fakta — fotograf, kreditlinje, datering — var læsbare. GDPR-dimensionen faldt bort
ét lag inde.

Samme fejlklasse som `MM-01` (2026-08-06) rettede, hvor grenen ubetinget returnerede
`true`. Rettelsen dengang tog kun halvdelen med.

**Bevist mod prod-kopi**, ikke udledt af koden. Med den gamle regel genindsat:

```
fakta levende anon=1 (vent 0)  medlem=1 (vent 0)    ← faktummet læsbart
levende=0                                            ← mens billedet selv var skjult
```

## Ændringen

| Greb | Hvorfor |
|---|---|
| `entitet_offentlig`s media-gren → `media_synlig_anon` | Begge dimensioner, samme regel som media-rækken selv |
| `entitet_offentlig` **flyttet ned** under `media_synlig_anon` | SQL-kroppe valideres ved `CREATE` |
| `media_synlig_auth` → `SECURITY DEFINER` | Ubrugt i politikker, men som INVOKER tvang den `authenticated`s grant åbent |
| `media_rettigheder_ok` tilbagekaldt fra `public, anon, authenticated` | Efter de tre greb er alle kaldere DEFINER-lag |
| Vagten udvidet | Kræver at `media_synlig_auth` + `entitet_offentlig` er DEFINER, og at `entitet_offentlig` **faktisk** gater media på synlighed |
| `db-migrations.sql`s konkurrerende definition afstemt | Den overskrev `entitet_offentlig` med den gamle gren, så `db-rls → db-migrations` degraderede gaten lydløst |
| `media_afbilder_privat` + `media_synlig_auth` lukket for `authenticated` | Direkte orakler over mere, end medlemstieren selv kan se |

Definitionsrækkefølgen i filen er nu en forudsætning:
`media_rettigheder_ok` → `media_id_for_object` → `media_synlig_anon`/`_auth` →
`entitet_offentlig` → `media_object_synlig_anon`.

## Afprøvet før prod

Engangskopi via `createdb -T`, baseline lagt med `origin/main`s `db-rls.sql` = prod i dag.

- **Hele læsefladen uændret** før/efter for både anon og medlem: 6864 fakta (md5 ens),
  2008 relationer (md5 ens), 1115 narrativer, 987 noter, 0 tekst-henvisninger, 13 medier,
  33 storage-objekter.
- **Men det beviser intet af sig selv:** 0 af 13 medier er skjulte i prod, så reglen har
  ingen rækker at skelne på. Den syntetiske fixture i `db-verify` Task 8 er hele prøven —
  to fakta, ét på et skjult og ét på et synligt medie, begge rettighedsfrigivne.
- Hele katalogets delta: **nøjagtig 6 linjer**, alle tilsigtede (`entitet_offentlig` krop,
  `media_rettigheder_ok` ACL med krop UÆNDRET, `media_synlig_auth` `prosecdef` med krop
  UÆNDRET).
- Negative kontroller: gammel regel genindsat → fixturen fælder den; `media_synlig_auth`
  som INVOKER og `entitet_offentlig` på rå rettigheder → `MEDIE_INDKAPSLING_BRUDT`.
- **Rækkefølgen `db-rls → db-migrations` afprøvet særskilt**, fordi det var netop den, der
  degraderede gaten før. Negativ kontrol med den gamle migration: `RETTIGHEDER — LAEKAGEN
  ER TILBAGE`. Efter rettelsen: `SYNLIGHED`.
- Fortryd-scriptet ramte udgangspunktet præcist (tom `diff`).
- CI's egen sekvens: exit 0, 120 OK-linjer.

## Rækkefølge

CI grøn **før** prod.

1. Push + `--draft` PR (push er gated — spørg først)
2. Alle CI-jobs grønne
3. Tør kørsel
4. Anvend
5. Browser-/API-tjek + advisor-optælling
6. Markér PR klar og merge

## Kørsel

Prod-skrivning går gennem din egen shell (`! zsh …`).

```
zsh ~/.private/medie-rettighedsgate/rettighedsgate-apply.zsh                  # tør
zsh ~/.private/medie-rettighedsgate/rettighedsgate-apply.zsh --jeg-mener-det  # anvend
```

Scriptet kræver `--jeg-mener-det`, afviser ukendte argumenter, kræver et rent repo på
`main` (eller arbejdsgrenen), og har en **indholds**-vagt: `db-rls.sql` skal bære både
`media_synlig_anon(p_id)`-grenen og medie-indkapslingen.

**Låsevindue:** hele filen i én transaktion holder `AccessExclusiveLock` på alle
politik-bærende tabeller, til den committer. Målt lokalt: ~0,1 s. Kør i en stille periode.

**Acceptkriteriet i rapporten:** blokken "hele læsefladen" skal være **uændret**, md5 og
alt. Ændrer ét tal sig, er noget galt — fortryd.

## Efter anvendelsen

1. Hent et rigtigt billede som gæst (signeret URL) — samme prøve som ved #204.
2. Tæl anon-kaldbare `SECURITY DEFINER`-funktioner. `media_rettigheder_ok` skal være væk;
   forvent **8** uden for `red_*` (de 9 fra 20/9 minus denne). Tæl også de
   *authenticated*-kaldbare: `media_afbilder_privat` og `media_synlig_auth` skal være væk
   dér.
3. Se en medie-detaljeside i webfladen som gæst: kreditlinje og fotograf skal stadig vises
   for et **synligt** billede. Det er den ene ting, denne ændring kunne skjule ved en fejl.

## Fortrydelse

```
psql -X -v ON_ERROR_STOP=1 -f ~/.private/medie-rettighedsgate/rettighedsgate-fortryd.sql
```

Én transaktion, fail-closed readback (anon skal se fakta, relationer og medier bagefter).
**Bemærk:** fortrydelsen genåbner lækagen — fakta på et GDPR-skjult medie bliver læsbare
for gæster igen. Fortryd kun hvis noget faktisk gik galt, og lad være med at merge imens.
