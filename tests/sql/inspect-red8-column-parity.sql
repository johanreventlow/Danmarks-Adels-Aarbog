-- Review-handling A3 (fund 1b-01, B9): kolonnerne i de 25 RED-8-tabeller skal være ens i en frisk base
-- (schema.sql) og en migreret base (db-migrations.sql) — især id'ets identity-egenskaber, som schema.sql
-- manglede for 16 af tabellerne. Én linje pr. kolonne; kalderen tjekker antallet af tabeller (25), så en
-- manglende tabel ikke giver en falsk ens diff. Sekvensernes aktuelle værdi indgår ikke (afhænger af data).
\set ON_ERROR_STOP on
SELECT l FROM (
  SELECT c.table_name||'|'||c.column_name||'|'||c.data_type||'|'||c.is_nullable||'|'||c.is_identity||'|'||
         coalesce(c.identity_generation,'')||'|'||coalesce(c.column_default,'') AS l
    FROM information_schema.columns c
   WHERE c.table_schema='public'
     AND c.table_name IN ('assertion','change_event','change_set','citation','coat_of_arms','conclusion','estate',
       'fact','family','feed_pin','haendelse','historical_event','lineage','media','media_variant','narrative','note',
       'organisation','person','place','relation','repository','source','story','story_kilde')) x
 ORDER BY l COLLATE "C";
