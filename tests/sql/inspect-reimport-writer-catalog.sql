\set ON_ERROR_STOP on

-- Stable, byte-comparable receipt for a fresh and a terminally upgraded
-- ledger.  This deliberately captures both object identity and its effective
-- security contract, rather than merely listing function names.
WITH targets AS (
  SELECT c.oid,c.relkind,n.nspname,c.relname,c.relowner,c.relacl,c.relrowsecurity,c.relforcerowsecurity
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='private' AND c.relname IN (
    'reimport_writer_profile','reimport_authorization','reimport_batch','reimport_event','reimport_name_completion_result',
    'reimport_1939_authorization','reimport_1939_write_batch','reimport_1939_write_event','reimport_1939_name_completion_result'
  )
), functions AS (
  SELECT p.oid,p.oid::regprocedure::text AS signature,r.rolname AS owner,p.prosecdef,
    coalesce(array_to_string(p.proconfig,','),'') AS config,
    encode(extensions.digest(convert_to(pg_get_functiondef(p.oid),'UTF8'),'sha256'),'hex') AS body_sha256
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_roles r ON r.oid=p.proowner
  WHERE (n.nspname='public' AND p.proname IN (
    'red_authorize_reimport','red_preflight_reimport_authorization','red_begin_reimport','red_apply_reimport_source_evidence','red_apply_reimport_person_create','red_apply_reimport_canonical_delta','red_finalize_reimport','red_reimport_batch_result',
    'red_authorize_reimport_reversal','red_reverse_reimport','red_authorize_reimport_cutover','red_activate_reimport_batch',
    'red_lock_reimport_name_completion','red_authorize_reimport_name_completion','red_preflight_reimport_name_completion',
    'red_begin_reimport_name_completion','red_apply_reimport_name_completion','red_finalize_reimport_name_completion',
    'red_authorize_1939_v50_reimport','red_begin_1939_v50_reimport','red_apply_1939_v50_source_evidence','red_apply_1939_v50_person_create',
    'red_apply_1939_v50_canonical_delta','red_finalize_1939_v50_reimport','red_authorize_1939_v50_reversal','red_reverse_1939_v50_reimport',
    'red_authorize_1939_v50_cutover','red_activate_1939_v50_batch','red_lock_1939_v50_name_completion',
    'red_authorize_1939_v50_name_completion','red_preflight_1939_v50_name_completion','red_begin_1939_v50_name_completion',
    'red_apply_1939_v50_name_completion','red_finalize_1939_v50_name_completion'
  )) OR (n.nspname='private' AND p.proname IN (
    'require_reimport_writer_editor','require_reimport_open_batch','lock_reimport_writer','validate_reimport_authorization_payload','validate_reimport_writer_config','ensure_reimport_source_evidence',
    'validate_reimport_name_completion','reject_reimport_writer_mutation',
    'reimport_canonical_json_text','reimport_canonical_json_sha256',
    'require_reimport_1939_editor','require_reimport_1939_open_batch',
    'ensure_reimport_1939_source_evidence','validate_reimport_1939_name_completion',
    'reject_reimport_1939_event_mutation','reimport_1939_canonical_json_text',
    'reimport_1939_canonical_json_sha256'
  ))
), rows AS (
  SELECT jsonb_build_object('kind','relation','name',nspname||'.'||relname,'relkind',relkind,
    'rls',relrowsecurity,'force_rls',relforcerowsecurity) row_value FROM targets
  UNION ALL
  SELECT jsonb_build_object('kind','column','table',target.nspname||'.'||target.relname,
    'ordinal',attribute.attnum,'name',attribute.attname,
    'type',format_type(attribute.atttypid,attribute.atttypmod),
    'not_null',attribute.attnotnull,'identity',attribute.attidentity::text,
    'generated',attribute.attgenerated::text,
    'collation',CASE WHEN attribute.attcollation=0 THEN ''
      ELSE collation_namespace.nspname||'.'||collation_row.collname END)
  FROM targets target
  JOIN pg_attribute attribute ON attribute.attrelid=target.oid
    AND attribute.attnum>0 AND NOT attribute.attisdropped
  LEFT JOIN pg_collation collation_row ON collation_row.oid=attribute.attcollation
  LEFT JOIN pg_namespace collation_namespace ON collation_namespace.oid=collation_row.collnamespace
  UNION ALL
  SELECT jsonb_build_object('kind','constraint','table',n.nspname||'.'||c.relname,
    'type',x.contype,'parent',coalesce(x.conparentid::regclass::text,''),'definition',pg_get_constraintdef(x.oid,true))
  FROM pg_constraint x JOIN pg_class c ON c.oid=x.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE x.conrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT jsonb_build_object('kind','policy','table',n.nspname||'.'||c.relname,'name',p.polname,
    'command',p.polcmd,'permissive',p.polpermissive,'roles',coalesce((SELECT string_agg(r.rolname,',' ORDER BY r.rolname) FROM pg_roles r WHERE r.oid=ANY(p.polroles)),''),
    'using',coalesce(pg_get_expr(p.polqual,p.polrelid),''),'check',coalesce(pg_get_expr(p.polwithcheck,p.polrelid),''))
  FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE p.polrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT jsonb_build_object('kind','default','table',n.nspname||'.'||c.relname,
    'column',a.attname,'expression',pg_get_expr(d.adbin,d.adrelid))
  FROM pg_attrdef d JOIN pg_class c ON c.oid=d.adrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  JOIN pg_attribute a ON a.attrelid=d.adrelid AND a.attnum=d.adnum
  WHERE d.adrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT jsonb_build_object('kind','owned_sequence','sequence',sn.nspname||'.'||s.relname,
    'table',tn.nspname||'.'||t.relname,'column',a.attname)
  FROM pg_class s JOIN pg_namespace sn ON sn.oid=s.relnamespace
  JOIN pg_depend d ON d.objid=s.oid AND d.deptype='a'
  JOIN pg_class t ON t.oid=d.refobjid JOIN pg_namespace tn ON tn.oid=t.relnamespace
  JOIN pg_attribute a ON a.attrelid=t.oid AND a.attnum=d.refobjsubid
  WHERE s.relkind='S' AND t.oid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT jsonb_build_object('kind','index','table',n.nspname||'.'||c.relname,
    'definition',regexp_replace(pg_get_indexdef(i.oid),'^CREATE( UNIQUE)? INDEX [^ ]+','CREATE\\1 INDEX'))
  FROM pg_index x JOIN pg_class i ON i.oid=x.indexrelid JOIN pg_class c ON c.oid=x.indrelid
  JOIN pg_namespace n ON n.oid=c.relnamespace WHERE x.indrelid IN (SELECT oid FROM targets)
  UNION ALL
  SELECT jsonb_build_object('kind','trigger','table',n.nspname||'.'||c.relname,
    'parent',coalesce(g.tgparentid::regclass::text,''),'definition',regexp_replace(pg_get_triggerdef(g.oid,true),'^CREATE TRIGGER [^ ]+','CREATE TRIGGER'))
  FROM pg_trigger g JOIN pg_class c ON c.oid=g.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE g.tgrelid IN (SELECT oid FROM targets) AND NOT g.tgisinternal
  UNION ALL
  SELECT jsonb_build_object('kind','table_grant','name',nspname||'.'||relname,'grantee',grantee.rolname,
    'privilege',grant_row.privilege_type,'grantable',grant_row.is_grantable)
  FROM targets CROSS JOIN LATERAL aclexplode(coalesce(relacl,acldefault(CASE WHEN relkind='S' THEN 'S'::"char" ELSE 'r'::"char" END,relowner))) grant_row
  JOIN pg_roles grantee ON grantee.oid=grant_row.grantee
  WHERE grantee.rolname IN ('anon','authenticated','service_role')
  UNION ALL
  SELECT jsonb_build_object('kind','function_grant','name',signature,'grantee',grantee.rolname,
    'privilege',grant_row.privilege_type,'grantable',grant_row.is_grantable)
  FROM functions CROSS JOIN LATERAL aclexplode(coalesce((SELECT proacl FROM pg_proc WHERE oid=functions.oid),acldefault('f'::"char",(SELECT proowner FROM pg_proc WHERE oid=functions.oid)))) grant_row
  JOIN pg_roles grantee ON grantee.oid=grant_row.grantee
  WHERE grantee.rolname IN ('anon','authenticated','service_role')
  UNION ALL
  SELECT jsonb_build_object('kind','function','name',signature,'owner',owner,'definer',prosecdef,'path',config,'body_sha256',body_sha256,
    'anon',has_function_privilege('anon',oid,'EXECUTE'),'authenticated',has_function_privilege('authenticated',oid,'EXECUTE'),
    'service_role',has_function_privilege('service_role',oid,'EXECUTE')) FROM functions
)
SELECT jsonb_agg(row_value ORDER BY row_value::text COLLATE "C") FROM rows;
