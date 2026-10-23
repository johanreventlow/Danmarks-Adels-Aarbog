#!/usr/bin/env bash
# 5a+5b-overførslen, plan B1 Task 1-2: nøglekort, nøglede digests, uberørt-hash, andre kilder og værn. Samme kæde i to baser med forskellig collation,
# tidszone og tilfældig forhistorik skal give ens digests, selv om tilfældige id'er (fortolkninger, bindinger) er forskellige;
# en ændret værdi, en ombytning, et andet mål og et ukendt tilfældigt uuid skal derimod give en afvigelse i netop det lag.
# Brug: bash tests/sql/test-transfer-5ab-digests.sh <prefix>
set -euo pipefail
pre=${1:?prefix}; A=${pre}_a; B=${pre}_b; C=${pre}_c; M=${pre}_m; N=${pre}_n; O=${pre}_o
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
source tests/sql/lib-transfer-5ab.sh
fail() { echo "DG5AB_FAIL: $*"; exit 1; }
dg() { qa "$1" -v src="$2" ${3:+-v mode=$3} -f $S/transfer_5ab_digests.sql; }
km() { qa "$1" -f $S/transfer_5ab_keymap.sql; }
t5_build_ab tests/sql/fixtures/indholds-id-dump.sql tests/sql/fixtures/transfer-5ab-dispositions-dump.sql
# C: kopi af A før kæden, til uberørt-målingen med en kæde, der kun skriver i -25001 (Task 2).
t5_clone "$A" "$C"
t5_chain "$A" tests/sql/fixtures/indholds-id-chain.sql; t5_chain "$B" tests/sql/fixtures/indholds-id-chain.sql
for s in -25001 -25002; do dg "$A" $s > "$tmp/a$s.dg"; dg "$B" $s > "$tmp/b$s.dg"; done
grep -q '^daa.transfer_5ab_digests={' "$tmp/a-25001.dg" || fail "uventet udskrift: $(head -c 80 "$tmp/a-25001.dg")"

# dg_same: ens digests for begge kilder, intet uoversat uuid.
for s in -25001 -25002; do
  d=$(dgcmp "$tmp/a$s.dg" "$tmp/b$s.dg"); [ -z "$d" ] || fail "dg_same $s: $d"
  for x in a b; do [ "$(dgval "$tmp/$x$s.dg" n_uuid_unmapped)" = 0 ] || fail "dg_same $s: n_uuid_unmapped i $x"; done
done
echo "dg_same OK"

# dg_ids_differ (vagt): de tilfældige id'er er faktisk forskellige i A og B.
alias_ids() { qa "$1" -c "SELECT string_agg(id::text,',' ORDER BY id) FROM ($2) x"; }
[ "$(alias_ids "$A" "SELECT id FROM private.interpretation WHERE source_id=-25001")" != \
  "$(alias_ids "$B" "SELECT id FROM private.interpretation WHERE source_id=-25001")" ] || fail "dg_ids_differ: fortolknings-id'er ens"
pq="SELECT p.id FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id WHERE i.source_id=-25002"
[ "$(alias_ids "$A" "$pq")" != "$(alias_ids "$B" "$pq")" ] || fail "dg_ids_differ: bindings-id'er ens"
echo "dg_ids_differ OK"

# dg_layers_nonempty (vagt).
for l in personas identities candidates control_samples interpretations parties classifications; do
  [ "$(dgval "$tmp/a-25001.dg" $l)" -ge 1 ] || fail "dg_layers_nonempty: $l tom i -25001"; done
for l in bindings family_sources; do
  [ "$(dgval "$tmp/a-25002.dg" $l)" -ge 1 ] || fail "dg_layers_nonempty: $l tom i -25002"; done
echo "dg_layers_nonempty OK"

# mut <navn> <kilde> <sql>: kopi af B med ændringen (triggere slået fra) og digesten målt i kopien.
ct() { qa "$1" -v src="$2" -f $S/transfer_5ab_content.sql; }
mut() { t5_clone "$B" "$M"; q "$M" -c "SET session_replication_role=replica" -c "$3"; dg "$M" "$2" > "$tmp/$1.dg"; }
# dg_value: én ændret marriage_ordinal ⇒ kun parties.
mut value -25001 "UPDATE private.interpretation_party SET marriage_ordinal=marriage_ordinal+10 WHERE (interpretation_key,party_role,version)=
  (SELECT interpretation_key,party_role,version FROM private.interpretation_party ip WHERE marriage_ordinal IS NOT NULL
     AND interpretation_key IN (SELECT interpretation_key FROM private.interpretation WHERE source_id=-25001) ORDER BY 1,2,3 LIMIT 1)"
