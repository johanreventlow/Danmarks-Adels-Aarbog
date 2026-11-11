#!/usr/bin/env bash
# Trin 6d-3: opgradering fra main (prods skema før 6d-3): DDL-blokken løftes; migrationerne køres to gange på en base, hvor
# kilde 1 og 3 findes (som i prod), så profil-seeds'ene indsættes; de ændrede og nye funktioner har bagefter præcis
# schema.sql's kroppe (sha256 af pg_get_functiondef, målt på en frisk base bygget her) og samme proacl; præcis to overloads
# af relation_ordered_windows; profiltabellen er privat og har de fire seeds uden dubletter; 6d-3's to testfiler og
# db-verify er grønne. Ingen kilde 1-md5 her: opgraderingsbaserne er tomme, så md5 ville sammenligne tomt med tomt.
# Kun lokalt/CI. Ved succes droppes de tre baser, scriptet selv oprettede (<db>, <db>_f, <db>_v); ved fejl står de tilbage.
set -euo pipefail
name=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
db="$name"; dbf="${name}_f"; dbv="${name}_v"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
a() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
# Funktioner, der findes både før og efter 6d-3 (kroppen ændres).
fns="private.write_relation_persona(uuid,text,jsonb) private.relation_ordered_windows(text,text) private.relation_marriage_ordinals(uuid) private.identity_candidate_input(bigint,jsonb) private.verify_relation_persona_receipts(uuid)"
# Nye i 6d-3 (findes ikke i base-versionen): MISSING i den gamle base.
newfns="private.relation_ordered_windows(text,text,text) private.relation_text_form(bigint) private.relation_fold_raw_text(text) private.relation_name_compare_text(bigint,text)"
sha() { # sha256 af kroppen + proacl for hver funktion i den angivne base, ét sæt linjer
  for f in $fns $newfns; do a "$1" "SELECT '$f|'||coalesce((SELECT encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex')||'|'||coalesce(p.proacl::text,'NULL') FROM pg_proc p WHERE p.oid=to_regprocedure('$f')),'MISSING')"; done
}
createdb "$db"; createdb "$dbf"; createdb "$dbv"
# Frisk reference: kun schema.sql + rls (som CI's frisk schema-sti).
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do q "$dbf" -f "$f"; done
fresh=$(sha "$dbf")
! grep -q MISSING <<<"$fresh" || { echo "FRESH_INVALID: en 6d-3-funktion mangler i schema.sql" >&2; echo "$fresh" >&2; exit 1; }
# Prods skema: base-versionens skema, rls, migrationer to gange.
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q "$db" -f "$f"; done
old=$(sha "$db")
for f in $newfns; do
  grep -qF "$f|MISSING" <<<"$old" || { echo "UPGRADE_BASE_INVALID: $f findes allerede i $base" >&2; exit 1; }
done
[ "$(a "$db" "SELECT to_regclass('private.relation_persona_profile') IS NULL")" = "t" ] || { echo "UPGRADE_BASE_INVALID: relation_persona_profile findes allerede i $base" >&2; exit 1; }
# De gamle kroppe er til stede og adskiller sig fra de nye (ellers beviser opgraderingen intet).
for f in $fns; do
  [ "$(grep -F "$f|" <<<"$old")" != "$(grep -F "$f|" <<<"$fresh")" ] || { echo "UPGRADE_BASE_INVALID: $f er allerede ny i $base" >&2; exit 1; }
done
# Som i prod findes kilde 1 og 3, før 6d-3's migrationer køres: seeds'ene indsættes af migrationen.
q "$db" -c "INSERT INTO public.source(id,titel,udgave,slags) VALUES(1,'Testudgave A','2018-20','DAA-udgave') ON CONFLICT(id) DO NOTHING" \
        -c "INSERT INTO public.source(id,titel,udgave,slags) VALUES(3,'Testudgave B','1939','DAA-udgave') ON CONFLICT(id) DO NOTHING"
