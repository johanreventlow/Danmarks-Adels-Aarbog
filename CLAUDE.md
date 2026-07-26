# Danmarks Adels Aarbog — digital følgesvend (PoC: Reventlow)

Et levende, multimedie- og slægtskabssøgende **supplement** til det trykte DAA — ikke en
konkurrent. Kernefunktion: **"er vi i familie?"** (slægtskabssøgning på tværs af slægter).
Gratis for foreningens medlemmer, abonnement for forskere/genealoger. PoC afgrænset til
**familien Reventlow** (live i prod — aktuelle tal: `docs/database-current-state.md`); lykkes den, er
målet foreningens samlede data.

## Stack (rør ikke uden god grund)

- **Backend:** Supabase (Postgres + Auth + Storage + RLS + auto-API), **EU-region** (persondata om levende). Skema deployet.
- **Frontend:** TypeScript + React — `web/` (Vite, PWA-først) og `mobile/` (RN/Expo). Begge har læser- **og** redaktør-flade bundet af RLS.
- **Data / ETL:** Python til udtræk/segmentering/validering (`.claude/skills/daa-*/scripts/`); **R** (DBI/RPostgres/dbplyr) til DB-load-laget.
- **Interop:** GEDCOM 7 til import/eksport (intern model er rigere, fladgøres ved eksport).

## Kommandoer

| Spor | Kommandoer |
|---|---|
| Monorepo | npm workspaces, ÉN rod-lockfile → `npm ci` fra roden, kør pr. workspace: `npm run test -w @daa/core`. Delt DOM/RN-fri kerne: `packages/core` + `packages/feed`. |
| `web/` | `npm run dev` · `npm run build` · `npm run test` (vitest) · `npm run e2e` (Playwright) |
| `mobile/` | `npm start` · `npm run ios` / `npm run android` (expo) · `npm test` (jest) |
| Data | Indgange: `/daa-extract` (stamtavle) · `/daa-presens` (præsensliste) · `/daa-haendelser`. Load går gennem skill'ens `load_daa.R` (append/staged) — **`supabase_load.R` i roden er historisk, brug den aldrig mod prod.** `Rscript run-tests.R` = R-suiten. |
| DB | `schema.sql` = **source of truth** · `db-migrations.sql` (idempotent → prod) · `db-verify.sql` (asserts) · `db-rls.sql` (politikker) |
| CI | `.github/workflows/ci.yml` — 6 jobs skal være grønne: core · feed · r · pipeline · web · mobil (m. `tsc --noEmit`) |

Hemmeligheder ligger i `~/.Renviron` / env-variabler — aldrig i kode eller git.

## Datamodellens invarianter (SKAL respekteres)

1. **Evidensbaseret.** Et forhold = uforanderlige **påstande** (én kildes udsagn, kildebundne) + én foranderlig **konklusion** ovenpå. Gælder fakta *og* relationer. Påstande overskrives aldrig — rettelse = ny påstand + ny konklusion.
2. **Lille fast entitetssæt + én generisk, polymorf relation** (rolle + periode + kilde + konfidens; enhver entitet → enhver entitet). Nye behov bliver nye *rolle-/faktatyper* (data), ikke nye tabeller.
3. **Alt er et faktum.** Events/attributter = `fact` på enhver entitet (også sted, ejendom, våben har egne tidslinjer).
4. **Cache er en envejs-projektion.** `person.visning_*` og `person.koen` afledes af konklusioner — **redigér aldrig direkte**; regenereres når en konklusion ændres.
5. **Fuzzy datoer** = `(date_min, date_max)` + kvalifikator + rå tekst (gem altid originalen). Floruit (dokumenteret-aktiv span) ≠ levetid.
6. **Narrativ vs. struktureret.** Lang biografisk prosa bevares ordret i `narrative` (fuldtekstsøgbar); strukturerede fakta udtrækkes *selektivt* — kun hvor de bærer rygrad, forbindelse eller funktion.
7. **Konfidens på links.** `family_member.konfidens` (sikker/sandsynlig/formodet/omstridt) flager usikre slægtskaber; finderen skal *vise* usikkerhed, ikke skjule den.
8. **GDPR indbygget.** `person.levende` styrer synlighed (afdøde relativt åbne, levende kræver samtykke) — er også forretningsmodellen, kortlagt på RLS.
9. **Kontrolleret vokabular.** `slags`/`type`/`rolle`/`dekoration`/`koen` trækker på `vocab`-tabellen, så "samme slags"-forespørgsler er pålidelige.

## Faldgruber

- **Supabase:** brug *Session pooler* (IPv4), `sslmode=require`, EU-region. Free-tier pauser efter 7 dages inaktivitet (hold varm før live-demo) og har ingen backup — hold et dump i repo'et.
- **Hver trykt DAA-udgave er en selvstændig `source`** — så modstridende udgaver håndteres indfødt.
- **Arbejdsmapper indeholder PII:** `work/`, `work_1939_stamtavle/`, `work_presens/` (gitignoreret) rummer prosa om levende personer — commit dem aldrig, send dem aldrig til en model (invariant 8).

## Levende dokumentation (status/backlog bor IKKE her)

- `docs/README.md` — dokumentationsindeks (start her)
- `docs/database-current-state.md` — hvad der faktisk er i prod + deploy-procedure
- `docs/changelog.md` — dateret statushistorik (source of truth for "hvad er lavet")
- `docs/decisions.md` — arkitektur-/datamodel-beslutninger + åben backlog
- `datamodel-oversigt.md` — **autoritativ** konceptuel modelbeskrivelse (*hvorfor*)

---

use fable subagents when you need more intelligence

## Codex til udvikling og review

`codex:codex-rescue` kan bruges til afgrænsede udviklingsopgaver — ikke kun fejlretning — samt til review og adversarial review (Codex er stærk til at finde problemer i eget eller andres arbejde). Vælg model efter opgavens sværhedsgrad:

- `gpt-5.6-sol` — høj intelligens: arkitektur/refactors på tværs af flere filer, DB-migrationer, alt der kræver dømmekraft
- `gpt-5.6-terra` — almindelig: afgrænsede, veldefinerede opgaver (én komponent, én testfil)
- `gpt-5.6-luna` — lavest intelligens: rene rutineopgaver (mekaniske omdøbninger, oprydning, ensartede gentagne rettelser)
