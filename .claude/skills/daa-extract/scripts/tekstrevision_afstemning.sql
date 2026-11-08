-- Trin 6c-3 (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.4; plan Task 5): afstemningen efter en kildetekst-revision.
-- Læse-kun. Pr. forældet nøgle (revisionsevent'ets superseded_keys) og pr. ny nøgle på samme poster (gældende version
-- citerer en klausul i helpostens aktuelle sæt, clause_observation_current): nøgle, version, status, prædikat, persona,
-- modpart-persona, marriage_ordinal, binding_loss-promotion og mål. Matchningen gammel → ny beregnes her, med én kontrakt
-- pr. art (spec §4.4); klausulordinalen kræves aldrig:
--   fakta (bundet til en påstand): samme persona + prædikat, og binding_value_matches(regelens value_kind, ny værdi,
--     målpåstandens vaerdi_tekst, date_raw) mod den gamle bindings påstand, som den står nu;
--   ægteskab: samme principal, ægtefælle-persona og marriage_ordinal (Review Focus 1), og relation_binding_state's
--     familie = den gamle bindings familie (meningsfuld efter parterne);
--   forælder: samme principal, og den eneste relation_structural_candidates-familie = den gamle (før afgørelsen); når
--     afgørelsen har skrevet en forælderpart, skal den være den gamle nøgles, og relation_binding_state's familie den
--     gamle (efter afgørelsen);
--   barn: samme principal, og relation_child_rule's familie = den gamle;
--   ubundet (ingen binding i binding_loss): samme persona + prædikat og saml_blanktegn_v1-lige værdier.
-- En kandidat er en ny nøgle på samme post med samme prædikat og art, hvis gældende status ikke er rejected eller
-- superseded. Genfundet = præcis én kandidat, som ingen anden forældet nøgle også har; tvetydig eller ingen →
-- ikke_genfundet; relationer i fase foer_parter → afventer. Pr. binding: ny_binding = den genfundne nye nøgle har en
-- gyldig binding (private.text_revision_binding_set, revisionens og kvitteringens prædikat) mod samme mål;
-- fremmed_binding = en anden ny nøgle på posten med samme prædikat har det.
-- Faktaenes rettelse_kandidater: nye nøgler (samme persona + prædikat), hvis rettelsesmål efter kontrolmodellens regel
-- (interpretation_control_rows.sql, maal0/maal) er den gamle bindings påstand: B på et REAL_DIFF retter og binder dér.
-- Udskriver kun nøgler, versioner, statusser, persona_key'er, mål-id'er (påstand/familie), gamle promotion-id'er, udfald
-- og hashes — ingen værdier, navne eller tekst, ingen interpretation.id'er og ingen nye promotion-id'er.
--
-- Variabler: batch (revisionens reimport_batch.id), fase (foer_parter | efter_parter | efter_afgoerelser).
-- Alene (ejerforbindelse; de private funktioner er lukket for authenticated):
--   psql -X -v ON_ERROR_STOP=1 -v batch=<uuid> -v fase=<fase> -f tekstrevision_afstemning.sql > afstemning-<fase>.json
-- Indlejret (kvitteringens preflight og kvittering): `\set afstemning_inline 1` før `\i`; filen åbner da ingen
-- transaktion. Resultatet lægges altid i GUC'en daa.tekstrevision_afstemning (som klassifikationens daa.control_result).
\if :{?afstemning_inline}
\else
\set ON_ERROR_STOP on
\set QUIET on
\pset format unaligned
\pset tuples_only on
BEGIN READ ONLY;
\endif
SELECT set_config('daa.afstemning_batch', :'batch', false) AS batch, set_config('daa.afstemning_fase', :'fase', false) AS fase
\g /dev/null
DO $afstemning_tjek$
DECLARE v_batch uuid; v_fase text:=current_setting('daa.afstemning_fase'); v_status text; v_n integer; v_bad integer;
BEGIN
  IF v_fase IS NULL OR v_fase NOT IN ('foer_parter','efter_parter','efter_afgoerelser') THEN
    RAISE EXCEPTION 'AFSTEMNING_FASE_UGYLDIG';
  END IF;
  BEGIN
    v_batch:=current_setting('daa.afstemning_batch')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RAISE EXCEPTION 'AFSTEMNING_BATCH_UGYLDIG';
  END;
  SELECT status INTO v_status FROM private.reimport_batch WHERE id=v_batch;
  IF v_status IS NULL OR v_status NOT IN ('finalized','activated') THEN RAISE EXCEPTION 'AFSTEMNING_BATCH_UGYLDIG'; END IF;
  SELECT count(*),count(*) FILTER (WHERE operation<>'source_text_revision'
           OR jsonb_typeof(payload->'superseded_keys') IS DISTINCT FROM 'array'
           OR jsonb_typeof(payload->'binding_loss') IS DISTINCT FROM 'array'
           OR payload->>'parent_observation_id' IS NULL)
    INTO v_n,v_bad FROM private.reimport_event WHERE batch_id=v_batch;
  IF v_n=0 OR v_bad<>0 THEN RAISE EXCEPTION 'AFSTEMNING_BATCH_UGYLDIG'; END IF;