# Opgradering: de aktuelle migrationer og rls to gange.
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q "$db" -f "$f"; done
new=$(sha "$db")
[ "$new" = "$fresh" ] || { echo "UPGRADE_BODY_OR_ACL_MISMATCH" >&2; diff <(echo "$fresh") <(echo "$new") >&2 || true; exit 1; }
[ "$(a "$db" "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='relation_ordered_windows'")" = "2" ] || { echo "UPGRADE_OVERLOAD_COUNT" >&2; exit 1; }
# ACL: ingen EXECUTE for anon/authenticated/service_role/PUBLIC på nogen af funktionerne (som i den friske base).
for f in $fns $newfns; do
  [ "$(a "$db" "SELECT NOT has_function_privilege('anon','$f','EXECUTE') AND NOT has_function_privilege('authenticated','$f','EXECUTE') AND NOT has_function_privilege('service_role','$f','EXECUTE')
    AND NOT EXISTS(SELECT 1 FROM pg_proc p, aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x WHERE p.oid=to_regprocedure('$f') AND x.grantee=0)")" = "t" ] || { echo "UPGRADE_ACL_MISMATCH: $f" >&2; exit 1; }
done
# Profiltabellen: RLS, ingen rettigheder til API-roller, PK (profile,source_id), fire seeds uden dubletter.
[ "$(a "$db" "SELECT c.relrowsecurity FROM pg_class c WHERE c.oid='private.relation_persona_profile'::regclass")" = "t" ] || { echo "UPGRADE_PROFILE_RLS" >&2; exit 1; }
[ "$(a "$db" "SELECT NOT EXISTS(SELECT 1 FROM pg_class c, aclexplode(coalesce(c.relacl,acldefault('r',c.relowner))) x
   WHERE c.oid='private.relation_persona_profile'::regclass AND (x.grantee=0 OR x.grantee IN (SELECT oid FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role'))))")" = "t" ] || { echo "UPGRADE_PROFILE_ACL" >&2; exit 1; }
[ "$(a "$db" "SELECT string_agg(a.attname,',' ORDER BY k.ord) FROM pg_constraint c CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY k(n,ord) JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.n WHERE c.conrelid='private.relation_persona_profile'::regclass AND c.contype='p'")" = "profile,source_id" ] || { echo "UPGRADE_PROFILE_PK" >&2; exit 1; }
seeds=$(a "$db" "SELECT profile||'|'||source_id||'|'||text_form||'|'||predicate_forms::text FROM private.relation_persona_profile ORDER BY profile")
expected='relation-persona-1939-v1|3|raw|{"relation.parent": "v1", "relation.marriage": "v3"}
relation-persona-2018-20-v1|1|folded|{"relation.child": "v1", "relation.parent": "v1", "relation.marriage": "v1"}
relation-persona-2018-20-v2|1|folded|{"relation.marriage": "v2"}
relation-persona-2018-20-v3|1|folded|{"relation.marriage": "v3"}'
[ "$seeds" = "$expected" ] || { echo "UPGRADE_SEEDS_MISMATCH" >&2; diff <(echo "$expected") <(echo "$seeds") >&2 || true; exit 1; }
# Writer-bootstrap som CI's writer-job (kontrakt v2 kræves af red_authorize_reimport), lagt oven på den opgraderede base.
q "$db" -f tests/sql/1939-v50-writer-bootstrap.sql
q "$db" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
q "$db" -f db-rls.sql
# 6d-3's testfiler (fra repo-roden: test-relation-fold læser sin fixture med relativ sti). De rører kun egne, rullede
# transaktioner med negative id'er.
for t in test-relation-persona-profile test-relation-fold; do q "$db" -f "tests/sql/$t.sql"; done
# Selvstændig base til db-verify (som test-6d1-upgrade.sh).
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q "$dbv" -f "$f"; done
# Oprydning: kun de tre baser, dette kald selv oprettede.
dropdb --if-exists "$db"; dropdb --if-exists "$dbf"; dropdb --if-exists "$dbv"
echo UPGRADE_OK
