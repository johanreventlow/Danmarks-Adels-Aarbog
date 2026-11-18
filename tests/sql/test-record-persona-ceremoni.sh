#!/usr/bin/env bash
# Dataceremonien for record_persona (record_persona_ceremoni.sql) og målingen (maal_record_persona.sql) ende-til-ende
# på en syntetisk mini-kilde (fixtures/ceremoni-record-persona.sql), kaldt med -v-variabler som runneren gør.
# Manifestet (JSONL, én kanonisk linje pr. kort) bygges af basen med samme definitioner som kortbyggeren; svarfilen er
# ren tekst med manifestets sha i første linje. Negative scenarier ruller tilbage og køres på basen selv eller på en
# kopi, der kun afviger i det, scenariet tester; det skrivende scenarie kører på sin egen kopi.
# Brug: bash tests/sql/test-record-persona-ceremoni.sh <basenavn>
#   Opretter <basenavn> og <basenavn>_go/_kladde/_andre/_persona/_anon; dropper netop dem, når hele testen er grøn (ellers står de
#   til eftersyn). Scriptet dropper aldrig andre baser.
set -euo pipefail
db=${1:?database}
S=.claude/skills/daa-extract/scripts
F=tests/sql/fixtures
tmp=$(mktemp -d "/tmp/${db}.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 "$@"; }
v() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "RECORD_PERSONA_CEREMONI_TEST_FAILED: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
SRC=-6400; ACTOR=a6400000-0000-0000-0000-000000006400; PROFILE=fixture-pub-a; RULE=rp-header-v1
# jvar <ind> <ud> <python-sætning over d (listen af manifestlinjer)>: en variant af manifestet, kanonisk JSONL.
jvar() { python3 -I -c 'import json,sys
d=[json.loads(l) for l in open(sys.argv[1],encoding="utf-8") if l.strip()]; exec(sys.argv[3])
open(sys.argv[2],"w",encoding="utf-8").write("".join(json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(",",":"))+"\n" for x in d))' "$1" "$2" "$3"; }

createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do
  q -d "$db" -f "$f" >/dev/null 2>&1 || fail "opsætning: $f"; done
q -d "$db" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' >/dev/null 2>&1 \
  || fail "opsætning: tests/sql/reimport-writer-v2-bootstrap.sql"
q -d "$db" -f db-rls.sql >/dev/null 2>&1 || fail "opsætning: db-rls.sql (anden gang)"
(cd $F && q -d "$db" -f ceremoni-record-persona.sql >/dev/null 2>&1) || fail "opsætning: fixtures/ceremoni-record-persona.sql"
[ "$(v "$db" "SELECT public.narrative_record_contract_version()")" = "2" ] || fail "kontrakt v2"
PSHA=$(v "$db" "SELECT profile_sha256 FROM private.reimport_writer_profile WHERE source_id=$SRC AND profile_id='$PROFILE'")

# Manifestet bygges af basen (kortbyggerens definitioner): mention- og foldet tekst = sha256 over UTF-8 af
# source_mention.verbatim_text / btrim(relation_fold_raw_text(helpostens forekomst).folded); header_ids = overskrifternes
# observationer (projektejerens valg på kortet); legacy = personens tilbagetrukne narrativ i kilden.
env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$db" -v src=$SRC -v rule=$RULE > "$tmp/m-raw.jsonl" <<'SQL'
WITH v(kort,linje,k,p,alias,gl,glr,kl,hids,human,sp) AS (VALUES
  ('K1',1,'rpc-a',-640001::bigint,-640011::bigint,3,'III',NULL::text,'{"linje":0,"slaegtled":20}','[]','["header:0","header:20"]'),
  ('K2',2,'rpc-b',-640002::bigint,-640012::bigint,4,'IV A','Hr-Opdigtets-Søn','{"linje":0,"kuld":600}','["slaegtled"]','["header:0","header:600"]'))
SELECT jsonb_build_object('alias_person_id',v.alias,
  'foldet_sha256',encode(sha256(convert_to(btrim((private.relation_fold_raw_text(occ.verbatim_text)).folded),'UTF8')),'hex'),
  'helpost_observation_id',obs.id,'kort',v.kort,'legacy_narrative_id',n.id,'legacy_status_foer',l.status,'linje',v.linje,
  'mention_id',m.id,'mention_text_sha256',encode(sha256(convert_to(m.verbatim_text,'UTF8')),'hex'),'person_id',v.p,
  'placement',jsonb_build_object('generation_label_raw',v.glr,'generation_local',v.gl,
    'header_ids',(SELECT jsonb_object_agg(h.key,private.header_observation_uuid(occ.rendition_id,:'rule',h.value::int))
                    FROM jsonb_each_text(v.hids::jsonb) h),
    'human_header_levels',v.human::jsonb,'kuld_label',v.kl,
    'scheme_entry_id',(SELECT e.id FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
                        WHERE s.source_id=:src AND s.kind='stamtavle' AND e.code='H'),
    'section_path',v.sp::jsonb),
  'record_key',v.k)::text
  FROM v
  JOIN private.source_record r ON r.source_id=:src AND r.record_key=v.k
  JOIN private.source_record_anchor_current a ON a.source_record_id=r.id AND a.decision_status='accepted'
  JOIN private.source_record_occurrence occ ON occ.id=a.occurrence_id
  JOIN private.source_observation obs ON obs.occurrence_id=occ.id AND obs.observation_kind='person'
  JOIN private.source_mention m ON m.observation_id=obs.id
  JOIN public.narrative n ON n.subjekt_type='person' AND n.subjekt_id=v.p AND n.source_id=:src
  JOIN private.narrative_legacy_publication l ON l.narrative_id=n.id
 ORDER BY v.linje;
SQL
jvar "$tmp/m-raw.jsonl" "$tmp/m.jsonl" 'pass'
[ "$(grep -c . "$tmp/m.jsonl")" = 2 ] || fail "manifest: ikke to linjer"
M=$tmp/m.jsonl

# svar <manifest> <ud> <linjer...>: svarfilen med manifestets sha i første kommentarlinje.
svar() { local mf=$1 out=$2; shift 2
  { echo "# opdigtet svarfil (test) manifest_sha256=$(sha "$mf")"; echo "# kort K1-K2"; printf '%s\n' "$@"; } > "$out"; }
alle_j() { svar "$1" "$2" "K1-identitet J  # Henrik" "K1-placement J" "K2-identitet J" "K2-placement J  # kuld"; }
alle_j "$M" "$tmp/svar.txt"

maal() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -v src=$SRC -v manifest_path="${MAALM:-$M}" -d "$1" -f $S/maal_record_persona.sql; }
felt() { maal "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# run <base> <mærke>: ceremonien; overstyr med MF= SV= MSHA= SSHA= PSH= RUL= foran.
run() {
  local mf=${MF:-$M} sv=${SV:-$tmp/svar.txt}
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v actor=$ACTOR -v src=$SRC \
    -v profile_id=$PROFILE -v profile_sha="${PSH:-$PSHA}" -v header_rule_version="${RUL:-$RULE}" \
    -v manifest_path="$mf" -v manifest_sha="${MSHA:-$(sha "$mf")}" -v svar_path="$sv" -v svar_sha="${SSHA:-$(sha "$sv")}" \
    -f $S/record_persona_ceremoni.sql > "$tmp/$2.out" 2>&1
}
kode() { grep -o 'T_RP_[A-Z_0-9]*' "$tmp/$1.out" | head -1; }
ok() { run "$@" || fail "$2: $(kode "$2") $(grep -m1 -E 'ERROR|FEJL' "$tmp/$2.out" || true)"; }
# Aftryk af alt, ceremonien kan skrive (også reimport-tabellerne), og som skal være uændret efter en afvisning.
state() { v "$1" "SELECT concat_ws('/',
  (SELECT count(*) FROM private.reimport_authorization),(SELECT count(*) FROM private.reimport_batch),
  (SELECT count(*) FROM private.reimport_event),(SELECT count(*) FROM private.extraction_run),
  (SELECT count(*) FROM private.source_persona),(SELECT count(*) FROM private.source_persona_mention),
  (SELECT count(*) FROM private.source_persona_identity_event),(SELECT count(*) FROM private.source_record_placement),
  (SELECT count(*) FROM private.source_persona_placement),(SELECT count(*) FROM private.legacy_placement_disposition),
  (SELECT count(*) FROM public.person_lineage_membership),(SELECT count(*) FROM public.person_slaegt_membership),
  (SELECT count(*) FROM public.change_set),(SELECT count(*) FROM public.change_event),(SELECT count(*) FROM public.narrative),
  (SELECT count(*) FROM private.narrative_record_publication),(SELECT count(*) FROM private.narrative_publication_event))"; }
nej() {  # nej <base> <mærke> <kode>: afvist med koden, intet skrevet
  local b=$1 t=$2 c=$3 s0; s0=$(state "$b")
  if run "$b" "$t"; then fail "$t: godtaget, forventede $c"; fi
  grep -q "$c" "$tmp/$t.out" || fail "$t: forventede $c, fik $(kode "$t") $(grep -m1 ERROR "$tmp/$t.out" || true)"
  [ "$(state "$b")" = "$s0" ] || fail "$t: afvisningen skrev"
  [ "$(felt "$b" fase)" = "ddl" ] || fail "$t: fasen ændret"
}

for c in go kladde andre persona anon; do createdb -T "$db" "${db}_$c"; done
f0=$(maal "$db")
[[ "$f0" =~ ^T_RP_MAAL\ fase=ddl\ personas=0\ identiteter=0\ placements=0\ kladder=0\ eligible=0\ header_violations=0\  ]] \
  || fail "mål før: $f0"
K0=$(felt "$db" KOORD_2018_20); KS0=$(felt "$db" KOORD_SRC); FA0=$(felt "$db" FAKTA); BIO0=$(felt "$db" BIO)
SY0=$(felt "$db" synlige_1939)

# ---- Negative scenarier (basen ændres ikke) ----
MSHA=$(printf '0%.0s' {1..64}) nej "$db" fejl-manifest-sha T_RP_PRE_SHA
SSHA=$(printf '0%.0s' {1..64}) nej "$db" fejl-svar-sha T_RP_PRE_SHA
PSH=$(printf '0%.0s' {1..64}) nej "$db" fejl-profil-sha T_RP_PRE_PROFIL
# Svarfilen: ethvert N, manglende, dobbelt eller ukendt svar og et svar til et andet manifest stopper før authorize.
svar "$M" "$tmp/s-n.txt" "K1-identitet J" "K1-placement J" "K2-identitet J" "K2-placement N  # forkert kuld"
SV="$tmp/s-n.txt" nej "$db" svar-n T_RP_PRE_SVAR
svar "$M" "$tmp/s-mangler.txt" "K1-identitet J" "K1-placement J" "K2-identitet J"
SV="$tmp/s-mangler.txt" nej "$db" svar-mangler T_RP_PRE_SVAR
svar "$M" "$tmp/s-dobbelt.txt" "K1-identitet J" "K1-placement J" "K2-identitet J" "K2-placement J" "K1-identitet J"
SV="$tmp/s-dobbelt.txt" nej "$db" svar-dobbelt T_RP_PRE_SVAR
svar "$M" "$tmp/s-ukendt.txt" "K1-identitet J" "K1-placement J" "K2-identitet J" "K2-placement J" "K9-identitet J"
SV="$tmp/s-ukendt.txt" nej "$db" svar-ukendt T_RP_PRE_SVAR
svar "$M" "$tmp/s-form.txt" "K1-identitet J" "K1-placement J" "K2-identitet J" "K2-placement Ja"
SV="$tmp/s-form.txt" nej "$db" svar-form T_RP_PRE_SVAR
{ echo "# opdigtet svarfil manifest_sha256=$(printf '1%.0s' {1..64})"; sed 1d "$tmp/svar.txt"; } > "$tmp/s-andet-manifest.txt"
SV="$tmp/s-andet-manifest.txt" nej "$db" svar-andet-manifest T_RP_PRE_SVAR
sed 1d "$tmp/svar.txt" > "$tmp/s-uden-sha.txt"
SV="$tmp/s-uden-sha.txt" nej "$db" svar-uden-manifest-sha T_RP_PRE_SVAR
grep -q 'T_RP_PRE_SVAR' "$tmp/svar-n.out" && ! grep -q 'T_RP_OK' "$tmp/svar-n.out" || fail "svar-n: kvittering"
# Manifestet: hver variant har sin egen (korrekte) svarfil, så det er førtilstanden, der afviser.
mvar() {  # mvar <mærke> <python-sætning> <kode>
  jvar "$M" "$tmp/m-$1.jsonl" "$2"; alle_j "$tmp/m-$1.jsonl" "$tmp/s-$1.txt"
  MF="$tmp/m-$1.jsonl" SV="$tmp/s-$1.txt" nej "$db" "$1" "$3"; }
mvar mention-sha 'd[0]["mention_text_sha256"]="2"*64' T_RP_PRE_MANIFEST
mvar mention-id 'd[1]["mention_id"]="00000000-0000-4000-8000-000000000001"' T_RP_PRE_MANIFEST
mvar mention-dublet 'd[1]["mention_id"]=d[0]["mention_id"]' T_RP_PRE_MANIFEST
mvar foldet-sha 'd[1]["foldet_sha256"]="3"*64' T_RP_PRE_MANIFEST
mvar helpost 'd[0]["helpost_observation_id"]=d[1]["helpost_observation_id"]' T_RP_PRE_MANIFEST
mvar legacy-status 'd[0]["legacy_status_foer"]="grandfathered_publication"' T_RP_PRE_MANIFEST
mvar forbyttet-person 'd[0]["person_id"],d[1]["person_id"]=d[1]["person_id"],d[0]["person_id"]' T_RP_PRE_MANIFEST
mvar alias 'd[0]["alias_person_id"]=d[1]["alias_person_id"]' T_RP_PRE_MANIFEST
mvar header-art 'd[0]["placement"]["header_ids"]["linje"]=d[0]["placement"]["header_ids"]["slaegtled"]' T_RP_PRE_MANIFEST
mvar header-niveau 'd[1]["placement"]["human_header_levels"]=["kuld"]' T_RP_PRE_MANIFEST
mvar entry 'd[0]["placement"]["scheme_entry_id"]=-1' T_RP_PRE_MANIFEST
mvar section-path 'd[0]["placement"]["section_path"]="header:0"' T_RP_PRE_MANIFEST
mvar ekstra-noegle 'd[0]["ekstra"]=1' T_RP_PRE_MANIFEST
mvar dobbelt-kort 'd[1]["kort"]="K1"' T_RP_PRE_MANIFEST
mvar ukendt-post 'd[0]["record_key"]="rpc-x"' T_RP_PRE_MANIFEST
RUL=anden-regel nej "$db" header-regel T_RP_PRE_MANIFEST
# Årsagen står i fejlen (uden id'er og tekst), så runnerens log viser, hvilken førtilstand der afveg.
aarsag() { grep -q "$2" "$tmp/$1.out" || fail "$1: forventede årsagen »$2«, fik $(grep -m1 -o 'T_RP_[^\"]*' "$tmp/$1.out")"; }
aarsag mention-sha 'kort K1 (mention)'; aarsag mention-id 'kort K2 (mention)'; aarsag mention-dublet 'dublet'
aarsag foldet-sha 'kort K2 (foldet tekst)'; aarsag helpost 'kort K1 (helpost)'; aarsag legacy-status 'kort K1 (legacy)'
aarsag alias 'kort K1 (alias)'; aarsag header-art 'kort K1 (overskrift)'; aarsag header-niveau 'kort K2 (overskrift)'
aarsag header-regel 'kort K1 (overskrift)'; aarsag entry 'kort K1 (entry)'; aarsag ukendt-post 'kort K1 (post)'
aarsag svar-n 'N for K2-placement'
# Overskriftsvalidatoren efter skrivningen: Henrik under kuldet (forkert nærmeste) ruller alt tilbage.
jvar "$M" "$tmp/m-forkert-kuld.jsonl" 'd[0]["placement"]["header_ids"]["kuld"]=d[1]["placement"]["header_ids"]["kuld"]'
alle_j "$tmp/m-forkert-kuld.jsonl" "$tmp/s-forkert-kuld.txt"
MF="$tmp/m-forkert-kuld.jsonl" SV="$tmp/s-forkert-kuld.txt" nej "$db" forkert-kuld T_RP_WRITE_HEADER
[ "$(maal "$db")" = "$f0" ] || fail "basen er ændret af de negative scenarier"

# En kladde oprettet efter manifestet: posten har nu en aktiv binding.
q -d "${db}_kladde" >/dev/null <<SQL
INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',-640001,$SRC,'9','Opdigtet kladde');
INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
  SELECT max(n.id),r.id,'Fixture','Fixture side 9','draft' FROM public.narrative n, private.source_record r
   WHERE n.subjekt_id=-640001 AND n.tekst='Opdigtet kladde' AND r.source_id=$SRC AND r.record_key='rpc-a' GROUP BY r.id;
SQL
nej "${db}_kladde" kladde-efter-manifest T_RP_PRE_MANIFEST
aarsag kladde-efter-manifest 'kort K1 (binding)'

# En persona på en helpost uden batch (fx skrevet af en anden vej): fasen afviser, før noget skrives.
q -d "${db}_persona" >/dev/null <<SQL
INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
  SELECT $SRC,'anden-vej:rpc-b',r.created_run_id FROM private.source_record r WHERE r.source_id=$SRC AND r.record_key='rpc-b';
INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal)
  SELECT sp.id,m.id,'primary',1 FROM private.source_persona sp, private.source_record r
    JOIN private.source_record_anchor_current a ON a.source_record_id=r.id
    JOIN private.source_observation o ON o.occurrence_id=a.occurrence_id AND o.observation_kind='person'
    JOIN private.source_mention m ON m.observation_id=o.id
   WHERE sp.persona_key='anden-vej:rpc-b' AND r.source_id=$SRC AND r.record_key='rpc-b';
