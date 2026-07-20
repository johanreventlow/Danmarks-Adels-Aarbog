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

## ⚠ Forudsætning der SKAL afklares før Trin 0: mediehåndtering-bundling

`db-migrations.sql` og `db-rls.sql` er **monolitiske, kumulative filer** — husets etablerede
mønster er at køre hele filen (idempotent `CREATE IF NOT EXISTS`/`CREATE OR REPLACE`), ikke
et kurateret udsnit (jf. Problem 2-runbooken, `fase4-runbook.md`, som selv kørte hele filen).

Levende-feed fase 2-sektionen (db-migrations.sql linje ~2564) og fase 3-sektionen (linje
~2726) har **Mediehåndtering fase 1 (filside/CRUD, linje ~2637) og fase 2 (døde links, linje
~2715) interleaved imellem sig** — samme commit-periode, samme fil. At køre
`db-migrations.sql`/`db-rls.sql` i sin helhed anvender derfor **også** mediehåndtering fase
1+2-skemaet i samme cutover-event, uanset om det er tilsigtet.

**Beslutning påkrævet:** acceptér bundlingen (kør hele filen, én samlet cutover — anbefalet,
matcher husets mønster og mediehåndtering fase 1+2 er selv "implementeret lokalt, prod-deploy
gated" og venter i samme kø), eller bed om at få migrations-sektionerne udskilt til separate
filer først (ekstra arbejde, afviger fra husmønstret, ingen kendt fordel medmindre
mediehåndtering fase 1+2 bevidst skal vente længere).

*Denne runbook antager bundling accepteret. Hvis ikke: stop her og få sektionerne udskilt
først.*

---

## Forbindelse (KRITISK — uændret fra Problem 2-runbooken)

Brug **Session pooler (port 5432, IPv4)** eller direkte forbindelse — IKKE
transaction-pooleren (6543). Sæt password via `PGPASSWORD`/`~/.pgpass`, ALDRIG i
conn-strengen på kommandolinjen. Verificér basen er vågen (Supabase free-tier pauser efter 7
dages inaktivitet).

## Skrive-frys (obligatorisk)

Ingen redaktør-aktivitet fra Trin 0 til Trin 3 er grøn. Samme `max(id)+1`-race som Problem 2.

## GATE 0 — Rehearsal mod test-restore (OBLIGATORISK — endnu IKKE kørt for fase 2+3)

I modsætning til Problem 2 (rehearset 2026-07-17) og K1/K2 (rehearset 2026-07-17) er der
**ingen eksisterende rehearsal for fase 2+3**, fordi de landede på main *efter* den seneste
rehearsal (2026-07-18/19). Uden en frisk rehearsal er dette den eneste udækkede cutover i
husets historie.

1. Tag et frisk prod-dump (Trin 0 nedenfor) og `pg_restore` det til en **lokal engangs-DB**.
2. Kør Trin 1-1b-3-4 mod kopien → bekræft grønt. Fase 2+3-verify-blokkene sår deres egen
   engangs-`auth.users`/`profiles`-testbruger (`…f2`/`…f3` UUID'er, `db-verify.sql:1783,
   1963`) — de kræver IKKE en forhåndseksisterende redaktionsprofil (modsat de ældre
   Problem 2-æra-blokke der brugte den delte `…0001`-profil) og bør derfor kunne køre grønt
   direkte mod en frisk prod-kopi.
3. **Øv rollbacken:** `db-rollback-fase3.sql` findes og er lokalt rehearset (bevarer bevidst
   fase 2's `haendelse`-tabel). **`db-rollback-fase2.sql` findes IKKE endnu** — se
   "Rollback"-afsnittet nedenfor. Rehearsal-trin 3 må derfor enten (a) skrive og øve den
   manglende fase 2-rollback først, eller (b) acceptere at fase 2 kun kan rulles tilbage via
   fuld backup-restore (nuklear) indtil videre.

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

**Fase 3 (kirurgisk, foretrukket):**
```bash
LC_ALL=C psql -h <host> -p 5432 -U <user> -d <db> -f db-rollback-fase3.sql
```
Rehearset. Bevarer bevidst `haendelse` (fase 2) og den delte versionsmotor.

**Fase 2:** ⚠ **`db-rollback-fase2.sql` findes ikke.** Skal enten skrives (DROP TABLE
`haendelse` + fjern `version_pk_registry`-række + trigger + vokabular + RPC
`red_set_haendelse_status` — kompliceres af at `story.haendelse_id` har `ON DELETE SET NULL`,
så en fase 2-rollback efter fase 3 har data kræver at nulstille de referencer først) eller
mediehåndtering-mønstret følges (ingen separat rollback — kun fuld backup-restore). Afklares
inden GATE 0 udføres i praksis.

**Nuklear (fuld restore, sidste udvej — mister writes efter Trin 0-dumpet):**
```bash
pg_restore -d "host=<host> port=5432 user=<user> dbname=<db>" --clean --if-exists --no-owner ~/daa-prod-backup-<dato>.dump
```

## Loadere fremadrettet

Ingen ændring for `load_daa.R`/`load_presens.R` (rører ikke `haendelse`/`story`). Den
kommende `load_haendelser.R` (del af `daa-haendelser`-skillen) kræver den migrerede base —
egen, senere runbook-tilføjelse når hændelsesudtrækket bliver godkendt.

## Rehearsal-log

*(udfyldes ved GATE 0-kørsel)*
