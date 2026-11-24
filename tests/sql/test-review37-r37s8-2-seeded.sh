#!/usr/bin/env bash
# Review 37 R37S8-2-1 (#397): verify-enheden r37s8-2 skal have tænder på en frisk base. Et frisk byg har ikke Supabases
# standardrettigheder, så enheden er grøn uden at bevise noget; kun opgraderingstesten seedede dem, og den pensioneres,
# når en ny ceremoni afløser den. Denne test kræver ingen base-commit og bliver i CI:
# 1) Frisk base (bootstrap + dblink + schema.sql + db-rls.sql): enheden er grøn.
# 2) Supabase-formens retter seedes (som prod havde dem før R37S8-2): enheden er RØD.
# 3) DO-blokken $review37_r37s8_2_skriveret$ alene: enheden er grøn igen.
# Ved succes droppes basen, scriptet selv oprettede (<db>); ved fejl står den tilbage.
set -euo pipefail
db=${1:?database}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
fail() { echo "R37S8_2_SEEDED_FAIL: $1" >&2; exit 1; }
awk '$0=="DO $review37_r37s8_2_skriveret$" {p=1} p{print} $0=="$review37_r37s8_2_skriveret$;" {p=0}' db-rls.sql > "$tmp/rls.sql"
[ "$(head -1 "$tmp/rls.sql")" = 'DO $review37_r37s8_2_skriveret$' ] || fail "DO-blokken mangler i db-rls.sql"
awk '$0=="-- BEGIN-VERIFY r37s8-2" {p=1} p{print} $0=="-- END-VERIFY r37s8-2" {p=0}' db-verify.sql > "$tmp/v-unit.sql"
[ "$(head -1 "$tmp/v-unit.sql")" = "-- BEGIN-VERIFY r37s8-2" ] || fail "verify-enheden r37s8-2 mangler i db-verify.sql"
unit() { local out
  if out=$(env -u PGOPTIONS psql -X -v ON_ERROR_STOP=1 -d "$db" -f "$tmp/v-unit.sql" 2>&1); then
    [ -z "$1" ] || { echo "$out" >&2; fail "r37s8-2 er grøn med seedede retter (forventede: $1)"; }
    grep -q "NOTICE:  OK: review37 R37S8-2" <<<"$out" || { echo "$out" >&2; fail "r37s8-2: OK-linjen mangler"; }
  else
    [ -n "$1" ] || { echo "$out" >&2; fail "r37s8-2 fejlede"; }
    grep -qF -- "$1" <<<"$out" || { echo "$out" >&2; fail "r37s8-2 fejlede af en anden grund end: $1"; }
  fi; }

createdb "$db"
q -f tests/sql/evidence-promotion-bootstrap.sql
q -c 'CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA extensions'
q -f schema.sql
q -f db-rls.sql
unit ""
# Supabase-formen: alle ikke-SELECT-retter på public-tabeller/-views, sekvensretter og standardrettigheder.
q -c "DO \$s\$ DECLARE r record; BEGIN
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c
            WHERE c.relnamespace='public'::regnamespace AND c.relkind IN ('r','p','v','m','f') LOOP
    EXECUTE format('GRANT INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER, MAINTAIN ON TABLE %s TO anon, authenticated', r.rel);
  END LOOP;
  FOR r IN SELECT c.oid::regclass AS rel FROM pg_class c WHERE c.relnamespace='public'::regnamespace AND c.relkind='S' LOOP
    EXECUTE format('GRANT SELECT, UPDATE, USAGE ON SEQUENCE %s TO anon, authenticated', r.rel);
  END LOOP;
  ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated;
END \$s\$"
unit "FEJL: R37S8-2 —"
env -u PGOPTIONS psql -X -q -1 -v ON_ERROR_STOP=1 -d "$db" -f "$tmp/rls.sql" >/dev/null || fail "DO-blokken fejlede"
unit ""
dropdb "$db"
echo R37S8_2_SEEDED_OK