SQL
nej "${db}_persona" persona-findes T_RP_PRE_FASE

# \$medlemskab_andre\$: forhåndsvisningen rammer en tredje person (rpc-c's medlemskab er væk, så den er eligible igen).
v "${db}_andre" "DELETE FROM public.person_lineage_membership WHERE person_id=-640003" >/dev/null
v "${db}_andre" "DELETE FROM public.person_slaegt_membership WHERE person_id=-640003" >/dev/null
nej "${db}_andre" medlemskab-andre T_RP_PRE_MEDLEMSKAB
[ "$(v "${db}_andre" "SELECT count(*) FROM private.source_persona WHERE source_id=$SRC")" = 1 ] || fail "medlemskab-andre: personas skrevet"

# \$koord_anon\$: en tredjepart gør en privat person i en anden kilde offentlig mellem førmålingen og POST (simuleret
# af en trigger på første persona-skrivning). Redaktørens koordinater er uændrede (redaktionen ser også private), og
# personen har ingen fakta eller tekst, så kun anon-koordinathashen afslører ændringen.
q -d "${db}_anon" >/dev/null <<'SQL'
INSERT INTO public.person(id,levende,privat,status) VALUES (-640102,false,true,'rpc');
INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (-640102,-6401,'I',2,'b2');
CREATE FUNCTION public.rp_test_offentliggoer() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
  SET search_path=pg_catalog SET session_replication_role=replica AS $f$
