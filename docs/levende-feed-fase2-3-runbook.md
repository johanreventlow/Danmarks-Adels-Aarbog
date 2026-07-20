# Levende feed fase 2+3 — prod-cutover runbook

**Status:** Forberedt, IKKE udført. Prod-anvendelse kræver eksplicit bruger-godkendelse der
navngiver prod-målet. **Prod har INGEN backup ud over hvad denne runbook selv tager.**

**Formål:** Anvend levende-feed fase 2 (`haendelse`) og fase 3 (`story`/`story_kilde`/
`feed_pin` + syv RPC'er) skemaerne på prod. **Kun skema+RLS+RPC'er — ingen data.**
Begge faser starter tomme; feed-motoren degraderer bevist gracefult til fase 1-adfærd
med tom `haendelse` (`packages/feed/src/pool.ts:32-44`, `haendelserBy ?? []`-fallback), og
`story` kræver ikke noget `haendelse_id`-anker (fri historie er gyldig).

**Eksplicit UDENFOR scope for denne runbook (senere, separat godkendelse):**
- Fase 2's offline LLM-hændelsesudtræk (`daa-haendelser`-skillen: narrativ → `haendelse`).
  **Aldrig kørt endnu, hverken lokalt eller mod prod** — intet `work/haendelser/`-artefakt
  findes. Bruger har eksplicit bedt om at få dette noteret som en kommende opgave
  (2026-07-20), sideordnet med fase 4-LLM-assist (begge udskudt af samme grund: PoC har
  for få kilder til at retfærdiggøre LLM-kørslen endnu). Se
  [`decisions.md`](decisions.md#levende-feed-fase-4-llm-assist-udskudt-ikke-annulleret-2026-07-20).
- Fase 4 (LLM-assist Edge Function) — udskudt, se samme beslutning.

---

## Mediehåndtering-bundling — accepteret (bruger-beslutning 2026-07-20)

`db-migrations.sql` og `db-rls.sql` er **monolitiske, kumulative filer** — husets etablerede
mønster er at køre hele filen (idempotent `CREATE IF NOT EXISTS`/`CREATE OR REPLACE`), ikke
et kurateret udsnit (jf. Problem 2-runbooken, `fase4-runbook.md`, som selv kørte hele filen).

Levende-feed fase 2-sektionen (db-migrations.sql linje ~2564) og fase 3-sektionen (linje
~2726) har **Mediehåndtering fase 1 (filside/CRUD, linje ~2637) og fase 2 (døde links, linje
~2715) interleaved imellem sig** — samme commit-periode, samme fil. At køre
`db-migrations.sql`/`db-rls.sql` i sin helhed anvender derfor **også** mediehåndtering fase
1+2-skemaet i samme cutover-event.

**Besluttet: acceptér bundlingen** — kør hele filen, én samlet cutover. Matcher husets
mønster, og mediehåndtering fase 1+2 er selv "implementeret lokalt, prod-deploy gated" og
venter i samme kø. Rehearsalen nedenfor er kørt mod denne antagelse.

---

## Forbindelse (KRITISK — uændret fra Problem 2-runbooken)

Brug **Session pooler (port 5432, IPv4)** eller direkte forbindelse — IKKE
transaction-pooleren (6543). Sæt password via `PGPASSWORD`/`~/.pgpass`, ALDRIG i
conn-strengen på kommandolinjen. Verificér basen er vågen (Supabase free-tier pauser efter 7
dages inaktivitet).

## Skrive-frys (obligatorisk)

Ingen redaktør-aktivitet fra Trin 0 til Trin 3 er grøn. Samme `max(id)+1`-race som Problem 2.

## GATE 0 — Rehearsal mod test-restore (OBLIGATORISK — skema+rollback-delen kørt 2026-07-20)

1. **Skema-rehearsal — DONE 2026-07-20:** kørt mod en frisk lokal kopi af
   `daa_feed23_gate0_20260720_0120` (1758 personer — matcher prod-tallet efter K3
   1939-loadet). `db-migrations.sql` + `db-rls.sql` anvendt rent (idempotent, ingen fejl);
   fase 3-tabellerne (`story`/`story_kilde`/`feed_pin`) oprettet oven på basens
   eksisterende fase 2 (`haendelse`) + mediehåndtering fase 1-tilstand.
   ⚠ **Provenansen af `daa_feed23_gate0_20260720_0120` er ikke selv sporet** (formentlig fra
   en tidligere sessions arbejde samme dag) — personantallet matcher prod, men det er IKKE
   en verificeret frisk `pg_dump`/`pg_restore` af det faktiske nuværende prod-indhold. Før
   den rigtige cutover: tag et ægte frisk prod-dump og gentag minimum Trin 1-1b-3 mod DEN
   kopi, så rehearsalen er bevist mod sandheden, ikke en antaget kopi.
2. **db-verify — DONE 2026-07-20:** `OK: levende feed fase 2 (haendelse
   CHECK/RLS/RPC/versionering/fortryd)` og `OK: levende feed fase 3 (story/story_kilde/
   feed_pin CHECK/UNIQUE/RLS/RPC/fuld versionering/fortryd)` — begge grønne. Blokkene sår
   deres egen engangs-`auth.users`/`profiles`-testbruger (`…f2`/`…f3` UUID'er,
   `db-verify.sql:1783, 1963`), så de kræver INGEN forhåndseksisterende redaktionsprofil og
   kørte grønt uden auth-shim. Øvrige fejl i samme kørsel (profiles-FK, storage.buckets) er
   kendte, urelaterede miljøhuller (samme mønster som Problem 2-runbooken).
3. **Rollback — DONE 2026-07-20:** `db-rollback-fase2.sql` (ny) + `db-rollback-fase3.sql`
   begge kørt i korrekt rækkefølge (fase 3 → fase 2) mod samme kopi:
   - Forkert rækkefølge afvist korrekt: `db-rollback-fase2.sql` kørt FØR fase 3 gav
     `ERROR: Fase 2 rollback afbrudt: public.story findes stadig. Kør db-rollback-fase3.sql
     først.` — hele transaktionen rullede tilbage, intet blev droppet.
   - Korrekt rækkefølge: fase 3-rollback fjernede `story`/`story_kilde`/`feed_pin`, bevarede
     `haendelse`; fase 2-rollback fjernede derefter `haendelse` + `version_pk_registry`-
     rækker + vokabular + RPC.
   - **Idempotens bekræftet:** begge scripts kørt igen på allerede-tom base → `OK`-notice,
     ingen fejl.
   - **Re-migration bekræftet:** `db-migrations.sql` + `db-rls.sql` kørt igen efter
     rollback → `haendelse`/`story`/`feed_pin` genskabt korrekt.
4. **Ikke rehearset endnu:** Trin 4 (`get_advisors(security)`) kræver et rigtigt Supabase-
   projekt og kan ikke køres mod en lokal kopi — udestår til selve cutoveren.

## Forudsætninger (verificér på prod FØR noget anvendes; read-only)

```sql
-- (a) fase 2+3-objekter findes IKKE endnu (forventet før cutover)
SELECT to_regclass('public.haendelse'), to_regclass('public.story'),
       to_regclass('public.story_kilde'), to_regclass('public.feed_pin');  -- alle NULL
-- (b) mediehåndtering fase 1+2-objekter findes IKKE endnu (bundling-konsekvens, jf. ⚠ ovenfor)
SELECT to_regclass('public.red_opdater_media'), to_regclass('public.red_genopret_media');
-- (c) umigreret baseline for version_pk_registry (skal ikke allerede kende story/haendelse)
SELECT count(*) FROM version_pk_registry WHERE tabel IN ('haendelse','story','feed_pin');  -- =0
```

## Trin 0 — BACKUP (obligatorisk, eneste rollback-kilde ud over db-rollback-fase3.sql)

```bash
export PGPASSWORD='…'   # ikke i conn-strengen
pg_dump -h <session-pooler-host> -p 5432 -U <user> -d <db> --schema=public -Fc \
  -f ~/daa-prod-backup-$(date +%Y%m%d-%H%M).dump
chmod 600 ~/daa-prod-backup-*.dump          # PII: levende-persondata
# krypter (age/gpg) + notér sletningsfrist efter verificeret cutover.
```
GATE 0 SKAL være grøn før Trin 1.

## Trin 1 — Skema-migration (DDL + funktioner)

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> --single-transaction -v ON_ERROR_STOP=1 -f db-migrations.sql
```
- Hele filen (jf. ⚠ ovenfor — bundler mediehåndtering fase 1+2). Idempotent additiv:
  `haendelse`/`story`/`story_kilde`/`feed_pin`, vokabular, ni RPC'er, `version_pk_registry`,
  triggere.
- `LC_ALL=C` → fejl printes `ERROR:` (ikke dansk `FEJL:`).

## Trin 1b — RLS/grants (db-rls.sql)

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> --single-transaction -v ON_ERROR_STOP=1 -f db-rls.sql
```
- Deployer `haendelse`-RLS (`db-rls.sql:353-`), `story`/`story_kilde`-RLS (`:551-`, inkl.
  `redaktion_read` for kladder) og `feed_pin`-RLS (`:582-`, offentligt læsbar — ingen PII).
  Idempotent (`drop … if exists` + `create`). Kør efter Trin 1.

## Trin 2 — Ingen backfill

Fase 2+3 starter tomme. Intet backfill-script. (Selve hændelses-udtrækket er separat
gated, se toppen af dette dokument.)

## Trin 3 — Verificér (db-verify)

```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -f db-verify.sql 2>&1 | grep -iE "OK:|SPRINGER|ERROR|FEJL"
```
- Forvent grønt for `OK: levende feed fase 2 (haendelse CHECK/RLS/RPC/versionering/fortryd)`
  og den tilsvarende fase 3-linje — begge selv-sående (ingen forhånds-redaktionsprofil
  nødvendig, jf. GATE 0 pkt. 2).
- Øvrige SPRINGER/ERROR-mønstre er de samme kendte miljøafhængige som i Problem 2-runbooken
  (auth.users-FK, storage.buckets, tom-DB-data) — ikke fase 2/3-specifikke.

## Trin 4 — Sikkerheds-advisors

Kør Supabase `get_advisors(security)`. Forvent: alle nye funktioner `SECURITY DEFINER SET
search_path=public` + `current_rolle()`-gated; ingen ny anon-kaldbar skrivevej på
`haendelse`/`story`/`feed_pin`. Jf. [[koer-get-advisors-efter-ddl]].

## Trin 5 — Post-cutover

- Opdatér `docs/changelog.md` + `docs/database-current-state.md` (fjern fase 2+3 fra
  "mangler i prod"-listen; noter hændelses-udtræk fortsat udestående).
- Ophæv skrive-frysen. Slet/afkrypter backup efter frist.

## ROLLBACK

**Rækkefølge er PÅKRÆVET: fase 3 før fase 2.** `story.haendelse_id` refererer `haendelse`;
`db-rollback-fase2.sql` afviser eksplicit at køre, hvis `story` stadig findes.

**Fase 3 (kirurgisk, foretrukket):**
```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -f db-rollback-fase3.sql
```
Rehearset (også 2026-07-20, se GATE 0). Bevarer bevidst `haendelse` (fase 2) og den delte
versionsmotor.

**Fase 2 (kirurgisk, kør EFTER fase 3):**
```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -f db-rollback-fase2.sql
```
Rehearset 2026-07-20 (skrevet som del af denne runbook, samme mønster som fase 3's script:
låser tabellen, afbryder ved data/historik, drift-værn på `version_pk_registry`/vokabular,
ingen `CASCADE`). Fjerner `haendelse`, `red_set_haendelse_status`, vokabular
(`haendelse_feed_status`/`haendelse_kategori`) og `version_pk_registry`-rækken.

**Nuklear (fuld restore, sidste udvej — mister writes efter Trin 0-dumpet):**
```bash
pg_restore -d "host=<host> port=5432 user=<user> dbname=<db>" --clean --if-exists --no-owner ~/daa-prod-backup-<dato>.dump
```

## Loadere fremadrettet

Ingen ændring for `load_daa.R`/`load_presens.R` (rører ikke `haendelse`/`story`). Den
kommende `load_haendelser.R` (del af `daa-haendelser`-skillen) kræver den migrerede base —
egen, senere runbook-tilføjelse når hændelsesudtrækket bliver godkendt.

## Rehearsal-log

**2026-07-20 (lokal, skema+rollback):** frisk kopi af `daa_feed23_gate0_20260720_0120`
(1758 personer). `db-migrations.sql`+`db-rls.sql` idempotent rent → fase 3-tabeller oprettet.
`db-verify.sql`: fase 2 + fase 3-blokke begge `OK`, selv-sående, ingen auth-shim nødvendig.
`db-rollback-fase2.sql` (ny) afviste korrekt forkert rækkefølge (`story` findes stadig);
fase 3→fase 2-rollback i korrekt rækkefølge fjernede alt rent; begge rollbacks idempotente;
re-migration efter rollback genskabte skemaet korrekt. Testdatabase droppet efter kørslen.
**Ikke dækket af denne rehearsal:** et ægte frisk `pg_dump`/`pg_restore` af nuværende prod
(basen var en formodet, ikke verificeret, prod-kopi), og `get_advisors(security)` (kræver
rigtigt Supabase-projekt).
