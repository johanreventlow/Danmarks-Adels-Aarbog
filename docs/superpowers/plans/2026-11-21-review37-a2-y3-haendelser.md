# Plan: review 37 A2 + Y3 (hændelser og synlighed; feed i bidder)

Spec: `docs/superpowers/specs/2026-11-21-review37-a2-y3-haendelser-design.md` (godkendt 2026-11-21).
Gren: `fix/review37-haendelse-db`. Én commit pr. task. Push først når PR'en er færdig; `[skip ci]` i mellem-push.
Codex: højst 2 runder på koden (efter Task 4); derefter regel frem for flere runder.

## Task 1 — A2 i databasen

Alle ændrede funktioner rettes **både** i `schema.sql` (source of truth) og som idempotent kopi i `db-migrations.sql`
(eksisterende spejle: `narrative_publication_state` 13655, `narrative_legacy_candidate_publication_state` 16017,
`narrative_legacy_publication_state` 14214 + 16098, `narrative_record_state` 13963, `mutate_person_narrative_record`
14710, `person_purge_fortrydelse` 38737). Den sidste definition i hver fil skal være den nye.

1. `private.narrative_har_haendelse(bigint) RETURNS boolean` (SQL, STABLE, `SET search_path=pg_catalog`), REVOKE fra
   PUBLIC/anon/authenticated/service_role.
2. `narrative_publication_state` og `narrative_legacy_candidate_publication_state` (+ død kopi af
   `narrative_legacy_publication_state` i begge filer): `has_haendelse` → konstant `false`; fjern `EXISTS(haendelse)`.
3. `narrative_record_state`: `v_text_editable := v_publication_allowed AND NOT private.narrative_har_haendelse(<id>)`.
   Narrativ-id'et tages fra den valgte bindings narrativ (samme som publication_state brugte).
4. `mutate_person_narrative_record` (revise): læs låsen via hjælperen, ikke `v_before_publication->>'has_haendelse'`.
5. `person_purge_fortrydelse` R30: **prædikatet beholdes** (overmængde: melder også tab for kladder, hvor kvitteringen
   reelt ikke ændres — fail-closed); kommentaren omskrives til, at kvitteringen ændres via `text_editable` på publicerede,
   tilladte bindinger.
6. `db-verify.sql`: asserts for (a) hjælperens ACL, (b) at `narrative_publication_state` aldrig giver
   `has_haendelse=true` med en hændelse til stede, (c) at revise afvises med hændelse.
7. Tests: `tests/sql/test-narrative-record-contract.sql` (task5-revalideringstesten ~4287: hændelse ændrer ikke længere
   publication_state → testen omskrives til at bevise uændret synlighed + ændret editor-token) og
   `tests/sql/test-person-purge.sql` (S26 ~884-980 forventer `nested has_haendelse` true→false: omskrives til
   `text_editable`/token på en publiceret binding, og en kladde-variant med uændret kvittering; ~2475).
8. Python-definitionsvagten (`test_identity_guard_static.py` ALLOWLIST) ajourføres, hvis antallet af definitioner pr.
   fil ændres.

**Verifikation:** lokal engangsbase (CI-bootstrap → schema → rls → migrations → migrations → rls) + de berørte
SQL-tests + `test-person-purge.sh`; `db-verify.sql` grøn.

## Task 2 — Y3-RPC

1. `private.feed_cursor_noegle(id smallint PRIMARY KEY CHECK (id=1), noegle text NOT NULL)`, udfyldt med
   `encode(extensions.gen_random_bytes(32),'hex')` hvis tom (idempotent); ingen grants.
2. `public.public_haendelse_feed(p_fortsaet text, p_max_narrativer int, p_max_raekker int) RETURNS jsonb`
   (plpgsql, STABLE, SECURITY DEFINER, `SET search_path=pg_catalog`), efter spec §4.2: lofter valideres
   (1..200 / 1..2000), cursor dekrypteres (fejl → `FEED_CURSOR_INVALID`), kandidatrækker efter cursor i orden
   `(narrative_id, id)` med begge lofter, gate én gang pr. narrativ (MATERIALIZED), rækkefiltre pr. række, metadata
   af returnerede rækker, `naeste` krypteret eller null. GRANT EXECUTE til anon, authenticated.
3. `db-rls.sql`: REVOKE/GRANT; `db-verify.sql`: ACL + at tabellen ikke kan læses af anon/authenticated.
4. Ny test `tests/sql/test-haendelse-feed.sql` (spec §6.0-0a, 4): blandede rækker på ét narrativ, skjult/privat
   narrativ, tom bid med `naeste`, stop ved null, ingen dubletter og samme id-mængde som RLS-politikken, manipuleret og
   fremmed mærke afvises, mærket indeholder ingen klartekst-id. Køres i det CI-job, der kører
   `test-narrative-record-contract.sql` (ci.yml:863).

## Task 3 — webklient

`web/src/data/haendelser.ts` (tolerant) og `web/src/data/feedGrundlag.ts` (fail-closed) bladrer via RPC'en, til
`naeste` er null. Vitest efter spec §4.3. Gate: `npm run test -w web` + `npm run build -w web` (ikke `tsc -p web`).

## Task 4 — mobil (dev-only, paritet)

`mobile/src/data/haendelser.ts` samme ændring; jest + `tsc --noEmit` som i CI.

## Task 5 — opgraderingsvej og stand-in-generalprøve

1. Opgraderingstest fra prod-formet base (mønster: `tests/sql/test-person-purge-upgrade.sh`).
2. Stand-in fra nyeste læsedump (projektejerens runner); privat runner `~/.private/review37-a2y3/prod.zsh`
   (standin/apply/fortryd/tal, facit-hashes, røgtest) efter mønstret fra `review37-p1p2`.
3. Færdigbevis spec §6 på stand-in: id-mængder ved fire punkter, hashes, lås/kvitteringer, Y3-tider som anon med 3 s.

## Task 6 — prod og afslutning

DDL i prod (projektejeren kører apply) → efterkontrol → merge → Vercel-røgtest som anon → docs
(`database-current-state.md`, `changelog.md`) → #397 krydses af. **#130 frigives først herefter.**
