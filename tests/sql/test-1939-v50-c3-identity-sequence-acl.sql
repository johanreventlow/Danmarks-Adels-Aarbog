\set ON_ERROR_STOP on

-- Run on a disposable pre-identity baseline.  These default privileges model
-- a permissive Supabase owner; without artifact-local REVOKEs the new identity
-- sequences would be directly callable by API roles.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO PUBLIC, anon, authenticated;

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
