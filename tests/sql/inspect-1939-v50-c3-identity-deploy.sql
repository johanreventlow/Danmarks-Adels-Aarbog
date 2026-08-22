\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- Stable, one-record-per-line catalog serialization for the C3 deploy proof.
-- Variable-length catalog text is UTF-8 hex encoded so psql output is safe to
-- compare byte-for-byte with cmp(1) and contains no embedded line breaks.

-- Comparison cannot distinguish "missing at both endpoints" from parity.  Fail
-- before serialization if any reviewed object has disappeared.
DO $expected_inventory$
DECLARE
  v_missing text[];
BEGIN
  WITH expected(signature) AS (VALUES
    ('private.identity_components_have_rejection(bigint,bigint)'),
    ('private.cleanup_identity_relation_update_prelock()'),
    ('private.lock_identity_people(bigint[])'),
    ('private.prelock_identity_relation_update(jsonb,jsonb)'),
    ('public._samme_som_gruppe(bigint)'),
    ('public._version_upsert_row(text,jsonb)'),
    ('public.enforce_samme_som_invariants()'),
    ('public.red_apply_1939_v50_name_completion(uuid,text,jsonb)'),
    ('public.red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)'),
    ('public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text)'),
    ('public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text)'),
    ('public.red_set_konklusion(bigint)'),
    ('public.red_edit_oplysning(bigint,text,text,text)'),
    ('public.red_relation(text,bigint,text,bigint,text,text)'),
    ('public.red_samme_som(bigint,bigint)'),
    ('public.red_ikke_samme_som(bigint,bigint)'),
    ('public.red_tilfoej_relation(bigint,text,bigint,text,text)'),
    ('public._ensure_foraeldrefamilie_redaktionel(bigint,bigint)'),
    ('public.red_tilfoej_foraeldre_paastand(bigint,bigint,bigint,text,text,text)'),
    ('public.red_vaelg_foraeldre(bigint,text)'),
    ('public.red_slet_person(bigint)')
  )
  SELECT array_agg(signature ORDER BY signature) INTO v_missing
  FROM expected WHERE to_regprocedure(signature) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_DEPLOY_SERIALIZER_MISSING_FUNCTION: %',v_missing;
  END IF;

  WITH expected(relname) AS (VALUES
    ('public.relation'),('public.assertion'),('public.conclusion'),
    ('private.identity_relation_update_prelock')
  )
  SELECT array_agg(relname ORDER BY relname) INTO v_missing
  FROM expected WHERE to_regclass(relname) IS NULL;
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_DEPLOY_SERIALIZER_MISSING_TABLE: %',v_missing;
  END IF;

  WITH expected(relname,tgname) AS (VALUES
    ('private.identity_relation_update_prelock','trg_identity_relation_update_prelock_cleanup'),
    ('public.assertion','trg_assertion_regen'),
    ('public.assertion','trg_assertion_relation_target'),
    ('public.assertion','trg_log_assertion'),
    ('public.conclusion','trg_conclusion_regen'),
    ('public.conclusion','trg_conclusion_relation_target'),
    ('public.conclusion','trg_log_conclusion'),
    ('public.relation','trg_enforce_samme_som'),
    ('public.relation','trg_enforce_samme_som_update'),
    ('public.relation','trg_log_relation'),
    ('public.relation','trg_relation_evidence_delete')
  )
  SELECT array_agg(format('%s.%s',relname,tgname) ORDER BY relname,tgname)
    INTO v_missing
  FROM expected e
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_trigger t
    WHERE t.tgrelid=to_regclass(e.relname) AND t.tgname=e.tgname
      AND NOT t.tgisinternal
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_DEPLOY_SERIALIZER_MISSING_TRIGGER: %',v_missing;
  END IF;

  WITH expected(relname,conname) AS (VALUES
    ('private.identity_relation_update_prelock','identity_relation_update_prelock_pkey'),
    ('private.identity_relation_update_prelock','trg_identity_relation_update_prelock_cleanup'),
    ('public.assertion','assertion_date_certainty_chk'),
    ('public.assertion','assertion_pkey'),
    ('public.conclusion','conclusion_pkey'),
    ('public.conclusion','conclusion_target_type_target_id_key'),
    ('public.conclusion','conclusion_valgt_assertion_id_fkey'),
    ('public.relation','relation_pkey')
  )
  SELECT array_agg(format('%s.%s',relname,conname) ORDER BY relname,conname)
    INTO v_missing
  FROM expected e
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    WHERE c.conrelid=to_regclass(e.relname) AND c.conname=e.conname
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_DEPLOY_SERIALIZER_MISSING_CONSTRAINT: %',v_missing;
  END IF;

  WITH expected(relname,indexname) AS (VALUES
    ('private.identity_relation_update_prelock','identity_relation_update_prelock_pkey'),
    ('public.assertion','assertion_pkey'),
    ('public.assertion','ix_assertion_objekt'),
    ('public.assertion','ix_assertion_target'),
    ('public.conclusion','conclusion_pkey'),
    ('public.conclusion','conclusion_target_type_target_id_key'),
    ('public.conclusion','ix_conclusion_target'),
    ('public.relation','ix_relation_objekt'),
    ('public.relation','ix_relation_subjekt'),
    ('public.relation','relation_afbildet_uidx'),
    ('public.relation','relation_pkey')
  )
  SELECT array_agg(format('%s.%s',relname,indexname) ORDER BY relname,indexname)
    INTO v_missing
  FROM expected e
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_index ix JOIN pg_class i ON i.oid=ix.indexrelid
    WHERE ix.indrelid=to_regclass(e.relname) AND i.relname=e.indexname
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_DEPLOY_SERIALIZER_MISSING_INDEX: %',v_missing;
  END IF;

  WITH expected(relname) AS (VALUES
    ('public.relation'),('public.assertion'),('public.conclusion')
  )
  SELECT array_agg(relname ORDER BY relname) INTO v_missing
  FROM expected e
  WHERE pg_get_serial_sequence(e.relname,'id') IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM pg_attribute a
       WHERE a.attrelid=to_regclass(e.relname) AND a.attname='id'
         AND a.attidentity='d'
     );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'C3_DEPLOY_SERIALIZER_MISSING_IDENTITY_SEQUENCE: %',v_missing;
  END IF;
