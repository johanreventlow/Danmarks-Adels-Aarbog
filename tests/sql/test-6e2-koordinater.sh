#!/usr/bin/env bash
# Trin 6e-2 Task 3: koordinat-RPC'en (kildegate på 1939's nøgle, printed_page, mængdebaseret medlemskab).
# Frisk base (bootstrap + schema.sql + db-rls.sql): test-6e2-koordinater.sql og den eksisterende koordinattest.
# Kun lokalt/CI. Ved succes droppes basen, scriptet selv oprettede (<db>); ved fejl står den tilbage.
set -euo pipefail
db=${1:?database}
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$1" "${@:2}" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql \
         tests/sql/test-6e2-koordinater.sql tests/sql/test-person-source-coordinates.sql; do q "$db" -f "$f"; done
dropdb --if-exists "$db"
echo KOORDINATER_OK
