-- Uberørt-hash og andre kilder for 5a+5b-overførslen (plan B1 Task 2). Læse-kun; ingen CREATE.
-- daa.transfer_5ab_untouched: som transfer_untouched_hash.sql (alle tabeller i public/private og deres sekvenser), men minus
--   de tabeller, 5a+5b-kæden skriver i (kortlægningen §B) og sekvenser ejet af dem.
-- daa.transfer_5ab_other_sources: for hver af de udelukkede tabeller de rækker, hvis kilde ikke er src (direkte via
--   source_id eller via join), så en skrivning i en anden kilde stadig opdages.
-- Brug: psql -v src=<kilde> -f transfer_5ab_untouched_hash.sql ⇒ to linjer »daa.transfer_5ab_<navn>=<sha256>«.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL row_security=off;
SELECT set_config('daa.t5_src', :'src', true) AS s \gset t5_
DO $uh$
DECLARE
  src bigint:=current_setting('daa.t5_src')::bigint; r record; h text; acc text:=''; oth text:='';
  -- (tabel, udtryk for rækkens kilde, rækken hedder x). Rækkefølgen er ligegyldig; hashen sorterer.
  chain constant text[][]:=ARRAY[
    ['private.reimport_writer_profile', 'x.source_id'],
    ['private.reimport_authorization', 'x.source_id'],
    ['private.reimport_batch', 'x.source_id'],
    ['private.reimport_event', '(SELECT b.source_id FROM private.reimport_batch b WHERE b.id=x.batch_id)'],
    ['private.extraction_run', 'x.source_id'],
    ['private.source_persona', 'x.source_id'],
    ['private.source_mention', '(SELECT rd.source_id FROM private.source_observation o JOIN private.source_record_occurrence oc ON oc.id=o.occurrence_id
                                  JOIN private.source_rendition rd ON rd.id=oc.rendition_id WHERE o.id=x.observation_id)'],
    ['private.source_persona_mention', '(SELECT p.source_id FROM private.source_persona p WHERE p.id=x.persona_id)'],
    ['private.interpretation_party', '(SELECT min(i.source_id) FROM private.interpretation i WHERE i.interpretation_key=x.interpretation_key)'],
    ['private.interpretation', 'x.source_id'],
    ['private.interpretation_observation', '(SELECT i.source_id FROM private.interpretation i WHERE i.id=x.interpretation_id)'],
    ['private.source_persona_identity_candidate_run', 'x.source_id'],
    ['private.source_persona_identity_candidate', '(SELECT r.source_id FROM private.source_persona_identity_candidate_run r WHERE r.id=x.run_id)'],
    ['private.identity_control_run', 'x.source_id'],
    ['private.identity_control_exclusion', '(SELECT c.source_id FROM private.identity_control_run c WHERE c.id=x.control_run_id)'],
    ['private.identity_control_parent_card', '(SELECT c.source_id FROM private.identity_control_run c WHERE c.id=x.control_run_id)'],
    ['private.identity_control_sample', '(SELECT c.source_id FROM private.identity_control_run c WHERE c.id=x.control_run_id)'],
    ['private.identity_control_event', '(SELECT c.source_id FROM private.identity_control_run c WHERE c.id=x.control_run_id)'],
    ['private.identity_control_parent_event', '(SELECT c.source_id FROM private.identity_control_parent_card pc
                                               JOIN private.identity_control_run c ON c.id=pc.control_run_id WHERE pc.id=x.card_id)'],
    ['private.source_persona_identity', '(SELECT p.source_id FROM private.source_persona p WHERE p.id=x.source_persona_id)'],
    ['private.source_persona_identity_event', '(SELECT p.source_id FROM private.source_persona p WHERE p.id=x.source_persona_id)'],
    ['private.relation_classification_event', '(SELECT min(i.source_id) FROM private.interpretation i WHERE i.interpretation_key=x.interpretation_key)'],
    ['private.clause_disposition', '(SELECT rd.source_id FROM private.source_observation o JOIN private.source_record_occurrence oc ON oc.id=o.occurrence_id
                                    JOIN private.source_rendition rd ON rd.id=oc.rendition_id WHERE o.id=x.observation_id)'],
    ['private.interpretation_promotion', '(SELECT i.source_id FROM private.interpretation i WHERE i.id=x.interpretation_id)'],
    -- En bindingsbatch hører til src, hvis en af dens bindinger gør; ellers tælles den som anden kilde (NULL).
    ['private.interpretation_promotion_batch', '(SELECT max(i.source_id) FILTER (WHERE i.source_id=' || 'current_setting(''daa.t5_src'')::bigint)
                                               FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id
                                              WHERE p.batch_id=x.id)']];
  excl text[]; i int;
BEGIN
  SELECT array_agg(chain[k][1]) INTO excl FROM generate_subscripts(chain, 1) k;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','p') AND (n.nspname||'.'||c.relname) <> ALL (excl)
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT encode(sha256(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"), ''''), ''UTF8'')), ''hex'')
                      FROM (SELECT to_jsonb(x)::text t FROM %I.%I x) s', r.nspname, r.relname) INTO h;
    acc:=acc||r.nspname||'.'||r.relname||'='||h||E'\n';
  END LOOP;
  FOR r IN SELECT n.nspname, c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('private','public') AND c.relkind='S'
              AND NOT EXISTS (SELECT 1 FROM pg_depend d JOIN pg_class t ON t.oid=d.refobjid JOIN pg_namespace tn ON tn.oid=t.relnamespace
                               WHERE d.objid=c.oid AND d.deptype IN ('a','i') AND (tn.nspname||'.'||t.relname)=ANY(excl))
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    EXECUTE format('SELECT last_value::text||'':''||is_called::text FROM %I.%I', r.nspname, r.relname) INTO h;
    acc:=acc||'seq:'||r.nspname||'.'||r.relname||'='||h||E'\n';
  END LOOP;
  FOR i IN 1..array_length(chain, 1) LOOP
    IF to_regclass(chain[i][1]) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('SELECT encode(sha256(convert_to(coalesce(string_agg(t, E''\n'' ORDER BY t COLLATE "C"), ''''), ''UTF8'')), ''hex'')
                      FROM (SELECT to_jsonb(x)::text t FROM %s x WHERE %s IS DISTINCT FROM $1) s', chain[i][1], chain[i][2])
      INTO h USING src;
    oth:=oth||chain[i][1]||'='||h||E'\n';
  END LOOP;
  PERFORM set_config('daa.t5_untouched', encode(sha256(convert_to(acc, 'UTF8')), 'hex'), true);
  PERFORM set_config('daa.t5_other', encode(sha256(convert_to(oth, 'UTF8')), 'hex'), true);
END $uh$;
SELECT 'daa.transfer_5ab_untouched='||current_setting('daa.t5_untouched');
SELECT 'daa.transfer_5ab_other_sources='||current_setting('daa.t5_other');
COMMIT;
