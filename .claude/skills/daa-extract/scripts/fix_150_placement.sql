-- #150 trin 5c-1 (spec 2026-10-26-trin5c-placement-membership-design.md §4-§6, GO 2): overskrifts-forekomster,
-- placements, legacy-ledger, slægtens status, memberships og revalidering af kildens publicerede biografier i ÉN
-- transaktion, så læseren aldrig ser `stale_published`. Ceremonien bruger de genbrugelige private funktioner fra
-- placement-blokken (write_header_evidence, write_record_placement, write_persona_placement, record_legacy_disposition)
-- og redaktør-RPC'erne (membership-promotion, red_revalider_person_narrative_record), så trin 6 kan genbruge dem.
-- Forhåndsbetingelser `FIX150_PRE_*`, efterbetingelser `FIX150_POST_*`.
-- Manifestet (build_header_manifest.py) og afgørelsesfilen (token-filens godkendte poster) indlæses klientside; de
-- kan nævne levende ægtefæller, så runneren sender stderr til en privat fil.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v src=1 -v manifest_path=<fil> -v approvals_path=<fil>
--   -v manifest_sha=<sha256 af manifestfilen> -v approvals_sha=<sha256 af afgørelsesfilen> -v go=<GO-kode>
--   -v rendition_sha=<renditionens content_sha256> -v expect_headers=N -v expect_placements=N -v expect_published=N
--   -v expect_bindings=N -v expect_ledger=N -v expect_revalidated=N -v expect_memberships=N -f fix_150_placement.sql
-- En post uden hovedperson-persona (prod: de 4 sidste poster i linje I-IV) får record-placement og ledger mapped, men
-- hverken persona-placement eller membership (spec §5: record_label følger linjen).
\set QUIET on
\set ON_ERROR_STOP on
\set m `cat :'manifest_path'`
\set a `cat :'approvals_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'FIX150_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('fix150.src', :'src', true),
       set_config('fix150.go', :'go', true), set_config('fix150.manifest_sha', :'manifest_sha', true),
       set_config('fix150.approvals_sha', :'approvals_sha', true), set_config('fix150.rendition_sha', :'rendition_sha', true),
       set_config('fix150.expect', json_build_object('headers', :'expect_headers'::int, 'placements', :'expect_placements'::int,
         'published', :'expect_published'::int, 'bindings', :'expect_bindings'::int, 'ledger', :'expect_ledger'::int,
         'revalidated', :'expect_revalidated'::int, 'memberships', :'expect_memberships'::int)::text, true) \g /dev/null
CREATE TEMP TABLE fix150_input ON COMMIT DROP AS SELECT :'m'::jsonb AS m, :'a'::jsonb AS a;

-- Poster, der skrives: maskinelt enige eller godkendt i token-filen. Én række pr. post med record, persona og helpost.
CREATE TEMP TABLE fix150_post (record_key text PRIMARY KEY, p jsonb, basis text, record_id uuid, persona_id uuid,
  basis_obs uuid, person_id bigint, entry_id bigint, rp uuid, pp uuid) ON COMMIT DROP;
-- Publiceringstilstand og læserhashes før skrivningen.
CREATE TEMP TABLE fix150_foer (record_key text PRIMARY KEY, person_id bigint, status text, eligibility text, blocked boolean)
  ON COMMIT DROP;
CREATE TEMP TABLE fix150_paritet (laeser text PRIMARY KEY, foer text, efter text) ON COMMIT DROP;

-- Læserhashes (spec §6.3): redaktørlæserne som redaktør, de offentlige som ejer. regen_person_visning skriver cache;
-- den køres i et savepoint (en undtagelsesblok), hashen gemmes i en variabel, og cachen rulles tilbage.
CREATE FUNCTION pg_temp.fix150_paritet(p_kol text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_src bigint:=current_setting('fix150.src')::bigint; v_persons bigint[]; v_grid text; v_match text;
  v_fam text; v_bio text; v_regen text;
BEGIN
  SELECT array_agg(person_id ORDER BY person_id) INTO v_persons FROM public.person_external_id WHERE source_id=v_src;
  SET LOCAL ROLE authenticated;
  v_grid:=(SELECT md5(string_agg(g::text, '|' ORDER BY g::text)) FROM public.red_person_grid() g);
  v_match:=md5(public.red_match_personer()::text);
  RESET ROLE;
  v_fam:=(SELECT md5(string_agg(s::text, '|' ORDER BY s::text))
            FROM public.public_family_sources(ARRAY(SELECT id FROM public.family ORDER BY id)) s);
  v_bio:=(SELECT md5(string_agg(s::text, '|' ORDER BY s::text)) FROM public.public_person_bio_source_versions_v2(v_persons) s);
  BEGIN
    PERFORM public.regen_person_visning(x) FROM unnest(v_persons) x;
    v_regen:=(SELECT md5(string_agg(row(p.id,p.visning_navn,p.visning_foedt,p.visning_doed,p.visning_titel,
                                        p.visning_efternavn,p.visning_fuldt_navn)::text, '|' ORDER BY p.id))
                FROM public.person p WHERE p.id=ANY(v_persons));
    RAISE EXCEPTION 'FIX150_PARITET_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'FIX150_PARITET_ROLLBACK' THEN RAISE; END IF;
  END;
  EXECUTE format('INSERT INTO fix150_paritet(laeser,%1$I) SELECT * FROM unnest(%2$L::text[],%3$L::text[])
                  ON CONFLICT (laeser) DO UPDATE SET %1$I=excluded.%1$I', p_kol,
    ARRAY['red_person_grid','red_match_personer','public_family_sources','public_person_bio_source_versions_v2',
          'regen_person_visning'], ARRAY[coalesce(v_grid,'tom'),coalesce(v_match,'tom'),coalesce(v_fam,'tom'),
          coalesce(v_bio,'tom'),coalesce(v_regen,'tom')]);
END $f$;

DO $pre$
DECLARE v_src bigint:=current_setting('fix150.src')::bigint; e jsonb:=current_setting('fix150.expect')::jsonb;
  m jsonb:=(SELECT m FROM fix150_input); a jsonb:=(SELECT a FROM fix150_input); v_n bigint; v_entry bigint;
BEGIN
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'FIX150_PRE_ROLE'; END IF;
  IF to_regclass('private.legacy_placement_disposition') IS NULL
     OR to_regprocedure('public.red_promote_placement_memberships(bigint,text)') IS NULL THEN RAISE EXCEPTION 'FIX150_PRE_DDL'; END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'FIX150_PRE_GUC'; END IF;
  -- Fase: intet skrevet for kilden endnu (genkørsel stopper her).
  IF EXISTS (SELECT 1 FROM private.source_record_placement rp JOIN private.source_record r ON r.id=rp.source_record_id
              WHERE r.source_id=v_src)
     OR EXISTS (SELECT 1 FROM private.legacy_placement_disposition)
     OR EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE source_basis->>'rule_version'='placement-membership-v1') THEN
    RAISE EXCEPTION 'FIX150_PRE_FASE';
  END IF;
  -- Manifestet: regelversion, alle strukturinvarianter sande (fail-closed for hele kørslen), afgørelsesfilens poster
  -- findes i manifestet som unresolved.
  IF m->>'header_rule_version' IS DISTINCT FROM 'header-2018-20-v1' OR jsonb_typeof(m->'invariants')<>'object'
     OR EXISTS (SELECT 1 FROM jsonb_each_text(m->'invariants') i WHERE i.value<>'true')
     OR (SELECT count(*) FROM jsonb_each(m->'invariants'))<6 THEN
    RAISE EXCEPTION 'FIX150_PRE_INVARIANTS';
  END IF;
  IF jsonb_typeof(a->'record_keys')<>'array'
     OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(a->'record_keys') k
                 WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(m->'placements') p
                                    WHERE p->>'record_key'=k AND p->>'status'='unresolved')) THEN
    RAISE EXCEPTION 'FIX150_PRE_APPROVALS';
  END IF;
  -- Renditionen: præcis én for kilden med det bundne indhold.
  IF (SELECT count(*) FROM private.source_rendition WHERE source_id=v_src AND content_sha256=current_setting('fix150.rendition_sha'))<>1 THEN
    RAISE EXCEPTION 'FIX150_PRE_RENDITION';
  END IF;
  -- Hver entry i kildens stamtavle-schema har præcis én canonical-linje.
  FOR v_entry IN SELECT e.id FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
                  WHERE s.source_id=v_src AND s.kind='stamtavle' LOOP
    BEGIN PERFORM private.lineage_of_entry(v_entry);
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'FIX150_PRE_LINEAGE entry %', v_entry; END;
  END LOOP;
  -- Identitet = binding for ALLE bindinger med accepteret hovedperson-identitet, uanset manifeststatus (spec §4.5;
  -- en placement for en post, hvis identitet peger på en anden person, ville blokere bindingen).
  SELECT count(*) INTO v_n
    FROM private.narrative_record_publication b
    JOIN public.narrative n ON n.id=b.narrative_id AND n.source_id=v_src AND n.subjekt_type='person'
    JOIN private.source_record_anchor_current ac ON ac.source_record_id=b.source_record_id AND ac.decision_status='accepted'
    JOIN private.source_observation o ON o.occurrence_id=ac.occurrence_id AND o.parent_observation_id IS NULL
    JOIN private.source_mention sm ON sm.observation_id=o.id
    JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
    JOIN private.source_persona_identity i ON i.source_persona_id=spm.persona_id AND i.decision_status='accepted';
  IF v_n<>(e->>'bindings')::bigint THEN RAISE EXCEPTION 'FIX150_PRE_BINDINGS n=%', v_n; END IF;
  IF EXISTS (
    SELECT 1 FROM private.narrative_record_publication b
      JOIN public.narrative n ON n.id=b.narrative_id AND n.source_id=v_src AND n.subjekt_type='person'
      JOIN private.source_record_anchor_current ac ON ac.source_record_id=b.source_record_id AND ac.decision_status='accepted'
      JOIN private.source_observation o ON o.occurrence_id=ac.occurrence_id AND o.parent_observation_id IS NULL
      JOIN private.source_mention sm ON sm.observation_id=o.id
      JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
      JOIN private.source_persona_identity i ON i.source_persona_id=spm.persona_id AND i.decision_status='accepted'
     WHERE i.canonical_person_id IS DISTINCT FROM n.subjekt_id) THEN
    RAISE EXCEPTION 'FIX150_PRE_IDENTITY';
  END IF;
  -- Publiceringstilstand før: præcis de forventede publicerede, alle tilladte, ingen forældede.
  INSERT INTO fix150_foer
  SELECT pe.record_key, pe.person_id, s->>'publication_status', s->>'eligibility_status', (s->>'blocking_reason') IS NOT NULL
    FROM public.person_external_id pe, LATERAL private.narrative_record_state(pe.person_id, pe.source_id, pe.record_key) s
   WHERE pe.source_id=v_src AND pe.record_key IS NOT NULL;
  IF (SELECT count(*) FROM fix150_foer WHERE status='published')<>(e->>'published')::bigint
     OR EXISTS (SELECT 1 FROM fix150_foer WHERE status='stale_published')
     OR EXISTS (SELECT 1 FROM public.person_external_id pe,
                  LATERAL private.narrative_record_state(pe.person_id, pe.source_id, pe.record_key) s
                 WHERE pe.source_id=v_src AND s->>'publication_status'='published'
                   AND (NOT coalesce((s#>>'{publication_state,publication_policy,publication_allowed}')::boolean,false)
                        OR s->>'published_text_sha256' IS NULL)) THEN
    RAISE EXCEPTION 'FIX150_PRE_PUBLISHED';
  END IF;
  -- Poster, der skrives, med record, hovedperson-persona, helpost, person og entry; præcis én af hver.
  INSERT INTO fix150_post(record_key,p,basis)
  SELECT p->>'record_key', p, CASE WHEN p->>'status'='machine_ok' THEN 'machine' ELSE 'human_group_review' END
    FROM jsonb_array_elements(m->'placements') p
   WHERE p->>'status'='machine_ok' OR p->>'record_key' IN (SELECT jsonb_array_elements_text(a->'record_keys'));
  -- Record og helpost (præcis én accepteret helpost); hovedperson-persona højst én (ingen er tilladt, flere stopper).
  UPDATE fix150_post f SET record_id=x.record_id, basis_obs=x.basis_obs,
         persona_id=(SELECT spm.persona_id FROM private.source_mention sm
                       JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
                      WHERE sm.observation_id=x.basis_obs)
    FROM (SELECT sr.record_key, sr.id AS record_id, o.id AS basis_obs, count(*) OVER (PARTITION BY sr.record_key) AS n
            FROM private.source_record sr
            JOIN private.source_record_anchor_current ac ON ac.source_record_id=sr.id AND ac.decision_status='accepted'
            JOIN private.source_observation o ON o.occurrence_id=ac.occurrence_id AND o.parent_observation_id IS NULL
                                              AND o.observation_kind='person_post'
           WHERE sr.source_id=v_src) x
   WHERE x.record_key=f.record_key AND x.n=1;
  UPDATE fix150_post f SET person_id=pe.person_id FROM public.person_external_id pe
   WHERE pe.source_id=v_src AND pe.record_key=f.record_key;
  UPDATE fix150_post f SET entry_id=e2.id FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e2 ON e2.scheme_id=s.id
   WHERE s.source_id=v_src AND s.kind='stamtavle' AND e2.code=f.p->>'entry_code';
  IF EXISTS (SELECT 1 FROM fix150_post WHERE record_id IS NULL OR person_id IS NULL OR entry_id IS NULL) THEN
    RAISE EXCEPTION 'FIX150_PRE_RECORDS n=%', (SELECT count(*) FROM fix150_post WHERE record_id IS NULL OR person_id IS NULL
                                                 OR entry_id IS NULL);
  END IF;
  -- Ingen helpost med mere end én hovedperson-persona.
  IF EXISTS (SELECT 1 FROM fix150_post f JOIN private.source_mention sm ON sm.observation_id=f.basis_obs
               JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
              GROUP BY f.record_key HAVING count(*)>1) THEN
    RAISE EXCEPTION 'FIX150_PRE_PERSONA';
  END IF;
  -- Memberships: placerede hovedpersoner med accepteret identitet.
  IF (SELECT count(*) FROM fix150_post f JOIN private.source_persona_identity i ON i.source_persona_id=f.persona_id
        AND i.decision_status='accepted')<>(e->>'memberships')::bigint THEN
    RAISE EXCEPTION 'FIX150_PRE_MEMBERSHIPS';
  END IF;
  IF (SELECT count(*) FROM fix150_post)<>(e->>'placements')::bigint THEN
    RAISE EXCEPTION 'FIX150_PRE_PLACEMENTS n=%', (SELECT count(*) FROM fix150_post);
  END IF;
  IF jsonb_array_length(m->'headers')<>(e->>'headers')::int THEN RAISE EXCEPTION 'FIX150_PRE_HEADERS'; END IF;
END $pre$;
SELECT pg_temp.fix150_paritet('foer') \g /dev/null

-- Skrivning 1: overskrifter, placements og ledger (private funktioner, som ejer).
DO $skriv$
DECLARE v_src bigint:=current_setting('fix150.src')::bigint; e jsonb:=current_setting('fix150.expect')::jsonb;
  m jsonb:=(SELECT m FROM fix150_input); v_rend uuid; v_n integer; r record; v_ids jsonb; v_ev jsonb; k text;
  v_key text:='header-2018-20-v1';
BEGIN
  SELECT id INTO v_rend FROM private.source_rendition WHERE source_id=v_src AND content_sha256=current_setting('fix150.rendition_sha');
  v_n:=private.write_header_evidence(v_src, v_rend, jsonb_build_object('run_key',v_key,'schema_version','header-manifest-v1',
    'extractor_version','build_header_manifest.py','profile_version',v_key,'input_sha256',current_setting('fix150.rendition_sha'),
    'manifest',jsonb_build_object('manifest_sha256',current_setting('fix150.manifest_sha'),'go',current_setting('fix150.go'))),
    m->'headers');
  IF v_n<>(e->>'headers')::int THEN RAISE EXCEPTION 'FIX150_WRITE_HEADERS n=%', v_n; END IF;
  FOR r IN SELECT * FROM fix150_post ORDER BY record_key COLLATE "C" LOOP
    v_ids:='{}'::jsonb;
    FOR k IN SELECT jsonb_object_keys(r.p->'header_ids') LOOP
      v_ids:=v_ids||jsonb_build_object(k, private.header_observation_uuid(v_rend, v_key,
               split_part(r.p#>>ARRAY['header_ids',k], ':', 2)::integer));
    END LOOP;
    v_ev:=jsonb_build_object('rule_version',v_key,'header_ids',v_ids,'basis',r.basis,'record_key',r.record_key,
      'manifest_sha256',current_setting('fix150.manifest_sha'),'approvals_sha256',current_setting('fix150.approvals_sha'),
      'go',current_setting('fix150.go'),'decided_by_name','#150 trin 5c-1 (GO 2)');
    UPDATE fix150_post SET rp=private.write_record_placement(r.record_id, r.entry_id, r.p, (v_ids->>'linje')::uuid, v_ev)
     WHERE record_key=r.record_key;
  END LOOP;
  UPDATE fix150_post SET pp=private.write_persona_placement(persona_id, rp, basis_obs,
    jsonb_build_object('rule_version','placement-membership-v1','record_placement_id',rp,'go',current_setting('fix150.go'),
      'manifest_sha256',current_setting('fix150.manifest_sha'),'decided_by_name','#150 trin 5c-1 (GO 2)'))
   WHERE persona_id IS NOT NULL;
  -- Ledger: alle legacy-rækker. Kilden: mapped med placement, ellers unresolved; andre kilder: retained_legacy.
  PERFORM private.record_legacy_disposition(pe.person_id, pe.source_id,
            CASE WHEN f.rp IS NOT NULL THEN 'mapped' WHEN pe.source_id=v_src THEN 'unresolved' ELSE 'retained_legacy' END,
            f.rp, jsonb_build_object('rule_version','placement-membership-v1','go',current_setting('fix150.go'),
              'manifest_sha256',current_setting('fix150.manifest_sha'),'decided_by_name','#150 trin 5c-1 (GO 2)'))
    FROM public.person_external_id pe
    LEFT JOIN fix150_post f ON pe.source_id=v_src AND f.record_key=pe.record_key
   ORDER BY pe.source_id, pe.person_id;
  -- Slægten bliver aktiv under sit eget change_set (fortrydelig via change_event).
  PERFORM public.begin_change_set('placement_slaegt_active','#150 trin 5c-1: slægt aktiv (GO 2)');
  UPDATE public.slaegt s SET status='active' FROM public.lineage_scheme ls
   WHERE ls.slaegt_id=s.id AND ls.source_id=v_src AND ls.kind='stamtavle' AND s.status<>'active';
  PERFORM set_config('app.change_set_id','',true);
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'FIX150_WRITE_NEAREST'; END IF;
END $skriv$;

-- Skrivning 2: memberships gennem promotions-RPC'en (eget change_set), som redaktør.
SET LOCAL ROLE authenticated;
SELECT public.red_preview_placement_memberships(:src)::text AS g_pv \gset
RESET ROLE;
SELECT set_config('fix150.pv', :'g_pv', true) \g /dev/null
DO $mid$
DECLARE v jsonb:=current_setting('fix150.pv')::jsonb; e jsonb:=current_setting('fix150.expect')::jsonb;
BEGIN
  -- Egnede = de forventede memberships; ikke-egnede kun not_accepted for en persona uden accepteret identitet.
  IF (SELECT count(*) FROM jsonb_array_elements(v->'items') i WHERE (i->>'eligible')::boolean)<>(e->>'memberships')::bigint
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') i
                 WHERE NOT (i->>'eligible')::boolean
                   AND (i->>'reason_code'<>'not_accepted'
                        OR EXISTS (SELECT 1 FROM private.source_persona_placement pp
                                     JOIN private.source_persona_identity id ON id.source_persona_id=pp.source_persona_id
                                    WHERE pp.id=(i->>'persona_placement_id')::uuid AND id.decision_status='accepted')))
     OR btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'FIX150_MID_MEMBERSHIP_PREVIEW';
  END IF;
END $mid$;
SET LOCAL ROLE authenticated;
SELECT public.red_promote_placement_memberships(:src, :'g_pv'::jsonb->>'preview_sha256') AS g_promoted \gset
RESET ROLE;

-- Skrivning 3: revalidering. Én klientdrevet sætning pr. forældet publicering; app.change_set_id ryddes før hvert kald
-- (RPC'en afviser et fremmed change_set). Tilstands-sha'en læses som ejer, sætningerne køres som redaktør.
CREATE TEMP TABLE fix150_reval ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY pe.record_key COLLATE "C") AS ord,
       format('SELECT set_config(%L,%L,true), public.red_revalider_person_narrative_record(%s,%s,%L,%L)',
              'app.change_set_id', '', pe.person_id, pe.source_id, pe.record_key, s->>'state_sha256') AS stmt
  FROM public.person_external_id pe, LATERAL private.narrative_record_state(pe.person_id, pe.source_id, pe.record_key) s
 WHERE pe.source_id=:src AND pe.record_key IS NOT NULL AND s->>'publication_status'='stale_published';
GRANT SELECT ON fix150_reval TO authenticated;
SELECT count(*) AS g_reval FROM fix150_reval \gset
SET LOCAL ROLE authenticated;
\o /dev/null
SELECT stmt FROM fix150_reval ORDER BY ord \gexec
\o
RESET ROLE;
SELECT set_config('app.change_set_id','',true), set_config('fix150.reval', :'g_reval', true),
       set_config('fix150.promoted', :'g_promoted', true) \g /dev/null
SELECT pg_temp.fix150_paritet('efter') \g /dev/null

DO $post$
DECLARE v_src bigint:=current_setting('fix150.src')::bigint; e jsonb:=current_setting('fix150.expect')::jsonb; v_n bigint;
BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'FIX150_POST_GUC'; END IF;
  IF current_setting('fix150.reval')::bigint<>(e->>'revalidated')::bigint THEN
    RAISE EXCEPTION 'FIX150_POST_REVALIDATED n=%', current_setting('fix150.reval'); END IF;
  -- Publiceringer: samme antal publicerede, ingen forældede, ingen nye blokeringer, uændret eligibility pr. post.
  CREATE TEMP TABLE fix150_efter ON COMMIT DROP AS
  SELECT pe.record_key, s->>'publication_status' AS status, s->>'eligibility_status' AS eligibility,
         (s->>'blocking_reason') IS NOT NULL AS blocked
    FROM public.person_external_id pe, LATERAL private.narrative_record_state(pe.person_id, pe.source_id, pe.record_key) s
   WHERE pe.source_id=v_src AND pe.record_key IS NOT NULL;
  IF (SELECT count(*) FROM fix150_efter WHERE status='published')<>(e->>'published')::bigint
     OR EXISTS (SELECT 1 FROM fix150_efter WHERE status='stale_published') THEN
    RAISE EXCEPTION 'FIX150_POST_PUBLISHED'; END IF;
  IF EXISTS (SELECT 1 FROM fix150_foer f JOIN fix150_efter x USING (record_key)
              WHERE f.status IS DISTINCT FROM x.status OR f.eligibility IS DISTINCT FROM x.eligibility
                 OR (x.blocked AND NOT f.blocked)) THEN
    RAISE EXCEPTION 'FIX150_POST_ELIGIBILITY'; END IF;
  -- Ledger: alle legacy-rækker har én gældende disposition.
  SELECT count(*) INTO v_n FROM private.legacy_placement_disposition_current WHERE is_current;
  IF v_n<>(e->>'ledger')::bigint OR v_n<>(SELECT count(*) FROM public.person_external_id)
     OR (SELECT count(*) FROM private.legacy_placement_disposition)<>v_n THEN
    RAISE EXCEPTION 'FIX150_POST_LEDGER n=%', v_n; END IF;
  IF (SELECT count(*) FROM private.legacy_placement_disposition_current WHERE source_id=v_src AND disposition='mapped')
       <>(SELECT count(*) FROM fix150_post) THEN RAISE EXCEPTION 'FIX150_POST_LEDGER_MAPPED'; END IF;
  -- Memberships: én pr. placeret hovedperson med accepteret identitet, alle gældende.
  IF current_setting('fix150.promoted')::bigint<>(e->>'memberships')::bigint
     OR (SELECT count(*) FROM public.person_lineage_membership WHERE source_basis->>'rule_version'='placement-membership-v1')
          <>(e->>'memberships')::bigint
     OR (SELECT count(*) FROM public.person_slaegt_membership WHERE source_basis->>'rule_version'='placement-membership-v1')
          <>(e->>'memberships')::bigint
     OR private.placement_membership_not_current()<>0 THEN
    RAISE EXCEPTION 'FIX150_POST_MEMBERSHIPS'; END IF;
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'FIX150_POST_NEAREST'; END IF;
  IF EXISTS (SELECT 1 FROM public.slaegt s JOIN public.lineage_scheme ls ON ls.slaegt_id=s.id
              WHERE ls.source_id=v_src AND ls.kind='stamtavle' AND s.status<>'active') THEN
    RAISE EXCEPTION 'FIX150_POST_SLAEGT'; END IF;
  -- Paritet: læserne er byte-identiske før og efter.
  IF (SELECT count(*) FROM fix150_paritet)<>5 OR EXISTS (SELECT 1 FROM fix150_paritet WHERE foer IS DISTINCT FROM efter OR foer IS NULL) THEN
    RAISE EXCEPTION 'FIX150_POST_PARITET %', (SELECT string_agg(laeser, ',') FROM fix150_paritet
                                               WHERE foer IS DISTINCT FROM efter OR foer IS NULL);
  END IF;
END $post$;
COMMIT;
SELECT count(*) AS g_headers FROM private.source_observation o JOIN private.extraction_run r ON r.id=o.extraction_run_id
 WHERE r.source_id=:src AND r.run_key='header-2018-20-v1' \gset
SELECT count(*) AS g_placements FROM private.source_record_placement rp JOIN private.source_record r ON r.id=rp.source_record_id
 WHERE r.source_id=:src \gset
SELECT count(*) AS g_ledger FROM private.legacy_placement_disposition \gset
\echo FIX150_OK headers=:g_headers placements=:g_placements ledger=:g_ledger memberships=:g_promoted revalideret=:g_reval
