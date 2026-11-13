\set ON_ERROR_STOP on
-- Trin 6e-2 Task 1: sidekort. Syntetiske negative id'er; alt rulles tilbage.
BEGIN;
INSERT INTO public.source(id,titel,sidekort) VALUES
  (-6201,'sidekort-med-kort','[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1},{"pdf_fra":547,"pdf_til":548,"trykt_fra":57},{"pdf_fra":550,"pdf_til":555,"trykt_fra":59},{"pdf_fra":571,"pdf_til":598,"trykt_fra":65}]'),
  (-6202,'sidekort-uden-kort',NULL);
DO $t$
DECLARE r record; v text; n int := 0;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('490','1'),('541','52'),('545','56'),('546',NULL),('547','57'),('549',NULL),('550','59'),('555','64'),
    ('556',NULL),('570',NULL),('571','65'),('587','81'),('598','92'),('599',NULL),('4',NULL),('abc',NULL),
    ('541-542','52-53'),('555-571','64-65'),('546-547',NULL),('541-541','52'),('541-',NULL),(' 541',NULL),('1234567890',NULL),(NULL,NULL)
  ) AS x(inp,outp) LOOP
    v := public.source_trykt_side(-6201, r.inp);
    IF v IS DISTINCT FROM r.outp THEN
      RAISE EXCEPTION 'TEST_FAILED: source_trykt_side(%) = % (forventet %)', r.inp, v, r.outp;
    END IF;
    n := n + 1;
  END LOOP;
  IF public.source_trykt_side(-6202,'201-202') IS DISTINCT FROM '201-202' OR public.source_trykt_side(-6202,'4') IS DISTINCT FROM '4'
     OR public.source_trykt_side(-6202,NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED: kilde uden sidekort';
  END IF;
  RAISE NOTICE 'OK: % omregninger', n;
END $t$;
-- CHECK afviser ugyldige kort.
DO $t$
DECLARE bad text; n int := 0;
BEGIN
  FOREACH bad IN ARRAY ARRAY[
    '[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1},{"pdf_fra":540,"pdf_til":550,"trykt_fra":60}]',
    '[{"pdf_fra":550,"pdf_til":555,"trykt_fra":59},{"pdf_fra":490,"pdf_til":545,"trykt_fra":1}]',
    '[{"pdf_fra":490,"pdf_til":545}]',
    '[{"pdf_fra":545,"pdf_til":490,"trykt_fra":1}]',
    '[]','{}','"x"','[{"pdf_fra":"490","pdf_til":545,"trykt_fra":1}]','[{"pdf_fra":490,"pdf_til":545,"trykt_fra":1,"x":2}]',
    '[{"pdf_fra":490,"pdf_til":545,"trykt_fra":0}]','[{"pdf_fra":1.5,"pdf_til":545,"trykt_fra":1}]'
  ] LOOP
    BEGIN
      UPDATE public.source SET sidekort = bad::jsonb WHERE id = -6202;
      RAISE EXCEPTION 'TEST_FAILED: CHECK afviste ikke %', bad;
    EXCEPTION WHEN check_violation THEN n := n + 1;
    END;
  END LOOP;
  RAISE NOTICE 'OK: % ugyldige kort afvist', n;
END $t$;
-- side_trykt(citation) som computed field.
INSERT INTO public.citation(id,source_id,side) VALUES (-6201,-6201,'538'),(-6202,-6202,'538');
DO $t$
BEGIN
  IF (SELECT c.side_trykt FROM public.citation c WHERE c.id=-6201) IS DISTINCT FROM '49' THEN RAISE EXCEPTION 'TEST_FAILED: side_trykt med kort'; END IF;
  IF (SELECT public.side_trykt(c) FROM public.citation c WHERE c.id=-6202) IS DISTINCT FROM '538' THEN RAISE EXCEPTION 'TEST_FAILED: side_trykt uden kort'; END IF;
END $t$;
-- anon og authenticated kan kalde begge (INVOKER læser source.sidekort).
SET LOCAL ROLE anon;
DO $t$
BEGIN
  IF public.source_trykt_side(-6201,'541') IS DISTINCT FROM '52' THEN RAISE EXCEPTION 'TEST_FAILED: anon source_trykt_side'; END IF;
  -- række-literal: uafhængig af, om RLS lader anon se fixture-citationen
  IF public.side_trykt(ROW(-6201,NULL,-6201,'538',NULL,NULL,NULL)::public.citation) IS DISTINCT FROM '49' THEN RAISE EXCEPTION 'TEST_FAILED: anon side_trykt med kort'; END IF;
  IF public.side_trykt(ROW(-6202,NULL,-6202,'538',NULL,NULL,NULL)::public.citation) IS DISTINCT FROM '538' THEN RAISE EXCEPTION 'TEST_FAILED: anon side_trykt uden kort'; END IF;
END $t$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $t$
BEGIN
  IF public.source_trykt_side(-6201,'541') IS DISTINCT FROM '52' THEN RAISE EXCEPTION 'TEST_FAILED: authenticated source_trykt_side'; END IF;
  IF public.side_trykt(ROW(-6201,NULL,-6201,'538',NULL,NULL,NULL)::public.citation) IS DISTINCT FROM '49' THEN RAISE EXCEPTION 'TEST_FAILED: authenticated side_trykt'; END IF;
END $t$;
RESET ROLE;
ROLLBACK;
