#!/usr/bin/env bash
# Trin 6e-2 Task 2: postetiket uden bogtrykt nøgle og tom postdel.
# 1) Frisk base (bootstrap + schema.sql + db-rls.sql): test-6e2-etiket.sql.
# 2) Opgradering fra base-skemaet (2. arg = base-commit, default merge-base med origin/main): migrationen to gange, samme test,
#    byte-ens funktionskroppe/ACL, og bindingens CHECK identisk med schema.sql.
# Ved succes droppes de to baser, scriptet selv oprettede (<db>, <db>_u); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
db="$name"; dbu="${name}_u"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
createdb "$db"; createdb "$dbu"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/test-6e2-etiket.sql; do q "$db" -f "$f"; done
echo FRISK_OK
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql"; do q "$dbu" -f "$f"; done
[ "$(a "$dbu" "SELECT count(*) FROM pg_proc WHERE proname='narrative_record_wanted_labels'")" = "0" ] \
  || { echo "UPGRADE_BASE_INVALID: etiketreglen findes allerede i $base" >&2; exit 1; }
q "$dbu" -f db-migrations.sql
q "$dbu" -f db-migrations.sql -f db-rls.sql -f db-migrations.sql   # hel fil igen: ældre blokke må ikke genoprette den gamle CHECK/validator
q "$dbu" -f tests/sql/test-6e2-etiket.sql
sha() { for f in 'private.linje_kode(text,text)' 'private.record_key_uden_bognoegle(text)' 'private.narrative_record_wanted_labels(uuid)' 'private.narrative_record_wanted_labels_ex(uuid,boolean)' 'private.narrative_record_labels(uuid)' 'private.validate_reimport_case_elements(jsonb,jsonb)'; do
  a "$1" "SELECT '$f|'||encode(extensions.digest(convert_to(pg_get_functiondef(to_regprocedure('$f')),'UTF8'),'sha256'),'hex')||'|'||coalesce((SELECT proacl::text FROM pg_proc WHERE oid=to_regprocedure('$f')),'NULL')"; done
  a "$1" "SELECT 'check|'||pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='private.narrative_record_publication'::regclass AND conname='narrative_record_publication_record_label_check'"; }
[ "$(sha "$db")" = "$(sha "$dbu")" ] || { echo "UPGRADE_BODY_OR_ACL_MISMATCH" >&2; diff <(sha "$db") <(sha "$dbu") >&2 || true; exit 1; }
dropdb --if-exists "$db"; dropdb --if-exists "$dbu"
echo UPGRADE_OK
