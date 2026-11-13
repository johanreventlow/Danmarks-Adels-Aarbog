#!/usr/bin/env bash
# Trin 6e-2 Task 9: etiket-ceremonien (etiket_ceremoni.sql) ende-til-ende på en syntetisk mini-kilde
# (fixtures/etiket-ceremoni.sql) med de rigtige filer sidekort_1939.json og linjeetiketter_6e2.json, kaldt med
# -v-variabler som runneren gør. Forventningerne tages med maal_trin6e2.sql (fase ddl) som i runbooken.
# Brug: bash tests/sql/test-etiket-ceremoni.sh <basenavn>
#   Opretter <basenavn> og <basenavn>_{go,neg,fremmed,stale,politik}. Ved succes droppes præcis de seks; ved fejl står de
#   tilbage til fejlsøgning.
set -euo pipefail
db=${1:?database}
S=.claude/skills/daa-extract/scripts
F=tests/sql/fixtures
SK=$S/sidekort_1939.json; ET=$S/linjeetiketter_6e2.json
tmp=$(mktemp -d "${TMPDIR:-/tmp}/${db}.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 "$@"; }
v() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
anon() { env -u PGOPTIONS psql -X -q -At -v ON_ERROR_STOP=1 -d "$1" -c 'SET ROLE anon' -c "$2"; }
fail() { echo "ETIKET_CEREMONI_TEST_FAILED: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
# jvar <ind> <ud> <python-sætning over d>: en variant af en JSON-fil.
jvar() { python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); exec(sys.argv[3])
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=1)+"\n")' "$1" "$2" "$3"; }

createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do
  q -d "$db" -f "$f" >/dev/null 2>&1 || fail "opsætning: $f"; done
q -d "$db" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' >/dev/null 2>&1 \
  || fail "opsætning: tests/sql/reimport-writer-v2-bootstrap.sql"
q -d "$db" -f db-rls.sql >/dev/null 2>&1 || fail "opsætning: db-rls.sql (anden gang)"
(cd $F && q -d "$db" -f etiket-ceremoni.sql >/dev/null 2>&1) || fail "opsætning: fixtures/etiket-ceremoni.sql"
[ "$(v "$db" "SELECT public.narrative_record_contract_version()")" = "2" ] || fail "kontrakt v2"

