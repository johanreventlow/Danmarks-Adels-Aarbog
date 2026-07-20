# Database — Current State (operatør-guide)

> **Formål:** Ét sted der siger *hvad der faktisk er i prod lige nu*, hvilke SQL-filer
> der er autoritative, og hvordan man deployer sikkert. Changelog fortæller *historien*;
> denne side fortæller *tilstanden*. Ved uenighed mellem en fils egen header og denne
> side: stol på changelog + denne side, og ret filens header.
>
> **Sidst afstemt:** 2026-07-20 (live-objektinventar kørt direkte mod prod via Supabase MCP,
> ikke kun mod changelog). Opdatér ved hver prod-deploy.
>
> **Fund ved 2026-07-20-afstemningen:** denne sides "Sidst afstemt: 2026-07-01" havde stået
> ureflekteret i tre uger. Et direkte objektinventar (tabeller + `pg_proc`-funktionsnavne)
> viste at ALT arbejde dateret 2026-07-02 til 2026-07-17 i `db-migrations.sql`/`db-rls.sql`
> (samme_som/ikke_samme_som, udledt slægtsnavn, dato-hærdning, Problem 2 forældrefamilie-fase 1,
> K2 staging-gate m.fl.) reelt VAR live i prod — blot aldrig dokumenteret her. Kun tre
> ting manglede reelt: `haendelse`-tabellen (levende feed fase 2), `story`/`story_kilde`/
> `feed_pin` (levende feed fase 3) og `red_publicer_personer` (K2 selektiv publicering,
> selv samme dag). Alle tre er nu deployet (se §2). **Læring:** stol ikke på denne sides
> dato uden et faktisk objekt-tjek ved næste afstemning — dokumentationsdrift er reel.

---

## 1. Autoritative filer (rod-niveau)

| Fil | Rolle | Køres mod prod? |
|---|---|---|
| `schema.sql` | **Source of truth** for hele skemaet (PostgreSQL/Supabase + DuckDB-blokke). Fuld gen-opbygning fra bunden. | Kun ved frisk base / clean-slate |
| `db-migrations.sql` | **Idempotente additive migrationer** oven på en allerede-deployet base. Afstemmer en kørende base med `schema.sql`. Skrevet drop-/create-if-exists. | Ja — den inkrementelle deploy-sti |
| `db-rls.sql` | **RLS-laget** (anon-tier GDPR-filtrering + historik-deny-all + helpere). Definitionen af politikkerne. | Ja — anon-tier er live (se §2) |
| `db-verify.sql` | **Adfærds-verifikation** (Task 1-11): asserts der bekræfter RPC'er, triggere, cache-regen, RLS-gating og versionering virker. Ikke en integritetsrapport. | Kør efter deploy for grønt lys |
| `docs/db-backups/*.sql` | **Pre-apply dumps** (tidsstemplet). Tages FØR hver prod-ændring — free tier har ingen indbygget backup. | Nej (aflæsning/restore) |

`supabase_load.R` (rod) er **historisk** — den oprindelige seed-loader, erstattet af
`/daa-extract`'s bulk-`load_daa.R`. Behold som reference; brug ikke til nye loads.

---

## 2. Hvad er LIVE i prod

Alt herunder er **verificeret deployet** jf. `docs/changelog.md` (dato + evidens i parentes).

### Skema & kerne
- **Evidensmodel:** `assertion` / `conclusion` / `citation` — påstand vs. blåstemplet konklusion.
- **Generisk `relation`** (polymorf, rolle + periode + konfidens) og **polymorf `fact`** på enhver entitet.
- **`person.visning_*`-cache** + envejs-regenerering via triggere `trg_conclusion_regen`
  / `trg_assertion_regen` → `regen_person_visning(pid)` (`schema.sql`). *Batch-rebuild:*
  loop `regen_person_visning` over alle person-id'er (ingen dedikeret "rebuild-all"-wrapper endnu).
- **`lineage`-entitet** med `parent_lineage_id` (forgrening) + `status` — additivt skema (2026-06-30).
- **Data:** ~960 personer loadet (Reventlow-udsnittet). *Præcist antal drifter — se seneste
  changelog-entry; versioneringslaget rapporterede 963 uændret pr. 2026-06-30.*

