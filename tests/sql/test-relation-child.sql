-- Trin 5b 2b-iii (spec 2026-10-20): børnehenvisninger. Kun opdigtede navne. Kører i writer-1939-v50-db.
\set ON_ERROR_STOP on
BEGIN;
DO $child_ref$
DECLARE r jsonb;
BEGIN
  -- interval, slægtled, romertal
  r:=private.relation_child_ref('12 børn: Tolvte slægtled, III, nr. 34-45');
  IF r IS DISTINCT FROM '{"count":12,"sex":null,"uncertain":false,"gen_local":12,"gen_through":null,"section":"III","nr_from":34,"nr_to":45}'::jsonb THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: interval %',r; END IF;
  -- test_ref_enkelt_nummer: Datter, enkelt nummer ⇒ nr_to=nr_from, køn kvinde
  r:=private.relation_child_ref('Datter: Fjortende slægtled, V, nr. 119');
  IF r->>'count'<>'1' OR r->>'sex'<>'kvinde' OR r->>'nr_from'<>'119' OR r->>'nr_to'<>'119' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: enkelt nummer %',r; END IF;
  -- parentes-slægtled, U+2011-bindestreg, intet romertal, punktum
  r:=private.relation_child_ref(E'9 børn: Andet (femtende) slægtled, nr. 1‑8.');
  IF r->>'gen_local'<>'2' OR r->>'gen_through'<>'15' OR r->>'section' IS NOT NULL OR r->>'nr_to'<>'8' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: parentes %',r; END IF;
  -- uden henvisning, usikker, sønner
  r:=private.relation_child_ref('3 sønner (?)');
  IF r->>'count'<>'3' OR r->>'sex'<>'mand' OR NOT (r->>'uncertain')::boolean OR r->>'nr_from' IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: usikker %',r; END IF;
  -- æøå uafhængigt af databasens locale (Opus plan-review fund 2)
  IF private.relation_child_ref('2 børn: Første slægtled, I, nr. 1-2')->>'gen_local'<>'1' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: første'; END IF;
  IF private.relation_child_ref('17 børn')->>'count'<>'17' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: kun antal'; END IF;
  -- uden for grammatikken ⇒ NULL
  IF private.relation_child_ref('X') IS NOT NULL OR private.relation_child_ref('se nedenfor') IS NOT NULL
     OR private.relation_child_ref('2 børn: Tolvte slægtled, III, nr. 9-3') IS NOT NULL      -- omvendt interval
     OR private.relation_child_ref('2 børn: Hundrede slægtled, III, nr. 1-2') IS NOT NULL   -- ukendt ordenstal
     OR private.relation_child_ref('0 børn') IS NOT NULL
     OR private.relation_child_ref('300 børn: Andet slægtled, I, nr. 1-300') IS NOT NULL    -- urimeligt interval
     OR private.relation_child_ref(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: uden for grammatikken'; END IF;
END $child_ref$;
ROLLBACK;
\echo RELATION_CHILD_TEST_OK
