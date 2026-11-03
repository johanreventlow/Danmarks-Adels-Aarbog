-- Læse-kun kandidatliste til linjeskift-v1-rettelsen (spec 2026-11-02 §4.4 pkt. 4), til ceremoni 3's GO-pakke.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 [-v source_id=3] -f linjeskift_kandidater.sql
-- Udskrift (kun antal, id'er og hashes; ingen værdier):
--   T6C2_LINJESKIFT antal=<n> delstreng_i_tilstand=<n> forventet_sha256=<hex> graenser_udfyldt=<n> graenser_sha256=<hex>
--   <assertion_id>|<interpretation_id>   ét par pr. linje, stigende på assertion_id; interpretation_id er forslagets
--                                        aktuelle version, som red_ret_paastand(…,'linjeskift-v1',p_interpretation_id)
--                                        tager
-- forventet_sha256 er sha256 over parrene og kandidaternes forventede tilstand med red_ret_paastand's seks
-- p_forventet-nøgler; graenser_udfyldt/graenser_sha256 måler date_min/date_max/date_qualifier (spec §4.4 pkt. 4:
-- »måles før og efter«). Begge beregnes af linjeskift_forventet.sql; kandidaterne af linjeskift_kandidat_par.sql.
--
-- Runnerkontrakt (Task 11, ceremoni 3). GO-pakken bærer parlisten (daa.linjeskift_kandidat_par-formen),
-- forventet_sha256 og graenser_sha256. I skrive-transaktionen, før første rettelse:
--   (a) sæt daa.linjeskift_kilde = kilden, \ir linjeskift_kandidat_par.sql, og RAISE, hvis
--       daa.linjeskift_kandidat_par ikke er identisk med GO-pakkens parliste;
--   (b) sæt daa.linjeskift_par = parlisten, \ir linjeskift_forventet.sql, og RAISE, hvis
--       daa.linjeskift_forventet_sha256 afviger fra GO-pakkens sha (drift i par, date_raw, vaerdi_tekst, faktum, valgt
--       påstand eller citationsmængde).
-- Kald derefter red_ret_paastand(assertion_id, element->'forventet', 'linjeskift-v1', interpretation_id) pr. element
-- i daa.linjeskift_forventet (de seks nøgler uændret; intet genopbygget i runneren). Efter rettelserne, i samme
-- transaktion: \ir linjeskift_forventet.sql igen med samme par og RAISE, hvis daa.linjeskift_graenser_sha256 eller
-- daa.linjeskift_graenser_udfyldt afviger fra GO-pakkens. Vagterne virker uden at værdier forlader basen.
-- Kilden kommer fra -v source_id (standard 3); den står aldrig fast i koden.
-- Kræver 6c-2a og 6c-2b (binding_value_matches, saml_blanktegn_v1, paastand_korrektion); køres i ceremoni 3 efter §4.3.
--
-- Afgrænsningen (spec §4.4 pkt. 4, sætning for sætning; controllerens afgørelse 3), i linjeskift_kandidat_par.sql:
--   K1 datoforslag fra kilden: aktuel version (interpretation_current) for kilden, status proposed eller accepted
--      (som red_ret_paastand), strengværdi, prædikat med aktiv assertion-regel og value_kind date_raw
--      (private.interpretation_predicate_promotable, som red_ret_paastand), persona med accepteret identitet.
--      Den aktuelle version er §4.3-versionen, hvor dato-markoer-v1 er kørt; ellers version 1.
--   K2 »det eneste mål for et datoforslag«: mål = påstande på identitetens persons fakta af reglens faktatype, hvis
--      date_raw rå eller efter private.saml_blanktegn_v1 er lig forslaget efter private.binding_value_matches.
--      Forslaget skal have præcis ét mål. Desuden må ingen anden fortolkningsnøgle (alle kilder, aktuel version
--      proposed/accepted, samme regelvej) ramme påstanden efter rettelsen (som TARGET_SHARED), og nøglen må ikke have
--      en levende rettelse eller gældende binding på en anden påstand (red_ret_paastand's »ét forslag retter én
--      påstand«).
--   K3 »hvis version fra §4.3 bliver lig påstanden efter rettelsen«: binding_value_matches('date_raw', forslagets
--      aktuelle værdi, NULL, saml_blanktegn_v1(date_raw)) — samme lighed som red_ret_paastand og bindingsgyldigheden.
--   K4 der er noget at rette: date_raw IS DISTINCT FROM saml_blanktegn_v1(date_raw).
--   K5 »kun påstande, som alene forslagets egen kilde citerer«: mængden af citerende kilder er præcis {forslagets
--      source_id} (udgaveneutralt, fra data).
--   K6 »ingen eksisterende gyldig binding må blive ugyldig«: ingen gældende binding (assertion_binding_current) på
--      påstanden, hvis værdi ikke matcher den samlede date_raw (red_ret_paastand's PAASTAND_BINDING_BRYDES).
--
-- Gate (spec §4.4 pkt. 4 sidste sætning): ingen kandidats nuværende date_raw må indgå i en tilstand, der hashes.
-- Tilstandene og deres input (læst i schema.sql):
--   familie     private.relation_binding_state(interpretation_id) → relation_binding_state_sha256, gemt som
--               interpretation_promotion.evidence->>'state_sha256' (target_type family, target_id = familie).
--               Input: fortolkningens id/nøgle/version/status/prædikat/kilde, parternes identiteter, familiens
--               family_member-rækker, ordinaler, børneflokkens reference. Læser ikke public.assertion.
--   placement   private.membership_state(persona_placement_id) (hashet i placement_membership_set og gemt i
--               person_lineage_membership/person_slaegt_membership.source_basis). Input: identitet, placements,
--               slægtsskemaets indgang. Læser ikke public.assertion.
--   publicering private.narrative_publication_state(person, kilde, record_key) (publication_state_sha256; gemt som
--               narrative_publication_event.after_state). Input: record, kilde, personens levende/privat/staged,
--               ankre, placements, identiteter, revisioner, binding og narrativets tekst. Læser ikke public.assertion.
--   Kontrollen pr. kandidat (personen = faktaets subjekt) beregner de aktuelle tilstande og læser de gemte:
--   familiebindinger på familier, personen er medlem af (beregnet relation_binding_state + gemt evidence);
--   membership_state for placements af personas med accepteret identitet til personen + gemt source_basis;
--   narrative_publication_state for personens draft/published-bindinger + seneste gemte after_state pr. strøm for
--   personens narrativer. En kandidat er berørt, når dens date_raw er en hel JSON-værdi et sted i en af dem
--   (jsonpath ==, kodepunktslighed, uafhængig af collation) → LINJESKIFT_TILSTAND_BEROERT (kun antallet), ingen liste.
--   delstreng_i_tilstand tæller (uden at stoppe) kandidater, hvis date_raw (JSON-escapet) står som delstreng i en af
--   tilstandene — i praksis narrativets tekst, som rettelsen ikke ændrer. Er tallet > 0, afgør controlleren, om
--   narrativteksten hører under gaten.
\set QUIET on
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
\if :{?source_id} \else \set source_id 3 \endif
BEGIN READ ONLY;
SELECT set_config('daa.linjeskift_kilde',:'source_id',true) \g /dev/null
\ir linjeskift_kandidat_par.sql
SELECT count(p) AS antal,
       coalesce(string_agg(split_part(p,':',1),',' ORDER BY o),'') AS ider,
       current_setting('daa.linjeskift_kandidat_par') AS par,
       coalesce(string_agg(replace(p,':','|'),E'\n' ORDER BY o),'') AS parlinjer
  FROM unnest(string_to_array(nullif(current_setting('daa.linjeskift_kandidat_par'),''),',')) WITH ORDINALITY u(p,o) \gset m_

SELECT set_config('daa.t6c2_lk_ider',:'m_ider',true) \g /dev/null
WITH k AS (
  SELECT a.id, a.date_raw, f.subjekt_id AS pid, to_jsonb(a.date_raw) AS v,
         substr(to_jsonb(a.date_raw)::text,2,length(to_jsonb(a.date_raw)::text)-2) AS esc
    FROM public.assertion a JOIN public.fact f ON f.id=a.target_id
   WHERE a.id=ANY(string_to_array(nullif(current_setting('daa.t6c2_lk_ider'),''),',')::bigint[])
), tilstand AS (
  -- familie: beregnet og gemt for familiebindinger på personens familier
  SELECT k.id, s.state
    FROM k
    JOIN public.family_member fm ON fm.person_id=k.pid
    JOIN private.interpretation_promotion p ON p.target_type='family' AND p.target_id=fm.family_id
    CROSS JOIN LATERAL (VALUES (private.relation_binding_state(p.interpretation_id)),(p.evidence)) s(state)
  UNION ALL
  -- placement: beregnet membership_state for personens persona-placements
  SELECT k.id, private.membership_state(pp.id)
    FROM k
    JOIN private.source_persona_identity i ON i.canonical_person_id=k.pid AND i.decision_status='accepted'
    JOIN private.source_persona_placement_current pp ON pp.source_persona_id=i.source_persona_id
  UNION ALL
  -- placement: gemt source_basis
  SELECT k.id, m.source_basis FROM k JOIN public.person_lineage_membership m ON m.person_id=k.pid
  UNION ALL
  SELECT k.id, m.source_basis FROM k JOIN public.person_slaegt_membership m ON m.person_id=k.pid
  UNION ALL
  -- publicering: beregnet for personens draft/published-bindinger
  SELECT k.id, private.narrative_publication_state(k.pid,sr.source_id,sr.record_key)
    FROM k
    JOIN public.narrative n ON n.subjekt_type='person' AND n.subjekt_id=k.pid
    JOIN private.narrative_record_publication b ON b.narrative_id=n.id AND b.status IN ('draft','published')
    JOIN private.source_record sr ON sr.id=b.source_record_id
  UNION ALL
  -- publicering: seneste gemte tilstand pr. strøm for personens narrativer
  SELECT k.id, e.after_state
    FROM k
    JOIN public.narrative n ON n.subjekt_type='person' AND n.subjekt_id=k.pid
    JOIN LATERAL (SELECT DISTINCT ON (ev.stream_ref) ev.after_state
                    FROM private.narrative_publication_event ev
                   WHERE ev.narrative_id=n.id
                   ORDER BY ev.stream_ref,ev.stream_version DESC) e ON true
)
SELECT count(DISTINCT t.id) FILTER (WHERE jsonb_path_exists(t.state,'$.** ? (@ == $v)',jsonb_build_object('v',k.v)))
         AS beroert,
       count(DISTINCT t.id) FILTER (WHERE position(k.esc IN t.state::text)>0) AS delstreng
  FROM tilstand t JOIN k ON k.id=t.id
 WHERE t.state IS NOT NULL \gset m_

SELECT set_config('daa.t6c2_lk_beroert',:'m_beroert',true) \g /dev/null
DO $gate$
BEGIN
  IF current_setting('daa.t6c2_lk_beroert')::bigint>0 THEN
    RAISE EXCEPTION 'LINJESKIFT_TILSTAND_BEROERT: % kandidater indgår i en tilstand',
      current_setting('daa.t6c2_lk_beroert');
  END IF;
END $gate$;

SELECT set_config('daa.linjeskift_par',:'m_par',true) \g /dev/null
\ir linjeskift_forventet.sql
SELECT format('T6C2_LINJESKIFT antal=%s delstreng_i_tilstand=%s forventet_sha256=%s graenser_udfyldt=%s '
              'graenser_sha256=%s',:'m_antal',:'m_delstreng',current_setting('daa.linjeskift_forventet_sha256'),
              current_setting('daa.linjeskift_graenser_udfyldt'),current_setting('daa.linjeskift_graenser_sha256'));
SELECT :'m_parlinjer' WHERE :'m_parlinjer'<>'';
ROLLBACK;