### Redaktions-RPC-lag (SECURITY DEFINER, rolle-gated)
- `profiles`, `suggestion`, `current_rolle()`, `red_upsert_fakta`, `red_set_konklusion`,
  `red_edit_oplysning` (append → jsonb), `red_slet_oplysning`, `red_suggest`, m.fl.
- **Opret-entitet (2026-06-29):** `red_opret_person` / `_estate` / `_kilde` / `_organisation`.
- ⚠️ Alle bruger `max(id)+1` til PK-tildeling — **race-følsomt, bevidst PoC-gæld** under
  single-editor. Migrér til IDENTITY/sekvenser før multi-writer. (Selv-dokumenteret i koden.)

### RLS — anon-tier (GDPR)
- **Live siden 2026-06-25** (kørt via `work/rls_deploy.R`). Anon ser kun **afdøde ikke-private**
  personer + personbundne rækker; **levende usynlige** for anon. Verificeret: 893 afdøde
  synlige, 0 levende lækket, midlertidig `dev_anon_read` (USING true) droppet.
- Helper `person_offentlig(pid)` (SECURITY DEFINER, fail-closed på `levende`).

### Versionering + hyperlinks (DB-lag, applied 2026-06-30, atomisk `--single-transaction`)
- `change_set` / `change_event` + generisk `log_change`-trigger på **22 versionerede tabeller**
  (`version_pk_registry` styrer PK/skip-kolonner). `red_fortryd_change_set` inverse-applier
  ét sæt m. optimistisk divergens-tjek.
- **Hyperlinks:** `parse_mentions` + afledt `text_mention`-indeks (regen-trigger på
  narrative/note) + døde-links-view. **Deny-all RLS** på historik-tabellerne.
- 24 verify-asserts grønne ved apply. Bugfix 2026-07-01: `_version_upsert_row` ekskluderer
  nu `GENERATED ALWAYS`-kolonner (fortryd var knækket for `narrative.fts`).

### Mediehåndtering fase 0-2 (live, senest bekræftet 2026-07-20)
- **Slice 0** (bucket, gating, upload-RPC'er) live siden 2026-07-05. **Fase 1** (filside:
  `red_opdater_media`, `red_genopret_media`, kunstner/datering i `red_upload_media`) og
  **fase 2** (bibliotek: `red_doede_links` udvidet med `maal_type='media'`, `text_mention`
  `GRANT SELECT` + korrekt `media_synlig_anon`-gating i `tm_read`) deployet 2026-07-20.
- `media`-afbildet-gating er FULDT AKTIV (ikke deny-all/tom — se rettelse i §3): 6 media-
  rækker i prod (2 `klar`, 4 `fjernet`), `media_variant` populeret.

### Levende feed fase 2-3 + K2 selektiv publicering (deployet 2026-07-20)
- **`haendelse`** (fase 2, regenererbar hændelses-projektion af narrativer) + **`story`/
  `story_kilde`/`feed_pin`** (fase 3, kurateret formidlingslag) — additive tabeller,
  RLS aktiv (anon ser kun `publiceret`+ikke-privat+offentligt-subjekt for story;
  `feed_status<>'skjult'` for haendelse), versioneret via `log_change`.
- **`red_publicer_personer(person_ids[])`**: selektiv modstykke til `red_publicer_udgave`
  — publicerer kun udvalgte 1939-personer (+ familie-partnere) fremfor hele kilden på én gang.
- Deployet direkte via Supabase MCP (`execute_sql`/`apply_migration`), ikke `psql`-runbooken;
  objekt-eksistens + `get_advisors(security)` verificeret efter apply (117 fund, alle kendte
  mønstre — SECURITY DEFINER-eksponering + bevidst deny-all på historik-tabeller — ingen nye).
  **Udestår:** brugerens egen live-røgtest af filside/bibliotek/feed i appen.

---

## 3. Hvad er IKKE live / bevidst udskudt

