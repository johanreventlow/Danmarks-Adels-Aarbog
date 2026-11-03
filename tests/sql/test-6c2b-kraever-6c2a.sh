#!/usr/bin/env bash
# Trin 6c-2: 6c-2b-blokken kræver 6c-2a. red_ret_paastand (6c-2b) kalder private.binding_value_matches, som kun
# 6c-2a opretter; plpgsql slår kaldet op ved kørsel, så uden vagten ville 6c-2b lykkes og først fejle ved den første
# rettelse. Blokkene udtrækkes som ceremonien gør: fra overskriften til næste `-- ===== ` (eller filens slutning).
# Basen skal have alle migrationer; begge tilfælde kører i én transaktion, der rulles tilbage, så basen er uændret:
#   1) binding_value_matches omdøbt væk, kun 6c-2b anvendt: afvises med MIGRATION_6C2B_KRAEVER_6C2A;
#   2) binding_value_matches omdøbt væk, 6c-2a og derefter 6c-2b anvendt: lykkes.
set -euo pipefail
db=${1:?database}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
blok() {  # $1 = overskriftens tekst mellem '-- ===== ' og ' ====='; $2 = målfil
  awk -v h="-- ===== $1 =====" '$0==h{on=1;print;next} on&&/^-- ===== /{exit} on{print}' db-migrations.sql > "$2"
  [ "$(head -n1 "$2")" = "-- ===== $1 =====" ] && [ "$(wc -l < "$2")" -gt 1 ] || { echo "BLOK_MANGLER: $1" >&2; exit 1; }
}
blok 'trin 6c-2a: set-baseret bindingstjek (vej B)' "$tmp/6c2a.sql"
blok 'trin 6c-2b: forslagsversion, påstandsrettelse, én binding pr. påstand' "$tmp/6c2b.sql"
grep -q 'binding_value_matches' "$tmp/6c2b.sql" || { echo 'BLOK_6C2B_KALDER_IKKE_BINDING_VALUE_MATCHES' >&2; exit 1; }
omdoeb="ALTER FUNCTION private.binding_value_matches(text,jsonb,text,text) RENAME TO binding_value_matches_6c2b_vagt;"

# 1) Uden 6c-2a: vagten afviser blokken, før noget andet i den kører.
printf 'BEGIN;\n%s\n\\i %s\nROLLBACK;\n' "$omdoeb" "$tmp/6c2b.sql" > "$tmp/uden.sql"
if env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$tmp/uden.sql" >"$tmp/uden.out" 2>&1; then
  echo 'TEST_6C2B_UDEN_6C2A_LYKKEDES' >&2; exit 1
fi
grep -q 'MIGRATION_6C2B_KRAEVER_6C2A' "$tmp/uden.out" || { echo 'TEST_6C2B_FORKERT_FEJL:' >&2; cat "$tmp/uden.out" >&2; exit 1; }

# 2) Med 6c-2a først: blokken lykkes, og funktionen findes igen.
printf 'BEGIN;\n%s\n\\i %s\n\\i %s\n%s\nROLLBACK;\n' "$omdoeb" "$tmp/6c2a.sql" "$tmp/6c2b.sql" \
  "DO \$\$ BEGIN IF to_regprocedure('private.binding_value_matches(text,jsonb,text,text)') IS NULL THEN RAISE EXCEPTION 'TEST_6C2A_OPRETTEDE_IKKE'; END IF; END \$\$;" \
  > "$tmp/med.sql"
env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" -f "$tmp/med.sql" >"$tmp/med.out" 2>&1 \
  || { echo 'TEST_6C2B_MED_6C2A_FEJLEDE:' >&2; cat "$tmp/med.out" >&2; exit 1; }

# Basen er uændret: funktionen har sit eget navn, og omdøbningen findes ikke.
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT to_regprocedure('private.binding_value_matches(text,jsonb,text,text)') IS NOT NULL
  AND to_regprocedure('private.binding_value_matches_6c2b_vagt(text,jsonb,text,text)') IS NULL")" = "t" ]
echo 'MIGRATION_6C2B_KRAEVER_6C2A OK'
