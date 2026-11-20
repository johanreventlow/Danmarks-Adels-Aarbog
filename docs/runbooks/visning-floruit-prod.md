# Runbook: `visning_floruit` i prod (Task 4)

Plan: `docs/superpowers/plans/2026-11-19-visning-floruit.md` (Task 4). Spec:
`docs/superpowers/specs/2026-11-19-visning-floruit-design.md`. Kode: PR #398, merget som `5e274f54`.

## Udgangspunkt

- **Rækkefølgen blev brudt 20/11:** #398 blev merget før prod-DDL. Vercel deployede main ca. 3 minutter efter, og
  web's person-hentning fejlede med `42703 column person.visning_floruit does not exist`. Projektejeren rullede
  produktion tilbage med Vercels Instant Rollback (bundt `index-DfPw3TVN.js`). **Efter en Instant Rollback promoverer
  Vercel ikke nye main-deploys automatisk**, før projektejeren selv promoverer igen (trin 5).
- **Kun blokken, aldrig hele filen** (stopregel A1, `docs/decisions.md`): runneren klipper blokken
  `-- ===== visning-floruit: »Nævnes …« som cache =====` … `-- END visning-floruit` ud af `db-migrations.sql` ved den
  fastlåste commit `5e274f54` og kræver sha `856e1ecf…`. Blokken er filens hale, og der er ingen anden SQL-ændring i
  main siden record_persona-ceremonien 18/11 (`git log aca139a0..5e274f54 -- db-migrations.sql db-rls.sql schema.sql`
  viser kun floruit-commits). `db-rls.sql` er uændret og køres ikke; blokken har sin egen eksplicitte
  `REVOKE … FROM PUBLIC, anon, authenticated, service_role`.
- **Runner:** `~/.private/visning-floruit/prod.zsh` (aldrig i repoet). Kaldes fra repo-roden med `/bin/zsh -f`.
  Bruger `~/.private/5ab-overfoersel/lib.zsh` til forbindelsen (Session pooler, prods faste målidentitet) og
  udskriver kun id'er, antal og tider.

## Hvad `apply` gør (ÉN transaktion)

1. `SET LOCAL lock_timeout = '5s'`, `statement_timeout = '110s'`.
2. **Uden for låsevinduet** (kun læselåse): snapshot af alle personrækker som `to_jsonb(person) - 'visning_floruit'`,
   antal `change_set`/`change_event`, og facit: forventet `(id, floruit)` beregnet uafhængigt efter spec §5 med
   `least`/`greatest` pr. række og livsdato-reglen.
3. **Låsevinduet** (`ALTER TABLE person` og `DROP TRIGGER` tager ACCESS EXCLUSIVE til COMMIT/ROLLBACK): blokken,
   katalogtjekket `OK: visning-floruit katalog` (sha `9c14704a…`) og backfill `SELECT regen_person_floruit(id) FROM
   person` (ruling R5).
4. Invarianter, ellers ROLLBACK med kun id'er i fejlen:
   - personrækkerne er uændrede bortset fra `visning_floruit` (EXCEPT begge veje = 0);
   - `change_set`/`change_event` uændrede;
   - `(id, visning_floruit)` = facit (EXCEPT begge veje = 0);
   - ingen person har både floruit og livsdatoer.
5. Uden `--jeg-mener-det`: ROLLBACK (prøvekørsel; tager stadig låsene et øjeblik). Med flaget: `NOTIFY pgrst,
   'reload schema'` og COMMIT.

Facit-sammenligningen læser samme cachede `visning_foedt`/`visning_doed` som funktionen. Den efterprøver altså spænd,
offentlighedsregel og konfidensfilter, ikke selve livsdato-reglen; den dækkes af db-verify's `livsdatoer`-blok.

Før transaktionen gemmer `apply` målets egne definitioner af `regen_person_visning`, `trg_regen_from_conclusion`,
`trg_regen_from_assertion` og triggerne `trg_conclusion_regen`/`trg_assertion_regen` (læse-kun). Ved COMMIT kopieres
de til `~/.private/visning-floruit/fortryd-definitioner.prod.sql`.

## `fortryd`

