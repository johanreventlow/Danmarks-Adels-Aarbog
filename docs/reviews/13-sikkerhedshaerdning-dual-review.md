# Dual-review: sikkerhedshærdning (review 12, punkt 1)

**Dato:** 2026-07-02
**Diff under review:** commits `ca66d8b` (SQL-delen) + `b917303` (REVOKE-syntaks-følgefix), anvendt til prod.
**Formål:** Lukker version_pk_registry (ingen RLS, anon fuld DML inkl. TRUNCATE) og `_subjekt_synlighed`/`begin_change_set` (PUBLIC-eksekverbare uden intern rolle-gate) + `SET search_path=public` på 12 advisor-flaggede funktioner.

## Phase 1 — Claude draft-review

### Verificerede fund (egen review, før Codex)

**V1 [bekræftet, allerede rettet] — REVOKE FROM PUBLIC utilstrækkeligt mod Supabase.**
Første version af migrationen brugte `REVOKE EXECUTE ... FROM PUBLIC;` for `_subjekt_synlighed`/`begin_change_set`. Empirisk test mod prod (`SET ROLE anon; SELECT _subjekt_synlighed(...)`) viste kaldet stadig lykkedes efter migrationen. Root cause: Supabase grantér anon/authenticated EXECUTE direkte via `ALTER DEFAULT PRIVILEGES`, ikke via PUBLIC-pseudo-rollen. Rettet ved at navngive rollerne eksplicit (`FROM PUBLIC, anon, authenticated`), re-verificeret empirisk (permission denied). Se `db-rls.sql:406-414` og memory `supabase-revoke-from-public-insufficient`.

**V2 [verificeret] — app-laget kalder ingen af de reducerede funktioner/tabellen direkte.**
`grep -rn "_subjekt_synlighed\|begin_change_set\|version_pk_registry" mobile/src web/src` → 0 hits i begge apps. Al skriveaktivitet går gennem `red_*`-RPC'erne, som fortsat er eksekverbare (kun de to interne hjælpefunktioner + registret er strammet).

**V3 [verificeret] — R-loaderens DB-forbindelse er upåvirket.**
`supabase_load.R`/`load_daa.R` forbinder med `SUPABASE_USER` fra `~/.Renviron` (Supabase Session pooler-mønster = `postgres`-rollen, ejeren af alle objekter). Ejeren bypasser RLS uanset policy og er ikke omfattet af REVOKE'erne (kun `anon, authenticated` blev revoked). [inferred: ikke eksekveret mod prod i denne omgang — konklusionen hviler på at `SUPABASE_USER` faktisk resolver til `postgres`, hvilket er Supabases standard-connection-string-mønster, men ikke direkte aflæst fra `.Renviron`-indholdet (utilgængeligt for review).]

**V4 [verificeret] — advisor-dækning komplet efter follow-up.** Live advisor-scan efter fix: 0 `rls_disabled_in_public`, 0 `function_search_path_mutable`. `pg_proc.proacl` for begge funktioner viser kun `postgres`/`service_role`. `information_schema.role_table_grants` for `version_pk_registry` viser kun `postgres`/`service_role`.

### Uafklarede/lavere-tillid punkter (kandidater til Codex)

**U1 — er `service_role` korrekt eksponeret/ikke-eksponeret?** Fixet revokerede kun fra `anon, authenticated` (table) og `PUBLIC, anon, authenticated` (funktioner) — `service_role` beholder implicit adgang (aldrig revoked). Er det korrekt at `service_role` (bruges typisk af server-side/edge-functions, ikke af klient-apps) skal have adgang til `version_pk_registry`/de to interne funktioner? Ingen edge functions er fundet i repoet (`mcp__supabase__list_edge_functions` ikke kørt i denne omgang) — er der en reel bruger af `service_role`-nøglen der ville have brug for direkte adgang, eller er det unødvendig eksponering?

**U2 — er de resterende ~25 `red_*`/`hist_*`-RPC'er en levende risiko trods intern rolle-gate?** Bevidst udeladt fra denne fix (defence-in-depth, ikke en aktiv sårbarhed — de har `current_rolle() <> 'redaktion'`-gate). Er der en vej til at kalde dem UDEN at trigge den gate (fx et race mellem `auth.uid()`-opslag og rolle-check, eller en variant af RPC'et der ikke starter med gate-tjekket)?

**U3 — er der andre tabeller/funktioner i skemaet med samme mønster som `version_pk_registry` havde (ingen RLS + Supabase-default-grants) som IKKE er dækket af denne fix eller af review 12's RLS-analyse?**

