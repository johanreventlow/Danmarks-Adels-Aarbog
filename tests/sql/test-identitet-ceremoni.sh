#!/usr/bin/env bash
# Trin 6d-2a Task 6: identitets-ceremonien (identitet_ceremoni.sql) og målingen (maal_trin6d2a.sql) ende-til-ende på en
# syntetisk mini-kilde (fixtures/ceremoni-6d2a.sql): ét samme_som-kort (K1) og tre identitetskort (K2 unresolved/2,
# K3 og K4 uden identitetsrække). Manifestet bygges af den lokale base med samme hash-definitioner som runbookens
# kortbygger; svarfilen er ren tekst. Negative scenarier ruller tilbage og køres på basen selv; de tre skrivende
# scenarier (alle J, blandet A/N/J, fire N) kører på hver sin skabelonkopi. Scriptet dropper aldrig databaser.
# Brug: bash tests/sql/test-identitet-ceremoni.sh <basenavn>   (opretter <basenavn> og <basenavn>_go/_mix/_n)
set -euo pipefail
db=${1:?database}
S=.claude/skills/daa-extract/scripts
F=tests/sql/fixtures
tmp=$(mktemp -d "/tmp/${db}.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 "$@"; }
v() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "IDENTITET_CEREMONI_TEST_FAILED: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -c1-64; }
SRC=-620100; ACTOR=a1500000-0000-0000-0000-000000000150
# jvar <ind> <ud> <python-sætning over d>: en variant af manifestet.
jvar() { python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); exec(sys.argv[3])
open(sys.argv[2],"w",encoding="utf-8").write(json.dumps(d,ensure_ascii=False)+"\n")' "$1" "$2" "$3"; }

createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql; do
  q -d "$db" -f "$f" >/dev/null 2>&1 || fail "opsætning: $f"; done
(cd $F && q -d "$db" -f ceremoni-6d2a.sql >/dev/null 2>&1) || fail "opsætning: fixtures/ceremoni-6d2a.sql"

# Svarfilen først (manifestet bærer dens sha). Ren tekst med kommentarer.
svar() {  # svar <ud> <linjer...>
  local out=$1; shift; { echo "# opdigtet svarfil (test)"; printf '%s\n' "$@"; } > "$out"; }
svar "$tmp/alle-j.txt" "K1 J" "K2 J  # kommentar" "K3 J" "K4 J"
svar "$tmp/blandet.txt" "K1 A -620102" "K2 A -620107" "K3 N" "K4 J"
svar "$tmp/fire-n.txt" "K1 N" "K2 N" "K3 N" "K4 N"

# Manifestet bygges af basen. Hash-definitionerne: narrativtekst og persona-mention = sha256 over UTF-8 af
# narrative.tekst / source_mention.verbatim_text (personaens mention med ordinal=1).
manifest() {  # manifest <base> <svar-sha> <ud>
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v src=$SRC -v svar_sha="$2" > "$3" <<'SQL'
WITH n AS (SELECT id,subjekt_id,side,encode(sha256(convert_to(tekst,'UTF8')),'hex') AS sha FROM public.narrative WHERE source_id=:src),
p AS (SELECT sp.id,sp.persona_key,encode(sha256(convert_to(sm.verbatim_text,'UTF8')),'hex') AS sha,
             i.decision_status AS st,coalesce(i.version,0) AS ver
        FROM private.source_persona sp
        JOIN private.source_persona_mention spm ON spm.persona_id=sp.id AND spm.ordinal=1
        JOIN private.source_mention sm ON sm.id=spm.mention_id
        LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id
       WHERE sp.source_id=:src AND sp.persona_key LIKE 'U-%'),
kort AS (
  SELECT 1 AS o,jsonb_build_object('kort','K1','linje',1,'handling','samme_som','alias_person_id',-620105,'objekt_person_id',-620101,
    'forventet_foer',jsonb_build_object('samme_som_kant',false,'staged',false),
    'kandidat',jsonb_build_object('person_id',-620101,'narrative_id',c.id,'side',c.side,'tekst_sha256',c.sha),
    'oversigt',jsonb_build_object('narrative_id',o.id,'side',o.side,'tekst_sha256',o.sha,'kontekst_narrative_id',x.id,
                                  'kontekst_tekst_sha256',x.sha)) AS j
    FROM n c,n o,n x WHERE c.subjekt_id=-620101 AND o.subjekt_id=-620105 AND x.subjekt_id=-620106
  UNION ALL
  SELECT r.o,jsonb_build_object('kort','K'||r.o,'linje',r.o,'handling','identitet','source_persona_id',p.id,'persona_key',p.persona_key,
    'forventet_foer',jsonb_build_object('identitet_status',p.st,'identitet_version',p.ver),
    'kandidat',jsonb_build_object('person_id',r.cand,'narrative_id',c.id,'side',c.side,'tekst_sha256',c.sha),
    'oversigt',jsonb_build_object('side',505,'tekst_sha256',p.sha,'mention_sha256',p.sha))
    FROM (VALUES (2,'U-2',-620102),(3,'U-3',-620103),(4,'U-4',-620104)) r(o,key,cand)
    JOIN p ON p.persona_key=r.key JOIN n c ON c.subjekt_id=r.cand)
SELECT jsonb_build_object('contract','trin6d2a-kortmanifest-v1','source_id',:src::bigint,'kort_html_sha256',repeat('a',64),
  'svar_sha256',:'svar_sha','kort',(SELECT jsonb_agg(j ORDER BY o) FROM kort))::text;
SQL
}
manifest "$db" "$(sha "$tmp/alle-j.txt")" "$tmp/m-alle-j.json"
[ "$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["kort"]))' "$tmp/m-alle-j.json")" = 4 ] || fail "manifest: ikke fire kort"
# Manifester til de andre svarfiler (samme kort; kun svar_sha256 afviger).
for s in blandet fire-n; do manifest "$db" "$(sha "$tmp/$s.txt")" "$tmp/m-$s.json"; done

maal() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -v src=$SRC -v par_a=-620105 -v par_b=-620101 -d "$1" -f $S/maal_trin6d2a.sql; }
felt() { maal "$1" | tr ' ' '\n' | sed -n "s/^$2=//p"; }

