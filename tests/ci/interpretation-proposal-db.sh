#!/usr/bin/env bash
# Én katalogrækkefølge af interpretation_proposal-projektionens DB-bevis, i sin
# egen friske database. CI kalder scriptet én gang pr. rækkefølge i SAMME job
# (tidligere en matrix med to jobs — hver sin R-opsætning og minutafrunding).
#
# Loginrollerne er cluster-globale og oprettes idempotent; EXECUTE på
# pg_control_system() er pr. database og tildeles derfor hver gang.
#
# Brug: tests/ci/interpretation-proposal-db.sh <schema-rls-migrations|schema-migrations-rls>
# Forudsætter PGHOST/PGPORT/PGUSER/PGPASSWORD mod en superuser og Rscript med
# DBI, RPostgres, jsonlite, digest og testthat.
set -euo pipefail

catalog_order="${1:?katalogrækkefølge mangler}"
case "$catalog_order" in
  schema-rls-migrations|schema-migrations-rls) ;;
  *) echo "ukendt katalogrækkefølge: $catalog_order" >&2; exit 1 ;;
esac

export PGDATABASE="proposal_projection_${catalog_order//-/_}"
out_dir="ci-out/${catalog_order}"
mkdir -p "$out_dir"
createdb "$PGDATABASE"

echo "::group::Bootstrap, dedikerede logins og katalog ($catalog_order)"
psql -v ON_ERROR_STOP=1 -f tests/sql/evidence-promotion-bootstrap.sql
psql -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='daa_proposal_ci') THEN
    CREATE ROLE daa_proposal_ci NOINHERIT LOGIN PASSWORD 'ci-operation' IN ROLE authenticated;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='daa_proposal_authorizer_ci') THEN
    CREATE ROLE daa_proposal_authorizer_ci NOINHERIT LOGIN PASSWORD 'ci-authorizer' IN ROLE service_role;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='daa_proposal_nonmember_ci') THEN
    CREATE ROLE daa_proposal_nonmember_ci NOINHERIT LOGIN PASSWORD 'ci-nonmember';
  END IF;
  IF NOT has_function_privilege('daa_proposal_ci','pg_control_system()','EXECUTE') THEN
    GRANT EXECUTE ON FUNCTION pg_control_system() TO daa_proposal_ci;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname LIKE 'daa_proposal_%' AND (rolsuper OR rolinherit)) THEN
    RAISE EXCEPTION 'CI_PROPOSAL_LOGIN_INVALID';
  END IF;
  IF (SELECT array_agg(g.rolname::text ORDER BY g.rolname) FROM pg_auth_members m
        JOIN pg_roles r ON r.oid=m.member JOIN pg_roles g ON g.oid=m.roleid
       WHERE r.rolname='daa_proposal_ci') IS DISTINCT FROM ARRAY['authenticated']
     OR (SELECT array_agg(g.rolname::text ORDER BY g.rolname) FROM pg_auth_members m
        JOIN pg_roles r ON r.oid=m.member JOIN pg_roles g ON g.oid=m.roleid
       WHERE r.rolname='daa_proposal_authorizer_ci') IS DISTINCT FROM ARRAY['service_role']
     OR EXISTS (SELECT 1 FROM pg_auth_members m JOIN pg_roles r ON r.oid=m.member
       WHERE r.rolname='daa_proposal_nonmember_ci') THEN
    RAISE EXCEPTION 'CI_PROPOSAL_MEMBERSHIP_INVALID';
  END IF;
END $$;
SQL
psql -v ON_ERROR_STOP=1 -f schema.sql
case "$catalog_order" in
  schema-rls-migrations)
    psql -v ON_ERROR_STOP=1 -f db-rls.sql
    psql -v ON_ERROR_STOP=1 -f db-migrations.sql
    psql -v ON_ERROR_STOP=1 -f db-migrations.sql ;;
  schema-migrations-rls)
    psql -v ON_ERROR_STOP=1 -f db-migrations.sql
    psql -v ON_ERROR_STOP=1 -f db-migrations.sql ;;
esac
psql -v ON_ERROR_STOP=1 -f db-rls.sql
echo "::endgroup::"

echo "::group::Receipt-kontrakt og db-verify ($catalog_order)"
psql -v ON_ERROR_STOP=1 -f tests/sql/test-interpretation-proposal.sql
psql -v ON_ERROR_STOP=1 -f tests/sql/run-db-verify-disposable.sql
echo "::endgroup::"

echo "::group::Syntetiske writer-fixtures ($catalog_order)"
psql -v ON_ERROR_STOP=1 -f tests/sql/1939-v50-writer-bootstrap.sql
psql -v ON_ERROR_STOP=1 -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
psql -v ON_ERROR_STOP=1 -f db-rls.sql
echo "::endgroup::"

echo "::group::Negative logins ($catalog_order)"
if PGUSER=daa_proposal_nonmember_ci PGPASSWORD=ci-nonmember psql -v ON_ERROR_STOP=1 \
     -c 'BEGIN' -c 'SET LOCAL ROLE authenticated' > "$out_dir/nonmember.out" 2>&1; then
  echo "ikke-medlem kunne skifte til authenticated" >&2; exit 1
fi
grep -Fq 'permission denied to set role' "$out_dir/nonmember.out"
if DAA_PROPOSAL_STRICT_LOGINS=1 DAA_PROPOSAL_OPERATION_PGUSER="$PGUSER" DAA_PROPOSAL_OPERATION_PGPASSWORD="$PGPASSWORD" \
     DAA_PROPOSAL_AUTHORIZER_PGUSER=daa_proposal_authorizer_ci DAA_PROPOSAL_AUTHORIZER_PGPASSWORD=ci-authorizer \
     Rscript tests/integration/test-reimport-interpretation-proposal.R > "$out_dir/superuser.out" 2>&1; then
  echo "superuser-login blev accepteret som operationslogin" >&2; exit 1
fi
grep -Fq 'INTEGRATION_LOGIN_SUPERUSER:OPERATION' "$out_dir/superuser.out"
echo "::endgroup::"

echo "::group::Dry-run, apply, match og replay gennem dedikerede logins ($catalog_order)"
DAA_PYTHON="${DAA_PYTHON:-python3}" \
DAA_REIMPORT_TEST_ROLE=authenticated \
DAA_PROPOSAL_STRICT_LOGINS=1 \
DAA_PROPOSAL_OPERATION_PGUSER=daa_proposal_ci \
DAA_PROPOSAL_OPERATION_PGPASSWORD=ci-operation \
DAA_PROPOSAL_AUTHORIZER_PGUSER=daa_proposal_authorizer_ci \
DAA_PROPOSAL_AUTHORIZER_PGPASSWORD=ci-authorizer \
  Rscript tests/integration/test-reimport-interpretation-proposal.R > "$out_dir/integration.out" 2>&1 \
  || { tail -n 40 "$out_dir/integration.out"; exit 1; }
tail -n 1 "$out_dir/integration.out" | grep -Fx 'interpretation_proposal integration OK'
echo "::endgroup::"
echo "interpretation_proposal $catalog_order OK"
