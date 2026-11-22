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
| Monorepo | npm workspaces, ÉN rod-lockfile → `npm ci` fra roden, kør pr. workspace: `npm run test -w @daa/core`. Delt DOM/RN-fri kerne: `packages/core` + `packages/feed`; fælles designværdier (farver, skrifter, afstande) i `packages/theme` (kopi af designsystemets `tokens.json`; kopiér igen ved ændringer). |
| `web/` | `npm run dev` · `npm run build` · `npm run test` (vitest) · `npm run e2e` (Playwright) |
| `mobile/` | `npm start` · `npm run ios` / `npm run android` (expo) · `npm test` (jest) |
| Data | Indgange: `/daa-extract` (stamtavle) · `/daa-presens` (præsensliste) · `/daa-haendelser`. Genimport og nye udgaver går gennem evidenskæden (`docs/evidensbaseret-genimport/`). **`load_daa.R`, `post_load_fixup.R` og `backfill_slaegtled.R` er frosset** (lukket ved kontrakt v2; `docs/decisions.md` 2026-10-27, B5), og **`supabase_load.R` i roden er historisk, brug den aldrig mod prod.** `Rscript run-tests.R` = R-suiten. |
| DB | `schema.sql` = **source of truth** · `db-migrations.sql` (idempotent → prod) · `db-verify.sql` (asserts) · `db-rls.sql` (politikker) |
| CI | `.github/workflows/ci.yml` — kører kun på PR'er (ikke docs/`.md`-rene) + manuelt (`workflow_dispatch`), **ikke** ved push til main: Actions-minutter er begrænsede. 7 jobs: node (core · feed · theme · web · mobil m. `tsc --noEmit`) · r · python · 4 PostgreSQL-jobs. node, R og python kører ved enhver ikke-docs-PR; jobbet `changes` springer de fire PostgreSQL-jobs over, når PR'en kun rører `web/`/`mobile/`/`packages/`/`package*.json` (~11 min mod ~30); manuel start kører alt. Saml rettelser i få PR'er, push først når en PR er færdig, og brug `[skip ci]` i mellemliggende push |

Hemmeligheder ligger i `~/.Renviron` / env-variabler — aldrig i kode eller git.

## Datamodellens invarianter (SKAL respekteres)

1. **Evidensbaseret.** Et forhold = uforanderlige **påstande** (én kildes udsagn, kildebundne) + én foranderlig **konklusion** ovenpå. Gælder fakta *og* relationer. Påstande overskrives aldrig — rettelse = ny påstand + ny konklusion. *Undtagelser:* OCR-rettelse (`red_ret_ocr_felt`) retter transskriptionen i stedet for at skabe en ny påstand; originalen bevares i `import_korrektion` og `change_event` (`docs/decisions.md` 2026-10-27, B12). Tilsvarende retter `red_ret_ocr_paastand` en importeret kildepåstand uden importanker; originalen står i `paastand_korrektion` (grund `ocr`) og `change_event` (decisions 2026-11-20). `red_slet_oplysning` kan slette en påstand; importerede (`uforanderlig`) påstande spærres i reviewets trin B (1d.1-02).
2. **Lille fast entitetssæt + én generisk, polymorf relation** (rolle + periode + kilde + konfidens; enhver entitet → enhver entitet). Nye behov bliver nye *rolle-/faktatyper* (data), ikke nye tabeller.
3. **Alt er et faktum.** Events/attributter = `fact` på enhver entitet (også sted, ejendom, våben har egne tidslinjer).
4. **Cache er en envejs-projektion.** `person.visning_*` afledes af konklusioner — **redigér aldrig direkte**; regenereres når en konklusion ændres. (`person.koen` er en arbejdsværdi direkte på personen, jf. `datamodel-oversigt.md`, og skrives af `red_set_koen` — review 1b-12.)
5. **Fuzzy datoer** = `(date_min, date_max)` + kvalifikator + rå tekst (gem altid originalen). Floruit (dokumenteret-aktiv span) ≠ levetid.
6. **Narrativ vs. struktureret.** Lang biografisk prosa bevares ordret i `narrative` (fuldtekstsøgbar); strukturerede fakta udtrækkes *selektivt* — kun hvor de bærer rygrad, forbindelse eller funktion.
7. **Konfidens på links.** `family_member.konfidens` (sikker/sandsynlig/formodet/omstridt) flager usikre slægtskaber; finderen skal *vise* usikkerhed, ikke skjule den.
8. **GDPR indbygget.** `person.levende` styrer synlighed (afdøde relativt åbne, levende kræver samtykke) — er også forretningsmodellen, kortlagt på RLS.
9. **Kontrolleret vokabular.** `slags`/`type`/`rolle`/`dekoration`/`koen` trækker på `vocab`-tabellen, så "samme slags"-forespørgsler er pålidelige.

