#!/usr/bin/env bash
# Trin 6d-1 Task 7: placement-ceremonien (placement_ceremoni.sql) ende-til-ende på en syntetisk mini-kilde
# (fixtures/ceremoni-6d1.sql + manifest-6d1.json, mapping-6d1.json, approvals-6d1.json), kaldt med -v-variabler som
# runneren gør. Kilden -1610 har to grene (I, II), fire records (p1-p3 publiceret, p4 unresolved), en eksisterende
# entry VI og en modpart (-161101) i kilden -1611. Koordinat-baselinen tages med maal_trin6d1.sql som i runbooken.
# Brug: bash tests/sql/test-placement-ceremoni.sh <basenavn>   (opretter <basenavn> og <basenavn>_<scenarie>)
set -euo pipefail
db=${1:?database}
S=.claude/skills/daa-extract/scripts
F=tests/sql/fixtures
tmp=$(mktemp -d "/tmp/${db}.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 "$@"; }
v() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "PLACEMENT_CEREMONI_TEST_FAILED: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
jget() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1],encoding="utf-8"))[sys.argv[2]])' "$1" "$2"; }
# jvar <ind> <ud> <python-sætning over d>: en variant af en JSON-fixture.
jvar() { python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); exec(sys.argv[3])
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False,indent=1)+"\n")' "$1" "$2" "$3"; }
# appr <manifest> <ud> <godkendelser som JSON-liste> [gruppekort som JSON-liste]  (godkendelseskontrakt v2)
appr() { python3 -I -c 'import json,sys
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps({"manifest_sha256":sys.argv[1],"approvals":json.loads(sys.argv[3]),
  "gruppekort":json.loads(sys.argv[4])})+"\n")' "$(sha "$1")" "$2" "$3" "${4:-[]}"; }

createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do
  q -d "$db" -f "$f" >/dev/null 2>&1 || fail "opsætning: $f"; done
q -d "$db" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' >/dev/null 2>&1 \
  || fail "opsætning: tests/sql/reimport-writer-v2-bootstrap.sql"
q -d "$db" -f db-rls.sql >/dev/null 2>&1 || fail "opsætning: db-rls.sql (anden gang)"
(cd $F && q -d "$db" -f ceremoni-6d1.sql >/dev/null 2>&1) || fail "opsætning: fixtures/ceremoni-6d1.sql"
[ "$(v "$db" "SELECT public.narrative_record_contract_version()")" = "2" ] || fail "kontrakt v2"

M=$F/manifest-6d1.json; MP=$F/mapping-6d1.json; AP=$F/approvals-6d1.json
[ "$(jget "$AP" manifest_sha256)" = "$(sha "$M")" ] || fail "approvals-6d1.json hører ikke til manifest-6d1.json"
appr "$M" "$tmp/ingen.json" '[]'

