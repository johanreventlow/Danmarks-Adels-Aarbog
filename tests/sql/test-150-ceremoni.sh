#!/usr/bin/env bash
# #150 trin 5c-1 (plan Task 6): placement-ceremonien (fix_150_placement.sql) ende-til-ende på en syntetisk mini-kilde
# (fixtures/ceremoni-150.sql + fixtures/manifest-150.json), kaldt med -v-variabler som runneren gør. Kontrakt v2 som
# prod (samme basisopskrift som familiekilde-testene). Brug: bash tests/sql/test-150-ceremoni.sh <basenavn>
set -euo pipefail
db=${1:?database}
S=.claude/skills/daa-extract/scripts
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 "$@"; }
v() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -c "$2"; }
fail() { echo "CEREMONI150_TEST_FAILED: $*" >&2; exit 1; }

createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql tests/sql/1939-v50-writer-bootstrap.sql; do
  q -d "$db" -f "$f" >/dev/null; done
q -d "$db" -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT' >/dev/null
q -d "$db" -f db-rls.sql >/dev/null
(cd tests/sql/fixtures && q -d "$db" -f ceremoni-150.sql >/dev/null)
[ "$(v "$db" "SELECT public.narrative_record_contract_version()")" = "2" ] || fail "kontrakt v2"

M=tests/sql/fixtures/manifest-150.json
echo '{"sheet_sha256":"'"$(printf x | shasum -a 256 | cut -c1-64)"'","record_keys":[]}' > "$tmp/ingen.json"
echo '{"sheet_sha256":"'"$(printf y | shasum -a 256 | cut -c1-64)"'","record_keys":["I-3"]}' > "$tmp/i3.json"
sha() { shasum -a 256 "$1" | cut -c1-64; }
# ceremoni <base> <afgørelsesfil> <placements> <revalideret> → stdout+stderr til $tmp/<base>.out
ceremoni() {
  env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -d "$1" -v actor=a1500000-0000-0000-0000-000000000150 -v src=-1550 \
    -v manifest_path="$M" -v approvals_path="$2" -v manifest_sha="$(sha "$M")" -v approvals_sha="$(sha "$2")" -v go=deadbeef \
    -v rendition_sha="$(printf '2%.0s' {1..64})" -v expect_headers=3 -v expect_placements="$3" -v expect_published=2 \
    -v expect_bindings=3 -v expect_ledger=4 -v expect_revalidated="$4" -f $S/fix_150_placement.sql > "$tmp/$1.out" 2>&1
}
fase() { env -u PGOPTIONS psql -X -At -v ON_ERROR_STOP=1 -v src=-1550 -d "$1" -f $S/fix_150_maal.sql | tail -1; }
for c in neg go genk human fortryd; do createdb -T "$db" "${db}_$c"; done

# FIX150_PRE_IDENTITY: identiteten på den unresolved post (I-3, draft) peger på en anden person end bindingen → stop
# før skrivning.
q -d "${db}_neg" >/dev/null <<'SQL'
BEGIN;
INSERT INTO public.person(id) VALUES (-155099);
WITH p AS (SELECT spm.persona_id FROM private.source_record sr
             JOIN private.source_record_anchor_current ac ON ac.source_record_id=sr.id
             JOIN private.source_observation o ON o.occurrence_id=ac.occurrence_id AND o.parent_observation_id IS NULL
             JOIN private.source_mention sm ON sm.observation_id=o.id
             JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
            WHERE sr.source_id=-1550 AND sr.record_key='I-3')
INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
  decided_by,decided_by_name,decided_at)
SELECT persona_id,-155099,'accepted',2,'{"fixture":"neg"}','a1500000-0000-0000-0000-000000000150','fixture','2026-10-27' FROM p;
UPDATE private.source_persona_identity i SET canonical_person_id=-155099,version=2,evidence='{"fixture":"neg"}',
  decided_at='2026-10-27' FROM private.source_persona_identity_event e
 WHERE e.source_persona_id=i.source_persona_id AND e.version=2;
COMMIT;
SQL
if ceremoni "${db}_neg" "$tmp/ingen.json" 2 2; then fail "manipuleret identitet godtaget"; fi
grep -q 'FIX150_PRE_IDENTITY' "$tmp/${db}_neg.out" || fail "forventede FIX150_PRE_IDENTITY: $(grep -o 'FIX150_[A-Z_]*' "$tmp/${db}_neg.out" | head -1)"
[ "$(fase "${db}_neg")" = "FIX150 ddl=efter fase=foer" ] || fail "negativen skrev"