**V5 [selv-fundet, rettet] — `current_rolle()` havde samme "FROM PUBLIC alene"-bug som V1, ikke fanget af den oprindelige fix.**
`db-rls.sql:318` (nu 320) revokerede kun `from public` med kommentaren "hygiejne: ikke kaldbar af anon" — men uden at navngive `anon` eksplicit havde revoke'et ingen effekt (samme root cause som V1). Empirisk verificeret: `pg_proc.proacl` viste `anon=X/postgres` stadig til stede efter den oprindelige review-12-fix; `SET ROLE anon; SELECT current_rolle();` lykkedes. Alvor: LAV — funktionen returnerer for anon kun den hårdkodede konstant `'medlem'` (ingen PII, ingen privilegie-bypass, `authenticated`-adgangen var upåvirket via den efterfølgende eksplicitte GRANT). Rettet ved at navngive `anon` eksplicit i revoke'et; re-verificeret lokalt og mod prod (permission denied for anon, uændret for authenticated).

## Phase 2-3 — Codex adversarial-review (2026-07-02)

**Trigger:** JA — empirisk claim (REVOKE-syntaks), sikkerheds-/GDPR-relevant prod-ændring, cross-package-kontrakt (DB↔app).
**Verdict:** `approve` — "No ship-blocking defect found."

## Phase 4 — Reconcile

| Fund | Codex-dom | Klassifikation | Handling |
|---|---|---|---|
| V1 | confirmed fixed | **verified** (reproduceret af mig selv, lokalt + prod, før Codex kørte) | Ingen — allerede rettet |
| V2 | confirmed | **verified** (grep-reproduktion i draft) | Ingen |
| V3 | recalibreret — "configured username is not runtime-verified" | **inferred** (Codex bekræfter selv ikke at have læst `.Renviron`; jeg har heller ikke — secrets-fil, uden for scope) | Efterladt som dokumenteret antagelse, ikke en blokerende risiko (owner-bypass gælder uanset præcis rollenavn så længe det er `postgres`-ejeren) |
| V4 | confirmed, men "live catalog results are document-only" | **verified** (jeg kørte selv `pg_proc.proacl`/advisor-forespørgslerne direkte mod prod via `execute_sql`/`get_advisors` — Codex har ikke DB-adgang og kunne kun læse min dokumentation, hvilket den korrekt flagger som en grænse for sin egen verifikation) | Ingen — min egen empiri står |
| U1 | dismissed — "service_role already has privileged database access" | **verified** (matcher Supabases standardkonvention: service_role er designet til at omgå RLS) | Ingen fix nødvendig |
| U2 | dismissed — "all privileged red_*/hist_* RPCs gate before protected work; red_suggest intentionally uses an auth gate" | **verified** (matcher review 12's RLS-agent-fund + min egen grep af `current_rolle() <> 'redaktion'`-mønsteret, 54 forekomster) | Ingen fix nødvendig |
| U3 | dismissed — "every CREATE TABLE candidate is covered by RLS" | **verified** (jeg reproducerede selv: 27 tabeller, 10 via db-rls.sqls dynamiske loop + 17 via eksplicit `ALTER TABLE`, 0 udækkede) | Ingen fix nødvendig |
| Ny (V5) | Codex fandt selvstændigt samme `current_rolle()`-gab som jeg allerede havde identificeret i min egen efterfølgende gennemgang (parallelt, før jeg læste Codex' output) | **verified** (to uafhængige reproduktioner: min egen `pg_proc.proacl`-tjek + Codex' selvstændige kodegennemgang, samme konklusion) | **Rettet** — se V5 ovenfor |

**Læring:** "REVOKE ... FROM PUBLIC alene er utilstrækkeligt mod Supabase" er ikke en engangsfejl i to funktioner — det er et mønster der kan gemme sig andre steder i filen hvor `from public` bruges uden eksplicit rollenavngivning. Denne dual-review-cyklus fangede det ANDET forekomst (`current_rolle()`) ved selvstændig, parallel verifikation (både Claude og Codex), hvilket bekræfter værdien af at grep'e for mønsteret bredt fremfor kun at rette de oprindeligt identificerede instanser. Gemt til memory: `supabase-revoke-from-public-insufficient`.

**Ikke fundet nødvendigt at følge op på:** U1-U3 kræver ingen handling. V3 forbliver en dokumenteret, lav-risiko antagelse (ikke empirisk lukket, men owner-bypass-logikken er robust over for præcis rollenavn).
