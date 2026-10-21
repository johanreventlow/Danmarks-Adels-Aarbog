-- Indholds-id (#151, spec §5.1): det, kæden selv skriver, oven på indholds-id-dump.sql. Køres som ejer efter
-- relation-5b.sql og relation-2a.sql i harnessets transaktion og afslutter selv med COMMIT.
-- Ægtefællepersonas (rigtig writer) → kandidatkørsel 1 → kontrolkørsel → Bo Beta afgøres same → kandidatkørsel 2 → 2a.
CREATE FUNCTION pg_temp.fid_candidates(p_in jsonb,p_rules jsonb) RETURNS jsonb LANGUAGE sql AS $$
  -- p_rules: {navn: [[person_id, corroboration_eligible], …]} i rangorden; personas uden regel får ingen kandidater.
  SELECT coalesce(jsonb_agg(jsonb_build_object('source_persona_id',pe->>'source_persona_id','candidate_person_id',(r.v->>0)::bigint,
           'rank',r.o,'score',CASE r.o WHEN 1 THEN 0.95 ELSE 0.4 END,'tier',CASE r.o WHEN 1 THEN 'auto' ELSE 'none' END,
           'basis',jsonb_build_object('signals',jsonb_build_array('name'),'corroboration_eligible',(r.v->>1)::boolean))
         ORDER BY pe->>'source_persona_id' COLLATE "C",r.o),'[]'::jsonb)
    FROM jsonb_array_elements(p_in->'input'->'personas') pe
    CROSS JOIN LATERAL jsonb_array_elements(p_rules->(pe->>'name')) WITH ORDINALITY r(v,o)
   WHERE p_rules ? (pe->>'name');
$$;
GRANT EXECUTE ON FUNCTION pg_temp.fid_candidates(jsonb,jsonb) TO authenticated;

DO $chain$
DECLARE
  v_actor uuid:='11000000-0000-0000-0000-000000025001'; v_el jsonb; v_in jsonb; v_run1 uuid; v_run2 uuid; v_ctl uuid;
  v_bo uuid; v_cand uuid; v_pv jsonb;
BEGIN
  -- 1. Ægtefællepersonas gennem den rigtige writer (én pr. ægteskabspåstand).
  SELECT jsonb_object_agg('relation-persona:'||ic.interpretation_key::text,
           pg_temp.f5b_payload(NULL,jsonb_build_object('key',ic.interpretation_key),io.observation_id,ic.value->>'raw',
             substring(ic.value->>'raw' from 'm\. ([A-Z][a-z]+ [A-Z][a-z]+)')))
    INTO v_el
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.ordinal=1
   WHERE ic.source_id=-25001 AND ic.predicate='relation.marriage';
  PERFORM pg_temp.f5b_write(-25001,v_actor,v_el);

  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  -- 2. Kandidatkørsel 1: Bo Beta og Cia Ceta uegnede til stikprøven, Dy Delta egnet.
  v_in:=red_identity_candidate_input(-25001,'{"mode":"undecided"}');
  v_run1:=red_record_identity_candidates(jsonb_build_object('source_id',-25001,'generator_version','test','config','{"k":1}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),
    pg_temp.fid_candidates(v_in,'{"Bo Beta":[[-25002,false],[-25010,false]],"Cia Ceta":[[-25003,false],[-25011,false]],
                                  "Dy Delta":[[-25005,true],[-25012,false]]}'));
  -- 3. Kontrolkørsel på kørsel 1.
  v_ctl:=red_register_identity_control_run(v_run1);
  -- 4. Bo Beta afgøres same på arket, mens kørsel 1 er den gældende (kandidaten slås op som ejer).
  RESET ROLE;
  SELECT c.source_persona_id,c.id INTO v_bo,v_cand
    FROM private.source_persona_identity_candidate c
   WHERE c.run_id=v_run1 AND c.rank=1 AND c.candidate_person_id=-25002;
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(v_bo,0,'same',-25002,'test',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',1,'candidate_id',v_cand,'run_id',v_run1));
  -- 5. Kandidatkørsel 2 (ny config). Dy Deltas rang 1 står uden for familien, så personaen (der er i
  --    kontrolstikprøven) ikke kommer på undtagelsesarket (SPOUSE_SHEET_CONTROL_SAMPLE).
  v_in:=red_identity_candidate_input(-25001,'{"mode":"undecided"}');
  v_run2:=red_record_identity_candidates(jsonb_build_object('source_id',-25001,'generator_version','test','config','{"k":2}'::jsonb,
    'input_spec','{"mode":"undecided"}'::jsonb,'input_sha256',v_in->>'input_sha256'),
    pg_temp.fid_candidates(v_in,'{"Cia Ceta":[[-25003,false],[-25011,false]],"Dy Delta":[[-25013,false],[-25012,false]]}'));
  -- 6. 2a for kilden: Bo Betas ægteskab får ordinal_afvigelse (bogen 1°, familien 2). Ingen binding.
  v_pv:=red_preview_relation_decisions(-25001);
  PERFORM red_decide_relation_interpretations(-25001,v_pv->>'set_sha256');
  RESET ROLE;
END $chain$;
COMMIT;