## Evidensbaseret genimport — bindende styringsgrundlag

Ved arbejde med DAA-import/genimport, source records/personas, fortolkning,
identitetsafstemning, promotion eller importpublicering: læs først, i rækkefølge,
`docs/evidensbaseret-genimport/vision.md`, `roadmap.md`,
`teknisk-maalarkitektur.md` og `status.md`.

Før en plan eller implementering skal opgaven kobles til roadmapmål,
værdikædeled, leverancetype, redaktionel/læserrettet værdi, færdigbevis og det
workflow den erstatter. Omprioritér ikke roadmapet, og opret ikke nye permanente
editionsnavngivne overflader uden en beslutning i `docs/decisions.md`.

Historiske specs, planer, reviews og changelog er
historik, ikke aktuel programstatus. Levende kode og schema er source of truth for tekniske detaljer,
der kan være ændret siden statussnapshotet.

## Faldgruber

- **Supabase:** brug *Session pooler* (IPv4), `sslmode=require`, EU-region. Free-tier pauser efter 7 dages inaktivitet (hold varm før live-demo) og har ingen backup — hold et dump **uden for** repo'et (`~/.private`, chmod 600; dumps rummer levende-persondata og er gitignoreret).
- **Hver trykt DAA-udgave er en selvstændig `source`** — så modstridende udgaver håndteres indfødt.
- **Arbejdsmapper (gitignoreret) — commit dem aldrig:** `work/` (2018-20), `work_2018_saerudgave/` og `work_1939_stamtavle/` er udtræk af trykte, publicerede udgaver og **må læses af en model** (projektejerens beslutning 2026-11-21/22). `work_presens*/` (præsenslister over nulevende) må **aldrig** sendes til en model (invariant 8); det håndhæves af `.claude/settings.json`.

## Levende dokumentation (status/backlog bor IKKE her)

- `docs/README.md` — dokumentationsindeks (start her)
- `docs/database-current-state.md` — hvad der faktisk er i prod + deploy-procedure
- `docs/changelog.md` — dateret ændringshistorik; ikke statusorakel
- `docs/decisions.md` — arkitektur-/datamodel-beslutninger + åben backlog
- `datamodel-oversigt.md` — autoritativ bred konceptmodel (*hvorfor*);
  `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md` styrer
  source-record-, narrativ- og genimportproveniens

---

use fable subagents when you need more intelligence

## Codex til udvikling og review

`codex:codex-rescue` kan bruges til afgrænsede udviklingsopgaver — ikke kun fejlretning — samt til review og adversarial review (Codex er stærk til at finde problemer i eget eller andres arbejde). Vælg model efter opgavens sværhedsgrad:

- `gpt-5.6-sol` — høj intelligens: arkitektur/refactors på tværs af flere filer, DB-migrationer, alt der kræver dømmekraft
- `gpt-5.6-terra` — almindelig: afgrænsede, veldefinerede opgaver (én komponent, én testfil)
- `gpt-5.6-luna` — lavest intelligens: rene rutineopgaver (mekaniske omdøbninger, oprydning, ensartede gentagne rettelser)
