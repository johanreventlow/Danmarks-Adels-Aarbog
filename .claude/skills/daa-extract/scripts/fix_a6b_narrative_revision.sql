-- A6b (plan 2026-10-28-a6b-noise-re-narrativer.md, Task 3; decisions 2026-10-28): reviderer de publicerede 2018-20-
-- narrativer, som v1-støjreglen beskar, i ÉN transaktion med redaktør-RPC'en red_revider_publiceret_person_narrative_record
-- (ny narrative_publication_event med før- og eftertilstand; intet overskrives uden audit). Kildetekst og klausuler
-- røres ikke (trin 6). Fortrydelse = samme script med retning=tilbage (ny tekst -> gammel tekst).
-- Manifestet (build_narrative_revision_manifest.py) indlæses klientside; det rummer posttekst. Teksten indsættes aldrig
-- som literal i en sætning: RPC-kaldene henter den fra en temp-tabel, så den ikke kan stå i en fejlmeddelelse.
-- Forhåndsbetingelser `A6B_PRE_*`, efterbetingelser `A6B_POST_*`.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v src=1 -v manifest_path=<fil> -v manifest_sha=<manifestets
--   manifest_sha256> -v go=<GO-kode> -v retning=frem|tilbage -v bundne=<nøgler, kommasepareret>
--   -v ubundne=<nøgler, kommasepareret> -f fix_a6b_narrative_revision.sql
\set QUIET on
\set ON_ERROR_STOP on
\set m `cat :'manifest_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'A6B_PRE_TIMEOUT'; END IF; END $timeout$;
DO $kontekst$ BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'A6B_PRE_AUDIT_KONTEKST'; END IF;
END $kontekst$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('a6b.src', :'src', true),
       set_config('a6b.go', :'go', true), set_config('a6b.manifest_sha', :'manifest_sha', true),
       set_config('a6b.retning', :'retning', true), set_config('a6b.bundne', :'bundne', true),
       set_config('a6b.ubundne', :'ubundne', true) \g /dev/null
CREATE TEMP TABLE a6b_input ON COMMIT DROP AS SELECT :'m'::jsonb AS m;

-- Én række pr. manifestelement. fra/til følger retningen; person og narrativ kun for bundne poster.
CREATE TEMP TABLE a6b_post (rk text PRIMARY KEY, person_id bigint, narrative_id bigint, fra_text text, til_text text,
  fra_sha text, til_sha text, state jsonb, events_foer uuid[]) ON COMMIT DROP;

DO $pre$
DECLARE v_m jsonb:=(SELECT m FROM a6b_input); v_src bigint:=current_setting('a6b.src')::bigint;
  v_frem boolean; v_bundne text[]; v_ubundne text[]; r record; v_cur text;
BEGIN
  IF current_setting('a6b.retning') NOT IN ('frem','tilbage') THEN RAISE EXCEPTION 'A6B_PRE_RETNING'; END IF;
  v_frem:=current_setting('a6b.retning')='frem';
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id=current_setting('request.jwt.claim.sub')::uuid
                                                AND rolle='redaktion') THEN
    RAISE EXCEPTION 'A6B_PRE_ROLLE'; END IF;
  IF v_m->>'kind' IS DISTINCT FROM 'narrative_revision' OR (v_m->>'source_id')::bigint IS DISTINCT FROM v_src
     OR v_m->>'manifest_sha256' IS DISTINCT FROM current_setting('a6b.manifest_sha') THEN
    RAISE EXCEPTION 'A6B_PRE_MANIFEST_SHA'; END IF;

  -- Lås alle manifestets source records, også den ubundne, før bindingerne læses: FOR UPDATE blokerer nye bindinger
  -- (en FK-indsættelse tager FOR KEY SHARE på posten), så mængderne nedenfor afgøres på en tilstand, der holder.
  IF (SELECT count(*) FROM (SELECT 1 FROM private.source_record sr
                             WHERE sr.source_id=v_src
                               AND sr.record_key IN (SELECT x->>'record_key' FROM jsonb_array_elements(v_m->'elements') x)
                             ORDER BY sr.record_key COLLATE "C" FOR UPDATE) l)
     <> jsonb_array_length(v_m->'elements') THEN
    RAISE EXCEPTION 'A6B_PRE_MAENGDE'; END IF;

  INSERT INTO a6b_post (rk, person_id, narrative_id, fra_text, til_text, fra_sha, til_sha)
  SELECT x->>'record_key', n.subjekt_id, n.id,
         CASE WHEN v_frem THEN x->>'old_text' ELSE x->>'new_text' END,
         CASE WHEN v_frem THEN x->>'new_text' ELSE x->>'old_text' END,
         CASE WHEN v_frem THEN x->>'old_sha256' ELSE x->>'new_sha256' END,
         CASE WHEN v_frem THEN x->>'new_sha256' ELSE x->>'old_sha256' END
    FROM jsonb_array_elements(v_m->'elements') x
    LEFT JOIN private.source_record sr ON sr.source_id=v_src AND sr.record_key=x->>'record_key'
    LEFT JOIN private.narrative_record_publication p ON p.source_record_id=sr.id
    LEFT JOIN public.narrative n ON n.id=p.narrative_id AND n.subjekt_type='person';
  IF EXISTS (SELECT 1 FROM a6b_post WHERE encode(sha256(convert_to(fra_text,'UTF8')),'hex')<>fra_sha
                                       OR encode(sha256(convert_to(til_text,'UTF8')),'hex')<>til_sha) THEN
    RAISE EXCEPTION 'A6B_PRE_MANIFEST_SHA'; END IF;

  -- Lås og tilstand pr. bundet post (nøgleorden), derefter bindinger, mængder og tekst under låsene.
  FOR r IN SELECT rk, person_id FROM a6b_post WHERE narrative_id IS NOT NULL ORDER BY rk COLLATE "C" LOOP
    UPDATE a6b_post SET state=private.narrative_record_state(r.person_id, v_src, r.rk, true),
                        events_foer=(SELECT coalesce(array_agg(e.id),'{}') FROM private.narrative_publication_event e
                                      WHERE e.narrative_id=a6b_post.narrative_id)
     WHERE rk=r.rk;
  END LOOP;
  -- Bindingerne genlæses under låsene og skal være dem, der blev materialiseret.
  IF EXISTS (SELECT 1 FROM a6b_post p
               LEFT JOIN private.source_record sr ON sr.source_id=v_src AND sr.record_key=p.rk
               LEFT JOIN private.narrative_record_publication pub ON pub.source_record_id=sr.id
               LEFT JOIN public.narrative n ON n.id=pub.narrative_id AND n.subjekt_type='person'
              WHERE n.id IS DISTINCT FROM p.narrative_id OR n.subjekt_id IS DISTINCT FROM p.person_id) THEN
    RAISE EXCEPTION 'A6B_PRE_MAENGDE'; END IF;

  -- Mængder, ikke antal: præcis de godkendte bundne og ubundne nøgler.
  v_bundne:=string_to_array(current_setting('a6b.bundne'),',');
  v_ubundne:=string_to_array(current_setting('a6b.ubundne'),',');
  IF (SELECT coalesce(array_agg(rk ORDER BY rk),'{}') FROM a6b_post WHERE narrative_id IS NOT NULL)
       IS DISTINCT FROM (SELECT coalesce(array_agg(k ORDER BY k),'{}') FROM unnest(v_bundne) k)
     OR (SELECT coalesce(array_agg(rk ORDER BY rk),'{}') FROM a6b_post WHERE narrative_id IS NULL)
       IS DISTINCT FROM (SELECT coalesce(array_agg(k ORDER BY k),'{}') FROM unnest(v_ubundne) k) THEN
    RAISE EXCEPTION 'A6B_PRE_MAENGDE'; END IF;
  IF NOT EXISTS (SELECT 1 FROM a6b_post p JOIN public.narrative n ON n.id=p.narrative_id
                  WHERE encode(sha256(convert_to(n.tekst,'UTF8')),'hex')<>p.til_sha) THEN
    RAISE EXCEPTION 'A6B_PRE_ALLEREDE_ANVENDT'; END IF;
  FOR r IN SELECT p.rk, p.fra_sha, encode(sha256(convert_to(n.tekst,'UTF8')),'hex') AS cur, p.state
             FROM a6b_post p JOIN public.narrative n ON n.id=p.narrative_id ORDER BY p.rk COLLATE "C" LOOP
    IF r.cur<>r.fra_sha THEN RAISE EXCEPTION 'A6B_PRE_TEKST_DRIFT %', r.rk; END IF;
    IF r.state->>'publication_status' IS DISTINCT FROM 'published'
       OR NOT coalesce(r.state->'allowed_actions' ? 'publish_revision', false) THEN
      RAISE EXCEPTION 'A6B_PRE_STATUS %', r.rk; END IF;
  END LOOP;
END $pre$;

-- Skrivning: én klientdrevet sætning pr. bundet post; app.change_set_id ryddes før hvert kald (RPC'en afviser et
-- fremmed change_set). Tilstands-sha'en læses som ejer, sætningerne køres som redaktør; teksten hentes fra temp-tabellen.
CREATE TEMP TABLE a6b_kald ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY rk COLLATE "C") AS ord,
       format('SELECT set_config(%L,%L,true), public.red_revider_publiceret_person_narrative_record(%s,%s,%L,'
              '(SELECT til_text FROM a6b_post WHERE rk=%L),%L)',
              'app.change_set_id', '', person_id, current_setting('a6b.src')::bigint, rk, rk, state->>'state_sha256') AS stmt
  FROM a6b_post WHERE narrative_id IS NOT NULL;
GRANT SELECT ON a6b_kald, a6b_post TO authenticated;
SET LOCAL ROLE authenticated;
\o /dev/null
SELECT stmt FROM a6b_kald ORDER BY ord \gexec
\o
RESET ROLE;
SELECT set_config('app.change_set_id','',true) \g /dev/null

DO $post$
DECLARE v_src bigint:=current_setting('a6b.src')::bigint; r record; v_state jsonb; v_nye bigint; v_sets bigint;
BEGIN
  FOR r IN SELECT p.* FROM a6b_post p WHERE narrative_id IS NOT NULL ORDER BY rk COLLATE "C" LOOP
    v_state:=private.narrative_record_state(r.person_id, v_src, r.rk, false);
    IF v_state->>'publication_status' IS DISTINCT FROM 'published' THEN RAISE EXCEPTION 'A6B_POST_STATUS %', r.rk; END IF;
    IF (SELECT encode(sha256(convert_to(tekst,'UTF8')),'hex') FROM public.narrative WHERE id=r.narrative_id)<>r.til_sha THEN
      RAISE EXCEPTION 'A6B_POST_TEKST %', r.rk; END IF;
  END LOOP;
  -- Præcis én ny event pr. bundet narrativ, hver med sit eget change_set, og ingen nye events andre steder.
  SELECT count(*), count(DISTINCT e.change_set_id) INTO v_nye, v_sets
    FROM private.narrative_publication_event e JOIN a6b_post p ON p.narrative_id=e.narrative_id
   WHERE e.id <> ALL (p.events_foer);
  IF v_nye<>(SELECT count(*) FROM a6b_post WHERE narrative_id IS NOT NULL) OR v_sets<>v_nye THEN
    RAISE EXCEPTION 'A6B_POST_EVENTS nye=% sets=%', v_nye, v_sets; END IF;
  IF (SELECT array_agg(DISTINCT p.rk ORDER BY p.rk) FROM private.narrative_publication_event e
        JOIN a6b_post p ON p.narrative_id=e.narrative_id WHERE e.id <> ALL (p.events_foer))
     IS DISTINCT FROM (SELECT array_agg(k ORDER BY k) FROM unnest(string_to_array(current_setting('a6b.bundne'),',')) k) THEN
    RAISE EXCEPTION 'A6B_POST_MAENGDE'; END IF;
  PERFORM set_config('a6b.revideret', v_nye::text, true);
  PERFORM set_config('a6b.sets', v_sets::text, true);
END $post$;

SELECT 'A6B_OK retning='||current_setting('a6b.retning')||' revideret='||current_setting('a6b.revideret')
       ||' ubundet='||(SELECT count(*) FROM a6b_post WHERE narrative_id IS NULL)
       ||' change_sets='||current_setting('a6b.sets')||' go='||current_setting('a6b.go');
COMMIT;
