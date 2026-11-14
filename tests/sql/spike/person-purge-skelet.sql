-- Task 0 (fuld personsletning): låse-spike. KUN til engangsbaser; lægges oven på bootstrap + schema.sql + db-rls.sql
-- (+ db-migrations.sql). Idempotent, så den kan lægges på igen efter en mellemliggende db-migrations.sql, der
-- genskaber de gamle kroppe af enforce_relation_evidence_target (db-migrations.sql l. 2969) og
-- validate_entity_description_subject (l. 7520).
--
-- Indhold:
--   1. spike.indstilling: vagternes tilstand ('enforce' | 'warn'). En tabelrække, ikke en GUC, så createdb -T arver den.
--   2. Vagterne fra Global Constraints (eksistensvagt, fakta-mål, fakta-slettevagt, entity_description). feed_pin er
--      udeladt i spiket (red_set_feed_pin er en enkelt RPC; den skal have samme lås i Task 8).
--   3. spike.red_slet_person_helt_skelet(P, opt): tager KUN L1-L13 med L5b i slettegrafens orden og sletter derefter
--      noget repræsentativt (P's fakta/relationer med evidens, memberships og evt. selve personen). Det er ikke den
--      rigtige sletning.
-- Markør til harnessen: hver vagtfunktion indeholder strengen SPIKE_PERSON_PURGE_VAGT_V1.

SET client_min_messages = warning;
CREATE SCHEMA IF NOT EXISTS spike;
REVOKE ALL ON SCHEMA spike FROM PUBLIC;
CREATE TABLE IF NOT EXISTS spike.indstilling (noegle text PRIMARY KEY, vaerdi text NOT NULL);
INSERT INTO spike.indstilling VALUES ('vagt_mode','enforce') ON CONFLICT (noegle) DO NOTHING;
REVOKE ALL ON TABLE spike.indstilling FROM PUBLIC;

-- Brud: 'enforce' → exception; 'warn' → WARNING med et grep-bart mærke (CI-inventar uden at stoppe ved første fejl).
CREATE OR REPLACE FUNCTION spike.vagt_brud(p_kode text, p_tabel text, p_type text, p_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,spike AS $$
DECLARE v_ctx text;
BEGIN
  -- SPIKE_PERSON_PURGE_VAGT_V1
  -- Kendte brud (kommasepareret 'type:id' i noegle='kendte'): kun advarsel, også i enforce. Bruges til en
  -- enforce-kørsel, der beviser, at warn-inventaret er komplet (alle andre brud fejler som i planen).
  IF p_type||':'||p_id = ANY(string_to_array(coalesce((SELECT vaerdi FROM spike.indstilling WHERE noegle='kendte'),''),',')) THEN
    RAISE WARNING 'SPIKE_VAGT_KENDT kode=% tabel=% type=% id=%', p_kode, p_tabel, p_type, p_id;
    RETURN;
  END IF;
  IF coalesce((SELECT vaerdi FROM spike.indstilling WHERE noegle='vagt_mode'),'enforce')='warn' THEN
    -- Kaldstakken (kun funktionsnavne), så inventaret kan skelne testens egen INSERT fra en skriver i skemaet.
    GET DIAGNOSTICS v_ctx = PG_CONTEXT;
    SELECT string_agg(m[1], ' < ') INTO v_ctx
      FROM regexp_matches(v_ctx, 'function ([^ (]+)\(', 'g') m
     WHERE m[1] NOT IN ('spike.vagt_brud','vagt_brud','validate_polymorf_subjekt_findes','enforce_relation_evidence_target',
                        'guard_fact_evidence_delete');
    RAISE WARNING 'SPIKE_VAGT_BRUD kode=% tabel=% type=% id=% stak=%', p_kode, p_tabel, p_type, p_id, coalesce(v_ctx,'-');
    RETURN;
  END IF;
  RAISE EXCEPTION '%: % %', p_kode, p_type, p_id USING DETAIL = format('tabel=%s', p_tabel);
END $$;
REVOKE ALL ON FUNCTION spike.vagt_brud(text,text,text,bigint) FROM PUBLIC;

-- ---------------------------------------------------------------------------------------------------------------
-- 2a. Fakta-mål: den eksisterende relation-vagt (schema.sql l. 7367) udvides til target_type='fact'.
--     D-6: ved UPDATE med uændret (type, id) returneres straks (fortryd sætter alle kolonner).
CREATE OR REPLACE FUNCTION enforce_relation_evidence_target()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  -- SPIKE_PERSON_PURGE_VAGT_V1
  IF TG_OP='UPDATE' AND NEW.target_type IS NOT DISTINCT FROM OLD.target_type
     AND NEW.target_id IS NOT DISTINCT FROM OLD.target_id THEN
    RETURN NEW;
  END IF;
  IF NEW.target_type='relation' THEN
    PERFORM 1 FROM relation WHERE id=NEW.target_id FOR KEY SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Relations-evidens kræver eksisterende relation %', NEW.target_id;
    END IF;
  ELSIF lower(NEW.target_type)='fact' THEN
    PERFORM 1 FROM fact WHERE id=NEW.target_id FOR KEY SHARE;
    IF NOT FOUND THEN
      PERFORM spike.vagt_brud('POLYMORF_SUBJEKT_FINDES_IKKE', TG_TABLE_NAME, 'fact', NEW.target_id);
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.enforce_relation_evidence_target() FROM PUBLIC, anon, authenticated;

-- 2b. Eksistensvagten for person/familie. Argumenterne er kolonnepar (type, id); relation får to par.
--     Begge ender låses i id-orden, personer før familier (D-8); type sammenlignes med lower() (D-8).
CREATE OR REPLACE FUNCTION private.validate_polymorf_subjekt_findes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_new jsonb := to_jsonb(NEW); v_old jsonb; i int; v_uaendret boolean := true; r record;
BEGIN
  -- SPIKE_PERSON_PURGE_VAGT_V1
  IF TG_OP='UPDATE' THEN
    v_old := to_jsonb(OLD);
    FOR i IN 0..TG_NARGS-1 LOOP
      IF (v_new->>TG_ARGV[i]) IS DISTINCT FROM (v_old->>TG_ARGV[i]) THEN v_uaendret := false; END IF;
    END LOOP;
    IF v_uaendret THEN RETURN NEW; END IF;   -- D-6
  END IF;
  FOR r IN
    SELECT lower(v_new->>TG_ARGV[2*k]) AS typ, (v_new->>TG_ARGV[2*k+1])::bigint AS id
      FROM generate_series(0, TG_NARGS/2-1) k
     WHERE lower(v_new->>TG_ARGV[2*k]) IN ('person','family') AND v_new->>TG_ARGV[2*k+1] IS NOT NULL
     ORDER BY (lower(v_new->>TG_ARGV[2*k])='family'), (v_new->>TG_ARGV[2*k+1])::bigint
  LOOP
    IF r.typ='person' THEN
      PERFORM 1 FROM public.person WHERE id=r.id FOR KEY SHARE;
    ELSE
      PERFORM 1 FROM public.family WHERE id=r.id FOR KEY SHARE;
    END IF;
    IF NOT FOUND THEN
      PERFORM spike.vagt_brud('POLYMORF_SUBJEKT_FINDES_IKKE', TG_TABLE_NAME, r.typ, r.id);
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.validate_polymorf_subjekt_findes() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS trg_spike_polymorf_fact ON public.fact;
CREATE TRIGGER trg_spike_polymorf_fact BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id ON public.fact
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('subjekt_type','subjekt_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_note ON public.note;
CREATE TRIGGER trg_spike_polymorf_note BEFORE INSERT OR UPDATE OF target_type,target_id ON public.note
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('target_type','target_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_narrative ON public.narrative;
CREATE TRIGGER trg_spike_polymorf_narrative BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id ON public.narrative
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('subjekt_type','subjekt_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_story ON public.story;
CREATE TRIGGER trg_spike_polymorf_story BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id ON public.story
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('subjekt_type','subjekt_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_suggestion ON public.suggestion;
CREATE TRIGGER trg_spike_polymorf_suggestion BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id ON public.suggestion
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('subjekt_type','subjekt_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_relation ON public.relation;
CREATE TRIGGER trg_spike_polymorf_relation
  BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id,objekt_type,objekt_id ON public.relation
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('subjekt_type','subjekt_id','objekt_type','objekt_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_assertion_objekt ON public.assertion;
CREATE TRIGGER trg_spike_polymorf_assertion_objekt BEFORE INSERT OR UPDATE OF objekt_type,objekt_id ON public.assertion
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('objekt_type','objekt_id');
DROP TRIGGER IF EXISTS trg_spike_polymorf_haendelse ON public.haendelse;
CREATE TRIGGER trg_spike_polymorf_haendelse BEFORE INSERT OR UPDATE OF subjekt_type,subjekt_id ON public.haendelse
  FOR EACH ROW EXECUTE FUNCTION private.validate_polymorf_subjekt_findes('subjekt_type','subjekt_id');

-- 2c. entity_description: FOR KEY SHARE i stedet for EXISTS. Bevidst stadig SECURITY INVOKER som i schema.sql
--     (l. 11967), så spiket viser, om en invoker uden UPDATE-ret på måltabellen rammer »permission denied«.
CREATE OR REPLACE FUNCTION validate_entity_description_subject()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,public AS $$
BEGIN
  -- SPIKE_PERSON_PURGE_VAGT_V1
  IF TG_OP='UPDATE' AND NEW.subjekt_type IS NOT DISTINCT FROM OLD.subjekt_type
     AND NEW.subjekt_id IS NOT DISTINCT FROM OLD.subjekt_id THEN
    RETURN NEW;
  END IF;
  IF NEW.subjekt_type='person' THEN PERFORM 1 FROM public.person WHERE id=NEW.subjekt_id FOR KEY SHARE;
  ELSIF NEW.subjekt_type='slaegt' THEN PERFORM 1 FROM public.slaegt WHERE id=NEW.subjekt_id FOR KEY SHARE;
  ELSIF NEW.subjekt_type='lineage' THEN PERFORM 1 FROM public.lineage WHERE id=NEW.subjekt_id FOR KEY SHARE;
  ELSIF NEW.subjekt_type='coat_of_arms' THEN PERFORM 1 FROM public.coat_of_arms WHERE id=NEW.subjekt_id FOR KEY SHARE;
  ELSIF NEW.subjekt_type='media' THEN PERFORM 1 FROM public.media WHERE id=NEW.subjekt_id FOR KEY SHARE;
  ELSIF NEW.subjekt_type='estate' THEN PERFORM 1 FROM public.estate WHERE id=NEW.subjekt_id FOR KEY SHARE;
  ELSE RAISE EXCEPTION 'ENTITY_DESCRIPTION_SUBJECT_INVALID';
  END IF;
  IF FOUND THEN RETURN NEW; END IF;
  RAISE EXCEPTION 'ENTITY_DESCRIPTION_SUBJECT_INVALID';
END $$;

-- 2d. Fakta-slettevagten: forælderhalvdelen af FK'en (D-7), efter mønstret i guard_relation_evidence_delete.
CREATE OR REPLACE FUNCTION private.guard_fact_evidence_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $$
BEGIN
  -- SPIKE_PERSON_PURGE_VAGT_V1
  IF TG_OP='UPDATE' AND NEW.id IS NOT DISTINCT FROM OLD.id THEN RETURN NEW; END IF;
  IF EXISTS (SELECT 1 FROM public.assertion WHERE lower(target_type)='fact' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM public.conclusion WHERE lower(target_type)='fact' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM public.note WHERE lower(target_type)='fact' AND target_id=OLD.id)
     OR EXISTS (SELECT 1 FROM public.relation
                 WHERE (lower(subjekt_type)='fact' AND subjekt_id=OLD.id)
                    OR (lower(objekt_type)='fact' AND objekt_id=OLD.id)) THEN
    PERFORM spike.vagt_brud('FACT_HAR_EVIDENS', 'fact', TG_OP, OLD.id);
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.guard_fact_evidence_delete() FROM PUBLIC, anon, authenticated, service_role;
DROP TRIGGER IF EXISTS trg_spike_fact_evidence_delete ON public.fact;
CREATE TRIGGER trg_spike_fact_evidence_delete BEFORE DELETE OR UPDATE OF id ON public.fact
  FOR EACH ROW EXECUTE FUNCTION private.guard_fact_evidence_delete();

-- ---------------------------------------------------------------------------------------------------------------
-- 3. Skelettet. opt (jsonb), alle valgfri:
--   l5b          boolean  (default true)  — false = positiv kontrol for D-2
--   l8_mode      text     (default 'ROW EXCLUSIVE') — 'SHARE ROW EXCLUSIVE' = positiv kontrol for D-1
--   pause_after  text     — 'L5'|'L5b'|'L6'|'L8'|'L10'|'L13'|'DELETE': pg_sleep(pause_s) efter dette trin
--   pause_s      numeric  (default 3)
--   slet_person  boolean  (default false) — slet også personrækken (kun for en »let« P uden ledger/narrativ)
--   preview      text     — forventet preview-hash; mangler den, beregnes den ved indgangen (før L1)
-- Returnerer jsonb med de låste mængder og hvad der blev slettet.
-- X ∪ Y
CREATE OR REPLACE FUNCTION spike.person_purge_personas(p bigint) RETURNS SETOF uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  SELECT source_persona_id FROM private.source_persona_identity WHERE canonical_person_id=p
  UNION SELECT source_persona_id FROM private.source_persona_identity_event WHERE canonical_person_id=p
$$;

CREATE OR REPLACE FUNCTION spike.person_purge_preview(p bigint) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  SELECT md5(jsonb_build_object(
    'facts',(SELECT coalesce(jsonb_agg(id ORDER BY id),'[]') FROM public.fact WHERE subjekt_type='person' AND subjekt_id=p),
    'assertions',(SELECT coalesce(jsonb_agg(a.id ORDER BY a.id),'[]') FROM public.assertion a JOIN public.fact f
                    ON a.target_type='fact' AND a.target_id=f.id WHERE f.subjekt_type='person' AND f.subjekt_id=p),
    'relations',(SELECT coalesce(jsonb_agg(id ORDER BY id),'[]') FROM public.relation
                  WHERE (subjekt_type='person' AND subjekt_id=p) OR (objekt_type='person' AND objekt_id=p)),
    'notes',(SELECT coalesce(jsonb_agg(id ORDER BY id),'[]') FROM public.note WHERE target_type='person' AND target_id=p),
    'personas',(SELECT coalesce(jsonb_agg(x ORDER BY x),'[]') FROM spike.person_purge_personas(p) x),
    'kandidater',(SELECT coalesce(jsonb_agg(c.id ORDER BY c.id),'[]') FROM private.source_persona_identity_candidate c
                   WHERE c.candidate_person_id=p),
    'memberships',(SELECT count(*) FROM public.person_lineage_membership WHERE person_id=p))::text)
$$;

-- L3: sources(P)
CREATE OR REPLACE FUNCTION spike.person_purge_sources(p bigint) RETURNS bigint[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  SELECT coalesce(array_agg(DISTINCT s ORDER BY s),'{}') FROM (
    SELECT source_id s FROM public.person_external_id WHERE person_id=p
    UNION SELECT sp.source_id FROM private.source_persona sp WHERE sp.id IN (SELECT spike.person_purge_personas(p))
    UNION SELECT sp.source_id FROM private.source_persona_identity_candidate c
            JOIN private.source_persona sp ON sp.id=c.source_persona_id WHERE c.candidate_person_id=p
    UNION SELECT r.source_id FROM private.identity_control_sample smp
            JOIN private.identity_control_run r ON r.id=smp.control_run_id
           WHERE smp.source_persona_id IN (SELECT spike.person_purge_personas(p))
  ) q WHERE s IS NOT NULL
$$;

-- L5b: records hvor X∪Y-personas er placeret + records P's narrativer er bundet til
CREATE OR REPLACE FUNCTION spike.person_purge_records(p bigint) RETURNS uuid[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  SELECT coalesce(array_agg(DISTINCT r ORDER BY r),'{}') FROM (
    SELECT pl.source_record_id r FROM private.source_persona_placement pp
      JOIN private.source_record_placement pl ON pl.id=pp.record_placement_id
     WHERE pp.source_persona_id IN (SELECT spike.person_purge_personas(p))
    UNION SELECT b.source_record_id FROM private.narrative_record_publication b
      JOIN public.narrative n ON n.id=b.narrative_id WHERE n.subjekt_type='person' AND n.subjekt_id=p
  ) q WHERE r IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION spike.red_slet_person_helt_skelet(p_person_id bigint, p_opt jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_preview text := coalesce(p_opt->>'preview', spike.person_purge_preview(p_person_id));
  v_pause text := p_opt->>'pause_after';
  v_pause_s numeric := coalesce((p_opt->>'pause_s')::numeric, 3);
  v_l8 text := coalesce(p_opt->>'l8_mode','ROW EXCLUSIVE');
  v_sources bigint[]; v_profiles text[]; v_records uuid[]; v_personas uuid[]; v_people bigint[];
  v_facts bigint[]; v_rels bigint[]; v_src bigint; v_prof record; v_n jsonb := '{}';
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  PERFORM set_config('statement_timeout','30s',true);   -- virker først fra næste statement (se analysen)
  IF v_l8 NOT IN ('ROW EXCLUSIVE','SHARE ROW EXCLUSIVE') THEN RAISE EXCEPTION 'SPIKE_OPT_L8'; END IF;
  -- L1
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  -- L2
  IF auth.uid() IS NULL OR public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'PURGE_FREMMED_CHANGE_SET'; END IF;
  -- L3
  v_sources := spike.person_purge_sources(p_person_id);
  SELECT coalesce(array_agg(w.source_id::text||':'||w.profile_id ORDER BY w.source_id,w.profile_id),'{}') INTO v_profiles
    FROM private.reimport_writer_profile w WHERE w.source_id=ANY(v_sources);
  -- L4
  FOR v_prof IN SELECT DISTINCT w.source_id,w.profile_id FROM private.reimport_writer_profile w
                 WHERE w.source_id=ANY(v_sources) ORDER BY w.source_id,w.profile_id LOOP
    PERFORM private.lock_reimport_writer(v_prof.source_id,v_prof.profile_id);
  END LOOP;
  -- L5
  FOREACH v_src IN ARRAY v_sources LOOP
    PERFORM pg_advisory_xact_lock(hashtextextended('daa-identity-candidates:'||v_src::text,0));
  END LOOP;
  IF v_pause='L5' THEN PERFORM pg_sleep(v_pause_s); END IF;
  -- L5b
  v_records := spike.person_purge_records(p_person_id);
  IF coalesce((p_opt->>'l5b')::boolean,true) THEN
    PERFORM 1 FROM private.source_record WHERE id=ANY(v_records) ORDER BY id FOR UPDATE;
  END IF;
  IF v_pause='L5b' THEN PERFORM pg_sleep(v_pause_s); END IF;
  -- L6
  SELECT coalesce(array_agg(x ORDER BY x),'{}') INTO v_personas FROM spike.person_purge_personas(p_person_id) x;
  PERFORM 1 FROM private.source_persona WHERE id=ANY(v_personas) ORDER BY id FOR UPDATE;
  PERFORM 1 FROM private.source_persona_identity WHERE source_persona_id=ANY(v_personas)
    ORDER BY source_persona_id FOR UPDATE;
  IF v_pause='L6' THEN PERFORM pg_sleep(v_pause_s); END IF;
  -- L7
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  PERFORM private.guard_identity_mutation_snapshot();
  -- L8
  EXECUTE format('LOCK TABLE public.change_set IN %s MODE', v_l8);
  IF v_pause='L8' THEN PERFORM pg_sleep(v_pause_s); END IF;
  -- L9
  PERFORM 1 FROM public.source s JOIN public.person_external_id pei ON pei.source_id=s.id
   WHERE pei.person_id=p_person_id ORDER BY s.id,pei.source_id FOR UPDATE OF s,pei;
  -- L10
  SELECT array_agg(DISTINCT x ORDER BY x) INTO v_people FROM (
    SELECT p_person_id x
    UNION SELECT CASE WHEN subjekt_id=p_person_id THEN objekt_id ELSE subjekt_id END FROM public.relation
     WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
       AND (subjekt_id=p_person_id OR objekt_id=p_person_id)) q;
  PERFORM private.lock_identity_people(v_people);
  IF v_pause='L10' THEN PERFORM pg_sleep(v_pause_s); END IF;
  -- L11
  PERFORM private.lock_family_rows(ARRAY[p_person_id]);
  -- L12
  IF EXISTS (SELECT unnest(spike.person_purge_sources(p_person_id)) EXCEPT SELECT unnest(v_sources))
     OR EXISTS (SELECT unnest(spike.person_purge_records(p_person_id)) EXCEPT SELECT unnest(v_records)) THEN
    RAISE EXCEPTION 'PURGE_LOCKSET_DRIFT';
  END IF;
  -- L13
  IF spike.person_purge_preview(p_person_id) IS DISTINCT FROM v_preview THEN
    RAISE EXCEPTION 'PURGE_PREVIEW_AENDRET';
  END IF;
  IF v_pause='L13' THEN PERFORM pg_sleep(v_pause_s); END IF;

  -- Repræsentativ sletning (børn før forældre, så fakta-slettevagten er tilfreds).
  SELECT coalesce(array_agg(id ORDER BY id),'{}') INTO v_facts FROM public.fact
   WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(array_agg(id ORDER BY id),'{}') INTO v_rels FROM public.relation
   WHERE (subjekt_type='person' AND subjekt_id=p_person_id) OR (objekt_type='person' AND objekt_id=p_person_id)
      OR (subjekt_type='fact' AND subjekt_id=ANY(v_facts)) OR (objekt_type='fact' AND objekt_id=ANY(v_facts));
  DELETE FROM public.citation WHERE assertion_id IN (
    SELECT id FROM public.assertion WHERE (target_type='fact' AND target_id=ANY(v_facts))
                                       OR (target_type='relation' AND target_id=ANY(v_rels)));
  DELETE FROM public.conclusion WHERE (target_type='fact' AND target_id=ANY(v_facts))
                                   OR (target_type='relation' AND target_id=ANY(v_rels));
  DELETE FROM public.assertion WHERE (target_type='fact' AND target_id=ANY(v_facts))
                                  OR (target_type='relation' AND target_id=ANY(v_rels));
  DELETE FROM public.note WHERE (target_type='person' AND target_id=p_person_id)
                             OR (target_type='fact' AND target_id=ANY(v_facts))
                             OR (target_type='relation' AND target_id=ANY(v_rels));
  UPDATE public.haendelse SET relation_id=NULL WHERE relation_id=ANY(v_rels);
  UPDATE public.haendelse SET fact_id=NULL WHERE fact_id=ANY(v_facts);
  DELETE FROM public.relation WHERE id=ANY(v_rels);
  DELETE FROM public.fact WHERE id=ANY(v_facts);
  DELETE FROM public.person_lineage_membership WHERE person_id=p_person_id;
  DELETE FROM public.person_slaegt_membership WHERE person_id=p_person_id;
  IF coalesce((p_opt->>'slet_person')::boolean,false) THEN
    DELETE FROM public.person_external_id WHERE person_id=p_person_id;
    DELETE FROM public.family_member WHERE person_id=p_person_id;
    DELETE FROM public.slaegtsnavn_karantaene WHERE person_id=p_person_id;
    DELETE FROM public.person WHERE id=p_person_id;
  END IF;
  IF v_pause='DELETE' THEN PERFORM pg_sleep(v_pause_s); END IF;
  RETURN jsonb_build_object('sources',to_jsonb(v_sources),'profiles',to_jsonb(v_profiles),
    'records',to_jsonb(v_records),'personas',to_jsonb(v_personas),'people',to_jsonb(v_people),
    'facts',to_jsonb(v_facts),'relations',to_jsonb(v_rels),
    'person_slettet',coalesce((p_opt->>'slet_person')::boolean,false));
END $$;
REVOKE ALL ON FUNCTION spike.red_slet_person_helt_skelet(bigint,jsonb) FROM PUBLIC;
