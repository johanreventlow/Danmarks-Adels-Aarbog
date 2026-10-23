-- Nøglede digests for 5a+5b-lagene (plan B1 Task 1). Læse-kun; ingen CREATE.
-- Hvert lag er en mængde rækker (nøgle k, indhold j) med en fast kolonneliste; derefter oversættes hver uuid i k og j via
-- nøglekortet (transfer_5ab_keymap.sql). En uuid, kortet ikke kender, bliver stående (så laget afviger mellem baser) og
-- tælles i n_uuid_unmapped. Base-bundne evidensnøgler udelades (se exk nedenfor).
--   -v src=<kilde>                 ⇒ én linje daa.transfer_5ab_digests={"<lag>":{"n":…,"sha256":…},…,"n_uuid_unmapped":…}
--   -v src=<kilde> -v mode=rows    ⇒ linjer <lag>|<nøgle>|<rækkesha> (bærer uuid'er, der ikke kan oversættes: 0600-fil)
--   -v src=<kilde> -v mode=unmapped ⇒ linjer <lag>|<tabel>.<nøgle>|<antal> for uoversatte uuid'er, uden selve uuid'erne
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL row_security=off;
\set t5_km_included 1
\ir transfer_5ab_keymap.sql
\unset t5_km_included
\if :{?mode}
\else
\set mode digests
\endif
SELECT set_config('daa.t5_src', :'src', true) AS s, set_config('daa.t5_mode', :'mode', true) AS m \gset t5_
DO $dg$
DECLARE
  src bigint:=current_setting('daa.t5_src')::bigint; mode text:=current_setting('daa.t5_mode');
  km jsonb:=current_setting('daa.t5_km')::jsonb;
  -- Base-bundne evidensnøgler (hver tilføjelse er en ruling: »base-bundet«).
  exk constant text:='ARRAY[''pack_sha256'',''state_sha256'',''preview_sha256'',''preview_hash'',''set_sha256'',''batch_id'',''manifest_sha256'',''supersedes_promotion_id'']';
  re constant text:='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
  -- tr(x): x med hver kendt uuid erstattet af sin nøgle; um(x): antal ukendte uuid'er i x.
  tr constant text:='(SELECT coalesce(string_agg(p.s||coalesce($1->>m.a[1], m.a[1], ''''), '''' ORDER BY p.o), '''')
    FROM regexp_split_to_table(%1$s, %2$L) WITH ORDINALITY p(s,o) LEFT JOIN regexp_matches(%1$s, %2$L, ''g'') WITH ORDINALITY m(a,o) ON m.o=p.o)';
  um constant text:='(SELECT count(*) FROM regexp_matches(%1$s, %2$L, ''g'') m(a) WHERE NOT ($1 ? m.a[1]))';
  -- Id-arrays i dispositionsevidens: sorteret efter oversættelsen (elementerne selv oversættes bagefter som resten).
  sorted_ev constant text:='coalesce((SELECT jsonb_object_agg(e.key, CASE WHEN jsonb_typeof(e.value)=''array''
      AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(e.value) x WHERE jsonb_typeof(x)<>''string'')
      THEN (SELECT coalesce(jsonb_agg(x ORDER BY coalesce($1->>x, x) COLLATE "C"), ''[]'') FROM jsonb_array_elements_text(e.value) x)
      ELSE e.value END) FROM jsonb_each(%s) e), ''{}''::jsonb)';
  r record; res jsonb:='{}'; out text:=''; unm bigint:=0; n bigint; h text; u bigint; lines text; fam bigint[]; famj jsonb;
  role0 text:=current_user;
BEGIN
  -- Familiekilderne som læseren ser dem (anon); familierne = mål for kildens bindinger.
  IF to_regclass('private.interpretation_promotion') IS NOT NULL
     AND to_regprocedure('public.public_family_sources(bigint[])') IS NOT NULL THEN
    SELECT coalesce(array_agg(DISTINCT p.target_id ORDER BY p.target_id), '{}') INTO fam FROM private.interpretation_promotion p
      JOIN private.interpretation i ON i.id=p.interpretation_id WHERE i.source_id=src AND p.target_type='family';
    EXECUTE 'SET LOCAL ROLE anon';
    SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]') INTO famj FROM public.public_family_sources(fam) f;
    EXECUTE format('SET LOCAL ROLE %I', role0);
  END IF;
  FOR r IN SELECT * FROM (VALUES
    ('personas', 'private.source_persona', '{private.source_persona,private.source_persona_mention}',
     'SELECT p.id::text k, jsonb_build_object(''persona_key'', p.persona_key, ''mentions'', coalesce((SELECT jsonb_agg(jsonb_build_object(
          ''mention_id'', m.mention_id, ''mention_role'', m.mention_role, ''ordinal'', m.ordinal)
          ORDER BY coalesce($1->>m.mention_id::text, m.mention_id::text) COLLATE "C", m.mention_role COLLATE "C", m.ordinal)
        FROM private.source_persona_mention m WHERE m.persona_id=p.id), ''[]'')) j
      FROM private.source_persona p WHERE p.source_id=$2'),
    ('identities', 'private.source_persona_identity', '{private.source_persona_identity}',
     'SELECT i.source_persona_id::text k, jsonb_build_object(''persona'', i.source_persona_id, ''canonical_person_id'', i.canonical_person_id,
        ''decision_status'', i.decision_status, ''version'', i.version, ''evidence'', i.evidence - %1$s, ''decided_by'', i.decided_by,
        ''decided_by_name'', i.decided_by_name) j
      FROM private.source_persona_identity i JOIN private.source_persona p ON p.id=i.source_persona_id WHERE p.source_id=$2'),
    ('identity_events', 'private.source_persona_identity_event', '{private.source_persona_identity_event}',
     'SELECT e.source_persona_id::text||''#''||e.version k, jsonb_build_object(''persona'', e.source_persona_id,
        ''canonical_person_id'', e.canonical_person_id, ''decision_status'', e.decision_status, ''version'', e.version,
        ''evidence'', e.evidence - %1$s, ''decided_by'', e.decided_by, ''decided_by_name'', e.decided_by_name) j
      FROM private.source_persona_identity_event e JOIN private.source_persona p ON p.id=e.source_persona_id WHERE p.source_id=$2'),
    ('candidate_runs', 'private.source_persona_identity_candidate_run', '{private.source_persona_identity_candidate_run}',
     'SELECT r.id::text k, jsonb_build_object(''run'', r.id, ''generator_version'', r.generator_version, ''config'', r.config,
        ''config_sha256'', r.config_sha256, ''input_spec'', r.input_spec, ''input_sha256'', r.input_sha256,
        ''candidates_sha256'', r.candidates_sha256, ''persona_count'', r.persona_count, ''candidate_count'', r.candidate_count,
        ''created_by'', r.created_by) j
      FROM private.source_persona_identity_candidate_run r WHERE r.source_id=$2'),
    ('candidates', 'private.source_persona_identity_candidate', '{private.source_persona_identity_candidate}',
     'SELECT c.id::text k, to_jsonb(c) - ''id'' j FROM private.source_persona_identity_candidate c
        JOIN private.source_persona_identity_candidate_run r ON r.id=c.run_id WHERE r.source_id=$2'),
    ('control_runs', 'private.identity_control_run', '{private.identity_control_run}',
     'SELECT c.id::text k, to_jsonb(c) - ARRAY[''id'',''source_id'',''created_at''] j FROM private.identity_control_run c WHERE c.source_id=$2'),
    ('control_samples', 'private.identity_control_sample', '{private.identity_control_sample}',
     'SELECT s.id::text k, to_jsonb(s) - ''id'' j FROM private.identity_control_sample s
        JOIN private.identity_control_run c ON c.id=s.control_run_id WHERE c.source_id=$2'),
    ('control_exclusions', 'private.identity_control_exclusion', '{private.identity_control_exclusion}',
     'SELECT x.control_run_id::text||'':''||x.source_persona_id k, to_jsonb(x) j FROM private.identity_control_exclusion x
        JOIN private.identity_control_run c ON c.id=x.control_run_id WHERE c.source_id=$2'),
    ('control_parent_cards', 'private.identity_control_parent_card', '{private.identity_control_parent_card}',
     'SELECT pc.id::text k, to_jsonb(pc) - ''id'' j FROM private.identity_control_parent_card pc
        JOIN private.identity_control_run c ON c.id=pc.control_run_id WHERE c.source_id=$2'),
    ('control_events', 'private.identity_control_event', '{private.identity_control_event}',
     'SELECT e.control_run_id::text||''#''||e.seq k, to_jsonb(e) - ''created_at'' j FROM private.identity_control_event e
        JOIN private.identity_control_run c ON c.id=e.control_run_id WHERE c.source_id=$2'),
    ('control_parent_events', 'private.identity_control_parent_event', '{private.identity_control_parent_event}',
     'SELECT e.card_id::text||''#''||e.seq k, to_jsonb(e) - ''created_at'' j FROM private.identity_control_parent_event e
        JOIN private.identity_control_parent_card pc ON pc.id=e.card_id JOIN private.identity_control_run c ON c.id=pc.control_run_id
       WHERE c.source_id=$2'),
    ('interpretations', 'private.interpretation', '{private.interpretation}',
     'SELECT i.id::text k, jsonb_build_object(''interpretation_key'', i.interpretation_key, ''version'', i.version, ''predicate'', i.predicate,
        ''interpretation_kind'', i.interpretation_kind, ''value'', i.value, ''schema_version'', i.schema_version,
        ''derivation_kind'', i.derivation_kind, ''confidence'', i.confidence, ''status'', i.status, ''method'', i.method,
        ''model_version'', i.model_version, ''prompt_version'', i.prompt_version, ''persona'', i.source_persona_id,
        ''supersedes_id'', i.supersedes_id, ''decision_evidence'', i.decision_evidence - %1$s, ''decided_by'', i.decided_by,
        ''decided_by_name'', i.decided_by_name) j
      FROM private.interpretation i WHERE i.source_id=$2'),
    ('parties', 'private.interpretation_party', '{private.interpretation_party}',
     'SELECT ip.interpretation_key::text||'':''||ip.party_role||''#''||ip.version k, to_jsonb(ip) - ARRAY[''origin_ref'',''created_at''] j
        FROM private.interpretation_party ip
       WHERE ip.interpretation_key IN (SELECT interpretation_key FROM private.interpretation WHERE source_id=$2)'),
    ('classifications', 'private.relation_classification_event', '{private.relation_classification_event}',
     'SELECT e.interpretation_key::text||''#''||e.seq k, jsonb_build_object(''interpretation_key'', e.interpretation_key, ''seq'', e.seq,
        ''interpretation_version'', e.interpretation_version, ''classification'', e.classification,
        ''evidence'', e.evidence - %1$s, ''created_by'', e.created_by) j
      FROM private.relation_classification_event e
     WHERE e.interpretation_key IN (SELECT interpretation_key FROM private.interpretation WHERE source_id=$2)'),
    ('dispositions', 'private.clause_disposition', '{private.clause_disposition,private.source_observation,private.source_record_occurrence,private.source_rendition}',
     format('SELECT d.observation_id::text||''#''||d.version k, jsonb_build_object(''observation_id'', d.observation_id, ''version'', d.version,
        ''disposition'', d.disposition, ''decided_by_kind'', d.decided_by_kind, ''decided_by'', d.decided_by,
        ''decided_by_name'', d.decided_by_name, ''evidence'', %s) j
      FROM private.clause_disposition d JOIN private.source_observation o ON o.id=d.observation_id
      JOIN private.source_record_occurrence oc ON oc.id=o.occurrence_id JOIN private.source_rendition rd ON rd.id=oc.rendition_id
     WHERE rd.source_id=$2', format(sorted_ev, '(coalesce(d.evidence,''{}'') - %1$s)'))),
    ('writer_profiles', 'private.reimport_writer_profile', '{private.reimport_writer_profile}',
     'SELECT w.profile_id k, jsonb_build_object(''profile_id'', w.profile_id, ''profile_version'', w.profile_version,
        ''profile_sha256'', w.profile_sha256, ''writer_config'', w.writer_config) j
      FROM private.reimport_writer_profile w WHERE w.source_id=$2'),
    ('bindings', 'private.interpretation_promotion', '{private.interpretation_promotion}',
     'SELECT p.id::text k, jsonb_build_object(''interpretation'', p.interpretation_id, ''target_type'', p.target_type,
        ''target_id'', p.target_id, ''rule_key'', p.rule_key, ''rule_version'', p.rule_version, ''evidence'', p.evidence - %1$s,
        ''promoted_by'', p.promoted_by) j
      FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id WHERE i.source_id=$2'),
    ('family_sources', 'public.public_family_sources', '{private.interpretation_promotion}',
     'SELECT (x->>''family_id'')||'':''||(x->>''slags'')||'':''||coalesce(x->>''source_record_ref'',''-'')||'':''||coalesce(x->>''counterpart_person_id'',''-'') k,
        x j FROM jsonb_array_elements(coalesce($3, ''[]'')) x'),
    ('authorizations_consumed', 'private.reimport_authorization', '{private.reimport_authorization}',
     'SELECT a.operation k, jsonb_build_object(''operation'', a.operation, ''n'', count(*),
        ''manifests'', CASE WHEN a.operation=''relation_persona''
          THEN jsonb_agg(a.manifest_sha256 ORDER BY a.manifest_sha256 COLLATE "C") END) j
      FROM private.reimport_authorization a WHERE a.source_id=$2 AND a.status=''consumed'' GROUP BY a.operation'),
    ('authorizations_issued', 'private.reimport_authorization', '{private.reimport_authorization}',
     'SELECT a.operation k, jsonb_build_object(''operation'', a.operation, ''n'', count(*)) j
      FROM private.reimport_authorization a WHERE a.source_id=$2 AND a.status=''issued'' GROUP BY a.operation'),
    ('counts', 'private.reimport_batch', '{private.reimport_batch,private.reimport_event,private.extraction_run,private.interpretation_promotion_batch,private.interpretation_promotion}',
     'SELECT k, jsonb_build_object(''n'', n) j FROM (
        SELECT ''reimport_batch:''||coalesce(b.profile_id,''-'')||'':''||b.status k, count(*) n FROM private.reimport_batch b
         WHERE b.source_id=$2 GROUP BY 1
        UNION ALL SELECT ''reimport_event:''||e.operation, count(*) FROM private.reimport_event e
          JOIN private.reimport_batch b ON b.id=e.batch_id WHERE b.source_id=$2 GROUP BY 1
        UNION ALL SELECT ''extraction_run:''||x.schema_version||'':''||x.extractor_version, count(*) FROM private.extraction_run x
         WHERE x.source_id=$2 GROUP BY 1
        UNION ALL SELECT ''interpretation_promotion_batch'', count(DISTINCT p.batch_id) FROM private.interpretation_promotion p
          JOIN private.interpretation i ON i.id=p.interpretation_id WHERE i.source_id=$2) c')
  ) v(lag, tabel, tabs, sql) LOOP
    IF NOT (SELECT bool_and(to_regclass(t) IS NOT NULL) FROM unnest(r.tabs::text[]) t) THEN
      res:=res||jsonb_build_object(r.lag, jsonb_build_object('n', 0, 'sha256', encode(sha256(''::bytea), 'hex')));
      CONTINUE;
    END IF;
    IF mode='unmapped' THEN
      EXECUTE format('WITH raw AS (%1$s) SELECT coalesce(string_agg(%2$L||''|''||%3$L||''.''||f||''|''||n, E''\n''
                        ORDER BY f COLLATE "C"), '''') FROM (SELECT f, sum(n) n FROM (
                        SELECT ''<nøgle>'' f, %4$s n FROM raw
                        UNION ALL SELECT e.key, %5$s FROM raw, jsonb_each(raw.j) e) a GROUP BY f HAVING sum(n)>0) b',
                     format(r.sql, exk), r.lag, replace(r.tabel, 'private.', ''), format(um, 'raw.k', re), format(um, 'e.value::text', re))
        INTO lines USING km, src, famj;
      IF lines<>'' THEN out:=out||lines||E'\n'; END IF;
      CONTINUE;
    END IF;
    EXECUTE format('WITH raw AS (%1$s), t AS (SELECT %2$s k, %3$s j, %4$s + %5$s u FROM raw),
                    l AS (SELECT k||''|''||encode(sha256(convert_to(j, ''UTF8'')), ''hex'') line, u FROM t)
                    SELECT count(*), encode(sha256(convert_to(coalesce(string_agg(line, E''\n'' ORDER BY line COLLATE "C"), ''''), ''UTF8'')), ''hex''),
                           coalesce(sum(u), 0), coalesce(string_agg(%6$L||''|''||line, E''\n'' ORDER BY line COLLATE "C"), '''') FROM l',
                   format(r.sql, exk), format(tr, 'raw.k', re), format(tr, 'raw.j::text', re), format(um, 'raw.k', re),
                   format(um, 'raw.j::text', re), r.lag)
      INTO n, h, u, lines USING km, src, famj;
    res:=res||jsonb_build_object(r.lag, jsonb_build_object('n', n, 'sha256', h));
    unm:=unm+u;
    IF lines<>'' THEN out:=out||lines||E'\n'; END IF;
  END LOOP;
  IF mode='digests' THEN out:='daa.transfer_5ab_digests='||(res||jsonb_build_object('n_uuid_unmapped', unm))::text;
  ELSIF mode NOT IN ('rows','unmapped') THEN RAISE EXCEPTION 'T5_DIGEST_MODE %', mode; END IF;
  PERFORM set_config('daa.t5_out', rtrim(out, E'\n'), true);
END $dg$;
SELECT l FROM regexp_split_to_table(current_setting('daa.t5_out'), E'\n') l WHERE l<>'' ORDER BY l COLLATE "C";
COMMIT;