Dropper de to nye triggere, genskaber de gemte definitioner, dropper de fire nye funktioner og sætter
`visning_floruit = NULL` i én transaktion (samme `lock_timeout`). Kolonnen, `skip_cols` og sletteinventarets S1
bliver stående: `red_slet_person_helt`'s kandidatkolonne-vagt kræver, at alle person-kolonner står i inventaret, og en
tom kolonne er ufarlig. **Web på main læser kolonnen**, så fortryd i prod kræver også, at Vercel står på et bundt fra
før #398 (Instant Rollback).

## Generalprøve (20/11, stand-in fra `daa-prod-20261118191613-laes.dump`)

Stand-in `daa5ab_ddl_standin_20261120103420_vf1` med prods standardrettighed efterlignet (nye funktioner får EXECUTE
til anon/authenticated/service_role, som når `postgres` opretter dem i prod), så blokkens REVOKE blev afprøvet mod
samme udgangspunkt.

| Trin | Resultat |
|---|---|
| `apply` (prøve) | facit 232, backfill 1808 personer, `floruit=232 spaend=33`, invarianter OK, transaktion 231 ms (51 ms før blokken), ROLLBACK |
| `apply --jeg-mener-det` | samme tal, 206 ms, COMMIT |
| `apply` igen | afvist: `VF_ALLEREDE_ANVENDT` |
| `fortryd` (prøve, så commit) | 232 nulstillet, 15 ms; nye funktioner/triggere væk, gamle definitioner tilbage, `trg_conclusion_regen`/`trg_assertion_regen` findes |
| `fortryd` igen | afvist: `VF_IKKE_ANVENDT` |
| `apply --jeg-mener-det` efter fortryd | samme tal, 206 ms, COMMIT; gemte fortryd-definitioner identiske i alle tre kørsler |
| `db-verify.sql` @ `5e274f54`, fuld | rc 0, 155 OK, heraf alle seks `visning-floruit`-blokke (44 s; dblink og lokal `REVOKE EXECUTE … FROM PUBLIC`-standard som ved tidligere generalprøver) |

`VF_INFO omvendte_paastande=0`: ingen påstand i dumpet har `date_min > date_max`.

Prods tal kan afvige fra stand-in'ens, hvis data er ændret siden 18/11. Det er i orden, fordi facit beregnes i samme
transaktion. **Det forventede antal er prøvekørslens tal i prod (trin 2), ikke 232.**

## Ceremoni (projektejeren kører; sessionen læser udskriften)

1. **Tjek:** `/bin/zsh -f ~/.private/visning-floruit/prod.zsh tal` → `VF_TAL kolonne=mangler`.
2. **Prøvekørsel:** `/bin/zsh -f ~/.private/visning-floruit/prod.zsh apply` → `NOTICE: OK: visning-floruit katalog`,
   `VF_INVARIANTER_OK`, `VF_ROLLBACK`, `VF_APPLY_PROEVE_OK`. Notér `VF_TAL` og `VF_TID_TRANSAKTION`.
   Ved `lock_timeout`/`55P03`: en læser holdt en lås i 5 s. Intet er ændret; kør igen.
3. **Commit** (efter eksplicit ja): `… prod.zsh apply --jeg-mener-det` → samme tal som trin 2, `VF_COMMIT`,
   `VF_APPLY_COMMIT_OK`.
4. **Efterkontrol:** `… prod.zsh tal` → `VF_TAL` som trin 3 og `VF_TRIGGERE nye=2`. Sessionen kalder REST som anon:
   `person?select=id,visning_floruit` svarer 200, og person 44 har `1349–1391`.
5. **Vercel:** projektejeren promoverer den nyeste produktions-deploy fra main (`5e274f54` eller nyere).
   Sessionen tjekker, at live-bundtet læser `visning_floruit`, og browsertjekker som anon (desktop og mobil):
   44 viser »Nævnes 1349–1391«; 392 (Conrad) er uændret; en person uden dato viser ingen årslinje.
6. **Advisors:** projektejeren kører Security Advisor i dashboardet (MCP når ikke prod): ingen nye fund.
7. **Dokumentation:** `docs/database-current-state.md` (§33), `docs/changelog.md`, `docs/decisions.md`.
