# Runbook: visningscachens titel- og datoregel i prod (#396)

Udført 2026-11-20 (`database-current-state.md` §34). Runner `~/.private/visning-cache-396/prod.zsh` (privat, aldrig i
repoet), kørt med `/bin/zsh -f` i projektejerens shell; prod-skrivninger er spærret for agenten.

## Handlinger

| Handling | Hvad |
|---|---|
| `standin <dump> <suffiks>` | lokal stand-in fra et læsedump (`~/.private/5ab-overfoersel/koer.zsh 39-laesedump.sh`) |
| `tal` | læse-kun: regel anvendt? personer hvis seks `visning_*` afviger fra den nye regel |
| `apply [--jeg-mener-det]` | én transaktion; uden flaget ROLLBACK |
| `fortryd [--jeg-mener-det]` | prods egen definition fra før apply + regen af backfillen |

## Blok og invarianter

- Blokken `-- ===== visning-cache-regler` … `-- END visning-cache-regler` fra `db-migrations.sql` @ `5f115574`,
  sha `2488a570d804c7047abd395275aa108cbaa56c22e4854609ef39dafb3cd87545`. Runneren nægter, hvis målets
  `regen_person_visning` ikke er den forventede `max()`-version.
- Backfill = præcis {392, 1088}. Udeladt = {811, 852}: 811 efter projektejerens afgørelse (#401), 852 rettet
  redaktionelt. Drift før backfill uden for de udeladte skal være backfill-mængden, ellers stop.
- Efter backfill: kun backfill-personerne ændret og kun i `visning_titel`; ingen drift uden for de udeladte;
  `slaegtsnavn_karantaene` og `change_set`/`change_event` uændrede.

## Generalprøve (stand-in `daa5ab_ddl_standin_20261120123536_vc1`, dump `4a946268…`)

| Skridt | Resultat |
|---|---|
| tal | drift 4: 392, 811, 852, 1088 |
| apply (prøve) | drift efter 811, 852; 164 ms; ROLLBACK |
| apply → tal | regel anvendt; drift 811, 852 |
| fortryd → tal | 392 = storkansler, 1088 = Sekltnt.; drift 4 igen |
| apply med fremmed drift (person 44) | `VC_DRIFT_UVENTET`, rullet tilbage |

## Prod (2026-11-20)

| Skridt | Resultat |
|---|---|
| apply (prøve) | drift før 392, 811, 1088 (852 allerede rettet); efter 811; 2,4 s; ROLLBACK |
| apply --jeg-mener-det | samme; 1,2 s; COMMIT |
| tal (ny forbindelse) | regel anvendt; drift 811; 392 = Greve, 1088 = Fændrik ved sjæll. Inf.Reg.; floruit 232 |

## Fortrydelse

`/bin/zsh -f ~/.private/visning-cache-396/prod.zsh fortryd --jeg-mener-det`. Web er upåvirket. Floruit-fortrydelsen
(`docs/runbooks/visning-floruit-prod.md`) gemmer en ældre `regen_person_visning`: kører den, er `max()`-reglen
tilbage, og denne apply skal køres igen.
