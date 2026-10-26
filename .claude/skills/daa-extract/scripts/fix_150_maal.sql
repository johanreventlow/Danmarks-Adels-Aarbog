-- #150 trin 5c-1 (spec 2026-10-26-trin5c-placement-membership-design.md): læsemåling før og efter DDL og dataceremoni.
-- Udskriver tal (ingen navne) og til sidst `FIX150 ddl=<foer|efter> fase=<foer|bundet|ukendt>`. Ledger-tabellen og
-- membership-funktionerne slås op dynamisk, så filen kan køre før placement-blokkens DDL.
-- Brug (læsetransaktion): psql -X -At -v ON_ERROR_STOP=1 -v src=1 -f fix_150_maal.sql
\set QUIET on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '15min';
SELECT set_config('fix150.src', :'src', true) \g /dev/null
WITH k AS (SELECT current_setting('fix150.src')::bigint AS src),
d AS (SELECT to_regclass('private.legacy_placement_disposition') IS NOT NULL AS ddl),
t AS (
  SELECT
    (SELECT count(*) FROM public.person_external_id pe, k WHERE pe.source_id=k.src) AS pei_src,
    (SELECT count(*) FROM public.person_external_id) AS pei_alle,
    (SELECT count(*) FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id, k
      WHERE r.source_id=k.src AND pc.decision_status='accepted') AS record_placements,
    (SELECT count(*) FROM private.source_persona_placement_current pc
       JOIN private.source_record_placement rp ON rp.id=pc.record_placement_id
       JOIN private.source_record r ON r.id=rp.source_record_id, k
      WHERE r.source_id=k.src AND pc.decision_status='accepted' AND pc.placement_role='principal_member') AS persona_placements,
    (SELECT count(*) FROM private.source_persona_placement_current pc
       JOIN private.source_record_placement rp ON rp.id=pc.record_placement_id
       JOIN private.source_record r ON r.id=rp.source_record_id
       JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted', k
      WHERE r.source_id=k.src AND pc.decision_status='accepted' AND pc.placement_role='principal_member') AS med_identitet,
    (SELECT count(*) FROM private.source_observation o, k
      WHERE o.observation_kind IN ('header_linje','header_slaegtled','header_kuld','header_aegteskab')
        AND EXISTS (SELECT 1 FROM private.extraction_run r WHERE r.id=o.extraction_run_id AND r.source_id=k.src)) AS headers,
    CASE WHEN (SELECT ddl FROM d) THEN (xpath('/row/n/text()', query_to_xml(
      'SELECT count(*) AS n FROM private.legacy_placement_disposition_current WHERE is_current', false, true, '')))[1]::text::bigint
      ELSE 0 END AS ledger_gaeldende,
    CASE WHEN (SELECT ddl FROM d) THEN (xpath('/row/n/text()', query_to_xml(
      'SELECT count(*) AS n FROM private.legacy_placement_disposition', false, true, '')))[1]::text::bigint
      ELSE 0 END AS ledger_raekker,
    (SELECT count(*) FROM public.person_lineage_membership WHERE source_basis->>'rule_version'='placement-membership-v1')
      AS memberships,
    CASE WHEN (SELECT ddl FROM d) THEN (xpath('/row/n/text()', query_to_xml(
      'SELECT private.placement_membership_not_current() AS n', false, true, '')))[1]::text::bigint
      ELSE 0 END AS ikke_gaeldende,
    (SELECT string_agg(DISTINCT s.status, ',') FROM public.slaegt s JOIN public.lineage_scheme ls ON ls.slaegt_id=s.id, k
      WHERE ls.source_id=k.src) AS slaegt_status
), p AS (
  SELECT s->>'publication_status' AS status, count(*) AS n
    FROM public.person_external_id pe, k,
         LATERAL private.narrative_record_state(pe.person_id, pe.source_id, pe.record_key) s
   WHERE pe.source_id=k.src AND pe.record_key IS NOT NULL
   GROUP BY 1
)
SELECT format('pei_src=%s pei_alle=%s headers=%s record_placements=%s persona_placements=%s ledger_raekker=%s ledger_gaeldende=%s memberships=%s ikke_gaeldende=%s slaegt=%s',
              pei_src, pei_alle, headers, record_placements, persona_placements, ledger_raekker, ledger_gaeldende, memberships,
              ikke_gaeldende, slaegt_status)
       ||E'\npublicering '||coalesce((SELECT string_agg(status||'='||n, ' ' ORDER BY status) FROM p), '-')
       ||E'\nFIX150 ddl='||CASE WHEN (SELECT ddl FROM d) THEN 'efter' ELSE 'foer' END
       ||' fase='||CASE
          WHEN record_placements=0 AND persona_placements=0 AND headers=0 AND ledger_raekker=0 AND memberships=0 THEN 'foer'
          WHEN record_placements>0 AND persona_placements<=record_placements AND ledger_gaeldende=pei_alle
               AND ledger_raekker=pei_alle AND memberships=med_identitet AND ikke_gaeldende=0 AND slaegt_status='active'
               AND coalesce((SELECT n FROM p WHERE status='stale_published'),0)=0 THEN 'bundet'
          ELSE 'ukendt' END
  FROM t;
COMMIT;
