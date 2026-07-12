# Danmarks Adels Aarbog — digital følgesvend (PoC: Reventlow)

Et levende, multimedie- og slægtskabssøgende **supplement** til det trykte DAA — ikke en
konkurrent. Kernefunktion: **"er vi i familie?"** (slægtskabssøgning på tværs af slægter).
Gratis for foreningens medlemmer, abonnement for forskere/genealoger. PoC afgrænset til
**familien Reventlow** (~922 personer, live i prod); lykkes den, er målet foreningens samlede data.

## Stack (rør ikke uden god grund)

- **Backend:** Supabase (Postgres + Auth + Storage + RLS + auto-API), **EU-region** (persondata om levende). Skema deployet.
- **Frontend:** TypeScript + React — `web/` (Vite, PWA-først) og `mobile/` (RN/Expo). Begge har læser- **og** redaktør-flade bundet af RLS.
- **Data / ETL:** **R** (DBI/RPostgres/dbplyr). Python-filer er kun reference — R er fremadrettet.
- **Interop:** GEDCOM 7 til import/eksport (intern model er rigere, fladgøres ved eksport).

## Kommandoer

| Spor | Kommandoer |
|---|---|
| `web/` | `npm run dev` · `npm run build` · `npm run test` (vitest) · Playwright e2e |
| `mobile/` | `npm start` · `npm run ios` / `npm run android` (expo) · `npm test` (jest) |
| Data (R) | `Rscript supabase_load.R` (seed/reload) · `Rscript run-tests.R` |
| DB | `schema.sql` = **source of truth** · `db-migrations.sql` (idempotent → prod) · `db-verify.sql` (asserts) · `db-rls.sql` (politikker) |

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

## Levende dokumentation (status/backlog bor IKKE her)

- `docs/README.md` — dokumentationsindeks (start her)
- `docs/database-current-state.md` — hvad der faktisk er i prod + deploy-procedure
- `docs/changelog.md` — dateret statushistorik (source of truth for "hvad er lavet")
- `docs/decisions.md` — arkitektur-/datamodel-beslutninger + åben backlog
- `datamodel-oversigt.md` — **autoritativ** konceptuel modelbeskrivelse (*hvorfor*)

---

use fable subagents when you need more intelligence