# $revalider_to_i_traek$: to publicerede revalideres i samme transaktion; begge published, 0 stale; ledger 4 gældende;
# memberships for de 2 egnede.
[ "$(fase "${db}_go")" = "FIX150 ddl=efter fase=foer" ] || fail "fase før"
ceremoni "${db}_go" "$tmp/ingen.json" 2 2 || fail "ceremoni: $(grep -o 'FIX150_[A-Z_]*[^:]*' "$tmp/${db}_go.out" | head -1)"
grep -q '^FIX150_OK headers=3 placements=2 ledger=4 memberships=2 revalideret=2$' "$tmp/${db}_go.out" || fail "kvittering"
[ "$(fase "${db}_go")" = "FIX150 ddl=efter fase=bundet" ] || fail "fase efter: $(fase "${db}_go")"
[ "$(v "${db}_go" "SELECT count(*) FILTER (WHERE s->>'publication_status'='published')||'/'||count(*) FILTER (WHERE s->>'publication_status'='stale_published')
       FROM public.person_external_id pe, LATERAL private.narrative_record_state(pe.person_id,pe.source_id,pe.record_key) s WHERE pe.source_id=-1550")" = "2/0" ] \
  || fail "publicering efter"
[ "$(v "${db}_go" "SELECT string_agg(disposition,',' ORDER BY person_id) FROM private.legacy_placement_disposition_current WHERE is_current")" \
  = "retained_legacy,unresolved,mapped,mapped" ] || fail "ledger"

# Genkørsel → FIX150_PRE_FASE.
ceremoni "${db}_genk" "$tmp/ingen.json" 2 2 || fail "første kørsel (genk)"
if ceremoni "${db}_genk" "$tmp/ingen.json" 2 2; then fail "genkørsel godtaget"; fi
grep -q 'FIX150_PRE_FASE' "$tmp/${db}_genk.out" || fail "forventede FIX150_PRE_FASE"

# Godkendt i token-filen (I-3): tre placements; draften revalideres ikke (den var aldrig publiceret).
ceremoni "${db}_human" "$tmp/i3.json" 3 2 || fail "ceremoni m. godkendelse: $(grep -o 'FIX150_[A-Z_]*' "$tmp/${db}_human.out" | head -1)"
[ "$(v "${db}_human" "SELECT evidence->>'basis' FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id
       WHERE r.record_key='I-3' AND r.source_id=-1550")" = "human_group_review" ] || fail "godkendt post bærer ikke basis"

# $fortryd_en_post$: runbookens manuelle rækkefølge for I-2 ender med published og 0 stale.
ceremoni "${db}_fortryd" "$tmp/ingen.json" 2 2 || fail "ceremoni (fortryd)"
q -d "${db}_fortryd" >/dev/null <<'SQL' || fail "fortrydelse"
BEGIN;
SELECT set_config('request.jwt.claim.sub','a1500000-0000-0000-0000-000000000150',true);
CREATE TEMP TABLE f ON COMMIT DROP AS
SELECT pp.id AS pp, rp.id AS rp, l.lineage_id
  FROM private.source_record r JOIN private.source_record_placement rp ON rp.source_record_id=r.id
  JOIN private.source_persona_placement pp ON pp.record_placement_id=rp.id
  JOIN public.person_lineage_membership l ON l.person_id=-155002
 WHERE r.source_id=-1550 AND r.record_key='I-2';
GRANT SELECT ON f TO authenticated;
SET LOCAL ROLE authenticated;
SELECT public.red_reverse_placement_membership(-155002,(SELECT lineage_id FROM f),'fortryd I-2 (test)');
SELECT set_config('app.change_set_id','',true);
SELECT public.red_decide_source_persona_placement((SELECT pp FROM f),1,'superseded','{"basis":"fortryd"}');
SELECT public.red_decide_source_record_placement((SELECT rp FROM f),1,'superseded','{"basis":"fortryd"}');
SELECT set_config('app.change_set_id','',true);
RESET ROLE;
SELECT private.narrative_record_state(-155002,-1550,'I-2')->>'state_sha256' AS h \gset
SET LOCAL ROLE authenticated;
SELECT public.red_revalider_person_narrative_record(-155002,-1550,'I-2',:'h');
SELECT set_config('app.change_set_id','',true);
RESET ROLE;
SELECT private.record_legacy_disposition(-155002,-1550,'unresolved',NULL,'{"basis":"fortryd"}');
DO $c$ BEGIN
  IF (SELECT private.narrative_record_state(-155002,-1550,'I-2')->>'publication_status')<>'published'
     OR EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE person_id=-155002)
     OR (SELECT disposition FROM private.legacy_placement_disposition_current WHERE person_id=-155002)<>'unresolved'
     OR NOT (SELECT is_current FROM private.legacy_placement_disposition_current WHERE person_id=-155002) THEN
    RAISE EXCEPTION 'FORTRYD_FAILED'; END IF;
END $c$;
COMMIT;
SQL
echo CEREMONI150_TEST_OK
