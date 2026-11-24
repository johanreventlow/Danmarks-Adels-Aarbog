# Fuld personsletning — færdigbevis (Task 13, prod 18/11)

Alle ni personer på slettelisten er slettet i prod og kontrolleret. Ingen DDL i ceremonien (den kom med record_persona,
main `aca139a0`). Runbook: `docs/runbooks/personsletning-prod.md`. Runner: `~/.private/5ab-overfoersel/43-personsletning.sh`
fastlåst til main `57a7fd44` (#386). Kun id'er, antal og tabelnavne her.

> Review 37 P7: de ni var fejlprofiler, dubletter og importfejl (dataoprydning), ikke GDPR-anmodninger. Et færdigbevis
> for en **GDPR-sletning** må ikke ligge i git; se `docs/runbooks/personsletning-prod.md`, »Ægte GDPR-sletning«.

## Dumps (vejen tilbage)

| Dump (`~/.private/…/prod/laesedump/`) | sha256 (start) | Taget før |
|---|---|---|
| `daa-prod-20261118175533-laes.dump` | `823d0d8d` | 1791 |
| `daa-prod-20261118181138-laes.dump` | `aa1ae54d` | 1823, 1824 |
| `daa-prod-20261118191613-laes.dump` | `845d77ff` | 963, 1795, 1620, 1135, 940, 1814 |

Alle kan læses (`pg_restore --list`, 144 tabeller med data). Et dump gendanner alle personer, det dækker.

## Pr. person

| id | slettet via | forhåndsvisning (steder / blok. / adv.) | sletning | `efter` | Q9 / `tilbage` |
|---|---|---|---|---|---|
| 1791 | Redaktion | 32 / 0 / 0 | – | nul-kontrol OK, REST_OK | narrativ 867 (bog, 1198) |
| 1823 | Redaktion | 25 / 0 / 0 | – | nul-kontrol OK, REST_OK (id+link) | S58c=5 |
| 1824 | Redaktion | 20 / 0 / 0 | – | nul-kontrol OK, REST_OK (id+link) | – |
| 963 | runner `slet` | 1118 / 0 / 2 | 3,7 s | nul-kontrol OK, REST_OK (id+link) | S44=2, S52=1, S54b=1, S57=7 |
| 1795 | Redaktion | 14 / 0 / 0 | – | nul-kontrol OK, REST_OK (id+link) | – |
| 1620 | Redaktion | 199 / 0 / 2 | – | nul-kontrol OK, REST_OK | narrativ 875 (bog, 1206) |
| 1135 | runner `slet` | 818 / 0 / 0 | 4,0 s | nul-kontrol OK, REST_OK (id+link) | S53=1 |
| 940 | runner `slet` | 1132 / 0 / 2 | 16,4 s | nul-kontrol OK, REST_OK (id+link) | – |
| 1814 | Redaktion | 10 / 0 / 1 | – | nul-kontrol OK, REST_OK | narrativ 596 (bog, 927) + én citation |

`verify` (personsletningens afsnit af `db-verify.sql`, READ ONLY) er grøn efter hver runde (1791; 1823+1824; de seks).
Udbakken var tom for alle (`storage_antal=0`).

## Afvigelser under ceremonien

- **Efter-kontrollen var for streng/for svag og blev rettet undervejs** (øvet på stand-in før brug i prod):
  tælleren gater nu med `count.sql`'s egen nul-kontrol og før-mængder; navnetjekket springes over for personer med
  navnefæller (1823/1824 er dubletter af 1613/1614, 1795 har tomt navn, 963/1135/940 deler navn med andre);
  S41b/bog dækker også `legacy_payload` (#386, til 1620).
- **1823 blev slettet uden `foer`.** Før-filen er prod-målingen taget tidligere samme aften (byte-ens med en måling
  på dumpet `aa1ae54d`); før-mængderne kommer fra dumpet. Begge mapper har `KILDE.txt`.
- **1824's første sletning gik ikke igennem.** `efter` stoppede (»findes stadig«); rigtig `foer` i prod, derefter
  sletning.
- **963 fik gentagne »Det tog for lang tid« i Redaktion** (8 s-loftet). 963, 1135 og 940 blev slettet med runnerens
  `slet`: samme RPC som authenticated med redaktørens uid, 90 s, forhåndsvisning og sletning i én transaktion, og
  projektejerens godkendelse bundet til antal steder (`--steder N`; forkert antal → intet slettet).

## Tid (prod, `tid`, læse-kun)

Første forhåndsvisning i kold base 7,2 s (og > 8 s ved en tidligere måling); varm 1,2–2,1 s. Sletning via runner
3,7 / 4,0 / 16,4 s for profiler med 818–1132 steder.
