\set ON_ERROR_STOP on

-- Run on a disposable pre-identity baseline.  These default privileges model
-- a permissive Supabase owner; without artifact-local REVOKEs the new identity
-- sequences would be directly callable by API roles.
DO $pre_artifact_absence$
DECLARE v_sequence text;
BEGIN
  FOREACH v_sequence IN ARRAY ARRAY[
    'public.relation_id_seq','public.assertion_id_seq','public.conclusion_id_seq'
  ] LOOP
    IF to_regclass(v_sequence) IS NOT NULL THEN
      RAISE EXCEPTION 'C3_IDENTITY_SEQUENCE_PRE_ARTIFACT_PRESENT: %',v_sequence;
    END IF;
  END LOOP;
END $pre_artifact_absence$;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO PUBLIC, anon, authenticated;

CREATE SEQUENCE public.c3_identity_sequence_acl_premise;
DO $permissive_premise$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['PUBLIC','anon','authenticated'] LOOP
    IF (v_role='PUBLIC' AND 2 <> (
          SELECT count(DISTINCT a.privilege_type) FROM pg_class c
          CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('S',c.relowner))) a
          WHERE c.oid='public.c3_identity_sequence_acl_premise'::regclass
            AND a.grantee=0 AND a.privilege_type IN ('USAGE','SELECT')
        )) OR (v_role<>'PUBLIC' AND NOT (
          has_sequence_privilege(v_role,'public.c3_identity_sequence_acl_premise','USAGE')
          AND has_sequence_privilege(v_role,'public.c3_identity_sequence_acl_premise','SELECT')
        )) THEN
      RAISE EXCEPTION 'C3_IDENTITY_SEQUENCE_DEFAULT_ACL_PREMISE_MISSING: %',v_role;
    END IF;
  END LOOP;
END $permissive_premise$;
DROP SEQUENCE public.c3_identity_sequence_acl_premise;

\ir ../../db-migrations-c3-identity.sql

DO $acl$
DECLARE
  v_sequence text;
  v_role text;
BEGIN
  FOREACH v_sequence IN ARRAY ARRAY[
    'public.relation_id_seq','public.assertion_id_seq','public.conclusion_id_seq'
  ] LOOP
    FOREACH v_role IN ARRAY ARRAY['PUBLIC','anon','authenticated'] LOOP
      IF (v_role='PUBLIC' AND EXISTS (
            SELECT 1 FROM pg_class c
            CROSS JOIN LATERAL aclexplode(coalesce(c.relacl,acldefault('S',c.relowner))) a
            WHERE c.oid=v_sequence::regclass AND a.grantee=0
              AND a.privilege_type IN ('USAGE','SELECT','UPDATE')
          )) OR (v_role<>'PUBLIC' AND (
            has_sequence_privilege(v_role,v_sequence,'USAGE')
            OR has_sequence_privilege(v_role,v_sequence,'SELECT')
            OR has_sequence_privilege(v_role,v_sequence,'UPDATE')
          )) THEN
        RAISE EXCEPTION 'C3_IDENTITY_SEQUENCE_PRIVILEGE_EXPANDED: % %',v_role,v_sequence;
      END IF;
    END LOOP;
  END LOOP;
END $acl$;

DO $success$
BEGIN
  RAISE NOTICE 'OK: C3 identity sequences revoke permissive Supabase defaults';
END $success$;
