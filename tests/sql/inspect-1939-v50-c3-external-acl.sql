\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- Stable whole-surface privilege records for the three externally reachable
-- role classes.  Sequences are explicit because the C3 additive path creates
-- three new identity sequences whose ACLs must not widen access.
WITH acl_rows AS (
  SELECT concat_ws('|','SURFACE_FUNCTION_ACL',
           format('%I.%I(%s)',n.nspname,p.proname,
                  pg_get_function_identity_arguments(p.oid)),
           CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
           x.privilege_type,x.is_grantable::int,pg_get_userbyid(x.grantor)) AS record,
         x.grantee
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(
    p.proacl,acldefault('f',p.proowner)
  )) x
  WHERE n.nspname IN ('public','private')

  UNION ALL

  SELECT concat_ws('|','SURFACE_TABLE_ACL',format('%I.%I',n.nspname,c.relname),
           CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
           x.privilege_type,x.is_grantable::int,pg_get_userbyid(x.grantor)),
         x.grantee
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(
    c.relacl,acldefault('r',c.relowner)
  )) x
  WHERE n.nspname IN ('public','private')
    AND c.relkind IN ('r','p','v','m','f')

  UNION ALL

  SELECT concat_ws('|','SURFACE_SEQUENCE_ACL',format('%I.%I',n.nspname,c.relname),
           CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
           x.privilege_type,x.is_grantable::int,pg_get_userbyid(x.grantor)),
         x.grantee
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(
    c.relacl,acldefault('S',c.relowner)
  )) x
  WHERE n.nspname IN ('public','private')
    AND c.relkind='S'
)
SELECT record
FROM acl_rows
WHERE grantee=0 OR pg_get_userbyid(grantee) IN ('anon','authenticated')
ORDER BY record;