END $expected_inventory$;

WITH expected(signature) AS (
  VALUES
    ('private.identity_components_have_rejection(bigint,bigint)'),
    ('private.cleanup_identity_relation_update_prelock()'),
    ('private.lock_identity_people(bigint[])'),
    ('private.prelock_identity_relation_update(jsonb,jsonb)'),
    ('public._samme_som_gruppe(bigint)'),
    ('public._version_upsert_row(text,jsonb)'),
    ('public.enforce_samme_som_invariants()'),
    ('public.red_apply_1939_v50_name_completion(uuid,text,jsonb)'),
    ('public.red_upsert_fakta(text,bigint,text,text,date,date,text,text,text)'),
    ('public.red_tilfoej_oplysning(bigint,text,date,date,text,text,text)'),
    ('public.red_opret_fakta(text,bigint,text,text,date,date,text,text,text)'),
    ('public.red_set_konklusion(bigint)'),
    ('public.red_edit_oplysning(bigint,text,text,text)'),
    ('public.red_relation(text,bigint,text,bigint,text,text)'),
    ('public.red_samme_som(bigint,bigint)'),
    ('public.red_ikke_samme_som(bigint,bigint)'),
    ('public.red_tilfoej_relation(bigint,text,bigint,text,text)'),
    ('public._ensure_foraeldrefamilie_redaktionel(bigint,bigint)'),
    ('public.red_tilfoej_foraeldre_paastand(bigint,bigint,bigint,text,text,text)'),
    ('public.red_vaelg_foraeldre(bigint,text)'),
    ('public.red_slet_person(bigint)')
), functions AS (
  SELECT
    p.oid,
    format('%I.%I(%s)', n.nspname, p.proname,
           pg_get_function_identity_arguments(p.oid)) AS signature,
    pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef,
    p.provolatile,
    p.proparallel,
    COALESCE(array_to_string(p.proconfig, E'\n'), '') AS proconfig,
    pg_get_functiondef(p.oid) AS definition
  FROM expected e
  JOIN pg_proc p ON p.oid=to_regprocedure(e.signature)
  JOIN pg_namespace n ON n.oid = p.pronamespace
)
SELECT concat_ws('|',
         'TOUCHED_FUNCTION',
         signature,
         owner_name,
         prosecdef::int,
         provolatile,
         proparallel,
         encode(convert_to(proconfig, 'UTF8'), 'hex'),
         encode(convert_to(definition, 'UTF8'), 'hex'))
FROM functions
ORDER BY signature;

WITH touched_tables(nspname, relname) AS (
  VALUES
    ('public', 'relation'),
    ('public', 'assertion'),
    ('public', 'conclusion'),
    ('private', 'identity_relation_update_prelock')
)
SELECT concat_ws('|',
         'TOUCHED_TABLE',
         format('%I.%I', n.nspname, c.relname),
         pg_get_userbyid(c.relowner),
         c.relkind,
         c.relrowsecurity::int,
         c.relforcerowsecurity::int,
         c.relpersistence)
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN touched_tables t ON t.nspname = n.nspname AND t.relname = c.relname
ORDER BY n.nspname, c.relname;