END $afstemning_tjek$;
WITH prm AS (
  SELECT current_setting('daa.afstemning_batch')::uuid AS batch,current_setting('daa.afstemning_fase') AS fase
), bat AS (
  SELECT b.id,b.source_id FROM private.reimport_batch b JOIN prm ON prm.batch=b.id
), ev AS (
  SELECT e.element_id,e.source_record_key AS record_key,(e.payload->>'parent_observation_id')::uuid AS helpost,
         e.payload->'superseded_keys' AS sk,e.payload->'binding_loss' AS bl
    FROM private.reimport_event e JOIN prm ON e.batch_id=prm.batch
   WHERE e.operation='source_text_revision'
), gb AS (
  -- Revisionens tabte bindinger (målt før forældelsen); target_id er tekst i eventet.
  SELECT ev.element_id,(b->>'interpretation_key')::uuid AS key,(b->>'promotion_id')::uuid AS promotion_id,
         b->>'target_type' AS target_type,(b->>'target_id')::bigint AS target_id
    FROM ev CROSS JOIN LATERAL jsonb_array_elements(ev.bl) b
), gba AS MATERIALIZED (
  -- Påstandsbindingerne med den gamle promotions regelversion og påstandens værdi, som den står nu (bruges kun i
  -- sammenligningen; udskrives ikke).
  SELECT gb.key,gb.target_id,r.value_kind,a.vaerdi_tekst,a.date_raw
    FROM gb
    JOIN private.interpretation_promotion p ON p.id=gb.promotion_id
    LEFT JOIN private.interpretation_promotion_rule r ON r.rule_key=p.rule_key AND r.rule_version=p.rule_version
    LEFT JOIN public.assertion a ON a.id=gb.target_id
   WHERE gb.target_type='assertion'
), gv AS MATERIALIZED (
  -- De forældede nøgler: gældende (superseded) version; felterne er kopien af versionen før.
  SELECT ev.element_id,ev.record_key,k::uuid AS key,cur.version,cur.status,prev.status AS status_foer,cur.predicate,
         cur.interpretation_kind AS kind,cur.source_persona_id AS persona_id,cur.value,
         CASE jsonb_typeof(cur.value) WHEN 'string' THEN cur.value #>> '{}' ELSE cur.value->>'raw' END AS vt,
         pt.principal,pt.spouse,pt.ordinal,pt.parent,
         CASE WHEN EXISTS (SELECT 1 FROM gb WHERE gb.key=k::uuid AND gb.target_type='assertion') THEN 'fakta'
              WHEN EXISTS (SELECT 1 FROM gb WHERE gb.key=k::uuid AND gb.target_type='family') THEN
                CASE cur.predicate WHEN 'relation.marriage' THEN 'aegteskab' WHEN 'relation.parent' THEN 'foraelder'
                                   WHEN 'relation.child' THEN 'barn' ELSE 'ukendt' END
              WHEN EXISTS (SELECT 1 FROM gb WHERE gb.key=k::uuid) THEN 'ukendt'
              ELSE 'ubundet' END AS art
    FROM ev
    CROSS JOIN LATERAL jsonb_array_elements_text(ev.sk) k
    CROSS JOIN LATERAL (SELECT * FROM private.interpretation_current c WHERE c.interpretation_key=k::uuid) cur
    LEFT JOIN private.interpretation prev ON prev.id=cur.supersedes_id
    LEFT JOIN LATERAL (
      SELECT max(pc.source_persona_id::text) FILTER (WHERE pc.party_role='principal') AS principal,
             max(pc.source_persona_id::text) FILTER (WHERE pc.party_role='spouse') AS spouse,
             max(pc.marriage_ordinal) FILTER (WHERE pc.party_role='spouse') AS ordinal,
             max(pc.source_persona_id::text) FILTER (WHERE pc.party_role='parent') AS parent
        FROM private.interpretation_party_current pc WHERE pc.interpretation_key=k::uuid) pt ON true
), ny AS (
  -- De nye nøgler på samme poster: gældende version citerer en klausul i helpostens aktuelle sæt.
  SELECT DISTINCT ev.element_id,ev.record_key,i.interpretation_key AS key
    FROM ev
    JOIN private.clause_observation_current k ON k.parent_observation_id=ev.helpost
    JOIN private.interpretation_observation io ON io.observation_id=k.id
    JOIN private.interpretation i ON i.id=io.interpretation_id
   WHERE i.source_id=(SELECT source_id FROM bat)
     AND NOT EXISTS (SELECT 1 FROM gv WHERE gv.key=i.interpretation_key)
     AND i.id=(SELECT c.id FROM private.interpretation_current c WHERE c.interpretation_key=i.interpretation_key)
), nv AS MATERIALIZED (
  SELECT ny.element_id,ny.record_key,ny.key,ic.id,ic.version,ic.status,ic.predicate,ic.interpretation_kind AS kind,
         ic.source_persona_id AS persona_id,ic.value,ic.source_id,
         CASE jsonb_typeof(ic.value) WHEN 'string' THEN ic.value #>> '{}' ELSE ic.value->>'raw' END AS vt,
         pt.principal,pt.spouse,pt.ordinal,pt.parent,
         CASE WHEN ic.predicate IN ('relation.marriage','relation.parent')
              THEN (private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint END AS st_familie,
         CASE WHEN ic.predicate='relation.parent' THEN sc.familie END AS foraelder_familie,
         CASE WHEN ic.predicate='relation.child'
              THEN (private.relation_child_rule(ic.id)->>'family_id')::bigint END AS barn_familie,
         rm.assertion_id AS rettelse_maal
    FROM ny
    CROSS JOIN LATERAL (SELECT * FROM private.interpretation_current c WHERE c.interpretation_key=ny.key) ic
    LEFT JOIN LATERAL (
      SELECT max(pc.source_persona_id::text) FILTER (WHERE pc.party_role='principal') AS principal,
             max(pc.source_persona_id::text) FILTER (WHERE pc.party_role='spouse') AS spouse,
             max(pc.marriage_ordinal) FILTER (WHERE pc.party_role='spouse') AS ordinal,
             max(pc.source_persona_id::text) FILTER (WHERE pc.party_role='parent') AS parent
        FROM private.interpretation_party_current pc WHERE pc.interpretation_key=ny.key) pt ON true
    LEFT JOIN LATERAL (
      -- »Eneste« kandidat som serverens og forælderarkets regel: præcis én række.
      SELECT CASE WHEN count(*)=1 THEN min(c.family_id) END AS familie
        FROM private.relation_structural_candidates(ny.key) c WHERE ic.predicate='relation.parent') sc ON true
    LEFT JOIN LATERAL (
      -- Rettelsesmålet efter interpretation_control_rows.sql (maal0/maal): den identificerede persons påstand af
      -- regelens faktatype, citeret af præcis forslagets egen kilde; præcis én → målet.
      SELECT CASE WHEN count(*)=1 THEN min(a.id) END AS assertion_id
        FROM private.interpretation_promotion_rule_current pr
        JOIN private.source_persona_identity i
          ON i.source_persona_id=ic.source_persona_id AND i.decision_status='accepted'
        JOIN public.fact f ON f.subjekt_type='person' AND f.subjekt_id=i.canonical_person_id
                          AND f.faktatype=pr.expected_fact_type
        JOIN public.assertion a ON a.target_type='fact' AND a.target_id=f.id
       WHERE pr.predicate=ic.predicate AND pr.interpretation_kind=ic.interpretation_kind
         AND pr.target_type='assertion' AND pr.status='active'
         AND ARRAY(SELECT DISTINCT c.source_id FROM public.citation c WHERE c.assertion_id=a.id ORDER BY 1)
             =ARRAY[ic.source_id]) rm ON true
), par AS (
  SELECT g.key AS gammel,n.key AS ny,
    (CASE g.art
      WHEN 'fakta' THEN n.persona_id=g.persona_id
        AND NOT EXISTS (SELECT 1 FROM gba WHERE gba.key=g.key
                         AND private.binding_value_matches(gba.value_kind,n.value,gba.vaerdi_tekst,gba.date_raw)
                             IS NOT TRUE)
      WHEN 'aegteskab' THEN n.principal=g.principal AND n.spouse=g.spouse AND n.ordinal=g.ordinal
        AND NOT EXISTS (SELECT 1 FROM gb WHERE gb.key=g.key AND n.st_familie IS DISTINCT FROM gb.target_id)
      WHEN 'foraelder' THEN n.principal=g.principal AND n.foraelder_familie IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM gb WHERE gb.key=g.key AND n.foraelder_familie IS DISTINCT FROM gb.target_id)
        AND (n.parent IS NULL OR (n.parent=g.parent
             AND NOT EXISTS (SELECT 1 FROM gb WHERE gb.key=g.key AND n.st_familie IS DISTINCT FROM gb.target_id)))
      WHEN 'barn' THEN n.principal=g.principal
        AND NOT EXISTS (SELECT 1 FROM gb WHERE gb.key=g.key AND n.barn_familie IS DISTINCT FROM gb.target_id)
      WHEN 'ubundet' THEN n.persona_id IS NOT DISTINCT FROM g.persona_id
        AND CASE WHEN g.vt IS NULL OR n.vt IS NULL THEN g.value=n.value
                 ELSE private.saml_blanktegn_v1(g.vt)=private.saml_blanktegn_v1(n.vt) END
      ELSE false END) IS TRUE AS ok
    FROM gv g
    JOIN nv n ON n.element_id=g.element_id AND n.predicate=g.predicate AND n.kind=g.kind
   WHERE n.status NOT IN ('rejected','superseded')
), okp AS (
  SELECT gammel,ny FROM par WHERE ok
), udf AS (
  SELECT g.key,
         coalesce((SELECT jsonb_agg(o.ny::text ORDER BY o.ny::text COLLATE "C") FROM okp o WHERE o.gammel=g.key),
                  '[]'::jsonb) AS kandidater,
         (SELECT count(*) FROM okp o WHERE o.gammel=g.key) AS n,
         (SELECT min(o.ny::text) FROM okp o WHERE o.gammel=g.key) AS ny1
    FROM gv g
), udf2 AS (
  SELECT u.key,u.kandidater,
         CASE WHEN (SELECT fase FROM prm)='foer_parter' AND g.art IN ('aegteskab','foraelder','barn') THEN 'afventer'
              WHEN u.n=1 AND (SELECT count(*) FROM okp o WHERE o.ny::text=u.ny1)=1 THEN 'genfundet'
              ELSE 'ikke_genfundet' END AS udfald,
         CASE WHEN (SELECT fase FROM prm)='foer_parter' AND g.art IN ('aegteskab','foraelder','barn') THEN 'afventer_parter'
              WHEN u.n=0 THEN 'ingen' WHEN u.n>1 THEN 'flere'
              WHEN (SELECT count(*) FROM okp o WHERE o.ny::text=u.ny1)>1 THEN 'delt' END AS grund,
         u.ny1
    FROM udf u JOIN gv g ON g.key=u.key
), rk AS (
  SELECT g.key,jsonb_agg(n.key::text ORDER BY n.key::text COLLATE "C") AS kandidater
    FROM gv g
    JOIN nv n ON n.element_id=g.element_id AND n.predicate=g.predicate AND n.kind=g.kind AND n.persona_id=g.persona_id
   WHERE g.art='fakta' AND n.status NOT IN ('rejected','superseded')
     AND EXISTS (SELECT 1 FROM gb WHERE gb.key=g.key AND gb.target_type='assertion' AND gb.target_id=n.rettelse_maal)
   GROUP BY g.key
), nb AS MATERIALIZED (
  -- De nye nøglers gyldige bindinger, med samme prædikat som revisionen og kvitteringens writer.
  SELECT t.target_type,t.interpretation_key AS key,t.target_id::bigint AS target_id
    FROM private.text_revision_binding_set(ARRAY(SELECT key FROM nv)) t
), bo AS (
  SELECT gb.promotion_id,gb.target_type,gb.target_id,gb.key,u.udfald,
         CASE WHEN u.udfald='genfundet' THEN u.ny1 END AS ny_noegle,
         EXISTS (SELECT 1 FROM nb WHERE u.udfald='genfundet' AND nb.key::text=u.ny1
                   AND nb.target_type=gb.target_type AND nb.target_id=gb.target_id) AS ny_binding,
         EXISTS (SELECT 1 FROM nb JOIN nv n ON n.key=nb.key
                  JOIN gv g ON g.key=gb.key AND n.element_id=g.element_id AND n.predicate=g.predicate
                 WHERE nb.target_type=gb.target_type AND nb.target_id=gb.target_id
                   AND (u.udfald<>'genfundet' OR nb.key::text<>u.ny1)) AS fremmed_binding
    FROM gb JOIN udf2 u ON u.key=gb.key
), pk AS (
  SELECT id::text AS id,persona_key FROM private.source_persona
   WHERE id IN (SELECT persona_id FROM gv UNION SELECT persona_id FROM nv)
      OR id::text IN (SELECT x FROM (SELECT principal FROM gv UNION SELECT spouse FROM gv UNION SELECT parent FROM gv
                                     UNION SELECT principal FROM nv UNION SELECT spouse FROM nv
                                     UNION SELECT parent FROM nv) y(x) WHERE x IS NOT NULL)
), ds AS (
  SELECT CASE WHEN (SELECT fase FROM prm)<>'foer_parter' THEN
           (SELECT coalesce(jsonb_agg(x#>>'{state,interpretation,interpretation_key}'
                                      ORDER BY x#>>'{state,interpretation,interpretation_key}' COLLATE "C"),'[]'::jsonb)
              FROM jsonb_array_elements(private.relation_decision_set((SELECT source_id FROM bat))->'items') x)
         END AS keys
), j0 AS (
  SELECT jsonb_build_object(
    'contract','tekstrevision-afstemning-v1',
    'fase',(SELECT fase FROM prm),
    'source_id',(SELECT source_id FROM bat),
    'poster',coalesce((SELECT jsonb_agg(jsonb_build_object('element_id',ev.element_id,'record_key',ev.record_key,
                 'superseded',jsonb_array_length(ev.sk),'binding_loss',jsonb_array_length(ev.bl))
                 ORDER BY ev.element_id COLLATE "C") FROM ev),'[]'::jsonb),
    'gamle',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_key',g.key::text,'version',g.version,'status',g.status,'status_foer',g.status_foer,
        'element_id',g.element_id,'record_key',g.record_key,'predicate',g.predicate,'art',g.art,
        'persona',(SELECT persona_key FROM pk WHERE pk.id=g.persona_id::text),
        'principal',(SELECT persona_key FROM pk WHERE pk.id=g.principal),
        'modpart',(SELECT persona_key FROM pk WHERE pk.id=coalesce(g.spouse,g.parent)),
        'marriage_ordinal',g.ordinal,
        'bindinger',coalesce((SELECT jsonb_agg(jsonb_build_object('promotion_id',b.promotion_id::text,
                       'target_type',b.target_type,'target_id',b.target_id) ORDER BY b.promotion_id::text COLLATE "C")
                       FROM gb b WHERE b.key=g.key),'[]'::jsonb),
        'kandidater',u.kandidater,
        'rettelse_kandidater',coalesce((SELECT r.kandidater FROM rk r WHERE r.key=g.key),'[]'::jsonb),
        'udfald',u.udfald,'grund',u.grund,'ny_noegle',CASE WHEN u.udfald='genfundet' THEN u.ny1 END)
        ORDER BY g.key::text COLLATE "C") FROM gv g JOIN udf2 u ON u.key=g.key),'[]'::jsonb),
    'nye',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'interpretation_key',n.key::text,'version',n.version,'status',n.status,'element_id',n.element_id,
        'record_key',n.record_key,'predicate',n.predicate,
        'persona',(SELECT persona_key FROM pk WHERE pk.id=n.persona_id::text),
        'principal',(SELECT persona_key FROM pk WHERE pk.id=n.principal),
        'modpart',(SELECT persona_key FROM pk WHERE pk.id=coalesce(n.spouse,n.parent)),
        'marriage_ordinal',n.ordinal,
        'familie',CASE n.predicate WHEN 'relation.marriage' THEN n.st_familie WHEN 'relation.parent' THEN n.foraelder_familie
                                   WHEN 'relation.child' THEN n.barn_familie END,
        'binding_familie',CASE WHEN n.predicate='relation.parent' THEN n.st_familie END)
        ORDER BY n.key::text COLLATE "C") FROM nv n),'[]'::jsonb),
    'bindinger',coalesce((SELECT jsonb_agg(jsonb_build_object(
        'promotion_id',b.promotion_id::text,'target_type',b.target_type,'target_id',b.target_id,
        'gammel_noegle',b.key::text,'udfald',b.udfald,'ny_noegle',b.ny_noegle,'ny_binding',b.ny_binding,
        'fremmed_binding',b.fremmed_binding) ORDER BY b.promotion_id::text COLLATE "C") FROM bo b),'[]'::jsonb),
    'aegteskab_afgoerelsessaet',(SELECT keys FROM ds),
    'antal',jsonb_build_object(
      'gamle',(SELECT count(*) FROM gv),'nye',(SELECT count(*) FROM nv),'bindinger',(SELECT count(*) FROM gb),
      'genfundet',(SELECT count(*) FROM udf2 WHERE udfald='genfundet'),
      'ikke_genfundet',(SELECT count(*) FROM udf2 WHERE udfald='ikke_genfundet'),
      'afventer',(SELECT count(*) FROM udf2 WHERE udfald='afventer'),
      'ny_binding',(SELECT count(*) FROM bo WHERE ny_binding))) AS j
), j AS (
  -- Den logiske hash dækker alt undtagen batch-id'et (tilfældigt pr. base), så stand-in og prod kan sammenlignes.
  SELECT j0.j||jsonb_build_object('batch_id',(SELECT batch::text FROM prm),
           'logisk_sha256',private.reimport_canonical_json_sha256(j0.j)) AS j FROM j0
)
SELECT set_config('daa.tekstrevision_afstemning',j::text,false) AS afstemning FROM j;
\if :{?afstemning_inline}
\else
ROLLBACK;
\endif