BEGIN UPDATE public.person SET privat=false WHERE id=-640102 AND privat; RETURN NULL; END $f$;
CREATE TRIGGER rp_test_offentliggoer AFTER INSERT ON private.source_persona
  FOR EACH STATEMENT EXECUTE FUNCTION public.rp_test_offentliggoer();
SQL
# Forudsætning: anon ser ikke personen før, men gør efter offentliggørelsen; redaktøren ser den begge gange.
anon_q() { v "${db}_anon" "BEGIN; $1 SET LOCAL ROLE anon;
  SELECT 'N='||count(*) FROM public.public_person_source_coordinates() WHERE person_id=-640102; ROLLBACK;" | sed -n 's/^N=//p'; }
red_q() { v "${db}_anon" "BEGIN; $1 SELECT set_config('request.jwt.claim.sub','$ACTOR',true) IS NOT NULL;
  SELECT 'N='||count(*) FROM public.public_person_source_coordinates() WHERE person_id=-640102; ROLLBACK;" | sed -n 's/^N=//p'; }
[ "$(anon_q '')" = 0 ] && [ "$(anon_q 'UPDATE public.person SET privat=false WHERE id=-640102;')" = 1 ] \
  || fail "koord-anon: anon-forudsætning"
[ "$(red_q '')" = 1 ] && [ "$(red_q 'UPDATE public.person SET privat=false WHERE id=-640102;')" = 1 ] \
  || fail "koord-anon: redaktør-forudsætning"
nej "${db}_anon" koord-anon T_RP_POST_KOORD_ANDRE_ANON
[ "$(v "${db}_anon" "SELECT privat FROM public.person WHERE id=-640102")" = t ] || fail "koord-anon: ikke rullet tilbage"

# ---- Alle J: personas, identiteter, placements, ledger, medlemskab og kladder ----
ok "${db}_go" go
grep -qx 'T_RP_OK personas=2 identiteter=2 placements=2 medlemskab=2 kladder=2' "$tmp/go.out" || fail "kvittering: $(tail -3 "$tmp/go.out")"
f1=$(maal "${db}_go")
[[ "$f1" =~ ^T_RP_MAAL\ fase=data\ personas=2\ identiteter=2\ placements=2\ kladder=2\ eligible=2\ header_violations=0\  ]] \
  || fail "mål efter: $f1"
[ "$(felt "${db}_go" KOORD_2018_20)" = "$K0" ] || fail "KOORD_2018_20 ændret"
[ "$(felt "${db}_go" KOORD_SRC)" != "$KS0" ] || fail "KOORD_SRC uændret: placementen skulle vises for kilden"
[ "$(felt "${db}_go" FAKTA)" = "$FA0" ] && [ "$(felt "${db}_go" BIO)" = "$BIO0" ] || fail "FAKTA/BIO ændret før publiceringen"
[ "$(felt "${db}_go" synlige_1939)" = "$SY0" ] || fail "synlige tekster ændret før publiceringen"
# Hver skrevet identitet matcher sin manifestlinjes person (personaen på postens helpost-mention).
[ "$(v "${db}_go" "SELECT string_agg(r.record_key||':'||i.decision_status||':'||i.canonical_person_id||':'||i.version||':'||(i.evidence->>'basis')||':'||(i.evidence->>'line'),',' ORDER BY r.record_key)
   FROM private.source_record r
   JOIN private.source_record_anchor_current a ON a.source_record_id=r.id AND a.decision_status='accepted'
   JOIN private.source_observation o ON o.occurrence_id=a.occurrence_id AND o.observation_kind='person'
   JOIN private.source_mention m ON m.observation_id=o.id
   JOIN private.source_persona_mention spm ON spm.mention_id=m.id
   JOIN private.source_persona_identity i ON i.source_persona_id=spm.persona_id
  WHERE r.source_id=$SRC AND r.record_key IN ('rpc-a','rpc-b')")" \
  = "rpc-a:accepted:-640001:1:human_sheet:1,rpc-b:accepted:-640002:1:human_sheet:2" ] || fail "identiteter"
[ "$(v "${db}_go" "SELECT string_agg(DISTINCT (i.evidence->>'sheet_sha256')||'/'||(i.evidence->>'rows_sha256'),',')
   FROM private.source_persona_identity i JOIN private.source_persona sp ON sp.id=i.source_persona_id
  WHERE sp.source_id=$SRC AND sp.persona_key LIKE '%rpc-_' AND sp.persona_key NOT LIKE 'fixture:%'")" \
  = "$(sha "$M")/$(sha "$tmp/svar.txt")" ] || fail "identitetens evidens (sheet/rows)"
# Placements (record + principal_member) med kortets værdier og human_sheet-evidens.
[ "$(v "${db}_go" "SELECT string_agg(r.record_key||':'||coalesce(pc.printed_number,'-')||':'||pc.generation_local||':'||pc.generation_label_raw||':'||coalesce(pc.kuld_label,'-')||':'||(pc.evidence->>'basis')||':'||(pc.evidence->'human_header_levels')::text||':'||array_to_string(pc.section_path,';'),',' ORDER BY r.record_key)
   FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id
  WHERE r.source_id=$SRC AND r.record_key IN ('rpc-a','rpc-b') AND pc.decision_status='accepted'")" \
  = 'rpc-a:-:3:III:-:human_sheet:[]:header:0;header:20,rpc-b:-:4:IV A:Hr-Opdigtets-Søn:human_sheet:["slaegtled"]:header:0;header:600' ] \
  || fail "record-placements"
[ "$(v "${db}_go" "SELECT count(*) FROM private.source_persona_placement_current pp
   JOIN private.source_record_placement rp ON rp.id=pp.record_placement_id JOIN private.source_record r ON r.id=rp.source_record_id
  WHERE r.source_id=$SRC AND r.record_key IN ('rpc-a','rpc-b') AND pp.decision_status='accepted' AND pp.placement_role='principal_member'")" = 2 ] \
  || fail "persona-placements"
[ "$(v "${db}_go" "SELECT private.placement_human_header_levels($SRC)")" = 1 ] || fail "human_header_levels"
# Ledger: version 2 mapped på den nye placement; legacy-teksterne er stadig tilbagetrukne.
[ "$(v "${db}_go" "SELECT string_agg(d.person_id||':'||d.version||':'||d.disposition||':'||(d.placement_id=pc.id),',' ORDER BY d.person_id)
   FROM private.legacy_placement_disposition_current d
   JOIN private.source_record_placement_current pc ON pc.id=d.placement_id
  WHERE d.source_id=$SRC AND d.person_id IN (-640001,-640002)")" = "-640002:2:mapped:true,-640001:2:mapped:true" ] || fail "ledger"
[ "$(v "${db}_go" "SELECT string_agg(l.status,',') FROM private.narrative_legacy_publication l JOIN public.narrative n ON n.id=l.narrative_id WHERE n.source_id=$SRC")" \
  = "withdrawn,withdrawn" ] || fail "legacy-status"
# Medlemskab: gældende for begge; rpc-c urørt.
[ "$(v "${db}_go" "SELECT count(*) FROM public.person_lineage_membership l WHERE l.person_id IN (-640001,-640002) AND private.membership_is_current(l.person_id,l.lineage_id)")" = 2 ] \
  || fail "medlemskab"
[ "$(v "${db}_go" "SELECT count(*) FROM jsonb_array_elements(private.placement_membership_set($SRC)->'items') i WHERE i->>'reason_code'='already_current'")" = 3 ] \
  || fail "medlemskabssættet efter"
# Kladderne: draft, ikke privat, foldet tekst med manifestets sha; tilstanden er existing_exact_binding.
[ "$(v "${db}_go" "SELECT string_agg(r.record_key||':'||b.status||':'||n.privat||':'||encode(sha256(convert_to(n.tekst,'UTF8')),'hex'),',' ORDER BY r.record_key)
   FROM private.narrative_record_publication b JOIN private.source_record r ON r.id=b.source_record_id
   JOIN public.narrative n ON n.id=b.narrative_id WHERE r.source_id=$SRC AND r.record_key IN ('rpc-a','rpc-b')")" \
  = "$(python3 -I -c 'import json,sys
print(",".join(x["record_key"]+":draft:false:"+x["foldet_sha256"] for x in (json.loads(l) for l in open(sys.argv[1]))))' "$M")" ] \
  || fail "kladder"
[ "$(v "${db}_go" "SELECT string_agg(private.narrative_publication_state(v.p,$SRC,v.k)#>>'{authority,kind}',',' ORDER BY v.k)
   FROM (VALUES ('rpc-a',-640001::bigint),('rpc-b',-640002::bigint)) v(k,p)")" = "existing_exact_binding,existing_exact_binding" ] \
  || fail "narrativtilstand"
# Kvitteringsposten: én change_set med kilden som subjekt og kvitteringen som summary.
[ "$(v "${db}_go" "SELECT count(*) FROM public.change_set WHERE operation='record_persona_ceremoni' AND subjekt_type='source' AND subjekt_id=$SRC
   AND summary='T_RP_OK personas=2 identiteter=2 placements=2 medlemskab=2 kladder=2'")" = 1 ] || fail "kvitteringspost"
[ "$(v "${db}_go" "SELECT count(*) FROM private.reimport_batch WHERE source_id=$SRC AND status='finalized' AND manifest_sha256='$(sha "$M")'
   AND preview_sha256='$(sha "$tmp/svar.txt")'")" = 1 ] || fail "batch"
# Genkørsel: fasen stopper, intet skrives.
nej_fase() { local s0; s0=$(state "${db}_go")
  if run "${db}_go" genk; then fail "genkørsel godtaget"; fi
  grep -q 'T_RP_PRE_FASE' "$tmp/genk.out" || fail "genkørsel: forventede T_RP_PRE_FASE, fik $(kode genk)"
  [ "$(state "${db}_go")" = "$s0" ] || fail "genkørslen skrev"; }
nej_fase

for c in go kladde andre persona anon; do dropdb "${db}_$c"; done
dropdb "$db"
echo RECORD_PERSONA_CEREMONI_TEST_OK
