-- Review 37 blok 3: før-kontrol (kun læsning), som prod-runneren kører i deploy-transaktionen FØR blokken. Tæller de
-- rækker, hver af blokkens tabel-CHECKs ville afvise, og stopper med R37B3_FOER_OVERTRAEDELSER, hvis én tæller ikke er 0
-- (så fejler deployet med et navngivet tal pr. constraint i stedet for ADD CONSTRAINT's første 23514). Udtrykkene er de
-- samme som i DO-blokken $review37_b3_checks$ (schema.sql og db-migrations.sql), skrevet som NOT (udtryk) med NULL =
-- tilladt, som en CHECK. Forvent: NOTICE "OK: review37 b3 før-kontrol — 0 overtrædelser i 12 constraints".
DO $review37_b3_foer$
DECLARE v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'relation_afbildet_kanonisk', (SELECT count(*) FROM public.relation WHERE NOT coalesce(
      lower(btrim(rolle)) <> 'afbildet' OR (rolle = 'afbildet' AND ((subjekt_type = 'person' AND objekt_type = 'media')
        OR (subjekt_type = 'media' AND objekt_type IN ('estate','coat_of_arms','lineage','family','place')))), true)),
    'relation_periode_orden', (SELECT count(*) FROM public.relation WHERE NOT coalesce(
      (start_min IS NULL OR start_max IS NULL OR start_min <= start_max)
      AND (end_min IS NULL OR end_max IS NULL OR end_min <= end_max)
      AND (start_min IS NULL OR end_max IS NULL OR start_min <= end_max), true)),
    'relation_konfidens_chk', (SELECT count(*) FROM public.relation
      WHERE NOT coalesce(konfidens IN ('sikker','sandsynlig','formodet','omstridt'), true)),
    'assertion_dato_orden', (SELECT count(*) FROM public.assertion WHERE date_min > date_max),
    'assertion_date_qualifier_chk', (SELECT count(*) FROM public.assertion WHERE NOT coalesce(
      date_qualifier IN ('exact','before','after','between','about','floruit','until_event','open_end','ongoing'), true)),
    'haendelse_dato_orden', (SELECT count(*) FROM public.haendelse WHERE date_min > date_max),
    'haendelse_date_qualifier_chk', (SELECT count(*) FROM public.haendelse WHERE NOT coalesce(
      date_qualifier IN ('exact','before','after','between','about','floruit','until_event','open_end','ongoing'), true)),
    'story_dato_orden', (SELECT count(*) FROM public.story WHERE date_min > date_max),
    'story_date_qualifier_chk', (SELECT count(*) FROM public.story WHERE NOT coalesce(
      date_qualifier IN ('exact','before','after','between','about','floruit','until_event','open_end','ongoing'), true)),
    'family_member_rolle_chk', (SELECT count(*) FROM public.family_member WHERE NOT coalesce(
      rolle IN ('partner','barn','adopteret_barn','plejebarn','stedbarn'), true)),
    'family_member_konfidens_chk', (SELECT count(*) FROM public.family_member WHERE NOT coalesce(
      konfidens IN ('sikker','sandsynlig','formodet','omstridt'), true)),
    'conclusion_status_chk', (SELECT count(*) FROM public.conclusion WHERE NOT coalesce(
      status IN ('afklaret','omstridt','forældet','tilbagetrukket'), true))
  ) INTO v;
  IF EXISTS (SELECT 1 FROM jsonb_each_text(v) WHERE value::bigint <> 0) THEN
    RAISE EXCEPTION 'R37B3_FOER_OVERTRAEDELSER: %',
      (SELECT jsonb_object_agg(key, value) FROM jsonb_each(v) WHERE value::bigint <> 0);
  END IF;
  RAISE NOTICE 'OK: review37 b3 før-kontrol — 0 overtrædelser i % constraints', (SELECT count(*) FROM jsonb_object_keys(v));
END
$review37_b3_foer$;
