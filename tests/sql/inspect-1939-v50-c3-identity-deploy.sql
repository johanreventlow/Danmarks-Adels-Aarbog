\set ON_ERROR_STOP on
\pset tuples_only on
\pset format unaligned

-- Stable, one-record-per-line catalog serialization for the C3 deploy proof.
-- Variable-length catalog text is UTF-8 hex encoded so psql output is safe to
-- compare byte-for-byte with cmp(1) and contains no embedded line breaks.

WITH expected(proname) AS (
  VALUES
    ('identity_components_have_rejection'),
    ('cleanup_identity_relation_update_prelock'),
    ('lock_identity_people'),
    ('prelock_identity_relation_update'),
    ('_samme_som_gruppe'),
    ('_version_upsert_row'),
    ('enforce_samme_som_invariants'),
    ('red_apply_1939_v50_name_completion'),
    ('red_upsert_fakta'),
    ('red_tilfoej_oplysning'),
    ('red_opret_fakta'),
    ('red_set_konklusion'),
    ('red_edit_oplysning'),
    ('red_relation'),
    ('red_samme_som'),
    ('red_ikke_samme_som'),
    ('red_tilfoej_relation'),
    ('_ensure_foraeldrefamilie_redaktionel'),
    ('red_tilfoej_foraeldre_paastand'),
    ('red_vaelg_foraeldre'),
    ('red_slet_person')
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
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN expected e ON e.proname = p.proname
  WHERE n.nspname IN ('public', 'private')
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

SELECT concat_ws('|',
         'PROOF_CONSTRAINT',
         con.conname,
         con.contype,
         con.condeferrable::int,
         con.condeferred::int,
         con.convalidated::int,
         encode(convert_to(pg_get_constraintdef(con.oid, true), 'UTF8'), 'hex'))
FROM pg_constraint con
WHERE con.conrelid = to_regclass('private.identity_relation_update_prelock')
ORDER BY con.conname;

SELECT concat_ws('|',
         'PROOF_INDEX',
         i.relname,
         ix.indisunique::int,
         ix.indisprimary::int,
         ix.indisvalid::int,
         encode(convert_to(pg_get_indexdef(i.oid), 'UTF8'), 'hex'))
FROM pg_index ix
JOIN pg_class i ON i.oid = ix.indexrelid
WHERE ix.indrelid = to_regclass('private.identity_relation_update_prelock')
ORDER BY i.relname;

WITH touched_triggers(relid, tgname) AS (
  VALUES
    (to_regclass('private.identity_relation_update_prelock'),
     'trg_identity_relation_update_prelock_cleanup'),
    (to_regclass('public.relation'), 'trg_prelock_identity_relation_update'),
    (to_regclass('public.relation'), 'trg_samme_som_invariants')
)
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
JOIN touched_triggers x ON x.relid = t.tgrelid AND x.tgname = t.tgname
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