[ "$(dgcmp "$tmp/b-25001.dg" "$tmp/value.dg")" = parties ] || fail "dg_value: $(dgcmp "$tmp/b-25001.dg" "$tmp/value.dg")"
dg "$M" -25001 rows > "$tmp/value.rows"; ct "$M" -25001 > "$tmp/value.ct"; dropdb "$M"
echo "dg_value OK"
# ct_same / ct_value (plan B2 Task 2): indholdsprojektionen er ens i A og B trods andre tilfældige id'er, collation og
# tidszone, og dg_value's ændrede nummer giver præcis én afvigende linje i laget ordinal.
for s in -25001 -25002; do
  ct "$A" $s > "$tmp/a$s.ct"; ct "$B" $s > "$tmp/b$s.ct"
  cmp -s "$tmp/a$s.ct" "$tmp/b$s.ct" || fail "ct_same $s: A og B afviger ($(diff "$tmp/a$s.ct" "$tmp/b$s.ct" | grep -c '^[<>]') linjer)"
done
for l in binding ordinal identity origin classification interpretation persona family_source disposition; do
  cut -d'|' -f1 "$tmp/a-25001.ct" "$tmp/a-25002.ct" | grep -qx "$l" || fail "ct_same: laget $l tomt"; done
echo "ct_same OK"
ch=$(comm -3 <(LC_ALL=C sort "$tmp/b-25001.ct") <(LC_ALL=C sort "$tmp/value.ct") | sed 's/^\t//' | cut -d'|' -f1-2 | LC_ALL=C sort -u)
[ "$(echo "$ch" | wc -l | tr -d ' ')" = 1 ] && [ "${ch%%|*}" = ordinal ] || fail "ct_value: ændringen gav '$ch'"
echo "ct_value OK"
# dg_swap: ombyttet afgørelse (canonical_person_id) mellem to accepterede personas ⇒ identities. (decision_status selv kan
# ikke byttes mellem accepted og andet: source_persona_identity_target_check.)
mut swap -25001 "WITH p AS (SELECT i.source_persona_id id,i.canonical_person_id c,
    row_number() OVER (ORDER BY i.canonical_person_id) r, count(*) OVER () n
    FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id
   WHERE sp.source_id=-25001 AND i.decision_status='accepted'),
  x AS (SELECT (SELECT id FROM p WHERE r=1) a,(SELECT c FROM p WHERE r=1) ca,(SELECT id FROM p WHERE r=n) b,(SELECT c FROM p WHERE r=n) cb)
  UPDATE private.source_persona_identity i SET canonical_person_id=CASE WHEN i.source_persona_id=x.a THEN x.cb ELSE x.ca END
    FROM x WHERE i.source_persona_id IN (x.a,x.b) AND x.ca<>x.cb"
d=$(dgcmp "$tmp/b-25001.dg" "$tmp/swap.dg"); dropdb "$M"; [ "$d" = identities ] || fail "dg_swap: '$d'"
echo "dg_swap OK"
# dg_target: én binding med andet target_id ⇒ bindings (og højst family_sources).
mut target -25002 "UPDATE private.interpretation_promotion SET target_id=target_id+1000 WHERE id=(SELECT p.id FROM private.interpretation_promotion p
  JOIN private.interpretation i ON i.id=p.interpretation_id WHERE i.source_id=-25002 ORDER BY p.target_id LIMIT 1)"
d=$(dgcmp "$tmp/b-25002.dg" "$tmp/target.dg"); dropdb "$M"
case "$d" in bindings|bindings,family_sources) ;; *) fail "dg_target: '$d'";; esac
echo "dg_target OK"