| Emne | Status |
|---|---|
| **RLS `authenticated`-tier** (medlem/forsker ser levende slægtninge m. samtykke) | Kun skitseret i `db-rls.sql` §FREMTID. Bygges når login/profiles-auth er på plads. Indtil da er levende data usynlige for alle uden `redaktion`-rolle. |
| **`max(id)+1` → IDENTITY/sekvenser** | Udskudt post-PoC. Kritisk før flerbruger-skrivning. |
| **Samtykke-granularitet pr. levende person** (`samtykke_offentlig`) | Designes med auth-laget. |
| **Vocab-håndhævelse** | `vocab`-tabel findes, men `rolle`/`faktatype`/`konfidens` m.fl. er fritekst (ingen FK til vocab). Håndhæves i dag kun konventionelt. |
| **Polymorf døde-link-integritetsrapport** | Kun `text_mention` har et døde-links-view. Bredere orphan-check (fact/relation/assertion → subjekt) findes ikke systematisk endnu. |
| **Mediehåndtering fase 3 — hygiejne** | Implementeret og verificeret lokalt på `d97c64e`, men **ikke live i prod**. Det aktuelle `schema.sql` har NULL-bar `media.created_at DEFAULT now()`, det partielle firekolonne-index `relation_afbildet_uidx` for `rolle='afbildet'` og constraint-specifik domænefejl i `red_relation`; den scoped blok `mediehaandtering_fase3_hygiejne` i `db-migrations.sql` bringer en fase 1+2-base til samme flade. Web/mobil bruger sha-stier; janitoren er report-first. `db-rls.sql` er uændret af fase 3, og gamle storage-stier migreres ikke. Deploy følger den separate fase 3-runbook. |

---

## 4. Deploy-procedure (observeret mønster)

Free tier: ingen branch-base, ingen indbygget backup. Etableret arbejdsgang:

1. **Backup først:** dump berørte objekter til `docs/db-backups/<dato>-<beskrivelse>-pre.sql`.
2. **TDD mod lokal prod-kopi:** `postgresql@17` + auth-shim + read-only `pg_dump` af `public`
   (se memory `lokal-db-testbase`). Kør ændring + `db-verify.sql` lokalt før prod.
3. **Apply atomisk:** `psql --single-transaction` med den relevante fil (`db-migrations.sql`
   for additivt; `db-rls.sql` for RLS). Alt-eller-intet — ingen delvis korruption.
4. **Verificér:** kør `db-verify.sql` mod prod → alle asserts grønne. For RLS: `SET ROLE anon`
   + tæl synlige rækker.
5. **Dokumentér:** ny changelog-entry + opdatér denne side.

Git-gates (global regel §5): prod-deploy af SQL bekræftes eksplicit med bruger.

---

## 5. Se også

- `docs/changelog.md` — kronologisk historik med fejl, reviews, testniveau.
- `docs/decisions.md` — arkitektur-log (ikke-oplagte valg + fravalgte alternativer).
- `datamodel-oversigt.md` — konceptuel model (læs først for *hvorfor*).
- `docs/README.md` — dokumentationsindeks.

## Mediehåndtering fase 1+2 — LIVE i prod (2026-07-20)

Redaktionslaget har nu en filside for eksisterende `media`-rækker. Kuraterbare metadata
(`titel`, `slags`, `kunstner`, `datering`) opdateres via `red_opdater_media`; blødt fjernede
rækker kan genoprettes via `red_genopret_media`. Rettighedsgaten vedligeholdes fortsat gennem
`red_set_media_rettigheder`, og `red_upload_media` accepterer nu også kunstner og datering.

`upload_status='fjernet'` er fortsat usynlig for offentligheden og for almindelige medlemmer.
Redaktionen læser derimod rækken for at kunne vise status og genoprette den. Lightbox og
narrativ-mention-pickere filtrerer eksplicit til `upload_status='klar'`.

`red_doede_links` er udvidet med `maal_type='media'`: kun et media-id uden en eksisterende
`media`-række er dødt. En række med `upload_status='fjernet'` er ikke død, fordi den stadig
findes og kan genoprettes. `security_invoker` er bevaret. Samtidig fik `text_mention` sit
hidtil manglende `GRANT SELECT` (viewet var reelt utilgængeligt for alle, inkl. redaktionen,
siden 2026-06-30) og `tm_read`-policyen bruger nu `media_synlig_anon` for `maal_type='media'`
i stedet for `entitet_offentlig`s ubetingede `true`-gren — lukker et latent fail-open-hul
(aldrig udnyttet i praksis, da manglende GRANT gjorde tabellen uforespørgelig).

Se §2 for detaljer om deploy-vejen (kørt direkte via Supabase MCP samme dag som levende
feed fase 2-3, se ovenfor).
