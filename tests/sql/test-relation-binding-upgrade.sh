#!/usr/bin/env bash
# Trin 5b 2a (#151): db-migrations + db-rls to gange på en base bygget fra ebf2022 (5b del 1, før 2a):
# ændret regeltabel og ændret signatur for add_interpretation_promotion_rule_version.
# Kun lokalt; CI kører den friske schema-sti. Kræver en lokal PostgreSQL (PGHOST m.fl.).
set -euo pipefail
db=${1:?database}; base=${2:-ebf2022}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$f" >/dev/null
done
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-relation-binding.sql
# De eksisterende text/date-regler virker stadig funktionelt efter opgraderingen (spec §8).
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-evidence-promotion.sql
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/test-interpretation-predicate.sql
psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f tests/sql/run-db-verify-disposable.sql
echo UPGRADE_OK
