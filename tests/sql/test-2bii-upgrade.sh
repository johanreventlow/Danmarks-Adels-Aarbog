#!/usr/bin/env bash
# Trin 5b 2b-ii (#151, spec §11): opgradering fra main (før 2b-ii) med eksisterende familier og bindinger;
# sekvensen for family.id sættes over max(id), migrationerne køres to gange mere. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
q -f tests/sql/fixtures/spouse-exception-2bi.sql          # committede familier og bindinger
# Migrerede baser har allerede identity (mains generelle identity-blok); risikoen er en sekvens bag max(id),
# fx efter load_daa.R's eksplicitte id'er. Simulér det, og kræv at 2b-ii-migrationen løfter sekvensen.
q -c "INSERT INTO family(id,type) VALUES ((SELECT max(id) FROM family)+100,'vielse')"
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT (SELECT max(id) FROM family) > (SELECT last_value FROM family_id_seq)")" = "t" ]
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
for t in test-family-id-identity test-identity-deceased-context test-relation-binding test-spouse-exception-projection; do q -f "tests/sql/$t.sql"; done
# db-verify i en søsterbase med samme opgraderingssti uden fixtures (som 2b-i's opgraderingstest)
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
echo UPGRADE_OK
