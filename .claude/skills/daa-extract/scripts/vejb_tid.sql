-- Læse-kun tidsmåling af fakta-kaldet for vej B (spec 2026-11-02 §4.1 pkt. 3): public.public_person_facts kaldes som
-- anon 5 gange pr. person. Hvert kald er sit eget SQL-udsagn (genereret og kørt med \gexec), så statement_timeout
-- (prod: 2 min) gælder pr. kald, og linjerne for de kald, der nåede at køre, er skrevet ud, hvis et kald stopper.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v personer=<id>,<id>,... -f vejb_tid.sql
-- Udskrift, én linje pr. kald, i personlistens rækkefølge:
--   T6C2_VEJB person=<id> ms=<n>          (n = hele millisekunder, afrundet)
-- Tiden er clock_timestamp()-differencen inde i udsagnet: t0 tages i en materialiseret CTE, fakta-kaldet afhænger
-- lateralt af den (kører altså efter t0), og sluttiden tages i projektionen. Kun id'er og tider: rækkerne tælles
-- (count(*)), ingen faktaværdi læses ud.
-- Tiden er en nedre grænse: rækkerne overføres ikke til klienten (kun en optælling), og planlægningen af
-- funktionens interne forespørgsler (plpgsql-plancache pr. session) ses kun i det første kald.
-- Rollen skiftes med SET LOCAL ROLE anon i en READ ONLY-transaktion, der rulles tilbage. SET ROLE giver ikke anon's
-- login-indstillinger (fx statement_timeout); sessionens gælder. Medianen af de 5 kald pr. person beregnes af
-- runneren. Stand-in-tid er ikke prod-tid (memory »stand-in-tid er ikke prod-tid«); målet gælder prod.
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
DO $v$
BEGIN
  IF current_setting('daa.t6c2_vejb_personer') !~ '^\s*-?[0-9]+(\s*,\s*-?[0-9]+)*\s*$' THEN
    RAISE EXCEPTION 'VEJB_PERSONER_UGYLDIG';
  END IF;
END $v$;
SET LOCAL ROLE anon;
SELECT format($q$WITH t AS MATERIALIZED (SELECT clock_timestamp() AS t0),
  f AS MATERIALIZED (SELECT count(*) AS n
                       FROM t CROSS JOIN LATERAL public.public_person_facts(
                              CASE WHEN t.t0 IS NOT NULL THEN ARRAY[%s]::bigint[] END) x)
SELECT format('T6C2_VEJB person=%%s ms=%%s',%s,round(extract(epoch FROM clock_timestamp()-t.t0)*1000)::bigint)
  FROM t, f$q$,u.pid,u.pid)
  FROM unnest(string_to_array(regexp_replace(current_setting('daa.t6c2_vejb_personer'),'\s','','g'),',')::bigint[])
       WITH ORDINALITY u(pid,o)
       CROSS JOIN generate_series(1,5) g
 ORDER BY u.o,g \gexec
ROLLBACK;