# dg_unmapped: samme logiske række i A og B med hver sit tilfældige uuid i evidensen ⇒ laget afviger, tællerne > 0, og
# mode=unmapped navngiver tabel og nøgle (uden uuid).
uq="UPDATE private.source_persona_identity SET evidence=evidence||jsonb_build_object('fremmed',gen_random_uuid())
  WHERE source_persona_id=(SELECT i.source_persona_id FROM private.source_persona_identity i JOIN private.source_persona sp
    ON sp.id=i.source_persona_id WHERE sp.source_id=-25001 ORDER BY sp.persona_key COLLATE \"C\" LIMIT 1)"
t5_clone "$A" "$N"; t5_clone "$B" "$O"
for x in N O; do db=${!x}; q "$db" -c "SET session_replication_role=replica" -c "$uq"; dg "$db" -25001 > "$tmp/u$x.dg"
  dg "$db" -25001 unmapped > "$tmp/u$x.um"; done
[ "$(dgcmp "$tmp/uN.dg" "$tmp/uO.dg")" = identities ] || fail "dg_unmapped: $(dgcmp "$tmp/uN.dg" "$tmp/uO.dg")"
for x in N O; do [ "$(dgval "$tmp/u$x.dg" n_uuid_unmapped)" -ge 1 ] || fail "dg_unmapped: tæller 0 i $x"
  grep -qx 'identities|source_persona_identity.evidence|1' "$tmp/u$x.um" || fail "dg_unmapped: mode=unmapped '$(head -3 "$tmp/u$x.um")'"
  grep -Eq '[0-9a-f]{8}-[0-9a-f]{4}-' "$tmp/u$x.um" && fail "dg_unmapped: uuid i mode=unmapped"; done
dropdb "$N"; dropdb "$O"
echo "dg_unmapped OK"

# dg_rows: rækkeudskriften er ens i A og B, og dg_value's ændring giver præcis én afvigende linje (samme lag og nøgle).
dg "$A" -25001 rows > "$tmp/a.rows"; dg "$B" -25001 rows > "$tmp/b.rows"
cmp -s "$tmp/a.rows" "$tmp/b.rows" || fail "dg_rows: A og B afviger ($(diff "$tmp/a.rows" "$tmp/b.rows" | grep -c '^[<>]') linjer)"
[ "$(wc -l < "$tmp/a.rows")" -ge 20 ] || fail "dg_rows: for få linjer"
ch=$(comm -3 <(LC_ALL=C sort "$tmp/b.rows") <(LC_ALL=C sort "$tmp/value.rows") | sed 's/^\t//' | cut -d'|' -f1-2 | LC_ALL=C sort -u)
[ "$(echo "$ch" | wc -l | tr -d ' ')" = 1 ] && [ "${ch%%|*}" = parties ] || fail "dg_rows: ændringen gav '$ch'"
echo "dg_rows OK"

# dg_readonly: eget kald med PGOPTIONS bevaret (harnessets q/qa fjerner den); positiv kontrol: en skrivning fejler.
ro() { PGOPTIONS='-c default_transaction_read_only=on' psql -X -Atq -v ON_ERROR_STOP=1 -d "$A" "$@"; }
ro -v src=-25001 -f $S/transfer_5ab_digests.sql > "$tmp/ro.dg" 2>"$tmp/ro.err" || fail "dg_readonly: digests ($(head -1 "$tmp/ro.err"))"
cmp -s "$tmp/ro.dg" "$tmp/a-25001.dg" || fail "dg_readonly: anden digest"
ro -f $S/transfer_5ab_keymap.sql > /dev/null 2>"$tmp/ro.err" || fail "dg_readonly: nøglekort ($(head -1 "$tmp/ro.err"))"
# ct_readonly: projektionen (med anon-kaldet) kører også under default_transaction_read_only.
ro -v src=-25002 -f $S/transfer_5ab_content.sql > "$tmp/ro.ct" 2>"$tmp/ro.err" || fail "ct_readonly: $(head -1 "$tmp/ro.err")"
cmp -s "$tmp/ro.ct" "$tmp/a-25002.ct" || fail "ct_readonly: anden projektion"
if ro -c "INSERT INTO public.note DEFAULT VALUES" >/dev/null 2>"$tmp/ro.err"; then fail "dg_readonly: skrivning lykkedes"; fi
grep -q 'read-only transaction' "$tmp/ro.err" || fail "dg_readonly: skrivningen fejlede af anden grund: $(head -1 "$tmp/ro.err")"
echo "dg_readonly OK"

# km_unique: nøglekortet er unikt på uuid; opslagsklasserne (ikke binding:, genbinding er tilladt) er unikke på nøgle; aktørens profil står ikke i kortet.
km "$A" > "$tmp/a.km"
[ "$(cut -d'|' -f1 "$tmp/a.km" | sort | uniq -d | wc -l | tr -d ' ')" = 0 ] || fail "km_unique: dublet på uuid"
lk='^(persona|fortolkning|kandidatkoersel|kandidat|kontrol|foraelderkort|stikproeve|omtale|disposition):'
dup=$(cut -d'|' -f2 "$tmp/a.km" | grep -E "$lk" | sort | uniq -d | head -3); [ -z "$dup" ] || fail "km_unique: dublet på nøgle ($dup)"
for c in persona fortolkning kandidatkoersel kandidat kontrol stikproeve omtale; do
  grep -q "|$c:" "$tmp/a.km" || fail "km_unique: ingen $c-linjer"; done
grep -q '11000000-0000-0000-0000-000000025001' "$tmp/a.km" && fail "km_unique: aktørens uuid i nøglekortet"
grep -q '|profil:' "$tmp/a.km" && fail "km_unique: profilklassen i nøglekortet"
echo "km_unique OK"

# km_old_tree: nøglekortet og digests kører på prods træ før GO 1 (b42266e, uden 5b-tabeller).
old=${pre}_old; dropdb --if-exists "$old" >/dev/null 2>&1 || true; createdb -E UTF8 --template=template0 --locale=C "$old"
ot=$(mktemp -d "$tmp/old.XXXX"); for f in schema.sql db-rls.sql; do git show "b42266e:$f" > "$ot/$f"; done
for f in tests/sql/evidence-promotion-bootstrap.sql "$ot/schema.sql" "$ot/db-rls.sql"; do q "$old" -f "$f"; done
km "$old" > "$tmp/old.km"; dg "$old" -25001 > "$tmp/old.dg"
grep -Eq "$lk" "$tmp/old.km" && fail "km_old_tree: 5b-klasser i et træ uden 5b-data"
grep -q '^daa.transfer_5ab_digests={' "$tmp/old.dg" || fail "km_old_tree: ingen digest"
dropdb "$old"
echo "km_old_tree OK"

# --- Task 2: uberørt-hash, andre kilder og værn ---
uh() { qa "$1" -v src="$2" -f $S/transfer_5ab_untouched_hash.sql; }
gd() { qa "$1" -v src="$2" -f $S/transfer_5ab_guards.sql; }
# un_before_after: transfer-5ab-chain.sql skriver kun i -25001 ⇒ uberørt-hashen og andre kilder er uændrede i samme base.
uh "$C" -25001 > "$tmp/c.before"
grep -Eq '^daa.transfer_5ab_untouched=[0-9a-f]{64}$' "$tmp/c.before" && grep -Eq '^daa.transfer_5ab_other_sources=[0-9a-f]{64}$' "$tmp/c.before" \
  || fail "un_before_after: uventet udskrift"
t5_chain "$C" tests/sql/fixtures/transfer-5ab-chain.sql
uh "$C" -25001 > "$tmp/c.after"
cmp -s "$tmp/c.before" "$tmp/c.after" || fail "un_before_after: $(diff "$tmp/c.before" "$tmp/c.after" | grep '^>' | cut -d= -f1 | tr '\n' ' ')"
# Vagt: kæden skrev faktisk (personas i -25001 voksede).
[ "$(qa "$C" -c "SELECT count(*) FROM private.source_persona WHERE source_id=-25001")" -gt \
  "$(qa "$A" -c "SELECT count(*) FROM private.source_persona p WHERE p.source_id=-25001 AND p.persona_key NOT LIKE '%#rel-marriage-%'")" ] \
  || fail "un_before_after: kæden skrev ingen personas"
echo "un_before_after OK"
# un_other_source: B's forhistoriske persona i en anden kilde (-25099) ændret ⇒ kun other_sources afviger.
uh "$B" -25001 > "$tmp/b.uh"
[ "$(qa "$B" -c "SELECT count(*) FROM private.source_persona WHERE source_id=-25099")" -ge 1 ] || fail "un_other_source: ingen persona i -25099"
mut other -25001 "UPDATE private.source_persona SET persona_key=persona_key||'-x' WHERE source_id=-25099"
uh "$M" -25001 > "$tmp/m.uh"; dropdb "$M"
d=$( { diff "$tmp/b.uh" "$tmp/m.uh" || true; } | { grep '^>' || true; } | cut -c3- | cut -d= -f1 | tr -d '\n')
[ "$d" = daa.transfer_5ab_other_sources ] || fail "un_other_source: '$d'"
# Positiv kontrol: en ændring uden for kædens tabeller (public.person) flytter uberørt-hashen.
mut untouched -25001 "UPDATE public.person SET visning_navn=coalesce(visning_navn,'')||'.' WHERE id=(SELECT min(id) FROM public.person)"
uh "$M" -25001 > "$tmp/m2.uh"; dropdb "$M"
d=$( { diff "$tmp/b.uh" "$tmp/m2.uh" || true; } | { grep '^>' || true; } | cut -c3- | cut -d= -f1 | tr -d '\n')
[ "$d" = daa.transfer_5ab_untouched ] || fail "un_other_source: positiv kontrol '$d'"
echo "un_other_source OK"
# dg_dispositions_nonempty: dispositionsfixturen giver ét lag med n ≥ 1, ens i A og B.
[ "$(dgval "$tmp/a-25001.dg" dispositions)" -ge 1 ] || fail "dg_dispositions_nonempty: tom"
echo "dg_dispositions_nonempty OK"
# gd_values: værnene i A.
gd "$A" -25001 > "$tmp/a1.gd"; gd "$A" -25002 > "$tmp/a2.gd"
gv() { python3 -I -c 'import json,sys; j=json.loads(open(sys.argv[1]).read().split("=",1)[1]); v=j
for p in sys.argv[2].split("."): v=v[p]
print(v)' "$1" "$2"; }
[ "$(gv "$tmp/a1.gd" person_create_elements)" = 0 ] || fail "gd_values: person_create_elements $(gv "$tmp/a1.gd" person_create_elements)"
[ "$(gv "$tmp/a2.gd" ordinal_correction_rows)" -ge 1 ] || fail "gd_values: ordinal_correction_rows i -25002"
[ "$(gv "$tmp/a1.gd" book_ordinal_match.n_total)" -ge 1 ] || fail "gd_values: ingen »N°« i -25001"
gd "$B" -25001 > "$tmp/b1.gd"; cmp -s "$tmp/a1.gd" "$tmp/b1.gd" || fail "gd_values: A og B afviger"
PGOPTIONS='-c default_transaction_read_only=on' psql -X -Atq -v ON_ERROR_STOP=1 -d "$A" -v src=-25001 -f $S/transfer_5ab_guards.sql >/dev/null 2>&1 \
  && PGOPTIONS='-c default_transaction_read_only=on' psql -X -Atq -v ON_ERROR_STOP=1 -d "$A" -v src=-25001 -f $S/transfer_5ab_untouched_hash.sql >/dev/null 2>&1 \
  || fail "gd_values: værn eller uberørt-hash kører ikke læse-kun"
echo "gd_values OK"

# gd_ordinal_null: en ægtefællepart uden persona har intet nummer (tilladt, interpretation_party_ordinal_check) og modsiger
# ikke bogen; serverens egen kontrol (ORDINAL_BOOK_MISMATCH) rammer den heller aldrig. Et forkert nummer tæller derimod.
[ "$(gv "$tmp/a1.gd" ordinal_book_mismatch)" = 0 ] || fail "gd_ordinal_null: ordinal_book_mismatch i A"
G=${pre}_g; t5_clone "$A" "$G"
party() { q "$G" -v n="$1" <<'SQL'
INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,origin,origin_ref)
SELECT pc.interpretation_key,'spouse',pc.version+1,NULL,nullif(:n,0),'relation_decision',gen_random_uuid()
  FROM private.interpretation_current ic JOIN private.interpretation_party_current pc
    ON pc.interpretation_key=ic.interpretation_key AND pc.party_role='spouse'
 WHERE ic.source_id=-25001 AND ic.predicate='relation.marriage' AND private.relation_book_ordinal(ic.value->>'raw') IS NOT NULL
 ORDER BY pc.interpretation_key::text COLLATE "C" LIMIT 1;
SQL
}
party 0 >/dev/null; [ "$(gv <(gd "$G" -25001) ordinal_book_mismatch)" = 0 ] || fail "gd_ordinal_null: part uden persona talt som afvigelse"
party 99 >/dev/null; [ "$(gv <(gd "$G" -25001) ordinal_book_mismatch)" = 1 ] || fail "gd_ordinal_null: forkert nummer ikke talt"
dropdb "$G"; echo "gd_ordinal_null OK"

dropdb "$A"; dropdb "$B"; dropdb "$C"; echo DG5AB_OK