maal() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -v src=-6920 -d "$1" -f $S/maal_trin6e2.sql; }
felt() { maal "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
M0=$(maal "$db")
f0() { echo "$M0" | tr ' ' '\n' | sed -n "s/^$1=//p"; }
[ "$(f0 fase)" = "ddl" ] || fail "fase før: $M0"
[ "$(f0 BINDINGER_RECORD)" = "4" ] && [ "$(f0 SPRUNGET)" = "1" ] && [ "$(f0 UDEN_PLACEMENT)" = "1" ] && [ "$(f0 STALE)" = "0" ] || fail "fixture: $M0"
KA=$(f0 KOORD_ANDRE); EA=$(f0 ETIKETTER_ANDRE)
[ "$KA" != d41d8cd98f00b204e9800998ecf8427e ] && [ "$EA" != d41d8cd98f00b204e9800998ecf8427e ] || fail "andre kilder tomme: $M0"
for c in go neg fremmed; do createdb -T "$db" "${db}_$c"; done

# run <base> <mærke>: ceremonien med standardforventningerne; overstyr med E_*=… / SKF= / ETF= / *SHA= / ACTOR= foran.
run() {
  local skf=${SKF:-$SK} etf=${ETF:-$ET}
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v actor="${ACTOR:-a6e20000-0000-0000-0000-0000000006e2}" \
    -v src=-6920 -v go=deadbeef \
    -v sidekort_path="$skf" -v sidekort_sha="${SKSHA:-$(sha "$skf")}" \
    -v etiketter_path="$etf" -v etiketter_sha="${ETSHA:-$(sha "$etf")}" \
    -v expect_bindinger="${E_BIND:-4}" -v expect_sprunget="${E_SPR:-1}" -v expect_tomme="${E_TOM:-1}" -v expect_entries="${E_ENT:-5}" \
    -v expect_koord_andre="${E_KA:-$KA}" -v expect_etiketter_andre="${E_EA:-$EA}" \
    -v expect_bio_offentlige="${E_BIO:-$(f0 BIO_OFFENTLIGE)}" -v expect_fakta_bundne="${E_FAKTA:-$(f0 FAKTA_BUNDNE)}" \
    -f $S/etiket_ceremoni.sql > "$tmp/$2.out" 2>&1
}
kode() { grep -o 'ETK_[A-Z_0-9]*' "$tmp/$1.out" | grep -v '^ETK_OK$\|^ETK_LINJE$' | head -1; }
ok() { run "$@" || fail "$2: $(kode "$2") $(grep -m1 -E 'ERROR|FEJL' "$tmp/$2.out" || true)"; }
# Intet skrevet: fasen er ddl, og kildens og modpartens etiketter og linjenavne er som før.
etiketter() { v "$1" "SELECT string_agg(sr.record_key||'='||b.record_label||'|'||b.citation_label,';' ORDER BY sr.record_key)
  FROM private.narrative_record_publication b JOIN private.source_record sr ON sr.id=b.source_record_id"; }
E0=$(etiketter "$db"); SKEMA0=$(f0 SKEMA_ETIKETTER)
urort() { [ "$(felt "$1" fase)" = "ddl" ] && [ "$(etiketter "$1")" = "$E0" ] && [ "$(felt "$1" SKEMA_ETIKETTER)" = "$SKEMA0" ]; }
nej() {  # nej <base> <mærke> <kode>: ceremonien stopper med koden og skriver intet
  local b=$1 t=$2 c=$3
  if run "$b" "$t"; then fail "$t: godtaget, forventede $c"; fi
  grep -q "$c" "$tmp/$t.out" || fail "$t: forventede $c, fik $(kode "$t") $(grep -m1 ERROR "$tmp/$t.out" || true)"
  urort "$b" || fail "$t: negativen skrev"
}
events() { v "$1" "SELECT count(*) FROM private.narrative_publication_event"; }

# $fuld$: sidekort, 5 linjenavne, 4 bindinger med læsbare etiketter, 4 revalideret, 0 stale; andre kilder uændrede.
ok "${db}_go" go
K=record-6e200000-0000-0000-0000-00000000000
grep -qx "ETK_OK bindinger=4 tomme=1 entries=5 revalideret=4 sprunget=1 stale=0 koord_andre=$KA etiketter_andre=$EA" "$tmp/go.out" \
  || fail "kvittering: $(grep ETK_OK "$tmp/go.out" || tail -3 "$tmp/go.out")"
[ "$(grep -c '^ETK_LINJE code=' "$tmp/go.out")" = "5" ] || fail "ETK_LINJE-linjer: $(grep -c ETK_LINJE "$tmp/go.out")"
grep -qx 'ETK_LINJE code=Stamme-holstenske foer=Den holstenske Linje. efter=A. Den holstenske Linje.' "$tmp/go.out" \
  || fail "ETK_LINJE for stammeafsnit A"
[ "$(etiketter "${db}_go")" = "${K}1=IV, nr. 3|DAA T, s. 49;${K}2=|DAA T, s. 52;${K}3=A, nr. 2|DAA T, s. 2;${K}4=III|DAA T, s. 66;${K}5=${K}5|DAA T side 543;V-1=V-1|DAA M, s. 45" ] \
  || fail "etiketter: $(etiketter "${db}_go")"
[ "$(v "${db}_go" "SELECT sidekort::text FROM public.source WHERE id=-6920")" = "$(v "${db}_go" "SELECT '$(cat $SK)'::jsonb::text")" ] \
  || fail "sidekort"
[ "$(v "${db}_go" "SELECT string_agg(e.code||'='||e.label,';' ORDER BY e.sort_order) FROM public.lineage_scheme s
       JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id WHERE s.source_id=-6920")" \
  = "Stamme-holstenske=A. Den holstenske Linje.;Stamme-ældre-meklenborgske=B. Den ældre meklenborgske Linje.;I=I. Den holstenske Linje.;II=II. Linjen Gallentin.;III=III. Den ældre meklenborgske Linje af Ziesendorf.;IV=IV. Den danske grevelige Linje af 1673.;V=V. Den grevelige Linje af 1767.;VI=VI. Den fyenske Linje." ] \
  || fail "linjeskema"
# Én ny revalidated-hændelse pr. binding i kilden, ingen i modparten.
[ "$(v "${db}_go" "SELECT string_agg(e.source_id||':'||e.event_type||':'||count,',' ORDER BY e.source_id,e.event_type) FROM (
       SELECT source_id,event_type,count(*) FROM private.narrative_publication_event GROUP BY 1,2) e")" \
  = "$(v "$db" "SELECT string_agg(e.source_id||':'||e.event_type||':'||(count+CASE WHEN e.source_id=-6920 AND e.event_type='revalidated' THEN 4 ELSE 0 END),',' ORDER BY e.source_id,e.event_type) FROM (
       SELECT source_id,event_type,count(*) FROM private.narrative_publication_event GROUP BY 1,2) e")" ] || fail "hændelser"
MG=$(maal "${db}_go"); fg() { echo "$MG" | tr ' ' '\n' | sed -n "s/^$1=//p"; }
[ "$(fg fase)" = "data" ] && [ "$(fg BINDINGER_RECORD)" = "0" ] && [ "$(fg SPRUNGET)" = "1" ] && [ "$(fg UDEN_PLACEMENT)" = "0" ] && [ "$(fg STALE)" = "0" ] \
  || fail "maal efter: $MG"
for x in KOORD_ANDRE ETIKETTER_ANDRE BIO_OFFENTLIGE FAKTA_BUNDNE; do [ "$(fg $x)" = "$(f0 $x)" ] || fail "maal $x ændret"; done
[ "$(fg SKEMA_ETIKETTER)" != "$SKEMA0" ] || fail "SKEMA_ETIKETTER uændret"
# Den tomme postdel og den trykte side når læseren (biografien som anon).
[ "$(anon "${db}_go" "SELECT record_label||'|'||citation_label FROM public.public_person_bio_source_versions_v2(ARRAY[-692002::bigint])")" \
  = "|DAA T, s. 52" ] || fail "læser: tom postdel"

# $genkoersel$: ETK_PRE_FASE uden skrivning.
ev=$(events "${db}_go")
if run "${db}_go" genk; then fail "genkørsel godtaget"; fi
grep -q 'ETK_PRE_FASE' "$tmp/genk.out" || fail "genkørsel: forventede ETK_PRE_FASE, fik $(kode genk)"
[ "$(events "${db}_go")" = "$ev" ] || fail "genkørsel skrev hændelser"

# $fremmed_kilde$: en ændring i modparten under ceremonien (trigger på linjeskemaet) → ETK_POST_ANDRE, intet skrevet.
q -d "${db}_fremmed" >/dev/null <<'SQL' || fail "fremmed: trigger"
CREATE FUNCTION public.t6e2_fremmed() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE private.narrative_record_publication b SET citation_label=b.citation_label||' (ændret)'
    FROM private.source_record sr WHERE sr.id=b.source_record_id AND sr.source_id=-6921;
  RETURN NULL;
END $$;
CREATE TRIGGER t6e2_fremmed AFTER UPDATE ON public.lineage_scheme_entry FOR EACH STATEMENT EXECUTE FUNCTION public.t6e2_fremmed();
SQL
nej "${db}_fremmed" fremmed ETK_POST_ANDRE
grep -q 'ETK_POST_ANDRE etiketter' "$tmp/fremmed.out" || fail "fremmed: forventede etiketter, fik $(grep -m1 ERROR "$tmp/fremmed.out")"
# … og en ændring af andre kilders koordinater før kørslen (forventningen er fase foer's hash).
v "${db}_fremmed" "DROP TRIGGER t6e2_fremmed ON public.lineage_scheme_entry" >/dev/null
v "${db}_fremmed" "UPDATE public.person_external_id SET nr=7 WHERE person_id=-692101 AND source_id=-6921" >/dev/null
nej "${db}_fremmed" fremmed2 'ETK_POST_ANDRE koord'

# $forkert_etiket_foer$: en label_foer, som ikke står i linjeskemaet (linje I's uden punktum) → ETK_PRE_ETIKET.
jvar "$ET" "$tmp/et-foer.json" 'd[1]["label_foer"]=d[1]["label_foer"].rstrip(".")'
ETF="$tmp/et-foer.json" nej "${db}_neg" etiket ETK_PRE_ETIKET
# $sha$: ændret sidekortfil mod den bundne sha → ETK_PRE_SHA; ditto etiketfilen.
jvar "$SK" "$tmp/sk-aendret.json" 'd[0]["trykt_fra"]=2'
SKF="$tmp/sk-aendret.json" SKSHA="$(sha "$SK")" nej "${db}_neg" sha ETK_PRE_SHA
ETF="$tmp/et-foer.json" ETSHA="$(sha "$ET")" nej "${db}_neg" sha2 ETK_PRE_SHA
# Øvrige PRE-negativer: forventet antal, rolle, ugyldigt sidekort, etiketfilens form, tvetydig placement, stale.
E_BIND=5 nej "${db}_neg" bind ETK_PRE_BINDINGER
E_SPR=0 nej "${db}_neg" spr ETK_PRE_BINDINGER
ACTOR=00000000-0000-0000-0000-000000000001 nej "${db}_neg" rolle ETK_PRE_ROLE
jvar "$SK" "$tmp/sk-overlap.json" 'd[1]["pdf_fra"]=500'
SKF="$tmp/sk-overlap.json" nej "${db}_neg" sidekort ETK_PRE_SIDEKORT
jvar "$ET" "$tmp/et-dublet.json" 'd[1]["code"]=d[0]["code"]'
ETF="$tmp/et-dublet.json" nej "${db}_neg" fil ETK_PRE_FIL
E_ENT=4 nej "${db}_neg" ent ETK_PRE_FIL
# POST-negativer (rulles tilbage): forkert antal tomme, forkerte læsertal.
E_TOM=2 nej "${db}_neg" tom ETK_POST_TOMME
E_BIO=999 nej "${db}_neg" bio 'ETK_POST_LAESER bio'
# $sprunget_roert$: den oversprungne (staged) binding ændres under ceremonien (trigger på linjeskemaet) → ETK_POST_SPRUNGET.
q -d "${db}_neg" >/dev/null <<SQL || fail "sprunget: trigger"
CREATE FUNCTION public.t6e2_sprunget() RETURNS trigger LANGUAGE plpgsql AS \$f\$
BEGIN
  UPDATE private.narrative_record_publication b SET citation_label='DAA T side 544'
    FROM private.source_record sr WHERE sr.id=b.source_record_id AND sr.record_key='${K}5';
  RETURN NULL;
END \$f\$;
CREATE TRIGGER t6e2_sprunget AFTER UPDATE ON public.lineage_scheme_entry FOR EACH STATEMENT EXECUTE FUNCTION public.t6e2_sprunget();
SQL
nej "${db}_neg" sprunget ETK_POST_SPRUNGET
v "${db}_neg" "DROP TRIGGER t6e2_sprunget ON public.lineage_scheme_entry" >/dev/null
# Stale før kørslen → ETK_PRE_STALE (en binding ændret uden revalidering), og tvetydig placement → ETK_PRE_TVETYDIG.
createdb -T "$db" "${db}_stale"
v "${db}_stale" "UPDATE private.narrative_record_publication b SET citation_label='DAA T side 999' FROM private.source_record sr
  WHERE sr.id=b.source_record_id AND sr.record_key='${K}1'" >/dev/null
if run "${db}_stale" stale; then fail "stale godtaget"; fi
grep -q ETK_PRE_STALE "$tmp/stale.out" || fail "stale: fik $(kode stale)"
q -d "${db}_stale" >/dev/null <<SQL || fail "tvetydig: opsætning"
UPDATE private.narrative_record_publication b SET citation_label='DAA T side 538' FROM private.source_record sr
  WHERE sr.id=b.source_record_id AND sr.record_key='${K}1';
SET session_replication_role=replica;
INSERT INTO private.source_record_placement(id,source_record_id,scheme_entry_id,header_observation_id,initial_status,printed_number)
SELECT gen_random_uuid(),p.source_record_id,(SELECT e.id FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
  WHERE s.source_id=-6920 AND e.code='II'),p.header_observation_id,'accepted','9'
  FROM private.source_record_placement p JOIN private.source_record sr ON sr.id=p.source_record_id WHERE sr.record_key='${K}1';
INSERT INTO private.source_record_placement_decision(placement_id,version,decision_status,evidence,decision_origin,decided_by_name)
SELECT p.id,1,'accepted','{"fixture":"6e2 tvetydig"}','migration','fixture' FROM private.source_record_placement p
  JOIN private.source_record sr ON sr.id=p.source_record_id WHERE sr.record_key='${K}1' AND p.printed_number='9';
SQL
# Den ekstra placement ændrer proveniensen; revalidér som redaktør, så kun tvetydigheden står tilbage.
q -d "${db}_stale" >/dev/null <<SQL || fail "tvetydig: revalidering"
BEGIN;
SELECT set_config('request.jwt.claim.sub','a6e20000-0000-0000-0000-0000000006e2',true) \\g /dev/null
SELECT private.narrative_record_state(-692001,-6920,'${K}1')->>'state_sha256' AS h \\gset
SET LOCAL ROLE authenticated;
SELECT public.red_revalider_person_narrative_record(-692001,-6920,'${K}1',:'h') \\g /dev/null
COMMIT;
SQL
if run "${db}_stale" tvetydig; then fail "tvetydig godtaget"; fi
grep -q ETK_PRE_TVETYDIG "$tmp/tvetydig.out" || fail "tvetydig: fik $(kode tvetydig)"

# $politik$: en offentlig person med en privat, publiceret og ikke-forældet biografi kan ikke revalideres (6d-1's
# kriterium) → ETK_PRE_POLITIK før skrivning. Hændelsen, der matcher den private tilstand, indsættes direkte (replica).
# (Den staged r5 springes over og tæller ikke her.)
createdb -T "$db" "${db}_politik"
q -d "${db}_politik" >/dev/null <<SQL || fail "politik: opsætning"
BEGIN;
UPDATE public.narrative n SET privat=true FROM private.narrative_record_publication b JOIN private.source_record sr
  ON sr.id=b.source_record_id WHERE n.id=b.narrative_id AND sr.record_key='${K}2';
CREATE TEMP TABLE s AS SELECT private.narrative_record_state(-692002,-6920,'${K}2') AS st;
SET LOCAL session_replication_role=replica;
INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
  source_id,source_record_id,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,decided_by_name)
SELECT e.change_set_id,e.stream_ref,e.stream_version+1,'revalidated',e.binding_id,e.narrative_id,e.source_id,e.source_record_id,
       'fixture: staged baseline',e.after_state,s.st->'publication_state',e.after_state_sha256,s.st->>'publication_state_sha256',
       e.decided_by,'fixture'
  FROM private.narrative_publication_event e, s
 WHERE e.binding_id=(SELECT b.id FROM private.narrative_record_publication b JOIN private.source_record sr ON sr.id=b.source_record_id
                      WHERE sr.record_key='${K}2')
 ORDER BY e.stream_version DESC LIMIT 1;
COMMIT;
SQL
[ "$(v "${db}_politik" "SELECT private.narrative_record_state(-692002,-6920,'${K}2')->>'publication_status'")" = "published" ] \
  || fail "politik: fixturen er ikke published"
if run "${db}_politik" politik; then fail "politik godtaget"; fi
grep -q 'ETK_PRE_POLITIK n=1' "$tmp/politik.out" || fail "politik: fik $(kode politik) $(grep -m1 ERROR "$tmp/politik.out" || true)"
[ "$(felt "${db}_politik" fase)" = "ddl" ] || fail "politik: negativen skrev"

for c in go neg fremmed stale politik; do dropdb --if-exists "${db}_$c"; done
dropdb --if-exists "$db"
echo ETIKET_CEREMONI_TEST_OK
