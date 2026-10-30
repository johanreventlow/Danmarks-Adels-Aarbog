-- Trin 6a: viewparitet mellem en frisk schema.sql-base og en base migreret med ÉN kørsel af db-migrations.sql.
-- Et view med `SELECT t.*` får kolonnelisten låst ved oprettelsen. Står viewet i db-migrations.sql før den
-- ALTER TABLE ADD COLUMN, der udvider tabellen, mangler kolonnen i den migrerede base, men ikke i den friske.
-- Én linje pr. view: navn|kolonneliste i rækkefølge|sha256(pg_get_viewdef). Kalderen tjekker antallet.
-- Alle views i public og private indgår: målt lokalt afviger ingen andre views end det, 6a rettede
-- (private.clause_observation_current), så listen behøver ingen indsnævring.
\set ON_ERROR_STOP on
SELECT l FROM (
  SELECT n.nspname||'.'||c.relname||'|'||
         coalesce((SELECT string_agg(a.attname,',' ORDER BY a.attnum) FROM pg_attribute a
                    WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped),'')||'|'||
         encode(sha256(convert_to(pg_get_viewdef(c.oid,true),'UTF8')),'hex') AS l
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE c.relkind='v' AND n.nspname IN ('public','private')) x
 ORDER BY l COLLATE "C";
