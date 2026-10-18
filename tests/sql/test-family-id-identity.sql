-- Trin 5b 2b-ii (#151, spec §4): family.id er identity, og sekvensen ligger ikke bag max(id).
\set ON_ERROR_STOP on
BEGIN;
DO $family_id$
DECLARE f1 bigint; f2 bigint; v_seq text; v_last bigint; v_called boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='family'
                  AND column_name='id' AND is_identity='YES') THEN
    RAISE EXCEPTION 'FAMILY_ID_TEST_FAILED: ikke identity';
  END IF;
  INSERT INTO family(type) VALUES ('vielse') RETURNING id INTO f1;
  INSERT INTO family(type) VALUES ('vielse') RETURNING id INTO f2;
  IF f1 IS NULL OR f2 IS NULL OR f1=f2 THEN RAISE EXCEPTION 'FAMILY_ID_TEST_FAILED: id'; END IF;
  v_seq:=pg_get_serial_sequence('public.family','id');
  EXECUTE format('SELECT last_value,is_called FROM %s',v_seq) INTO v_last,v_called;
  IF (SELECT max(id) FROM family) > (CASE WHEN v_called THEN v_last ELSE v_last-1 END) THEN
    RAISE EXCEPTION 'FAMILY_ID_TEST_FAILED: sekvens bag max';
  END IF;
  RAISE NOTICE 'OK: family.id identity og sekvens';
END $family_id$;
ROLLBACK;