WITH touched_tables(nspname, relname) AS (
  VALUES
    ('public', 'relation'),
    ('public', 'assertion'),
    ('public', 'conclusion'),
    ('private', 'identity_relation_update_prelock')
)
SELECT concat_ws('|',
         'TOUCHED_COLUMN',
         format('%I.%I', n.nspname, c.relname),
         a.attnum,
         a.attname,
         format_type(a.atttypid, a.atttypmod),
         a.attnotnull::int,
         a.attidentity,
         COALESCE(encode(convert_to(pg_get_expr(d.adbin, d.adrelid), 'UTF8'), 'hex'), ''))
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN touched_tables t ON t.nspname = n.nspname AND t.relname = c.relname
JOIN pg_attribute a ON a.attrelid = c.oid
LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
WHERE a.attnum > 0 AND NOT a.attisdropped
ORDER BY n.nspname, c.relname, a.attnum;

WITH identity_tables(nspname,relname,attname) AS (
  VALUES
    ('public','relation','id'),
    ('public','assertion','id'),
    ('public','conclusion','id')
), identity_sequences AS (
  SELECT t.nspname AS table_schema,
         t.relname AS table_name,
         t.attname AS column_name,
         seq.oid AS sequence_oid,
         sn.nspname AS sequence_schema,
         seq.relname AS sequence_name,
         seq.relowner,
         seq.relpersistence,
         s.seqtypid,
         s.seqstart,
         s.seqincrement,
         s.seqmax,
         s.seqmin,
         s.seqcache,
         s.seqcycle,
         dep.deptype
  FROM identity_tables t
  JOIN pg_class tab ON tab.oid=to_regclass(format('%I.%I',t.nspname,t.relname))
  JOIN pg_attribute a ON a.attrelid=tab.oid AND a.attname=t.attname
  JOIN pg_class seq ON seq.oid=to_regclass(pg_get_serial_sequence(
                              format('%I.%I',t.nspname,t.relname),t.attname))
  JOIN pg_namespace sn ON sn.oid=seq.relnamespace
  JOIN pg_sequence s ON s.seqrelid=seq.oid
  JOIN pg_depend dep ON dep.classid='pg_class'::regclass
                    AND dep.objid=seq.oid
                    AND dep.refclassid='pg_class'::regclass
                    AND dep.refobjid=tab.oid
                    AND dep.refobjsubid=a.attnum
                    AND dep.deptype='i'
)
SELECT concat_ws('|',
         'IDENTITY_SEQUENCE',
         format('%I.%I.%I',table_schema,table_name,column_name),
         format('%I.%I',sequence_schema,sequence_name),
         pg_get_userbyid(relowner),
         relpersistence,
         format_type(seqtypid,NULL),
         seqstart,
         seqincrement,
         seqmin,
         seqmax,
         seqcache,
         seqcycle::int,
         deptype)
FROM identity_sequences
ORDER BY table_schema,table_name,column_name;

WITH identity_tables(nspname,relname,attname) AS (
  VALUES
    ('public','relation','id'),
    ('public','assertion','id'),
    ('public','conclusion','id')
), identity_sequences AS (
  SELECT t.nspname AS table_schema,
         t.relname AS table_name,
         t.attname AS column_name,
         seq.oid,
         seq.relowner,
         sn.nspname AS sequence_schema,
         seq.relname AS sequence_name
  FROM identity_tables t
  JOIN pg_class seq ON seq.oid=to_regclass(pg_get_serial_sequence(
                              format('%I.%I',t.nspname,t.relname),t.attname))
  JOIN pg_namespace sn ON sn.oid=seq.relnamespace
)
SELECT concat_ws('|',
         'IDENTITY_SEQUENCE_ACL',
         format('%I.%I.%I',table_schema,table_name,column_name),
         format('%I.%I',sequence_schema,sequence_name),
         CASE WHEN x.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
         x.privilege_type,
         x.is_grantable::int,
         pg_get_userbyid(x.grantor))
FROM identity_sequences s
CROSS JOIN LATERAL aclexplode(COALESCE(
  (SELECT c.relacl FROM pg_class c WHERE c.oid=s.oid),
  acldefault('S',s.relowner)
)) x
ORDER BY table_schema,table_name,column_name,x.grantee,x.privilege_type,x.grantor;