# run <base> <mærke>: ceremonien; overstyr med MF= SV= MSHA= SSHA= E_K= E_I= E_R= foran.
run() {
  local mf=${MF:-$tmp/m-alle-j.json} sv=${SV:-$tmp/alle-j.txt}
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v actor=$ACTOR -v src=$SRC \
    -v manifest_path="$mf" -v manifest_sha="${MSHA:-$(sha "$mf")}" -v svar_path="$sv" -v svar_sha="${SSHA:-$(sha "$sv")}" \
    -v expect_kanter="${E_K:-1}" -v expect_identiteter="${E_I:-3}" -v expect_regel="${E_R:-1}" \
    -f $S/identitet_ceremoni.sql > "$tmp/$2.out" 2>&1
}
kode() { grep -o 'T6D2A_[A-Z_0-9]*' "$tmp/$1.out" | head -1; }
ok() { run "$@" || fail "$2: $(kode "$2") $(grep -m1 -E 'ERROR|FEJL' "$tmp/$2.out" || true)"; }
# Tilstandsaftryk, der skal være uændret efter en afvist kørsel.
state() { v "$1" "SELECT (SELECT count(*) FROM public.relation WHERE rolle='samme_som')||'/'||
  (SELECT count(*) FROM public.change_set)||'/'||(SELECT count(*) FROM public.change_event)||'/'||
  (SELECT md5(coalesce(string_agg(source_persona_id||':'||version||':'||decision_status||':'||coalesce(canonical_person_id::text,''),',' ORDER BY source_persona_id),''))
     FROM private.source_persona_identity)||'/'||(SELECT count(*) FROM private.source_persona_identity_event)"; }
nej() {  # nej <base> <mærke> <kode>: afvist med koden, intet skrevet
  local b=$1 t=$2 c=$3 s0; s0=$(state "$b"); shift 3
  if run "$b" "$t"; then fail "$t: godtaget, forventede $c"; fi
  grep -q "$c" "$tmp/$t.out" || fail "$t: forventede $c, fik $(kode "$t") $(grep -m1 ERROR "$tmp/$t.out" || true)"
  [ "$(state "$b")" = "$s0" ] || fail "$t: afvisningen skrev"
  [ "$(felt "$b" fase)" = "ddl" ] || fail "$t: fasen ændret"
}

# Hashes, som en ceremoni ikke må ændre for de personer, kortene ikke vedrører (ikke-nye identiteter).
guard() { v "$1" "SELECT md5((private.placement_membership_set($SRC)->'items')::text)||'/'||
  (SELECT md5(coalesce(string_agg(coalesce(private.persona_family_context(sp.id)::text,'-')||':'||i.version,',' ORDER BY sp.persona_key),''))
     FROM private.source_persona sp JOIN private.source_persona_identity i ON i.source_persona_id=sp.id AND i.decision_status='accepted'
    WHERE sp.source_id=$SRC AND sp.persona_key IN ('I-2','I-3'))"; }

for c in go mix n; do createdb -T "$db" "${db}_$c"; done
f0=$(maal "$db")
[ "$(felt "$db" fase)" = "ddl" ] || fail "fase før: $f0"
[ "$(felt "$db" regel)" = "0" ] && [ "$(felt "$db" unresolved)" = "1" ] && [ "$(felt "$db" uden_identitet)" = "2" ] \
  && [ "$(felt "$db" kanter_par)" = "0" ] || fail "mål før: $f0"
K0=$(felt "$db" KOORD_2018_20); KS0=$(felt "$db" KOORD_SRC); FA0=$(felt "$db" FAKTA); BIO0=$(felt "$db" BIO)
G0=$(guard "$db")

# ---- Negative scenarier (basen ændres ikke) ----
MSHA=$(printf '0%.0s' {1..64}) nej "$db" fejlsha PRE_SHA
SSHA=$(printf '0%.0s' {1..64}) nej "$db" fejlsvarsha PRE_SHA
jvar "$tmp/m-alle-j.json" "$tmp/m-forkert-svar-sha.json" 'd["svar_sha256"]="1"*64'
MF="$tmp/m-forkert-svar-sha.json" nej "$db" manifest-svar-sha PRE_SHA
jvar "$tmp/m-alle-j.json" "$tmp/m-tekst.json" 'd["kort"][0]["kandidat"]["tekst_sha256"]="2"*64'
MF="$tmp/m-tekst.json" nej "$db" kandidattekst PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-version.json" 'd["kort"][1]["forventet_foer"]["identitet_version"]=3'
MF="$tmp/m-version.json" nej "$db" identitetsversion PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-status.json" 'd["kort"][2]["forventet_foer"]["identitet_status"]="unresolved"'
MF="$tmp/m-status.json" nej "$db" identitetsstatus PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-staged.json" 'd["kort"][0]["forventet_foer"]["staged"]=True'
MF="$tmp/m-staged.json" nej "$db" staged PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-kant.json" 'd["kort"][0]["forventet_foer"]["samme_som_kant"]=True'
MF="$tmp/m-kant.json" nej "$db" kant PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-oversigt.json" 'd["kort"][3]["oversigt"]["mention_sha256"]="3"*64'
MF="$tmp/m-oversigt.json" nej "$db" oversigtstekst PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-kontekst.json" 'd["kort"][0]["oversigt"]["kontekst_tekst_sha256"]="4"*64'
MF="$tmp/m-kontekst.json" nej "$db" kontekst PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-persona.json" 'd["kort"][1]["persona_key"]="U-9"'
MF="$tmp/m-persona.json" nej "$db" persona-nøgle PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-subjekt.json" 'd["kort"][3]["kandidat"]["person_id"]=-620103'
MF="$tmp/m-subjekt.json" nej "$db" kandidat-subjekt PRE_MANIFEST
jvar "$tmp/m-alle-j.json" "$tmp/m-kontrakt.json" 'd["contract"]="anden"'
MF="$tmp/m-kontrakt.json" nej "$db" kontrakt PRE_MANIFEST
svar "$tmp/mangler.txt" "K1 J" "K2 J" "K3 J"
jvar "$tmp/m-alle-j.json" "$tmp/m-mangler.json" 'd["svar_sha256"]="'"$(sha "$tmp/mangler.txt")"'"'
MF="$tmp/m-mangler.json" SV="$tmp/mangler.txt" nej "$db" svar-mangler PRE_SVAR
svar "$tmp/ukendt.txt" "K1 J" "K2 J" "K3 J" "K4 J" "K9 J"
jvar "$tmp/m-alle-j.json" "$tmp/m-ukendt.json" 'd["svar_sha256"]="'"$(sha "$tmp/ukendt.txt")"'"'
MF="$tmp/m-ukendt.json" SV="$tmp/ukendt.txt" nej "$db" svar-ukendt PRE_SVAR
svar "$tmp/dobbelt.txt" "K1 J" "K2 J" "K3 J" "K4 J" "K4 N"
jvar "$tmp/m-alle-j.json" "$tmp/m-dobbelt.json" 'd["svar_sha256"]="'"$(sha "$tmp/dobbelt.txt")"'"'
MF="$tmp/m-dobbelt.json" SV="$tmp/dobbelt.txt" nej "$db" svar-dobbelt PRE_SVAR
svar "$tmp/a-uden-id.txt" "K1 J" "K2 J" "K3 J" "K4 A"
jvar "$tmp/m-alle-j.json" "$tmp/m-a-uden-id.json" 'd["svar_sha256"]="'"$(sha "$tmp/a-uden-id.txt")"'"'
MF="$tmp/m-a-uden-id.json" SV="$tmp/a-uden-id.txt" nej "$db" svar-a-uden-id PRE_SVAR
svar "$tmp/a-ukendt.txt" "K1 J" "K2 J" "K3 J" "K4 A -999"
jvar "$tmp/m-alle-j.json" "$tmp/m-a-ukendt.json" 'd["svar_sha256"]="'"$(sha "$tmp/a-ukendt.txt")"'"'
MF="$tmp/m-a-ukendt.json" SV="$tmp/a-ukendt.txt" nej "$db" svar-a-ukendt-person PRE_MANIFEST
# Efterbetingelserne: forkerte forventninger ruller alt tilbage.
E_R=0 nej "$db" post-regel T6D2A_POST_REGEL
E_K=0 nej "$db" post-kanter T6D2A_POST_KVITTERING
E_I=2 nej "$db" post-identiteter T6D2A_POST_KVITTERING
# Fire N: også registreringen af N'erne er konsistent med efterbetingelserne (ikke-N ville ændre unresolved).
[ "$(maal "$db")" = "$f0" ] || fail "basen er ændret af de negative scenarier"

# ---- Alle J: kobling og tre identiteter ----
ok "${db}_go" go
grep -qx 'T6D2A_OK kanter=1 identiteter=3 regel=1' "$tmp/go.out" || fail "kvittering: $(cat "$tmp/go.out" | tail -3)"
[ "$(felt "${db}_go" fase)" = "data" ] || fail "fase efter: $(maal "${db}_go")"
[ "$(felt "${db}_go" regel)" = "1" ] && [ "$(felt "${db}_go" synlige_oversigt)" = "0" ] \
  && [ "$(felt "${db}_go" kanter_par)" = "1" ] && [ "$(felt "${db}_go" unresolved)" = "0" ] \
  && [ "$(felt "${db}_go" uden_identitet)" = "0" ] || fail "mål efter: $(maal "${db}_go")"
[ "$(felt "${db}_go" KOORD_2018_20)" = "$K0" ] && [ "$(felt "${db}_go" KOORD_SRC)" = "$KS0" ] || fail "koordinater ændret"
[ "$(felt "${db}_go" FAKTA)" = "$FA0" ] || fail "FAKTA ændret"
[ "$(felt "${db}_go" BIO)" != "$BIO0" ] || fail "BIO uændret: oversigtsomtalen skulle være skjult for læseren"
[ "$(v "${db}_go" "SELECT string_agg(sp.persona_key||':'||i.decision_status||':'||i.canonical_person_id||':'||i.version,',' ORDER BY sp.persona_key)
   FROM private.source_persona sp JOIN private.source_persona_identity i ON i.source_persona_id=sp.id WHERE sp.persona_key LIKE 'U-%'")" \
  = "U-2:accepted:-620102:3,U-3:accepted:-620103:1,U-4:accepted:-620104:1" ] || fail "identiteter"
[ "$(v "${db}_go" "SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND ((subjekt_id=-620105 AND objekt_id=-620101) OR (subjekt_id=-620101 AND objekt_id=-620105))")" = 1 ] \
  || fail "kant"
[ "$(v "${db}_go" "SELECT count(*) FROM public.change_set WHERE operation='identitet_ceremoni' AND summary='T6D2A_OK kanter=1 identiteter=3 regel=1'")" = 1 ] \
  || fail "kvitteringspost"
[ "$(v "${db}_go" "SELECT count(*) FROM public.change_event e JOIN public.change_set c ON c.id=e.change_set_id WHERE c.operation='identitet_ceremoni'")" = 0 ] \
  || fail "kvitteringen har hændelser"
[ "$(v "${db}_go" "SELECT coalesce(nullif(current_setting('app.change_set_id',true),''),'tom')")" = tom ] || fail "app.change_set_id ryddet"
# De to identiteter, der peger på personer med en eksisterende accepteret kilde-persona: medlemskabssættet og
# persona_family_context for de eksisterende personaer er uændrede.
[ "$(guard "${db}_go")" = "$G0" ] || fail "placement_membership_set / persona_family_context ændret"
# Genkørsel: kvitteringen findes.
if run "${db}_go" genk; then fail "genkørsel godtaget"; fi
grep -q 'T6D2A_PRE_FASE' "$tmp/genk.out" || fail "forventede T6D2A_PRE_FASE: $(kode genk)"

# ---- Blandet: A på en kobling og en identitet, N på ét, J på ét ----
MF="$tmp/m-blandet.json" SV="$tmp/blandet.txt" E_K=1 E_I=2 E_R=1 ok "${db}_mix" mix
grep -qx 'T6D2A_OK kanter=1 identiteter=2 regel=1' "$tmp/mix.out" || fail "kvittering (blandet): $(tail -3 "$tmp/mix.out")"
[ "$(v "${db}_mix" "SELECT string_agg(sp.persona_key||':'||coalesce(i.decision_status,'-')||':'||coalesce(i.canonical_person_id::text,'-'),',' ORDER BY sp.persona_key)
   FROM private.source_persona sp LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id WHERE sp.persona_key LIKE 'U-%'")" \
  = "U-2:accepted:-620107,U-3:-:-,U-4:accepted:-620104" ] || fail "identiteter (blandet)"
[ "$(v "${db}_mix" "SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND subjekt_id=-620105 AND objekt_id=-620102")" = 1 ] \
  || fail "kant (A)"
[ "$(felt "${db}_mix" unresolved)" = 0 ] && [ "$(felt "${db}_mix" uden_identitet)" = 1 ] || fail "mål (blandet): $(maal "${db}_mix")"

# ---- Fire N: intet skrevet, kvittering og fase data ----
MF="$tmp/m-fire-n.json" SV="$tmp/fire-n.txt" E_K=0 E_I=0 E_R=0 ok "${db}_n" n
grep -qx 'T6D2A_OK kanter=0 identiteter=0 regel=0' "$tmp/n.out" || fail "kvittering (fire N): $(tail -3 "$tmp/n.out")"
[ "$(felt "${db}_n" fase)" = "data" ] && [ "$(felt "${db}_n" unresolved)" = 1 ] && [ "$(felt "${db}_n" uden_identitet)" = 2 ] \
  && [ "$(felt "${db}_n" kanter_par)" = 0 ] || fail "mål (fire N): $(maal "${db}_n")"
[ "$(felt "${db}_n" FAKTA)" = "$FA0" ] && [ "$(felt "${db}_n" BIO)" = "$BIO0" ] || fail "fire N ændrede læserne"
[ "$(v "${db}_n" "SELECT count(*) FROM public.relation WHERE rolle='samme_som'")" = 0 ] || fail "fire N skrev en kant"
echo IDENTITET_CEREMONI_TEST_OK
