-- Nøglekort for 5a+5b-overførslen (plan B1 Task 1). Læse-kun; ingen CREATE (prod kører under
-- default_transaction_read_only). Oversætter hver uuid, kæden kan efterlade i en hashet række, til en nøgle af indholdet:
--   opslagsklasser (unikke nøgler; svaroverførslen slår op i dem): persona: fortolkning: kandidatkoersel: kandidat: kontrol:
--     foraelderkort: stikproeve: omtale: binding: disposition:
--   gennemstrømning (fælles med D1/prod): obs:<uuid>, ikey:<interpretation_key>, kildepost:<public_ref>, og d1:<uuid> som
--     fallback for enhver uuid-primærnøgle uden indholdsklasse (fundet via kataloget);
--   mange-til-én (tilfældige id'er uden indholdsnøgle): batch, autorisation, udtraek, haendelse, bindingsbatch;
--   profil:<sha256(uuid)[:16]> for public.profiles (aktøren): bruges i digests, men står aldrig i udskriften.
-- Selvstændigt: stdout-linjer »<uuid>|<nøgle>« sorteret COLLATE "C", unik på uuid; kalderen skriver dem til en 0600-fil
-- (linjerne bærer uuid'er). Med \set t5_km_included 1 (fra transfer_5ab_digests.sql) lægges kortet kun i daa.t5_km.
-- Tabeller, der ikke findes, springes over, så filen kører på ældre træer (b42266e) og beviskædens baser.
\set ON_ERROR_STOP on
\if :{?t5_km_included}
\else
BEGIN READ ONLY;
SET LOCAL search_path TO pg_catalog;
SET LOCAL TimeZone='UTC';
SET LOCAL DateStyle='ISO, MDY';
SET LOCAL IntervalStyle='postgres';
SET LOCAL extra_float_digits=1;
SET LOCAL row_security=off;
\endif
DO $km$
DECLARE
  parts text[]:='{}'; covered text[]:='{}'; r record; q text; km jsonb;
  -- Kørselsnøglen (kandidatkørsel) og personanøglen, genbrugt af flere klasser.
  runkey constant text:='(cr.input_sha256||'':''||cr.config_sha256)';
  pkey constant text:='(sp.source_id||'':''||sp.persona_key)';
BEGIN
  -- (<tabeller>, prio, cov, <sql med u uuid, k text>): klassen tages kun med, hvis tabellerne findes; cov = klassen dækker
  -- den første tabels primærnøgle (så d1:-fallback springer tabellen over).
  FOR r IN SELECT * FROM (VALUES
    ('{private.source_persona}', 1, true,
     format('SELECT sp.id u, ''persona:''||%s k FROM private.source_persona sp', pkey)),
    ('{private.interpretation}', 1, true,
     'SELECT i.id u, ''fortolkning:''||i.interpretation_key||''#''||i.version k FROM private.interpretation i'),
    ('{private.interpretation}', 2, false,
     'SELECT DISTINCT i.interpretation_key u, ''ikey:''||i.interpretation_key k FROM private.interpretation i'),
    ('{private.source_persona_identity_candidate_run}', 1, true,
     format('SELECT cr.id u, ''kandidatkoersel:''||%s k FROM private.source_persona_identity_candidate_run cr', runkey)),
    ('{private.source_persona_identity_candidate,private.source_persona_identity_candidate_run,private.source_persona}', 1, true,
     format('SELECT c.id u, ''kandidat:''||%s||'':''||%s||'':''||c.rank k FROM private.source_persona_identity_candidate c
               JOIN private.source_persona_identity_candidate_run cr ON cr.id=c.run_id JOIN private.source_persona sp ON sp.id=c.source_persona_id',
            runkey, pkey)),
    ('{private.identity_control_run,private.source_persona_identity_candidate_run}', 1, true,
     format('SELECT ic.id u, ''kontrol:''||%s k FROM private.identity_control_run ic
               JOIN private.source_persona_identity_candidate_run cr ON cr.id=ic.candidate_run_id', runkey)),
    ('{private.identity_control_parent_card,private.identity_control_run,private.source_persona_identity_candidate_run}', 1, true,
     format('SELECT pc.id u, ''foraelderkort:''||%s||'':''||pc.interpretation_key k FROM private.identity_control_parent_card pc
               JOIN private.identity_control_run ic ON ic.id=pc.control_run_id
               JOIN private.source_persona_identity_candidate_run cr ON cr.id=ic.candidate_run_id', runkey)),
    ('{private.identity_control_sample,private.identity_control_run,private.source_persona_identity_candidate_run,private.source_persona}', 1, true,
     format('SELECT s.id u, ''stikproeve:''||%s||'':''||s.sample_kind||'':''||coalesce(%s,''ikey:''||s.interpretation_key::text) k
               FROM private.identity_control_sample s JOIN private.identity_control_run ic ON ic.id=s.control_run_id
               JOIN private.source_persona_identity_candidate_run cr ON cr.id=ic.candidate_run_id
               LEFT JOIN private.source_persona sp ON sp.id=s.source_persona_id', runkey, pkey)),
    ('{private.source_persona_mention,private.source_persona}', 1, true,
     format('SELECT m.mention_id u, ''omtale:''||%s||'':''||m.mention_role||'':''||m.ordinal k FROM private.source_persona_mention m
               JOIN private.source_persona sp ON sp.id=m.persona_id', pkey)),
    ('{private.interpretation_promotion,private.interpretation}', 1, true,
     'SELECT p.id u, ''binding:''||i.interpretation_key||''#''||i.version||'':''||p.target_type||'':''||p.target_id||'':''||p.rule_key
             ||'':''||p.rule_version k FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id'),
    ('{private.clause_disposition}', 1, true,
     'SELECT d.id u, ''disposition:''||d.observation_id||''#''||d.version k FROM private.clause_disposition d'),
    ('{private.source_observation}', 1, true, 'SELECT o.id u, ''obs:''||o.id k FROM private.source_observation o'),
    ('{private.source_record}', 2, false,
     'SELECT r.public_ref u, ''kildepost:''||r.public_ref k FROM private.source_record r WHERE r.public_ref IS NOT NULL'),
    ('{public.profiles}', 1, true,
     'SELECT pr.id u, ''profil:''||left(encode(sha256(convert_to(pr.id::text,''UTF8'')),''hex''),16) k FROM public.profiles pr'),
    ('{private.reimport_batch}', 1, true, 'SELECT id u, ''batch'' k FROM private.reimport_batch'),
    ('{private.reimport_authorization}', 1, true, 'SELECT id u, ''autorisation'' k FROM private.reimport_authorization'),
    ('{private.extraction_run}', 1, true, 'SELECT id u, ''udtraek'' k FROM private.extraction_run'),
    ('{private.source_persona_identity_event}', 1, true, 'SELECT id u, ''haendelse'' k FROM private.source_persona_identity_event'),
    ('{private.interpretation_promotion_batch}', 1, true, 'SELECT id u, ''bindingsbatch'' k FROM private.interpretation_promotion_batch')
  ) v(tabs, prio, cov, sql) LOOP
    IF (SELECT bool_and(to_regclass(t) IS NOT NULL) FROM unnest(r.tabs::text[]) t) THEN
      parts:=parts||format('SELECT u, k, %s AS prio FROM (%s) x', r.prio, r.sql);
      IF r.cov THEN covered:=covered||(r.tabs::text[])[1]; END IF;
    END IF;
  END LOOP;
  -- d1:-fallback: hver uuid-primærnøgle (én kolonne) i private/public, hvis tabel ikke har en klasse ovenfor.
  FOR r IN SELECT format('%I.%I', n.nspname, c.relname) t, a.attname col
             FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
             JOIN pg_index i ON i.indrelid=c.oid AND i.indisprimary AND i.indnatts=1
             JOIN pg_attribute a ON a.attrelid=c.oid AND a.attnum=i.indkey[0] AND a.atttypid='uuid'::regtype
            WHERE n.nspname IN ('private','public') AND c.relkind IN ('r','p')
            ORDER BY n.nspname COLLATE "C", c.relname COLLATE "C" LOOP
    IF NOT r.t = ANY(covered) THEN
      parts:=parts||format('SELECT %1$I u, ''d1:''||%1$I k, 9 AS prio FROM %2$s', r.col, r.t);
    END IF;
  END LOOP;
  -- Unik på uuid: laveste prioritet og derefter nøgle vinder (omtale før d1 for samme mention; persona før d1 for identiteten).
  q:=format('SELECT coalesce(jsonb_object_agg(u, k), ''{}'') FROM (SELECT DISTINCT ON (u::text) u::text u, k FROM (%s) a
               WHERE u IS NOT NULL ORDER BY u::text, prio, k COLLATE "C") b', array_to_string(parts, ' UNION ALL '));
  EXECUTE q INTO km;
  PERFORM set_config('daa.t5_km', km::text, true);
END $km$;
\if :{?t5_km_included}
\else
SELECT e.key||'|'||e.value FROM jsonb_each_text(current_setting('daa.t5_km')::jsonb) e
 WHERE e.value NOT LIKE 'profil:%' ORDER BY e.key COLLATE "C";
COMMIT;
\endif