-- is_called changes the next generated ID even when last_value is identical, so
-- state is read from each sequence relation rather than pg_sequences alone.
WITH identity_tables(nspname,relname,attname) AS (
  VALUES
    ('public','relation','id'),
    ('public','assertion','id'),
    ('public','conclusion','id')
), identity_sequences AS (
  SELECT t.nspname AS table_schema,
         t.relname AS table_name,
         t.attname AS column_name,
         sn.nspname AS sequence_schema,
         seq.relname AS sequence_name
  FROM identity_tables t
  JOIN pg_class seq ON seq.oid=to_regclass(pg_get_serial_sequence(
                              format('%I.%I',t.nspname,t.relname),t.attname))
  JOIN pg_namespace sn ON sn.oid=seq.relnamespace
)
SELECT format(
  'SELECT concat_ws(''|'',''IDENTITY_SEQUENCE_STATE'',%L,%L,last_value,is_called::int) FROM %I.%I;',
  format('%I.%I.%I',table_schema,table_name,column_name),
  format('%I.%I',sequence_schema,sequence_name),
  sequence_schema,sequence_name)
FROM identity_sequences
ORDER BY table_schema,table_name,column_name
\gexec

SELECT concat_ws('|',
         'TOUCHED_CONSTRAINT',
         format('%I.%I',n.nspname,c.relname),
         con.conname,
         con.contype,
         con.condeferrable::int,
         con.condeferred::int,
         con.convalidated::int,
         encode(convert_to(pg_get_constraintdef(con.oid, true), 'UTF8'), 'hex'))
FROM pg_constraint con
JOIN pg_class c ON c.oid=con.conrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE (n.nspname,c.relname) IN (
  ('public','relation'),('public','assertion'),('public','conclusion'),
  ('private','identity_relation_update_prelock')
)
ORDER BY n.nspname,c.relname,con.conname;

SELECT concat_ws('|',
         'TOUCHED_INDEX',
         format('%I.%I',n.nspname,c.relname),
         i.relname,
         ix.indisunique::int,
         ix.indisprimary::int,
         ix.indisvalid::int,
         encode(convert_to(pg_get_indexdef(i.oid), 'UTF8'), 'hex'))
FROM pg_index ix
JOIN pg_class i ON i.oid = ix.indexrelid
JOIN pg_class c ON c.oid=ix.indrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE (n.nspname,c.relname) IN (
  ('public','relation'),('public','assertion'),('public','conclusion'),
  ('private','identity_relation_update_prelock')
)
ORDER BY n.nspname,c.relname,i.relname;

SELECT concat_ws('|',
         'TOUCHED_TRIGGER',
         format('%I.%I', n.nspname, c.relname),
         t.tgname,
         t.tgenabled,
         t.tgisinternal::int,
         t.tgtype,
         encode(convert_to(pg_get_triggerdef(t.oid, true), 'UTF8'), 'hex'))
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE NOT t.tgisinternal
  AND (n.nspname,c.relname) IN (
    ('public','relation'),('public','assertion'),('public','conclusion'),
    ('private','identity_relation_update_prelock')
  )
ORDER BY n.nspname, c.relname, t.tgname;

-- Direct/effective ACL rows for every function in the two application schemas.
-- acldefault is expanded when proacl is NULL, exposing unexpected PUBLIC
-- execution rather than treating a NULL ACL as no grant.
SELECT concat_ws('|',
         'SURFACE_FUNCTION_ACL',
         format('%I.%I(%s)', n.nspname, p.proname,
                pg_get_function_identity_arguments(p.oid)),
         CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
         x.privilege_type,
         x.is_grantable::int,
         pg_get_userbyid(x.grantor))
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) x
WHERE n.nspname IN ('public', 'private')
ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid),
         x.grantee, x.privilege_type, x.grantor;

-- Whole-surface table ACL serialization, including SELECT and every DML-class
-- privilege, for PUBLIC/anon/authenticated expansion review.
SELECT concat_ws('|',
         'SURFACE_TABLE_ACL',
         format('%I.%I', n.nspname, c.relname),
         CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END,
         x.privilege_type,
         x.is_grantable::int,
         pg_get_userbyid(x.grantor))
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl, acldefault('r', c.relowner))) x
WHERE n.nspname IN ('public', 'private')
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY n.nspname, c.relname, x.grantee, x.privilege_type, x.grantor;

SELECT concat_ws('|',
         'SURFACE_POLICY',
         schemaname,
         tablename,
         policyname,
         permissive,
         array_to_string(roles, ','),
         cmd,
         COALESCE(encode(convert_to(qual, 'UTF8'), 'hex'), ''),
         COALESCE(encode(convert_to(with_check, 'UTF8'), 'hex'), ''))
FROM pg_policies
WHERE schemaname IN ('public', 'private')
ORDER BY schemaname, tablename, policyname;
