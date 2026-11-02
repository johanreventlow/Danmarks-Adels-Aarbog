-- Læse-kun tidsmåling af fakta-kaldet for vej B (spec 2026-11-02 §4.1 pkt. 3): public.public_person_facts kaldes som
-- anon 5 gange pr. person, og hvert kald måles med clock_timestamp()-differencer i én plpgsql-blok.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v personer=<id>,<id>,... -f vejb_tid.sql
-- Udskrift, én linje pr. kald, i personlistens rækkefølge:
--   T6C2_VEJB person=<id> ms=<n>          (n = hele millisekunder, afrundet)
-- Kun id'er og tider: rækkerne tælles (PERFORM count(*)), ingen faktaværdi læses ud.
-- Rollen skiftes med SET LOCAL ROLE anon i en READ ONLY-transaktion, der rulles tilbage. SET ROLE giver ikke anon's
-- login-indstillinger (fx statement_timeout); tiden er fakta-kaldets egen. Medianen af de 5 kald pr. person beregnes
-- af runneren. Stand-in-tid er ikke prod-tid (memory »stand-in-tid er ikke prod-tid«); målet gælder prod.
-- Fejl: VEJB_PERSONER_MANGLER (ingen -v personer), VEJB_PERSONER_UGYLDIG (ikke en kommasepareret liste af heltal).
\set QUIET on
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\if :{?personer}
\else
DO $m$ BEGIN RAISE EXCEPTION 'VEJB_PERSONER_MANGLER'; END $m$;
\endif
BEGIN READ ONLY;
SELECT set_config('daa.t6c2_vejb_personer',:'personer',true) \g /dev/null
SET LOCAL ROLE anon;
DO $vejb$
DECLARE
  v_txt text := current_setting('daa.t6c2_vejb_personer');
  v_pid bigint;
  v_t0 timestamptz;
  v_ud text[] := '{}';
  i integer;
BEGIN
  IF v_txt IS NULL OR v_txt !~ '^\s*-?[0-9]+(\s*,\s*-?[0-9]+)*\s*$' THEN
    RAISE EXCEPTION 'VEJB_PERSONER_UGYLDIG';
  END IF;
  FOREACH v_pid IN ARRAY string_to_array(regexp_replace(v_txt,'\s','','g'),',')::bigint[] LOOP
    FOR i IN 1..5 LOOP
      v_t0 := clock_timestamp();
      PERFORM count(*) FROM public.public_person_facts(ARRAY[v_pid]);
      v_ud := v_ud || format('T6C2_VEJB person=%s ms=%s',v_pid,
                             round(extract(epoch FROM clock_timestamp()-v_t0)*1000)::bigint);
    END LOOP;
  END LOOP;
  PERFORM set_config('daa.t6c2_vejb_ud',array_to_string(v_ud,E'\n'),true);
END $vejb$;
SELECT current_setting('daa.t6c2_vejb_ud');
ROLLBACK;
