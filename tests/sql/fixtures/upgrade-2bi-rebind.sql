-- Trin 5b 2b-i Task 8 (spec §10): efter opgraderingen fra 2a — genbind O1 efter en ordinal-rettelse og skriv
-- ordinal_beholdt for O2. Data fra spouse-exception-2bi.sql (kilde -21501), bundet med 2a-koden. Committes.
\set ON_ERROR_STOP on
BEGIN;
DO $upgrade_2bi_rebind$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b0501'; v_o1 uuid; v_o2 uuid; v_fam bigint; v_old uuid; v_old_state text;
  items jsonb; pv jsonb; v_new uuid;
BEGIN
  -- O1 = ægteskabet med bogens nr. 2 (hovedperson -21505), O2 = bogens nr. 3 (hovedperson -21507)
  SELECT ic.id,(private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint INTO v_o1,v_fam
    FROM private.interpretation_current ic WHERE ic.source_id=-21501 AND ic.predicate='relation.marriage' AND ic.status='accepted'
     AND (private.relation_binding_state(ic.id)->>'book_ordinal')::int=2;
  SELECT ic.id INTO v_o2 FROM private.interpretation_current ic WHERE ic.source_id=-21501 AND ic.predicate='relation.marriage'
     AND ic.status='accepted' AND (private.relation_binding_state(ic.id)->>'book_ordinal')::int=3;
  SELECT id,evidence->>'state_sha256' INTO v_old,v_old_state FROM private.interpretation_promotion
   WHERE interpretation_id=v_o1 AND target_type='family';
  IF v_o1 IS NULL OR v_o2 IS NULL OR v_old IS NULL THEN RAISE EXCEPTION 'UPGRADE_2BI_FAILED: fixturen mangler'; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_set_familie_ordinal(v_fam,-21505,'partner',2);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_o1::text,'family_id',v_fam));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-21501,items);
  PERFORM red_promote_relation_interpretations_batch(-21501,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT id INTO v_new FROM private.interpretation_promotion WHERE interpretation_id=v_o1 AND target_type='family' AND id<>v_old;
  IF (SELECT count(*) FROM private.interpretation_promotion WHERE interpretation_id=v_o1 AND target_type='family')<>2
     OR (SELECT evidence->>'supersedes_promotion_id' FROM private.interpretation_promotion WHERE id=v_new) IS DISTINCT FROM v_old::text
     OR (SELECT evidence->>'state_sha256' FROM private.interpretation_promotion WHERE id=v_old) IS DISTINCT FROM v_old_state THEN
    RAISE EXCEPTION 'UPGRADE_2BI_FAILED: genbindingen efter opgraderingen';
  END IF;
  PERFORM private.append_relation_classification(v_o2,'ordinal_beholdt','{"line":1,"note":"opgraderingstest"}');
END $upgrade_2bi_rebind$;
COMMIT;