maal() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -v src=-1610 -d "$1" -f $S/maal_trin6d1.sql; }
felt() { maal "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }
KOORD=$(felt "$db" KOORD_2018_20)
KSRC=$(felt "$db" KOORD_SRC)
[ "$(felt "$db" fase)" = "ddl" ] || fail "fase før: $(maal "$db")"
[[ "$KOORD" =~ ^[0-9a-f]{32}$ ]] || fail "KOORD_2018_20: $KOORD"

# run <base> <mærke>: ceremonien med standardforventningerne (fuld kørsel); overstyr med E_*=… / MF= / MP= / AP= foran.
run() {
  local mf=${MF:-$M} mp=${MPF:-$MP} ap=${AP_:-$tmp/ingen.json}
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "${CONN:-$1}" -v actor=a6d10000-0000-0000-0000-0000000006d1 -v src=-1610 \
    -v manifest_path="$mf" -v manifest_sha="${MSHA:-$(sha "$mf")}" \
    -v mapping_path="$mp" -v mapping_sha="$(jget "$mp" sheet_sha256)" -v mapping_token_sha="${TSHA:-$(jget "$mp" token_sha256)}" \
    -v mapping_file_sha="${MFSHA:-$(sha "$mp")}" -v approvals_file_sha="${AFSHA:-$(sha "$ap")}" \
    -v approvals_path="$ap" -v approvals_sha="$(sha "$ap")" -v go=deadbeef \
    -v rendition_sha="${RSHA:-$(printf '2%.0s' {1..64})}" \
    -v header_rule_version="${RULE:-header-test-6d1-v1}" \
    -v expect_headers=6 -v expect_human_levels="${E_HUM:-0}" -v expect_entries="${E_ENT:-3}" -v expect_placements="${E_PL:-3}" \
    -v expect_persona_placements="${E_PP:-3}" -v expect_bindings="${E_BIND:-3}" -v expect_published=3 \
    -v expect_revalidated="${E_REVAL:-3}" -v expect_ledger_mapped="${E_MAP:-3}" -v expect_ledger_retained="${E_RET:-1}" \
    -v expect_memberships="${E_MEM:-3}" -v expect_corroborated=1 -v expect_conflict=0 \
    -v expect_laeser_1939="${E_LAES:-uaendret}" -v expect_koord_2018_20="${E_KOORD:-$KOORD}" \
    -f $S/placement_ceremoni.sql > "$tmp/$2.out" 2>&1
}
kode() { grep -o 'PLC_[A-Z_0-9]*' "$tmp/$1.out" | head -1; }
ok() { run "$@" || fail "$2: $(kode "$2") $(grep -m1 -E 'ERROR|FEJL' "$tmp/$2.out" || true)"; }
nej() {  # nej <base> <mærke> <kode>: ceremonien stopper med koden og skriver intet
  local b=$1 t=$2 c=$3; shift 3
  if run "$b" "$t"; then fail "$t: godtaget, forventede $c"; fi
  grep -q "$c" "$tmp/$t.out" || fail "$t: forventede $c, fik $(kode "$t") $(grep -m1 ERROR "$tmp/$t.out" || true)"
  [ "$(felt "$b" fase)" = "ddl" ] || fail "$t: negativen skrev"
}
ledger() { v "$1" "SELECT string_agg(disposition||':'||coalesce(evidence->>'grund',''),',' ORDER BY person_id)
  FROM private.legacy_placement_disposition_current WHERE source_id=-1610 AND is_current"; }
pub() { v "$1" "SELECT count(*) FILTER (WHERE s->>'publication_status'='published')||'/'||count(*) FILTER (WHERE s->>'publication_status'='stale_published')
  FROM private.narrative_record_publication b JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=-1610
  JOIN public.narrative n ON n.id=b.narrative_id, LATERAL private.narrative_record_state(n.subjekt_id,sr.source_id,sr.record_key) s"; }
# Ændr identiteten for recordens hovedperson-persona (ny version, som en redaktørafgørelse).
ident() {  # ident <base> <record_key> <status> <person|NULL>
  q -d "$1" >/dev/null <<SQL
BEGIN;
INSERT INTO public.person(id) SELECT $4 WHERE $4 IS NOT NULL ON CONFLICT DO NOTHING;
CREATE TEMP TABLE p ON COMMIT DROP AS SELECT spm.persona_id, i.version FROM private.source_record sr
  JOIN private.source_record_anchor_current ac ON ac.source_record_id=sr.id
  JOIN private.source_observation o ON o.occurrence_id=ac.occurrence_id AND o.parent_observation_id IS NULL
  JOIN private.source_mention sm ON sm.observation_id=o.id
  JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
  JOIN private.source_persona_identity i ON i.source_persona_id=spm.persona_id
 WHERE sr.source_id=-1610 AND sr.record_key='$2';
INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
  decided_by,decided_by_name,decided_at)
SELECT persona_id,$4,'$3',version+1,'{"fixture":"ident"}','a6d10000-0000-0000-0000-0000000006d1','fixture','2026-11-09' FROM p;
UPDATE private.source_persona_identity i SET canonical_person_id=$4,decision_status='$3',version=p.version+1,
  evidence='{"fixture":"ident"}',decided_by='a6d10000-0000-0000-0000-0000000006d1',decided_by_name='fixture',decided_at='2026-11-09'
  FROM p WHERE p.persona_id=i.source_persona_id;
COMMIT;
SQL
}
for c in go neg ident unres appr same overlap park udenpost parit fortsat stale gruppe blandet struktur usikker; do createdb -T "$db" "${db}_$c"; done
events_p2() { v "$1" "SELECT count(*) FROM private.narrative_publication_event e JOIN private.narrative_record_publication b ON b.id=e.binding_id
  JOIN private.source_record sr ON sr.id=b.source_record_id WHERE sr.source_id=-1610 AND sr.record_key='p2'"; }
ev0=$(events_p2 "$db")

# $fuld_koersel$: linjeskema, overskrifter, 3 placements, ledger 3 mapped + 1 retained, 3 medlemskaber (1 corroborated),
# 3 revalideret, 0 stale; 2018-20-koordinaterne og kildens egne læserrækker (gaten: I/1 to gange) uændrede.
ok "${db}_go" go
grep -q '^PLC_OK entries=3 headers=6 placements=3 persona=3 ledger_mapped=3 memberships=3 revalideret=3 corroborated=1 conflict=0 human_levels=0$' \
  "$tmp/go.out" || fail "kvittering: $(grep PLC_OK "$tmp/go.out" || tail -3 "$tmp/go.out")"
[ "$(pub "${db}_go")" = "3/0" ] || fail "publicering efter: $(pub "${db}_go")"
[ "$(ledger "${db}_go")" = "retained_legacy:ingen_placement,mapped:,mapped:,mapped:" ] || fail "ledger: $(ledger "${db}_go")"
[ "$(felt "${db}_go" fase)" = "data" ] || fail "fase efter: $(maal "${db}_go")"
[ "$(felt "${db}_go" KOORD_2018_20)" = "$KOORD" ] || fail "2018-20-koordinater ændret"
[ "$(felt "${db}_go" KOORD_SRC)" = "$KSRC" ] || fail "kildens læserrækker ændret"
[ "$(v "${db}_go" "SELECT string_agg(e.code||':'||e.sort_order||':'||(SELECT string_agg(l.kode||'/'||el.relation_kind,'+' ORDER BY el.relation_kind)
       FROM public.lineage_scheme_entry_lineage el JOIN public.lineage l ON l.id=el.lineage_id WHERE el.entry_id=e.id),',' ORDER BY e.code)
       FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id WHERE s.source_id=-1610")" \
  = "I:1:I/canonical+II/historical_alias,II:2:II/canonical,VI:3:VI/canonical" ] || fail "linjeskema (VI flyttet 1→3)"
[ "$(v "${db}_go" "SELECT state FROM private.membership_component_states() WHERE -161001=ANY(members)")" = "corroborated" ] \
  || fail "komponent"
# $binding_via_record$: p2's legacy-nøgle er x-2, men bindingen revalideres via recorden.
[ "$(v "${db}_go" "SELECT record_key FROM public.person_external_id WHERE person_id=-161002")" = "x-2" ] || fail "fixture x-2"
[ "$(events_p2 "${db}_go")" -gt "$ev0" ] || fail "p2 ikke revalideret"

# Genkørsel → PLC_PRE_FASE.
if run "${db}_go" genk; then fail "genkørsel godtaget"; fi
grep -q 'PLC_PRE_FASE' "$tmp/genk.out" || fail "forventede PLC_PRE_FASE: $(kode genk)"

# $fortryd_en_post$: membership-reversal → placements superseded → revalidering → ledger; ender published, 0 stale.
q -d "${db}_go" >/dev/null <<'SQL' || fail "fortrydelse"
BEGIN;
SELECT set_config('request.jwt.claim.sub','a6d10000-0000-0000-0000-0000000006d1',true);
CREATE TEMP TABLE f ON COMMIT DROP AS
SELECT pp.id AS pp, rp.id AS rp, l.lineage_id
  FROM private.source_record r JOIN private.source_record_placement rp ON rp.source_record_id=r.id
  JOIN private.source_persona_placement pp ON pp.record_placement_id=rp.id
  JOIN public.person_lineage_membership l ON l.person_id=-161002
 WHERE r.source_id=-1610 AND r.record_key='p2';
GRANT SELECT ON f TO authenticated;
SET LOCAL ROLE authenticated;
SELECT public.red_reverse_placement_membership(-161002,(SELECT lineage_id FROM f),'fortryd p2 (test)');
SELECT set_config('app.change_set_id','',true);
SELECT public.red_decide_source_persona_placement((SELECT pp FROM f),1,'superseded','{"basis":"fortryd"}');
SELECT public.red_decide_source_record_placement((SELECT rp FROM f),1,'superseded','{"basis":"fortryd"}');
SELECT set_config('app.change_set_id','',true);
RESET ROLE;
SELECT private.narrative_record_state(-161002,-1610,'p2')->>'state_sha256' AS h \gset
SET LOCAL ROLE authenticated;
SELECT public.red_revalider_person_narrative_record(-161002,-1610,'p2',:'h');
SELECT set_config('app.change_set_id','',true);
RESET ROLE;
SELECT private.record_legacy_disposition(-161002,-1610,'retained_legacy',NULL,'{"grund":"fortrudt","basis":"fortryd"}');
DO $c$ BEGIN
  IF (SELECT private.narrative_record_state(-161002,-1610,'p2')->>'publication_status')<>'published'
     OR EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE person_id=-161002)
     OR private.placement_membership_not_current()<>0
     OR (SELECT disposition FROM private.legacy_placement_disposition_current WHERE person_id=-161002)<>'retained_legacy'
     OR NOT (SELECT is_current FROM private.legacy_placement_disposition_current WHERE person_id=-161002) THEN
    RAISE EXCEPTION 'FORTRYD_FAILED'; END IF;
END $c$;
COMMIT;
SQL
[ "$(pub "${db}_go")" = "3/0" ] || fail "publicering efter fortrydelse: $(pub "${db}_go")"

# Inputnegativer på én base (en afvist kørsel ruller alt tilbage).
N=${db}_neg
jvar "$MP" "$tmp/mp-uden-ii.json" 'd["entries"]=[e for e in d["entries"] if e["code"]!="II"]'
MPF="$tmp/mp-uden-ii.json" nej "$N" mp1 PLC_PRE_MAPPING
jvar "$MP" "$tmp/mp-vi.json" 'd["entries"][2]["canonical"]={"source_id":-1611,"kode":"I"}'
MPF="$tmp/mp-vi.json" nej "$N" mp2 PLC_PRE_MAPPING
jvar "$MP" "$tmp/mp-label.json" 'd["entries"][0]["label_sha256"]="0"*64'
MPF="$tmp/mp-label.json" nej "$N" mp3 PLC_PRE_MAPPING
jvar "$MP" "$tmp/mp-sort.json" 'd["entries"][1]["sort_order"]=3'
MPF="$tmp/mp-sort.json" nej "$N" mp4 'PLC_PRE_MAPPING label/sort_order'
jvar "$MP" "$tmp/mp-uden-vi.json" 'd["entries"]=[e for e in d["entries"] if e["code"]!="VI"]'
MPF="$tmp/mp-uden-vi.json" E_ENT=3 nej "$N" mp6 'PLC_PRE_MAPPING eksisterende mangler'
jvar "$MP" "$tmp/mp-negsort.json" 'd["entries"][2]["sort_order"]=-1'
MPF="$tmp/mp-negsort.json" nej "$N" mp7 'PLC_PRE_MAPPING label/sort_order'
MFSHA=$(printf x | shasum -a 256 | cut -c1-64) nej "$N" fil1 PLC_PRE_MAPPING_FIL
AFSHA=$(printf x | shasum -a 256 | cut -c1-64) nej "$N" fil2 PLC_PRE_APPROVALS_FIL
RSHA=$(printf '3%.0s' {1..64}) nej "$N" rend PLC_PRE_RENDITION
CONN="dbname=$N options=-capp.change_set_id=5" nej "$N" guc PLC_PRE_GUC
jvar "$MP" "$tmp/mp-alias.json" 'd["entries"][0]["aliases"]=[{"source_id":-1611,"kode":"XX"}]'
MPF="$tmp/mp-alias.json" nej "$N" mp5 PLC_PRE_MAPPING
appr "$M" "$tmp/a-nr.json" '[{"record_key":"p4","printed_number":"9"}]'
AP_="$tmp/a-nr.json" nej "$N" ap1 PLC_PRE_APPROVALS
python3 -I -c 'import json,sys; open(sys.argv[1],"w").write(json.dumps({"manifest_sha256":"0"*64,"approvals":[]})+"\n")' "$tmp/a-andet.json"
AP_="$tmp/a-andet.json" nej "$N" ap2 PLC_PRE_APPROVALS
appr "$M" "$tmp/a-p1.json" '[{"record_key":"p1"}]'
AP_="$tmp/a-p1.json" nej "$N" ap3 PLC_PRE_APPROVALS
jvar "$M" "$tmp/m-flere.json" 'd["placements"][3]["reasons"]=["flere_personas_i_post"]'
appr "$tmp/m-flere.json" "$tmp/a-flere.json" '[{"record_key":"p4"}]'
MF="$tmp/m-flere.json" AP_="$tmp/a-flere.json" nej "$N" ap4 PLC_PRE_APPROVALS
MSHA=$(printf x | shasum -a 256 | cut -c1-64) nej "$N" sha1 PLC_PRE_SHA
TSHA=$(printf x | shasum -a 256 | cut -c1-64) nej "$N" sha2 PLC_PRE_SHA
jvar "$M" "$tmp/m-inv.json" 'd["invariants"]["segmenter_paritet"]=False'
appr "$tmp/m-inv.json" "$tmp/a-inv.json" '[]'
MF="$tmp/m-inv.json" AP_="$tmp/a-inv.json" nej "$N" inv1 PLC_PRE_INVARIANTS
RULE=header-anden-v1 nej "$N" inv2 PLC_PRE_INVARIANTS
E_PL=4 nej "$N" ant1 PLC_PRE_PLACEMENTS
E_RET=2 nej "$N" ant2 PLC_PRE_LEDGER
E_KOORD=$(printf '0%.0s' {1..32}) nej "$N" koord PLC_POST_KOORD
E_LAES=placement nej "$N" laes1 PLC_POST_LAESER
E_LAES=ukendt nej "$N" laes2 PLC_PRE_ARGS

# Identitet ≠ binding (p2 peger nu på en anden person) → PLC_PRE_IDENTITY uden skrivning.
ident "${db}_ident" p2 accepted -161099
nej "${db}_ident" ident PLC_PRE_IDENTITY

# Persona med unresolved identitet (p2): record-placement, ingen persona-placement, binding stadig published; ledger
# ingen_identitet. Uden p2's medlemskab er kildens placements entydige → læseren viser placement for -161001/-161003.
ident "${db}_unres" p2 unresolved NULL
E_PP=2 E_BIND=2 E_MAP=2 E_RET=2 E_MEM=2 nej "${db}_unres" unres1 PLC_POST_LAESER
E_PP=2 E_BIND=2 E_MAP=2 E_RET=2 E_MEM=2 E_LAES=placement ok "${db}_unres" unres2
[ "$(pub "${db}_unres")" = "3/0" ] || fail "unres: publicering"
[ "$(ledger "${db}_unres")" = "retained_legacy:ingen_placement,mapped:,retained_legacy:ingen_identitet,mapped:" ] \
  || fail "unres: ledger $(ledger "${db}_unres")"
[ "$(v "${db}_unres" "SELECT count(rp.id)||'/'||count(pp.id) FROM private.source_record r JOIN private.source_record_placement rp ON rp.source_record_id=r.id
       LEFT JOIN private.source_persona_placement pp ON pp.record_placement_id=rp.id WHERE r.source_id=-1610 AND r.record_key='p2'")" = "1/0" ] \
  || fail "unres: p2 placements"
[ "$(v "${db}_unres" "SELECT string_agg(person_id||':'||provenance_kind,',' ORDER BY person_id) FROM public.public_person_source_coordinates() WHERE source_id=-1610")" \
  = "-161004:legacy_external_id,-161003:placement,-161002:legacy_external_id,-161001:placement" ] || fail "unres: læser"

# Godkendt kort (p4, nr_ikke_fortloebende): fire placements, basis human_group_review.
AP_=$AP E_PL=4 E_PP=4 E_MAP=4 E_RET=0 E_MEM=4 ok "${db}_appr" appr
[ "$(v "${db}_appr" "SELECT evidence->>'basis' FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id
       WHERE r.record_key='p4' AND r.source_id=-1610")" = "human_group_review" ] || fail "godkendt post bærer ikke basis"
[ "$(ledger "${db}_appr")" = "mapped:,mapped:,mapped:,mapped:" ] || fail "appr: ledger"

# To personas med samme kanoniske person → PLC_PRE_SAME_PERSON.
ident "${db}_same" p4 accepted -161001
AP_=$AP E_PL=4 E_PP=4 E_MAP=4 E_RET=0 E_MEM=4 nej "${db}_same" same PLC_PRE_SAME_PERSON

# Personen har allerede et medlemskab → PLC_PRE_MEMBERSHIP_OVERLAP.
v "${db}_overlap" "INSERT INTO public.person_lineage_membership(person_id,lineage_id,role)
  SELECT -161002,id,'member' FROM public.lineage WHERE source_id=-1610 AND kode='VI'" >/dev/null
nej "${db}_overlap" overlap PLC_PRE_MEMBERSHIP_OVERLAP

# $parkeret_gren$: gren II parkeret → ingen entry, ingen placement; ledger retained_legacy/parkeret_gren; PLC_OK.
jvar "$MP" "$tmp/mp-park.json" 'd["entries"][1].update(canonical=None,aliases=[],parkeret=True)'
MPF="$tmp/mp-park.json" E_ENT=2 E_PL=2 E_PP=2 E_BIND=2 E_REVAL=2 E_MAP=2 E_RET=2 E_MEM=2 ok "${db}_park" park
[ "$(ledger "${db}_park")" = "retained_legacy:parkeret_gren,retained_legacy:parkeret_gren,mapped:,mapped:" ] \
  || fail "park: ledger $(ledger "${db}_park")"
[ "$(v "${db}_park" "SELECT count(*) FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
       WHERE s.source_id=-1610 AND e.code='II'")" = "0" ] || fail "park: entry II oprettet"
[ "$(pub "${db}_park")" = "3/0" ] || fail "park: publicering"

# En record uden nummereret post (uden_post) → ledger ingen_nummereret_post.
jvar "$M" "$tmp/m-uden.json" 'd["placements"][3].update(entry_code=None,printed_number=None,section_path=[],header_ids={},reasons=["uden_post"],post_char_from=None)'
appr "$tmp/m-uden.json" "$tmp/a-uden.json" '[]'
MF="$tmp/m-uden.json" AP_="$tmp/a-uden.json" ok "${db}_udenpost" udenpost
[ "$(ledger "${db}_udenpost")" = "retained_legacy:ingen_nummereret_post,mapped:,mapped:,mapped:" ] \
  || fail "udenpost: ledger $(ledger "${db}_udenpost")"

# $paritet_2018_20$: en bevidst ændring af en modpartsrække midt i ceremonien får POST til at fejle.
q -d "${db}_parit" >/dev/null <<'SQL'
CREATE FUNCTION public.t6d1_saboter() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN UPDATE public.person_external_id SET nr=nr+100 WHERE person_id=-161102 AND source_id=-1611; RETURN NULL; END $$;
CREATE TRIGGER t6d1_saboter AFTER INSERT ON private.legacy_placement_disposition
  FOR EACH STATEMENT EXECUTE FUNCTION public.t6d1_saboter();
SQL
nej "${db}_parit" parit PLC_POST_PARITET
grep -q 'koord_andre' "$tmp/parit.out" || fail "parit: koord_andre ikke nævnt: $(grep -m1 PLC_POST "$tmp/parit.out")"

# 5c-1's form i prod: kildens legacy-rækker har allerede v1 retained_legacy (uden grund). Ceremonien kører; mapped bliver
# v2, og en række, der forbliver retained_legacy, får ingen ny version (record_legacy_disposition er idempotent).
v "${db}_fortsat" "SELECT private.record_legacy_disposition(person_id,source_id,'retained_legacy',NULL,
  '{\"rule_version\":\"placement-membership-v1\",\"fixture\":\"5c-1\"}') FROM public.person_external_id WHERE source_id=-1610" >/dev/null
ok "${db}_fortsat" fortsat
[ "$(ledger "${db}_fortsat")" = "retained_legacy:,mapped:,mapped:,mapped:" ] || fail "fortsat: ledger $(ledger "${db}_fortsat")"
[ "$(v "${db}_fortsat" "SELECT string_agg(version::text,',' ORDER BY person_id) FROM private.legacy_placement_disposition_current
       WHERE source_id=-1610")" = "1,2,2,2" ] || fail "fortsat: versioner"

# En forældet publicering før ceremonien (p3's biografi gjort privat → ny tilstand) → PLC_PRE_PUBLISHED.
v "${db}_stale" "UPDATE public.narrative SET privat=true WHERE subjekt_type='person' AND subjekt_id=-161003 AND source_id=-1610" >/dev/null
[ "$(pub "${db}_stale")" = "2/1" ] || fail "stale: fixture $(pub "${db}_stale")"
nej "${db}_stale" stale PLC_PRE_PUBLISHED

# --- Runde 2: gruppekort og strukturkort (godkendelseskontrakt v2) ---
KORT='[{"id":"kuld:9000","value":"II"}]'
rp() { v "$1" "SELECT concat_ws('|',e.code,pc.printed_number,pc.generation_local,pc.generation_label_raw,pc.kuld_label,
  cardinality(pc.section_path),pc.evidence->>'basis',coalesce(pc.evidence->>'human_header_levels','-'),
  (pc.evidence->'header_ids') ? 'kuld',jsonb_array_length(coalesce(pc.evidence#>'{human_review,gruppekort}','[]')))
  FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id
  JOIN public.lineage_scheme_entry e ON e.id=pc.scheme_entry_id WHERE r.source_id=-1610 AND r.record_key='$2'"; }
plc() { v "$1" "SELECT string_agg(r.record_key,',' ORDER BY r.record_key) FROM private.source_record_placement rp
  JOIN private.source_record r ON r.id=rp.source_record_id WHERE r.source_id=-1610"; }

# gruppe: to poster under ét godkendt gruppekort (kuld II mangler; kuld I står foran) → kuld_label = værdien, nærmeste-
# reglen undtager kuld, human_levels 2. g3 har også uenig:legacy_nr uden record-approval → skrives ikke.
appr "$M" "$tmp/a-gruppe.json" '[]' "$KORT"
AP_="$tmp/a-gruppe.json" E_PL=5 E_PP=5 E_MEM=5 E_HUM=2 ok "${db}_gruppe" gruppe
grep -q ' human_levels=2$' "$tmp/gruppe.out" || fail "gruppe: kvittering $(grep PLC_OK "$tmp/gruppe.out")"
[ "$(plc "${db}_gruppe")" = "g1,g2,p1,p2,p3" ] || fail "gruppe: placements $(plc "${db}_gruppe")"
[ "$(rp "${db}_gruppe" g1)" = 'II|1|1|Første|II|2|human_group_review|["kuld"]|f|1' ] || fail "gruppe: g1 $(rp "${db}_gruppe" g1)"
[ "$(v "${db}_gruppe" "SELECT private.placement_header_violations(-1610)||'/'||private.placement_human_header_levels(-1610)")" = "0/2" ] \
  || fail "gruppe: nærmeste/human"
# gruppe_blandet: med record-approval for g3 skrives den også.
appr "$M" "$tmp/a-blandet.json" '[{"record_key":"g3"}]' "$KORT"
AP_="$tmp/a-blandet.json" E_PL=6 E_PP=6 E_MEM=6 E_HUM=3 ok "${db}_blandet" blandet
[ "$(rp "${db}_blandet" g3)" = 'II|3|1|Første|II|2|human_group_review|["kuld"]|f|1' ] || fail "blandet: g3 $(rp "${db}_blandet" g3)"

# struktur: ikke_parret-post med record-approval og nummer → nærmeste overskrifter (linje II, slægtled 1, kuld I).
appr "$M" "$tmp/a-struktur.json" '[{"record_key":"s1","printed_number":"7"}]'
AP_="$tmp/a-struktur.json" E_PL=4 E_PP=4 E_MEM=4 ok "${db}_struktur" struktur
[ "$(rp "${db}_struktur" s1)" = 'II|7|1|Første|I|3|human_group_review|-|t|0' ] || fail "struktur: s1 $(rp "${db}_struktur" s1)"

# stamme_generation_usikker: record-approval uden nummer = manifestets værdier.
appr "$M" "$tmp/a-usikker.json" '[{"record_key":"u1"}]'
AP_="$tmp/a-usikker.json" E_PL=4 E_PP=4 E_MEM=4 ok "${db}_usikker" usikker
[ "$(rp "${db}_usikker" u1)" = 'II|5|1|Første|I|3|human_group_review|-|t|0' ] || fail "usikker: u1 $(rp "${db}_usikker" u1)"

# Negativer (runde 2) på neg-basen.
appr "$M" "$tmp/a-kort-forkert.json" '[]' '[{"id":"kuld:9000","value":"III"}]'
AP_="$tmp/a-kort-forkert.json" nej "$N" kort1 PLC_PRE_GRUPPEKORT
appr "$M" "$tmp/a-kort-ukendt.json" '[]' '[{"id":"kuld:1","value":"II"}]'
AP_="$tmp/a-kort-ukendt.json" nej "$N" kort2 PLC_PRE_GRUPPEKORT
appr "$M" "$tmp/a-kort-dublet.json" '[]' '[{"id":"kuld:9000","value":"II"},{"id":"kuld:9000","value":"II"}]'
AP_="$tmp/a-kort-dublet.json" nej "$N" kort3 PLC_PRE_GRUPPEKORT
appr "$M" "$tmp/a-unik.json" '[{"record_key":"s1","printed_number":"7"},{"record_key":"s2","printed_number":"7"}]'
AP_="$tmp/a-unik.json" E_PL=5 E_PP=5 E_MEM=5 nej "$N" unik PLC_PRE_UNIK
appr "$M" "$tmp/a-s1-uden-nr.json" '[{"record_key":"s1"}]'
AP_="$tmp/a-s1-uden-nr.json" nej "$N" struk1 PLC_PRE_APPROVALS
appr "$M" "$tmp/a-u1-nr.json" '[{"record_key":"u1","printed_number":"9"}]'
AP_="$tmp/a-u1-nr.json" nej "$N" usik1 PLC_PRE_APPROVALS
appr "$M" "$tmp/a-g1-record.json" '[{"record_key":"g1"}]' "$KORT"
AP_="$tmp/a-g1-record.json" nej "$N" kort4 PLC_PRE_APPROVALS
appr "$M" "$tmp/a-g3-uden-kort.json" '[{"record_key":"g3"}]'
AP_="$tmp/a-g3-uden-kort.json" nej "$N" kort5 PLC_PRE_APPROVALS
# human_id_brud: et bekræftet niveau har også et id → stop før skrivning.
jvar "$M" "$tmp/m-human-id.json" 'd["placements"][4]["header_ids"]["kuld"]="header:4500"'
appr "$tmp/m-human-id.json" "$tmp/a-human-id.json" '[]' "$KORT"
MF="$tmp/m-human-id.json" AP_="$tmp/a-human-id.json" E_PL=5 E_PP=5 E_MEM=5 E_HUM=2 nej "$N" humanid PLC_PRE_HUMAN
AP_="$tmp/a-gruppe.json" E_PL=5 E_PP=5 E_MEM=5 E_HUM=1 nej "$N" hum1 PLC_PRE_HUMAN_LEVELS
jvar "$M" "$tmp/m-inv4.json" 'del d["invariants"]["gruppekort_daekker_overskriftsaarsager"]'
appr "$tmp/m-inv4.json" "$tmp/a-inv4.json" '[]'
MF="$tmp/m-inv4.json" AP_="$tmp/a-inv4.json" nej "$N" inv3 PLC_PRE_INVARIANTS

echo PLACEMENT_CEREMONI_TEST_OK
