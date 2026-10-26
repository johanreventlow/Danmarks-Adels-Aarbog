-- #248 skridt 1 (se fix_248_identitet.sql): læsemåling. Udskriver en linje pr. sag med id'er og antal og til sidst
-- `FIX248 fase=<foer|efter|ukendt>`. Brug (læsetransaktion): psql -X -At -v ON_ERROR_STOP=1 -v src=1 -f fix_248_maal.sql
\set QUIET on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
WITH v(linje, ik, sp, pp, bp, up, fid, ufid, soeskende_ik) AS (VALUES
  (1, '613f3d20-863c-5109-936b-95c91233c7a6'::uuid, '5e2c4e89-763c-5804-9587-230d09f6d4f9'::uuid, 94::bigint, 624::bigint, 625::bigint,
      64::bigint, 65::bigint, '0c785da9-3323-5f35-9e16-51dff01517f1'::uuid),
  (2, '7f9e119d-3c84-5c2f-9d5f-81e2e67a6893'::uuid, '07a3dfe2-ec4d-55ca-aa7d-66691b6b05b6'::uuid, 286::bigint, 744::bigint, 745::bigint,
      193::bigint, 194::bigint, '1db74c8b-33f4-501c-95f5-5382c37c3399'::uuid)),
m AS (
  SELECT v.*,
    (SELECT i.canonical_person_id FROM private.source_persona_identity i WHERE i.source_persona_id=v.sp AND i.decision_status='accepted') person,
    (SELECT i.version FROM private.source_persona_identity i WHERE i.source_persona_id=v.sp) version,
    (SELECT (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint FROM private.interpretation_current ic
      WHERE ic.interpretation_key=v.ik AND ic.status='accepted') tilstand_fam,
    (SELECT count(*) FROM private.interpretation_current ic JOIN private.interpretation_promotion x ON x.interpretation_id=ic.id AND x.target_type='family'
      WHERE ic.interpretation_key=v.ik AND x.evidence->>'state_sha256'=private.reimport_canonical_json_sha256(private.relation_binding_state(ic.id))) gaeldende,
    (SELECT count(*) FROM private.interpretation_current ic JOIN private.interpretation_promotion x ON x.interpretation_id=ic.id AND x.target_type='family'
      WHERE ic.interpretation_key=v.soeskende_ik AND x.target_id=v.fid
        AND x.evidence->>'state_sha256'=private.reimport_canonical_json_sha256(private.relation_binding_state(ic.id))) soeskende,
    (SELECT count(*) FROM public.public_family_sources(ARRAY[v.fid]) s WHERE s.counterpart_person_id=v.bp) kilder_fid,
    (SELECT count(*) FROM public.public_family_sources(ARRAY[v.ufid]) s WHERE s.counterpart_person_id=v.up) kilder_ufid
    FROM v),
f AS (
  SELECT m.*, CASE
    WHEN person=bp AND version=1 AND tilstand_fam=fid AND gaeldende=1 AND soeskende=1 AND kilder_fid=2 AND kilder_ufid=0 THEN 'foer'
    WHEN person=up AND version=2 AND tilstand_fam=ufid AND gaeldende=0 AND soeskende=1 AND kilder_fid=1 AND kilder_ufid=0 THEN 'efter'
    ELSE 'ukendt' END fase
    FROM m)
SELECT string_agg(format('linje=%s person=%s version=%s tilstand_fam=%s gaeldende=%s soeskende=%s kilder_fid=%s kilder_ufid=%s fase=%s',
                         linje, person, version, tilstand_fam, gaeldende, soeskende, kilder_fid, kilder_ufid, fase), E'\n' ORDER BY linje)
       ||E'\nFIX248 fase='||CASE WHEN bool_and(fase='foer') THEN 'foer' WHEN bool_and(fase='efter') THEN 'efter' ELSE 'ukendt' END
  FROM f;
COMMIT;
